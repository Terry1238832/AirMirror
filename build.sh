#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VENDOR="$ROOT/Vendor"
ENGINE_SRC="$VENDOR/UxPlay"
ENGINE_BIN="$VENDOR/bin/uxplay"
HELPERS_DIR=""

mkdir -p "$VENDOR/bin"

echo "==> generating icons"
swift "$ROOT/scripts/generate_icon.swift" "$ROOT/AirMirror/Assets.xcassets/AppIcon.appiconset"

echo "==> checking AirPlay engine dependencies"
if ! command -v brew >/dev/null 2>&1; then
  echo "需要 Homebrew 来安装 cmake / openssl / gstreamer。先安装 https://brew.sh"
  exit 1
fi

HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
export HOMEBREW_NO_AUTO_UPDATE

need_pkgs=()
for pkg in cmake libplist openssl@3 pkgconf gstreamer; do
  if ! brew list --formula "$pkg" >/dev/null 2>&1; then
    need_pkgs+=("$pkg")
  fi
done
if (( ${#need_pkgs[@]} )); then
  echo "==> brew install ${need_pkgs[*]}"
  brew install "${need_pkgs[@]}"
fi

echo "==> fetching UxPlay"
UXPLAY_COMMIT="59f65c804c16f7f6fc7bce6786d5b1eaaf1bf157"
if [[ ! -d "$ENGINE_SRC/.git" ]]; then
  git clone https://github.com/FDH2/UxPlay.git "$ENGINE_SRC"
  git -C "$ENGINE_SRC" checkout "$UXPLAY_COMMIT"
elif [[ "$(git -C "$ENGINE_SRC" rev-parse HEAD)" != "$UXPLAY_COMMIT" ]]; then
  git -C "$ENGINE_SRC" fetch origin "$UXPLAY_COMMIT"
  git -C "$ENGINE_SRC" checkout "$UXPLAY_COMMIT"
fi
python3 "$ROOT/scripts/patch_uxplay.py"

echo "==> building UxPlay"
OPENSSL_ROOT="$(brew --prefix openssl@3)"
cmake -S "$ENGINE_SRC" -B "$ENGINE_SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT"
cmake --build "$ENGINE_SRC/build" --config Release --parallel
cp "$ENGINE_SRC/build/uxplay" "$ENGINE_BIN"
chmod +x "$ENGINE_BIN"

echo "==> building 镜投"
xcodebuild \
  -project "$ROOT/AirMirror.xcodeproj" \
  -scheme AirMirror \
  -configuration Release \
  -derivedDataPath "$ROOT/build/DerivedData" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual

APP="$ROOT/build/DerivedData/Build/Products/Release/AirMirror.app"
HELPERS_DIR="$APP/Contents/Helpers"
mkdir -p "$HELPERS_DIR"
cp "$ENGINE_BIN" "$HELPERS_DIR/uxplay"
chmod +x "$HELPERS_DIR/uxplay"
python3 "$ROOT/scripts/bundle_runtime.py" "$APP"
codesign --force --sign - --entitlements "$ROOT/AirMirror/AirMirror.entitlements" "$APP"

DIST="$ROOT/dist"
mkdir -p "$DIST"
rm -rf "$DIST/镜投.app"
cp -R "$APP" "$DIST/镜投.app"

echo "Built $DIST/镜投.app"

if [[ "${1:-}" == "--open" ]]; then
  open "$DIST/镜投.app"
fi
