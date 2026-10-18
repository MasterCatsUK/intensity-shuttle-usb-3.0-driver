#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk=${1:-'../../adobe-sdk26/Premiere Pro 26.0 C++ SDK/Examples'}
if [[ ! -f "$sdk/Headers/PrSDKTransmit.h" ]]; then echo 'Supply the Adobe SDK Examples directory as argument 1.' >&2;exit 1;fi
bundle='build/Shuttle Transmit.bundle'
mkdir -p "$bundle/Contents/MacOS"
xcrun clang++ -std=c++17 -O2 -fobjc-arc -fvisibility=hidden -arch arm64 -mmacosx-version-min=13.0 \
    -DPRMAC_ENV=1 -I"$sdk/Headers" -I"$sdk/Headers/SP" \
    -bundle ShuttleTransmit.mm -framework Foundation -o "$bundle/Contents/MacOS/ShuttleTransmit"
python3 - "$bundle" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.shuttle.premiere.transmit',CFBundleExecutable='ShuttleTransmit',CFBundleName='Shuttle Transmit',CFBundlePackageType='BNDL',CFBundleVersion='1',CFBundleShortVersionString='0.1.29',LSMinimumSystemVersion='13.0')))
PY
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
echo "Built $bundle; nothing installed."
