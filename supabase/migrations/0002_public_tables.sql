-- 0002_public_tables.sql
-- クライアントが RLS 経由で参照してよいデータ。
-- ここには一切のインサイト実数値・SNSトークンを置かない（AGENTS.md R-1）。

-- =============================================================================
-- マスタ
-- =============================================================================
create table public.genres (
  id          serial primary key,
  name        text not null unique,
  sort_order  int  not null default 0
);

create table public.prefectures (
  id    serial primary key,
  name  text not null unique
);

create table public.cities (
  id             serial primary key,
  prefecture_id  int  not null references public.prefectures(id),
  name           text not null,
  unique (prefecture_id, name)
);

create table public.railway_lines (
  id    serial primary key,
  name  text not null
);

create table public.stations (
  id         serial primary key,
  line_id    int    not null references public.railway_lines(id),
  name       text   not null,
  latitude   double precision,
  longitude  double precision
);

create index stations_line_idx on public.stations (line_id);

-- =============================================================================
-- ユーザー
-- =============================================================================
create table public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  role              text not null check (role in ('creator', 'client', 'admin')),
  admin_level       text check (admin_level in ('moderator', 'super_admin')),
  status            text not null default 'pending'
                      check (status in ('pending', 'active', 'suspended', 'withdrawn')),
  suspended_reason  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint profiles_admin_level_only_for_admin
    check (admin_level is null or role = 'admin')
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.creator_profiles (
  user_id             uuid primary key references public.profiles(id) on delete cascade,
  full_name           text not null,
  birth_date          date not null,
  prefecture_id       int references public.prefectures(id),
  bio                 text,
  preferred_genre_ids int[] not null default '{}',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.creator_profiles is
  '投稿者の識別情報。client ロールには SELECT ポリシーを一切作らないこと（AGENTS.md R-5）。';

create trigger creator_profiles_set_updated_at
  before update on public.creator_profiles
  for each row execute function public.set_updated_at();

create table public.client_profiles (
  user_id            uuid primary key references public.profiles(id) on delete cascade,
  store_name         text not null,
  genre_id           int references public.genres(id),
  postal_code        text,
  prefecture_id      int references public.prefectures(id),
  city_id            int references public.cities(id),
  address_line       text,
  latitude           double precision,
  longitude          double precision,
  nearest_station_id int references public.stations(id),
  description        text,
  contact_email      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger client_profiles_set_updated_at
  before update on public.client_profiles
  for each row execute function public.set_updated_at();

-- SNS 連携の「状態」のみ。トークンも数値も持たない。
create table public.social_links (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  platform        text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  status          text not null default 'active'
                    check (status in ('active', 'reauth_required', 'revoked')),
  linked_at       timestamptz not null default now(),
  last_synced_at  timestamptz,
  unique (user_id, platform)
);

comment on table public.social_links is
  '連携済みか否かと最終同期日時のみ。フォロワー数を含むいかなる数値も置かないこと。';

create table public.terms_agreements (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  terms_version text not null,
  agreed_at     timestamptz not null default now()
);

create table public.device_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  token      text not null,
  platform   text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now(),
  unique (token)
);

-- =============================================================================
-- 案件
-- =============================================================================
create table public.campaigns (
  id                  uuid primary key default gen_random_uuid(),
  client_id           uuid not null references public.client_profiles(user_id) on delete cascade,
  status              text not null default 'draft'
                        check (status in ('draft', 'recruiting', 'screening', 'relaxation_proposed',
                                          'in_progress', 'posting_closed', 'completed',
                                          'cancelled', 'suspended')),
  title               text not null,
  store_name_snapshot text not null,
  genre_id            int references public.genres(id),
  reward_description  text not null,
  reward_value_jpy    int  not null check (reward_value_jpy >= 0),
  -- 将来の有償案件に備えた拡張点（ADR: 12章 E-1）。初期は in_kind のみ。
  reward_type         text not null default 'in_kind' check (reward_type in ('in_kind', 'paid')),
  criteria            jsonb not null default '{"op":"AND","children":[]}'::jsonb,
  original_criteria   jsonb,
  quota               int  not null check (quota >= 1),
  apply_start_at      timestamptz not null,
  apply_end_at        timestamptz not null,
  post_start_at       timestamptz not null,
  post_end_at         timestamptz not null,
  required_content    text not null,
  prefecture_id       int references public.prefectures(id),
  city_id             int references public.cities(id),
  latitude            double precision,
  longitude           double precision,
  nearest_station_id  int references public.stations(id),
  published_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint campaigns_period_order check (
    apply_start_at < apply_end_at
    and apply_end_at <= post_start_at
    and post_start_at < post_end_at
  )
);

create index campaigns_status_apply_end_idx on public.campaigns (status, apply_end_at);
create index campaigns_area_idx             on public.campaigns (prefecture_id, city_id);
create index campaigns_reward_idx           on public.campaigns (reward_value_jpy desc);
create index campaigns_published_idx        on public.campaigns (published_at desc);
create index campaigns_client_idx           on public.campaigns (client_id);

create trigger campaigns_set_updated_at
  before update on public.campaigns
  for each row execute function public.set_updated_at();

create table public.campaign_images (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns(id) on delete cascade,
  storage_path text not null,
  sort_order   int  not null default 0
);

create index campaign_images_campaign_idx on public.campaign_images (campaign_id);

create table public.campaign_hashtags (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns(id) on delete cascade,
  tag          text not null,
  -- ステマ規制対応の広告表記タグ（#PR 等）は削除不可
  is_mandatory boolean not null default false,
  unique (campaign_id, tag)
);

-- =============================================================================
-- 応募
-- =============================================================================
create table public.applications (
  id          uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  creator_id  uuid not null references public.profiles(id) on delete cascade,
  -- 案件内で閉じた連番。PR依頼者にはこれだけを見せる（ADR-0005）
  alias_no    int  not null,
  status      text not null default 'applied'
                check (status in ('applied', 'screening', 'matched', 'rejected', 'withdrawn',
                                  'cancel_requested', 'cancelled', 'posted', 'no_post', 'completed')),
  message     text,
  matched_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (campaign_id, creator_id),
  unique (campaign_id, alias_no)
);

create index applications_campaign_status_idx on public.applications (campaign_id, status);
create index applications_creator_idx         on public.applications (creator_id);

create trigger applications_set_updated_at
  before update on public.applications
  for each row execute function public.set_updated_at();

create table public.cancellation_requests (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  reason         text not null,
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_at     timestamptz,
  decided_reason text,
  created_at     timestamptz not null default now()
);

create index cancellation_requests_application_idx on public.cancellation_requests (application_id);

create table public.relaxation_proposals (
  id                            uuid primary key default gen_random_uuid(),
  campaign_id                   uuid not null references public.campaigns(id) on delete cascade,
  proposed_criteria             jsonb,
  proposed_apply_end_at         timestamptz,
  -- k 未満は丸めた値を入れる（OI-34）
  estimated_additional_creators int,
  is_estimate_masked            boolean not null default false,
  status                        text not null default 'pending'
                                  check (status in ('pending', 'approved', 'rejected', 'expired')),
  expires_at                    timestamptz,
  decided_at                    timestamptz,
  created_at                    timestamptz not null default now()
);

create index relaxation_proposals_campaign_idx on public.relaxation_proposals (campaign_id, status);

create table public.post_submissions (
  id                uuid primary key default gen_random_uuid(),
  application_id    uuid not null unique references public.applications(id) on delete cascade,
  post_url          text not null,
  external_media_id text,
  is_verified       boolean not null default false,
  verified_at       timestamptz,
  verify_error      text,
  created_at        timestamptz not null default now()
);

comment on column public.post_submissions.post_url is
  '投稿URLから投稿者本人が特定できるため、client には公開しない（RLS で遮断）。';

-- =============================================================================
-- チャット
-- =============================================================================
create table public.chat_rooms (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.applications(id) on delete cascade,
  is_readonly    boolean not null default false,
  created_at     timestamptz not null default now()
);

create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text,
  image_path text,
  read_at    timestamptz,
  created_at timestamptz not null default now(),
  constraint messages_content_present check (body is not null or image_path is not null)
);

create index messages_room_created_idx on public.messages (room_id, created_at desc);

-- =============================================================================
-- 通報・通知
-- =============================================================================
create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('user', 'campaign', 'message')),
  target_id   uuid not null,
  reason_code text not null,
  detail      text,
  status      text not null default 'open' check (status in ('open', 'in_review', 'closed')),
  created_at  timestamptz not null default now()
);

create index reports_status_idx on public.reports (status, created_at desc);

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  type       text not null,
  payload    jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

create table public.favorites (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, campaign_id)
);
