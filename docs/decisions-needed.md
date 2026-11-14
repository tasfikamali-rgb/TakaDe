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
**Decided 2026-11-11:** accounts on Supabase Auth: email code, Apple, Google and Microsoft, with a separate Account tab (ADR 16). Supabase holds only the account; groups stay on the phone. The relay will use the same Supabase Postgres, ciphertext only.
**Open, owner:** fill in the anon key in `Config/Supabase.local.xcconfig`, set up the providers and email templates, deploy `delete-account` (supabase/README.md). Until then builds use the on-device sign-in from ADR 11.
**Open, owner:** a sender domain and SMTP provider for the sign-in codes before launch (Owner materials 5).
**Decided 2026-11-11:** shared groups through the encrypted relay on Supabase, for every user; only shared groups leave the phone, idle ones are removed from the server after a year without changes (ADR 19, ADR 28).
**Open, owner:** run the shared-groups SQL and turn on anonymous sign-ins (supabase/README.md). Tappable https invite links wait on takadeapp.com and a paid Apple Developer account.
**Decided 2026-11-12:** app notifications (not SMS) when someone changes an expense or payment you're in, written on the phone so the relay learns nothing (ADR 25). Built as local notifications plus background refresh.
**Open, owner:** push, so they arrive within seconds, needs the paid Apple Developer Program and an APNs key that Sabit enters in Supabase (ADR 25, Part 2).

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
Product name spelling (TakaDe), logo and app icon.
- **Decided 2026-11-11:** logo and app icon are the split ৳ mark (ADR 17, files in `docs/brand/`).
- **Decided 2026-11-11:** Apple and Google sign-in in release 1, optional, kept on the device only (ADR 11).
- **Owner action:** Google OAuth iOS client id in `Config/Google.local.xcconfig`; paid Apple Developer Program for Sign in with Apple.
- **Decided 2026-11-11:** members can store an optional bKash, Nagad, Rocket, upay or bank number for others to copy when settling. Built: tap a person on the group screen to add numbers; Settle up shows them with Copy.
- **Decided 2026-11-11:** optional Face ID or passcode lock in Profile, off by default (ADR 14). Built.
- **Decided 2026-11-14:** passkeys (Face ID sign-in), offered after signing in and in Account (ADR 35). Built, switched off until takadeapp.com, the paid Apple team and Supabase's passkey settings exist.

## 7. Store accounts and release checks (blocks: testing on real phones, publishing)
- **Apple Developer Program** (US$99/year) for TestFlight and the App Store, and
  **Google Play Console** (US$25 once) for internal testing, the pre-launch report and Play.
  Decide whose name/entity owns them; it shows on the store listing.
- **Export compliance:** whether the app uses non-exempt encryption. Today it only uses the
  operating system's encryption, which is usually exempt, but the owner (with advice if
  needed) should confirm before we set `ITSAppUsesNonExemptEncryption`.
- **Privacy answers:** the App Store privacy label and Play Data safety form must match
  `App/Resources/PrivacyInfo.xcprivacy` ("no data collected") while the app stays local-only.
