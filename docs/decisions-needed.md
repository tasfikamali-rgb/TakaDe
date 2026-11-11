# Decisions needed

These block the next phases. The local-only MVP does not depend on any of them.

## 1. Sync and accounts (blocks: shared groups, invitations, notifications)
Pick one, per CLAUDE.md:
- **Stay local-only** for the first release; share by exporting a read-only summary.
- **Encrypted sync service**: clients encrypt ledger data; a small service stores ciphertext.
  Needs key recovery design.
- **Conventional backend** (e.g. a hosted database): easiest for collaboration, but the
  server can read data. Changes the "no central database" premise.

Recommendation: ship local-only first, then decide with real usage.

## 2. bKash, upay and bank settlement (blocks: any payment button)
No public peer-to-peer API is assumed. Needed per provider: official docs, merchant or
partner eligibility, sandbox credentials, callback signing, reconciliation rules, fees, and
legal review. Until then the app only records payments as "reported, not verified".
A first safe step could be showing the recipient's bKash number to copy, with no deep link.

## 3. Receipt OCR (blocks: scanning)
On-device (Apple Vision, nothing leaves the phone) or a cloud service (better accuracy,
needs disclosure and a processor review). Recommendation: on-device first.

## 4. Localization details
- A native Bengali reviewer for the string catalog (all strings are marked `needs_review`).
- Number grouping: 1,234,567 or lakh style 12,34,567?
- Default digits in Bengali UI: Bengali (১২৩) or Latin (123)?

## 5. Platforms
Android, widgets and foldables are planned but not started. Which comes after iPhone?

## 6. Brand
Product name spelling (TakaDe), logo and app icon. The icon slot is currently empty.
