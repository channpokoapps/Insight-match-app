// sync-worker/index.ts
// 割り当てられた連携アカウント分だけインサイトを取得し、private に保存する。
//
// 重要:
//   - 取得した数値は private スキーマにしか書かない（AGENTS.md R-1）
//   - 数値をログに出さない（R-7）
//   - 失敗は指数バックオフで最大5回まで再試行する（ADR-0004）
//   - private へは直接 SQL で接続する（PostgREST に private を公開しない R-2）

import { assertServiceRole, safeLog } from "../_shared/client.ts";
import { sql } from "../_shared/db.ts";
import { decryptToken, encryptToken } from "../_shared/crypto.ts";
import {
  aggregateWindows,
  type MediaMetrics,
  parseDemographics,
  parseInsightValues,
  toRatios,
} from "../_shared/insights.ts";

const MAX_ATTEMPT = 5;
const BACKOFF_MINUTES = [5, 15, 45, 120, 360];

const GRAPH = "https://graph.facebook.com/v21.0";

/** 取得対象の投稿期間。最長の集計ウィンドウ（90日）に合わせる。 */
const MEDIA_WINDOW_DAYS = 90;

/** メディア一覧の最大ページ数（1ページ50件）。暴走とレート消費の上限。 */
const MAX_MEDIA_PAGES = 5;

/** 個別インサイトを取得する最大メディア数。
 *  レート制限（約200リクエスト/ユーザー/時）内に収める（要件 9-4-1）。 */
const MAX_INSIGHT_MEDIA = 60;

/** トークンの残り有効期間がこの日数を切ったら更新する（T-016 / FR-SNS-07）。 */
const TOKEN_REFRESH_BEFORE_DAYS = 10;

interface Payload {
  job_id: string;
  credential_ids: string[];
}

interface Credential {
  id: string;
  user_id: string;
  platform: string;
  external_account_id: string;
  access_token_encrypted: string;
  token_expires_at: Date | null;
  status: string;
}

Deno.serve(async (req) => {
  try {
    assertServiceRole(req);
  } catch (res) {
    return res as Response;
  }

  const { job_id, credential_ids }: Payload = await req.json();
  const db = sql();

  let success = 0;
  let failure = 0;

  for (const credentialId of credential_ids) {
    try {
      await syncOne(credentialId);
      await db`
        update private.sync_job_items
           set status = 'success', error_code = null, error_message = null
         where job_id = ${job_id} and credential_id = ${credentialId}`;
      success += 1;
    } catch (e) {
      failure += 1;
      const code = classifyError(e);
      const [item]: { attempt: number }[] = await db`
        select attempt from private.sync_job_items
         where job_id = ${job_id} and credential_id = ${credentialId}`;
      const attempt = (item?.attempt ?? 0) + 1;
      const retryable = code !== "AUTH_REVOKED" && attempt < MAX_ATTEMPT;
      const nextRetryAt = retryable
        ? new Date(Date.now() + BACKOFF_MINUTES[attempt - 1] * 60_000)
        : null;

      // 例外メッセージにトークンが含まれうるため error_message は保存しない
      await db`
        update private.sync_job_items
           set status = ${retryable ? "retry" : "failed"},
               attempt = ${attempt},
               error_code = ${code},
               error_message = null,
               next_retry_at = ${nextRetryAt}
         where job_id = ${job_id} and credential_id = ${credentialId}`;

      if (code === "AUTH_REVOKED") {
        await markReauthRequired(credentialId);
      }
      safeLog("sync_item_failed", { job_id, credential_id: credentialId, error_code: code });
    }
  }

  safeLog("sync_worker_done", { job_id, count: credential_ids.length, status: `${success}/${failure}` });

  return Response.json({ ok: true, success, failure });
});

async function syncOne(credentialId: string): Promise<void> {
  const db = sql();
  const [cred]: Credential[] = await db`
    select id, user_id, platform, external_account_id,
           access_token_encrypted::text as access_token_encrypted,
           token_expires_at, status
      from private.social_credentials
     where id = ${credentialId}`;
  if (!cred) throw new Error("API_ERROR");
  if (cred.status !== "active") throw new Error("AUTH_REVOKED");

  if (cred.platform !== "instagram") {
    // TikTok / YouTube は将来対応（OI-02 / OI-18）
    return;
  }

  let token = await decryptToken(cred.access_token_encrypted);
  token = await maybeRefreshToken(cred, token);

  // --- 投稿一覧と個別インサイトの取得（要件 9-4-3） ------------------------
  const media = await fetchAllMedia(cred.external_account_id, token);
  await attachMediaInsights(media, token);
  const followers = await fetchInstagramFollowers(cred.external_account_id, token);

  if (media.length > 0) {
    const rows = media.map((m) => ({
      credential_id: cred.id,
      external_media_id: m.id,
      media_type: m.media_type ?? null,
      permalink: m.permalink ?? null,
      posted_at: m.timestamp,
      reach: m.reach ?? null,
      impressions: m.impressions ?? null,
      likes: m.like_count ?? null,
      comments: m.comments_count ?? null,
      saves: m.saved ?? null,
      shares: m.shares ?? null,
      views: m.views ?? null,
      fetched_at: new Date(),
    }));
    for (let i = 0; i < rows.length; i += 200) {
      const chunk = rows.slice(i, i + 200);
      await db`
        insert into private.media_snapshots ${db(chunk)}
        on conflict (credential_id, external_media_id) do update set
          media_type = excluded.media_type,
          permalink = excluded.permalink,
          posted_at = excluded.posted_at,
          reach = excluded.reach,
          impressions = excluded.impressions,
          likes = excluded.likes,
          comments = excluded.comments,
          saves = excluded.saves,
          shares = excluded.shares,
          views = excluded.views,
          fetched_at = excluded.fetched_at`;
    }
  }

  // --- 集計（_shared/insights.ts の純粋関数） -----------------------------
  for (const w of aggregateWindows(media, Date.now())) {
    await db`
      insert into private.creator_metrics
        (user_id, platform, window_days, followers, avg_reach, avg_impressions,
         avg_likes, avg_comments, avg_saves, avg_shares, avg_views,
         engagement_rate, post_count, computed_at)
      values
        (${cred.user_id}, 'instagram', ${w.window_days}, ${followers},
         ${w.avg_reach}, ${w.avg_impressions}, ${w.avg_likes}, ${w.avg_comments},
         ${w.avg_saves}, ${w.avg_shares}, ${w.avg_views},
         ${w.engagement_rate}, ${w.post_count}, now())
      on conflict (user_id, platform, window_days) do update set
        followers = excluded.followers,
        avg_reach = excluded.avg_reach,
        avg_impressions = excluded.avg_impressions,
        avg_likes = excluded.avg_likes,
        avg_comments = excluded.avg_comments,
        avg_saves = excluded.avg_saves,
        avg_shares = excluded.avg_shares,
        avg_views = excluded.avg_views,
        engagement_rate = excluded.engagement_rate,
        post_count = excluded.post_count,
        computed_at = excluded.computed_at`;
  }

  // --- オーディエンス属性（T-021。取得のみ、条件には使わない = OI-35） ----
  await syncDemographics(cred, token);

  // public 側には「同期できた」という事実だけを書く
  await db`
    update public.social_links
       set last_synced_at = now(), status = 'active'
     where user_id = ${cred.user_id} and platform = 'instagram'`;
}

/**
 * 長期トークンの残り有効期間が短いときに再交換して延長する（T-016）。
 *
 * META_APP_ID / META_APP_SECRET が未設定の間はスキップする。
 * 交換が認可エラーで失敗した場合は再認可が必要。
 */
async function maybeRefreshToken(cred: Credential, token: string): Promise<string> {
  const expiresAt = cred.token_expires_at ? new Date(cred.token_expires_at).getTime() : null;
  if (
    expiresAt === null ||
    expiresAt - Date.now() > TOKEN_REFRESH_BEFORE_DAYS * 86_400_000
  ) {
    return token;
  }
  const appId = Deno.env.get("META_APP_ID");
  const appSecret = Deno.env.get("META_APP_SECRET");
  if (!appId || !appSecret) return token;

  const res = await fetch(
    `${GRAPH}/oauth/access_token?grant_type=fb_exchange_token` +
      `&client_id=${encodeURIComponent(appId)}` +
      `&client_secret=${encodeURIComponent(appSecret)}` +
      `&fb_exchange_token=${encodeURIComponent(token)}`,
  );
  if (res.status === 401 || res.status === 403 || res.status === 400) {
    // 失効済みトークンの交換失敗は再認可でしか回復できない
    throw new Error("AUTH_REVOKED");
  }
  if (!res.ok) return token; // 一時障害なら現行トークンで続行
  const body = await res.json();
  if (typeof body.access_token !== "string") return token;

  const newExpiresAt = typeof body.expires_in === "number"
    ? new Date(Date.now() + body.expires_in * 1000)
    : new Date(Date.now() + 60 * 86_400_000);
  const encrypted = await encryptToken(body.access_token);
  await sql()`
    update private.social_credentials
       set access_token_encrypted = cast(${encrypted} as bytea),
           token_expires_at = ${newExpiresAt}
     where id = ${cred.id}`;
  safeLog("token_refreshed", { credential_id: cred.id, platform: "instagram" });
  return body.access_token;
}

async function markReauthRequired(credentialId: string): Promise<void> {
  const db = sql();
  const [row]: { user_id: string; platform: string }[] = await db`
    update private.social_credentials
       set status = 'reauth_required'
     where id = ${credentialId}
     returning user_id, platform`;
  if (!row) return;
  await db`
    update public.social_links
       set status = 'reauth_required'
     where user_id = ${row.user_id} and platform = ${row.platform}`;
}

/** メディア一覧をページネーションで取得する。集計対象期間より古い投稿で打ち切る。 */
async function fetchAllMedia(accountId: string, token: string): Promise<MediaMetrics[]> {
  const fields = "id,media_type,permalink,timestamp,like_count,comments_count";
  const oldest = Date.now() - MEDIA_WINDOW_DAYS * 86_400_000;
  const out: MediaMetrics[] = [];

  let url: string | null = `${GRAPH}/${encodeURIComponent(accountId)}/media` +
    `?fields=${fields}&limit=50&access_token=${encodeURIComponent(token)}`;

  for (let page = 0; page < MAX_MEDIA_PAGES && url; page++) {
    const res: Response = await fetch(url);
    if (res.status === 401 || res.status === 403) throw new Error("AUTH_REVOKED");
    if (res.status === 429) throw new Error("RATE_LIMIT");
    if (!res.ok) throw new Error("API_ERROR");
    const body: { data?: MediaMetrics[]; paging?: { next?: string } } = await res.json();
    const items = body.data ?? [];

    let reachedEnd = false;
    for (const m of items) {
      if (new Date(m.timestamp).getTime() < oldest) {
        reachedEnd = true;
        break;
      }
      out.push(m);
    }
    if (reachedEnd) break;
    url = body.paging?.next ?? null;
  }
  return out;
}

/**
 * メディアごとのインサイト（リーチ・保存など）を取得して書き込む。
 *
 * TODO(OI-37): 取得可能な指標は Meta の仕様変更で変わりうる。
 * impressions は新規投稿では廃止済みのため views を主とし、
 * 未対応メディアは縮退したメトリクスで再試行 → それでも失敗なら
 * 一覧で取れた いいね/コメント のみで集計する（NULL は平均から除外）。
 */
async function attachMediaInsights(media: MediaMetrics[], token: string): Promise<void> {
  const targets = media.slice(0, MAX_INSIGHT_MEDIA);
  for (const m of targets) {
    const values = await fetchMediaInsights(m.id, token);
    if (values === null) continue;
    m.reach = values.reach ?? null;
    m.saved = values.saved ?? null;
    m.shares = values.shares ?? null;
    m.views = values.views ?? null;
    // impressions は取得できた場合のみ（旧投稿の互換）
    m.impressions = values.impressions ?? null;
  }
}

/** 1メディア分のインサイトを取得する。未対応・取得不可は null。 */
async function fetchMediaInsights(
  mediaId: string,
  token: string,
): Promise<Record<string, number> | null> {
  for (const metrics of ["reach,saved,shares,views", "reach,saved"]) {
    const res = await fetch(
      `${GRAPH}/${encodeURIComponent(mediaId)}/insights` +
        `?metric=${metrics}&access_token=${encodeURIComponent(token)}`,
    );
    if (res.status === 401 || res.status === 403) throw new Error("AUTH_REVOKED");
    if (res.status === 429) throw new Error("RATE_LIMIT");
    if (res.ok) return parseInsightValues(await res.json());
    // 400 はメディア種別が指標に未対応の場合があるため、縮退して再試行する
    if (res.status !== 400) return null;
  }
  return null;
}

async function fetchInstagramFollowers(accountId: string, token: string): Promise<number | null> {
  const url = `${GRAPH}/${encodeURIComponent(accountId)}` +
    `?fields=followers_count&access_token=${encodeURIComponent(token)}`;
  const res = await fetch(url);
  if (res.status === 401 || res.status === 403) throw new Error("AUTH_REVOKED");
  if (!res.ok) return null;
  const body = await res.json();
  return typeof body.followers_count === "number" ? body.followers_count : null;
}

/**
 * フォロワーのオーディエンス属性を取得して保存する（T-021）。
 *
 * 条件式には使わない（OI-35）。取得失敗は同期全体を失敗させない。
 */
async function syncDemographics(cred: Credential, token: string): Promise<void> {
  const db = sql();
  for (const dimension of ["age", "gender", "city"] as const) {
    try {
      const res = await fetch(
        `${GRAPH}/${encodeURIComponent(cred.external_account_id)}/insights` +
          `?metric=follower_demographics&period=lifetime&metric_type=total_value` +
          `&breakdown=${dimension}&access_token=${encodeURIComponent(token)}`,
      );
      if (!res.ok) continue; // フォロワー100人未満などで取得不可の場合がある
      const ratios = toRatios(parseDemographics(await res.json()));
      if (ratios.length === 0) continue;
      const rows = ratios.map((r) => ({
        user_id: cred.user_id,
        platform: "instagram",
        dimension,
        bucket: r.bucket,
        ratio: r.ratio,
        computed_at: new Date(),
      }));
      await db`
        insert into private.audience_demographics ${db(rows)}
        on conflict (user_id, platform, dimension, bucket) do update set
          ratio = excluded.ratio,
          computed_at = excluded.computed_at`;
    } catch {
      // 属性は補助情報。失敗しても同期は続行する
    }
  }
}

function classifyError(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  if (["AUTH_REVOKED", "RATE_LIMIT", "API_ERROR", "CONFIG_ERROR"].includes(msg)) return msg;
  return "UNKNOWN";
}
