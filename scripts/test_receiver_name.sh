#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/ReceiverNameRegression" "$ROOT/build/ModuleCache"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$ROOT/build/ModuleCache" \
  "$ROOT/AirMirror/ReceiverNamePreference.swift" "$ROOT/scripts/tests/receiver_name_regression.swift" \
  -o "$ROOT/build/ReceiverNameRegression/test"
"$ROOT/build/ReceiverNameRegression/test"
