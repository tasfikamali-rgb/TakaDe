-- TakaDe: a read-only health check of the Supabase project (docs/adr/0033-ready-for-10k.md).
-- Paste into the SQL editor and press Run. It changes nothing. Each row is one check:
-- "ok" is fine, "MISSING" means a file in supabase/migrations hasn't been run yet, and
-- "look" means read the detail.

with expected(what, kind, name, file) as (values
  ('Throwaway email block',   'function', 'public.hook_before_user_created(jsonb)', '20261111000000_block_disposable_emails.sql'),
  ('Shared groups',           'table',    'public.sync_change',                     '20261112000000_shared_groups.sql'),
  ('Receipts in groups',      'table',    'public.sync_receipt',                    '20261112010000_receipt_photos.sql'),
  ('TakaDe IDs',              'table',    'public.friend_id',                       '20261112020000_friend_ids.sql'),
  ('Security limits',         'table',    'public.sync_usage',                      '20261112030000_security_hardening.sql'),
  ('Social messages',         'table',    'public.friend_message',                  '20261112040000_friend_messages.sql'),
  ('Shop name counts',        'table',    'public.store_name_count',                '20261112060000_store_name_counts.sql'),
  ('Rejoin + log cleanup',    'function', 'public.rejoin_sync_group(uuid,text)',    '20261112070000_ready_for_10k.sql'),
  ('Packed old changes',      'table',    'public.sync_bundle',                     '20261112080000_pack_old_changes.sql')
)
select 'migration' as area, what as check_name,
       case when (kind = 'table' and to_regclass(name) is not null)
              or (kind = 'function' and to_regprocedure(name) is not null)
            then 'ok' else 'MISSING' end as status,
       file as detail
  from expected

union all
select 'migration', 'Groups kept a year (not 90 days)',
       case when position('365 days' in coalesce((select prosrc from pg_proc where oid = to_regprocedure('public.sync_cleanup()')), '')) > 0
            then 'ok' else 'MISSING' end,
       '20261112050000_keep_groups_one_year.sql'

union all
select 'nightly job', j.jobname,
       case when not j.active then 'look'
            when r.status is null then 'not run yet'
            when r.status = 'succeeded' then 'ok' else 'look' end,
       coalesce('last run ' || to_char(r.start_time, 'YYYY-MM-DD HH24:MI') || ' UTC: ' || r.status
                || coalesce(' - ' || left(r.return_message, 120), ''), j.schedule)
  from cron.job j
  left join lateral (select d.status, d.start_time, d.return_message from cron.job_run_details d
                      where d.jobid = j.jobid order by d.start_time desc limit 1) r on true
 where j.jobname like 'takade-%'

union all
select 'space', 'Whole database (free plan: 500 MB)',
       case when pg_database_size(current_database()) < 350 * 1024 * 1024 then 'ok' else 'look' end,
       pg_size_pretty(pg_database_size(current_database()))

union all
select * from (
  select 'space', 'Table ' || n.nspname || '.' || c.relname, 'info',
         pg_size_pretty(pg_total_relation_size(c.oid)) || ', about ' || greatest(c.reltuples, 0)::bigint || ' rows'
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind = 'r' and n.nspname in ('public', 'auth', 'auth_guard', 'cron', 'realtime', 'storage')
   order by pg_total_relation_size(c.oid) desc
   limit 12
) biggest

union all
select 'accounts', 'Accounts (email, Apple, Google)', 'info', count(*)::text from auth.users where not is_anonymous
union all
select 'accounts', 'Guest sign-ins for shared groups', 'info', count(*)::text from auth.users where is_anonymous
union all
select 'accounts', 'Accounts waiting to be deleted (soft-deleted)',
       case when count(*) = 0 then 'ok' else 'look' end, count(*)::text
  from auth.users where deleted_at is not null
union all
select 'accounts', 'Every account has its own user ID',
       case when count(*) = count(distinct id) then 'ok' else 'look' end, count(*)::text || ' accounts'
  from auth.users
union all
select 'accounts', 'TakaDe IDs that are unique',
       case when (select count(*) from public.friend_id) = (select count(distinct code) from public.friend_id) then 'ok' else 'look' end,
       (select count(*) from public.friend_id)::text || ' IDs'
union all
select 'accounts', 'Accounts without a TakaDe ID yet', 'info',
       (select count(*) from auth.users u where not u.is_anonymous
          and not exists (select 1 from public.friend_id f where f.user_id = u.id))::text
       || ' (made the first time the person opens Account or Social)'
union all
select 'accounts', 'Sign-in log older than 30 days',
       case when (select count(*) from auth.audit_log_entries where created_at < now() - interval '30 days') = 0 then 'ok' else 'look' end,
       (select count(*) from auth.audit_log_entries where created_at < now() - interval '30 days')::text || ' rows'

union all
select 'realtime', 'Tables sending live updates', 'info',
       coalesce(string_agg(schemaname || '.' || tablename, ', '), 'none')
  from pg_publication_tables where pubname = 'supabase_realtime'

union all
select 'connections', 'Open database connections now', 'info',
       count(*)::text || ' (free plan: 60 direct)'
  from pg_stat_activity;
