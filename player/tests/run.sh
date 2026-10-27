#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
flags=(-std=c++14 -O2 -fobjc-arc -Wno-deprecated-declarations -mmacosx-version-min=13.0)
frameworks=(-framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics -framework AudioToolbox -framework CoreText)
xcrun clang++ "${flags[@]}" tests/GenerateFixture.mm "${frameworks[@]}" -o build/tests/generate
xcrun clang++ "${flags[@]}" tests/engine_test.mm src/MovieSource.mm src/StreamingSource.mm "${frameworks[@]}" -o build/tests/engine-test
fixture="$PWD/build/tests/synthetic-sync.mov"
if [[ ! -f "$fixture" ]]; then build/tests/generate "$fixture"; fi
if [[ ! -f build/tests/Player-Output-Test.mov ]]; then build/tests/generate "$PWD/build/tests/Player-Output-Test.mov" --bars; fi
xcrun clang++ -std=c++14 -O2 tests/preview_clock_test.cpp -o build/tests/preview-clock-test
build/tests/preview-clock-test
build/tests/engine-test "$fixture"
xcrun clang++ "${flags[@]}" tests/web_video_test.mm -framework Foundation -o build/tests/web-video-test
build/tests/web-video-test
python3 tests/web_worker_test.py 'build/Shuttle Player.app/Contents/MacOS/ShuttleWebWorker'
'build/Shuttle Player.app/Contents/MacOS/ShuttlePlayer' --ui-test

xcrun clang++ "${flags[@]}" tests/stream_test.mm src/StreamingSource.mm "${frameworks[@]}" -o build/tests/stream-test
build/tests/stream-test "$fixture" "$PWD/build/Shuttle Player.app/Contents/MacOS"
xcrun clang++ "${flags[@]}" tests/stream_stall_test.mm src/StreamingSource.mm "${frameworks[@]}" -o build/tests/stream-stall-test
python3 tests/stream_stall_test.py 'build/Shuttle Player.app/Contents/MacOS/ShuttleWebWorker' build/tests/stream-stall-test

xcrun clang++ "${flags[@]}" tests/stream_engine_test.mm src/MovieSource.mm src/StreamingSource.mm "${frameworks[@]}" -o build/tests/stream-engine-test
build/tests/stream-engine-test "$fixture" "$PWD/build/Shuttle Player.app/Contents/MacOS"

xcrun clang++ "${flags[@]}" tests/stream_tls_test.mm src/StreamingSource.mm "${frameworks[@]}" -o build/tests/stream-tls-test
python3 tests/stream_tls_test.py build/tests/stream-tls-test 'build/Shuttle Player.app/Contents/MacOS'

python3 tests/http_range_test.py 'build/Shuttle Player.app/Contents/MacOS/WebTools/ffprobe' "$fixture"

xcrun clang++ "${flags[@]}" tests/stream_seek_test.mm src/MovieSource.mm src/StreamingSource.mm "${frameworks[@]}" -o build/tests/stream-seek-test
build/tests/stream-seek-test "$fixture" "$PWD/build/Shuttle Player.app/Contents/MacOS"
