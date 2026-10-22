"""在独立副本中区分工作线程、预投 AcceptEx 数量和 Windows backlog；不修改生产单元。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import socket
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import run_http_bench as bench

CASES = {
    'threads4': (4, 4, 2147483647, 0),
    'backlog2048': (4, 4, -2048, 0),
    'accepts65': (4, 65, 2147483647, 0),
    'rate30000': (4, 4, 2147483647, 30000),
    'threads65': (65, 65, 2147483647, 0),
}


def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new, 1)


def prepare(root, fastmm):
    exe = bench.build(root, 'diagnostic', '97ce754', fastmm)
    folder = exe.parent.parent
    source = (bench.REPO / 'Net/Net.CrossSocket.Iocp.pas').read_text(encoding='utf-8-sig')
    source = replace_once(source, '\nimplementation\n', '''
// 仅存在于诊断副本，所有指标都在接受连接时统计，不进入每请求发送路径。
var
  BenchSubmitted, BenchAccepted, BenchSubmitErrors, BenchCompleteErrors: Integer;

implementation
''')
    source = replace_once(source, 'TSocketAPI.Listen(LListenSocket)',
                          'TSocketAPI.Listen(LListenSocket, StrToIntDef(ParamStr(3), SOMAXCONN))')
    source = replace_once(source, 'for I := 1 to GetIoThreads do',
                          'for I := 1 to StrToIntDef(ParamStr(2), GetIoThreads) do')
    source = replace_once(source, '      if Result then\n      begin\n        // 成功提交后',
                          '      if Result then\n      begin\n        AtomicIncrement(BenchSubmitted);\n        // 成功提交后')
    source = replace_once(source, "    _Log('Accept socket error %d: %s', [LError, SysErrorMessage(LError)]);",
                          "    AtomicIncrement(BenchSubmitErrors);\n    _Log('Accept socket error %d: %s', [LError, SysErrorMessage(LError)]);")
    source = replace_once(source, "  if not Result and (LError <> 0) then\n    _Log('AcceptEx error %d: %s', [LError, SysErrorMessage(LError)]);",
                          "  if not Result and (LError <> 0) then\n  begin\n    AtomicIncrement(BenchSubmitErrors);\n    _Log('AcceptEx error %d: %s', [LError, SysErrorMessage(LError)]);\n  end;")
    source = replace_once(source, 'begin\n  LClientSocket := APerIoData.Socket;\n  APerIoData.Socket := INVALID_SOCKET;',
                          'begin\n  AtomicIncrement(BenchAccepted);\n  LClientSocket := APerIoData.Socket;\n  APerIoData.Socket := INVALID_SOCKET;')
    source = replace_once(source, '        begin\n          // 失败的 AcceptEx 尚未移交连接',
                          '        begin\n          AtomicIncrement(BenchCompleteErrors);\n          // 失败的 AcceptEx 尚未移交连接')
    (folder / 'source/Net.CrossSocket.Iocp.pas').write_text(source, encoding='utf-8-sig', newline='\r\n')
    demo = (folder / 'HttpServer.dpr').read_text(encoding='utf-8-sig')
    demo = replace_once(demo, '  ,Net.CrossSocket.Base', '  ,Windows\n  ,Net.CrossSocket.Iocp\n  ,Net.CrossSocket.Base')
    demo = replace_once(demo, '  __HttpServer: ICrossHttpServer;', '  __HttpServer: ICrossHttpServer;\n  BenchCommand: string;')
    demo = replace_once(demo, 'TCrossHttpServer.Create(0, False)', 'TCrossHttpServer.Create(StrToIntDef(ParamStr(1), 4), False)')
    demo = replace_once(demo, '  __HttpServer.Port := 18080;', "  __HttpServer.Addr := '127.0.0.1';\n  __HttpServer.Port := 18080;")
    demo = replace_once(demo, '  TestCrossHttpServer;\n  Readln;', '''  CrossSocketLogEnabled := True;
  _SetCrossLogger(procedure(const S: string) begin
    if (Pos('AcceptEx error', S) > 0) or (Pos('Accept socket error', S) > 0)
      or (Pos('Accept context error', S) > 0) then begin Writeln(S); Flush(Output); end;
  end);
  TestCrossHttpServer;
  repeat
    Readln(BenchCommand);
    if BenchCommand = 'stats' then
    begin
      Writeln(Format('STATS tick=%d accepted=%d submitted=%d submit_errors=%d complete_errors=%d active=%d listens=%d',
        [GetTickCount64, AtomicCmpExchange(BenchAccepted, 0, 0), AtomicCmpExchange(BenchSubmitted, 0, 0),
         AtomicCmpExchange(BenchSubmitErrors, 0, 0), AtomicCmpExchange(BenchCompleteErrors, 0, 0),
         __HttpServer.ConnectionsCount, __HttpServer.ListensCount]));
      Flush(Output);
    end;
  until BenchCommand = 'quit';''')
    (folder / 'HttpServer.dpr').write_text(demo, encoding='utf-8-sig', newline='\r\n')
    output = bench.command(['cmd.exe', '/d', '/c', 'build.cmd'], folder, 120)
    (folder / 'diagnostic-build.log').write_bytes(output)
    metadata = {'production_iocp_sha256': hashlib.sha256((bench.REPO / 'Net/Net.CrossSocket.Iocp.pas').read_bytes()).hexdigest(),
                'diagnostic_iocp_sha256': hashlib.sha256((folder / 'source/Net.CrossSocket.Iocp.pas').read_bytes()).hexdigest(),
                'binary_sha256': hashlib.sha256(exe.read_bytes()).hexdigest(),
                'backlog_hint_definition': 'Microsoft WinSock2.h: SOMAXCONN_HINT(b) (-(b))'}
    (folder / 'diagnostic-source.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    return exe


def run(root, exe, case, index, duration, concurrency=1000):
    threads, accepts, backlog, rate = CASES[case]
    guard = socket.socket()
    try:
        guard.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        guard.bind(('0.0.0.0', bench.PORT))
    finally:
        guard.close()
    prefix = root / f'{index}-{case}'
    with prefix.with_suffix('.server.log').open('wb') as log:
        server = subprocess.Popen([str(exe), str(threads), str(accepts), str(backlog)], cwd=exe.parent,
            stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, creationflags=bench.FLAGS)
        client = None
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('diagnostic server exited')
                try:
                    with socket.create_connection(('127.0.0.1', bench.PORT), 0.2):
                        break
                except (ConnectionError, TimeoutError):
                    time.sleep(0.05)
            else:
                raise RuntimeError('startup timeout')
            url = f'http://127.0.0.1:{bench.PORT}/'
            bench.command([bench.AB, '-n', '20000', '-c', str(concurrency), '-k', url], root)
            server.stdin.write(b'stats\n'); server.stdin.flush()
            args = [str(bench.BOMB), '-c', str(concurrency), '-d', str(duration)+'s', '-l', '-p', 'r', '-o', 'json']
            if rate:
                args += ['-r', str(rate)]
            args.append(url)
            before_cpu = bench.cpu_seconds(server)
            client = subprocess.Popen(args, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=bench.FLAGS)
            started = time.monotonic()
            next_stats = 1.0
            while client.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed > duration + 15:
                    raise RuntimeError('client timeout')
                if elapsed >= next_stats:
                    server.stdin.write(b'stats\n'); server.stdin.flush()
                    next_stats += 2.0
                time.sleep(0.1)
            raw, stderr = client.communicate()
            server_cpu = bench.cpu_seconds(server) - before_cpu
            prefix.with_suffix('.bomb.json').write_bytes(raw)
            if client.returncode:
                raise RuntimeError(stderr.decode(errors='replace'))
            data = json.loads(raw)['result']
            server.stdin.write(b'stats\n'); server.stdin.flush()
            time.sleep(0.05)
            table = bench.command(['netstat.exe', '-ano', '-p', 'tcp'], root).decode(errors='replace')
            listeners = [line.strip() for line in table.splitlines() if ':18080 ' in line and 'LISTENING' in line]
            with socket.create_connection(('127.0.0.1', bench.PORT), 2):
                fresh_connection = True
            row = dict(index=index, case=case, threads=threads, accepts=accepts, backlog=backlog, rate=rate,
                       concurrency=concurrency, ok=data['req2xx'], errors=data['others'], error_details=data.get('errors', []),
                       effective_ok_rps=data['req2xx']/data['timeTakenSeconds'], reported_rps=data['rps']['mean'],
                       server_cpu_s=server_cpu, listeners_after=listeners, fresh_connection=fresh_connection)
        finally:
            if client is not None and client.poll() is None:
                client.kill(); client.communicate()
            try:
                server.communicate(b'quit\n', timeout=10)
            except subprocess.TimeoutExpired:
                server.kill(); server.communicate()
    text = prefix.with_suffix('.server.log').read_text(encoding='gb18030', errors='replace')
    row['stats'] = [dict((k, int(v)) for k, v in re.findall(r'(\w+)=(\d+)', line))
                    for line in text.splitlines() if line.startswith('STATS ')]
    row['accept_error_logs'] = [line for line in text.splitlines()
                                if not line.startswith('STATS ') and 'error' in line.lower()]
    print(json.dumps({k:v for k,v in row.items() if k != 'stats'}), flush=True)
    return row


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--cases', nargs='+', choices=list(CASES), default=list(CASES))
    parser.add_argument('--samples', type=int, default=1)
    parser.add_argument('--duration', type=int, default=10)
    parser.add_argument('--concurrency', type=int, default=1000)
    parser.add_argument('--exe', type=Path, help='复用已有诊断二进制，避免重复构建')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        parser.error('invalid label')
    root = bench.HERE / 'bin' / args.label
    root.mkdir(exist_ok=False)
    exe = args.exe.resolve(strict=True) if args.exe else prepare(root, Path(r'D:\Design\Delphi\VclFmxRtl\FastMM5\FastMM5.pas'))
    results = []
    for index in range(args.samples):
        for case in (args.cases if index % 2 == 0 else list(reversed(args.cases))):
            results.append(run(root, exe, case, index, args.duration, args.concurrency))
            (root / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
