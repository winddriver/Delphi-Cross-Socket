"""独立验证FPC队列尾槽兼容层；--raw保留未适配RTL的红例。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
import run_tests as config

def build(target,raw):
    out=config.HERE/'bin'/('managed-raw' if raw else 'managed-fixed')/target
    units=config.HERE/'lib'/('managed-raw' if raw else 'managed-fixed')/target
    out.mkdir(parents=True,exist_ok=True);units.mkdir(parents=True,exist_ok=True)
    linux='linux' in target;source=config.HERE/'QueueManagedTests.lpr'
    if target.startswith('fpc'):
        args=[config.FPC/('ppcrossx64.exe' if linux else 'fpc.exe'),'-B','-O2',
              '-Fu'+str(config.REPO/'DelphiToFPC'),'-Fi'+str(config.REPO),'-FE'+str(out),'-FU'+str(units)]
        if linux:args+=['-Tlinux']
        if raw:args+=['-dRAW_QUEUE']
    else:
        arch='linux64' if linux else ('win32' if '32' in target else 'win64')
        args=[config.DELPHI/'bin'/('dcclinux64.exe' if linux else ('dcc32.exe' if arch=='win32' else 'dcc64.exe')),
              '-Q','-B','-$O+','-NSSystem;'+('Posix' if linux else 'System.Win;Winapi'),
              '-U'+str(config.DELPHI/'lib'/arch/'release'),'-I'+str(config.REPO),'-E'+str(out),'-N0'+str(units)]
        if linux:
            libs=[config.DELPHI/'lib/linux64/release',config.SDK/'usr/lib/x86_64-linux-gnu',config.SDK/'lib/x86_64-linux-gnu',config.SDK/'usr/lib/gcc/x86_64-linux-gnu/11']
            args+=['--syslibroot:'+str(config.SDK),'--libpath:'+';'.join(map(str,libs))]
    args+=[source]
    r=subprocess.run(list(map(str,args)),cwd=config.HERE,capture_output=True,timeout=90,
                     creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (out/'build.log').write_bytes(r.stdout+r.stderr)
    if r.returncode:print((r.stdout+r.stderr).decode(errors='replace'));raise SystemExit(r.returncode)
    paths=[source,config.REPO/'DelphiToFPC/DTF.Generics.pas']
    (out/'source.json').write_text(json.dumps({str(p.relative_to(config.REPO)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2),encoding='utf-8')
    print('PASS build',target,raw,flush=True)

def run(target,raw):
    out=config.HERE/'bin'/('managed-raw' if raw else 'managed-fixed')/target
    exe=out/('QueueManagedTests'+('' if 'linux' in target else '.exe'));rows=[]
    for case in ('interface','record','string','capacity'):
        r=subprocess.run([str(exe),case],cwd=config.HERE,capture_output=True,timeout=15,
                         creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        text=(r.stdout+r.stderr).decode('utf-8' if 'linux' in target else 'gb18030',errors='replace')
        rows.append({'case':case,'code':r.returncode,'output':text});print(target,raw,case,r.returncode,text.strip(),flush=True)
    (out/'results.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    return all(r['code']==0 for r in rows)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('targets',nargs='+');p.add_argument('--raw',action='store_true')
    p.add_argument('--run-only',action='store_true');p.add_argument('--build-only',action='store_true');o=p.parse_args();ok=True
    for target in o.targets:
        if not o.run_only:build(target,o.raw)
        if not o.build_only:ok=run(target,o.raw) and ok
    raise SystemExit(0 if ok else 1)
