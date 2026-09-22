#!/usr/bin/env bash
# Idempotent setup for the Cursor Cloud Agent (Linux) environment.
#
# NOTE: ClipHistory is a macOS menu-bar app. The GUI executable (ClipHistoryApp)
# depends on AppKit/SwiftUI/Carbon/ServiceManagement/ApplicationServices and
# CANNOT build or run on Linux. This environment enables the platform-portable
# core library (ClipHistory) and its unit-test suite on the Linux Cloud Agent.
set -euo pipefail

SWIFT_VERSION="6.1.2"
SWIFT_ROOT="/opt/swift"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-s1 \
  libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata \
  unzip zlib1g-dev libsqlite3-dev libncurses-dev curl ca-certificates

# Swift toolchain (Linux). Skipped when already present, e.g. when booting from
# a snapshot/build that already contains it.
if [ ! -x "${SWIFT_ROOT}/usr/bin/swift" ]; then
  url="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"
  tmp="$(mktemp -d)"
  curl -fSL --retry 4 --retry-delay 4 -o "${tmp}/swift.tar.gz" "$url"
  sudo mkdir -p "$SWIFT_ROOT"
  sudo tar -xzf "${tmp}/swift.tar.gz" -C "$SWIFT_ROOT" --strip-components=1
  rm -rf "$tmp"
fi

# Expose the toolchain on PATH for every shell and command.
for tool in swift swiftc swift-build swift-test swift-run swift-package sourcekit-lsp; do
  if [ -x "${SWIFT_ROOT}/usr/bin/${tool}" ]; then
    sudo ln -sf "${SWIFT_ROOT}/usr/bin/${tool}" "/usr/local/bin/${tool}"
  fi
done

swift --version

# Warm the build of the portable core library so dependencies resolve.
swift build --target ClipHistory
