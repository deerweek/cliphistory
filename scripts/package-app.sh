#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$root/scripts/toolchain.sh"
# shellcheck disable=SC1091
source "$root/scripts/signing.sh"
cd "$root"

mkdir -p .build
bin=".build/ClipHistory"
app="$root/dist/剪贴板记录.app"
installed="${HOME}/Applications/剪贴板记录.app"

swiftc \
  -sdk "$SDKROOT" \
  -target "$TARGET" \
  -parse-as-library \
  -O \
  -o "$bin" \
  Sources/ClipHistory/*.swift \
  Sources/ClipHistoryApp/*.swift \
  -lsqlite3 \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework ServiceManagement \
  -framework ApplicationServices

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/剪贴板记录"
cp "$root/scripts/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
chmod +x "$app/Contents/MacOS/剪贴板记录"
sign_app "$app"

mkdir -p "${HOME}/Applications"
rm -rf "$installed"
cp -R "$app" "$installed"
sign_app "$installed"

echo "已安装 $installed"
