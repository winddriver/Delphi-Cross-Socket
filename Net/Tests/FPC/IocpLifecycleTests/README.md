# IOCP 生命周期回归

对应 `docs/plans/2026-10-19-project-improvements.md` 的 F01 / A01。
只运行 Windows 回环连接，固定 2 个 I/O 工作线程，不依赖外部服务。

## 构建与运行

沿用相邻工程的 Delphi 13.1 / FPC Lazarus 构建方式。本机工具路径定义在 `run_tests.py`，其他机器按实际安装目录调整；不安装依赖、不修改全局配置。

在仓库根目录运行：

```powershell
python Net/Tests/FPC/IocpLifecycleTests/run_tests.py --targets win64 win32 fpc64
```

也可进入本目录后执行 `python run_tests.py`，默认验证 Delphi Win64 和 FPC Win64。
`--cases` 选择单项，`--build-only` 仅构建，`--no-build` 仅运行已有产物。
`--label` 区分验证轮次；构建和运行记录保存在忽略的 `bin/<label>/<target>/`，Delphi 单元保存在 `lib/<label>/<target>/`，FPC 单元保存在 `lib/x86_64-win64/`。

每个场景运行在独立子进程中，15 秒超时后由 Python 终止并等待回收。测试程序不创建其他进程；断言失败直接退出，避免旧版代码在异常展开时进入有故障的停止过程。辅助线程随测试进程结束，不留下后台服务。

## 场景与断言

| 场景 | 验证内容 |
| --- | --- |
| `churn` | 100 次应用侧关闭已经挂起零字节读取的连接；保留连接每轮收发成功；之后新连接仍可收发；工作线程没有提前退出。 |
| `connection-cancel` | 每次明确用 `CancelIoEx` 取消连接上的挂起读取，再关闭连接；其余断言与 `churn` 相同，确保覆盖取消完成包。 |
| `listen-close` | 关闭一个挂有 AcceptEx 的监听，另一个监听及其既有连接继续收发。 |
| `listen-cancel` | 仅取消监听上的待完成 AcceptEx，保持监听打开；该监听随后仍能接入新连接，另一监听的既有连接不受影响。 |
| `pending-stop` | 4 条连接挂着读取和大块发送；发送缓存设为 0、对端暂不读取，确认 4 次 WSASend 返回 pending 且停止前没有完成通知；停止后通知完整、连接全部析构、工作线程全部退出。 |
| `extra-sentinel` | 受控提前退出一个工作线程；使真实挂起读取的取消完成出现在停止哨兵之后，验证 drain 忽略多余哨兵、回收连接，并且连接拥有的句柄只关闭一次。 |

测试进程通过 `Net.Winsock2` 已有函数指针观测真实 `WSARecv` / `WSASend`，保留原始返回值和错误码，不伪造收发结果。创建新连接时清除旧句柄的读取记录，避免句柄重用造成假阳性。

`extra-sentinel` 另外将一个连接的实际 `closesocket` 延后到所有工作线程结束屏障之后执行，从而稳定控制队列先后顺序。只有这个场景注入线程退出和关闭时序；真实 socket、读取、完成端口和取消完成仍由 Windows 提供。这不是自然发生概率或压力测试的证明。

## 基线对照

可以把历史 `Net.CrossSocket.Iocp.pas` 保存到忽略目录中，用 Delphi 优先搜索该目录构建对照，无需切换分支或覆盖工作区源码：

```powershell
python run_tests.py --targets win64 --label baseline-final --source-dir bin/baseline
```

`source.json` 记录实际使用的 IOCP 源码和测试源码 SHA-256；`results.json` 及各场景 `.log` 记录运行结果。`--source-dir` 仅用于 Delphi 对照构建。

## 2026-10-19 验证记录

- 原生产代码的 Delphi Win64 对照：`connection-cancel` 第一轮即报告工作线程提前退出；`listen-close` 和 `listen-cancel` 报告 `echo timeout; ended=2`；`extra-sentinel` 报告访问异常。
- 原生产代码上的普通 `churn` 和 `pending-stop` 在本机通过，因此不以它们单独证明旧缺陷。明确取消和停止时序场景提供红基线。
- 修复后的 Delphi Win64、Win32、FPC Win64：每目标 6 个场景通过，共 18/18。每个目标分别执行 100 次普通关闭和 100 次显式取消后关闭。
- 本套件不验证 Epoll/Kqueue、吞吐性能、长时间压力或其他计划项。编译仍有项目既有提示和警告，不宣称零警告。
