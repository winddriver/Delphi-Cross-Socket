"""独立进程触发真实写入错误，核验缓冲区/句柄/临时文件清理和原文件内容。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
CASES = ["readonly-destroy", "readonly-flush-destroy", "readonly-clean", "writable-destroy",
         "writable-flush", "temp-empty", "temp-write", "temp-failure", "temp-failure-after-flush"]
ORIGINAL = b"original-unchanged-file-content"


def limit_file_size():
    import resource
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    parent = HERE / "bin/fixtures" if os.name == "nt" else Path(tempfile.gettempdir())
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / ("file-stream-cleanup-" + uuid.uuid4().hex)
    root.mkdir()
    root = root.resolve()
    results = []
    try:
        for case in CASES:
            folder = root / case
            folder.mkdir()
            original = folder / "original.bin"
            if not case.startswith("temp-"):
                original.write_bytes(ORIGINAL)
            record = {"case": case}
            try:
                kwargs = {}
                if os.name != "nt" and case.startswith("temp-failure"):
                    kwargs["preexec_fn"] = limit_file_size
                process = subprocess.run([str(executable), case, str(folder)], capture_output=True,
                                         timeout=10, **kwargs)
                record.update(returncode=process.returncode, output=process.stdout.decode("utf-8", errors="replace"))
                if case.startswith("readonly-"):
                    assert original.read_bytes() == ORIGINAL, "只读错误路径改变了原文件"
                elif case.startswith("writable-"):
                    assert original.read_bytes() == b"buffered-write", "正常缓冲写入未完成"
                else:
                    record["remaining_files"] = [p.name for p in folder.iterdir()]
                assert process.returncode == 0, record["output"] + process.stderr.decode("utf-8", errors="replace")
                if case.startswith("temp-"):
                    assert not record["remaining_files"], "临时文件遗留"
                record["status"] = "pass"
            except Exception as error:
                record.update(status="fail", detail=str(error))
            results.append(record)
            print(record["status"].upper(), case, record.get("output", "").strip(), flush=True)
    finally:
        if root.parent != parent.resolve() or not root.name.startswith("file-stream-cleanup-"):
            raise RuntimeError("测试目录边界异常，拒绝清理")
        shutil.rmtree(root)
    args.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "results": results},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(record["status"] != "pass" for record in results))


if __name__ == "__main__":
    main()
