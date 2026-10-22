"""用正式 HttpServer 示例的临时副本比较优化前后 HTTP 吞吐，不覆盖示例或占用已有服务。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import socket
import statistics
import subprocess
import time
import xml.etree.ElementTree as ET
import ctypes
from ctypes import wintypes

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
AB = Path(r'D:\Tools\Development\ab\ab.exe')
BOMB = AB.with_name('bombardier-windows-amd64.exe')
FLAGS = subprocess.CREATE_NO_WINDOW
PORT = 18080
UNITS = ('Net.CrossHttpParams.pas', 'Net.CrossHttpServer.pas')
KERNEL = ctypes.WinDLL('kernel32', use_last_error=True)
KERNEL.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4


def cpu_seconds(process):
    values = [wintypes.FILETIME() for _ in range(4)]
    if not KERNEL.GetProcessTimes(int(process._handle), *[ctypes.byref(v) for v in values]):
        raise ctypes.WinError(ctypes.get_last_error())
    return sum((v.dwHighDateTime << 32) + v.dwLowDateTime for v in values[2:]) / 1e7


def command(args, cwd, timeout=90):
    p = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, timeout=timeout, creationflags=FLAGS)
    if p.returncode:
        raise RuntimeError((p.stdout + p.stderr).decode(errors='replace')[-6000:])
    return p.stdout


def build(root, role, before, fastmm):
    folder = root / role
    folder.mkdir()
    source = folder / 'source'
    source.mkdir()
    metadata = {}
    for name in UNITS:
        data = command(['git', 'show', before + ':Net/' + name], REPO) if role == 'before' else (REPO / 'Net' / name).read_bytes()
        (source / name).write_bytes(data)
        metadata[name] = hashlib.sha256(data).hexdigest()
    demo = REPO / 'Net/Demos/Delphi/HttpServer'
    data = (demo / 'HttpServer.dpr').read_bytes()
    assert b'TCrossHttpServer.Create(0, True)' in data
    data = data.replace(b'TCrossHttpServer.Create(0, True)', b'TCrossHttpServer.Create(0, False)')
    data = data.replace(b'__HttpServer.Port := 8080;', b'__HttpServer.Port := 18080;')
    data = data.replace(b'uses', b'uses\r\n  FastMM5,', 1)
    (folder / 'HttpServer.dpr').write_bytes(data)
    shutil.copy2(demo / 'HttpServer.res', folder / 'HttpServer.res')
    tree = ET.parse(demo / 'HttpServer.dproj')
    ET.register_namespace('', 'http://schemas.microsoft.com/developer/msbuild/2003')
    ns = '{http://schemas.microsoft.com/developer/msbuild/2003}'
    search = ';'.join(map(str, [source, REPO / 'Net', REPO / 'Utils', REPO / 'DelphiToFPC', fastmm.parent]))
    for item in tree.iter(ns + 'DCC_UnitSearchPath'):
        item.text = search + ';$(DCC_UnitSearchPath)'
    tree.write(folder / 'HttpServer.dproj', encoding='utf-8', xml_declaration=True)
    (folder / 'units').mkdir()
    (folder / 'out').mkdir()
    # 交给 cmd 文件处理引号，避免 Python 对嵌套 /c 字符串的二次转义。
    script = ('@echo off\ncall "' + str(DELPHI / 'bin/rsvars.bat') + '"\n'
              'if errorlevel 1 exit /b %errorlevel%\n'
              'msbuild HttpServer.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 '
              '/p:DCC_ExeOutput=out /p:DCC_DcuOutput=units /p:DCC_IncludePath="' + str(REPO) + '" /v:minimal /nologo\n')
    (folder / 'build.cmd').write_text(script, encoding='utf-8', newline='\r\n')
    output = command(['cmd.exe', '/d', '/c', 'build.cmd'], folder, 120)
    (folder / 'build.log').write_bytes(output)
    exe = folder / 'out/HttpServer.exe'
    metadata['binary_sha256'] = hashlib.sha256(exe.read_bytes()).hexdigest()
    metadata['demo_sha256'] = hashlib.sha256(data).hexdigest()
    metadata['fastmm_sha256'] = hashlib.sha256(fastmm.read_bytes()).hexdigest()
    (folder / 'source.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print('BUILD PASS', role, flush=True)
    return exe


def benchmark(root, role, exe, index, duration):
    prefix = root / f'{index}-{role}'
    guard = socket.socket()
    try:
        guard.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        guard.bind(('0.0.0.0', PORT))
    finally:
        guard.close()
    with prefix.with_suffix('.server.log').open('wb') as log:
        server = subprocess.Popen([str(exe)], cwd=exe.parent, stdin=subprocess.PIPE,
                                  stdout=log, stderr=subprocess.STDOUT, creationflags=FLAGS)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('server exited before readiness')
                try:
                    with socket.create_connection(('127.0.0.1', PORT), 0.3) as s:
                        s.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\nConnection: Keep-Alive\r\n\r\n')
                        response = b''
                        while len(response) < 210:
                            part = s.recv(4096)
                            if not part:
                                break
                            response += part
                    assert len(response) == 210 and b'Content-Length: 78\r\n' in response, response
                    prefix.with_suffix('.response.txt').write_bytes(response)
                    break
                except (ConnectionError, TimeoutError):
                    time.sleep(0.05)
            else:
                raise RuntimeError('server startup timeout')
            url = f'http://127.0.0.1:{PORT}/'
            command([AB, '-n', '20000', '-c', '1000', '-k', url], root)
            cpu_before = cpu_seconds(server)
            raw = command([AB, '-n', '100000', '-c', '1000', '-k', url], root)
            ab_cpu = cpu_seconds(server) - cpu_before
            prefix.with_suffix('.ab.txt').write_bytes(raw)
            text = raw.decode(errors='replace')
            def field(name):
                return float(re.search(r'^' + re.escape(name) + r':\s*([\d.]+)', text, re.M)[1])
            assert field('Failed requests') == 0 and field('Total transferred') == 21000000, text
            assert 'Non-2xx responses:' not in text, text
            cpu_before = cpu_seconds(server)
            raw = command([BOMB, '-c', '1000', '-d', str(duration) + 's', '-l', '-p', 'r', '-o', 'json', url], root)
            bomb_cpu = cpu_seconds(server) - cpu_before
            prefix.with_suffix('.bomb.json').write_bytes(raw)
            data = json.loads(raw)['result']
            assert sum(data[k] for k in ('others', 'req1xx', 'req3xx', 'req4xx', 'req5xx')) == 0, data
            row = {'index': index, 'role': role, 'ab_rps': field('Requests per second'),
                   'bomb_rps': data['rps']['mean'], 'bomb_ok': data['req2xx'],
                   'bomb_p99_us': data['latency']['percentiles']['99'], 'errors': data['others'],
                   'ab_server_cpu_s': ab_cpu, 'bomb_server_cpu_s': bomb_cpu,
                   'bomb_server_cpu_us_per_response': bomb_cpu * 1e6 / data['req2xx']}
            print(json.dumps(row), flush=True)
            return row
        finally:
            try:
                server.communicate(b'\r\n', timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.communicate()


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--before', default='97ce754')
    p.add_argument('--label', required=True)
    p.add_argument('--samples', type=int, default=3)
    p.add_argument('--duration', type=int, default=10)
    p.add_argument('--fastmm', type=Path, default=Path(r'D:\Design\Delphi\VclFmxRtl\FastMM5\FastMM5.pas'))
    o = p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', o.label):
        p.error('invalid label')
    root = HERE / 'bin' / o.label
    root.mkdir(exist_ok=False)
    executables = {role: build(root, role, o.before, o.fastmm.resolve(strict=True)) for role in ('before', 'after')}
    rows = []
    for i in range(o.samples):
        for role in (('before', 'after') if i % 2 == 0 else ('after', 'before')):
            rows.append(benchmark(root, role, executables[role], i, o.duration))
            (root / 'samples.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    summary = {role: {key: statistics.median(row[key] for row in rows if row['role'] == role)
                     for key in ('ab_rps', 'bomb_rps', 'bomb_p99_us', 'ab_server_cpu_s',
                                 'bomb_server_cpu_us_per_response')} for role in ('before', 'after')}
    (root / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(json.dumps(summary), flush=True)
