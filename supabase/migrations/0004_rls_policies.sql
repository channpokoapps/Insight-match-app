-- 0004_rls_policies.sql
-- public スキーマの全テーブルで RLS を有効化する。方針はデフォルト拒否。
-- 明示的に許可した行だけが見える。

-- =============================================================================
-- 有効化
-- =============================================================================
alter table public.profiles              enable row level security;
alter table public.creator_profiles      enable row level security;
alter table public.client_profiles       enable row level security;
alter table public.social_links          enable row level security;
alter table public.terms_agreements      enable row level security;
alter table public.device_tokens         enable row level security;
alter table public.campaigns             enable row level security;
alter table public.campaign_images       enable row level security;
alter table public.campaign_hashtags     enable row level security;
alter table public.applications          enable row level security;
alter table public.cancellation_requests enable row level security;
alter table public.relaxation_proposals  enable row level security;
alter table public.post_submissions      enable row level security;
alter table public.chat_rooms            enable row level security;
alter table public.messages              enable row level security;
alter table public.reports               enable row level security;
alter table public.notifications         enable row level security;
alter table public.favorites             enable row level security;

-- マスタは全ログインユーザーが読めてよい（書き込みは service_role のみ）
alter table public.genres        enable row level security;
alter table public.prefectures   enable row level security;
alter table public.cities        enable row level security;
alter table public.railway_lines enable row level security;
alter table public.stations      enable row level security;

create policy genres_select_all        on public.genres        for select to authenticated using (true);
create policy prefectures_select_all   on public.prefectures   for select to authenticated using (true);
create policy cities_select_all        on public.cities        for select to authenticated using (true);
create policy railway_lines_select_all on public.railway_lines for select to authenticated using (true);
create policy stations_select_all      on public.stations      for select to authenticated using (true);

-- =============================================================================
-- profiles
-- =============================================================================
create policy profiles_select_self on public.profiles
  for select to authenticated using (id = auth.uid());

create policy profiles_update_self on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = auth.uid() and role in ('creator', 'client'));

create policy profiles_admin_all on public.profiles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- =============================================================================
-- creator_profiles
--   client ロール向けのポリシーは意図的に作らない。
--   投稿者の氏名が PR依頼者から見える経路を持たせないため（AGENTS.md R-5）。
-- =============================================================================
create policy creator_profiles_self on public.creator_profiles
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy creator_profiles_admin_select on public.creator_profiles
  for select to authenticated using (public.is_admin());

-- =============================================================================
-- client_profiles
--   案件詳細で店舗情報が必要なため、投稿者からも読めてよい。
--   連絡先は含めないビュー経由で参照させる。
-- =============================================================================
create policy client_profiles_self on public.client_profiles
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy client_profiles_select_creator on public.client_profiles
  for select to authenticated using (public.current_app_role() = 'creator');

create policy client_profiles_admin_select on public.client_profiles
  for select to authenticated using (public.is_admin());

create view public.v_client_public
with (security_invoker = true) as
  select user_id, store_name, genre_id, prefecture_id, city_id,
         address_line, latitude, longitude, nearest_station_id, description
  from public.client_profiles;

-- =============================================================================
-- social_links / terms_agreements / device_tokens
-- =============================================================================
create policy social_links_self on public.social_links
  for select to authenticated using (user_id = auth.uid());

create policy social_links_admin_select on public.social_links
  for select to authenticated using (public.is_admin());

create policy terms_agreements_self on public.terms_agreements
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy device_tokens_self on public.device_tokens
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =============================================================================
-- campaigns
--   creator には SELECT ポリシーを作らない。
--   案件の閲覧は list_campaigns_for_creator() / get_campaign_detail() の RPC 経由に限る。
--   criteria を直接読めると他者の分布推測や条件回避の材料になるため。
-- =============================================================================
create policy campaigns_owner_all on public.campaigns
  for all to authenticated
  using (client_id = auth.uid())
  with check (client_id = auth.uid());

create policy campaigns_admin_all on public.campaigns
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy campaign_images_owner on public.campaign_images
  for all to authenticated
  using (exists (select 1 from public.campaigns c
                 where c.id = campaign_id and c.client_id = auth.uid()))
  with check (exists (select 1 from public.campaigns c
                      where c.id = campaign_id and c.client_id = auth.uid()));

create policy campaign_hashtags_owner on public.campaign_hashtags
  for all to authenticated
  using (exists (select 1 from public.campaigns c
                 where c.id = campaign_id and c.client_id = auth.uid()))
  with check (exists (select 1 from public.campaigns c
                      where c.id = campaign_id and c.client_id = auth.uid()));

-- =============================================================================
-- applications
--   client には直接 SELECT させない。creator_id が取得できてしまい、
--   案件をまたいだ名寄せが可能になるため（ADR-0005）。
--   PR依頼者は v_applications_for_client 経由で alias_no のみを見る。
-- =============================================================================
create policy applications_creator_select on public.applications
  for select to authenticated using (creator_id = auth.uid());

create policy applications_admin_all on public.applications
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- security_invoker を付けない = ビュー所有者権限で実行され、
-- 下位テーブルの RLS を経由せずにこのビューの WHERE 句だけが効く。
-- creator_id を意図的に射影から除外している。
create view public.v_applications_for_client as
  select a.id,
         a.campaign_id,
         a.alias_no,
         a.status,
         a.message,
         a.matched_at,
         a.created_at,
         (ps.id is not null)          as has_submission,
         coalesce(ps.is_verified, false) as is_post_verified
  from public.applications a
  join public.campaigns c on c.id = a.campaign_id
  left join public.post_submissions ps on ps.application_id = a.id
  where c.client_id = auth.uid();

comment on view public.v_applications_for_client is
  'PR依頼者向け。creator_id・投稿URLを含めないこと（ADR-0005 / AGENTS.md R-5）。';

grant select on public.v_applications_for_client to authenticated;

-- =============================================================================
-- cancellation_requests
-- =============================================================================
create policy cancellation_requests_creator on public.cancellation_requests
  for all to authenticated
  using (exists (select 1 from public.applications a
                 where a.id = application_id and a.creator_id = auth.uid()))
  with check (exists (select 1 from public.applications a
                      where a.id = application_id and a.creator_id = auth.uid()));

create policy cancellation_requests_client_select on public.cancellation_requests
  for select to authenticated
  using (exists (select 1 from public.applications a
                 join public.campaigns c on c.id = a.campaign_id
                 where a.id = application_id and c.client_id = auth.uid()));

create policy cancellation_requests_client_update on public.cancellation_requests
  for update to authenticated
  using (exists (select 1 from public.applications a
                 join public.campaigns c on c.id = a.campaign_id
                 where a.id = application_id and c.client_id = auth.uid()));

-- =============================================================================
-- relaxation_proposals
-- =============================================================================
create policy relaxation_proposals_client on public.relaxation_proposals
  for all to authenticated
  using (exists (select 1 from public.campaigns c
                 where c.id = campaign_id and c.client_id = auth.uid()))
  with check (exists (select 1 from public.campaigns c
                      where c.id = campaign_id and c.client_id = auth.uid()));

-- =============================================================================
-- post_submissions
--   投稿URLは投稿者の特定につながるため client には見せない。
--   PR依頼者は v_applications_for_client の has_submission / is_post_verified を見る。
-- =============================================================================
create policy post_submissions_creator on public.post_submissions
  for all to authenticated
  using (exists (select 1 from public.applications a
                 where a.id = application_id and a.creator_id = auth.uid()))
  with check (exists (select 1 from public.applications a
                      where a.id = application_id and a.creator_id = auth.uid()));

create policy post_submissions_admin_select on public.post_submissions
  for select to authenticated using (public.is_admin());

-- =============================================================================
-- chat_rooms / messages
--   admin には既定でポリシーを作らない。
--   通報のある会話のみ super_admin が RPC 経由で閲覧し、その RPC が監査ログを書く。
-- =============================================================================
create policy chat_rooms_participants on public.chat_rooms
  for select to authenticated
  using (exists (select 1 from public.applications a
                 join public.campaigns c on c.id = a.campaign_id
                 where a.id = application_id
                   and (a.creator_id = auth.uid() or c.client_id = auth.uid())));

create policy messages_participants_select on public.messages
  for select to authenticated
  using (exists (select 1 from public.chat_rooms r
                 join public.applications a on a.id = r.application_id
                 join public.campaigns c on c.id = a.campaign_id
                 where r.id = room_id
                   and (a.creator_id = auth.uid() or c.client_id = auth.uid())));

create policy messages_participants_insert on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (select 1 from public.chat_rooms r
                join public.applications a on a.id = r.application_id
                join public.campaigns c on c.id = a.campaign_id
                where r.id = room_id
                  and r.is_readonly = false
                  and (a.creator_id = auth.uid() or c.client_id = auth.uid()))
  );

-- =============================================================================
-- reports / notifications / favorites
-- =============================================================================
create policy reports_insert_self on public.reports
  for insert to authenticated with check (reporter_id = auth.uid());

create policy reports_select_self on public.reports
  for select to authenticated using (reporter_id = auth.uid());

create policy reports_admin_all on public.reports
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy notifications_self on public.notifications
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy favorites_self on public.favorites
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
