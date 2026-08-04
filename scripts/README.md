# scripts

## build_master_data.mjs

全国の都道府県・市区町村・路線・駅のマスタデータから、マイグレーション SQL を生成する。

```bash
node scripts/build_master_data.mjs           # 生成して上書き
node scripts/build_master_data.mjs --check   # 既存ファイルと差分があるか確認するだけ
```

生成されるファイル（**手で編集しないこと**）:

| ファイル | 内容 |
|---|---|
| `supabase/migrations/0012_master_cities.sql` | 都道府県 47 件・市区町村 1,902 件 |
| `supabase/migrations/0013_master_railways.sql` | 路線 602 件・駅 8,988 件 |

依存パッケージはなく、Node 18 以降の `fetch` だけで動く。全 602 路線の詳細を
1 本ずつ取得するため、1 分ほどかかる。

### 出典とライセンス

| データ | 出典 | ライセンス |
|---|---|---|
| 都道府県・市区町村 | [code4fukui/address-japan](https://github.com/code4fukui/address-japan) `data/city.csv`（デジタル庁 アドレス・ベース・レジストリ 市区町村マスターデータセット由来） | MIT License |
| 路線・駅 | [Seo-4d696b75/station_database](https://github.com/Seo-4d696b75/station_database) `out/main` | **CC BY 4.0** |

**駅データは CC BY 4.0 のため、クレジット表示が必要**。アプリ内の
「設定 → データ出典」画面（`app/lib/features/settings/presentation/data_sources_page.dart`）で
表示している。出典を変更したらこの画面も更新すること。

### 更新のしかた

駅データは月次で更新される（新駅開業・駅名改称など）。取り込み直すときは、

1. `node scripts/build_master_data.mjs` を実行する
2. `git diff --stat` で件数の変化が妥当か確認する
3. `0012` / `0013` は `on conflict do update` で書かれているため、**再適用しても
   既存 id は壊れない**。ただし駅が廃止されると `delete` されるので、
   `client_profiles.nearest_station_id` / `campaigns.nearest_station_id` が
   null に落ちうる点に注意する
4. 新しい番号のマイグレーションとして切り出すか、既存を差し替えるかは
   本番適用済みかどうかで判断する（適用済みなら新規ファイルにする）

### 設計メモ

- 市区町村の `id` は**全国地方公共団体コードの上 5 桁**（JIS コード）。連番ではない。
- 政令指定都市は「札幌市」の行と「札幌市 中央区」の行が両方あるため、
  区を持つ市の親行は落とし、`札幌市中央区` の形で 1 行にする。
- `cities` は `(prefecture_id, name)` が一意。同一県内で名前が衝突する町村
  （北海道の `泊村` が古宇郡と国後郡にある）は郡名を付けて区別する。
- 路線・駅の `id` は駅データ側のコードをそのまま使う。駅は路線ごとに 1 行
  （`stations.line_id` が not null のため）。
- `railway_lines.prefecture_ids` は所属駅から集計した非正規化列。
  「都道府県 → 路線 → 駅」の絞り込みを 1 クエリで済ませるために持つ。
- 廃線・廃駅（`closed`）は取り込まない。
