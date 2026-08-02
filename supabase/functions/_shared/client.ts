// _shared/client.ts
// Edge Function の呼び出し元検証とログのサニタイズ。
//
// 注意:
//   - service_role キーは Edge Function の環境変数からのみ読む。アプリに埋め込まない（AGENTS.md R-6）。
//   - DB アクセスは _shared/db.ts（直接 SQL）を使う。private は PostgREST に公開しない（R-2）。

/**
 * 呼び出し元が service_role であることを確認する。
 * pg_cron / 管理用途以外から叩かれないようにする。
 *
 * 完全一致に加えて JWT の role クレームも許容する。ゲートウェイ
 * （verify_jwt）が署名検証済みの前提であり、Vault に登録した
 * service_role キーが環境変数と別発行でも動くようにするため。
 */
export function assertServiceRole(req: Request): void {
    const auth = req.headers.get("Authorization") ?? "";
    const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
    if (auth === expected) return;
    const payload = decodeJwtPayload(auth.replace(/^Bearer\s+/i, ""));
    if (payload?.role === "service_role") return;
    throw new Response("unauthorized", { status: 401 });
}

/** JWT のペイロード部を検証なしでデコードする（署名検証はゲートウェイ側）。 */
function decodeJwtPayload(token: string): { role?: string } | null {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    try {
        const b64 = parts[1].replaceAll("-", "+").replaceAll("_", "/");
        const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
        return JSON.parse(atob(padded)) as { role?: string };
    } catch {
        return null;
    }
}

/**
 * ログにインサイト値・トークン・個人情報を出さないためのサニタイズ（AGENTS.md R-7）。
 * 記録してよいのは識別子とエラーコードのみ。
 */
export function safeLog(event: string, fields: Record<string, string | number>): void {
    const allowed = ["job_id", "item_id", "credential_id", "user_id", "platform", "status", "error_code", "count"];
    const out: Record<string, string | number> = {};
    for (const [k, v] of Object.entries(fields)) {
        if (allowed.includes(k)) out[k] = v;
    }
    console.log(JSON.stringify({ event, ...out }));
}
