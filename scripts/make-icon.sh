#!/bin/zsh
set -euo pipefail

# 重新生成 Resources/AppIcon.icns。改了 MakeIcon.swift 之后跑一次即可，
# 平时构建不需要，build-app.sh 直接用已经生成好的 icns。
ROOT_DIR="${0:A:h:h}"
WORK_DIR="$ROOT_DIR/work/icon"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
SDK_DIR="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"

cd "$ROOT_DIR"
if [[ ! -d "$SDK_DIR" ]]; then
  SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$WORK_DIR"

swiftc -O -sdk "$SDK_DIR" \
  scripts/MakeIcon.swift \
  -o "$WORK_DIR/make-icon"
"$WORK_DIR/make-icon" "$ICONSET_DIR"

iconutil --convert icns "$ICONSET_DIR" --output "$ROOT_DIR/Resources/AppIcon.icns"
echo "$ROOT_DIR/Resources/AppIcon.icns"
