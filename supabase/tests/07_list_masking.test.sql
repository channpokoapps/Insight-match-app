-- 07_list_masking.test.sql
-- 案件一覧 RPC (list_campaigns_for_creator) が、応募条件を満たさない投稿者に
-- 報酬内容(reward_description)の実値を送らないことを確認する。
-- 詳細 RPC (get_campaign_detail) と同じ「値そのものを送らない」方式(0010)。

begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

-- ---------------------------------------------------------------------------
-- 準備: 店舗1・投稿者2(条件未達 300 / 条件充足 2000)・募集中案件1
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('ffffffff-0000-0000-0000-000000000001', 'mask-cl@example.test'),
  ('ffffffff-0000-0000-0000-000000000002', 'mask-low@example.test'),
  ('ffffffff-0000-0000-0000-000000000003', 'mask-high@example.test');

insert into public.profiles (id, role, status) values
  ('ffffffff-0000-0000-0000-000000000001', 'client',  'active'),
  ('ffffffff-0000-0000-0000-000000000002', 'creator', 'active'),
  ('ffffffff-0000-0000-0000-000000000003', 'creator', 'active');

insert into public.client_profiles (user_id, store_name)
values ('ffffffff-0000-0000-0000-000000000001', 'マスクテスト店');

insert into public.creator_profiles (user_id, full_name, birth_date) values
  ('ffffffff-0000-0000-0000-000000000002', '未達花子', '1999-01-10'),
  ('ffffffff-0000-0000-0000-000000000003', '充足次郎', '1997-03-20');

insert into private.creator_metrics (user_id, platform, window_days, followers) values
  ('ffffffff-0000-0000-0000-000000000002', 'instagram', 30, 300),
  ('ffffffff-0000-0000-0000-000000000003', 'instagram', 30, 2000);

insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content, criteria
) values (
  'ffffffff-1111-0000-0000-000000000001',
  'ffffffff-0000-0000-0000-000000000001', 'recruiting', 'マスク検証案件', 'マスクテスト店',
  'ディナーコース1名分', 5000, 3, now() - interval '1 hour', now() + interval '7 days',
  now() + interval '7 days', now() + interval '14 days', '写真3枚',
  '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb
);

-- ---------------------------------------------------------------------------
-- 条件を満たさない投稿者: is_eligible = false、reward_description は届かない
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"ffffffff-0000-0000-0000-000000000002","role":"authenticated"}', true);

select is(
  (select l.is_eligible from public.list_campaigns_for_creator() l
   where l.id = 'ffffffff-1111-0000-0000-000000000001'),
  false,
  '条件未達の投稿者には is_eligible = false が返る'
);

select is(
  (select l.reward_description from public.list_campaigns_for_creator() l
   where l.id = 'ffffffff-1111-0000-0000-000000000001'),
  null,
  '条件未達の投稿者には報酬内容の実値を送らない'
);

-- ---------------------------------------------------------------------------
-- 条件を満たす投稿者: 実値が返る
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
                  '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (select l.is_eligible from public.list_campaigns_for_creator() l
   where l.id = 'ffffffff-1111-0000-0000-000000000001'),
  true,
  '条件充足の投稿者には is_eligible = true が返る'
);

select is(
  (select l.reward_description from public.list_campaigns_for_creator() l
   where l.id = 'ffffffff-1111-0000-0000-000000000001'),
  'ディナーコース1名分',
  '条件充足の投稿者には報酬内容の実値が返る'
);

select * from finish();
rollback;
