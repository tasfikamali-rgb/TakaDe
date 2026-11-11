#!/usr/bin/env python3
"""Static checks for adaptive layout (iPhone Duo, iPad, split view, rotation).

Based on Apple's "Designing for iPhone Duo" HIG page (Sept 2026), which asks apps to:
  - use size classes (compact on the outer display, regular on the inner one),
  - "Avoid fixed widths and display-specific dependencies",
  - keep functionality and state the same between displays,
  - not override the default bar placement.

These checks catch the code patterns that break those rules. They cannot see the
running layout; the Maestro flows and simulator screenshots cover that.

A line can opt out with a trailing comment `// adaptive-ok: <reason>`, e.g. an
off-screen image rendered at a fixed size for sharing.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "App" / "Sources"

RULES = [
    (r"UIScreen\.main", "Reads the screen size directly; use the view's size or size classes instead "
     "(a foldable has two displays and changes size while running)."),
    (r"userInterfaceIdiom|UIDevice\.current\.model",
     "Branches on device type; use size classes so iPhone Duo's inner display gets the regular layout."),
    (r"\.frame\(\s*(min)?[wW]idth:\s*[0-9]{3,}", "Fixed width of 100pt or more; use maxWidth, layout "
     "margins or size classes so it fits the wider, shorter outer display and split view."),
    (r"\.statusBarHidden\(true\)|\.persistentSystemOverlays\(\.hidden\)",
     "Hides system UI; check it isn't covering a reserved region (camera, folding area)."),
    (r"\.toolbar\(\.hidden,\s*for:\s*\.tabBar\)|toolbarBackground\(\.hidden",
     "Overrides default bar placement/visibility; HIG asks not to on iPhone Duo. Confirm it's intended."),
]

# Files that are never laid out on screen (rendered off-screen, e.g. by ImageRenderer).
OFFSCREEN_FILES = {
    "App/Sources/Features/Share/GroupShareCard.swift": "share image rendered by ImageRenderer at a fixed size",
}

WARN_ONLY = {3, 4}  # index into RULES: reported, but don't fail CI


def main() -> int:
    gh = os.environ.get("GITHUB_ACTIONS") == "true"
    errors = warnings = 0
    uses_size_classes = False
    for path in sorted(SOURCES.rglob("*.swift")):
        rel = path.relative_to(ROOT)
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("//", 1)[0]
            if "horizontalSizeClass" in code or "NavigationSplitView" in code:
                uses_size_classes = True
            if "adaptive-ok:" in line or str(rel) in OFFSCREEN_FILES:
                continue
            for i, (pattern, msg) in enumerate(RULES):
                if re.search(pattern, code):
                    level = "warning" if i in WARN_ONLY else "error"
                    if level == "error":
                        errors += 1
                    else:
                        warnings += 1
                    print(f"::{level} file={rel},line={n}::{msg}" if gh else f"{rel}:{n}: {level}: {msg}")
    if not uses_size_classes:
        errors += 1
        print("error: no view reads horizontalSizeClass or uses NavigationSplitView; "
              "iPhone Duo's inner display would get the phone layout.")
    print(f"\nAdaptive layout check: {errors} errors, {warnings} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
