// meta-oauth/index.ts
// Instagram（Meta）の OAuth 認可フロー（要件 9-4-2）。
//
// エンドポイント（verify_jwt は無効。認可開始はコード内で JWT を検証する）:
//   POST { action: "start" } + Authorization: Bearer <ユーザー JWT>
//     → 認可 URL を返す。アプリは外部ブラウザで開く。
//   GET ?code=...&state=...   （Meta からのリダイレクト）
//     → state 検証 → トークン交換 → 暗号化保存 → 完了ページを返す。
//
// 注意:
//   - トークン・数値をログに出さない（AGENTS.md R-7）。
//   - トークンは暗号化して private にのみ保存する（R-1 / ADR-0006）。

import { createClient } from "@supabase/supabase-js";
import { safeLog } from "../_shared/client.ts";
import { sql } from "../_shared/db.ts";
import { encryptToken, issueState, verifyState } from "../_shared/crypto.ts";

const GRAPH = "https://graph.facebook.com/v21.0";

/** 審査で説明可能な最小限のスコープ（要件 9-4-2）。 */
const SCOPES = [
  "instagram_basic",
  "instagram_manage_insights",
  "pages_show_list",
  "pages_read_engagement",
].join(",");

/** 連携完了後にアプリへ戻るためのカスタムスキーム URL。 */
const APP_RETURN_URL = "insightmatch://sns-link";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  try {
    if (req.method === "POST") {
      return await handleStart(req);
    }
    if (req.method === "GET") {
      return await handleCallback(url);
    }
    return new Response("method not allowed", { status: 405 });
  } catch (e) {
    safeLog("meta_oauth_error", { error_code: e instanceof Error ? e.message : "UNKNOWN" });
    return resultPage(false, "処理中にエラーが発生しました。アプリに戻って再度お試しください。");
  }
});

function config(): { appId: string; appSecret: string; redirectUri: string } {
  const appId = Deno.env.get("META_APP_ID");
  const appSecret = Deno.env.get("META_APP_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!appId || !appSecret || !supabaseUrl) throw new Error("CONFIG_ERROR");
  return {
    appId,
    appSecret,
    redirectUri: `${supabaseUrl}/functions/v1/meta-oauth`,
  };
}

/** 認可開始。呼び出しユーザーの JWT を検証し、state 付き認可 URL を返す。 */
async function handleStart(req: Request): Promise<Response> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const anon = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { auth: { persistSession: false } },
  );
  const { data, error } = await anon.auth.getUser(jwt);
  if (error || !data.user) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const { appId, redirectUri } = config();
  const state = await issueState(data.user.id);
  const authorizeUrl = "https://www.facebook.com/v21.0/dialog/oauth" +
    `?client_id=${encodeURIComponent(appId)}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}` +
    `&state=${encodeURIComponent(state)}` +
    `&scope=${encodeURIComponent(SCOPES)}`;
  return Response.json({ url: authorizeUrl });
}

/** Meta からのリダイレクトを受けてトークンを保存する。 */
async function handleCallback(url: URL): Promise<Response> {
  // 利用者が認可画面でキャンセルした場合
  if (url.searchParams.get("error")) {
    return resultPage(false, "連携がキャンセルされました。アプリに戻って再度お試しください。");
  }

  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) {
    return resultPage(false, "リクエストが不正です。アプリからやり直してください。");
  }
  const userId = await verifyState(state);
  if (!userId) {
    return resultPage(false, "セッションの有効期限が切れました。アプリからやり直してください。");
  }

  const { appId, appSecret, redirectUri } = config();

  // code → 短期トークン
  const shortRes = await fetch(
    `${GRAPH}/oauth/access_token?client_id=${encodeURIComponent(appId)}` +
      `&redirect_uri=${encodeURIComponent(redirectUri)}` +
      `&client_secret=${encodeURIComponent(appSecret)}` +
      `&code=${encodeURIComponent(code)}`,
  );
  if (!shortRes.ok) {
    safeLog("meta_oauth_error", { error_code: "TOKEN_EXCHANGE" });
    return resultPage(false, "認可コードの交換に失敗しました。再度お試しください。");
  }
  const shortToken = (await shortRes.json()).access_token as string;

  // 短期 → 長期トークン（約 60 日）
  const longRes = await fetch(
    `${GRAPH}/oauth/access_token?grant_type=fb_exchange_token` +
      `&client_id=${encodeURIComponent(appId)}` +
      `&client_secret=${encodeURIComponent(appSecret)}` +
      `&fb_exchange_token=${encodeURIComponent(shortToken)}`,
  );
  if (!longRes.ok) {
    safeLog("meta_oauth_error", { error_code: "LONG_TOKEN_EXCHANGE" });
    return resultPage(false, "トークンの取得に失敗しました。再度お試しください。");
  }
  const longBody = await longRes.json();
  const longToken = longBody.access_token as string;
  const expiresAt = typeof longBody.expires_in === "number"
    ? new Date(Date.now() + longBody.expires_in * 1000).toISOString()
    : new Date(Date.now() + 60 * 86_400_000).toISOString();

  // Facebook ページ経由で Instagram ビジネス/クリエイターアカウントを特定する
  const pagesRes = await fetch(
    `${GRAPH}/me/accounts?fields=instagram_business_account%7Bid%2Cusername%7D` +
      `&access_token=${encodeURIComponent(longToken)}`,
  );
  if (!pagesRes.ok) {
    safeLog("meta_oauth_error", { error_code: "PAGES_FETCH" });
    return resultPage(false, "アカウント情報の取得に失敗しました。再度お試しください。");
  }
  interface PageEntry {
    instagram_business_account?: { id: string; username?: string };
  }
  const pages = ((await pagesRes.json()).data ?? []) as PageEntry[];
  const igAccount = pages.find((p) => p.instagram_business_account)?.instagram_business_account;
  if (!igAccount) {
    return resultPage(
      false,
      "Instagram のビジネス／クリエイターアカウントが見つかりませんでした。" +
        "Instagram アプリでアカウント種別を切り替え、Facebook ページと連携してから再度お試しください。",
    );
  }

  // 暗号化して保存（private のみ。R-1 / ADR-0006。直接 SQL = R-2 維持）
  const encrypted = await encryptToken(longToken);
  const db = sql();
  let credId: string;
  try {
    const [cred]: { id: string }[] = await db`
      insert into private.social_credentials
        (user_id, platform, external_account_id, external_username,
         account_type, access_token_encrypted, token_expires_at, scopes, status)
      values
        (${userId}, 'instagram', ${igAccount.id}, ${igAccount.username ?? null},
         'business', cast(${encrypted} as bytea), ${expiresAt},
         ${SCOPES.split(",")}, 'active')
      on conflict (user_id, platform) do update set
        external_account_id = excluded.external_account_id,
        external_username = excluded.external_username,
        account_type = excluded.account_type,
        access_token_encrypted = excluded.access_token_encrypted,
        token_expires_at = excluded.token_expires_at,
        scopes = excluded.scopes,
        status = 'active'
      returning id`;
    credId = cred.id;

    // public には「連携済み」という事実だけを書く
    await db`
      insert into public.social_links (user_id, platform, status, linked_at)
      values (${userId}, 'instagram', 'active', now())
      on conflict (user_id, platform) do update set
        status = 'active', linked_at = now()`;
  } catch {
    safeLog("meta_oauth_error", { error_code: "DB_UPSERT" });
    return resultPage(false, "保存に失敗しました。再度お試しください。");
  }

  // 初回同期を即時実行する（OI-24。失敗しても連携自体は成立）
  await enqueueInitialSync(credId);

  safeLog("meta_oauth_linked", { user_id: userId, platform: "instagram" });
  return resultPage(true, "Instagram との連携が完了しました。アプリに戻ってください。");
}

/** 連携直後の初回同期。sync_jobs に記録してから sync-worker を非同期起動する。 */
async function enqueueInitialSync(credentialId: string): Promise<void> {
  try {
    const db = sql();
    const [job]: { id: string }[] = await db`
      insert into private.sync_jobs (target_count) values (1) returning id`;
    if (!job) return;
    await db`
      insert into private.sync_job_items (job_id, credential_id)
      values (${job.id}, ${credentialId})`;

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    // 応答を待たない（Edge Function のタイムアウトを避ける）
    fetch(`${supabaseUrl}/functions/v1/sync-worker`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ job_id: job.id, credential_ids: [credentialId] }),
    }).catch(() => {});
  } catch {
    // 初回同期の失敗は日次バッチが拾うため握りつぶす
  }
}

/** ブラウザに表示する完了／エラーページ。アプリへの復帰リンクを含む。 */
function resultPage(ok: boolean, message: string): Response {
  const title = ok ? "連携が完了しました" : "連携できませんでした";
  const icon = ok ? "✅" : "⚠️";
  const html = `<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${title} - SNS Insight Matcher</title>
<style>
body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;
min-height:100vh;margin:0;background:#f5f7fa;color:#1a1a2e}
.card{background:#fff;border-radius:16px;padding:32px;max-width:360px;margin:16px;
box-shadow:0 2px 12px rgba(0,0,0,.08);text-align:center}
.icon{font-size:48px}h1{font-size:20px}p{font-size:14px;line-height:1.7;color:#444}
a.btn{display:inline-block;margin-top:16px;padding:12px 24px;border-radius:24px;
background:#3A7AFE;color:#fff;text-decoration:none;font-weight:bold}
</style></head><body><div class="card">
<div class="icon">${icon}</div><h1>${title}</h1><p>${message}</p>
<a class="btn" href="${APP_RETURN_URL}">アプリに戻る</a>
</div>
<script>if(${ok}){setTimeout(function(){location.href="${APP_RETURN_URL}"},1200)}</script>
</body></html>`;
  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}
