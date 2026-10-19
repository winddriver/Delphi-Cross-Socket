"""完整构建目录 HTTP 回归或独立目录性能组件，输出按标签隔离。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")


def build(target, label, bench=False, new_api=False, hooks=False, resources=False):
    project = "DirectoryResourceTests" if resources else "DirectoryBench" if bench else "HttpDirectoryTests"
    flavor = label + "-" + target
    output, units = HERE / "bin" / flavor, HERE / "lib" / flavor / project
    output.mkdir(parents=True, exist_ok=True)
    units.mkdir(parents=True, exist_ok=True)
    if target == "fpc-win64":
        args = [r"D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe", "-B",
                "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"),
                "-Fu" + str(REPO / "DelphiToFPC"),
                r"-FuD:\Design\FreePascal\lazarus\components\lazutils\lib\x86_64-win64",
                "-Fi" + str(REPO), "-FE" + str(output), "-FU" + str(units), HERE / (project + ".lpr")]
    else:
        args = [DELPHI / "bin/dcc64.exe", "-Q", "-B", "-NSSystem;System.Win;Winapi",
                "-U" + ";".join(map(str, (REPO / "Net", REPO / "Utils", DELPHI / "lib/win64/release"))),
                "-I" + str(REPO), "-E" + str(output), "-N0" + str(units), HERE / (project + ".dpr")]
    defines = []
    if new_api:
        defines.append("DIRECTORY_LIMIT_API")
    if hooks:
        defines.append("CROSS_HTTP_DIRECTORY_TESTS")
    if target == "fpc-win64":
        args[1:1] = ["-d" + define for define in defines]
    elif defines:
        args.insert(1, "-D" + ";".join(defines))
    result = subprocess.run(list(map(str, args)), cwd=HERE, capture_output=True, timeout=120,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    (output / (project + ".build.log")).write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode(errors="replace")[-7000:])
        raise SystemExit(result.returncode)
    sources = [REPO / "Net/Net.CrossHttpRouter.pas", REPO / "Net/Net.CrossHttpRouterDirUtils.pas",
               HERE / (project + ".lpr")]
    (output / (project + ".source.json")).write_text(json.dumps(
        {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2), encoding="utf-8")
    print("PASS build", project, flavor)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+", choices=["delphi-win64", "fpc-win64"])
    parser.add_argument("--label", required=True)
    parser.add_argument("--bench", action="store_true")
    parser.add_argument("--new-api", action="store_true")
    parser.add_argument("--hooks", action="store_true")
    parser.add_argument("--resources", action="store_true")
    args = parser.parse_args()
    for selected in args.targets:
        build(selected, args.label, args.bench, args.new_api, args.hooks, args.resources)
