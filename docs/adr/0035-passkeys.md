# 35. Passkeys: sign in with Face ID

Status: accepted (Sabit, 2026-11-14: "like the Luma app... add a passkey to make it seamless").
Built behind a switch that stays off (`TAKADE_PASSKEY_DOMAIN` empty) until the website and the
paid Apple account exist. Checked by the CI build and unit tests only; not yet run on a phone
or against the live Supabase project, because neither can be until those exist.

## Decision
- **Where:** after any sign-in to a TakaDe account (Apple, Google, Microsoft, email code), the
  app offers "Sign in with Face ID next time" in a short sheet, once per account on this
  phone, only if the account has no passkey yet. "Not now" closes it; Account > Passkeys
  always has "Add a passkey", the list, and swipe to remove. The sign-in screens (first launch
  and Account) get "Sign in with a passkey" under the other methods. Linking doesn't show it.
- **How:** Supabase Auth's own passkeys (beta, all plans, no extra cost), called over REST like
  the rest of `SupabaseAuth`, with no Supabase SDK. iOS's `ASAuthorizationPlatformPublicKey
  CredentialProvider` shows the passkey sheet. The JSON in and out is in
  `TakaDeCore/PasskeyWire.swift`, with unit tests.
  - `POST /auth/v1/passkeys/registration/options` and `/registration/verify` (signed in)
  - `POST /auth/v1/passkeys/authentication/options` and `/authentication/verify` → session
  - `GET /auth/v1/passkeys`, `DELETE /auth/v1/passkeys/{id}`
  Paths and bodies come from Supabase's own client (`@supabase/auth-js` 2.119.0), since the
  REST format isn't in the docs yet.
- A passkey signs in to an account that already exists. It never makes a new account.

## What leaves the phone
The passkey's private key stays in the person's iCloud Keychain. Supabase stores the public
key, a credential id and dates. Face ID itself never reaches TakaDe or Supabase. iOS shows the
account's email in the passkey sheet and in the Passwords app (from Supabase's options); the
name stays off the server as before.

## What has to happen before it's switched on
1. Buy `takadeapp.com`; serve `docs/passkeys/apple-app-site-association` with the team id.
2. Paid Apple Developer team. The Associated Domains entitlement (`webcredentials:takadeapp.com`)
   is in `App/TakaDe.entitlements`, which only Release builds use today. Phone builds are
   Debug, so when the paid team arrives, put the entitlements file on Debug too (the same step
   Sign in with Apple needs).
3. Supabase > Authentication > Passkeys on the main and spare projects (`supabase/README.md`).
4. `TAKADE_PASSKEY_DOMAIN = takadeapp.com`, then try add, sign in, remove on a phone.

## Open
- The nightly refill of the spare project copies `auth` tables chosen in ADR 0034. Check that
  passkey rows go too, or people sign in another way once after a switch.
- Supabase may require user verification settings later; today it asks for "preferred",
  which on iPhone always means Face ID, Touch ID or the passcode.
