"""从最终生产源码独立重编既有 WS 帧组件及 TCP/握手端点，不改原测试输出。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCE = HERE.parent / "WebSocketFrameTests"
DELPHI = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64")
LAZ = Path(r"D:\Design\FreePascal\lazarus")
CN = Path(r"D:\Design\Delphi\VclFmxRtl\cncrypto\Source")
SDK = Path.home() / "Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk"


def build(target, label):
    linux = "linux" in target
    arch = "linux64" if linux else "win32" if target.endswith("win32") else "win64"
    output = HERE / "bin" / (label + "-" + target)
    output.mkdir(parents=True, exist_ok=True)
    for project in ("WebSocketFrameTests", "WebSocketLoopback"):
        units = HERE / "lib" / (label + "-" + target) / project
        units.mkdir(parents=True, exist_ok=True)
        defines = ["WS_SENDER_ONLY", "CROSS_WS_SENDER_SELFTEST"] if project == "WebSocketFrameTests" else ["WS_NEW_API"]
        paths = [REPO / "Net", REPO / "Utils", SOURCE]
        if target.startswith("fpc"):
            args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B", "-O2"]
            args += ["-d" + x for x in defines] + (["-Tlinux"] if linux else [])
            paths += [REPO / "DelphiToFPC", LAZ / "components/lazutils"]
            args += ["-Fu" + str(p) for p in paths]
            args += ["-Fi" + str(REPO), "-Fi" + str(SOURCE), "-FE" + str(output), "-FU" + str(units), SOURCE / (project + ".lpr")]
        else:
            compiler = {"win64": "dcc64.exe", "win32": "dcc32.exe", "linux64": "dcclinux64.exe"}[arch]
            args = [DELPHI / "bin" / compiler, "-Q", "-B", "-$O+", "-D" + ";".join(defines),
                    "-NSSystem;Posix" if linux else "-NSSystem;System.Win;Winapi",
                    "-U" + ";".join(map(str, paths + [CN, DELPHI / "lib" / arch / "release"])),
                    "-I" + str(REPO) + ";" + str(CN), "-E" + str(output), "-N0" + str(units)]
            if linux:
                libraries = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu",
                             SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
                args += ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libraries))]
            args.append(SOURCE / (project + ".dpr"))
        result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        (output / (project + ".build.log")).write_bytes(result.stdout + result.stderr)
        if result.returncode:
            print((result.stdout + result.stderr).decode(errors="replace")[-6500:])
            raise SystemExit(result.returncode)
        files = [REPO / "Net" / name for name in ("Net.CrossWebSocketSender.pas", "Net.CrossWebSocketParser.pas",
                 "Net.CrossWebSocketClient.pas", "Net.CrossWebSocketServer.pas")]
        files += [SOURCE / (project + ".lpr")]
        if project == "WebSocketFrameTests":
            files += [SOURCE / name for name in ("WebSocketSenderTests.pas", "WebSocketRegressionTests.pas", "WebSocketMessageQueueTests.inc")]
        (output / (project + ".source.json")).write_text(json.dumps({str(p.relative_to(REPO)):
            hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, indent=2) + "\n", encoding="utf-8")
        print("PASS build", project, target, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["delphi-win64", "delphi-win32", "fpc-win64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--label", default="regression-final")
    args = parser.parse_args()
    for target in args.targets:
        build(target, args.label)
