-- Social tab: messages between friends (docs/adr/0024-friend-messages.md).
-- Run after 20261112020000_friend_ids.sql. Safe to re-run.
--
-- A message is sealed on the sender's phone to the friend's public key (HPKE, the same
-- keys as TakaDe IDs), so the server stores it without being able to read it. The
-- friend's phone collects it and deletes it here; anything not collected in 30 days is
-- deleted. No names, phone numbers or message text are stored on the server.
--
-- Every value from the app reaches SQL as a function parameter or through PostgREST's own
-- parameter binding. Nothing here builds SQL from text (no EXECUTE), so there is nothing
-- to inject into.

create table if not exists public.friend_message (
  id         uuid primary key default gen_random_uuid(),
  to_user    uuid not null references auth.users (id) on delete cascade,
  from_user  uuid not null references auth.users (id) on delete cascade,
  sealed     text not null check (length(sealed) between 1 and 8000),
  created_at timestamptz not null default now()
);
create index if not exists friend_message_to_idx on public.friend_message (to_user, created_at);

-- Who blocked whom, so a blocked person's messages are dropped. Only reachable through
-- block_friend / unblock_friend.
create table if not exists public.friend_block (
  blocker uuid not null references auth.users (id) on delete cascade,
  blocked uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

-- Every send, kept for a day, for the spam limits (collected messages are deleted, so the
-- message table alone can't count them).
create table if not exists public.friend_message_log (
  user_id uuid not null references auth.users (id) on delete cascade,
  at      timestamptz not null default now()
);
create index if not exists friend_message_log_user_idx on public.friend_message_log (user_id, at);

alter table public.friend_message     enable row level security;
alter table public.friend_block       enable row level security;
alter table public.friend_message_log enable row level security;

revoke all on public.friend_message, public.friend_block, public.friend_message_log from anon, authenticated;
-- Read and delete your own messages. Sending goes through send_friend_message only.
grant select, delete on public.friend_message to authenticated;

drop policy if exists "own messages" on public.friend_message;
create policy "own messages" on public.friend_message
  for select to authenticated using (to_user = auth.uid() and public.is_account());
drop policy if exists "remove own messages" on public.friend_message;
create policy "remove own messages" on public.friend_message
  for delete to authenticated using (to_user = auth.uid() and public.is_account());

-- Leaves a sealed message for the account with this ID. Returns false when no account has
-- the ID (and counts that as a lookup, so IDs can't be guessed by sending). A blocked
-- sender gets true and the message is dropped, so blocking can't be detected.
create or replace function public.send_friend_message(p_code text, p_sealed text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_to uuid;
begin
  if not public.is_account() then
    raise exception 'account required' using errcode = '28000';
  end if;
  if p_sealed is null or length(p_sealed) not between 1 and 8000 then
    raise exception 'message not valid' using errcode = '22023';
  end if;
  -- Spam limits: 300 messages an hour and 2000 a day from one account.
  if (select count(*) from public.friend_message_log
       where user_id = auth.uid() and at > now() - interval '1 hour') >= 300
     or (select count(*) from public.friend_message_log
       where user_id = auth.uid() and at > now() - interval '1 day') >= 2000 then
    raise exception 'too many messages' using errcode = 'TK429';
  end if;
  insert into public.friend_message_log (user_id) values (auth.uid());

  select f.user_id into v_to from public.friend_id f where f.code = upper(p_code);
  if v_to is null then
    perform public.count_friend_lookup();
    return false;
  end if;
  if v_to = auth.uid() then
    raise exception 'that is you' using errcode = '22023';
  end if;
  if exists (select 1 from public.friend_block b where b.blocker = v_to and b.blocked = auth.uid()) then
    return true;
  end if;
  -- At most 500 messages waiting for one account.
  if (select count(*) from public.friend_message where to_user = v_to) >= 500 then
    raise exception 'too many waiting' using errcode = 'TK429';
  end if;
  insert into public.friend_message (to_user, from_user, sealed) values (v_to, auth.uid(), p_sealed);
  return true;
end;
$$;

-- Messages waiting for you, with the sender's current ID and public key so your phone can
-- check the message really came from that key. Says nothing else about the sender.
create or replace function public.friend_inbox()
returns table (id uuid, sealed text, created_at timestamptz, from_code text, from_key text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_account() then
    raise exception 'account required' using errcode = '28000';
  end if;
  return query
    select m.id, m.sealed, m.created_at, f.code, f.public_key
    from public.friend_message m
    left join public.friend_id f on f.user_id = m.from_user
    where m.to_user = auth.uid()
    order by m.created_at
    limit 100;
end;
$$;

create or replace function public.block_friend(p_code text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_blocked uuid;
begin
  perform public.count_friend_lookup();
  select f.user_id into v_blocked from public.friend_id f where f.code = upper(p_code);
  if v_blocked is null or v_blocked = auth.uid() then return; end if;
  insert into public.friend_block (blocker, blocked) values (auth.uid(), v_blocked) on conflict do nothing;
  -- Anything they already sent goes too.
  delete from public.friend_message where to_user = auth.uid() and from_user = v_blocked;
end;
$$;

create or replace function public.unblock_friend(p_code text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_blocked uuid;
begin
  perform public.count_friend_lookup();
  select f.user_id into v_blocked from public.friend_id f where f.code = upper(p_code);
  if v_blocked is null then return; end if;
  delete from public.friend_block where blocker = auth.uid() and blocked = v_blocked;
end;
$$;

revoke all on function public.send_friend_message(text, text) from public, anon;
grant execute on function public.send_friend_message(text, text) to authenticated;
revoke all on function public.friend_inbox() from public, anon;
grant execute on function public.friend_inbox() to authenticated;
revoke all on function public.block_friend(text) from public, anon;
grant execute on function public.block_friend(text) to authenticated;
revoke all on function public.unblock_friend(text) from public, anon;
grant execute on function public.unblock_friend(text) to authenticated;

-- New messages reach an open app at once through Supabase Realtime. Realtime applies the
-- "own messages" policy above, so a phone only hears about its own messages, and the app
-- treats the event only as a nudge to fetch through friend_inbox.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'friend_message') then
    alter publication supabase_realtime add table public.friend_message;
  end if;
end;
$$;

-- Daily: messages nobody collected in 30 days, and the send log after a day.
create or replace function public.friend_message_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.friend_message where created_at < now() - interval '30 days';
  delete from public.friend_message_log where at < now() - interval '1 day';
end;
$$;
revoke all on function public.friend_message_cleanup() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'takade-message-cleanup';
select cron.schedule('takade-message-cleanup', '37 21 * * *', 'select public.friend_message_cleanup()');
