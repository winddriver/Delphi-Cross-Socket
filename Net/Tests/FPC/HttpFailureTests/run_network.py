"""以真实 TCP 验证错误响应后的关闭，以及 keep-alive / HEAD / pipeline。"""
import queue
import socket
import subprocess
import threading


def good(path, method="GET", close=False):
    return (f"{method} {path} HTTP/1.1\r\nHost: localhost\r\n" +
            ("Connection: close\r\n" if close else "") + "\r\n").encode()


def bad(kind):
    prefix = b"POST /bad HTTP/1.1\r\nHost: localhost\r\n"
    return {
        "length": prefix + b"Content-Length: abc\r\n\r\n",
        "conflict": prefix + b"Content-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n",
        "chunk": prefix + b"Transfer-Encoding: chunked\r\n\r\nxyz\r\n",
        "crlf": b"GET /bad HTTP/1.1\r\nHost: localhost\n\r\n",
    }[kind]


class Responses:
    def __init__(self, connection):
        self.connection = connection
        self.data = b""

    def response(self, head=False):
        while b"\r\n\r\n" not in self.data:
            part = self.connection.recv(65536)
            assert part, "EOF before response headers"
            self.data += part
        raw, self.data = self.data.split(b"\r\n\r\n", 1)
        lines = raw.split(b"\r\n")
        status = int(lines[0].split()[1])
        headers = dict(line.split(b":", 1) for line in lines[1:])
        headers = {key.lower(): value.strip() for key, value in headers.items()}
        assert b"transfer-encoding" not in headers, "unexpected transfer encoding"
        size = 0 if head else int(headers[b"content-length"])
        while len(self.data) < size:
            part = self.connection.recv(65536)
            assert part, "EOF before response body"
            self.data += part
        body, self.data = self.data[:size], self.data[size:]
        return status, headers, body

    def closed(self):
        assert not self.data, "unexpected response bytes after final response"
        try:
            tail = self.connection.recv(1)
        except (ConnectionResetError, ConnectionAbortedError):
            tail = b""
        assert tail == b"", "connection sent extra data instead of closing"


def run(executable, case):
    process = subprocess.Popen([str(executable), "server"] + (["body"] if case == "body" else []), stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    messages = queue.Queue()
    lines = []

    def read_output():
        for line in process.stdout:
            text = line.decode("utf-8", errors="replace").strip()
            lines.append(text)
            messages.put(text)

    reader = threading.Thread(target=read_output)
    reader.start()
    error = ""
    expected = 0
    try:
        ready = messages.get(timeout=8)
        assert ready.startswith("READY "), ready
        with socket.create_connection(("127.0.0.1", int(ready.split()[1])), timeout=3) as connection:
            connection.settimeout(2)
            responses = Responses(connection)
            if case == "body":
                connection.sendall(good('/204') + good('/304') + good('/head-gzip', 'HEAD')
                                   + good('/205') + good('/after', close=True))
                for expected_status, is_head in [(204, True), (304, True), (200, True), (205, False)]:
                    status, headers, body = responses.response(is_head)
                    assert status == expected_status and body == b'', (status, body)
                    if status in (204, 304):
                        assert b'content-length' not in headers, headers
                    if status == 200:
                        assert headers.get(b'content-encoding') == b'gzip', headers
                        assert b'content-length' not in headers, headers
                    if status == 205:
                        assert headers.get(b'content-length') == b'0', headers
                status, _, body = responses.response()
                assert status == 200 and body == b'/after', (status, body)
                responses.closed()
                expected = 5
            elif case == "normal":
                connection.sendall(good("/one") + good("/head", "HEAD") + good("/two"))
                for path, head in [(b"/one", False), (b"", True), (b"/two", False)]:
                    status, _, body = responses.response(head)
                    assert status == 200 and body == path, (status, body)
                connection.sendall(good("/again", close=True))
                status, _, body = responses.response()
                assert status == 200 and body == b"/again", (status, body)
                responses.closed()
                expected = 4
            else:
                payload = bad("length" if case in ("same", "split") else case)
                if case == "same":
                    payload += good("/tail")
                connection.sendall(payload)
                status, headers, _ = responses.response()
                assert status == 400, status
                assert headers.get(b"connection", b"").lower() == b"close", headers
                if case == "split":
                    try:
                        connection.sendall(good("/tail"))
                    except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                        pass
                responses.closed()
    except Exception as failure:
        error = type(failure).__name__ + ": " + str(failure)
    finally:
        try:
            if process.poll() is None:
                process.stdin.write(b"stop\n")
                process.stdin.flush()
                process.wait(timeout=5)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            process.kill()
            process.wait()
        reader.join(timeout=3)
        process.stdin.close()
        process.stdout.close()
    total = next((int(line.split()[1]) for line in lines if line.startswith("TOTAL ")), None)
    if total != expected:
        error += f"; business total={total}, expected={expected}"
    if process.returncode:
        error += f"; server exit={process.returncode}"
    return not error, "\n".join(lines + ([error] if error else ["PASS tcp-" + case]))


if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable")
    parser.add_argument("--cases", nargs="+",
                        choices=["length", "conflict", "chunk", "crlf", "same", "split", "normal", "body"],
                        default=["length", "conflict", "chunk", "crlf", "same", "split", "normal", "body"])
    options = parser.parse_args()
    failed = False
    for case in options.cases:
        passed, output = run(options.executable, case)
        failed |= not passed
        print(case, "PASS" if passed else "FAIL", output.replace("\n", "; "), flush=True)
    sys.exit(int(failed))
