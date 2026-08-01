-- 0005_functions.sql
-- ADR-0003 の第2層。private を読めるのはここに定義した SECURITY DEFINER 関数だけ。
-- 戻り値の型には boolean / 件数 / k-匿名性を満たす集計値しか含めないこと（AGENTS.md R-3）。

-- =============================================================================
-- 条件式 JSON の検証
--   metric / attr / cmp をホワイトリストで制限し、ネスト深さを 3 までに抑える。
--   ここを通らない criteria は保存させない。
-- =============================================================================
create or replace function private.validate_criteria(p_node jsonb, p_depth int default 0)
returns void
language plpgsql
immutable
as $$
declare
  v_child jsonb;
  v_op    text;
begin
  if p_node is null or p_node = 'null'::jsonb then
    return;
  end if;

  if p_depth > 3 then
    raise exception 'criteria: ネストが深すぎます（最大3段）';
  end if;

  v_op := p_node->>'op';

  if v_op is not null then
    if v_op not in ('AND', 'OR') then
      raise exception 'criteria: 未対応の演算子 %', v_op;
    end if;
    if jsonb_typeof(p_node->'children') <> 'array' then
      raise exception 'criteria: children が配列ではありません';
    end if;
    if jsonb_array_length(p_node->'children') > 20 then
      raise exception 'criteria: 条件数が多すぎます（最大20）';
    end if;
    for v_child in select jsonb_array_elements(p_node->'children') loop
      perform private.validate_criteria(v_child, p_depth + 1);
    end loop;
    return;
  end if;

  -- リーフ
  if p_node ? 'metric' then
    if (p_node->>'metric') not in (
      'followers', 'avg_reach', 'avg_impressions', 'avg_likes', 'avg_comments',
      'avg_saves', 'avg_shares', 'avg_views', 'engagement_rate', 'post_count'
    ) then
      raise exception 'criteria: 未対応の指標 %', p_node->>'metric';
    end if;
    if (p_node->>'platform') not in ('instagram', 'tiktok', 'youtube') then
      raise exception 'criteria: 未対応のプラットフォーム %', p_node->>'platform';
    end if;
    if (p_node->>'window')::int not in (7, 30, 90) then
      raise exception 'criteria: 未対応の集計期間 %', p_node->>'window';
    end if;
  elsif p_node ? 'attr' then
    if (p_node->>'attr') not in ('prefecture_id', 'age', 'genre_id') then
      raise exception 'criteria: 未対応の属性 %', p_node->>'attr';
    end if;
  else
    raise exception 'criteria: metric または attr が必要です';
  end if;

  if (p_node->>'cmp') not in ('>=', '<=', '>', '<', '=', 'contains') then
    raise exception 'criteria: 未対応の比較演算子 %', p_node->>'cmp';
  end if;

  if jsonb_typeof(p_node->'value') not in ('number', 'string') then
    raise exception 'criteria: value は数値または文字列である必要があります';
  end if;
end;
$$;

-- =============================================================================
-- 条件式の評価
--   動的SQLを一切使わない（AGENTS.md R-9）。
-- =============================================================================
create or replace function private.compare(p_actual numeric, p_cmp text, p_value numeric)
returns boolean
language sql
immutable
as $$
  select case
    when p_actual is null then false
    when p_cmp = '>=' then p_actual >= p_value
    when p_cmp = '<=' then p_actual <= p_value
    when p_cmp = '>'  then p_actual >  p_value
    when p_cmp = '<'  then p_actual <  p_value
    when p_cmp = '='  then p_actual =  p_value
    else false
  end;
$$;

create or replace function private.eval_criteria(p_user_id uuid, p_node jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_op     text;
  v_child  jsonb;
  v_result boolean;
  v_actual numeric;
  v_cmp    text;
  v_value  numeric;
begin
  if p_node is null or p_node = 'null'::jsonb then
    return true;
  end if;

  v_op := p_node->>'op';

  if v_op = 'AND' then
    for v_child in select jsonb_array_elements(p_node->'children') loop
      if not private.eval_criteria(p_user_id, v_child) then
        return false;
      end if;
    end loop;
    return true;
  elsif v_op = 'OR' then
    v_result := false;
    for v_child in select jsonb_array_elements(p_node->'children') loop
      if private.eval_criteria(p_user_id, v_child) then
        return true;
      end if;
    end loop;
    return false;
  end if;

  v_cmp := p_node->>'cmp';

  -- 属性条件
  if p_node ? 'attr' then
    if (p_node->>'attr') = 'prefecture_id' then
      select cp.prefecture_id into v_actual
      from public.creator_profiles cp where cp.user_id = p_user_id;
    elsif (p_node->>'attr') = 'age' then
      select extract(year from age(current_date, cp.birth_date)) into v_actual
      from public.creator_profiles cp where cp.user_id = p_user_id;
    elsif (p_node->>'attr') = 'genre_id' then
      return exists (
        select 1 from public.creator_profiles cp
        where cp.user_id = p_user_id
          and (p_node->>'value')::int = any (cp.preferred_genre_ids)
      );
    else
      return false;
    end if;
    return private.compare(v_actual, v_cmp, (p_node->>'value')::numeric);
  end if;

  -- インサイト条件
  v_value := (p_node->>'value')::numeric;

  select case p_node->>'metric'
           when 'followers'       then m.followers::numeric
           when 'avg_reach'       then m.avg_reach
           when 'avg_impressions' then m.avg_impressions
           when 'avg_likes'       then m.avg_likes
           when 'avg_comments'    then m.avg_comments
           when 'avg_saves'       then m.avg_saves
           when 'avg_shares'      then m.avg_shares
           when 'avg_views'       then m.avg_views
           when 'engagement_rate' then m.engagement_rate
           when 'post_count'      then m.post_count::numeric
         end
    into v_actual
  from private.creator_metrics m
  where m.user_id     = p_user_id
    and m.platform    = (p_node->>'platform')
    and m.window_days = (p_node->>'window')::int;

  return private.compare(v_actual, v_cmp, v_value);
end;
$$;

-- =============================================================================
-- k-匿名性の丸め
-- =============================================================================
create or replace function private.mask_count(p_count int)
returns jsonb
language sql
immutable
as $$
  select case
    when p_count is null then jsonb_build_object('count', null, 'masked', true, 'label', '取得できません')
    when p_count < private.k_threshold()
      then jsonb_build_object('count', null, 'masked', true,
                              'label', private.k_threshold()::text || '人未満')
    else jsonb_build_object('count', p_count, 'masked', false, 'label', p_count::text || '人')
  end;
$$;

-- =============================================================================
-- 条件に一致する投稿者数（PR依頼者向け・リアルタイム）
--   返すのは丸めた人数のみ。誰が該当するかは一切返さない。
-- =============================================================================
create or replace function public.count_matching_creators(p_criteria jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if public.current_app_role() is null then
    raise exception 'unauthorized';
  end if;

  perform private.validate_criteria(p_criteria, 0);

  select count(*) into v_count
  from public.profiles p
  where p.role = 'creator'
    and p.status = 'active'
    and exists (select 1 from public.social_links sl
                where sl.user_id = p.id and sl.status = 'active')
    and private.eval_criteria(p.id, p_criteria);

  return private.mask_count(v_count);
end;
$$;

-- =============================================================================
-- 案件の作成・更新（criteria の検証をサーバ側で強制する）
-- =============================================================================
create or replace function public.validate_campaign_criteria()
returns trigger
language plpgsql
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

create trigger campaigns_validate_criteria
  before insert or update of criteria, original_criteria on public.campaigns
  for each row execute function public.validate_campaign_criteria();

-- =============================================================================
-- 投稿者向け案件一覧
--   条件を満たす案件だけを返す（モザイク対象は含めない設計にするか、
--   モザイク表示するかは呼び出し側パラメータで切り替える）。
--   criteria そのものは絶対に返さない。
-- =============================================================================
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
         c.reward_description,
         c.reward_value_jpy,
         c.prefecture_id,
         c.city_id,
         c.apply_end_at,
         c.post_start_at,
         c.post_end_at,
         (select ci.storage_path from public.campaign_images ci
          where ci.campaign_id = c.id order by ci.sort_order limit 1),
         private.eval_criteria(v_uid, c.criteria),
         exists (select 1 from public.applications a
                 where a.campaign_id = c.id and a.creator_id = v_uid)
  from public.campaigns c
  where c.status = 'recruiting'
    and c.apply_start_at <= now()
    and c.apply_end_at   >  now()
    and (p_prefecture_id is null or c.prefecture_id = p_prefecture_id)
    and (p_genre_id      is null or c.genre_id      = p_genre_id)
    and (p_min_reward    is null or c.reward_value_jpy >= p_min_reward)
    and (p_include_ineligible or private.eval_criteria(v_uid, c.criteria))
  order by c.published_at desc nulls last
  limit least(coalesce(p_limit, 20), 50)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- =============================================================================
-- 案件詳細（投稿者向け）
--   条件を満たさない場合、詳細項目はモザイク対象としてクライアントに返さない。
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

-- =============================================================================
-- 応募
--   条件充足判定をサーバ側で再検証する（AGENTS.md R-8）。
--   alias_no をここで採番する。
-- =============================================================================
create or replace function public.apply_to_campaign(p_campaign_id uuid, p_message text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_row      public.campaigns%rowtype;
  v_alias_no int;
  v_app_id   uuid;
begin
  if v_uid is null or public.current_app_role() <> 'creator' then
    raise exception 'unauthorized';
  end if;

  -- 同一案件への同時応募を直列化して alias_no の重複を防ぐ
  select * into v_row from public.campaigns c
  where c.id = p_campaign_id for update;

  if not found then
    raise exception 'campaign not found';
  end if;
  if v_row.status <> 'recruiting' or v_row.apply_end_at <= now() then
    raise exception 'この案件は現在応募を受け付けていません';
  end if;
  if not private.eval_criteria(v_uid, v_row.criteria) then
    -- 具体的にどの条件で落ちたかは返さない（インサイト値の推測を防ぐ）
    raise exception '応募条件を満たしていません';
  end if;
  if exists (select 1 from public.applications a
             where a.campaign_id = p_campaign_id and a.creator_id = v_uid) then
    raise exception 'すでに応募済みです';
  end if;

  select coalesce(max(a.alias_no), 0) + 1 into v_alias_no
  from public.applications a where a.campaign_id = p_campaign_id;

  insert into public.applications (campaign_id, creator_id, alias_no, status, message)
  values (p_campaign_id, v_uid, v_alias_no, 'applied', p_message)
  returning id into v_app_id;

  insert into private.audit_logs (actor_id, action, target_type, target_id)
  values (v_uid, 'apply_to_campaign', 'application', v_app_id);

  return v_app_id;
end;
$$;

-- =============================================================================
-- 選考（PR依頼者）
--   application_id 単位で採否を決める。creator_id は引数にも戻り値にも出さない。
-- =============================================================================
create or replace function public.decide_application(p_application_id uuid, p_decision text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_camp  uuid;
  v_room  uuid;
begin
  if p_decision not in ('matched', 'rejected') then
    raise exception 'invalid decision';
  end if;

  select a.campaign_id into v_camp
  from public.applications a
  join public.campaigns c on c.id = a.campaign_id
  where a.id = p_application_id
    and c.client_id = v_uid
    and a.status in ('applied', 'screening');

  if v_camp is null then
    raise exception 'unauthorized or invalid state';
  end if;

  update public.applications
     set status = p_decision,
         matched_at = case when p_decision = 'matched' then now() else null end
   where id = p_application_id;

  if p_decision = 'matched' then
    insert into public.chat_rooms (application_id)
    values (p_application_id)
    on conflict (application_id) do nothing
    returning id into v_room;
  end if;

  insert into private.audit_logs (actor_id, action, target_type, target_id, context)
  values (v_uid, 'decide_application', 'application', p_application_id,
          jsonb_build_object('decision', p_decision));
end;
$$;

-- =============================================================================
-- 条件緩和の増加人数試算
--   増分も k 未満なら丸める（OI-34）。
-- =============================================================================
create or replace function public.estimate_relaxation(p_campaign_id uuid, p_new_criteria jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_old jsonb;
  v_cur int;
  v_new int;
begin
  select c.criteria into v_old from public.campaigns c
  where c.id = p_campaign_id and c.client_id = v_uid;

  if v_old is null then
    raise exception 'unauthorized';
  end if;

  perform private.validate_criteria(p_new_criteria, 0);

  select count(*) filter (where private.eval_criteria(p.id, v_old)),
         count(*) filter (where private.eval_criteria(p.id, p_new_criteria))
    into v_cur, v_new
  from public.profiles p
  where p.role = 'creator' and p.status = 'active'
    and exists (select 1 from public.social_links sl
                where sl.user_id = p.id and sl.status = 'active');

  return jsonb_build_object(
    'current',    private.mask_count(v_cur),
    'relaxed',    private.mask_count(v_new),
    'additional', private.mask_count(greatest(v_new - v_cur, 0))
  );
end;
$$;

-- =============================================================================
-- ヒストグラム生成
--   件数が k 未満のビンは隣のビンに併合する（ADR-0003 第3層）。
-- =============================================================================
create or replace function private.build_histogram(p_values numeric[], p_bin_width numeric)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_k       int := private.k_threshold();
  v_min     numeric;
  v_max     numeric;
  v_edges   numeric[];
  v_counts  int[];
  v_i       int;
  v_idx     int;
  v_bins    int;
  v_out     jsonb := '[]'::jsonb;
  v_acc     int := 0;
  v_from    numeric;
begin
  if p_values is null or array_length(p_values, 1) is null then
    return v_out;
  end if;

  select min(v), max(v) into v_min, v_max from unnest(p_values) as v;
  v_min := floor(v_min / p_bin_width) * p_bin_width;
  v_max := floor(v_max / p_bin_width) * p_bin_width + p_bin_width;
  v_bins := greatest(((v_max - v_min) / p_bin_width)::int, 1);

  v_counts := array_fill(0, array[v_bins]);
  for v_i in 1 .. array_length(p_values, 1) loop
    v_idx := least(floor((p_values[v_i] - v_min) / p_bin_width)::int + 1, v_bins);
    v_counts[v_idx] := v_counts[v_idx] + 1;
  end loop;

  v_from := v_min;
  for v_i in 1 .. v_bins loop
    v_acc := v_acc + v_counts[v_i];
    -- k 未満のうちは確定させず、次のビンに繰り越して併合する
    if v_acc >= v_k or v_i = v_bins then
      if v_acc > 0 then
        v_out := v_out || jsonb_build_object(
          'from',  v_from,
          'to',    v_min + p_bin_width * v_i,
          'count', v_acc
        );
      end if;
      v_from := v_min + p_bin_width * v_i;
      v_acc  := 0;
    end if;
  end loop;

  return v_out;
end;
$$;

-- =============================================================================
-- 成果レポート
--   参加人数が k 未満なら一切の集計値を返さない。
-- =============================================================================
create or replace function public.get_campaign_report(p_campaign_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_n     int;
  v_snap  jsonb;
  v_reach numeric[];
  v_likes numeric[];
  v_saves numeric[];
begin
  if not exists (select 1 from public.campaigns c
                 where c.id = p_campaign_id and c.client_id = v_uid) then
    raise exception 'unauthorized';
  end if;

  -- 確定済みスナップショットがあればそれを返す（生データ削除後も表示できる）
  select s.summary into v_snap
  from private.campaign_report_snapshots s where s.campaign_id = p_campaign_id;
  if v_snap is not null then
    return v_snap;
  end if;

  select count(*) into v_n
  from private.campaign_post_insights cpi
  where cpi.campaign_id = p_campaign_id;

  if v_n < private.k_threshold() then
    return jsonb_build_object(
      'available', false,
      'reason', 'k_anonymity',
      'message', '投稿数が' || private.k_threshold()::text || '件未満のため、レポートは表示できません'
    );
  end if;

  select array_agg(ms.reach::numeric) filter (where ms.reach is not null),
         array_agg(ms.likes::numeric) filter (where ms.likes is not null),
         array_agg(ms.saves::numeric) filter (where ms.saves is not null)
    into v_reach, v_likes, v_saves
  from private.campaign_post_insights cpi
  join private.media_snapshots ms on ms.id = cpi.media_snapshot_id
  where cpi.campaign_id = p_campaign_id;

  return jsonb_build_object(
    'available', true,
    'participant_count', v_n,
    'metrics', jsonb_build_object(
      'reach', jsonb_build_object(
        'median',    (select percentile_cont(0.5) within group (order by v) from unnest(v_reach) v),
        'total',     (select sum(v) from unnest(v_reach) v),
        'histogram', private.build_histogram(v_reach, 1000)
      ),
      'likes', jsonb_build_object(
        'median',    (select percentile_cont(0.5) within group (order by v) from unnest(v_likes) v),
        'total',     (select sum(v) from unnest(v_likes) v),
        'histogram', private.build_histogram(v_likes, 50)
      ),
      'saves', jsonb_build_object(
        'median',    (select percentile_cont(0.5) within group (order by v) from unnest(v_saves) v),
        'total',     (select sum(v) from unnest(v_saves) v),
        'histogram', private.build_histogram(v_saves, 10)
      )
    )
  );
end;
$$;

-- =============================================================================
-- 投稿者向け：自分のSNS連携状態
--   自分自身に対しても実数値は返さない。連携状態と最終同期日時のみ。
--   実数値は各SNSの公式アプリで確認してもらう方針（AGENTS.md R-1 の一貫性維持）。
-- =============================================================================
create or replace function public.get_my_sns_status()
returns table (
  platform       text,
  status         text,
  last_synced_at timestamptz,
  is_ready       boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select sl.platform,
         sl.status,
         sl.last_synced_at,
         (sl.status = 'active'
          and exists (select 1 from private.creator_metrics m
                      where m.user_id = sl.user_id and m.platform = sl.platform))
  from public.social_links sl
  where sl.user_id = auth.uid();
$$;

-- =============================================================================
-- 実行権限
--   anon には一切公開しない。
-- =============================================================================
revoke all on function public.count_matching_creators(jsonb)          from public, anon;
revoke all on function public.list_campaigns_for_creator(int, int, int, boolean, int, int) from public, anon;
revoke all on function public.get_campaign_detail(uuid)               from public, anon;
revoke all on function public.apply_to_campaign(uuid, text)           from public, anon;
revoke all on function public.decide_application(uuid, text)          from public, anon;
revoke all on function public.estimate_relaxation(uuid, jsonb)        from public, anon;
revoke all on function public.get_campaign_report(uuid)               from public, anon;
revoke all on function public.get_my_sns_status()                     from public, anon;

grant execute on function public.count_matching_creators(jsonb)       to authenticated;
grant execute on function public.list_campaigns_for_creator(int, int, int, boolean, int, int) to authenticated;
grant execute on function public.get_campaign_detail(uuid)            to authenticated;
grant execute on function public.apply_to_campaign(uuid, text)        to authenticated;
grant execute on function public.decide_application(uuid, text)       to authenticated;
grant execute on function public.estimate_relaxation(uuid, jsonb)     to authenticated;
grant execute on function public.get_campaign_report(uuid)            to authenticated;
grant execute on function public.get_my_sns_status()                  to authenticated;

-- private の関数はクライアントから直接呼ばせない
revoke all on function private.eval_criteria(uuid, jsonb)   from public, anon, authenticated;
revoke all on function private.validate_criteria(jsonb, int) from public, anon, authenticated;
revoke all on function private.build_histogram(numeric[], numeric) from public, anon, authenticated;
revoke all on function private.mask_count(int)              from public, anon, authenticated;
revoke all on function private.k_threshold()                from public, anon, authenticated;
revoke all on function private.compare(numeric, text, numeric) from public, anon, authenticated;
