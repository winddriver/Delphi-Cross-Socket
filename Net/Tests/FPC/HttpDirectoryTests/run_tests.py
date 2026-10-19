"""检查真实目录 HTTP 输出，解析 HTML 并沿生成链接再次下载文件。"""
import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid
from urllib.parse import quote, urljoin, urlsplit

HERE = Path(__file__).resolve().parent
DIR = "nested 中文 &copy;%+"
NAMES = ["plain.txt", "name&copy;.txt", "中文 空格%+.txt", "quote'file.txt"]
CASES = ["reflected-tag", "reflected-attribute", "canonical-breadcrumb", "root",
         "root-slash", "nested", "nested-slash", "filename-entities", "extensionless-entries", "download-special",
         "breadcrumb-parent", "mount-root", "mount-special", "download-direct",
         "traversal-outside", "traversal-encoded", "linux-html-filename", "linux-quote-filename"]


class Page(HTMLParser):
    def __init__(self, body):
        super().__init__(convert_charrefs=True)
        self.anchors = []
        self.current = None
        self.unsafe = []
        self.feed(body.decode("utf-8"))

    def handle_starttag(self, tag, attrs):
        if tag not in {"html", "head", "style", "title", "meta", "body", "table", "tr", "td", "a", "b", "font", "br", "div"}:
            self.unsafe.append("unexpected tag: " + tag)
        for name, value in attrs:
            if name.startswith("on"):
                self.unsafe.append("event attribute: " + name)
        if tag == "a":
            href = dict(attrs).get("href")
            assert href is not None, "链接缺少 href"
            self.current = [href, ""]
            self.anchors.append(self.current)

    def handle_data(self, data):
        if self.current is not None:
            self.current[1] += data

    def handle_endtag(self, tag):
        if tag == "a":
            self.current = None

    def safe(self):
        assert not self.unsafe, "; ".join(self.unsafe)
        return self

    def href(self, label):
        values = [href for href, text in self.anchors if text == label]
        assert values, "没有保持原始文本的链接: " + label
        return values[0]


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    # Linux 使用本地临时文件系统，避免 /mnt/d 的 Windows 文件名限制。
    parent = Path(tempfile.gettempdir()) if os.name != "nt" else HERE / "bin" / "fixtures"
    parent.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        # Python 3.13 的 mkdtemp(0700) 会排除沙箱 SID；沿用工作区继承权限。
        root = parent / ("http-directory-" + uuid.uuid4().hex)
        root.mkdir()
        root = root.resolve()
    else:
        root = Path(tempfile.mkdtemp(prefix="http-directory-", dir=parent)).resolve()
    base = root / "www"
    base.mkdir()
    (root / "outside.txt").write_bytes(b"outside-secret")
    for name in NAMES:
        (base / name).write_bytes(("body:" + name).encode("utf-8"))
    (base / "LICENSE").write_bytes(b"extensionless-file")
    (base / "plain-directory").mkdir()
    (base / "plain-directory" / "child").write_bytes(b"extensionless-child")
    nested = base / DIR
    (nested / "second.dir").mkdir(parents=True)
    (nested / "plain.txt").write_bytes(b"nested-file")
    (nested / "second.dir" / "deep.txt").write_bytes(b"deep-file")
    results = []

    def request(target, mount="/files"):
        result = subprocess.run([str(executable), str(base), target, quote(mount, safe="/")], capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        header, separator, body = result.stdout.partition(b"\r\n\r\n")
        assert separator, "缺少响应头边界"
        lines = header.split(b"\r\n")
        assert lines[0].startswith(b"HTTP/1.1 "), repr(lines[0])
        status = int(lines[0].split()[1])
        fields = dict(line.split(b":", 1) for line in lines[1:])
        lengths = [value for key, value in fields.items() if key.lower() == b"content-length"]
        assert lengths and int(lengths[0]) == len(body), "正文长度不一致"
        return status, body

    def listing(target, mount="/files"):
        status, body = request(target, mount)
        assert status == 200, f"目录返回 {status}"
        return Page(body).safe()

    def follow(page, label, target, expected, mount="/files"):
        href = page.href(label)
        assert all(ord(char) < 128 for char in href), "链接未按 UTF-8 URL 编码"
        assert " " not in href and '"' not in href, "链接残留未编码字符"
        url = urlsplit(urljoin("http://test" + target, href))
        assert url.netloc == "test" and url.scheme == "http", "生成链接离开本站"
        status, body = request(url.path + ("?" + url.query if url.query else ""), mount)
        assert status == 200 and body == expected, f"链接目标错误: {href!r} -> {status}"

    try:
        for case in CASES:
            if case.startswith("linux-") and os.name == "nt":
                results.append({"case": case, "status": "skip", "detail": "Windows 不允许该文件名，仅在 Linux 运行"})
                print("SKIP:", case)
                continue
            try:
                if case.startswith("reflected-"):
                    payload = '<svg onload=alert(1)>' if case == "reflected-tag" else '" onmouseover="alert(1)'
                    target = "/files/" + quote(payload + "/../", safe="")
                    page = listing(target)
                    assert not any("alert(1)" in href or "alert(1)" in text for href, text in page.anchors), "导航仍使用已折叠的原始路径"
                    follow(page, "plain.txt", target, b"body:plain.txt")
                elif case == "canonical-breadcrumb":
                    page = listing("/files/missing%2F..%2F")
                    assert not any(text in {"missing", ".."} for _, text in page.anchors), "导航没有使用规范化路径"
                elif case in {"root", "root-slash"}:
                    target = "/files" + ("/" if case.endswith("slash") else "")
                    follow(listing(target), "plain.txt", target, b"body:plain.txt")
                elif case in {"nested", "nested-slash"}:
                    target = "/files/" + quote(DIR, safe="") + ("/" if case.endswith("slash") else "")
                    page = listing(target)
                    page.href(DIR)
                    follow(page, "plain.txt", target, b"nested-file")
                elif case == "filename-entities":
                    page = listing("/files/")
                    page.href("name&copy;.txt")
                    page.href(DIR)
                elif case == "extensionless-entries":
                    target = "/files/"
                    page = listing(target)
                    follow(page, "LICENSE", target, b"extensionless-file")
                    directory_url = urlsplit(urljoin("http://test" + target, page.href("plain-directory"))).path
                    follow(listing(directory_url), "child", directory_url, b"extensionless-child")
                elif case == "download-special":
                    page = listing("/files")
                    for name in NAMES:
                        follow(page, name, "/files", ("body:" + name).encode("utf-8"))
                elif case == "breadcrumb-parent":
                    target = "/files/" + quote(DIR, safe="") + "/second.dir/"
                    page = listing(target)
                    parent_url = urlsplit(urljoin("http://test" + target, page.href(DIR))).path
                    follow(listing(parent_url), "plain.txt", parent_url, b"nested-file")
                    assert page.href("Home") == "/files/", "Home 链接错误"
                elif case in {"mount-root", "mount-special"}:
                    mount = "/" if case == "mount-root" else '/files"&home'
                    target = quote(mount, safe="/")
                    page = listing(target, mount)
                    assert page.href("Home") == quote(mount.rstrip("/"), safe="/") + "/", "挂载根路径编码错误"
                    follow(page, "plain.txt", target, b"body:plain.txt", mount)
                elif case == "download-direct":
                    status, body = request("/files/plain.txt")
                    assert status == 200 and body == b"body:plain.txt"
                elif case.startswith("traversal-"):
                    target = "/files/../outside.txt" if case.endswith("outside") else "/files/%2e%2e%2Foutside.txt"
                    status, body = request(target)
                    assert status == 404 and b"outside-secret" not in body, "突破目录边界"
                elif case.startswith("linux-"):
                    directory = base / case
                    directory.mkdir()
                    name = '<svg onload=alert(1)>.txt' if case == "linux-html-filename" else 'quote"file.txt'
                    (directory / name).write_bytes(b"linux-special-file")
                    target = "/files/" + case
                    follow(listing(target), name, target, b"linux-special-file")
                else:
                    raise AssertionError("未实现用例")
                results.append({"case": case, "status": "pass"})
                print("PASS:", case)
            except Exception as error:
                results.append({"case": case, "status": "fail", "detail": str(error)})
                print("FAIL:", case, str(error))
    finally:
        if root.parent != parent.resolve() or not root.name.startswith("http-directory-"):
            raise RuntimeError("临时目录边界异常，拒绝递归清理")
        shutil.rmtree(root)
    passed = sum(item["status"] == "pass" for item in results)
    skipped = sum(item["status"] == "skip" for item in results)
    print(f"HttpDirectoryTests: {passed}/{len(results) - skipped} passed; {skipped} skipped")
    if args.report:
        args.report.write_text(json.dumps({"executable": str(executable),
            "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "results": results},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if passed + skipped == len(results) else 1)


if __name__ == "__main__":
    main()
