-- seed.sql
-- ローカル開発用のマスタデータ。`supabase db reset` で自動投入される。
-- 個人情報・実データは絶対に含めないこと。

-- 飲食店専用のジャンル（0011_restaurant_genres.sql と同じ内容）。
-- マイグレーションが投入済みのため通常は何も起きない。名前で衝突を避ける。
insert into public.genres (name, sort_order) values
  ('和食', 10),
  ('寿司', 20),
  ('居酒屋', 30),
  ('ラーメン・うどん・蕎麦', 40),
  ('焼肉', 50),
  ('焼き鳥・串', 60),
  ('カフェ', 70),
  ('イタリアン', 80),
  ('フレンチ', 90),
  ('中華', 100),
  ('エスニック', 110),
  ('テイクアウト・デリ', 120),
  ('その他', 999)
on conflict (name) do nothing;

select setval('public.genres_id_seq', (select max(id) from public.genres));

insert into public.prefectures (id, name) values
  (1, '北海道'), (2, '青森県'), (3, '岩手県'), (4, '宮城県'), (5, '秋田県'),
  (6, '山形県'), (7, '福島県'), (8, '茨城県'), (9, '栃木県'), (10, '群馬県'),
  (11, '埼玉県'), (12, '千葉県'), (13, '東京都'), (14, '神奈川県'), (15, '新潟県'),
  (16, '富山県'), (17, '石川県'), (18, '福井県'), (19, '山梨県'), (20, '長野県'),
  (21, '岐阜県'), (22, '静岡県'), (23, '愛知県'), (24, '三重県'), (25, '滋賀県'),
  (26, '京都府'), (27, '大阪府'), (28, '兵庫県'), (29, '奈良県'), (30, '和歌山県'),
  (31, '鳥取県'), (32, '島根県'), (33, '岡山県'), (34, '広島県'), (35, '山口県'),
  (36, '徳島県'), (37, '香川県'), (38, '愛媛県'), (39, '高知県'), (40, '福岡県'),
  (41, '佐賀県'), (42, '長崎県'), (43, '熊本県'), (44, '大分県'), (45, '宮崎県'),
  (46, '鹿児島県'), (47, '沖縄県')
on conflict (id) do nothing;

select setval('public.prefectures_id_seq', (select max(id) from public.prefectures));

-- 市区町村・路線・駅は件数が多いため、別途インポートスクリプトで投入する（OI-10）。
-- 動作確認用に最小限のみ登録する。
insert into public.cities (id, prefecture_id, name) values
  (1, 13, '渋谷区'), (2, 13, '新宿区'), (3, 13, '港区'), (4, 27, '大阪市北区')
on conflict (id) do nothing;

select setval('public.cities_id_seq', (select max(id) from public.cities));

insert into public.railway_lines (id, name) values
  (1, 'JR山手線'), (2, '東京メトロ銀座線')
on conflict (id) do nothing;

select setval('public.railway_lines_id_seq', (select max(id) from public.railway_lines));

insert into public.stations (id, line_id, name, latitude, longitude) values
  (1, 1, '渋谷', 35.658034, 139.701636),
  (2, 1, '新宿', 35.690921, 139.700258),
  (3, 2, '表参道', 35.665247, 139.712313)
on conflict (id) do nothing;

select setval('public.stations_id_seq', (select max(id) from public.stations));
