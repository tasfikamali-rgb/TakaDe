# 28. Activity as a message feed, an unread number, and the ৳ refresh

Status: accepted (Sabit, 2026-11-12: "whenever someone changes anything ... it should go in
the activity section as one, like a chatbot thing. Whenever there is a new change, you get a
notification, and inside the activity section it should say one ... there should be a
refresh toggle ... rather than a circle refreshing, the logo going 360"). Built; checked by
unit tests and the CI build, not yet on a real phone.

## Decision
- **Feed.** Activity shows each expense or payment change as one message bubble, grouped by
  day, newest first. Changes made on this phone sit on the right; other people's sit on the
  left with that person's picture (or the group's icon when the author isn't known). The
  wording and the before → after lines are the same as before (ADR 22). Newest first is kept,
  not chat order, so pulling down at the top is where new things appear.
- **Unread number.** `ActivityInbox` counts changes from other phones as they're applied
  (`GroupSync.onChangesFromOthers`), leaving out the person's own changes made on another
  phone and a group's first download when joining. The number shows on the Activity tab (the
  pill bar and the system tab bar) and on the app icon, and clears when Activity is opened.
  Those entries say "New" (text and a dot, never colour alone) until Activity is opened
  again. Only the count is stored, in UserDefaults on the phone.
- **Notifications for every change.** ADR 25 only notified about expenses and payments the
  person was part of. Now every change someone else makes in a shared group notifies, still
  written on the phone after decryption: an expense you're not in reads "Rafi added “Taxi”.",
  a payment between two others reads "Rafi says they paid Nila ৳500." (their word, not verified). Your own changes from another
  phone still say nothing, and the app lock still hides the details.
- **Checking more often, without live connections.** While the app is open, shared groups are
  checked once a minute (one small request per shared group). No Realtime channel is opened
  for this, so it doesn't count against the free plan's 200 connections (ADR 25, PR #47).
- **Refresh.** Activity, Groups, a group's page, Social and Account refresh by pulling down.
  There's no refresh button (Sabit, 2026-11-12: "just scrolling up means refresh"). The system
  spinner is hidden app-wide and replaced by the ৳ mark, which turns
  with the pull and then a full 360° per lap until the check finishes. With Reduce Motion it
  stays still. iOS 18 and later read the pull from the scroll view; on iOS 17 the system
  spinner shows during the pull and the mark turns while refreshing.

- **Photos in Activity.** A member's picture is their contact photo on this phone, else the
  photo of the one TakaDe friend with exactly the same name (matched on the phone), else their
  initial. Social uses an inline title like Account, so the ৳ sits right under the bar.

## Not done
- Instant delivery still needs push (ADR 25 part 2, paid Apple account).
- Group renames and new members aren't counted or shown in Activity yet; they stay in the
  group's History.
