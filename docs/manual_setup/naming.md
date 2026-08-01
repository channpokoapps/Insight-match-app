# サービス名・ドメイン・パッケージ名の確定

`OI-44` に対応する。**Android のパッケージ名（applicationId）は Play 公開後に変更できない**ため、
公開前に必ずここの値を最終確認する。

---

## 1. 現在の暫定値（コードに設定済み）

| 項目 | 暫定値 | 変更できる期限 |
| --- | --- | --- |
| サービス名 | Insight Match（インサイトマッチング・仮） | ストア掲載まで |
| Dart パッケージ名 | `insight_match`（`app/pubspec.yaml`） | いつでも（内部名） |
| Android applicationId | `app.insightmatch.android`（`app/android/app/build.gradle.kts`） | **Play 公開まで** |
| ドメイン | 未取得（`OI-44`） | OAuth リダイレクト設定前に確定 |

## 2. 変更する場合の手順

1. `app/android/app/build.gradle.kts` の `namespace` と `applicationId` を変更する。
2. `app/android/app/src/main/kotlin/` のディレクトリと `MainActivity.kt` の `package` 行を合わせる。
3. Firebase コンソールに登録した Android アプリのパッケージ名も作り直す
   （`google-services.json` を再ダウンロードして差し替える）。
4. GCP の Android OAuth クライアント（SHA-1 登録）も作り直す。

## 3. 決める前のチェック

- [ ] 商標・既存サービス名との重複を確認した（J-PlatPat / ストア検索）
- [ ] 同名ドメインが取得可能なことを確認した
- [ ] SNS アカウント名（Instagram など）が取得可能なことを確認した
