"""在已有 Linux 环境运行交叉编译产物，使用系统 OpenSSL 3。"""
import json
from pathlib import Path
import subprocess
import sys
from run_tests import MODES

binary = Path(sys.argv[1]).resolve()
directory = binary.parent
broken = directory / "libIncompleteCrypto.so"
logs = directory / "openssl3"
logs.mkdir(parents=True, exist_ok=True)
results = []
for mode in MODES:
    p = subprocess.run([str(binary), mode, "/usr/lib/x86_64-linux-gnu/libssl.so.3",
                        "/usr/lib/x86_64-linux-gnu/libcrypto.so.3", str(broken)],
                       capture_output=True, text=True, timeout=45)
    (logs / (mode + ".log")).write_text(p.stdout + p.stderr, encoding="utf-8")
    print(directory.name, p.stdout.strip(), flush=True)
    results.append(dict(mode=mode, returncode=p.returncode, output=p.stdout, error=p.stderr))
    (logs / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    if p.returncode:
        print(p.stderr, file=sys.stderr)
        raise SystemExit(p.returncode)
print(f"PASS {directory.name} {len(MODES)}/{len(MODES)}")
