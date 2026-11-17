#!/bin/zsh
# Builds the portfolio screens-page assets from marketing/ (icon.png, popover.png @2x).
# Output: prototype/shots/{icon-256.png,popover.jpg,desktop.jpg}
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
mkdir -p prototype/shots
sips -s format png --resampleWidth 256 marketing/icon.png --out prototype/shots/icon-256.png >/dev/null
sips -s format jpeg -s formatOptions 88 --resampleWidth 600 marketing/popover.png --out prototype/shots/popover.jpg >/dev/null
cp tools/desk.html "$T/desk.html"; cp marketing/icon.png "$T/icon.png"; cp marketing/popover.png "$T/popover.png"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1440,900 --screenshot="$T/desk.png" "file://$T/desk.html" 2>/dev/null
sips -s format jpeg -s formatOptions 86 "$T/desk.png" --out prototype/shots/desktop.jpg >/dev/null
rm -rf "$T"
echo "Wrote prototype/shots/"
