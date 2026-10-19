"""从同一生产版本生成仅等待方式不同的基准源码，已有不同内容时拒绝覆盖。"""
import hashlib


def timer_source(here, repo, polling=False):
    source = repo / "Utils/Utils.EasyTimer.pas"
    if not polling:
        return source
    body = source.read_bytes()
    waiting = b"if not LRun then FWake.WaitFor(LWait);"
    if body.count(waiting) != 1:
        raise RuntimeError("等待代码已变化，需要重新审查轮询基准的生成规则")
    body = body.replace(waiting, b"Sleep(10);")
    label = hashlib.sha256(body).hexdigest()[:16]
    target = here / "bin" / ("polling-source-" + label) / "Utils.EasyTimer.pas"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != body:
        raise RuntimeError("已有不同版本的轮询基准源码，请保留旧证据并使用新的基准目录")
    if not target.exists():
        target.write_bytes(body)
    return target
