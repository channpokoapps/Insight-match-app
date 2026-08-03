# GitHub 自動化（Claude 連携・自動デプロイ）の初回セットアップ

[poc_guide.md](../poc_guide.md) のループ（Issue → Claude が実装 → プレビュー →
マージ → 本番反映 → APK 配布）を動かすために、**管理者が PC で 1 回だけ**行う設定。
ここが終わっていないと、各ワークフローは「Secrets 未設定」の案内を出してスキップする。

前提: PC に `gh`（GitHub CLI）・`firebase`・`claude` の各 CLI が入っていて、
`gh auth login` と `firebase login` が済んでいること。
コマンド中の `-R channpokoapps/Insight-match-app` は、リポジトリ直下で実行するなら省略できる。

> **Shift Navi との関係。** この仕組みは Shift Navi
> （Shift-management-app リポジトリ）と同じ構成の移植。ただし
> **Firebase プロジェクトは別**（`insight-match-2fbaa`）なので、
> サービスアカウント・キーストア・テスター登録はこのプロジェクト用に作り直す。
> Secrets は GitHub 上で読み出せないため、Shift Navi 側からコピーはできない。

---

## 0. 全体像 — どのワークフローに何が要るか

| ワークフロー | 動くために必要なもの | 未設定のときの挙動 |
| --- | --- | --- |
| `claude.yml`（Issue から実装） | Claude GitHub App ＋ Secret `CLAUDE_CODE_OAUTH_TOKEN` | ジョブが失敗する |
| `claude-code-review.yml`（PR 自動レビュー） | 同上 | ジョブが失敗する |
| `deploy_preview.yml`（PR のプレビュー） | §2・§3 の Secrets / Variables | 案内を出してスキップ |
| `deploy_production.yml`（本番反映） | §2・§3 の Secrets / Variables | 案内を出してスキップ |
| `android_build.yml`（APK 配布） | §2・§3・§5 の Secrets / Variables | ジョブが失敗する |

登録する一覧（すべて Settings → Secrets and variables → Actions でも確認できる）:

| 種別 | 名前 | 中身 | 手順 |
| --- | --- | --- | --- |
| Secret | `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` の出力 | §1 |
| Secret | `FIREBASE_SERVICE_ACCOUNT` | サービスアカウント鍵 JSON の全文 | §2 |
| Variable | `FIREBASE_PROJECT_ID` | `insight-match-2fbaa` | §2 |
| Secret | `FLUTTER_ENV_PROD` | `env/prod.json` の全文 | §3 |
| Secret | `FLUTTER_WEB_FIREBASE_CONFIG` | `env/web_firebase_config.json` の全文 | §3 |
| Secret | `ANDROID_KEYSTORE_BASE64` | upload キーストアの base64 | §5 |
| Secret | `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_PASSWORD` / `ANDROID_KEY_ALIAS` | キーストアのパスワード・エイリアス | §5 |
| Secret | `ANDROID_GOOGLE_SERVICES_JSON_BASE64` | `google-services.json` の base64 | §5 |
| Variable（任意） | `APP_DISTRIBUTION_GROUPS` | テスターグループのエイリアス（省略時 `testers`） | §5 |
| Variable（任意） | `FIREBASE_ANDROID_APP_ID` | Android の App ID（省略時は google-services.json から導出） | §5 |

---

## 1. Claude 連携（Issue から実装・PR 自動レビュー）

1. **Claude GitHub App のインストール確認。**
   <https://github.com/settings/installations> を開き、`Claude` がこのリポジトリに
   インストールされているか確認する。無ければ <https://github.com/apps/claude> から
   インストールし、対象リポジトリに `Insight-match-app` を含める。
   （2026-08-02 の PR #1 で `/install-github-app` フローを実行済みなら、
   インストール自体は済んでいる可能性が高い）

2. **OAuth トークンを Secrets に登録する。**

   ```bash
   claude setup-token
   # ブラウザで認可 → 表示されたトークンをコピーして:
   gh secret set CLAUDE_CODE_OAUTH_TOKEN -R channpokoapps/Insight-match-app
   # （プロンプトにトークンを貼り付ける）
   ```

   Pro / Max サブスクリプションの利用枠で動く。API 従量課金にしたい場合は
   `ANTHROPIC_API_KEY` を登録し、`claude.yml` / `claude-code-review.yml` の
   `claude_code_oauth_token:` を `anthropic_api_key:` に書き替える。

---

## 2. Firebase サービスアカウント（デプロイの認証）

CI が Hosting へのデプロイと App Distribution への配布に使う鍵。

1. [GCP コンソール → IAM → サービスアカウント](https://console.cloud.google.com/iam-admin/serviceaccounts)
   でプロジェクト `insight-match-2fbaa` を選び、**サービスアカウントを作成**。
   - 名前: `github-actions`
   - ロール: **Firebase Hosting 管理者** と **Firebase App Distribution 管理者** の 2 つ
     （最小権限。Auth の承認済みドメインを触る権限は意図的に与えない）
2. 作成したアカウントの「キー」タブ → **新しい鍵を作成 → JSON** でダウンロードする。
3. Secrets に登録し、**ローカルの鍵ファイルは消す**。

   ```bash
   gh secret set FIREBASE_SERVICE_ACCOUNT -R channpokoapps/Insight-match-app < ~/Downloads/insight-match-2fbaa-xxxx.json
   rm ~/Downloads/insight-match-2fbaa-xxxx.json
   ```

4. プロジェクト ID を Variables に登録する。

   ```bash
   gh variable set FIREBASE_PROJECT_ID -R channpokoapps/Insight-match-app --body "insight-match-2fbaa"
   ```

---

## 3. Flutter の接続設定（gitignore されている env ファイル）

`env/prod.json` と `env/web_firebase_config.json` は秘密情報（Supabase の URL /
anon キー、Firebase の Web 設定）を含むためコミットされていない
（作り方: [supabase.md](supabase.md)・[gcp_firebase.md](gcp_firebase.md)）。
CI はこれを Secrets から復元してビルドする。

```bash
gh secret set FLUTTER_ENV_PROD -R channpokoapps/Insight-match-app < env/prod.json
gh secret set FLUTTER_WEB_FIREBASE_CONFIG -R channpokoapps/Insight-match-app < env/web_firebase_config.json
```

> env ファイルの中身を変えたら（例: Supabase のキーをローテーションしたら）、
> この 2 つの Secret も同じコマンドで更新すること。

---

## 4. プレビュー URL のログイン許可（一度だけ）

プレビューは**固定チャンネル** `preview` にデプロイされる。URL は
`https://insight-match-2fbaa--preview-<ランダム>.web.app` の形で、
一度デプロイされれば変わらない（PR ごとに変わらないのがミソ。
毎回この節の登録をやり直さなくて済む）。

1. Secrets 登録後、適当な PR を作る（または既存 PR に push する）と
   プレビューがデプロイされ、PR のコメントに URL が出る。その URL を控える。
2. **Supabase**: [ダッシュボード](https://supabase.com/dashboard) →
   プロジェクト → Authentication → **URL Configuration → Redirect URLs** に
   **ワイルドカードで**追加する。

   ```
   https://insight-match-2fbaa--*.web.app/**
   ```

   Redirect URLs はホスト名部分にも `*` を使えるため、こう登録しておけば
   チャンネルのランダム部分が変わっても登録し直さなくてよい。
   実 URL（`https://insight-match-2fbaa--preview-<ランダム>.web.app/**`）を
   個別に足しても動くが、失効のたびに再登録が必要になる。
3. **Google ログイン**: [GCP コンソール → 認証情報](https://console.cloud.google.com/apis/credentials) →
   ウェブアプリケーションの OAuth クライアント → **承認済みの JavaScript 生成元**に
   プレビューの URL（パスなし）を追加する（ワイルドカード不可のため実 URL を登録）。
   ※ 現在の実装（`signInWithOAuth` によるリダイレクト方式）では Google 側は
   Supabase の callback URL しか見ないため必須ではないが、将来 Google の
   JS SDK を使う場合に備えて登録しておく。

> **この登録を飛ばすと、ログインは「無言で失敗」する。**
> `redirect_to` が Redirect URLs に一致しないと、Supabase はエラーを返さず
> **Site URL（本番 URL）へフォールバック**して戻す。PKCE の `code_verifier` は
> ログインを開始したオリジンの localStorage にしかないので、別オリジンで
> 受け取った `?code=` は交換に失敗し、セッションが張られないままログイン画面に戻る。
> 症状は「**Google で続行 → アカウントを選択 → 何も起きない／登録画面に進まない**」。

> **プレビューチャンネルは 30 日間デプロイが無いと失効し、URL のランダム部分が
> 変わる**。手順 2 をワイルドカードで登録していれば影響を受けない。
> 実 URL で登録した場合は 2〜3 をやり直す。

---

## 5. Android 配布（Firebase App Distribution）

`/apk` コメントで APK をスマホに配るための設定。

### 5-1. 署名鍵（upload keystore）を作る

署名が毎回同じであることが重要（変わるとスマホ側でアンインストールしないと
更新できない）。鍵は**このプロジェクト専用**に作る。

```bash
keytool -genkey -v \
  -keystore ~/insight-match-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
# 聞かれるパスワードと組織情報を入力する（パスワードは 2 か所、控えておく）
```

Secrets に登録する:

```bash
base64 -i ~/insight-match-upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 -R channpokoapps/Insight-match-app
gh secret set ANDROID_KEYSTORE_PASSWORD -R channpokoapps/Insight-match-app   # ストアのパスワード
gh secret set ANDROID_KEY_PASSWORD -R channpokoapps/Insight-match-app        # 鍵のパスワード（同じ値なら同じものを）
gh secret set ANDROID_KEY_ALIAS -R channpokoapps/Insight-match-app           # 上の例なら upload
```

キーストア本体は**リポジトリに置かず**、パスワード管理ツールなど安全な場所に
バックアップする（紛失すると既存端末を上書き更新できなくなる）。

### 5-2. リリース署名の SHA-1 を Firebase に登録する

Google ログインは署名のフィンガープリントを検証するため、release 鍵の SHA-1 を
追加しないと **APK 版だけログインに失敗する**。

```bash
keytool -list -v -keystore ~/insight-match-upload-keystore.jks -alias upload | grep SHA1
```

[Firebase コンソール](https://console.firebase.google.com/) → プロジェクトの設定 →
マイアプリ → Android アプリ → **フィンガープリントを追加** に貼り付ける。
その後 **google-services.json を再ダウンロード**して `app/android/app/` に置き直し、
Secrets にも登録する:

```bash
base64 -i app/android/app/google-services.json | gh secret set ANDROID_GOOGLE_SERVICES_JSON_BASE64 -R channpokoapps/Insight-match-app
```

### 5-3. App Distribution とテスターグループ

1. Firebase コンソール → **App Distribution** → 「開始」
2. **テスター グループ**を作成する。グループの**エイリアスを `testers`** にする
   （別名にした場合は `gh variable set APP_DISTRIBUTION_GROUPS --body "<エイリアス>"` で指定）
3. グループに自分（と確認してほしい人）のメールアドレスを追加する
4. 届いた招待メールをスマホで開き、案内どおり **App Tester** アプリを入れる

### 5-4. 動作確認

任意の PR に `/apk` とコメントする。8〜15 分でスマホの App Tester に通知が
届けば成功。届かないときは Actions のログ →
`https://appdistribution.firebase.google.com/testerapps/...`（PR への結果コメント内リンク）を確認。

---

## 6. トラブルシューティング

| 症状 | 原因と対処 |
| --- | --- |
| Issue に「依頼する」を選んだのに Actions で `claude` ジョブが失敗する | `CLAUDE_CODE_OAUTH_TOKEN` 未登録（§1）。または Claude GitHub App が未インストール |
| `claude` ジョブがそもそも起動しない | Issue の作成者に書き込み権限が無い（公開リポジトリのため OWNER / COLLABORATOR のみ起動する仕様）。コラボレーターとして招待する |
| プレビュー / 本番反映が「Secrets 未設定」でスキップされる | §2〜§3 が未完了。PR コメントと Actions の warning に不足名が出る |
| プレビューは開けるがログインできない | §4 の登録漏れ。プレビュー URL が変わった（30 日失効）場合も同じ |
| `/apk` が「Secret が未設定です」で失敗する | §5 が未完了。エラーメッセージに不足している Secret 名が出る |
| APK は届くが Google ログインに失敗する | §5-2 の SHA-1 登録漏れ、または google-services.json の Secret が古い |
| APK の更新がインストールできない（「アプリはインストールされていません」等） | 署名が変わっている。以前のキーストアを復元するか、端末側でアンインストールしてから入れ直す |

---

## 7. セキュリティ上の約束（AGENTS.md との関係）

- サービスアカウント鍵・キーストア・env ファイルを**リポジトリにコミットしない**
  （このリポジトリは公開。Secrets 経由でのみ CI に渡す）
- サービスアカウントのロールは Hosting と App Distribution の管理者のみ。
  **Supabase（インサイト実数値のある本番 DB）には一切アクセスできない**
- 本番 Supabase への反映（マイグレーション・Edge Functions）を自動化しないのは
  意図的な判断（R-1〜R-5 の防衛線を人間のレビュー＋手動操作に残すため）。
  再検討する場合は [../open_issues.md](../open_issues.md) の `OI-45` を参照
