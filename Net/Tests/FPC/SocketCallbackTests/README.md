# Socket 回调异常与关闭回归

对应 `docs/plans/2026-10-19-project-improvements.md` 的 A04 / F06 平台部分。
生产范围为 `Net.CrossSocket.Base.pas` 和 IOCP / Epoll / Kqueue 三个后端；HTTP 响应队列属于独立批次。保留 F01 的取消/停止修复，不更改 F05 的 Kqueue 注册引用算法。

## 验证目标

- 连接、接收或发送回调抛异常后，关闭当前连接；监听和同批其他连接继续工作。
- 每个完成通知独立执行；已经通知成功的回调即使抛异常，也不能再收到失败通知。
- OnSent 抛异常不能跳过对应的发送完成回调；取消、批量关闭和析构中的失败通知不能阻断资源收尾。
- 成功、关闭和析构通过同一短锁取走连接完成回调，用户回调在锁外执行。
- Disconnect 不把 Closed 状态写回 Disconnected；POSIX 发送在队列锁内拒绝关闭/断开连接，避免关闭清队列之后重新留下未完成发送。
- 连接事件注册的 Boolean 返回语义保持不变：无需 rearm 也可能返回 False。新增私有 `ACloseRequired` 只标识真实系统调用失败，10 个连接调用点均在释放队列锁之后关闭；监听注册接口保持不变。

## 构建与运行

沿用本项目现有 Delphi 13.1、Lazarus/FPC 3.3.1 和 Ubuntu SDK，不安装工具或修改全局配置。在本目录运行：

```powershell
python build.py win64 win32 fpc64 fpc-linux64 delphi-linux64 --label final
python run_tests.py bin/final/win64/SocketCallbackTests.exe --output bin/final/win64/results.json
python run_tests.py bin/final/win32/SocketCallbackTests.exe --output bin/final/win32/results.json
python run_tests.py bin/final/fpc64/SocketCallbackTests.exe --output bin/final/fpc64/results.json
```

在实际 Linux 环境运行交叉构建产物：

```sh
python3 run_tests.py bin/final/fpc-linux64/SocketCallbackTests --output bin/final/fpc-linux64/results.json
python3 run_tests.py bin/final/delphi-linux64/SocketCallbackTests --output bin/final/delphi-linux64/results.json
```

`build.py delphi-osx64 delphi-osxarm64 --label final` 只编译 Kqueue 单元及其依赖，不生成或运行 macOS 测试程序。

构建日志、运行结果和四个生产单元/测试 LPR 的 SHA-256 保存在忽略的 `bin/<label>/<target>/`，编译单元写入 `lib/`。每个运行场景使用独立进程，socket、事件屏障、启动、竞争和停止均有超时；失败时终止并等待测试进程，回收其输出线程和 Python socket，不留下后台服务。

## 场景

| 场景 | 验证内容 |
| --- | --- |
| `batch` | 单工作线程先阻塞在接收回调；主线程确认坏连接已经可读，再令好连接可读，最后放行。Linux 必须在同一次 ProcessIoEvent 中处理 BAD 和 GOOD；坏连接关闭，既有及新连接继续收发。 |
| `accept` | 首个接入连接回调抛异常，坏连接关闭；下一连接仍能接入和收发。 |
| `sent-event` | OnSent 对第一项抛异常，其对应完成通知及下一项通知仍各执行一次。 |
| `send-callback` | 第一个成功完成回调自身抛异常，不能把它改报失败，也不能跳过下一项。 |
| `pending-send` | 接收回调尚在处理中时连续排队发送；数据和两次通知完整，连接仍可继续收发，不因 pending 状态被误关。 |
| `cancel-sends` | 挂起三个发送后关闭；第一个失败通知抛异常，其余两项仍各通知一次失败。 |
| `cancel-error` | 受控取消/终止一个挂起发送，失败通知抛异常后，连接仍正确关闭。 |
| `stop` | 三条连接的断开回调均抛异常，停止仍完成且三条连接全部关闭。 |
| `connect-callback` | 真实回环连接成功回调抛异常后再关闭，不能重复通知失败。 |
| `connect-race` | 100 轮共享起跑屏障，成功通知与 Close 竞争，每轮只允许一个成功或失败结果。 |
| `send-close-race` | 100 轮共享起跑屏障，底层发送与 Close 竞争，每轮必须完成一次失败通知。 |
| `closed-state` | Close 后再 Disconnect，IsClosed 必须保持 True。 |
| `closed-send` | 绕过 DirectSend 的锁外快速检查，直接向关闭连接调用底层 Send，必须立即完成一次失败通知。 |
| `early-failure` | 独占本地端口使 Bind 确定失败；失败回调每次抛异常，预热后连续 20 次操作，进程句柄/fd 数不得增长。 |
| `register-failure`（仅 Linux） | 真实 epoll_ctl 失败触发关闭；断开回调启动另一线程进入发送路径，验证队列锁已经释放，原发送和探针均结算一次失败。 |

## 模拟与平台边界

大多数场景使用真实 TCP 回环。`connect-race`、`send-close-race`、`closed-state`、`closed-send` 使用实际创建的未连接 socket，专门验证通知所有权和终态，不模拟整套平台连接成功事件，也不宣称验证所有连接状态事件的先后顺序。

Linux 注册失败场景只操作测试进程拥有的描述符：先 dup 保留原 socket，再用自己打开的 `/dev/null` 替换原编号，让 epoll_ctl 对该编号产生真实系统错误。临时描述符在 finally 中回收；该过程由事件屏障隔离在工作线程暂停期间。锁探针直接进入底层 Send，绕过 DirectSend 对关闭连接的快速返回；连接已标记关闭，探针不发送网络数据。测试不修改内核参数或全局安全策略。

`pending-send` 覆盖接收处理中追加发送；关闭期间的探针与 `closed-send` 覆盖关闭/no-op 边界。没有通过修改私有 pending 计数制造状态，也不声称穷举所有线程交错。

## 2026-10-19 验证记录

初始八项红基线：Delphi Win64 **6 项失败、2 项通过**；FPC Linux **7 项失败、1 项通过**。Windows 出现回调异常后连接不关闭、OnSent 跳过完成通知、批量停止被异常中断及成功后重复失败通知；Linux 还明确丢失同批后续事件、完成队列与取消队列的后续通知。原始四个生产单元快照在 `bin/baseline-sources/`，产物和记录在 `bin/baseline/`。

随后分别保留两轮补充红基线：

- `before-register-fix`：真实 Linux 注册失败时，断开回调仍持有发送队列锁，锁探针失败。
- `before-closed-fix`：Windows/Linux 均复现 Closed 被 Disconnect 降级；Linux 还复现关闭后底层发送及发送/关闭竞争的通知悬挂。Windows 的后两项原本通过，作为相邻回归保留。
- `before-early-fix`：失败回调抛异常使早期连接失败路径跳过 raw socket 关闭。20 次测量操作使 Windows 句柄数从 150 增至 170，FPC Linux fd 数从 7 增至 27；修复后三个 Windows 目标及两个 Linux 目标计数均保持不变。

A04 提交前实际运行：Delphi Win64、Delphi Win32、FPC Win64 **各 14/14**；WSL Ubuntu 的 Delphi Linux64、FPC Linux64 **各 15/15**，合计 **72/72**。Linux BAD/GOOD 的 ProcessIoEvent 轮次一致，确认同批事件隔离。每个目标的两类竞争均各执行 100 轮。

F01 `IocpLifecycleTests` 另按最终生产源码重新构建，三个 Windows 目标 **18/18 通过**，结果保存在该工程的 `bin/a04-regression/`。

Kqueue 的 macOS x64 / ARM64 单元均编译通过。当前没有 macOS/FreeBSD 实机环境，因此 **没有 Kqueue 运行验证**；F05 注册引用问题仍属后续独立任务。本批未执行长期压力或吞吐性能测试，项目既有编译警告不计作本批消除目标。

## F16：监听失败清理

后续 F16 / A10.2 复用本工程，只修改三个后端的 Listen：入口先设置 `LListenSocket := INVALID_SOCKET`；失败通知使用 try/finally 清理当前拥有的 raw socket 或监听对象。未修改 Base、Kqueue 注册引用或发送容器。

新增七项可单独运行：

```powershell
python build.py win64 win32 fpc64 fpc-linux64 delphi-linux64 --label f16-final
python run_tests.py bin/f16-final/win64/SocketCallbackTests.exe --cases listen-dns listen-socket listen-bind listen-listen listen-register listen-callback listen-register-callback --output bin/f16-final/win64/results.json
```

其他目标替换产物路径；Linux 使用 python3。七项分别覆盖地址解析失败、socket 创建失败、绑定冲突、listen 调用失败、事件注册失败、raw socket 失败回调抛异常，以及回调保留失败监听对象后抛异常。

每项执行 20 次失败尝试，验证通知次数及资源计数；过程中保留一个正常监听、一条已连接 TCP 和一个只读文件，失败后既有连接继续收发，原监听还能接入新连接，文件仍可读取。

注入边界：

- Windows 用 Net.Winsock2 已有函数变量观测 close，并注入 socket/listen 的错误返回；DNS 失败路径必须没有项目发出的 close 调用。
- Linux socket/listen 错误由四条 seccomp 指令在测试主线程中返回指定 errno；不修改全局配置，已有 I/O 线程不受该过滤器影响。该注入仅适用于 Linux x86_64。
- 注册失败使用另一个运行中的测试实例，在 `CreateListen` 后令其原生监听句柄无效；Linux 用 `/dev/null` 占住原编号，使 epoll_ctl 真正返回错误。停止后的实例现在会在准入阶段拒绝，不能再用于验证原生注册失败。原有失败回调、保留对象、20 次资源计数和主监听存活断言不变。
- 所有注入都只在对应测试子进程中生效。不制造栈值来控制未初始化变量。

红基线位于 `bin/f16-baseline/`：Windows 地址解析失败 20 次错误调用了 close 20 次；监听失败回调抛异常使 Windows 句柄从 156 增至 176、FPC Linux fd 从 10 增至 30。Linux 本机的未初始化值没有碰巧误关存活资源，DNS 原版用例通过，此项不冒称 Linux 动态复现。其他阶段的正常失败清理原版通过，作为相邻回归保留。

Windows 首次无效地址查询会初始化系统缓存句柄，例中计数为 155→164；它不是本项目 socket 泄漏。DNS 采用零 close 观测和既有资源存活断言；已预热的其他失败分支才使用句柄数保持不变的断言。

修复后重新构建，Delphi Win64、Win32、FPC Win64、Delphi Linux64、FPC Linux64 的七项均通过，共 **35/35**，记录在 `bin/f16-final/<target>/`。三个 Windows DNS 用例的项目 close 次数均为 0；失败回调不再增加句柄。保留监听对象后抛异常的补充项也验证对象已经关闭，不能依赖接口最终释放才清理。

Kqueue x64/ARM64 再次仅编译通过，无 macOS/FreeBSD 运行验证。F16 的 35 项与上面的历史 A04 72 项分开记录，不把未重跑的历史场景计作本轮全套运行。


## 2026-10-20 macOS 续验

F05 修复后，arm64 macOS14 / FPC3.3.1 实机13/13通过：batch、accept、sent-event、send-callback、pending-send、cancel-sends、cancel-error、stop、connect-callback、connect-race、send-close-race、closed-state、closed-send。两种竞争各100轮。Mac不接受零大小发送缓冲区，测试仅在MACOS使用4096，其它平台保持0；未运行基于/proc或Linux seccomp的用例。

Base线程ID调试格式、FPC Darwin地址声明和读写锁零值比较另经Windows三个目标各13/13、Linux两个目标各14/14回归，共67/67，记录在bin/mac-prereq/manifest.json。该组保留构建时的测试源快照，后续MACOS条件分支适配不改变Windows/Linux展开代码。最终Kqueue的Delphi OSX64/OSXARM64仍仅编译单元通过；Mac原生FPC结果及边界详见[生命周期回归](../KqueueLifecycleTests/README.md)。历史章节保留当时尚未实机验证的事实。
