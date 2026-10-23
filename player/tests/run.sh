#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
flags=(-std=c++14 -O2 -fobjc-arc -Wno-deprecated-declarations -mmacosx-version-min=13.0)
frameworks=(-framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics -framework AudioToolbox -framework CoreText)
xcrun clang++ "${flags[@]}" tests/GenerateFixture.mm "${frameworks[@]}" -o build/tests/generate
xcrun clang++ "${flags[@]}" tests/engine_test.mm src/MovieSource.mm "${frameworks[@]}" -o build/tests/engine-test
fixture="$PWD/build/tests/synthetic-sync.mov"
if [[ ! -f "$fixture" ]]; then build/tests/generate "$fixture"; fi
if [[ ! -f build/tests/Player-Output-Test.mov ]]; then build/tests/generate "$PWD/build/tests/Player-Output-Test.mov" --bars; fi
xcrun clang++ -std=c++14 -O2 tests/preview_clock_test.cpp -o build/tests/preview-clock-test
build/tests/preview-clock-test
build/tests/engine-test "$fixture"
'build/Shuttle Player.app/Contents/MacOS/ShuttlePlayer' --ui-test
