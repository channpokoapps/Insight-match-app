# インフルエンサーマッチングアプリ

店舗（PR依頼者）と投稿者をマッチングするモバイルアプリ。

**このアプリの中核は「インサイトを条件に使えるが、実数値は誰にも見えない」という一点です。**
コードを書く前に [AGENTS.md](AGENTS.md) を必ず読んでください。

---

## 1. これは何か

| | |
|---|---|
| PR依頼者ができること | 案件を作成し、インサイト条件（例：直近30日の平均リーチが3,000以上）で応募者を絞り込む。条件に該当する人数はリアルタイムで見えるが、**誰が該当するかも、その人の数値も見えない** |
| 投稿者ができること | 条件を満たす案件だけに応募できる。条件を満たさない案件は詳細がモザイク表示される |
| 見えないもの | インサイト実数値（本人・PR依頼者・運営のいずれにも）、投稿者の氏名・SNSアカウント（PR依頼者に対して） |

## 2. 技術スタック

| 領域 | 採用 |
|---|---|
| アプリ | Flutter（Android 先行 / iOS は将来） |
| 状態管理 | Riverpod |
| ルーティング | go_router |
| バックエンド | Supabase（PostgreSQL / RLS / Edge Functions / Storage / Auth） |
| バッチ | pg_cron → Edge Function |
| 通知 | Firebase Cloud Messaging |

選定理由は [docs/adr/](docs/adr/) を参照。

## 3. リポジトリ構成

```
.
├── AGENTS.md                  開発ルール（最重要）
├── app/                       Flutter アプリ
│   ├── lib/
│   │   ├── core/              設定・DI・エラー・ルーティング
│   │   ├── features/          機能単位（auth / sns_link / campaign / ...）
│   │   └── shared/            共通ウィジェット・ユーティリティ
│   └── test/
├── supabase/
│   ├── migrations/            DB マイグレーション（唯一の DB 変更手段）
│   ├── functions/             Edge Functions
│   ├── tests/                 pgTAP による非開示要件の自動検証
│   ├── seed.sql               ローカル用マスタデータ
│   └── config.toml
└── docs/
    ├── requirements/          要件定義書（全13章）
    ├── adr/                   アーキテクチャ決定記録
    ├── api/openapi.yaml       API 定義
    ├── backlog.md             実装タスク
    ├── open_issues.md         未決事項（OI-xx）
    └── glossary.md            用語集
```

## 4. セットアップ

前提：Flutter SDK 3.x / Docker Desktop / Supabase CLI / Node.js（Supabase CLI を npm で入れる場合）

```powershell
# 1. Supabase をローカルで起動
supabase start

# 2. マイグレーションとシードを適用
supabase db reset

# 3. 非開示要件のテストが通ることを確認（必須）
supabase test db

# 4. Flutter の依存を取得
cd app
flutter pub get

# 5. 環境変数を設定して起動
flutter run --dart-define-from-file=../env/local.json
```

詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。

## 5. 最初に読むもの

| 目的 | ファイル |
|---|---|
| **環境構築（別PCで始めるとき）** | [docs/setup_checklist.md](docs/setup_checklist.md) |
| 開発ルール・禁止事項 | [AGENTS.md](AGENTS.md) |
| 何を作るのか | [docs/requirements/01_introduction.md](docs/requirements/01_introduction.md) |
| 機能一覧（FR-ID） | [docs/requirements/05_functional_requirements.md](docs/requirements/05_functional_requirements.md) |
| DB 設計と非開示の担保方法 | [docs/requirements/08_data_model.md](docs/requirements/08_data_model.md) |
| 実装の着手順 | [docs/backlog.md](docs/backlog.md) |
| まだ決まっていないこと | [docs/open_issues.md](docs/open_issues.md) |

## 6. 進め方の注意

- 仕様が不明な点を推測で実装しない。[docs/open_issues.md](docs/open_issues.md) に `OI-xx` として起票する。
- 非開示に関わる判断で迷ったら、**必ず開示しない側に倒す**。
- Meta（Instagram Graph API）の App Review に 2〜4 週間かかる。ここがクリティカルパスなので、実装より先に申請準備を進める（[OI-01](docs/open_issues.md)）。
