# 13. Sync through an end-to-end encrypted relay (design only)

Status: accepted as the direction (Sabit, 2026-11-11). Not built. Hosting, cost and any account creation come back to Sabit before anything is set up.

## Context
Release 1 is local-only (ADR 1): each phone holds its own SQLite ledger and nothing is uploaded. Shared groups, invitations and multi-device use need some reachable service. CLAUDE.md asks for a deliberate choice instead of a central database slipped in. The options compared in the sign-in plan were: stay local-only, an encrypted relay, iCloud/CloudKit sharing (iPhone only, so it shuts out Android, most of the Bangladesh market), and a conventional backend that can read everything (which breaks the promise that people's data stays theirs).

## Decision
When sync is built, it uses a small relay that stores encrypted change logs and can't read them.

- **Per-group keys.** Each shared group gets a random symmetric key, made on the device that shares it. It's kept in the iOS Keychain (Android Keystore), never in SQLite, never sent to the relay. Keys carry an epoch; rotating the key (for example after removing someone, or revoking an invite) bumps the epoch.
- **Encrypted outbox.** Every local edit is written to a `change_outbox` row in the same transaction as the ledger change. The payload is encrypted with the group key before upload. `change_id` is a random id and doubles as the idempotency key, so a retried upload never applies twice.
- **Ordering.** Each change carries a hybrid logical clock (HLC) value and its device id. Members pull changes after their last cursor, decrypt them on the device, and apply them to their own SQLite file. Conflicts resolve per entity by HLC, with device id as the tie-breaker. Every applied change still lands in the append-only audit log, so nothing silently disappears.
- **Invites.** An invite link carries the group key after the `#`. Browsers don't send the fragment to servers, so the relay never sees it. Links expire, and revoking one means rotating the key.
- **Recovery.** Keys are backed up through iCloud Keychain (Google Block Store on Android), plus an optional recovery code the person writes down. Losing every device and the code means losing the shared data, and the app has to say so plainly before sync is turned on.
- **What the relay sees.** Ciphertext, group ids, device ids, sizes and timestamps. Never names, amounts, notes or receipt data. That metadata is listed in the privacy disclosure.

Planned schema (a later migration, written only when sync is built): `account`, `device`, `member.account_id`, `group_sync (group_id, key_epoch, server_cursor)`, and `change_outbox (change_id, group_id, entity, entity_id, hlc, device_id, payload, uploaded_at)`.

**Phone OTP** is planned for when invites by phone number arrive. It needs an SMS provider, sender registration in Bangladesh, abuse limits and a decision on storing numbers, so it isn't built now.

## Consequences
- No server code, hosting choice, account or domain until Sabit approves the hosting and cost.
- The app, store listing and website must not say "end-to-end encrypted" until a security review of the real implementation, including key handling, recovery and the metadata above.
- Payment verification is separate (CLAUDE.md principle 4). Encrypting the ledger doesn't make a reported payment verified.
- Until sync ships, sharing stays a read-only summary or an export file.
