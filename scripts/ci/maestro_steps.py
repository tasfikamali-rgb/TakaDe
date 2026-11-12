#!/usr/bin/env python3
"""Prints the steps of failed Maestro flows from Maestro's debug output
(commands-*.json, found recursively under the given folders): each command, its
status and how long it took, plus the texts on screen when the failing step ran.
Shows in CI where a flow stopped and where its time went."""
import json
import os
import sys

roots = sys.argv[1:] or [os.path.expanduser("~/.maestro/tests")]


def describe(command):
    if not isinstance(command, dict) or not command:
        return str(command)[:100]
    name, body = next(iter(command.items()))
    if isinstance(body, dict):
        detail = body.get("description") or body.get("selector") or body.get("text") or ""
        return f"{name} {json.dumps(detail, ensure_ascii=False)[:90]}" if detail else name
    return name


def texts(node, out):
    if not isinstance(node, dict):
        return
    attrs = node.get("attributes") or {}
    text = attrs.get("text") or attrs.get("accessibilityText") or attrs.get("hintText")
    if text and text not in out:
        out.append(text[:80])
    for child in node.get("children") or []:
        texts(child, out)


# os.walk, not glob: Maestro nests its output under a hidden .maestro folder, which glob skips.
paths = sorted({os.path.join(d, f) for r in roots for d, _, files in os.walk(r)
                for f in files if f.startswith("commands-") and f.endswith(".json")})
if not paths:
    print("No Maestro debug output (commands-*.json) found under:", ", ".join(roots))
for path in paths:
    try:
        with open(path, encoding="utf-8") as fh:
            entries = json.load(fh)
    except (OSError, ValueError) as err:
        print(f"{path}: unreadable ({err})")
        continue
    if not isinstance(entries, list):
        continue
    metas = [e.get("metadata") or {} for e in entries if isinstance(e, dict)]
    if not any(m.get("status") == "FAILED" or m.get("error") for m in metas):
        continue
    print(f"\n== {os.path.relpath(path)}")
    for entry in entries:
        meta = entry.get("metadata") or {}
        duration = meta.get("duration")
        secs = f"{duration / 1000:6.1f}s" if isinstance(duration, (int, float)) else "      "
        print(f"  {str(meta.get('status', '?')):10} {secs}  {describe(entry.get('command'))}")
        error = meta.get("error")
        if error:
            print(f"      error: {str(error.get('message') if isinstance(error, dict) else error)[:300]}")
        if meta.get("hierarchy"):
            on_screen = []
            texts(meta["hierarchy"], on_screen)
            print("      on screen:", " | ".join(on_screen[:40]))
