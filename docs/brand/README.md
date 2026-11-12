# TakaDe brand files

The mark is the Bangladeshi taka sign (৳) cut on a diagonal, with the two halves slid apart: money, split. Chosen by Sabit on 2026-11-11 from four concepts (ADR 17).

| File | Use |
| --- | --- |
| `icon-light.svg` | App icon, default (ink ৳ on lime). Source for `AppIcon-Light.png`. |
| `icon-dark.svg` | App icon, iOS dark appearance (lime ৳ on near-black). |
| `icon-tinted.svg` | App icon, iOS tinted appearance (white ৳ on black; iOS applies the tint). |
| `icon-1024.png` | 1024×1024 PNG of the light icon, for store listings and Android later. |
| `icon-mark.svg` | Mark alone, transparent, ink. For light backgrounds. |
| `icon-mark-dark.svg` | Mark alone, transparent, lime. For dark backgrounds. |
| `logo-on-light.svg` | The logo, "৳akade": the split ৳ stands in for the t, then "akade" in Inter Display Bold. Green `#1F9D55` ৳ and ink text, for white or light backgrounds. |
| `logo-on-dark.svg` | The same logo with a lime ৳ and near-white text, for dark backgrounds. |
| `social-preview.png` | 1280×640 link preview for the GitHub repo (Settings › Social preview) and for sharing links. |
| `android/res/` | Android launcher icon, ready to copy into the app's `res/`: adaptive icon (lime background, ink foreground, monochrome layer for themed icons) plus legacy PNGs for every density. |
| `android/play-store-icon-512.png` | Google Play listing icon, 512×512, opaque. Play applies its own corner mask. |

## Launch
The iPhone launch screen shows the whole ৳ (`LaunchMark`, 96 pt) on `launchBackground` (lime in light mode, near-black in dark). `LaunchSplash` then cuts the sign into the logo's two halves with a light tap, slides it left while "akade" wipes in beside it, ending on the logo "৳akade", holds, and fades to the app in about 1.7 s. `TakaWordmark.swift` (the outlined "akade" and the lockup positions) is generated from `logo-on-light.svg` by `scripts/brand_wordmark_swift.py`. It plays on every open: a cold launch and each return from the background. Reduce Motion cross-fades the sign to the logo instead. The halves are drawn in SwiftUI by `TakaMark`, generated from the same glyph.

## Rules
- Colors are the app tokens: lime `#4BE83A`, ink `#161616`, near-black `#0B0B0B`. No gradients, shadows or outlines on the mark.
- Icon files are full-bleed 1024×1024 squares with no rounded corners and no transparency. iOS applies the corner mask itself.
- All paths are flattened (no clip paths), so they import cleanly into Figma, Icon Composer and Android Studio.
- The ৳ glyph comes from Hind Siliguri SemiBold (SIL Open Font License), converted to outlines. The wordmarks are outlined Inter Display (OFL) and Hind Siliguri. Outlining keeps them identical everywhere without shipping font files.
- Keep clear space around the mark of at least a quarter of its height. Don't recolor the halves differently, rotate, or close the gap.
- Lockup: mark on the left at the height of the wordmark's capital T, gap equal to half the mark width.

## Not done yet
- Icon Composer (`.icon`) layered version for iOS 26 Liquid Glass. The asset catalog icons above work on iOS 17 and later, including dark and tinted on iOS 18+. Open `icon-light.svg` in Icon Composer if we want glass layers.
- Android splash screen (Android 12 SplashScreen API uses the adaptive icon foreground), when the Android app starts.
- Home-screen widget branding.
