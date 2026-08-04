-- 0015_campaign_creation.sql
-- 案件作成機能（FR-CMP-01〜03 / 06〜10 / 12）のための campaigns 拡張。
--
-- 1) platforms: 投稿対象 SNS（instagram / tiktok / youtube の複数選択）。
-- 2) visit_start_at / visit_end_at: 来店・訪問期間。
--    期間は「応募期間 → 訪問期間 → 投稿・報告期間」の 3 段階になる。
--    通販型など訪問を伴わない将来の案件に備えて null 許容（両方 null か両方設定）。
-- 3) 広告表記タグ（#PR）を案件作成時にサーバー側で自動付与し、
--    所有者でも削除・変更できないようにする（FR-CMP-09 / OI-04 ステマ規制対応）。
--
-- 非開示要件への影響（AGENTS.md R-1〜R-5）:
-- - 追加カラムはいずれも PR依頼者自身が入力する公開情報であり、
--   インサイト実数値・投稿者の識別情報は含まれない。
-- - get_campaign_detail は 0005 のマスキング構造（非合致なら detail ごと送らない）を
--   維持したまま、新カラムを detail 側に追加する。非合致時に返る情報は増えない。
-- - campaign_hashtags のポリシー分割は所有者スコープを変えず、
--   広告表記タグの更新・削除を禁止する方向にのみ狭める。

-- =============================================================================
-- campaigns: 投稿対象プラットフォーム・訪問期間
-- =============================================================================
alter table public.campaigns
  add column platforms      text[] not null default '{instagram}'::text[],
  add column visit_start_at timestamptz,
  add column visit_end_at   timestamptz;

comment on column public.campaigns.platforms is
  '投稿対象 SNS。値域は social_links.platform と揃える。';
comment on column public.campaigns.visit_start_at is
  '来店・訪問期間の開始。訪問を伴わない案件は visit_end_at とともに null。';

alter table public.campaigns
  add constraint campaigns_platforms_allowed check (
    platforms <@ array['instagram', 'tiktok', 'youtube']::text[]
    and cardinality(platforms) >= 1
  );

-- 訪問期間は両方 null か両方設定。設定時は
-- 応募締切 <= 訪問開始 < 訪問終了 <= 報告終了、報告開始は訪問開始以降とする。
alter table public.campaigns
  add constraint campaigns_visit_period check (
    ((visit_start_at is null) = (visit_end_at is null))
    and (visit_start_at is null or (
      visit_start_at < visit_end_at
      and apply_end_at <= visit_start_at
      and visit_start_at <= post_start_at
      and visit_end_at <= post_end_at
    ))
  );

-- =============================================================================
-- 案件の所有者ポリシーを client ロールに限定する
--   従来の client_id = auth.uid() だけでは、creator が自分の uid を
--   client_id にして INSERT すると RLS を通過し、client_profiles を
--   自作すれば案件を作成できてしまう。ロールもサーバー側で検査する（R-8）。
-- =============================================================================
drop policy campaigns_owner_all on public.campaigns;

create policy campaigns_owner_all on public.campaigns
  for all to authenticated
  using (client_id = auth.uid() and public.current_app_role() = 'client')
  with check (client_id = auth.uid() and public.current_app_role() = 'client');

-- =============================================================================
-- criteria 検証トリガーの権限修正
--   0005 の validate_campaign_criteria は SECURITY INVOKER のまま
--   private.validate_criteria を呼ぶため、authenticated からの INSERT が
--   「permission denied for schema private」で必ず失敗していた
--   （これまで案件作成のクライアント経路が無く潜在していた）。
--   private を読む関数の規約（AGENTS.md §2）どおり SECURITY DEFINER にする。
--   private への GRANT は行わない（R-2）。
-- =============================================================================
create or replace function public.validate_campaign_criteria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.validate_criteria(new.criteria, 0);
  if new.original_criteria is not null then
    perform private.validate_criteria(new.original_criteria, 0);
  end if;
  return new;
end;
$$;

revoke all on function public.validate_campaign_criteria() from public, anon, authenticated;

-- =============================================================================
-- 広告表記タグ（#PR）の自動付与と保護（OI-04）
--   付与は SECURITY DEFINER のトリガーで行い、所有者の RLS からは
--   is_mandatory 行を操作できないようにする。
-- =============================================================================
create function public.add_ad_disclosure_tag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.campaign_hashtags (campaign_id, tag, is_mandatory)
  values (new.id, '#PR', true)
  on conflict (campaign_id, tag) do update set is_mandatory = true;
  return new;
end;
$$;

revoke all on function public.add_ad_disclosure_tag() from public, anon, authenticated;

create trigger campaigns_add_ad_disclosure_tag
  after insert on public.campaigns
  for each row execute function public.add_ad_disclosure_tag();

-- for all だった所有者ポリシーを操作別に分割し、広告表記タグ
-- （is_mandatory = true）の追加・変更・削除を所有者からもできなくする。
-- 案件ごと削除するときは FK の on delete cascade が消す
-- （参照整合の内部動作は RLS の対象外のため妨げない）。
drop policy campaign_hashtags_owner on public.campaign_hashtags;

create policy campaign_hashtags_select_owner on public.campaign_hashtags
  for select to authenticated
  using (exists (select 1 from public.campaigns c
                 where c.id = campaign_id and c.client_id = auth.uid()));

create policy campaign_hashtags_insert_owner on public.campaign_hashtags
  for insert to authenticated
  with check (
    not is_mandatory
    and exists (select 1 from public.campaigns c
                where c.id = campaign_id and c.client_id = auth.uid())
  );

create policy campaign_hashtags_update_owner on public.campaign_hashtags
  for update to authenticated
  using (
    not is_mandatory
    and exists (select 1 from public.campaigns c
                where c.id = campaign_id and c.client_id = auth.uid())
  )
  with check (
    not is_mandatory
    and exists (select 1 from public.campaigns c
                where c.id = campaign_id and c.client_id = auth.uid())
  );

create policy campaign_hashtags_delete_owner on public.campaign_hashtags
  for delete to authenticated
  using (
    not is_mandatory
    and exists (select 1 from public.campaigns c
                where c.id = campaign_id and c.client_id = auth.uid())
  );

-- =============================================================================
-- get_campaign_detail: 投稿対象と訪問期間を detail（条件合致時のみ）へ追加
--   0005 と同じシグネチャの create or replace のため GRANT は維持される。
-- =============================================================================
create or replace function public.get_campaign_detail(p_campaign_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_eligible boolean;
  v_row      public.campaigns%rowtype;
begin
  if v_uid is null or public.current_app_role() <> 'creator' then
    raise exception 'unauthorized';
  end if;

  select * into v_row from public.campaigns c
  where c.id = p_campaign_id and c.status in ('recruiting', 'screening', 'in_progress');

  if not found then
    raise exception 'campaign not found';
  end if;

  v_eligible := private.eval_criteria(v_uid, v_row.criteria);

  return jsonb_build_object(
    'id',               v_row.id,
    'title',            v_row.title,
    'store_name',       v_row.store_name_snapshot,
    'genre_id',         v_row.genre_id,
    'reward_value_jpy', v_row.reward_value_jpy,
    'prefecture_id',    v_row.prefecture_id,
    'apply_end_at',     v_row.apply_end_at,
    'is_eligible',      v_eligible,
    -- 条件を満たすときだけ実体を返す。満たさないときは値そのものを送らない。
    'detail', case when v_eligible then jsonb_build_object(
        'reward_description', v_row.reward_description,
        'required_content',   v_row.required_content,
        'city_id',            v_row.city_id,
        'latitude',           v_row.latitude,
        'longitude',          v_row.longitude,
        'nearest_station_id', v_row.nearest_station_id,
        'platforms',          to_jsonb(v_row.platforms),
        'visit_start_at',     v_row.visit_start_at,
        'visit_end_at',       v_row.visit_end_at,
        'post_start_at',      v_row.post_start_at,
        'post_end_at',        v_row.post_end_at,
        'hashtags', (select coalesce(jsonb_agg(h.tag), '[]'::jsonb)
                     from public.campaign_hashtags h where h.campaign_id = v_row.id),
        'images',   (select coalesce(jsonb_agg(i.storage_path order by i.sort_order), '[]'::jsonb)
                     from public.campaign_images i where i.campaign_id = v_row.id)
      ) else null end
  );
end;
$$;
