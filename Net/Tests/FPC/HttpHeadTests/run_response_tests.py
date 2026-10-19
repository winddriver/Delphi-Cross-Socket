"""用原始 TCP 响应验证客户端状态行、定界和连接复用。"""
import argparse
import hashlib
import http.server
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading

CASES = {
    'bad-version': ('response-invalid', b'HTP/1.1 200 OK', b'Content-Length: 2\r\n', b'ok'),
    'bad-status': ('response-invalid', b'HTTP/1.1 xyz Broken', b'Content-Length: 2\r\n', b'ok'),
    'short-status': ('response-invalid', b'HTTP/1.1 20 Broken', b'Content-Length: 2\r\n', b'ok'),
    'long-status': ('response-invalid', b'HTTP/1.1 2000 Broken', b'Content-Length: 2\r\n', b'ok'),
    'missing-reason-space': ('response-invalid', b'HTTP/1.1 200', b'Content-Length: 2\r\n', b'ok'),
    'bad-length': ('response-invalid', b'HTTP/1.1 200 OK', b'Content-Length: nope\r\nConnection: close\r\n', b'ok'),
    'length-overflow': ('response-invalid', b'HTTP/1.1 200 OK', b'Content-Length: 9223372036854775808\r\nConnection: close\r\n', b'ok'),
    'conflict': ('response-invalid', b'HTTP/1.1 200 OK', b'Content-Length: 2\r\nTransfer-Encoding: chunked\r\n', b'2\r\nok\r\n0\r\n\r\n'),
    'unsupported-te': ('response-invalid', b'HTTP/1.1 200 OK', b'Transfer-Encoding: example\r\nConnection: close\r\n', b'ok'),
    'response-list': ('response-close', b'HTTP/1.1 200 OK', b'Content-Length: 2\r\nConnection: example, CLOSE\r\n', b'ok'),
    'response-duplicates': ('response-close', b'HTTP/1.1 200 OK', b'Content-Length: 2\r\nConnection: keep-alive\r\nConnection: close\r\n', b'ok'),
    'http10-default': ('response-close', b'HTTP/1.0 200 OK', b'Content-Length: 2\r\n', b'ok'),
    'http10-list': ('response-reuse', b'HTTP/1.0 200 OK', b'Content-Length: 2\r\nConnection: example, keep-alive\r\n', b'ok'),
    'http11-default': ('response-reuse', b'HTTP/1.1 200 OK', b'Content-Length: 2\r\n', b'ok'),
    'empty-reason': ('response-reuse', b'HTTP/1.1 200 ', b'Content-Length: 2\r\n', b'ok'),
    'empty-headers': ('response-empty', b'HTTP/1.1 204 No Content', b'', b''),
    'close-body-list': ('response-close', b'HTTP/1.1 200 OK', b'Connection: example, close\r\n', b'ok'),
    'close-body-unknown': ('response-close', b'HTTP/1.1 200 OK', b'Connection: example\r\n', b'ok'),
    'request-close': ('response-close', b'HTTP/1.1 200 OK', b'Content-Length: 2\r\n', b'ok'),
    'close-body-keepalive': ('response-close', b'HTTP/1.1 200 OK', b'Connection: keep-alive\r\n', b'ok'),
    'head-metadata': ('response-head-metadata', b'HTTP/1.1 200 OK', b'Content-Length: 2\r\nTransfer-Encoding: example\r\n', b''),
    'invalid-then-valid': ('response-invalid', b'HTP/1.1 200 OK', b'Content-Length: 2\r\n',
                           b'okHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nno'),
}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(5)
        with self.server.lock:
            self.server.connections += 1
            self.number = self.server.connections

    def handle(self):
        try:
            super().handle()
        except (ConnectionError, TimeoutError):
            pass

    def do_GET(self):
        with self.server.lock:
            self.server.requests.append(self.path)
        if self.path.endswith('/after'):
            first, fields, body = b'HTTP/1.1 200 OK', b'Content-Length: 2\r\n', b'ok'
        else:
            _, first, fields, body = CASES[self.server.case]
        # 204空字段是合法控制例，不能为了测试加一个标识字段。
        identity = b'' if self.server.case == 'empty-headers' and not self.path.endswith('/after') else f'X-Connection-Id: {self.number}\r\n'.encode()
        self.connection.sendall(first + b'\r\n' + fields + identity + b'\r\n' + body)
        if not self.path.endswith('/after') and self.server.case in {
            'bad-length', 'length-overflow', 'unsupported-te', 'close-body-list', 'close-body-unknown', 'close-body-keepalive'
        }:
            self.connection.shutdown(socket.SHUT_WR)
            self.close_connection = True
        else:
            # 故意保持有close字段的TCP连接，客户端必须依据协议自行关闭，不能靠服务端兜底。
            self.close_connection = False

    do_HEAD = do_GET


def run(executable, name):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.case = name
    server.connections = 0
    server.requests = []
    server.lock = threading.Lock()
    worker = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': .02})
    worker.start()
    try:
        mode = CASES[name][0]
        result = subprocess.run([str(executable), mode, f'http://127.0.0.1:{server.server_port}/{name}'],
                                capture_output=True, timeout=20, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        raw = result.stdout + result.stderr
        try:
            detail = raw.decode('utf-8').strip()
        except UnicodeDecodeError:
            detail = raw.decode('gb18030', errors='replace').strip()
        errors = []
        if server.requests != ['/' + name, '/' + name + '/after']:
            errors.append('request order: ' + repr(server.requests))
        expected_connections = 2 if mode in ('response-close', 'response-invalid') else 1
        if server.connections != expected_connections:
            errors.append(f'connections={server.connections}, expected={expected_connections}')
        return {'case': name, 'passed': result.returncode == 0 and not errors, 'output': detail, 'errors': errors}
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--cases', nargs='+', choices=list(CASES), default=list(CASES))
    options = parser.parse_args()
    executable = options.executable.resolve(strict=True)
    results = []
    for name in options.cases:
        try:
            result = run(executable, name)
        except Exception as error:
            result = {'case': name, 'passed': False, 'output': str(error)}
        results.append(result)
        print('PASS' if result['passed'] else 'FAIL', name, result['output'], result.get('errors', []), flush=True)
    report = {'binary_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
              'passed': sum(r['passed'] for r in results), 'total': len(results), 'results': results}
    if options.report:
        options.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return int(report['passed'] != report['total'])


if __name__ == '__main__':
    raise SystemExit(main())
