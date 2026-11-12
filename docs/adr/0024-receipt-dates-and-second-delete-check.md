# 24. Receipt dates can't be in the future; wiping data asks twice

Status: accepted (Sabit, 2026-11-12: "whenever we scan receipts, we should not be able to put
future dates in" and "you should be asked again before deleting everything").

## Decision

- **Receipts are dated today or earlier.** A receipt is printed when you pay. The receipt
  reader skips any date after today (usually a misread, or a "valid till" or delivery date on
  the slip) and keeps looking on the following lines. The receipt review date picker stops at
  today.
- **An expense with a receipt photo can't be dated after today.** Adding a receipt moves a
  future date back to today, the date picker stops at today, and the saved date is clamped too.
- **An expense without a receipt can still have a future date**, for things like rent due next
  week or a planned trip.
- **Wiping all data asks a second time.** "Delete all my data" → "Delete everything" and
  "Delete account" → "Delete account and all my data" both lead to a final "Are you sure?" with
  "Yes, delete everything" and "Keep my data". Deleting the account but keeping groups, and
  deleting a single expense (which can be undone), still ask once.
