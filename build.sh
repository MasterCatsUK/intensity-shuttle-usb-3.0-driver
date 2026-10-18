#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export SDKROOT="$(xcrun --show-sdk-path)"
mkdir -p build
if [ ! -f build/libusb-1.0.29/libusb/.libs/libusb-1.0.a ]; then
    tar -xjf vendor/libusb-1.0.29.tar.bz2 -C build
    (cd build/libusb-1.0.29; ./configure --disable-shared --enable-static --disable-examples-build --disable-tests-build; make -j4)
fi
app="build/Shuttle Camera.app"
ext="$app/Contents/Library/SystemExtensions/local.shuttle.camera.extension.systemextension"
mkdir -p "$app/Contents/MacOS" "$ext/Contents/MacOS" build/bin
if [ -d "$ext/Contents/Helpers" ]; then
    retired="$(mktemp -d build/retired-helper.XXXXXX)"
    mv "$ext/Contents/Helpers" "$retired/"
fi
if [ -f "$ext/Contents/MacOS/shuttle-bridge" ]; then
    retired="$(mktemp -d build/retired-helper.XXXXXX)"
    mv "$ext/Contents/MacOS/shuttle-bridge" "$retired/"
fi
cxx="$(xcrun --find clang++)"
flags=(-isysroot "$SDKROOT" -std=c++14 -O2 -Wall -Wextra -Wno-unused-parameter -Ivendor -Ibuild/libusb-1.0.29/libusb)
"$cxx" "${flags[@]}" src/Bridge.cpp vendor/bmusb.cpp build/libusb-1.0.29/libusb/.libs/libusb-1.0.a \
    -framework IOKit -framework CoreFoundation -framework Security -framework CoreMedia \
    -o build/bin/shuttle-bridge
"$cxx" "${flags[@]}" -fobjc-arc src/CameraExtension.mm vendor/bmusb.cpp \
    build/libusb-1.0.29/libusb/.libs/libusb-1.0.a -framework CoreMediaIO -framework CoreMedia \
    -framework CoreVideo -framework Foundation -framework IOKit -framework Security -framework Accelerate \
    -o "$ext/Contents/MacOS/ShuttleCameraExtension"
"$cxx" "${flags[@]}" -fobjc-arc src/Host.mm -framework AppKit -framework SystemExtensions -framework CoreMediaIO \
    -o "$app/Contents/MacOS/ShuttleCamera"
python3 tools/package.py "$app" "$ext"
codesign --force --sign - build/bin/shuttle-bridge
codesign --force --sign - --entitlements resources/Extension.entitlements "$ext"
codesign --force --sign - --entitlements resources/Host.entitlements "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt locally signed development bundle: %s\n' "$app"
printf 'Not activated. This script does not change SIP or system-extension settings.\n'

# Combine capture and HDMI playback into one host; camera service stays tested 15.
./unified/build.sh "$PWD/build/Shuttle Camera.app" "$PWD/build/libusb-1.0.29"
ditto 'unified/build/Shuttle Camera.app' 'build/Shuttle Camera.app'
