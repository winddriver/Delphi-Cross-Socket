"""比较同一二进制下32MiB原始正文的默认内存与128KiB阈值落盘。"""
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
import time


def memory(pid):
    if os.name == 'nt':
        # 使用环境已有的psutil，仅做测试进程观测，不新增项目依赖。
        import psutil
        info = psutil.Process(pid).memory_info()
        return {'rss': info.rss, 'peak_rss': info.peak_wset, 'private': info.private}
    fields = {}
    for line in Path(f'/proc/{pid}/status').read_text().splitlines():
        if line.startswith(('VmRSS:', 'VmHWM:')):
            fields[line.split(':', 1)[0]] = int(line.split()[1]) * 1024
    return {'rss': fields['VmRSS'], 'peak_rss': fields['VmHWM'], 'private': None}


def sample(executable, mode):
    existing = set(executable.parent.glob('body-*'))
    process = subprocess.Popen([str(executable), 'storage', 'bench-' + mode], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    events = queue.Queue()
    lines = []

    def read():
        for raw in process.stdout:
            line = raw.decode('utf-8', errors='replace').strip()
            lines.append(line)
            events.put(line)

    reader = threading.Thread(target=read)
    reader.start()
    try:
        first = events.get(timeout=10)
        if first != 'BASELINE':
            raise RuntimeError(first)
        baseline = memory(process.pid)
        started = time.perf_counter()
        process.stdin.write(b'continue\n'); process.stdin.flush()
        ready = events.get(timeout=20)
        if ready != 'MEMORY_READY':
            raise RuntimeError(ready)
        elapsed = time.perf_counter() - started
        held = memory(process.pid)
        file_mode = None
        if mode == 'spill' and os.name != 'nt':
            created = set(executable.parent.glob('body-*')) - existing
            files = [path for directory in created for path in directory.iterdir() if path.is_file()]
            if len(files) != 1:
                raise RuntimeError('expected one private temporary body')
            file_mode = files[0].stat().st_mode & 0o777
            if file_mode & 0o077:
                raise RuntimeError(f'temporary body is accessible to other users: {file_mode:o}')
        process.stdin.write(b'verify\n'); process.stdin.flush()
        process.wait(timeout=30)
        reader.join(timeout=3)
        if process.returncode != 0 or not any(line.startswith('PASS storage bench-') for line in lines):
            raise RuntimeError('; '.join(lines))
        return {'mode': mode, 'baseline': baseline, 'held': held, 'receive_seconds': elapsed,
                'rss_growth': held['rss'] - baseline['rss'],
                'peak_growth': held['peak_rss'] - baseline['peak_rss'], 'file_mode': file_mode, 'cleanup_ok': True}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        reader.join(timeout=3)
        process.stdin.close()
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    options = parser.parse_args()
    executable = options.executable.resolve(strict=True)
    # WSL的/mnt/d不呈现POSIX权限；Linux在原生临时目录运行同一字节的程序验证0600。
    temporary = tempfile.TemporaryDirectory(prefix='cross-body-memory-') if os.name != 'nt' else None
    actual = executable
    try:
        if temporary:
            actual = Path(temporary.name) / executable.name
            shutil.copy2(executable, actual)
        sample(actual, 'memory'); sample(actual, 'spill')
        results = []
        for iteration in range(options.rounds):
            for mode in (('memory', 'spill') if iteration % 2 == 0 else ('spill', 'memory')):
                value = sample(actual, mode)
                value['round'] = iteration + 1
                results.append(value)
                print(mode, 'peak_growth', value['peak_growth'], 'cleanup', value['cleanup_ok'], flush=True)
    finally:
        if temporary:
            temporary.cleanup()
    options.report.write_text(json.dumps({'binary_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
                                         'body_bytes': 32 * 1024 * 1024, 'threshold_bytes': 128 * 1024,
                                         'location': 'native temporary directory' if os.name != 'nt' else 'workspace bin',
                                         'results': results}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
