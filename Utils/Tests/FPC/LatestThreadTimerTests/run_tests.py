"""新版Thread/Timer公开API与用户选定兼容行为；每项独立进程，有界等待。Python 3.9+。"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CASES = ["thread-api", "selected-self-wait", "thread-mixed", "thread-retained-control", "thread-capture-cleanup",
         "timer-hooks", "timer-timeout-fallback", "selected-nonpositive-interval",
         "timer-release-before", "timer-release-proc", "timer-release-after",
         "timer-base-release", "timer-install-after"]
SELECTED_BEHAVIOR = {"selected-self-wait", "selected-nonpositive-interval"}
D = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes(source):
    paths = [source / "Utils.EasyThread.pas", source / "Utils.EasyTimer.pas",
             REPO / "Utils/Utils.AnonymousThread.pas", REPO / "Utils/Utils.SyncObjs.pas",
             HERE / "LatestThreadTimerTests.lpr", HERE / "LatestThreadTimerTests.dpr"]
    # 另有工具单元同步时，记录完整项目依赖快照，避免将旧依赖结果冒充当前组合。
    paths += [path for path in (REPO / "Utils").glob("*.pas")
              if path.name not in ("Utils.EasyThread.pas", "Utils.EasyTimer.pas")]
    paths += list((REPO / "DelphiToFPC").glob("*.pas")) + [REPO / "zLib.inc"]
    return {str(path): digest(path) for path in paths}


def build(options):
    target = options.build
    source = options.source.resolve(strict=True) if options.source else REPO / "Utils"
    before = source_hashes(source)
    # 只开启输入源码已有的析构计数观察入口，不改写supplied源码。
    worker_observer = "GetEasyThreadDestroyedCountForTest" in (source / "Utils.EasyThread.pas").read_text(encoding="utf-8-sig")
    out = HERE / "bin" / options.label / target
    units = HERE / "lib" / options.label / target
    # 新标签不能覆盖旧基线；重跑现有二进制请直接传可执行文件。
    out.mkdir(parents=True, exist_ok=False)
    units.mkdir(parents=True, exist_ok=False)
    search = [source, REPO / "Utils", REPO / "DelphiToFPC", REPO / "Net"]
    native_mac = target == "fpc-macos-arm64"
    linux = target.endswith("linux64")
    if target.startswith("fpc-"):
        if native_mac:
            if sys.platform != "darwin" or not options.compiler or not options.fpc_config:
                raise RuntimeError("Mac原生构建需要在目标Mac传--compiler及已有--fpc-config；不修改配置")
            compiler = options.compiler.resolve(strict=True)
        else:
            compiler = options.compiler or FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe")
        args = [str(compiler)]
        if options.fpc_config:
            args.append("@" + str(options.fpc_config.resolve(strict=True)))
        args += ["-B", "-Tdarwin" if native_mac else "-Tlinux" if linux else "-Twin64"]
        if worker_observer:
            args.append("-dCROSS_EASY_THREAD_TESTS")
        if native_mac:
            args += ["-Paarch64"]
        args += ["-Fu" + str(path) for path in search]
        lazy = options.lazutils or (LAZ / ("components/lazutils" if linux else "components/lazutils/lib/x86_64-win64"))
        if lazy.is_dir():
            args += ["-Fu" + str(lazy)]
        args += ["-Fi" + str(REPO), "-FE" + str(out), "-FU" + str(units), str(HERE / "LatestThreadTimerTests.lpr")]
    else:
        arch = "linux64" if linux else "win32" if target == "delphi-win32" else "win64"
        compiler = options.compiler or D / "bin" / ("dcclinux64.exe" if linux else "dcc32.exe" if arch == "win32" else "dcc64.exe")
        args = [str(compiler), "-Q", "-B", "-NSSystem;" + ("Posix" if linux else "System.Win;Winapi"),
                "-U" + ";".join(str(path) for path in search + [CN, D / "lib" / arch / "release"]),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(out), "-N0" + str(units)]
        if worker_observer:
            args.append("-DCROSS_EASY_THREAD_TESTS")
        if linux:
            libraries = [D / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu",
                         SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args += ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(str(path) for path in libraries)]
        args += [str(HERE / "LatestThreadTimerTests.dpr")]
    process = subprocess.run(args, cwd=HERE, capture_output=True, timeout=120,
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (out / "build.log").write_bytes(process.stdout + process.stderr)
    metadata = {"recorded_utc": datetime.now(timezone.utc).isoformat(), "target": target,
                "command": args, "source_root": str(source), "sources": before,
                "worker_destruction_observer": worker_observer,
                "exit_code": process.returncode, "source_unchanged": source_hashes(source) == before}
    (out / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    if process.returncode:
        print((process.stdout + process.stderr).decode(errors="replace"))
        raise RuntimeError("build failed; preserve this label and inspect build.log")
    if not metadata["source_unchanged"]:
        raise RuntimeError("source changed during compilation")
    return out / ("LatestThreadTimerTests" if linux or native_mac else "LatestThreadTimerTests.exe")


def run(executable, cases, report, timeout):
    binary = executable.resolve(strict=True)
    report = report or binary.parent / "results.json"
    if report.exists():
        raise RuntimeError("refuse to overwrite existing result; supply a new --report")
    report.parent.mkdir(parents=True, exist_ok=True)
    log_dir = report.parent / (report.stem + "-logs")
    log_dir.mkdir(parents=True, exist_ok=False)
    rows = []
    for case in cases:
        try:
            process = subprocess.run([str(binary), case], cwd=binary.parent, capture_output=True,
                                     timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            text = (process.stdout + process.stderr).decode("utf-8", errors="replace")
            passed = process.returncode == 0 and ("PASS " + case) in text.splitlines()
            row = {"case": case, "passed": passed, "exit_code": process.returncode, "output": text}
        except subprocess.TimeoutExpired as error:
            text = ((error.stdout or b"") + (error.stderr or b"")).decode("utf-8", errors="replace")
            row = {"case": case, "passed": False, "exit_code": None,
                   "output": text + "\nchild timed out and was killed/reaped"}
        if case.startswith("timer-release-") or case in {"timer-hooks", "timer-timeout-fallback", "timer-base-release", "timer-install-after"}:
            row["worker_termination_observed"] = "OBSERVATION worker-termination=confirmed" in row["output"].splitlines()
            row["retired_memory_check_complete"] = row["passed"] and row["worker_termination_observed"]
            if not row["worker_termination_observed"]:
                row["observation_limit"] = "未观察到实际worker析构，PASS不能证明最后回调返回后无继续访问；无hook时隔离内存保留至子进程退出"
        row["category"] = "user-selected behavior" if case in SELECTED_BEHAVIOR else "API/lifetime invariant"
        rows.append(row)
        (log_dir / (case + ".log")).write_text(row["output"], encoding="utf-8")
        print(("PASS " if row["passed"] else "FAIL ") + case, flush=True)
    result = {"recorded_utc": datetime.now(timezone.utc).isoformat(), "binary": str(binary),
              "sha256": digest(binary), "platform": sys.platform, "passed": sum(row["passed"] for row in rows),
              "total": len(rows), "results": rows,
              "note": "supplied自等待抛错及非正周期拒绝，与用户明确选择不同；相关红例单列，不混同安全缺陷；释放用例须worker_termination_observed=true才完成终结后的内存检查"}
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print("{}/{}".format(result["passed"], result["total"]))
    return result["passed"] == result["total"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", nargs="?", type=Path)
    parser.add_argument("--build", choices=["delphi-win64", "delphi-win32", "fpc-win64", "delphi-linux64", "fpc-linux64", "fpc-macos-arm64"])
    parser.add_argument("--label", default="latest-api")
    parser.add_argument("--source", type=Path, help="已冻结supplied或合并后两个Utils单元的目录，始终只读")
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--fpc-config", type=Path)
    parser.add_argument("--lazutils", type=Path)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--timeout", type=float, default=15)
    options = parser.parse_args()
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must use letters, numbers, hyphen or underscore")
    if not options.build and not options.executable:
        parser.error("provide an executable or --build")
    if options.build_only and not options.build:
        parser.error("--build-only requires --build")
    binary = build(options) if options.build else options.executable
    if options.build_only:
        print("PASS build " + options.build)
        return 0
    return 0 if run(binary, options.cases, options.report, options.timeout) else 1


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    raise SystemExit(main())
