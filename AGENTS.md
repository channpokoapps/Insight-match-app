# AGENTS.md — 開発ルール

このリポジトリで作業する開発者および AI エージェントは、本ファイルのルールに従うこと。
仕様の根拠は [docs/README.md](docs/README.md) の要件定義書にある。

---

## 0. 絶対に破ってはならないルール（違反したコードはマージ禁止）

このプロダクトは「**インサイトを条件に使えるが、実数値は誰にも見えない**」という一点で成立している。
以下は機能追加・リファクタリング・パフォーマンス改善のいかなる理由があっても優先される。

| # | ルール |
|---|---|
| **R-1** | インサイト実数値と SNS アクセストークンは `private` スキーマにのみ置く。`public` のテーブル・ビュー・マテビューに写像しない |
| **R-2** | `private` スキーマを `anon` / `authenticated` に GRANT しない。PostgREST の公開スキーマにも含めない |
| **R-3** | クライアントに返す型に、インサイト実数値を含むフィールドを定義しない。返してよいのは boolean / 件数 / k-匿名性を満たす集計値のみ |
| **R-4** | 該当人数・集計値は **5 人未満なら実数を返さない**（k = 5）。二分探索で個人の値を逆算されるため |
| **R-5** | PR依頼者に投稿者を見せるときは `applications.alias_no`（案件内連番）のみ。`creator_id`・氏名・SNS アカウント名を露出しない |
| **R-6** | `service_role` キーをクライアント（Flutter アプリ）に埋め込まない。アプリが持つのは `anon` キーのみ |
| **R-7** | ログにインサイト値・トークン・個人情報を出力しない |
| **R-8** | 権限判定をクライアント側だけで行わない。応募可否・条件合致はサーバー側で必ず再判定する |
| **R-9** | ユーザー入力を SQL 文字列に連結しない。条件式は構造化 JSON を許可リストで検証する |
| **R-10** | 投稿検証で、ユーザーが提出した URL をサーバーから直接フェッチしない（SSRF）。本人のメディア一覧 API と突合する |

**R-1〜R-5 に触れる変更を行うときは、対応するテストを `supabase/tests/` に追加すること。**

---

## 1. リポジトリ構成

```
app/                Flutter アプリ（Android / iOS / 管理画面 Web）
supabase/
  migrations/       DB マイグレーション（DB を変更する唯一の手段）
  functions/        Edge Functions（Deno / TypeScript）
  tests/            権限・RLS・k-匿名性の検証 SQL
docs/               要件定義書・ADR・API 仕様・バックログ
.github/            CI・Issue テンプレート
```

---

## 2. データベース

### スキーマの使い分け

| スキーマ | 置くもの | クライアントからの参照 |
|---|---|---|
| `public` | 案件・応募・チャット・プロフィール・マスタ | RLS 経由で可 |
| `private` | **インサイト実数値・SNS トークン・監査ログ** | **不可（GRANT しない）** |

### ルール

- DB の変更は **必ず `supabase/migrations/` のマイグレーションで行う**。本番 DB を直接変更しない。
- `public` に新しいテーブルを作ったら、**同じマイグレーション内で** `ENABLE ROW LEVEL SECURITY` とポリシーを書く。ポリシーのないテーブルを作らない。
- RLS は**デフォルト拒否**。「誰が読めるか」を明示的に許可する。
- `private` を読む関数は `SECURITY DEFINER` かつ `SET search_path = ''`（スキーマを完全修飾で書く）。
- `SECURITY DEFINER` 関数を追加したら、`EXECUTE` 権限を必要なロールにだけ GRANT する。

### 命名規約

| 対象 | 規約 | 例 |
|---|---|---|
| テーブル | 複数形・スネークケース | `campaigns`, `creator_profiles` |
| カラム | スネークケース | `apply_end_at`, `reward_value_jpy` |
| 日時カラム | `_at` 接尾辞、型は `timestamptz` | `created_at` |
| 真偽値カラム | `is_` / `has_` 接頭辞 | `is_readonly` |
| 関数 | 動詞から始まるスネークケース | `count_matching_creators` |
| ポリシー | `{テーブル}_{操作}_{対象}` | `campaigns_select_owner` |
| マイグレーション | `NNNN_snake_case.sql` | `0004_rls_policies.sql` |

---

## 3. Flutter

### 構成

- **feature-first**。`lib/features/{機能}/` の下に `data/` `domain/` `presentation/` を置く。
- 横断的な基盤は `lib/core/`、共有ウィジェットは `lib/shared/`。
- 状態管理は **Riverpod**。`StatefulWidget` の `setState` はローカルな UI 状態のみに使う。
- ルーティングは **go_router**。認証・ロールによるリダイレクトは 1 か所に集約する。
- モデルは**不変クラス + 手書き `fromJson`** とする（RPC の返却は形が単純で、コード生成の
  ビルド時間・依存衝突に見合わないため。`app/test/` の単体テストで形を担保する）。
  freezed / build_runner は使わない。

### ルール

- **PR依頼者向けの画面・モデルに、投稿者のインサイト値や識別情報を持つフィールドを定義しない。** 型として存在させないことが最大の防御になる。
- Supabase の呼び出しは `data/` レイヤの Repository に閉じ込める。Widget から直接 `Supabase.instance` を触らない。
- **Web 版は閲覧専用のお試し版**。応募・チャット・SNS 連携などのアクション UI は、
  `kIsWeb` を直接見ずに `lib/core/platform/platform_capability.dart` で可否を判定し、
  不可なら `lib/shared/widgets/install_prompt.dart` のインストール導線を表示する。
  ただし**権限の担保はあくまでサーバー側（RLS / RPC）**であり、この判定は UI の出し分けにすぎない。
- インサイト数値を表示する画面には、必ず**最終同期日時**を併記する。
- 例外は握りつぶさない。ユーザーに見せるメッセージは「原因」と「次の行動」を含める。
- コメントは「コードから読み取れないこと」だけを 1 行で書く。処理の言い換えを書かない。

---

## 4. Edge Functions

- SNS API を叩くのは Edge Functions のみ。Flutter から SNS API を直接呼ばない。
- 1 ユーザーの処理失敗が他ユーザーを止めないよう、ユーザー単位で例外を捕捉して `private.sync_job_items` に記録する。
- レート制限・一時障害は指数バックオフでリトライキューへ。認可エラーはリトライせず `reauth_required` にする。
- シークレットは環境変数から読む。ハードコードしない。

---

## 5. テスト

| 種別 | 場所 | 必須度 |
|---|---|---|
| 権限・RLS・k-匿名性 | `supabase/tests/` | **必須**（R-1〜R-5 に関わる変更時） |
| Flutter ユニット | `app/test/` | ドメインロジックは必須 |
| Widget テスト | `app/test/` | 主要画面 |

CI では `flutter analyze` / `flutter test` / マイグレーション適用 ＋ `supabase/tests/` を実行する。
**`supabase/tests/` が落ちた場合は、他がすべて通っていてもマージしない。**

---

## 6. コミット・PR

- コミットメッセージは Conventional Commits（`feat:` `fix:` `docs:` `refactor:` `test:` `chore:`）。
- PR には対応する機能 ID（`FR-xxx-nn`）を書く。
- **DB スキーマの変更を含む PR では、非開示要件（R-1〜R-5）への影響を PR 本文に明記する。**

---

## 7. 仕様が曖昧なとき

- 要件定義書の **`OI-xx`（未決事項）** を確認する → [docs/open_issues.md](docs/open_issues.md)
- 記載がなければ**推測で実装せず**、`OI` を新規起票して確認を求める。
- 特に「インサイトをどこまで見せるか」に関わる判断は、**必ず非開示側に倒す**。

---

## 8. 用語

コード・コミット・ドキュメントで使う用語は [docs/glossary.md](docs/glossary.md) に統一する。

| 使う | 使わない |
|---|---|
| creator（投稿者） | influencer |
| client（PR依頼者） | advertiser, company |
| campaign（案件） | offer, job, recruitment |
| insight（インサイト） | analytics, stats |
