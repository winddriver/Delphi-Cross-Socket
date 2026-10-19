"""在现有 Linux 环境运行同一真实 OpenSSL 组件回归。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from run_tests import MODES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executables", nargs="+", type=Path)
    parser.add_argument("--ssl", default="/lib/x86_64-linux-gnu/libssl.so.3")
    parser.add_argument("--crypto", default="/lib/x86_64-linux-gnu/libcrypto.so.3")
    parser.add_argument("--cert", type=Path, required=True)
    parser.add_argument("--key", type=Path, required=True)
    options = parser.parse_args()
    failed = False
    for path in options.executables:
        exe = path.resolve(strict=True)
        results = []
        for mode in MODES:
            try:
                result = subprocess.run([str(exe), mode, options.ssl, options.crypto,
                                         str(options.cert.resolve(strict=True)), str(options.key.resolve(strict=True))],
                                        capture_output=True, timeout=20)
                data = result.stdout + result.stderr
                passed = result.returncode == 0 and ("PASS " + mode).encode() in data
            except subprocess.TimeoutExpired as error:
                data = (error.stdout or b"") + b"\nTIMEOUT (child killed and reaped)\n"
                passed = False
            (exe.parent / (mode + ".log")).write_bytes(data)
            results.append({"mode": mode, "passed": passed, "output": data.decode(errors="replace")})
            print(exe.parent.name, mode, "PASS" if passed else "FAIL", flush=True)
            failed |= not passed
        (exe.parent / "results.json").write_text(json.dumps({
            "executable_sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
            "ssl": options.ssl, "crypto": options.crypto, "results": results,
        }, indent=2), encoding="utf-8")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
