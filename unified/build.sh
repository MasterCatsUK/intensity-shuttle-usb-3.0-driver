#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
camera_source=${1:-'../build/Shuttle Video.app'}
usb_base=${2:-"$PWD/../build"}
app='build/Shuttle Video.app'
mkdir -p build
ditto "$camera_source" "$app"
mkdir -p "$app/Contents/Resources"
cp resources/Startup.m4v "$app/Contents/Resources/Startup.m4v"
cp resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
    mkdir -p "build/$arch"
    usb="$usb_base/$arch/libusb-1.0.29"
    flags=(-arch "$arch" -std=c++14 -O2 -fobjc-arc -Werror=unguarded-availability-new -Wno-deprecated-declarations -mmacosx-version-min=14.4)
    xcrun clang++ "${flags[@]}" -I"$usb/libusb" -x objective-c++ src/output/PlaybackTest.cpp src/output/TimecodeOverlay.mm src/output/CaptureGuard.mm src/output/MovieSource.mm src/output/DesktopSource.mm src/output/ListeningOutput.mm src/output/Scopes.mm \
      -x none "$usb/libusb/.libs/libusb-1.0.a" -framework IOKit -framework CoreFoundation -framework Security -framework Foundation -framework CoreMediaIO -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics -framework CoreText -framework ScreenCaptureKit -framework ImageIO -framework Accelerate -framework AudioToolbox -framework CoreAudio -o "build/$arch/ShuttlePlayback"
    xcrun clang++ "${flags[@]}" src/output/ScreenOutput.mm src/output/ListeningOutput.mm src/output/Scopes.mm src/output/TimecodeOverlay.mm src/output/MovieSource.mm \
      -framework Cocoa -framework CoreImage -framework CoreMedia -framework CoreMediaIO -framework CoreVideo -framework AVFoundation -framework CoreText -framework ImageIO -framework Accelerate -framework AudioToolbox -framework CoreAudio -o "build/$arch/ShuttleScreenOutput"
    xcrun clang++ "${flags[@]}" src/output/VirtualDisplayMain.mm -framework Cocoa -framework CoreGraphics -o "build/$arch/ShuttleDisplay"
    xcrun clang++ "${flags[@]}" src/capture/Recorder.mm -framework AVFoundation -framework VideoToolbox -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -framework CoreAudio -framework AudioToolbox -o "build/$arch/ShuttleRecorder"
    xcrun clang++ "${flags[@]}" src/CombinedHost.mm -framework AudioToolbox -framework CoreAudio -framework Cocoa -framework SystemExtensions -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -framework CoreImage -framework AVFoundation -framework ImageIO -o "build/$arch/ShuttleCamera"

    xcrun clang++ "${flags[@]}" src/OutputExtension.mm -framework Foundation -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -o "build/$arch/ShuttleOutputExtension"
done
for program in ShuttlePlayback ShuttleScreenOutput ShuttleDisplay ShuttleRecorder ShuttleCamera; do
    lipo -create "build/arm64/$program" "build/x86_64/$program" -output "$app/Contents/MacOS/$program"
    codesign --force --sign - "$app/Contents/MacOS/$program"
done
ext="$app/Contents/Library/SystemExtensions/local.shuttle.output.extension.systemextension"
mkdir -p "$ext/Contents/MacOS"
lipo -create build/arm64/ShuttleOutputExtension build/x86_64/ShuttleOutputExtension -output "$ext/Contents/MacOS/ShuttleOutputExtension"
python3 - "$app" "$ext" <<'PY'
import sys,plistlib
from pathlib import Path
app,ext=map(Path,sys.argv[1:])
(ext/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.shuttle.output.extension',CFBundleName='Shuttle Video Output Extension',CFBundleExecutable='ShuttleOutputExtension',CFBundlePackageType='SYSX',CFBundleShortVersionString='0.1.48',CFBundleVersion='13',LSMinimumSystemVersion='14.4',NSSystemExtensionUsageDescription='Provide Virtual Shuttle and Intensity Shuttle as Final Cut output devices.',CMIOExtension={'CMIOExtensionMachServiceName':'group.local.shuttle.camera.output'})))
p=app/'Contents/Info.plist';info=plistlib.loads(p.read_bytes());info.update(CFBundleName='Shuttle Video',CFBundleDisplayName='Shuttle Video',CFBundleVersion='54',CFBundleShortVersionString='0.1.54',CFBundleIconFile='AppIcon.icns',LSMinimumSystemVersion='14.4',NSCameraUsageDescription='Show and record video from the Intensity Shuttle.',NSMicrophoneUsageDescription='Show levels, monitor and record stereo input from the Intensity Shuttle.');p.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - --entitlements resources/OutputExtension.entitlements "$ext"
codesign --force --sign - --entitlements resources/Host.entitlements "$app"
codesign --verify --deep --strict "$app"
echo 'Built universal Shuttle Video 54, camera21 / output13. Nothing installed.'
