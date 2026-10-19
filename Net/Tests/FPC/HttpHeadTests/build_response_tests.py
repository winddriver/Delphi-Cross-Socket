"""全量构建既有客户端测试；可从隔离源码快照复现响应解析红例。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
FPC = Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ = Path(r'D:\Design\FreePascal\lazarus')
SDK = Path.home() / 'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'


def build(target, label, source_root):
    out, units = HERE / 'bin' / label / target, HERE / 'lib' / label / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    linux = 'linux' in target
    search = ([source_root] if source_root else []) + [REPO / 'Net', REPO / 'Utils']
    if target.startswith('fpc'):
        args = [FPC / ('ppcrossx64.exe' if linux else 'ppcx64.exe'), '-B']
        if linux:
            args.append('-Tlinux')
        args += ['-Fu' + str(p) for p in search + [REPO / 'DelphiToFPC', LAZ / 'components/lazutils']]
        args += ['-Fi' + str(REPO), '-FE' + str(out), '-FU' + str(units), HERE / 'HttpHeadTests.lpr']
    else:
        arch = 'linux64' if linux else ('win32' if target == 'delphi-win32' else 'win64')
        compiler = 'dcclinux64.exe' if linux else ('dcc32.exe' if arch == 'win32' else 'dcc64.exe')
        args = [DELPHI / 'bin' / compiler, '-Q', '-B', '-NSSystem;Posix' if linux else '-NSSystem;System.Win;Winapi',
                '-U' + ';'.join(map(str, search + [DELPHI / 'lib' / arch / 'release'])), '-I' + str(REPO),
                '-E' + str(out), '-N0' + str(units)]
        if linux:
            libs = [DELPHI / 'lib/linux64/release', SDK / 'usr/lib/x86_64-linux-gnu',
                    SDK / 'lib/x86_64-linux-gnu', SDK / 'usr/lib/gcc/x86_64-linux-gnu/11']
            args += ['--syslibroot:' + str(SDK), '--libpath:' + ';'.join(map(str, libs))]
        args.append(HERE / 'HttpHeadTests.dpr')
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    (out / 'build.log').write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors='replace')[-4500:])
        raise SystemExit(result.returncode)
    sources = [HERE / 'HttpHeadTests.lpr', HERE / 'HttpClientResponseTests.inc']
    for name in ('Net.CrossHttpClient.pas', 'Net.CrossHttpParser.pas'):
        sources.append(source_root / name if source_root and (source_root / name).exists() else REPO / 'Net' / name)
    (out / 'source.json').write_text(json.dumps({p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2), encoding='utf-8')
    print('BUILD PASS', target, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('targets', nargs='+', choices=['delphi-win64', 'delphi-win32', 'fpc-win64', 'delphi-linux64', 'fpc-linux64'])
    parser.add_argument('--label', required=True)
    parser.add_argument('--source-root', type=Path)
    options = parser.parse_args()
    if not options.label.replace('-', '').replace('_', '').isalnum():
        parser.error('invalid label')
    for target in options.targets:
        build(target, options.label, options.source_root.resolve() if options.source_root else None)
