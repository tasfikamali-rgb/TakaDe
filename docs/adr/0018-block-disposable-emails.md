# 0018. Block throwaway email addresses

Date: 2026-11-11 · Status: accepted (Sabit asked for it)

## Context

Throwaway ("10-minute") inboxes let anyone make accounts that can't be traced or recovered,
which invites abuse once invitations and sync arrive. Sabit asked that they can't be used to
sign up or sign in.

## Decision

- **Server (the real control):** a Supabase Auth "Before User Created" Postgres hook,
  `public.hook_before_user_created`, refuses any new account whose email domain, or a parent
  domain, is in `auth_guard.disposable_email_domains`. It runs for every sign-up path (email
  code, Apple, Google, Microsoft). A trigger on `auth.users` also refuses changing an existing
  account's email to a throwaway one. Only `supabase_auth_admin` can call the hook or read the list.
- **App (a courtesy):** `TakaDeCore.DisposableEmail` checks the same list before sending a code
  and shows "Temporary email addresses can't be used with TakaDe…". The app also maps the
  server's `disposable_email_not_allowed` refusal to that message.
- **List:** the MIT-licensed community list
  [disposable-email-domains](https://github.com/disposable-email-domains/disposable-email-domains)
  (PyPI package of the same name, version 0.0.293, 10,181 domains).
  `scripts/update-disposable-domains.py` regenerates both the app and server copies from one
  download. Apple's Hide My Email relay (`privaterelay.appleid.com`) and the big real providers
  are always allowed.

## Consequences

- No list is complete: new throwaway domains appear daily, so refresh the list before release
  and every few months. Someone with their own domain can still make a throwaway address; rate
  limits and later abuse controls cover that.
- Existing accounts made before the hook was on aren't removed.
- Sign-in by email code only sends to existing accounts, so after the hook is on a throwaway
  address has no account to sign in to.
- The in-app message only shows once email sign-in is switched on (`TAKADE_EMAIL_SIGN_IN`).
