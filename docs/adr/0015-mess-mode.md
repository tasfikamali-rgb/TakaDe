# 15. Mess mode

Status: accepted (Sabit asked threads to build features from the inspiration spec, 2026-11-11). Built local-only.

## Context
Many people in Bangladesh live in a mess: a shared flat or hostel where one manager buys the bazar, everyone's meals are counted every day, and at the end of the month the bazar is split by meals eaten. Rent, bills and the cook are split separately, usually equally. Members hand the manager deposits during the month. This is the main thing generic split apps don't do, and it fits local-only well because the manager keeps the books on one phone.

## Decision
- A group has a kind: standard (trip, flat, dinner) or mess. A mess has a manager, the person who created it.
- Meal counts are stored per person per day in half meals (`meal_count`, migration `v4_mess`), so a breakfast can count as half. Days are stored as text ("2026-11-05") so a count never moves with the time zone. Every change goes in the audit log.
- Bazar is any expense in the Bazar category dated in the month. The month summary splits each bazar expense by everyone's meals that month (`.shares` by half meals). Rounding is largest-remainder per expense, so every poisha lands on someone and the summary matches the ledger exactly. This replaces the spec's "remainder to the manager" rule, which would make the summary and the ledger disagree by a few poisha.
- "Split bazar by meals" applies that split to the month's bazar expenses as ordinary edits (version + 1, audited). Running it again after a meal count changes simply re-splits. Nothing is locked, so a mistake can be fixed.
- Rent, bills and other fixed costs stay as recorded, normally split equally.
- Deposits are recorded payments to the manager. When the manager records one on their own phone, it's marked received by them (ADR 7). It still isn't provider-verified.
- The summary (meal rate, meals and meal cost per person, who pays whom) can be shared to the mess chat as text from the share sheet.

## Consequences
- Each member's phone only knows what's recorded on it. Until sync (ADR 13), the manager's phone is the source of truth and members see the shared summary.
- The meal rate shown is rounded down to the poisha for display; the split uses exact shares.
