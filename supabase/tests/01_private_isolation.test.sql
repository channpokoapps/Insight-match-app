-- 01_private_isolation.test.sql
-- 第1層（スキーマ分離）が壊れていないことを検証する。
-- このテストが落ちた状態でマージしてはならない（AGENTS.md）。

begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

select has_schema('private', 'private スキーマが存在する');

-- スキーマ USAGE
select ok(not has_schema_privilege('anon', 'private', 'USAGE'),
          'anon は private スキーマを USAGE できない');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'),
          'authenticated は private スキーマを USAGE できない');

-- 主要テーブルの SELECT
select ok(not has_table_privilege('authenticated', 'private.creator_metrics', 'SELECT'),
          'authenticated は creator_metrics を SELECT できない');
select ok(not has_table_privilege('authenticated', 'private.media_snapshots', 'SELECT'),
          'authenticated は media_snapshots を SELECT できない');
select ok(not has_table_privilege('authenticated', 'private.social_credentials', 'SELECT'),
          'authenticated は social_credentials を SELECT できない');
select ok(not has_table_privilege('authenticated', 'private.audience_demographics', 'SELECT'),
          'authenticated は audience_demographics を SELECT できない');
select ok(not has_table_privilege('anon', 'private.creator_metrics', 'SELECT'),
          'anon は creator_metrics を SELECT できない');

-- private のテーブルがひとつも公開ロールに漏れていないことを網羅的に確認
-- （has_table_privilege は WHERE の評価順序によっては private 以外の行にも
--   適用されうるため、スキーマ名もタプルから組み立てて存在しない名前を引かない）
select is(
  (select count(*)::int
   from pg_tables t
   where t.schemaname = 'private'
     and (has_table_privilege('authenticated', format('%I.%I', t.schemaname, t.tablename), 'SELECT')
       or has_table_privilege('anon',          format('%I.%I', t.schemaname, t.tablename), 'SELECT'))),
  0,
  'private の全テーブルが anon / authenticated から不可視である'
);

-- public 側にインサイト実数値カラムが混入していないか
select hasnt_column('public', 'social_links', 'followers',
                    'social_links にフォロワー数を持たせていない');
select is(
  (select count(*)::int
   from information_schema.columns
   where table_schema = 'public'
     and column_name in ('followers', 'avg_reach', 'avg_impressions',
                         'engagement_rate', 'access_token', 'access_token_encrypted')),
  0,
  'public スキーマにインサイト実数値・トークン列が存在しない'
);

-- PostgREST の公開スキーマ設定
select is(
  (select count(*)::int
   from unnest(string_to_array(
          coalesce(current_setting('pgrst.db_schemas', true), 'public'), ',')) s
   where trim(s) = 'private'),
  0,
  'PostgREST の公開スキーマに private が含まれていない'
);

-- private のヘルパー関数を直接呼べない
select ok(not has_function_privilege('authenticated', 'private.eval_criteria(uuid, jsonb)', 'EXECUTE'),
          'authenticated は eval_criteria を直接実行できない');

select * from finish();
rollback;
