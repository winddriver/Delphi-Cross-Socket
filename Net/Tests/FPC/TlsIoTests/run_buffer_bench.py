"""实际WS编码/TLS接收基准；分开计时与分配统计，前后版交替执行。"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys
sys.dont_write_bytecode = True
import run_tests as c

MODES = ['bench-ws', 'bench-tls12', 'bench-tls13']
ALL_MODES = MODES + ['bench-tx12', 'bench-tx13', 'bench-control12', 'bench-control13',
                     'bench-large-rx12', 'bench-large-rx13', 'bench-large-tx12', 'bench-large-tx13']
LABEL = 'o06-ws-final'
PATTERN = re.compile(r'BENCH (\S+) n=(\d+) batch_ns=(\d+) alloc_calls=(\d+) requested_bytes=(\d+) p99_ns=(\d+)')
BASE_REF = '65a5df2'
BASE_LABEL = 'o06-before'


def baseline_source():
    source = c.HERE / 'bin' / BASE_LABEL / 'production'
    source.mkdir(parents=True, exist_ok=True)
    for name in ['Net.CrossSslSocket.OpenSSL.pas', 'Net.CrossWebSocketParser.pas']:
        raw = subprocess.check_output(['git', 'show', BASE_REF + ':Net/' + name], cwd=c.REPO)
        data = b'\xef\xbb\xbf' + raw.decode('utf-8-sig').replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8')
        path = source / name
        if path.exists():
            if path.read_bytes() != data: raise RuntimeError('baseline source differs: ' + str(path))
        else:
            with path.open('xb') as stream: stream.write(data)
    return source


def build(target, variant):
    source = baseline_source() if variant == 'before' else c.REPO / 'Net'
    out = c.HERE / 'bin' / (LABEL + '-' + variant) / target
    out.mkdir(parents=True, exist_ok=True)
    # 旧源不包含新容量API，兼容宏只影响容量测试辅助函数，基准路径仍保持限额默认0。
    old_limits = 'TCrossSslQueueLimits' not in (source / 'Net.CrossSslSocket.OpenSSL.pas').read_text(encoding='utf-8-sig')
    c.build(target, out, source, False, True, limits_baseline=old_limits)
    meta = json.loads((out / 'source.json').read_text())
    meta.update({p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
                 [source / 'Net.CrossWebSocketParser.pas', c.HERE / 'BufferBench.inc',
                  c.REPO / 'DelphiToFPC/DTF.Generics.pas']})
    (out / 'source.json').write_text(json.dumps(meta, indent=2), encoding='utf-8')
    print('PASS build', target, variant, flush=True)


def run(target, variant, number, modes=MODES):
    out = c.HERE / 'bin' / (LABEL + '-' + variant) / target
    records = {}
    for mode in modes:
        args = [out / 'TlsIoTests.exe', mode,
                c.REPO / 'Net/Tools/OpenSSL/libssl-3-x64.dll', c.REPO / 'Net/Tools/OpenSSL/libcrypto-3-x64.dll',
                c.HERE / 'bin/managed-final3/win64/test-cert.pem', c.HERE / 'bin/managed-final3/win64/test-key.pem']
        result = c.execute(args, 180)
        data = result.stdout + result.stderr
        (out / (mode + '-' + str(number) + '.log')).write_bytes(data)
        if result.returncode:
            print(data.decode(errors='replace')); raise RuntimeError('benchmark failed')
        for name, n, elapsed, alloc, requested, p99 in PATTERN.findall(data.decode(errors='replace')):
            n = int(n)
            records[name] = {'n': n, 'ns_per_op': int(elapsed) / n,
                             'alloc_calls_per_op': int(alloc) / n,
                             'requested_bytes_per_op': int(requested) / n, 'p99_ns': int(p99)}
        for name, size, calls, nonempty in re.findall(r'TXWIRE (\S+) bytes=(\d+) pending_calls=(\d+) nonempty=(\d+)', data.decode(errors='replace')):
            records[name].update(wire_bytes=int(size), pending_calls_per_op=int(calls) / records[name]['n'],
                                 pending_nonempty_per_op=int(nonempty) / records[name]['n'])
    assert len(records) == sum(2 if mode.startswith('bench-large-') else 16 if mode == 'bench-ws' else 6 if mode.startswith('bench-tx') else
                              2 if mode.startswith('bench-control') else 3 for mode in modes)
    print('PASS run', target, variant, number, flush=True)
    return records


def describe(values):
    q = statistics.quantiles(values, n=4, method='inclusive')
    return {'median': statistics.median(values), 'q1': q[0], 'q3': q[2], 'iqr': q[2] - q[0], 'samples': values}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--targets', nargs='+', choices=['win64', 'fpc64'], default=['win64', 'fpc64'])
    p.add_argument('--build', choices=['before', 'after'])
    p.add_argument('--smoke', choices=['before', 'after'])
    p.add_argument('--compare', action='store_true')
    p.add_argument('--rounds', type=int, default=5)
    p.add_argument('--modes', nargs='+', choices=ALL_MODES, default=MODES)
    p.add_argument('--run-label', default='')
    p.add_argument('--artifact-label', default=LABEL)
    p.add_argument('--baseline-ref', default=BASE_REF)
    p.add_argument('--baseline-label', default=BASE_LABEL)
    o = p.parse_args()
    LABEL = o.artifact_label
    BASE_REF = o.baseline_ref
    BASE_LABEL = o.baseline_label
    if not LABEL.replace('-', '').replace('_', '').isalnum(): p.error('invalid artifact label')
    if not BASE_LABEL.replace('-', '').replace('_', '').isalnum(): p.error('invalid baseline label')
    if o.run_label and not o.run_label.replace('-', '').replace('_', '').isalnum(): p.error('invalid run label')
    if o.compare and o.rounds < 5: p.error('comparison requires at least five paired rounds')
    for target in o.targets:
        if o.build: build(target, o.build)
        if o.smoke: run(target, o.smoke, 'smoke', o.modes)
        if o.compare:
            samples = {v: [] for v in ('before', 'after')}
            for iteration in range(o.rounds):
                for variant in (['before', 'after'] if iteration % 2 == 0 else ['after', 'before']):
                    number = str(iteration) if not o.run_label else o.run_label + '-' + str(iteration)
                    samples[variant].append(run(target, variant, number, o.modes))
            summary = {}
            for name in samples['before'][0]:
                summary[name] = {v: {key: describe([s[name][key] for s in samples[v]])
                                     for key in ['ns_per_op', 'alloc_calls_per_op', 'requested_bytes_per_op', 'p99_ns']}
                                 for v in samples}
            dest = c.HERE / 'bin' / (LABEL + '-results' + ('-' + o.run_label if o.run_label else ''))
            dest.mkdir(parents=True, exist_ok=True)
            (dest / (target + '.json')).write_text(json.dumps({'raw': samples, 'summary': summary,
              'binaries': {v: hashlib.sha256((c.HERE/'bin'/(LABEL+'-'+v)/target/'TlsIoTests.exe').read_bytes()).hexdigest()
                           for v in samples}}, indent=2), encoding='utf-8')
