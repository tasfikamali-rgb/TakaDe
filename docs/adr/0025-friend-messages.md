# 25. Social tab: friends and encrypted messages

Status: accepted (Sabit, 2026-11-12: a Social tab between Groups and Activity listing people
you've added, where you can message friends; later the same day, a live "typing…"
indicator and low latency). Builds on ADR 16 (accounts on Supabase) and ADR 21 (TakaDe IDs).
Free plan only.

## Decision
- **Who's in Social:** people you add by TakaDe ID or QR code (in Social, or when adding them
  to a group by ID), and people who add you, shown under Requests until you accept, write
  back, or block. Kept in SQLite on the phone (`friend`, `friend_message`), per TakaDe
  account. Names are what you typed, or the name the other person gave, never changed.
- **Messages:** text only, up to 1000 characters. Each is sealed on the phone with HPKE in
  authenticated mode (CryptoKit, X25519, HKDF-SHA256, ChaCha20-Poly1305) to the friend's
  public key, using your own account key as the sender key. The friend's phone opens it only
  if it was sealed by the key the server says belongs to that ID, and pins that key; a later
  key change adds "X is using TakaDe on a new phone" to the chat.
- **Server:** `friend_message` holds the sealed message until the friend's phone collects it
  and deletes it (or 30 days). `send_friend_message` checks the limits (300 an hour, 2000 a
  day, 500 waiting per account) and drops messages from blocked senders without telling
  them. An ID nobody has counts as a lookup, so IDs can't be guessed by sending.
  `friend_inbox` returns waiting messages with the sender's current ID and public key.
- **Privileges** (same pattern as ADR 24, security review): the tables start from `revoke
  all`; the app's sign-ins may only read a waiting message's id, sealed text and time and
  delete their own. No insert or update; sending, blocking and the inbox go through
  `security definer` functions with an empty `search_path` and no dynamic SQL. Works the
  same whether `20261112030000_security_hardening.sql` runs before or after it.
- **Latency:** the message appears in your chat at once and sends in the background.
  A phone holds a Supabase Realtime connection only while a chat is on screen (Sabit,
  2026-11-12, so the Free plan's 200 concurrent connections serve far more people). Then
  Realtime pushes a "new row" event (row-level security applies) and the app fetches straight
  away. Elsewhere, an open app checks for messages when it opens or comes back, when the
  Social tab opens or is pulled down, and every 60 seconds while it stays in the foreground.
  A message to someone not in that chat can therefore take up to a minute to show. With the
  app closed, messages wait until it's opened: push notifications need an Apple Developer
  account and APNs, later. Group sync and group notifications don't use Realtime at all.
- **Typing:** while a chat is open, both phones join a Realtime broadcast channel named
  `typing-` + 16 bytes from HKDF over their shared X25519 secret. At most one signal every
  2.5 seconds while typing; the indicator hides after 6 seconds without one.

## Names and photos (Sabit, 2026-11-12, after testing on iPhone and iPad)
- Your QR code now carries your own name (`takade://friend?c=…&n=…`), so whoever scans it
  sees your name at once. It goes camera to camera, never through the server; the typed or
  shared ID still carries none.
- A hello carries your name and a 128 px profile photo (16 KB JPEG at most), sealed like a
  message. When someone accepts you, their phone sends its own name and photo back the same
  way. Never to someone not accepted, never in answer to a profile, so it can't loop.
- A name typed on this phone wins; otherwise the friend's own name is used, and their TakaDe
  ID shows until one arrives. Photos from friends are checked (one JPEG, at most 512 px) and
  kept on the phone only. Sealed messages may now be up to 40,000 characters.
- A hello that couldn't be sent is tried again each time the app opens.
- "Use my Google photo" asks Google in its own sheet and saves the photo on the phone; the
  sign-in service still gets no name or photo (Sabit chose this over automatic at sign-in).
- Photo updates (2026-11-12): setting, replacing or removing your photo sends a sealed
  `profile` envelope with your current photo to everyone in your chats; it's retried each
  time the app opens until all were sent. A hello or profile with no photo means the sender
  removed it. Friends' avatars redraw when one arrives.
- After a Google sign-in or link, the app asks "Use your Google photo?" when there's no
  photo yet (and once for people already signed in with Google). Yes opens Google's sheet for
  that account (`login_hint`), where Google asks to share the profile photo. The sign-in
  token sent to the account server still asks for email only, so it carries no name or photo.

## What the server can see
Who sends a message to whom and when, its size, and when a typing channel is used (not who
is in it, unless it matches connections to timing). Not names, text or the key to open it.
This hasn't had a security review, so the app says messages are "encrypted on your phone so
only your friend's phone can read them" and doesn't claim more.

## Not built
Group chats, photos, read receipts, push notifications, message deletion for both sides,
backup of chats (they're in "Export my data" and go with "Delete all my data").

## Setup
Run `supabase/migrations/20261112040000_friend_messages.sql` in the SQL editor.
