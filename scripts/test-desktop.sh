#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
BUILD_DIR="$ROOT_DIR/work/desktop-tests"
mkdir -p "$BUILD_DIR" "$ROOT_DIR/work/clang-cache-tests"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/work/clang-cache-tests"
for NAME in Fixture Receiver; do
  APP_DIR="$BUILD_DIR/ClipTiny$NAME.app"
  mkdir -p "$APP_DIR/Contents/MacOS" "$BUILD_DIR/$NAME"
  cp "Tests/DesktopSupport/${NAME}Main.swift" "$BUILD_DIR/$NAME/main.swift"
  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.local.ClipTiny.Desktop$NAME</string>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>ClipTiny $NAME</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
  SOURCE_FILES=()
  if [[ "$NAME" == Fixture ]]; then
    for SOURCE_FILE in Sources/ClipTiny/*.swift; do
      [[ "$SOURCE_FILE" == Sources/ClipTiny/main.swift ]] || SOURCE_FILES+=("$SOURCE_FILE")
    done
  fi
  swiftc -target "$(uname -m)-apple-macosx26.0" "${SOURCE_FILES[@]}" "$BUILD_DIR/$NAME/main.swift" -o "$APP_DIR/Contents/MacOS/$NAME"
  codesign --force --sign - "$APP_DIR"
done
swiftc Tests/DesktopSupport/Driver.swift -o "$BUILD_DIR/driver"
RUN_DIR="$(mktemp -d "$BUILD_DIR/run.XXXXXX")"
echo "报告目录：$RUN_DIR"
"$BUILD_DIR/driver" "$RUN_DIR" "$BUILD_DIR/ClipTinyFixture.app" "$BUILD_DIR/ClipTinyReceiver.app"
