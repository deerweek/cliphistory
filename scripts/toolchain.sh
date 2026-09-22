# Shared compiler settings. This Mac's default SDK is 26.2 (Swift 6.2),
# but the installed compiler is 6.1.2, so we pin a matching SDK.
: "${SDKROOT:=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk}"
: "${MACOSX_DEPLOYMENT_TARGET:=14.0}"
TARGET="${TARGET:-arm64-apple-macos${MACOSX_DEPLOYMENT_TARGET}}"

if [[ ! -d "$SDKROOT" ]]; then
  echo "找不到 SDK：$SDKROOT" >&2
  exit 1
fi

export SDKROOT
export MACOSX_DEPLOYMENT_TARGET
