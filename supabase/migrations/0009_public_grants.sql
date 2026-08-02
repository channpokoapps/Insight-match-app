-- 0009_public_grants.sql
-- public スキーマのテーブル権限を明示的に付与する。
--
-- 背景: 新しい Supabase イメージ（2026 時点）では、postgres ロールが作成した
-- テーブルに anon / authenticated への DML 権限が自動付与されなくなった
-- （pg_default_acl が SELECT/INSERT/UPDATE/DELETE を含まない）。
-- 0002〜0008 は自動付与を前提としていたため、RLS 以前にテーブル権限で
-- 全操作が拒否されてしまう。ここで明示的に付与し、行の可視性は従来どおり
-- RLS（0004 のデフォルト拒否 + 個別ポリシー）が担保する。
--
-- 非開示要件への影響（AGENTS.md R-1〜R-5）:
-- - private スキーマには一切付与しない（0001 の revoke を維持）。
-- - messages は **除外**。0007 の列単位 GRANT（sender_id を含まない）が正であり、
--   テーブル全体に SELECT を付与すると送信者の匿名性が壊れる。
-- - anon には付与しない（全ポリシーが to authenticated のため不要）。

set check_function_bodies = off;

grant usage on schema public to anon, authenticated;

-- マスタ（読み取りのみ。書き込みは service_role が行う）
grant select on public.genres,
                public.prefectures,
                public.cities,
                public.railway_lines,
                public.stations
  to authenticated;

-- ユーザー所有データ（行の絞り込みは RLS が行う）
grant select, insert, update, delete on
  public.profiles,
  public.creator_profiles,
  public.client_profiles,
  public.terms_agreements,
  public.device_tokens,
  public.campaigns,
  public.campaign_images,
  public.campaign_hashtags,
  public.applications,
  public.cancellation_requests,
  public.relaxation_proposals,
  public.post_submissions,
  public.chat_rooms,
  public.reports,
  public.notifications,
  public.favorites
  to authenticated;

-- 連携状態は参照のみ（書き込みは Edge Functions = service_role）
grant select on public.social_links to authenticated;

-- ビュー（v_applications_for_client / v_chat_messages は 0004 / 0007 で付与済み）
grant select on public.v_client_public to authenticated;

-- 注意: 今後 public にテーブルを追加するマイグレーションでは、
-- RLS ポリシーとあわせて必要な GRANT も同じファイル内に書くこと。
