# Decisions needed

These block the next phases. The local-only MVP does not depend on any of them.

## 1. Sync and accounts (blocks: shared groups, invitations, notifications)
Pick one, per CLAUDE.md:
- **Stay local-only** for the first release; share by exporting a read-only summary.
- **Encrypted sync service**: clients encrypt ledger data; a small service stores ciphertext.
  Needs key recovery design.
- **Conventional backend** (e.g. a hosted database): easiest for collaboration, but the
  server can read data. Changes the "no central database" premise.

**Decided 2026-11-11:** local-only for the first release (ADR 1).
**Decided 2026-11-11:** when sync comes, it uses an end-to-end encrypted relay (ADR 13). Design only for now.
**Open, owner:** hosting and cost for the relay. Nothing is created until Sabit chooses.
**Planned:** phone OTP sign-in arrives with phone-number invites (ADR 13). Not built.

## 2. bKash, upay and bank settlement (blocks: any payment button)
No public peer-to-peer API is assumed. Needed per provider: official docs, merchant or
partner eligibility, sandbox credentials, callback signing, reconciliation rules, fees, and
legal review. Until then the app only records payments as "reported, not verified".
A first safe step could be showing the recipient's bKash number to copy, with no deep link.

## 3. Receipt OCR (blocks: scanning)
On-device (Apple Vision, nothing leaves the phone) or a cloud service (better accuracy,
needs disclosure and a processor review). **Decided 2026-11-11:** on-device (ADR 8).

## 4. Localization details
- A native Bengali reviewer for the string catalog (all strings are marked `needs_review`).
- **Decided 2026-11-11:** lakh grouping, and Bengali digits by default in the Bengali UI (ADR 6).
- **Decided 2026-11-11:** Hind Siliguri for Bengali text and digits (ADR 9).

## 5. Platforms
**Decided 2026-11-11:** iPhone with layouts that adapt to any width (iPad, split view, foldables), then Android, then home-screen widgets.

## 6. Brand
Product name spelling (TakaDe), logo and app icon. The icon slot is currently empty.
- **Decided 2026-11-11:** Apple and Google sign-in in release 1, optional, kept on the device only (ADR 11).
- **Owner action:** Google OAuth iOS client id in `Config/Google.local.xcconfig`; paid Apple Developer Program for Sign in with Apple.
- **Decided 2026-11-11:** members can store an optional bKash, Nagad, Rocket, upay or bank number for others to copy when settling. Built: tap a person on the group screen to add numbers; Settle up shows them with Copy.
- **Decided 2026-11-11:** optional Face ID or passcode lock in Profile, off by default (ADR 14). Built.
