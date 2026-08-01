// _shared/client.ts
// Edge Function から Supabase にアクセスするための共通クライアント。
//
// 注意:
//   - service_role キーは Edge Function の環境変数からのみ読む。アプリに埋め込まない（AGENTS.md R-6）。
//   - private スキーマへのアクセスはこのクライアント経由に限る。

import { createClient, SupabaseClient } from "@supabase/supabase-js";

export function createServiceClient(): SupabaseClient {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) {
        throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY が設定されていません");
    }
    return createClient(url, key, {
        auth: { persistSession: false },
        db: { schema: "private" },
    });
}

export function createPublicServiceClient(): SupabaseClient {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) {
        throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY が設定されていません");
    }
    return createClient(url, key, { auth: { persistSession: false } });
}

/**
 * 呼び出し元が service_role であることを確認する。
 * pg_cron / 管理用途以外から叩かれないようにする。
 */
export function assertServiceRole(req: Request): void {
    const auth = req.headers.get("Authorization") ?? "";
    const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
    if (auth !== expected) {
        throw new Response("unauthorized", { status: 401 });
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
