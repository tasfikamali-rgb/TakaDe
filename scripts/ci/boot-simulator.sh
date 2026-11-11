#!/usr/bin/env bash
# Boots the newest available simulator whose name starts with $1 (e.g. "iPhone 16")
# and prints its UDID. Avoids hard-coding device names that change with Xcode.
set -euo pipefail
prefix="${1:?usage: boot-simulator.sh <name prefix>}"
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
prefix = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in devices if "iOS" in r), reverse=True,
                  key=lambda r: [int(x) for x in r.rsplit("iOS-", 1)[-1].split("-")])
for runtime in runtimes:
    for d in devices[runtime]:
        if d["name"].startswith(prefix):
            print(d["udid"]); sys.exit(0)
sys.exit("no simulator named " + prefix + "*")
' "$prefix")
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
echo "$udid"
