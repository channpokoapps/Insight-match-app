# 開発環境セットアップ・チェックリスト

このリポジトリを**別のPC**で開いて、実装を開始できる状態にするための手順書です。

- 【事実】= このリポジトリの現状から確認できること
- 【前提】= この手順が成り立つために必要な条件
- 【推奨】= 決めていないが、こうするのがよいと考えられること
- 【要確認】= 着手前に人が判断する必要があること

---

## A-0. この文書の使い方

【事実】現在のリポジトリには **要件定義・DB マイグレーション・Edge Functions・Flutter のドメイン層とデータ層**まで入っています。
一方で、**このリポジトリを作成した環境には Flutter SDK / Supabase CLI / Docker / Deno がありません**。したがって、以下はいずれも **一度も実行されていません**。

| 項目 | 状態 |
|---|---|
| `flutter pub get` / `flutter analyze` / `flutter test` | **未実行** |
| `supabase start` / `supabase db reset` / `supabase test db` | **未実行** |
| `deno task check` / `deno lint` | **未実行** |
| Android プロジェクト（`app/android/`） | **未生成** |
| GitHub Actions | **未実行** |

つまり **A-1〜A-8 は「動作確認」ではなく「初回の実行」** です。エラーが出るのは想定内なので、出たものを潰していってください。

### 完了の定義

以下がすべて通ったらセットアップ完了です。

- [ ] `supabase db reset` が最後まで通る
- [ ] `supabase test db` で `01`〜`06` のテストがすべて ok
- [ ] `flutter analyze --fatal-infos` が 0 issues
- [ ] `flutter test` が全件成功
- [ ] `deno task check` がエラーなし
- [ ] GitHub Actions の全ジョブが緑

---

## A-1. アカウント・外部サービスの準備

【要確認】以下は人の判断・申請が必要です。コードでは解決できません。

| # | やること | 関連 |
|---|---|---|
| 1 | GitHub リポジトリを作成し、このディレクトリを push する | — |
| 2 | Supabase アカウント作成（本番プロジェクトは後でよい。ローカル開発だけなら不要） | ADR-0002 |
| 3 | Meta for Developers のアプリ作成。**Instagram Graph API の審査は時間がかかるため最優先で着手** | `OI-01` `OI-37` |
| 4 | Firebase プロジェクト作成（プッシュ通知） | `OI-11` |
| 5 | Google Play Console の開発者登録 | — |

【推奨】3 は Meta の審査に数週間かかることがあるため、コードを書き始めるのと**同時に**申請作業を進めてください。審査待ちの間は開発モードのテストユーザーで動かせます。

---

## A-2. ツールのインストール（Windows / PowerShell）

【前提】管理者権限があること。

| ツール | 必要バージョン | 用途 |
|---|---|---|
| Git | 2.40+ | — |
| Flutter SDK | 3.22+（Dart 3.4+） | アプリ本体 |
| Android Studio | 最新 | Android SDK / エミュレータ |
| Docker Desktop | 最新 | Supabase ローカル環境 |
| Supabase CLI | 1.190+ | マイグレーション・pgTAP |
| Deno | 1.45+ | Edge Functions |
| VS Code | 最新 | — |

```powershell
# winget が使える環境ならまとめて入る
winget install --id Git.Git -e
winget install --id Docker.DockerDesktop -e
winget install --id DenoLand.Deno -e
winget install --id Supabase.CLI -e
winget install --id Google.AndroidStudio -e
```

Flutter は winget 版だとパスの扱いで詰まることがあるため、【推奨】は公式手順（zip 展開 → PATH 追加）です。

```powershell
# 入ったか確認
flutter --version
dart --version
supabase --version
deno --version
docker --version
```

```powershell
# Android のライセンス同意（これを忘れるとビルド時に失敗する）
flutter doctor
flutter doctor --android-licenses
```

VS Code を開くと `.vscode/extensions.json` に沿って拡張機能の推奨が出ます。すべて入れてください。
【事実】Deno 拡張はワークスペース全体で有効にすると Dart の解析が壊れるため、`.vscode/settings.json` で `supabase/functions` のみに限定済みです。

---

## A-3. Flutter プロジェクトのプラットフォーム生成

【事実】`app/` には `lib/` `test/` `pubspec.yaml` はありますが、`android/` `ios/` `web/` などのプラットフォーム固有ディレクトリは**ありません**（環境依存のファイルなのでリポジトリに含めていません）。

```powershell
cd app
flutter create . --project-name insight_match --org app.insightmatch --platforms=android,web
```

【要確認】`--org` は逆ドメイン形式のアプリケーション ID になります（例: `jp.co.yourcompany`）。**一度ストアに公開すると変更できません**ので、A-1 の 5 と合わせて先に決めてください（`OI-05` に関連）。

`flutter create .` は既存ファイルを上書きしません（`pubspec.yaml` は既存が優先されます）が、実行後に必ず差分を確認してください。

```powershell
git status
git diff app/pubspec.yaml
```

万一 `pubspec.yaml` が書き換わっていたら元に戻します。

```powershell
git checkout -- app/pubspec.yaml
```

【推奨】iOS は後回しにします。Instagram 連携と非開示ロジックの検証を Android で先に終わらせるほうが手戻りが少ないためです（`OI-06`）。

---

## A-4. 環境変数

【事実】`app/lib/core/env/env.dart` は `--dart-define` から値を読みます。ハードコードはしていません。

```powershell
Copy-Item env\local.example.json env\local.json
```

`env/local.json` を開き、A-5 の `supabase start` が出力する値を書き込みます。

| キー | 値 |
|---|---|
| `SUPABASE_URL` | `supabase start` の `API URL` |
| `SUPABASE_ANON_KEY` | `supabase start` の `anon key` |
| `IS_PRODUCTION` | ローカルは `false` |

【事実】`env/local.json` は `.gitignore` 済みです。`env/local.example.json` だけがコミット対象になります。

> **`service_role key` は絶対に `env/local.json` に書かないでください**（AGENTS.md R-6）。
> このキーは RLS をすべて無視できるため、アプリに渡った時点で非開示の仕組みが無効になります。
> Edge Functions は Supabase 側から自動で受け取るので、アプリ側に書く必要はありません。

---

## A-5. Supabase ローカル環境

【前提】Docker Desktop が起動していること。

```powershell
cd d:\app2
supabase start
```

初回はイメージのダウンロードで時間がかかります。完了すると API URL / anon key / service_role key / Studio URL が表示されるので、A-4 に転記します。

```powershell
# マイグレーションを全部当て直して seed を流す
supabase db reset
```

### 【要確認】0006_cron.sql で止まる場合

【事実】`supabase/migrations/0006_cron.sql` は `pg_cron` / `pg_net` と Vault のシークレット（`project_url` / `service_role_key`）に依存します。ローカル環境ではこれらが無く、失敗する可能性があります。

失敗した場合の対処（どちらかを選ぶ）:

1. Studio の SQL Editor で Vault にダミー値を登録してから再実行する
2. ローカル検証では 0006 を一時的に対象外にする（**コミットはしない**）

```powershell
# 2 の場合。検証が終わったら必ず戻すこと
Rename-Item supabase\migrations\0006_cron.sql 0006_cron.sql.skip
supabase db reset
Rename-Item supabase\migrations\0006_cron.sql.skip 0006_cron.sql
```

【推奨】恒久対応としては、0006 の内容を「拡張機能の作成」と「cron スケジュール登録」に分割し、後者を本番専用マイグレーションにします。判断は実際にエラーを見てから行ってください。

### 権限テスト（このプロダクトで最も重要な検証）

```powershell
supabase test db
```

期待する出力:

```
supabase/tests/01_private_isolation.test.sql .. ok
supabase/tests/02_rls.test.sql ............... ok
supabase/tests/03_k_anonymity.test.sql ....... ok
supabase/tests/04_criteria.test.sql .......... ok
supabase/tests/05_alias.test.sql ............. ok
supabase/tests/06_chat_masking.test.sql ...... ok
```

**ここが落ちたまま先へ進まないでください。** これらは「インサイト実数値が誰にも見えない」ことを機械的に保証する唯一の仕組みです（AGENTS.md R-1〜R-5）。

【推奨】pgTAP のアサーション（`has_column_privilege` の引数順など）は初回に細かい書式エラーが出やすい部分です。落ちた場合、まず**テストの書き方の誤り**を疑い、次に**本体の実装の誤り**を疑ってください。ただし「テストを消して通す」は禁止です。

---

## A-6. Flutter のビルドと実行

```powershell
cd app
flutter pub get
flutter analyze --fatal-infos
flutter test
```

【前提】`analysis_options.yaml` で `prefer_const_constructors` などを有効にしているため、初回は `--fatal-infos` で指摘が出る可能性があります。指摘は**ルールを緩めるのではなく**コードを直して解消してください。

```powershell
# エミュレータまたは実機で起動
flutter run --dart-define-from-file=..\env\local.json
```

【決定済み（2026-08）】モデルは**手書き `fromJson` を正式採用**し、freezed / build_runner は
依存からも削除しました（AGENTS.md §3 参照。ビルド時間と依存衝突の回避のため）。
コード生成の実行は不要です。

---

## A-7. Edge Functions

```powershell
cd supabase\functions
deno task check
deno lint
deno fmt --check
```

ローカルで動かす場合:

```powershell
cd d:\app2
supabase functions serve sync-worker --env-file supabase\functions\.env.local
```

【要確認】`supabase/functions/.env.local` には Meta の App ID / App Secret / トークン暗号鍵が必要です。このファイルは `.gitignore` 済みで、**リポジトリには存在しません**。A-1 の 3 が完了してから作成してください。

【事実】`sync-worker/index.ts` の `decryptToken` は AES-GCM の実装が入っていますが、**鍵の管理方法が未決**です（`OI-17`）。着手前に方式を決めてください。

---

## A-8. CI を緑にする

【事実】`.github/workflows/ci.yml` に 5 つのジョブがあります。**一度も実行されていません。**

| ジョブ | 内容 | 通す順番 |
|---|---|---|
| `guardrails` | 非開示要件の静的チェック（grep） | 1 番目（依存が無く速い） |
| `database` | マイグレーション適用 + pgTAP | 2 番目 |
| `functions` | `deno lint` / `deno task check` | 3 番目 |
| `flutter` | `analyze` / `test` | 4 番目 |
| `android-build` | APK ビルド | 5 番目（`app/android/` 生成後） |

【推奨】ローカルで A-5〜A-7 を通してから push してください。CI で試行錯誤すると 1 回あたり数分待つことになります。

---

## A-9. 実装に着手する前に決めるべきこと

【要確認】以下は**コードの構造に影響する**ため、実装を進める前に判断が必要です。詳細は [open_issues.md](open_issues.md) を参照してください。

| ID | 決めること | 影響範囲 |
|---|---|---|
| `OI-01` | Meta 審査の申請主体（法人 / 個人） | 申請開始時期。全体の日程を左右する |
| `OI-17` | SNS アクセストークンの暗号化方式と鍵管理 | Edge Functions・`private.social_credentials` |
| `OI-26` | 認証方式（メール / SNS / 電話） | 認証画面・`profiles` |
| `OI-06` | 対応 OS 下限 | `pubspec.yaml`・使えるパッケージ |
| `OI-37` | Instagram で実際に取れる指標の確定 | 条件式の選択肢・`private.creator_metrics` |
| `OI-43` | チャットのリアルタイム配信方式 | `chat_repository.dart`・Realtime 設定 |
| `OI-04` | ステマ規制（`#PR` 表記）の強制方法 | 投稿検証ロジック |
| `OI-14` | 参加者が k 未満の案件のレポート表示 | `campaign_report.dart` |

【推奨】`OI-37` は「Meta の開発モードで 1 アカウント連携して、実際に返る JSON を見る」だけで決着します。**最初のスプリントでここを潰す**と、条件式まわりの手戻りが激減します。

---

## A-10. 最初の 2 スプリントの進め方

【推奨】[backlog.md](backlog.md) の「リリース0（内部検証）」から着手します。

### スプリント 1 — 土台と非開示の検証

1. A-1〜A-8 のセットアップ完了
2. `T-001`〜`T-006`（認証・プロフィール・ロール分岐）
3. `supabase/tests/` が全部通る状態を維持する

### スプリント 2 — Instagram 連携

1. `T-010`〜`T-016`（OAuth・トークン保存・手動同期）
2. `T-020`〜`T-026`（インサイト取得・`private.creator_metrics` への集計）
3. `OI-37` の確定と `docs/requirements/09_external_integrations.md` の更新

【推奨】UI は後回しにしてください。このプロダクトの難しさは画面ではなく**「見せない」仕組み**にあります。そこが動いてから画面を作るほうが速く終わります。

---

## A-11. 詰まりやすいところ

| 症状 | 原因 | 対処 |
|---|---|---|
| `supabase start` が終わらない | Docker が起動していない / メモリ不足 | Docker Desktop の割り当てを 4GB 以上にする |
| `db reset` が 0006 で失敗 | Vault のシークレット未設定 | A-5 の手順を参照 |
| `supabase test db` が 0 件 | ファイル名が `*.test.sql` でない | 命名規約を確認 |
| VS Code で Dart のエラーが大量に出る | Deno 拡張がワークスペース全体で有効 | `.vscode/settings.json` の `deno.enablePaths` を確認 |
| `flutter run` で接続エラー | Android エミュレータから `localhost` は見えない | `SUPABASE_URL` を `http://10.0.2.2:54321` にする |
| `flutter analyze` で大量の info | `--fatal-infos` は info も失敗扱い | コードを直す。ルールを消さない |
| CI の `guardrails` が落ちる | `app/lib` に `service_role` の文字列 | 本当に混入していないか確認する |

---

## A-12. このPCでできること / 別PCが必要なこと

【事実】現時点での切り分けです。

| できること（ツール不要） | 別PCが必要なこと |
|---|---|
| 要件定義・ADR の追記・修正 | `flutter` コマンド全般 |
| SQL マイグレーションの記述 | `supabase` コマンド全般 |
| Dart のドメイン型・Repository の記述 | `deno` コマンド全般 |
| Edge Functions のコード記述 | Docker を使う検証すべて |
| OpenAPI・バックログの更新 | 実機・エミュレータでの動作確認 |
| 画面のウィジェット実装（動作確認は別PC） | コード生成（`build_runner`） |

【推奨】UI の実装は「別PCでセットアップが通ってから」にしてください。動作確認できない画面コードを増やしても、後でまとめて直すことになります。

---

## 未決事項（この文書に関するもの）

| ID | 内容 | 推奨案 |
|---|---|---|
| `OI-05` | アプリケーション ID（`--org` の逆ドメイン）に使う法人ドメイン | A-1 の 5 と同時に決定する |
| `OI-06` | 対応 OS 下限。A-3 の `flutter create` 後に `build.gradle` へ反映が必要 | Android 8.0（API 26）以上 |
| `OI-17` | トークン暗号鍵の置き場所。Supabase Vault / 環境変数 / KMS | Supabase Vault |
| `OI-43` | チャットのリアルタイム配信方式 | 当面は再取得。将来は Broadcast で通知のみ |

新しく判明した未決事項は [open_issues.md](open_issues.md) に追記してください。
