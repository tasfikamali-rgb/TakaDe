# Maestro UI flows

[Maestro](https://maestro.mobile.dev) drives the real app on a simulator or
emulator from short YAML files. The same flows run on iOS now and on Android
later, because they tap by visible text instead of platform-specific IDs.

CI runs these on every pull request (`.github/workflows/ui-tests.yml`) on an
iPhone and an iPad, in light and dark mode, and uploads the screenshots as the
`screenshots-*` artifacts on the run page.

Run locally on a Mac (needs an iOS simulator installed):

```sh
curl -fsSL https://get.maestro.mobile.dev | bash
scripts/ci/build-sim-app.sh              # builds build/TakaDe.app
xcrun simctl boot "iPhone 16" && xcrun simctl install booted build/TakaDe.app
maestro test -e OUT=maestro-results maestro/flows
```

When the Android app exists, give it the same visible strings and run the
flows with `--app-id` or a copy of each flow with the Android `appId`.
