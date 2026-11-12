# 19. Shared groups through the encrypted relay

Status: accepted (Sabit, 2026-11-11: "make sure the share button actually works... it takes
you directly into the group", "not only for my phone, but also for all future users", and
keep it within Supabase's free plan). Builds on ADR 13 (relay design) and ADR 16 (Supabase).
Implemented in the app and as a SQL migration. Not yet run on the Supabase project or tested
between two real phones.

## Context
Groups live in SQLite on each phone (ADR 1). The share button only sent a picture of the
balances, so a friend couldn't open the group or add to it. Sabit wants a link that opens the
group on the friend's phone, for every user, on the free Supabase plan (500 MB database).

## Decision
**Only shared groups leave the phone.** A group goes to the relay the first time someone taps
Invite. Then all of it (the group, people, every expense including deleted ones, payments
and meal counts) is queued and uploaded. After that every change is queued in `sync_outbox` in
the same SQLite transaction as the change itself, and uploaded when online. Groups nobody
invites anyone to never leave the phone.

**Encryption.** Each shared group has a random 256-bit key made on the phone and kept in the
Keychain (`app.takade.sync`, this device only). Each change is JSON, compressed with zlib,
then sealed with AES-GCM (CryptoKit) with the group id and change id as authenticated data.
The relay stores `v1.` + base64 of the sealed box. No custom cryptography.

**Invite links.** `takade://join?g=<group>&t=<token>#k=<key>`. The token (32 random bytes)
lets the relay add the person: only its SHA-256 is stored, it expires after 7 days, and
members can stop all links ("Stop this link"). The key is after the `#` and is never sent to
the relay. Anyone holding a whole link can join until it expires or is stopped, and the
Invite screen says so. The app also accepts `https://takadeapp.com/join?...` for when the
website exists.

**What the relay can see.** Ciphertext, group ids, an anonymous user id per phone, which of
those are in which group, invite hashes, sizes and times. Not names, amounts, notes or
receipts. This is not described as end-to-end encrypted anywhere until a security review
(ADR 13 still applies).

**Identity.** Sharing uses an anonymous Supabase user per phone, separate from the TakaDe
account, so friends can join without an account and the relay can't tie a group to an email.
The session is in the Keychain. Losing the phone means joining again with a new link from
another member. Row-level security allows reads and writes only to a group's members; the
only way in is `join_sync_group(token)`.

**Order and conflicts.** The relay numbers changes (`seq`). Every phone applies all changes,
its own included, in that order, so all phones end the same:
- Group settings: last one wins. People are merged by id and never removed.
- Expenses: higher `version` wins; equal versions go to the later one.
- Payments: same rules as on the phone. Nothing from another phone can create a `confirmed`
  payment or move one to confirmed (CLAUDE.md principle 4). An acknowledgement by the
  recipient from another phone is accepted as the group's word, not as proof of payment.
- Meal counts: last one wins.
- A change that can't be decrypted or breaks a rule (unknown person, wrong currency, wrong
  group) is skipped and the cursor moves past it, so one bad change can't block a group.
Own changes coming back are applied without a second history entry. Changes from others are
recorded in the history with source `sync`.

**Who am I.** "Which one is me" is per phone and never synced. After joining, the person
picks their name from the group's people or adds themselves.

**When syncing happens.** At launch, when the app comes back, shortly after any edit, every
20 seconds while a shared group is open, and on pull to refresh. Offline, everything still
works on the phone and the group screen says changes will go up later.

## Storage (Supabase free plan, 500 MB)
- A compressed, encrypted expense is about 0.5 KB. Rough sizing: 10,000 active people adding
  about 20 shared expenses a month is about 100 MB a month.
- Nightly `pg_cron` job `takade-sync-cleanup`: drops groups with no change for 90 days (the
  phones keep everything and show "No longer shared", and inviting again re-uploads), invites
  that expired over a week ago, and anonymous users in no group.
- `select * from public.sync_storage();` in the SQL editor shows sizes.
- Next step if it grows: compaction (a fresh snapshot per group and dropping changes every
  member has already pulled). Not built.

## Universal links
A tappable `https://takadeapp.com/join/...` needs the domain, an `apple-app-site-association`
file on it, and the Associated Domains entitlement, which needs a paid Apple Developer team.
Until then the link is `takade://`: iMessage and Notes open it, WhatsApp and Messenger may
not. The shared message says to copy it into TakaDe's "Join with a link", which reads a link
out of a whole pasted message.

## Not built yet
- Removing someone from a group (needs key rotation, ADR 13).
- Syncing the same person's groups across their own phones, and key backup or recovery.
- Leaving a group on the relay from the app. Delete all my data forgets the keys and the
  sharing sign-in on the phone; the relay copy goes when the group is idle for 90 days.
- Push notifications for new expenses.
- Payment numbers (bKash and others) stay on each phone and are not shared.

## Release checks
1. Apple privacy label: decide with the security review whether the ciphertext and
   anonymous user id need an entry (Apple exempts data the developer can't read).
2. Supabase recommends CAPTCHA with anonymous sign-ins to limit abuse; add it before launch.
3. Test on two phones: invite, join, add from both, offline then online, stop link, 90-day
   cleanup (run `select public.sync_cleanup()` after back-dating a test group).
4. Export compliance (`ITSAppUsesNonExemptEncryption`): the app now encrypts data itself
   with CryptoKit for shared groups. Re-check the answer with this in mind; it is still the
   owner's decision (docs/decisions-needed.md).
