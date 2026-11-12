# DESIGN.md

Design system for a native iOS expense splitting app with bKash integration (think Splitwise, but settling up happens through bKash). Built in SwiftUI. Read this whole file before writing any UI code.

## 0. Before you start (required)

Do these steps first, every new session, before touching any view code. Do not skip them because you think you already know the material; the skills carry project specific rules.

The three skills in steps 1 to 3 are already checked in under `.claude/skills/` (see `.claude/skills/README.md`), so a fresh clone has them. Run those install commands only to update a skill.

1. Install the Apple design skill (fluid motion, springs, gestures, materials, typography):

```bash
npx skills add https://github.com/emilkowalski/skills --skill apple-design
```

2. Install the SwiftUI Pro skill (modern SwiftUI API, accessibility, performance):

```bash
npx skills add https://github.com/twostraws/swiftui-agent-skill --skill swiftui-pro
```

If `npx` is missing, run `brew install node` first.

3. Install the unslop skill so nothing ships looking AI generated:

```bash
git clone --depth 1 https://github.com/heydamir/unslop.git /tmp/unslop
mkdir -p .claude/skills
cp -r /tmp/unslop/skills/unslop .claude/skills/unslop
```

Restart Claude Code after copying so the skill loads. Run it on every screen before calling the screen done.

4. Pull the DESIGN.md reference collection and read the fintech entries (Wise, Revolut, Mercury) plus Apple. Use them for calibration of density and tone, not to copy:

```bash
git clone --depth 1 https://github.com/VoltAgent/awesome-design-md .design-refs/awesome-design-md
ls .design-refs/awesome-design-md/design-md
```

5. Download the fonts from Fontshare (free for commercial use) and bundle them:

```bash
mkdir -p .design-refs/fonts && cd .design-refs/fonts
curl -L -o author.zip "https://api.fontshare.com/v2/fonts/download/author"
curl -L -o ranade.zip "https://api.fontshare.com/v2/fonts/download/ranade"
unzip -o author.zip -d author && unzip -o ranade.zip -d ranade
```

If either download fails, stop and ask me to grab them manually from fontshare.com. Copy the OTF files into `Resources/Fonts/`, add them to the target, and list each file under `UIAppFonts` in Info.plist.

6. Look at the reference media in `.design-refs/media/` (the animated notch nav, the send money keypad video, the wallet home video, the headline type screenshot, and the three dashboard references described in section 1b). Their behavior and feel are the brief.

7. Invoke `/apple-design`, `/swiftui-pro` and `/unslop` when building or reviewing any screen.

`.design-refs/` goes in `.gitignore`.

## 1. Visual theme and atmosphere

Calm, tactile, money you can touch. Light gray canvas, white sheets that slide up over the wallet header (white in light mode, near-black only in dark mode), one hot lime accent that only appears when something happens (selected tab, money sent, debt settled). Big numbers do the talking. Everything feels physical: sheets have weight, the nav notch is liquid, confirmation is a swipe, not a tap.

Density is low on home and high only inside transaction lists. One memorable thing per screen, everything around it quiet.

## 1a. Modern, simple, uncluttered

This is the rule above all other rules. Every screen should feel like a current, well made iOS app, not a template.

1. One job per screen. If a screen tries to show balances, groups, charts and activity at equal weight, it is cluttered. Pick the main thing, make it big, push the rest down or one tap deeper.
2. Remove before you add. Before finishing a screen, delete one element (a label, a divider, an icon, a shadow) and check if it got better. It usually does.
3. Hierarchy comes from size, weight and spacing, not from more boxes, more colors or more borders.
4. Generous whitespace. When in doubt, add space, not decoration.
5. No filler: no placeholder stats, no decorative icons beside every label, no emoji in UI, no "Welcome back!" banners, no badges that carry no information.

### Do not make AI slop

Run `/unslop` on every screen. On top of what that skill catches, these are banned here: purple to blue gradients, glow effects, glassmorphism stacked on glassmorphism, rows of identical cards with the same radius and the same soft shadow, three equal feature tiles, emoji used as icons, a colored word inside an otherwise plain headline, all caps eyebrow labels, `→` tacked onto button text, and generic copy like "Unlock your potential". If a screen could belong to any random finance app, it is not done.

## 1b. What the reference designs do best

Take the specific idea from each reference, not the whole look. These are the patterns to reuse.

**Green logistics dashboard (ShipX style).** The dark header color bleeds into the top of the screen, and the content sits on a lighter sheet with large rounded top corners, so the header and body read as two physical layers. Stat cards tuck their icon into a curved cutout in the card corner, the same liquid notch idea as our nav bar, so reuse it on group summary cards. Change indicators are small tinted pills (`+1.3% ↗` on a pale tint of its own color), never loose colored text. The chart uses a hatched fill with a scrubber line and a value bubble, which reads clearly without heavy color. The floating nav expands the active tab into a labelled pill. The whole palette is one hue at several lightness levels, which keeps it calm. Do not copy its multicolor corner icons; we keep one accent.

**Savings goals app (black card, progress goals).** The balance card is a dark, slightly textured physical object with four round action buttons labelled underneath (Top up, Send, Withdraw, History), which is the clearest action row of all the references. Goal cards are the model for our group and debt cards: icon, title, chevron, then a nested inner card with amount left, target right, a thin progress bar, and two pieces of meta under it (time left, percent). Layering uses slightly different grays card within card instead of shadows. The bar chart uses rounded pill bars with a subtle hatch. A full width dark pill CTA pins to the bottom on detail screens ("Top up"); use this for "Settle up". It is almost entirely monochrome, with one small color per goal only for identity.

**Lilac wallet (Nina Skrbic).** The greeting is two tone by weight and shade (bold name, muted rest), which feels personal without extra elements. The currency is a small chip above the balance and the cents drop smaller beside it. The change pill straddles the seam between the header and the black action band, tying the two areas together. The action row is Send, a square Scan button in the middle, and Request, which fits bKash QR payments perfectly. The content sheet has a grabber and a gentle notch at its top edge. Send again is a 2×2 avatar grid with an add tile, beside a small income sparkline card, and recent activity rows are simple: icon in a soft circle, name, time, amount right aligned and large.

## 2. Color palette and roles

| Token | Hex | Role |
|---|---|---|
| `canvas` | `#F2F2F2` | App background, light mode |
| `surface` | `#FFFFFF` | Sheets, cards, keypad keys |
| `ink` | `#161616` | Primary text |
| `header` | `#FFFFFF` | Wallet header, nav bar, swipe track. Light in light mode: dark surfaces belong to dark mode only (Sabit, 2026-11-11) |
| `inkMuted` | `#5E5E5E` | Secondary text (5.7:1 on canvas, so it passes WCAG AA for small text), "Available" labels, decimals |
| `lime` | `#4BE83A` | Active tab circle, success screen, settle up. Never for body text |
| `lilac` | `#DAD7EE` | Optional soft header tint for group screens |
| `owed` | `#1F9D55` | "You are owed" amounts (readable green, lime is too light for text) |
| `owe` | `#E5533D` | "You owe" amounts |
| `bkash` | `#E2136E` | Only on bKash pay and settle buttons and the bKash logo badge |

Dark mode: canvas `#0E0E0E`, surface `#1C1C1E`, raised surface `#2A2A2C`, ink becomes `#F5F5F5`, inkMuted becomes `#9A9A9F`, owed becomes `#3DD27A`, owe becomes `#FF6B57`. Lime and bKash pink stay the same. In dark mode the wallet header (`#2A2A2C`) must still separate from the canvas, so it uses `#1C1C1E` with the sheet at `#000000` or the reverse; never two near identical blacks touching. Define every color in an asset catalog with light and dark variants; never hardcode hex in views.

### Contrast and appearance, both modes perfect

The app follows the system appearance and must look finished in light mode and in dark mode. Neither is an afterthought.

1. Every text and background pair meets WCAG AA (4.5:1 for body, 3:1 for large numbers and icons) in both modes. Check each pair; do not eyeball it.
2. Text on lime is always `#161616` in both modes. Text on bKash pink is always white.
3. Tinted pills (gains, losses, status) get their own light and dark tints so the text stays readable on both.
4. Shadows fade out in dark mode; separation comes from the lighter raised surface instead.
5. Check every screen with `.preferredColorScheme(.light)` and `.preferredColorScheme(.dark)` previews side by side, plus Increase Contrast and the largest Dynamic Type size. A screen is not done until all of these look right.

Rule: no more than one saturated color visible at rest on a screen.

## 3. Typography

One modern family, the kind big fintech apps use (changed from Ranade and Author on 2026-11-11 at Sabit's request).

**Inter Display** SemiBold is the display face: balances, amounts on the keypad, screen titles, success messages. **Inter** (Regular, Medium, SemiBold) is the UI face: labels, buttons, list rows, body. Both have tabular figures, so amounts line up and don't jitter. Open licensed (SIL OFL), so the files are committed in `App/Resources/Fonts/Inter`.

**Anek Bangla** (Medium, SemiBold; SIL OFL) draws Bengali digits (০–৯) and the ৳ beside them in amounts, the keypad and meal counts, because Hind Siliguri's digits didn't look right (Sabit, 2026-11-12, ADR 23). Bengali words stay in Hind Siliguri; Latin digits stay in Inter.

**Hind Siliguri** (SIL OFL) covers Bengali: Bangla interface text, Bengali digits and the ৳ sign, at the same sizes and weights.

Headline treatment follows the reference screenshot ("Trusted by teams that build world class apps."): medium to semibold weight, tight negative tracking, tight leading, sentence case, centered only for hero moments.

| Style | Font | Size (pt) | Weight | Tracking | Leading |
|---|---|---|---|---|---|
| Balance | Inter Display | 48 | Semibold | -0.01em | 1.0 |
| Keypad amount | Inter Display | 56 | Semibold | -0.01em | 1.0 |
| Title | Inter Display | 28 | Semibold | -0.005em | 1.1 |
| Headline | Inter | 20 | Semibold | 0 | 1.2 |
| Body | Inter | 16 | Regular | 0 | 1.4 |
| Label | Inter | 14 | Medium | 0 | 1.3 |
| Caption | Inter | 12 | Medium | 0 | 1.3 |

Money formatting: the currency symbol `৳` and the decimals render smaller and in `inkMuted`, like `৳ 7,854.43` where `.43` is roughly 45% of the main size and baseline aligned. Always use `.monospacedDigit()` on amounts that change so numbers do not jitter. Animate amount changes with `.contentTransition(.numericText())`.

Register fonts through `Font.custom(_:size:relativeTo:)` so Dynamic Type still scales them. No all caps labels, no eyebrow text above headings.

## 4. Components

1. **Bottom nav: compact floating pill** (Sabit, 2026-11-12; replaces the liquid notch bar). A small `tabBarBackground` capsule (white with a soft shadow and hairline in light mode, raised dark gray in dark mode) centered above the home indicator, not full width. Four tabs (Groups, Activity, Account, Settings), each an SF Symbol over a short Inter / Hind Siliguri label. The selected tab sits on a `tabBarIndicator` capsule that springs across to the next tab (`matchedGeometryEffect`, `Motion.tabSwitch`: response 0.34, damping 0.76), its icon switches to the fill variant with a small bounce, and `.sensoryFeedback(.selection, trigger:)` fires on the same frame. Reduce Motion swaps the spring for a short ease and skips the bounce. Colors come only from the `tabBar…` tokens in `Color+Tokens.swift`.

2. **Wallet header**. `header` block at the top of Home (white in light mode, raised dark gray in dark mode) with "Total balance" label, big Inter Display balance, and two pill buttons side by side: Send (filled white) and Request (outlined). Below it a compact Spending or "You are owed" card with stacked avatars.

3. **Transactions sheet**. White sheet with a grabber that overlaps the header and scrolls up over it. Rows: 36pt avatar or merchant logo, name, sub label, amount right aligned (`owed` green for incoming, `ink` for outgoing). Fade the top edge with a mask, no hard divider.

4. **Amount keypad sheet** (from the send money video). Segmented Send / Request toggle at the top, recipient chip under it, huge centered amount, "Available ৳ x" caption. Then a row of + − × ÷ operators (this is core for splitting: `1200 ÷ 4` should just work), then a 3×4 keypad of soft rounded keys. Keys scale to 0.96 on press down, instantly.

5. **Swipe to confirm**. Replaces the pay button on send and settle. A track with a thumb the user drags right; it tracks 1:1 with the finger, rubber bands past the end, and springs back if released before 70%. On commit, haptic success.

6. **Success screen**. Full screen lime, big checkmark, amount in Inter Display, "Sent to Pavlo" in Inter. Enters by expanding from the confirm thumb's position. Tap anywhere to close; it collapses back the same way it came.

7. **Send again grid**. 2×2 avatar tiles with a plus tile, next to a small income or balance trend card, as in the wallet reference.

8. **bKash settle button**. The only place `bkash` pink appears, with the bKash mark. Label states exactly what happens: "Settle ৳ 450 with bKash".

Corner radius by hierarchy, not one value everywhere: sheets 28, cards 20, keys 16, pills fully rounded. Use `.continuous` corner style.

## 5. Layout

Spacing scale in points: 4, 8, 12, 16, 20, 24, 32, 48. Screen side margin 20. Touch targets at least 44×44. Content left aligned in lists; hero numbers and the success screen centered. Respect safe areas; the floating nav sits 8pt above the home indicator and content scrolls under it with a soft gradient fade.

## 6. Depth and materials

Three layers: canvas, sheet, floating chrome (nav bar, toolbars). Floating chrome uses `.ultraThinMaterial` or solid `ink` with a soft shadow (radius 20, y 8, 18% black). Sheets use a lighter shadow. Never stack translucent on translucent. Modal tasks (keypad, settle up) dim the background with a scrim and push it back slightly (scale 0.94). Non blocking panels get no scrim.

## 7. Motion

Follow the apple-design skill. In SwiftUI terms:

| Use | Animation |
|---|---|
| Default UI change | `.spring(response: 0.35, dampingFraction: 1.0)` |
| Tab bar pill | `.spring(response: 0.34, dampingFraction: 0.76)` |
| Flicked cards | `.spring(response: 0.4, dampingFraction: 0.8)` |
| Sheets and drawers | `.spring(response: 0.3, dampingFraction: 0.8)` |
| Press feedback | 0.1s ease out to scale 0.96 |

Every gesture driven animation must be interruptible: grab a moving sheet and it follows the finger. Hand release velocity into the spring. Project flick momentum to choose the snap point. Enter and exit along the same path. With Reduce Motion on, swap slides and springs for short opacity crossfades.

## 8. Do and don't

Do: let the numbers be big, keep lime rare, make confirmation physical, write labels that say exactly what happens ("Split equally", "Settle up", "Remind Rishan").

Don't: use red and green as the only signal for owe and owed (add the words), put lime text on white, use gradients as decoration, use stock SF Symbols where a custom icon is needed for brand (bKash), or apologize in error messages. Errors say what went wrong and how to fix it.

## 9. Accessibility

Every icon button gets an accessibility label. Amounts read naturally ("seven thousand eight hundred fifty four taka"). Support Dynamic Type up to AX sizes without truncating balances (allow wrapping or a smaller fallback). Contrast at least 4.5:1 for text. Test with VoiceOver on the keypad and swipe to confirm (provide a double tap alternative for confirm).

## 10. Agent prompt guide

When asked to build a screen: reread sections 2 to 4, pick the closest component above, build it with the tokens, then review it against `/apple-design` and `/swiftui-pro` before calling it done. If something in a request conflicts with this file, ask before deviating.
