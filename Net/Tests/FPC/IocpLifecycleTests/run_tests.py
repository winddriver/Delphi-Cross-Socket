"""构建并以独立子进程运行真实 Windows IOCP 生命周期回归。"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
LAZBUILD = Path(r"D:\Design\FreePascal\lazarus\lazbuild.exe")
CASES = ["churn", "connection-cancel", "listen-close", "listen-cancel", "pending-stop", "extra-sentinel"]


def execute(args, timeout):
    # 子进程不启动其他进程；run 超时时会终止并等待本进程，不遗留后台服务。
    return subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                          timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)


def build(target, output, label, source_dir):
    output.mkdir(parents=True, exist_ok=True)
    units = HERE / "lib" / label / target
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc64":
        if source_dir:
            raise ValueError("--source-dir is only supported for Delphi baseline builds")
        args = [LAZBUILD, "--build-all", "--skip-dependencies", HERE / "IocpLifecycleTests.lpi"]
    else:
        arch = "win64" if target == "win64" else "win32"
        compiler = "dcc64.exe" if arch == "win64" else "dcc32.exe"
        paths = ([source_dir] if source_dir else []) + [REPO / "Net", REPO / "Utils",
                                                      DELPHI / "lib" / arch / "release"]
        args = [DELPHI / "bin" / compiler, "-Q", "-B", "-$O+",
                "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, paths)),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units),
                HERE / "IocpLifecycleTests.dpr"]
    result = execute(args, 120)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace"))
        raise RuntimeError("build failed: " + target)
    if target == "fpc64":
        shutil.copy2(HERE / "bin/fpc64/IocpLifecycleTests.exe", output / "IocpLifecycleTests.exe")


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", choices=["win64", "win32", "fpc64"],
                        default=["win64", "fpc64"])
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--label", default="current")
    parser.add_argument("--source-dir", type=Path,
                        help="Delphi 对照构建优先读取此目录下的 IOCP 单元，不覆盖工作区源码")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    options = parser.parse_args()
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must contain only letters, numbers, '-' or '_'")
    if options.source_dir:
        options.source_dir = options.source_dir.resolve()
        if not (options.source_dir / "Net.CrossSocket.Iocp.pas").is_file():
            parser.error("source-dir must contain Net.CrossSocket.Iocp.pas")
    failed = False
    for target in options.targets:
        output = HERE / "bin" / options.label / target
        if not options.no_build:
            build(target, output, options.label, options.source_dir)
            source = ((options.source_dir or (REPO / "Net")) / "Net.CrossSocket.Iocp.pas")
            (output / "source.json").write_text(json.dumps({
                "iocp_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "test_sha256": hashlib.sha256((HERE / "IocpLifecycleTests.lpr").read_bytes()).hexdigest(),
                "target": target,
            }, indent=2), encoding="utf-8")
            print("BUILD PASS", target, flush=True)
        if options.build_only:
            continue
        results = []
        for case in options.cases:
            try:
                result = execute([output / "IocpLifecycleTests.exe", case], 15)
                data = result.stdout + result.stderr
                code = result.returncode
            except subprocess.TimeoutExpired as error:
                data = (error.stdout or b"") + (error.stderr or b"") + b"\nTIMEOUT (child killed and reaped)\n"
                code = "timeout"
            (output / (case + ".log")).write_bytes(data)
            passed = code == 0 and b"PASS " in data
            failed |= not passed
            results.append({"case": case, "passed": passed, "exit_code": code})
            print(target, case, "PASS" if passed else "FAIL",
                  data.decode(errors="replace").strip(), flush=True)
        (output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
