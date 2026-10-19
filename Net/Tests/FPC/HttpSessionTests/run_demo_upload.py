"""运行已构建的正式 HttpServer 示例，真实 TLS multipart 上传并核对文件摘要。"""
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
PORT = 8080


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_free_port():
    """独占试绑定两个地址族；若有其他进程占用则退出，绝不停止它。"""
    guards = []
    try:
        for family, address in [(socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")]:
            guard = socket.socket(family, socket.SOCK_STREAM)
            guards.append(guard)
            guard.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            if family == socket.AF_INET6:
                guard.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            guard.bind((address, PORT))
    finally:
        for guard in guards:
            guard.close()


def listener_owners():
    # 当前测试环境的 Windows PowerShell CIM 查询可能静默给出空集合；使用实际TCP表。
    result = subprocess.run(["netstat.exe", "-ano"], capture_output=True, timeout=10,
                            check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    owners = set()
    for line in result.stdout.decode(errors="replace").splitlines():
        columns = line.split()
        if (len(columns) == 5 and columns[0] == "TCP" and columns[3] == "LISTENING"
                and columns[1].rsplit(":", 1)[-1] == str(PORT)):
            owners.add(int(columns[4]))
    return sorted(owners)


def loaded_openssl(pid):
    """核对实际子进程加载的库路径，不能只凭测试目录存在 DLL 推断。"""
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    psapi.EnumProcessModulesEx.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.HMODULE),
                                         wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.DWORD]
    psapi.GetModuleFileNameExW.argtypes = [wintypes.HANDLE, wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]
    handle = kernel.OpenProcess(0x0400 | 0x0010, False, pid)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        modules = (wintypes.HMODULE * 256)()
        needed = wintypes.DWORD()
        if not psapi.EnumProcessModulesEx(handle, modules, ctypes.sizeof(modules), ctypes.byref(needed), 3):
            raise ctypes.WinError(ctypes.get_last_error())
        assert needed.value <= ctypes.sizeof(modules), "module array too small"
        result = {}
        for module in modules[:needed.value // ctypes.sizeof(wintypes.HMODULE)]:
            name = ctypes.create_unicode_buffer(32768)
            if psapi.GetModuleFileNameExW(handle, module, name, len(name)):
                path = Path(name.value)
                if path.name.lower().startswith(("libssl", "libcrypto")):
                    result[path.name] = {"path": str(path), "sha256": digest(path)}
        assert len(result) == 2, result
        return result
    finally:
        kernel.CloseHandle(handle)


def multipart(files):
    boundary = "codex-upload-" + uuid.uuid4().hex
    body = bytearray()
    for index, (name, content) in enumerate(files):
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file{index}\"; "
                 f"filename=\"{name}\"\r\nContent-Type: application/octet-stream\r\n\r\n").encode("utf-8")
        body += content + b"\r\n"
    body += f"--{boundary}--\r\n".encode("ascii")
    return boundary, bytes(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=HERE / "bin/s03-formal-server/HttpServer.exe")
    parser.add_argument("--cert", type=Path, required=True, help="带有效CA约束/SAN的现有自签名测试证书")
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    assert os.name == "nt", "正式示例本轮为 Windows Release Win64"
    exe, cert, key = [p.resolve(strict=True) for p in (options.exe, options.cert, options.key)]
    require_free_port()
    assert not listener_owners(), "8080 被其他进程使用，未启动示例"
    output = options.output or exe.parent / ("upload-" + uuid.uuid4().hex)
    output = output.resolve()
    output.mkdir(parents=False, exist_ok=False)
    temp = output / "temp"
    temp.mkdir()
    runtime = output / "HttpServer.exe"
    shutil.copy2(exe, runtime)
    shutil.copy2(cert, output / "server.crt")
    shutil.copy2(key, output / "server.key")
    for name in ("libssl-3-x64.dll", "libcrypto-3-x64.dll"):
        shutil.copy2(REPO / "Net/Tools/OpenSSL" / name, output / name)
    assert digest(exe) == digest(runtime)
    sources = [REPO / "Net/Demos/Delphi/HttpServer/HttpServer.dpr", REPO / "Utils/Utils.Hash.pas",
               REPO / "Net/Net.CrossHttpServer.pas", REPO / "Net/Net.CrossHttpParams.pas",
               REPO / "Net/Net.CrossHttpSessions.pas", REPO / "Net/Net.CrossSslSocket.OpenSSL.pas"]
    report = {"recorded_utc": datetime.now(timezone.utc).isoformat(), "binary": str(exe),
              "binary_sha256": digest(exe), "runtime_binary": str(runtime),
              "script_sha256": digest(Path(__file__)),
              "certificate": str(cert), "certificate_sha256": digest(cert),
              "certificate_and_hostname_verification": True,
              "sources_at_run": {str(p.relative_to(REPO)): digest(p) for p in sources},
              "build_log_sha256": digest(exe.parent / "build.log"),
              "note": "运行既有MSBuild Release Win64产物；本脚本不编译，也不把当前依赖快照当作独立构建证明。",
              "cases": [], "stopped_by_enter": False}
    files = [("empty.bin", b""), ("中文-雪.txt", "中文、雪和🙂\n零字节前\x00零字节后".encode("utf-8")),
             ("bytes.bin", bytes(range(256)) * 257 + b"\x00\xff\x80end")]
    env = os.environ.copy()
    env["TEMP"] = str(temp)
    env["TMP"] = str(temp)
    process = None
    error = None
    with (output / "server.log").open("wb") as server_log:
        try:
            process = subprocess.Popen([str(runtime)], cwd=output, stdin=subprocess.PIPE,
                                       stdout=server_log, stderr=subprocess.STDOUT, env=env,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            report["pid"] = process.pid
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                assert process.poll() is None, "正式示例在监听前退出"
                owners = listener_owners()
                assert not any(owner != process.pid for owner in owners), "8080 出现其他进程，停止本脚本启动的示例"
                if process.pid in owners:
                    break
                time.sleep(0.1)
            else:
                raise TimeoutError("示例没有在8080监听")
            report["loaded_openssl"] = loaded_openssl(process.pid)
            for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
                context = ssl.create_default_context(cafile=str(cert))
                context.minimum_version = version
                context.maximum_version = version
                connection = http.client.HTTPSConnection("localhost", PORT, timeout=10, context=context)
                try:
                    connection.connect()
                    negotiated = connection.sock.version()
                    for repeat in range(2):
                        selected = files if repeat == 0 else list(reversed(files))
                        boundary, data = multipart(selected)
                        connection.request("POST", "/upload", body=data,
                                           headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
                        response = connection.getresponse()
                        text = response.read().decode("utf-8")
                        (output / f"response-{version.name}-{repeat}.txt").write_text(text, encoding="utf-8")
                        assert response.status == 200, (response.status, text)
                        rows = re.findall(r"FileName: ([^\r\n]+)\r?\nMD5: ([0-9a-fA-F]+)\r?\nSHA1: ([0-9a-fA-F]+)", text)
                        assert len(rows) == len(selected), text
                        checked = []
                        for (actual_name, md5, sha1), (name, content) in zip(rows, selected):
                            assert actual_name == name, (actual_name, name)
                            assert md5.lower() == hashlib.md5(content).hexdigest(), (name, "MD5", md5)
                            assert sha1.lower() == hashlib.sha1(content).hexdigest(), (name, "SHA1", sha1)
                            checked.append({"filename": name, "bytes": len(content), "md5": md5.lower(), "sha1": sha1.lower()})
                        report["cases"].append({"tls": negotiated, "repeat": repeat, "http_status": response.status,
                                                "hashes": checked, "passed": True})
                finally:
                    connection.close()
        except Exception as exception:
            error = repr(exception)
            report["error"] = error
        finally:
            if process is not None:
                if process.poll() is None:
                    try:
                        process.communicate(input=b"\r\n", timeout=15)
                        report["stopped_by_enter"] = True
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=10)
                        report["forced_stop"] = True
                report["exit_code"] = process.returncode
            report["remaining_listener_owners"] = listener_owners()
            # 正式示例没有启用AutoDeleteFiles，按原有默认语义保留上传文件。
            # 只在本脚本独占TEMP且子进程已结束后收集并清理，不把它称为示例自动清理。
            retained = [p for p in temp.rglob("*") if p.is_file()]
            report["retained_uploads_before_test_cleanup"] = [
                {"file": str(p.relative_to(temp)), "bytes": p.stat().st_size, "sha256": digest(p)} for p in retained]
            for path in retained:
                path.resolve().relative_to(temp.resolve())
                assert not path.is_symlink(), "测试TEMP中出现意外符号链接"
                path.unlink()
            report["remaining_temp_files"] = [str(p.relative_to(temp)) for p in temp.rglob("*") if p.is_file()]
            report["passed"] = (error is None and len(report["cases"]) == 4 and report["stopped_by_enter"]
                                and report.get("exit_code") == 0 and not report["remaining_listener_owners"]
                                and not report["remaining_temp_files"])
            (output / "results.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "output": str(output), "cases": len(report["cases"]),
                      "error": error, "stopped_by_enter": report["stopped_by_enter"]}, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
