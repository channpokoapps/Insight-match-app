-- 0007_chat_sender_masking.sql
--
-- 問題：`public.messages` をそのまま SELECT させると、PR依頼者に投稿者の
--       `sender_id`（= creator_id）が渡ってしまう。案件をまたいだ名寄せが可能になり、
--       ADR-0005 の前提が崩れる（AGENTS.md R-5 違反）。
--
-- 対策：列レベルで `sender_id` を読めなくし、参照はマスク済みビューに限定する。

-- =============================================================================
-- messages の列単位の権限
--   Supabase の既定では authenticated に全列の権限が付いているため、
--   いったん剥がしてから必要な列だけ与え直す。
-- =============================================================================
revoke select, insert, update, delete on public.messages from anon, authenticated;

grant select (id, room_id, body, image_path, read_at, created_at)
  on public.messages to authenticated;

-- 送信時は自分の ID を書く必要があるため INSERT だけ sender_id を許可する。
-- 他人の ID を入れられないことは RLS ポリシー（sender_id = auth.uid()）が保証する。
grant insert (room_id, sender_id, body, image_path)
  on public.messages to authenticated;

grant update (read_at) on public.messages to authenticated;

-- =============================================================================
-- 参照用ビュー
--   誰が送ったかは「自分か / 相手か」だけが分かればよい。
--   security_invoker を付けない（= 定義者権限）ため、WHERE 句で参加者を絞る。
-- =============================================================================
create view public.v_chat_messages as
  select m.id,
         m.room_id,
         m.body,
         m.image_path,
         m.read_at,
         m.created_at,
         (m.sender_id = auth.uid())  as is_own,
         (m.sender_id = c.client_id) as sender_is_client,
         a.alias_no                  as counterpart_alias_no
  from public.messages m
  join public.chat_rooms r  on r.id = m.room_id
  join public.applications a on a.id = r.application_id
  join public.campaigns c    on c.id = a.campaign_id
  where a.creator_id = auth.uid() or c.client_id = auth.uid();

comment on view public.v_chat_messages is
  'チャット参照はこのビュー経由に限る。sender_id を射影しないこと（AGENTS.md R-5）。';

grant select on public.v_chat_messages to authenticated;

-- =============================================================================
-- Realtime について
--   postgres_changes は行全体を配信するため、`public.messages` を
--   supabase_realtime パブリケーションに追加すると sender_id が漏れる。
--   このマイグレーションでは意図的に追加しない。
--   リアルタイム配信の方式は OI-43 で確定させる。
-- =============================================================================
