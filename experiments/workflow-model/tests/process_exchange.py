import subprocess,threading,queue,socket,tempfile,pathlib,time,json,sys
if len(sys.argv)!=2: raise SystemExit('Usage: python3 process_exchange.py /absolute/path/rescue-exchange-host')
exe=sys.argv[1]
folder=pathlib.Path(tempfile.mkdtemp(prefix='rescue-process-',dir='/private/tmp'))
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
ports=[port(),port()];processes=[];evidence=[]
def start(role):
 p=subprocess.Popen([exe,str(role),str(folder/f'{role}.sqlite'),str(ports[role])],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
 q=queue.Queue();threading.Thread(target=lambda:[q.put(l.strip()) for l in p.stdout],daemon=True).start();processes.append(p)
 wait(q,lambda l:l.startswith('READY'))
 return p,q
def wait(q,predicate):
 deadline=time.monotonic()+12
 while time.monotonic()<deadline:
  try:l=q.get(timeout=.2)
  except queue.Empty:continue
  evidence.append(l)
  if predicate(l):return l
 raise AssertionError('Timed out: '+str(evidence[-15:]))
def cmd(p,q,c,condition):
 p.stdin.write(c+'\n');p.stdin.flush();return wait(q,lambda l:l.startswith('STATE ') and condition(l))
try:
 p,pq=start(0);r,rq=start(1)
 cmd(p,pq,'sos',lambda l:'pending=1' in l and 'delivery=0' in l)
 cmd(r,rq,'state',lambda l:'request=false' in l)
 cmd(p,pq,f'send {ports[1]}',lambda l:'pending=0' in l and 'delivery=1' in l)
 wait(rq,lambda l:l.startswith('INBOUND SAVED') and 'request=true' in l)
 cmd(r,rq,'ack',lambda l:'pending=1' in l)
 cmd(r,rq,'reply',lambda l:'pending=2' in l)
 cmd(r,rq,f'send {ports[0]}',lambda l:'pending=0' in l)
 cmd(p,pq,'state',lambda l:'delivery=2' in l and 'messages=3' in l)
 cmd(p,pq,'correction',lambda l:'pending=1' in l and 'Floor 4' in l)
 cmd(p,pq,f'send {ports[1]}',lambda l:'pending=0' in l)
 cmd(r,rq,'state',lambda l:'Floor 4' in l)
 cmd(p,pq,'sos',lambda l:'pending=0' in l) # second SOS rejects without altering the saved request
 # Queue a correction with peer unavailable, then kill and restart this process.
 cmd(p,pq,'correction',lambda l:'pending=1' in l)
 unused=port();cmd(p,pq,f'send {unused}',lambda l:'pending=1' in l)
 p.kill();p.wait(timeout=5)
 p,pq=start(0)
 cmd(p,pq,'state',lambda l:'pending=1' in l and 'delivery=2' in l)
 cmd(p,pq,f'send {ports[1]}',lambda l:'pending=0' in l)
 print('PASS: independent-process SOS, explicit acknowledgment/reply, correction, refused connection and killed-process outbox recovery')
 print('Evidence directory:',folder)
 (folder/'evidence.json').write_text(json.dumps(evidence,indent=2))
 print('\n'.join(evidence[-14:]))
finally:
 for p in processes:
  if p.poll() is None:p.terminate()
 for p in processes:
  try:p.wait(timeout=3)
  except subprocess.TimeoutExpired:p.kill()
