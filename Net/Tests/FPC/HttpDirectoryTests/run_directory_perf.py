"""真实文件系统目录基准；采集进程实际峰值工作集 / VmHWM，不安装依赖。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import uuid

HERE = Path(__file__).resolve().parent


def memory(pid):
    if os.name == "nt":
        import psutil
        info = psutil.Process(pid).memory_info()
        return {"rss_bytes": info.rss, "peak_bytes": info.peak_wset}
    fields = {}
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith(("VmRSS:", "VmHWM:")):
            key, value, _ = line.split()
            fields[key[:-1]] = int(value) * 1024
    return {"rss_bytes": fields["VmRSS"], "peak_bytes": fields["VmHWM"]}


def measure(exe, directory, limit, iterations):
    process = subprocess.Popen([str(exe), str(directory), str(limit), str(iterations)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding="utf-8", errors="replace")
    lines = queue.Queue()
    reader = threading.Thread(target=lambda: [lines.put(line.rstrip()) for line in process.stdout], daemon=True)
    reader.start()
    try:
        assert lines.get(timeout=15) == "READY", "基准未就绪"
        before = memory(process.pid)
        process.stdin.write("go\n")
        process.stdin.flush()
        result = lines.get(timeout=180).split()
        assert result[0] == "RESULT" and len(result) == 6, result
        after = memory(process.pid)
        ticks, frequency, count, length, checksum = map(int, result[1:])
        process.stdin.write("stop\n")
        process.stdin.flush()
        process.wait(timeout=15)
        assert process.returncode == 0, process.stderr.read()
        return {"entries": len(list(directory.iterdir())), "limit": limit, "iterations": count,
                "elapsed_ticks": ticks, "frequency": frequency,
                "ms_per_listing": ticks * 1000 / frequency / count,
                "characters": length, "hash": str(checksum), "before": before, "after": after,
                "peak_growth_bytes": max(0, after["peak_bytes"] - before["peak_bytes"])}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        reader.join(timeout=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    executables = {"baseline": args.baseline.resolve(strict=True)}
    if args.candidate:
        executables["candidate"] = args.candidate.resolve(strict=True)
    parent = HERE / "bin/fixtures" if os.name == "nt" else Path(tempfile.gettempdir())
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / ("http-directory-perf-" + uuid.uuid4().hex)
    root.mkdir()
    root = root.resolve()
    results = []
    try:
        for size, iterations in [(100, 60), (1000, 15), (10000, 3)]:
            directory = root / str(size)
            directory.mkdir()
            for i in range(size):
                entry = directory / (f"item{i} 中文 & %.dir" if i % 10 == 0 else f"item{i} 中文 & %.txt")
                if i % 10 == 0:
                    entry.mkdir()
                else:
                    entry.write_bytes(bytes([i % 256]) * (i % 128))
            for round_index in range(args.rounds):
                names = list(executables)
                if round_index % 2:
                    names.reverse()
                full_hashes = []
                for name in names:
                    limits = [0, 100] if name == "candidate" and size > 100 else [0]
                    for limit in limits:
                        record = measure(executables[name], directory, limit, iterations)
                        record.update({"version": name, "round": round_index + 1})
                        results.append(record)
                        if limit == 0:
                            full_hashes.append((record["characters"], record["hash"]))
                        print(name, size, limit, f'{record["ms_per_listing"]:.3f} ms',
                              "peak", record["after"]["peak_bytes"], flush=True)
                assert len(set(full_hashes)) == 1, "完整页面内容与基线不一致"
    finally:
        if root.parent != parent.resolve() or not root.name.startswith("http-directory-perf-"):
            raise RuntimeError("临时目录边界异常，拒绝清理")
        shutil.rmtree(root)
    report = {"executables": {name: {"path": str(path),
               "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for name, path in executables.items()},
              "memory_note": "操作系统峰值工作集或 VmHWM；包括一次未计时预热和最终保留页面；增长为启动就绪后峰值之差。",
              "results": results}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
