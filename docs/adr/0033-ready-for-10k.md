# 33. Supabase ready for 10,000 people on the free plan

Status: accepted (Sabit, 2026-11-12: "make sure everything is perfect and there will be no
issues if we get 10k users and fix any bugs"). SQL checked on a local PostgreSQL 16 with a
Supabase stand-in (auth, cron, roles); app code checked by the CI build, not yet on a phone.
The owner runs `supabase/migrations/20261112070000_ready_for_10k.sql` and then
`supabase/checks/health_check.sql` in the SQL editor.

## Fixes
- **Guests no longer drop out of shared groups.** The sharing sign-in is an anonymous
  Supabase user. When its refresh failed (the app closed between the service using the old
  refresh token and the phone saving the new one), the phone started a new guest user,
  which RLS treats as a stranger: pulls came back empty and the next upload ended the group
  on that phone. Now each phone stores a random rejoin secret per group in its Keychain and
  its SHA-256 on its own `sync_member` row (`set_sync_rejoin`). A new guest sign-in calls
  `rejoin_sync_group` to move the old row over. Hashes are hidden from other members by
  column grants. A refresh whose answer was lost is also retried at once (the service
  returns the same tokens within its reuse window), and the refresh finishes in the
  background, as PR #77 did for accounts.
- **One request a minute, not one per group.** The once-a-minute check, the check when the
  app comes back and the background refresh read `sync_group?select=id,last_change_at` once
  and sync only groups that changed, have edits waiting or failed last time. A person in 5
  groups sends 1 request a minute instead of 5. Launch and pull to refresh still sync every
  group.
- **Indexes for account deletion.** `sync_change.author`, `sync_receipt.author`,
  `friend_message.from_user` and `friend_block.blocked` point at accounts without an index,
  so each account deletion (and each guest removed by the nightly cleanup) read those tables
  in full. At 10k people `sync_change` is the biggest table.
- **Deleted accounts.** `delete-account` calls `auth.admin.deleteUser` without soft delete,
  so the account, its TakaDe ID, messages, invites and memberships go at once (foreign keys
  cascade; shared-group changes keep the ciphertext with the author set to null). Supabase's
  own sign-in log (`auth.audit_log_entries`) still holds emails, so a nightly job removes
  entries older than 30 days.

## Checked and fine
- Every account gets a Supabase user id (UUID primary key) and, the first time Account or
  Social opens, a TakaDe ID with a unique constraint; the app retries a clash.
- RLS: every table has it on, API roles start from `revoke all`, `auth.uid()` is read once per
  request, membership checks go through `my_sync_groups()`.
- Rate limits: uploads, groups, invite links, ID lookups, messages, shop names.
- Realtime: only `friend_message`, only while a chat is open.

## Limits that need a decision later
- **Database size (500 MB).** `sync_change` keeps every change of an active group. Estimate:
  ~110 MB after month 1, +~50 MB a month, full around month 7-8 at 10k people. Options:
  compact old changes into a snapshot per group (app + server work), or the Pro plan
  ($25/month, 8 GB).
- **Egress (5 GB a month).** Polling headers alone are ~1 KB a request; at ~10 people
  online on average this is ~2 GB a month. Watch Usage in the dashboard.
- **Auth rate limits per IP.** Mobile networks in Bangladesh share IPs (carrier NAT), so the
  defaults for anonymous sign-ins (30 an hour per IP) and token refreshes can block real
  people. Raise them in Authentication > Rate Limits and turn on CAPTCHA before launch.
- **Email codes.** The built-in sender allows only a few emails an hour for the whole
  project; custom SMTP (Resend) is required before email sign-in is switched on.
- **No backups on the free plan.** Phones keep every group, so the relay can be rebuilt by
  sharing again, but accounts and TakaDe IDs can't.
