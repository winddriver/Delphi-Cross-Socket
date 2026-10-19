"""独立进程验证 Session 语义、真实 Cookie 写回与受控线程生命周期。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

SEMANTICS = ["unknown-id", "expired-get", "expired-exists", "imported-id", "touch-valid",
             "id-collision", "writer-reentry", "get-touch-locked", "exists-touch-locked",
             "concurrent-known", "concurrent-unknown", "http-unknown-cookie",
             "http-known-cookie", "http-expired-cookie"]
LIFECYCLE = ["lifecycle-start", "lifecycle-prelock", "lifecycle-locked", "lifecycle-idle", "lifecycle-exception"]


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--semantics-only", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="仅运行旧可执行文件已有的 19 项")
    parser.add_argument("--unit-compatibility", action="store_true", help="增加新旧单元类型同一性验证")
    args = parser.parse_args()
    binary = args.executable.resolve(strict=True)
    cases = SEMANTICS if args.semantics_only else SEMANTICS + LIFECYCLE
    if not args.baseline:
        cases = cases + ["bad-id-generator"]
        if not args.semantics_only:
            cases = cases + ["constructor-failure"]
    if args.unit_compatibility:
        cases = cases + ["unit-compatibility"]
    results = []
    for case in cases:
        try:
            proc = subprocess.run([str(binary), case], capture_output=True, timeout=15)
            output = (proc.stdout + proc.stderr).decode("utf-8", errors="replace").strip()
            passed = proc.returncode == 0 and output == f"PASS: {case}"
            results.append(dict(case=case, passed=passed, exit_code=proc.returncode, output=output))
        except subprocess.TimeoutExpired:
            results.append(dict(case=case, passed=False, exit_code=None, output="独立进程超时"))
        print(results[-1]["output"], flush=True)
    passed = sum(result["passed"] for result in results)
    print(f"HttpSessionTests: {passed}/{len(results)} passed")
    if args.report:
        args.report.write_text(json.dumps(dict(binary=str(binary), sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), results=results), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
