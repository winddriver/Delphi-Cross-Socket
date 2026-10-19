"""构建并逐进程验证 SSL 信息与托管记录；沿用相邻 OpenSslLoadTests 工具链。"""
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
MODES = ["no-key", "failed-key", "tls12", "tls13", "rsa-no-key", "key-error", "ssl-reset", "cert-reset"]


def execute(args, timeout=90):
    return subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                          timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)


def build(target, output):
    units = HERE / "lib" / output.parent.name / target
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc64":
        args = [FPC, "-Twin64", "-B", "-Fu" + str(REPO / "Net"),
                "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ), "-Fi" + str(REPO), "-FE" + str(output),
                "-FU" + str(units), HERE / "SslInfoTests.lpr"]
    else:
        arch = "win64" if target == "win64" else "win32"
        compiler = "dcc64.exe" if arch == "win64" else "dcc32.exe"
        args = [DELPHI / "bin" / compiler, "-Q", "-B", "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [REPO / "Net", REPO / "Utils", CN,
                                            DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units),
                HERE / "SslInfoTests.dpr"]
    result = execute(args)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace"))
        raise RuntimeError("build failed " + target)
    (output / "source.json").write_text(json.dumps({
        "openssl_sha256": hashlib.sha256((REPO / "Net/Net.OpenSSL.pas").read_bytes()).hexdigest(),
        "test_sha256": hashlib.sha256((HERE / "SslInfoTests.lpr").read_bytes()).hexdigest(),
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
    options = parser.parse_args()
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label 只允许字母数字及横线")
    if bool(options.ssl) != bool(options.crypto):
        parser.error("ssl 与 crypto 必须同时指定")
    failed = False
    for target in options.targets:
        output = HERE / "bin" / options.label / target
        output.mkdir(parents=True, exist_ok=True)
        if not options.no_build:
            build(target, output)
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
                result = execute([output / "SslInfoTests.exe", mode, ssl, crypto, cert, key], 20)
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
            "ssl": str(ssl), "crypto": str(crypto), "results": results,
        }, indent=2), encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
