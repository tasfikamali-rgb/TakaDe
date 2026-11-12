-- Security and speed review of the shared-group relay and TakaDe IDs (docs/adr/0024-security-review.md).
-- Run after 20261112020000_friend_ids.sql. Safe to re-run.
--
-- 1. Exact privileges. Supabase gives the API roles every privilege on new public tables by
--    default, so the earlier "grant select, insert" lines added nothing on their own. Here the
--    app's sign-ins get exactly the columns the app sends, and the server sets every time
--    and author column itself.
-- 2. Upload limits per sign-in, so one phone (or a script with the app's public key) can't
--    fill the free plan's 500 MB.
-- 3. Faster rules: the "is this person in the group" check runs once per request instead of
--    once per row, and an upload touches its group once instead of once per change.

-- 1. Privileges ------------------------------------------------------------------------

revoke all on public.sync_group, public.sync_member, public.sync_invite, public.sync_change, public.sync_receipt
  from public, anon, authenticated;

grant select on public.sync_group to authenticated;
grant insert (id) on public.sync_group to authenticated;

grant select, delete on public.sync_member to authenticated;

grant select on public.sync_invite to authenticated;
grant insert (token_hash, group_id, expires_at) on public.sync_invite to authenticated;
grant update (revoked_at) on public.sync_invite to authenticated;

grant select on public.sync_change to authenticated;
grant insert (change_id, group_id, ciphertext) on public.sync_change to authenticated;

grant select on public.sync_receipt to authenticated;
grant insert (id, group_id, ciphertext) on public.sync_receipt to authenticated;

-- A link that was stopped stays stopped.
drop policy if exists "members revoke invites" on public.sync_invite;
create policy "members revoke invites" on public.sync_invite
  for update to authenticated
  using (public.is_sync_member(group_id))
  with check (public.is_sync_member(group_id) and revoked_at is not null);

-- The friend tables already started from "revoke all"; the ID row's time is the server's too.
revoke all on public.friend_id from authenticated;
grant select, delete on public.friend_id to authenticated;
grant insert (user_id, code, public_key) on public.friend_id to authenticated;
grant update (code, public_key) on public.friend_id to authenticated;

create or replace function public.friend_id_touch()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists friend_id_touch on public.friend_id;
create trigger friend_id_touch before insert or update on public.friend_id
  for each row execute function public.friend_id_touch();

-- 2. Upload limits ---------------------------------------------------------------------

-- Bytes and rows each sign-in uploaded, per hour. Only the server reads or writes it.
create table if not exists public.sync_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  hour    timestamptz not null,
  rows    integer not null default 0,
  bytes   bigint not null default 0,
  primary key (user_id, hour)
);
alter table public.sync_usage enable row level security;
revoke all on public.sync_usage from public, anon, authenticated;

create index if not exists sync_group_created_by_idx on public.sync_group (created_by, created_at);
create index if not exists sync_invite_created_by_idx on public.sync_invite (created_by, created_at);

-- Counts one upload (a whole batch at once) and refuses it past the limits. The first share
-- of a big group with a year of meals and a few hundred receipt photos fits easily.
create or replace function public.sync_count_upload()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_rows  integer;
  v_bytes bigint;
  v_hour_rows  integer;
  v_hour_bytes bigint;
  v_day_bytes  bigint;
begin
  -- The SQL editor and nightly cleanup have no sign-in and aren't limited.
  if v_user is null then
    return null;
  end if;
  select count(*), coalesce(sum(octet_length(a.ciphertext)), 0) into v_rows, v_bytes from added a;
  insert into public.sync_usage as u (user_id, hour, rows, bytes)
  values (v_user, date_trunc('hour', now()), v_rows, v_bytes)
  on conflict (user_id, hour) do update set rows = u.rows + excluded.rows, bytes = u.bytes + excluded.bytes
  returning u.rows, u.bytes into v_hour_rows, v_hour_bytes;
  select coalesce(sum(u.bytes), 0) into v_day_bytes
    from public.sync_usage u
   where u.user_id = v_user and u.hour > now() - interval '24 hours';
  if v_hour_rows > 20000 or v_hour_bytes > 50 * 1024 * 1024 or v_day_bytes > 100 * 1024 * 1024 then
    raise exception 'too many uploads' using errcode = 'TK429';
  end if;
  return null;
end;
$$;
revoke all on function public.sync_count_upload() from public, anon, authenticated;

drop trigger if exists sync_change_count_upload on public.sync_change;
create trigger sync_change_count_upload after insert on public.sync_change
  referencing new table as added
  for each statement execute function public.sync_count_upload();
drop trigger if exists sync_receipt_count_upload on public.sync_receipt;
create trigger sync_receipt_count_upload after insert on public.sync_receipt
  referencing new table as added
  for each statement execute function public.sync_count_upload();

-- New groups and invite links: 50 groups and 200 links a day per sign-in.
create or replace function public.sync_count_new()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return null;
  end if;
  if tg_table_name = 'sync_group' then
    if (select count(*) from public.sync_group g
         where g.created_by = v_user and g.created_at > now() - interval '1 day') > 50 then
      raise exception 'too many groups' using errcode = 'TK429';
    end if;
  elsif tg_table_name = 'sync_invite' then
    if (select count(*) from public.sync_invite i
         where i.created_by = v_user and i.created_at > now() - interval '1 day') > 200 then
      raise exception 'too many invite links' using errcode = 'TK429';
    end if;
  end if;
  return null;
end;
$$;
revoke all on function public.sync_count_new() from public, anon, authenticated;

drop trigger if exists sync_group_count_new on public.sync_group;
create trigger sync_group_count_new after insert on public.sync_group
  for each statement execute function public.sync_count_new();
drop trigger if exists sync_invite_count_new on public.sync_invite;
create trigger sync_invite_count_new after insert on public.sync_invite
  for each statement execute function public.sync_count_new();

-- Nightly cleanup, now also dropping usage counts older than two days.
create or replace function public.sync_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.sync_group where last_change_at < now() - interval '90 days';
  delete from public.sync_invite where expires_at < now() - interval '7 days';
  delete from public.sync_usage where hour < now() - interval '2 days';
  delete from auth.users u
   where u.is_anonymous
     and u.created_at < now() - interval '7 days'
     and not exists (select 1 from public.sync_member m where m.user_id = u.id);
end;
$$;
revoke all on function public.sync_cleanup() from public, anon, authenticated;

-- 3. Speed -----------------------------------------------------------------------------

-- Every group this sign-in is in, worked out once per request by the rules below.
create or replace function public.my_sync_groups()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select m.group_id from public.sync_member m where m.user_id = (select auth.uid());
$$;
revoke all on function public.my_sync_groups() from public, anon;
grant execute on function public.my_sync_groups() to authenticated;

drop policy if exists "members read group" on public.sync_group;
create policy "members read group" on public.sync_group
  for select to authenticated using (id in (select public.my_sync_groups()));
drop policy if exists "members read members" on public.sync_member;
create policy "members read members" on public.sync_member
  for select to authenticated using (group_id in (select public.my_sync_groups()));
drop policy if exists "members read invites" on public.sync_invite;
create policy "members read invites" on public.sync_invite
  for select to authenticated using (group_id in (select public.my_sync_groups()));
drop policy if exists "members read changes" on public.sync_change;
create policy "members read changes" on public.sync_change
  for select to authenticated using (group_id in (select public.my_sync_groups()));
drop policy if exists "members read receipts" on public.sync_receipt;
create policy "members read receipts" on public.sync_receipt
  for select to authenticated using (group_id in (select public.my_sync_groups()));

-- One "last change" update per upload, not one per change in it.
create or replace function public.sync_touch_groups()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.sync_group g set last_change_at = now()
   where g.id in (select distinct a.group_id from added a);
  return null;
end;
$$;
revoke all on function public.sync_touch_groups() from public, anon, authenticated;

drop trigger if exists sync_change_touch_group on public.sync_change;
create trigger sync_change_touch_group after insert on public.sync_change
  referencing new table as added
  for each statement execute function public.sync_touch_groups();
drop trigger if exists sync_receipt_touch_group on public.sync_receipt;
create trigger sync_receipt_touch_group after insert on public.sync_receipt
  referencing new table as added
  for each statement execute function public.sync_touch_groups();

-- Friend rules: read the sign-in once per request.
drop policy if exists "own id" on public.friend_id;
create policy "own id" on public.friend_id
  for all to authenticated
  using (user_id = (select auth.uid()) and (select public.is_account()))
  with check (user_id = (select auth.uid()) and (select public.is_account()));
drop policy if exists "own invites" on public.friend_invite;
create policy "own invites" on public.friend_invite
  for select to authenticated using (to_user = (select auth.uid()) and (select public.is_account()));
drop policy if exists "remove own invites" on public.friend_invite;
create policy "remove own invites" on public.friend_invite
  for delete to authenticated using (to_user = (select auth.uid()) and (select public.is_account()));
