# Flutter アプリ

## 初回だけ必要な作業

このディレクトリには `lib/`・`test/`・`pubspec.yaml` のみを置いています。
Android / iOS のプラットフォームフォルダは Git 管理せず、各自の環境で生成します。

```powershell
cd app
flutter create . --project-name app2 --org com.example --platforms=android
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

> `flutter create .` は既存の `lib/main.dart` を上書きしません。
> `pubspec.yaml` が書き換わった場合は `git checkout pubspec.yaml` で戻してください。

## 起動

```powershell
flutter run --dart-define-from-file=../env/local.json
```

## ディレクトリ方針（feature-first）

```
lib/
├── core/                 アプリ全体で共有する土台
│   ├── env/              環境変数
│   ├── error/            失敗の分類。表示文言はここでしか作らない
│   ├── logging/          ログ。インサイト値・トークン・個人情報を出さない
│   ├── router/           go_router の定義
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

詳細は [../AGENTS.md](../AGENTS.md) を参照してください。
