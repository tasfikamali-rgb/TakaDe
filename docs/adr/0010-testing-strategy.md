# 10. Testing that doesn't need a local simulator

Status: Accepted (2026-11-11)

Testing waited on an ~8 GB simulator download on the owner's laptop. Instead, every pull
request runs on GitHub's macOS runners, which already have simulators:

- `swift test` for the ledger and storage package (fast, no simulator).
- A store-readiness script (`scripts/ci/store_check.py`) for the reasons App Store
  uploads are commonly rejected: privacy manifest, permission strings, icon, iPad
  orientations, export compliance key, untranslated strings.
- XCUITest with Apple's `performAccessibilityAudit()` on the main screens, at the largest
  text size and in Bengali.
- Maestro flows that drive the real app on an iPhone and an iPad, light and dark, and
  upload screenshots as run artifacts.

Maestro was chosen over XCUITest for journeys because the same YAML flows can drive the
Android app later. XCUITest stays only for Apple's accessibility audit, which Maestro lacks.
Snapshot testing was not added yet: it needs reference images recorded on one fixed
simulator and would add a dependency; the screenshot artifacts cover visual review for now.

Trying builds on a real phone (TestFlight, Google Play internal testing) needs developer
accounts the owner hasn't created; see docs/testing.md and decisions-needed.md.
