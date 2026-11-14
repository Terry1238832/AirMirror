#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/ReceiverRestartRegression" "$ROOT/build/ModuleCache"
xcrun swiftc -parse-as-library -module-cache-path "$ROOT/build/ModuleCache" \
  "$ROOT/AirMirror/ReceiverRestartBudget.swift" "$ROOT/scripts/tests/receiver_restart_regression.swift" \
  -o "$ROOT/build/ReceiverRestartRegression/test"
"$ROOT/build/ReceiverRestartRegression/test"
