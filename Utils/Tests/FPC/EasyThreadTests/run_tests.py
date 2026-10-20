"""独立进程验证 EasyThread 的任务、包装对象和回调资源生命周期。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

CASES = ["self-natural", "self-exception", "self-terminate", "self-wait",
         "external-wait", "anonymous-external-destroy"]


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--baseline", action="store_true", help="只运行原始六项，无测试开关时也可用")
    parser.add_argument("--production", action="store_true", help="运行除构造故障注入之外的现有全部回归")
    args = parser.parse_args()
    binary = args.executable.resolve(strict=True)
    results = []
    cases = CASES if args.baseline else CASES + ["constructor-failure-self", "constructor-failure-anonymous"]
    if not args.baseline:
        if args.production:
            cases = CASES.copy()
        cases += ["control-external-destroy", "join-timers16", "join-timers64", "join-concurrent", "join-worker-self"]
        if os.name != "nt":
            cases += ["join-id-reuse"]
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
    print(f"EasyThreadTests: {passed}/{len(results)} passed")
    if args.report:
        args.report.write_text(json.dumps(dict(binary=str(binary), sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), results=results), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
