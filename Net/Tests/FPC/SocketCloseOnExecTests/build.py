"""使用项目已有 Delphi / FPC 和 Ubuntu SDK 交叉编译，不安装依赖。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"


def build(target):
    output = HERE / "bin" / target
    units = HERE / "lib" / target
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc-linux64":
        args = [FPC / "ppcrossx64.exe", "-Tlinux", "-B", "-Fu" + str(REPO / "Net"),
                "-Fu" + str(REPO / "DelphiToFPC"), "-Fi" + str(REPO),
                "-FE" + str(output), "-FU" + str(units), HERE / "SocketCloseOnExecTests.lpr"]
    else:
        compilers = {"linux64": "dcclinux64", "android": "dccaarm", "android64": "dccaarm64",
                     "osx64": "dccosx64", "osxarm64": "dccosxarm64", "iosDevice64": "dcciosarm64"}
        arch = target.removeprefix("delphi-")
        args = [DELPHI / "bin" / (compilers[arch] + ".exe"), "-Q", "-B", "-NSSystem;Posix",
                "-U" + str(REPO / "Net"), "-I" + str(REPO), "-N0" + str(units)]
        if arch == "linux64":
            libs = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu",
                    SDK / "lib/x86_64-linux-gnu", SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args += ["-E" + str(output), "--syslibroot:" + str(SDK),
                     "--libpath:" + ";".join(map(str, libs)), HERE / "SocketCloseOnExecTests.dpr"]
        else:
            args += [REPO / "Net/Net.SocketAPI.pas"]
    process = subprocess.run(list(map(str, args)), cwd=REPO, capture_output=True, timeout=120)
    (output / "build.log").write_bytes(process.stdout + process.stderr)
    if process.returncode:
        print((process.stdout + process.stderr).decode(errors="replace"))
        raise SystemExit(process.returncode)
    print("PASS build " + target, flush=True)


for target in (sys.argv[1:] or ["fpc-linux64", "delphi-linux64"]):
    build(target)
