"""默认无额度：真实Owner.Send的1字节排队成本，时间与RTL申请分开测量。"""
import argparse
import json
from pathlib import Path
import statistics
import sys
sys.dont_write_bytecode=True
from run_socket import run

HERE=Path(__file__).resolve().parent

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8',errors='backslashreplace')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('targets',nargs='+')
    p.add_argument('--before',required=True);p.add_argument('--after',required=True)
    p.add_argument('--samples',type=int,default=5);p.add_argument('--count',type=int,default=10000)
    o=p.parse_args()
    for target in o.targets:
        paths={label:(HERE/'bin'/label/target/('CapacityTests'+('' if 'linux' in target else '.exe'))).resolve()
               for label in (o.before,o.after)}
        rows=[]
        for i in range(o.samples+1):
            pair={'index':i,'warmup':i==0}
            labels=[o.before,o.after]
            if i%2:labels.reverse()
            for label in labels:
                row=run(paths[label],'socket-bench-time',o.count)
                if not row['passed'] or row['metric'] is None:raise RuntimeError(row)
                pair[label]=row
            rows.append(pair)
        summary={};allocations={}
        for label in (o.before,o.after):
            values=[r[label]['metric']['enqueue_us'] for r in rows if not r['warmup']]
            q=statistics.quantiles(values,n=4,method='inclusive')
            summary[label]={'median_us':statistics.median(values),'iqr_us':q[2]-q[0],
                            'per_send_ns':statistics.median(values)*1000/o.count}
            allocations[label]=run(paths[label],'socket-bench-alloc',o.count)
            if not allocations[label]['passed']:raise RuntimeError(allocations[label])
        output={'n':o.count,'pairs':rows,'summary':summary,'allocation':allocations}
        (HERE/'bin'/o.after/target/'send-bench.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
        print(target,summary,{k:v['metric'] for k,v in allocations.items()},flush=True)
