# 16. Logo and app icon

Status: accepted (Sabit picked "Split ৳" from four concepts, 2026-11-11).

## Context
The app icon slot was empty, which blocks App Store upload. The brand uses one accent (lime) with ink, Inter for Latin text and Hind Siliguri for Bangla (ADR 9). Concepts offered: split coin, split ৳, coin in the tab-bar notch, and a দে monogram.

## Decision
- The mark is the taka sign from Hind Siliguri SemiBold, cut on a diagonal with the halves slid apart.
- iOS app icon is one 1024×1024 universal image with light, dark and tinted appearances in `AppIcon.appiconset`. Light: ink on lime. Dark: lime on `#0B0B0B`. Tinted: white on black.
- Source SVGs and wordmarks live in `docs/brand/`, with usage rules in its README.

## Consequences
- The ৳ is a Bangla currency glyph, so the icon says "Bangladesh" and "money" at once. It is busier than a pure geometric shape at the 29 pt Settings size; checked at 60, 40 and 29 pt in the concept preview.
- Android adaptive and monochrome icons, and an Icon Composer version, are follow-ups.
