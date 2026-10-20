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


def build(target, production=False, label=None):
    flavor = ("production-" if production else "") + target
    output = HERE / "bin" / label / flavor if label else HERE / "bin" / flavor
    units = HERE / "lib" / label / flavor if label else HERE / "lib" / flavor
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc-linux64":
        args = [FPC / "ppcrossx64.exe", "-Tlinux", "-B",
                "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"),
                "-Fu" + str(REPO / "DelphiToFPC"),
                "-Fu" + str(LAZ / "components/lazutils"), "-Fi" + str(REPO),
                "-FE" + str(output), "-FU" + str(units), HERE / "EasyThreadTests.lpr"]
    else:
        libraries = [DELPHI / "lib/linux64/release", SDK / "usr/lib/x86_64-linux-gnu",
                     SDK / "lib/x86_64-linux-gnu", SDK / "usr/lib/gcc/x86_64-linux-gnu/11"]
        args = [DELPHI / "bin/dcclinux64.exe", "-Q", "-B", "-NSSystem;Posix",
                "-U" + ";".join(map(str, (REPO / "Net", REPO / "Utils", CN,
                                         DELPHI / "lib/linux64/release"))),
                "-I" + str(REPO) + ";" + str(CN), "-E" + str(output),
                "-N0" + str(units), "--syslibroot:" + str(SDK),
                "--libpath:" + ";".join(map(str, libraries)), HERE / "EasyThreadTests.dpr"]
    if not production:
        args.insert(1, "-dCROSS_EASY_THREAD_TESTS" if target == "fpc-linux64" else "-DCROSS_EASY_THREAD_TESTS")
    elif target == "fpc-linux64":
        args.insert(1, "-uCROSS_EASY_THREAD_TESTS")
    sources = [REPO / "Utils/Utils.EasyThread.pas", REPO / "Utils/Utils.AnonymousThread.pas",
               REPO / "Utils/Utils.EasyTimer.pas", REPO / "Utils/Utils.SyncObjs.pas",
               HERE / "EasyThreadTests.lpr", HERE / "EasyThreadJoinTests.inc",
               HERE / "run_tests.py", HERE / "build_linux.py"]
    before = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                            timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
    (output / "build.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-6000:])
        raise SystemExit(result.returncode)
    metadata = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    (output / "source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    (output / "build.json").write_text(json.dumps(dict(command=list(map(str, args)),
        sources_before=before, sources_after=metadata), indent=2), encoding="utf-8")
    if before != metadata:
        raise RuntimeError("构建期间源码发生变化，本次产物不得作为冻结版本证据")
    print("PASS build", flavor, flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["fpc-linux64", "delphi-linux64"])
    parser.add_argument("--production", action="store_true", help="不启用构造失败测试入口")
    parser.add_argument("--label", help="产物放入 bin/lib 的独立标签目录；省略保持原路径")
    options = parser.parse_args()
    if options.label and not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("invalid label")
    for selected in options.targets:
        build(selected, options.production, options.label)
