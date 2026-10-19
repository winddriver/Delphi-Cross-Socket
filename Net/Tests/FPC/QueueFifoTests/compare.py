"""只比较相同测试源、相同目标的前后样本，不将微基准宣称为网络吞吐。"""
import argparse
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('before');parser.add_argument('after');parser.add_argument('targets',nargs='+')
options=parser.parse_args()
for target in options.targets:
    old=HERE/'bin'/options.before/target;new=HERE/'bin'/options.after/target
    a=json.loads((old/'source.json').read_text());b=json.loads((new/'source.json').read_text())
    for name,value in a.items():
        if '/QueueFifoTests/' in name.replace('\\','/') and b.get(name)!=value:raise RuntimeError('测试源不同: '+name)
    rows={(x['name'],x['depth']):x for x in json.loads((new/'benchmarks.json').read_text())}
    print(target)
    for prior in json.loads((old/'benchmarks.json').read_text()):
        current=rows[(prior['name'],prior['depth'])];x=prior['median_us'];y=current['median_us']
        print(f"{prior['name']:18s} {prior['depth']:5d}: {x:12.3f} -> {y:12.3f} us  {(y/x-1)*100:+.1f}%")
