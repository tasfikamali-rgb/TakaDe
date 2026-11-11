# 0011: Optional Apple and Google sign-in, kept on the device

Status: accepted (Sabit, 2026-11-11). Plan: "TakaDe sign-in, user data and storage plan" (Claude Doc).

## Context
Sabit wants login and sign-up in release 1 while each person's data stays with them. There is no TakaDe server, and the sync model (CLAUDE.md gate) is not chosen yet.

## Decision
- **Onboarding:** language, then Sign in with Apple or Google, or "Continue without account", then the person's name (prefilled from the provider, editable, stored exactly as typed). App Review 5.1.1: no account is forced, since the ledger works without one. 4.8: Sign in with Apple is always shown first, and whenever Google is.
- **On the device only.** The profile keeps the provider, the provider's user id and an optional email in SQLite (`local_profile`, migration v2). Nothing is sent to a TakaDe server, because none exists.
- **Google without an SDK.** "Continue with Google" uses `ASWebAuthenticationSession` with PKCE (OAuth 2.0 for native apps). The ID token comes straight from Google's token endpoint over TLS; the app checks `aud` and `iss` and reads `sub`, `email` and `name`. The refresh token is kept in the Keychain (`AfterFirstUnlockThisDeviceOnly`) only so it can be revoked. The Google Sign-In SDK was rejected: its privacy manifest declares name, email, phone number, user id, coarse location and "other data" (including for analytics) as collected and linked, and it pulls in App Check and GoogleUtilities.
- **Apple:** `SignInWithAppleButton`; name and email arrive only on the first authorization. The authorization code is never exchanged, so the app holds no Apple tokens. On launch, `credentialState(forUserID:)` unlinks the account if the person revoked it in iOS Settings. The entitlement is on Release builds only, because free Apple ID teams can't use the capability; Debug builds show a short "didn't work, continue without an account" message instead.
- **Profile > Account:** sign out (forgets the link, revokes Google, clears the Keychain) and Delete account (the same, plus an option to erase all data). **Profile > Your data:** Export my data (JSON via the share sheet, with a warning that the file leaves TakaDe's protection) and Delete all my data (every row and the history, then `VACUUM` so deleted rows don't linger in free pages).
- **At rest:** the database folder is created with Data Protection `completeUntilFirstUserAuthentication`, so the file and its journal are encrypted until the phone is first unlocked after a restart. That is the whole claim; nothing stronger.
- **Payment handles:** `payment_handle` (bKash, Nagad, Rocket, upay, bank) exists in the schema for the settle-up copy feature. Wallet numbers must be 11-digit Bangladeshi mobiles, which also refuses anything PIN-shaped. No UI yet: Sabit hasn't decided on storing payment numbers.

## Open checks before submission
1. **Apple token revocation.** Apple asks apps with account deletion to revoke Sign in with Apple tokens through its REST API. That needs a server with a client secret and tokens from exchanging the authorization code. This app never exchanges the code and holds no tokens, so there is nothing to revoke; the person can also stop using Apple ID with TakaDe in iOS Settings. This reading is from memory: re-check Apple's current account-deletion guidance at submission, and revisit when a server exists.
2. **Privacy label.** Without the Google SDK, TakaDe itself sends nothing anywhere, and sign-in data goes only between the phone and Apple or Google. Whether the label can still say "Data Not Collected" depends on Apple's definition of collection for sign-in identifiers kept on the device; confirm at submission.

## Owner actions
- Google: create an iOS OAuth client (bundle id app.takade.ios) in Google Cloud and put its id in `Config/Google.local.xcconfig`. Until then the Google button is hidden.
- Apple: Sign in with Apple needs the paid Apple Developer Program and the capability on the App ID.
- Google's branding rules ask for the official "G" logo on the button; add the asset from Google's branding page before release.
