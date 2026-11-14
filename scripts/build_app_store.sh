#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:---local}"
if [[ "$MODE" != "--local" && "$MODE" != "--archive" ]]; then
  print -u2 "usage: scripts/build_app_store.sh [--local|--archive]"
  exit 2
fi
swift "$ROOT/scripts/generate_icon.swift" "$ROOT/AirMirror/Assets.xcassets/AppIcon.appiconset"
python3 "$ROOT/scripts/build_store_engine.py" --if-needed

ARGS=(-project "$ROOT/AirMirror.xcodeproj" -scheme AirMirrorStore -configuration AppStore
      -derivedDataPath "$ROOT/build/StoreSandbox" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES)
python3 "$ROOT/scripts/select_store_signing.py" "$ROOT/build/store-local-signing.json"
SIGNING_SHA="$(python3 -c 'import json; print(json.load(open("build/store-local-signing.json"))["sha"])')"
SIGNING_TEAM="$(python3 -c 'import json; print(json.load(open("build/store-local-signing.json"))["team"])')"
ARGS+=("CODE_SIGN_IDENTITY=$SIGNING_SHA" "DEVELOPMENT_TEAM=$SIGNING_TEAM"
       CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual)

if [[ "$MODE" == "--local" ]]; then
  ARGS+=(PRODUCT_BUNDLE_IDENTIFIER=com.liangyu.airmirror.mas)
  xcodebuild "${ARGS[@]}" build
  APP="$ROOT/build/StoreSandbox/Build/Products/AppStore/AirMirror.app"
else
  xcodebuild "${ARGS[@]}" -archivePath "$ROOT/build/AppStore/AirMirror.xcarchive" archive
  APP="$ROOT/build/AppStore/AirMirror.xcarchive/Products/Applications/AirMirror.app"
fi
python3 "$ROOT/scripts/validate_store_app.py" "$APP"
print "Built $APP"
if [[ "$MODE" == "--archive" ]]; then
  print "Development-signed archive: export through Xcode's App Store Connect distribution workflow before submission."
fi
