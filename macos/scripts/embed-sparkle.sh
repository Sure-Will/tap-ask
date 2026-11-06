#!/usr/bin/env bash
# Embed and sign the pinned SwiftPM artifact; preserve framework symlinks.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?Usage: embed-sparkle.sh app-path signing-identity}"
IDENTITY="${2:?Missing signing identity}"
ARTIFACT="$PWD/.build/artifacts/sparkle/Sparkle"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
cp "$ARTIFACT/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
# TapAsk is not sandboxed and does not enable these optional XPC services.
rm -rf "$FRAMEWORK/Versions/B/XPCServices"
rm -f "$FRAMEWORK/XPCServices"
for component in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK"; do
    codesign --force --options runtime --sign "$IDENTITY" "$component"
done
