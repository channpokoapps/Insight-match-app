# ADR-0007: Firebase / Google Cloud の運用を一時停止する

- **状態**：承認
- **日付**：2026-08-13
- **関連**：[ADR-0002](0002-supabase.md)、[gcp_firebase.md](../manual_setup/gcp_firebase.md)、[github_automation.md](../manual_setup/github_automation.md)、[poc_guide.md](../poc_guide.md)

## 背景

- アプリの運用をいったん停止する。稼働中の Firebase プロジェクト（`insight-match-2fbaa`）と、それに紐づく Google Cloud プロジェクトを削除し、費用が発生しうる状態を解消したい。
- 一方で、ソースコードは GitHub に残し、将来 Firebase / Google Cloud を再設定すればアプリを再び動かせる状態を維持したい。
- Claude Code（本セッション）は GitHub リポジトリの読み書きのみが可能で、Firebase Console・Google Cloud Console・Supabase ダッシュボードを操作する権限を持たない。したがって**実際のプロジェクト削除（課金停止そのもの）はコードの変更では実現できず、運営者が各コンソールで手動で行う必要がある**（手順は本 ADR 末尾）。
- ADR-0002 の時点で Firebase の用途は Hosting（お試し Web 版）・GA4（計測）・FCM（プッシュ通知、未実装）・Web の Google ログイン中継の 4 つに限定されており、Cloud Functions は使っていない。設計上これらは無料枠内に収まる想定だが、プロジェクトを稼働させ続けること自体（と、それを動かす GitHub Actions の自動化）を止めたいという要望のため、稼働中のリソースとそれを動かす自動化を対象にする。

## 対象範囲

| 対象 | 今回の対応 |
|---|---|
| Firebase Hosting（`insight-match-2fbaa.web.app`）・Authentication・GA4・FCM・App Distribution | プロジェクトごと削除（運営者が手動で実施。下記手順） |
| GitHub Actions の Firebase/GCP 自動化 | 本 PR でリポジトリから削除（「決定」参照） |
| **Supabase**（DB・Auth・Edge Functions） | **対象外。** バックエンドとして稼働を継続する |
| Flutter アプリ内の Firebase SDK 統合コード | **削除しない。**「決定」参照 |

## 選択肢

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| A | GitHub Actions 側の Firebase/GCP 自動化のみ削除し、アプリ内の Firebase SDK 統合コードは残す | 再設定時のコード変更が最小限で済む（設定値の注入だけで復活する）。差分が小さくレビューしやすい | 使われていない依存関係がアプリのコード上に残り続ける |
| B | A に加え、アプリ内の Firebase SDK 統合コード（`firebase_core` 等の依存、Google ログイン中継、GA4 送信、`web_firebase_options.dart`）も削除する | リポジトリが「今動く分だけ」になる | 変更量が大きい。再設定時にコードの復元が必要になり「再設定すれば作れる」の手間が増える |
| C | 何もしない（プロジェクト削除だけ運営者に依頼する） | 変更ゼロ | プロジェクト削除後、`deploy_preview.yml` 等が存在しない Firebase プロジェクトへのデプロイを試み続け、CI が恒常的に失敗する |

## 決定

**案 A** を採用する。

以下の GitHub Actions ワークフロー・アクション・スクリプトを削除する。いずれも Firebase/GCP との通信が唯一の役割であり、単体では意味を持たないため。

- `.github/workflows/deploy_preview.yml`（PR プレビューを Firebase Hosting へデプロイ）
- `.github/workflows/deploy_production.yml`（本番 Hosting への自動デプロイ）
- `.github/workflows/setup_auth.yml` と `scripts/setup_google_auth.mjs`（Firebase Authentication の Google プロバイダ設定を GCP API から自動化）
- `.github/actions/setup_firebase/action.yml`（上記 2 ワークフローが共有する firebase-tools 認証アクション）
- `.github/workflows/android_build.yml`（APK ビルド＋ Firebase App Distribution 配布。配布が Firebase 依存のため）

一方で、次のものは**削除しない**。

- `firebase.json` / `.firebaserc.example` / `env/web_firebase_config.example.json`
- Flutter アプリ内の Firebase 関連コード（`app/lib/core/firebase/`、`app/lib/core/analytics/`、`auth_repository.dart` の Google ログイン中継、`pubspec.yaml` の `firebase_*` 依存）

これらはビルド時の設定値が無くても動く設計（`main.dart` の `_initializeFirebase()` は初期化失敗を握りつぶす）であり、存在するだけでは課金対象にならないため、残しても「費用がかかるものを削除する」という目的に反しない。むしろ再設定時のコード変更を最小化できる。

**Supabase は対象外。** 今回の依頼は Firebase / Google Cloud に限定されており、Supabase はこのアプリの中核バックエンド（DB・認証・RLS による非開示の強制）であるため、明示的な依頼なしに停止・削除しない。

## 影響

- 良い影響：GitHub Actions が Firebase/GCP へ通信・デプロイしなくなる。プロジェクト削除後もワークフローが失敗し続ける状態を避けられる。
- 受け入れるトレードオフ：
  - お試し Web 版（`insight-match-2fbaa.web.app`）が閲覧不可になる。
  - **Web・Android とも Google ログインが使えなくなる**（`GOOGLE_WEB_CLIENT_ID` が参照する GCP OAuth クライアントごと消えるため）。メールアドレス＋パスワードでのログインは Supabase Auth 側の機能のため影響を受けない。
  - GA4 計測、`/apk` コメントでの APK 配布が止まる。
  - Supabase 側の機能（案件・応募・チャット・インサイト同期など）は Firebase と独立しているため**影響を受けない**。
- 新たな制約：Firebase/GCP を必要とする機能の変更・確認は、再設定（下記手順）が完了するまで検証できない。

## Firebase / Google Cloud プロジェクトの削除手順（運営者が行う）

Claude Code はこの操作を代行できない（各コンソールへの認証情報を持たない）。運営者が以下を行う。

1. <https://console.firebase.google.com/> を開き、対象プロジェクト（`insight-match-2fbaa`）を選ぶ。
2. 「プロジェクトの設定」（歯車アイコン）→「全般」タブを一番下までスクロールし、「プロジェクトを削除」を選ぶ。
3. 案内に従いプロジェクト ID を入力して確定する。
   - Firebase プロジェクトは Google Cloud プロジェクトと同一のため、これで Hosting・Identity Toolkit（Authentication）・Analytics など Cloud 側のリソースも削除される。個別に Google Cloud Console 側で追加の削除操作をする必要は通常ない。
   - 削除後もしばらく（Google の運用ポリシーに従う期間）は Google Cloud Console（<https://console.cloud.google.com/cloud-resource-manager>）から復元できる猶予がある。**手違いで消したときはここを確認する。**
4. （任意）GitHub の Settings → Secrets and variables → Actions から、今回のワークフロー削除で使われなくなった値を整理する。ストレージ自体は無料なので必須ではない。
   - 例: `FIREBASE_SERVICE_ACCOUNT` / `FLUTTER_WEB_FIREBASE_CONFIG` / `GOOGLE_WEB_CLIENT_SECRET` / `ANDROID_GOOGLE_SERVICES_JSON_BASE64`（Secrets）、`FIREBASE_PROJECT_ID` / `FIREBASE_ANDROID_APP_ID` / `APP_DISTRIBUTION_GROUPS`（Variables）
   - **`FLUTTER_ENV_PROD` は削除しないこと。** Supabase の接続情報も含まれており、Supabase 側の自動化（`supabase_migrate.yml` 等）が引き続き参照する。

## 再設定して復元する手順

1. 削除したファイルはこのコミットの revert で復元できる：`git revert <このコミットの SHA>`。個別ファイルだけ戻したい場合は `git show <このコミットの親>:<パス> > <パス>` でもよい。
2. [gcp_firebase.md](../manual_setup/gcp_firebase.md) の手順で新しい Firebase プロジェクトを作る（プロジェクト ID は変わってよい。`insight-match-2fbaa` はコード中にハードコードされておらず、`FIREBASE_PROJECT_ID` などの設定値経由で参照される）。
3. [github_automation.md](../manual_setup/github_automation.md) の手順で Secrets / Variables を登録し直す。
4. 1. で復元したワークフローが動くことを確認する。
