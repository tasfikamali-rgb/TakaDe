# 32. Shop names from scanned receipts, counted for ad insights

Status: accepted (Sabit, 2026-11-12: "whenever someone scans ... if the company name arises,
just [keep] that one, because we have an intention to put ads in the future in the app").
Built; checked by unit tests and the CI build, not yet on a real phone. The Supabase SQL must
be run by the owner.

## Decision
- **Opt-in, off by default.** After the first scan where the person confirms a shop name, the
  app asks once: "Share shop names?" with equal "Share shop names" / "Don't share" buttons.
  Settings > Data and export has the same switch. Nothing is sent until they say yes. Only
  asked when the phone has a sign-in (an account or a sharing sign-in); guests without one
  are never asked and nothing is sent.
- **Only the confirmed shop name.** The name from the review screen, after the person checked
  or edited it. It is trimmed, single-spaced and lower-cased (`StoreName.normalized`, repeated
  in SQL). The person's home country from onboarding (`ZZ` for "Somewhere else") goes with it.
  No amount, date, items, receipt text or photo.
- **Counts, not records.** `store_name_count (month, country, name, scans)` holds no user id,
  so a row can't be traced to a person. `top_store_names()` (owner only, from the SQL editor)
  hides names seen fewer than 5 times, so a rare name can't single someone out.
- **Spam limit without a trail.** `store_name_usage` keeps one row per sign-in: today's date
  and how many names were sent (limit 30 a day). It never holds a name. It's deleted with the
  account.
- **Size.** About 50 bytes per shop, country and month. Thousands of shops a month is still a
  few MB a year, so no compression is needed.

## Why not link names to the email or user id
Linking purchase history to a person for advertising needs a stricter consent flow and, if
ever combined with other companies' data or ad networks, Apple's App Tracking Transparency
prompt. Bangladesh's Personal Data Protection Ordinance 2025, and GDPR for users in the UK and
EU, ask for consent and purpose limits on personal data. Unlinked counts answer "which shops
do people use, where" without being personal data about anyone. If per-person ad targeting is
ever wanted, it's a new decision.

## Store and legal checks before release
- **App Store privacy label:** Purchases > Purchase History: collected, *not linked to you*,
  *not used for tracking*, purposes Analytics and Developer's Advertising or Marketing.
  Matches `PrivacyInfo.xcprivacy`.
- **Google Play Data safety (Android):** Financial info > Purchase history: collected,
  optional, purposes Analytics and Advertising or marketing, not shared.
- **Privacy policy (not written yet):** say shop names are collected only with consent, what's
  sent, that it's counted without identity, how to turn it off. Counsel to review.
- When ads actually ship, re-check: an ad SDK may itself collect data and need its own label
  entries, and possibly ATT.

## Limits
- The request is made with the sign-in token (for the spam limit), so at that moment the
  service could see who sent it; only the count is stored. Server logs on Supabase may keep
  request metadata for a short time, not the request body.
- Turning the switch off stops new names; counts already added can't be removed per person,
  since they aren't linked to anyone.
