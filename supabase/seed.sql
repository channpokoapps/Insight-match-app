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

-- 都道府県・市区町村・路線・駅は 0012 / 0013 のマイグレーションが投入する
-- （全国分あり、scripts/build_master_data.mjs で生成）。ここでは何も入れない。
