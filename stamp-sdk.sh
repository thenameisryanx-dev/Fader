#!/bin/bash
# Records in a binary which macOS SDK it was really built with. Usage: ./stamp-sdk.sh path/to/binary
#
# SwiftPM writes "SDK 15.0" (the minimum macOS) into Fader even when building with a newer SDK.
# macOS reads that number to pick the design: an app claiming SDK 15 keeps the old-style controls
# instead of Liquid Glass. This rewrites it to the installed SDK; the minimum macOS stays 15.0.
set -euo pipefail

BIN="${1:?usage: stamp-sdk.sh path/to/binary}"
[ -f "$BIN" ] || { echo "stamp-sdk.sh: $BIN not found" >&2; exit 1; }

SDK="$(xcrun --show-sdk-version)"
MINOS="$(xcrun vtool -show-build "$BIN" | awk '$1 == "minos" { print $2; exit }')"
xcrun vtool -set-build-version macos "${MINOS:-15.0}" "$SDK" -replace -output "$BIN" "$BIN"
