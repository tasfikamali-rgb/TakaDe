#!/bin/bash
# Prints each PNG under a folder (and the xcresult attachment manifest, if any) into
# the CI log as base64 between BEGIN-PNG/END-PNG lines, so a failing screen can be
# looked at straight from the log. Shrinks to 700 px with sips unless the second
# argument is "full" (needed to judge small clips, such as Bengali vowel signs).
# Debug output only: the workflow calls this on failure.
dir="${1:?folder}"
size="${2:-700}"
[ -f "$dir/manifest.json" ] && { echo "Attachment names:"; cat "$dir/manifest.json"; echo; }
count=0
find "$dir" -name '*.png' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  count=$((count + 1)); [ "$count" -gt 12 ] && break
  [ "$size" != "full" ] && { sips -Z "$size" "$f" >/dev/null 2>&1 || true; }
  echo "::group::Screenshot $(basename "$f")"
  echo "BEGIN-PNG $f"
  base64 -i "$f" | fold -w 20000
  echo
  echo "END-PNG"
  echo "::endgroup::"
done
exit 0
