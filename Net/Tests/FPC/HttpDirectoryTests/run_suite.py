"""组合执行已有安全回归、新增页面行为和资源清理测试；每个请求仍有独立超时。"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["delphi-win64", "fpc-win64", "delphi-linux64", "fpc-linux64"])
    parser.add_argument("--label", default="final")
    parser.add_argument("--red", action="store_true")
    args = parser.parse_args()
    failed = False
    extension = ".exe" if os.name == "nt" else ""
    for target in args.targets:
        assert target.endswith("win64" if os.name == "nt" else "linux64"), "运行环境与目标不一致"
        label = "listing-baseline" if args.red else args.label
        resource_label = "resource-baseline2" if args.red else args.label
        executable = HERE / "bin" / (label + "-" + target) / ("HttpDirectoryTests" + extension)
        baseline = HERE / "bin" / ("listing-baseline-" + target) / ("HttpDirectoryTests" + extension)
        resource = HERE / "bin" / (resource_label + "-" + target) / ("DirectoryResourceTests" + extension)
        cases = [("listing", "run_listing_tests.py", [executable, "--baseline", baseline]),
                 ("resource", "run_resource_tests.py", [resource])]
        if not args.red:
            cases.insert(0, ("security", "run_tests.py", [executable]))
        for name, script, arguments in cases:
            report = HERE / "bin" / (name + "-" + ("red-final" if args.red else args.label) + "-" + target + ".json")
            process = subprocess.run([sys.executable, "-B", str(HERE / script), *map(str, arguments),
                                      "--report", str(report)], cwd=HERE, capture_output=True, timeout=180)
            failed |= process.returncode != 0
            if report.exists():
                records = json.loads(report.read_text(encoding="utf-8"))["results"]
                summary = {status: sum(r["status"] == status for r in records) for status in ("pass", "fail", "skip")}
                print(target, name, summary, flush=True)
            if process.returncode and not args.red:
                print(process.stdout.decode("utf-8", errors="replace"), process.stderr.decode("utf-8", errors="replace"))
    raise SystemExit(failed)


if __name__ == "__main__":
    main()
