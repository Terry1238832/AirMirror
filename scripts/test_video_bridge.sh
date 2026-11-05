#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$ROOT/build/VideoBridgeRegression"
mkdir -p "$TEST_BUILD" "$ROOT/build/ModuleCache"

xcrun swiftc \
  -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$ROOT/build/ModuleCache" \
  "$ROOT/AirMirror/VideoBridge.swift" \
  "$ROOT/scripts/tests/video_bridge_regression.swift" \
  -o "$TEST_BUILD/video_bridge_regression"

"$TEST_BUILD/video_bridge_regression"
