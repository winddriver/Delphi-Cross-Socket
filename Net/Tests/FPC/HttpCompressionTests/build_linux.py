"""沿用相邻测试的本机工具链交叉构建 Linux 回归，不修改全局配置。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"


def build(target, production=False):
    flavor = ("production-" if production else "") + target
    output = HERE / "bin" / flavor
    units = HERE / "lib" / flavor
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc-linux64":
        args = [FPC / "ppcrossx64.exe", "-Tlinux", "-B",
                "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"),
                "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ / "components/lazutils"), "-Fi" + str(REPO),
                "-FE" + str(output), "-FU" + str(units), HERE / "HttpCompressionTests.lpr"]
    else:
        libraries = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu",
                     SDK / "lib/x86_64-linux-gnu", SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
        args = [DELPHI / "bin/dcclinux64.exe", "-Q", "-B", "-NSSystem;Posix",
                "-U" + ";".join(map(str, (REPO / "Net", REPO / "Utils", CN,
                                         DELPHI / "lib/linux64/release"))),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(output),
                "-N0" + str(units), "--syslibroot:" + str(SDK),
                "--libpath:" + ";".join(map(str, libraries)), HERE / "HttpCompressionTests.dpr"]
    if not production:
        args.insert(1, "-dCROSS_HTTP_COMPRESSION_TESTS" if target == "fpc-linux64" else "-DCROSS_HTTP_COMPRESSION_TESTS")
    elif target == "fpc-linux64":
        args.insert(1, "-uCROSS_HTTP_COMPRESSION_TESTS")
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                            timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-6000:])
        raise SystemExit(result.returncode)
    sources = [REPO / "Net/Net.CrossHttpParser.pas",
               HERE / "HttpCompressionTests.lpr", HERE / "HttpCompressionMemberTests.inc"]
    metadata = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print("PASS build", flavor, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["fpc-linux64", "delphi-linux64"])
    parser.add_argument("--production", action="store_true", help="不启用测试时序入口")
    options = parser.parse_args()
    for selected in options.targets:
        build(selected, options.production)
