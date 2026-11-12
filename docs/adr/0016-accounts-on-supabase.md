# 0016: TakaDe accounts on Supabase Auth

Status: accepted (Sabit, 2026-11-11, on a decision card; confirmed "yeah go for it"). Plan: "TakaDe sign-in, user data and storage plan", sections "Adding email, Microsoft and more sign-in options" and "Separate Create an account and Sign in screens".

## Context
Sabit wants a separate Account section, Create an account and Sign in as separate choices, and sign-in with email and Microsoft as well as Apple and Google. Email sign-up needs a service that sends a code to the inbox, so an on-device-only account (ADR 11) can't do it. Supabase was chosen over Firebase (Google's SDK adds data collection to the privacy label) and over Microsoft-only (no email).

## Decision
- **What Supabase holds:** the account only. That's the user id, email, and which sign-ins are linked (`auth.identities`). No name or picture (Sabit, 2026-11-11): the name stays on the phone and in the groups. Email-code signup sends no name, Apple's name is used on the phone only, Google is asked for `openid email` without `profile`, and the app clears `name`, `full_name`, `picture` and `avatar_url` from `user_metadata` if an older version left them. Groups, expenses, payments and receipts stay in SQLite on the phone (ADR 1). The encrypted relay in ADR 13 will later run on the same Supabase Postgres, storing only ciphertext. That part is design only, not built.
- **Names are fixed** (Sabit, 2026-11-12): a name is required at first launch and can't be removed or changed afterwards. To use another name, the person makes a new account. New groups use it without asking. Each group can give anyone an optional nickname (`member.nickname`, migration v7), which never changes the name; shared groups carry it inside the encrypted group change. A profile from an older version with no name gets one chance to set it in Account.
- **No Supabase SDK.** The app calls Supabase Auth's REST (GoTrue) API with `URLSession` (`SupabaseAuth.swift`), so no third-party code joins the privacy manifest. The session (access and refresh tokens) is kept in the Keychain only (`AfterFirstUnlockThisDeviceOnly`). It is never stored in SQLite, logs or UserDefaults.
- **Methods:**
  - Email: a 6-digit code sent with `POST /otp`, then checked with `POST /verify`. There are no passwords.
  - Apple: native Sign in with Apple. The ID token goes to `POST /token?grant_type=id_token`, with a SHA-256 nonce: Apple gets the hash and Supabase the raw value.
  - Google and Microsoft (Azure): Supabase OAuth in `ASWebAuthenticationSession` with PKCE (S256). The callback is `takade://auth-callback`, and the code is exchanged with `grant_type=pkce`.
  - Google (2026-11-11): Supabase's web OAuth made Google's screen say "continue to yxsfbakrtmpsuuuuogbl.supabase.co", which Sabit found unprofessional. Google now uses the app's own iOS client (GoogleSignInService, PKCE, with a nonce) and hands the ID token to `token?grant_type=id_token` (provider google, `link_identity` to link), like Apple. The iOS client id is in the Google provider's Client IDs. If no iOS client is configured, the web flow is the fallback. Microsoft keeps the web flow.
  - Launch switches (2026-11-11): Microsoft is skipped for launch (Sabit; the university Azure account can't register apps), and email codes wait for a custom email sender on the takadeapp.com domain and the code template. Each sits behind an xcconfig flag (`TAKADE_MICROSOFT_SIGN_IN`, `TAKADE_EMAIL_SIGN_IN`), off by default, so the code path stays and the button is hidden.
- **Create an account vs Sign in:**
  - First launch (changed 2026-11-12, Sabit): after country and language, one screen offers Continue with Apple, Continue with Google, and Continue without account. The same button makes the account or opens an existing one. The name comes after that choice, prefilled with Apple's name when Apple sends one, and kept on the phone only. The Account tab still has separate Create an account and Sign in.
  - The wrong door is handled gently:
    - Sign in with a provider that has no account creates one (Supabase does this). The app notices the new account (`created_at` ≈ `last_sign_in_at`), says so, and asks for a name.
    - Create with an existing account signs the person in and says so.
  - Email Sign in uses `create_user: false`. The app shows the same message whether or not the address has an account ("If x has a TakaDe account, we've sent it a code"), so the screen can't be used to check who uses TakaDe. Signup errors for unknown emails are swallowed for the same reason.
- **Account tab** (Settings is now its own tab):
  - Shows the profile (name, email) and the linked sign-in methods. Removing one uses `DELETE /user/identities/{id}`, and the last one can't be removed.
  - Add a sign-in method:
    - Google and Microsoft use `GET /user/identities/authorize` with PKCE.
    - Apple uses the id_token grant with `link_identity`.
    - Email uses `PUT /user`, then an `email_change` code.
  - Also has Sign out, Export my data, Delete all my data, and Delete account.
- **Delete account:** a Supabase Edge Function (`supabase/functions/delete-account`) checks the caller's token and deletes that user with the service-role key, which lives only on Supabase. If the function can't be reached, nothing is removed on the phone, so the person can retry. The person can also erase all data on the phone.
- **On the phone:**
  - `local_profile` gains `account_id` and `account_email`.
  - A new `account_identity` table (migration v5) keeps provider, provider_user_id, email and linked_at, so the Account tab works offline.
  - Both tables are erased by Delete all my data and included in Export my data. Tokens are never included.
- **Without configuration:** if `Config/Supabase.local.xcconfig` is missing (today's builds), the same screens use the on-device Apple and Google link from ADR 11, and email and Microsoft are hidden.

## Privacy label
With accounts on, TakaDe collects these data types, linked to the person and used for App Functionality (account management):
- Email Address
- User ID

Name was dropped on 2026-11-11 when names stopped going to the service.

None are used for tracking. `PrivacyInfo.xcprivacy` declares them. The App Store Connect label must say the same at submission. The privacy policy must name Supabase as processor and its Asia-Pacific region. Groups and expenses are still not collected.

## Checks before release (from memory, re-check against current docs)
1. Linking Apple through `grant_type=id_token` with `link_identity` needs a recent Supabase Auth version. Test it on the real project.
2. Supabase's built-in email sender is rate-limited and for testing only. Set up custom SMTP and a sender domain before launch (CLAUDE.md email gate).
3. Apple's account-deletion guidance asks apps to revoke Sign in with Apple tokens. Supabase holds Apple's tokens for native sign-in only if it exchanged a code, and the app sends only the ID token. Confirm at submission whether revocation is still expected.
4. Price and limits: free tier at the start, about USD 25 a month on Pro. Quoted from memory, so check before upgrading.

## Owner actions
See supabase/README.md:
1. Create the project (done 2026-11-11; host in `Config/TakaDe.xcconfig`).
2. Put the anon key in `Config/Supabase.local.xcconfig`.
3. Set up the Apple, Google and Microsoft providers, the redirect URL, and manual linking.
4. Edit the email templates to show the code.
5. Deploy `delete-account`.
