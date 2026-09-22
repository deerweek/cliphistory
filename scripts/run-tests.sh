#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$root/.build/ModuleCache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$root/.build/ModuleCache}"
# shellcheck disable=SC1091
source "$root/scripts/toolchain.sh"
cd "$root"

mkdir -p .build
out=".build/ClipHistoryTests"

swiftc \
  -sdk "$SDKROOT" \
  -target "$TARGET" \
  -o "$out" \
  Sources/ClipHistory/*.swift \
  Tests/ClipHistoryTests/StoreTests.swift \
  -lsqlite3

"$out"
