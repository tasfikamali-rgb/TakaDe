# 29. New groups add real people, two clear kinds, iPhone stays upright

Status: accepted (Sabit, 2026-11-12: "adding like a generic [name] doesn't make any sense
because that person is not real ... it should be search option or contact option ... QR code
scanning ... invite by email"; "Strip or flat ... write generic fancy terms like hangout ...
trip"; "The iPhone or Duo should not have landscape mode. Only the iPad"). Built; checked by
the CI build, not yet on a real phone.

## Decision
- **No free-text names on the new-group screen.** People come from a real place:
  - **Search** one box over your TakaDe friends (the Social tab's accepted friends) and, if
    Contacts access was given, your contacts' names. With the box empty it suggests up to six
    friends. The box never asks for Contacts on its own; a "Search your contacts too" row asks
    when you're typing and access hasn't been decided yet.
  - **Pick from contacts** opens the existing multi-select sheet (ADR 22): only picked people's
    photo and BD mobile are read, on the phone.
  - **Scan a TakaDe QR code** adds that account; the name in their QR code is used, or the one
    you gave them as a friend, or you type one when the code has none.
  - **Invite by email** collects addresses on the screen only. After the group is made, Apple's
    mail screen (or another mail app via `mailto:`) opens with the group's 7-day invite link;
    the email goes from the person's own account, so there's no email service or cost, and the
    addresses are never stored. They join with their own name (the existing join sheet).
- **TakaDe people get their invite on Create.** The group is saved, its invite link made
  (which makes it a shared group, ADR 19), and each TakaDe user gets the sealed friend invite
  with their member ID (ADR 21), as "Add a TakaDe user" already did on the group page. If the
  invites can't go (offline), the group stays made, the screen says so and offers Done.
- **Two kinds, shown as cards with a line each.** "Hangout or trip" (bills split as they come)
  and "Mess" (meals counted daily, bazar shared by meals). They're the only two that behave
  differently, so more labels for the same behaviour (trip, flat, hangout) would be choices
  without a difference. The stored `GroupKind` is unchanged.
- **Icon on the cover.** The group icon now sits inside the cover's corner with a hairline
  edge instead of overlapping the cover with a background-coloured ring, which looked like a
  stray circle on iPad's textured sheet background.
- **Orientation.** iPhone (including the foldable iPhone Duo) is portrait only; iPad keeps all
  four orientations, which iPad multitasking needs (`scripts/ci/store_check.py`).

## Consequences
- The group page's own "Add a person" is unchanged for now (it still allows a typed name).
- UI flows add Apple's sample simulator contact "Kate Bell" instead of typing a name, with
  Contacts allowed in `launchApp`.
- Bengali strings are drafted and marked for native review.
