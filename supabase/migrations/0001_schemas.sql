-- 0001_schemas.sql
-- スキーマ分離とロール権限の基礎。ADR-0003 の第1層（スキーマ分離）を実装する。

-- 後続マイグレーション（0002）で作られる profiles を参照する language sql 関数を
-- ここで定義するため、作成時の本文検証を無効にする（実行時には存在するので問題ない）。
set check_function_bodies = off;

-- =============================================================================
-- private スキーマ
--   インサイト実数値・SNSアクセストークン・監査ログを置く。
--   anon / authenticated には USAGE を与えない = クライアントから到達不能。
-- =============================================================================
create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- 将来 private に作られるオブジェクトにも、クライアントロールの権限を付けない
alter default privileges in schema private
  revoke all on tables from anon, authenticated;
alter default privileges in schema private
  revoke all on functions from anon, authenticated;
alter default privileges in schema private
  revoke all on sequences from anon, authenticated;

grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;
alter default privileges in schema private grant all on tables to service_role;
alter default privileges in schema private grant all on sequences to service_role;

comment on schema private is
  'インサイト実数値とSNSトークンを保持する非公開スキーマ。anon/authenticatedにGRANTしないこと（ADR-0003）。';

-- =============================================================================
-- 共通の更新日時トリガ
-- =============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =============================================================================
-- 権限判定ヘルパー
--   RLS ポリシー内から profiles を参照すると再帰するため、
--   SECURITY DEFINER で RLS をバイパスして読む。
-- =============================================================================
create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin' and p.status = 'active'
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.admin_level = 'super_admin'
      and p.status = 'active'
  );
$$;

-- =============================================================================
-- k-匿名性のしきい値（k = 5）
--   マジックナンバーを散在させないため関数で一元管理する。
-- =============================================================================
create or replace function private.k_threshold()
returns integer
language sql
immutable
as $$ select 5 $$;

comment on function private.k_threshold() is
  'k-匿名性のしきい値。この人数未満のときは実数を返さない（ADR-0003 第3層）。';
