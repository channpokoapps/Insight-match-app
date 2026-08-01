# 開発環境セットアップと貢献ガイド

## 1. 必要なもの

| ツール | バージョン | 用途 |
|---|---|---|
| Flutter SDK | 3.22 以上 | アプリ本体 |
| Dart | Flutter 同梱 | — |
| Android Studio | 最新安定版 | Android SDK / エミュレータ |
| Docker Desktop | 最新 | Supabase ローカル環境 |
| Supabase CLI | 1.180 以上 | DB・Edge Functions |
| Deno | 1.4x | Edge Functions のローカル実行・型チェック |
| Git | 2.4x | — |

### インストール（Windows / PowerShell）

```powershell
# Flutter（推奨: 公式手順で zip 展開して PATH を通す）
flutter --version
flutter doctor

# Supabase CLI
npm install -g supabase
supabase --version

# Deno
irm https://deno.land/install.ps1 | iex
```

## 2. 初回セットアップ

```powershell
git clone <repository-url> insight-match-app
cd app2

# --- Supabase ---
supabase start          # 初回は Docker イメージの取得に時間がかかる
supabase db reset       # migrations + seed.sql を適用

# --- 非開示要件のテスト（ここが通らない状態で作業を進めない） ---
supabase test db

# --- Flutter ---
cd app
flutter pub get
```

`supabase start` の出力に含まれる `API URL` と `anon key` を控えます。

## 3. 環境変数

`env/local.example.json` をコピーして `env/local.json` を作成します
（**このファイルは Git にコミットしない**。gitignore 済み）。

```json
{
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_ANON_KEY": "<supabase start が表示した anon key>",
  "GOOGLE_WEB_CLIENT_ID": "",
  "IS_PRODUCTION": false
}
```

```powershell
flutter run --dart-define-from-file=../env/local.json
```

> `service_role` キーはアプリの環境変数に**絶対に入れません**（AGENTS.md R-6）。
> Edge Functions からのみ、Supabase 側の環境変数として利用します。

Edge Functions のローカル実行：

```powershell
supabase functions serve sync-insights --env-file supabase/functions/.env.local
```

`supabase/functions/.env.local`（コミットしない）：

```
TOKEN_ENCRYPTION_KEY=<base64 の 32 バイト鍵>
```

## 4. 日常の開発フロー

```powershell
# 1. ブランチを作る
git switch -c feat/FR-CMP-03-campaign-create

# 2. DB を変える場合はマイグレーションを追加
supabase migration new add_something
# 生成された supabase/migrations/<timestamp>_add_something.sql を編集
supabase db reset          # 常に一から適用し直して検証する

# 3. テスト
supabase test db           # DB の権限・RLS・k-匿名性
cd app
flutter analyze
flutter test

# 4. コミット
git commit -m "feat(campaign): 案件作成フォームを追加 (FR-CMP-03)"
```

### マイグレーションの注意

- **本番 DB を直接変更しない。** 変更は必ず `supabase/migrations/` に置く。
- `public` に新しいテーブルを作るときは、**同じマイグレーション内**で `enable row level security` とポリシーを書く。
- `private` スキーマのオブジェクトに `anon` / `authenticated` の権限を付けない。
- 既存マイグレーションを書き換えない（適用済み環境と乖離する）。修正は新しいファイルで行う。
- ファイル名は `supabase migration new` が付ける連番（タイムスタンプ）に従う。初期構築分のみ `0001_`〜`0006_` の固定連番を使っている。

### モデルの書き方

モデルは**不変クラス + 手書き `fromJson`** で書く（AGENTS.md §3）。
freezed / build_runner によるコード生成は使わない。
形の担保は `app/test/` の単体テストで行う。

## 5. コミットメッセージ

Conventional Commits に従います。

```
<type>(<scope>): <日本語の要約> (<FR-ID>)
```

| type | 用途 |
|---|---|
| `feat` | 機能追加 |
| `fix` | 不具合修正 |
| `refactor` | 挙動を変えない整理 |
| `test` | テストのみ |
| `docs` | ドキュメントのみ |
| `chore` | ビルド・依存関係など |

例：`feat(search): インサイト条件のAND/OR入力に対応 (FR-SRCH-04)`

## 6. Pull Request

PR には次を含めます。

- 対応する `FR-xxx-nn` または `OI-xx`
- 動作確認手順
- **非開示要件への影響**（「なし」でも明記する）
  - private スキーマの権限を変えたか
  - クライアントに返す項目を増やしたか
  - k-匿名性の判定に触れたか

`supabase test db` と `flutter analyze` / `flutter test` が通っていることが必須です。

## 7. レビュー時のチェックリスト

- [ ] インサイト実数値がクライアントに返る経路を作っていないか
- [ ] `private` を `anon` / `authenticated` に GRANT していないか
- [ ] 新しい `public` テーブルに RLS とポリシーがあるか
- [ ] PR依頼者向けのレスポンスに `creator_id` や投稿URLが混ざっていないか
- [ ] 5 人未満の集計値を返していないか
- [ ] ログにインサイト値・トークン・個人情報を出していないか
- [ ] SQL を文字列連結で組み立てていないか
- [ ] クライアント側の条件判定だけで応募を許可していないか（サーバ側で再検証しているか）

## 8. よくある詰まりどころ

| 症状 | 原因と対処 |
|---|---|
| `supabase start` が失敗する | Docker Desktop が起動していない。または 54321〜54324 番ポートが使用中 |
| `supabase db reset` でマイグレーションが落ちる | `0006_cron.sql` の pg_cron / pg_net はローカルで無効な場合がある。ローカル検証時は該当ファイルを一時的に除外してよい（本番設定はダッシュボードで行う） |
| `supabase test db` で pgtap が無いと言われる | 各テストファイル冒頭の `create extension if not exists pgtap with schema extensions;` が実行されているか確認する |
| RLS で自分のデータが見えない | `profiles` に該当行があるか、`status` が `active` かを確認する |
| `flutter run` で環境変数が null | `--dart-define-from-file` のパスが間違っている |
