#!/bin/bash
# Build locally only; no installation, activation or security changes.
set -euo pipefail
cd "$(dirname "$0")"
[[ -n ${1:-} && -f "$1/Headers/PrSDKTransmit.h" ]] || { echo 'Usage: ./build-release.sh "/path/to/Premiere C++ SDK/Examples"' >&2;exit 64; }
adobe_examples=$(CDPATH= cd -- "$1" && pwd)
./build.sh
./audio/build.sh
./unified/premiere/build.sh "$adobe_examples"
python3 tools/stage_release.py
./installer/build.sh "$PWD/build/release-source/shuttle-video-development" "$PWD/build/packages" "$PWD/build/package-work"
echo 'Build complete. Nothing installed; see build/packages.'
