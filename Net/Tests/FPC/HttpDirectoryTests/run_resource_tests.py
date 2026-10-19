"""用受控异常验证实际列表析构和原生搜索句柄释放，并计数实际枚举量。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import uuid

HERE = Path(__file__).resolve().parent


def handles(pid):
    if os.name == "nt":
        import psutil
        return psutil.Process(pid).num_handles()
    return len(list(Path(f"/proc/{pid}/fd").iterdir()))


def run(executable, directory, stage, limit):
    process = subprocess.Popen([str(executable), str(directory), str(stage), str(limit)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding="utf-8", errors="replace")
    lines = queue.Queue()
    reader = threading.Thread(target=lambda: [lines.put(line.rstrip()) for line in process.stdout], daemon=True)
    reader.start()
    try:
        assert lines.get(timeout=10) == "READY", "子进程未就绪"
        before = handles(process.pid)
        process.stdin.write("go\n")
        process.stdin.flush()
        values = lines.get(timeout=10).split()
        assert values[0] == "RESULT", values
        numbers = list(map(int, values[1:]))
        # 保留可直接重跑的早期红基线；该版本还输出已弃用的 builder 计数。
        if len(numbers) == 5:
            assert numbers.pop(1) == 0
        lists, entries, thrown, length = numbers
        after = handles(process.pid)
        process.stdin.write("stop\n")
        process.stdin.flush()
        process.wait(timeout=10)
        assert process.returncode == 0, process.stderr.read()
        return {"lists_alive": lists, "entries_seen": entries,
                "exception_seen": bool(thrown), "characters": length,
                "handles_before": before, "handles_after": after}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        reader.join(timeout=1)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    parent = HERE / "bin/fixtures" if os.name == "nt" else Path(tempfile.gettempdir())
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / ("http-directory-resource-" + uuid.uuid4().hex)
    root.mkdir()
    root = root.resolve()
    results = []
    try:
        directory = root / "entries"
        directory.mkdir()
        (root / "empty").mkdir()
        for i in range(20):
            (directory / f"entry{i}").write_bytes(b"test")
        cases = [(name, stage, 0, None) for stage, name in enumerate(
            ["first-list-created", "search-opened", "entry-collected", "before-sort", "before-render", "row-render"])]
        cases += [("unlimited-scan", -1, 0, 20), ("limited-one-scan", -1, 1, 2),
                  ("limited-partial-scan", -1, 7, 8), ("limited-exact-scan", -1, 20, 20),
                  ("limited-larger-scan", -1, 21, 20), ("empty-directory", -1, 1, 0),
                  ("missing-directory", -1, 0, 0), ("direct-negative-rejected", -1, -1, 0)]
        for name, stage, limit, expected in cases:
            record = {"case": name}
            try:
                selected = root / "empty" if name == "empty-directory" else root / "missing" if name == "missing-directory" else directory
                record.update(run(executable, selected, stage, limit))
                assert record["exception_seen"] == (stage >= 0 or limit < 0), "注入异常或负数拒绝未到达"
                assert record["lists_alive"] == 0, "实际对象未析构"
                assert record["handles_after"] <= record["handles_before"], "搜索句柄未释放"
                if expected is not None:
                    assert record["entries_seen"] == expected, "枚举超过 N+1 或丢失条目"
                    assert (record["characters"] == 0) if limit < 0 else (record["characters"] > 0)
                record["status"] = "pass"
            except Exception as error:
                record.update(status="fail", detail=str(error))
            results.append(record)
            print(record["status"].upper(), name, record, flush=True)
    finally:
        if root.parent != parent.resolve() or not root.name.startswith("http-directory-resource-"):
            raise RuntimeError("临时目录边界异常，拒绝清理")
        shutil.rmtree(root)
    args.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "results": results},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(item["status"] != "pass" for item in results))


if __name__ == "__main__":
    main()
