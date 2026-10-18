#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -n ${1:-} ]]; then camera_source=$1;
elif [[ -d '../build/Shuttle Camera.app' ]]; then camera_source='../build/Shuttle Camera.app';
elif [[ -d '../Shuttle Camera.app' ]]; then camera_source='../Shuttle Camera.app';
else camera_source='../shuttle-camera-extension/build/Shuttle Camera.app'; fi
if [[ -n ${2:-} ]]; then libusb_root=$2;
elif [[ -d ../build/libusb-1.0.29 ]]; then libusb_root=../build/libusb-1.0.29;
else libusb_root=../shuttle-playback/build/libusb-1.0.29; fi
app='build/Shuttle Camera.app'
mkdir -p build
ditto "$camera_source" "$app"
mkdir -p "$app/Contents/Resources"
cp resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$app/Contents/Info.plist"
flags=(-std=c++14 -O2 -fobjc-arc -Wno-deprecated-declarations -mmacosx-version-min=27.0)
xcrun clang++ "${flags[@]}" -I"$libusb_root/libusb" -x objective-c++ src/output/PlaybackTest.cpp src/output/TimecodeOverlay.mm src/output/CaptureGuard.mm src/output/MovieSource.mm src/output/DesktopSource.mm \
    -x none "$libusb_root/libusb/.libs/libusb-1.0.a" -framework IOKit -framework CoreFoundation -framework Security \
    -framework Foundation -framework CoreMediaIO -framework AVFoundation -framework CoreMedia -framework CoreVideo \
    -framework CoreGraphics -framework CoreText -framework ScreenCaptureKit -framework ImageIO -framework Accelerate -o "$app/Contents/MacOS/ShuttlePlayback"
xcrun clang++ "${flags[@]}" src/output/VirtualDisplayMain.mm -framework Cocoa -framework CoreGraphics -o "$app/Contents/MacOS/ShuttleDisplay"
xcrun clang++ "${flags[@]}" src/CombinedHost.mm -framework CoreAudio -framework Cocoa -framework SystemExtensions -framework CoreMediaIO -framework CoreMedia -framework ImageIO -o "$app/Contents/MacOS/ShuttleCamera"
ext="$app/Contents/Library/SystemExtensions/local.shuttle.output.extension.systemextension"
mkdir -p "$ext/Contents/MacOS"
xcrun clang++ "${flags[@]}" src/OutputExtension.mm -framework Foundation -framework CoreMediaIO -framework CoreMedia -framework CoreVideo -o "$ext/Contents/MacOS/ShuttleOutputExtension"
python3 - "$ext" <<'PYMETA'
import sys,plistlib
from pathlib import Path
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.shuttle.output.extension',CFBundleName='Shuttle HDMI Output Extension',CFBundleExecutable='ShuttleOutputExtension',CFBundlePackageType='SYSX',CFBundleShortVersionString='0.1',CFBundleVersion='12',LSMinimumSystemVersion='27.0',NSSystemExtensionUsageDescription='Provide the Intensity Shuttle as a video output device for editing apps.',CMIOExtension={'CMIOExtensionMachServiceName':'group.local.shuttle.camera.output'})))
PYMETA
codesign --force --sign - --entitlements resources/OutputExtension.entitlements "$ext"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 39' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.39' "$app/Contents/Info.plist"
codesign --force --sign - "$app/Contents/MacOS/ShuttleDisplay"
codesign --force --sign - "$app/Contents/MacOS/ShuttlePlayback"
codesign --force --sign - --entitlements resources/Host.entitlements "$app"
codesign --verify --deep --strict "$app"
echo 'Built experimental unified camera host 39; embedded camera extension stays at version 17 with live input picture controls. Nothing installed.'
