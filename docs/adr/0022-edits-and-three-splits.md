# 22. Visible edits, an edit log in Activity, and three ways to split

Status: accepted (Sabit, 2026-11-12: "where is the edit button in the groups and the settle
up?", edits should show in Activity with who edited what and the amount, and the split
screen should offer about 3 options instead of 5).

## Decision
- **Edit buttons.** Every expense row and every payment row in a group has a pencil button
  (44 pt) next to it, as well as the row itself opening the editor. Payments get a new Edit
  payment screen: amount, how it was paid and the transaction ID can be fixed; who paid whom
  and the status stay. A provider-confirmed or reversed payment can't be edited. Once the
  person paid has marked a payment received, only they can change its amount (the payer
  can still fix the method or ID), so an acknowledgement never silently covers a different
  amount. The same rule is checked again when a change arrives from another phone.
- **Who edited.** Expenses and payments carry `changedBy`, the group member who saved that
  version. It's a member id the group already has, inside the encrypted change, so the
  relay learns nothing new. Phones record it in History only when that person is in the
  group. It's a claim by the other phone, like everything else in a shared group, not proof.
- **What changed.** History already keeps a copy of the expense or payment after each
  change. Activity and History compare it with the copy before and list the differences
  (`ExpenseChange`, `SettlementChange` in TakaDeCore): name, amount (old → new), date, who
  paid, split, category, receipt photo; for payments amount, method, transaction ID and
  status. Nothing new is stored for this.
- **Activity** now lists expenses and payments added, edited and deleted across groups,
  newest first, instead of only expenses.
- **Three splits: Equally, Amounts, Shares.** Equal covers most bills (and leaving someone
  out is a toggle). Amounts covers "I had the biryani, you had tea". Shares covers a couple
  counting as two and any ratio (60/40 is 3 and 2 shares), which makes Percent redundant;
  Tricount offers the same set. Adjust (extras) was the least used and the hardest to
  explain. The ledger still understands percentage and adjusted rules, so older expenses
  and changes from not-yet-updated phones keep their balances; editing one opens it as
  Amounts with each person's exact share, so nothing moves unless the person changes it.

## Consequences
- A phone on an older build rejects a payment whose amount was edited (it required the
  amount to stay the same), so it shows the old amount until it's updated.
- `changedBy` from another phone isn't verified; a member could claim another member made
  a change. Signed changes would need per-member keys, which shared groups don't have yet.
