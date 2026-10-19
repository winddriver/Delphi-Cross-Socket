"""真实本地 TCP + TLS 1.2/1.3 + WS；不替换物理发送或伪造 False。"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import queue
import socket
import ssl
import struct
import subprocess
import sys
import threading

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def exact(peer, count):
    result = b""
    while len(result) < count:
        data = peer.recv(count - len(result))
        if not data:
            raise EOFError("TLS 对端提前关闭")
        result += data
    return result


def frame(opcode, payload=b""):
    assert len(payload) < 126
    mask = os.urandom(4)
    return bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + bytes(
        value ^ mask[index % 4] for index, value in enumerate(payload))


def receive_frame(peer):
    first, second = exact(peer, 2)
    count = second & 127
    if count == 126:
        count = struct.unpack("!H", exact(peer, 2))[0]
    elif count == 127:
        count = struct.unpack("!Q", exact(peer, 8))[0]
    assert not second & 128, "服务端帧不应掩码"
    assert count < 128 * 1024, "非预期帧长度"
    return first & 15, exact(peer, count)


def run_case(executable, mode, version, ssl_library, crypto_library, cert, key):
    process = subprocess.Popen([str(executable), mode, str(ssl_library), str(crypto_library),
        str(cert), str(key), version], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    first_line = ""
    error = None
    output = ""
    negotiated = None
    wire_closed = False
    try:
        ready = queue.Queue()
        threading.Thread(target=lambda: ready.put(process.stdout.readline()), daemon=True).start()
        first_line = ready.get(timeout=8)
        assert first_line.startswith("READY "), first_line
        port = int(first_line.split()[1])
        context = ssl.create_default_context(cafile=str(cert))
        # 复用现有 CA:TRUE 测试证书，保持证书链和 localhost 名称检查。
        assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
        protocol = ssl.TLSVersion.TLSv1_2 if version == "TLSv1.2" else ssl.TLSVersion.TLSv1_3
        context.minimum_version = context.maximum_version = protocol
        with socket.create_connection(("127.0.0.1", port), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname="localhost") as peer:
                negotiated = peer.version()
                assert negotiated == version
                ws_key = base64.b64encode(os.urandom(16)).decode()
                peer.sendall((f"GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
                    f"Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {ws_key}\r\n\r\n").encode())
                response = b""
                while not response.endswith(b"\r\n\r\n"):
                    response += exact(peer, 1)
                    assert len(response) < 16384
                expected = base64.b64encode(hashlib.sha1((ws_key + MAGIC).encode()).digest())
                assert response.startswith(b"HTTP/1.1 101 ") and expected in response, response
                peer.sendall(frame(1, b"small"))
                assert receive_frame(peer) == (2, b"small")
                if mode == "normal":
                    peer.sendall(frame(8))
                    assert receive_frame(peer)[0] == 8
                else:
                    peer.sendall(frame(1, b"large"))
                try:
                    after = peer.recv(1)
                except ConnectionResetError:
                    after = b""
                assert after == b"", "超限后仍收到 WS 应用帧字节" if mode == "limit" else "Close 后未结束"
                wire_closed = True
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            output, _ = process.communicate("\n", timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()
            error = (error + "; " if error else "") + "子进程退出超时"
    output = first_line + output
    passed = error is None and process.returncode == 0 and f"PASS {mode}" in output
    return {"mode": mode, "version": version, "negotiated": negotiated,
        "wire_closed": wire_closed, "passed": passed, "returncode": process.returncode,
        "error": error, "output": output}


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--normal-only", action="store_true")
    parser.add_argument("--ssl")
    parser.add_argument("--crypto")
    parser.add_argument("--cert", type=Path, default=HERE.parent / "TlsCipherSuitesTests/bin/handshake-7da2cdf00d4746348af6e7865b93e945/rsa-cert.pem")
    parser.add_argument("--key", type=Path, default=HERE.parent / "TlsCipherSuitesTests/bin/handshake-7da2cdf00d4746348af6e7865b93e945/rsa-key.pem")
    options = parser.parse_args()
    executable = options.executable.resolve(strict=True)
    cert, key = options.cert.resolve(strict=True), options.key.resolve(strict=True)
    ssl_library = options.ssl or (REPO / "Net/Tools/OpenSSL/libssl-3-x64.dll" if os.name == "nt" else "libssl.so.3")
    crypto_library = options.crypto or (REPO / "Net/Tools/OpenSSL/libcrypto-3-x64.dll" if os.name == "nt" else "libcrypto.so.3")
    results = []
    for version in ["TLSv1.2", "TLSv1.3"]:
        for mode in (["normal"] if options.normal_only else ["normal", "limit"]):
            result = run_case(executable, mode, version, ssl_library, crypto_library, cert, key)
            results.append(result)
            print("PASS" if result["passed"] else "FAIL", version, mode, result["output"].strip(), result["error"] or "", flush=True)
    options.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "python_ssl": ssl.OPENSSL_VERSION, "native_ssl": str(ssl_library), "native_crypto": str(crypto_library),
        "cert_sha256": hashlib.sha256(cert.read_bytes()).hexdigest(), "results": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(not result["passed"] for result in results))
