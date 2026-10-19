# Connect 预连接失败通知测试

使用真实 TCP 端口占用迫使 `Connect(..., ALocalPort, ...)` 在创建连接对象前绑定失败。回调只计数、不抛异常，因此不会遮住外层地址循环的第二次通知。测试不修改原生函数指针或生产代码。

Python 父进程持有 `AF_INET` 的 `0.0.0.0:随机端口` 监听，Windows 开启并使用 `SO_EXCLUSIVEADDRUSE`；Linux 不启用地址重用。启动 Pascal 子进程前，另一个原生 socket 绑定相同通配地址必须失败。监听始终保持到子进程退出，随后由上下文管理器关闭；不接受或处理任何连接。被测目标始终为数字地址 `127.0.0.1`，并断言地址解析只返回一个结果。

本机 Windows 的一个必要细节：独占监听只绑定 `127.0.0.1` 时，另一个 socket 首次绑定 `0.0.0.0` 的同端口仍可能成功。组件正是使用通配本地地址，因此父监听也采用通配地址，并增加原生 Bind 预检。初始 `bin/before/`、`bin/before-parent/` 只保存测试前提诊断，**不计为合格红例**。

## 2026-10-20 红绿结果

旧源码固定为 `7d05902` 的 Base/IOCP/Epoll/Kqueue 四单元快照，位于 `bin/before-wildcard/production/`。绿色四单元从 transport 冻结的工作区复制，逐一核对先前 Windows 构建哈希后保存在 `bin/after-wildcard/production/`，Linux 也使用同一份绿色快照。

| 目标 | 旧版一次 / 20 次 Connect 的回调次数 | 修复后一次 / 20 次 | 结果 |
| --- | --- | --- | --- |
| Delphi Win64 / IOCP | 2 / 40 | 1 / 20 | 红→绿 |
| FPC Win64 / IOCP | 2 / 40 | 1 / 20 | 红→绿 |
| Delphi Linux64 / Epoll | 2 / 40 | 1 / 20 | 红→绿 |
| FPC Linux64 / Epoll | 2 / 40 | 1 / 20 | 红→绿 |

所有运行的成功回调数、非 nil 连接回调数、连接对象创建数均为 0；每次地址数为 1。因此不涉及 DNS 多地址或异步 TCP 拒绝，直接验证 `_Failed2` 与外层 `_Failed1` 的一次结算边界。旧版八个场景均为预期失败，修复后 **8/8**。Linux 在现有 Ubuntu 22.04 WSL 中实际运行，不以交叉编译代替运行。

每个目标目录包含 `build.log`、`source.json`、两份次数日志和 `results.json`，实际二进制/来源及采集时间汇总在 `bin/connect-failure-manifest.json`。测试只负责证据；生产修复由 transport 分工完成。未验证 macOS/Kqueue 运行、完整多地址容错策略、TLS 或 HTTP 组合。

## 复现

Windows 在本目录运行：

```powershell
python -B run_tests.py --label before-wildcard --baseline-ref 7d05902 --targets win64 fpc64
python -B run_tests.py --label after-wildcard --targets win64 fpc64
```

旧版命令退出 1 是预期红例；不要因为红例失败而跳过绿色命令。`--label` 隔离输出，生产快照已存在时只核对内容，不覆盖。

交叉构建与真实 Linux 运行：

```powershell
python -B run_tests.py --label before-wildcard --baseline-ref 7d05902 --targets fpc-linux64 delphi-linux64 --build-only
python -B run_tests.py --label after-wildcard --source bin/after-wildcard/production --targets fpc-linux64 delphi-linux64 --build-only
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/ConnectFailureTests -- python3 -B run_tests.py --label after-wildcard --run bin/after-wildcard/fpc-linux64/ConnectFailureTests bin/after-wildcard/delphi-linux64/ConnectFailureTests
```

源码/正式构建依据沿用相邻 `SocketCallbackTests` 与 `CapacityTests` 的已安装 Delphi/FPC 工具链；不修改全局编译或网络配置。
