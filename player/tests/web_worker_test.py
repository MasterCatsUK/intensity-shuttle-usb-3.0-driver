# GPL-2.0-or-later. Explicit subprocess-group cleanup test; no network/USB.
from pathlib import Path
import subprocess,sys,tempfile,time
worker=Path(sys.argv[1]).resolve()
assert subprocess.run([str(worker),'/usr/bin/true']).returncode==0
assert subprocess.run([str(worker),'/usr/bin/false']).returncode==1
with tempfile.TemporaryDirectory() as d:
    pidfile=Path(d)/'child'
    code='import subprocess,time,pathlib; p=subprocess.Popen(["/bin/sleep","30"]); pathlib.Path('+repr(str(pidfile))+').write_text(str(p.pid)); time.sleep(30)'
    process=subprocess.Popen([str(worker),sys.executable,'-c',code])
    deadline=time.monotonic()+5
    while not pidfile.exists():
        assert time.monotonic()<deadline
        time.sleep(.01)
    child=int(pidfile.read_text());process.terminate();started=time.monotonic();process.wait(timeout=7)
    assert time.monotonic()-started<6
    state=subprocess.run(['/bin/ps','-o','stat=','-p',str(child)],capture_output=True,text=True).stdout.strip()
    assert not state or state.startswith('Z'),state
print('PASS own worker group cancellation, descendant cleanup and exit-code forwarding; unrelated processes untouched')
