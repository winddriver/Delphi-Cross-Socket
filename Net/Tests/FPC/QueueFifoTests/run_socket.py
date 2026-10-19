"""真实Linux TCP背压回归；逐字节验证部分发送恢复与关闭取消。"""
import argparse
import json
from pathlib import Path
import queue
import socket
import subprocess
import threading

TOTAL=16*1024*1024

def run(exe,depth,cancel):
    process=subprocess.Popen([str(exe),'socket-network',str(depth)],stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    messages=queue.Queue();lines=[];peer=None;error=''
    def collect():
        for raw in process.stdout:
            text=raw.decode(errors='replace').strip();lines.append(text);messages.put(text)
    reader=threading.Thread(target=collect);reader.start()
    def wait(prefix):
        while True:
            line=messages.get(timeout=10)
            if line.startswith('FAIL '):raise AssertionError(line)
            if line.startswith(prefix):return line
    def command(value):process.stdin.write((value+'\n').encode());process.stdin.flush()
    try:
        port=int(wait('PORT ').split()[1]);peer=socket.socket()
        peer.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4096)
        peer.settimeout(10);peer.connect(('127.0.0.1',port));wait('CONNECTED')
        peer.sendall(b'Q');wait('QUEUED ');command('probe');wait('EAGAIN ')
        if cancel:command('close')
        received=bytearray()
        while len(received)<TOTAL:
            try:chunk=peer.recv(min(262144,TOTAL-len(received)))
            except ConnectionResetError:chunk=b''
            if not chunk:break
            received.extend(chunk)
        expected=b''.join(bytes([i%251])*(TOTAL//depth+(TOTAL%depth if i==0 else 0)) for i in range(depth))
        assert received==expected[:len(received)],'发送字节乱序/缓冲区提前释放'
        if not cancel:assert len(received)==TOTAL,'队列恢复后数据不完整'
        else:assert len(received)<TOTAL,'关闭用例未保留待发送项'
        command('done');_,calls,success,failure=wait('DONE ').split()
        assert int(calls)==depth and int(success)+int(failure)==depth
        assert (int(failure)>0) if cancel else (int(failure)==0)
        command('stop');wait('STOPPED');process.wait(timeout=5)
        assert process.returncode==0
    except Exception as exc:error=type(exc).__name__+': '+str(exc)
    finally:
        if process.poll() is None:
            try:command('stop');process.wait(timeout=3)
            except (OSError,subprocess.TimeoutExpired):process.kill();process.wait()
        if peer:peer.close()
        reader.join(timeout=3);process.stdin.close();process.stdout.close()
    return {'depth':depth,'cancel':cancel,'passed':not error,'error':error,'output':'\n'.join(lines)}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('executable',type=Path)
    parser.add_argument('--output',type=Path);options=parser.parse_args();results=[]
    for depth in (100,1000,10000):
        for cancel in (False,True):
            result=run(options.executable.resolve(),depth,cancel);results.append(result)
            print(depth,'cancel' if cancel else 'drain','PASS' if result['passed'] else result['error'],flush=True)
    if options.output:options.output.write_text(json.dumps(results,indent=2),encoding='utf-8')
    raise SystemExit(0 if all(r['passed'] for r in results) else 1)
