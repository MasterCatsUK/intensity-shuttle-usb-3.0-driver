#!/usr/bin/env python3
"""Package a built player plus complete editable source. No install or upload."""
from pathlib import Path
import shutil, subprocess, hashlib, zipfile, sys
root=Path(__file__).resolve().parent
out=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root.parent.parent/'outputs'/'Shuttle-Player-0.3.2'
if out.exists(): raise SystemExit(f'Refusing to overwrite an existing release: {out}')
out.mkdir(parents=True)
app=out/'Shuttle Player.app';shutil.copytree(root/'build'/'Shuttle Player.app',app)
source=out/'Source';source.mkdir()
for name in ['src','resources','vendor','tests','docs','tools']:
    shutil.copytree(root/name,source/name)
for name in ['build.sh','package.py','README.md','Read Me.html','COPYING','THIRD-PARTY-NOTICES.md','VALIDATION.md','CHANGELOG.md','.gitignore']:
    shutil.copy2(root/name,source/name)
for name in ['Read Me.html','README.md','COPYING','THIRD-PARTY-NOTICES.md','VALIDATION.md','CHANGELOG.md']:
    shutil.copy2(root/name,out/name)
shutil.copytree(root/'docs',out/'docs')
resources=app/'Contents'/'Resources'
for name in ['Read Me.html','COPYING','THIRD-PARTY-NOTICES.md']:
    shutil.copy2(root/name,resources/name)
shutil.copytree(root/'docs',resources/'docs',dirs_exist_ok=True)
shutil.copy2(root/'build'/'tests'/'Player-Output-Test.mov',out/'Player-Output-Test.mov')
(out/'Install.txt').write_text('Shuttle Player0.3.2: copy Shuttle Player.app to Applications. Open File > Open Video URL, paste a YouTube/Dailymotion/Vimeo link, choose Download first or Stream, then Open and Play. Stream supports scrub and ten-second skips, briefly buffering after each jump; Loop uses Download first. Choose HDMI and the required format first. Existing local-file and Stretch controls remain. No main-app/driver install or reactivation. This app is ad-hoc signed, not notarized. Intel/older macOS runtime untested. Source, pinned helper inputs/build scripts and all licences are included. No cached site videos are distributed.\n')
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
files=sorted(p for p in out.rglob('*') if p.is_file())
(out/'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(out).as_posix()}\n' for p in files))
archive=out.parent/(out.name+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(out.rglob('*')):
        if p.is_file(): z.write(p,Path(out.name)/p.relative_to(out))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert all('/build/' not in n and '/qa/' not in n for n in z.namelist())
print(out);print(archive)
