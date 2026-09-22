#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
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
