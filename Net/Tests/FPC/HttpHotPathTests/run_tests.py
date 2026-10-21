"""HTTP 热路径行为回归与前后交替微基准；沿现有 HttpFailureTests 构建方式。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
CN = Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
FPC = Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe')


def execute(args, timeout=60):
    p = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True,
                       timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
    raw = p.stdout + p.stderr
    try:
        output = raw.decode('utf-8')
    except UnicodeDecodeError:
        output = raw.decode('gb18030', errors='replace')
    return p.returncode, output


def build(target, label, source=None, checked=False):
    out = HERE / 'bin' / label / target
    units = HERE / 'lib' / label / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    search = ([source] if source else []) + [REPO / 'Net', REPO / 'Utils', CN]
    if target == 'fpc64':
        search += [REPO / 'DelphiToFPC', Path(r'D:\Design\FreePascal\lazarus\components\lazutils')]
        args = [FPC, '-B', '-O2'] + ['-Fu' + str(p) for p in search]
        args += ['-Fi' + str(REPO), '-FE' + str(out), '-FU' + str(units)]
        if checked:
            args += ['-Cr', '-Co']
        args += [HERE / 'HttpHotPathTests.lpr']
    else:
        args = [DELPHI / 'bin' / ('dcc64.exe' if target == 'win64' else 'dcc32.exe'), '-Q', '-B', '-$O+',
                '-NSSystem;System.Win;Winapi', '-U' + ';'.join(map(str, search + [DELPHI / 'lib' / target / 'release'])),
                '-I' + str(REPO) + ';' + str(CN), '-E' + str(out), '-N0' + str(units)]
        if checked:
            args += ['-$R+', '-$Q+']
        args += [HERE / 'HttpHotPathTests.dpr']
    code, text = execute(args, 120)
    (out / 'build.log').write_text(text, encoding='utf-8')
    if code:
        raise RuntimeError(text[-8000:])
    metadata = {'args': list(map(str, args)), 'sources': {}}
    for name in ('Net.CrossHttpParams.pas', 'Net.CrossHttpServer.pas'):
        p = source / name if source and (source / name).exists() else REPO / 'Net' / name
        metadata['sources'][name] = hashlib.sha256(p.read_bytes()).hexdigest()
    metadata['test_sha256'] = hashlib.sha256((HERE / 'HttpHotPathTests.lpr').read_bytes()).hexdigest()
    metadata['includes'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in HERE.glob('*.inc')}
    metadata['binary_sha256'] = hashlib.sha256((out / 'HttpHotPathTests.exe').read_bytes()).hexdigest()
    (out / 'source.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print('BUILD PASS', label, target, flush=True)


def invoke(target, label, args):
    exe = HERE / 'bin' / label / target / 'HttpHotPathTests.exe'
    code, output = execute([exe] + args)
    if code or 'PASS ' not in output:
        raise RuntimeError(f'{label} {target} {args}\n{output}')
    return output


def compare(target, before, after, names, count, samples):
    rows = []
    for name in names:
        pairs = []
        for i in range(samples + 1):
            pair = {'index': i, 'warmup': i == 0}
            for label in ([before, after] if i % 2 == 0 else [after, before]):
                output = invoke(target, label, ['bench', name, str(count)])
                pair[label] = float(re.search(r'us=([\d.]+)', output)[1])
            pairs.append(pair)
        row = {'name': name, 'count': count, 'pairs_us': pairs, 'summary': {}, 'allocations': {}}
        for label in (before, after):
            values = [x[label] for x in pairs if not x['warmup']]
            row['summary'][label] = {'median_us': statistics.median(values), 'min_us': min(values), 'max_us': max(values)}
            output = invoke(target, label, ['bench', name, '10000', 'alloc'])
            m = re.search(r'calls=(\d+) bytes=(\d+)', output)
            row['allocations'][label] = {'count': 10000, 'calls': int(m[1]), 'bytes': int(m[2])}
        rows.append(row)
        print(target, name, json.dumps({k: row[k] for k in ('summary', 'allocations')}), flush=True)
    (HERE / 'bin' / after / target / 'benchmarks.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--targets', nargs='+', default=['win64', 'win32', 'fpc64'])
    p.add_argument('--label', required=True)
    p.add_argument('--source-root', type=Path)
    p.add_argument('--cases', nargs='+', default=['tokens'])
    p.add_argument('--no-build', action='store_true')
    p.add_argument('--checked', action='store_true')
    p.add_argument('--before')
    p.add_argument('--benchmarks', nargs='+', default=['tokens'])
    p.add_argument('--count', type=int, default=300000)
    p.add_argument('--samples', type=int, default=5)
    o = p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', o.label):
        p.error('invalid label')
    for target in o.targets:
        if not o.no_build:
            build(target, o.label, o.source_root.resolve() if o.source_root else None, o.checked)
        results = []
        for case in o.cases:
            output = invoke(target, o.label, [case])
            results.append({'case': case, 'output': output})
            print(target, output.strip(), flush=True)
        (HERE / 'bin' / o.label / target / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
        if o.before:
            compare(target, o.before, o.label, o.benchmarks, o.count, o.samples)
