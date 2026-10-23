#!/bin/bash
# Universal development build only. No installation, activation or security changes.
set -euo pipefail
cd "$(dirname "$0")"
export SDKROOT="$(xcrun --show-sdk-path)"
app='build/Shuttle Video.app'
ext="$app/Contents/Library/SystemExtensions/local.shuttle.camera.extension.systemextension"
mkdir -p "$app/Contents/MacOS" "$ext/Contents/MacOS"
for arch in arm64 x86_64; do
    usb="$PWD/build/$arch/libusb-1.0.29"
    if [[ ! -f "$usb/libusb/.libs/libusb-1.0.a" || ! -f "$usb/.player-macos13" ]]; then
        mkdir -p "build/$arch";tar -xjf vendor/libusb-1.0.29.tar.bz2 -C "build/$arch"
        if [[ $arch == arm64 ]]; then triplet=aarch64-apple-darwin; else triplet=x86_64-apple-darwin; fi
        (cd "$usb"; ac_cv_func_pipe2=no CC=clang CFLAGS="-arch $arch -O2 -mmacosx-version-min=14.4" LDFLAGS="-arch $arch -mmacosx-version-min=14.4" \
          ./configure --host="$triplet" --disable-shared --enable-static --disable-examples-build --disable-tests-build > ../configure.log 2>&1
          make MAKE=/usr/bin/make -j4 > ../make.log 2>&1;touch .player-macos13)
    fi
    flags=(-arch "$arch" -isysroot "$SDKROOT" -mmacosx-version-min=14.4 -std=c++14 -O2 -Werror=unguarded-availability-new -Wno-deprecated-declarations -Ivendor -I"$usb/libusb")
    xcrun clang++ "${flags[@]}" -fobjc-arc src/CameraExtension.mm vendor/bmusb.cpp "$usb/libusb/.libs/libusb-1.0.a" \
      -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -framework Foundation -framework IOKit -framework Security -framework Accelerate -o "build/$arch/ShuttleCameraExtension"
done
lipo -create build/arm64/ShuttleCameraExtension build/x86_64/ShuttleCameraExtension -output "$ext/Contents/MacOS/ShuttleCameraExtension"
python3 tools/package.py "$app" "$ext"
codesign --force --sign - --entitlements resources/Extension.entitlements "$ext"
./unified/build.sh "$PWD/$app" "$PWD/build"
ditto 'unified/build/Shuttle Video.app' "$app"
echo 'Built universal Shuttle Video 0.1.54. Intel and older macOS are untested; nothing installed.'
