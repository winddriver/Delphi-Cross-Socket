"""使用现有工具链构建 WebSocket 握手回环端点，输出至独立的 bin/lib 子目录。"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
FPC = Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ = Path(r'D:\Design\FreePascal\lazarus')
CN = Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
SDK = Path.home() / 'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'


def build(target, label):
    output, units = HERE / 'bin' / label / target, HERE / 'lib' / label / target
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == 'fpc64':
        args = [LAZ / 'lazbuild.exe', '--build-all', '--skip-dependencies', HERE / 'WebSocketLoopback.lpi']
    elif target == 'fpc-linux64':
        args = [FPC / 'ppcrossx64.exe', '-Tlinux', '-B', '-dWS_NEW_API',
                '-Fu' + str(REPO / 'Net'), '-Fu' + str(REPO / 'Utils'),
                '-Fu' + str(REPO / 'DelphiToFPC'), '-Fu' + str(LAZ / 'components/lazutils'),
                '-Fi' + str(REPO), '-FE' + str(output), '-FU' + str(units), HERE / 'WebSocketLoopback.lpr']
    else:
        arch = target.removeprefix('delphi-')
        compiler = {'win64': 'dcc64.exe', 'win32': 'dcc32.exe', 'linux64': 'dcclinux64.exe'}[arch]
        args = [DELPHI / 'bin' / compiler, '-Q', '-B', '-$O+', '-DWS_NEW_API',
                '-NSSystem;Posix' if arch == 'linux64' else '-NSSystem;System.Win;Winapi',
                '-U' + ';'.join(map(str, [REPO / 'Net', REPO / 'Utils', CN, DELPHI / 'lib' / arch / 'release'])),
                '-I' + str(REPO) + ';' + str(CN), '-E' + str(output), '-N0' + str(units)]
        if arch == 'linux64':
            libraries = [DELPHI / 'lib/linux64/release', SDK / 'usr/lib/x86_64-linux-gnu',
                         SDK / 'lib/x86_64-linux-gnu', SDK / 'usr/lib/gcc/x86_64-linux-gnu/11']
            args += ['--syslibroot:' + str(SDK), '--libpath:' + ';'.join(map(str, libraries))]
        args += [HERE / 'WebSocketLoopback.dpr']
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    (output / 'build.log').write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors='replace')[-6000:])
        raise SystemExit(result.returncode)
    if target == 'fpc64':
        shutil.copy2(HERE / 'bin/x86_64-win64/WebSocketLoopback.exe', output / 'WebSocketLoopback.exe')
    sources = [REPO / 'Net' / name for name in ['Net.CrossHttpParams.pas', 'Net.CrossHttpClient.pas',
               'Net.CrossWebSocketParser.pas', 'Net.CrossWebSocketServer.pas', 'Net.CrossWebSocketClient.pas']]
    sources.append(HERE / 'WebSocketLoopback.lpr')
    (output / 'source.json').write_text(json.dumps({str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
                                                   for p in sources}, indent=2), encoding='utf-8')
    print('PASS build', target, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('targets', nargs='+', choices=['win64', 'win32', 'fpc64', 'delphi-linux64', 'fpc-linux64'])
    parser.add_argument('--label', default='f15-final')
    options = parser.parse_args()
    if not options.label.replace('-', '').replace('_', '').isalnum():
        parser.error('invalid label')
    for target in options.targets:
        build(target, options.label)
