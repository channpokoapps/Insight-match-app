-- 06_chat_masking.test.sql
-- チャットで投稿者の identity が PR依頼者に渡らないことを検証する（AGENTS.md R-5）。

begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

select ok(not has_column_privilege('authenticated', 'public.messages', 'sender_id', 'SELECT'),
          'authenticated は messages.sender_id を SELECT できない');
select ok(has_column_privilege('authenticated', 'public.messages', 'body', 'SELECT'),
          'authenticated は messages.body を SELECT できる');
select ok(has_column_privilege('authenticated', 'public.messages', 'sender_id', 'INSERT'),
          '送信時のみ sender_id を書き込める');

select hasnt_column('public', 'v_chat_messages', 'sender_id',
                    'v_chat_messages に sender_id が存在しない');
select has_column('public', 'v_chat_messages', 'is_own',
                  'v_chat_messages で自分の発言かどうかは判定できる');

-- messages が Realtime に公開されていないこと
select is(
  (select count(*)::int
   from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'messages'),
  0,
  'messages は Realtime に公開されていない（行全体が配信されるため）'
);

select * from finish();
rollback;
