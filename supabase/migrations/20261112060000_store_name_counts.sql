-- TakaDe: shop names from scanned receipts, counted for future ad insights (ADR 0032).
-- Sabit, 2026-11-12: "whenever someone scans ... if the company name arises, just [keep] that
-- one, because we have an intention to put ads in the future in the app."
--
-- Only for people who said yes in the app (off by default). Each confirmed shop name adds 1 to
-- a count kept by month, home country and name. The count has no user id, email, amount,
-- date, items or photo, so it can't be traced back to a person. A separate counter keeps
-- one row per sign-in with today's number of names sent, only to stop spam (30 a day).
--
-- Safe to run more than once. Paste into the Supabase SQL editor and press Run.

create table if not exists public.store_name_count (
  month   date    not null check (extract(day from month) = 1),
  country text    not null check (country ~ '^[A-Z]{2}$'),
  name    text    not null check (char_length(name) between 2 and 120),
  scans   integer not null default 0 check (scans >= 0),
  primary key (month, country, name)
);
alter table public.store_name_count enable row level security;
revoke all on public.store_name_count from public, anon, authenticated;

create table if not exists public.store_name_usage (
  user_id uuid    primary key references auth.users (id) on delete cascade,
  day     date    not null,
  sent    integer not null default 0
);
alter table public.store_name_usage enable row level security;
revoke all on public.store_name_usage from public, anon, authenticated;

-- Counts one shop name. The phone already cleans the name; this repeats it so a modified app
-- can't store anything else.
create or replace function public.count_store_name(p_name text, p_country text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_name    text;
  v_country text;
  v_sent    integer;
begin
  if auth.uid() is null then
    raise exception 'sign in required' using errcode = '28000';
  end if;
  v_name := lower(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'));
  if char_length(v_name) not between 2 and 120 or v_name !~ '[[:alpha:]]' then
    raise exception 'name not valid' using errcode = '22023';
  end if;
  v_country := case when p_country ~ '^[A-Z]{2}$' then p_country else 'ZZ' end;

  insert into public.store_name_usage as u (user_id, day, sent)
  values (auth.uid(), current_date, 1)
  on conflict (user_id) do update
    set sent = case when u.day = current_date then u.sent + 1 else 1 end,
        day  = current_date
  returning u.sent into v_sent;
  if v_sent > 30 then
    raise exception 'too many shop names today' using errcode = 'TK429';
  end if;

  insert into public.store_name_count as c (month, country, name, scans)
  values (date_trunc('month', now())::date, v_country, v_name, 1)
  on conflict (month, country, name) do update set scans = c.scans + 1;
end;
$$;
revoke all on function public.count_store_name(text, text) from public, anon;
grant execute on function public.count_store_name(text, text) to authenticated;

-- For the owner in the SQL editor (not callable from the app): the top shops, leaving out
-- names seen fewer than 5 times so a rare name can't point at one person.
create or replace function public.top_store_names(p_months integer default 3, p_country text default null)
returns table (name text, scans bigint)
language sql stable security definer set search_path = ''
as $$
  select c.name, sum(c.scans)::bigint
    from public.store_name_count c
   where c.month >= (date_trunc('month', now()) - make_interval(months => greatest(p_months, 1) - 1))::date
     and (p_country is null or c.country = p_country)
   group by c.name
  having sum(c.scans) >= 5
   order by 2 desc
   limit 200;
$$;
revoke all on function public.top_store_names(integer, text) from public, anon, authenticated;
