"""FIFO排空基准及生命周期回归；输出保留原始样本和源哈希。"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
DELPHI=Path(r'D:\Design\Delphi\D13.1')
FPC=Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ=Path(r'D:\Design\FreePascal\lazarus')
CN=Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
SDK=Path.home()/'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'
CASES=['request-concurrent','request-wrap','request-cancel','response-ready-order','response-concurrent','response-cancel','response-lifetime']
SOURCES=[REPO/'Net'/name for name in ('Net.CrossHttpServer.pas','Net.CrossHttpClient.pas',
         'Net.CrossSocket.Epoll.pas','Net.CrossSocket.Kqueue.pas','Net.CrossSocket.Base.pas',
         'Net.CrossHttpParser.pas','Net.CrossHttpParams.pas','Net.CrossHttpUtils.pas',
         'Net.CrossSslSocket.Base.pas','Net.CrossSslSocket.OpenSSL.pas','Net.OpenSSL.pas')]
SOURCES.append(REPO/'DelphiToFPC/DTF.Generics.pas')

def build(target,label):
    out=HERE/'bin'/label/target;units=HERE/'lib'/label/target
    out.mkdir(parents=True,exist_ok=True);units.mkdir(parents=True,exist_ok=True)
    linux='linux' in target
    queue_api=bool(re.search(r'TSendQueue\s*=\s*class\(TQueue',SOURCES[2].read_text(encoding='utf-8-sig')))
    paths=SOURCES+[HERE/'QueueFifoTests.lpr',HERE/'QueueRegressions.inc',HERE/'QueueSocketTests.inc']
    metadata={str(p.relative_to(REPO)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    defines=['FIFO_QUEUE_API'] if queue_api else []
    if target.startswith('fpc'):
        args=[FPC/('ppcrossx64.exe' if linux else 'fpc.exe'),'-B','-O2',
              '-Fu'+str(REPO/'Net'),'-Fu'+str(REPO/'Utils'),'-Fu'+str(REPO/'DelphiToFPC'),
              '-Fu'+str(LAZ/('components/lazutils' if linux else 'components/lazutils/lib/x86_64-win64')),
              '-Fi'+str(REPO),'-FE'+str(out),'-FU'+str(units)]
        if linux:args+=['-Tlinux']
        args+=['-d'+d for d in defines]+[HERE/'QueueFifoTests.lpr']
    else:
        arch='linux64' if linux else ('win32' if '32' in target else 'win64')
        args=[DELPHI/'bin'/('dcclinux64.exe' if linux else ('dcc32.exe' if arch=='win32' else 'dcc64.exe')),
              '-Q','-B','-$O+','-NSSystem;'+('Posix' if linux else 'System.Win;Winapi'),
              '-U'+';'.join(map(str,[REPO/'Net',REPO/'Utils',CN,DELPHI/'lib'/arch/'release'])),
              '-I'+str(REPO)+';'+str(CN),'-E'+str(out),'-N0'+str(units)]
        if defines:args+=['-D'+';'.join(defines)]
        if linux:
            libs=[DELPHI/'lib/linux64/release',SDK/'usr/lib/x86_64-linux-gnu',SDK/'lib/x86_64-linux-gnu',SDK/'usr/lib/gcc/x86_64-linux-gnu/11']
            args+=['--syslibroot:'+str(SDK),'--libpath:'+';'.join(map(str,libs))]
        args+=[HERE/'QueueFifoTests.dpr']
    result=subprocess.run(list(map(str,args)),cwd=HERE,capture_output=True,timeout=120,
                          creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (out/'build.log').write_bytes(result.stdout+result.stderr)
    if result.returncode:
        print((result.stdout+result.stderr).decode(errors='replace')[-7000:]);raise SystemExit(result.returncode)
    changed=[str(p.relative_to(REPO)) for p in paths if hashlib.sha256(p.read_bytes()).hexdigest()!=metadata[str(p.relative_to(REPO))]]
    if changed:raise RuntimeError('构建期间源码变化，必须重建: '+','.join(changed))
    (out/'source.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    print('PASS build',target,'queue_api=',queue_api,flush=True)

def run(target,label,samples,regression_only,bench_only):
    out=HERE/'bin'/label/target;exe=out/('QueueFifoTests'+('' if 'linux' in target else '.exe'))
    results=[];benchmarks=[]
    def invoke(args,filename):
        try:
            r=subprocess.run([str(exe)]+list(map(str,args)),cwd=HERE,capture_output=True,timeout=60,
                             creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            text=(r.stdout+r.stderr).decode('utf-8' if 'linux' in target else 'gb18030',errors='replace');code=r.returncode
        except subprocess.TimeoutExpired as e:text=str(e);code=-1
        (out/filename).write_text(text,encoding='utf-8')
        if code:print(target,args,code,text,flush=True)
        return code,text
    if not bench_only:
        for case in CASES+(['socket-ownership'] if 'linux' in target else []):
            code,text=invoke([case],case+'.log');results.append({'case':case,'code':code,'output':text})
            print(target,case,'PASS' if not code else 'FAIL',flush=True)
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    if not regression_only:
        names=['request','response']+(['socket-container'] if 'linux' in target else [])
        for name in names:
            for depth in (1,100,1000,10000):
                values=[]
                for sample in range(samples+1):
                    code,text=invoke(['bench',name,depth],f'{name}-{depth}-{sample}.log')
                    if code:raise RuntimeError('benchmark failed')
                    match=re.search(r'us=([\d.]+) heap_queued=(-?\d+) heap_drained=(-?\d+)',text)
                    if not match:raise RuntimeError(text)
                    # 第0次是独立预热样本，保留原文但不计入统计。
                    if sample:values.append({'us':float(match[1]),
                        'heap_queued':int(match[2]) if int(match[2])>=0 else None,
                        'heap_drained':int(match[3]) if int(match[3])>=0 else None})
                row={'name':name,'depth':depth,'samples':values,'median_us':statistics.median(x['us'] for x in values)}
                benchmarks.append(row);print(target,name,depth,row['median_us'],'us',flush=True)
        (out/'benchmarks.json').write_text(json.dumps(benchmarks,indent=2),encoding='utf-8')
    return all(r['code']==0 for r in results)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('targets',nargs='+')
    p.add_argument('--label',default='baseline');p.add_argument('--samples',type=int,default=5)
    p.add_argument('--run-only',action='store_true');p.add_argument('--build-only',action='store_true')
    p.add_argument('--regression-only',action='store_true');p.add_argument('--bench-only',action='store_true')
    o=p.parse_args();ok=True
    if not re.fullmatch(r'[A-Za-z0-9_-]+',o.label):p.error('invalid label')
    for target in o.targets:
        if not o.run_only:build(target,o.label)
        if not o.build_only:ok=run(target,o.label,o.samples,o.regression_only,o.bench_only) and ok
    raise SystemExit(0 if ok else 1)
