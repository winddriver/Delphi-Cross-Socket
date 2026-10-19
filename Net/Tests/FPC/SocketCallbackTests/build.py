"""使用现有工具链构建回调异常回归，产物仅写 bin/lib。"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"
SOURCES = [REPO / ("Net/Net.CrossSocket." + name + ".pas")
           for name in ("Base", "Iocp", "Epoll", "Kqueue")]


def build(target, label):
    output = HERE / "bin" / label / target
    units = HERE / "lib" / label / target
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc64":
        args = [LAZ / "lazbuild.exe", "--build-all", "--skip-dependencies", HERE / "SocketCallbackTests.lpi"]
    elif target == "fpc-linux64":
        args = [FPC / "ppcrossx64.exe", "-Tlinux", "-B",
                "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"),
                "-Fu" + str(REPO / "DelphiToFPC"), "-Fu" + str(LAZ / "components/lazutils"),
                "-Fi" + str(REPO), "-FE" + str(output), "-FU" + str(units),
                HERE / "SocketCallbackTests.lpr"]
    else:
        arch = target.removeprefix("delphi-")
        compiler = {"linux64": "dcclinux64.exe", "win64": "dcc64.exe", "win32": "dcc32.exe",
                    "osx64": "dccosx64.exe", "osxarm64": "dccosxarm64.exe"}[arch]
        args = [DELPHI / "bin" / compiler, "-Q", "-B", "-$O+",
                "-NSSystem;Posix" if arch in ("linux64", "osx64", "osxarm64") else "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [REPO / "Net", REPO / "Utils", DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units)]
        if arch == "linux64":
            libraries = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu",
                         SDK / "lib/x86_64-linux-gnu", SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args += ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libraries))]
        args.append(REPO / "Net/Net.CrossSocket.Kqueue.pas" if arch.startswith("osx")
                    else HERE / "SocketCallbackTests.dpr")
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                            timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-7000:])
        raise SystemExit(result.returncode)
    if target == "fpc64":
        shutil.copy2(HERE / "bin/fpc64/SocketCallbackTests.exe", output / "SocketCallbackTests.exe")
    metadata = {source.name: hashlib.sha256(source.read_bytes()).hexdigest()
                for source in SOURCES + [HERE / "SocketCallbackTests.lpr"]}
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print("PASS compile-only" if target.startswith("delphi-osx") else "PASS build", target, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["win64", "win32", "fpc64", "fpc-linux64", "delphi-linux64",
                                                       "delphi-osx64", "delphi-osxarm64"])
    parser.add_argument("--label", default="current")
    options = parser.parse_args()
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("invalid label")
    for target in options.targets:
        build(target, options.label)
