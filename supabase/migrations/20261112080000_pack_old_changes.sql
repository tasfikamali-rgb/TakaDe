-- TakaDe: pack a shared group's older changes into one bundle (docs/adr/0034-packed-changes-and-backups.md).
-- Run after every earlier file in this folder. Safe to run more than once. Paste into the
-- Supabase SQL editor and press Run.
--
-- `sync_change` keeps one sealed row per change, forever, so a new member's phone can build
-- the group from row one. Each row also carries ids, times and index entries, and each is
-- compressed on its own, so a busy group takes far more space than its data needs.
--
-- Now a member's phone that is fully up to date sometimes packs the group: it seals the
-- group's current state (the group, every expense, payment and meal count) into one
-- compressed bundle with the group's key, uploads it, and the server deletes the rows the
-- bundle covers. The server still sees only ciphertext.
--
-- A phone whose place in the group is before the bundle (a new member, or a phone that was
-- away) reads the bundle first, then the rows after it.
--
-- Rows from the last 10 minutes are never packed: an upload in progress might not be visible
-- yet, and packing it would lose it for everyone else.

create table if not exists public.sync_bundle (
  group_id     uuid primary key references public.sync_group (id) on delete cascade,
  id           uuid not null,
  -- The bundle holds the group as it was after every change up to this one.
  through_seq  bigint not null check (through_seq > 0),
  author       uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  ciphertext   text not null check (length(ciphertext) between 1 and 8388608)
);
create index if not exists sync_bundle_author_idx on public.sync_bundle (author) where author is not null;

alter table public.sync_bundle enable row level security;
revoke all on public.sync_bundle from public, anon, authenticated;
grant select (group_id, id, through_seq, created_at, ciphertext) on public.sync_bundle to authenticated;

drop policy if exists "members read bundles" on public.sync_bundle;
create policy "members read bundles" on public.sync_bundle
  for select to authenticated using (group_id in (select public.my_sync_groups()));

-- Where a pack could end now, and how many rows it would remove. Phones ask once a day per
-- group and pack only when it's worth it.
create or replace function public.sync_pack_point(p_group uuid)
returns table (through_seq bigint, packable bigint, packed_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_through bigint;
  v_after bigint;
begin
  if not exists (select 1 from public.sync_member m where m.group_id = p_group and m.user_id = (select auth.uid())) then
    raise exception 'not a member' using errcode = '42501';
  end if;
  select max(c.seq) into v_through
    from public.sync_change c
   where c.group_id = p_group and c.created_at < now() - interval '10 minutes';
  select b.through_seq into v_after from public.sync_bundle b where b.group_id = p_group;
  return query
    select v_through,
           (select count(*) from public.sync_change c
             where c.group_id = p_group and c.seq <= coalesce(v_through, 0)),
           (select b.created_at from public.sync_bundle b where b.group_id = p_group);
end;
$$;
revoke all on function public.sync_pack_point(uuid) from public, anon;
grant execute on function public.sync_pack_point(uuid) to authenticated;

-- Stores the bundle and deletes the rows it covers, in one transaction. False (nothing
-- changed) when the pack is stale, too early or not needed.
create or replace function public.pack_sync_group(p_group uuid, p_id uuid, p_through bigint, p_ciphertext text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_limit bigint;
  v_old public.sync_bundle%rowtype;
begin
  if v_user is null
     or not exists (select 1 from public.sync_member m where m.group_id = p_group and m.user_id = v_user) then
    raise exception 'not a member' using errcode = '42501';
  end if;
  if p_id is null or p_through is null or p_ciphertext is null
     or length(p_ciphertext) not between 1 and 8388608 then
    raise exception 'bad bundle' using errcode = '22023';
  end if;
  -- One pack at a time per group.
  perform 1 from public.sync_group g where g.id = p_group for update;
  select * into v_old from public.sync_bundle b where b.group_id = p_group;
  -- At most one pack per group every 6 hours.
  if found and v_old.created_at > now() - interval '6 hours' then
    return false;
  end if;
  select max(c.seq) into v_limit
    from public.sync_change c
   where c.group_id = p_group and c.created_at < now() - interval '10 minutes';
  if v_limit is null or p_through > v_limit or p_through <= coalesce(v_old.through_seq, 0) then
    return false;
  end if;
  insert into public.sync_bundle (group_id, id, through_seq, author, created_at, ciphertext)
  values (p_group, p_id, p_through, v_user, now(), p_ciphertext)
  on conflict (group_id) do update
    set id = excluded.id, through_seq = excluded.through_seq, author = excluded.author,
        created_at = excluded.created_at, ciphertext = excluded.ciphertext;
  delete from public.sync_change c where c.group_id = p_group and c.seq <= p_through;
  return true;
end;
$$;
revoke all on function public.pack_sync_group(uuid, uuid, bigint, text) from public, anon;
grant execute on function public.pack_sync_group(uuid, uuid, bigint, text) to authenticated;

-- Space used, now with bundles.
create or replace function public.sync_storage()
returns table (what text, size text, row_count bigint)
language sql stable security definer set search_path = ''
as $$
  select 'whole database', pg_size_pretty(pg_database_size(current_database())), null::bigint
  union all
  select 'shared changes', pg_size_pretty(pg_total_relation_size('public.sync_change')), (select count(*) from public.sync_change)
  union all
  select 'packed bundles', pg_size_pretty(pg_total_relation_size('public.sync_bundle')), (select count(*) from public.sync_bundle)
  union all
  select 'receipt photos', pg_size_pretty(pg_total_relation_size('public.sync_receipt')), (select count(*) from public.sync_receipt)
  union all
  select 'shared groups', pg_size_pretty(pg_total_relation_size('public.sync_group')), (select count(*) from public.sync_group)
  union all
  select 'guest sign-ins', null, (select count(*) from auth.users where is_anonymous);
$$;
revoke all on function public.sync_storage() from public, anon, authenticated;
