"""独立构建完整消息发送队列测试；不改握手测试或主测试入口。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r'D:\Design\Delphi\D13.1')
FPC = Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ = Path(r'D:\Design\FreePascal\lazarus')
CN = Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
SDK = Path.home() / 'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'
CASES = ['legacy', 'fifo', 'control', 'sync-depth', 'source-error',
         'local-close', 'peer-close', 'protocol-close', 'timeout', 'external-close',
         'io-failure', 'cancel-error', 'source-error-queued', 'source-close',
         'source-close-error', 'callback-reentry', 'large-control',
         'prepare-close-race', 'owner-lifetime', 'close-frame-error', 'close-frame-timeout',
         'managed-message', 'managed-control']

def build(target, label):
    out = HERE / 'bin' / ('sender-' + label) / target
    units = HERE / 'lib' / ('sender-' + label) / target
    out.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    source = out / 'SenderQueueTests.lpr'
    source.write_text('''program SenderQueueTests;
{$I zLib.inc}
uses {$IFDEF FPC}{$IFDEF UNIX}cthreads,{$ENDIF}{$ENDIF} SysUtils, WebSocketSenderTests;
begin
  try
    if ParamStr(1)='legacy' then RunWebSocketSenderTests
    else RunWebSocketMessageQueueTest(ParamStr(1));
  except on E:Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
''', encoding='utf-8-sig', newline='\r\n')
    linux = 'linux' in target
    if target.startswith('fpc'):
        args = [FPC / ('ppcrossx64.exe' if linux else 'fpc.exe'), '-B', '-O2', '-dWS_SENDER_ONLY', '-dCROSS_WS_SENDER_SELFTEST',
                '-Fu' + str(REPO / 'Net'), '-Fu' + str(REPO / 'Utils'),
                '-Fu' + str(REPO / 'DelphiToFPC'), '-Fu' + str(HERE),
                '-Fu' + str(LAZ / ('components/lazutils' if linux else 'components/lazutils/lib/x86_64-win64')),
                '-Fi' + str(REPO), '-Fi' + str(HERE), '-FE' + str(out), '-FU' + str(units)]
        if linux: args += ['-Tlinux']
    else:
        arch = 'linux64' if linux else ('win32' if '32' in target else 'win64')
        args = [DELPHI / 'bin' / ('dcclinux64.exe' if linux else ('dcc32.exe' if arch=='win32' else 'dcc64.exe')),
                '-Q', '-B', '-$O+', '-DWS_SENDER_ONLY;CROSS_WS_SENDER_SELFTEST' + (';__LITTLE_PIECE__' if 'pieces' in target else ''),
                '-NSSystem;' + ('Posix' if linux else 'System.Win;Winapi'),
                '-U' + ';'.join(map(str, [REPO/'Net', REPO/'Utils', HERE, CN, DELPHI/'lib'/arch/'release'])),
                '-I' + str(REPO) + ';' + str(HERE) + ';' + str(CN), '-E' + str(out), '-N0' + str(units)]
        if linux:
            libs = [DELPHI/'lib/linux64/release',SDK/'usr/lib/x86_64-linux-gnu',SDK/'lib/x86_64-linux-gnu',SDK/'usr/lib/gcc/x86_64-linux-gnu/11']
            args += ['--syslibroot:' + str(SDK), '--libpath:' + ';'.join(map(str,libs))]
    args.append(source)
    r = subprocess.run(list(map(str,args)),cwd=HERE,capture_output=True,timeout=120,
                       creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (out/'build.log').write_bytes(r.stdout+r.stderr)
    if r.returncode:
        print((r.stdout+r.stderr).decode(errors='replace')[-7000:]);raise SystemExit(r.returncode)
    paths = [REPO/'Net/Net.CrossWebSocketSender.pas', REPO/'Net/Net.CrossWebSocketParser.pas',
             REPO/'Net/Net.CrossSocket.Base.pas', REPO/'DelphiToFPC/DTF.Generics.pas',
             HERE/'WebSocketSenderTests.pas',HERE/'WebSocketMessageQueueTests.inc']
    (out/'source.json').write_text(json.dumps({str(p.relative_to(REPO)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2),encoding='utf-8')
    print('PASS build',target,flush=True)
    return out

def run(target,label,cases):
    out = HERE/'bin'/('sender-'+label)/target
    exe = out/('SenderQueueTests' + ('' if 'linux' in target else '.exe'))
    results=[]
    for case in cases:
        try:
            r=subprocess.run([str(exe),case],cwd=HERE,capture_output=True,timeout=20,
                             creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            text=(r.stdout+r.stderr).decode('utf-8' if 'linux' in target else 'gb18030',errors='replace');code=r.returncode
        except subprocess.TimeoutExpired as e:
            text='TIMEOUT '+str(e);code=-1
        (out/(case+'.log')).write_text(text,encoding='utf-8')
        results.append({'case':case,'returncode':code,'output':text})
        print(target,case,code,text.strip(),flush=True)
    (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    return all(r['returncode']==0 for r in results)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('targets',nargs='+');p.add_argument('--label',default='current')
    p.add_argument('--run-only',action='store_true');p.add_argument('--build-only',action='store_true')
    p.add_argument('--cases',nargs='+',default=CASES);o=p.parse_args();ok=True
    for target in o.targets:
        if not o.run_only: build(target,o.label)
        if not o.build_only: ok=run(target,o.label,o.cases) and ok
    raise SystemExit(0 if ok else 1)
