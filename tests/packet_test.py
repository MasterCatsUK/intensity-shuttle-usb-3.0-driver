"""Fixture and live USB tests. Run with --usb only while PAL S-Video is playing."""
from pathlib import Path
import argparse
import struct
import subprocess
import threading

parser=argparse.ArgumentParser()
parser.add_argument('--usb',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
helper=root/'build/bin/shuttle-bridge'
header=struct.Struct('<8I2Q')
tests=[('fixture',['--fixture','--seconds','1'])]
if args.usb: tests.append(('USB S-Video',['--seconds','3']))
for name,options in tests:
    with (root/'build'/('usb-test.log' if name!='fixture' else 'fixture-test.log')).open('wb') as log:
        proc=subprocess.Popen([str(helper),*options],stdout=subprocess.PIPE,stderr=log)
        timer=threading.Timer(15,proc.kill)
        timer.start()
        count=0;previous=None;gaps=0;first=None;last=None
        def read_exact(n):
            chunks=[]
            while n:
                chunk=proc.stdout.read(n)
                if not chunk: break
                chunks.append(chunk);n-=len(chunk)
            return b''.join(chunks)
        try:
            while True:
                data=read_exact(header.size)
                if not data:break
                assert len(data)==header.size,'Truncated header'
                magic,version,size,w,h,stride,field,_,ns,seq=header.unpack(data)
                assert (magic,version,size,w,h,stride)==(0x31564853,1,829440,720,576,1440)
                pixels=read_exact(size)
                assert len(pixels)==size,'Truncated image'
                if name=='fixture':
                    assert field==count%2
                    assert all(x==128 for x in pixels[0::2])
                    assert all(x==(180 if field else 50) for x in pixels[1::2])
                if previous is not None:
                    assert ns>previous[0],'Nonmonotonic host time'
                    if seq==previous[1]+1 and name!='fixture':
                        assert ns-previous[0]==20000000,('Unexpected frame cadence',ns-previous[0])
                    if seq!=previous[1]+1:gaps+=1
                previous=(ns,seq);first=ns if first is None else first;last=ns;count+=1
            rc=proc.wait(timeout=5)
            assert rc==0,(name,rc)
            assert count==50 if name=='fixture' else count>=25,'No sustained PAL input'
            print(f'{name}: PASS; {count} complete 720x576 packets; sequence gaps={gaps}; span={(last-first)/1e9:.3f}s')
        finally:
            timer.cancel()
            if proc.poll() is None:proc.kill();proc.wait()
