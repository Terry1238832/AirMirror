#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$ROOT/build/WindowMotionRegression"
mkdir -p "$TEST_BUILD" "$ROOT/build/ModuleCache"

# Same-file assembly keeps the test access to private layout helpers out of the app API.
cat "$ROOT/AirMirror/VideoBridge.swift" \
  "$ROOT/scripts/tests/window_motion_regression.swift" \
  > "$TEST_BUILD/window_motion_regression.generated.swift"

xcrun swiftc \
  -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$ROOT/build/ModuleCache" \
  "$TEST_BUILD/window_motion_regression.generated.swift" \
  -o "$TEST_BUILD/window_motion_regression"

"$TEST_BUILD/window_motion_regression"
