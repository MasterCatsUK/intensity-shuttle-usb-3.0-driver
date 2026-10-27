#!/bin/bash
# GPL-2.0-or-later. Build bundled URL helpers from pinned, hash-checked sources.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import hashlib,json
from pathlib import Path
root=Path('vendor/web-tools')
for name,digest in json.loads((root/'SHA256.json').read_text()).items():
 assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
print('PASS pinned web helper hashes')
PY
mkdir -p build/web-tools build/web-src
for arch in arm64 x86_64; do
 qroot="$PWD/build/web-src/quickjs-$arch"
 if [[ ! -x "$qroot/qjs" ]]; then
  mkdir -p "$qroot";tar -xf vendor/web-tools/quickjs-2026-06-04.tar.xz --strip-components=1 -C "$qroot"
  make -C "$qroot" -j4 CC="clang -arch $arch -mmacosx-version-min=13.0" AR=ar HOST_CC=clang CROSS_PREFIX=player- qjs > "$PWD/build/quickjs-$arch.log" 2>&1
 fi
 froot="$PWD/build/web-src/ffmpeg-8.1.3-$arch"
 if [[ ! -x "$froot/ffmpeg" || ! -f "$froot/.player-streaming-v2" ]]; then
  mkdir -p "$froot";tar -xf vendor/web-tools/ffmpeg-8.1.3.tar.xz --strip-components=1 -C "$froot"
  if [[ $arch == arm64 ]]; then farch=aarch64; else farch=x86_64; fi
  (cd "$froot"; ./configure --enable-cross-compile --target-os=darwin --arch="$farch" --cc=clang --ar=ar \
   --extra-cflags="-arch $arch -mmacosx-version-min=13.0" --extra-ldflags="-arch $arch -mmacosx-version-min=13.0" \
   --disable-autodetect --disable-doc --disable-debug --enable-network --enable-securetransport --disable-everything --disable-x86asm \
   --enable-ffmpeg --enable-ffprobe --enable-protocol=file,pipe,http,https,tcp,tls,crypto --enable-demuxer=mov,matroska,mpegts,aac,hls \
   --enable-muxer=mp4,mov,adts,rawvideo,pcm_s32le --enable-parser=aac,h264,hevc --enable-bsf=aac_adtstoasc,extract_extradata,setts \
   --enable-decoder=aac,h264,pcm_s16le,pcm_s32le --enable-encoder=rawvideo,pcm_s32le --enable-filter=scale,pad,crop,fps,format,setsar,aresample,asetpts > "../ffmpeg-configure-$arch.log" 2>&1
   make -j4 > "../ffmpeg-build-$arch.log" 2>&1
   touch .player-streaming-v2)
 fi
done
lipo -create build/web-src/quickjs-arm64/qjs build/web-src/quickjs-x86_64/qjs -output build/web-tools/qjs
for bin in ffmpeg ffprobe; do lipo -create "build/web-src/ffmpeg-8.1.3-arm64/$bin" "build/web-src/ffmpeg-8.1.3-x86_64/$bin" -output "build/web-tools/$bin"; done
cp vendor/web-tools/yt-dlp_macos build/web-tools/yt-dlp
chmod +x build/web-tools/*
for bin in yt-dlp qjs ffmpeg ffprobe; do codesign --force --sign - "build/web-tools/$bin"; done
mkdir -p resources/Web-Licences
cp vendor/web-tools/yt-dlp-THIRD-PARTY.txt resources/Web-Licences/yt-dlp-THIRD-PARTY.txt
tar -xOf vendor/web-tools/yt-dlp-2026.10.26.tar.gz yt-dlp/LICENSE > resources/Web-Licences/yt-dlp-LICENSE.txt
cp build/web-src/quickjs-arm64/LICENSE resources/Web-Licences/QuickJS-LICENSE.txt
cp build/web-src/ffmpeg-8.1.3-arm64/COPYING.LGPLv2.1 resources/Web-Licences/FFmpeg-LGPL-2.1.txt
cp build/web-src/ffmpeg-8.1.3-arm64/LICENSE.md resources/Web-Licences/FFmpeg-LICENSE.md
