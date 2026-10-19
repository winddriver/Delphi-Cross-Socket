"""真实 TCP 超时快照重验：在收集和处理之间改变同一连接的活动/请求状态。"""
import argparse
import json
from pathlib import Path
import queue
import socket
import subprocess
import sys
import threading

CASES=('idle-reuse','request-progress','request-reuse','idle-reserved','idle-expire','request-expire')

def run(exe,mode):
    server=socket.socket();server.bind(('127.0.0.1',0));server.listen();server.settimeout(8)
    url='http://127.0.0.1:'+str(server.getsockname()[1])
    p=subprocess.Popen([str(exe),'client',mode,url],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    lines=[];messages=queue.Queue();peers=[];error=''
    def collect():
        for raw in p.stdout:
            try:line=raw.decode('utf-8').strip()
            except UnicodeDecodeError:line=raw.decode('gb18030',errors='replace').strip()
            lines.append(line);messages.put(line)
    reader=threading.Thread(target=collect);reader.start()
    def wait(prefix):
        while True:
            value=messages.get(timeout=8)
            if value.startswith('FAIL '):raise AssertionError(value)
            if value.startswith(prefix):return value
    def accept():
        c,_=server.accept();c.settimeout(8);peers.append(c);return c
    def request(c,path):
        data=bytearray()
        while not data.endswith(b'\r\n\r\n'):
            part=c.recv(1)
            if not part:raise AssertionError('请求发送前连接已关闭')
            data.extend(part)
        assert data.startswith(b'GET '+path.encode()+b' '),data
    def reply(c,body=b'ok'):
        c.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body)
    def closed(c):
        try:return c.recv(1)==b''
        except ConnectionResetError:return True
    try:
        c=accept();request(c,'/first')
        if mode.startswith('request-'):c.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\na')
        else:reply(c)
        if mode=='request-expire':
            assert closed(c),'超时后实际TCP未关闭'
        elif mode=='idle-expire':
            assert closed(c),'过期空闲连接未关闭'
            c=accept();request(c,'/second');reply(c)
        elif mode=='idle-reserved':
            wait('SCANNED');request(c,'/second');reply(c)
        else:
            wait('COLLECTED')
            if mode=='request-progress':
                wait('CHANGE');c.sendall(b'b');p.stdin.write(b'changed\n');p.stdin.flush()
                wait('SCANNED');c.sendall(b'cd')
            else:
                if mode=='request-reuse':wait('CHANGE');c.sendall(b'bcd')
                request(c,'/second');wait('SECOND');wait('SCANNED');reply(c)
        wait('PASS ');p.wait(timeout=5);assert p.returncode==0
    except Exception as exc:error=type(exc).__name__+': '+str(exc)
    finally:
        for c in peers:c.close()
        server.close()
        if p.poll() is None:
            try:p.wait(timeout=2)
            except subprocess.TimeoutExpired:p.kill();p.wait()
        reader.join(timeout=3)
        for pipe in (p.stdin,p.stdout):
            try:pipe.close()
            except OSError:pass
    return {'case':mode,'passed':not error,'error':error,'output':'\n'.join(lines)}

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('executable',type=Path)
    ap.add_argument('--output',type=Path);ap.add_argument('--cases',nargs='*',choices=CASES)
    o=ap.parse_args();rows=[]
    for mode in o.cases or CASES:
        row=run(o.executable.resolve(),mode);rows.append(row)
        print(mode,'PASS' if row['passed'] else row['error'],flush=True)
        if o.output:o.output.write_text(json.dumps(rows,indent=2),encoding='utf-8')
    raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
