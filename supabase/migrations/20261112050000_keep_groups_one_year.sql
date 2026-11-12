-- TakaDe: keep quiet shared groups for a year, not 90 days (Sabit, 2026-11-12: "a lot of
-- people do it once a month or like once a year. So make it once a year.").
--
-- Same cleanup as 20261112030000_security_hardening.sql, with one change: a shared group is
-- removed from the relay only after 365 days with no change. Every phone keeps its own copy
-- either way. Sharing sign-ins are still removed after 7 days only when they are in no group
-- at all, so a member of a quiet group is never signed out by this.
--
-- Safe to run more than once. Paste into the Supabase SQL editor and press Run.

create or replace function public.sync_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.sync_group where last_change_at < now() - interval '365 days';
  delete from public.sync_invite where expires_at < now() - interval '7 days';
  delete from public.sync_usage where hour < now() - interval '2 days';
  delete from auth.users u
   where u.is_anonymous
     and u.created_at < now() - interval '7 days'
     and not exists (select 1 from public.sync_member m where m.user_id = u.id);
end;
$$;
revoke all on function public.sync_cleanup() from public, anon, authenticated;
