"""在真实 macOS/FreeBSD TCP 上逐进程运行 Kqueue 析构回归；Python 3.9 兼容。"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import queue
import re
import socket
import subprocess
import sys
import threading
import time

CASES = ["idle-close", "queued-sends", "repeated-close", "queued-sends-drain",
         "fetched-read-close", "fetched-write-close", "fetched-read-write-close"]


def run(executable, case, send_count):
    process = subprocess.Popen([str(executable), case, str(send_count)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    messages = queue.Queue()
    lines = []
    peer = None
    error = ""
    deadline = time.monotonic() + 20

    def remaining():
        value = deadline - time.monotonic()
        if value <= 0:
            raise TimeoutError("独立子进程超过 20 秒")
        return value

    def collect():
        for raw in process.stdout:
            line = raw.decode("utf-8", errors="replace").strip()
            lines.append(line)
            messages.put(line)
        messages.put(None)

    reader = threading.Thread(target=collect, daemon=True)
    reader.start()

    def wait(prefix):
        # 两个 worker 的到达次序不同；先前已经输出的屏障不能被丢弃。
        for line in lines:
            if line.startswith(prefix):
                return line
        while True:
            line = messages.get(timeout=remaining())
            if line is None:
                raise RuntimeError("子进程提前退出: " + "; ".join(lines))
            if line.startswith("FAIL "):
                raise AssertionError(line)
            if line.startswith(prefix):
                return line

    def command(value):
        process.stdin.write((value + "\n").encode())
        process.stdin.flush()

    try:
        port = int(wait("PORT ").split()[1])
        peer = socket.create_connection(("127.0.0.1", port), timeout=min(5, remaining()))
        wait("GATED")
        command("run")
        if case == "queued-sends-drain":
            peer.settimeout(min(5, remaining()))
            received = bytearray()
            while len(received) < send_count:
                part = peer.recv(send_count - len(received))
                if not part:
                    raise AssertionError("成功发送的数据提前结束")
                received.extend(part)
            if received != b"Q" * send_count:
                raise AssertionError("实际发送内容不一致")
            wait("DRAINED")
            command("close")
        elif case.startswith("fetched-"):
            wait("PREPARED")
            if case != "fetched-read-close":
                # 先锁住已取出 WRITE 的 worker，再产生 READ，双 worker
                # 用例由原生端验证两个线程 ID 确实不同。
                wait("FETCHED_WRITE ")
            if case != "fetched-write-close":
                peer.sendall(b"R")
                wait("FETCHED_READ ")
            command("close")
            wait("CLOSED_FETCHED")
        # 初始三例不向连接写入数据，保持 READ 注册空闲；事件在途例
        # 则在 native hook 阻塞期间关闭，不能再发布收到的业务字节。
        peer.settimeout(min(5, remaining()))
        try:
            data = peer.recv(1)
        except ConnectionResetError:
            data = b""
        if data:
            raise AssertionError("关闭取消后仍发送了非预期应用字节")
        process.wait(timeout=remaining())
        reader.join(timeout=min(2, remaining()))
        if process.returncode != 0:
            raise AssertionError("原生析构断言失败，exit=" + str(process.returncode))
        if "PASS " + case not in lines:
            raise AssertionError("没有最终 PASS")
    except Exception as exc:
        error = type(exc).__name__ + ": " + str(exc)
    finally:
        if peer is not None:
            peer.close()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        reader.join(timeout=2)
        process.stdin.close()
        process.stdout.close()
    result_line = next((line for line in lines if line.startswith("RESULT ")), "")
    ref_line = next((line for line in lines if line.startswith("REFS ")), "")
    expected_sends = send_count if case in ("queued-sends", "queued-sends-drain") else (
        1 if case in ("fetched-write-close", "fetched-read-write-close") else 0)
    return {"case": case, "send_count": expected_sends,
        "passed": not error, "returncode": process.returncode, "error": error,
        "counts": {key: int(value) for key, value in re.findall(r"(\w+)=(-?\d+)", result_line)},
        "references": {key: int(value) for key, value in re.findall(r"(\w+)=(-?\d+)", ref_line)},
        "output": "\n".join(lines)}


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--send-count", type=int, default=64)
    parser.add_argument("--report", type=Path, required=True)
    options = parser.parse_args()
    if not 1 <= options.send_count <= 1024:
        parser.error("--send-count 必须在 1..1024")
    executable = options.executable.resolve(strict=True)
    results = []
    for case in options.cases:
        result = run(executable, case, options.send_count)
        results.append(result)
        print("PASS" if result["passed"] else "FAIL", case, result["counts"],
              result["references"], result["error"], flush=True)
    options.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "platform": platform.platform(), "machine": platform.machine(),
        "python": sys.version, "results": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(not result["passed"] for result in results))
