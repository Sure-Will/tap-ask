#!/usr/bin/env bash
# Full check run outside the Codex sandbox: debug build, every test (including
# the WebKit and window tests the sandbox cannot run), then the release app.
# Never launches the app. Used by `codex-task --verify`.
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/cache"

echo "== swift build"
swift build --disable-sandbox --cache-path "$PWD/.build/cache"

echo "== swift test"
swift test --disable-sandbox --cache-path "$PWD/.build/cache" 2>&1 | tee .build/verify-test.log
grep -E "Executed [0-9]+ tests" .build/verify-test.log | tail -1

echo "== build-app"
scripts/build-app.sh

echo "== verify ok"
