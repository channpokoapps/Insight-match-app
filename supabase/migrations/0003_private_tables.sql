-- 0003_private_tables.sql
-- インサイト実数値・SNSアクセストークン・監査ログ。
-- クライアントロール（anon / authenticated）からは到達できない（0001 で GRANT を剥奪済み）。

-- =============================================================================
-- SNS 認証情報
-- =============================================================================
create table private.social_credentials (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references public.profiles(id) on delete cascade,
  platform                text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  external_account_id     text not null,
  external_username       text,
  account_type            text check (account_type in ('business', 'creator', 'personal')),
  access_token_encrypted  bytea not null,
  refresh_token_encrypted bytea,
  token_expires_at        timestamptz,
  scopes                  text[] not null default '{}',
  status                  text not null default 'active'
                            check (status in ('active', 'reauth_required', 'revoked')),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (user_id, platform)
);

comment on column private.social_credentials.access_token_encrypted is
  '平文で保存しないこと。暗号化方式は OI-17 で確定する。';

create trigger social_credentials_set_updated_at
  before update on private.social_credentials
  for each row execute function public.set_updated_at();

-- =============================================================================
-- 投稿単位の生データ（最も機微）
-- =============================================================================
create table private.media_snapshots (
  id                uuid primary key default gen_random_uuid(),
  credential_id     uuid not null references private.social_credentials(id) on delete cascade,
  external_media_id text not null,
  media_type        text,
  permalink         text,
  posted_at         timestamptz not null,
  reach             int,
  impressions       int,
  likes             int,
  comments          int,
  saves             int,
  shares            int,
  views             int,
  fetched_at        timestamptz not null default now(),
  unique (credential_id, external_media_id)
);

create index media_snapshots_credential_posted_idx
  on private.media_snapshots (credential_id, posted_at desc);

-- =============================================================================
-- 集計値（マッチング判定はこのテーブルのみを参照する）
-- =============================================================================
create table private.creator_metrics (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  platform        text not null check (platform in ('instagram', 'tiktok', 'youtube')),
  window_days     int  not null check (window_days in (7, 30, 90)),
  followers       int,
  avg_reach       numeric,
  avg_impressions numeric,
  avg_likes       numeric,
  avg_comments    numeric,
  avg_saves       numeric,
  avg_shares      numeric,
  avg_views       numeric,
  engagement_rate numeric,
  post_count      int,
  computed_at     timestamptz not null default now(),
  primary key (user_id, platform, window_days)
);

create index creator_metrics_lookup_idx on private.creator_metrics (platform, window_days);

-- =============================================================================
-- オーディエンス属性
-- =============================================================================
create table private.audience_demographics (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  platform    text not null,
  dimension   text not null check (dimension in ('gender', 'age', 'city', 'country')),
  bucket      text not null,
  ratio       numeric not null check (ratio >= 0 and ratio <= 1),
  computed_at timestamptz not null default now(),
  unique (user_id, platform, dimension, bucket)
);

-- =============================================================================
-- 案件成果分のインサイト
--   成果レポートの集計対象を「案件の投稿」だけに構造的に限定する。
--   WHERE 句の書き忘れで過去投稿が混入する余地をなくすための設計（要件 10章）。
-- =============================================================================
create table private.campaign_post_insights (
  id                 uuid primary key default gen_random_uuid(),
  application_id     uuid not null unique references public.applications(id) on delete cascade,
  campaign_id        uuid not null references public.campaigns(id) on delete cascade,
  media_snapshot_id  uuid not null references private.media_snapshots(id) on delete cascade,
  measured_at        timestamptz not null default now()
);

create index campaign_post_insights_campaign_idx on private.campaign_post_insights (campaign_id);

-- 案件完了時に確定させる匿名集計スナップショット。
-- 投稿者が退会・連携解除して生データが消えても、レポートが壊れないようにする（OI-36）。
create table private.campaign_report_snapshots (
  campaign_id     uuid primary key references public.campaigns(id) on delete cascade,
  participant_num int  not null,
  summary         jsonb not null,
  created_at      timestamptz not null default now()
);

comment on table private.campaign_report_snapshots is
  'k-匿名性を満たす集計値のみを含むため個人情報を含まない。生データ削除後もレポート表示に使える。';

-- =============================================================================
-- バッチ管理
-- =============================================================================
create table private.sync_jobs (
  id            uuid primary key default gen_random_uuid(),
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  target_count  int not null default 0,
  success_count int not null default 0,
  failure_count int not null default 0
);

create table private.sync_job_items (
  id            uuid primary key default gen_random_uuid(),
  job_id        uuid not null references private.sync_jobs(id) on delete cascade,
  credential_id uuid not null references private.social_credentials(id) on delete cascade,
  status        text not null default 'pending'
                  check (status in ('pending', 'running', 'success', 'failed', 'retry')),
  attempt       int  not null default 0,
  next_retry_at timestamptz,
  error_code    text,
  error_message text,
  updated_at    timestamptz not null default now()
);

create index sync_job_items_retry_idx on private.sync_job_items (status, next_retry_at);

create trigger sync_job_items_set_updated_at
  before update on private.sync_job_items
  for each row execute function public.set_updated_at();

-- =============================================================================
-- 監査ログ（アプリから削除・更新できないよう、権限を付与しない）
-- =============================================================================
create table private.audit_logs (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles(id) on delete set null,
  action      text not null,
  target_type text,
  target_id   uuid,
  context     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index audit_logs_actor_idx on private.audit_logs (actor_id, created_at desc);
