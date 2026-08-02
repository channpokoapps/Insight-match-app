// _shared/db.ts
// Edge Function から private スキーマへアクセスするための直接 Postgres 接続。
//
// private は PostgREST の公開スキーマに含めない（AGENTS.md R-2）ため、
// supabase-js（PostgREST 経由）では service_role でも到達できない。
// Edge Functions に自動注入される SUPABASE_DB_URL で直接 SQL を実行する。
//
// 注意:
//   - この接続はアプリ（Flutter）からは絶対に張れない（R-6。DB URL は
//     Edge Functions の環境変数にのみ存在する）。
//   - 値の埋め込みは必ずテンプレートリテラルのパラメータバインドで行う（R-9）。

import postgres from "postgres";

type Sql = ReturnType<typeof postgres>;

let _sql: Sql | null = null;

/** 接続プールを返す（プロセス内で使い回す）。 */
export function sql(): Sql {
  if (!_sql) {
    const url = Deno.env.get("SUPABASE_DB_URL");
    if (!url) throw new Error("CONFIG_ERROR");
    _sql = postgres(url, { prepare: false, max: 2 });
  }
  return _sql;
}
