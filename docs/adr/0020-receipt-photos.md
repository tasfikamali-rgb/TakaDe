# 20. Receipt photos on expenses

Status: accepted (Sabit, 2026-11-12: "you should also have the receipt uploaded so that other
people can trust how much you actually paid"; keep within the Supabase free plan). Builds on
ADR 8 (on-device receipt reading) and ADR 19 (shared groups).

## Decision
- After a scanned receipt is reviewed, its photo is kept with the expense (`Expense.receiptID`).
  The form shows it, it opens full size, and it can be removed.
- On the phone: a grayscale JPEG, at most 1400 px on the long side, quality lowered until it
  is under 180 KB (usually 60 to 150 KB), with no metadata (no location). Stored as a file in
  the protected `Ledger/Receipts` folder, never in the photo library or SQLite. Delete all my
  data removes the folder.
- In a group nobody was invited to, the photo never leaves the phone.
- In a shared group, the photo is sealed with the group's key (AES-GCM, group and receipt id
  as authenticated data, no extra compression) and uploaded to `sync_receipt` before the
  expense change that points to it. Other phones download it the first time someone opens
  the expense, then keep it.
- Photos are in a Postgres table, not Supabase Storage, so they cascade away with their group
  in the 90-day idle cleanup (ADR 19). Supabase doesn't allow deleting Storage files from SQL,
  so Storage would need a separate cleanup service.

## Storage
About 120 KB per photo once base64-encoded. On the free plan's 500 MB database that is roughly
3,000 photos alongside the expense changes. `select * from public.sync_storage();` shows the
space used. If photos become common, the options are moving them to Storage (1 GB free) with
an Edge Function for cleanup, or the Pro plan (8 GB).

## Not yet
- A photo for an expense typed in by hand, with no scan (could reuse the same picker).
- Export: Export my data includes the receipt id, not the image.
- An old photo that is replaced or removed stays on the phone and the relay until the group
  is cleaned up.
