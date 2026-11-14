# Passkey website file

iOS makes a TakaDe passkey only for a website that says the app may use it. Once
`takadeapp.com` exists:

1. Replace `TEAMID` in `apple-app-site-association` with the paid Apple Developer team id
   (10 characters, from developer.apple.com > Membership). The team id is public, not a secret.
2. Serve the file, unchanged and with no `.json` ending, at
   `https://takadeapp.com/.well-known/apple-app-site-association`, over HTTPS, with
   `Content-Type: application/json` and no redirect. Apple's servers fetch it, so it must be
   public. Check with `curl -i https://takadeapp.com/.well-known/apple-app-site-association`.
3. Later, tappable invite links (`https://takadeapp.com/join?...`, ADR 0019) add an
   `"applinks"` section to the same file.

The rest of the setup is in `supabase/README.md` (Passkeys) and ADR 0035.
