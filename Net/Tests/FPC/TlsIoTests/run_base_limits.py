"""真实TCP/TLS与Base字节额度组合：正常回环、实际密文拒绝、逻辑队列取消。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import socket
import ssl
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
import run_tests as build_windows
import build_linux

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCE_NAMES = ["Net.CrossSocket.Base.pas", "Net.CrossSocket.Iocp.pas", "Net.CrossSocket.Epoll.pas",
                "Net.CrossSocket.Kqueue.pas", "Net.CrossSslSocket.OpenSSL.pas"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    paths = [REPO / "Net" / n for n in SOURCE_NAMES]
    paths += [HERE / "TlsIoTests.lpr", HERE / "TlsBaseLimitTests.inc", Path(__file__).resolve()]
    return {str(p.relative_to(REPO)): sha(p) for p in paths}


def read_exact(connection, count):
    parts = bytearray()
    while len(parts) < count:
        data = connection.recv(count - len(parts))
        if not data:
            raise RuntimeError("TLS EOF before expected plaintext")
        parts += data
    return bytes(parts)


def run(exe, options):
    rows = []
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        for limited in (False, True):
            mode = "base-tls-limited" if limited else "base-tls-unlimited"
            name = version.name + ("-limited" if limited else "-unlimited")
            process = subprocess.Popen([str(exe), mode, options.ssl, options.crypto,
                                        str(options.cert.resolve()), str(options.key.resolve())],
                                       cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            lines = []
            incoming = queue.Queue()

            def output_reader():
                for line in iter(process.stdout.readline, b""):
                    lines.append(line)
                    incoming.put(line)
                incoming.put(None)

            reader = threading.Thread(target=output_reader, daemon=True)
            reader.start()
            error = None
            payload = b""
            eof = False
            negotiated = None
            try:
                deadline = time.monotonic() + 10
                port = None
                while time.monotonic() < deadline:
                    line = incoming.get(timeout=max(0.01, deadline - time.monotonic()))
                    if line is None:
                        break
                    if line.startswith(b"PORT "):
                        port = int(line.split()[1])
                        break
                assert port is not None, b"".join(lines).decode(errors="replace")
                context = ssl.create_default_context(cafile=str(options.cert.resolve()))
                context.minimum_version = version
                context.maximum_version = version
                with socket.create_connection(("127.0.0.1", port), timeout=10) as raw:
                    with context.wrap_socket(raw, server_hostname="localhost") as peer:
                        negotiated = peer.version()
                        assert read_exact(peer, 4) == b"PING"
                        peer.sendall(b"PONG")
                        if not limited:
                            payload = read_exact(peer, 3 + 65536 + 4)
                            assert payload == b"ARM" + b"A" * 65536 + b"TAIL"
                            peer.sendall(b"DONE")
                        while True:
                            try:
                                data = peer.recv(4096)
                            except (ssl.SSLEOFError, ConnectionResetError):
                                eof = True
                                break
                            if not data:
                                eof = True
                                break
                            if limited:
                                payload += data
                            else:
                                raise AssertionError("unexpected plaintext after control payload")
                            assert len(payload) <= 3, "rejected ciphertext or later logical write reached peer"
                if limited:
                    assert payload == b"ARM", payload
                process.wait(timeout=10)
            except Exception as exception:
                error = repr(exception)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10)
                reader.join(timeout=2)
                process.stdout.close()
            text = b"".join(lines).decode(errors="replace")
            passed = error is None and eof and process.returncode == 0 and ("PASS " + mode) in text
            row = {"case": name, "tls": negotiated, "limited": limited, "passed": passed,
                   "exit_code": process.returncode, "error": error, "peer_eof": eof,
                   "peer_payload_bytes": len(payload), "peer_payload_sha256": hashlib.sha256(payload).hexdigest(),
                   "certificate_and_hostname_verified": True, "output": text}
            rows.append(row)
            (exe.parent / (name + ".log")).write_text(text, encoding="utf-8")
            print(exe.parent.name, name, "PASS" if passed else "FAIL", error or "", flush=True)
    report = {"binary": str(exe), "sha256": sha(exe), "ssl": options.ssl, "crypto": options.crypto,
              "certificate_sha256": sha(options.cert), "peer_openssl": ssl.OPENSSL_VERSION, "results": rows}
    (exe.parent / "base-results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return all(row["passed"] for row in rows)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="base-combination")
    parser.add_argument("--targets", nargs="+", default=["win64", "fpc64"],
                        choices=["win64", "fpc64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--run", nargs="*", type=Path)
    parser.add_argument("--cert", type=Path, required=True)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--ssl", default=str(REPO / "Net/Tools/OpenSSL/libssl-3-x64.dll")
                        if os.name == "nt" else "/lib/x86_64-linux-gnu/libssl.so.3")
    parser.add_argument("--crypto", default=str(REPO / "Net/Tools/OpenSSL/libcrypto-3-x64.dll")
                        if os.name == "nt" else "/lib/x86_64-linux-gnu/libcrypto.so.3")
    options = parser.parse_args()
    assert options.label.replace("-", "").replace("_", "").isalnum()
    options.cert = options.cert.resolve(strict=True)
    options.key = options.key.resolve(strict=True)
    passed = True
    if options.run:
        for path in options.run:
            passed = run(path.resolve(strict=True), options) and passed
    else:
        for target in options.targets:
            before = sources()
            if "linux" in target:
                build_linux.build(target, options.label, capacity=True)
            else:
                output = HERE / "bin" / options.label / target
                output.mkdir(parents=True, exist_ok=True)
                build_windows.build(target, output, REPO / "Net", selftest=False, capacity=True)
            assert sources() == before, "production/test source changed during build"
            out = HERE / "bin" / options.label / target
            (out / "base-source.json").write_text(json.dumps(before, indent=2), encoding="utf-8")
            if "linux" not in target:
                passed = run(out / "TlsIoTests.exe", options) and passed
    raise SystemExit(0 if passed else 1)
