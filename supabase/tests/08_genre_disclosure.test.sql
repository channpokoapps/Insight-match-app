-- 08_genre_disclosure.test.sql
-- ジャンルの複数選択対応(0011)で、店舗の公開範囲が広がっていないことを確認する。
--
-- v_client_public は投稿者が案件詳細で参照するビュー。列構成を作り直したので、
-- 連絡先(contact_email)と郵便番号(postal_code)が紛れ込んでいないことを固定する。
-- また「その他」の自由記述を集計する運営向け関数が、管理者以外から呼べないことを確認する。

begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

-- ---------------------------------------------------------------------------
-- 準備: 店舗1(連絡先・郵便番号あり)・投稿者1・管理者1
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'genre-cl@example.test'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'genre-cr@example.test'),
  ('eeeeeeee-0000-0000-0000-000000000003', 'genre-ad@example.test');

insert into public.profiles (id, role, status, admin_level) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'client',  'active', null),
  ('eeeeeeee-0000-0000-0000-000000000002', 'creator', 'active', null),
  ('eeeeeeee-0000-0000-0000-000000000003', 'admin',   'active', 'moderator');

insert into public.client_profiles (
  user_id, store_name, genre_ids, genre_other_text, postal_code, contact_email
) values (
  'eeeeeeee-0000-0000-0000-000000000001', 'ジャンル検証店',
  array[(select id from public.genres where name = '居酒屋')],
  'スペインバル', '150-0002', 'secret-owner@example.test'
);

-- ---------------------------------------------------------------------------
-- 公開ビューの列構成
-- ---------------------------------------------------------------------------
select hasnt_column(
  'public', 'v_client_public', 'contact_email',
  'v_client_public に連絡先メールアドレスを含めない'
);

select hasnt_column(
  'public', 'v_client_public', 'postal_code',
  'v_client_public に郵便番号を含めない'
);

select has_column(
  'public', 'v_client_public', 'genre_ids',
  'v_client_public で複数ジャンルを参照できる'
);

-- ---------------------------------------------------------------------------
-- 投稿者からの見え方
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"eeeeeeee-0000-0000-0000-000000000002","role":"authenticated"}', true);

select is(
  (select array_length(v.genre_ids, 1) from public.v_client_public v
   where v.user_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  1,
  '投稿者は店舗のジャンルを参照できる'
);

-- ---------------------------------------------------------------------------
-- 「その他」自由記述の集計は運営専用
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select * from public.list_genre_other_suggestions(1) $$,
  'unauthorized',
  '投稿者はジャンル自由記述の集計を取得できない'
);

select set_config('request.jwt.claims',
                  '{"sub":"eeeeeeee-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (select s.store_count from public.list_genre_other_suggestions(1) s
   where s.genre_text = 'スペインバル'),
  1,
  '運営はマスタ昇格候補として自由記述を集計できる'
);

select * from finish();
rollback;
