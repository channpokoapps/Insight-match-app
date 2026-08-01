-- 03_k_anonymity.test.sql
-- 第3層（k-匿名性）が機能していることを検証する。k = 5。

begin;
create extension if not exists pgtap with schema extensions;

select plan(8);

select is(private.k_threshold(), 5, 'k のしきい値は 5');

-- ---------------------------------------------------------------------------
-- フィクスチャ：条件に一致する投稿者を 4 人だけ作る
-- ---------------------------------------------------------------------------
insert into auth.users (id, email)
select ('aaaaaaaa-0000-0000-0000-00000000000' || i)::uuid, 'k' || i || '@example.test'
from generate_series(1, 6) i;

insert into auth.users (id, email)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'kclient@example.test');

insert into public.profiles (id, role, status)
select ('aaaaaaaa-0000-0000-0000-00000000000' || i)::uuid, 'creator', 'active'
from generate_series(1, 6) i;

insert into public.profiles (id, role, status)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'client', 'active');

insert into public.creator_profiles (user_id, full_name, birth_date)
select ('aaaaaaaa-0000-0000-0000-00000000000' || i)::uuid, 'テスト' || i, '1995-01-01'
from generate_series(1, 6) i;

insert into public.client_profiles (user_id, store_name)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'テスト店');

insert into public.social_links (user_id, platform, status)
select ('aaaaaaaa-0000-0000-0000-00000000000' || i)::uuid, 'instagram', 'active'
from generate_series(1, 6) i;

-- 1〜4 はフォロワー 10000（条件一致）、5〜6 は 100（不一致）
insert into private.creator_metrics (user_id, platform, window_days, followers)
select ('aaaaaaaa-0000-0000-0000-00000000000' || i)::uuid, 'instagram', 30,
       case when i <= 4 then 10000 else 100 end
from generate_series(1, 6) i;

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"bbbbbbbb-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is(
  (public.count_matching_creators(
     '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb
   )->>'masked')::boolean,
  true,
  '該当4人のときは masked = true'
);

select is(
  public.count_matching_creators(
    '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb
  )->'count',
  'null'::jsonb,
  '該当4人のときは実数を返さない'
);

select is(
  public.count_matching_creators(
    '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb
  )->>'label',
  '5人未満',
  '該当4人のときは「5人未満」と表示する'
);

-- 5 人目を条件一致に変更
reset role;
update private.creator_metrics set followers = 10000
where user_id = 'aaaaaaaa-0000-0000-0000-000000000005';

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"bbbbbbbb-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is(
  (public.count_matching_creators(
     '{"metric":"followers","platform":"instagram","window":30,"cmp":">=","value":1000}'::jsonb
   )->>'count')::int,
  5,
  '該当5人になれば実数を返す'
);

reset role;

-- ---------------------------------------------------------------------------
-- ヒストグラムの小ビン併合
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int
   from jsonb_array_elements(private.build_histogram(array[1,2,3,1100,1200]::numeric[], 1000)) b
   where (b->>'count')::int < 5),
  0,
  'ヒストグラムに件数5未満のビンが残らない'
);

select is(
  (select sum((b->>'count')::int)::int
   from jsonb_array_elements(private.build_histogram(array[1,2,3,1100,1200]::numeric[], 1000)) b),
  5,
  'ビン併合後も合計件数が保存される'
);

-- ---------------------------------------------------------------------------
-- 成果レポートの n < k
-- ---------------------------------------------------------------------------
insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, apply_start_at, apply_end_at,
  post_start_at, post_end_at, required_content
) values (
  'cccccccc-0000-0000-0000-000000000001',
  'bbbbbbbb-0000-0000-0000-000000000001',
  'completed', 'レポートテスト', 'テスト店', 'ランチ無料',
  1200, 10, now() - interval '30 days', now() - interval '20 days',
  now() - interval '20 days', now() - interval '5 days', '写真3枚以上'
);

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"bbbbbbbb-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is(
  (public.get_campaign_report('cccccccc-0000-0000-0000-000000000001')->>'available')::boolean,
  false,
  '投稿数が5件未満ならレポートを返さない'
);

select * from finish();
rollback;
