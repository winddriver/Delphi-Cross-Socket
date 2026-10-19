"""运行独立标签下的完整组件、合法帧矩阵与现有11项TCP回环。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def run(target, label):
    out = HERE / 'bin' / label / target
    extension = '' if 'linux' in target else '.exe'
    rows = []
    for name, command in [
        ('components', [out / ('WebSocketFrameTests' + extension)]),
        ('loopback', [sys.executable, HERE / 'run_loopback.py', out / ('WebSocketLoopback' + extension)]),
    ]:
        r = subprocess.run(list(map(str, command)), cwd=HERE, capture_output=True, timeout=120,
                           creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        (out / (name + '.log')).write_bytes(r.stdout + r.stderr)
        text = (r.stdout + r.stderr).decode(errors='replace')
        rows.append({'name': name, 'returncode': r.returncode, 'output': text})
        print(target, name, r.returncode, text.strip(), flush=True)
    data = {'results': rows, 'binaries': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [out / ('WebSocketFrameTests' + extension), out / ('WebSocketLoopback' + extension)]}}
    (out / 'results.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
    return all(row['returncode'] == 0 for row in rows)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('targets', nargs='+')
    p.add_argument('--label', required=True)
    o = p.parse_args()
    ok = True
    for target in o.targets: ok = run(target, o.label) and ok
    raise SystemExit(0 if ok else 1)
