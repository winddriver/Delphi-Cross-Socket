"""沿用相邻测试的工具链；所有产物写入 bin/lib，不修改全局配置。"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
D = Path(r"D:\Design\Delphi\D13.1")
F = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"
MODES = ["missing-crypto", "partial", "missing-proc", "failure-exit", "auto-name",
         "references", "init-ssl-fail", "init-crypto-fail", "unexpected",
         "context-fail", "concurrent", "load-unload", "failed-owner"]


def run(args, log, cwd=REPO):
    p = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, timeout=90)
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_bytes(p.stdout + p.stderr)
    if p.returncode:
        print((p.stdout + p.stderr).decode(errors="replace"))
        raise RuntimeError(f"exit={p.returncode}: {args[0]}")
    return p.stdout.decode(errors="replace")


def check_resets():
    source = (REPO / "Net/Net.OpenSSL.pas").read_text(encoding="utf-8-sig")
    declared = source.split("{$IFNDEF __SSL_STATIC__}", 1)[1].split("{$ELSE __SSL_STATIC__}", 1)[0]
    names = set(re.findall(r"^\s{2}(\w+)\s*:\s*(?:function|procedure)\b", declared, re.M))
    loader = source.split("class procedure TSSLTools.LoadSslLibs;", 1)[1].split("class function TSSLTools.GetLibCRYPTO", 1)[0]
    names.update(re.findall(r"@(\w+)\s*:=", loader))
    clear = source.split("class procedure TSSLTools._ClearSslProcs;", 1)[1].split("\nend;", 1)[0]
    resets = set(re.findall(r"@(\w+)\s*:=\s*nil", clear))
    if names != resets:
        raise RuntimeError(f"函数表清理不完整: missing={names-resets}, extra={resets-names}")
    print(f"PASS {len(names)} dynamic function resets", flush=True)


def build(target):
    out = HERE / "bin" / target
    units = HERE / "lib" / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    for name in ("IncompleteCrypto", "OpenSslLoadTests"):
        if target.startswith("fpc"):
            linux = target.endswith("linux64")
            args = [F / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-Tlinux" if linux else "-Twin64", "-B", "-dNEW_SSL_LOAD", "-dCROSS_OPENSSL_SELFTEST",
                    "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"),
                    "-Fu" + str(REPO / "DelphiToFPC"),
                    "-Fu" + str(LAZ / ("components/lazutils" if linux else "components/lazutils/lib/x86_64-win64")),
                    "-Fi" + str(REPO), "-FE" + str(out), "-FU" + str(units), HERE / (name + ".lpr")]
            if linux and name == "IncompleteCrypto":
                # FPC 无 libc 的共享库会把加载器作为链接输入，须使用宿主可读的交叉库路径。
                args[1:1] = [r"-FLD:\Design\FreePascal\cross\lib\x86_64-linux\ld-linux-x86-64.so.2"]
        else:
            arch = target.removeprefix("delphi-")
            compiler = {"win32": "dcc32.exe", "win64": "dcc64.exe", "linux64": "dcclinux64.exe"}[arch]
            args = [D / "bin" / compiler, "-Q", "-B",
                    "-DNEW_SSL_LOAD;CROSS_OPENSSL_SELFTEST", "-NSSystem;System.Win;Winapi",
                    "-U" + ";".join(map(str, (REPO / "Net", REPO / "Utils", CN, D / "lib" / arch / "release"))),
                    "-I" + str(REPO), "-E" + str(out), "-N0" + str(units), HERE / (name + ".dpr")]
            if arch == "linux64":
                libs = [D / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu",
                        SDK / "lib/x86_64-linux-gnu", SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
                args[1:1] = ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libs))]
        run(args, out / (name + "-build.log"))
    return out


def main():
    # 编译器输出可能采用本地代码页，诊断中的替换字符也必须能正常输出。
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
    parser = argparse.ArgumentParser()
    parser.add_argument("targets", nargs="*", default=["delphi-win64", "delphi-win32", "fpc-win64"])
    parser.add_argument("--ssl", type=Path)
    parser.add_argument("--crypto", type=Path)
    parser.add_argument("--label", default="openssl3")
    parser.add_argument("--build-only", action="store_true")
    options = parser.parse_args()
    if bool(options.ssl) != bool(options.crypto):
        parser.error("--ssl 和 --crypto 必须同时提供")
    check_resets()
    for target in options.targets:
        out = build(target)
        broken = out / ("libIncompleteCrypto.so" if target.endswith("linux64") else "IncompleteCrypto.dll")
        if not broken.is_file():
            raise FileNotFoundError("没有生成不完整符号测试库: " + str(broken))
        if options.build_only:
            print("PASS build " + target, flush=True)
            continue
        logs = out / options.label
        suffix = "" if target.endswith("win32") else "-x64"
        libdir = REPO / "Net/Tools/OpenSSL"
        if target.endswith("win32"):
            libdir = Path(r"D:\Design\Delphi\VclFmxRtl\zLib\Net\OpenSSL.Libs\OpenSSL3\Windows\x86")
        ssl = options.ssl or libdir / ("libssl-3" + suffix + ".dll")
        crypto = options.crypto or libdir / ("libcrypto-3" + suffix + ".dll")
        if not ssl.is_file() or not crypto.is_file():
            raise FileNotFoundError("需要提供匹配位数的 OpenSSL 库路径")
        results = []
        for mode in MODES:
            result = run([out / "OpenSslLoadTests.exe", mode, ssl, crypto,
                          broken], logs / (mode + ".log"))
            results.append(dict(mode=mode, output=result.strip()))
            print(target, result.strip(), flush=True)
        (logs / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"PASS {target} {len(results)}/{len(MODES)}", flush=True)


if __name__ == "__main__":
    main()
