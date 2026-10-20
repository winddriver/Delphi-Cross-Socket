"""真实TCP地址回退、关闭与回调回归；冻结生产源码并保存构建/运行证据。"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import threading

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
D = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"
MAC_SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/MacOSX14.0.sdk"
UNITS = ["Net.CrossSocket.Base.pas", "Net.CrossSocket.Iocp.pas", "Net.CrossSocket.Epoll.pas", "Net.CrossSocket.Kqueue.pas"]
SCENARIOS = ["v6-refused-v4-success", "v4-refused-v6-success", "all-refused", "callback-close",
             "external-close-published", "close-before-callback", "close-between-attempts",
             "register-failure-fallback", "callback-raises", "destroy-200",
             "unsupported-family-fallback", "close-during-resolution", "close-before-publish",
             "connect-after-close-all"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(ref, label):
    source = HERE / "bin" / label / "production"
    source.mkdir(parents=True, exist_ok=True)
    for name in UNITS:
        data = subprocess.check_output(["git", "show", ref + ":Net/" + name], cwd=REPO)
        path = source / name
        if path.exists():
            assert path.read_bytes() == data, "cannot replace existing baseline source"
        else:
            path.write_bytes(data)
    return source


def build(target, label, source, heap_trace=False, probe=False):
    if heap_trace and not target.startswith("fpc"):
        raise ValueError("--heap-trace requires an FPC target")
    program = "HostFallbackProbe" if probe else "ConnectFallbackTests"
    out = HERE / "bin" / label / target / ("host-probe" if probe else "suite")
    units = HERE / "lib" / label / target / ("host-probe" if probe else "suite")
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    paths = [source / n for n in UNITS] + [HERE / (program + ".lpr"), HERE / (program + ".dpr")]
    before = {str(p): sha(p) for p in paths}
    linux = "linux" in target
    mac = "osx" in target
    search = [source, REPO / "Net", REPO / "Utils", REPO / "DelphiToFPC"]
    if target.startswith("fpc"):
        args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B", "-Tlinux" if linux else "-Twin64"]
        if heap_trace:
            args += ["-gh"]
        args += ["-Fu" + str(p) for p in search]
        args += ["-Fu" + str(LAZ / ("components/lazutils" if linux else "components/lazutils/lib/x86_64-win64")),
                 "-Fi" + str(REPO), "-FE" + str(out), "-FU" + str(units), HERE / (program + ".lpr")]
    else:
        arch = target.removeprefix("delphi-") if mac else ("linux64" if linux else ("win32" if target == "win32" else "win64"))
        compiler = "dcc" + arch + ".exe" if mac else ("dcclinux64.exe" if linux else ("dcc32.exe" if arch == "win32" else "dcc64.exe"))
        args = [D / "bin" / compiler,
                "-Q", "-B", "-NSSystem;" + ("Posix" if linux or mac else "System.Win;Winapi"),
                "-U" + ";".join(map(str, search + [CN, D / "lib" / arch / "release"])),
                "-I" + str(REPO), "-E" + str(out), ("-NU" if mac else "-N0") + str(units)]
        if linux:
            libs = [D / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu",
                    SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args += ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libs))]
        if mac:
            rtl = D / "lib" / arch / "release"
            args += ["-O" + str(rtl), "--syslibroot:" + str(MAC_SDK),
                     "--libpath:" + ";".join(map(str, (rtl, MAC_SDK / "usr/lib"))),
                     "--frameworkpath:" + str(MAC_SDK / "System/Library/Frameworks")]
        args += [HERE / (program + ".dpr")]
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (out / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")); raise RuntimeError("build failed")
    assert before == {str(p): sha(p) for p in paths}, "source changed during build"
    (out / "source.json").write_text(json.dumps(before, indent=2), encoding="utf-8")
    (out / "command.json").write_text(json.dumps(list(map(str, args)), indent=2), encoding="utf-8")
    print("PASS build", target, flush=True)
    return out / (program if linux or mac else program + ".exe")


@contextlib.contextmanager
def endpoints():
    """Windows/Linux持有拒绝端口；Darwin须先关闭绑定才能收到ECONNREFUSED。"""
    sockets = []
    accepted = []
    errors = []
    stop = threading.Event()
    selector = selectors.DefaultSelector()
    worker = None
    try:
        for family, host, listen in [(socket.AF_INET, "127.0.0.1", True), (socket.AF_INET6, "::1", True),
                                     (socket.AF_INET, "127.0.0.1", False), (socket.AF_INET6, "::1", False)]:
            endpoint = socket.socket(family, socket.SOCK_STREAM)
            sockets.append(endpoint)
            if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                endpoint.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            if family == socket.AF_INET6:
                endpoint.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            endpoint.bind((host, 0))
            if listen:
                endpoint.listen(256)
                endpoint.setblocking(False)
                selector.register(endpoint, selectors.EVENT_READ)
        addresses = [(endpoint.family, endpoint.getsockname()) for endpoint in sockets]
        if sys.platform == "darwin":
            # Darwin对绑定但不监听端口不立即拒绝；保留地址后释放，再真实预检。
            for endpoint in sockets[2:]:
                endpoint.close()
        for family, address in addresses[2:]:
            with socket.socket(family, socket.SOCK_STREAM) as probe:
                probe.settimeout(8)
                try:
                    probe.connect(address)
                except ConnectionRefusedError:
                    pass
                else:
                    raise RuntimeError("refused-address precondition failed")

        def accept_connections():
            try:
                while not stop.is_set():
                    for key, _ in selector.select(0.1):
                        connection, _ = key.fileobj.accept()
                        # 保持服务端连接到被测子进程退出，避免远端主动断开干扰结果。
                        accepted.append(connection)
            except Exception as error:
                errors.append(repr(error))

        worker = threading.Thread(target=accept_connections)
        worker.start()
        yield [address[1] for _, address in addresses]
        if errors:
            raise RuntimeError("server failed: " + str(errors))
    finally:
        stop.set()
        if worker:
            worker.join(timeout=3)
        selector.close()
        for endpoint in accepted + sockets:
            endpoint.close()


def run(exe, scenarios):
    rows = []
    for scenario in scenarios:
        with endpoints() as ports:
            try:
                result = subprocess.run([str(exe), scenario] + list(map(str, ports)), capture_output=True, timeout=35,
                                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                data, code = result.stdout + result.stderr, result.returncode
            except subprocess.TimeoutExpired as error:
                data, code = (error.stdout or b"") + (error.stderr or b"") + b"\nPROCESS TIMEOUT\n", None
        (exe.parent / (scenario + ".log")).write_bytes(data)
        passed = code == 0 and ("PASS connect-fallback " + scenario).encode() in data
        rows.append({"scenario": scenario, "ports": ports, "refusal_prechecked": True,
                     "refusal_strategy": "released-and-prechecked" if sys.platform == "darwin" else "bound-not-listening",
                     "exit_code": code, "passed": passed, "output": data.decode(errors="replace")})
        print(exe.parent.name, data.decode(errors="replace").strip(), flush=True)
    (exe.parent / "results.json").write_text(json.dumps({"binary": str(exe), "sha256": sha(exe),
        "platform": sys.platform, "results": rows}, indent=2), encoding="utf-8")
    return all(row["passed"] for row in rows)


def run_probe(exe):
    """由被测Pascal程序报告系统解析顺序，第二地址族监听同一端口。"""
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    discovery = subprocess.run([str(exe), "discover"], capture_output=True, timeout=15, creationflags=flags)
    output = (discovery.stdout + discovery.stderr).decode(errors="replace")
    (exe.parent / "discover.log").write_text(output, encoding="utf-8")
    if discovery.returncode:
        raise RuntimeError("address discovery failed: " + output)
    families = next((line.removeprefix("FAMILIES ").strip() for line in output.splitlines()
                     if line.startswith("FAMILIES ")), "")
    if families not in ("46", "64"):
        print("SKIP host-fallback: localhost does not resolve both families:", families, flush=True)
        (exe.parent / "results.json").write_text(json.dumps({"binary": str(exe), "sha256": sha(exe),
            "platform": sys.platform, "skipped": True, "families": families}), encoding="utf-8")
        return True
    family_map = {"4": (socket.AF_INET, "127.0.0.1"), "6": (socket.AF_INET6, "::1")}
    with contextlib.ExitStack() as stack:
        endpoints = []
        port = 0
        for index, key in enumerate(families):
            family, host = family_map[key]
            endpoint = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
            if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                endpoint.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            if family == socket.AF_INET6:
                endpoint.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            endpoint.bind((host, port))
            port = endpoint.getsockname()[1]
            if index:
                endpoint.listen(8)
            endpoints.append(endpoint)
        if sys.platform == "darwin":
            endpoints[0].close()
        for index, key in enumerate(families):
            family, host = family_map[key]
            with socket.socket(family, socket.SOCK_STREAM) as check:
                check.settimeout(8)
                try:
                    check.connect((host, port))
                except ConnectionRefusedError:
                    if index:
                        raise RuntimeError("second address must accept connections")
                else:
                    if not index:
                        raise RuntimeError("first address must refuse connections")
        result = subprocess.run([str(exe), str(port), families], capture_output=True, timeout=20,
                                creationflags=flags)
    data = result.stdout + result.stderr
    passed = result.returncode == 0 and b"PASS host-fallback" in data
    (exe.parent / "host-fallback.log").write_bytes(data)
    (exe.parent / "results.json").write_text(json.dumps({"binary": str(exe), "sha256": sha(exe),
        "platform": sys.platform, "families": families, "port": port,
        "first_refusal_prechecked": True, "second_success_prechecked": True,
        "exit_code": result.returncode, "passed": passed,
        "output": data.decode(errors="replace")}, indent=2), encoding="utf-8")
    print(exe.parent.name, data.decode(errors="replace").strip(), flush=True)
    return passed


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", default=["win64", "fpc64"],
                        choices=["win64", "win32", "fpc64", "delphi-linux64", "fpc-linux64", "delphi-osxarm64", "delphi-osx64"])
    parser.add_argument("--label", required=True)
    parser.add_argument("--baseline-ref")
    parser.add_argument("--source", type=Path, help="使用已冻结的四单元快照")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--heap-trace", action="store_true", help="仅FPC构建：启用heaptrc并在退出时输出堆报告")
    parser.add_argument("--probe", action="store_true", help="运行不依赖解析测试入口的系统localhost回退探针")
    parser.add_argument("--run", nargs="+", type=Path)
    parser.add_argument("--scenarios", nargs="+", choices=SCENARIOS, default=SCENARIOS)
    options = parser.parse_args()
    if options.heap_trace and (options.run or any(not target.startswith("fpc") for target in options.targets)):
        parser.error("--heap-trace requires FPC build targets; use --run alone to run an existing heaptrc binary")
    assert options.label.replace("-", "").replace("_", "").isalnum()
    assert not (options.baseline_ref and options.source), "baseline and explicit source are mutually exclusive"
    ok = True
    if options.run:
        for exe in options.run:
            ok = (run_probe(exe.resolve(strict=True)) if options.probe else
                  run(exe.resolve(strict=True), options.scenarios)) and ok
    else:
        source = (snapshot(options.baseline_ref, options.label) if options.baseline_ref else
                  options.source.resolve(strict=True) if options.source else REPO / "Net")
        for target in options.targets:
            exe = build(target, options.label, source, options.heap_trace, options.probe)
            if not options.build_only and "linux" not in target and "osx" not in target:
                ok = (run_probe(exe) if options.probe else run(exe, options.scenarios)) and ok
    raise SystemExit(0 if ok else 1)
