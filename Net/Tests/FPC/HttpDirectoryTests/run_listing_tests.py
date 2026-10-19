"""通过真实 HTTP 页面与下载验证条目上限，并逐字节比较不限额页面。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid
from urllib.parse import quote

sys.dont_write_bytecode = True
from run_tests import Page

HERE = Path(__file__).resolve().parent
CASES = ["empty", "full-compatible", "zero-compatible", "natural-directories-first",
         "size-boundaries", "limit-one", "limit-below-total", "limit-exact-total", "limit-above-total",
         "limit-max-integer", "limit-empty", "truncated-notice", "page-only-statistics", "enumerated-prefix",
         "limited-special-names", "download-unlisted", "negative-rejected", "limited-nested", "limited-reflection",
         "limited-traversal"]


class Rows(Page):
    def __init__(self, body):
        self.rows, self.row, self.cell = [], None, None
        super().__init__(body)

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        elif tag == "td" and self.row is not None:
            self.cell = ""
        super().handle_starttag(tag, attrs)

    def handle_data(self, data):
        if self.cell is not None:
            self.cell += data
        super().handle_data(data)

    def handle_endtag(self, tag):
        if tag == "td" and self.cell is not None:
            self.row.append(self.cell)
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None
        super().handle_endtag(tag)


def request(executable, directory, target="/files/", limit=0):
    result = subprocess.run([str(executable), str(directory), target, "/files", str(limit)],
                            capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    header, sep, body = result.stdout.partition(b"\r\n\r\n")
    assert sep, "缺少响应边界"
    lines = header.split(b"\r\n")
    status = int(lines[0].split()[1])
    lengths = [int(line.split(b":", 1)[1]) for line in lines[1:] if line.lower().startswith(b"content-length:")]
    assert lengths == [len(body)], "响应正文长度错误"
    return status, body


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    executable, baseline = args.executable.resolve(strict=True), args.baseline.resolve(strict=True)
    parent = HERE / "bin/fixtures" if os.name == "nt" else Path(tempfile.gettempdir())
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / ("http-directory-listing-" + uuid.uuid4().hex)
    root.mkdir()
    root = root.resolve()
    directory, empty = root / "www", root / "empty"
    directory.mkdir()
    empty.mkdir()
    results = []
    try:
        for name in ["z10", "z2", "a20", "a3"]:
            (directory / name).mkdir()
            (directory / name / "child").write_bytes(b"child-body")
        payloads = {"size0": b"", "size1023": b"a" * 1023, "size1024": b"b" * 1024,
                    "size1048576": b"c" * 1048576, "file10": b"ten", "file2": b"two",
                    "中文 空格%+&'.txt": b"special", "bare": b"extensionless"}
        if os.name != "nt":
            payloads['<svg onload=alert(1)>".txt'] = b"linux-special"
        for name, content in payloads.items():
            (directory / name).write_bytes(content)
        enumerated = [entry.name for entry in directory.iterdir()]
        total = len(enumerated)
        _, old_body = request(baseline, directory)
        old_page = Rows(old_body).safe()
        all_names = [name for _, name in old_page.anchors if name != "Home"]

        def listing(limit=0, target="/files/", base=directory):
            status, body = request(executable, base, target, limit)
            assert status == 200, f"目录返回 {status}"
            return Rows(body).safe(), body

        def labels(page):
            return [name for _, name in page.anchors if name != "Home"]

        for case in CASES:
            try:
                if case in {"empty", "limit-empty"}:
                    page, body = listing(1 if case == "limit-empty" else 0, base=empty)
                    assert labels(page) == [] and "空目录" in body.decode()
                    assert body == request(baseline, empty)[1]
                elif case in {"full-compatible", "zero-compatible", "limit-exact-total", "limit-above-total", "limit-max-integer"}:
                    limit = {"limit-exact-total": total, "limit-above-total": total + 1,
                             "limit-max-integer": 2147483647}.get(case, 0)
                    assert listing(limit)[1] == old_body, "完整页面与原版逐字节不同"
                elif case == "natural-directories-first":
                    names = labels(listing()[0])
                    assert names[:4] == ["a3", "a20", "z2", "z10"]
                    assert names.index("file2") < names.index("file10")
                elif case == "size-boundaries":
                    rows = {row[0]: row for row in listing()[0].rows if len(row) == 5}
                    for name, expected in [("size0", "0B"), ("size1023", "1023B"),
                                           ("size1024", "1.00K"), ("size1048576", "1.00M")]:
                        assert rows[name][2].strip() == expected, (name, rows.get(name))
                elif case in {"limit-one", "limit-below-total", "enumerated-prefix"}:
                    limit = 1 if case == "limit-one" else total - 1 if case == "limit-below-total" else 3
                    names = labels(listing(limit)[0])
                    expected = [name for name in all_names if name in enumerated[:limit]]
                    assert names == expected, (names, expected)
                elif case == "truncated-notice":
                    text = listing(3)[1].decode()
                    assert "仅显示枚举前 3 项" in text and "非目录全量统计" in text
                    assert "目录优先" in text and "自然顺序" in text
                elif case == "page-only-statistics":
                    limit = total - 1
                    selected = enumerated[:limit]
                    dirs = sum((directory / name).is_dir() for name in selected)
                    text = listing(limit)[1].decode()
                    assert f"本页目录: {dirs}, 文件: {limit - dirs}" in text
                elif case == "limited-special-names":
                    special = root / "special"
                    special.mkdir()
                    names = ["中文 空格%+&'.txt", "another"]
                    if os.name != "nt":
                        names[0] = '<svg onload=alert(1)>"%+.txt'
                    for name in names:
                        (special / name).write_bytes(b"special")
                    page, _ = listing(1, base=special)
                    selected = next(special.iterdir()).name
                    assert labels(page) == [selected]
                    href = page.href(selected)
                    assert all(ord(c) < 128 for c in href) and " " not in href and '"' not in href
                    assert request(executable, special, href, 1) == (200, b"special")
                elif case == "download-unlisted":
                    name = next(name for name in payloads if name != enumerated[0])
                    assert name not in labels(listing(1)[0])
                    assert request(executable, directory, "/files/" + quote(name, safe=""), 1) == (200, payloads[name])
                elif case == "negative-rejected":
                    result = subprocess.run([str(executable), str(directory), "/files/", "/files", "-1"],
                                            capture_output=True, timeout=15)
                    assert result.returncode != 0, "负数应在路由工厂明确拒绝"
                    assert b"HTTP/1.1 200" not in result.stdout
                elif case == "limited-nested":
                    page, _ = listing(1, "/files/a3/")
                    assert page.href("Home") == "/files/" and page.href("a3") == "/files/a3/"
                    assert request(executable, directory, page.href("child"), 1) == (200, b"child-body")
                elif case == "limited-reflection":
                    payload = '<svg onload=alert(1)>'
                    page, _ = listing(1, "/files/" + quote(payload + '/../', safe=""))
                    # 安全显示的真实文件名也可含 alert(1)，只排除被 .. 消除的导航片段。
                    assert not any(name == payload or href == "/files/" + quote(payload, safe="") + "/"
                                   for href, name in page.anchors)
                elif case == "limited-traversal":
                    (root / "secret").write_bytes(b"secret-outside")
                    status, body = request(executable, directory, "/files/%2e%2e%2fsecret", 1)
                    assert status == 404 and b"secret-outside" not in body
                results.append({"case": case, "status": "pass"})
                print("PASS", case, flush=True)
            except Exception as error:
                results.append({"case": case, "status": "fail", "detail": str(error)})
                print("FAIL", case, str(error), flush=True)
    finally:
        if root.parent != parent.resolve() or not root.name.startswith("http-directory-listing-"):
            raise RuntimeError("临时目录边界异常，拒绝清理")
        shutil.rmtree(root)
    args.report.write_text(json.dumps({"executable": str(executable),
        "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "baseline": str(baseline),
        "baseline_sha256": hashlib.sha256(baseline.read_bytes()).hexdigest(), "results": results},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(any(record["status"] != "pass" for record in results))


if __name__ == "__main__":
    main()
