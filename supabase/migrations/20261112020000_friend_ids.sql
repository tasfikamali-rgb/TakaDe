-- TakaDe IDs: add a friend who has a TakaDe account by their ID or QR code
-- (docs/adr/0021-takade-ids.md). Run after 20261112000000_shared_groups.sql. Safe to re-run.
--
-- What the server keeps per account: a random 8-character ID and a public key. No phone
-- numbers, no contacts, no names. An invite to a group is sealed on the sender's phone
-- with the friend's public key, so the server stores it without being able to read it,
-- and it is deleted when the friend joins or declines, or after 7 days.

create table if not exists public.friend_id (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  -- Crockford base32, 8 characters (40 bits): shown as TKD-XXXX-XXXX.
  code       text not null unique check (code ~ '^[0-9A-HJKMNP-TV-Z]{8}$'),
  -- X25519 public key, base64url without padding (43 characters).
  public_key text not null check (length(public_key) between 40 and 64),
  updated_at timestamptz not null default now()
);

create table if not exists public.friend_invite (
  id         uuid primary key default gen_random_uuid(),
  to_user    uuid not null references auth.users (id) on delete cascade,
  from_user  uuid references auth.users (id) on delete cascade,
  sealed     text not null check (length(sealed) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists friend_invite_to_idx on public.friend_invite (to_user, created_at);
create index if not exists friend_invite_from_idx on public.friend_invite (from_user, created_at);

-- Every ID lookup, kept for a day, so nobody can try IDs one after another.
create table if not exists public.friend_lookup (
  user_id uuid not null references auth.users (id) on delete cascade,
  at      timestamptz not null default now()
);
create index if not exists friend_lookup_user_idx on public.friend_lookup (user_id, at);

-- Only real accounts get an ID. The guest sign-ins used for shared groups don't.
create or replace function public.is_account()
returns boolean
language sql stable set search_path = ''
as $$
  select auth.uid() is not null and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false;
$$;

alter table public.friend_id     enable row level security;
alter table public.friend_invite enable row level security;
alter table public.friend_lookup enable row level security;

revoke all on public.friend_id, public.friend_invite, public.friend_lookup from anon, authenticated;
-- Your own ID only. Anyone else's is reached through find_friend, one at a time.
grant select, insert, update, delete on public.friend_id to authenticated;
grant select, delete on public.friend_invite to authenticated;

drop policy if exists "own id" on public.friend_id;
create policy "own id" on public.friend_id
  for all to authenticated
  using (user_id = auth.uid() and public.is_account())
  with check (user_id = auth.uid() and public.is_account());

drop policy if exists "own invites" on public.friend_invite;
create policy "own invites" on public.friend_invite
  for select to authenticated using (to_user = auth.uid() and public.is_account());
drop policy if exists "remove own invites" on public.friend_invite;
create policy "remove own invites" on public.friend_invite
  for delete to authenticated using (to_user = auth.uid() and public.is_account());

-- Counts a lookup and refuses the 31st in an hour.
create or replace function public.count_friend_lookup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_account() then
    raise exception 'account required' using errcode = '28000';
  end if;
  if (select count(*) from public.friend_lookup
       where user_id = auth.uid() and at > now() - interval '1 hour') >= 30 then
    raise exception 'too many lookups' using errcode = 'TK429';
  end if;
  insert into public.friend_lookup (user_id) values (auth.uid());
end;
$$;
revoke all on function public.count_friend_lookup() from public, anon, authenticated;

-- The public key for an ID, or no row. Says nothing else about the account.
create or replace function public.find_friend(p_code text)
returns table (public_key text)
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.count_friend_lookup();
  return query select f.public_key from public.friend_id f where f.code = upper(p_code);
end;
$$;

-- Leaves a sealed invite for the account with this ID.
create or replace function public.send_friend_invite(p_code text, p_sealed text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_to uuid;
begin
  perform public.count_friend_lookup();
  if p_sealed is null or length(p_sealed) not between 1 and 4000 then
    raise exception 'invite not valid' using errcode = '22023';
  end if;
  select f.user_id into v_to from public.friend_id f where f.code = upper(p_code);
  if v_to is null then
    raise exception 'no such id' using errcode = 'P0002';
  end if;
  -- Spam limits: 50 invites a day from one account, 100 waiting for one account.
  if (select count(*) from public.friend_invite
       where from_user = auth.uid() and created_at > now() - interval '1 day') >= 50
     or (select count(*) from public.friend_invite where to_user = v_to) >= 100 then
    raise exception 'too many invites' using errcode = 'TK429';
  end if;
  insert into public.friend_invite (to_user, from_user, sealed) values (v_to, auth.uid(), p_sealed);
end;
$$;

revoke all on function public.find_friend(text) from public, anon;
grant execute on function public.find_friend(text) to authenticated;
revoke all on function public.send_friend_invite(text, text) from public, anon;
grant execute on function public.send_friend_invite(text, text) to authenticated;

-- Daily: invites older than 7 days and lookups older than a day.
create or replace function public.friend_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.friend_invite where created_at < now() - interval '7 days';
  delete from public.friend_lookup where at < now() - interval '1 day';
end;
$$;
revoke all on function public.friend_cleanup() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'takade-friend-cleanup';
select cron.schedule('takade-friend-cleanup', '23 21 * * *', 'select public.friend_cleanup()');
