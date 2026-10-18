"""Write only local bundle metadata; no installation or security changes."""
from pathlib import Path
import plistlib
import sys

app, ext = map(Path, sys.argv[1:])
common = dict(CFBundleDevelopmentRegion="en", CFBundleShortVersionString="0.1",
              CFBundleVersion="15", LSMinimumSystemVersion="27.0")
host = dict(common, CFBundleIdentifier="local.shuttle.camera", CFBundleName="Shuttle Camera",
            CFBundleExecutable="ShuttleCamera", CFBundlePackageType="APPL",
            NSHighResolutionCapable=True,
            NSSystemExtensionUsageDescription="Expose the USB 3 Intensity Shuttle as a PAL or NTSC camera.")
camera = dict(common, CFBundleIdentifier="local.shuttle.camera.extension",
              CFBundleName="Shuttle Camera Extension", CFBundleExecutable="ShuttleCameraExtension",
              CFBundlePackageType="SYSX",
              NSSystemExtensionUsageDescription="Capture SD video from the USB 3 Intensity Shuttle.",
              CMIOExtension={"CMIOExtensionMachServiceName":"group.local.shuttle.camera.extension"})
for path, info in [(app,host),(ext,camera)]:
    with (path/"Contents/Info.plist").open("wb") as f:
        plistlib.dump(info,f)
