#!/bin/bash
# GPL-2.0-or-later. Universal build; no installation or driver/security changes.
set -euo pipefail
cd "$(dirname "$0")"
export SDKROOT="$(xcrun --show-sdk-path)"
app='build/Shuttle Player.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
    root="$PWD/build/$arch/libusb-1.0.29"
    if [[ ! -f "$root/libusb/.libs/libusb-1.0.a" || ! -f "$root/.player-macos13" ]]; then
        mkdir -p "build/$arch"
        tar -xjf vendor/libusb-1.0.29.tar.bz2 -C "build/$arch"
        if [[ $arch == arm64 ]]; then triplet=aarch64-apple-darwin; else triplet=x86_64-apple-darwin; fi
        (cd "$root"; if [[ -f Makefile ]]; then make MAKE=/usr/bin/make clean >/dev/null 2>&1; fi
          ac_cv_func_pipe2=no CC=clang CFLAGS="-arch $arch -O2 -mmacosx-version-min=13.0" LDFLAGS="-arch $arch -mmacosx-version-min=13.0" \
          ./configure --host="$triplet" --disable-shared --enable-static --disable-examples-build --disable-tests-build > ../configure.log 2>&1
          make MAKE=/usr/bin/make -j4 > ../make.log 2>&1
          touch .player-macos13)
    fi
    flags=(-arch "$arch" -std=c++14 -O2 -fobjc-arc -Wno-deprecated-declarations -Werror=unguarded-availability-new -mmacosx-version-min=13.0)
    xcrun clang++ "${flags[@]}" src/PlayerOutput.mm src/MovieSource.mm src/CaptureGuard.mm -I"$root/libusb" "$root/libusb/.libs/libusb-1.0.a" \
      -framework Foundation -framework AVFoundation -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -framework CoreGraphics -framework IOKit -framework Security -o "build/$arch/ShuttlePlayerOutput"
    xcrun clang++ "${flags[@]}" src/PlayerHost.mm -framework Cocoa -framework AVFoundation -framework UniformTypeIdentifiers -framework CoreMedia -o "build/$arch/ShuttlePlayer"
done
for bin in ShuttlePlayer ShuttlePlayerOutput; do
    lipo -create "build/arm64/$bin" "build/x86_64/$bin" -output "$app/Contents/MacOS/$bin"
done
cp resources/AppIcon.icns COPYING THIRD-PARTY-NOTICES.md 'Read Me.html' "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/docs"
cp docs/Shuttle-Player.png "$app/Contents/Resources/docs/"
python3 - "$app" <<'PY'
from pathlib import Path
import plistlib,sys
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.shuttle.player',CFBundleName='Shuttle Player',CFBundleDisplayName='Shuttle Player',CFBundleExecutable='ShuttlePlayer',CFBundlePackageType='APPL',CFBundleShortVersionString='0.1.1',CFBundleVersion='2',CFBundleIconFile='AppIcon.icns',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True,NSPrincipalClass='NSApplication')))
PY
codesign --force --sign - "$app/Contents/MacOS/ShuttlePlayerOutput"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
lipo -info "$app/Contents/MacOS/ShuttlePlayer"
lipo -info "$app/Contents/MacOS/ShuttlePlayerOutput"
echo "Built $app. Intel is untested on hardware. Nothing installed."
