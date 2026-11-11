#!/usr/bin/env python3
"""Prints UI test failures from `xcresulttool get test-results summary` JSON (stdin),
and appends them to the GitHub step summary when running in Actions."""
import json
import os
import sys

data = json.load(sys.stdin)
lines = []
for failure in data.get("testFailures", []):
    name = failure.get("testIdentifierString") or failure.get("testName")
    lines.append(f"- {name}: {failure.get('failureText')}")
print("\n".join(lines) if lines else json.dumps(data, indent=1)[:4000])
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary and lines:
    with open(summary, "a", encoding="utf-8") as fh:
        fh.write("### UI test failures\n\n" + "\n".join(lines) + "\n\n")
