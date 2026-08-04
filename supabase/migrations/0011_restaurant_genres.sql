-- 0011_restaurant_genres.sql
-- ジャンルを飲食店専用の 13 種に置き換え、店舗が複数選択できるようにする。
--
-- 本サービスは飲食店専用だが、ジャンルマスタに「美容・サロン」「フィットネス・ジム」
-- などの非飲食が混在し、かつ店舗側は単一選択しかできなかった。
-- あわせて「その他」を選んだときの自由記述を受け取り、同じ記述が一定数たまったら
-- 運営がマスタへ昇格できるようにする（list_genre_other_suggestions）。
--
-- 非開示要件への影響（AGENTS.md R-1〜R-5）:
-- - インサイト実数値の露出面は増やさない。追加するのは店舗の属性のみ。
-- - v_client_public を作り直すが、contact_email と postal_code は引き続き含めない
--   （投稿者に見せるのは案件詳細に必要な店舗情報だけ）。

-- =============================================================================
-- 1. 旧ジャンルの退避
--    既存 id の名前を書き換えると既存行の意味が黙って変わるため、新しい id で
--    追加し、参照を張り替えてから旧行を消す。name の一意制約を空けるために
--    いったん退避用の名前に変える。
-- =============================================================================
create temporary table _genre_migration as
select id as old_id, name as old_name
from public.genres;

update public.genres g
set name = '__old__' || g.id || '__' || g.name
where g.id in (select old_id from _genre_migration);

-- =============================================================================
-- 2. 飲食ジャンル 13 種を投入
-- =============================================================================
insert into public.genres (name, sort_order) values
  ('和食',                  10),
  ('寿司',                  20),
  ('居酒屋',                30),
  ('ラーメン・うどん・蕎麦',  40),
  ('焼肉',                  50),
  ('焼き鳥・串',             60),
  ('カフェ',                70),
  ('イタリアン',             80),
  ('フレンチ',              90),
  ('中華',                 100),
  ('エスニック',            110),
  ('テイクアウト・デリ',     120),
  ('その他',               999);

-- 旧ジャンル → 新ジャンルの対応。飲食以外と対応先のないものはすべて「その他」に倒す。
alter table _genre_migration add column new_id int;

update _genre_migration m
set new_id = g.id
from public.genres g
where g.name = case m.old_name
                 when '飲食（カフェ）'      then 'カフェ'
                 when '飲食（居酒屋・バー）' then '居酒屋'
                 else 'その他'
               end;

-- =============================================================================
-- 3. 店舗プロフィールを複数ジャンル対応にする
--    v_client_public が genre_id に依存しているため、先にビューを落とす。
--    列構成が変わるので、どのみち作り直しが必要（§6 で再作成する）。
-- =============================================================================
drop view if exists public.v_client_public;

alter table public.client_profiles
  add column genre_ids        int[] not null default '{}',
  add column genre_other_text text;

comment on column public.client_profiles.genre_other_text is
  'ジャンルで「その他」を選んだときの自由記述。同じ記述が増えたらマスタへ昇格する（list_genre_other_suggestions）。';

update public.client_profiles cp
set genre_ids = array[m.new_id]
from _genre_migration m
where cp.genre_id = m.old_id
  and m.new_id is not null;

alter table public.client_profiles drop column genre_id;

alter table public.creator_profiles
  add column genre_other_text text;

comment on column public.creator_profiles.genre_other_text is
  '得意なジャンルで「その他」を選んだときの自由記述。';

-- =============================================================================
-- 4. 残る参照の張り替えと旧ジャンルの削除
-- =============================================================================
update public.campaigns c
set genre_id = m.new_id
from _genre_migration m
where c.genre_id = m.old_id
  and m.new_id is not null;

-- int[] は要素ごとに置き換える。重複は array_agg(distinct) で畳む。
update public.creator_profiles cp
set preferred_genre_ids = sub.ids
from (
  select cp2.user_id,
         array_agg(distinct coalesce(m.new_id, old.id)) as ids
  from public.creator_profiles cp2
  cross join lateral unnest(cp2.preferred_genre_ids) as old(id)
  left join _genre_migration m on m.old_id = old.id
  group by cp2.user_id
) sub
where cp.user_id = sub.user_id;

delete from public.genres
where id in (select old_id from _genre_migration);

drop table _genre_migration;

-- =============================================================================
-- 5. 複数ジャンルでの絞り込みに備えたインデックス
-- =============================================================================
create index client_profiles_genre_ids_idx
  on public.client_profiles using gin (genre_ids);

create index creator_profiles_genre_ids_idx
  on public.creator_profiles using gin (preferred_genre_ids);

-- =============================================================================
-- 6. 公開ビューの作り直し（§3 で落としたものを新しい列構成で戻す）
--    contact_email と postal_code は引き続き含めない。
-- =============================================================================
create view public.v_client_public
with (security_invoker = true) as
  select user_id, store_name, genre_ids, genre_other_text,
         prefecture_id, city_id, address_line,
         latitude, longitude, nearest_station_id, description
  from public.client_profiles;

grant select on public.v_client_public to authenticated;

-- =============================================================================
-- 7. 「その他」の自由記述を集計する運営向け関数
--    マスタへ昇格させる候補を拾うためのもの。管理者以外は実行できない。
-- =============================================================================
create or replace function public.list_genre_other_suggestions(
  p_min_count int default 3
)
returns table (
  genre_text  text,
  store_count int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'unauthorized';
  end if;

  return query
  select lower(btrim(cp.genre_other_text)) as genre_text,
         count(*)::int                     as store_count
  from public.client_profiles cp
  where cp.genre_other_text is not null
    and btrim(cp.genre_other_text) <> ''
  group by 1
  having count(*) >= greatest(coalesce(p_min_count, 3), 1)
  order by 2 desc, 1;
end;
$$;

revoke all on function public.list_genre_other_suggestions(int) from public, anon;
grant execute on function public.list_genre_other_suggestions(int) to authenticated;
