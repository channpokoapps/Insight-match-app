-- 0010_mask_reward_in_list.sql
-- 案件一覧 RPC の報酬内容を非開示側に倒す。
--
-- これまで list_campaigns_for_creator は、応募条件を満たさない投稿者にも
-- reward_description の実値を返していた(UI で伏せていただけで、通信上は届いていた)。
-- get_campaign_detail と同じ「条件を満たさないときは値そのものを送らない」方式に揃える。
-- 影響ルール: R-8(サーバ側での再判定)。開示範囲の判断は非開示側に倒す。

create or replace function public.list_campaigns_for_creator(
  p_prefecture_id int default null,
  p_genre_id      int default null,
  p_min_reward    int default null,
  p_include_ineligible boolean default true,
  p_limit         int default 20,
  p_offset        int default 0
)
returns table (
  id                 uuid,
  title              text,
  store_name         text,
  genre_id           int,
  reward_description text,
  reward_value_jpy   int,
  prefecture_id      int,
  city_id            int,
  apply_end_at       timestamptz,
  post_start_at      timestamptz,
  post_end_at        timestamptz,
  thumbnail_path     text,
  is_eligible        boolean,
  has_applied        boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or public.current_app_role() <> 'creator' then
    raise exception 'unauthorized';
  end if;

  return query
  select c.id,
         c.title,
         c.store_name_snapshot,
         c.genre_id,
         -- 条件を満たすときだけ実体を返す。満たさないときは値そのものを送らない。
         case when e.eligible then c.reward_description else null end,
         c.reward_value_jpy,
         c.prefecture_id,
         c.city_id,
         c.apply_end_at,
         c.post_start_at,
         c.post_end_at,
         (select ci.storage_path from public.campaign_images ci
          where ci.campaign_id = c.id order by ci.sort_order limit 1),
         e.eligible,
         exists (select 1 from public.applications a
                 where a.campaign_id = c.id and a.creator_id = v_uid)
  from public.campaigns c
  cross join lateral (
    select private.eval_criteria(v_uid, c.criteria) as eligible
  ) e
  where c.status = 'recruiting'
    and c.apply_start_at <= now()
    and c.apply_end_at   >  now()
    and (p_prefecture_id is null or c.prefecture_id = p_prefecture_id)
    and (p_genre_id      is null or c.genre_id      = p_genre_id)
    and (p_min_reward    is null or c.reward_value_jpy >= p_min_reward)
    and (p_include_ineligible or e.eligible)
  order by c.published_at desc nulls last
  limit least(coalesce(p_limit, 20), 50)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
