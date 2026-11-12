# 26. Group icons come from the group's name; the photo is a cover

Status: accepted (Sabit, 2026-11-12: "If we write car, emoji of the car will pop up in the
group photo... when we add a group photo, it becomes a cover photo... you don't have the
ability to change that... if you cannot find any... add our company TakaDe logo"). Built;
checked by unit tests and the CI build, not yet on a real phone.

## Decision
- **Icon.** `GroupIcon.emoji(for:)` in TakaDeCore picks one emoji from the group's name with
  an on-device word list (about 60 icons, English, Bangla written in English letters, and
  Bengali). Occasions and places are checked before general words, so "Cox's Bazar trip" is
  🏖️ and "Office iftar" is 🌙. An emoji typed into the name wins. No match shows the TakaDe
  mark in the brand blue.
- Words match whole: "Cards" is not "car". English allows -s/-es; Bengali allows common
  case endings (গাড়ির, বিয়েতে, ঈদের) compared by code point, so বাসা (home) isn't বাস (bus).
- The icon is **not stored and not editable**. Every phone derives it from the name, so a
  shared group shows the same icon everywhere with no sync change, and renaming updates it.
- **Cover.** The group photo is now a 2:1 banner (at most 1200 px wide, JPEG) across the top
  of the group screen, with the icon overlapping its lower edge. Photos saved earlier were
  square and are cropped to fit. The group still takes its colour from the photo. Covers
  stay on this phone, as before (ADR 19 doesn't carry them).

## Consequences
- No downloads or image assets: the list is a few kilobytes of code.
- A name can get a surprising icon; the list is easy to adjust and is covered by tests.
- Bengali strings for the cover photo controls are drafted and need native review.
