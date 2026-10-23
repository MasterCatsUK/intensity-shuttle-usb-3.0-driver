"""Read-only architecture/deployment/signature validation of release bundles."""
import plistlib,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bundles=[root/'build/Shuttle Video.app',root/'audio/build/Shuttle Audio.driver',root/'unified/premiere/build/Shuttle Transmit.bundle'] if len(sys.argv)==1 else list(map(Path,sys.argv[1:]))
count=0
for bundle in bundles:
 subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
 for p in bundle.rglob('*'):
  if not p.is_file():continue
  with p.open('rb') as f:magic=f.read(4)
  if magic not in [bytes.fromhex(x) for x in ['cffaedfe','feedfacf','cafebabe','bebafeca']]:continue
  archs=subprocess.check_output(['lipo','-archs',str(p)],text=True).split();assert set(archs)=={'arm64','x86_64'},(p,archs)
  loads=subprocess.check_output(['vtool','-show-build',str(p)],text=True)
  mins=[line.split()[-1] for line in loads.splitlines() if line.strip().startswith('minos ')]
  assert len(mins)==2 and all(tuple(map(int,m.split('.'))) <= (14,4) for m in mins),(p,mins)
  count+=1
 for info in bundle.rglob('Info.plist'):
  p=plistlib.loads(info.read_bytes());minimum=p.get('LSMinimumSystemVersion')
  assert minimum=='14.4',(info,minimum)
  expected={'local.shuttle.camera':'54','local.shuttle.camera.extension':'21','local.shuttle.output.extension':'13','local.shuttle.audio':'4','local.shuttle.premiere.transmit':'2'}
  assert p.get('CFBundleVersion')==expected.get(p.get('CFBundleIdentifier')),(info,p.get('CFBundleVersion'))
print(f'PASS: {count} Mach-O programs contain arm64 and x86_64, minOS <=14.4, matching bundle metadata and deep signatures.')
