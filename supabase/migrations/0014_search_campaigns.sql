-- 0014_search_campaigns.sql
-- 案件一覧 RPC にエリア・沿線・ジャンルの絞り込みと並び替えを追加する。
--
-- これまで list_campaigns_for_creator は都道府県・ジャンル・最低報酬を
-- 1 件ずつしか受け取れず、画面にはフィルタ UI 自体が無かった。
-- 投稿者が「阪急千里線沿い」「大阪市北区と中央区」のように複数条件で
-- 探せるよう、配列で受け取れるようにする。
--
-- 非開示要件への影響（AGENTS.md R-1〜R-5）:
-- - **0010 の報酬マスキングをそのまま維持する**。応募条件を満たさない
--   投稿者には reward_description の実値を送らない（UI で伏せるのではなく
--   値そのものを返さない）。
-- - 冒頭の creator 以外を弾く検査も維持する（R-8: 権限判定はサーバ側）。
-- - 並び順はユーザー入力を SQL に連結せず、許可リストを case で分岐する（R-9）。
-- - 絞り込み条件が増えても返す列は変わらないため、開示範囲は広がらない。

-- 引数を増やすと別シグネチャの関数が並ぶ（オーバーロード）ので、旧版を明示的に落とす。
-- 0005 で付けた GRANT も同時に消えるため、末尾で新シグネチャに付け直す。
drop function if exists public.list_campaigns_for_creator(int, int, int, boolean, int, int);

create function public.list_campaigns_for_creator(
  p_prefecture_ids int[]   default null,
  p_city_ids       int[]   default null,
  p_line_ids       int[]   default null,
  p_station_ids    int[]   default null,
  p_genre_ids      int[]   default null,
  p_min_reward     int     default null,
  p_include_ineligible boolean default true,
  p_sort           text    default 'newest',
  p_limit          int     default 20,
  p_offset         int     default 0
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
  nearest_station_id int,
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
  v_uid  uuid := auth.uid();
  -- 許可リスト。想定外の値はすべて新着順に倒す。
  v_sort text := case when p_sort = 'reward_desc' then 'reward_desc' else 'newest' end;
begin
  if v_uid is null or public.current_app_role() <> 'creator' then
    raise exception 'unauthorized';
  end if;

  return query
  select c.id,
         c.title,
         c.store_name_snapshot,
         c.genre_id,
         -- 条件を満たすときだけ実体を返す。満たさないときは値そのものを送らない（0010）。
         case when e.eligible then c.reward_description else null end,
         c.reward_value_jpy,
         c.prefecture_id,
         c.city_id,
         c.nearest_station_id,
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
    and (p_prefecture_ids is null or c.prefecture_id = any (p_prefecture_ids))
    and (p_city_ids       is null or c.city_id       = any (p_city_ids))
    and (p_station_ids    is null or c.nearest_station_id = any (p_station_ids))
    and (p_line_ids       is null or c.nearest_station_id in (
          select s.id from public.stations s where s.line_id = any (p_line_ids)
        ))
    and (p_genre_ids      is null or c.genre_id      = any (p_genre_ids))
    and (p_min_reward     is null or c.reward_value_jpy >= p_min_reward)
    and (p_include_ineligible or e.eligible)
  order by
    case when v_sort = 'reward_desc' then c.reward_value_jpy end desc nulls last,
    c.published_at desc nulls last
  limit least(coalesce(p_limit, 20), 50)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.list_campaigns_for_creator(
  int[], int[], int[], int[], int[], int, boolean, text, int, int
) from public, anon;

grant execute on function public.list_campaigns_for_creator(
  int[], int[], int[], int[], int[], int, boolean, text, int, int
) to authenticated;

-- 絞り込みに使う列のインデックス。エリアは 0002 の campaigns_area_idx が効く。
create index if not exists campaigns_genre_idx   on public.campaigns (genre_id);
create index if not exists campaigns_station_idx on public.campaigns (nearest_station_id);
