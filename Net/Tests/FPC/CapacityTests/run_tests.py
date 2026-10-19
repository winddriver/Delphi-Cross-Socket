"""容量组件回归；每个用例在独立限时子进程中运行。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

CASES=['client-count','client-nil','client-raise','client-reenter','client-cancel',
       'client-concurrent','client-separate','client-sync-fail','client-default']

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('executable',type=Path)
    p.add_argument('--output',type=Path);p.add_argument('--cases',nargs='+',default=CASES)
    o=p.parse_args();exe=o.executable.resolve();rows=[]
    for case in o.cases:
        try:
            r=subprocess.run([str(exe),case],capture_output=True,timeout=15)
            try:output=(r.stdout+r.stderr).decode('utf-8')
            except UnicodeDecodeError:output=(r.stdout+r.stderr).decode('gb18030',errors='replace')
            row={'case':case,'passed':r.returncode==0,'code':r.returncode,'output':output}
        except subprocess.TimeoutExpired as exc:
            row={'case':case,'passed':False,'code':-1,'output':str(exc)}
        rows.append(row);print(case,'PASS' if row['passed'] else row['output'].strip(),flush=True)
        if o.output:o.output.write_text(json.dumps({'binary_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),
                                                   'results':rows},indent=2),encoding='utf-8')
    raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
