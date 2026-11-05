#!/usr/bin/env bash
# Assemble a universal (arm64 + x86_64) ad-hoc signed app from the SwiftPM release build. Never launches it.
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
codesign --force --options runtime --sign - "$APP"
echo "Built $APP"
