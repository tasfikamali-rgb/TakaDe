# 27. Shared groups get the receipt's text, not its photo; quiet groups kept a year

Status: accepted (Sabit, 2026-11-12: "when we scan it... turn it into... a text file, so that
it's smaller, and use a compression system wherever you feel you can"; "Just keep it like
English for the whole receipt thing... all the other around it can be in Bengali"; "make it
once a year"). Built; checked by unit tests and the CI build, not yet on a real phone.

## Why
A receipt photo is 100 to 240 KB on the relay (JPEG, then base64). At 10,000 users with 1 in
10 shared expenses photographed, photos alone would add about 800 MB a month, far past the
Supabase Free plan's 500 MB database. The receipt's text is what people check.

## Decision
- **Text, not photo.** Before a shared expense goes up, the phone reads the receipt photo with
  Apple Vision (already used for scanning, ADR 8), and uploads only the lines of text:
  JSON `{"v":1,"lines":[...]}`, zlib-compressed, sealed with the group key (AES-GCM, its own
  authenticated context `takade.receipt-text.v1`), prefix `t1.`. Usually 0.5 to 2 KB instead
  of 100 to 240 KB: roughly 100 times smaller. Same `sync_receipt` table, so no schema change.
- The photo **stays on the phone that took it**. That phone shows the photo; everyone else
  sees "Receipt text", the lines exactly as read, in a monospaced list they can select.
- The text is read once and kept next to the photo (`<id>.receipt`, compressed), so it isn't
  re-read on every sync.
- Photos uploaded by earlier builds (`v1.` prefix) still open as photos.
- **English receipts.** The scanner reads English only (`en-US`), and the receipt's own words
  and amounts (including in the review screen) are shown as printed, with Latin digits,
  never translated. Headings, buttons and notes around them follow the app language.
- Untrusted input: at most 400 lines of 300 characters and 64 KB once decompressed (bounded
  inflate, ADR 24); the text is only shown, never turned into amounts.
- **Quiet groups kept a year.** The nightly cleanup now removes a shared group only after 365
  days with no change (was 90), because many groups are used monthly or yearly. Migration
  `20261112050000_keep_groups_one_year.sql` must be run in the SQL editor. Sharing sign-ins
  are removed after 7 days only when they're in no group, so a quiet group's members are
  never signed out by it.
- Compression elsewhere: expense changes were already zlib-compressed before sealing (ADR 19);
  friend messages are small sealed text. Switching to a stronger compressor (LZMA) would save
  little on such small rows and is harder for the Android app, so zlib stays.

## Consequences
- Friends can't see the photo itself, only its text. A blurry photo may give poor or no text
  ("No text could be read from this receipt").
- Storage at 10,000 users becomes about 110 MB after a month plus about 50 MB a month of
  expense changes; receipt text adds only a few MB a month. Keeping quiet groups a year means
  less is cleaned up, so the 500 MB limit is reached in roughly 7 to 8 months of steady use;
  trimming old changes that every member already has is the next saving if needed.
- The server could reject photo-sized uploads with a tighter `sync_receipt` size check; not
  done yet, so older builds keep working.
