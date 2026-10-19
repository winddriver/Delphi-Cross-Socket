"""独立输出构建真实双端 WS 流适配回归，不改生产测试入口或全局配置。"""
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


def build(target, label, source_dir=None, queue_limits=False):
    output, units = HERE / "bin" / (label + "-" + target), HERE / "lib" / (label + "-" + target)
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    linux = target.endswith("linux64")
    if target.startswith("fpc"):
        args = [FPC / ("ppcrossx64.exe" if linux else "ppcx64.exe"), "-B", "-O2",
                "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ / "components/lazutils"), "-Fi" + str(REPO),
                "-FE" + str(output), "-FU" + str(units), HERE / "WebSocketStreamTests.lpr"]
        if linux:
            args.insert(1, "-Tlinux")
        if source_dir:
            args.insert(1, "-Fu" + str(source_dir))
    else:
        arch = "linux64" if linux else "win32" if target.endswith("win32") else "win64"
        args = [DELPHI / "bin" / {"win64": "dcc64.exe", "win32": "dcc32.exe", "linux64": "dcclinux64.exe"}[arch],
                "-Q", "-B", "-$O+", "-NSSystem;Posix" if linux else "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, [REPO / "Net", REPO / "Utils", CN, DELPHI / "lib" / arch / "release"])),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(output), "-N0" + str(units), HERE / "WebSocketStreamTests.dpr"]
        if linux:
            libs = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu", SDK / "lib/x86_64-linux-gnu",
                    SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
            args[1:1] = ["--syslibroot:" + str(SDK), "--libpath:" + ";".join(map(str, libs))]
        if source_dir:
            index = next(i for i, arg in enumerate(args) if str(arg).startswith("-U"))
            args[index] = "-U" + str(source_dir) + ";" + str(args[index])[2:]
    if queue_limits:
        args.insert(1, "-dWS_STREAM_QUEUE_LIMITS" if target.startswith("fpc") else "-DWS_STREAM_QUEUE_LIMITS")
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-7000:])
        raise SystemExit(result.returncode)
    sources = [REPO / "Net" / name for name in ["Net.CrossWebSocketClient.pas", "Net.CrossWebSocketServer.pas",
               "Net.CrossWebSocketSender.pas", "Net.CrossWebSocketParser.pas", "Net.CrossHttpClient.pas",
               "Net.CrossHttpServer.pas", "Net.CrossHttpParser.pas", "Net.CrossHttpParams.pas", "Net.CrossSocket.Base.pas"]]
    sources += [REPO / "Utils/Utils.IOUtils.pas", HERE / "WebSocketStreamTests.lpr"]
    if (REPO / "Net/Net.CrossHttpSessions.pas").exists():
        sources.append(REPO / "Net/Net.CrossHttpSessions.pas")
    metadata = {}
    for path in sources:
        actual = source_dir / path.name if source_dir and (source_dir / path.name).exists() else path
        metadata[str(path.relative_to(REPO))] = hashlib.sha256(actual.read_bytes()).hexdigest()
    (output / "source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("PASS build", label, target, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["delphi-win64", "delphi-win32", "fpc-win64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--label", required=True)
    parser.add_argument("--source-dir", type=Path, help="使用已保存的旧生产单元快照构建同一组断言")
    parser.add_argument("--queue-limits", action="store_true", help="通过两端具体类配置有限发送队列")
    options = parser.parse_args()
    for target in options.targets:
        build(target, options.label, options.source_dir.resolve(strict=True) if options.source_dir else None, options.queue_limits)
