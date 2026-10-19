"""编译实际生产单元的其他平台分支；不代表链接或设备运行验证。"""
from run_tests import D, F, LAZ, HERE, REPO, CN, run

targets = [("android", "dccaarm.exe", ""), ("android64", "dccaarm64.exe", ""),
           ("iosDevice64", "dcciosarm64.exe", ""), ("osx64", "dccosx64.exe", ""),
           ("osxarm64", "dccosxarm64.exe", ""), ("linux64-static", "dcclinux64.exe", "__SSL_STATIC__")]
for target, compiler, defines in targets:
    output = HERE / "lib" / ("delphi-" + target)
    output.mkdir(parents=True, exist_ok=True)
    args = [D / "bin" / compiler, "-Q", "-B", "-NSSystem;Posix",
            "-U" + str(REPO / "Net") + ";" + str(REPO / "Utils") + ";" + str(CN),
            "-I" + str(REPO), "-N0" + str(output)]
    if defines:
        args.append("-D" + defines)
    args.append(REPO / "Net/Net.CrossSslSocket.OpenSSL.pas")
    run(args, HERE / "bin" / ("delphi-" + target) / "compile.log")
    print("PASS unit compile " + target, flush=True)

output = HERE / "lib/fpc-linux64-static"
output.mkdir(parents=True, exist_ok=True)
args = [F / "ppcrossx64.exe", "-Tlinux", "-B", "-d__SSL_STATIC__",
        "-Fu" + str(REPO / "Net"), "-Fu" + str(REPO / "Utils"),
        "-Fu" + str(REPO / "DelphiToFPC"), "-Fu" + str(LAZ / "components/lazutils"),
        "-Fi" + str(REPO), "-FU" + str(output), REPO / "Net/Net.CrossSslSocket.OpenSSL.pas"]
run(args, HERE / "bin/fpc-linux64-static/compile.log")
print("PASS unit compile fpc-linux64-static", flush=True)
