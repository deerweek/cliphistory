#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$root/.build/ModuleCache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$root/.build/ModuleCache}"
# shellcheck disable=SC1091
source "$root/scripts/toolchain.sh"
# shellcheck disable=SC1091
source "$root/scripts/signing.sh"
cd "$root"

mkdir -p .build
bin=".build/ClipHistory"
app="$root/dist/剪贴板记录.app"
installed="${CLIPHISTORY_INSTALL_DEST:-${HOME}/Applications/剪贴板记录.app}"

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
  -framework ApplicationServices \
  -framework Vision

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/剪贴板记录"
cp "$root/scripts/Info.plist" "$app/Contents/Info.plist"
if [[ -f "$root/scripts/AppIcon.icns" ]]; then
  cp "$root/scripts/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$app/Contents/PkgInfo"
chmod +x "$app/Contents/MacOS/剪贴板记录"
sign_app "$app"

if [[ "${CLIPHISTORY_SKIP_INSTALL:-0}" == "1" ]]; then
  echo "已生成 $app（跳过安装）"
  exit 0
fi

mkdir -p "$(dirname "$installed")"
if [[ -e "$installed" ]] && ! rm -rf "$installed" 2>/dev/null; then
  echo "已生成 $app，但无法覆盖 $installed。请在 Finder 中移除旧应用后重新运行，或设置 CLIPHISTORY_INSTALL_DEST 指定可写路径。" >&2
  exit 1
fi
if ! cp -R "$app" "$installed"; then
  echo "已生成 $app，但无法安装到 $installed。请手动复制应用，或设置 CLIPHISTORY_INSTALL_DEST 指定可写路径。" >&2
  exit 1
fi
sign_app "$installed"

if ! cmp -s "$app/Contents/MacOS/剪贴板记录" "$installed/Contents/MacOS/剪贴板记录"; then
  echo "安装校验失败：$installed 中的可执行文件与构建产物不一致。" >&2
  exit 1
fi

echo "已安装 $installed"
