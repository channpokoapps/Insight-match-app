-- 04_criteria.test.sql
-- 条件式 JSON のホワイトリスト検証と、応募時のサーバ側再検証を確認する。

begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

-- ---------------------------------------------------------------------------
-- validate_criteria
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ select private.validate_criteria(
       '{"op":"AND","children":[
          {"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000},
          {"attr":"prefecture_id","cmp":"=","value":13}
        ]}'::jsonb) $$,
  '正当な条件式は通る'
);

select throws_ok(
  $$ select private.validate_criteria(
       '{"metric":"secret_score","platform":"instagram","window":30,"cmp":">=","value":1}'::jsonb) $$,
  null, null,
  '許可されていない指標は拒否される'
);

select throws_ok(
  $$ select private.validate_criteria(
       '{"metric":"followers","platform":"instagram","window":45,"cmp":">=","value":1}'::jsonb) $$,
  null, null,
  '許可されていない集計期間は拒否される'
);

select throws_ok(
  $$ select private.validate_criteria(
       '{"metric":"followers","platform":"instagram","window":30,"cmp":"like","value":1}'::jsonb) $$,
  null, null,
  '許可されていない比較演算子は拒否される'
);

select throws_ok(
  $$ select private.validate_criteria(
       '{"op":"AND","children":[{"op":"OR","children":[{"op":"AND","children":[
          {"op":"OR","children":[
            {"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1}]}]}]}]}'::jsonb) $$,
  null, null,
  'ネストが4段以上なら拒否される'
);

select throws_ok(
  $$ select private.validate_criteria('{"op":"NOT","children":[]}'::jsonb) $$,
  null, null,
  '未対応の演算子は拒否される'
);

-- ---------------------------------------------------------------------------
-- 案件保存時にトリガで強制されるか
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('dddddddd-0000-0000-0000-000000000001', 'ccl@example.test'),
  ('dddddddd-0000-0000-0000-000000000002', 'ccr@example.test');

insert into public.profiles (id, role, status) values
  ('dddddddd-0000-0000-0000-000000000001', 'client',  'active'),
  ('dddddddd-0000-0000-0000-000000000002', 'creator', 'active');

insert into public.client_profiles (user_id, store_name)
values ('dddddddd-0000-0000-0000-000000000001', '条件テスト店');

insert into public.creator_profiles (user_id, full_name, birth_date)
values ('dddddddd-0000-0000-0000-000000000002', '応募太郎', '1998-06-15');

insert into public.social_links (user_id, platform, status)
values ('dddddddd-0000-0000-0000-000000000002', 'instagram', 'active');

insert into private.creator_metrics (user_id, platform, window_days, followers)
values ('dddddddd-0000-0000-0000-000000000002', 'instagram', 30, 300);

select throws_ok(
  $$ insert into public.campaigns (
       client_id, status, title, store_name_snapshot, reward_description,
       reward_value_jpy, quota, apply_start_at, apply_end_at,
       post_start_at, post_end_at, required_content, criteria)
     values ('dddddddd-0000-0000-0000-000000000001', 'draft', 'NG案件', '条件テスト店',
             '無料', 0, 1, now(), now() + interval '1 day',
             now() + interval '1 day', now() + interval '2 days', 'x',
             '{"metric":"dm_history","platform":"instagram","window":30,"cmp":">=","value":1}'::jsonb) $$,
  null, null,
  '不正な criteria を持つ案件は保存できない'
);

insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content, criteria
) values (
  'eeeeeeee-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-000000000001', 'recruiting', '条件付き案件', '条件テスト店',
  'コーヒー1杯', 500, 3, now() - interval '1 hour', now() + interval '7 days',
  now() + interval '7 days', now() + interval '14 days', '写真3枚',
  '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb
);

-- ---------------------------------------------------------------------------
-- 条件を満たさない投稿者は応募できない
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"dddddddd-0000-0000-0000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$ select public.apply_to_campaign('eeeeeeee-0000-0000-0000-000000000001') $$,
  null, null,
  '条件を満たさない投稿者はサーバ側で応募を拒否される'
);

-- 案件詳細では詳細情報が返らない
select is(
  public.get_campaign_detail('eeeeeeee-0000-0000-0000-000000000001')->'detail',
  'null'::jsonb,
  '条件を満たさない場合、詳細情報は返さない'
);

select * from finish();
rollback;
