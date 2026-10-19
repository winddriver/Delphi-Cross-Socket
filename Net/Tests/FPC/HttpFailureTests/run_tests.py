"""构建并运行 HTTP 失败终态、响应顺序及真实断开回归。"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
from run_network import run as run_network

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
LAZBUILD = Path(r"D:\Design\FreePascal\lazarus\lazbuild.exe")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
CASES = (["parser-" + kind for kind in ("length", "conflict", "chunk", "crlf", "abort", "callback")] +
         ["reject-" + kind for kind in ("header", "bodydata", "bodyend", "reentry")] +
         ["memory-" + kind for kind in ("same", "split", "queued", "header", "limit", "sync")] +
         ["queue-" + kind for kind in ("late", "late-nocompress", "late-release", "callback", "request-end",
                                      "cancel-callback", "active-close", "source-error", "reentry-send", "reentry-close",
                                      "request-end-close", "duplicate-physical", "ready-close-race", "logger")] +
         ["tcp-" + kind for kind in ("length", "conflict", "chunk", "crlf", "same", "split", "normal")])
SOURCES = ["Net.CrossHttpParser.pas", "Net.CrossHttpServer.pas", "Net.CrossSocket.Base.pas",
           "Net.CrossSocket.Iocp.pas", "Net.CrossSocket.Epoll.pas", "Net.CrossSocket.Kqueue.pas"]


def build(target, output, label):
    output.mkdir(parents=True, exist_ok=True)
    units = HERE / "lib" / label / target
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc64":
        args = [LAZBUILD, "--build-all", "--skip-dependencies", HERE / "HttpFailureTests.lpi"]
    else:
        arch = "win64" if target == "win64" else "win32"
        compiler = "dcc64.exe" if arch == "win64" else "dcc32.exe"
        args = [DELPHI / "bin" / compiler, "-Q", "-B", "-$O+", "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [REPO / "Net", REPO / "Utils", CN,
                                           DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(output), "-N0" + str(units),
                HERE / "HttpFailureTests.dpr"]
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                            timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace"))
        raise RuntimeError("build failed: " + target)
    if target == "fpc64":
        shutil.copy2(HERE / "bin/fpc64/HttpFailureTests.exe", output / "HttpFailureTests.exe")
    metadata = {name: hashlib.sha256((REPO / "Net" / name).read_bytes()).hexdigest()
                for name in SOURCES}
    metadata["test_sha256"] = hashlib.sha256((HERE / "HttpFailureTests.lpr").read_bytes()).hexdigest()
    metadata["queue_test_sha256"] = hashlib.sha256((HERE / "HttpResponseQueueTests.inc").read_bytes()).hexdigest()
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print("BUILD PASS", target, flush=True)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", choices=["win64", "win32", "fpc64"],
                        default=["win64", "fpc64"])
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--label", default="current")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    options = parser.parse_args()
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("invalid label")
    failed = False
    for target in options.targets:
        output = HERE / "bin" / options.label / target
        if not options.no_build:
            build(target, output, options.label)
        if options.build_only:
            continue
        results = []
        for case in options.cases:
            mode, kind = case.split("-", 1)
            if mode == "tcp":
                passed, text = run_network(output / "HttpFailureTests.exe", kind)
            else:
                try:
                    result = subprocess.run([str(output / "HttpFailureTests.exe"), mode, kind],
                                            cwd=HERE, capture_output=True, timeout=15,
                                            creationflags=subprocess.CREATE_NO_WINDOW)
                    text = (result.stdout + result.stderr).decode("utf-8", errors="replace").strip()
                    passed = result.returncode == 0 and text.startswith("PASS ")
                except subprocess.TimeoutExpired:
                    text = "TIMEOUT (child killed and reaped)"
                    passed = False
            failed |= not passed
            (output / (case + ".log")).write_text(text, encoding="utf-8")
            results.append({"case": case, "passed": passed, "output": text})
            print(target, case, "PASS" if passed else "FAIL", text.replace("\n", "; "), flush=True)
        (output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
