#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/work/clang-cache-tests"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
# Command Line Tools 将 Testing.framework 放在独立目录，SwiftPM 未必自动搜索它。
TEST_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
TEST_FLAGS=()
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
  TEST_FLAGS=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS"
              -Xlinker -F -Xlinker "$TEST_FRAMEWORKS"
              -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS"
              -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS/../usr/lib")
fi
swift test --disable-xctest --scratch-path "$ROOT_DIR/work/tests" "${TEST_FLAGS[@]}" "$@"
