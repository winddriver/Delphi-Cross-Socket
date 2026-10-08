"""用原始 HTTP 请求头与真实回环连接验证客户端；仅使用 Python 标准库。"""

import argparse
import http.server
import subprocess
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        self.connection.settimeout(5)
        with self.server.lock:
            self.server.connections += 1
            self.connection_id = self.server.connections

    def log_message(self, *_args):
        pass

    def handle(self):
        try:
            super().handle()
        except ConnectionResetError:
            # 客户端结束测试时关闭连接；请求次数和复用另有断言。
            pass

    def handle_request(self):
        try:
            lengths = self.headers.get_all("Content-Length", [])
            encodings = self.headers.get_all("Transfer-Encoding", [])
            self.server.requests.append((self.command, self.path))
            if self.command == "HEAD":
                # 立即检查并响应，不等待错误声明的正文，以便旧实现能明确失败。
                assert not lengths, f"HEAD 仍有 Content-Length: {lengths}"
                assert not encodings, f"HEAD 仍有 Transfer-Encoding: {encodings}"
                assert not self.headers.get("Content-Encoding"), "HEAD 仍启用了正文压缩"
            elif self.command in ("POST", "PUT", "PATCH"):
                if self.server.mode == "post-chunk":
                    assert encodings == ["chunked"], f"分块头错误: {encodings}"
                    assert not lengths, "分块请求同时包含 Content-Length"
                    body = b""
                    while True:
                        size = int(self.rfile.readline().strip(), 16)
                        if size == 0:
                            assert self.rfile.readline() == b"\r\n"
                            break
                        body += self.rfile.read(size)
                        assert self.rfile.read(2) == b"\r\n"
                    assert body == b"abc", f"分块正文错误: {body!r}"
                else:
                    expected = b"abc" if self.server.mode == "post-body" else b""
                    assert lengths == [str(len(expected))], f"正文长度声明错误: {lengths}"
                    assert not encodings, f"意外分块头: {encodings}"
                    assert self.rfile.read(len(expected)) == expected
            elif self.command != "GET":
                raise AssertionError(f"意外方法: {self.command}")
        except Exception as error:
            self.server.errors.append(str(error))
        self.send_response(200)
        # HEAD 响应保留表示长度，但没有响应正文。
        self.send_header("Content-Length", "2")
        self.send_header("X-Connection-Id", str(self.connection_id))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(b"ok")
        self.wfile.flush()

    do_HEAD = do_GET = do_POST = do_PUT = do_PATCH = handle_request


def run(executable, mode):
    if mode == "remove":
        result = subprocess.run([executable, mode], capture_output=True, timeout=20)
        return result, []
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.mode = mode
    server.errors = []
    server.requests = []
    server.connections = 0
    server.lock = threading.Lock()
    worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
    worker.start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/{mode}"
        result = subprocess.run([executable, mode, url], capture_output=True, timeout=20)
    finally:
        server.shutdown()
        server.server_close()
        worker.join()
    method = "HEAD" if mode.startswith("head-") else mode.split("-")[0].upper()
    expected = [(method, f"/{mode}"), ("GET", f"/{mode}/after")]
    if server.requests != expected:
        server.errors.append(f"请求次数或顺序错误: {server.requests}")
    if server.connections != 1:
        server.errors.append(f"连接未复用: {server.connections}")
    return result, server.errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("executable")
    args = parser.parse_args()
    modes = ["remove", "head-bytes", "head-stream", "head-chunk", "head-empty",
             "head-headers", "head-gzip", "head-gzip-empty", "head-deflate-empty",
             "post-empty", "put-empty", "patch-empty", "post-body", "post-chunk"]
    failed = 0
    for mode in modes:
        result, errors = run(args.executable, mode)
        raw_output = result.stdout + result.stderr
        try:
            output = raw_output.decode("utf-8").strip()
        except UnicodeDecodeError:
            output = raw_output.decode("gb18030", errors="replace").strip()
        if result.returncode or errors:
            failed += 1
            print(f"FAIL: {mode}: {output}; {'; '.join(errors)}")
        else:
            print(f"PASS: {mode}")
    print(f"HttpHeadTests: {len(modes) - failed}/{len(modes)} passed")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
