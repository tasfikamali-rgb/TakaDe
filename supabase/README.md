# Supabase (accounts only)

TakaDe uses Supabase Auth for accounts: Create an account and Sign in with email (6-digit
code), Apple, Google or Microsoft. See docs/adr/0016-accounts-on-supabase.md. Supabase holds
only the account: id, email, name and which sign-ins are linked. Groups, expenses and
payments stay in SQLite on the phone.

Sabit created the project on 2026-11-11 (host `yxsfbakrtmpsuuuuogbl.supabase.co`, Asia-Pacific
region; the host is in `Config/TakaDe.xcconfig`). Nothing is deployed yet. Remaining steps:

1. **Anon key:** put the anon public key in `Config/Supabase.local.xcconfig` (see the
   `.example` file). Never put the service-role key in the app.
2. **Authentication > URL Configuration:** add `takade://auth-callback` to Redirect URLs.
3. **Authentication > Sign In / Providers:**
   - Email: on, "Confirm email" on. Edit the Magic Link and Confirm signup templates to
     show `{{ .Token }}` (the 6-digit code) instead of a link. Set up custom SMTP with the
     project's sender domain before launch; the built-in sender is for testing only.
   - Apple: on. Add the app's bundle id (`app.takade.ios`) as a client id. Native sign-in
     passes Apple's ID token, so no Services ID secret is needed for the app.
   - Google: on, with a **Web** OAuth client id and secret from Google Cloud (Supabase does
     the code exchange), and the iOS client id added to "Authorized Client IDs".
   - Azure (Microsoft): on, with an app registration from Microsoft Entra, tenant `common`
     so personal and work accounts both work.
   - Turn on **Allow manual linking**, so people can link more sign-ins from the Account tab.
4. **Functions:** `supabase functions deploy delete-account`.
5. Tell the coding thread, which then checks every flow on a phone.
