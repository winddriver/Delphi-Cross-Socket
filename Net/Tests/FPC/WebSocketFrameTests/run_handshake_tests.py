"""复用真实端点验证 WebSocket 握手；仅访问本机临时 TCP 端口。"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import queue
import socket
import subprocess
import sys
import threading

KEY = 'dGhlIHNhbXBsZSBub25jZQ=='
MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'


def accept(key):
    return base64.b64encode(hashlib.sha1((key + MAGIC).encode()).digest()).decode()


class Process:
    def __init__(self, executable, *args):
        self.p = subprocess.Popen([str(executable), *args], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        self.lines, self.messages = [], queue.Queue()
        self.reader = threading.Thread(target=self.read)
        self.reader.start()

    def read(self):
        for raw in self.p.stdout:
            line = raw.decode('utf-8', errors='replace').strip()
            self.lines.append(line)
            self.messages.put(line)

    def next(self):
        return self.messages.get(timeout=8)

    def stop(self):
        try:
            if self.p.poll() is None:
                self.p.stdin.write(b'stop\n')
                self.p.stdin.flush()
                self.p.wait(timeout=6)
        except (OSError, subprocess.TimeoutExpired):
            self.p.kill()
            self.p.wait()
        self.reader.join(timeout=3)
        self.p.stdin.close()
        self.p.stdout.close()


def read_headers(s):
    data = bytearray()
    while not data.endswith(b'\r\n\r\n'):
        part = s.recv(1)
        assert part, '响应头未结束就断开'
        data += part
        assert len(data) < 32768, '响应头过长'
    lines = data.decode('ascii').split('\r\n')
    headers = {}
    for line in lines[1:]:
        if line:
            name, value = line.split(':', 1)
            headers.setdefault(name.lower(), []).append(value.strip())
    return lines[0], headers


def closed(s):
    try:
        assert s.recv(1) == b'', '拒绝握手后仍发送了额外数据'
    except (ConnectionResetError, ConnectionAbortedError):
        pass


def request(kind):
    method, version = 'GET', 'HTTP/1.1'
    headers = [('Host', 'localhost'), ('Upgrade', 'websocket'), ('Connection', 'Upgrade'),
               ('Sec-WebSocket-Key', KEY), ('Sec-WebSocket-Version', '13')]
    valid = kind in ('valid', 'tokens', 'case', 'repeated-connection', 'extension-offer')
    name = {'missing-key': 'Sec-WebSocket-Key', 'missing-version': 'Sec-WebSocket-Version',
            'missing-host': 'Host'}.get(kind)
    if name:
        headers = [(n, v) for n, v in headers if n != name]
    replacements = {
        'fake-upgrade': ('Upgrade', 'xwebsocket'), 'fake-connection': ('Connection', 'XUpgrade'),
        'unicode-upgrade': ('Upgrade', 'webſocket'),
        'bad-key': ('Sec-WebSocket-Key', '!!!!!!!!!!!!!!!!!!!!!!=='),
        'short-key': ('Sec-WebSocket-Key', base64.b64encode(b'a' * 15).decode()),
        'long-key': ('Sec-WebSocket-Key', base64.b64encode(b'a' * 17).decode()),
        'noncanonical-key': ('Sec-WebSocket-Key', KEY[:-3] + 'R=='),
        'version-12': ('Sec-WebSocket-Version', '12'),
        'tokens': ('Connection', 'keep-alive, Upgrade'),
        'case': ('Upgrade', 'WebSocket')}
    if kind in replacements:
        key, value = replacements[kind]
        headers = [(n, value if n == key else v) for n, v in headers]
    if kind == 'post': method = 'POST'
    if kind == 'head': method = 'HEAD'
    if kind == 'http10': version = 'HTTP/1.0'
    if kind == 'duplicate-key': headers.append(('Sec-WebSocket-Key', KEY))
    if kind == 'duplicate-version': headers.append(('Sec-WebSocket-Version', '13'))
    if kind == 'duplicate-host': headers.append(('Host', 'other'))
    if kind == 'extension-offer': headers.append(('Sec-WebSocket-Extensions', 'permessage-deflate'))
    if kind == 'repeated-connection':
        headers = [(n, 'keep-alive' if n == 'Connection' else v) for n, v in headers]
        headers.append(('Connection', 'Upgrade'))
    return (f'{method} /ws {version}\r\n' + ''.join(f'{n}: {v}\r\n' for n, v in headers)
            + '\r\n').encode(), valid, method


SERVER_CASES = ['valid', 'tokens', 'case', 'repeated-connection', 'extension-offer',
                'post', 'head', 'http10', 'fake-upgrade', 'fake-connection', 'missing-key',
                'bad-key', 'short-key', 'long-key', 'noncanonical-key', 'duplicate-key',
                'missing-version', 'version-12', 'duplicate-version', 'missing-host', 'duplicate-host', 'unicode-upgrade']


def run_server(executable):
    process = Process(executable, 'server', 'handshake')
    results = []
    try:
        ready = process.next()
        assert ready.startswith('READY '), ready
        port = int(ready.split()[1])
        for case in SERVER_CASES:
            detail = ''
            try:
                payload, valid, method = request(case)
                with socket.create_connection(('127.0.0.1', port), timeout=2) as s:
                    s.settimeout(2)
                    s.sendall(payload)
                    first, headers = read_headers(s)
                    status = int(first.split()[1])
                    if valid:
                        assert status == 101, (status, headers)
                        assert headers.get('sec-websocket-accept') == [accept(KEY)], headers
                        assert 'sec-websocket-extensions' not in headers, headers
                    else:
                        assert status in (400, 426), (status, headers)
                        if case == 'version-12':
                            assert headers.get('sec-websocket-version') == ['13'], headers
                        size = 0 if method == 'HEAD' else int(headers.get('content-length', ['0'])[0])
                        while size:
                            data = s.recv(size)
                            assert data, '错误响应正文不完整'
                            size -= len(data)
                        closed(s)
            except Exception as error:
                detail = f'{type(error).__name__}: {error}'
            results.append({'case': 'server-' + case, 'passed': not detail, 'detail': detail})
    finally:
        process.stop()
    opened = next((int(line.split()[1]) for line in process.lines if line.startswith('OPENS ')), -1)
    expected = sum(request(case)[1] for case in SERVER_CASES)
    results.append({'case': 'server-open-count', 'passed': opened == expected and process.p.returncode == 0,
                    'detail': f'opens={opened}, expected={expected}, exit={process.p.returncode}'})
    return results


CLIENT_CASES = ['valid', 'case', 'tokens', 'repeated-connection', 'protocol',
                'status-200', 'http10', 'missing-upgrade', 'fake-upgrade', 'missing-connection',
                'fake-connection', 'bad-accept', 'duplicate-accept', 'unsolicited-protocol',
                'wrong-protocol-case', 'duplicate-protocol', 'extension', 'offered-extension',
                'changed-key', 'invalid-protocol', 'response-error', 'changed-key-ows', 'filtered-protocol', 'unicode-upgrade']


def run_client(executable, case):
    valid = case in ('valid', 'case', 'tokens', 'repeated-connection', 'protocol', 'changed-key', 'changed-key-ows')
    offered = 'protocol' if case in ('protocol', 'wrong-protocol-case', 'duplicate-protocol') else (
        'extension' if case == 'offered-extension' else '')
    offered = {'changed-key': 'key', 'invalid-protocol': 'invalid-protocol',
               'response-error': 'response-error', 'changed-key-ows': 'key-ows',
               'filtered-protocol': 'filtered-protocol'}.get(case, offered)
    detail = ''
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(6)
        process = Process(executable, 'handshake-client', f'ws://127.0.0.1:{listener.getsockname()[1]}/ws', offered)
        try:
            s, _ = listener.accept()
            with s:
                s.settimeout(2)
                _, req = read_headers(s)
                if case == 'filtered-protocol':
                    assert 'sec-websocket-protocol' not in req, req
                expected_accept = accept(req['sec-websocket-key'][0])
                headers = [('Upgrade', 'websocket'), ('Connection', 'Upgrade'),
                           ('Sec-WebSocket-Accept', expected_accept)]
                replacements = {'case': ('Upgrade', 'WebSocket'), 'tokens': ('Connection', 'keep-alive, upgrade'),
                                'fake-upgrade': ('Upgrade', 'xwebsocket'), 'fake-connection': ('Connection', 'XUpgrade'),
                                'unicode-upgrade': ('Upgrade', 'webſocket'),
                                'bad-accept': ('Sec-WebSocket-Accept', 'invalid')}
                if case in replacements:
                    key, value = replacements[case]
                    headers = [(n, value if n == key else v) for n, v in headers]
                if case.startswith('missing-'):
                    headers = [(n, v) for n, v in headers if n.lower() != case[len('missing-'):]]
                if case == 'repeated-connection':
                    headers = [(n, 'keep-alive' if n == 'Connection' else v) for n, v in headers]
                    headers.append(('Connection', 'Upgrade'))
                if case == 'duplicate-accept': headers.append(('Sec-WebSocket-Accept', expected_accept))
                if case in ('protocol', 'unsolicited-protocol', 'wrong-protocol-case', 'duplicate-protocol'):
                    headers.append(('Sec-WebSocket-Protocol', 'Chat' if case == 'wrong-protocol-case' else 'chat'))
                if case == 'duplicate-protocol': headers.append(('Sec-WebSocket-Protocol', 'chat'))
                if case == 'invalid-protocol': headers.append(('Sec-WebSocket-Protocol', 'chat bad'))
                if case == 'filtered-protocol': headers.append(('Sec-WebSocket-Protocol', 'chat'))
                if case in ('extension', 'offered-extension'): headers.append(('Sec-WebSocket-Extensions', 'permessage-deflate'))
                version = 'HTTP/1.0' if case == 'http10' else 'HTTP/1.1'
                status = '200 OK' if case == 'status-200' else '101 Switching Protocols'
                if case == 'status-200': headers.append(('Content-Length', '0'))
                s.sendall((f'{version} {status}\r\n' + ''.join(f'{n}: {v}\r\n' for n, v in headers) + '\r\n').encode())
                result = process.next()
                assert result == ('RESULT 1 0' if valid else 'RESULT 0 1'), result
                if not valid: closed(s)
        except Exception as error:
            detail = f'{type(error).__name__}: {error}'
        finally:
            process.stop()
    if process.p.returncode:
        detail += f'; exit={process.p.returncode}: {process.lines}'
    if not valid and 'COUNTS 0 1' not in process.lines:
        detail += f'; 失败通知次数错误: {process.lines}'
    return {'case': 'client-' + case, 'passed': not detail, 'detail': detail}


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--report', type=Path)
    options = parser.parse_args()
    executable = options.executable.resolve(strict=True)
    results = run_server(executable) + [run_client(executable, case) for case in CLIENT_CASES]
    for result in results:
        print('PASS' if result['passed'] else 'FAIL', result['case'], result['detail'], flush=True)
    report = {'sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
              'passed': sum(x['passed'] for x in results), 'total': len(results), 'results': results}
    if options.report:
        options.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Handshake:', report['passed'], '/', report['total'])
    return int(report['passed'] != report['total'])


if __name__ == '__main__':
    raise SystemExit(main())
