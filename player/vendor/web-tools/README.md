# Pinned web tools

Official yt-dlp2026.10.26 universal executable and source, QuickJS2026-06-04 source, and FFmpeg8.1.3 source. SHA256.json pins every input and is verified by tools/build_web_tools.sh before building. The official yt-dlp checksum list and FFmpeg detached upstream signature are included for independent verification. FFmpeg source: https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz . Upstream signature: same URL plus .asc . Build configuration and complete licences are in the source tree and packaged app resources.

FFmpeg8.1.3 supplies bounded HTTP request_size support used for YouTube streaming. This is an LGPL build with no GPL/nonfree components enabled. No helper auto-update or remote plug-in execution is enabled.
