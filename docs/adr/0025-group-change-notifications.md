# 25. Notifications for changes in shared groups

Status: accepted (Sabit, 2026-11-12: "whenever there is a change in one of the groups and one
of the things they are owed, they should get a notification... app notification itself", not
SMS). Part 1 is implemented. Part 2 (push) is planned and needs a paid Apple Developer team.
Neither has been tried on a real phone yet.

## Context
Shared groups sync through the encrypted relay (ADR 19). Nobody hears about a change until
they open the group. Sabit wants an app notification when someone changes a group,
especially what they're owed. The relay must not learn names or amounts (ADR 13, 19), we
stay on the Supabase free plan, and the app is installed with a free Personal Team today.
A free team can't use the Push Notifications capability, so remote push isn't possible yet.

## Decision

### Part 1, built: the phone writes its own notifications
- Notifications are **local notifications** (`UNUserNotificationCenter`). When TakaDe syncs a
  shared group, it decrypts the changes with the group key, applies them, and only then
  decides what to say. Names and amounts never leave the phone for this.
- **What counts.** Only expenses and payments **someone else** changed, and only ones this
  person is in: an expense they paid for or have a share in, or a payment to or from them
  (`GroupNotice` in TakaDeCore). Group renames, people and meal counts don't notify. Nothing
  is sent while the phone hasn't chosen "which one is me". The first download of a group
  just joined or shared doesn't notify.
- **What it says.** Title: the group's name. Body: the first change ("Rafi added “Hotel”.
  Your share is ৳ 300.00."), "+ 2 more" when there are more, and where the person stands in
  the group now. Payments recorded by the payer say "says they paid you", because that's
  their word, not proof (CLAUDE.md principle 4). Names are shown as entered; amounts use
  the chosen language's digits. One notification per group; a newer one replaces it.
- **Privacy on screen.** iOS's own "Show Previews" setting applies. With TakaDe's app lock
  on, the notification only says "Something changed in a shared group", so it doesn't show
  what the lock hides. "Delete all my data" clears shown notifications.
- **Asking.** Never at launch. A shared group shows a "Know when this group changes" card
  that says what the notifications are for; "Turn on" then shows iOS's question. "Not now"
  hides the card for good. Settings > Notifications has the same switch.
- **When they arrive.** Whenever TakaDe syncs: while it's open (every 20 s on an open shared
  group, banners are skipped for the group on screen), when it comes back, and in
  **background app refresh** (`BGAppRefreshTask` `app.takade.refresh`, asked for about every
  15 minutes). iOS decides when background refresh runs; it can be hours, and it doesn't run
  after the app is swiped away or with Background App Refresh off. Background refresh works
  with a free Personal Team.

### Part 2, planned: push, for notifications within seconds
Needs the Apple Developer Program (US$99/year). Design, so the relay still learns nothing new:
1. Apple Developer: an APNs auth key (.p8). Sabit puts it straight into Supabase as an Edge
   Function secret. It never goes in the repo or a chat.
2. Supabase table `push_device` (sharing user id, APNs token, sandbox or production, updated
   time), row-level security so a phone sees only its own rows; removed with the idle-group cleanup (a year since ADR 27).
3. On each insert into `sync_change`, an Edge Function sends a push to the group's other
   members' tokens. The push carries only the group id and the change's sequence number,
   with `mutable-content` and a generic, localized fallback ("Something changed in a shared
   group"). Coalesced to at most one push per group per minute.
4. A Notification Service Extension on the phone fetches that change from the relay, opens it
   with the group key (shared through an App Group keychain) and rewrites the text with the
   same `NotificationText` as Part 1. If it runs out of time, the generic text shows.
5. What Apple and Supabase see in addition to today: that a phone got a nudge for a group id
   at a time. Not names, amounts or titles.
6. Cost: Edge Functions' free tier is 500,000 calls a month; one per change, fewer when
   coalesced. Fine for the 10k-user target; to check against real numbers before launch.

## Not built
- Part 2 above.
- Notifications for groups that aren't shared (nothing else changes them), friend requests,
  or messages.
- Per-group mute.
- SMS or email notifications (Sabit asked for in-app only).

## Checks before release
- Two phones: change an expense on one, see the notification on the other (open, in the
  background, and after background refresh).
- Bengali text reviewed with the rest of the string catalog.
- App Store privacy answers: local notifications collect nothing; recheck when push adds
  device tokens on Supabase (Part 2).
