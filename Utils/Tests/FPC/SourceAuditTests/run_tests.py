"""构建当前源码并在隔离目录运行文件、哈希、Punycode 与 FPC 读取器回归。"""
from pathlib import Path
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DELPHI = Path(r"D:\Design\Delphi\D13.1")
FPC = Path(r"D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe")


def run():
    failures = 0
    for name in ("delphi", "fpc"):
        out = HERE / "bin" / name
        out.mkdir(parents=True, exist_ok=True)
        if name == "delphi":
            args = [DELPHI / "bin/dcc64.exe", "-B", "-Q", "-NSSystem;System.Win;Winapi",
                    "-U" + str(REPO / "Utils") + ";" + str(DELPHI / "lib/win64/release"),
                    "-I" + str(REPO), "-N0" + str(out), "-E" + str(out), HERE / "SourceAuditTests.dpr"]
        else:
            args = [FPC, "-B", "-O2", "-Fu" + str(REPO / "Utils"), "-Fu" + str(REPO / "DelphiToFPC"),
                    r"-FuD:\Design\FreePascal\lazarus\components\lazutils", "-Fi" + str(REPO),
                    "-FU" + str(out), "-FE" + str(out), HERE / "SourceAuditTests.lpr"]
        build = subprocess.run(args, cwd=out, capture_output=True, timeout=120)
        if build.returncode:
            print((build.stdout + build.stderr).decode(errors="replace")[-2500:])
            return 1
        for case in ["hash", "buffer", "move", "punycode"] + (["reader"] if name == "fpc" else []):
            folder = out / (case + "-" + uuid.uuid4().hex)
            folder.mkdir()
            try:
                result = subprocess.run([out / "SourceAuditTests.exe", case], cwd=folder, timeout=15)
                failures += result.returncode != 0
            finally:
                for item in folder.iterdir():
                    item.unlink()
                folder.rmdir()
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(run())
