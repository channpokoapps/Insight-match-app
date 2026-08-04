-- 0017_campaign_suspend_and_templates.sql
-- 募集の一時停止・再開（FR-CMP-13 / T-115）と、条件テンプレート（FR-CMP-16）。
--
-- 1) 一時停止は「募集を止めるが応募は残す」操作。取り下げ（cancel_campaign）と違い
--    応募は中止しない。運営による強制停止（FR-ADM-04）と同じ `suspended` 状態を
--    使うため、**誰が止めたか**を持たせ、運営が止めた案件を PR依頼者が
--    再開できないようにする。
-- 2) 条件テンプレートは PR依頼者ごとの条件式の保存。
--
-- 非開示要件への影響（AGENTS.md R-1〜R-5）:
-- - 一時停止中は `status <> 'recruiting'` になるため、既存の RPC
--   （list_campaigns_for_creator / get_campaign_detail / apply_to_campaign）が
--   そのまま投稿者への露出と応募を止める。開示範囲は広がらない。
-- - 一時停止の通知は応募者本人の notifications にのみ入れる。payload に
--   投稿者を特定できる値を入れない（R-5）。
-- - criteria_templates は PR依頼者自身が作る条件式の保管庫であり、
--   インサイト実数値も投稿者の識別情報も持たない。RLS は所有者のみ（R-5）。
--   保存時の条件式検証は private を読むため SECURITY DEFINER に閉じ込める（R-2）。

-- =============================================================================
-- 1. 一時停止・再開（FR-CMP-13）
-- =============================================================================
alter table public.campaigns
  add column suspended_by     text check (suspended_by in ('client', 'admin')),
  add column suspended_reason text;

comment on column public.campaigns.suspended_by is
  '一時停止した主体。admin が止めた案件は PR依頼者が再開できない（FR-ADM-04）。';

alter table public.campaigns
  add constraint campaigns_suspended_by_only_when_suspended check (
    suspended_by is null or status = 'suspended'
  );

create function public.suspend_campaign(p_campaign_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.campaigns%rowtype;
begin
  if v_uid is null or public.current_app_role() <> 'client' then
    raise exception 'unauthorized';
  end if;

  select * into v_row from public.campaigns c
  where c.id = p_campaign_id and c.client_id = v_uid
  for update;

  if not found then
    raise exception 'campaign not found';
  end if;

  if v_row.status <> 'recruiting' then
    raise exception '募集中の案件だけを一時停止できます';
  end if;

  -- 応募済みの投稿者は選考待ちのまま止まるため、状況を伝える。
  insert into public.notifications (user_id, type, payload)
  select a.creator_id,
         'campaign_suspended',
         jsonb_build_object(
           'campaign_id', v_row.id,
           'campaign_title', v_row.title,
           'reason', p_reason
         )
  from public.applications a
  where a.campaign_id = v_row.id
    and a.status not in ('withdrawn', 'cancelled', 'completed');

  update public.campaigns c
     set status = 'suspended',
         suspended_by = 'client',
         suspended_reason = p_reason
   where c.id = v_row.id;
end;
$$;

create function public.resume_campaign(p_campaign_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.campaigns%rowtype;
begin
  if v_uid is null or public.current_app_role() <> 'client' then
    raise exception 'unauthorized';
  end if;

  select * into v_row from public.campaigns c
  where c.id = p_campaign_id and c.client_id = v_uid
  for update;

  if not found then
    raise exception 'campaign not found';
  end if;

  if v_row.status <> 'suspended' then
    raise exception '一時停止中の案件だけを再開できます';
  end if;

  -- 運営が止めた案件は PR依頼者の操作では戻せない（FR-ADM-04）。
  if v_row.suspended_by is distinct from 'client' then
    raise exception 'この案件は運営により停止されています。運営にお問い合わせください';
  end if;

  update public.campaigns c
     set status = 'recruiting',
         suspended_by = null,
         suspended_reason = null
   where c.id = v_row.id;
end;
$$;

revoke all on function public.suspend_campaign(uuid, text) from public, anon;
revoke all on function public.resume_campaign(uuid)        from public, anon;
grant execute on function public.suspend_campaign(uuid, text) to authenticated;
grant execute on function public.resume_campaign(uuid)        to authenticated;

-- 一時停止した案件は、そのまま取り下げ（中止）にもできるようにする。
-- 0016 の cancel_campaign は suspended を許可していなかった。
create or replace function public.cancel_campaign(p_campaign_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.campaigns%rowtype;
begin
  if v_uid is null or public.current_app_role() <> 'client' then
    raise exception 'unauthorized';
  end if;

  select * into v_row from public.campaigns c
  where c.id = p_campaign_id and c.client_id = v_uid
  for update;

  if not found then
    raise exception 'campaign not found';
  end if;

  if v_row.status not in ('draft', 'recruiting', 'screening',
                          'relaxation_proposed', 'suspended') then
    raise exception 'この状態の案件は取り下げできません';
  end if;

  -- 運営が停止した案件は、PR依頼者の操作では動かせない（FR-ADM-04）。
  if v_row.status = 'suspended' and v_row.suspended_by is distinct from 'client' then
    raise exception 'この案件は運営により停止されています。運営にお問い合わせください';
  end if;

  -- 通知は応募者本人にだけ届く。PR依頼者にはここでも投稿者を返さない（R-5）。
  insert into public.notifications (user_id, type, payload)
  select a.creator_id,
         'campaign_cancelled',
         jsonb_build_object(
           'campaign_id', v_row.id,
           'campaign_title', v_row.title,
           'reason', p_reason
         )
  from public.applications a
  where a.campaign_id = v_row.id
    and a.status not in ('withdrawn', 'cancelled', 'completed');

  update public.applications a
     set status = 'cancelled'
   where a.campaign_id = v_row.id
     and a.status not in ('withdrawn', 'cancelled', 'completed');

  update public.campaigns c
     set status = 'cancelled',
         suspended_by = null,
         suspended_reason = null
   where c.id = v_row.id;
end;
$$;

-- =============================================================================
-- 2. 条件テンプレート（FR-CMP-16）
-- =============================================================================
create table public.criteria_templates (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.client_profiles(user_id) on delete cascade,
  name       text not null check (length(btrim(name)) between 1 and 60),
  criteria   jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (client_id, name)
);

comment on table public.criteria_templates is
  'PR依頼者が再利用する条件式。インサイト実数値は持たない（AGENTS.md R-1）。';

create index criteria_templates_client_idx
  on public.criteria_templates (client_id, created_at desc);

create trigger criteria_templates_set_updated_at
  before update on public.criteria_templates
  for each row execute function public.set_updated_at();

-- 条件式の検証は campaigns と同じホワイトリストを通す。
-- private.validate_criteria を呼ぶため SECURITY DEFINER（AGENTS.md §2）。
create function public.validate_criteria_template()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.validate_criteria(new.criteria, 0);
  return new;
end;
$$;

revoke all on function public.validate_criteria_template() from public, anon, authenticated;

create trigger criteria_templates_validate_criteria
  before insert or update of criteria on public.criteria_templates
  for each row execute function public.validate_criteria_template();

alter table public.criteria_templates enable row level security;

create policy criteria_templates_owner_all on public.criteria_templates
  for all to authenticated
  using (client_id = auth.uid() and public.current_app_role() = 'client')
  with check (client_id = auth.uid() and public.current_app_role() = 'client');

grant select, insert, update, delete on public.criteria_templates to authenticated;
