# 0009: Hind Siliguri for Bengali text

Status: accepted (Sabit, 2026-11-11)

## Context
Ranade and Author have no Bengali glyphs. Without a pairing, Bangla text and Bengali digits fall back to the system Bengali face, which makes the Bangla app look like a different product.

## Decision
Bundle Hind Siliguri (Regular, Medium, SemiBold; SIL Open Font License, so the files and OFL.txt are committed in App/Resources/Fonts/HindSiliguri).

- In the Bengali interface, Author roles use Hind Siliguri at the same weight, and display roles (titles) use its SemiBold.
- Amounts follow the digit setting, not the language: Bengali digits use Hind Siliguri, Latin digits keep Ranade. The ৳ sign always comes from Hind Siliguri, since it is a Bengali character.
- Sizes and Dynamic Type behave the same as the Latin faces (`Font.custom(_:size:relativeTo:)`).

## Consequences
Latin names inside the Bengali interface render in Hind Siliguri's Latin, which is consistent within a screen. Bengali names typed into the English interface still fall back to the system face; a font cascade would fix that but loses Dynamic Type scaling in SwiftUI, so it is left for later.

## Latin faces are not in git
Ranade and Author come from Fontshare under the ITF Free Font License, which allows use in apps but not redistributing the font files, so they stay gitignored and `scripts/fetch-fonts.sh` downloads them. Builds without them fall back to SF. Screenshot and release builds must run the script first; the store-readiness check should fail when the files are missing.
