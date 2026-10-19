"""运行已独立重编的既有 WS 帧、TCP 回环和101握手回归，保留程序哈希。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE.parent / "WebSocketFrameTests"


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+")
    parser.add_argument("--label", default="regression-final")
    options = parser.parse_args()
    failed = False
    for target in options.targets:
        assert ("linux" in target) == (os.name != "nt"), "运行环境和目标不匹配"
        folder = HERE / "bin" / (options.label + "-" + target)
        suffix = ".exe" if os.name == "nt" else ""
        frame = folder / ("WebSocketFrameTests" + suffix)
        endpoint = folder / ("WebSocketLoopback" + suffix)
        stages = [("frame", [frame]), ("loopback", [sys.executable, "-B", ORIGINAL / "run_loopback.py", endpoint]),
                  ("handshake", [sys.executable, "-B", ORIGINAL / "run_handshake_tests.py", endpoint,
                                 "--report", folder / "handshake.json"])]
        records = []
        for name, command in stages:
            result = subprocess.run(list(map(str, command)), cwd=HERE, capture_output=True, timeout=180)
            output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
            (folder / (name + ".run.log")).write_text(output, encoding="utf-8")
            records.append({"stage": name, "returncode": result.returncode, "output": output})
            failed |= result.returncode != 0
            print(target, name, result.returncode, output.strip().splitlines()[-1:] if result.returncode == 0 else output, flush=True)
        (folder / "regression.json").write_text(json.dumps({"binaries": {
            frame.name: hashlib.sha256(frame.read_bytes()).hexdigest(), endpoint.name: hashlib.sha256(endpoint.read_bytes()).hexdigest()},
            "results": records}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(failed)
