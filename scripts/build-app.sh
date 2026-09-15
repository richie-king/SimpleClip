#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/ClipTiny.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$ROOT_DIR/work/build"
SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"

cd "$ROOT_DIR"

mkdir -p "$BUILD_DIR" "$ROOT_DIR/work/clang-cache-x86_64" "$ROOT_DIR/work/clang-cache-arm64"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

for ARCH in x86_64 arm64; do
  CLANG_MODULE_CACHE_PATH="$ROOT_DIR/work/clang-cache-$ARCH" \
    swiftc -O -whole-module-optimization \
    -sdk "$SDK_DIR" \
    -target "$ARCH-apple-macosx26.0" \
    Sources/ClipTiny/*.swift \
    -o "$BUILD_DIR/ClipTiny-$ARCH"
done
lipo -create \
  "$BUILD_DIR/ClipTiny-x86_64" \
  "$BUILD_DIR/ClipTiny-arm64" \
  -output "$BUILD_DIR/ClipTiny"

cp "$BUILD_DIR/ClipTiny" "$CONTENTS_DIR/MacOS/ClipTiny"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod +x "$CONTENTS_DIR/MacOS/ClipTiny"

codesign --force --deep --sign - "$APP_DIR"
# Finder 会缓存旧图标，改动图标后靠 touch 让它重新读取。
touch "$APP_DIR"
echo "$APP_DIR"
