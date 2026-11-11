-- TakaDe shared groups: an encrypted relay (docs/adr/0018-shared-groups.md).
--
-- Phones encrypt every change with the group's key before uploading it. The key is made on
-- the phone that shares the group, travels only inside invite links (after the "#") and is
-- kept in each phone's Keychain. This database stores ciphertext plus the routing data it
-- needs: group ids, which accounts are members, invite hashes, sizes and times. It never
-- stores names, amounts, notes or receipts in readable form.
--
-- Members are Supabase users. A phone that isn't signed in to a TakaDe account uses an
-- anonymous Supabase user, so friends can join without making an account.
-- Run once in the SQL editor (or `supabase db push`). Safe to re-run.

create table if not exists public.sync_group (
  id          uuid primary key,
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  -- Updated on every upload; groups idle for 90 days are removed from the server (below).
  last_change_at timestamptz not null default now()
);

create table if not exists public.sync_member (
  group_id   uuid not null references public.sync_group (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists sync_member_user_idx on public.sync_member (user_id);

-- Only the SHA-256 of an invite token is stored, so a database leak can't be used to join.
create table if not exists public.sync_invite (
  token_hash  text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  group_id    uuid not null references public.sync_group (id) on delete cascade,
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null check (expires_at <= created_at + interval '30 days'),
  revoked_at  timestamptz
);
create index if not exists sync_invite_group_idx on public.sync_invite (group_id);

-- Append-only. `seq` is the order every phone applies changes in; `change_id` makes a
-- retried upload a no-op.
create table if not exists public.sync_change (
  seq         bigint generated always as identity primary key,
  change_id   uuid not null unique,
  group_id    uuid not null references public.sync_group (id) on delete cascade,
  author      uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  ciphertext  text not null check (length(ciphertext) between 1 and 262144)
);
create index if not exists sync_change_group_seq_idx on public.sync_change (group_id, seq);

create or replace function public.sync_change_touch_group()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.sync_group set last_change_at = now() where id = new.group_id;
  return new;
end;
$$;
drop trigger if exists sync_change_touch_group on public.sync_change;
create trigger sync_change_touch_group after insert on public.sync_change
  for each row execute function public.sync_change_touch_group();

-- Membership check used by every policy. SECURITY DEFINER so policies on sync_member don't
-- recurse into themselves.
create or replace function public.is_sync_member(g uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.sync_member m where m.group_id = g and m.user_id = (select auth.uid())
  );
$$;

-- Whoever creates a group is its first member.
create or replace function public.sync_group_add_creator()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.created_by is not null then
    insert into public.sync_member (group_id, user_id) values (new.id, new.created_by)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists sync_group_add_creator on public.sync_group;
create trigger sync_group_add_creator after insert on public.sync_group
  for each row execute function public.sync_group_add_creator();

-- When the last member leaves (or their user is deleted), the group's ciphertext goes too.
create or replace function public.sync_member_drop_empty_group()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.sync_group g
   where g.id = old.group_id
     and not exists (select 1 from public.sync_member m where m.group_id = old.group_id);
  return old;
end;
$$;
drop trigger if exists sync_member_drop_empty_group on public.sync_member;
create trigger sync_member_drop_empty_group after delete on public.sync_member
  for each row execute function public.sync_member_drop_empty_group();

-- Joining with an invite token: the only way to become a member of someone else's group.
create or replace function public.join_sync_group(p_token text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_group uuid;
begin
  if v_user is null then
    raise exception 'sign-in required' using errcode = '28000';
  end if;
  if p_token is null or length(p_token) not between 20 and 128 then
    raise exception 'invite not valid' using errcode = 'P0002';
  end if;
  select i.group_id into v_group
    from public.sync_invite i
   where i.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     and i.revoked_at is null
     and i.expires_at > now();
  if v_group is null then
    raise exception 'invite not valid' using errcode = 'P0002';
  end if;
  insert into public.sync_member (group_id, user_id) values (v_group, v_user)
  on conflict do nothing;
  return v_group;
end;
$$;

revoke all on function public.join_sync_group(text) from public, anon;
grant execute on function public.join_sync_group(text) to authenticated;
revoke all on function public.is_sync_member(uuid) from public, anon;
grant execute on function public.is_sync_member(uuid) to authenticated;

-- Row-level security: only a group's members can see or add anything in it.
alter table public.sync_group  enable row level security;
alter table public.sync_member enable row level security;
alter table public.sync_invite enable row level security;
alter table public.sync_change enable row level security;

revoke all on public.sync_group, public.sync_member, public.sync_invite, public.sync_change from anon;
grant select, insert on public.sync_group to authenticated;
grant select, delete on public.sync_member to authenticated;
grant select, insert, update (revoked_at) on public.sync_invite to authenticated;
grant select, insert on public.sync_change to authenticated;

drop policy if exists "members read group" on public.sync_group;
create policy "members read group" on public.sync_group
  for select to authenticated using (public.is_sync_member(id));
drop policy if exists "create own group" on public.sync_group;
create policy "create own group" on public.sync_group
  for insert to authenticated with check (created_by = (select auth.uid()));

drop policy if exists "members read members" on public.sync_member;
create policy "members read members" on public.sync_member
  for select to authenticated using (public.is_sync_member(group_id));
drop policy if exists "leave a group" on public.sync_member;
create policy "leave a group" on public.sync_member
  for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "members read invites" on public.sync_invite;
create policy "members read invites" on public.sync_invite
  for select to authenticated using (public.is_sync_member(group_id));
drop policy if exists "members create invites" on public.sync_invite;
create policy "members create invites" on public.sync_invite
  for insert to authenticated
  with check (public.is_sync_member(group_id) and created_by = (select auth.uid()));
drop policy if exists "members revoke invites" on public.sync_invite;
create policy "members revoke invites" on public.sync_invite
  for update to authenticated
  using (public.is_sync_member(group_id)) with check (public.is_sync_member(group_id));

drop policy if exists "members read changes" on public.sync_change;
create policy "members read changes" on public.sync_change
  for select to authenticated using (public.is_sync_member(group_id));
drop policy if exists "members add changes" on public.sync_change;
create policy "members add changes" on public.sync_change
  for insert to authenticated
  with check (public.is_sync_member(group_id) and author = (select auth.uid()));

-- Keeping the free plan's 500 MB in reach (docs/adr/0018-shared-groups.md, "Storage").
-- Nightly: drop groups with no change for 90 days (the phones keep everything and can share
-- again), invites that expired over a week ago, and guest sign-ins that belong to no group.
create extension if not exists pg_cron;

create or replace function public.sync_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.sync_group where last_change_at < now() - interval '90 days';
  delete from public.sync_invite where expires_at < now() - interval '7 days';
  delete from auth.users u
   where u.is_anonymous
     and u.created_at < now() - interval '7 days'
     and not exists (select 1 from public.sync_member m where m.user_id = u.id);
end;
$$;
revoke all on function public.sync_cleanup() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'takade-sync-cleanup';
select cron.schedule('takade-sync-cleanup', '17 21 * * *', 'select public.sync_cleanup()');

-- How much space sharing uses. Run in the SQL editor: select * from public.sync_storage();
create or replace function public.sync_storage()
returns table (what text, size text, row_count bigint)
language sql stable security definer set search_path = ''
as $$
  select 'whole database', pg_size_pretty(pg_database_size(current_database())), null::bigint
  union all
  select 'shared changes', pg_size_pretty(pg_total_relation_size('public.sync_change')), (select count(*) from public.sync_change)
  union all
  select 'shared groups', pg_size_pretty(pg_total_relation_size('public.sync_group')), (select count(*) from public.sync_group)
  union all
  select 'guest sign-ins', null, (select count(*) from auth.users where is_anonymous);
$$;
revoke all on function public.sync_storage() from public, anon, authenticated;
