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
3. **Receipt photos:** then run `migrations/20261112010000_receipt_photos.sql` (ADR 0020).
4. Check space used at any time: `select * from public.sync_storage();`
5. **TakaDe IDs:** run `migrations/20261112020000_friend_ids.sql` (ADR 0021), so friends with
   accounts can add each other by ID or QR code. It stores an ID and a public key per account.
6. **Security review:** run `migrations/20261112030000_security_hardening.sql` (ADR 0024). It
   tightens what the app's sign-ins may write, adds upload limits per sign-in, and makes the
   access rules faster. Safe to re-run.
7. **Keep quiet groups a year:** run `migrations/20261112050000_keep_groups_one_year.sql`
   (ADR 0028). The nightly cleanup then removes a shared group only after 365 days with no
   change, instead of 90. Safe to re-run.
8. **Shop name counts:** run `migrations/20261112060000_store_name_counts.sql` (ADR 0032).
   Only people who say yes in the app send the shop name from a scanned receipt; it is
   counted by month and country with no link to the person. See the top shops with
   `select * from public.top_store_names(3, 'BD');` (last 3 months, Bangladesh; `null` for
   everywhere).

9. **Ready for 10k people:** run `migrations/20261112070000_ready_for_10k.sql` (ADR 0033). It
   lets a phone rejoin its shared groups if its sharing sign-in is lost, adds indexes that
   keep account deletion fast, and removes Supabase's sign-in log after 30 days. Safe to re-run.
10. **Health check:** run `checks/health_check.sql` at any time. It changes nothing and lists
    which files above have run, the nightly jobs' last results, space used, and account checks.

## Social tab messages (ADR 0025)

1. **SQL editor:** run `migrations/20261112040000_friend_messages.sql` after the TakaDe IDs
   file. It adds the sealed message box, blocking, spam limits, a nightly cleanup, and puts
   `friend_message` on Realtime so a new message reaches an open app at once.
2. **Project Settings > Realtime:** leave **Allow public access** on (the default). The
   "typing…" signal uses a broadcast channel whose name only the two phones can work out.
   With it off, messages still arrive at once in an open chat; only "typing…" stops showing.
3. Free plan limits that matter: 200 phones connected to Realtime at the same time and 2
   million Realtime messages a month. A phone is connected only while one of its chats is
   on screen; otherwise the app checks for messages every minute while open.

## Packed changes, backups and the spare (ADR 0034)

Run `migrations/20261112080000_pack_old_changes.sql` in the SQL editor. Phones then pack busy
groups' older changes into one bundle. Backups and the spare project: see docs/backups.md.

## Passkeys (ADR 0035)

Supabase Auth's passkeys are in beta and open on every plan, including Free. They need the
website first, so do these in order once `takadeapp.com` is bought and the paid Apple
Developer account exists:

1. Put the website file up (`docs/passkeys/README.md`).
2. **Authentication > Passkeys:** turn on **Enable Passkey authentication**, with
   - Relying Party Display Name: `TakaDe`
   - Relying Party ID: `takadeapp.com` (no `https://`). Never change it afterwards: every
     passkey people made stops working.
   - Relying Party Origins: `https://takadeapp.com`
3. Do the same on the spare project, with the same values, so passkeys still work after
   "switch to spare".
4. Check: `curl https://yxsfbakrtmpsuuuuogbl.supabase.co/auth/v1/settings -H "apikey: <anon key>"`
   shows `"passkeys_enabled": true` (people have reported the switch not sticking on Free
   until another Auth setting was saved too).
5. Set `TAKADE_PASSKEY_DOMAIN = takadeapp.com` in `Config/TakaDe.xcconfig`, and make sure the
   phone build carries `App/TakaDe.entitlements` (Associated Domains).
