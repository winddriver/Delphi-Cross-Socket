"""使用现有工具链构建容量回归；自动识别前版是否已有配置API。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[3]
D=Path(r'D:\Design\Delphi\D13.1');FPC=Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ=Path(r'D:\Design\FreePascal\lazarus');CN=Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
SDK=Path.home()/'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'
SOURCES=[REPO/'Net'/n for n in ('Net.CrossHttpClient.pas','Net.CrossSocket.Base.pas','Net.CrossSocket.Iocp.pas','Net.CrossSocket.Epoll.pas','Net.CrossSocket.Kqueue.pas','Net.CrossSslSocket.OpenSSL.pas')]

def hashes(override):
    paths=SOURCES+[HERE/'CapacityTests.lpr',HERE/'CapacityTests.dpr']+sorted(HERE.glob('*.inc'))
    return {p.relative_to(REPO).as_posix():hashlib.sha256(
        (override/p.name if override and (override/p.name).is_file() else p).read_bytes()).hexdigest() for p in paths}

def build(target,label,override):
    out=HERE/'bin'/label/target;units=HERE/'lib'/label/target
    out.mkdir(parents=True,exist_ok=True);units.mkdir(parents=True,exist_ok=True);before=hashes(override)
    client_source=(override/'Net.CrossHttpClient.pas' if override and (override/'Net.CrossHttpClient.pas').is_file() else REPO/'Net/Net.CrossHttpClient.pas')
    api='MaxPendingRequestsPerServer' in client_source.read_text(encoding='utf-8-sig')
    race_hook='SetClientAdmissionTestHook' in client_source.read_text(encoding='utf-8-sig')
    base_source=(override/'Net.CrossSocket.Base.pas' if override and (override/'Net.CrossSocket.Base.pas').is_file() else REPO/'Net/Net.CrossSocket.Base.pas')
    socket_api='MaxPendingSendCount' in base_source.read_text(encoding='utf-8-sig')
    linux='linux' in target;search=([override] if override else [])+[REPO/'Net',REPO/'Utils',REPO/'DelphiToFPC']
    if target.startswith('fpc'):
        args=[FPC/('ppcrossx64.exe' if linux else 'fpc.exe'),'-B','-O2','-dCROSS_CAPACITY_TESTS']
        if api:args+=['-dCAPACITY_API']
        if race_hook:args+=['-dCLIENT_RACE_HOOK']
        if socket_api:args+=['-dSOCKET_CAPACITY_API']
        args+=['-Fu'+str(p) for p in search]
        args+=['-Fu'+str(LAZ/('components/lazutils' if linux else 'components/lazutils/lib/x86_64-win64')),
               '-Fi'+str(REPO),'-FE'+str(out),'-FU'+str(units)]
        if linux:args+=['-Tlinux']
        args+=[HERE/'CapacityTests.lpr']
    else:
        arch='linux64' if linux else ('win32' if target=='win32' else 'win64')
        args=[D/'bin'/('dcclinux64.exe' if linux else ('dcc32.exe' if arch=='win32' else 'dcc64.exe')),
              '-Q','-B','-$O+','-DCROSS_CAPACITY_TESTS'+(';CAPACITY_API' if api else '')+(';CLIENT_RACE_HOOK' if race_hook else '')+(';SOCKET_CAPACITY_API' if socket_api else ''),'-NSSystem;'+('Posix' if linux else 'System.Win;Winapi'),
              '-U'+';'.join(map(str,search+[CN,D/'lib'/arch/'release'])),'-I'+str(REPO)+';'+str(CN),
              '-E'+str(out),'-N0'+str(units)]
        if linux:
            libs=[D/'lib/linux64/release',SDK/'usr/lib/x86_64-linux-gnu',SDK/'lib/x86_64-linux-gnu',SDK/'usr/lib/gcc/x86_64-linux-gnu/11']
            args+=['--syslibroot:'+str(SDK),'--libpath:'+';'.join(map(str,libs))]
        args+=[HERE/'CapacityTests.dpr']
    r=subprocess.run(list(map(str,args)),cwd=HERE,capture_output=True,timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (out/'build.log').write_bytes(r.stdout+r.stderr)
    if r.returncode:print((r.stdout+r.stderr).decode(errors='replace')[-7000:]);return False
    if before!=hashes(override):raise RuntimeError('构建期间源码变化')
    (out/'source.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    (out/'config.json').write_text(json.dumps({'target':target,'test_macros':['CROSS_CAPACITY_TESTS']+(['CAPACITY_API'] if api else [])+(['CLIENT_RACE_HOOK'] if race_hook else []),'source_override':str(override) if override else None},indent=2),encoding='utf-8')
    print('PASS build',target,flush=True);return True

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('targets',nargs='+',choices=['win64','win32','fpc64','fpc-linux64','linux64'])
    ap.add_argument('--label',default='current');ap.add_argument('--source',type=Path)
    o=ap.parse_args();ok=True
    for t in o.targets:ok=build(t,o.label,o.source.resolve() if o.source else None) and ok
    raise SystemExit(0 if ok else 1)
