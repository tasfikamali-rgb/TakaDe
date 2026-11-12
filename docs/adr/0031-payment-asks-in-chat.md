# 31. Payment requests and proof requests in Social chats

Status: accepted (Sabit, 2026-11-12: "some option inside the chat to send directly the group
and ask them to give you the money and they settle up using that", and "an option that says
message him to send proof"). Built; checked by the CI build, not yet on a real phone.

## Decision
- **Ask in Social.** In Settle up, when someone owes you, "Ask *name* in Social" sends a payment
  request into your chat with them. It carries the group, who pays whom, the amount and your
  wallet numbers. In their chat it shows as a card with the amount, the numbers with Copy, and
  **Settle up**, which opens that group's settle-up screen with your payment picked.
- **Ask for proof.** When someone recorded paying you and you haven't tapped "I got it", the
  Payments card offers "Ask for proof". The card in their chat has **Send transaction ID**: the
  ID is saved on their payment in the group (so it syncs to everyone) and sent back in the chat.
  Chats are text only, so a screenshot isn't possible inside TakaDe; the transaction ID is the
  proof that can be checked against the wallet's history. It's still their word, never a check
  with bKash, Nagad or upay (ADR 0030).
- **Status without extra messages.** Each card works out its own state from the group's
  payments on that phone: "Not paid yet", "Recorded as paid, not confirmed yet", "Received", or
  the transaction ID. A pay request is answered by any payment from that person to the asker
  recorded after it was sent. Nothing is sent automatically and there are no repeated reminders;
  asking again is a tap, so it can't turn into spam.
- **Which chat.** Groups don't store TakaDe IDs, so the chat is found by the person's name in the
  group (ignoring case and spaces). If no chat or several match, you pick the chat. The numbers
  in a request are offered on the settle-up screen as the asker's numbers only when the chat is
  the one this phone links to that name; otherwise they show in the card as "Numbers *friend*
  sent", so a friend can't pass off their own number as someone else's.
- **Privacy and size.** The request rides inside the existing sealed chat message
  (`FriendEnvelope.ask` on a `.text` envelope): the server sees only the usual sealed blob and
  deletes it once collected. No new tables or columns on Supabase. On the phone, `friend_message`
  gains an `ask` JSON column (migration v12). Older app versions ignore the field and show the
  words, which say the same thing.
- **Checked input.** An incoming request is untrusted: amounts must be positive, payer and payee
  different, numbers pass the same checks as saved ones, and a card only offers Settle up or
  Send transaction ID when the group is on this phone and this phone's person is the payer.

## Later
- Group chats: Social has one-to-one chats only, so a request goes to one person.
- Web links that open a group from any browser once the TakaDe website is live (Sabit,
  2026-11-12). Today's invite links need the app.
- Photo proof in chat would need image messages (storage on the server), which the Free plan
  budget doesn't cover yet.
