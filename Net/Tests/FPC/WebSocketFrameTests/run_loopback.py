"""使用真实回环 TCP 检查标准端点；仅使用 Python 标准库。"""
import base64, hashlib, os, socket, struct, subprocess, sys, threading, queue
from pathlib import Path
EXE=Path(sys.argv[1]).resolve()
MAGIC='258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

def launch(*args):
    return subprocess.Popen([str(EXE),*args],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))

def read_ready(p):
    q=queue.Queue()
    threading.Thread(target=lambda:q.put(p.stdout.readline()),daemon=True).start()
    line=q.get(timeout=8)
    assert line.startswith('READY '),line
    return int(line.split()[1])

def exact(s,n):
    result=b''
    while len(result)<n:
        data=s.recv(n-len(result))
        if not data: raise EOFError('peer closed')
        result+=data
    return result

def frame(op,data=b'',fin=True,masked=True):
    h=bytes([op|(0x80 if fin else 0)])
    n=len(data)
    h+=bytes([(0x80 if masked else 0)|(n if n<126 else 126 if n<65536 else 127)])
    if n>=126:h+=struct.pack('!H' if n<65536 else '!Q',n)
    if masked:
        key=os.urandom(4);h+=key;data=bytes(v^key[i%4] for i,v in enumerate(data))
    return h+data

def recv_frame(s):
    a,b=exact(s,2);n=b&127
    if n==126:n=struct.unpack('!H',exact(s,2))[0]
    elif n==127:n=struct.unpack('!Q',exact(s,8))[0]
    assert n<=2*1024*1024
    key=exact(s,4) if b&128 else None
    data=exact(s,n)
    if key:data=bytes(v^key[i%4] for i,v in enumerate(data))
    return a&15,data,key is not None

def headers(s):
    data=b''
    while not data.endswith(b'\r\n\r\n'):
        data+=exact(s,1)
        assert len(data)<16384
    return data

def connect(port):
    s=socket.create_connection(('127.0.0.1',port),timeout=3)
    key=base64.b64encode(os.urandom(16)).decode()
    s.sendall((f'GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n').encode())
    assert b'101' in headers(s)
    return s

p=launch('server')
try:
    port=read_ready(p)
    with connect(port) as s:
        s.sendall(frame(1,b'A',False)+frame(9,b'x')+frame(0,b'B'))
        assert recv_frame(s)==(10,b'x',False)
        assert recv_frame(s)==(2,b'AB',False)
        s.sendall(frame(8)+frame(1,b'forbidden'))
        assert recv_frame(s)==(8,b'',False)
        assert s.recv(1)==b''
    bad=[(frame(1,b'A',masked=False),1002),(frame(1,b'\xc0\x80'),1007),(frame(9,b'x',False),1002),(frame(0,b'A'),1002),(frame(8,b'\x03\xed'),1002),(frame(1,b'A',False)+frame(2,b'B'),1002)]
    for data,code in bad:
        with connect(port) as s:
            s.sendall(data);op,payload,mask=recv_frame(s)
            assert (op,mask,struct.unpack('!H',payload[:2])[0])==(8,False,code)
            assert s.recv(1)==b''
    # 只发超限帧头，不发送正文，验证分配前拒绝。
    with connect(port) as s:
        s.sendall(bytes([0x82,0xff])+struct.pack('!Q',2*1024*1024)+b'abcd')
        op,data,mask=recv_frame(s);assert op==8 and data[:2]==struct.pack('!H',1009)
    print('Native server loopback: 8 scenarios passed')
finally:
    try:p.communicate('\n',timeout=5)
    except subprocess.TimeoutExpired:p.kill();p.communicate()
    assert p.returncode==0,p.returncode

for mode in ('peer','local','invalid'):
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(5)
        p=launch('client',f'ws://127.0.0.1:{listener.getsockname()[1]}/ws',mode)
        try:
            s,_=listener.accept();s.settimeout(3)
            with s:
                request=headers(s).decode();key=next(x.split(':',1)[1].strip() for x in request.split('\r\n') if x.lower().startswith('sec-websocket-key:'))
                accept=base64.b64encode(hashlib.sha1((key+MAGIC).encode()).digest()).decode()
                s.sendall((f'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n').encode())
                assert recv_frame(s)==(1,b'request',True)
                if mode=='invalid':
                    s.sendall(frame(1,b'bad',masked=True));op,data,masked=recv_frame(s)
                    assert (op,masked,data[:2])==(8,True,struct.pack('!H',1002))
                else:
                    s.sendall(frame(1,b'A',False,False)+frame(9,b'x',masked=False)+frame(0,b'B',masked=False))
                    assert recv_frame(s)==(10,b'x',True)
                    if mode=='peer':s.sendall(frame(8,masked=False)+frame(1,b'forbidden',masked=False))
                    assert recv_frame(s)==(8,b'',True)
                    if mode=='local':s.sendall(frame(8,masked=False))
            output,_=p.communicate(timeout=8)
            assert p.returncode==0,output
            assert output.count('MESSAGE AB')==(0 if mode=='invalid' else 1),output
            assert 'forbidden' not in output,output
        finally:
            if p.poll() is None:p.kill();p.communicate()
print('Native client loopback: 3 scenarios passed')
