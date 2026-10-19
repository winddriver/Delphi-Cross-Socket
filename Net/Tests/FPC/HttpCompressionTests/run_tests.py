"""独立进程验证真实压缩解析及原生分配生命周期，每项最多十秒。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CONTEXTS = ["server-length", "server-chunk", "client-length", "client-chunk", "client-close"]
CASES = [context + "-" + encoding + "-" + action
         for context in CONTEXTS for encoding in ("gzip", "deflate")
         for action in ("normal", "split", "truncated", "disconnect", "destroy")]
CASES += ["server-length-gzip-" + action for action in
          ("large", "empty", "corrupt", "failraise", "rejectbegin", "rejectdata", "rejectend",
           "throwbegin", "throwdata", "throwend", "limit")]
CASES += ["client-close-gzip-finishraise", "client-close-gzip-destroyraise"]
BASE_CASES = CASES.copy()
CASES += [context + "-gzip-" + action for context in CONTEXTS
          for action in ("headerfinish", "headerdestroy", "reuse")]
CASES += ["repeated"]
CASES += ["client-close-gzip-successabort", "client-close-deflate-successabort",
          "server-length-gzip-successabort"]
HOOK_CASES = ["server-length-gzip-initfail", "server-length-gzip-windowfail"]


def build(target, label, production=False):
    output = HERE / "bin" / (label + "-" + target)
    units = HERE / "lib" / (label + "-" + target)
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc-win64":
        args = [r"D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe", "-B",
                "-dCROSS_HTTP_COMPRESSION_TESTS", "-Fu" + str(REPO / "Net"),
                "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                r"-FuD:\Design\FreePascal\lazarus\components\lazutils\lib\x86_64-win64",
                "-Fi" + str(REPO), "-FE" + str(output), "-FU" + str(units),
                HERE / "HttpCompressionTests.lpr"]
    else:
        delphi = Path(r"D:\Design\Delphi\D13.1")
        args = [delphi / "bin/dcc64.exe", "-Q", "-B", "-DCROSS_HTTP_COMPRESSION_TESTS",
                "-NSSystem;System.Win;Winapi", "-U" + ";".join(map(str, (
                    REPO / "Net", REPO / "Utils", delphi / "lib/win64/release"))),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units),
                HERE / "HttpCompressionTests.dpr"]
    if production:
        args = [arg for arg in args if str(arg).lower() != "-dcross_http_compression_tests"]
        if target == "fpc-win64":
            args.insert(1, "-uCROSS_HTTP_COMPRESSION_TESTS")
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-7000:])
        raise SystemExit(result.returncode)
    sources = [REPO / "Net/Net.CrossHttpParser.pas", HERE / "HttpCompressionTests.lpr"]
    metadata = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return output / "HttpCompressionTests.exe"


def run(executable, report, production=False, baseline=False):
    executable = Path(executable).resolve()
    results = []
    for case in (BASE_CASES if baseline else CASES) + ([] if production else HOOK_CASES):
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
    parser.add_argument("--baseline", action="store_true", help="只重跑红基线包含的原 65 项")
    options = parser.parse_args()
    exe = build(options.build, options.label, options.production) if options.build else options.executable
    if not exe:
        parser.error("指定可执行文件或 --build")
    raise SystemExit(0 if run(exe, options.report, options.production, options.baseline) else 1)
