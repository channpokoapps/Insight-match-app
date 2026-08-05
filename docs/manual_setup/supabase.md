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
     - `https://<firebase-project>.web.app`（`/**` はパス区切りの `/` を要求するため、
       素のオリジンも念のため併記して登録する）
     - `https://<firebase-project>--*.web.app/**`
       （**Firebase Hosting のプレビューチャンネル**。`deploy_preview.yml` が
       `https://<firebase-project>--preview-xxxxxxxx.web.app` を払い出すため、
       ワイルドカードで登録しないとプレビュー環境でログインが完了しない。
       詳細は [github_automation.md](github_automation.md) §4）
     - `http://localhost:*/**`（ローカル開発用）
     - `app.insightmatch.android://auth-callback`（**将来の Android ディープリンク用。
       現状アプリ側に受け口（intent-filter）は未実装で、メールリンクは Web 版に着地する**）

> **⚠️ Redirect URLs の登録漏れは「無言で失敗」する**
>
> アプリは自分の起動オリジンに `/` を付けた URL（例:
> `https://<firebase-project>.web.app/`）を `redirect_to` として渡す
> （`auth_repository.dart` の `webRedirectUrl`。確認メールと
> パスワード再設定メールで共通）。
> それが Redirect URLs に**一致しない**場合、Supabase はエラーを返さず
> **Site URL へフォールバック**して戻す。
>
> このとき、PKCE の `code_verifier` は**リンクを要求したオリジンの
> localStorage** にしかない。別オリジン（Site URL 側）で受け取った `?code=` は
> 交換できずに失敗し、セッションが張られないままログイン画面に戻る。
>
> 症状は「メールのリンクを開いたのに何も起きない／登録画面に進まない」。
> **プレビュー URL でメールリンクが完了しないときは、まずここを疑う。**
>
> **Google ログインはこの経路を使わない**（§4.2）。Google は Web でも
> ページを離れず ID トークンを直接受け取る方式に変えたため、Redirect URLs も
> PKCE も関与しない。
3. 本番公開前に **SMTP（独自ドメインのメール）** を設定する。既定の送信元はレート制限が厳しい。
   送信者名（From name）は **`SNS Insight Matcher`** にする。差出人がサービス名で表示されないと、
   確認メールがフィッシングと区別できず開かれない。

### 4.1.1 メールテンプレート（アプリ名入りの日本語文面）

テンプレートはリポジトリの `supabase/templates/` が正であり、ローカルでは
`supabase/config.toml` の `[auth.email.template.*]` から読み込まれる。
**本番はダッシュボード管理なので、内容を変更したら手動で貼り直す必要がある。**

Supabase **Authentication → Emails → Templates** で、以下の 3 つを差し替える。

| テンプレート | Subject | 貼り付ける本文 |
|---|---|---|
| Confirm signup | `【SNS Insight Matcher】メールアドレスのご確認` | `supabase/templates/confirmation.html` |
| Reset password | `【SNS Insight Matcher】パスワード再設定のご案内` | `supabase/templates/recovery.html` |
| Change email address | `【SNS Insight Matcher】メールアドレス変更のご確認` | `supabase/templates/email_change.html` |

ヘッダのアイコンは `{{ .SiteURL }}/icons/Icon-192.png`（Web 版が配信するアプリアイコン）を
参照している。**Site URL が Web 版の公開 URL になっていること**が前提で、画像がブロックされた
場合も alt テキストとブランド色の帯でサービス名が分かるようにしてある。
なお現在の `Icon-192.png` は Flutter の既定アイコンのままなので、独自アイコンへの
差し替えが必要（`docs/open_issues.md` の OI-47）。

### 4.2 Google サインイン

> **前提: アプリは Web も Android も「ID トークン方式」で統一している。**
> Web も Google Identity Services（GIS）のボタンでページを離れずに
> ID トークンを受け取り、`signInWithIdToken` に渡す
> （`auth_repository.dart` / `google_continue_button.dart`）。
> **Supabase の Redirect URLs も PKCE も使わない**ので、下の GCP 設定さえ
> 合っていればプレビュー・本番のどちらでも同じように動く。

GCP コンソール（**Firebase プロジェクトと同じ GCP プロジェクトでよい**）→ APIs & Services → Credentials:

1. **OAuth 同意画面**を構成する（External / アプリ名 / サポートメール）。
2. OAuth クライアントを **2 つ**作成する。
   - **ウェブ アプリケーション**:
     - **承認済みの JavaScript 生成元**（**Web ログインに必須**）に、
       アプリを配信するオリジンを**パスなし**で登録する。
       ここが未登録だと GIS がボタンを描画できず、押しても認証が始まらない。
       ワイルドカードは使えないため実 URL を 1 つずつ登録する。
       - `https://<firebase-project>.web.app`
       - `https://<firebase-project>--preview-xxxxxxxx.web.app`
         （プレビューチャンネル。URL は固定なので一度登録すればよい。
         [github_automation.md](github_automation.md) §4）
       - `http://localhost:<ポート>`（ローカル開発で使う場合）
     - 承認済みリダイレクト URI に
       `https://<project-ref>.supabase.co/auth/v1/callback` を追加。
       （現在のアプリは使わないが、ダッシュボードから
       Google プロバイダの疎通確認をする場合に必要）
   - **Android**: パッケージ名 `app.insightmatch.android` と **SHA-1**（下記コマンドで取得）を登録。

     ```bash
     cd app/android && ./gradlew signingReport   # debug 用 SHA-1
     ```

     Play 公開後は **Play Console → アプリの署名** に表示される SHA-1 も追加登録する。
3. **ウェブ**クライアントの Client ID を、ビルドに `GOOGLE_WEB_CLIENT_ID` として
   注入する（`env/prod.json` → GitHub Secrets `FLUTTER_ENV_PROD`）。
   **未注入だと Web / Android とも Google ボタンが無効になり、画面に
   「Google ログインは現在設定中です」と表示される。**
4. Supabase **Authentication → Providers → Google**:
   - Enabled: ON
   - Client ID / Client Secret: **ウェブ**クライアントの値
   - **Authorized Client IDs**: ウェブクライアントの Client ID を追加
     （**Web / Android とも `signInWithIdToken` で検証されるため必須**）。

### 4.3 トラブルシューティング: Google でログインできない

「Google で続行 → アカウントを選択 → ログインできない」ときは、
症状ごとに見る場所が違う。

| 症状 | 見るところ |
|---|---|
| ボタンが「Getting ready」のまま／描画されない | §4.2 の **承認済みの JavaScript 生成元**。ブラウザのコンソールに GIS の生成元エラーが出る |
| ボタンは出るが押しても何も起きない | 同上（生成元未登録）。または `GOOGLE_WEB_CLIENT_ID` の値違い |
| 「Google ログインは現在設定中です」と出る | `GOOGLE_WEB_CLIENT_ID` がビルドに注入されていない（§4.2 の 3.） |
| アカウント選択後に「Google ログインに失敗しました」と出る | Supabase → Providers → Google の **Authorized Client IDs** にウェブクライアントの Client ID が入っていない（§4.2 の 4.）。ID トークンの `aud` 検証で弾かれている |
| Android だけ失敗する | GCP の **Android クライアント**の SHA-1 未登録。`serverClientId` に Android クライアント ID を渡していないことも確認する |

どのオリジン・どのビルドで起きたかは、ログイン画面下部の灰色の診断行
（起動 URL のトレースとビルド識別子）で確認できる。

> **メールのリンク**（確認メール・パスワード再設定）が完了しない場合は
> 本節ではなく §4.1 の Redirect URLs 登録漏れ（無言フォールバック）を疑うこと。

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

   CLI からも実行できる（**`--linked` を忘れると本番でなくローカル DB に入る**ので注意）:

   ```bash
   supabase db query --linked "select vault.create_secret('...', 'project_url');"
   ```

   ※ 2026-08-02 実施済み。

3. 動作確認: 翌日以降、**Table Editor → private.sync_jobs** に行が増えていれば
   日次バッチが動いている（連携 0 件でも 1 行残る = Free プラン一時停止対策の
   heartbeat を兼ねる）。

## 6. 運用

- **週次バックアップ**: `supabase db dump -f backup_$(date +%Y%m%d).sql`（Free に自動バックアップは無い）。
- ダッシュボードのアカウントに **MFA を有効化**する。
- 使用量アラート: **Settings → Usage** を月 1 回確認する（DB 500MB / Egress 5GB が無料枠）。
