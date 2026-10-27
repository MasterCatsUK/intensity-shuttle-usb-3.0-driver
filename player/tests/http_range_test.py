#!/usr/bin/env python3
"""Read a real MOV through a server that rejects open-ended/oversized ranges."""
import http.server,re,subprocess,sys,threading
from pathlib import Path
media=Path(sys.argv[2]).read_bytes();requests=[];limit=1048576
class Server(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def log_message(self,*args):pass
 def do_GET(self):
  field=self.headers.get('Range','');match=re.fullmatch(r'bytes=(\d+)-(\d+)',field)
  if not match:
   requests.append(('unbounded',));self.send_response(400);self.send_header('Content-Length','0');self.end_headers();return
  start,end=map(int,match.groups());requests.append((start,end))
  if end-start+1>limit or start>=len(media):
   self.send_response(416);self.send_header('Content-Length','0');self.end_headers();return
  end=min(end,len(media)-1);self.send_response(206);self.send_header('Content-Type','video/quicktime');self.send_header('Accept-Ranges','bytes');self.send_header('Content-Range',f'bytes {start}-{end}/{len(media)}');self.send_header('Content-Length',str(end-start+1));self.end_headers()
  try:self.wfile.write(media[start:end+1])
  except (BrokenPipeError,ConnectionResetError):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Server);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
try:
 subprocess.run([sys.argv[1],'-v','error','-request_size',str(limit),'-short_seek_size',str(limit),'-multiple_requests','1','-show_packets','-show_entries','packet=pts_time','-of','csv=p=0',f'http://127.0.0.1:{server.server_port}/fixture.mov'],check=True,stdout=subprocess.DEVNULL,timeout=20)
 assert len(requests)>=2 and all(len(r)==2 and r[1]-r[0]+1<=limit for r in requests),requests
 print(f'PASS: full MOV demux via {len(requests)} bounded HTTP ranges, each ≤1 MiB; no open-ended/oversized request.')
finally:server.shutdown();server.server_close();thread.join()
