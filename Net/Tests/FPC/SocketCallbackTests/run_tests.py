"""运行真实 Socket 回调异常回归；进程、门控和 socket 操作均有超时。"""
import argparse
import queue
import socket
import subprocess
import sys
import threading
from pathlib import Path

CASES = ["batch", "accept", "sent-event", "send-callback", "pending-send", "cancel-sends", "cancel-error", "stop", "connect-callback", "connect-race", "send-close-race", "closed-state", "closed-send", "early-failure"]
CASES += ["listen-dns", "listen-socket", "listen-bind", "listen-listen", "listen-register", "listen-callback", "listen-register-callback"]
if sys.platform.startswith("linux"):
    CASES.append("register-failure")


def receive_closed(connection):
    data = b""
    while True:
        try:
            part = connection.recv(65536)
        except (ConnectionResetError, ConnectionAbortedError):
            part = b""
        if not part:
            return data
        data += part


def run(executable, case):
    listener = None
    args = [str(executable), case]
    if case in ("connect-callback", "early-failure", "listen-bind", "listen-callback"):
        listener = socket.socket()
        if case != "connect-callback" and sys.platform == "win32":
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        listener.bind(("0.0.0.0", 0))
        listener.listen()
        listener.settimeout(5)
        if case in ("connect-callback", "early-failure"):
            args.append(str(listener.getsockname()[1]))
    process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    messages = queue.Queue()
    lines = []
    peers = []

    def read_output():
        for line in process.stdout:
            text = line.decode("utf-8", errors="replace").strip()
            lines.append(text)
            messages.put(text)

    reader = threading.Thread(target=read_output)
    reader.start()

    def wait(prefix):
        while True:
            text = messages.get(timeout=5)
            assert not text.startswith("FAIL "), text
            if text.startswith(prefix):
                return text

    def command(text):
        process.stdin.write((text + "\n").encode())
        process.stdin.flush()

    def connect(port):
        peer = socket.create_connection(("127.0.0.1", port), timeout=3)
        peer.settimeout(3)
        peers.append(peer)
        wait("CONNECTED ")
        return peer

    def ping(peer):
        peer.sendall(b"G")
        assert peer.recv(1) == b"G", "unrelated connection did not echo"

    error = ""
    try:
        if case in ("connect-race", "send-close-race", "closed-state", "closed-send", "early-failure"):
            process.wait(timeout=15)
        elif case == "connect-callback":
            peer, _ = listener.accept()
            peers.append(peer)
            process.wait(timeout=8)
        else:
            port = int(wait("READY ").split()[1])
            if case == "batch":
                blocker, bad, good = [connect(port) for _ in range(3)]
                blocker.sendall(b"B")
                wait("BLOCKED")
                bad.sendall(b"X")
                command("bad-ready")
                wait("BAD_READY")
                good.sendall(b"G")
                command("release")
                assert good.recv(1) == b"G", "later event in ready batch was lost"
                receive_closed(bad)
                ping(connect(port))
                if sys.platform != "win32":
                    bad_cycle = next(line.split()[1] for line in lines if line.startswith("BAD "))
                    good_cycle = next(line.split()[1] for line in lines if line.startswith("GOOD "))
                    assert bad_cycle == good_cycle, "test did not exercise one epoll batch"
            elif case == "accept":
                bad = connect(port)
                good = connect(port)
                ping(good)
                receive_closed(bad)
            elif case in ("sent-event", "send-callback"):
                bad, good = connect(port), connect(port)
                bad.sendall(b"S")
                data = receive_closed(bad)
                assert data.startswith(b"A"), "first send was not completed"
                ping(good)
            elif case == "pending-send":
                peer = connect(port)
                peer.sendall(b"S")
                data = b""
                while len(data) < 2:
                    part = peer.recv(2 - len(data))
                    assert part, "pending connection was incorrectly closed"
                    data += part
                assert data == b"AB", data
                ping(peer)
            elif case in ("cancel-sends", "cancel-error"):
                bad = connect(port)
                bad.sendall(b"S")
                wait("BLOCKED")
                command("close" if case == "cancel-sends" else "cancel")
                receive_closed(bad)
            elif case == "register-failure":
                bad = connect(port)
                bad.sendall(b"B")
                wait("BLOCKED")
                command("register-failure")
                wait("QUEUE_UNLOCKED")
                receive_closed(bad)
            elif case == "stop":
                for _ in range(3):
                    connect(port)
            elif case.startswith("listen-"):
                peer = connect(port)
                ping(peer)
                if case not in ("listen-bind", "listen-callback"):
                    command(case)
                else:
                    command(("listen-bind " if case == "listen-bind" else "listen-throw ") +
                            str(listener.getsockname()[1]))
                wait("LISTEN_CHECKED")
                ping(peer)
                ping(connect(port))
            command("stop")
            process.wait(timeout=8)
    except Exception as failure:
        error = type(failure).__name__ + ": " + str(failure)
    finally:
        if process.poll() is None:
            try:
                command("release")
                command("stop")
                process.wait(timeout=3)
            except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
                process.kill()
                process.wait()
        reader.join(timeout=3)
        for peer in peers:
            peer.close()
        if listener:
            listener.close()
        process.stdin.close()
        process.stdout.close()
    if process.returncode:
        error += f"; server exit={process.returncode}"
    if case in ("sent-event", "send-callback", "pending-send", "cancel-sends", "cancel-error"):
        count = 3 if case == "cancel-sends" else (1 if case == "cancel-error" else 2)
        callbacks = [line.split()[1:] for line in lines if line.startswith("CALLBACK ")]
        for item in range(1, count + 1):
            results = [value for key, value in callbacks if key == str(item)]
            if len(results) != 1:
                error += f"; callback {item}: {results}"
            elif case in ("sent-event", "send-callback") and item == 1 and results != ["1"]:
                error += "; first successful callback changed to failure"
            elif case.startswith("cancel-") and results != ["0"]:
                error += f"; cancelled callback {item} was successful"
        if sys.platform != "win32" and case in ("sent-event", "send-callback"):
            if callbacks != [["1", "1"], ["2", "1"]]:
                error += "; completed epoll sends were not both reported successfully"
    if case == "stop" and len([line for line in lines if line.startswith("DISCONNECTED ")]) != 3:
        error += "; not all disconnect callbacks ran"
    if case == "register-failure":
        if "QUEUE_UNLOCKED" not in lines or "PROBE_CALLBACK 0" not in lines or "CALLBACK 1 0" not in lines:
            error += "; registration failure did not settle callbacks outside queue lock"
    if not any(line.startswith("STOPPED") for line in lines):
        error += "; stop did not finish"
    return not error, "\n".join(lines + ([error] if error else ["PASS " + case]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    failed = False
    results = []
    for case in options.cases:
        passed, output = run(options.executable.resolve(), case)
        failed |= not passed
        results.append({"case": case, "passed": passed, "output": output})
        print(case, "PASS" if passed else "FAIL", output.replace("\n", "; "), flush=True)
    if options.output:
        import json
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(json.dumps(results, indent=2), encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
