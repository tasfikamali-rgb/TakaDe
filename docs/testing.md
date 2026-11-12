# Testing TakaDe

You don't need a simulator on your Mac to see the app working. Every pull request runs
the checks below on GitHub's Mac machines, in parallel, and reports pass or fail.

## When things run

GitHub's free plan for private repos gives 2,000 minutes a month and counts macOS
minutes 10×, so only the cheap checks run on every push:

- **Every push to a PR:** ledger/storage tests, store-readiness and adaptive-layout
  checks, app build.
- **On merge to `main`, by hand, or when a PR gets the `ui-tests` label:**
  accessibility audit, Maestro flows, iPhone Duo.

## What runs

| Check | Workflow / job | What it catches |
|---|---|---|
| Ledger and storage tests | `CI` / Ledger and storage tests | Money maths, splits, rounding, balances, settlement states, SQLite |
| Store readiness (source) | `CI` / App Store readiness | Privacy manifest, permission strings, icon, iPad orientations, Bengali coverage (runs on Linux in seconds) |
| Build + store readiness (app) | `CI` / Build app… | The same checks against the *built* app, e.g. the manifest really is bundled |
| Accessibility audit | `CI` / Build app… | Apple's own audit on the main screens: contrast, labels, touch-target size, Dynamic Type, clipped text; launch at the largest text size and in Bengali |
| Adaptive layout (static) | `CI` / App Store readiness | Patterns Apple's iPhone Duo HIG warns about: reading screen size, device-type branches, fixed widths, hidden bars (`scripts/ci/adaptive_check.py`) |
| Rotation keeps state | `UI flows…` / `03_resize_keeps_state` | The open group survives a width change (rotation stands in for folding) |
| iPhone Duo | `UI flows…` / iPhone Duo | Runs the flows on the iPhone Duo simulator on the newest runner Xcode. If the runner has no such simulator, the job says **NOT TESTED** in its summary instead of passing silently. Folded/unfolded poses are switched in Xcode's Device Hub, so the second pose is a manual check for now |
| Onboarding and delete-all-data | `UI flows…` / `subflows/onboarding`, `04_delete_all_data` | Every flow starts with first-launch onboarding; deleting all data returns to onboarding with no groups left. Delete account (signed in) needs a test Apple/Google account and is checked by hand |
| UI flows | `UI flows and screenshots` | Creates a group, adds an expense with the keypad, opens settle up, switches language; all flows on iPhone 16 split across two machines, the main journey again in dark mode, and the layout flows on iPad Pro 13-inch |

### When a flow fails

The flows don't take routine screenshots (Sabit's call: results only). On a failure the
job uploads `maestro-debug-<device>` under **Artifacts**, with Maestro's own failure
screenshot and logs, and prints the text that was on screen.

### Speed

- Jobs run side by side instead of one after another: one Maestro job per device.
- The free plan runs at most 5 Mac jobs at a time across the whole repo, so most of the
  wait is queueing when several branches run at once. Each run asks for 4 Macs (build,
  accessibility, iPhone, iPad); the iPhone Duo job only runs when started by hand.
- Simulators boot while the app builds or Maestro downloads, not before.
- Swift packages are cached between runs.
- A new push cancels the run that was still going for the same branch.
- Store checks on source run on Linux, which starts much faster than macOS.

GitHub bills macOS minutes at 10× Linux minutes on private repositories. If the free
allowance runs low, the UI-flows workflow can be limited to `workflow_dispatch` (run by hand).

## Codemagic (free alternative when GitHub minutes run out)

`codemagic.yaml` runs the same checks on Codemagic's Mac minis. A **personal**
Codemagic account gets 500 free macOS M2 minutes a month, reset on the 1st (teams get
none). GitHub's free plan gives a private repo the equivalent of 200 macOS minutes.

- `checks` (every PR update and push): ledger tests, store and layout checks, app build.
- `ui-tests` (push to `main`, or **Start new build** in Codemagic): accessibility audit,
  Maestro flows on iPhone and iPad in light and dark. Failure output is under the build's **Artifacts**.

To turn it on: sign in at codemagic.io with GitHub on a personal account, add the
TakaDe repo, and pick "codemagic.yaml" as the configuration. No secrets are needed.

## Trying it on your own iPhone, today, with no download

Xcode can install straight onto an iPhone over a cable using a free Apple ID; no
simulator is needed:

1. `brew install xcodegen && xcodegen generate`, then open `TakaDe.xcodeproj`.
2. Plug in the iPhone, trust the Mac, and turn on **Developer Mode** on the phone
   (Settings → Privacy & Security).
3. In Xcode: TakaDe target → Signing & Capabilities → Team → add your Apple ID.
   Change the bundle ID if Xcode says it's taken.
4. Pick the iPhone at the top and press Run.

Free signing expires after 7 days; just run again.

## Later, needs accounts (see decisions-needed.md, section 7)

- **TestFlight** (Apple Developer Program): send builds to your and testers' phones
  without a cable. A GitHub Action can upload on every merge to `main`.
- **Google Play internal testing + pre-launch report** (Play Console): every upload is
  automatically installed and crawled on a range of real Android phones, with crash,
  accessibility and security reports. This is the closest thing to "will Play accept it".
- **Firebase Test Lab / BrowserStack** if we need specific real devices (foldables, older
  Androids) beyond what emulators give us. Paid beyond small free tiers.

The Maestro flows in `maestro/` are written to run on Android too once that app exists,
so the same journeys gate both platforms.

## Before submitting to the stores

Automated checks reduce rejections; they don't guarantee approval. Things only a person
can do, re-checked at submission time against Apple's and Google's current rules:

- [ ] App icon and store screenshots .
- [ ] App Store privacy label and Play Data safety form match the privacy manifest.
- [ ] Export compliance answer (decisions-needed.md §7).
- [ ] Bengali strings reviewed by a native speaker (the store check counts what's left).
- [ ] Privacy policy URL (required by both stores, needs counsel-reviewed text).
- [ ] Review notes explaining that TakaDe records who owes whom and does not move money;
      "settled" is reported by people, not verified by bKash/upay.
- [ ] Test on at least one real iPhone and one lower-end Android phone.
- [ ] Run `scripts/ci/store_check.py --app <built app> --release`; it must pass.
- [ ] Make the GitHub repo private again (it was made public for free CI minutes on 2026-11-11).

Android-specific checks (target API level, 16 KB page size, Data safety, the Play
pre-launch report) get added when the Android app is started.

## Maestro Cloud (optional, faster)

The same flows can run on Maestro Cloud's iPhones and Android phones in parallel.
To turn it on, create a Maestro Cloud project and add two repository secrets
(GitHub → Settings → Secrets and variables → Actions): `MAESTRO_CLOUD_API_KEY` and
`MAESTRO_CLOUD_PROJECT_ID`. The `Maestro Cloud` job skips itself until both exist.
