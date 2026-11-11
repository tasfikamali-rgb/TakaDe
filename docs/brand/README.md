# TakaDe brand files

The mark is the Bangladeshi taka sign (৳) cut on a diagonal, with the two halves slid apart: money, split. Chosen by Sabit on 2026-11-11 from four concepts (ADR 16).

| File | Use |
| --- | --- |
| `icon-light.svg` | App icon, default (ink ৳ on lime). Source for `AppIcon-Light.png`. |
| `icon-dark.svg` | App icon, iOS dark appearance (lime ৳ on near-black). |
| `icon-tinted.svg` | App icon, iOS tinted appearance (white ৳ on black; iOS applies the tint). |
| `icon-1024.png` | 1024×1024 PNG of the light icon, for store listings and Android later. |
| `icon-mark.svg` | Mark alone, transparent, ink. For light backgrounds. |
| `icon-mark-dark.svg` | Mark alone, transparent, lime. For dark backgrounds. |
| `wordmark.svg` | "TakaDe" in Inter Display SemiBold, outlined. |
| `wordmark-bn.svg` | "টাকা দে" in Hind Siliguri SemiBold, outlined. |

## Rules
- Colors are the app tokens: lime `#4BE83A`, ink `#161616`, near-black `#0B0B0B`. No gradients, shadows or outlines on the mark.
- Icon files are full-bleed 1024×1024 squares with no rounded corners and no transparency. iOS applies the corner mask itself.
- The ৳ glyph comes from Hind Siliguri SemiBold (SIL Open Font License), converted to outlines. The wordmarks are outlined Inter Display (OFL) and Hind Siliguri. Outlining keeps them identical everywhere without shipping font files.
- Keep clear space around the mark of at least a quarter of its height. Don't recolor the halves differently, rotate, or close the gap.
- Lockup: mark on the left at the height of the wordmark's capital T, gap equal to half the mark width.

## Not done yet
- Icon Composer (`.icon`) layered version for iOS 26 Liquid Glass. The asset catalog icons above work on iOS 17 and later, including dark and tinted on iOS 18+. Open `icon-light.svg` in Icon Composer if we want glass layers.
- Android adaptive icon (foreground/background layers) and monochrome icon, when the Android app starts.
- Home-screen widget and launch screen branding.
