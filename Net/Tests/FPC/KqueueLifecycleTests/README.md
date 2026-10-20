# Kqueue 注册引用与析构回归

对应 F05/A06，首批建立无生产钩子的真实 TCP 红例，随后补充单一观察钩子控制的事件在途窗口。测试使用独立进程，父进程通过回环 TCP 建立一个连接，通过标准输入控制主线程；不替换 `kevent`、不模拟发送完成、不手工追加 `_Release` 回收缺陷引用。

单 worker 派生 `ProcessIoEvent` 在 inherited 返回后阻塞：此时 accept 批次和其中临时连接接口均已退出，初始 READ 已注册，下一次 `kevent` 尚未执行。主线程执行测试步骤后放行 worker 并 Stop，避免依赖长 Sleep 碰概率。

- `idle-close`：peer 保持空闲，主线程主动 Close 并清掉所有测试保存的连接接口，检查真实连接析构一次。
- `queued-sends`：屏障中连续发送默认 64 个一字节项，然后主动 Close。每项必须取消一次、不能报告成功，线上不能出现应用数据；同时记录排队前后只读 RefCount，检查同一 WRITE 注册没有按发送次数累积引用。
- `repeated-close`：同一连接连续 Close 32 次，只允许一次断连通知和一次析构。
- `queued-sends-drain`：屏障中排入同样的 N 个发送，放行后等待每项成功完成；父进程逐字节收到 N 个 `Q` 后才允许关闭，最终析构一次。
- `fetched-read-close`：真实 `kevent` 已返回 READ、尚未遍历/解引用事件时阻塞；主线程关闭并撤掉测试持有的连接，随后放行，业务收取次数必须为 0、析构一次。
- `fetched-write-close`：先排入一个发送，真实 WRITE 已被取出但未处理时关闭；发送必须取消一次，线上没有应用字节、析构一次。
- `fetched-read-write-close`：使用两个 worker，先让一个取出 WRITE 并停住，再由父进程写入一个字节触发另一个 worker 的 READ；原生端确认两个线程 ID 不同。两者均停在遍历之前时关闭，再放行，验证读不发布、写取消一次和析构一次。

派生 `CreateConnection` 返回带独立计数对象的 `TKqueueConnection` 子类。结果同时记录创建数、析构进入数、析构完成数、断连通知数、发送完成数和 owner 连接表数量；**owner 表归零不代表对象已经析构**。计数对象不持有连接接口，发送通知通过独立函数生成闭包，只捕获计数对象。红例若连接仍泄漏，计数对象保留到子进程退出，不形成悬空计数指针，也不掩盖泄漏。

父进程每项总超时 20 秒，原生屏障超时 10 秒。Stop 由主线程执行，不在 I/O 回调中执行。重复发送次数可用 `--send-count 1/32/128` 分别采样，报告保存实际引用增量和析构结果。每个发送使用独立序号计数，检测重复通知，不仅检查完成总数。日志输出序列化，避免两个 worker 的屏障行交错。

```text
python3 -B run_tests.py ./KqueueLifecycleTests --report baseline.json
python3 -B run_tests.py ./KqueueLifecycleTests --cases queued-sends --send-count 128 --report baseline-128.json
```

原三例已由主任务在 arm64 macOS 14.0 / FPC 3.3.1 实际运行，确认有效红结果：空闲关闭/重复关闭均为 owner 0 而析构 0；连续发送 64 项的引用计数从 3 增到 67，发送均 False 一次但析构仍为 0。之前基础监听失败的结果不计作 F05 红例。这里记录的是主任务回传的已执行结果，具体原始报告由主任务保存。

七例已在 arm64 macOS 14.0 / FPC 3.3.1 实际通过，未定义 DEBUG 与定义 DEBUG 的构建各 7/7。每例连接析构恰好一次，owner 和事件注册表均归零；64 次发送的引用增量由 64 降为 0。fetched 三例要求编译时开启 `CROSS_KQUEUE_TESTS`，使用唯一约定入口 `CrossKqueueEventsReadyForTest(const AEvents: PKEvent; const ACount: Integer)`，位置是 `kevent` 成功返回后、遍历及解引用前。测试只读 `Ident` / `Filter`，不读 `uData`、不假设其保存对象指针，也不额外持有连接。关闭时对象是否立即析构取决于生产所有权设计；断言只要求最终恰好一次析构和迟到事件安全，不强行要求在途窗口中的特定引用数。

无测试宏时可选择原三例及 `queued-sends-drain`；默认运行列表含 fetched 三例，需要匹配测试宏构建。`.dpr` 复用 `.lpr`，Pascal 源为 UTF-8 BOM / CRLF，Python runner 兼容 3.9。测试依赖仓库 Net/Utils、FPC 时另需 DelphiToFPC 与现有 Lazarus 单元搜索路径，不需要 TLS 或证书。

真实注册失败和监听事件在途现已由下列独立边界套件验证；fd 重用的强制回归与长期压力尚未运行。


## 原生构建与平台前置

本机实际使用已有 FPC 3.3.1-21398-g0d76f2fb7f、Lazarus 与 Xcode SDK。SSH 默认找不到安装目录中的 fpc.cfg，因此显式加载它；未安装依赖或改全局配置。原生入口兼容 Python 3.9，label 不覆盖已有产物：

```sh
python3 -B build_mac.py \
  --fpc "$HOME/FreePascall/fpc/bin/aarch64-darwin/fpc" \
  --config "$HOME/FreePascall/fpc/bin/aarch64-darwin/fpc.cfg" \
  --lazutils "$HOME/FreePascall/lazarus/components/lazutils" \
  --label verify --programs lifecycle edges address callbacks --debug
python3 -B run_tests.py bin/verify/lifecycle/KqueueLifecycleTests --report bin/verify/lifecycle/results.json
python3 -B run_edge_tests.py bin/verify/edges/KqueueEdgeTests --report bin/verify/edges/results.json
bin/verify/address/SocketAddressTests all
```

`SocketAddressTests` 独立验证 Darwin addrinfo 的 C 布局、getnameinfo 数值端口、IPv4 与 IPv6 的真实 Bind/Listen/Connect/Accept/双向字节。旧 SocketAPI 四种模式全部失败：canon/addr 偏移反转、端口80被返回为`http`、两个地址族的 sockaddr 为nil；修正 Darwin 分支后四项通过。线程ID的 typed-zero 与 DEBUG 数字格式也按FPC Darwin的指针类型修正。此兼容前置与F05的三项有效引用红例分开记录。

现有 `SocketCallbackTests` 在最终 Mac 代码上 13/13 通过（batch、accept、sent-event、send-callback、pending-send、cancel-sends、cancel-error、stop、connect-callback、connect-race、send-close-race、closed-state、closed-send），两类竞争各100轮。Mac 不接受零大小发送缓冲区，cancel测试只在MACOS使用4096，其它平台仍使用0；没有把不适用于Mac的/proc或seccomp用例算作通过。

Windows Delphi Win64/Win32、FPC Win64 各13/13，Linux Delphi/FPC 各14/14（额外真实注册失败重入），合计67/67；对应 `../SocketCallbackTests/bin/mac-prereq/manifest.json`。这组记录保留其实际旧测试源码哈希，后续仅MACOS发送缓冲区分支改动不改变这些平台的展开代码。四个生产依赖构建前后哈希一致；Delphi OSX64/OSXARM64 单元也编译通过，记录在 `../SocketCallbackTests/bin/kqueue-final/`，**不是 Delphi macOS 程序链接或运行验证**。

实机验证范围是macOS 14 arm64 / FPC3.3.1的基础Socket；未运行FreeBSD、32位BSD、Delphi macOS原生程序、上层TLS/HTTP/WS组合或长期压力。注册表引入每个活跃对象一个条目及事件查找短锁，本轮没有吞吐基准，不宣称性能提升。


## 注册与监听边界：实机 5/5

`KqueueEdgeTests` 与 `run_edge_tests.py` 使用独立进程，五项均在最终生产代码的 DEBUG 原生构建通过：

- `register-failure`：单 worker 屏障中 dup 保留测试TCP，关闭原描述符而保留连接对象中的原数值，调用实际Send触发真实kevent失败。该区间不创建其它描述符，fcntl确认原编号仍无效；DEBUG日志确认注册失败一次。发送失败一次，连接/监听各析构一次，所有表归零。
- `listen-fetched-close`：监听READ已返回但未处理时Close；放行后不能创建连接，监听析构一次、表归零。
- `listen-update-error`：注册成功后的UpdateAddr抛错，原异常传播，没有成功通知，监听fd关闭、对象析构一次、表归零。
- `listen-publish-error`：owner发布完成后派生TriggerListened抛错，同样完成清理且不通知成功。
- `stop-from-io`：在真实接收回调调用StopLoop，必须立即抛ECrossSocket，owner和注册数保持不变；原连接还能实际回包OK并成功通知，然后主线程正常停止、析构及归零。

## 最终证据

Mac共29个不同场景通过：生命周期7、注册/监听边界5、既有Socket回调13、地址4。第一次无DEBUG的7项与最终DEBUG的7项分别保存，不重复计入29。构建日志保留既有字符串转换及SDK最低目标警告；本轮实际运行系统为macOS14，不据此扩展最低系统版本支持声明。

本地忽略目录 `bin/mac-arm64/final-manifest.json` 汇总平台、最终源码哈希、29项计数与报告位置；镜像中的原始报告位于 `Net/Tests/FPC/KqueueLifecycleTests/bin/kqueue-final/`、`kqueue-edges/`、`platform-prereq-2/`。旧源码红例在镜像 `bin/kqueue-before/`（对象泄漏）和 `bin/address-before/`（Darwin地址ABI/常量），更早监听失败记录不冒充引用红例。`validation.tgz`、实际Mach-O产物及日志也保留在该目录；二进制哈希与构建metadata已核对，最终测试进程无残留。

最终生产 SHA-256：

- Kqueue：`92ea87b80f460ed4eb0315119c7421ae1d83f7af2d39f06e37cd626568e7504a`
- Base：`a3b39bc8dcef254a8a1e61e386bf9cb2b63be5be1ac9be7eaa4f65eea7d875cc`
- SocketAPI：`c2904d805e429bce58bd0f48574f250cffde0f25591298327dc138bac5f263dc`
- SyncObjs：`f24c92996ae7a68bd087542b9165a3e95c486fa749b723186b5f0bd402f4b858`
