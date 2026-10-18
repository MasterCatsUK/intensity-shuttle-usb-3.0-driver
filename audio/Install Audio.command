#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang++ -O2 -Wno-deprecated-declarations tools/AdminInstall.cpp -framework Security -o build/admin-install
./build/admin-install "$PWD/tools/install-local.sh"
