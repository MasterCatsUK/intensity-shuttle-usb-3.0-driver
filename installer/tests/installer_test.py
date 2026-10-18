"""Exercise the shipped shell scripts on a temporary filesystem, never the Mac."""
from pathlib import Path
import json,os,plistlib,re,shlex,subprocess,sys,tempfile,unittest
SOURCE=Path(__file__).resolve().parents[1]
MOCK='''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
root=Path(os.environ['SHUTTLE_TEST_CASE_DIR']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps([name,*args])+'\\n')
if name=='id':print(0)
elif name=='sysctl':print(1)
elif name=='sw_vers':print('27.0.1')
elif name=='csrutil':print('System Integrity Protection status: '+('enabled.' if (root/'sip-enabled').exists() else 'disabled.'))
elif name=='stat':
 if args[-1]=='/dev/console':print(501)
 elif args[1]=='%u':print(0)
 else:print(oct(Path(args[-1]).stat().st_mode & 0o777)[2:])
elif name=='pgrep':
 marker={'ShuttleCamera':'settings-open','ShuttleOutput':'output-open','ShuttlePlayback':'playback-active','Final Cut Pro':'finalcut-open','/Adobe Premiere Pro[^/]*\\.app/Contents/MacOS/Adobe Premiere Pro':'premiere-open'}.get(args[-1],'none')
 sys.exit(0 if (root/marker).exists() else 1)
elif name=='ps':
 print('/Applications/Adobe Premiere Pro 2025.app/Contents/MacOS/Adobe Premiere Pro 2025' if (root/'premiere-open').exists() else '/Library/Application Support/Adobe/Adobe Desktop Common/IPCBox/AdobeIPCBroker.app/Contents/MacOS/AdobeIPCBroker')
elif name=='check-capture':sys.exit(int((root/'capture-status').read_text()))
elif name=='launchctl':
 if args[0]=='asuser':sys.exit(subprocess.run(args[2:]).returncode)
elif name=='sudo':sys.exit(subprocess.run(args[2:]).returncode)
'''
class InstallerTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='Shuttle installer test ');self.root=Path(self.temp.name);self.fs=self.root/'filesystem';self.scripts=self.root/'scripts';self.bin=self.root/'mock commands';self.bin.mkdir();self.scripts.mkdir()
  self.output=self.fs/'Applications/Shuttle Output.app';self.app=self.fs/'Applications/Shuttle Camera.app';self.audio=self.fs/'Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver';self.support=self.fs/'Library/Application Support/Shuttle Camera';self.premiere=self.fs/'Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle'
  (self.root/'capture-status').write_text('0');self.env=dict(os.environ,SHUTTLE_TEST_CASE_DIR=str(self.root))
  commands=['id','sysctl','sw_vers','csrutil','stat','pgrep','ps','launchctl','sudo','codesign','chown','open']
  for name in [*commands,'check-capture']:
   p=(self.scripts if name=='check-capture' else self.bin)/name;p.write_text(MOCK);p.chmod(0o755)
  for name in ['preinstall','postinstall']:
   s=(SOURCE/'scripts'/name).read_text()
   s=re.sub(r"'(/(?:Applications|Library)[^']*)'",lambda m:shlex.quote(str(self.fs)+m[1]),s)
   s=re.sub(r'(?<= )/(Applications|Library)(?= )',lambda m:shlex.quote(str(self.fs)+'/'+m[1]),s)
   for name2 in commands:
    for prefix in ['/usr/bin/','/usr/sbin/','/bin/']:
     s=s.replace(prefix+name2,shlex.quote(str(self.bin/name2)))
   (self.scripts/name).write_text(s)
 def tearDown(self):self.temp.cleanup()
 def bundle(self,path,identifier,version,body):
  (path/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
  (path/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'CFBundleVersion':str(version)}))
  (path/'Contents/MacOS/program').write_text(body)
 def payload(self):
  self.bundle(self.app,'local.shuttle.camera',39,'new camera');self.bundle(self.audio,'local.shuttle.audio',3,'new audio');self.bundle(self.premiere,'local.shuttle.premiere.transmit',1,'new plugin')
 def run_script(self,name,*args):
  return subprocess.run(['/bin/bash',str(self.scripts/name),*args],env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 def pre(self):return self.run_script('preinstall','package.pkg','/','/')
 def post(self):return self.run_script('postinstall','package.pkg','/','/')
 def calls(self):
  p=self.root/'calls.jsonl';return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
 def restarts(self):return [x for x in self.calls() if x[:2]==['launchctl','kickstart']]
 def test_fresh_install_and_audio_refresh(self):
  self.assertEqual(self.pre().returncode,0);self.payload();r=self.post();self.assertEqual(r.returncode,0,r.stdout);self.assertEqual(len(self.restarts()),1);self.assertTrue((self.support/'Installation Status.txt').exists())
 def test_identical_reinstall_preserves_backup_and_avoids_audio_restart(self):
  self.payload();self.assertEqual(self.pre().returncode,0);backup=Path((self.support/'Install State/pending-backup').read_text().strip());self.assertEqual((backup/'Shuttle Camera.app/Contents/MacOS/program').read_text(),'new camera');r=self.post();self.assertEqual(r.returncode,0,r.stdout);self.assertEqual(self.restarts(),[])
 def test_upgrade_from_19_preserves_unchanged_hal_and_backup(self):
  self.bundle(self.app,'local.shuttle.camera',19,'previous camera');self.bundle(self.audio,'local.shuttle.audio',3,'new audio')
  self.assertEqual(self.pre().returncode,0);backup=Path((self.support/'Install State/pending-backup').read_text().strip())
  self.payload();r=self.post();self.assertEqual(r.returncode,0,r.stdout)
  self.assertEqual((backup/'Shuttle Camera.app/Contents/MacOS/program').read_text(),'previous camera');self.assertEqual(self.restarts(),[])
 def test_upgrade_from_20_preserves_unchanged_hal_and_backup(self):
  self.bundle(self.app,'local.shuttle.camera',20,'previous camera20');self.bundle(self.audio,'local.shuttle.audio',3,'new audio')
  self.assertEqual(self.pre().returncode,0);backup=Path((self.support/'Install State/pending-backup').read_text().strip())
  self.payload();r=self.post();self.assertEqual(r.returncode,0,r.stdout)
  self.assertEqual((backup/'Shuttle Camera.app/Contents/MacOS/program').read_text(),'previous camera20');self.assertEqual(self.restarts(),[])
 def test_upgrade_from_21_preserves_unchanged_hal_and_backup(self):
  self.bundle(self.app,'local.shuttle.camera',21,'previous camera21');self.bundle(self.audio,'local.shuttle.audio',3,'new audio')
  self.assertEqual(self.pre().returncode,0);backup=Path((self.support/'Install State/pending-backup').read_text().strip())
  self.payload();r=self.post();self.assertEqual(r.returncode,0,r.stdout)
  self.assertEqual((backup/'Shuttle Camera.app/Contents/MacOS/program').read_text(),'previous camera21');self.assertEqual(self.restarts(),[])
 def test_changed_audio_is_backed_up_then_restarted(self):
  self.bundle(self.audio,'local.shuttle.audio',2,'old audio');self.assertEqual(self.pre().returncode,0);backup=Path((self.support/'Install State/pending-backup').read_text().strip());self.payload();r=self.post();self.assertEqual(r.returncode,0,r.stdout);self.assertEqual((backup/'Shuttle Audio.driver/Contents/MacOS/program').read_text(),'old audio');self.assertEqual(len(self.restarts()),1)
 def test_active_capture_rejected_without_writes(self):
  (self.root/'capture-status').write_text('10');r=self.pre();self.assertNotEqual(r.returncode,0);self.assertIn('Capture is running',r.stdout);self.assertFalse(self.support.exists());self.assertEqual(self.restarts(),[])
 def test_unknown_capture_state_rejected(self):
  (self.root/'capture-status').write_text('11');self.assertNotEqual(self.pre().returncode,0);self.assertFalse(self.support.exists())
 def test_sip_enabled_rejected_without_changes(self):
  (self.root/'sip-enabled').touch();r=self.pre();self.assertNotEqual(r.returncode,0);self.assertIn('does not change SIP',r.stdout);self.assertFalse(self.support.exists())
 def test_newer_bundle_and_unrelated_bundle_rejected(self):
  for ident,version in [('local.shuttle.camera',40),('other.application',16)]:
   self.bundle(self.app,ident,version,'preserved');self.assertNotEqual(self.pre().returncode,0);self.assertEqual((self.app/'Contents/MacOS/program').read_text(),'preserved');self.assertFalse(self.support.exists())
 def test_newer_audio_rejected_without_writes(self):
  self.bundle(self.audio,'local.shuttle.audio',4,'future audio');r=self.pre();self.assertNotEqual(r.returncode,0,r.stdout);self.assertEqual((self.audio/'Contents/MacOS/program').read_text(),'future audio');self.assertFalse(self.support.exists());self.assertEqual(self.restarts(),[])
 def test_builder_requires_exact_nested_payload_versions(self):
  self.payload();(self.app/'Contents/MacOS/ShuttleDisplay').write_text('mock display helper');extensions=self.app/'Contents/Library/SystemExtensions'
  camera=extensions/'local.shuttle.camera.extension.systemextension';output=extensions/'local.shuttle.output.extension.systemextension'
  self.bundle(camera,'local.shuttle.camera.extension',17,'camera');self.bundle(output,'local.shuttle.output.extension',12,'output')
  build=(SOURCE/'build.sh').read_text();guard=re.search(r'python3 - "\$app" "\$audio" <<\x27PY\x27\n(.*?)\nPY',build,re.S).group(1)
  def check():return subprocess.run([sys.executable,'-',str(self.app),str(self.audio)],input=guard,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  r=check();self.assertEqual(r.returncode,0,r.stdout)
  for path,identifier,version,correct in [(self.app,'local.shuttle.camera',38,39),(output,'local.shuttle.output.extension',11,12),(camera,'local.shuttle.camera.extension',16,17),(self.audio,'local.shuttle.audio',2,3)]:
   with self.subTest(bundle=identifier,version=version):
    self.bundle(path,identifier,version,'wrong version');self.assertNotEqual(check().returncode,0);self.bundle(path,identifier,correct,'correct version')
  (self.app/'Contents/MacOS/ShuttleDisplay').unlink();self.assertNotEqual(check().returncode,0)
 def test_symlink_rejected(self):
  self.app.parent.mkdir(parents=True);self.app.symlink_to(self.root,target_is_directory=True);self.assertNotEqual(self.pre().returncode,0);self.assertFalse(self.support.exists())
 def test_capture_started_during_install_skips_coreaudio_restart(self):
  self.assertEqual(self.pre().returncode,0);self.payload();(self.root/'capture-status').write_text('10');r=self.post();self.assertEqual(r.returncode,0,r.stdout);self.assertEqual(self.restarts(),[]);self.assertIn('Core Audio was not restarted',(self.support/'Installation Status.txt').read_text())
 def test_final_cut_must_be_closed(self):
  (self.root/'finalcut-open').touch();r=self.pre();self.assertNotEqual(r.returncode,0);self.assertIn('Quit Final Cut Pro',r.stdout);self.assertFalse(self.support.exists())
 def test_premiere_must_be_closed(self):
  (self.root/'premiere-open').touch();r=self.pre();self.assertNotEqual(r.returncode,0);self.assertIn('Quit Adobe Premiere Pro',r.stdout);self.assertFalse(self.support.exists())
 def test_premiere_newer_or_unrelated_bundle_rejected(self):
  for ident,version in [('local.shuttle.premiere.transmit',2),('other.plugin',1)]:
   self.bundle(self.premiere,ident,version,'preserved');self.assertNotEqual(self.pre().returncode,0);self.assertFalse(self.support.exists())
 def test_settings_app_must_be_closed(self):
  (self.root/'settings-open').touch();r=self.pre();self.assertNotEqual(r.returncode,0);self.assertIn('Quit the Shuttle Camera',r.stdout);self.assertFalse(self.support.exists())
 def test_output_app_and_playback_must_be_closed(self):
  for marker in ['output-open','playback-active']:
   with self.subTest(marker=marker):
    (self.root/marker).touch();r=self.pre();self.assertNotEqual(r.returncode,0,r.stdout);self.assertIn('quit Shuttle Output',r.stdout);self.assertFalse(self.support.exists());(self.root/marker).unlink()
 def test_output_bundle_is_validated_and_backed_up(self):
  self.bundle(self.output,'local.shuttle.output',2,'newer output');self.assertNotEqual(self.pre().returncode,0)
  self.bundle(self.output,'other.product',1,'unrelated output');self.assertNotEqual(self.pre().returncode,0)
  self.bundle(self.output,'local.shuttle.output',1,'working output');self.assertEqual(self.pre().returncode,0)
  backup=Path((self.support/'Install State/pending-backup').read_text().strip());self.assertEqual((backup/'Shuttle Output.app/Contents/MacOS/program').read_text(),'working output')
 def test_unified_install_retires_old_output_app_after_verification(self):
  self.bundle(self.output,'local.shuttle.output',1,'working output');self.assertEqual(self.pre().returncode,0)
  backup=Path((self.support/'Install State/pending-backup').read_text().strip());self.payload();r=self.post();self.assertEqual(r.returncode,0,r.stdout)
  self.assertFalse(self.output.exists());self.assertEqual((backup/'Retired Shuttle Output.app/Contents/MacOS/program').read_text(),'working output')
if __name__=='__main__':unittest.main(verbosity=2)
