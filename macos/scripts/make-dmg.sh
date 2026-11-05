#!/usr/bin/env bash
# Build the app and package it with an Applications shortcut using macOS tools.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - Info.plist)"
DMG="build/TapAsk-$VERSION-macOS.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tapask-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto build/TapAsk.app "$STAGING_DIR/TapAsk.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG"
hdiutil create -volname TapAsk -fs HFS+ -format UDZO -srcfolder "$STAGING_DIR" "$DMG"
hdiutil verify "$DMG"
echo "Built $DMG"
