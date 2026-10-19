"""Multipart 回归与顺序读取基准；保留退出码、原始样本和构建源哈希。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
FPC = Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ = Path(r'D:\Design\FreePascal\lazarus')
SDK = Path.home() / 'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'
TARGETS = ['win64', 'win32', 'fpc64', 'fpc-linux64', 'delphi-linux64']
CASES = ['wire-0', 'wire-1', 'wire-100', 'wire-1000', 'short-read',
         'early-zero', 'length-grow', 'length-shrink', 'length-between',
         'seek-overflow', 'read-overflow', 'init-overflow', 'sparse-file',
         'init-total-overflow', 'init-tail-overflow', 'negative-size',
         'ownership', 'ownership-init', 'count-1', 'count-100', 'count-1000']
SOURCES = [REPO / p for p in [
    'zLib.inc', 'Net/Net.CrossHttpParams.pas', 'Net/Net.CrossHttpUtils.pas',
    'DelphiToFPC/DTF.Types.pas', 'DelphiToFPC/DTF.Generics.pas',
    'Utils/Utils.AnonymousThread.pas', 'Utils/Utils.RegEx.pas',
    'Utils/Utils.IOUtils.pas', 'Utils/Utils.DateTime.pas',
    'Utils/Utils.StrUtils.pas', 'Utils/Utils.SyncObjs.pas',
    'Utils/Utils.ArrayUtils.pas', 'Utils/Utils.Utils.pas']]


def hashes(params_source=None):
    paths = SOURCES + [HERE / 'MultipartStreamTests.lpr', HERE / 'MultipartStreamTests.dpr']
    paths += sorted(HERE.glob('*.inc'))
    return {p.relative_to(REPO).as_posix(): hashlib.sha256(
        ((params_source / p.name) if params_source and p.name == 'Net.CrossHttpParams.pas' else p).read_bytes()
    ).hexdigest() for p in paths}


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def invoke(args, cwd, env=None):
    # 独立进程组，超时/中断时回收进程及其编译器子进程。
    windows = os.name == 'nt'
    flags = (subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP) if windows else 0
    with subprocess.Popen(list(map(str, args)), cwd=cwd, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, creationflags=flags,
                          start_new_session=not windows) as proc:
        timed_out = False
        try:
            output, _ = proc.communicate(timeout=60)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            try:
                if windows:
                    subprocess.run(['taskkill.exe', '/PID', str(proc.pid), '/T', '/F'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=10, creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    os.killpg(proc.pid, signal.SIGKILL)
            except (OSError, subprocess.TimeoutExpired):
                pass
            if proc.poll() is None:
                proc.kill()
            output, _ = proc.communicate()
            if isinstance(error, KeyboardInterrupt):
                raise
            timed_out = True
        return (-1 if timed_out else proc.returncode), output, timed_out


def build(target, label, params_source=None):
    out = HERE / 'bin' / label / target
    units = HERE / 'lib' / label / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    metadata = hashes(params_source)
    linux = 'linux' in target
    if target.startswith('fpc'):
        args = [FPC / ('ppcrossx64.exe' if linux else 'fpc.exe'), '-B', '-O2']
        if params_source:
            args += ['-Fu' + str(params_source)]
        args += ['-Fu' + str(REPO / 'Net'), '-Fu' + str(REPO / 'Utils'),
                '-Fu' + str(REPO / 'DelphiToFPC'),
                '-Fu' + str(LAZ / ('components/lazutils' if linux else 'components/lazutils/lib/x86_64-win64')),
                '-Fi' + str(REPO), '-Fi' + str(HERE), '-FE' + str(out), '-FU' + str(units)]
        if linux:
            args += ['-Tlinux']
        args += [HERE / 'MultipartStreamTests.lpr']
    else:
        arch = 'linux64' if linux else ('win32' if target == 'win32' else 'win64')
        args = [DELPHI / 'bin' / ('dcclinux64.exe' if linux else ('dcc32.exe' if arch == 'win32' else 'dcc64.exe')),
                '-Q', '-B', '-$O+', '-NSSystem;' + ('Posix' if linux else 'System.Win;Winapi'),
                '-U' + ';'.join(map(str, ([params_source] if params_source else []) +
                                      [REPO / 'Net', REPO / 'Utils', DELPHI / 'lib' / arch / 'release'])),
                '-I' + str(REPO) + ';' + str(HERE), '-E' + str(out), '-N0' + str(units)]
        if linux:
            libs = [DELPHI / 'lib/linux64/release', SDK / 'usr/lib/x86_64-linux-gnu',
                    SDK / 'lib/x86_64-linux-gnu', SDK / 'usr/lib/gcc/x86_64-linux-gnu/11']
            args += ['--syslibroot:' + str(SDK), '--libpath:' + ';'.join(map(str, libs))]
        args += [HERE / 'MultipartStreamTests.dpr']
    code, output, timed_out = invoke(args, HERE)
    (out / 'build.log').write_bytes(output)
    save(out / 'build.json', {'command': list(map(str, args)), 'code': code, 'timeout': timed_out})
    if code:
        print(output.decode(errors='replace')[-7000:], flush=True)
        return False
    if hashes(params_source) != metadata:
        raise RuntimeError('构建期间源码变化，必须重建：' + target)
    exe = out / ('MultipartStreamTests' + ('' if linux else '.exe'))
    save(out / 'source.json', metadata)
    save(out / 'binary.json', {'sha256': hashlib.sha256(exe.read_bytes()).hexdigest()})
    print('PASS build', target, flush=True)
    return True


def run(target, options):
    out = HERE / 'bin' / options.label / target
    exe = out / ('MultipartStreamTests' + ('' if 'linux' in target else '.exe'))
    binary = json.loads((out / 'binary.json').read_text(encoding='utf-8'))
    if hashlib.sha256(exe.read_bytes()).hexdigest() != binary['sha256']:
        raise RuntimeError('二进制已变化，必须重建：' + str(exe))
    initial = hashes()
    built = json.loads((out / 'source.json').read_text(encoding='utf-8'))
    save(out / 'run-source.json', {'current': initial, 'matches_build': initial == built})
    temp = out / 'tmp'
    temp.mkdir(exist_ok=True)
    env = dict(os.environ, TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    results, benchmarks = [], []

    def call(args, filename):
        code, raw, timed_out = invoke([exe] + list(map(str, args)), out, env)
        text = raw.decode('utf-8' if 'linux' in target else 'gb18030', errors='replace')
        if timed_out:
            text += '\nTIMEOUT: 60 秒；子进程已终止并回收。\n'
        (out / filename).write_text(text, encoding='utf-8')
        return {'code': code, 'timeout': timed_out, 'output': text}

    try:
        if not options.bench_only:
            for case in options.cases:
                row = dict(case=case, **call([case], case + '.log'))
                results.append(row)
                save(out / 'results.json', results)
                print(target, case, 'PASS' if row['code'] == 0 else 'FAIL', row['code'], flush=True)
        if not options.regression_only:
            for kind in ('memory', 'mixed'):
                for fields in (0, 1, 100, 1000):
                    for block in (4096, 65536):
                        samples = []
                        for sample in range(options.samples + 1):
                            row = dict(sample=sample, warmup=sample == 0, **call(
                                ['bench', kind, fields, block], f'{kind}-{fields}-{block}-{sample}.log'))
                            match = re.search(r'BENCH\s+' + kind + r'\s+fields=(\d+)\s+block=(\d+)\s+bytes=(\d+)\s+us=([\d.]+)', row['output'])
                            if row['code'] == 0 and match and (int(match[1]), int(match[2])) == (fields, block):
                                row.update(bytes=int(match[3]), us=float(match[4]))
                            else:
                                row['parse_error'] = '退出失败或 BENCH 输出与请求不一致'
                            samples.append(row)
                        valid = [x['us'] for x in samples if not x['warmup'] and 'us' in x]
                        record = {'kind': kind, 'fields': fields, 'block': block, 'samples': samples,
                                  'median_us': statistics.median(valid) if len(valid) == options.samples else None}
                        benchmarks.append(record)
                        save(out / 'benchmarks.json', benchmarks)
                        print(target, kind, fields, block, record['median_us'], 'us', flush=True)
    finally:
        current = hashes()
        binary_unchanged = hashlib.sha256(exe.read_bytes()).hexdigest() == binary['sha256']
        save(out / 'run-integrity.json', {'sources_unchanged': initial == current,
            'binary_unchanged': binary_unchanged})
        if current != initial or not binary_unchanged:
            raise RuntimeError('运行期间源码或二进制变化，本轮不能作为冻结版本验证：' + target)
    return (all(row['code'] == 0 for row in results) and
            all('parse_error' not in sample for row in benchmarks for sample in row['samples']))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('targets', nargs='+', choices=TARGETS)
    parser.add_argument('--label', default='current')
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--params-source', type=Path, help='仅构建时优先使用该目录中的Params源码快照，不修改生产文件')
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--run-only', action='store_true')
    action.add_argument('--build-only', action='store_true')
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument('--regression-only', action='store_true')
    scope.add_argument('--bench-only', action='store_true')
    parser.add_argument('--cases', nargs='+', choices=CASES, default=CASES)
    options = parser.parse_args()
    if options.params_source:
        options.params_source = options.params_source.resolve()
        if not (options.params_source / 'Net.CrossHttpParams.pas').is_file():
            parser.error('params-source缺少Net.CrossHttpParams.pas')
    if not re.fullmatch(r'[A-Za-z0-9_-]+', options.label) or options.samples < 1:
        parser.error('label 仅可包含字母、数字、下划线和连字符；samples 必须大于零')
    ok = True
    for target in options.targets:
        if not options.run_only and not build(target, options.label, options.params_source):
            ok = False
            continue
        if not options.build_only:
            ok = run(target, options) and ok
    raise SystemExit(0 if ok else 1)
