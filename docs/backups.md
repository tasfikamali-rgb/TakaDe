# Backups and the spare database

What runs: a nightly locked copy of Supabase in Cloudflare R2 (30 days kept), and a spare
Supabase project refilled from it every night. Why and how: docs/adr/0034-packed-changes-and-backups.md.

## One-time setup (owner)

Never paste passwords or keys into chat. Each one goes straight into GitHub or Supabase.

1. **Main database address.** Supabase > your project > Connect > Session pooler. Copy the
   connection string and put your database password in it.
   GitHub > repository > Settings > Secrets and variables > Actions > New secret:
   `SUPABASE_DB_URL`.
2. **Backup passphrase.** Make a long random passphrase in your password manager. Save it
   there and as the secret `BACKUP_PASSPHRASE`. Without it the backups can't be opened.
3. **Cloudflare R2.** Make a free Cloudflare account, open R2, create a bucket (for example
   `takade-backups`, private). R2 > Manage API tokens > Create token with "Object Read &
   Write" for that bucket. Add secrets `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
   `R2_SECRET_ACCESS_KEY` and `R2_BUCKET`.
4. Actions > Nightly backup > Run workflow. It should end green and a file
   `takade-YYYY-MM-DD.tar.gz.gpg` appears in the bucket.

## Spare project

1. Create a second free Supabase project in another region (for example Mumbai).
2. In its SQL editor run every file in `supabase/migrations`, in order.
3. Copy its Authentication settings from the main project (providers, redirect URL,
   anonymous sign-ins, rate limits) the same way as supabase/README.md.
4. Add its Session pooler connection string as the secret `SPARE_DB_URL`. The next nightly
   run refills it.
5. In the app: `TAKADE_SUPABASE_SPARE_HOST` in Config/TakaDe.xcconfig, its anon key as
   `TAKADE_SUPABASE_SPARE_ANON_KEY` in Config/Supabase.local.xcconfig.

## The switch

Make a public file holding `{"use":"main"}`, for example in a second, public R2 bucket, and
set `TAKADE_SERVER_SWITCH_URL` to its address without `https://`. To move everyone to the
spare, change it to `{"use":"spare"}`: each phone switches the next time the app opens.
Change it back the same way.

Set up (2026-11-12): the file is `switch.json` in the public R2 bucket `takade-switch`
(nothing else goes in that bucket). To change it, open the bucket in Cloudflare, delete
`switch.json` and upload a new one with the other value. The spare already has main's
sign-in settings (Apple, Google, guest sign-ins, redirect link, disposable-email hook and
its domain list). Signing in again is needed after a switch: each project signs its own
sessions.

## Restoring a copy

Download the file from R2, then: `gpg -d takade-YYYY-MM-DD.tar.gz.gpg | tar xz`, then load
`data.sql` into a project with `SPARE_DB_URL=... scripts/backup/refill-spare.sh data.sql`.
Ask Claude to do it with you.
