"""独立构建 Sender-only WS 容量回归，使用已有工具链和隔离输出。"""
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


def build(target, label, limits=False, selftest=True):
    output, units = HERE / "bin" / (label + "-" + target), HERE / "lib" / (label + "-" + target)
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    linux = target.endswith("linux64")
    defines = (["WS_QUEUE_LIMITS"] if limits else []) + (["CROSS_WS_SENDER_SELFTEST"] if selftest else [])
    if target.startswith("fpc"):
        args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B", "-O2",
                "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ / "components/lazutils"), "-Fi" + str(REPO),
                "-FE" + str(output), "-FU" + str(units), HERE / "WebSocketCapacityTests.lpr"]
        args[1:1] = ["-d" + define for define in defines] + (["-Tlinux"] if linux else [])
    else:
        arch = "linux64" if linux else "win32" if target.endswith("win32") else "win64"
        args = [DELPHI / "bin" / {"win64": "dcc64.exe", "win32": "dcc32.exe", "linux64": "dcclinux64.exe"}[arch],
                "-Q", "-B", "-$O+", "-NSSystem;Posix" if linux else "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [REPO / "Net", REPO / "Utils", CN, DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(output), "-N0" + str(units), HERE / "WebSocketCapacityTests.dpr"]
        if defines:
            args.insert(1, "-D" + ";".join(defines))
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
    sources = [REPO / "Net" / name for name in ["Net.CrossWebSocketSender.pas", "Net.CrossWebSocketParser.pas",
               "Net.CrossSocket.Base.pas"]] + [HERE / "WebSocketCapacityTests.lpr"]
    (output / "source.json").write_text(json.dumps({str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
                                                  for p in sources}, indent=2) + "\n", encoding="utf-8")
    print("PASS build", label, target, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["delphi-win64", "delphi-win32", "fpc-win64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--label", required=True)
    parser.add_argument("--limits", action="store_true")
    parser.add_argument("--no-selftest", action="store_true")
    options = parser.parse_args()
    for target in options.targets:
        build(target, options.label, options.limits, not options.no_selftest)
