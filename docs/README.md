# ドキュメント索引

## 要件定義書

| # | ドキュメント | 概要 | 状態 |
|---|---|---|---|
| 0 | [00_index.md](requirements/00_index.md) | 要件定義書の目次・読み方・表記ルール・ID採番規則 | 作成済 |
| 1 | [01_introduction.md](requirements/01_introduction.md) | 背景・目的・スコープ・成功指標・用語定義 | 作成済 |
| 2 | [02_system_overview.md](requirements/02_system_overview.md) | システム全体像、コンポーネント構成、インサイト非開示アーキテクチャ原則 | 作成済 |
| 3 | [03_roles_and_permissions.md](requirements/03_roles_and_permissions.md) | ロール定義、権限マトリクス、アカウント状態遷移 | 作成済 |
| 4 | [04_assumptions_and_constraints.md](requirements/04_assumptions_and_constraints.md) | 前提条件・制約（SNS API／法規制／体制／スコープ） | 作成済 |
| 5 | [05_functional_requirements.md](requirements/05_functional_requirements.md) | 機能要件一覧（機能ID・優先度 Must/Should/Could、全118件） | 作成済 |
| 6 | [06_screens.md](requirements/06_screens.md) | 画面一覧・画面遷移図（ロール別）、モザイク表示仕様、レポートUI案 | 作成済 |
| 7 | [07_usecases.md](requirements/07_usecases.md) | 主要ユースケース（シーケンス図 10 本・状態遷移図 2 本） | 作成済 |
| 8 | [08_data_model.md](requirements/08_data_model.md) | データモデル（ER図・テーブル定義、public / private スキーマ分離） | 作成済 |
| 9 | [09_external_integrations.md](requirements/09_external_integrations.md) | 外部連携仕様（指標×プラットフォーム取得可否表、認可フロー、バッチ設計） | 作成済 |
| 10 | [10_non_functional.md](requirements/10_non_functional.md) | 非機能要件（性能・可用性・セキュリティ・コスト・保守性・テスト） | 作成済 |
| 11 | [11_tech_stack.md](requirements/11_tech_stack.md) | 技術スタック推奨案（Firebase/Supabase/AWS ・Flutter/RN 比較表） | 作成済 |
| 12 | [12_future_extensions.md](requirements/12_future_extensions.md) | 将来拡張（iOS対応・有料案件・決済）と不変条件 | 作成済 |

## 横断ドキュメント

| ドキュメント | 概要 |
|---|---|
| [setup_checklist.md](setup_checklist.md) | **開発環境のセットアップ手順**。別のPCで実装を始めるときは最初にこれを読む |
| [open_issues.md](open_issues.md) | 未決事項リスト（Open Issues / TBD）。全章の TBD をここに集約する（要件定義書 13章に相当） |
| [glossary.md](glossary.md) | 用語集。全章で使う用語の唯一の定義元（要件定義書 14章に相当） |
| [backlog.md](backlog.md) | 実装タスク（T-xxx）。機能要件をリリース0／リリース1に分けて着手順に並べたもの |
| [api/openapi.yaml](api/openapi.yaml) | RPC・Edge Functions のインターフェース定義 |

## アーキテクチャ決定記録（ADR）

| # | 決定 |
|---|---|
| — | [0000-template.md](adr/0000-template.md)（雛形） |
| 0001 | [Flutter を採用する](adr/0001-flutter.md) |
| 0002 | [Supabase を採用する](adr/0002-supabase.md) |
| 0003 | [インサイト非開示を3層で担保する](adr/0003-insight-non-disclosure.md) |
| 0004 | [日次バッチを pg_cron + Edge Function で実行する](adr/0004-daily-batch-pg-cron.md) |
| 0005 | [PR依頼者に見せる識別子は案件内連番とする](adr/0005-anonymous-alias.md) |

## リポジトリ内の関連ファイル

| ファイル | 概要 |
|---|---|
| [../AGENTS.md](../AGENTS.md) | 開発ルール。コードを書く前に必読 |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | 環境構築・開発フロー・レビュー観点 |
| [../supabase/migrations/](../supabase/migrations/) | DB 定義（唯一の変更手段） |
| [../supabase/tests/](../supabase/tests/) | 非開示要件の自動検証（pgTAP） |

## 決定済みの主要事項

| 項目 | 決定内容 |
|---|---|
| モバイル技術 | Flutter（Android 先行、将来 iOS） |
| バックエンド／DB | Supabase（PostgreSQL + RLS + Edge Functions） |
| 日次バッチ基盤 | Supabase pg_cron ＋ Edge Function |
| 匿名表示 | 案件内で閉じた連番（投稿者A / B / C…） |
| k-匿名性の閾値 | k = 5 |

> 根拠と経緯は [docs/adr/](adr/) に ADR として記録している。

## 更新ルール

- 各章の末尾には「本章の未決事項」を置き、`OI-xx` の ID で [open_issues.md](open_issues.md) を参照する（内容の本体は open_issues.md 側に書く）。
- 新しい用語を使う場合は必ず [glossary.md](glossary.md) に追記する。
- 図は Mermaid で記述し、画像ファイルは原則使用しない（差分レビュー可能性のため）。
- 記述には必ず【事実】【前提】【推奨】【仮定】のいずれかのラベルを付ける（[00_index.md](requirements/00_index.md) 0-3 参照）。
- 章をまたぐ参照は章番号ではなく ID（`FR-xxx-nn` 等）で行う。
