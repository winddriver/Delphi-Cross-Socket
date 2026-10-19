"""逐进程运行认证回归；退出码非零表示仍有期望行为未满足。"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


CASES = [
    "basic-valid", "basic-empty", "basic-colon", "basic-unknown", "basic-nil",
    "basic-bad-alphabet", "basic-bad-padding", "basic-bad-scheme",
    "basic-missing-colon", "basic-wrong-password", "digest-valid",
    "digest-unknown", "digest-nil", "digest-arbitrary-nonce",
    "digest-cross-target", "digest-replay", "digest-bad-scheme",
    "digest-wrong-password",
]

STATE_CASES = [
    "basic-invalid-utf8", "basic-control", "basic-truncated", "basic-duplicate-header",
    "basic-unicode", "basic-realm", "basic-realm-control", "basic-callback-error",
    "digest-wrong-realm", "digest-wrong-qop", "digest-wrong-algorithm",
    "digest-bad-response", "digest-bad-nc", "digest-zero-nc", "digest-duplicate-param",
    "digest-userhash-false", "digest-userhash-true", "digest-userhash-invalid",
    "digest-username-star", "digest-username-colon", "digest-quoted-values",
    "digest-raw-target", "digest-realm", "digest-expired", "digest-expires-during-lookup",
    "digest-random-failure", "digest-random-collision", "digest-nonce-capacity",
    "digest-use-capacity", "digest-total-capacity", "digest-wrong-then-correct",
    "digest-business-error", "digest-nc-case-replay", "digest-callback-error", "digest-reentrant-callback",
    "digest-concurrent-same", "digest-concurrent-order", "digest-closure-copy",
    "digest-clear-auth-success", "digest-clear-auth-challenge", "digest-release-last-closure",
]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path, help="可选 JSON 结果文件，通常放在 bin 下")
    parser.add_argument("--baseline", action="store_true", help="仅运行修复前已保存的 18 项")
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    results = []
    cases = CASES if args.baseline else CASES + STATE_CASES
    for case in cases:
        try:
            completed = subprocess.run(
                [str(executable), case], capture_output=True, timeout=15
            )
            raw_output = completed.stdout + completed.stderr
            try:
                output = raw_output.decode("utf-8").strip()
            except UnicodeDecodeError:
                output = raw_output.decode("gb18030", errors="replace").strip()
            passed = completed.returncode == 0 and output == f"PASS: {case}"
            results.append({"case": case, "passed": passed,
                            "exit_code": completed.returncode, "output": output})
        except subprocess.TimeoutExpired:
            results.append({"case": case, "passed": False,
                            "exit_code": None, "output": "运行超时"})
        print(results[-1]["output"])
    passed = sum(result["passed"] for result in results)
    print(f"HttpAuthTests: {passed}/{len(cases)} passed")
    if args.report:
        report = {"executable": str(executable),
                  "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                  "passed": passed, "total": len(cases), "results": results}
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if passed == len(cases) else 1)


if __name__ == "__main__":
    main()
