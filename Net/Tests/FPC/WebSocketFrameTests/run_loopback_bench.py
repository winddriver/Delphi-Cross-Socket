"""真实回环服务端基线对照；比较收帧、解析、回调和发送的总耗时。"""
from pathlib import Path
from prepare_baseline import prepare
import subprocess,socket,base64,os,struct,time,json,statistics
T=Path(__file__).resolve().parent;R=T.parents[3];B=prepare();D=Path(r'D:\Design\Delphi\D13.1');CN=Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
def exact(s,n):
    out=b''
    while len(out)<n:
        b=s.recv(n-len(out))
        if not b:raise EOFError()
        out+=b
    return out
def readframe(s):
    a,b=exact(s,2);n=b&127
    if n==126:n=struct.unpack('!H',exact(s,2))[0]
    if n==127:n=struct.unpack('!Q',exact(s,8))[0]
    assert not b&128
    return a&15,exact(s,n)
def frame(op,data):
    k=os.urandom(4);n=len(data);h=bytes([0x80|op,0x80|(n if n<126 else 126 if n<65536 else 127)])
    if n>=126:h+=struct.pack('!H' if n<65536 else '!Q',n)
    return h+k+bytes(v^k[i%4] for i,v in enumerate(data))
results={}
for arch in ('win64','win32'):
    for variant,root in (('base',B),('new',R)):
        dest=T/f'bin/loopbench-{arch}-{variant}';dest.mkdir(parents=True,exist_ok=True)
        args=[D/'bin'/('dcc64.exe' if arch=='win64' else 'dcc32.exe'),'-Q','-B','-$O+','-NSSystem;System.Win;Winapi','-U'+';'.join(map(str,(root/'Net',root/'Utils',CN,D/'lib'/arch/'release'))),'-I'+str(root)+';'+str(CN),'-E'+str(dest),'-N0'+str(dest)]
        if variant=='new':args+=['-DWS_NEW_API']
        args+=[T/'WebSocketLoopback.dpr']
        p=subprocess.run(list(map(str,args)),cwd=T,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
        (dest/'build.log').write_bytes(p.stdout+p.stderr)
        if p.returncode:raise RuntimeError((p.stdout+p.stderr).decode(errors='replace')[-3000:])
    samples={v:{} for v in ('base','new')}
    for turn in range(5):
        for variant in (('base','new') if turn%2==0 else ('new','base')):
            exe=T/f'bin/loopbench-{arch}-{variant}/WebSocketLoopback.exe'
            p=subprocess.Popen([str(exe),'server'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                line=p.stdout.readline();assert line.startswith('READY '),line;port=int(line.split()[1])
                with socket.create_connection(('127.0.0.1',port),timeout=5) as s:
                    s.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
                    key=base64.b64encode(os.urandom(16)).decode()
                    s.sendall((f'GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n').encode())
                    h=b''
                    while not h.endswith(b'\r\n\r\n'):h+=exact(s,1)
                    assert b'101' in h
                    for name,op,data,count in [('echo32',2,b'A'*32,3000),('ping0',9,b'',3000),('echo64k',2,b'A'*65536,128)]:
                        frames=[frame(op,data) for _ in range(count)]
                        start=time.perf_counter()
                        for w in frames:
                            s.sendall(w);got=readframe(s);assert got==(10 if op==9 else 2,data)
                        elapsed=(time.perf_counter()-start)*1000
                        samples[variant].setdefault(name,[]).append(elapsed)
                    s.sendall(frame(8,b''));assert readframe(s)==(8,b'')
            finally:
                try:p.communicate('\n',timeout=5)
                except subprocess.TimeoutExpired:p.kill();p.communicate()
                assert p.returncode==0
        print(arch,turn+1,'/5',flush=True)
    results[arch]={k:{'base_ms':statistics.median(a),'new_ms':statistics.median(samples['new'][k]),'time_change_pct':round((statistics.median(samples['new'][k])/statistics.median(a)-1)*100,2),'base_samples':a,'new_samples':samples['new'][k]} for k,a in samples['base'].items()}
    print(json.dumps({arch:results[arch]}),flush=True)
(T/'bin/loopback-benchmark-results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
