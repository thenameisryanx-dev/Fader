#!/bin/bash
# Runs every automated check. Run this after every change; it must pass before a change is done.
set -uo pipefail
cd "$(dirname "$0")"

fail() { echo; echo "❌ CHECK FAILED: $1"; exit 1; }

echo "▶ Running automated tests…"
swift test 2>&1 | tee /tmp/fader-test.log | grep -E "✘|error:|Test run with" || true
grep -q "Test run with .* passed" /tmp/fader-test.log || fail "tests (full output: /tmp/fader-test.log)"

echo "▶ Building Fader.app…"
./build.sh release > /tmp/fader-build.log 2>&1 || fail "app build (full output: /tmp/fader-build.log)"
if grep -q "warning:" /tmp/fader-build.log; then
    grep "warning:" /tmp/fader-build.log
    fail "build has warnings"
fi

echo
echo "✅ All automated checks passed. Now run the manual checks in TESTING.md that apply to this change."
