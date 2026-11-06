#!/usr/bin/env bash
# Build an isolated, universal debug app. Never launches it or registers a login item.
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/cache"

swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c debug --arch arm64 --arch x86_64
BIN_DIR="$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c debug --arch arm64 --arch x86_64 --show-bin-path)"
APP="build/TapAsk-Debug.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TapAsk" "$APP/Contents/MacOS/TapAsk-Debug"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string io.github.sure-will.tap-ask.debug "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string 'TapAsk Debug' "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'TapAsk Debug' "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string TapAsk-Debug "$APP/Contents/Info.plist"
# Debug builds never create an updater or access the production feed.
plutil -replace SUEnableAutomaticChecks -bool false "$APP/Contents/Info.plist"
plutil -replace SUAutomaticallyUpdate -bool false "$APP/Contents/Info.plist"
cp ../shared/providers.json "$APP/Contents/Resources/providers.json"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
scripts/embed-sparkle.sh "$APP" -
# Permit local memory inspection of this debug binary, without hardened runtime.
cat > build/debug-entitlements.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements build/debug-entitlements.plist "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo "Soak: open '$APP' --args -TapAskSoak 10 -TapAskSoakDwell 8"
echo "Measure: scripts/measure-memory.sh TapAsk-Debug round-1"
