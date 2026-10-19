"""测量真实 Timer 进程的 CPU、上下文切换、线程数和触发偏差，不修改系统配置。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time


def snapshot(pid):
    if os.name == "nt":
        # 使用本机已有 psutil，不安装依赖。Windows 的上下文切换只有合计计数。
        import psutil
        process = psutil.Process(pid)
        cpu, switches = process.cpu_times(), process.num_ctx_switches()
        import ctypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.QueryProcessCycleTime.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64)]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        cycles = ctypes.c_uint64()
        try:
            if not kernel.QueryProcessCycleTime(handle, ctypes.byref(cycles)):
                raise ctypes.WinError(ctypes.get_last_error())
        finally:
            kernel.CloseHandle(handle)
        return dict(cpu_seconds=cpu.user + cpu.system, switches=sum(switches), cycles=cycles.value,
                    threads=process.num_threads(), source="psutil " + psutil.__version__ + " + QueryProcessCycleTime")
    base = Path("/proc") / str(pid)
    fields = (base / "stat").read_text().rsplit(")", 1)[1].split()
    ticks = os.sysconf("SC_CLK_TCK")
    cpu = (int(fields[11]) + int(fields[12])) / ticks
    threads = list((base / "task").iterdir())
    switches = 0
    for thread in threads:
        for line in (thread / "status").read_text().splitlines():
            if line.startswith(("voluntary_ctxt_switches:", "nonvoluntary_ctxt_switches:")):
                switches += int(line.split()[1])
    return dict(cpu_seconds=cpu, switches=switches, threads=len(threads), source="/proc")


def idle(executable, count, mode, duration):
    process = subprocess.Popen([str(executable), "idle", str(count), mode],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    try:
        assert process.stdout.readline().decode().strip() == f"READY {count}"
        time.sleep(0.3)  # 仅用于测量预热，不参与生命周期断言。
        before = snapshot(process.pid)
        start = time.perf_counter()
        time.sleep(duration)
        elapsed = time.perf_counter() - start
        after = snapshot(process.pid)
        process.stdin.write(b"stop\n")
        process.stdin.flush()
        output = process.communicate(timeout=8)[0].decode(errors="replace").strip()
        cpu = after["cpu_seconds"] - before["cpu_seconds"]
        record = dict(timer_count=count, mode=mode, seconds=elapsed, cpu_ms=cpu * 1000,
                    cpu_percent_one_core=cpu / elapsed * 100,
                    context_switches=after["switches"] - before["switches"],
                    switches_per_second=(after["switches"] - before["switches"]) / elapsed,
                    threads_before=before["threads"], threads_after=after["threads"], source=after["source"],
                    cleanup_ok=process.returncode == 0 and output == "CALLS 0", cleanup_output=output)
        if "cycles" in before:
            record["cpu_cycles"] = after["cycles"] - before["cycles"]
        return record
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def timing(executable, interval):
    result = subprocess.run([str(executable), "timing", str(interval)], capture_output=True, timeout=12)
    line = result.stdout.decode(errors="replace").strip()
    assert result.returncode == 0 and line.startswith("TIMES "), line
    samples = list(map(int, line.split()[1:]))
    differences = [right - left for left, right in zip(samples, samples[1:])]
    errors = sorted(value - interval for value in differences)
    return dict(interval_ms=interval, initial_delay_ms=150, first_actual_ms=samples[0],
                first_error_ms=samples[0] - 150, actual_intervals_ms=differences,
                median_error_ms=statistics.median(errors), p95_error_ms=errors[int(.95 * (len(errors) - 1))],
                max_error_ms=max(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--duration", type=float, default=2)
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--compare", type=Path, help="正确性相同的轮询对照二进制，逐场景交替运行")
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    versions = [("event" if args.compare else "current", executable)]
    if args.compare:
        versions.insert(0, ("polling", args.compare.resolve(strict=True)))
    records, timings = [], []
    for round_number in range(args.rounds):
        for count, mode in [(0, "idle")] + [(n, mode) for n in (1, 16, 64) for mode in ("idle", "paused")]:
            for version, binary in versions if round_number % 2 == 0 else reversed(versions):
                record = idle(binary, count, mode, args.duration)
                record["round"], record["version"] = round_number + 1, version
                records.append(record)
                print("IDLE", version, count, mode, f'cpu_ms={record["cpu_ms"]:.3f}',
                      f'context_switches={record["context_switches"]}', f'threads={record["threads_after"]}',
                      f'cycles={record.get("cpu_cycles", "n/a")}', f'cleanup_ok={record["cleanup_ok"]}', flush=True)
        for interval in (5, 25, 100):
            for version, binary in versions if round_number % 2 == 0 else reversed(versions):
                record = timing(binary, interval)
                record["round"], record["version"] = round_number + 1, version
                timings.append(record)
                print("TIMING", version, interval, f'median_error_ms={record["median_error_ms"]}',
                      f'p95_error_ms={record["p95_error_ms"]}', flush=True)
    report = dict(executable=str(executable), sha256=hashlib.sha256(executable.read_bytes()).hexdigest(),
                  platform=sys.platform, idle=records, timing=timings,
                  note="上下文切换是空闲唤醒代理，非精确唤醒次数；CPU时间受平台计数精度和运行负载影响。")
    report["versions"] = {name: dict(executable=str(binary), sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
                          for name, binary in versions}
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    return int(not all(record["cleanup_ok"] for record in records))


if __name__ == "__main__":
    raise SystemExit(main())
