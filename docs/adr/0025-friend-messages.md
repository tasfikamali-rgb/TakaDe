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
  Supabase Realtime pushes a "new row" event to the friend's open app (row-level security
  applies), which then fetches straight away. No polling. With the app closed, messages wait
  until it's opened: push notifications need an Apple Developer account and APNs, later.
- **Typing:** while a chat is open, both phones join a Realtime broadcast channel named
  `typing-` + 16 bytes from HKDF over their shared X25519 secret. At most one signal every
  2.5 seconds while typing; the indicator hides after 6 seconds without one.

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
