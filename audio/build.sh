#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p 'build/Shuttle Audio.driver/Contents/MacOS'
for arch in arm64 x86_64; do
    mkdir -p "build/$arch/objects"
    flags=(-arch "$arch" -mmacosx-version-min=14.4 -std=c++17 -O2 -fPIC -Werror=unguarded-availability-new -Wno-invalid-noreturn -Wno-invalid-offsetof -Ivendor/libASPL/include -Isrc)
    for source in vendor/libASPL/src/*.cpp; do
        object="build/$arch/objects/$(basename "$source" .cpp).o"
        if [[ ! -f $object || $source -nt $object ]]; then xcrun clang++ "${flags[@]}" -c "$source" -o "$object"; fi
    done
    xcrun clang++ "${flags[@]}" -bundle src/AudioDriver.cpp "build/$arch/objects/"*.o -framework CoreFoundation -framework CoreAudio -o "build/$arch/ShuttleAudio"
done
lipo -create build/arm64/ShuttleAudio build/x86_64/ShuttleAudio -output 'build/Shuttle Audio.driver/Contents/MacOS/ShuttleAudio'
python3 - <<'PY'
from pathlib import Path
import plistlib
uid='73B7E34D-4748-4EEB-B07E-E3B72113C9A0'
info=dict(CFBundleIdentifier='local.shuttle.audio',CFBundleName='Shuttle Audio',CFBundleExecutable='ShuttleAudio',CFBundleVersion='4',CFBundleShortVersionString='0.1.48',LSMinimumSystemVersion='14.4',CFBundlePackageType='BNDL',CFBundleDevelopmentRegion='en',CFPlugInFactories={uid:'ShuttleAudioEntryPoint'},CFPlugInTypes={'443ABAB8-E7B3-491A-B985-BEB9187030DB':[uid]},sandboxSafe=True,AudioServerPlugIn_Network=True,AudioServerPlugIn_MachServices=[])
Path('build/Shuttle Audio.driver/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - 'build/Shuttle Audio.driver'
codesign --verify --deep --strict 'build/Shuttle Audio.driver'
