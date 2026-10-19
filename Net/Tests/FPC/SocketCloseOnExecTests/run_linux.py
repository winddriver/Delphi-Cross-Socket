"""在 x86_64 glibc Linux 运行真实 socket / fork / exec 与进程内故障注入。"""
import ctypes
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


class Filter(ctypes.Structure):
    _fields_ = [("code", ctypes.c_ushort), ("jt", ctypes.c_ubyte),
                ("jf", ctypes.c_ubyte), ("k", ctypes.c_uint)]


class Program(ctypes.Structure):
    _fields_ = [("length", ctypes.c_ushort), ("filters", ctypes.POINTER(Filter))]


def deny(rules):
    # 所有规则仅在测试子进程生效；未匹配的系统调用保持允许。
    instructions = []
    for number, argument, mask, value, error in rules:
        body = []
        if argument is not None:
            body += [(0x20, 0, 0, 16 + 8 * argument)]  # seccomp_data.args
            if mask is not None:
                body += [(0x54, 0, 0, mask)]
            body += [(0x15, 0, 1, value)]
        body += [(0x06, 0, 0, 0x50000 | error)]  # SECCOMP_RET_ERRNO
        instructions += [(0x20, 0, 0, 0), (0x15, 0, len(body), number)] + body
    instructions += [(0x06, 0, 0, 0x7FFF0000)]  # SECCOMP_RET_ALLOW
    filters = (Filter * len(instructions))(*(Filter(*row) for row in instructions))
    program = Program(len(filters), filters)
    libc = ctypes.CDLL(None, use_errno=True)

    def install():
        if libc.prctl(38, 1, 0, 0, 0) or libc.prctl(22, 2, ctypes.byref(program), 0, 0):
            raise OSError(ctypes.get_errno(), "无法安装测试进程过滤器")
    return install


def main():
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise SystemExit("本脚本仅支持 x86_64 Linux")
    binary = Path(sys.argv[1]).resolve()
    output = ROOT / "bin" / "linux"
    output.mkdir(parents=True, exist_ok=True)
    inject = output / "accept4_inject.so"
    subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-Wall", "-Wextra", "-Werror",
                    str(ROOT / "accept4_inject.c"), "-ldl", "-o", str(inject)], check=True)
    # x86_64 Linux: socket=41, accept=43, fcntl=72。
    old_socket = (41, 1, 0x80000, 0x80000, 22)
    tests = [("normal", {}, []),
             ("missing", {"SOCKET_TEST_MISSING": "1"}, []),
             ("load-fail", {"SOCKET_TEST_LOAD_FAIL": "1"}, []),
             ("enosys", {"SOCKET_TEST_ACCEPT4_ERRNO": "38"}, []),
             ("fallback", {"SOCKET_TEST_MISSING": "1"}, [old_socket]),
             ("explicit", {}, [old_socket]),
             ("socket-error", {}, [(41, 1, 0x80000, 0x80000, 1)]),
             ("get-fail", {}, [old_socket, (72, 1, None, 1, 5)]),
             ("set-fail", {}, [old_socket, (72, 1, None, 2, 5)]),
             ("accept-set-fail", {"SOCKET_TEST_ACCEPT4_ERRNO": "38"}, [(72, 1, None, 2, 5)]),
             ("no-fcntl", {}, [(72, 1, None, 1, 5), (72, 1, None, 2, 5)])]
    tests += [("error " + str(error), {"SOCKET_TEST_ACCEPT4_ERRNO": str(error)},
               [(43, None, None, None, 13)]) for error in (4, 11, 22, 24, 1)]
    results = []
    for mode, extra, rules in tests:
        env = dict(os.environ, LD_PRELOAD=str(inject), **extra)
        result = subprocess.run([str(binary), *mode.split()], env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=20,
                                preexec_fn=deny(rules) if rules else None)
        print(mode + ": " + result.stdout.strip(), flush=True)
        results.append(dict(mode=mode, returncode=result.returncode,
                            stdout=result.stdout, stderr=result.stderr))
        (output / (binary.parent.name + "-results.json")).write_text(
            json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            raise SystemExit(result.returncode)
    print(f"PASS {len(tests)}/{len(tests)} real Linux scenarios")


if __name__ == "__main__":
    main()
