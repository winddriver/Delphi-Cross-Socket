"""构建并运行组件回归和真实回环端点测试；不修改全局工具链配置。"""
from pathlib import Path
import subprocess,sys
T=Path(__file__).resolve().parent; R=T.parents[3]
D=Path(r'D:\Design\Delphi\D13.1'); CN=Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
LAZ=Path(r'D:\Design\FreePascal\lazarus\lazbuild.exe')
def run(args,log,cwd=T):
    p=subprocess.run(list(map(str,args)),cwd=cwd,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW,timeout=120)
    log.parent.mkdir(parents=True,exist_ok=True); log.write_bytes(p.stdout+p.stderr)
    if p.returncode:raise RuntimeError((p.stdout+p.stderr).decode(errors='replace')[-5000:])
    return p.stdout.decode(errors='replace')
for target in (sys.argv[1:] or ['win64','win32','win32-pieces','fpc64']):
    if target=='fpc64':
        for name in ('WebSocketFrameTests','WebSocketLoopback'):
            run([LAZ,'--build-all','--skip-dependencies',name+'.lpi'],T/'bin'/f'{name}-fpc-build.log')
        out=T/'bin/x86_64-win64'
    else:
        arch='win64' if target=='win64' else 'win32'; out=T/'bin'/('delphi-'+target); units=T/'lib'/('delphi-'+target)
        out.mkdir(parents=True,exist_ok=True);units.mkdir(parents=True,exist_ok=True)
        for name in ('WebSocketFrameTests','WebSocketLoopback'):
            defines='CROSS_OPENSSL_SELFTEST;WS_NEW_API'+(';__LITTLE_PIECE__' if target=='win32-pieces' else '')
            args=[D/'bin'/('dcc64.exe' if arch=='win64' else 'dcc32.exe'),'-Q','-B','-$O+','-D'+defines,'-NSSystem;System.Win;Winapi','-U'+';'.join(map(str,(R/'Net',R/'Utils',CN,D/'lib'/arch/'release'))),'-I'+str(R)+';'+str(CN),'-E'+str(out),'-N0'+str(units),T/(name+'.dpr')]
            run(args,T/'bin'/f'{name}-{target}-build.log')
    print(target,run([out/'WebSocketFrameTests.exe'],T/'bin'/f'tests-{target}.log').strip(),flush=True)
    print(target,run([sys.executable,T/'run_loopback.py',out/'WebSocketLoopback.exe'],T/'bin'/f'loopback-{target}.log').strip(),flush=True)
