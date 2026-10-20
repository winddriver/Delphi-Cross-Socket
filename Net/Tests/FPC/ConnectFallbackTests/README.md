# Connect 地址回退回归

`.dpr` 以两行 include 共用 `.lpr`，Delphi/FPC 运行同一份测试。Pascal 源码为 UTF-8 BOM。构建规则沿用仓库 `ConnectFailureTests` 的 Delphi 13.1、FPC 3.3.1 及现有 SDK 路径；工具位置集中于脚本开头。

## 测试方法

`ConnectFallbackTests` 通过受保护的 `ResolveConnectAddrs` 固定地址顺序，连接 Python 父进程持有的真实 IPv4/IPv6 回环服务。拒绝端口在 Windows/Linux 保持绑定但不监听，并在每个场景前以原生 socket 确认会拒绝。Darwin 对绑定但不监听的端口行为不同，改为保存端口后关闭并立即预检；存在端口被其他进程抢占的窗口，尝试数/结果断言会检测相关异常。

关闭窗口使用 `TEvent` 屏障，不依赖 Sleep 争抢时序；回调只计数，停止 IO 线程后检查每个操作恰好通知一次、对象全部析构、连接容器为空。每场景为独立进程，35 秒总超时。测试不启用生产测试宏。

| 场景 | 断言 |
| --- | --- |
| `v6-refused-v4-success` | IPv6 异步拒绝后 IPv4 成功，两个连接对象，一次成功 |
| `v4-refused-v6-success` | IPv4 异步拒绝后 IPv6 成功，两个连接对象，一次成功 |
| `all-refused` | 两个地址均拒绝，一次最终失败；回调提供已关闭连接和非零 LastNetError |
| `callback-close` | 成功回调主动 Close，仍只回调一次且释放连接 |
| `external-close-published` | 发布后暂停，另一线程 Close 完成后放行，不再尝试第二地址 |
| `close-before-callback` | LogicConnected 前暂停并外部 Close；已领取通知权时允许成功，仍只通知一次 |
| `close-between-attempts` | 第一个连接从容器移除时暂停，CloseAllConnections 后不得重试 |
| `register-failure-fallback` | 首次发布后关闭原始句柄，使真实后端 API 注册失败，第二地址仍成功 |
| `callback-raises` | 成功回调主动 Close 后抛异常，连接仍释放且不重复通知 |
| `destroy-200` | 200 次顺序真实连接，每次关闭，最终 200 个对象全部析构 |
| `unsupported-family-fallback` | 第一项地址族为 -1，创建失败后继续正常 IPv4；只创建一个连接对象 |
| `close-during-resolution` | 解析返回前暂停，CloseAllConnections 后不能创建连接，只通知失败 |
| `close-before-publish` | TriggerConnecting 调用 inherited 前暂停，CloseAllConnections 后不能发布/继续连接 |
| `connect-after-close-all` | CloseAllConnections 完成后新发起的 Connect 仍可成功 |

`register-failure-fallback` 是无效句柄错误注入，不声称复现资源耗尽；注入窗口不创建额外本进程句柄。`unsupported-family-fallback` 不代表真正禁用了 IPv6。构造/析构计数覆盖连接对象；FPC heaptrc 另外覆盖其堆分配的操作和匿名方法捕获，均不能证明原生系统句柄无泄漏或穷举所有并发交错。

## 不修改生产语义的原始基线探针

`HostFallbackProbe` 使用系统 `GetAddrInfo('localhost')` 获取实际地址族顺序，父进程在同一个端口让首地址族拒绝、第二地址族监听，并分别原生预检。随后调用公开 Connect，通过真实解析验证后续地址是否成功。没有覆盖解析方法、调整地址顺序或修改生产代码。若环境只返回一个地址族，明确 SKIP。

```powershell
python Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label raw-e159a08 --baseline-ref e159a088f721f1efbc0a7b88988317935cec1d82 --targets win64 --probe
```

`--baseline-ref` 通过 git show 冻结四个生产单元到 `bin/<label>/production`，同名快照若内容不同会拒绝覆盖。其他依赖使用工作区已有源码；原始基线的这部分依赖在本轮未修改。旧 master 不存在可覆写解析入口，不能直接编译主套件，因此红例采用独立的公开接口探针。

## 构建和运行

在仓库根目录执行：

```powershell
python Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label fixed --targets win64 win32 fpc64
python Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label fixed --targets delphi-linux64 fpc-linux64 --build-only
python Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label fixed-probe --targets win64 --probe
```

Linux 二进制必须在 Linux 中执行，Python 服务也运行在同一网络环境：

```text
python3 Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label fixed --run Net/Tests/FPC/ConnectFallbackTests/bin/fixed/delphi-linux64/suite/ConnectFallbackTests Net/Tests/FPC/ConnectFallbackTests/bin/fixed/fpc-linux64/suite/ConnectFallbackTests
```

FPC 堆检查：

```powershell
python Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label fixed-heap --targets fpc64 --heap-trace
```

`--scenarios` 选择场景；`--run` 只执行现有二进制；`--source` 选择已冻结的四单元目录。已有 Apple SDK 时可用 `--targets delphi-osxarm64 --build-only` 或 `delphi-osx64` 交叉编译；实际执行仍需 macOS。编译成功不计为运行通过。

macOS 原生 FPC 也可从仓库根目录直接构建；以下路径对应本次已有安装，不修改全局编译配置：

```sh
mkdir -p Net/Tests/FPC/ConnectFallbackTests/bin/native Net/Tests/FPC/ConnectFallbackTests/lib/native
"$HOME/FreePascall/fpc/bin/aarch64-darwin/fpc" \
  @"$HOME/FreePascall/fpc/bin/aarch64-darwin/fpc.cfg" -B -gh \
  -FuNet -FuUtils -FuDelphiToFPC -Fi. \
  -Fu"$HOME/FreePascall/lazarus/components/lazutils" \
  -FENet/Tests/FPC/ConnectFallbackTests/bin/native \
  -FUNet/Tests/FPC/ConnectFallbackTests/lib/native \
  Net/Tests/FPC/ConnectFallbackTests/ConnectFallbackTests.lpr
python3 -B Net/Tests/FPC/ConnectFallbackTests/run_tests.py --label native \
  --run Net/Tests/FPC/ConnectFallbackTests/bin/native/ConnectFallbackTests
```

证据保存在忽略的 `bin/<label>/<target>/suite` 或 `host-probe`，包括构建命令、日志、生产及测试源码 SHA-256、二进制 SHA-256、原始场景输出和 `results.json`。构建前后核对源码哈希，若源码正在变化则失败。`lib` 隔离各版本产物。重复运行更新对应结果文件，红绿版本应使用不同 label。

## 2026-10-20 当前主分支红例

原始基线 `e159a088f721f1efbc0a7b88988317935cec1d82`，四个生产文件直接从 Git 冻结，未应用 PR #216 或临时修改。

- Delphi 13.1 Win64 原生：localhost 顺序为 IPv4、IPv6，IPv4 拒绝而 IPv6 同端口可连接。实际回调 1 次、成功 0 次，探针按预期失败，证明旧 master 异步失败后未继续下个地址。证据：`bin/raw-e159a08/win64/host-probe/`。
- FPC 3.3.1 Linux64 / WSL Ubuntu 22.04：系统解析仅返回 IPv4，探针明确 SKIP；不计为红例或通过。证据：`bin/raw-e159a08/fpc-linux64/host-probe/`。

既有 PR 审查目录的运行结果未复制到本次证据目录，也不作为本轮通过依据。


## 2026-10-20 最终实现验证

最终批次 Windows/Linux 在 `bin/final-callback`，macOS 在 `bin/mac-current/final-results`；七个目标各 14/14，共 98/98。Windows 使用本机网络栈；Linux 在现有 WSL Ubuntu 22.04 内执行二进制及 Python 服务；macOS 为 arm64 macOS 14.0 原生执行。

| 编译器 / 平台 | 功能回归 | 堆检查 |
| --- | --- | --- |
| Delphi 13.1 Win64 | 14/14 | 未做 Delphi 堆泄漏检查 |
| Delphi 13.1 Win32 | 14/14 | 未做 Delphi 堆泄漏检查 |
| FPC 3.3.1 Win64 | 14/14 | 额外 -gh 的 14 场景逐个为 0 未释放块 / 0 字节 |
| Delphi 13.1 Linux64 | 14/14 | 未做 Delphi 堆泄漏检查 |
| FPC 3.3.1 Linux64 | 14/14 | 额外 -gh 的 14 场景逐个为 0 未释放块 / 0 字节 |
| Delphi 13.1 macOS ARM64 | 14/14 | 未做 Delphi 堆泄漏检查 |
| FPC macOS ARM64 | 14/14 | -gh 的 14 场景逐个为 0 未释放块 / 0 字节 |

最终七目标的 `all-refused` 都验证回调参数非 nil、连接已关闭、LastNetError 非零；`destroy-200` 都观察到 200 次成功回调以及 200 次连接析构。汇总 `bin/final-callback/verification-summary.json` 包含七目标二进制哈希、三平台堆检查结果和生产源码哈希。Windows/Linux 构建哈希在运行后再次与工作区核对一致；macOS 文件及签名证据见 `bin/mac-current/final-summary.json`。

### 两组红绿证据

同一份 `HostFallbackProbe` 源码在 Delphi Win64 从原始 master 失败变为最终实现通过：localhost IPv4→IPv6 顺序，首次原生拒绝、第二地址可连接，最终一次成功回调。红绿源码哈希相同，输出分别在 `bin/raw-e159a08/win64/host-probe` 和 `bin/final-callback/win64/host-probe`。macOS 在第一次冻结版本同样得到真实 localhost IPv6→IPv4 红绿对照；该探针未在末次失败诊断修正后重跑，不当作最终源码的探针验证。

初版实现的全部地址异步失败回调丢失了 connection，影响现有通过 LastNetError 读取失败原因的调用方。使用新断言和改动前四单元快照 `bin/pre-callback/production`，FPC Linux `all-refused` 实际失败，输出 `nil=1`；最终实现七目标都变为 `nil=0 open=0 zero_error=0`。若最后失败阶段发生在连接对象创建之前（解析、socket 或 bind 失败），仍允许返回 nil；测试没有要求保留更早尝试的连接。

`bin/first` 和 `bin/final` 是开发中间版本的诊断结果，未覆盖末次失败诊断断言，不计入最终通过数。Windows/Linux 最终堆证据位于 `bin/final-callback-heap/<target>/suite`；macOS 堆证据随 final-results 保存。三平台共 42 个场景逐条为零未释放块，不能扩大为原生系统句柄无泄漏或 Delphi 堆检查已通过。

### macOS 既有回归边界

末次修改后另行原生重跑既有 SocketCallbackTests，13/13。第一次冻结版本还通过 kqueue 生命周期 7 项、边界 5 项和地址 4 项；这 16 项未在末次失败诊断修正后重跑。两轮证据分别在 `bin/mac-current/summary.json` 和 `final-summary.json`。

这些结果覆盖本文列出的状态机窗口；没有声称覆盖全部线程交错、系统资源耗尽、所有系统句柄或长时间高并发负载。

### 既有兼容回归与正式构建

末次修改后重新构建并实际运行 Windows/Linux 的 SocketCallbackTests 67 项、ConnectFailureTests 8 项、HTTP HEAD 和请求生命周期 40 项，共 115/115；加上上述 macOS SocketCallbackTests 13 项，最终兼容回归合计 128/128。清单在 `../SocketCallbackTests/bin/connect-fallback-final/compatibility-manifest.json`。初轮 IOCP 生命周期 18 项使用调整前 Base，单独保存，不计入最终 128 项。

HttpClient 与 WebSocketServer 两个 Delphi 正式工程均以最终源码执行 Release/Win64 全量 MSBuild 成功。构建日志分别在对应示例的 `bin/connect-fallback-final/build.log`；实际命令与产物哈希以兼容清单为准。FPC、Delphi 的既有依赖警告保留，未宣称零警告；未执行 FreeBSD、32 位 kqueue、长期压力或 macOS 上层 TLS/HTTP 组合验收。
