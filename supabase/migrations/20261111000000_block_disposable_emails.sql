-- Block throwaway ("10-minute") email addresses from TakaDe accounts.
--
-- 1. public.hook_before_user_created: a Supabase Auth "Before User Created" hook. Turn it on in
--    Authentication > Hooks. It runs for every new account (email code, Apple, Google, Microsoft)
--    and rejects the sign-up when the email's domain, or a parent domain, is on the list.
-- 2. auth_guard_block_disposable_email_change: stops an existing account from switching its
--    email to a throwaway address later (Account tab > add email).
--
-- The domain list lives in auth_guard.disposable_email_domains and is loaded from
-- supabase/seed/disposable_email_domains.sql (regenerate with scripts/update-disposable-domains.py).
-- The app ships the same list so it can explain the problem before sending a code.

create schema if not exists auth_guard;

create table if not exists auth_guard.disposable_email_domains (
    domain text primary key check (domain = lower(domain) and domain <> '')
);

-- Nobody but the auth server and the database owner can read or change the list.
revoke all on schema auth_guard from public, anon, authenticated;
revoke all on auth_guard.disposable_email_domains from public, anon, authenticated;

create or replace function auth_guard.email_is_disposable(email text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    d text := lower(trim(trailing '.' from split_part(trim(coalesce(email, '')), '@', 2)));
    parts text[];
    i int;
begin
    -- Apple's Hide My Email relay is a real, permanent inbox.
    if d = '' or d = 'privaterelay.appleid.com' then
        return false;
    end if;
    parts := string_to_array(d, '.');
    -- Check the domain and each parent ("x.mailinator.com", then "mailinator.com"),
    -- but never a bare top-level domain like "com".
    for i in 1 .. greatest(array_length(parts, 1) - 1, 1) loop
        if exists (
            select 1 from auth_guard.disposable_email_domains
            where domain = array_to_string(parts[i:], '.')
        ) then
            return true;
        end if;
    end loop;
    return false;
end
$$;

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth_guard.email_is_disposable(event -> 'user' ->> 'email') then
        return jsonb_build_object(
            'error', jsonb_build_object(
                'http_code', 403,
                'message', 'disposable_email_not_allowed: Please use a permanent email address.'
            )
        );
    end if;
    return '{}'::jsonb;
end
$$;

create or replace function auth_guard.block_disposable_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if (new.email is distinct from old.email and auth_guard.email_is_disposable(new.email))
       or (new.email_change is distinct from old.email_change
           and coalesce(new.email_change, '') <> ''
           and auth_guard.email_is_disposable(new.email_change)) then
        raise exception 'disposable_email_not_allowed: Please use a permanent email address.'
            using errcode = 'check_violation';
    end if;
    return new;
end
$$;

drop trigger if exists auth_guard_block_disposable_email_change on auth.users;
create trigger auth_guard_block_disposable_email_change
    before update of email, email_change on auth.users
    for each row execute function auth_guard.block_disposable_email_change();

-- Only the auth server may call the hook.
grant usage on schema auth_guard to supabase_auth_admin;
grant select on auth_guard.disposable_email_domains to supabase_auth_admin;
grant execute on function auth_guard.email_is_disposable(text) to supabase_auth_admin;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
revoke execute on function auth_guard.email_is_disposable(text) from public, anon, authenticated;
