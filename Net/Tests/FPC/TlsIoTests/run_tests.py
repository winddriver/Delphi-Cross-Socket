"""构建并逐进程验证 TLS 输出顺序与挂起写；沿用相邻 OpenSslLoadTests 工具链。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe")
LAZ = Path(r"D:\Design\FreePascal\lazarus\components\lazutils\lib\x86_64-win64")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
MODES = ["order12", "order13", "want12", "capacity", "disconnected-error", "connected-error", "received-error",
         "active-close", "sync-reentry", "partial", "read-protocol", "keyupdate-order", "release-last", "write-callback-error", "read-order",
         "bad-tag12", "bad-tag13", "eof12", "eof13", "bad-tag-active", "eof-active",
         "bad-tag-sync", "eof-sync", "bad-tag-send-fail", "eof-send-fail", "terminal-disconnect-error", "handshake-tag12",
         "terminal-close-race", "terminal-release-last", "terminal-prefix-race", "terminal-prefix-io-fail", "terminal-log-reentry",
         "terminal-log-throw", "terminal-log-thread", "managed-wrap",
         "managed-clear-pending", "managed-clear-cipher", "managed-clear-plain"]
LIMIT_MODES = ["limits-write12", "limits-write13", "limits-close", "limits-want", "limits-reentry",
               "limits-cipher-bytes", "limits-cipher-count", "limits-receive12", "limits-receive13",
               "limits-overflow12", "limits-overflow13", "limits-receive-count", "limits-receive-active",
               "limits-receive-close", "limits-config", "limits-snapshot", "limits-wrap", "limits-concurrent", "limits-terminal",
               "limits-write-count", "limits-write-bytes", "limits-physical-failure", "limits-callback-failure", "limits-received-failure",
               "limits-handshake-barrier", "limits-terminal-active"]
MODES += LIMIT_MODES


def execute(args, timeout=90):
    return subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                          timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)


def build(target, output, source_root, selftest=True, benchmark=False, limits_baseline=False, capacity=False):
    units = HERE / "lib" / output.parent.name / target
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc64":
        args = [FPC, "-Twin64", "-B", "-Fu" + str(source_root), "-Fu" + str(REPO / "Net"),
                "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ), "-Fi" + str(REPO), "-FE" + str(output),
                "-FU" + str(units), HERE / "TlsIoTests.lpr"]
    else:
        arch = "win64" if target == "win64" else "win32"
        compiler = "dcc64.exe" if arch == "win64" else "dcc32.exe"
        args = [DELPHI / "bin" / compiler, "-Q", "-B", "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [source_root, REPO / "Net", REPO / "Utils", CN,
                                            DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units),
                HERE / "TlsIoTests.dpr"]
    if selftest:
        args.insert(1, "-dCROSS_OPENSSL_SELFTEST" if target == "fpc64" else "-DCROSS_OPENSSL_SELFTEST")
    if benchmark:
        args.insert(1, "-O2" if target == "fpc64" else "-$O+")
    if limits_baseline:
        args.insert(1, "-dTLS_LIMITS_BASELINE" if target == "fpc64" else "-DTLS_LIMITS_BASELINE")
    if capacity:
        args.insert(1, "-dCROSS_CAPACITY_TESTS" if target == "fpc64" else "-DCROSS_CAPACITY_TESTS")
    result = execute(args)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace"))
        raise RuntimeError("build failed " + target)
    (output / "source.json").write_text(json.dumps({
        "selftest": selftest,
        "limits_baseline": limits_baseline,
        "capacity_selftest": capacity,
        "benchmark_optimization": ("-O2" if target == "fpc64" else "-$O+") if benchmark else None,
        "tls_io_sha256": hashlib.sha256((source_root / "Net.CrossSslSocket.OpenSSL.pas").read_bytes()).hexdigest(),
        "test_sha256": hashlib.sha256((HERE / "TlsIoTests.lpr").read_bytes()).hexdigest(),
        "terminal_test_sha256": hashlib.sha256((HERE / "TlsTerminalTests.inc").read_bytes()).hexdigest(),
        "managed_test_sha256": hashlib.sha256((HERE / "TlsManagedQueueTests.inc").read_bytes()).hexdigest(),
        "limits_test_sha256": hashlib.sha256((HERE / "TlsQueueLimitTests.inc").read_bytes()).hexdigest(),
    }, indent=2), encoding="utf-8")


def main():
    sys.stdout.reconfigure(errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", choices=["win64", "win32", "fpc64"], default=["win64", "fpc64"])
    parser.add_argument("--label", default="current")
    parser.add_argument("--modes", nargs="+", choices=MODES, default=MODES)
    parser.add_argument("--ssl", type=Path)
    parser.add_argument("--crypto", type=Path)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--no-selftest", action="store_true", help="关闭调度钩子，运行其余正式构建场景")
    parser.add_argument("--limits-baseline", action="store_true", help="旧版没有新API：只省略配置调用，仍运行真实TLS与相同断言")
    parser.add_argument("--source-root", type=Path, default=REPO / "Net")
    options = parser.parse_args()
    if options.no_selftest:
        options.modes = [mode for mode in options.modes if not mode.startswith(("terminal-prefix-", "managed-clear-"))]
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label 只允许字母数字及横线")
    if bool(options.ssl) != bool(options.crypto):
        parser.error("ssl 与 crypto 必须同时指定")
    failed = False
    for target in options.targets:
        output = HERE / "bin" / options.label / target
        output.mkdir(parents=True, exist_ok=True)
        if not options.no_build:
            build(target, output, options.source_root.resolve(strict=True), not options.no_selftest,
                  limits_baseline=options.limits_baseline)
        libdir = REPO / "Net/Tools/OpenSSL"
        if target == "win32":
            libdir = Path(r"D:\Design\Delphi\VclFmxRtl\zLib\Net\OpenSSL.Libs\OpenSSL3\Windows\x86")
        suffix = "" if target == "win32" else "-x64"
        ssl = options.ssl or libdir / ("libssl-3" + suffix + ".dll")
        crypto = options.crypto or libdir / ("libcrypto-3" + suffix + ".dll")
        if not ssl.is_file() or not crypto.is_file():
            raise FileNotFoundError("需要匹配位数的 OpenSSL DLL")
        cert = output / "test-cert.pem"
        key = output / "test-key.pem"
        if not cert.exists():
            # 只生成本地短期测试证书，不访问系统证书配置。
            config = output / "certificate.cnf"
            if not config.exists():
                config.write_text("[req]\ndistinguished_name=subject\n[subject]\n", encoding="ascii")
            result = execute([REPO / "Net/Tools/OpenSSL/openssl.exe", "req", "-x509",
                              "-config", config, "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=localhost",
                              "-keyout", key, "-out", cert])
            (output / "certificate.log").write_bytes(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError("生成测试证书失败")
        results = []
        for mode in options.modes:
            try:
                result = execute([output / "TlsIoTests.exe", mode, ssl, crypto, cert, key], 20)
                data = result.stdout + result.stderr
                code = result.returncode
            except subprocess.TimeoutExpired as error:
                data = (error.stdout or b"") + b"\nTIMEOUT\n"
                code = "timeout"
            (output / (mode + ".log")).write_bytes(data)
            passed = code == 0 and ("PASS " + mode).encode() in data
            failed |= not passed
            results.append({"mode": mode, "passed": passed, "exit_code": code})
            print(target, mode, "PASS" if passed else "FAIL", data.decode(errors="replace").strip(), flush=True)
        (output / "results.json").write_text(json.dumps({
            "executable_sha256": hashlib.sha256((output / "TlsIoTests.exe").read_bytes()).hexdigest(),
            "ssl": str(ssl), "crypto": str(crypto), "results": results,
        }, indent=2), encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
