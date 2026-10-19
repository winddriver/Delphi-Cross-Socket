"""在 Linux 中复用同一组件与 TCP 场景，运行已构建的测试程序。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from run_tests import CASES
from run_network import run

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executables", nargs="+", type=Path)
    options = parser.parse_args()
    failed = False
    for path in options.executables:
        executable = path.resolve(strict=True)
        results = []
        for case in CASES:
            mode, kind = case.split("-", 1)
            if mode == "tcp":
                passed, detail = run(executable, kind)
            else:
                try:
                    result = subprocess.run([str(executable), mode, kind], cwd=HERE,
                                            capture_output=True, timeout=15)
                    detail = (result.stdout + result.stderr).decode("utf-8", errors="replace").strip()
                    passed = result.returncode == 0 and f'PASS {mode} {kind}' in detail.splitlines()
                except subprocess.TimeoutExpired:
                    passed, detail = False, "TIMEOUT (child killed and reaped)"
            failed |= not passed
            results.append({"case": case, "passed": passed, "output": detail})
            (executable.parent / (case + ".log")).write_text(detail, encoding="utf-8")
            print(executable.parent.name, case, "PASS" if passed else "FAIL", flush=True)
        report = {"executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                  "passed": sum(item["passed"] for item in results),
                  "total": len(results), "results": results}
        (executable.parent / "linux-results.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8")
        print(executable.parent.name, report["passed"], "/", report["total"], flush=True)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
