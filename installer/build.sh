#!/bin/bash
# GPL-2.0-or-later. Build an installer; never install or alter the running setup.
set -euo pipefail
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [[ -d "$script_root/../Shuttle Camera.app" ]]; then default_source="$script_root/.."; else default_source="$script_root/../../outputs/shuttle-camera-development"; fi
source_bundle=$(CDPATH= cd -- "${1:-$default_source}" && pwd)
output_dir=${2:-$source_bundle/../shuttle-installer}
/bin/mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
if [[ -n ${3:-} ]]; then /bin/mkdir -p "$3"; build=$(/usr/bin/mktemp -d "$3/run.XXXXXX"); else build=$(/usr/bin/mktemp -d /private/tmp/shuttle-pkg.XXXXXX); fi
build=$(CDPATH= cd -- "$build" && pwd)
printf 'Build directory: %s\n' "$build"
app="$source_bundle/Shuttle Camera.app"
audio="$source_bundle/audio/Shuttle Audio.driver"
premiere="$source_bundle/unified/premiere/build/Shuttle Transmit.bundle"
/usr/bin/codesign --verify --deep --strict "$premiere"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign --verify --deep --strict "$audio"
python3 - "$app" "$audio" <<'PY'
import plistlib,sys
from pathlib import Path
app=Path(sys.argv[1]);extensions=app/'Contents/Library/SystemExtensions'
for root,identifier,version in [(app,'local.shuttle.camera','31'),(Path(sys.argv[2]),'local.shuttle.audio','3'),
    (extensions/'local.shuttle.camera.extension.systemextension','local.shuttle.camera.extension','15'),
    (extensions/'local.shuttle.output.extension.systemextension','local.shuttle.output.extension','12')]:
    p=plistlib.loads((root/'Contents/Info.plist').read_bytes())
    assert (p['CFBundleIdentifier'],p['CFBundleVersion'])==(identifier,version), f'Unexpected payload version: {root}'
PY
/bin/mkdir -p "$build/scripts" "$build/payload/Applications" "$build/payload/Library/Audio/Plug-Ins/HAL" "$build/packages" "$build/resources"
/usr/bin/ditto "$script_root/scripts" "$build/scripts"
xcrun clang++ -std=c++17 -O2 -fobjc-arc -mmacosx-version-min=27.0 "$script_root/src/CaptureCheck.mm" \
    -framework Foundation -framework CoreMediaIO -o "$build/scripts/check-capture"
/usr/bin/codesign --force --sign - "$build/scripts/check-capture"
/bin/bash -n "$build/scripts/preinstall"
/bin/bash -n "$build/scripts/postinstall"
python3 "$script_root/tests/installer_test.py"
/usr/bin/ditto --norsrc --noextattr --noacl "$app" "$build/payload/Applications/Shuttle Camera.app"
/usr/bin/ditto --norsrc --noextattr --noacl "$audio" "$build/payload/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver"
plugin_target="$build/payload/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle"
/bin/mkdir -p "$(dirname "$plugin_target")"
/usr/bin/ditto --norsrc --noextattr --noacl "$premiere" "$plugin_target"
support="$build/payload/Library/Application Support/Shuttle Camera"
/bin/mkdir -p "$support"
/usr/bin/ditto "$script_root/resources" "$build/resources"
/bin/cp "$script_root/resources/ReadMe.html" "$support/Read Me.html"
/bin/cp "$script_root/PLAYBACK-ROADMAP.md" "$support/Playback Roadmap.md"
/bin/cp "$source_bundle/COPYING" "$support/COPYING"
# All source, dependencies, licences and installer sources accompany the binaries.
/usr/bin/ditto "$source_bundle" "$build/source/shuttle-camera-development"
/bin/mkdir -p "$build/source/shuttle-camera-development/installer"
for path in src scripts resources tests; do /usr/bin/ditto "$script_root/$path" "$build/source/shuttle-camera-development/installer/$path"; done
for path in build.sh README.md PLAYBACK-ROADMAP.md; do /bin/cp "$script_root/$path" "$build/source/shuttle-camera-development/installer/$path"; done
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$build/source/shuttle-camera-development" "$support/Source.zip"
# Explicitly replace whole bundles and never relocate them to another copy.
/usr/bin/pkgbuild --analyze --root "$build/payload" "$build/components.plist"
python3 - "$build/components.plist" "$build/requirements.plist" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]);items=plistlib.loads(p.read_bytes())
def update(items):
    for item in items:
        item.update(BundleIsRelocatable=False,BundleIsVersionChecked=True,BundleHasStrictIdentifier=True,BundleOverwriteAction='upgrade')
        update(item.get('ChildBundles',[]))
update(items);p.write_bytes(plistlib.dumps(items))
Path(sys.argv[2]).write_bytes(plistlib.dumps({'os':['27.0'],'arch':['arm64']}))
PY
/usr/bin/pkgbuild --identifier local.shuttle.capture.installer --version 0.1.31 \
    --root "$build/payload" --install-location / --component-plist "$build/components.plist" \
    --scripts "$build/scripts" --ownership recommended "$build/packages/ShuttleCapture.pkg"
/usr/bin/productbuild --synthesize --product "$build/requirements.plist" --package "$build/packages/ShuttleCapture.pkg" "$build/Distribution"
python3 - "$build/Distribution" <<'PY'
from pathlib import Path
import sys,xml.etree.ElementTree as E
p=Path(sys.argv[1]);tree=E.parse(p);root=tree.getroot()
E.SubElement(root,'title').text='Shuttle Capture — Development Build'
E.SubElement(root,'welcome',{'file':'Welcome.html','mime-type':'text/html'})
E.SubElement(root,'readme',{'file':'ReadMe.html','mime-type':'text/html'})
E.SubElement(root,'conclusion',{'file':'Conclusion.html','mime-type':'text/html'})
E.SubElement(root,'domains',{'enable_anywhere':'false','enable_currentUserHome':'false','enable_localSystem':'true'})
options=root.find('options');options.set('customize','never');options.set('rootVolumeOnly','true')
for reference in root.findall('pkg-ref'):
    if reference.text: reference.text='ShuttleCapture.pkg'
E.indent(tree,space='  ');tree.write(p,encoding='utf-8',xml_declaration=True)
PY
/usr/bin/productbuild --distribution "$build/Distribution" --resources "$build/resources" \
    --package-path "$build/packages" "$build/Shuttle-Capture-0.1.31.pkg"
# Validate the actual archive without invoking its installation scripts.
/usr/sbin/pkgutil --expand-full "$build/Shuttle-Capture-0.1.31.pkg" "$build/expanded"
expanded="$build/expanded/ShuttleCapture.pkg/Payload"
/usr/bin/codesign --verify --deep --strict "$expanded/Applications/Shuttle Camera.app"
/usr/bin/codesign --verify --deep --strict "$expanded/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver"
/usr/bin/diff -qr "$app" "$expanded/Applications/Shuttle Camera.app"
/usr/bin/diff -qr "$audio" "$expanded/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver"
/usr/bin/codesign --verify --deep --strict "$expanded/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle"
/usr/bin/diff -qr "$premiere" "$expanded/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle"
python3 - "$build/expanded" <<'PY'
from pathlib import Path
import sys,zipfile,xml.etree.ElementTree as E
root=Path(sys.argv[1]);dist=E.parse(root/'Distribution').getroot()
assert dist.find('options').get('hostArchitectures')=='arm64'
assert dist.find('domains').get('enable_localSystem')=='true'
assert dist.find('options').get('allow-external-scripts')!='yes'
source=root/'ShuttleCapture.pkg/Payload/Library/Application Support/Shuttle Camera/Source.zip'
with zipfile.ZipFile(source) as z:
    for name in ['src/CameraExtension.mm','audio/src/AudioDriver.cpp','installer/src/CaptureCheck.mm','installer/build.sh','unified/src/output/OutputPacket.hpp','unified/src/output/MovieSource.mm','unified/build.sh','vendor/libusb-1.0.29.tar.bz2','COPYING']:
        assert 'shuttle-camera-development/'+name in z.namelist(),name
print('PASS: exact unified camera/audio payloads, valid bundle signatures, ARM64/startup-volume restrictions, embedded complete source')
PY
package="$output_dir/Shuttle-Capture-0.1.31.pkg"
if [[ -e $package ]]; then /bin/mv "$package" "$build/previous-installer.pkg"; fi
/bin/cp "$build/Shuttle-Capture-0.1.31.pkg" "$package"
/bin/cp "$script_root/README.md" "$output_dir/Read Me.md"
/bin/cp "$script_root/PLAYBACK-ROADMAP.md" "$output_dir/Playback Roadmap.md"
(cd "$output_dir"; /usr/bin/shasum -a 256 Shuttle-Capture-0.1.31.pkg > SHA256.txt)
printf 'Built and expanded successfully: %s\nNothing was installed.\n' "$package"
