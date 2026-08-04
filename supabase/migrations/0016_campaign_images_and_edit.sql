-- 0016_campaign_images_and_edit.sql
-- 案件の画像アップロード（FR-CMP-11）と、編集・取り下げ（FR-CMP-13）。
--
-- 1) Storage バケット `campaign-images` と RLS ポリシー。
--    パス規約は `{campaign_id}/{ファイル名}`。先頭フォルダで所有者を判定する。
-- 2) 応募が入ったあとに公平性を損なう項目を編集できないようにするトリガー。
-- 3) 案件の取り下げ RPC（応募者への通知を伴う）。
--
-- 非開示要件への影響（AGENTS.md R-1〜R-5）:
-- - 画像は PR依頼者が自分で用意する店舗・商品写真であり、インサイト実数値も
--   投稿者の識別情報も含まない。下書きの画像は所有者以外に読ませない。
-- - 取り下げ通知は応募者本人の `notifications` に入れる。PR依頼者側へ
--   `creator_id` を返す経路は増やしていない（R-5）。通知の payload に
--   投稿者を特定できる値を入れない。
-- - 編集ガードは private を読む必要がないが、`applications` は client に
--   SELECT ポリシーが無いため SECURITY DEFINER で判定する（R-5 を保ったまま
--   件数の有無だけを見る）。

-- =============================================================================
-- 1. 案件画像の Storage バケット（FR-CMP-11）
--
--    ポリシー本体から public.campaigns を直接参照してはならない。
--    投稿者には campaigns の SELECT ポリシーが無い（0004）ため、
--    ポリシー内の exists が常に偽になり、公開案件の画像まで読めなくなる。
--    判定は SECURITY DEFINER のヘルパーに閉じ込め、返すのは boolean だけにする（R-3）。
-- =============================================================================
create function public.is_campaign_media_owner(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.campaigns c
    where c.id::text = p_folder
      and c.client_id = auth.uid()
  );
$$;

comment on function public.is_campaign_media_owner(text) is
  'Storage のパス先頭フォルダ（案件 id）が呼び出し元の案件かどうか。boolean のみ返す。';

create function public.can_view_campaign_media(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.campaigns c
    where c.id::text = p_folder
      and (c.client_id = auth.uid() or c.status <> 'draft')
  );
$$;

comment on function public.can_view_campaign_media(text) is
  '案件画像を参照してよいか。下書きは所有者のみ。boolean のみ返す（AGENTS.md R-3）。';

revoke all on function public.is_campaign_media_owner(text) from public, anon;
revoke all on function public.can_view_campaign_media(text) from public, anon;
grant execute on function public.is_campaign_media_owner(text) to authenticated;
grant execute on function public.can_view_campaign_media(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'campaign-images',
  'campaign-images',
  false,
  5242880, -- 5MiB。config.toml の file_size_limit（10MiB）より内側に置く
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- 参照。下書きのうちは所有者だけが見られる。
-- 公開後は投稿者にも見せる（一覧のサムネイルと、条件合致時の詳細で使う）。
create policy campaign_images_object_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'campaign-images'
    and public.can_view_campaign_media((storage.foldername(name))[1])
  );

-- 追加・差し替え・削除は案件の所有者のみ。
create policy campaign_images_object_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'campaign-images'
    and public.is_campaign_media_owner((storage.foldername(name))[1])
  );

create policy campaign_images_object_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'campaign-images'
    and public.is_campaign_media_owner((storage.foldername(name))[1])
  );

create policy campaign_images_object_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'campaign-images'
    and public.is_campaign_media_owner((storage.foldername(name))[1])
  );

-- =============================================================================
-- 2. 応募後の編集ガード（FR-CMP-13）
--    「応募が 1 件以上入った後は、投稿者条件・募集人数・期間を編集できない」。
--    取り下げ・辞退済みの応募は数えない（実質的に応募者がいないため）。
--    投稿対象プラットフォームも、投稿者が引き受けた作業内容そのものが
--    変わってしまうため同様に固定する（OI-48 で最終確認）。
-- =============================================================================
create function public.guard_campaign_edit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_has_applicants boolean;
begin
  if new.criteria          is not distinct from old.criteria
     and new.quota         is not distinct from old.quota
     and new.platforms     is not distinct from old.platforms
     and new.apply_start_at is not distinct from old.apply_start_at
     and new.apply_end_at  is not distinct from old.apply_end_at
     and new.visit_start_at is not distinct from old.visit_start_at
     and new.visit_end_at  is not distinct from old.visit_end_at
     and new.post_start_at is not distinct from old.post_start_at
     and new.post_end_at   is not distinct from old.post_end_at then
    return new;
  end if;

  -- 条件緩和（FR-APP-10）はこの経路を通さない。運営・システム側の
  -- service_role による適用は RLS もこのガードも対象外にする。
  if public.is_admin() then
    return new;
  end if;

  select exists (
    select 1 from public.applications a
    where a.campaign_id = old.id
      and a.status not in ('withdrawn', 'cancelled')
  ) into v_has_applicants;

  if v_has_applicants then
    raise exception '応募者がいるため、募集条件・募集人数・期間は変更できません'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_campaign_edit() from public, anon, authenticated;

create trigger campaigns_guard_edit
  before update on public.campaigns
  for each row execute function public.guard_campaign_edit();

-- =============================================================================
-- 3. 案件の取り下げ（FR-CMP-13）
--    応募者への通知を伴う。応募も同時に取り下げ扱いにする。
-- =============================================================================
create function public.cancel_campaign(p_campaign_id uuid, p_reason text default null)
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

  if v_row.status not in ('draft', 'recruiting', 'screening', 'relaxation_proposed') then
    raise exception 'この状態の案件は取り下げできません';
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
     set status = 'cancelled'
   where c.id = v_row.id;
end;
$$;

revoke all on function public.cancel_campaign(uuid, text) from public, anon;
grant execute on function public.cancel_campaign(uuid, text) to authenticated;
