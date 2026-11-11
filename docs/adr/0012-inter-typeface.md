# 0012: Inter for Latin text and numbers

Status: accepted (Sabit, 2026-11-11)

## Context
Sabit didn't like Ranade and Author and asked for a modern font of the kind big fintech companies use. Ranade and Author also couldn't be committed (their licence forbids redistributing the files), so CI and fresh clones built with the system font.

## Decision
Use Inter, the open-licensed grotesque many fintech and product teams use (Wise and Revolut-style interfaces), from Google Fonts' variable Inter 4. Static instances are cut from it with fontTools and committed under `App/Resources/Fonts/Inter` with OFL.txt:

- `InterDisplay-SemiBold` (optical size 32): balances, keypad amounts, titles.
- `Inter-Regular`, `Inter-Medium`, `Inter-SemiBold` (optical size 14): interface text.

Inter has tabular figures, which `.monospacedDigit()` turns on, so amounts don't jitter. Hind Siliguri stays for Bengali (ADR 0009). `scripts/fetch-fonts.sh` is gone: every font the app uses is in git, so CI screenshots show the real design.

## Consequences
Static instances keep `Font.custom(_:size:relativeTo:)` and Dynamic Type working without variable-font axes in SwiftUI. To change weights, cut a new instance from the variable font rather than synthesizing bold.
