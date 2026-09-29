#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chiakey-temporary-english.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

clang++ -std=c++11 -Wall -Wextra -Werror \
  "$ROOT_DIR/ChiaKey-Source/Loaders/OSX-IMK/Tests/TestTemporaryEnglishSession.cpp" \
  -o "$TEST_DIR/test-temporary-english"
"$TEST_DIR/test-temporary-english"
