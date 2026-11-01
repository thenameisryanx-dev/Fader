#!/bin/bash
# Double-click in Finder to rebuild Fader from the latest code and open it.
# Finder runs .command files in a Terminal window, which shows any build errors.
set -euo pipefail
cd "$(dirname "$0")"

# Build first: if the build fails, the Fader that's already running is left alone.
./build.sh

# Stop any running Fader so the fresh build opens instead of the old one.
# Its taps and aggregate devices are private, so Core Audio removes them when it exits.
if pkill -x Fader; then
    for _ in {1..25}; do
        pgrep -x Fader > /dev/null || break
        sleep 0.2
    done
fi

open build/Fader.app
echo "Fader is running in the menu bar. You can close this window."
