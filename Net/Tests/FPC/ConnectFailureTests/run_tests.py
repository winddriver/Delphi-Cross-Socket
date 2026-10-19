"""真实独占本地端口迫使Bind失败；回调不抛异常，观察一次Connect的全部通知。"""
import argparse
import hashlib
import json
import socket
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
D = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"
UNITS = ["Net.CrossSocket.Base.pas", "Net.CrossSocket.Iocp.pas", "Net.CrossSocket.Epoll.pas", "Net.CrossSocket.Kqueue.pas"]


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


def build(target, label, source):
    out = HERE / "bin" / label / target
    units = HERE / "lib" / label / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    paths = [source / n for n in UNITS] + [HERE / "ConnectFailureTests.lpr"]
    before = {str(p): sha(p) for p in paths}
    linux = "linux" in target
    search = [source, REPO / "Net", REPO / "Utils", REPO / "DelphiToFPC"]
    if target.startswith("fpc"):
        args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B", "-Tlinux" if linux else "-Twin64"]
        args += ["-Fu" + str(p) for p in search]
        args += ["-Fu" + str(LAZ / ("components/lazutils" if linux else "components/lazutils/lib/x86_64-win64")),
                 "-Fi" + str(REPO), "-FE" + str(out), "-FU" + str(units), HERE / "ConnectFailureTests.lpr"]
    else:
        arch = "linux64" if linux else ("win32" if target == "win32" else "win64")
        args = [D / "bin" / ("dcclinux64.exe" if linux else ("dcc32.exe" if arch == "win32" else "dcc64.exe")),
                "-Q", "-B", "-NSSystem;" + ("Posix" if linux else "System.Win;Winapi"),
                "-U" + ";".join(map(str, search + [CN, D / "lib" / arch / "release"])),
                "-I" + str(REPO), "-E" + str(out), "-N0" + str(units)]
        if linux:
            libs = [D / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu",
                    SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args += ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libs))]
        args += [HERE / "ConnectFailureTests.dpr"]
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (out / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")); raise RuntimeError("build failed")
    assert before == {str(p): sha(p) for p in paths}, "source changed during build"
    (out / "source.json").write_text(json.dumps(before, indent=2), encoding="utf-8")
    print("PASS build", target, flush=True)
    return out / ("ConnectFailureTests" if linux else "ConnectFailureTests.exe")


def run(exe):
    rows = []
    for count in (1, 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as guard:
            if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                guard.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            # 被测Connect绑定通配本地地址；本机只占127.0.0.1不能阻止首次通配绑定。
            guard.bind(("0.0.0.0", 0))
            guard.listen()
            port = guard.getsockname()[1]
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                try:
                    probe.bind(("0.0.0.0", port))
                except OSError:
                    pass
                else:
                    raise RuntimeError("native bind precondition did not fail")
            result = subprocess.run([str(exe), str(count), str(port)], capture_output=True, timeout=20,
                                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        data = result.stdout + result.stderr
        (exe.parent / f"attempts-{count}.log").write_bytes(data)
        rows.append({"attempts": count, "parent_exclusive_port": port, "native_bind_precheck_failed": True,
                     "exit_code": result.returncode,
                     "passed": result.returncode == 0 and b"PASS connect-failure" in data,
                     "output": data.decode(errors="replace")})
        print(exe.parent.name, data.decode(errors="replace").strip(), flush=True)
    (exe.parent / "results.json").write_text(json.dumps({"binary": str(exe), "sha256": sha(exe),
                                                         "results": rows}, indent=2), encoding="utf-8")
    return all(row["passed"] for row in rows)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", default=["win64", "fpc64"],
                        choices=["win64", "win32", "fpc64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--label", required=True)
    parser.add_argument("--baseline-ref")
    parser.add_argument("--source", type=Path, help="使用已冻结的四单元快照")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--run", nargs="*", type=Path)
    options = parser.parse_args()
    assert options.label.replace("-", "").replace("_", "").isalnum()
    assert not (options.baseline_ref and options.source), "baseline and explicit source are mutually exclusive"
    source = (snapshot(options.baseline_ref, options.label) if options.baseline_ref else
              options.source.resolve(strict=True) if options.source else REPO / "Net")
    ok = True
    if options.run:
        for exe in options.run:
            ok = run(exe.resolve(strict=True)) and ok
    else:
        for target in options.targets:
            exe = build(target, options.label, source)
            if not options.build_only and "linux" not in target:
                ok = run(exe) and ok
    raise SystemExit(0 if ok else 1)
