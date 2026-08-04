-- 09_search_filters.test.sql
-- 案件検索の絞り込み(0014)を足しても、報酬内容の非開示と権限判定が
-- 崩れていないことを確認する。
--
-- 絞り込み条件が増えると「条件を変えれば見えるのでは」という抜け道が
-- 生まれやすい。フィルタを通しても reward_description が漏れないこと、
-- creator 以外は一覧そのものを引けないことを固定する。

begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

-- ---------------------------------------------------------------------------
-- 準備: 大阪(阪急千里線 南千里)の案件1件、条件未達/充足の投稿者、PR依頼者
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('dddddddd-0000-0000-0000-000000000001', 'srch-cl@example.test'),
  ('dddddddd-0000-0000-0000-000000000002', 'srch-low@example.test'),
  ('dddddddd-0000-0000-0000-000000000003', 'srch-high@example.test');

insert into public.profiles (id, role, status) values
  ('dddddddd-0000-0000-0000-000000000001', 'client',  'active'),
  ('dddddddd-0000-0000-0000-000000000002', 'creator', 'active'),
  ('dddddddd-0000-0000-0000-000000000003', 'creator', 'active');

insert into public.client_profiles (user_id, store_name)
values ('dddddddd-0000-0000-0000-000000000001', '検索テスト店');

insert into public.creator_profiles (user_id, full_name, birth_date) values
  ('dddddddd-0000-0000-0000-000000000002', '未達花子', '1999-01-10'),
  ('dddddddd-0000-0000-0000-000000000003', '充足次郎', '1997-03-20');

insert into private.creator_metrics (user_id, platform, window_days, followers) values
  ('dddddddd-0000-0000-0000-000000000002', 'instagram', 30, 300),
  ('dddddddd-0000-0000-0000-000000000003', 'instagram', 30, 2000);

-- 実マスタから阪急千里線と南千里駅を取る（0013 で投入済み）。
insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content, criteria,
  prefecture_id, nearest_station_id
) values (
  'dddddddd-1111-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-000000000001', 'recruiting', '検索検証案件', '検索テスト店',
  'コース料理1名分', 8000, 3, now() - interval '1 hour', now() + interval '7 days',
  now() + interval '7 days', now() + interval '14 days', '写真3枚',
  '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb,
  27,
  (select s.id from public.stations s
   join public.railway_lines l on l.id = s.line_id
   where l.name = '阪急千里線' and s.name = '南千里' limit 1)
);

-- ---------------------------------------------------------------------------
-- 沿線で絞っても、条件未達の投稿者に報酬内容は届かない
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);

select is(
  (select l.reward_description
   from public.list_campaigns_for_creator(
     p_line_ids => array[(select id from public.railway_lines where name = '阪急千里線')]
   ) l
   where l.id = 'dddddddd-1111-0000-0000-000000000001'),
  null::text,
  '沿線で絞り込んでも条件未達の投稿者に報酬内容を送らない'
);

select is(
  (select l.reward_description
   from public.list_campaigns_for_creator(p_prefecture_ids => array[27]) l
   where l.id = 'dddddddd-1111-0000-0000-000000000001'),
  null::text,
  '都道府県で絞り込んでも条件未達の投稿者に報酬内容を送らない'
);

select is(
  (select l.reward_description
   from public.list_campaigns_for_creator(p_sort => 'reward_desc') l
   where l.id = 'dddddddd-1111-0000-0000-000000000001'),
  null::text,
  '報酬順に並べ替えても条件未達の投稿者に報酬内容を送らない'
);

-- ---------------------------------------------------------------------------
-- 絞り込み自体は効く
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int
   from public.list_campaigns_for_creator(
     p_line_ids => array[(select id from public.railway_lines where name = '阪急千里線')]
   ) l
   where l.id = 'dddddddd-1111-0000-0000-000000000001'),
  1,
  '最寄り駅が属する路線で絞り込むとヒットする'
);

select is(
  (select count(*)::int
   from public.list_campaigns_for_creator(p_prefecture_ids => array[13]) l
   where l.id = 'dddddddd-1111-0000-0000-000000000001'),
  0,
  '別の都道府県で絞り込むとヒットしない'
);

-- ---------------------------------------------------------------------------
-- 条件を満たす投稿者には実値が返る
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
                  '{"sub":"dddddddd-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (select l.reward_description
   from public.list_campaigns_for_creator(p_prefecture_ids => array[27]) l
   where l.id = 'dddddddd-1111-0000-0000-000000000001'),
  'コース料理1名分'::text,
  '条件充足の投稿者には報酬内容の実値が返る'
);

-- ---------------------------------------------------------------------------
-- creator 以外は一覧を引けない（R-8）
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
                  '{"sub":"dddddddd-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ select * from public.list_campaigns_for_creator() $$,
  'unauthorized',
  'PR依頼者は投稿者向けの案件一覧を引けない'
);

select * from finish();
rollback;
