# Supabase 本番プロジェクトの作成と設定

バックエンド（DB・認証・Edge Functions）はすべて Supabase に置く。
**開発はローカル CLI スタック（`supabase start`）だけで行い、クラウドの無料枠 2 プロジェクトのうち
1 つを本番専用に温存する**（`OI-16`）。

> **最重要**: 「Exposed schemas」に `private` を追加しない。
> 追加した瞬間にインサイト実数値と SNS トークンが全世界へ公開される。

---

## 1. プロジェクト作成

1. https://supabase.com/dashboard → **New project**
2. Organization を選び、以下を設定する。
   - Name: `insight-match-prod`
   - Region: **Northeast Asia (Tokyo)**
   - Database Password: パスワードマネージャで生成して保管
3. プラン: まず **Free**。
   - **Free は 7 日間 DB アクティビティが無いと一時停止する。** 日次バッチ（`0006_cron.sql`）が
     heartbeat を兼ねるが、公開後は Pro（約 $25/月）への移行を検討する（`OI-39`）。

## 2. スキーマ公開設定の確認（最重要）

1. **Settings → API → Exposed schemas** を開く。
2. `public, graphql_public` のみであること（**`private` が無いこと**）を確認する。
   ローカルの `supabase/config.toml` の `schemas = ["public", "graphql_public"]` と同じ状態にする。

## 3. マイグレーション適用

ローカルの作業ディレクトリ（リポジトリ直下）で:

```bash
supabase login
supabase link --project-ref <プロジェクトの Reference ID>
supabase db push          # supabase/migrations/ を順に適用
```

適用後、ダッシュボードの **Database → Extensions** で `pg_cron` / `pg_net` が有効なことを確認する。

## 4. 認証（Auth）の設定

### 4.1 メール / パスワード

1. **Authentication → Providers → Email**: Enabled のまま、**Confirm email を ON**。
2. **Authentication → URL Configuration**:
   - Site URL: お試し Web 版の URL（例: `https://<firebase-project>.web.app`）
   - Redirect URLs に以下を追加:
     - `https://<firebase-project>.web.app/**`
     - `http://localhost:*/**`（ローカル開発用）
     - `app.insightmatch.android://auth-callback`（パスワード再設定のディープリンク用）
3. 本番公開前に **SMTP（独自ドメインのメール）** を設定する。既定の送信元はレート制限が厳しい。

### 4.2 Google サインイン

GCP コンソール（**Firebase プロジェクトと同じ GCP プロジェクトでよい**）→ APIs & Services → Credentials:

1. **OAuth 同意画面**を構成する（External / アプリ名 / サポートメール）。
2. OAuth クライアントを **2 つ**作成する。
   - **ウェブ アプリケーション**: 承認済みリダイレクト URI に
     `https://<project-ref>.supabase.co/auth/v1/callback` を追加。
   - **Android**: パッケージ名 `app.insightmatch.android` と **SHA-1**（下記コマンドで取得）を登録。

     ```bash
     cd app/android && ./gradlew signingReport   # debug 用 SHA-1
     ```

     Play 公開後は **Play Console → アプリの署名** に表示される SHA-1 も追加登録する。
3. Supabase **Authentication → Providers → Google**:
   - Enabled: ON
   - Client ID / Client Secret: **ウェブ**クライアントの値
   - **Authorized Client IDs**: ウェブクライアントの Client ID を追加
     （Android は `signInWithIdToken` で検証されるため、ここにウェブ Client ID が必要）。

## 5. Edge Functions（Phase 3 以降）

```bash
supabase functions deploy meta-oauth
supabase functions deploy sync-insights
supabase functions deploy sync-worker
supabase secrets set META_APP_ID=... META_APP_SECRET=...
# TOKEN_ENCRYPTION_KEY は初期構築時に設定済み（ADR-0006）
```

### 5.1 日次バッチ（pg_cron）の有効化

マイグレーション 0006 で cron ジョブ自体は登録済みだが、
**Vault にシークレットを入れるまでは何もせず空振りする**（警告ログのみ）。

1. ダッシュボード → **Project Settings → API** で `service_role` キーをコピー
   （**アプリや env/ には絶対に貼らない**。使うのはこの SQL の中だけ）
2. ダッシュボード → **SQL Editor** で次の 2 行を実行:

   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
   select vault.create_secret('<service_role キー>', 'service_role_key');
   ```

3. 動作確認: 翌日以降、**Table Editor → private.sync_jobs** に行が増えていれば
   日次バッチが動いている（連携 0 件でも 1 行残る = Free プラン一時停止対策の
   heartbeat を兼ねる）。

## 6. 運用

- **週次バックアップ**: `supabase db dump -f backup_$(date +%Y%m%d).sql`（Free に自動バックアップは無い）。
- ダッシュボードのアカウントに **MFA を有効化**する。
- 使用量アラート: **Settings → Usage** を月 1 回確認する（DB 500MB / Egress 5GB が無料枠）。
