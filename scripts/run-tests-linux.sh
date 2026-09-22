#!/usr/bin/env bash
# Linux counterpart of run-tests.sh. macOS builds against the system SDK and
# its SQLite3 module; on Linux we compile the core sources together with the
# test file (single module, matching run-tests.sh) and supply the SQLite3
# module via the CSQLite module map.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mkdir -p .build
out=".build/ClipHistoryTests-linux"

swiftc \
  -o "$out" \
  Sources/ClipHistory/*.swift \
  Tests/ClipHistoryTests/StoreTests.swift \
  -Xcc -fmodule-map-file=Sources/CSQLite/module.modulemap \
  -lsqlite3

"$out"
