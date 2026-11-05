#!/usr/bin/env bash
# Regenerate the checked-in app icon from the shared BrandMark geometry.
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/cache"
swift run --disable-sandbox --cache-path "$PWD/.build/cache" make-icons
