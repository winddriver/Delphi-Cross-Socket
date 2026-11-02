"""Header 字节合同、内存连接以及真实 HTTP client 线上测试。"""
from pathlib import Path
import argparse
import hashlib
import json
import socket
import subprocess
import sys
import time
import queue
import threading

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
CN = Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
FPC = Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe')
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


# 仅解释测试进程的控制台输出，不参与线上 HTTP 字节的编码或解码。
def decode(data):
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return data.decode('gb18030', errors='replace')


# target 指编译目标；output 必须是新的独立目录，checked 覆盖断言/I/O/范围/溢出开关。
# Linux 在 Windows 工具链交叉编译，构建成功不等于运行通过，需到目标系统用 --executable 执行。
def build(target, output, checked):
    output.mkdir(parents=True, exist_ok=False)
    units = output / 'units'
    units.mkdir()
    search = [REPO / 'Net', REPO / 'Utils', CN]
    linux = 'linux' in target
    if target.startswith('fpc'):
        search += [REPO / 'DelphiToFPC', Path(r'D:\Design\FreePascal\lazarus\components\lazutils')]
        args = [FPC.with_name('ppcrossx64.exe') if linux else FPC, '-B', '-O3', '-CX', '-Xs', '-XX']
        if linux:
            args += ['-Tlinux']
        if checked:
            args += ['-Cr', '-Co', '-Ci', '-Sa']
        args += ['-Fu' + str(p) for p in search]
        args += ['-Fi' + str(REPO), '-FE' + str(output), '-FU' + str(units), HERE / 'HttpHeaderTests.lpr']
    else:
        arch = 'linux64' if linux else target
        args = [DELPHI / 'bin' / ('dcclinux64.exe' if linux else ('dcc64.exe' if target == 'win64' else 'dcc32.exe')),
                '-Q', '-B', '-$C-', '-$D+', '-$I-', '-$L+', '-$O+', '-$Q-', '-$R-', '-$Y+',
                '-NSSystem;Posix' if linux else '-NSSystem;System.Win;Winapi', '-U' + ';'.join(map(str, search + [DELPHI / 'lib' / arch / 'release'])),
                '-I' + str(REPO) + ';' + str(CN), '-E' + str(output), '-N0' + str(units)]
        if checked:
            args += ['-$C+', '-$I+', '-$Q+', '-$R+']
        if linux:
            sdk = Path.home() / 'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'
            libs = [DELPHI / 'lib/linux64/release', sdk / 'usr/lib/x86_64-linux-gnu', sdk / 'lib/x86_64-linux-gnu', sdk / 'usr/lib/gcc/x86_64-linux-gnu/11']
            args += ['--syslibroot:' + str(sdk), '--libpath:' + ';'.join(map(str, libs))]
        args += [HERE / 'HttpHeaderTests.dpr']
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120, creationflags=NO_WINDOW)
    (output / 'build.log').write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(decode(result.stdout + result.stderr)[-6000:])
    exe = output / ('HttpHeaderTests' if linux else 'HttpHeaderTests.exe')
    files = [REPO / 'Net' / name for name in ('Net.CrossHttpParams.pas', 'Net.CrossHttpUtils.pas',
             'Net.CrossHttpClient.pas', 'Net.CrossHttpServer.pas', 'Net.CrossHttpParser.pas', 'Net.CrossHttpSessions.pas')]
    files += [HERE / 'HttpHeaderTests.lpr', HERE / 'run_tests.py', REPO / 'Utils/Utils.Utils.pas']
    files += sorted(HERE.glob('*.inc'))
    metadata = {'command': list(map(str, args)), 'checked': checked,
                'sources': {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                'binary_sha256': hashlib.sha256(exe.read_bytes()).hexdigest(), 'binary_bytes': exe.stat().st_size}
    (output / 'build.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print('BUILD PASS', target, 'checked' if checked else 'release', flush=True)
    return exe


# exe 是实际 HTTP 客户端，case 选择线上响应或非法发送场景；Python 端不使用 HTTP 库，
# 直接保留 BOM 等原始字节，避免库替测试程序规范化报文。
def client(exe, case):
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(7)
        p = subprocess.Popen([str(exe), 'client', f'http://127.0.0.1:{listener.getsockname()[1]}/test', case],
                             cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
        received = bytearray()
        try:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(7)
                while b'\r\n\r\n' not in received:
                    try:
                        data = conn.recv(8192)
                    except ConnectionResetError:
                        data = b''
                    if not data:
                        break
                    received.extend(data)
                # 发送失败必须发生在任何请求字节上网之前；只有异常回调而已写出部分头也算失败。
                if case.startswith('invalid-'):
                    assert not received, f'非法发送泄漏字节: {received!r}'
                else:
                    # 逐字节核对动态Query的名称/值编码及重复项顺序，不用被测编码器生成预期。
                    target = (b'/test?dup=%E4%B8%AD%E6%96%87&dup&a%20b=x%2By%26%3D%2F%23&emoji=%F0%9F%98%80'
                              if case == 'query-values' else b'/test')
                    assert received.startswith((b'HEAD' if case == 'head-metadata' else b'GET') + b' ' + target + b' HTTP/1.1\r\n'), received
                    assert 'X-Text: 中文😀\r\n'.encode() in received, received
                    assert not received.startswith(b'\xef\xbb\xbf'), received
                    response = ('HTTP/1.1 200 中文\r\nX-Text: 中文\r\nSet-Cookie: a=1\r\n'
                                'Set-Cookie: b=2\r\nContent-Length: 0\r\nConnection: close\r\n\r\n').encode()
                    if case == 'cookie-values':
                        # 保留重复名称、字段名大小写及非法Cookie；测试库不能替客户端过滤。
                        response = (b'HTTP/1.1 200 OK\r\n'
                                    b'Set-Cookie: a=1; Path=/first; HttpOnly\r\n'
                                    b'X-Between: preserved\r\n'
                                    b'sEt-CoOkIe: a=2; Max-Age=60; Secure\r\n'
                                    b'SET-COOKIE: empty=\r\n'
                                    b'Set-Cookie: bad name=value\r\n'
                                    b'Set-Cookie: no-equals\r\n'
                                    b'Content-Length: 0\r\nConnection: close\r\n\r\n')
                    if case == 'opaque-response':
                        response = response.replace('X-Text: 中文'.encode(), b'X-Text: \xfe').replace(b'Content-Length: 0', b'Content-Length: 3') + b'abc'
                    if case == 'head-metadata':
                        response = 'HTTP/1.1 200 OK\r\nTransfer-Encoding: custom; p="中文"\r\n\r\n'.encode()
                    if case == 'empty-response':
                        response = b'HTTP/1.1 204 \r\n\r\n'
                    if case == 'bad-response':
                        response = b'HTTP/1.1 200 OK\r\nX: good\r\nbad\r\nContent-Length: 0\r\n\r\n'
                    if case == 'length-bom':
                        response = b'HTTP/1.1 200 OK\r\nContent-Length: \xef\xbb\xbf3\r\n\r\nabc'
                    if case == 'transfer-bom':
                        response = b'HTTP/1.1 200 OK\r\nTransfer-Encoding: \xef\xbb\xbfchunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n'
                    # 按单字节调用 sendall，不依赖 HTTP 库重编码；TCP 可合并读取，
                    # 确定的逐字节 Parser 边界由组件测试另行覆盖。
                    for value in response:
                        try:
                            conn.sendall(bytes([value]))
                        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                            # 对端提前拒绝非法头时，Windows 可能报告 reset 或 abort；
                            # 是否符合预期仍由下面客户端退出码及结果检查决定。
                            break
            text = decode(p.communicate(timeout=10)[0])
            assert p.returncode == 0 and 'PASS ' in text, text
            return {'case': case, 'output': text.strip(), 'sent_request_hex': received.hex()}
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate()


# exe 启动真实 HTTP Server；output 是本轮隔离目录，上传文件只在其 tcp-uploads 子目录产生。
# 响应状态、业务回调计数和最终文件清理一起判断，不能用“收到 400”替代完整失败链检查。
def expect_continue(port):
    interim = b'HTTP/1.1 100 Continue\r\n\r\n'
    prefix = b'POST /test HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n'
    waiting = prefix + b'Connection: close\r\nExpect: 100-continue\r\n\r\n'
    # 同一批次解析两个请求。第二个临时响应必须等第一个正文结束后才能发出。
    with socket.create_connection(('127.0.0.1', port), timeout=5) as conn:
        conn.sendall(prefix + b'\r\nabc' + waiting + b'abc')
        with conn.makefile('rb') as source:
            headers, response = source.read().split(b'\r\n\r\n', 1)
        assert headers.startswith(b'HTTP/1.1 200 ') and b'Content-Length: 2' in headers, headers
        assert response.startswith(b'ok' + interim + b'HTTP/1.1 200 '), response
        assert response.endswith(b'\r\n\r\nok'), response
    # 只发头并等 100，确保没有依赖请求正文的死锁。
    with socket.create_connection(('127.0.0.1', port), timeout=5) as conn:
        conn.sendall(waiting)
        with conn.makefile('rb') as source:
            assert source.read(len(interim)) == interim
            conn.sendall(b'abc')
            assert source.read().startswith(b'HTTP/1.1 200 ')
    with socket.create_connection(('127.0.0.1', port), timeout=5) as conn:
        conn.sendall(prefix + b'Content-Length: 2\r\nExpect: 100-continue\r\n\r\n')
        with conn.makefile('rb') as source:
            assert source.readline().startswith(b'HTTP/1.1 400 ')


def server(exe, output):
    storage = output / 'tcp-uploads'
    storage.mkdir(exist_ok=False)
    p = subprocess.Popen([str(exe), 'server', str(storage)], cwd=HERE, stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
    messages, lines = queue.Queue(), []

    def drain():
        for raw in p.stdout:
            line = decode(raw).strip()
            lines.append(line)
            messages.put(line)

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()
    results = []
    try:
        ready = messages.get(timeout=7)
        assert ready.startswith('READY '), ready
        port = int(ready.split()[1])
        first_part = ('--b\r\nContent-Disposition: form-data; name="file"; filename="中文.bin"\r\n'
                      'Content-Type: application/octet-stream\r\n\r\nabc\r\n--b\r\n').encode()
        for case in ('length', 'length-bom', 'length-duplicate-bom', 'transfer', 'transfer-bom',
                     'text-bom', 'expect-quoted', 'multipart-valid', 'multipart-invalid', 'multipart-split'):
            valid = case in ('length', 'transfer', 'text-bom', 'expect-quoted', 'multipart-valid')
            body = b'abc'
            fields = b'Content-Length: 3\r\n'
            if case == 'length-bom':
                fields = b'Content-Length: \xef\xbb\xbf3\r\n'
            if case == 'length-duplicate-bom':
                fields += b'Content-Length: \xef\xbb\xbf3\r\n'
            if case.startswith('transfer'):
                fields = b'Transfer-Encoding: ' + (b'\xef\xbb\xbf' if case.endswith('bom') else b'') + b'chunked\r\n'
                body = b'3\r\nabc\r\n0\r\n\r\n'
            if case == 'expect-quoted':
                fields += 'Expect: x="中文"\r\n'.encode()
            if case == 'text-bom':
                fields += 'X-Text: \ufeff中文\r\n'.encode()
            if case.startswith('multipart'):
                body = first_part + b'Content-Disposition: form-data; name="text"\r\n'
                if not valid:
                    body += b'Bad Name: x\r\n'
                body += b'\r\ntwo\r\n--b--\r\n'
                fields = b'Content-Type: multipart/form-data; boundary=b\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n'
            prefix = b'POST /test HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n' + fields + b'\r\n'
            with socket.create_connection(('127.0.0.1', port), timeout=5) as conn:
                conn.settimeout(5)
                if case == 'multipart-split':
                    # 排除上一连接尚待清理的文件，只等待本次新建的上传文件。
                    previous_files = set(storage.iterdir())
                    conn.sendall(prefix + first_part)
                    deadline = time.monotonic() + 3
                    while not (set(storage.iterdir()) - previous_files) and time.monotonic() < deadline:
                        time.sleep(0.01)
                    assert set(storage.iterdir()) - previous_files, '失败前没有实际创建上传文件'
                    conn.sendall(body[len(first_part):])
                else:
                    conn.sendall(prefix + body)
                # 等待对端 EOF/reset，而非主动关连接后再判“已关闭”；超时意味着收尾未完成。
                response = bytearray()
                while True:
                    try:
                        data = conn.recv(4096)
                    except ConnectionResetError:
                        break
                    if not data:
                        break
                    response.extend(data)
                status = int(response.split(b' ', 2)[1])
                assert status == (200 if valid else 400), (case, bytes(response))
                if valid:
                    assert response.endswith(b'\r\n\r\nok'), (case, bytes(response))
                results.append({'case': 'server-' + case, 'status': status})
        expect_continue(port)
        results.append({'case': 'server-100-continue'})
    finally:
        if p.poll() is None:
            try:
                p.stdin.write(b'\n')
                p.stdin.flush()
                p.wait(timeout=8)
            except (OSError, subprocess.TimeoutExpired):
                p.kill()
                p.wait()
        reader.join(timeout=3)
        p.stdin.close()
        p.stdout.close()
        (output / 'server.log').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    # 原五个合法请求，加上管线两项和等待 100 后提交正文的一项。
    assert p.returncode == 0 and 'REQUESTS 8' in lines, lines
    assert not list(storage.iterdir()), '关闭后上传临时文件未清理'
    return results


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--targets', nargs='+', choices=['win64', 'win32', 'fpc64', 'delphi-linux64', 'fpc-linux64'], default=['win64', 'win32', 'fpc64'])
    parser.add_argument('--checked', action='store_true')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--executable', type=Path, help='在目标系统运行已交叉编译的二进制')
    options = parser.parse_args()
    if not options.label.replace('-', '').replace('_', '').isalnum():
        parser.error('invalid label')
    for target in (['native'] if options.executable else options.targets):
        # 此分支运行已有目标平台产物，保留其 build.json；不把宿主平台构建冒充目标运行。
        if options.executable:
            exe = options.executable.resolve(strict=True)
            output = exe.parent
        else:
            output = HERE / 'bin' / options.label / target
            exe = build(target, output, options.checked)
        if options.build_only:
            continue
        result = subprocess.run([str(exe)], cwd=HERE, capture_output=True, timeout=30, creationflags=NO_WINDOW)
        text = decode(result.stdout + result.stderr)
        (output / 'component.log').write_text(text, encoding='utf-8')
        if result.returncode or 'PASS ' not in text:
            raise RuntimeError(text)
        rows = [{'case': 'component', 'output': text.strip()}]
        print(target, text.strip(), flush=True)
        rows.extend(server(exe, output))
        print(target, 'server TCP', len(rows) - 1, 'passed', flush=True)
        for case in ('valid', 'cookie-values', 'opaque-response', 'empty-response', 'head-metadata', 'bad-response', 'length-bom', 'transfer-bom', 'invalid-field', 'invalid-utf16', 'invalid-method', 'invalid-query', 'invalid-query-name', 'invalid-query-tail', 'query-values'):
            rows.append(client(exe, case))
            print(target, case, rows[-1]['output'], flush=True)
        (output / 'results.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
