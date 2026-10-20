"""用 Mac 已安装的 FPC 原生构建回归，显式加载已有配置，产物仅写 bin/lib。"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PROGRAMS = {
    "lifecycle": HERE / "KqueueLifecycleTests.lpr",
    "edges": HERE / "KqueueEdgeTests.lpr",
    "address": HERE / "SocketAddressTests.lpr",
    "callbacks": HERE.parent / "SocketCallbackTests/SocketCallbackTests.lpr",
}


def build(options, name):
    output = HERE / "bin" / options.label / name
    units = HERE / "lib" / options.label / name
    output.mkdir(parents=True, exist_ok=False)
    units.mkdir(parents=True, exist_ok=False)
    source = PROGRAMS[name]
    args = [str(options.fpc), "@" + str(options.config), "-B", "-gl",
            "-Fu" + str(ROOT / "Net"), "-Fu" + str(ROOT / "Utils"),
            "-Fu" + str(ROOT / "DelphiToFPC"), "-Fu" + str(options.lazutils),
            "-Fi" + str(ROOT), "-FE" + str(output), "-FU" + str(units)]
    if name in ("lifecycle", "edges"):
        args.append("-dCROSS_KQUEUE_TESTS")
    if options.debug:
        args.append("-dDEBUG")
    args.append(str(source))
    sources = [ROOT / "zLib.inc", source]
    for folder in ("Net", "Utils", "DelphiToFPC"):
        sources.extend(sorted((ROOT / folder).glob("*.pas")))
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sources}
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    (output / "build.log").write_bytes(result.stdout)
    metadata = {"command": args, "platform": platform.platform(),
                "machine": platform.machine(), "returncode": result.returncode,
                "config_sha256": hashlib.sha256(options.config.read_bytes()).hexdigest(),
                "sources": hashes}
    executable = output / source.stem
    if result.returncode == 0 and executable.is_file():
        metadata["executable_sha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
    (output / "source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    if result.returncode:
        print(result.stdout.decode("utf-8", errors="replace")[-6000:])
        raise SystemExit(result.returncode)
    print("PASS build", name, executable, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fpc", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--lazutils", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--programs", nargs="+", choices=PROGRAMS, default=list(PROGRAMS))
    options = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("该入口必须在真实 macOS 上运行")
    if not options.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label 只允许字母、数字、下划线和连字符")
    for field in ("fpc", "config", "lazutils"):
        setattr(options, field, getattr(options, field).resolve(strict=True))
    for name in options.programs:
        build(options, name)
