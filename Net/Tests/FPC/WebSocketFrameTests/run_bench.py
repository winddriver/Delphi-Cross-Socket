"""对照当前工作区与 bin/baseline；基线源码在修改前保存。"""
from pathlib import Path
from prepare_baseline import prepare
import subprocess, re, json, statistics, sys
TEST=Path(__file__).resolve().parent
ROOT=TEST.parents[3]
BASE=prepare()
DELPHI=Path(r'D:\Design\Delphi\D13.1')
CN=Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
FPC=Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64\fpc.exe')

def run(args,cwd,log):
    r=subprocess.run([str(x) for x in args],cwd=cwd,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW,timeout=90)
    log.write_bytes(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError((r.stdout+r.stderr).decode(errors='replace')[-5000:])
    return r.stdout.decode(errors='replace')

out={}
for arch in (sys.argv[1:] or ('win64','win32','fpc64')):
    for version,source in (('base',BASE),('new',ROOT)):
        dest=TEST/f'bin/bench-{arch}-{version}';dest.mkdir(parents=True,exist_ok=True)
        if arch=='fpc64':
            args=[FPC,'-B','-O2','-Fu'+str(source/'Net'),'-Fu'+str(source/'Utils'),'-Fu'+str(source/'DelphiToFPC'),'-FuD:/Design/FreePascal/lazarus/components/lazutils/lib/x86_64-win64','-Fi'+str(source),'-FE'+str(dest),'-FU'+str(dest)]
            if version=='new': args+=['-dWS_NEW_API']
            args+=[TEST/'WebSocketBench.lpr']
        else:
            compiler='dcc64.exe' if arch=='win64' else 'dcc32.exe'
            args=[DELPHI/'bin'/compiler,'-Q','-B','-$O+','-NSSystem;System.Win;Winapi','-U'+';'.join(map(str,(source/'Net',source/'Utils',CN,DELPHI/'lib'/arch/'release'))),'-I'+str(source)+';'+str(CN),'-E'+str(dest),'-N0'+str(dest)]
            if version=='new': args+=['-DWS_NEW_API']
            args+=[TEST/'WebSocketBench.dpr']
        run(args,TEST,dest/'build.log')
    samples={v:{} for v in ('base','new')}
    for round_no in range(5):
        for version in (('base','new') if round_no%2==0 else ('new','base')):
            dest=TEST/f'bin/bench-{arch}-{version}'
            text=run([dest/'WebSocketBench.exe'],TEST,dest/f'run-{round_no}.log')
            for name,ms in re.findall(r'BENCH (\S+) ms=([\d.]+)',text):
                samples[version].setdefault(name,[]).append(float(ms))
        print(f'{arch}: {round_no+1}/5',flush=True)
    out[arch]={}
    for name,old in samples['base'].items():
        new=samples['new'][name];a=statistics.median(old);b=statistics.median(new)
        out[arch][name]={'base_ms':a,'new_ms':b,'time_change_pct':round((b/a-1)*100,2),'base_samples':old,'new_samples':new}
    print(json.dumps({arch:out[arch]}),flush=True)
(TEST/'bin/benchmark-results.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
