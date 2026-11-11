# 4. Settlement status and what counts toward balances

Status: Accepted (2026-11-11)

## Decision
Settlements carry a status: `not_started`, `handoff_started`, `pending`,
`reported_unverified`, `confirmed`, `failed`, `reversed`. Moving to `confirmed` (and from
`confirmed` to `reversed`) requires provider evidence. No provider integration exists, so in
this MVP the app can reach `reported_unverified` at most. The storage layer additionally
refuses any confirmation it is asked to save.

Balances count `reported_unverified` and `confirmed` settlements, because otherwise a
local-only app could never show a debt as paid. The UI must always label reported payments
as "reported in TakaDe, not verified" and `GroupBalances.unverifiedSettled` exposes how much
of each balance relies on such reports.

## Consequences
When a provider integration exists, it is the only code path allowed to pass
`withProviderEvidence: true`.
