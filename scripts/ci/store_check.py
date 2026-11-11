#!/usr/bin/env python3
"""App Store readiness checks that can be automated.

Catches the common reasons Apple rejects or blocks an upload *before* anyone
submits: missing permission strings, a missing or incomplete privacy manifest,
no app icon, iPad multitasking orientation rules, insecure networking
exceptions, and untranslated strings.

Two levels:
  error    - something is wrong now (CI fails on every PR)
  blocker  - fine for development, but App Store Connect would reject it.
             Reported as a warning on PRs; fails when run with --release.

Usage:
  scripts/ci/store_check.py                      # source-only checks
  scripts/ci/store_check.py --app path/TakaDe.app  # also inspect the built app
  scripts/ci/store_check.py --app ... --release  # treat blockers as failures

This is not a substitute for App Review. It does not read the current
App Review Guidelines; see docs/testing.md for the manual checklist.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "App" / "Sources"
RESOURCES = ROOT / "App" / "Resources"
MANIFEST = RESOURCES / "PrivacyInfo.xcprivacy"

# Source pattern -> Info.plist key that must exist (with a non-trivial string).
USAGE_STRINGS = [
    (r"VNDocumentCameraViewController|DataScannerViewController|AVCaptureDevice|UIImagePickerController\b.*\.camera|sourceType\s*=\s*\.camera",
     "NSCameraUsageDescription", "camera"),
    (r"PHPhotoLibrary\.requestAuthorization|PHAsset\b", "NSPhotoLibraryUsageDescription", "photo library"),
    (r"PHPhotoLibrary\.shared\(\)\.performChanges|UIImageWriteToSavedPhotosAlbum",
     "NSPhotoLibraryAddUsageDescription", "saving photos"),
    (r"\bCNContactStore\b", "NSContactsUsageDescription", "contacts"),
    (r"\bCLLocationManager\b", "NSLocationWhenInUseUsageDescription", "location"),
    (r"\bAVAudioRecorder\b|AVAudioSession.*record", "NSMicrophoneUsageDescription", "microphone"),
    (r"\bLAContext\b", "NSFaceIDUsageDescription", "Face ID"),
    (r"\bEKEventStore\b", "NSCalendarsFullAccessUsageDescription", "calendar"),
]

# Required-reason API categories (Apple, "Describing use of required reason API").
# Pattern in our own Swift -> category that must be declared in the manifest.
REQUIRED_REASON_APIS = [
    (r"\bUserDefaults\b|@AppStorage|@SceneStorage", "NSPrivacyAccessedAPICategoryUserDefaults"),
    (r"creationDate|modificationDate|contentModificationDate|\.fileModificationDate|getattrlist|\bstat\(",
     "NSPrivacyAccessedAPICategoryFileTimestamp"),
    (r"systemUptime|mach_absolute_time", "NSPrivacyAccessedAPICategorySystemBootTime"),
    (r"volumeAvailableCapacity|systemFreeSize|statfs", "NSPrivacyAccessedAPICategoryDiskSpace"),
    (r"activeInputModes", "NSPrivacyAccessedAPICategoryActiveKeyboards"),
]

IPAD_ORIENTATIONS = {
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
}


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.blockers: list[str] = []
        self.passed: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def blocker(self, msg: str) -> None:
        self.blockers.append(msg)

    def ok(self, msg: str) -> None:
        self.passed.append(msg)


def swift_sources() -> str:
    parts = []
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        # Ignore line comments so documentation does not trigger checks.
        parts.append("\n".join(line.split("//", 1)[0] for line in text.splitlines()))
    return "\n".join(parts)


def load_plist(path: Path) -> dict:
    with path.open("rb") as fh:
        return plistlib.load(fh)


def check_manifest(src: str, r: Report) -> None:
    if not MANIFEST.exists():
        r.error("App/Resources/PrivacyInfo.xcprivacy is missing (required for App Store uploads).")
        return
    try:
        manifest = load_plist(MANIFEST)
    except Exception as exc:  # noqa: BLE001 - report any parse failure
        r.error(f"PrivacyInfo.xcprivacy is not a valid plist: {exc}")
        return
    for key in ("NSPrivacyTracking", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"):
        if key not in manifest:
            r.error(f"PrivacyInfo.xcprivacy has no {key}.")
    if manifest.get("NSPrivacyTracking") and not manifest.get("NSPrivacyTrackingDomains"):
        r.error("NSPrivacyTracking is true but NSPrivacyTrackingDomains is empty.")

    declared = {}
    for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
        declared[entry.get("NSPrivacyAccessedAPIType")] = entry.get("NSPrivacyAccessedAPITypeReasons", [])
    for pattern, category in REQUIRED_REASON_APIS:
        used = re.search(pattern, src) is not None
        if used and not declared.get(category):
            r.error(f"Source uses a {category} API but the privacy manifest does not declare it with a reason.")
        elif used:
            r.ok(f"{category} declared ({', '.join(declared[category])}).")
    r.ok("Privacy manifest present and parses.")


def check_usage_strings(src: str, info: dict, r: Report, where: str) -> None:
    for pattern, key, what in USAGE_STRINGS:
        if re.search(pattern, src):
            value = str(info.get(key, "")).strip()
            if not value:
                r.error(f"Code uses the {what} but {key} is missing from {where}. The app would crash on first use.")
            elif len(value) < 20:
                r.blocker(f"{key} is very short. Apple rejects vague purpose strings; say what it's used for.")
            else:
                r.ok(f"{key} present.")


def info_from_project_yml() -> dict:
    """Very small reader for the `info.properties` block of project.yml.

    Avoids a PyYAML dependency; only handles `Key: value` and `Key: [a, b]`.
    """
    text = (ROOT / "project.yml").read_text(encoding="utf-8")
    m = re.search(r"\n\s+properties:\n((?:\s{8,}.*\n)+)", text)
    props: dict = {}
    if not m:
        return props
    for line in m.group(1).splitlines():
        km = re.match(r"\s+([A-Za-z~]+):\s*(.*)$", line)
        if not km:
            continue
        key, value = km.group(1), km.group(2).strip()
        if value.startswith("[") and value.endswith("]"):
            props[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        elif value == "{}":
            props[key] = {}
        else:
            props[key] = value
    return props


def check_info(info: dict, r: Report) -> None:
    for key in ("CFBundleDisplayName", "CFBundleShortVersionString", "CFBundleVersion"):
        if key in info and not str(info[key]).strip():
            r.error(f"{key} is empty.")
    if "UILaunchScreen" not in info and "UILaunchStoryboardName" not in info:
        r.error("No launch screen (UILaunchScreen). Required for App Store uploads.")
    family = info.get("UIDeviceFamily", [1, 2])
    supports_ipad = 2 in family or "2" in family
    if supports_ipad and not info.get("UIRequiresFullScreen"):
        ipad = set(info.get("UISupportedInterfaceOrientations~ipad", []))
        missing = IPAD_ORIENTATIONS - ipad
        if missing:
            r.error("iPad multitasking needs all four orientations (or UIRequiresFullScreen). Missing: "
                    + ", ".join(sorted(missing)))
        else:
            r.ok("iPad orientations allow multitasking and split view.")
    ats = info.get("NSAppTransportSecurity", {})
    if isinstance(ats, dict) and ats.get("NSAllowsArbitraryLoads"):
        r.blocker("NSAllowsArbitraryLoads is on. Apple asks for a justification; use HTTPS instead.")
    if "ITSAppUsesNonExemptEncryption" not in info:
        r.blocker("ITSAppUsesNonExemptEncryption is not set, so every upload asks the export-compliance "
                  "question. The owner must decide the answer (see docs/decisions-needed.md).")
    locs = info.get("CFBundleLocalizations", [])
    if "bn" not in locs:
        r.error("CFBundleLocalizations does not list bn, so iOS won't offer Bengali.")


def check_app_icon(r: Report) -> None:
    contents = RESOURCES / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    if not contents.exists():
        r.error("AppIcon.appiconset is missing.")
        return
    data = json.loads(contents.read_text(encoding="utf-8"))
    images = [i for i in data.get("images", []) if i.get("filename")]
    if not images:
        r.blocker("App icon has no image. App Store Connect rejects uploads without a 1024x1024 icon.")
    else:
        for img in images:
            if not (contents.parent / img["filename"]).exists():
                r.error(f"App icon file {img['filename']} is listed but missing.")
        r.ok("App icon image present.")


def check_strings(r: Report) -> None:
    path = RESOURCES / "Localizable.xcstrings"
    if not path.exists():
        r.error("Localizable.xcstrings is missing.")
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    missing, review = [], []
    for key, entry in data.get("strings", {}).items():
        if entry.get("shouldTranslate") is False or not key.strip():
            continue
        bn = entry.get("localizations", {}).get("bn")
        if not bn:
            missing.append(key)
            continue
        state = bn.get("stringUnit", {}).get("state")
        if state in (None, "new", "needs_review"):
            review.append(key)
    if missing:
        sample = "; ".join(missing[:5])
        r.blocker(f"{len(missing)} strings have no Bengali translation (e.g. {sample}).")
    if review:
        r.blocker(f"{len(review)} Bengali strings are machine-drafted and still need human review.")
    if not missing and not review:
        r.ok("All strings have reviewed Bengali.")


def check_built_app(app: Path, src: str, r: Report) -> None:
    info_path = app / "Info.plist"
    if not info_path.exists():
        r.error(f"{info_path} not found.")
        return
    info = load_plist(info_path)
    check_info(info, r)
    check_usage_strings(src, info, r, "the built Info.plist")
    bundled = app / "PrivacyInfo.xcprivacy"
    if not bundled.exists():
        r.error("PrivacyInfo.xcprivacy is not inside the built app (is App/Resources in the target?).")
    else:
        r.ok("Privacy manifest is bundled in the app.")
    for font in info.get("UIAppFonts", []):
        if not list(app.rglob(font)):
            r.blocker(f"UIAppFonts lists {font} but it is not in the app (run scripts/fetch-fonts.sh).")
    if not list(app.rglob("bn.lproj")):
        r.error("No bn.lproj in the built app, so Bengali strings were not compiled in.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, help="Path to a built .app to inspect")
    parser.add_argument("--release", action="store_true", help="Fail on release blockers too")
    args = parser.parse_args()

    r = Report()
    src = swift_sources()
    check_manifest(src, r)
    check_app_icon(r)
    check_strings(r)
    if args.app:
        check_built_app(args.app, src, r)
    else:
        info = info_from_project_yml()
        check_info(info, r)
        check_usage_strings(src, info, r, "project.yml")

    gh = os.environ.get("GITHUB_ACTIONS") == "true"
    for msg in r.passed:
        print(f"  ok       {msg}")
    for msg in r.blockers:
        print(f"::warning title=Store blocker::{msg}" if gh and not args.release else f"  BLOCKER  {msg}")
    for msg in r.errors:
        print(f"::error title=Store check::{msg}" if gh else f"  ERROR    {msg}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("### App Store readiness\n\n")
            fh.write(f"{len(r.errors)} errors, {len(r.blockers)} release blockers, {len(r.passed)} passed\n\n")
            for msg in r.errors:
                fh.write(f"- ❌ {msg}\n")
            for msg in r.blockers:
                fh.write(f"- ⚠️ {msg}\n")
            fh.write("\n")

    print(f"\n{len(r.errors)} errors, {len(r.blockers)} release blockers, {len(r.passed)} passed")
    if r.errors or (args.release and r.blockers):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
