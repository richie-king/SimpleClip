#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
APP_DIR="$ROOT_DIR/outputs/ClipTiny.app"
BINARY="$APP_DIR/Contents/MacOS/ClipTiny"
PLIST="$APP_DIR/Contents/Info.plist"
ARCHIVE="$ROOT_DIR/work/verification/ClipTiny-verified.zip"
mkdir -p "$ROOT_DIR/work/verification"
[[ -x "$BINARY" ]]
plutil -lint "$PLIST"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" == APPL ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" == 26.0 ]]
cmp Resources/Info.plist "$PLIST"
cmp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
[[ "$(lipo -archs "$BINARY")" == 'x86_64 arm64' ]]
for ARCH in x86_64 arm64; do
  xcrun vtool -arch "$ARCH" -show-build "$BINARY" | awk '/minos/ { if ($2 == "26.0") found = 1 } END { exit !found }'
done
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE"
unzip -tq "$ARCHIVE"
EXTRACT_DIR="$(mktemp -d "$ROOT_DIR/work/verification/extracted.XXXXXX")"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
ditto -x -k "$ARCHIVE" "$EXTRACT_DIR"
codesign --verify --deep --strict --verbose=2 "$EXTRACT_DIR/ClipTiny.app"
cmp "$BINARY" "$EXTRACT_DIR/ClipTiny.app/Contents/MacOS/ClipTiny"
[[ -x "$EXTRACT_DIR/ClipTiny.app/Contents/MacOS/ClipTiny" ]]
shasum -a 256 "$ARCHIVE"
echo 'PASS: 应用结构、双架构、最低版本、菜单栏应用标记、资源、签名及压缩解压完整性'
