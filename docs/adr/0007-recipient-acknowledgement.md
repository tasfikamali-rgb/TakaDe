# 7. Recipient acknowledgement settles a debt without claiming verification

Status: Accepted (2026-11-11). Idea credited to a parallel draft in this project.

New status `acknowledged_by_recipient`: the person who was owed marks the money as
received, for example cash in hand. Only the recipient can do it
(`Settlement.acknowledge(by:)` checks this; `transition(to:)` refuses it). It counts toward
balances and is **not** included in `unverifiedSettled`, because the person who would be
harmed by a false claim is the one making it. The UI calls it "Marked received by the
person paid", never "verified".

A payer's own report stays `reported_unverified`, as in ADR 4.
