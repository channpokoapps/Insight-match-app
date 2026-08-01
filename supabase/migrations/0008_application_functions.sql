-- 0008_application_functions.sql
--
-- 投稿者向けの応募一覧。
-- 投稿者は `campaigns` に SELECT ポリシーを持たない（案件の参照は RPC 経由に限る）ため、
-- 案件名や投稿期限を含めた一覧はここで組み立てる。

create or replace function public.list_my_applications()
returns table (
  id            uuid,
  campaign_id   uuid,
  campaign_title text,
  status        text,
  created_at    timestamptz,
  chat_room_id  uuid,
  post_end_at   timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id,
         a.campaign_id,
         c.title,
         a.status,
         a.created_at,
         r.id,
         c.post_end_at
  from public.applications a
  join public.campaigns c on c.id = a.campaign_id
  left join public.chat_rooms r on r.application_id = a.id
  where a.creator_id = auth.uid()
  order by a.created_at desc;
$$;

revoke all on function public.list_my_applications() from public, anon;
grant execute on function public.list_my_applications() to authenticated;
