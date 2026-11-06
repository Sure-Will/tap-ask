#!/usr/bin/env bash
# Build signed distribution assets. Does not publish or install anything.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/make-dmg.sh
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - Info.plist)"
ACCOUNT="io.github.sure-will.tap-ask.updates"
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
if [[ "$PUBLIC_KEY" != "$(plutil -extract SUPublicEDKey raw -o - Info.plist)" ]]; then
    echo "TapAsk update signing key does not match Info.plist" >&2
    exit 1
fi
STAGING_DIR="$(mktemp -d "$PWD/build/update-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
DMG="TapAsk-$VERSION-macOS.dmg"
cp "build/$DMG" "$STAGING_DIR/$DMG"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/Sure-Will/tap-ask/releases/download/v$VERSION/" \
    --link "https://github.com/Sure-Will/tap-ask/releases/tag/v$VERSION" \
    "$STAGING_DIR"
SIGNATURE="$("$TOOLS/sign_update" --account "$ACCOUNT" -p "$STAGING_DIR/$DMG")"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$STAGING_DIR/$DMG" "$SIGNATURE"
(
    cd "$STAGING_DIR"
    shasum -a 256 "$DMG" > "$DMG.sha256"
)
mkdir -p build/updates
cp "$STAGING_DIR/$DMG" "$STAGING_DIR/$DMG.sha256" "$STAGING_DIR/appcast.xml" build/updates/
echo "Prepared build/updates/appcast.xml, $DMG and $DMG.sha256"
