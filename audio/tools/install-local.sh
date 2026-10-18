#!/bin/sh
set -eu
exec 2>&1
script_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$script_root/Shuttle Audio.driver"
if [ ! -d "$src" ]; then src="$script_root/build/Shuttle Audio.driver"; fi
dest='/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver'
if [ -e "$dest" ]; then
    echo 'Existing Shuttle audio driver found; no replacement performed.'
    exit 1
fi
/usr/bin/ditto "$src" "$dest"
/usr/sbin/chown -R root:wheel "$dest"
/bin/chmod -R go-w "$dest"
/usr/bin/codesign --verify --deep --strict "$dest"
/bin/launchctl kickstart -k system/com.apple.audio.coreaudiod
echo 'Shuttle audio driver installed; Core Audio restarted.'
