"""真实Epoll成功/取消批次；计时含事件调度、系统调用及回调，不是纯收集耗时或网络P99。"""
import argparse
import json
from pathlib import Path
import queue
import re
import socket
import statistics
import subprocess
import threading

def run(exe,mode,n):
    p=subprocess.Popen([str(exe),'socket',mode,str(n)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    messages=queue.Queue();lines=[];peer=None;error='';metric=None
    def collect():
        for raw in p.stdout:
            line=raw.decode(errors='replace').strip();lines.append(line);messages.put(line)
    reader=threading.Thread(target=collect);reader.start()
    def wait(prefix):
        while True:
            value=messages.get(timeout=10)
            if value.startswith('FAIL '):raise AssertionError(value)
            if value.startswith(prefix):return value
    def command(value):p.stdin.write((value+'\n').encode());p.stdin.flush()
    try:
        port=int(wait('PORT ').split()[1]);peer=socket.socket();peer.settimeout(10)
        peer.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1048576);peer.connect(('127.0.0.1',port));wait('CONNECTED')
        peer.sendall(b'Q');wait('QUEUED');cancel=mode.startswith('cancel');command('cancel' if cancel else 'release')
        data=bytearray();expected=n+(mode=='write-reentry')
        if not cancel:
            while len(data)<expected:
                try:part=peer.recv(expected-len(data))
                except ConnectionResetError:part=b''
                if not part:break
                data.extend(part)
            assert data==bytes(i%251 for i in range(len(data))),'批次字节顺序错误'
            if mode!='write-error':assert len(data)==expected,'批次未全部发送'
        else:
            try:assert not peer.recv(1),'取消前已有正文发送'
            except ConnectionResetError:pass
        command('done');line=wait('BENCH ')
        m=re.search(r'total_us=([\d.]+) batches=(\d+) max_batch=(\d+) callbacks=(\d+) disposed=(\d+)',line)
        assert m,line
        metric={'total_us':float(m[1]),'batches':int(m[2]),'max_batch':int(m[3]),'callbacks':int(m[4]),'disposed':int(m[5])}
        command('stop');wait('STOPPED');p.wait(timeout=5);assert p.returncode==0
    except Exception as exc:error=type(exc).__name__+': '+str(exc)
    finally:
        if p.poll() is None:
            try:command('release');command('stop');p.wait(timeout=3)
            except (OSError,subprocess.TimeoutExpired):p.kill();p.wait()
        if peer:peer.close()
        reader.join(timeout=3)
        for pipe in (p.stdin,p.stdout):
            try:pipe.close()
            except OSError:pass
    return {'mode':mode,'n':n,'passed':not error,'error':error,'metric':metric,'output':'\n'.join(lines)}

if __name__=='__main__':
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('executable',type=Path);a.add_argument('--output',type=Path)
    a.add_argument('--samples',type=int,default=5);a.add_argument('--regression-only',action='store_true');o=a.parse_args();rows=[];benches=[]
    for mode in ('write','write-reentry','write-error','cancel','cancel-mixed','cancel-nil','cancel-error','cancel-reentry'):
        row=run(o.executable.resolve(),mode,1000);rows.append(row);print(mode,'PASS' if row['passed'] else row['error'],flush=True)
    if not o.regression_only:
        for mode in ('write','cancel'):
            for n in (1,100,1000,10000):
                samples=[]
                for i in range(o.samples+1):
                    row=run(o.executable.resolve(),mode,n);row['warmup']=i==0;samples.append(row)
                    if not row['passed']:raise RuntimeError(row['error'])
                median=statistics.median(r['metric']['total_us'] for r in samples if not r['warmup'])
                benches.append({'mode':mode,'n':n,'samples':samples,'median_us':median});print(mode,n,median,'us',flush=True)
    if o.output:o.output.write_text(json.dumps({'results':rows,'benchmarks':benches},indent=2),encoding='utf-8')
    raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
