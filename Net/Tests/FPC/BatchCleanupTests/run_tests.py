"""批量清理回归及实际锁内收集/删除计时；不报告请求P99。"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[3]
D=Path(r'D:\Design\Delphi\D13.1');FPC=Path(r'D:\Design\FreePascal\fpc\bin\x86_64-win64')
LAZ=Path(r'D:\Design\FreePascal\lazarus');CN=Path(r'D:\Design\Delphi\VclFmxRtl\cncrypto\Source')
SDK=Path.home()/'Documents/Embarcadero/Studio/SDKs/ubuntu22.04.sdk'
CASES=['session-release','session-exception','session-renew','session-replace','session-concurrent-touch']
SOURCES=[REPO/'Net'/n for n in ('Net.CrossHttpParams.pas','Net.CrossHttpClient.pas','Net.CrossHttpParser.pas','Net.CrossSslSocket.OpenSSL.pas','Net.CrossSocket.Base.pas','Net.CrossSocket.Epoll.pas','Net.CrossSocket.Kqueue.pas')]
SOURCES += [REPO/'DelphiToFPC/DTF.Generics.pas',REPO/'Utils/Utils.ArrayUtils.pas',REPO/'Utils/Utils.SyncObjs.pas']

def hashes(override,session_only=False):
    paths=SOURCES+[HERE/'BatchCleanupTests.lpr',HERE/'BatchCleanupTests.dpr']+sorted(HERE.glob('*.inc'))
    if session_only:paths=[p for p in paths if p.name not in ('ClientTimeoutTests.inc','SocketBatchTests.inc') and not p.name.startswith(('Net.CrossSocket','Net.CrossHttpClient','Net.CrossHttpParser','Net.CrossSslSocket'))]
    return {p.relative_to(REPO).as_posix():hashlib.sha256(
        (override/p.name if override and (override/p.name).is_file() else p).read_bytes()).hexdigest() for p in paths}

def build(target,label,override,debug=False,session_only=False):
    out=HERE/'bin'/label/target;units=HERE/'lib'/label/target
    out.mkdir(parents=True,exist_ok=True);units.mkdir(parents=True,exist_ok=True);before=hashes(override,session_only)
    linux='linux' in target;search=([override] if override else [])+[REPO/'Net',REPO/'Utils',REPO/'DelphiToFPC']
    if target.startswith('fpc'):
        args=[FPC/('ppcrossx64.exe' if linux else 'fpc.exe'),'-B','-O2','-dCROSS_SESSION_TESTS','-dCROSS_HTTP_TIMEOUT_TESTS']
        if debug:args+=['-dDEBUG']
        if session_only:args+=['-dSESSION_ONLY']
        args+=['-Fu'+str(p) for p in search]
        args+=['-Fu'+str(LAZ/('components/lazutils' if linux else 'components/lazutils/lib/x86_64-win64')),
               '-Fi'+str(REPO),'-FE'+str(out),'-FU'+str(units)]
        if linux:args+=['-Tlinux']
        args+=[HERE/'BatchCleanupTests.lpr']
    else:
        arch='linux64' if linux else ('win32' if target=='win32' else 'win64')
        args=[D/'bin'/('dcclinux64.exe' if linux else ('dcc32.exe' if arch=='win32' else 'dcc64.exe')),
              '-Q','-B','-$O+','-DCROSS_SESSION_TESTS;CROSS_HTTP_TIMEOUT_TESTS'+(';DEBUG' if debug else '')+(';SESSION_ONLY' if session_only else ''),'-NSSystem;'+('Posix' if linux else 'System.Win;Winapi'),
              '-U'+';'.join(map(str,search+[CN,D/'lib'/arch/'release'])),'-I'+str(REPO)+';'+str(CN),
              '-E'+str(out),'-N0'+str(units)]
        if linux:
            libs=[D/'lib/linux64/release',SDK/'usr/lib/x86_64-linux-gnu',SDK/'lib/x86_64-linux-gnu',SDK/'usr/lib/gcc/x86_64-linux-gnu/11']
            args+=['--syslibroot:'+str(SDK),'--libpath:'+';'.join(map(str,libs))]
        args+=[HERE/'BatchCleanupTests.dpr']
    r=subprocess.run(list(map(str,args)),cwd=HERE,capture_output=True,timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (out/'build.log').write_bytes(r.stdout+r.stderr)
    if r.returncode:print((r.stdout+r.stderr).decode(errors='replace')[-7000:]);return False
    if before!=hashes(override,session_only):raise RuntimeError('构建期间源码变化')
    (out/'source.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    (out/'config.json').write_text(json.dumps({'target':target,'debug':debug,'session_only':session_only,'source_override':str(override) if override else None},indent=2),encoding='utf-8')
    print('PASS build',target,flush=True);return True

def run(target,options):
    out=HERE/'bin'/options.label/target;exe=out/('BatchCleanupTests'+('' if 'linux' in target else '.exe'))
    results=[];benches=[]
    def invoke(args,name):
        try:
            r=subprocess.run([str(exe)]+list(map(str,args)),cwd=out,capture_output=True,timeout=60,
                             creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            code=r.returncode;text=(r.stdout+r.stderr).decode('utf-8' if 'linux' in target else 'gb18030',errors='replace')
        except subprocess.TimeoutExpired as e:code=-1;text=str(e)
        (out/(name+'.log')).write_text(text,encoding='utf-8')
        return {'code':code,'output':text}
    if options.tail_only:
        row=invoke(['tail-session-idle'],'tail-session-idle')
        matches=re.findall(r'TAIL sample=(\d+) total_us=([\d.]+) lock_us=([\d.]+)',row['output'])
        if row['code'] or len(matches)!=100:raise RuntimeError(row['output'])
        samples=[{'index':int(i),'total_us':float(t),'lock_us':float(l)} for i,t,l in matches]
        summary={}
        for key in ('total_us','lock_us'):
            values=sorted(s[key] for s in samples)
            summary[key]={'median':statistics.median(values),'p99':values[98],'max':values[-1]}
        (out/'tail.json').write_text(json.dumps({'warmups':10,'samples':samples,'summary':summary},indent=2),encoding='utf-8')
        print(target,'tail',summary,flush=True)
        return True
    if options.sparse_only:
        for expired in (0,1):
            values=[]
            for sample in range(options.samples+1):
                row={'warmup':sample==0,**invoke(['bench-session-sparse',expired],f'sparse-{expired}-{sample}')}
                m=re.search(r'total_us=([\d.]+) lock_us=([\d.]+) collect_us=([\d.]+) remove_us=([\d.]+)',row['output'])
                if row['code'] or not m:raise RuntimeError(row['output'])
                row.update(zip(('total_us','lock_us','collect_us','remove_us'),map(float,m.groups())));values.append(row)
            allocation=invoke(['alloc-session-sparse',expired],f'sparse-alloc-{expired}')
            m=re.search(r'alloc_calls=(\d+) requested_bytes=(\d+) largest_request=(\d+)',allocation['output'])
            if allocation['code'] or not m:raise RuntimeError(allocation['output'])
            allocation.update(zip(('alloc_calls','requested_bytes','largest_request'),map(int,m.groups())))
            summary={key:statistics.median(v[key] for v in values if not v['warmup']) for key in ('total_us','lock_us','collect_us','remove_us')}
            benches.append({'n':10000,'expired':expired,'samples':values,'median':summary,'allocation':allocation})
            print(target,'sparse',expired,summary,allocation['output'].strip(),flush=True)
        (out/'sparse.json').write_text(json.dumps(benches,indent=2),encoding='utf-8')
        return not options.check_sparse_alloc or all(b['allocation']['largest_request']<4096 for b in benches)
    if not options.bench_only:
        for case in CASES:
            row={'case':case,**invoke([case],case)};results.append(row)
            print(target,case,row['code'],row['output'].strip(),flush=True)
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    if not options.regression_only:
        for count in (0,1,100,1000,10000):
            values=[]
            for sample in range(options.samples+1):
                row={'warmup':sample==0,**invoke(['bench-session',count],f'session-{count}-{sample}')}
                m=re.search(r'total_us=([\d.]+) lock_us=([\d.]+) collect_us=([\d.]+) remove_us=([\d.]+)',row['output'])
                if row['code'] or not m:raise RuntimeError(row['output'])
                row.update(zip(('total_us','lock_us','collect_us','remove_us'),map(float,m.groups())));values.append(row)
            summary={key:statistics.median(v[key] for v in values if not v['warmup']) for key in ('total_us','lock_us','collect_us','remove_us')}
            benches.append({'n':count,'samples':values,'median':summary});print(target,count,summary,flush=True)
        (out/'benchmarks.json').write_text(json.dumps(benches,indent=2),encoding='utf-8')
    return all(r['code']==0 for r in results)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('targets',nargs='+')
    p.add_argument('--label',default='before');p.add_argument('--source',type=Path)
    p.add_argument('--run-only',action='store_true');p.add_argument('--build-only',action='store_true')
    p.add_argument('--debug',action='store_true')
    p.add_argument('--session-only',action='store_true');p.add_argument('--sparse-only',action='store_true')
    p.add_argument('--tail-only',action='store_true')
    p.add_argument('--check-sparse-alloc',action='store_true',help='0/1过期场景不得出现整表规模的RTL申请')
    p.add_argument('--regression-only',action='store_true');p.add_argument('--bench-only',action='store_true');p.add_argument('--samples',type=int,default=5)
    o=p.parse_args();ok=True
    if o.source:o.source=o.source.resolve()
    for target in o.targets:
        if not o.run_only and not build(target,o.label,o.source,o.debug,o.session_only):ok=False;continue
        if not o.build_only:ok=run(target,o) and ok
    raise SystemExit(0 if ok else 1)
