# 27. Deleting a group, and who may

Status: accepted (Sabit, 2026-11-12: "whoever made the group should have the ability to
delete the group"). Built; covered by persistence tests and the CI build, not yet tried on
two phones.

## Decision
- Groups record their maker (`ExpenseGroup.createdBy`, column `created_by`, migration
  v10). It's set once and a synced snapshot can't change it. Older groups fall back to the
  first person listed, which the app has always made the group's maker.
- **Group not shared:** it lives only on this phone, so the phone's owner can delete it.
- **Shared group:** only the maker sees Delete group. The phone seals a `.groupDeleted`
  change (who deleted it, when) with the group key and sends it to the relay, then leaves
  the relay group. Every other phone, on its next sync, checks the change comes from the
  group's maker, deletes the group and leaves too. The relay drops the group when the last
  phone leaves (existing trigger), or after 90 idle days. No Supabase change is needed.
- Deleting removes the group, people, expenses, payments, meal counts, queued sync
  changes, the group's history (the one exception to append-only history, like Delete all
  my data) and the cover, member and receipt photos on the phone. It asks first and can't
  be undone. A shared group needs the internet to delete; offline, nothing is deleted.

## Limits
- The check that the maker sent the deletion relies on the group key, like every other
  shared change: someone with the key could forge it. Same trust model as edits (ADR 19).
- A phone that never syncs again keeps its copy.
- People who aren't the maker can't remove a shared group from their phone yet (no Leave).
