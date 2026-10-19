"""独立标签完整重编组件/合法帧矩阵与回环端点，记录共享HTTP依赖哈希。"""
import argparse
import hashlib
import json
import subprocess
import sys
sys.dont_write_bytecode = True
import run_sender_tests as c


def build(target, label):
    out = c.HERE / 'bin' / label / target
    units = c.HERE / 'lib' / label / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    linux = 'linux' in target
    for name in ['WebSocketFrameTests', 'WebSocketLoopback']:
        if target.startswith('fpc'):
            args = [c.FPC / ('ppcrossx64.exe' if linux else 'ppcx64.exe'), '-B', '-O2',
                    '-dWS_NEW_API', '-dCROSS_OPENSSL_SELFTEST', '-dCROSS_WS_SENDER_SELFTEST',
                    '-Fu' + str(c.REPO / 'Net'), '-Fu' + str(c.REPO / 'Utils'),
                    '-Fu' + str(c.REPO / 'DelphiToFPC'), '-Fu' + str(c.HERE),
                    '-Fu' + str(c.LAZ / ('components/lazutils' if linux else 'components/lazutils/lib/x86_64-win64')),
                    '-Fi' + str(c.REPO), '-FE' + str(out), '-FU' + str(units)]
            if linux: args += ['-Tlinux']
            args += [c.HERE / (name + '.lpr')]
        else:
            arch = 'linux64' if linux else 'win64'
            args = [c.DELPHI / 'bin' / ('dcclinux64.exe' if linux else 'dcc64.exe'), '-Q', '-B', '-$O+',
                    '-DWS_NEW_API;CROSS_OPENSSL_SELFTEST;CROSS_WS_SENDER_SELFTEST',
                    '-NSSystem;' + ('Posix' if linux else 'System.Win;Winapi'),
                    '-U' + ';'.join(map(str, [c.REPO/'Net', c.REPO/'Utils', c.HERE, c.CN, c.DELPHI/'lib'/arch/'release'])),
                    '-I' + str(c.REPO) + ';' + str(c.CN), '-E' + str(out), '-N0' + str(units)]
            if linux:
                libs = [c.DELPHI/'lib/linux64/release', c.SDK/'usr/lib/x86_64-linux-gnu',
                        c.SDK/'lib/x86_64-linux-gnu', c.SDK/'usr/lib/gcc/x86_64-linux-gnu/11']
                args += ['--syslibroot:' + str(c.SDK), '--libpath:' + ';'.join(map(str, libs))]
            args += [c.HERE / (name + '.dpr')]
        r = subprocess.run(list(map(str, args)), cwd=c.HERE, capture_output=True, timeout=120,
                           creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        (out / (name + '-build.log')).write_bytes(r.stdout + r.stderr)
        if r.returncode:
            print((r.stdout + r.stderr).decode(errors='replace')[-6000:])
            raise SystemExit(r.returncode)
    paths = list((c.REPO/'Net').glob('Net.Cross*.pas')) + [c.REPO/'DelphiToFPC/DTF.Generics.pas']
    paths += [p for p in c.HERE.iterdir() if p.suffix in ('.pas', '.lpr', '.inc')]
    (out/'source.json').write_text(json.dumps({str(p.relative_to(c.REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
                                             for p in paths}, indent=2), encoding='utf-8')
    print('PASS build', target, flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('targets', nargs='+', choices=['delphi-win64', 'fpc-win64', 'delphi-linux64', 'fpc-linux64'])
    p.add_argument('--label', required=True)
    o = p.parse_args()
    if not o.label.replace('-', '').replace('_', '').isalnum(): p.error('invalid label')
    for target in o.targets: build(target, o.label)
