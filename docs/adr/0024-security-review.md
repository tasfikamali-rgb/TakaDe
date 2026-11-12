# 24. Security review: injection, server rules and untrusted input

Status: accepted (Sabit, 2026-11-12, asked to make sure there's no SQL injection or anything
similar that could harm the app, and to keep latency low).

## What was checked
- **Local SQLite (GRDB).** Every query uses `?` arguments; no SQL is built from names, notes,
  amounts or other text. The only interpolated pieces are fixed SQL fragments and a `LIKE`
  pattern that is itself passed as an argument. No change needed.
- **Supabase REST calls.** Filters in request paths are built only from UUIDs, integers and the
  server's own user id, never from typed text. RPC arguments go in the JSON body. Server
  functions are `security definer` with an empty `search_path` and no dynamic SQL.
- **Links and QR codes.** Invite links and TakaDe IDs are parsed strictly (scheme, host, UUID,
  token alphabet and length, 32-byte key); anything else is ignored.
- **Edge function `delete-account`.** Deletes only the caller, read from their own token.
- **Encryption.** AES-GCM per group with group and change ids as authenticated data; HPKE for
  friend invites; keys in the Keychain (this device only). Unchanged.

## Decisions
- **Exact database privileges** (`20261112030000_security_hardening.sql`). Supabase grants the
  API roles every privilege on new tables by default, so the earlier narrower grants had no
  effect. The app's sign-ins now get only the columns the app sends; times and authors are
  always set by the server, and a stopped invite link stays stopped.
- **Upload limits per sign-in**: 20,000 changes or 50 MB an hour and 100 MB a day; 50 new
  shared groups and 200 invite links a day. Far above normal use (a first share of a year of
  mess meals plus a few hundred receipt photos fits), but one sign-in can no longer fill the
  free plan. CAPTCHA on sign-ups is still needed before launch.
- **Untrusted data from other phones.** Anyone with a group's link can write to it, so the
  phone now refuses: changes that decompress past 2 MB, group names, people's names, titles
  or notes far longer than the app allows, more than 500 people, and receipt photos that
  aren't a single JPEG up to 4000 px. Receipt photos are decoded at screen size. Friend
  invites with oversized names are dropped. Names are never cut or altered, only accepted or
  refused.
- **Latency.** Read rules check group membership once per request instead of once per row,
  and an upload updates its group's "last change" once instead of once per change.

## Not covered
- No penetration test or third-party audit has been done.
- Device-level threats (jailbreak, lost unlocked phone) are as described in ADR 0011.
