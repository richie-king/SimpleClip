#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/ClipTiny-arm64.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$ROOT_DIR/work/build"
SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"

cd "$ROOT_DIR"

mkdir -p "$BUILD_DIR" "$ROOT_DIR/work/clang-cache-arm64"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/work/clang-cache-arm64" \
  swiftc -O -whole-module-optimization \
  -sdk "$SDK_DIR" \
  -target "arm64-apple-macosx26.0" \
  Sources/ClipTiny/*.swift \
  -o "$BUILD_DIR/ClipTiny-arm64"

cp "$BUILD_DIR/ClipTiny-arm64" "$CONTENTS_DIR/MacOS/ClipTiny"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod +x "$CONTENTS_DIR/MacOS/ClipTiny"

codesign --force --deep --sign - "$APP_DIR"
touch "$APP_DIR"

# 打包为 zip
ZIP_FILE="$OUTPUT_DIR/ClipTiny-arm64.zip"
rm -f "$ZIP_FILE"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_FILE"

echo "$APP_DIR"
echo "$ZIP_FILE"
