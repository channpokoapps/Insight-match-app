# CLAUDE.md

このリポジトリで作業する前に、必ず [AGENTS.md](AGENTS.md) を読んで従うこと。
特に「§0 絶対に破ってはならないルール(R-1〜R-10)」は、機能追加・修正のいかなる理由よりも優先される。

## 要点(詳細は AGENTS.md)

- インサイト実数値・SNS トークンは `private` スキーマのみ。クライアントに返す型に実数値フィールドを定義しない。集計は k=5 未満なら実数を返さない。
- DB 変更は `supabase/migrations/` のマイグレーションのみ。`public` の新テーブルは同一マイグレーション内で RLS 有効化+ポリシー必須。
- Flutter は feature-first + Riverpod + go_router。Supabase 呼び出しは `data/` の Repository に閉じ込める。freezed / build_runner は使わない。
- R-1〜R-5 に触れる変更は `supabase/tests/` にテスト追加必須。CI で `supabase/tests/` が落ちたらマージ禁止。

## ブランチ・コミット・PR

- 作業ブランチ: `claude/<内容を表すslug>`
- コミット: Conventional Commits(`feat:` `fix:` `docs:` `refactor:` `test:` `chore:`)、日本語本文可
- PR には機能 ID(`FR-xxx-nn`)を記載。DB スキーマ変更を含む PR は R-1〜R-5 への影響を本文に明記
- `claude/**` ブランチの push で `.github/workflows/auto-pr.yml` が main 向け PR を自動作成する(クラウドセッションから直接 PR を作った場合は重複しないようスキップされる)
- 自動マージ禁止。R-1〜R-5 に関わるため必ず人間がレビューする

## 検証コマンド

- Flutter: `cd app && flutter analyze && flutter test`
- Supabase: `supabase db start && supabase test db`(権限・RLS・k-匿名性テスト)

## 仕様が曖昧なとき

推測で実装しない。[docs/open_issues.md](docs/open_issues.md) の `OI-xx` を確認し、なければ新規起票して確認を求める。インサイト開示範囲の判断は必ず非開示側に倒す。
