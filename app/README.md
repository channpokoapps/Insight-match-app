# Flutter アプリ

Android アプリと、閲覧専用のお試し Web 版を 1 つのコードベースで提供する。

`android/`（applicationId: `app.insightmatch.android`）と `web/` は
カスタム設定（条件付き google-services 適用・マニフェスト・PWA 設定）を含むため
**Git 管理する**。`flutter create` のやり直しは不要。

## 起動

```powershell
flutter pub get

# env/local.example.json をコピーして env/local.json を作り、anon key を設定してから
flutter run --dart-define-from-file=../env/local.json            # Android など
flutter run -d chrome --dart-define-from-file=../env/local.json  # Web お試し版
```

Firebase（GA4 計測）を有効にする場合は `google-services.json` の配置
（Android）や `env/web_firebase_config.json` の注入（Web）が必要。
未設定でも起動する（計測が無効になるだけ）。
手順は [../docs/manual_setup/gcp_firebase.md](../docs/manual_setup/gcp_firebase.md)。

## ディレクトリ方針（feature-first）

```
lib/
├── core/                 アプリ全体で共有する土台
│   ├── analytics/        GA4 イベント送信（install_cta_android / ios_interest 等）
│   ├── config/           公開設定値（ストア URL・規約バージョン）
│   ├── env/              環境変数
│   ├── error/            失敗の分類。表示文言はここでしか作らない
│   ├── firebase/         Web 版 Firebase 設定の組み立て
│   ├── logging/          ログ。インサイト値・トークン・個人情報を出さない
│   ├── masters/          マスタデータ（ジャンル・都道府県など）
│   ├── platform/         Web/Android の機能可否判定（閲覧専用 Web の中核）
│   ├── router/           go_router の定義（認証・登録段階のゲートを集約）
│   └── supabase/         SupabaseClient の Provider
├── features/<機能>/
│   ├── domain/           モデル・値オブジェクト
│   ├── data/             Repository（Supabase アクセスはここだけ）
│   └── presentation/     画面・Widget
└── shared/               複数機能で使う Widget・ユーティリティ
```

## 実装時の注意

- **Supabase へのアクセスは `data/` の Repository に閉じる。** 画面から直接 `SupabaseClient` を呼ばない。
- **`campaigns` などのテーブルを直接 select しない。** 投稿者向けの参照は RPC 経由のみ。
- 応募条件の判定結果（`is_eligible`）は表示の出し分けにのみ使う。**権限の担保はサーバ側**。
- 5 人未満で丸められた件数（`MaskedCount.masked == true`）から実数を推定して表示しない。
- `print` を使わない。`AppLogger` を使う（`avoid_print` で検出される）。
- **アクション UI は `kIsWeb` を直接見ない。** `PlatformCapability.isAvailable()` で判定し、
  不可なら `showInstallPromptSheet()` でインストール導線を表示する。

詳細は [../AGENTS.md](../AGENTS.md) を参照してください。
