# ADR-0006: SNS アクセストークンは Edge Function 内 AES-256-GCM で暗号化する

- **状態**：承認
- **日付**：2026-08-02
- **関連**：[09_external_integrations.md](../requirements/09_external_integrations.md) 9-4-4、`OI-17`、`FR-SNS-04`、AGENTS.md R-1/R-6/R-7

## 背景

- `private.social_credentials.access_token_encrypted` に保存する Meta の長期トークンは、
  漏洩すると投稿者本人になりすまして Instagram のデータへアクセスできる。
- DB のバックアップ・ダンプが漏れた場合でもトークンが読めない状態にしたい。
- 暗号化方式が未決（`OI-17`）のまま `sync-worker` の復号処理が仮実装になっていた。

## 選択肢

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| A | **Edge Function 内 AES-256-GCM、鍵は Supabase Secrets** | 鍵が DB の外にある（DB ダンプ単体では復号不可）。Web Crypto 標準 API のみで実装でき、ローカル検証も容易 | 鍵ローテーション時は再暗号化バッチが必要 |
| B | pgsodium / Vault（DB 内暗号化） | SQL だけで完結 | 鍵も DB 側にあり、ダンプ+設定漏洩で復号されうる。ローカル CLI との互換確認が必要 |
| C | 平文 + RLS/スキーマ分離のみ | 実装不要 | バックアップ漏洩で即アウト。論外 |

## 決定

**案 A** を採用する。

- アルゴリズム：AES-256-GCM（IV 12 バイトをランダム生成し、`IV || 暗号文` を連結して保存）
- 鍵：32 バイトを base64 した値を Supabase Secrets の `TOKEN_ENCRYPTION_KEY` に置く。
  リポジトリ・アプリ・DB には置かない。
- 保存形式：`private.social_credentials.access_token_encrypted`（bytea）。
  PostgREST 経由の入出力は `\x` 始まりの 16 進文字列として扱う。
- 実装：`supabase/functions/_shared/crypto.ts` に暗号化・復号を集約し、
  `meta-oauth`（保存側）と `sync-worker`（読み出し側）の双方が同じ実装を使う。
- OAuth の CSRF 対策 state も同じ鍵から HMAC-SHA256 で署名する
  （メッセージにプレフィックスを付けてドメイン分離する）。

## 影響

- 鍵をローテーションする場合は、新旧 2 鍵での復号を一時的に許容する再暗号化
  バッチが必要（将来課題。運用手順は monitoring_backup.md に記載予定）。
- `TOKEN_ENCRYPTION_KEY` が失われるとトークンは復元できず、全ユーザーが再連携になる。
  Secrets の値はパスワードマネージャにも控える。
