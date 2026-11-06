#!/usr/bin/env bash
# Assemble a signed universal app. Never launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/cache"

swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="build/TapAsk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TapAsk" "$APP/Contents/MacOS/TapAsk"
cp Info.plist "$APP/Contents/Info.plist"
cp ../shared/providers.json "$APP/Contents/Resources/providers.json"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
scripts/embed-sparkle.sh "$APP" "$IDENTITY"
SIGN_OPTIONS=(--force --options runtime --sign "$IDENTITY")
if [[ "$IDENTITY" == "-" ]]; then
    SIGN_OPTIONS+=(--entitlements AdHoc.entitlements)
fi
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
