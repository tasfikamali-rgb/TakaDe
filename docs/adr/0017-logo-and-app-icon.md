# 17. Logo and app icon

Status: accepted (Sabit picked "Split ৳" from four concepts, 2026-11-11).

## Context
The app icon slot was empty, which blocks App Store upload. The brand uses one accent (lime) with ink, Inter for Latin text and Hind Siliguri for Bangla (ADR 9). Concepts offered: split coin, split ৳, coin in the tab-bar notch, and a দে monogram.

## Decision
- The mark is the taka sign from Hind Siliguri SemiBold, cut on a diagonal with the halves slid apart.
- iOS app icon is one 1024×1024 universal image with light, dark and tinted appearances in `AppIcon.appiconset`. Light: ink on lime. Dark: lime on `#0B0B0B`. Tinted: white on black.
- The logo is "৳akaDe": the split ৳ replaces the T, followed by "akaDe" in Inter Display Bold (Sabit's pick from four wordmarks). The D is a capital, matching how the name is written: TakaDe (corrected 2026-11-12; the first version had a lowercase d). Sabit asked for an edgier, more unique logo; italic, sparkle, halftone and glow ideas from the references were dropped as template looks.
- Android adaptive, monochrome and legacy launcher icons and the Google Play 512 px icon are prepared in `docs/brand/android/` for the Kotlin app.
- On a cold launch the launch screen shows the whole ৳, and a short splash cuts it into the logo, then slides it left while "akade" wipes in beside it, ending on the logo "৳akade", before fading to the app (Reduce Motion: fade only). The splash also plays each time the app comes back from the background (Sabit, 2026-11-11), but not after Control Center or a notification pull.
- Source SVGs live in `docs/brand/`, with usage rules in its README.

## Consequences
- The ৳ is a Bangla currency glyph, so the icon says "Bangladesh" and "money" at once. It is busier than a pure geometric shape at the 29 pt Settings size; checked at 60, 40 and 29 pt in the concept preview.
- An Icon Composer (Liquid Glass) version and the Android splash are follow-ups.
- The splash adds about 1.7 s before the app is seen (taps already go through) on a cold launch. It never blocks loading, which runs underneath.
