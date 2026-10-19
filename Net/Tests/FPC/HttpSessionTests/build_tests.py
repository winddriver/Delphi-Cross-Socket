"""使用现有工具链构建 Session 回归；Linux 复用既有入口。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import build_linux

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
D = build_linux.DELPHI


def build(target, label, production):
    if 'linux' in target:
        build_linux.build(target, production, label)
        return
    flavor = ('production-' if production else '') + target
    output = HERE / 'bin' / label / flavor
    units = HERE / 'lib' / label / flavor
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    search = [REPO / 'Net', REPO / 'Utils', REPO / 'DelphiToFPC', build_linux.CN]
    if target == 'fpc-win64':
        args = [build_linux.FPC / 'ppcx64.exe', '-B', '-O2']
        args += ['-Fu' + str(p) for p in search + [build_linux.LAZ / 'components/lazutils']]
        args += ['-Fi' + str(REPO), '-FE' + str(output), '-FU' + str(units)]
        args += ['-uCROSS_SESSION_TESTS' if production else '-dCROSS_SESSION_TESTS', HERE / 'HttpSessionTests.lpr']
    else:
        arch = 'win32' if target == 'delphi-win32' else 'win64'
        args = [D / 'bin' / ('dcc32.exe' if arch == 'win32' else 'dcc64.exe'), '-Q', '-B', '-$O+',
                '-NSSystem;System.Win;Winapi', '-U' + ';'.join(map(str, search + [D / 'lib' / arch / 'release'])),
                '-I' + str(REPO), '-E' + str(output), '-N0' + str(units)]
        if not production:
            args += ['-DCROSS_SESSION_TESTS']
        args += [HERE / 'HttpSessionTests.dpr']
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    (output / 'build.log').write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).decode(errors='replace')[-6000:])
    paths = [REPO / 'Net/Net.CrossHttpParams.pas', REPO / 'Net/Net.CrossHttpSessions.pas',
             HERE / 'HttpSessionTests.lpr', REPO / 'Utils/Utils.AnonymousThread.pas']
    metadata = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    (output / 'source.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print('PASS build', flavor, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('targets', nargs='+', choices=['delphi-win64', 'delphi-win32', 'fpc-win64', 'delphi-linux64', 'fpc-linux64'])
    parser.add_argument('--label', required=True)
    parser.add_argument('--production', action='store_true')
    options = parser.parse_args()
    if not options.label.replace('-', '').replace('_', '').isalnum():
        parser.error('invalid label')
    for target in options.targets:
        build(target, options.label, options.production)
