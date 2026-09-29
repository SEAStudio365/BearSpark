#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/ChiaKey-Source"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chiakey-symbol-metadata.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun ibtool --compile "$TEST_DIR/SymbolWindow.nib" \
  "$SOURCE_DIR/Loaders/OSX-IMK/Interface/SymbolWindow.xib"
for dev_logging in 0 1; do
xcrun clang++ -DCHIAKEY_DEV_LOGGING="$dev_logging" -x objective-c++ -std=c++17 -DOV_USE_SQLITE -Wno-deprecated-declarations -Wno-incomplete-implementation \
  -I"$SOURCE_DIR/Frameworks/HeaderShims" \
  -I"$SOURCE_DIR/Frameworks/PlainVanilla/Headers" \
  -I"$SOURCE_DIR/Frameworks/CareService/Headers" \
  -I"$SOURCE_DIR/Loaders/CrossPlatform" \
  -I"$SOURCE_DIR/Loaders/OSX-IMK" \
  "$SOURCE_DIR/Loaders/OSX-IMK/CVButtonViewController.mm" \
  "$SOURCE_DIR/Loaders/OSX-IMK/CVFloatingPanelWindow.m" \
  "$SOURCE_DIR/Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm" \
  "$SOURCE_DIR/Loaders/OSX-IMK/Tests/TestSymbolMetadata.mm" \
  -framework Cocoa -framework InputMethodKit -lsqlite3 -lexpat \
  -o "$TEST_DIR/test-symbol-metadata"
"$TEST_DIR/test-symbol-metadata" "$TEST_DIR/SymbolWindow.nib"
done
