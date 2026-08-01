// sync-worker/index.ts
// 割り当てられた連携アカウント分だけインサイトを取得し、private に保存する。
//
// 重要:
//   - 取得した数値は private スキーマにしか書かない（AGENTS.md R-1）
//   - 数値をログに出さない（R-7）
//   - 失敗は指数バックオフで最大5回まで再試行する（ADR-0004）

import { createServiceClient, assertServiceRole, safeLog } from "../_shared/client.ts";

const MAX_ATTEMPT = 5;
const BACKOFF_MINUTES = [5, 15, 45, 120, 360];
const WINDOWS = [7, 30, 90] as const;

interface Payload {
  job_id: string;
  credential_ids: string[];
}

Deno.serve(async (req) => {
  try {
    assertServiceRole(req);
  } catch (res) {
    return res as Response;
  }

  const { job_id, credential_ids }: Payload = await req.json();
  const db = createServiceClient();

  let success = 0;
  let failure = 0;

  for (const credentialId of credential_ids) {
    try {
      await syncOne(db, credentialId);
      await db
        .from("sync_job_items")
        .update({ status: "success", error_code: null, error_message: null })
        .eq("job_id", job_id)
        .eq("credential_id", credentialId);
      success += 1;
    } catch (e) {
      failure += 1;
      const code = classifyError(e);
      const { data } = await db
        .from("sync_job_items")
        .select("attempt")
        .eq("job_id", job_id)
        .eq("credential_id", credentialId)
        .single();
      const attempt = (data?.attempt ?? 0) + 1;
      const retryable = code !== "AUTH_REVOKED" && attempt < MAX_ATTEMPT;

      await db
        .from("sync_job_items")
        .update({
          status: retryable ? "retry" : "failed",
          attempt,
          error_code: code,
          // 例外メッセージにトークンが含まれうるため保存しない
          error_message: null,
          next_retry_at: retryable
            ? new Date(Date.now() + BACKOFF_MINUTES[attempt - 1] * 60_000).toISOString()
            : null,
        })
        .eq("job_id", job_id)
        .eq("credential_id", credentialId);

      if (code === "AUTH_REVOKED") {
        await markReauthRequired(db, credentialId);
      }
      safeLog("sync_item_failed", { job_id, credential_id: credentialId, error_code: code });
    }
  }

  safeLog("sync_worker_done", { job_id, count: credential_ids.length, status: `${success}/${failure}` });

  return Response.json({ ok: true, success, failure });
});

// deno-lint-ignore no-explicit-any
async function syncOne(db: any, credentialId: string): Promise<void> {
  const { data: cred, error } = await db
    .from("social_credentials")
    .select("id, user_id, platform, external_account_id, access_token_encrypted, token_expires_at, status")
    .eq("id", credentialId)
    .single();
  if (error) throw error;
  if (cred.status !== "active") throw new Error("AUTH_REVOKED");

  if (cred.platform !== "instagram") {
    // TikTok / YouTube は将来対応（OI-02 / OI-18）
    return;
  }

  const token = await decryptToken(cred.access_token_encrypted);

  // --- 投稿一覧とインサイトの取得 --------------------------------------
  // TODO(OI-37): 取得する指標名は Meta の最新仕様で最終確認する。
  const media = await fetchInstagramMedia(cred.external_account_id, token);
  const followers = await fetchInstagramFollowers(cred.external_account_id, token);

  if (media.length > 0) {
    const rows = media.map((m) => ({
      credential_id: cred.id,
      external_media_id: m.id,
      media_type: m.media_type,
      permalink: m.permalink,
      posted_at: m.timestamp,
      reach: m.reach ?? null,
      impressions: m.impressions ?? null,
      likes: m.like_count ?? null,
      comments: m.comments_count ?? null,
      saves: m.saved ?? null,
      shares: m.shares ?? null,
      views: m.views ?? null,
      fetched_at: new Date().toISOString(),
    }));
    const { error: upsertError } = await db
      .from("media_snapshots")
      .upsert(rows, { onConflict: "credential_id,external_media_id" });
    if (upsertError) throw upsertError;
  }

  // --- 集計 ------------------------------------------------------------
  const now = Date.now();
  for (const windowDays of WINDOWS) {
    const from = now - windowDays * 86_400_000;
    const target = media.filter((m) => new Date(m.timestamp).getTime() >= from);
    const avg = (pick: (m: InstagramMedia) => number | null | undefined) => {
      const values = target.map(pick).filter((v): v is number => typeof v === "number");
      return values.length === 0 ? null : values.reduce((a, b) => a + b, 0) / values.length;
    };

    const avgReach = avg((m) => m.reach);
    const avgLikes = avg((m) => m.like_count);
    const avgComments = avg((m) => m.comments_count);
    const avgSaves = avg((m) => m.saved);
    const avgShares = avg((m) => m.shares);

    // エンゲージメント率 = (いいね + コメント + 保存 + シェア) / リーチ
    const engagement =
      avgReach && avgReach > 0
        ? ((avgLikes ?? 0) + (avgComments ?? 0) + (avgSaves ?? 0) + (avgShares ?? 0)) / avgReach
        : null;

    const { error: metricError } = await db.from("creator_metrics").upsert(
      {
        user_id: cred.user_id,
        platform: "instagram",
        window_days: windowDays,
        followers,
        avg_reach: avgReach,
        avg_impressions: avg((m) => m.impressions),
        avg_likes: avgLikes,
        avg_comments: avgComments,
        avg_saves: avgSaves,
        avg_shares: avgShares,
        avg_views: avg((m) => m.views),
        engagement_rate: engagement,
        post_count: target.length,
        computed_at: new Date().toISOString(),
      },
      { onConflict: "user_id,platform,window_days" },
    );
    if (metricError) throw metricError;
  }

  // public 側には「同期できた」という事実だけを書く
  const publicDb = db.schema("public");
  await publicDb
    .from("social_links")
    .update({ last_synced_at: new Date().toISOString(), status: "active" })
    .eq("user_id", cred.user_id)
    .eq("platform", "instagram");
}

// deno-lint-ignore no-explicit-any
async function markReauthRequired(db: any, credentialId: string): Promise<void> {
  const { data } = await db
    .from("social_credentials")
    .update({ status: "reauth_required" })
    .eq("id", credentialId)
    .select("user_id, platform")
    .single();
  if (!data) return;
  await db.schema("public")
    .from("social_links")
    .update({ status: "reauth_required" })
    .eq("user_id", data.user_id)
    .eq("platform", data.platform);
}

interface InstagramMedia {
  id: string;
  media_type?: string;
  permalink?: string;
  timestamp: string;
  like_count?: number;
  comments_count?: number;
  reach?: number;
  impressions?: number;
  saved?: number;
  shares?: number;
  views?: number;
}

async function fetchInstagramMedia(accountId: string, token: string): Promise<InstagramMedia[]> {
  // TODO: ページネーション・インサイトの個別取得を実装する。
  // ここでは呼び出し形だけを定義しておく。
  const fields = "id,media_type,permalink,timestamp,like_count,comments_count";
  const url =
    `https://graph.facebook.com/v21.0/${encodeURIComponent(accountId)}/media` +
    `?fields=${fields}&limit=50&access_token=${encodeURIComponent(token)}`;
  const res = await fetch(url);
  if (res.status === 401 || res.status === 403) throw new Error("AUTH_REVOKED");
  if (res.status === 429) throw new Error("RATE_LIMIT");
  if (!res.ok) throw new Error("API_ERROR");
  const body = await res.json();
  return (body.data ?? []) as InstagramMedia[];
}

async function fetchInstagramFollowers(accountId: string, token: string): Promise<number | null> {
  const url =
    `https://graph.facebook.com/v21.0/${encodeURIComponent(accountId)}` +
    `?fields=followers_count&access_token=${encodeURIComponent(token)}`;
  const res = await fetch(url);
  if (res.status === 401 || res.status === 403) throw new Error("AUTH_REVOKED");
  if (!res.ok) return null;
  const body = await res.json();
  return typeof body.followers_count === "number" ? body.followers_count : null;
}

// TODO(OI-17): 暗号化方式を確定してから実装する。
async function decryptToken(encrypted: string): Promise<string> {
  const keyRaw = Deno.env.get("TOKEN_ENCRYPTION_KEY");
  if (!keyRaw) throw new Error("CONFIG_ERROR");
  const raw = Uint8Array.from(atob(encrypted), (c) => c.charCodeAt(0));
  const iv = raw.slice(0, 12);
  const data = raw.slice(12);
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(atob(keyRaw), (c) => c.charCodeAt(0)),
    "AES-GCM",
    false,
    ["decrypt"],
  );
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, data);
  return new TextDecoder().decode(plain);
}

function classifyError(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  if (["AUTH_REVOKED", "RATE_LIMIT", "API_ERROR", "CONFIG_ERROR"].includes(msg)) return msg;
  return "UNKNOWN";
}
