"""使用已有 Delphi/FPC Windows/Linux 工具链，完整构建独立文件流清理回归。"""
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
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"


def build(target, label):
    output, units = HERE / "bin" / (label + "-" + target), HERE / "lib" / (label + "-" + target)
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    linux = target.endswith("linux64")
    if target.startswith("fpc"):
        args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B",
                "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ / "components/lazutils"), "-Fi" + str(REPO),
                "-FE" + str(output), "-FU" + str(units), HERE / "FileStreamCleanupTests.lpr"]
        if linux:
            args.insert(1, "-Tlinux")
    else:
        args = [DELPHI / "bin" / ("dcclinux64.exe" if linux else "dcc64.exe"), "-Q", "-B",
                "-NSSystem;Posix" if linux else "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [REPO / "Utils", DELPHI / ("lib/linux64/release" if linux else "lib/win64/release")])),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units), HERE / "FileStreamCleanupTests.dpr"]
        if linux:
            libs = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu",
                    SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args[1:1] = ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libs))]
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-6500:])
        raise SystemExit(result.returncode)
    sources = [REPO / "Utils/Utils.IOUtils.pas", HERE / "FileStreamCleanupTests.lpr"]
    (output / "source.json").write_text(json.dumps({p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                                                  indent=2) + "\n", encoding="utf-8")
    print("PASS build", label, target, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["delphi-win64", "fpc-win64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--label", required=True)
    options = parser.parse_args()
    for target in options.targets:
        build(target, options.label)
