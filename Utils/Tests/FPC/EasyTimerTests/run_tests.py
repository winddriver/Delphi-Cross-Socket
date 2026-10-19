"""独立进程验证 EasyTimer 行为与生命周期，每项最多十秒。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from build_common import timer_source

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
BASE_CASES = ["immediate", "delay", "pause-resume", "pause-after-first", "terminate-long",
              "external-destroy", "self-destroy", "self-destroy-exception", "exception-continues",
              "callback-terminate", "callback-wait", "heartbeat-idle", "heartbeat-paused",
              "heartbeat-callback", "finished-heartbeat", "create-destroy"]
ORIGINAL_CASES = BASE_CASES + ["constructor-failure", "batch-wait"]
CASES = ORIGINAL_CASES + ["interval-shorter", "interval-longer", "interval-paused",
                          "interval-initial", "interval-callback", "interval-nonpositive", "concurrent-create",
                          "huge-delay", "huge-interval"]


def build(target, label, production=False, polling=False):
    output = HERE / "bin" / (label + "-" + target)
    units = HERE / "lib" / (label + "-" + target)
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    timer = timer_source(HERE, REPO, polling)
    if target == "fpc-win64":
        args = [r"D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe", "-B",
                "-dCROSS_EASY_THREAD_TESTS", "-Fu" + str(REPO / "Net"),
                "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                r"-FuD:\Design\FreePascal\lazarus\components\lazutils\lib\x86_64-win64",
                "-Fi" + str(REPO), "-FE" + str(output), "-FU" + str(units),
                HERE / "EasyTimerTests.lpr"]
    else:
        delphi = Path(r"D:\Design\Delphi\D13.1")
        args = [delphi / "bin/dcc64.exe", "-Q", "-B", "-DCROSS_EASY_THREAD_TESTS",
                "-NSSystem;System.Win;Winapi", "-U" + ";".join(map(str, (
                    REPO / "Net", REPO / "Utils", delphi / "lib/win64/release"))),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units),
                HERE / "EasyTimerTests.dpr"]
    if production:
        args = [arg for arg in args if str(arg).lower() != "-dcross_easy_thread_tests"]
        if target == "fpc-win64":
            args.insert(1, "-uCROSS_EASY_THREAD_TESTS")
    if polling:
        if target == "fpc-win64":
            args.insert(1, "-Fu" + str(timer.parent))
        else:
            index = next(i for i, value in enumerate(args) if str(value).startswith("-U"))
            args[index] = "-U" + str(timer.parent) + ";" + str(args[index])[2:]
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-7000:])
        raise SystemExit(result.returncode)
    sources = [timer, REPO / "Utils/Utils.EasyThread.pas", HERE / "EasyTimerTests.lpr"]
    metadata = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return output / "EasyTimerTests.exe"


def run(executable, report, baseline=False, original=False, production=False):
    executable = Path(executable).resolve()
    results = []
    selected = BASE_CASES if baseline else ORIGINAL_CASES if original else CASES
    if production:
        selected = [case for case in selected if case != "constructor-failure"]
    for case in selected:
        try:
            result = subprocess.run([str(executable), case], cwd=HERE, capture_output=True,
                                    timeout=10, text=True, encoding="utf-8", errors="replace")
            record = dict(case=case, passed=result.returncode == 0,
                          returncode=result.returncode, output=result.stdout + result.stderr)
        except subprocess.TimeoutExpired as error:
            record = dict(case=case, passed=False, error=str(error))
        results.append(record)
        print(("PASS " if record["passed"] else "FAIL ") + case, flush=True)
    summary = dict(executable=str(executable), sha256=hashlib.sha256(executable.read_bytes()).hexdigest(),
                   passed=sum(r["passed"] for r in results), total=len(results), results=results)
    if report:
        Path(report).write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f'{summary["passed"]}/{summary["total"]}', flush=True)
    return summary["passed"] == summary["total"]


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", nargs="?")
    parser.add_argument("--build", choices=["delphi-win64", "fpc-win64"])
    parser.add_argument("--label", default="current")
    parser.add_argument("--report")
    parser.add_argument("--production", action="store_true")
    parser.add_argument("--polling", action="store_true", help="构建仅等待方式不同的正确性对照")
    parser.add_argument("--baseline", action="store_true", help="只运行不含构造故障注入的用例")
    parser.add_argument("--original", action="store_true", help="只运行原18项，不调用新增Interval属性")
    options = parser.parse_args()
    exe = build(options.build, options.label, options.production, options.polling) if options.build else options.executable
    if not exe:
        parser.error("指定可执行文件或 --build")
    raise SystemExit(0 if run(exe, options.report, options.baseline, options.original, options.production) else 1)
