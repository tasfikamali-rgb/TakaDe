-- Receipt photos for shared groups (docs/adr/0020-receipt-photos.md). Run after
-- 20261112000000_shared_groups.sql. Safe to re-run.
--
-- Each photo is a small grayscale JPEG (usually 60 to 150 KB), encrypted on the phone with
-- the group's key. It lives in this table rather than in Supabase Storage so it goes away
-- with its group: the 90-day idle cleanup deletes the group and the photos cascade.

create table if not exists public.sync_receipt (
  id          uuid primary key,
  group_id    uuid not null references public.sync_group (id) on delete cascade,
  author      uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  ciphertext  text not null check (length(ciphertext) between 1 and 320000)
);
create index if not exists sync_receipt_group_idx on public.sync_receipt (group_id);

alter table public.sync_receipt enable row level security;
revoke all on public.sync_receipt from anon;
grant select, insert on public.sync_receipt to authenticated;

drop policy if exists "members read receipts" on public.sync_receipt;
create policy "members read receipts" on public.sync_receipt
  for select to authenticated using (public.is_sync_member(group_id));
drop policy if exists "members add receipts" on public.sync_receipt;
create policy "members add receipts" on public.sync_receipt
  for insert to authenticated
  with check (public.is_sync_member(group_id) and author = (select auth.uid()));

-- A new photo counts as activity, so a group being used isn't cleaned up.
drop trigger if exists sync_receipt_touch_group on public.sync_receipt;
create trigger sync_receipt_touch_group after insert on public.sync_receipt
  for each row execute function public.sync_change_touch_group();

-- The size check, now with photos.
create or replace function public.sync_storage()
returns table (what text, size text, row_count bigint)
language sql stable security definer set search_path = ''
as $$
  select 'whole database', pg_size_pretty(pg_database_size(current_database())), null::bigint
  union all
  select 'shared changes', pg_size_pretty(pg_total_relation_size('public.sync_change')), (select count(*) from public.sync_change)
  union all
  select 'receipt photos', pg_size_pretty(pg_total_relation_size('public.sync_receipt')), (select count(*) from public.sync_receipt)
  union all
  select 'shared groups', pg_size_pretty(pg_total_relation_size('public.sync_group')), (select count(*) from public.sync_group)
  union all
  select 'guest sign-ins', null, (select count(*) from auth.users where is_anonymous);
$$;
revoke all on function public.sync_storage() from public, anon, authenticated;
