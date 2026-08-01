# ADR-0001: モバイル技術スタックに Flutter を採用する

- **状態**：承認
- **日付**：2026-07-31
- **関連**：[11_tech_stack.md](../requirements/11_tech_stack.md) 11-3、`NFR-OPS-01`

## 背景

- 対象プラットフォームは初期 Android、将来 iOS（[04_assumptions_and_constraints.md](../requirements/04_assumptions_and_constraints.md) E-1）。
- 運用保守工数の最小化が最優先。
- 運営管理画面も必要だが、専用の Web フロントを別技術で作ると保守対象が増える。
- 成果レポートでヒストグラム描画が必要。

## 選択肢

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| A | Flutter | UI まで共通化。iOS 展開コストが最小。Flutter Web で管理画面も同一リポジトリ。グラフライブラリが充実 | Dart の習得が必要。Flutter Web は初回ロードが重い |
| B | React Native (Expo) | TypeScript 人材が多い。管理画面を React で自然に作れる | OS 間の描画差異。Expo の制約 |
| C | Kotlin Multiplatform | ネイティブ UI の品質 | UI は個別実装で共通化率が低い。管理画面は別技術 |
| D | ネイティブ個別開発 | 品質最高 | 実装・保守が 2 倍。最優先方針に反する |

## 決定

**A（Flutter）** を採用する。

決め手は、初期 Android のみでも同じコードがそのまま iOS になること、および管理画面を Flutter Web で同一コードベースに載せられるため、**保守対象のリポジトリを 1 つに保てる**こと。GitHub Copilot 活用が前提のため、Dart の学習コストは相対的に小さい。

## 結果

- 良い影響：将来の iOS 展開が「ビルド設定・審査対応」だけになる。単一 CI で全プラットフォームを検証できる。
- 受け入れるトレードオフ：Flutter Web の管理画面は初回ロードが重い。許容できない場合は Supabase Studio での代替を検討する（`OI-15`）。
- 新たな制約：**iOS 固有の分岐を作らない。** プラットフォーム固有機能はプラグイン経由で抽象化し、初期リリース時点でも iOS ビルドが通ることを CI で確認する。
