#!/usr/bin/env bash
# Downloads Ranade and Author from Fontshare (free for commercial use; keep the
# license files) and copies the needed weights into App/Resources/Fonts.
# The app falls back to the system font if these are missing.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
for f in ranade author; do
  curl -fsSL -o "$tmp/$f.zip" "https://api.fontshare.com/v2/fonts/download/$f"
  unzip -oq "$tmp/$f.zip" -d "$tmp/$f"
done
dest=App/Resources/Fonts
mkdir -p "$dest"
for name in Ranade-Medium Author-Regular Author-Medium Author-Semibold; do
  file=$(find "$tmp" -name "$name.otf" | head -1)
  if [ -z "$file" ]; then echo "Missing $name.otf in the download" >&2; exit 1; fi
  cp "$file" "$dest/"
done
echo "Fonts copied to $dest. Re-run xcodegen generate."
