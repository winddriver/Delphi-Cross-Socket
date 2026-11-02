"""生成两份互不信任的短期证书，验证 HTTPS / WSS 客户端策略与双向握手。"""
import argparse
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
LIBDIR = REPO / "Net/OpenSSL.Libs/OpenSSL3/Windows/x64"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--openssl", type=Path, default=REPO / "Net/Tools/OpenSSL/openssl.exe")
    parser.add_argument("--ssl", default=str(LIBDIR / "libssl-3-x64.dll"))
    parser.add_argument("--crypto", default=str(LIBDIR / "libcrypto-3-x64.dll"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(dir=args.executable.resolve().parent) as tmp:
        root = Path(tmp)
        config = root / "cert.cnf"
        config.write_text("[req]\ndistinguished_name=dn\n[dn]\n", encoding="ascii")
        for name in ["server", "client"]:
            key_options = ["-nodes"] if name == "server" else ["-passout", "pass:test-passphrase"]
            subprocess.run([args.openssl, "req", "-x509", "-newkey", "rsa:2048", "-days", "2",
                            "-config", config, "-subj", "/CN=" + name,
                            "-addext", "basicConstraints=critical,CA:TRUE",
                            "-addext", "subjectAltName=DNS:localhost", *key_options,
                            "-out", root / (name + ".pem"), "-keyout", root / (name + ".key")],
                           check=True, capture_output=True)
        subprocess.run([args.executable.resolve(), "certificates", args.ssl, args.crypto,
                        root / "server.pem", root / "server.key", root / "client.pem", root / "client.key"],
                       check=True, timeout=100)


if __name__ == "__main__":
    main()
