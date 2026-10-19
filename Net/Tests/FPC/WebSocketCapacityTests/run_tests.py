"""每项独立进程运行 WS 容量与实体帧长度回归。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

CASES = ["default", "message-count", "message-bytes", "client-bytes", "provider-count", "provider-frame",
         "provider-overflow", "control-count", "close-budget", "close-wait", "invalid-config", "frame-overflow", "header-only",
         "message-reentry", "accepted-callback-error", "rejected-callback-error", "provider-first-overflow", "provider-no-space",
         "provider-close", "source-error", "control-bytes", "control-reentry", "close-count", "active-close",
         "duplicate-completion", "fixed-depth", "header-boundaries", "concurrent-limit", "encode-error", "mask-error",
         "close-frame-error", "settings-preparing", "encoding-close", "io-failure", "lower-layer-reject", "wide-limits"]
HOOK_CASES = {"encode-error", "mask-error", "close-frame-error", "settings-preparing", "encoding-close"}


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--cases", nargs="+", default=CASES)
    parser.add_argument("--no-selftest", action="store_true")
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    results = []
    for case in args.cases:
        if args.no_selftest and case in HOOK_CASES:
            continue
        try:
            proc = subprocess.run([str(executable), case], capture_output=True, timeout=15)
            record = {"case": case, "status": "pass" if proc.returncode == 0 else "fail", "returncode": proc.returncode,
                      "output": (proc.stdout + proc.stderr).decode("utf-8", errors="replace")}
        except subprocess.TimeoutExpired:
            record = {"case": case, "status": "fail", "output": "15秒外部超时"}
        results.append(record)
        print(record["status"].upper(), case, record["output"].strip(), flush=True)
    args.report.write_text(json.dumps({"executable": str(executable), "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                                      "results": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(r["status"] != "pass" for r in results))
