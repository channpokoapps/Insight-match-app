# 7. 主要ユースケース／業務フロー

---

## 7-1. ユースケース一覧

| ID | ユースケース | 主アクター | 関連機能 |
|---|---|---|---|
| `UC-01` | 投稿者が登録し SNS を連携する | creator | `FR-AUTH-01`, `FR-SNS-01`〜`03` |
| `UC-02` | 日次バッチでインサイトを更新する | system | `FR-INS-01`〜`06` |
| `UC-03` | PR依頼者が条件を設定して案件を公開する | client | `FR-CMP-04/05` |
| `UC-04` | 投稿者が案件一覧を見る（モザイク判定） | creator | `FR-SRCH-01/02` |
| `UC-05` | 応募して即マッチングする | creator | `FR-APP-01`〜`03` |
| `UC-06` | 応募者が募集人数を超えて選考する | client | `FR-APP-04`〜`06` |
| `UC-07` | 人数不足で条件緩和を提案・承認する | system / client | `FR-APP-08`〜`10` |
| `UC-08` | 投稿者がキャンセルを申請する | creator / client | `FR-APP-11/12` |
| `UC-09` | 投稿 URL を提出して検証する | creator / system | `FR-APP-14` |
| `UC-10` | PR依頼者が成果レポートを見る | client | `FR-RPT-01`〜`06` |
| `UC-11` | トークン失効から再認可する | system / creator | `FR-SNS-05/06` |
| `UC-12` | 通報を起票し運営が対応する | creator / client / admin | `FR-MSG-07`, `FR-ADM-05/06` |

---

## 7-2. UC-01：投稿者の登録と SNS 連携

```mermaid
sequenceDiagram
  autonumber
  actor CRE as 投稿者
  participant APP as アプリ
  participant AUTH as Supabase Auth
  participant EF as Edge Function<br/>(oauth-callback)
  participant IG as Instagram
  participant P as private スキーマ

  CRE->>APP: 新規登録（メール／パスワード／規約同意）
  APP->>AUTH: サインアップ
  AUTH-->>CRE: 確認メール送信
  CRE->>AUTH: メール内リンクを開く
  APP->>CRE: プロフィール入力を要求
  CRE->>APP: 氏名・生年月日・居住地 等
  APP->>APP: 18歳未満なら登録拒否
  APP->>CRE: SNS連携ガイドを表示<br/>（ビジネス／クリエイターへの切替手順）
  CRE->>IG: OAuth 認可画面で許可
  IG-->>EF: 認可コード（リダイレクト）
  EF->>IG: コードをアクセストークンに交換
  IG-->>EF: 長期アクセストークン
  EF->>IG: アカウント種別・基本情報を確認
  alt 個人アカウント
    EF-->>APP: エラー（切替が必要）
    APP->>CRE: 切替手順を再提示
  else ビジネス／クリエイター
    EF->>P: トークンを暗号化して保存
    EF->>P: 初回インサイト取得をキューへ登録
    EF-->>APP: 連携成功
    APP->>CRE: 同期待ち画面（進捗表示）
  end
```

【推奨】OAuth のリダイレクト先は Edge Function（サーバー）とし、**クライアントは認可コードもトークンも一切保持しない**。

---

## 7-3. UC-02：日次インサイト取得バッチ

```mermaid
sequenceDiagram
  autonumber
  participant CRON as pg_cron
  participant EF as Edge Function<br/>(sync-insights)
  participant P as private スキーマ
  participant IG as Instagram Graph API
  participant N as 通知

  CRON->>EF: 日次起動（深夜帯）
  EF->>P: 対象アカウントを取得<br/>（連携有効・前回同期から24h経過）
  loop バッチ単位（同時実行数を制限）
    EF->>P: トークンを復号
    EF->>IG: メディア一覧・インサイト取得
    alt 成功
      IG-->>EF: リーチ／保存／いいね／コメント／シェア／再生数
      EF->>P: 生データを upsert
      EF->>P: 7/30/90日平均・EG率・投稿頻度を再計算
      EF->>P: 同期成功を記録
    else 認可エラー
      EF->>P: ステータス = 要再認可
      EF->>N: 投稿者へ再連携依頼
    else レート制限 / 一時エラー
      EF->>P: リトライキューへ（指数バックオフ）
    end
  end
  EF->>P: バッチ実行サマリを記録
  opt 失敗率が閾値超過
    EF->>N: 運営へアラート
  end
```

【事実】1 ユーザーの失敗が他ユーザーの処理を止めない（各ユーザーの処理を独立したトランザクションにする）。

---

## 7-4. UC-03：条件設定と案件公開

```mermaid
sequenceDiagram
  autonumber
  actor CLI as PR依頼者
  participant APP as アプリ
  participant RPC as count_matching_creators()
  participant P as private スキーマ
  participant PUB as public スキーマ

  CLI->>APP: 条件を追加（例：平均保存数 >= 100）
  APP->>APP: デバウンス（入力停止 500ms 後）
  APP->>RPC: 条件式（JSON）
  RPC->>RPC: 条件式を検証<br/>（許可された指標・演算子のみ）
  RPC->>P: 集計値テーブルを COUNT
  alt 件数 >= 5
    RPC-->>APP: 件数（例：23）
  else 件数 < 5
    RPC-->>APP: "5人未満"
  end
  APP->>CLI: 「該当する投稿者：23人」
  CLI->>APP: OR 条件を追加して再計算
  Note over APP,RPC: 上記を繰り返す
  CLI->>APP: 募集要項・投稿指示を入力して公開
  APP->>PUB: 案件を INSERT（条件式を含む）
  PUB-->>APP: 公開完了
```

【推奨】条件式は**構造化 JSON**（`{"op":"AND","children":[{"metric":"avg_saves_30d","cmp":">=","value":100}]}` 等）で保存し、生の SQL 文字列は保存しない（SQL インジェクション対策）。RPC 側で許可リストに基づき SQL を組み立てる。

---

## 7-5. UC-04：案件一覧のモザイク判定

```mermaid
sequenceDiagram
  autonumber
  actor CRE as 投稿者
  participant APP as アプリ
  participant RPC as list_campaigns_for_creator()
  participant PUB as public スキーマ
  participant P as private スキーマ

  CRE->>APP: 案件一覧を開く（検索条件付き）
  APP->>RPC: 検索条件（地域・距離・ジャンル・並び順）
  RPC->>PUB: 公開中・応募期間内の案件を抽出
  RPC->>P: 呼び出しユーザーの集計値を取得
  loop 案件ごと
    RPC->>RPC: 条件式を評価 → is_eligible (boolean)
  end
  RPC-->>APP: 案件リスト<br/>（合致：全項目 / 非合致：is_eligible=false と最小限の項目のみ）
  APP->>CRE: 合致案件は通常表示、非合致はモザイク
```

【事実】**非合致案件については、店名・提供内容・想定価格などの詳細フィールドを RPC のレスポンスに含めない**。クライアント側でぼかすだけでは、通信内容から取得できてしまうため。

---

## 7-6. UC-05／UC-06：応募・選考・マッチング

### 状態遷移図：応募（application）

```mermaid
stateDiagram-v2
  [*] --> 応募中: 投稿者が応募
  応募中 --> マッチング成立: 応募者数 <= 募集人数（即時）
  応募中 --> 選考中: 応募期間終了かつ応募者数 > 募集人数
  応募中 --> 取消済: 投稿者が応募を取り消し
  選考中 --> マッチング成立: PR依頼者が選出
  選考中 --> 不成立: PR依頼者が選出せず／案件終了
  マッチング成立 --> キャンセル申請中: 投稿者がキャンセル申請
  キャンセル申請中 --> キャンセル成立: PR依頼者が承認
  キャンセル申請中 --> マッチング成立: PR依頼者が却下
  マッチング成立 --> 投稿済: 投稿URLを提出し検証成功
  マッチング成立 --> 未投稿終了: 投稿期間終了までに未提出
  投稿済 --> 完了: 案件完了処理
  キャンセル成立 --> [*]
  不成立 --> [*]
  取消済 --> [*]
  未投稿終了 --> [*]
  完了 --> [*]
```

### 状態遷移図：案件（campaign）

```mermaid
stateDiagram-v2
  [*] --> 下書き: 作成
  下書き --> 募集中: 公開
  募集中 --> 選考中: 応募期間終了かつ応募者数 > 募集人数
  募集中 --> 緩和提案中: 応募期間終了かつ応募者数 < 募集人数
  募集中 --> 進行中: 募集人数に達した／応募期間終了かつ充足
  緩和提案中 --> 募集中: PR依頼者が緩和案を承認（条件緩和・期間延長）
  緩和提案中 --> 進行中: PR依頼者が却下し現在の応募者で成立
  緩和提案中 --> 中止: 応募者0で却下／期限切れ
  選考中 --> 進行中: 選考確定
  選考中 --> 中止: 期限までに未確定（OI-30）
  進行中 --> 投稿期間終了: 投稿期間の終了日を経過
  投稿期間終了 --> 完了: 全投稿の検証完了
  完了 --> [*]
  中止 --> [*]
  募集中 --> 停止: 運営／依頼者が取り下げ
  進行中 --> 停止: 運営が強制停止
  停止 --> [*]
```

### シーケンス図：UC-05 即マッチング

```mermaid
sequenceDiagram
  autonumber
  actor CRE as 投稿者
  participant APP as アプリ
  participant RPC as apply_to_campaign()
  participant PUB as public スキーマ
  participant P as private スキーマ
  participant N as 通知

  CRE->>APP: 応募する
  APP->>RPC: 案件ID＋ひとことメッセージ
  RPC->>P: 呼び出しユーザーの集計値を取得
  RPC->>RPC: 条件を再判定（クライアントの状態を信用しない）
  alt 非合致 / 連携失効 / 期間外
    RPC-->>APP: エラー
  else 合致
    RPC->>PUB: 応募を INSERT（排他制御で二重応募を防止）
    RPC->>PUB: 現在の応募者数を確認
    alt 応募者数 <= 募集人数
      RPC->>PUB: 状態を「マッチング成立」に更新
      RPC->>PUB: チャットルームを作成
      RPC->>PUB: 案件内連番を採番（投稿者A/B/C…）
      RPC->>N: 双方へマッチング成立通知
    else 応募者数 > 募集人数
      RPC->>PUB: 状態は「応募中」のまま
      RPC->>N: PR依頼者へ新規応募通知
    end
    RPC-->>APP: 応募完了
  end
```

【推奨】「応募者数 ≦ 募集人数なら即マッチング」は、募集人数に達するまで先着順で成立し続けることを意味する。**同時応募による定員超過を防ぐため、応募 INSERT と定員判定を単一トランザクション内で行い、案件行に対して排他ロックを取る**。

### シーケンス図：UC-06 選考

```mermaid
sequenceDiagram
  autonumber
  participant SYS as システム
  actor CLI as PR依頼者
  participant APP as アプリ
  participant RPC as screen_applicants()
  participant P as private スキーマ
  participant N as 通知

  SYS->>SYS: 応募期間終了を検知（応募者数 > 募集人数）
  SYS->>N: PR依頼者へ選考開始を通知
  CLI->>APP: 応募者一覧を開く
  APP->>CLI: 投稿者A / B / C …（匿名連番・ひとことメッセージのみ）
  CLI->>APP: 追加条件を設定（例：平均リーチ >= 5000）
  APP->>RPC: 案件ID＋追加条件
  RPC->>P: 応募者の集計値で判定
  RPC-->>APP: 残り人数と、残った匿名連番のリスト
  Note over APP,RPC: 個々の実数値は返さない
  alt 残り人数 <= 募集人数
    CLI->>APP: 選考を確定
    APP->>RPC: 確定
    RPC->>RPC: 選出者をマッチング成立に、他を不成立に更新
    RPC->>N: 選出者・非選出者へ通知
  else まだ超過
    CLI->>APP: さらに条件を追加
  end
```

---

## 7-7. UC-07：条件緩和の提案と承認

```mermaid
sequenceDiagram
  autonumber
  participant SYS as システム（バッチ）
  participant RPC as generate_relaxation_proposal()
  participant P as private スキーマ
  actor CLI as PR依頼者
  participant N as 通知

  SYS->>SYS: 応募期間終了を検知（応募者数 < 募集人数）
  SYS->>RPC: 案件ID
  RPC->>P: 各条件を段階的に緩めた場合の該当人数を試算
  RPC->>RPC: 緩和案を生成<br/>①インサイト条件の緩和 ②応募期間の延長 ③両方
  RPC-->>SYS: 提案（例：平均保存数 100→70 で +12人）
  SYS->>N: PR依頼者へ提案通知
  CLI->>CLI: 提案内容を確認
  alt 承認
    CLI->>RPC: 承認（採用する案を選択）
    RPC->>RPC: 案件の条件・応募期間を更新、状態を「募集中」へ
    RPC->>N: 新たに条件合致した投稿者へ新着通知
  else 却下
    CLI->>RPC: 却下
    RPC->>RPC: 現在の応募者で成立させるか、案件を中止
  end
```

【事実】**承認しなければ緩和は適用されない。** システムが勝手に条件を下げることはない。

【推奨】緩和案の提示は「どの条件をどれだけ緩めると何人増えるか」を示す。ただし**増加人数も 5 人未満は丸める**（`OI-34`）。

---

## 7-8. UC-08：キャンセル申請

```mermaid
sequenceDiagram
  autonumber
  actor CRE as 投稿者
  participant APP as アプリ
  participant PUB as public スキーマ
  actor CLI as PR依頼者
  participant N as 通知

  CRE->>APP: キャンセル申請（理由を入力）
  APP->>PUB: 応募の状態を「キャンセル申請中」に更新
  APP->>N: PR依頼者へ通知
  CLI->>APP: 申請内容を確認
  alt 承認
    CLI->>PUB: 承認
    PUB->>PUB: 状態を「キャンセル成立」に更新、募集枠を1つ戻す
    PUB->>PUB: チャットを読み取り専用に
    PUB->>N: 投稿者へ承認通知
  else 却下
    CLI->>PUB: 却下（理由を添える）
    PUB->>PUB: 状態を「マッチング成立」に戻す
    PUB->>N: 投稿者へ却下通知
  end
```

【推奨】却下された場合に投稿者が履行できない状況は残るため、**却下後に一定期間が過ぎても投稿がない場合は自動的に「未投稿終了」とし、運営に記録を残す**運用を推奨する（`OI-31`）。

---

## 7-9. UC-09：投稿 URL の提出と検証

```mermaid
sequenceDiagram
  autonumber
  actor CRE as 投稿者
  participant APP as アプリ
  participant EF as Edge Function<br/>(verify-post)
  participant P as private スキーマ
  participant IG as Instagram Graph API
  participant PUB as public スキーマ

  CRE->>APP: 投稿URLを提出
  APP->>EF: 応募ID＋投稿URL
  EF->>P: 投稿者のトークンを復号
  EF->>IG: 本人のメディア一覧を取得
  EF->>EF: URL が本人のメディアに含まれるか照合
  EF->>EF: 指定ハッシュタグ（#PR 含む）の有無を確認
  alt 検証OK
    EF->>PUB: 応募状態を「投稿済」に更新、メディアIDを保存
    EF->>P: 当該メディアを成果集計の対象として記録
    EF-->>APP: 検証成功
  else 検証NG
    EF-->>APP: 理由を提示（他人の投稿／タグ不足 等）
  end
```

【事実】検証にも本人のトークンを使うため、**本人が連携を解除すると投稿検証ができない**。連携解除の前に警告を出す必要がある。

---

## 7-10. UC-10：成果レポートの閲覧

```mermaid
sequenceDiagram
  autonumber
  actor CLI as PR依頼者
  participant APP as アプリ
  participant RPC as get_campaign_report()
  participant PUB as public スキーマ
  participant P as private スキーマ

  CLI->>APP: 成果レポートを開く
  APP->>RPC: 案件ID
  RPC->>PUB: 依頼者本人か・投稿期間終了済かを検証
  RPC->>PUB: 当該案件の「投稿済」応募を取得
  RPC->>P: **当該案件の投稿分に限定**してインサイトを取得
  RPC->>RPC: 対象人数 n を判定
  alt n < 5
    RPC-->>APP: 非表示（理由付き）
  else n >= 5
    RPC->>RPC: 平均・中央値・最小・最大を算出
    RPC->>RPC: ヒストグラムを生成（件数5未満のビンは統合）
    RPC-->>APP: 匿名集計値のみ
  end
  APP->>CLI: ダッシュボード表示
```

---

## 7-11. UC-11：トークン失効からの再認可

```mermaid
sequenceDiagram
  autonumber
  participant EF as sync-insights
  participant P as private スキーマ
  participant N as 通知
  actor CRE as 投稿者
  participant IG as Instagram

  EF->>IG: インサイト取得
  IG-->>EF: 認可エラー
  EF->>P: ステータス = 要再認可
  EF->>N: 「連携が切れました」通知
  Note over CRE: この間、新規応募は不可。<br/>進行中案件の履行は継続可能
  CRE->>CRE: アプリを開く（常時バナー表示）
  CRE->>IG: 再認可
  IG-->>EF: 新しいトークン
  EF->>P: トークン更新、ステータス = 有効
  EF->>P: 即時インサイト取得をキューへ
```

---

## 7-12. UC-12：通報と運営対応

```mermaid
sequenceDiagram
  autonumber
  actor U as 通報者（投稿者／PR依頼者）
  participant APP as アプリ
  participant PUB as public スキーマ
  actor ADM as 運営
  participant AUD as 監査ログ

  U->>APP: 通報（対象・理由・詳細）
  APP->>PUB: 通報を INSERT（状態＝未対応）
  ADM->>APP: 通報一覧を確認
  opt チャット内容の確認が必要
    ADM->>APP: 会話を閲覧（super_admin のみ）
    APP->>AUD: 誰が・いつ・どの会話を・どの通報に基づき閲覧したかを記録
  end
  alt 違反あり
    ADM->>PUB: ユーザー停止／案件強制停止
    ADM->>AUD: 措置内容と理由を記録
  else 違反なし
    ADM->>PUB: 対応不要としてクローズ
  end
```

---

## 本章の未決事項

| ID | タイトル |
|---|---|
| `OI-30` | 選考が確定されない場合の期限と自動処理 |
| `OI-31` | キャンセル申請が却下された後の扱い |
| `OI-34` | 緩和提案で「増加人数」を提示する際の丸め方 |

詳細は [open_issues.md](../open_issues.md) を参照。
