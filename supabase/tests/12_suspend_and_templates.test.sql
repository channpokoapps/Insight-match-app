-- 12_suspend_and_templates.test.sql
-- 募集の一時停止・再開（FR-CMP-13 / T-115）と条件テンプレート（FR-CMP-16）。

begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

-- =============================================================================
-- フィクスチャ
-- =============================================================================
insert into auth.users (id, email) values
  ('1111aaaa-0000-0000-0000-000000000001', 'susp-client@example.test'),
  ('1111aaaa-0000-0000-0000-000000000002', 'susp-other@example.test'),
  ('1111aaaa-0000-0000-0000-000000000003', 'susp-creator@example.test');

insert into public.profiles (id, role, status) values
  ('1111aaaa-0000-0000-0000-000000000001', 'client',  'active'),
  ('1111aaaa-0000-0000-0000-000000000002', 'client',  'active'),
  ('1111aaaa-0000-0000-0000-000000000003', 'creator', 'active');

insert into public.client_profiles (user_id, store_name) values
  ('1111aaaa-0000-0000-0000-000000000001', '停止検証店'),
  ('1111aaaa-0000-0000-0000-000000000002', '別の停止検証店');

insert into public.creator_profiles (user_id, full_name, birth_date)
values ('1111aaaa-0000-0000-0000-000000000003', '停止検証投稿者', '1995-04-01');

insert into public.social_links (user_id, platform, status)
values ('1111aaaa-0000-0000-0000-000000000003', 'instagram', 'active');

insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content
) values (
  '2222aaaa-0000-0000-0000-000000000001',
  '1111aaaa-0000-0000-0000-000000000001',
  'recruiting', '一時停止検証案件', '停止検証店', 'ランチ1名分',
  1500, 3, now() - interval '1 hour', now() + interval '7 days',
  now() + interval '8 days', now() + interval '21 days', '写真3枚以上'
);

insert into public.applications (id, campaign_id, creator_id, alias_no, status)
values ('3333aaaa-0000-0000-0000-000000000001',
        '2222aaaa-0000-0000-0000-000000000001',
        '1111aaaa-0000-0000-0000-000000000003', 1, 'applied');

-- =============================================================================
-- 一時停止
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$ select public.suspend_campaign('2222aaaa-0000-0000-0000-000000000001', 'x') $$,
  null, null,
  '他の PR依頼者の案件は一時停止できない'
);

select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000003","role":"authenticated"}', true);

select throws_ok(
  $$ select public.suspend_campaign('2222aaaa-0000-0000-0000-000000000001', 'x') $$,
  null, null,
  '投稿者は案件を一時停止できない'
);

select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ select public.suspend_campaign('2222aaaa-0000-0000-0000-000000000001', '仕込みが間に合わないため') $$,
  '所有者は募集中の案件を一時停止できる'
);

reset role;

select is(
  (select c.status from public.campaigns c
   where c.id = '2222aaaa-0000-0000-0000-000000000001'),
  'suspended',
  '一時停止すると案件が停止中になる'
);

select is(
  (select c.suspended_by from public.campaigns c
   where c.id = '2222aaaa-0000-0000-0000-000000000001'),
  'client',
  '停止した主体が記録される'
);

-- 取り下げと違い、応募は残す
select is(
  (select a.status from public.applications a
   where a.id = '3333aaaa-0000-0000-0000-000000000001'),
  'applied',
  '一時停止では応募を中止しない'
);

select is(
  (select count(*)::int from public.notifications n
   where n.user_id = '1111aaaa-0000-0000-0000-000000000003'
     and n.type = 'campaign_suspended'),
  1,
  '応募者に一時停止が通知される'
);

select is(
  (select count(*)::int from public.notifications n
   where n.type = 'campaign_suspended'
     and (n.payload ? 'creator_id' or n.payload ? 'alias_no'
          or n.payload ? 'full_name')),
  0,
  '一時停止通知に投稿者を特定できる値が含まれない'
);

-- =============================================================================
-- 停止中は投稿者から見えず、応募もできない
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.list_campaigns_for_creator()
   where id = '2222aaaa-0000-0000-0000-000000000001'),
  0,
  '一時停止中の案件は投稿者の一覧に出ない'
);

select throws_ok(
  $$ select public.get_campaign_detail('2222aaaa-0000-0000-0000-000000000001') $$,
  null, null,
  '一時停止中の案件は詳細を取得できない'
);

select throws_ok(
  $$ select public.apply_to_campaign('2222aaaa-0000-0000-0000-000000000001') $$,
  null, null,
  '一時停止中の案件には応募できない'
);

-- =============================================================================
-- 再開
-- =============================================================================
select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ select public.resume_campaign('2222aaaa-0000-0000-0000-000000000001') $$,
  '所有者は一時停止した案件を再開できる'
);

reset role;

select is(
  (select c.status || coalesce('/' || c.suspended_by, '') from public.campaigns c
   where c.id = '2222aaaa-0000-0000-0000-000000000001'),
  'recruiting',
  '再開すると募集中に戻り、停止の記録が消える'
);

-- 運営が止めた案件は PR依頼者が再開できない（FR-ADM-04）
update public.campaigns
   set status = 'suspended', suspended_by = 'admin', suspended_reason = '規約違反の確認中'
 where id = '2222aaaa-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ select public.resume_campaign('2222aaaa-0000-0000-0000-000000000001') $$,
  null, null,
  '運営が停止した案件は PR依頼者が再開できない'
);

reset role;
update public.campaigns
   set status = 'recruiting', suspended_by = null, suspended_reason = null
 where id = '2222aaaa-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ select public.resume_campaign('2222aaaa-0000-0000-0000-000000000001') $$,
  null, null,
  '募集中の案件は再開できない'
);

-- =============================================================================
-- 一時停止からの取り下げ
-- =============================================================================
select lives_ok(
  $$ select public.suspend_campaign('2222aaaa-0000-0000-0000-000000000001', null) $$,
  '再開した案件をもう一度一時停止できる'
);

select lives_ok(
  $$ select public.cancel_campaign('2222aaaa-0000-0000-0000-000000000001', 'やむを得ず中止') $$,
  '一時停止中の案件はそのまま取り下げできる'
);

reset role;

select is(
  (select c.status || coalesce('/' || c.suspended_by, '') from public.campaigns c
   where c.id = '2222aaaa-0000-0000-0000-000000000001'),
  'cancelled',
  '取り下げると停止の記録が消えて中止になる'
);

update public.campaigns
   set status = 'suspended', suspended_by = 'admin', suspended_reason = '規約違反の確認中'
 where id = '2222aaaa-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ select public.cancel_campaign('2222aaaa-0000-0000-0000-000000000001', 'x') $$,
  null, null,
  '運営が停止した案件は PR依頼者が取り下げできない'
);

-- =============================================================================
-- 条件テンプレート（FR-CMP-16）
-- =============================================================================
select lives_ok(
  $$ insert into public.criteria_templates (client_id, name, criteria)
     values ('1111aaaa-0000-0000-0000-000000000001', 'フォロワー1000以上',
             '{"op":"AND","children":[{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}]}'::jsonb) $$,
  'PR依頼者は自分の条件テンプレートを保存できる'
);

select is(
  (select count(*)::int from public.criteria_templates),
  1,
  '保存したテンプレートを自分で参照できる'
);

select throws_ok(
  $$ insert into public.criteria_templates (client_id, name, criteria)
     values ('1111aaaa-0000-0000-0000-000000000002', '他人名義',
             '{"op":"AND","children":[]}'::jsonb) $$,
  '42501', null,
  '他の PR依頼者名義でテンプレートを保存できない'
);

-- 条件式のホワイトリストは campaigns と同じものを通る
select throws_ok(
  $$ insert into public.criteria_templates (client_id, name, criteria)
     values ('1111aaaa-0000-0000-0000-000000000001', '不正な指標',
             '{"metric":"dm_history","platform":"instagram","window":30,"cmp":">=","value":1}'::jsonb) $$,
  null, null,
  '未対応の指標を含むテンプレートは保存できない'
);

select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000002","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.criteria_templates),
  0,
  '他の PR依頼者のテンプレートは参照できない'
);

select set_config('request.jwt.claims',
                  '{"sub":"1111aaaa-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.criteria_templates),
  0,
  '投稿者はテンプレートを参照できない'
);

select throws_ok(
  $$ insert into public.criteria_templates (client_id, name, criteria)
     values ('1111aaaa-0000-0000-0000-000000000003', '投稿者のテンプレート',
             '{"op":"AND","children":[]}'::jsonb) $$,
  null, null,
  '投稿者はテンプレートを保存できない'
);

reset role;

-- 新規テーブルでも RLS が有効になっていること（AGENTS.md §2）
select ok(
  (select c.relrowsecurity from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'criteria_templates'),
  'criteria_templates で RLS が有効になっている'
);

select * from finish();
rollback;
