"""独立进程验证真实 WS 双端流适配、帧内容与发送失败收尾。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

CASES = ["eof", "negative", "short", "full", "read-first", "read-later", "queued-no-read",
         "size-error", "seek-error", "eof-callback-error", "empty", "range"]


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    results = []
    for side in ("client", "server"):
        for case in CASES:
            record = {"side": side, "case": case}
            try:
                process = subprocess.run([str(executable), side, case], capture_output=True, timeout=15)
                record.update(returncode=process.returncode,
                              output=(process.stdout + process.stderr).decode("utf-8", errors="replace"))
                record["status"] = "pass" if process.returncode == 0 else "fail"
            except subprocess.TimeoutExpired:
                record.update(status="fail", detail="15秒外部超时")
            results.append(record)
            print(record["status"].upper(), side, case, record.get("output", record.get("detail", "")).strip(), flush=True)
    args.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "results": results},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(record["status"] != "pass" for record in results))


if __name__ == "__main__":
    main()
