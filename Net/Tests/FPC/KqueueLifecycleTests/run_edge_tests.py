"""Kqueue 真实注册失败及监听发布/在途关闭边界；Python 3.9 兼容。"""
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

CASES = ["register-failure", "listen-fetched-close", "listen-update-error", "listen-publish-error", "stop-from-io"]


def run(executable, case):
    process = subprocess.Popen([str(executable), case], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = []
    messages = queue.Queue()
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

    try:
        if case in ("register-failure", "listen-fetched-close", "stop-from-io"):
            port = int(wait("PORT ").split()[1])
            peer = socket.create_connection(("127.0.0.1", port), timeout=min(5, remaining()))
            if case == "stop-from-io":
                peer.settimeout(min(5, remaining()))
                peer.sendall(b"R")
                wait("STOP_REJECTED alive=1")
                reply = b""
                while len(reply) < 2:
                    part = peer.recv(2 - len(reply))
                    if not part:
                        raise AssertionError("自停止拒绝后连接未能回包")
                    reply += part
                if reply != b"OK":
                    raise AssertionError("自停止拒绝后的真实回包错误")
                wait("REPLIED")
            else:
                wait("GATED" if case == "register-failure" else "FETCHED_LISTEN")
            process.stdin.write(b"run\n")
            process.stdin.flush()
            peer.settimeout(min(5, remaining()))
            try:
                received = peer.recv(1)
            except ConnectionResetError:
                received = b""
            if received:
                raise AssertionError("关闭/注册失败后出现非预期应用字节")
        process.wait(timeout=remaining())
        reader.join(timeout=min(2, remaining()))
        if process.returncode != 0:
            raise AssertionError("原生断言失败，exit=" + str(process.returncode))
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
    counts = {key: int(value) for key, value in re.findall(r"(\w+)=(-?\d+)", result_line)}
    return {"case": case, "passed": not error, "returncode": process.returncode,
        "error": error, "counts": counts, "output": "\n".join(lines)}


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--report", type=Path, required=True)
    options = parser.parse_args()
    executable = options.executable.resolve(strict=True)
    results = []
    for case in options.cases:
        result = run(executable, case)
        results.append(result)
        print("PASS" if result["passed"] else "FAIL", case, result["counts"], result["error"], flush=True)
    options.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "platform": platform.platform(), "machine": platform.machine(),
        "python": sys.version, "results": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(not result["passed"] for result in results))
