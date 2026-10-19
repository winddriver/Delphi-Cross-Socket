"""复用 HttpHeadTests 客户端，验证临时响应不会完成请求或污染连接复用。"""
import argparse
import gzip
import hashlib
import http.server
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading

CASES = [
    ("continue", "post-empty", [100], False, False),
    ("hints", "post-empty", [103], False, False),
    ("multiple", "post-empty", [100, 102, 103, 103], False, False),
    ("fragmented", "post-empty", [103, 100], True, False),
    ("head-hints", "head-empty", [103, 103], False, False),
    ("post-continue", "post-body", [100], False, False),
    ("hints-gzip", "post-empty", [103], False, True),
    ("borrowed-stream", "post-response-stream", [100, 103], False, True),
    ("hints-gzip-members", "post-empty", [103], False, True),
]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        self.connection.settimeout(5)
        self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with self.server.lock:
            self.server.connections += 1
            self.connection_id = self.server.connections

    def log_message(self, *_args):
        pass

    def handle(self):
        try:
            super().handle()
        except (ConnectionError, TimeoutError):
            # 未修复客户端可能在收到第一个 1xx 后就结束；由最终结果断言报错。
            pass

    def handle_request(self):
        with self.server.lock:
            self.server.requests.append((self.command, self.path))
        initial = not self.path.endswith("/after")
        if initial:
            status_text = {100: "Continue", 102: "Processing", 103: "Early Hints"}
            interim = b"".join(
                f"HTTP/1.1 {code} {status_text[code]}\r\nX-Interim: yes\r\n\r\n".encode()
                for code in self.server.codes
            )
            # POST 在读取正文前发送 100，覆盖仍在发送请求时收到临时响应。
            if self.server.fragmented:
                for value in interim:
                    self.connection.sendall(bytes([value]))
            else:
                self.connection.sendall(interim)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        expected = b"abc" if initial and self.server.mode == "post-body" else b""
        if body != expected:
            self.server.errors.append(f"request body mismatch: {body!r}")
        payload = b"ok"
        compressed = initial and self.server.compressed
        if compressed:
            if self.path == '/hints-gzip-members':
                payload = gzip.compress(b'o', mtime=0) + gzip.compress(b'k', mtime=0)
            else:
                payload = gzip.compress(payload, mtime=0)
        final = (f"HTTP/1.1 200 OK\r\nContent-Length: {len(payload)}\r\n"
                 f"X-Connection-Id: {self.connection_id}\r\n" +
                 ("Content-Encoding: gzip\r\n" if compressed else "") + "\r\n").encode()
        if self.command != "HEAD":
            final += payload
        if initial and self.server.fragmented:
            for value in final:
                self.connection.sendall(bytes([value]))
        else:
            self.connection.sendall(final)

    do_POST = do_HEAD = do_GET = handle_request


def run(executable, case):
    name, mode, codes, fragmented, compressed = case
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.codes, server.mode = codes, mode
    server.fragmented, server.compressed = fragmented, compressed
    server.requests, server.errors, server.connections = [], [], 0
    server.lock = threading.Lock()
    worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
    worker.start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/{name}"
        try:
            result = subprocess.run([str(executable), mode, url], capture_output=True, timeout=20,
                                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            raw = result.stdout + result.stderr
            try:
                detail = raw.decode("utf-8").strip()
            except UnicodeDecodeError:
                detail = raw.decode("gb18030", errors="replace").strip()
            passed = result.returncode == 0
        except subprocess.TimeoutExpired:
            passed, detail = False, "TIMEOUT (child killed and reaped)"
    finally:
        server.shutdown()
        server.server_close()
        worker.join()
    method = "HEAD" if mode.startswith("head-") else "POST"
    expected = [(method, "/" + name), ("GET", "/" + name + "/after")]
    if server.requests != expected:
        server.errors.append(f"request order: {server.requests}")
    if server.connections != 1:
        server.errors.append(f"connection count: {server.connections}")
    return {"case": name, "passed": passed and not server.errors,
            "output": detail, "errors": server.errors}


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path)
    options = parser.parse_args()
    executable = options.executable.resolve(strict=True)
    results = [run(executable, case) for case in CASES]
    for result in results:
        print("PASS" if result["passed"] else "FAIL", result["case"],
              result["output"], "; ".join(result["errors"]))
    report = {"executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
              "passed": sum(item["passed"] for item in results), "total": len(results),
              "results": results}
    if options.report:
        options.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Interim responses: {report['passed']}/{report['total']}")
    return int(report["passed"] != report["total"])


if __name__ == "__main__":
    raise SystemExit(main())
