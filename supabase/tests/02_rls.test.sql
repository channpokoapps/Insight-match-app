-- 02_rls.test.sql
-- public スキーマのデフォルト拒否と、匿名性を破る経路がないことを検証する。

begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

-- 全テーブルで RLS が有効か（マスタ含む）
select is(
  (select count(*)::int
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'public の全テーブルで RLS が有効になっている'
);

-- PR依頼者向けビューに投稿者を特定できる列がない
select hasnt_column('public', 'v_applications_for_client', 'creator_id',
                    'v_applications_for_client に creator_id が存在しない');
select has_column('public', 'v_applications_for_client', 'alias_no',
                  'v_applications_for_client に alias_no が存在する');
select hasnt_column('public', 'v_applications_for_client', 'post_url',
                    'v_applications_for_client に投稿URLが存在しない');

-- creator_profiles に client 向けの SELECT ポリシーがないこと
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename = 'creator_profiles'
     and qual like '%''client''%'),
  0,
  'creator_profiles に client 向けポリシーが存在しない'
);

-- campaigns は creator に直接読ませない（RPC 経由のみ）
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public' and tablename = 'campaigns'
     and qual like '%creator%'),
  0,
  'campaigns に creator 向けの直接 SELECT ポリシーが存在しない'
);

-- 実データでの確認
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'creator1@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'client1@example.test');

insert into public.profiles (id, role, status) values
  ('11111111-1111-1111-1111-111111111111', 'creator', 'active'),
  ('22222222-2222-2222-2222-222222222222', 'client',  'active');

insert into public.creator_profiles (user_id, full_name, birth_date)
values ('11111111-1111-1111-1111-111111111111', '山田テスト', '1995-04-01');

insert into public.client_profiles (user_id, store_name)
values ('22222222-2222-2222-2222-222222222222', 'テストカフェ');

insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content
) values (
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222',
  'recruiting', 'テスト案件', 'テストカフェ', 'ドリンク1杯',
  800, 5, now() - interval '1 day', now() + interval '7 days',
  now() + interval '7 days', now() + interval '14 days', '写真3枚以上'
);

insert into public.applications (campaign_id, creator_id, alias_no, status)
values ('33333333-3333-3333-3333-333333333333',
        '11111111-1111-1111-1111-111111111111', 1, 'applied');

-- PR依頼者として実行
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.applications),
  0,
  'PR依頼者は applications を直接 SELECT できない'
);

select is(
  (select count(*)::int from public.creator_profiles),
  0,
  'PR依頼者は creator_profiles を SELECT できない'
);

select is(
  (select alias_no from public.v_applications_for_client
   where campaign_id = '33333333-3333-3333-3333-333333333333'),
  1,
  'PR依頼者はビュー経由で連番のみを取得できる'
);

select * from finish();
rollback;
