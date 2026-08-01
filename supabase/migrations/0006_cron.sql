-- 0006_cron.sql
-- 日次バッチのスケジュール（ADR-0004）。
--
-- 事前準備（ローカルの db reset では自動で行われない）:
--   1. Supabase ダッシュボード > Database > Extensions で pg_cron / pg_net を有効化
--   2. Vault にシークレットを登録
--        select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--        select vault.create_secret('<service_role_key>', 'service_role_key');
--   ※ service_role キーは Vault にのみ置く。アプリには絶対に埋め込まない（AGENTS.md R-6）。

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function private.invoke_edge_function(p_name text, p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_key text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';

  if v_url is null or v_key is null then
    raise warning 'invoke_edge_function: Vault にシークレットが登録されていません';
    return null;
  end if;

  return net.http_post(
    url     := v_url || '/functions/v1/' || p_name,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key
               ),
    body    := p_body,
    timeout_milliseconds := 30000
  );
end;
$$;

revoke all on function private.invoke_edge_function(text, jsonb) from public, anon, authenticated;

-- 日次インサイト取得。03:00 JST = 18:00 UTC（前日）。
select cron.schedule(
  'sync-insights-daily',
  '0 18 * * *',
  $$ select private.invoke_edge_function('sync-insights', '{"trigger":"daily"}'::jsonb); $$
);

-- リトライ。15分ごとに next_retry_at を過ぎた失敗分だけを再実行する。
select cron.schedule(
  'sync-insights-retry',
  '*/15 * * * *',
  $$ select private.invoke_edge_function('sync-insights', '{"trigger":"retry"}'::jsonb); $$
);

-- 案件の期日進行（募集終了 → 選考中、投稿期間終了 → 完了）
create or replace function private.advance_campaign_statuses()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.campaigns
     set status = 'screening'
   where status = 'recruiting' and apply_end_at <= now();

  update public.campaigns
     set status = 'posting_closed'
   where status = 'in_progress' and post_end_at <= now();
end;
$$;

revoke all on function private.advance_campaign_statuses() from public, anon, authenticated;

select cron.schedule(
  'advance-campaign-statuses',
  '5 * * * *',
  $$ select private.advance_campaign_statuses(); $$
);
