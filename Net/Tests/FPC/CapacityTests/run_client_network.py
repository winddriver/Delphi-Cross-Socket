"""真实TCP客户端容量、取消和析构回调回归。"""
import argparse
import json
from pathlib import Path
import queue
import socket
import subprocess
import sys
import threading

CASES=['client-tcp-count','client-tcp-nil','client-tcp-raise','client-tcp-cancel',
       'client-tcp-stop','client-tcp-stop-reenter','client-race-pop','client-race-push','client-race-register']

def run_gap(exe,mode):
    listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen()
    try:
        try:
            r=subprocess.run([str(exe),mode,str(listener.getsockname()[1])],capture_output=True,timeout=10)
            output=(r.stdout+r.stderr).decode(errors='replace')
            return {'case':mode,'passed':r.returncode==0,'error':'' if r.returncode==0 else output.strip(),'output':output}
        except subprocess.TimeoutExpired as exc:
            return {'case':mode,'passed':False,'error':'停止超时','output':str(exc)}
    finally:listener.close()

def run_race(exe,mode):
    listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(.1)
    stop=threading.Event();paths=[];peers=[]
    def serve():
        while not stop.is_set():
            try:peer,_=listener.accept()
            except socket.timeout:continue
            except OSError:return
            peers.append(peer);peer.settimeout(.1);data=bytearray()
            try:
                while not stop.is_set():
                    try:part=peer.recv(4096)
                    except socket.timeout:continue
                    if not part:break
                    data.extend(part)
                    while b'\r\n\r\n' in data:
                        raw,_,rest=data.partition(b'\r\n\r\n');data=bytearray(rest)
                        path=raw.split(b' ')[1].decode();paths.append(path)
                        if mode!='client-race-push' or path!='/0':
                            peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n')
            except OSError:pass
            finally:peer.close()
    worker=threading.Thread(target=serve);worker.start()
    try:
        try:
            r=subprocess.run([str(exe),mode,'http://127.0.0.1:'+str(listener.getsockname()[1])],
                             capture_output=True,timeout=15)
            try:output=(r.stdout+r.stderr).decode('utf-8')
            except UnicodeDecodeError:output=(r.stdout+r.stderr).decode('gb18030',errors='replace')
            passed=r.returncode==0 and '/1' not in paths
            return {'case':mode,'passed':passed,'error':'' if passed else '内部接纳竞态失败',
                    'output':output,'requests':paths}
        except subprocess.TimeoutExpired as exc:
            return {'case':mode,'passed':False,'error':'停止超时','output':str(exc),'requests':paths}
    finally:
        stop.set();listener.close()
        for peer in peers:peer.close()
        worker.join(timeout=2)

def run(exe,mode):
    listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(8)
    p=subprocess.Popen([str(exe),mode,'http://127.0.0.1:'+str(listener.getsockname()[1])],
                       stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    lines=[];messages=queue.Queue();peers=[];error=''
    def collect():
        for raw in p.stdout:
            try:line=raw.decode('utf-8').strip()
            except UnicodeDecodeError:line=raw.decode('gb18030',errors='replace').strip()
            lines.append(line);messages.put(line)
    reader=threading.Thread(target=collect);reader.start()
    def wait(prefix):
        while True:
            line=messages.get(timeout=8)
            if line.startswith('FAIL '):raise AssertionError(line)
            if line.startswith(prefix):return line
    def accept():
        peer,_=listener.accept();peer.settimeout(8);peers.append(peer);return peer
    def request(peer,path):
        data=bytearray()
        while not data.endswith(b'\r\n\r\n'):
            part=peer.recv(1)
            if not part:raise AssertionError('请求未完成连接已断开')
            data.extend(part)
        assert data.startswith(b'GET '+path.encode()+b' '),data
    def reply(peer):peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok')
    try:
        peer=accept();request(peer,'/0');wait('READY')
        stopping=mode.startswith('client-tcp-stop')
        if mode=='client-tcp-cancel' or stopping:
            p.stdin.write(b'cancel\n');p.stdin.flush()
            try:assert peer.recv(1)==b'','取消后真实TCP未关闭'
            except ConnectionResetError:pass
            wait('CLEARED')
            if not stopping:peer=accept();request(peer,'/3');reply(peer)
        else:
            reply(peer)
            if mode!='client-tcp-nil':request(peer,'/1');reply(peer)
            request(peer,'/3');reply(peer)
        wait('PASS ');p.wait(timeout=5);assert p.returncode==0
        if stopping:
            listener.settimeout(.1)
            try:
                unexpected,_=listener.accept();unexpected.close();raise AssertionError('析构重入创建了新连接')
            except socket.timeout:pass
    except Exception as exc:error=type(exc).__name__+': '+str(exc)
    finally:
        for peer in peers:peer.close()
        listener.close()
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
    ap.add_argument('--output',type=Path);ap.add_argument('--cases',nargs='+',default=CASES)
    o=ap.parse_args();rows=[]
    for mode in o.cases:
        runner=run_gap if mode=='socket-connect-gap' else run_race if mode.startswith('client-race-') else run
        row=runner(o.executable.resolve(),mode);rows.append(row)
        print(mode,'PASS' if row['passed'] else row['error'],flush=True)
        if o.output:o.output.write_text(json.dumps(rows,indent=2),encoding='utf-8')
    raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
