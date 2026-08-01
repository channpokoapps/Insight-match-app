-- 05_alias.test.sql
-- 案件内連番（ADR-0005）が案件ごとに独立していることを検証する。

begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

insert into auth.users (id, email)
select ('ffffffff-0000-0000-0000-00000000000' || i)::uuid, 'a' || i || '@example.test'
from generate_series(1, 3) i;

insert into auth.users (id, email)
values ('99999999-0000-0000-0000-000000000001', 'aclient@example.test');

insert into public.profiles (id, role, status)
select ('ffffffff-0000-0000-0000-00000000000' || i)::uuid, 'creator', 'active'
from generate_series(1, 3) i;

insert into public.profiles (id, role, status)
values ('99999999-0000-0000-0000-000000000001', 'client', 'active');

insert into public.creator_profiles (user_id, full_name, birth_date)
select ('ffffffff-0000-0000-0000-00000000000' || i)::uuid, '連番' || i, '1996-01-01'
from generate_series(1, 3) i;

insert into public.social_links (user_id, platform, status)
select ('ffffffff-0000-0000-0000-00000000000' || i)::uuid, 'instagram', 'active'
from generate_series(1, 3) i;

insert into private.creator_metrics (user_id, platform, window_days, followers)
select ('ffffffff-0000-0000-0000-00000000000' || i)::uuid, 'instagram', 30, 5000
from generate_series(1, 3) i;

insert into public.client_profiles (user_id, store_name)
values ('99999999-0000-0000-0000-000000000001', '連番テスト店');

insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content
)
select ('88888888-0000-0000-0000-00000000000' || i)::uuid,
       '99999999-0000-0000-0000-000000000001', 'recruiting', '案件' || i, '連番テスト店',
       '無料', 500, 5, now() - interval '1 hour', now() + interval '7 days',
       now() + interval '7 days', now() + interval '14 days', '写真3枚'
from generate_series(1, 2) i;

-- 案件1：投稿者3 → 投稿者1 の順に応募
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"ffffffff-0000-0000-0000-000000000003","role":"authenticated"}', true);
select public.apply_to_campaign('88888888-0000-0000-0000-000000000001');

select set_config('request.jwt.claims',
                  '{"sub":"ffffffff-0000-0000-0000-000000000001","role":"authenticated"}', true);
select public.apply_to_campaign('88888888-0000-0000-0000-000000000001');

-- 案件2：投稿者1 が最初に応募
select public.apply_to_campaign('88888888-0000-0000-0000-000000000002');

reset role;

select is(
  (select alias_no from public.applications
   where campaign_id = '88888888-0000-0000-0000-000000000001'
     and creator_id  = 'ffffffff-0000-0000-0000-000000000003'),
  1,
  '案件1で最初に応募した投稿者の連番は 1'
);

select is(
  (select alias_no from public.applications
   where campaign_id = '88888888-0000-0000-0000-000000000001'
     and creator_id  = 'ffffffff-0000-0000-0000-000000000001'),
  2,
  '案件1で2番目に応募した投稿者の連番は 2'
);

select is(
  (select alias_no from public.applications
   where campaign_id = '88888888-0000-0000-0000-000000000002'
     and creator_id  = 'ffffffff-0000-0000-0000-000000000001'),
  1,
  '同一投稿者でも案件が変われば連番は独立する（名寄せ不可）'
);

select throws_ok(
  $$ insert into public.applications (campaign_id, creator_id, alias_no, status)
     values ('88888888-0000-0000-0000-000000000001',
             'ffffffff-0000-0000-0000-000000000002', 1, 'applied') $$,
  null, null,
  '案件内で連番が重複する行は作れない'
);

select * from finish();
rollback;
