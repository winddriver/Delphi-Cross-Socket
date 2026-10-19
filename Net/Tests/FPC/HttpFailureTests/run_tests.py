"""构建并运行 HTTP 失败终态、响应顺序及真实断开回归。"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

sys.dont_write_bytecode = True
from run_network import run as run_network

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
BODY_CASES = (["body-" + status + "-" + kind for status in ("204", "304", "head")
               for kind in ("status", "bytes", "chunk", "stream", "gzip", "gzip-stream", "auto")] +
              ["body-304-metadata", "body-304-metadata-bad", "body-304-metadata-conflict",
               "body-head-metadata", "body-head-identity-stream", "body-head204-bytes", "body-head304-bytes"] +
              ["body-head-auto-length", "body-head-gzip-length", "body-head-gzip-stream-length", "body-head-preencoded"] +
              ["body-" + status + "-" + kind for status in ("103", "101", "205", "connect", "200")
               for kind in ("bytes", "chunk", "gzip")])
CASES = (["parser-" + kind for kind in ("length", "conflict", "chunk", "crlf", "abort", "callback")] +
         ["reject-" + kind for kind in ("header", "bodydata", "bodyend", "reentry")] +
         ["memory-" + kind for kind in ("same", "split", "queued", "header", "limit", "sync")] +
         ["queue-" + kind for kind in ("late", "late-nocompress", "late-release", "callback", "request-end",
                                      "cancel-callback", "active-close", "source-error", "reentry-send", "reentry-close",
                                      "request-end-close", "duplicate-physical", "ready-close-race", "logger")] +
         ["tcp-" + kind for kind in ("length", "conflict", "chunk", "crlf", "same", "split", "normal", "body",
                                    "trailer", "trailer-gzip", "trailer-bad", "policy404", "policy500", "policyclose",
                                    "requestclose", "http10close", "http10keep", "capacity", "storage")]
         + BODY_CASES + ['policy-' + kind for kind in (
             '404', '500', 'header-close', 'header-list', 'header-duplicates', 'header-nontoken',
             'request-list', 'request-duplicates', 'http10-default', 'http10-list', 'http10-close',
             'snapshot-200', 'snapshot-204', 'snapshot-connection', 'snapshot-close')]
         + ['source-' + kind for kind in ('plain-first', 'plain-later', 'gzip-first', 'gzip-later',
                                         'plain-stream-eof', 'gzip-stream-eof', 'plain-stream-short', 'gzip-stream-short')]
         + ['storage-' + kind for kind in ('default', 'below', 'equal', 'above', 'chunked', 'gzip', 'form',
                                          'disconnect', 'disk-error', 'separate-path', 'limit-plain', 'limit-gzip', 'large-limit', 'large-header-limit')]
         + ['flush-' + kind for kind in ('plain', 'chunked', 'gzip')]
         + ['capacity-' + kind for kind in ('default', 'boundary', 'overflow', 'active', 'release', 'parsing', 'closed')])
SOURCES = ["Net.CrossHttpParser.pas", "Net.CrossHttpServer.pas", "Net.CrossSocket.Base.pas",
           "Net.CrossSocket.Iocp.pas", "Net.CrossSocket.Epoll.pas", "Net.CrossSocket.Kqueue.pas"]


def build(target, output, label, source_root=None):
    output.mkdir(parents=True, exist_ok=True)
    units = HERE / "lib" / label / target
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc64":
        search = ([source_root] if source_root else []) + [REPO / 'Net', REPO / 'Utils', REPO / 'DelphiToFPC', CN,
                                                         Path(r'D:\Design\FreePascal\lazarus\components\lazutils')]
        args = [Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe'), '-B']
        args += ['-Fu' + str(p) for p in search]
        args += ['-Fi' + str(REPO), '-FE' + str(output), '-FU' + str(units), HERE / 'HttpFailureTests.lpr']
    else:
        arch = "win64" if target == "win64" else "win32"
        compiler = "dcc64.exe" if arch == "win64" else "dcc32.exe"
        args = [DELPHI / "bin" / compiler, "-Q", "-B", "-$O+", "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, ([source_root] if source_root else []) + [REPO / "Net", REPO / "Utils", CN,
                                           DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(output), "-N0" + str(units),
                HERE / "HttpFailureTests.dpr"]
    server_source = source_root / 'Net.CrossHttpServer.pas' if source_root and (source_root / 'Net.CrossHttpServer.pas').exists() else REPO / 'Net/Net.CrossHttpServer.pas'
    if 'property BodyMemoryThreshold:' in server_source.read_text(encoding='utf-8-sig'):
        args.insert(1, '-dHTTP_BODY_STORAGE' if target == 'fpc64' else '-DHTTP_BODY_STORAGE')
    if 'property BodyTempPath:' in server_source.read_text(encoding='utf-8-sig'):
        args.insert(1, '-dHTTP_BODY_TEMP_PATH' if target == 'fpc64' else '-DHTTP_BODY_TEMP_PATH')
    if 'property MaxPendingRequests:' in server_source.read_text(encoding='utf-8-sig'):
        args.insert(1, '-dHTTP_QUEUE_LIMIT' if target == 'fpc64' else '-DHTTP_QUEUE_LIMIT')
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                            timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace"))
        raise RuntimeError("build failed: " + target)
    metadata = {name: hashlib.sha256(((source_root / name) if source_root and (source_root / name).exists()
                                     else REPO / "Net" / name).read_bytes()).hexdigest()
                for name in SOURCES}
    metadata["test_sha256"] = hashlib.sha256((HERE / "HttpFailureTests.lpr").read_bytes()).hexdigest()
    metadata["queue_test_sha256"] = hashlib.sha256((HERE / "HttpResponseQueueTests.inc").read_bytes()).hexdigest()
    metadata["body_test_sha256"] = hashlib.sha256((HERE / "HttpBodyPolicyTests.inc").read_bytes()).hexdigest()
    metadata["policy_test_sha256"] = hashlib.sha256((HERE / "HttpSendPolicyTests.inc").read_bytes()).hexdigest()
    metadata["storage_test_sha256"] = hashlib.sha256((HERE / "HttpBodyStorageTests.inc").read_bytes()).hexdigest()
    metadata["flush_test_sha256"] = hashlib.sha256((HERE / "HttpBodyFlushTests.inc").read_bytes()).hexdigest()
    metadata["capacity_test_sha256"] = hashlib.sha256((HERE / "HttpQueueLimitTests.inc").read_bytes()).hexdigest()
    metadata["Utils.IOUtils.pas"] = hashlib.sha256((REPO / 'Utils/Utils.IOUtils.pas').read_bytes()).hexdigest()
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
    parser.add_argument("--source-root", type=Path)
    options = parser.parse_args()
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("invalid label")
    failed = False
    for target in options.targets:
        output = HERE / "bin" / options.label / target
        if not options.no_build:
            build(target, output, options.label, options.source_root.resolve() if options.source_root else None)
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
                    raw = result.stdout + result.stderr
                    try:
                        text = raw.decode("utf-8").strip()
                    except UnicodeDecodeError:
                        text = raw.decode("gb18030", errors="replace").strip()
                    passed = result.returncode == 0 and f'PASS {mode} {kind}' in text.splitlines()
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
