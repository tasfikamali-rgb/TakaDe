#!/usr/bin/env bash
# Builds TakaDe.app for the iOS Simulator into build/TakaDe.app.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -f App/Resources/Fonts/Ranade-Medium.otf ] || scripts/fetch-fonts.sh
command -v xcodegen >/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
xcodegen generate --quiet
xcodebuild build \
  -project TakaDe.xcodeproj -scheme TakaDe \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -quiet CODE_SIGNING_ALLOWED=NO
rm -rf build/TakaDe.app
cp -R build/DerivedData/Build/Products/Debug-iphonesimulator/TakaDe.app build/TakaDe.app
echo "built build/TakaDe.app"
