# 14. Optional Face ID or passcode lock

Status: accepted (Sabit, 2026-11-11). Built.

## Context
A phone left unlocked shows every balance and name in TakaDe. Some people want a second lock, others find one annoying.

## Decision
Profile > Lock offers "Lock with Face ID" (or Touch ID, Optic ID, or passcode, whichever the phone has). It's off by default, and turning it on asks for one successful check first so nobody locks themselves out. It uses `LAContext` with `.deviceOwnerAuthentication`, so the phone passcode is always the fallback. TakaDe never sees or stores the passcode or face data.

When it's on, TakaDe locks once it goes to the background and asks again when it comes back. Whenever it isn't in front, a plain cover with only the app name sits in its own window above everything, so the app switcher snapshot and any open sheet show no balances or names.

## Consequences
- The lock protects the screen, not the file: the database is still protected by iOS Data Protection (ADR 11), not by the lock.
- The setting is a plain preference in `UserDefaults`; it isn't a secret.
- The cover covers the first window scene. If iPad multi-window is added, each scene needs its own cover.
