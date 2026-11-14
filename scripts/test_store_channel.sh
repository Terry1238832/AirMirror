#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$ROOT/build/StoreChannelRegression"
mkdir -p "$TEST_BUILD" "$ROOT/build/ModuleCache"
sources=("$ROOT"/AirMirror/*.swift)
sources=( ${sources:#*/AirMirrorApp.swift} )
sources=( ${sources:#*/ContentView.swift} )
xcrun swiftc -D APP_STORE -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" -module-cache-path "$ROOT/build/ModuleCache" \
  "${sources[@]}" "$ROOT"/AirMirror/WindowPaste/*.swift \
  "$ROOT/scripts/tests/store_channel_regression.swift" -o "$TEST_BUILD/test"
"$TEST_BUILD/test"
