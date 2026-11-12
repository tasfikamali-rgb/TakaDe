# Supabase (accounts and shared groups)

TakaDe uses Supabase Auth for accounts: Create an account and Sign in with email (6-digit
code), Apple, Google or Microsoft. See docs/adr/0016-accounts-on-supabase.md. Supabase holds
only the account: id, email, name and which sign-ins are linked. Groups, expenses and
payments stay in SQLite on the phone.

Sabit created the project on 2026-11-11 (host `yxsfbakrtmpsuuuuogbl.supabase.co`, Asia-Pacific
region; the host is in `Config/TakaDe.xcconfig`). Done so far: redirect URL, manual linking,
Apple (client id `app.takade.ios`) and Google (web client and secret, iOS client id added).
Nothing is deployed yet. Steps:

1. **Anon key:** put the anon public key in `Config/Supabase.local.xcconfig` (see the
   `.example` file). Never put the service-role key in the app.
2. **Authentication > URL Configuration:** add `takade://auth-callback` to Redirect URLs.
3. **Authentication > Sign In / Providers:**
   - Email: on, "Confirm email" on. Edit the Magic Link and Confirm signup templates to
     show `{{ .Token }}` (the 6-digit code) instead of a link. Set up custom SMTP with the
     project's sender domain before launch; the built-in sender is for testing only.
     Supabase only lets you edit templates once custom SMTP is on, so email codes stay
     hidden in the app (`TAKADE_EMAIL_SIGN_IN = NO`) until the sender and template are done.
   - Apple: on. Add the app's bundle id (`app.takade.ios`) as a client id. Native sign-in
     passes Apple's ID token, so no Services ID secret is needed for the app.
   - Google: on, with a **Web** OAuth client id and secret from Google Cloud (Supabase does
     the code exchange), and the iOS client id added to "Authorized Client IDs".
   - Azure (Microsoft): on, with an app registration from Microsoft Entra, tenant `common`
     so personal and work accounts both work. **Skipped for launch (Sabit, 2026-11-11):** the
     university Azure account can't register apps. The button stays hidden while
     `TAKADE_MICROSOFT_SIGN_IN = NO` in `Config/TakaDe.xcconfig`; flip it if Azure is set up later.
   - Turn on **Allow manual linking**, so people can link more sign-ins from the Account tab.
4. **Functions:** `supabase functions deploy delete-account`.
5. **Block throwaway emails** (see docs/adr/0018-block-disposable-emails.md):
   - In the SQL Editor, run `migrations/20261111000000_block_disposable_emails.sql`, then
     `seed/disposable_email_domains.sql` (about 10,000 domains). Both are safe to run again.
   - Authentication > Hooks > **Before User Created**: add a Postgres hook, schema `public`,
     function `hook_before_user_created`, and turn it on.
   - Check: creating an account with a `@mailinator.com` address fails; a Gmail one works.
   - To refresh the list: `python3 scripts/update-disposable-domains.py`, commit both
     generated files, and run the seed SQL again.
6. Tell the coding thread, which then checks every flow on a phone.

## Shared groups (ADR 0019)

Only groups someone invites others to are stored here, encrypted on the phone. Steps:

1. **SQL editor:** run `migrations/20261112000000_shared_groups.sql` once. It creates the
   relay tables with row-level security, the join function, and a nightly cleanup job.
2. **Authentication > Sign In / Providers:** turn on **Allow anonymous sign-ins**, so friends
   can join a group without making an account. Before launch, also turn on CAPTCHA.
3. Check space used at any time: `select * from public.sync_storage();`
