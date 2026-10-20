"""真实监听发布/关闭/停止回归；条件编译钩子只观察计数或暂停，不伪造完成结果。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import socket
import subprocess
import sys
import threading
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
D = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"
MAC_SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/MacOSX14.0.sdk"
UNITS = ["Net.CrossSocket.Base.pas", "Net.CrossSocket.Iocp.pas", "Net.CrossSocket.Epoll.pas", "Net.CrossSocket.Kqueue.pas"]
CASES = ["early-event", "close-before-publish", "stop-before-publish", "close-before-register",
         "stop-before-register", "restart-old-listen", "close-callback", "close-all-callback",
         "register-error", "publish-raises", "update-raises", "io-stop", "normal", "ipv6",
         "close-before-arm", "accept-before-publish-stop", "partial-accept-error", "late-accept-stop",
         "logger-raises", "logger-reenter", "accept-context-error"]
WINDOWS_ONLY = {"partial-accept-error", "late-accept-stop", "accept-context-error"}

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def snapshot(ref, label):
    source = HERE / "bin" / label / "production"
    source.mkdir(parents=True, exist_ok=True)
    for name in UNITS:
        data = subprocess.check_output(["git", "show", ref + ":Net/" + name], cwd=REPO)
        if name == "Net.CrossSocket.Iocp.pas" and b"GetPendingIoCountForTest" not in data:
            # 原始实现仅增加只读计数入口，不修改事件提交、派发或回收。
            content = data.decode("utf-8-sig").replace("\r\n", "\n")
            content = content.replace("    function ProcessIoEvent: Boolean; override;",
                "    function ProcessIoEvent: Boolean; override;\n"
                "    {$IFDEF CROSS_LISTEN_TESTS}\n"
                "    function GetPendingIoCountForTest: NativeInt;\n    {$ENDIF}")
            content = content.replace("{ TIocpCrossSocket }", "{ TIocpCrossSocket }\n\n"
                "{$IFDEF CROSS_LISTEN_TESTS}\n"
                "function TIocpCrossSocket.GetPendingIoCountForTest: NativeInt;\n"
                "begin\n  Result := AtomicCmpExchange(FPerIoDataCount, 0, 0);\nend;\n{$ENDIF}")
            data = b"\xef\xbb\xbf" + content.replace("\n", "\r\n").encode("utf-8")
        if name == "Net.CrossSocket.Base.pas" and b"CrossListenRegisteredForTest" not in data:
            content = data.decode("utf-8-sig").replace("\r\n", "\n")
            content = content.replace("implementation\n", "{$IFDEF CROSS_LISTEN_TESTS}\n"
                "type TCrossListenTestHook = reference to procedure(const AListen: ICrossListen);\n"
                "var CrossListenRegisteredForTest: TCrossListenTestHook;\n{$ENDIF}\n\nimplementation\n", 1)
            data = b"\xef\xbb\xbf" + content.replace("\n", "\r\n").encode()
        if name == "Net.CrossSocket.Iocp.pas" and b"CrossIocpAcceptReadyForTest" not in data:
            content = data.decode("utf-8-sig").replace("\r\n", "\n")
            content = content.replace("implementation\n", "{$IFDEF CROSS_LISTEN_TESTS}\n"
                "var CrossIocpAcceptReadyForTest: TCrossListenTestHook;\n{$ENDIF}\n\nimplementation\n", 1)
            content = content.replace("  LListen := APerIoData.CrossData as ICrossListen;",
                "  LListen := APerIoData.CrossData as ICrossListen;\n"
                "  {$IFDEF CROSS_LISTEN_TESTS}\n"
                "  if Assigned(CrossIocpAcceptReadyForTest) then CrossIocpAcceptReadyForTest(LListen);\n"
                "  {$ENDIF}", 1)
            data = b"\xef\xbb\xbf" + content.replace("\n", "\r\n").encode()
        path = source / name
        if path.exists():
            assert path.read_bytes() == data, "cannot replace existing baseline"
        else:
            path.write_bytes(data)
    return source

def build(target, label, source, heap=False):
    out = HERE / "bin" / label / target
    units = HERE / "lib" / label / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    linux, mac = "linux" in target, "osx" in target
    search = [source, REPO / "Net", REPO / "Utils", REPO / "DelphiToFPC"]
    inputs = [source / n for n in UNITS] + [HERE / "ListenLifecycleTests.lpr", HERE / "ListenLifecycleTests.dpr"]
    hashes = {str(p): sha(p) for p in inputs}
    if target.startswith("fpc"):
        if mac:
            if sys.platform != "darwin":
                raise RuntimeError("fpc-osxarm64 必须在 macOS 原生构建")
            native = Path.home() / "FreePascall/fpc/bin/aarch64-darwin"
            args = [native / "fpc", "@" + str(native / "fpc.cfg"), "-B", "-dCROSS_LISTEN_TESTS"]
            lazutils = Path.home() / "FreePascall/lazarus/components/lazutils"
        else:
            args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B",
                    "-Tlinux" if linux else "-Twin64", "-dCROSS_LISTEN_TESTS"]
            lazutils = LAZ / ("components/lazutils" if linux else "components/lazutils/lib/x86_64-win64")
        if heap:
            args += ["-gh"]
        args += ["-Fu" + str(p) for p in search]
        args += ["-Fu" + str(lazutils),
                 "-Fi" + str(REPO), "-FE" + str(out), "-FU" + str(units), HERE / "ListenLifecycleTests.lpr"]
    else:
        arch = target.removeprefix("delphi-") if mac else ("linux64" if linux else ("win32" if target == "win32" else "win64"))
        compiler = "dcc" + arch + ".exe" if mac else ("dcclinux64.exe" if linux else ("dcc32.exe" if arch == "win32" else "dcc64.exe"))
        rtl = D / "lib" / arch / "release"
        args = [D / "bin" / compiler, "-Q", "-B", "-DCROSS_LISTEN_TESTS",
                "-NSSystem;" + ("Posix" if linux or mac else "System.Win;Winapi"),
                "-U" + ";".join(map(str, search + [rtl])), "-I" + str(REPO), "-E" + str(out),
                ("-NU" if mac else "-N0") + str(units)]
        if linux:
            libs = [rtl, SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu", SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args += ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libs))]
        if mac:
            args += ["-O" + str(rtl), "--syslibroot:" + str(MAC_SDK),
                     "--libpath:" + ";".join(map(str, (rtl, MAC_SDK / "usr/lib"))),
                     "--frameworkpath:" + str(MAC_SDK / "System/Library/Frameworks")]
        args += [HERE / "ListenLifecycleTests.dpr"]
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (out / "build.log").write_bytes(result.stdout + result.stderr)
    (out / "command.json").write_text(json.dumps(list(map(str, args)), indent=2), encoding="utf-8")
    assert hashes == {str(p): sha(p) for p in inputs}, "sources changed during build"
    (out / "source.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")); raise RuntimeError("build failed")
    print("PASS build", target, flush=True)
    return out / ("ListenLifecycleTests" if linux or mac else "ListenLifecycleTests.exe")

def run_case(exe, case):
    proc = subprocess.Popen([str(exe), case], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    messages, output, peers = queue.Queue(), [], []
    def read():
        for line in proc.stdout:
            output.append(line)
            messages.put(line.strip())
        messages.put(None)
    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    deadline = time.monotonic() + 25
    def wait(prefix):
        while True:
            line = messages.get(timeout=max(0.1, deadline - time.monotonic()))
            if line is None or line.startswith("FAIL "):
                raise RuntimeError(line or "program exited")
            if line.startswith(prefix):
                return line
    def send(value):
        proc.stdin.write(value + "\n"); proc.stdin.flush()
    error = None
    try:
        if case == "early-event":
            port = int(wait("PUBLISH ").split()[1])
            peers.append(socket.create_connection(("127.0.0.1", port), 5))
            wait("BATCH")
            send("publish")
        if case in ("early-event", "normal", "ipv6", "io-stop", "accept-before-publish-stop", "late-accept-stop", "accept-context-error"):
            port = int(wait("READY ").split()[1])
            host = "::1" if case == "ipv6" else "127.0.0.1"
            count = 1 if case in ("early-event", "io-stop", "accept-before-publish-stop", "late-accept-stop") else 2
            if case == "accept-context-error":
                count = 3
            for _ in range(count):
                peers.append(socket.create_connection((host, port), 5))
            send("verify")
        wait("PASS " + case)
        proc.wait(timeout=max(1, deadline - time.monotonic()))
    except Exception as exc:
        error = str(exc)
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        reader.join(timeout=2)
        for peer in peers:
            peer.close()
        proc.stdin.close(); proc.stdout.close()
    data = "".join(output)
    passed = error is None and proc.returncode == 0
    (exe.parent / (case + ".log")).write_text(data, encoding="utf-8")
    print(case, "PASS" if passed else "FAIL", data.strip(), flush=True)
    return {"case": case, "passed": passed, "exit_code": proc.returncode, "error": error, "output": data}

def run(exe, cases):
    # Kqueue 的发布构建没有此错误日志；其锁内日志不属于本轮改动。
    applicable = [c for c in cases if not (sys.platform != 'win32' and c in WINDOWS_ONLY)
                  and not (sys.platform == 'darwin' and c in ('logger-reenter', 'logger-raises'))]
    rows = [run_case(exe, case) for case in applicable]
    (exe.parent / "results.json").write_text(json.dumps({"binary": str(exe), "sha256": sha(exe),
        "platform": sys.platform, "results": rows}, indent=2), encoding="utf-8")
    return all(row["passed"] for row in rows)

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--targets", nargs="+", default=["win64", "fpc64"],
        choices=["win64", "win32", "fpc64", "delphi-linux64", "fpc-linux64", "delphi-osxarm64", "delphi-osx64", "fpc-osxarm64"])
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--baseline-ref")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--heap-trace", action="store_true")
    parser.add_argument("--run", nargs="+", type=Path)
    opts = parser.parse_args()
    if opts.heap_trace and not opts.run and any(not t.startswith("fpc") for t in opts.targets):
        parser.error("--heap-trace 只适用于 FPC 目标")
    assert opts.label.replace("-", "").replace("_", "").isalnum()
    assert not (opts.baseline_ref and opts.source)
    ok = True
    if opts.run:
        for exe in opts.run:
            ok = run(exe.resolve(strict=True), opts.cases) and ok
    else:
        source = snapshot(opts.baseline_ref, opts.label) if opts.baseline_ref else opts.source.resolve() if opts.source else REPO / "Net"
        for target in opts.targets:
            exe = build(target, opts.label, source, opts.heap_trace)
            if not opts.build_only and "linux" not in target and "osx" not in target:
                ok = run(exe, opts.cases) and ok
    raise SystemExit(0 if ok else 1)
