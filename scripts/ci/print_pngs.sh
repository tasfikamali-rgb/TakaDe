#!/bin/bash
# Prints each PNG under a folder (and the xcresult attachment manifest, if any) into
# the CI log as base64 between BEGIN-PNG/END-PNG lines, shrunk to 700 px with sips,
# so a failing screen can be looked at straight from the log. Debug output only:
# the workflow calls this on failure.
dir="${1:?folder}"
[ -f "$dir/manifest.json" ] && { echo "Attachment names:"; cat "$dir/manifest.json"; echo; }
count=0
find "$dir" -name '*.png' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  count=$((count + 1)); [ "$count" -gt 12 ] && break
  sips -Z 700 "$f" >/dev/null 2>&1 || true
  echo "::group::Screenshot $(basename "$f")"
  echo "BEGIN-PNG $f"
  base64 -i "$f" | tr -d '\n'
  echo
  echo "END-PNG"
  echo "::endgroup::"
done
exit 0
