-- 10_campaign_creation.test.sql
-- 案件作成（0015）の検証。
-- - PR依頼者は自分の案件のみ作成できる（R-8: 権限判定はサーバー側）
-- - 広告表記タグ（#PR）が自動付与され、所有者でも削除・変更できない（OI-04）
-- - platforms / 訪問期間の check 制約
-- - 新カラムが get_campaign_detail の detail（条件合致時のみ）に載ること

begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

-- =============================================================================
-- フィクスチャ
-- =============================================================================
insert into auth.users (id, email) values
  ('aaaa0000-0000-0000-0000-000000000001', 'client-a@example.test'),
  ('aaaa0000-0000-0000-0000-000000000002', 'client-b@example.test'),
  ('aaaa0000-0000-0000-0000-000000000003', 'creator-a@example.test');

insert into public.profiles (id, role, status) values
  ('aaaa0000-0000-0000-0000-000000000001', 'client',  'active'),
  ('aaaa0000-0000-0000-0000-000000000002', 'client',  'active'),
  ('aaaa0000-0000-0000-0000-000000000003', 'creator', 'active');

insert into public.client_profiles (user_id, store_name) values
  ('aaaa0000-0000-0000-0000-000000000001', '検証カフェA'),
  ('aaaa0000-0000-0000-0000-000000000002', '検証カフェB');

insert into public.creator_profiles (user_id, full_name, birth_date)
values ('aaaa0000-0000-0000-0000-000000000003', '検証投稿者', '1995-04-01');

-- =============================================================================
-- PR依頼者A として案件を作成する
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"aaaa0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ insert into public.campaigns (
       id, client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, platforms, apply_start_at, apply_end_at,
       visit_start_at, visit_end_at, post_start_at, post_end_at, required_content
     ) values (
       'bbbb0000-0000-0000-0000-000000000001',
       'aaaa0000-0000-0000-0000-000000000001',
       'recruiting', '来店案件', '検証カフェA', 'コース料理1名分（5,000円相当）',
       5000, 3, '{instagram,tiktok}', now() - interval '1 hour', now() + interval '7 days',
       now() + interval '8 days', now() + interval '14 days',
       now() + interval '8 days', now() + interval '21 days', '写真3枚以上' ) $$,
  'PR依頼者は投稿対象と訪問期間を指定して自分の案件を作成できる'
);

select is(
  (select c.platforms from public.campaigns c
   where c.id = 'bbbb0000-0000-0000-0000-000000000001'),
  array['instagram', 'tiktok']::text[],
  '投稿対象プラットフォームが保存される'
);

select is(
  (select count(*)::int from public.campaign_hashtags h
   where h.campaign_id = 'bbbb0000-0000-0000-0000-000000000001'
     and h.tag = '#PR' and h.is_mandatory),
  1,
  '広告表記タグ #PR が削除不可タグとして自動付与される（OI-04）'
);

-- =============================================================================
-- ハッシュタグ: 任意タグは操作でき、広告表記タグは操作できない
-- =============================================================================
select lives_ok(
  $$ insert into public.campaign_hashtags (campaign_id, tag)
     values ('bbbb0000-0000-0000-0000-000000000001', 'カフェ巡り') $$,
  '所有者は任意タグを追加できる'
);

delete from public.campaign_hashtags
 where campaign_id = 'bbbb0000-0000-0000-0000-000000000001' and tag = 'カフェ巡り';

select is(
  (select count(*)::int from public.campaign_hashtags h
   where h.campaign_id = 'bbbb0000-0000-0000-0000-000000000001' and h.tag = 'カフェ巡り'),
  0,
  '所有者は任意タグを削除できる'
);

-- RLS の delete/update ポリシーは is_mandatory 行を対象外にするため、
-- 以下はエラーにならず 0 行のまま素通りする。行が残ることを確認する。
delete from public.campaign_hashtags
 where campaign_id = 'bbbb0000-0000-0000-0000-000000000001' and tag = '#PR';

select is(
  (select count(*)::int from public.campaign_hashtags h
   where h.campaign_id = 'bbbb0000-0000-0000-0000-000000000001'
     and h.tag = '#PR' and h.is_mandatory),
  1,
  '広告表記タグは所有者でも削除できない'
);

update public.campaign_hashtags
   set is_mandatory = false
 where campaign_id = 'bbbb0000-0000-0000-0000-000000000001' and tag = '#PR';

select is(
  (select h.is_mandatory from public.campaign_hashtags h
   where h.campaign_id = 'bbbb0000-0000-0000-0000-000000000001' and h.tag = '#PR'),
  true,
  '広告表記タグの削除不可フラグは所有者でも外せない'
);

select throws_ok(
  $$ insert into public.campaign_hashtags (campaign_id, tag, is_mandatory)
     values ('bbbb0000-0000-0000-0000-000000000001', '#ステマではない', true) $$,
  '42501', null,
  '所有者は削除不可タグを自分で追加できない（付与はサーバー側のみ）'
);

-- =============================================================================
-- 他人の案件・他ロールでは作成できない
-- =============================================================================
select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, apply_start_at, apply_end_at,
       post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000002',
       'draft', 'なりすまし案件', '検証カフェB', '無料',
       0, 1, now(), now() + interval '1 day',
       now() + interval '1 day', now() + interval '2 days', 'x' ) $$,
  '42501', null,
  '他の PR依頼者名義では案件を作成できない'
);

select set_config('request.jwt.claims',
                  '{"sub":"aaaa0000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, apply_start_at, apply_end_at,
       post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000003',
       'draft', '投稿者作成案件', 'x', '無料',
       0, 1, now(), now() + interval '1 day',
       now() + interval '1 day', now() + interval '2 days', 'x' ) $$,
  '42501', null,
  '投稿者は案件を作成できない'
);

-- =============================================================================
-- 投稿者から見た詳細: 新カラムは条件合致時の detail にのみ載る
--   （非合致時に detail ごと送らない挙動は 07_list_masking で検証済み）
-- =============================================================================
select is(
  public.get_campaign_detail('bbbb0000-0000-0000-0000-000000000001')
    -> 'detail' -> 'platforms',
  '["instagram","tiktok"]'::jsonb,
  '条件合致時は投稿対象プラットフォームが detail に含まれる'
);

select ok(
  (public.get_campaign_detail('bbbb0000-0000-0000-0000-000000000001')
     -> 'detail' ->> 'visit_start_at') is not null,
  '条件合致時は訪問期間が detail に含まれる'
);

-- =============================================================================
-- check 制約（ロールに依存しないため postgres に戻して検証）
-- =============================================================================
reset role;

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, platforms, apply_start_at, apply_end_at,
       post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000001', 'draft', 'x', 'x', 'x',
       0, 1, '{facebook}', now(), now() + interval '1 day',
       now() + interval '1 day', now() + interval '2 days', 'x' ) $$,
  '23514', null,
  '想定外のプラットフォームは登録できない'
);

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, platforms, apply_start_at, apply_end_at,
       post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000001', 'draft', 'x', 'x', 'x',
       0, 1, '{}', now(), now() + interval '1 day',
       now() + interval '1 day', now() + interval '2 days', 'x' ) $$,
  '23514', null,
  '投稿対象プラットフォームは 1 つ以上必要'
);

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, apply_start_at, apply_end_at,
       visit_start_at, visit_end_at, post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000001', 'draft', 'x', 'x', 'x',
       0, 1, now(), now() + interval '1 day',
       now() + interval '3 days', now() + interval '2 days',
       now() + interval '1 day', now() + interval '4 days', 'x' ) $$,
  '23514', null,
  '訪問終了は訪問開始より後でなければならない'
);

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, apply_start_at, apply_end_at,
       visit_start_at, visit_end_at, post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000001', 'draft', 'x', 'x', 'x',
       0, 1, now(), now() + interval '2 days',
       now() + interval '1 day', now() + interval '3 days',
       now() + interval '2 days', now() + interval '4 days', 'x' ) $$,
  '23514', null,
  '訪問開始は応募締切より前にできない'
);

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, apply_start_at, apply_end_at,
       visit_start_at, post_start_at, post_end_at, required_content
     ) values (
       'aaaa0000-0000-0000-0000-000000000001', 'draft', 'x', 'x', 'x',
       0, 1, now(), now() + interval '1 day',
       now() + interval '1 day',
       now() + interval '1 day', now() + interval '4 days', 'x' ) $$,
  '23514', null,
  '訪問期間は開始・終了をそろえて設定しなければならない'
);

select * from finish();
rollback;
