#!/usr/bin/env python3
"""Prints the steps of failed Maestro flows from Maestro's debug folder
(~/.maestro/tests/<run>/commands-*.json): each command, its status and how long it
took, so a failure in CI shows where the flow stopped and where the time went."""
import glob
import json
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.maestro/tests")


def describe(command):
    if not isinstance(command, dict) or not command:
        return str(command)[:100]
    name, body = next(iter(command.items()))
    if isinstance(body, dict):
        detail = body.get("description") or body.get("selector") or body.get("text") or ""
        return f"{name} {json.dumps(detail, ensure_ascii=False)[:90]}" if detail else name
    return name


for path in sorted(glob.glob(os.path.join(root, "*", "commands-*.json"))):
    try:
        with open(path, encoding="utf-8") as fh:
            entries = json.load(fh)
    except (OSError, ValueError) as err:
        print(f"{path}: unreadable ({err})")
        continue
    statuses = [(e.get("metadata") or {}).get("status") for e in entries]
    if "FAILED" not in statuses:
        continue
    print(f"\n== {os.path.basename(path)}")
    for entry in entries:
        meta = entry.get("metadata") or {}
        duration = meta.get("duration")
        secs = f"{duration / 1000:6.1f}s" if isinstance(duration, (int, float)) else "      "
        print(f"  {meta.get('status', '?'):10} {secs}  {describe(entry.get('command'))}")
        error = meta.get("error")
        if error:
            print(f"      error: {str(error.get('message') if isinstance(error, dict) else error)[:300]}")
