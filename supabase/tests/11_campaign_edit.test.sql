-- 11_campaign_edit.test.sql
-- 案件の編集ガード・取り下げ（FR-CMP-13）と、画像 Storage のポリシー（FR-CMP-11）。
--
-- Storage は行の挿入まで踏み込まず、ポリシーの存在と適用範囲を検証する。
-- storage.objects への直接 INSERT は storage 拡張のバージョンごとに
-- 付随トリガーの前提が変わるため、DB テストの安定性を優先する。

begin;
create extension if not exists pgtap with schema extensions;

select plan(23);

-- =============================================================================
-- フィクスチャ
-- =============================================================================
insert into auth.users (id, email) values
  ('cccc0000-0000-0000-0000-000000000001', 'edit-client@example.test'),
  ('cccc0000-0000-0000-0000-000000000002', 'edit-other@example.test'),
  ('cccc0000-0000-0000-0000-000000000003', 'edit-creator@example.test');

insert into public.profiles (id, role, status) values
  ('cccc0000-0000-0000-0000-000000000001', 'client',  'active'),
  ('cccc0000-0000-0000-0000-000000000002', 'client',  'active'),
  ('cccc0000-0000-0000-0000-000000000003', 'creator', 'active');

insert into public.client_profiles (user_id, store_name) values
  ('cccc0000-0000-0000-0000-000000000001', '編集検証店'),
  ('cccc0000-0000-0000-0000-000000000002', '別の店');

insert into public.creator_profiles (user_id, full_name, birth_date)
values ('cccc0000-0000-0000-0000-000000000003', '編集検証投稿者', '1995-04-01');

insert into public.campaigns (
  id, client_id, status, title, store_name_snapshot, reward_description,
  reward_value_jpy, quota, platforms, apply_start_at, apply_end_at,
  visit_start_at, visit_end_at, post_start_at, post_end_at, required_content
) values (
  'dddd0000-0000-0000-0000-000000000001',
  'cccc0000-0000-0000-0000-000000000001',
  'recruiting', '編集検証案件', '編集検証店', 'ランチ1名分',
  1500, 3, '{instagram}', now() - interval '1 hour', now() + interval '7 days',
  now() + interval '8 days', now() + interval '14 days',
  now() + interval '8 days', now() + interval '21 days', '写真3枚以上'
);

-- =============================================================================
-- 応募者がいないうちは自由に編集できる
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ update public.campaigns
        set quota = 5,
            post_end_at = now() + interval '30 days'
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '応募者がいなければ募集人数・期間を編集できる'
);

select is(
  (select c.quota from public.campaigns c
   where c.id = 'dddd0000-0000-0000-0000-000000000001'),
  5,
  '編集内容が保存される'
);

-- =============================================================================
-- 応募が入ったあとは公平性に関わる項目を編集できない
-- =============================================================================
reset role;
insert into public.applications (id, campaign_id, creator_id, alias_no, status)
values ('eeee0000-0000-0000-0000-000000000001',
        'dddd0000-0000-0000-0000-000000000001',
        'cccc0000-0000-0000-0000-000000000003', 1, 'applied');

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ update public.campaigns set quota = 10
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '23514', null,
  '応募者がいると募集人数を変更できない'
);

select throws_ok(
  $$ update public.campaigns set post_end_at = now() + interval '60 days'
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '23514', null,
  '応募者がいると期間を変更できない'
);

select throws_ok(
  $$ update public.campaigns
        set criteria = '{"op":"AND","children":[{"attr":"age","cmp":">=","value":20}]}'::jsonb
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '23514', null,
  '応募者がいると募集条件を変更できない'
);

select throws_ok(
  $$ update public.campaigns set platforms = '{instagram,youtube}'
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '23514', null,
  '応募者がいると投稿対象プラットフォームを変更できない'
);

select lives_ok(
  $$ update public.campaigns
        set title = '編集検証案件（改訂）',
            reward_description = 'ランチ1名分＋デザート',
            required_content = '写真5枚以上'
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '応募者がいても案内文（タイトル・提供内容・必須投稿内容）は編集できる'
);

select is(
  (select c.title from public.campaigns c
   where c.id = 'dddd0000-0000-0000-0000-000000000001'),
  '編集検証案件（改訂）',
  '案内文の編集は保存される'
);

-- 取り下げ済みの応募はロック対象に数えない
reset role;
update public.applications set status = 'withdrawn'
 where id = 'eeee0000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ update public.campaigns set quota = 8
      where id = 'dddd0000-0000-0000-0000-000000000001' $$,
  '辞退済みの応募しかない場合は編集できる'
);

reset role;
update public.applications set status = 'applied'
 where id = 'eeee0000-0000-0000-0000-000000000001';

-- =============================================================================
-- 取り下げ（cancel_campaign）
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$ select public.cancel_campaign('dddd0000-0000-0000-0000-000000000001', 'テスト') $$,
  null, null,
  '他の PR依頼者の案件は取り下げできない'
);

select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select throws_ok(
  $$ select public.cancel_campaign('dddd0000-0000-0000-0000-000000000001', 'テスト') $$,
  null, null,
  '投稿者は案件を取り下げできない'
);

select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ select public.cancel_campaign('dddd0000-0000-0000-0000-000000000001', '店舗都合のため') $$,
  '所有者は案件を取り下げできる'
);

reset role;

select is(
  (select c.status from public.campaigns c
   where c.id = 'dddd0000-0000-0000-0000-000000000001'),
  'cancelled',
  '取り下げると案件が中止になる'
);

select is(
  (select a.status from public.applications a
   where a.id = 'eeee0000-0000-0000-0000-000000000001'),
  'cancelled',
  '取り下げると進行中の応募も中止になる'
);

select is(
  (select count(*)::int from public.notifications n
   where n.user_id = 'cccc0000-0000-0000-0000-000000000003'
     and n.type = 'campaign_cancelled'),
  1,
  '応募者に取り下げの通知が届く'
);

-- 通知の payload に投稿者を特定できる値を入れない（AGENTS.md R-5）
select is(
  (select count(*)::int from public.notifications n
   where n.type = 'campaign_cancelled'
     and (n.payload ? 'creator_id' or n.payload ? 'alias_no'
          or n.payload ? 'full_name' or n.payload ? 'applications')),
  0,
  '取り下げ通知に投稿者を特定できる値が含まれない'
);

set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"cccc0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ select public.cancel_campaign('dddd0000-0000-0000-0000-000000000001', '再取り下げ') $$,
  null, null,
  '中止済みの案件は再度取り下げできない'
);

reset role;

-- =============================================================================
-- 画像 Storage のポリシー（FR-CMP-11）
-- =============================================================================
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname like 'campaign_images_object_%'),
  4,
  '案件画像バケットに参照・追加・更新・削除のポリシーが定義されている'
);

select is(
  (select count(*)::int from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname like 'campaign_images_object_%'
     and 'authenticated' <> all (roles)),
  0,
  '案件画像のポリシーはすべて authenticated 限定（anon に開かれていない）'
);

-- 書き込み系は所有者判定を必ず含む
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname in ('campaign_images_object_insert',
                        'campaign_images_object_update',
                        'campaign_images_object_delete')
     and coalesce(qual, '') || coalesce(with_check, '') like '%is_campaign_media_owner%'),
  3,
  '画像の追加・更新・削除は案件の所有者に限定されている'
);

-- 参照は「所有者、または公開済みの案件」に限る（下書きの画像を晒さない）
select ok(
  (select qual from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname = 'campaign_images_object_select') like '%can_view_campaign_media%',
  '画像の参照可否はサーバー側のヘルパーで判定している'
);

-- 判定ヘルパーは投稿者にも campaigns を読ませずに boolean だけを返す（R-3 / R-5）。
-- ポリシー内から campaigns を直接参照すると、campaigns の SELECT ポリシーを
-- 持たない投稿者では常に偽になり、公開案件の画像まで見えなくなる。
select is(
  (select count(*)::int from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('is_campaign_media_owner', 'can_view_campaign_media')
     and p.prosecdef),
  2,
  '画像判定ヘルパーは SECURITY DEFINER で定義されている'
);

select is(
  (select count(*)::int from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('is_campaign_media_owner', 'can_view_campaign_media')
     and p.prorettype = 'boolean'::regtype),
  2,
  '画像判定ヘルパーが返すのは boolean のみ'
);

select * from finish();
rollback;
