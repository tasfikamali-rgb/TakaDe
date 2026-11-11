# 1. Local-only MVP with no account or server

Status: Accepted (2026-11-11)

## Context
CLAUDE.md prefers local-first SQLite with no central database, and says sync, identity and
invitations need an explicit product decision before any service is introduced.

## Decision
The first release stores everything on one device. There is no account, no server, no
network access. Group members are local records, not users. The storage boundary is the
`LedgerRepository` protocol so a sync-capable implementation can replace it later.

## Consequences
- Useful alone (one person tracking a trip), but other members can't see the group.
- No push notifications, invitations or email. Sharing will start as an export/snapshot.
- Choosing a sync model is the next gating decision (see docs/decisions-needed.md).
