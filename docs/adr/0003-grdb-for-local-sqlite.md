# 3. GRDB for local SQLite

Status: Accepted (2026-11-11)

## Context
We need SQLite with migrations and transactions on iOS. Options: raw `sqlite3` C API,
SwiftData/Core Data, or GRDB.

## Decision
Use GRDB.swift (MIT licence, actively maintained, pinned to an exact version). It gives
SQL-level control, schema migrations and safe concurrency without the hidden behavior of
Core Data. It is used only inside `TakaDePersistence`; nothing else imports it.

## Schema notes
- Expenses and settlements keep queryable columns plus a JSON `payload` that is the
  source of truth, so new split fields don't need a column migration each time.
- `audit_event` is append-only, enforced by SQLite triggers.
- Expenses are soft-deleted (`deleted_at`) so history stays intact.

## Encryption at rest
The database is **not** encrypted by the app. It relies on iOS Data Protection
(`completeUntilFirstUserAuthentication`), which encrypts the file while the device has not
been unlocked since boot. SQLCipher-level encryption is a future decision if the threat
model calls for it. Do not describe local storage as end-to-end encrypted.
