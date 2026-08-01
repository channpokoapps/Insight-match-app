# Firebase（Hosting / GA4 / FCM）の設定

Firebase は次の 3 つだけに使う。バックエンドは Supabase（[supabase.md](supabase.md)）。

| 用途 | サービス | 費用 |
| --- | --- | --- |
| お試し Web 版の配信 | Firebase Hosting | 無料（10GB / 転送 360MB/日） |
| インストール導線・iOS 需要の計測 | Google Analytics (GA4) | 無料 |
| プッシュ通知（Phase 9） | FCM | 無料 |

> **Shift Navi とは別プロジェクトにする。**
> どちらかのサービスを畳むときにプロジェクト削除だけで完結し、GA4 の計測も混ざらない。
> プロジェクト数自体に課金は無いので、分けてもコストは変わらない。
> **Cloud Functions は使わない**（Blaze プランへの移行を不要にするため。サーバ処理は Supabase Edge Functions へ）。

---

## 1. プロジェクト作成

1. https://console.firebase.google.com → **プロジェクトを追加**
2. プロジェクト名: `insight-match`（ID は `insight-match-XXXXX` の形で自動採番される）
3. **Google アナリティクスを有効にする**（このプロジェクトの計測が iOS 版開発判断の材料になる）。
   アナリティクスの地域: 日本。

## 2. Web アプリ登録（お試し版 + GA4）

1. プロジェクトの設定 → マイアプリ → **ウェブアプリを追加**（ニックネーム: `insight-match-web`）。
   「Firebase Hosting も設定する」にチェック。
2. 表示された `firebaseConfig` の値を `env/web_firebase_config.example.json` をコピーした
   `env/web_firebase_config.json` に貼り付ける（**コミットしない**。gitignore 済み）。
   `measurementId`（`G-` で始まる値）も忘れずに設定する。
3. リポジトリ直下で Hosting を初期化する。

   ```bash
   firebase login
   cp .firebaserc.example .firebaserc   # プロジェクト ID を書き換える
   ```

4. ビルドしてデプロイする。

   ```bash
   cd app
   flutter build web \
     --dart-define-from-file=../env/prod.json \
     --dart-define-from-file=../env/web_firebase_config.json
   cd ..
   firebase deploy --only hosting
   ```

5. 公開 URL（`https://<project-id>.web.app`）を Supabase の
   **Auth → URL Configuration**（Site URL / Redirect URLs）に登録する（[supabase.md](supabase.md) §4.1）。

## 3. Android アプリ登録

1. プロジェクトの設定 → マイアプリ → **Android アプリを追加**
   - パッケージ名: `app.insightmatch.android`
   - SHA-1: `cd app/android && ./gradlew signingReport` の debug SHA-1
2. `google-services.json` をダウンロードし、`app/android/app/` に置く（**コミットしない**。gitignore 済み）。
   - ファイルが置かれると Gradle が自動で google-services プラグインを適用する
     （`app/android/app/build.gradle.kts` の条件分岐）。未配置でもビルドは通る（Analytics/FCM が無効になるだけ）。

## 4. GA4 でインストール導線を確認する

アプリが送るイベント（`app/lib/core/analytics/analytics_service.dart`）:

| イベント名 | 意味 |
| --- | --- |
| `install_cta_android` | Web 版で「Android アプリを入手」が押された回数 |
| `ios_interest` | 「iOS 版 (Coming Soon)」が押された回数。**iOS 版を作るかどうかの判断材料** |

- 動作確認: **GA4 → 管理 → DebugView**。デバッグビルド（`flutter run -d chrome`）からのイベントが
  リアルタイムに見える。
- 集計: **GA4 → レポート → エンゲージメント → イベント**（反映まで最大 24〜48 時間）。

## 5. FCM（Phase 9 で実施）

1. プロジェクトの設定 → **Cloud Messaging** → Firebase Admin SDK のサービスアカウント鍵を生成。
2. 鍵 JSON を Supabase のシークレットに登録する（Edge Function `send-push` が使用）。

   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
   ```

3. 鍵 JSON のローカルコピーは削除する。
