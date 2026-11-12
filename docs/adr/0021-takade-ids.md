# 21. TakaDe IDs: add a friend who has an account

Status: accepted (Sabit, 2026-11-12, asked how friends who already have TakaDe can add each
other without storing phone numbers, and approved IDs with QR codes). Phone-number sign-up is
not used: SMS costs money on the free plan. Opt-in hashed contact matching may come later.
Builds on ADR 16 (accounts on Supabase) and ADR 19 (shared groups).

## Decision
- Each TakaDe account gets an ID: 8 random Crockford base32 characters (40 bits), shown as
  `TKD-7F3K-9QXM`, with a QR code holding `takade://friend?c=…`. It's in the Account tab,
  and can be copied, shared or replaced ("Get a new ID" stops the old one at once).
- The server keeps, per account, only the ID and a public key (`friend_id`). No phone
  numbers, contacts or names. Guest sign-ins used for shared groups don't get IDs.
- In a group, "Add a person > TakaDe ID or QR code" takes a typed or scanned ID and the name
  the group knows them by. The phone looks up the ID, adds the person to the group, makes an
  invite link (ADR 19) and seals it, with the group name, the sender's name and the new
  person's member id, to the friend's public key using HPKE from CryptoKit (X25519,
  HKDF-SHA256, ChaCha20-Poly1305). The server stores the sealed invite (`friend_invite`)
  without being able to read it.
- The friend's phone checks for invites at launch and when the app comes back, opens them
  with the private key in its Keychain, and asks "Rafi invited you to Sylhet trip: Join or
  Decline". Joining picks the person the sender added. Joined, declined and 7-day-old
  invites are deleted.
- Limits against guessing IDs and spam: 30 lookups or sends per account per hour, 50 invites
  sent per day, 100 waiting per account. Lookups are logged for a day only.
- One key per account, kept in iCloud Keychain (end-to-end encrypted by Apple) so the same
  person's iPhone and iPad share it. Update 2026-11-12: it was first kept on one device only,
  and each device replaced the other's key on the server, so invites sealed for the iPhone
  were unreadable (and deleted) on the iPad and the other way round. Older device-only keys
  move to iCloud Keychain on first use. With iCloud Keychain off, each device still has its
  own key and the last one opened receives; an invite a device can't read is now left on
  the server for the other device (dropped after 7 days) instead of being deleted.
- While TakaDe is open it checks for invites every 15 seconds with one small request, and
  stops in the background. No always-on connection (Realtime is limited on the free plan).
  An invite closed with Cancel comes back the next time the app is opened.

## What the server can see
The ID, the public key, who sent an invite to whom and when (account ids), and the size of
the sealed invite. Not the group, names, amounts or the link inside it. This hasn't had a
security review, so the app says the invite "is encrypted on this phone so only their phone
can read it" and doesn't claim more.

## Setup
Run `supabase/migrations/20261112020000_friend_ids.sql` in the SQL editor.
