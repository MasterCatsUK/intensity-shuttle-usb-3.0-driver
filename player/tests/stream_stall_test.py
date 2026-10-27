#!/usr/bin/env python3
"""Run a controlled fake decoder inside the real isolated worker/stream buffer."""
import os, sys, tempfile, shutil, subprocess
from pathlib import Path
with tempfile.TemporaryDirectory(prefix='shuttle-stream-producer-') as directory:
    root=Path(directory);(root/'WebTools').mkdir()
    shutil.copy2(sys.argv[1],root/'ShuttleWebWorker')
    ffmpeg=root/'WebTools'/'ffmpeg'
    ffmpeg.write_text(f'#!{sys.executable}\n'+r'''
import os,sys,threading,time,struct
if os.environ.get('SHUTTLE_STREAM_FAKE_FAIL'): sys.exit(2)
video=next(a for a in sys.argv if a.endswith('/video.pipe'))
audio=next(a for a in sys.argv if a.endswith('/audio.pipe'))
short_audio=bool(os.environ.get("SHUTTLE_STREAM_SHORT_AUDIO"))
gate=threading.Barrier(2)
def write_video():
 with open(video,'wb',buffering=0) as out:
  for n in range(180):
   if n==80 and not short_audio: gate.wait();time.sleep(5)
   out.write(bytes([128,16+n%180,128,16+n%180])*(720*576//2))
def write_audio():
 with open(audio,'wb',buffering=0) as out:
  for n in range(60 if short_audio else 180):
   if n==80 and not short_audio: gate.wait();time.sleep(5)
   out.write(struct.pack('<ii',268435456,-268435456)*1920)
a=threading.Thread(target=write_video);b=threading.Thread(target=write_audio)
a.start();b.start();a.join();b.join()
''')
    ffmpeg.chmod(0o700)
    subprocess.run([sys.argv[2],str(root)],check=True,timeout=35)
