"""用对应架构的 Mbed TLS 2.14.0 对象重编 Delphi 端点，并用独立 TLS 实现逐字节验证。"""
import argparse
from pathlib import Path
import queue
import socket
import ssl
import subprocess
import threading

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def receive(peer, count):
    data = bytearray()
    while len(data) < count:
        part = peer.recv(min(65536, count - len(data)))
        if not part:
            raise EOFError("TLS 连接提前结束")
        data.extend(part)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--objects", type=Path, required=True)
    parser.add_argument("--arch", choices=["win32", "win64"], default="win32")
    parser.add_argument("--delphi", type=Path, default=Path(r"D:\Design\Delphi\D13.1"))
    args = parser.parse_args()
    out = HERE / "bin" / ("mbed-io-" + args.arch)
    units = HERE / "lib" / ("mbed-io-" + args.arch)
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    compiler = args.delphi / "bin" / ("dcc32.exe" if args.arch == "win32" else "dcc64.exe")
    libs = [REPO / "Net", REPO / "Utils", args.delphi / "lib" / args.arch / "release"]
    subprocess.run([compiler, "-Q", "-B", "-DCROSS_MBEDTLS_SELFTEST", "-NSSystem;System.Win;Winapi", "-U" + ";".join(map(str, libs)),
                    "-I" + str(REPO), "-O" + str(args.objects.resolve(strict=True)),
                    "-E" + str(out), "-N0" + str(units), HERE / "MbedIoRegression.dpr"],
                   cwd=out, check=True, timeout=90)
    keys = REPO / "Net/Tools/OpenSSL/keys"
    child = subprocess.Popen([out / "MbedIoRegression.exe", keys / "server.crt", keys / "server.key"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = queue.Queue()
    reader = threading.Thread(target=lambda: [lines.put(s) for s in child.stdout], daemon=True)
    reader.start()
    try:
        line = lines.get(timeout=8)
        if not line.startswith(b"PORT "):
            raise RuntimeError(line)
        address = ("127.0.0.1", int(line.split()[1]))
        with socket.create_connection(address, timeout=5) as raw:
            # 读到 TCP 连接已被接受再结束未完成的握手。
            raw.sendall(b"\x16")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        context.maximum_version = ssl.TLSVersion.TLSv1_2
        payload = bytes((i * 17 + i // 1024) % 256 for i in range(262177))
        with socket.create_connection(address, timeout=8) as raw, context.wrap_socket(raw) as peer:
            assert lines.get(timeout=5).strip() == b"WAIT_READ"
            peer.sendall(payload[:1])
            assert receive(peer, 1) == b"*", "握手前接纳的写入丢失"
            peer.sendall(payload[1:])
            assert receive(peer, len(payload)) == payload, "多记录收发字节发生变化"
            peer.sendall(b"P")
            assert lines.get(timeout=5).strip() == b"PRESSURE_CLOSED"
        with socket.create_connection(address, timeout=8) as raw, context.wrap_socket(raw):
            # 已连接的逻辑写挂在 WANT_READ；断开不得漏掉它的失败通知。
            assert lines.get(timeout=5).strip() == b"WAIT_READ"
        child.stdin.write(b"stop\n")
        child.stdin.flush()
        assert child.wait(timeout=6) == 0
        reader.join(timeout=2)
        assert b"COUNTS 1 2 1 0 262177" in lines.get(timeout=2)
        print("PASS Mbed TLS TLSv1.2: 262177 bytes in both directions; WANT_READ retry and cancellation")
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        child.stdin.close()
        child.stdout.close()


if __name__ == "__main__":
    main()
