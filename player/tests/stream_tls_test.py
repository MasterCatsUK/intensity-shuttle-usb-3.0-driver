#!/usr/bin/env python3
"""Self-contained TLS rejection check. Ephemeral localhost server/certificate."""
import functools,http.server,json,ssl,subprocess,sys,tempfile,threading
from pathlib import Path
with tempfile.TemporaryDirectory(prefix='shuttle-stream-tls-') as folder:
 root=Path(folder)
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-days','1','-nodes','-subj','/CN=localhost'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 requests=[]
 class Handler(http.server.SimpleHTTPRequestHandler):
  def log_message(self,*args): pass
  def do_GET(self):
   requests.append(self.path);super().do_GET()
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=folder))
 context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(root/'cert.pem',root/'key.pem');server.socket=context.wrap_socket(server.socket,server_side=True)
 thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 config=root/'stream.json';config.write_text(json.dumps(dict(version=1,duration=10,inputs=[dict(url=f'https://127.0.0.1:{server.server_port}/movie.mp4')],video=0,audio=-1)))
 try:
  subprocess.run([sys.argv[1],str(config),str(Path(sys.argv[2]).resolve())],check=True,timeout=12)
  assert not requests, "Untrusted server received an HTTP request"
 finally: server.shutdown();server.server_close();thread.join()
