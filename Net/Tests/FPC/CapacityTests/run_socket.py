"""真实Socket发送额度：阻塞工作线程形成确定在途批次，拒绝后恢复及取消。"""
import argparse
import json
from pathlib import Path
import queue
import re
import socket
import subprocess
import sys
import threading

CASES=['socket-count','socket-bytes','socket-direct','socket-nil','socket-reenter',
       'socket-close','socket-stop','socket-default','socket-invalid','socket-oversize',
       'socket-large-limit','socket-concurrent','socket-snapshot-limited','socket-snapshot-unlimited',
       'socket-raise','socket-reject-raise','socket-wrap-failure','socket-sync-failure']

def run(exe,mode,count=10000):
    p=subprocess.Popen([str(exe),mode,str(count)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    messages=queue.Queue();lines=[];peer=None;extra=None;error=''
    def collect():
        for raw in p.stdout:
            try:line=raw.decode('utf-8').strip()
            except UnicodeDecodeError:line=raw.decode('gb18030',errors='replace').strip()
            lines.append(line);messages.put(line)
    reader=threading.Thread(target=collect);reader.start()
    def wait(prefix):
        while True:
            line=messages.get(timeout=10)
            if line.startswith('FAIL '):raise AssertionError(line)
            if line.startswith(prefix):return line
    def command(value):p.stdin.write((value+'\n').encode());p.stdin.flush()
    def read(count):
        data=bytearray()
        while len(data)<count:
            part=peer.recv(count-len(data))
            if not part:raise AssertionError('已接纳数据未完整发送')
            data.extend(part)
        return bytes(data)
    try:
        port=int(wait('PORT ').split()[1]);peer=socket.socket();peer.settimeout(10)
        if mode.startswith('socket-partial'):peer.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,32768)
        peer.connect(('127.0.0.1',port));wait('CONNECTED')
        if mode=='socket-snapshot-unlimited':
            extra=socket.create_connection(('127.0.0.1',port),timeout=10);wait('CONNECTED EXTRA')
        peer.sendall(b'Q');wait('BLOCKED Q')
        command('queue');size=int(wait('QUEUED ').split()[1])
        if mode in ('socket-close','socket-stop','socket-raise','socket-partial-close','socket-sync-failure'):
            if mode=='socket-partial-close':command('release');command('probe');wait('PARTIAL')
            if mode not in ('socket-raise','socket-sync-failure'):command('stop-pending' if mode=='socket-stop' else 'close');wait('CLOSING')
            command('release')
            while True:
                try:data=peer.recv(4096)
                except ConnectionResetError:break
                if not data:break
            command('done');wait('DONE')
        else:
            command('release')
            if mode=='socket-partial':command('probe');wait('PARTIAL')
            if mode.startswith('socket-bench'):expected=b'*'*count
            elif mode in ('socket-default','socket-snapshot-unlimited'):expected=b''.join(bytes([i])*10 for i in range(32))
            elif mode=='socket-bytes':expected=b'\0'*12+b'\1'*8
            elif mode=='socket-large-limit':expected=b'\0'*21+b'\1'
            elif mode=='socket-partial':expected=b'\0'*(1024*1024)+b'\1'*(1024*1024)
            else:expected=b'\0'*10+b'\1'*10
            received=read(size)
            if mode=='socket-concurrent':
                accepted=next(line.removeprefix('ACCEPTED ') for line in lines if line.startswith('ACCEPTED '))
                assert len(set(received))==8 and set(received)=={int(x) for x in accepted.split(',') if x},'并发数据不匹配接纳项'
            else:assert received==expected,'实际数据乱序或包含拒绝项'
            command('first');wait('FIRST')
            if mode not in ('socket-default','socket-snapshot-unlimited') and not mode.startswith('socket-bench'):
                peer.sendall(b'R');wait('BLOCKED R');command('after');wait('AFTER');command('release')
                expected=bytes(range(64,72)) if mode=='socket-concurrent' else b'\3'*10+(b'' if mode=='socket-reenter' else b'\4'*10)
                assert read(len(expected))==expected,'额度释放后数据错误'
            command('done');wait('DONE')
        command('quit');wait('STOPPED');p.wait(timeout=5);assert p.returncode==0
    except Exception as exc:error=type(exc).__name__+': '+str(exc)
    finally:
        if p.poll() is None:
            try:command('release');command('quit');p.wait(timeout=3)
            except (OSError,subprocess.TimeoutExpired):p.kill();p.wait()
        if peer:peer.close()
        if extra:extra.close()
        reader.join(timeout=3)
        for pipe in (p.stdin,p.stdout):
            try:pipe.close()
            except OSError:pass
    output='\n'.join(lines);metric=None
    match=re.search(r'METRIC n=(\d+) enqueue_us=([\d.]+) alloc_calls=(\d+) requested_bytes=(\d+)',output)
    if match:metric=dict(zip(('n','enqueue_us','alloc_calls','requested_bytes'),(int(match[1]),float(match[2]),int(match[3]),int(match[4]))))
    return {'case':mode,'passed':not error,'error':error,'metric':metric,'output':output}

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('executable',type=Path)
    ap.add_argument('--output',type=Path);ap.add_argument('--cases',nargs='+',default=CASES)
    o=ap.parse_args();rows=[]
    for mode in o.cases:
        row=run(o.executable.resolve(),mode);rows.append(row)
        print(mode,'PASS' if row['passed'] else row['error'],flush=True)
        if o.output:o.output.write_text(json.dumps(rows,indent=2),encoding='utf-8')
    raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
