-- TakaDe: getting the free Supabase project ready for 10,000 people (docs/adr/0033-ready-for-10k.md).
-- Run after every earlier file in this folder. Safe to run more than once. Paste into the
-- Supabase SQL editor and press Run.
--
-- 1. Rejoin a shared group after the phone's sharing sign-in is lost. Each phone keeps a
--    random secret per group in its Keychain; only its SHA-256 is stored here, on that
--    phone's own member row. If the sign-in can't be refreshed (the app was closed mid
--    refresh, for example) the phone gets a new guest sign-in and moves its old member row
--    over with the secret, instead of silently dropping out of every shared group.
-- 2. Indexes on the columns that point at an account, so deleting an account (and the
--    nightly removal of unused guest sign-ins) doesn't read whole tables once per person.
-- 3. Deleted accounts: "Delete account" removes the account at once (no soft delete). The
--    sign-in log Supabase keeps (auth.audit_log_entries) still names the email, so entries
--    older than 30 days are removed every night.

-- 1. Rejoin ----------------------------------------------------------------------------

alter table public.sync_member add column if not exists rejoin_hash text
  check (rejoin_hash is null or rejoin_hash ~ '^[0-9a-f]{64}$');

-- Members see who is in their groups, but not each other's rejoin hashes.
revoke select on public.sync_member from authenticated;
grant select (group_id, user_id, joined_at) on public.sync_member to authenticated;

-- Stores the hash of this phone's rejoin secret on its own member row. False when this
-- sign-in isn't in the group.
create or replace function public.set_sync_rejoin(p_group uuid, p_hash text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'sign-in required' using errcode = '28000';
  end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'hash not valid' using errcode = '22023';
  end if;
  update public.sync_member set rejoin_hash = p_hash
   where group_id = p_group and user_id = (select auth.uid());
  return found;
end;
$$;

-- Moves the member row whose secret matches to this sign-in. False when no row matches
-- (the group is gone, or the secret was never stored).
create or replace function public.rejoin_sync_group(p_group uuid, p_secret text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_old  uuid;
  v_hash text;
begin
  if v_user is null then
    raise exception 'sign-in required' using errcode = '28000';
  end if;
  if p_secret is null or length(p_secret) not between 20 and 128 then
    return false;
  end if;
  v_hash := encode(sha256(convert_to(p_secret, 'UTF8')), 'hex');
  select m.user_id into v_old from public.sync_member m
   where m.group_id = p_group and m.rejoin_hash = v_hash
   limit 1;
  if v_old is null then
    return false;
  end if;
  if v_old = v_user then
    return true;
  end if;
  if exists (select 1 from public.sync_member m where m.group_id = p_group and m.user_id = v_user) then
    -- Already back in through a new link: keep that row, take the secret, drop the old row.
    delete from public.sync_member where group_id = p_group and user_id = v_old;
    update public.sync_member set rejoin_hash = v_hash where group_id = p_group and user_id = v_user;
  else
    update public.sync_member set user_id = v_user, rejoin_hash = v_hash
     where group_id = p_group and user_id = v_old;
  end if;
  return true;
end;
$$;

revoke all on function public.set_sync_rejoin(uuid, text) from public, anon;
grant execute on function public.set_sync_rejoin(uuid, text) to authenticated;
revoke all on function public.rejoin_sync_group(uuid, text) from public, anon;
grant execute on function public.rejoin_sync_group(uuid, text) to authenticated;

-- 2. Indexes for account deletion ---------------------------------------------------------

create index if not exists sync_change_author_idx on public.sync_change (author) where author is not null;
create index if not exists sync_receipt_author_idx on public.sync_receipt (author) where author is not null;
create index if not exists friend_message_from_idx on public.friend_message (from_user);
create index if not exists friend_block_blocked_idx on public.friend_block (blocked);

-- 3. Deleted accounts ------------------------------------------------------------------

-- Supabase's sign-in log keeps emails. Nothing in TakaDe reads it, so 30 days is enough.
create or replace function public.auth_log_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from auth.audit_log_entries where created_at < now() - interval '30 days';
exception
  when insufficient_privilege or undefined_table then
    raise warning 'auth_log_cleanup: auth.audit_log_entries not reachable (%)', sqlerrm;
end;
$$;
revoke all on function public.auth_log_cleanup() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'takade-auth-log-cleanup';
select cron.schedule('takade-auth-log-cleanup', '43 21 * * *', 'select public.auth_log_cleanup()');
select public.auth_log_cleanup();
