#!/bin/bash
# Packs Fader.app into a disk image (DMG) to send to other people.
# Usage: ./package.sh               builds a fresh release app, then makes build/Fader.dmg
#        ./package.sh APP DMG       packs an existing APP into DMG (used by the tests)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ $# -eq 0 ]; then
    "$ROOT/build.sh" release
fi
APP="${1:-$ROOT/build/Fader.app}"
DMG="${2:-$ROOT/build/Fader.dmg}"
[ -d "$APP" ] || { echo "No app at $APP" >&2; exit 1; }

# Everything in this folder ends up in the disk image.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Fader.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open Fader.txt" <<'EOF'
Installing Fader (needs macOS 15 or newer on an Apple Silicon Mac)

1. Drag Fader onto the Applications folder.
2. Open Fader from Applications. macOS will say it can't verify the app,
   because it isn't from the App Store or a paid Apple developer account.
   Click Done.
3. Open System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to the message about Fader. Confirm with your password.
4. Fader appears in the menu bar at the top right. Click it, then
   "Allow Access" to let it control app volumes.
EOF

rm -f "$DMG"
diskutil image create from --format UDZO --volumeName Fader "$STAGE" "$DMG" > /dev/null
echo "Built $DMG"
