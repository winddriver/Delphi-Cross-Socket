"""独立进程验证 chunked 定界、受限 trailer 和压缩资源，每项最多二十秒。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
KINDS = [
    'normal', 'trailer', 'trailer-ows', 'trailer-obstext',
    'protected-fields', 'zero-extension', 'chunk-extension', 'multiple',
    'limit-bytes', 'limit-fields', 'gzip-trailer', 'bad-size-lfcr',
    'bad-size-lf', 'bad-size-cr-text', 'bad-size-double-cr', 'bad-size-control',
    'bad-extension-control', 'bad-data-lfcr', 'bad-data-lf', 'bad-data-double-cr',
    'bad-data-cr-text', 'bad-zero-lfcr', 'bad-final-lfcr', 'bad-trailer-lf',
    'bad-trailer-cr', 'bad-trailer-fold', 'bad-trailer-name', 'bad-trailer-space',
    'bad-trailer-empty-name', 'bad-trailer-no-colon', 'bad-trailer-nul', 'bad-trailer-vtab',
    'bad-trailer-del', 'bad-limit-bytes', 'bad-limit-fields', 'bad-eof-size',
    'bad-eof-data', 'bad-eof-data-cr', 'bad-eof-trailer', 'bad-eof-empty',
    'bad-eof-final-cr', 'bad-gzip-truncated', 'bad-gzip-trailer', 'bad-callback-end',
    'bad-callback-data', 'bad-failure-callback',
]
BASE_CASES = [mode + "-" + kind for mode in ("server", "client") for kind in KINDS]
KINDS += ["reuse-bytes", "reuse-fields", "gzip-members-trailer", "bad-gzip-eof-trailer"]
CASES = [mode + "-" + kind for mode in ("server", "client") for kind in KINDS]


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
                HERE / "HttpChunkTests.lpr"]
    else:
        delphi = Path(r"D:\Design\Delphi\D13.1")
        args = [delphi / "bin/dcc64.exe", "-Q", "-B", "-DCROSS_HTTP_COMPRESSION_TESTS",
                "-NSSystem;System.Win;Winapi", "-U" + ";".join(map(str, (
                    REPO / "Net", REPO / "Utils", delphi / "lib/win64/release"))),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units),
                HERE / "HttpChunkTests.dpr"]
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
    sources = [REPO / "Net/Net.CrossHttpParser.pas", HERE / "HttpChunkTests.lpr"]
    metadata = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return output / "HttpChunkTests.exe"


def run(executable, report, baseline=False):
    executable = Path(executable).resolve()
    results = []
    for case in BASE_CASES if baseline else CASES:
        try:
            result = subprocess.run([str(executable), case], cwd=HERE, capture_output=True,
                                    timeout=20, text=True, encoding="utf-8", errors="replace")
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
    parser.add_argument("--baseline", action="store_true", help="只重跑原 92 项红基线")
    options = parser.parse_args()
    exe = build(options.build, options.label, options.production) if options.build else options.executable
    if not exe:
        parser.error("指定可执行文件或 --build")
    raise SystemExit(0 if run(exe, options.report, options.baseline) else 1)
