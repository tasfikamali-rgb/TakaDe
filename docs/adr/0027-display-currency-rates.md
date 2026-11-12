# 27. Show the balance in another currency with daily public rates

Status: accepted (Sabit, 2026-11-12: "the BDT button on top... the ability to change it to any
other currency... changes every time you open the app... it doesn't go through the back end
for every device"; "use that toggle... between BDT and the pounds with the logo... make the
BDT option a bit bigger"). Built; checked by unit tests and the CI build, not yet on a real
phone.

## Decision
- **Display only.** The home header's currency chip is now a two-sided toggle, `৳ BDT` and
  the person's other currency (`£ GBP`). Switching converts the *shown* total. The ledger is
  untouched: every expense, split, balance and settlement stays in the currency it was
  recorded in, as integer minor units. A converted figure is never stored, exported, shared
  or used to settle.
- **Source.** [fawazahmed0/exchange-api](https://github.com/fawazahmed0/exchange-api)
  (CC0, no key, no rate limit, updated daily). The phone downloads one public file, the
  BDT table (about 6 KB): jsDelivr first, then the project's Cloudflare mirror
  (`latest.currency-api.pages.dev`), as its README asks.
- **Straight from the phone.** Nothing goes through Supabase or any TakaDe server, so the
  backend has no cost or load from this. The request has no cookies and no body; it carries
  no names, amounts, account or device ID. The CDN sees the phone's IP address and that it
  asked for the BDT table, like any web request.
- **When.** Every time the app opens (or comes back to the front) and the header is set to
  the other currency, and when the person switches to it. People who never use it make no
  request. Skipped if the last download was under a minute ago.
- **Offline.** The last good table is kept in Application Support and used until a new one
  arrives. Under a converted total the header always says which rate it used and its date,
  e.g. "£1 = ৳166.91 · rate from 11 Nov", adding "offline" when the latest try failed. With
  no rates at all it shows taka and says to connect.
- **Not real time.** No free source has second-by-second taka rates; this one is daily.
  That's fine for seeing roughly what a balance is worth; it is not a quote for sending
  money.
- **Untrusted input.** The download is size-capped (256 KB), must have a valid date and the
  BDT table, and only positive numbers are kept. Conversion uses `Decimal`, rounds half away
  from zero to the target's ISO decimals (JPY 0, KWD 3), and gives up rather than overflow.
- **Picker.** Only currencies some country uses today (per iOS) and that have a rate are
  listed, so crypto, metals and retired currencies are left out. Popular ones for
  Bangladeshis abroad come first. The first guess is the currency of the country picked at
  onboarding, or US dollars for Bangladesh.
- "Delete all my data" clears the choice and the cached table.

## Consequences
- No new dependency, no key, no cost. If the source disappears, the toggle keeps showing
  the last rates with their date, and taka is always available.
- Only the home total converts. Group screens still show each group's own currency.
- Bengali strings are drafted and need native review.
