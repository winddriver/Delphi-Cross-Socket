# FIFO 排空基准与生命周期回归

对应 B01/O01。先建立未修改生产队列的基线，再替换 HTTP 请求、HTTP 响应及 Epoll/Kqueue 的 FIFO；不将理论复杂度当作实际吞吐。WebSocket/TLS 的兼容队列接入属于单独批次。

## 测量边界

- `request`：真实 `TServerDock.PushRequest/PopRequest`，计时仅覆盖取头、顺序断言和请求释放。构造、入队在计时外，不执行 HTTP 网络请求。
- `response`：真实 HTTP 解析、响应队列和发送路径，底层 `DirectSend` 只保存待完成操作；计时覆盖逐次物理完成至全部响应结束。解析、正文准备和入队在计时外。每批总正文固定 64 KiB，实际 HTTP 头总量随深度变化，不能将此数值当网络带宽。
- `socket-container`（Linux）：直接使用生产 `TSendQueue` 及其 `Notify`，计时覆盖 Peek、头删、回调通知和捕获对象释放；不包含 `epoll_wait/send`、锁竞争或 `_HandleWrite` 收集完成回调的成本。
- 深度均为 1、100、1000、10000；每个样本内排空批次数为 `min(100, max(1, 10000 div depth))`，报告每批微秒。保留一个预热进程样本及五个统计样本，汇总取中位数。深度 1 的数值接近计时及调用固定成本，不据此推断部署吞吐。
- `heap_queued/heap_drained` 为排空前后进程堆的已分配字节快照，**不是分配次数、峰值或锁占用时间**。Delphi Linux RTL 无此统计，JSON 使用 null。每批另外断言对象、回调捕获释放次数；不允许依靠最终析构掩盖出队槽位保留引用。

## 回归

请求队列：四生产者并发接纳、每个生产者内顺序、无重复/遗漏、出队后释放；固定深度循环出入队 10000 次，确认槽位不残留接口；批量取消时回调重入新增请求及另一个回调抛异常，原批次逐项完成，新项留给下一批。

响应队列：逆序及多线程 Ready 不越过未 Ready 的队首；始终只有一个在途物理写；关闭取消各通知一次；解除最后外部连接引用后，在途写仍保活连接，物理完成后释放。HTTP 连接有意保留最近请求，保活断言通过真实关闭清理解除该反向引用后执行。测试使用 INVALID_SOCKET，显式进入 InternalClose，不把公开 Close 的无 socket 快速分支当作生产缺陷。

Socket 容器：部分发送更新同一队首项、清空时先保留回调捕获、通知后各释放一次；正常排空必须释放全部捕获。`TSendQueue.Notify(cnRemoved)` 会 Dispose 指针，测试和实现都不能继续使用 Dequeue 返回的已释放指针。构建脚本按实际生产声明自动选择 TList 或 TQueue API。

`run_socket.py` 是独立真实 Linux TCP 回环：16 MiB 字节模式、小发送缓冲和暂停读取，等待排队的接收事件及后续写事件都返回，确认连接仍开且尚有未完成项。这才认定遇到 EAGAIN；然后恢复读取逐字节核验，或关闭并核验每项恰好一次及全部捕获释放。深度 100、1000、10000 各执行恢复和取消。该测试不作为耗时基准。

更广的回调异常、发送/Close 竞争、关闭后的拒绝及事件注册失败沿用相邻 `SocketCallbackTests`；HTTP 回调异常和 Ready/Close 竞争沿用 `HttpFailureTests`。容器基准不能替代这些回归。

## 运行

在本目录使用既有 Delphi/FPC 工具链，不安装依赖或修改全局配置：

```powershell
python run_tests.py win64 fpc64 --label before
python run_tests.py fpc-linux64 delphi-linux64 --label before --build-only
```

在 Linux 运行：

```sh
python3 run_tests.py fpc-linux64 delphi-linux64 --label before --run-only
python3 run_socket.py bin/before/fpc-linux64/QueueFifoTests --output bin/before/fpc-linux64/network.json
python3 run_socket.py bin/before/delphi-linux64/QueueFifoTests --output bin/before/delphi-linux64/network.json
```

实施后使用新标签 `after` 重跑，保留 `before` 产物，再运行：

```sh
python compare.py before after win64 fpc64 fpc-linux64 delphi-linux64
```

每个运行子进程都有超时，失败会终止并等待退出。网络测试回收 stdout 线程和 TCP socket。`bin/<label>/<target>` 保存构建日志、结果、原始基准和源 SHA-256；编译单元仅写 `lib/`。

Kqueue 仍无真实环境；可沿用 `SocketCallbackTests/build.py delphi-osx64 delphi-osxarm64 --label <label>` 编译检查，不能记为 macOS/FreeBSD 回归通过。Kqueue 注册引用算法属于 F05，不随本项改动。

## 替换前核查

三个 FIFO 都只需要队首操作。HTTP response 的 Ready 检查改为 Peek，保留 active item 与清理快照；client request 仍锁内出队、锁外取消通知。`FConnections.Remove` 是另一个连接列表，不能替换成 FIFO。

Epoll/Kqueue 的 `_HandleWrite` 还使用逐项 `TArrayUtils.Append` 收集完成回调；只替换头删不会自动消除该处潜在复制成本。本基准分别报告容器成本，不据此声称完成事件收集或真实网络吞吐已有同等提升。

## FPC 托管元素兼容

循环入队回归发现本机 FPC 3.3.1 的 `TQueue.MoveToFront` 在搬移托管元素后没有清空旧尾槽。逻辑队列清空仍可能保留接口、字符串、动态数组和回调捕获，直到容器析构。

项目自有 `DelphiToFPC/DTF.Generics.pas` 新增 `TFpcQueue<T>`：自动搬移后清除逻辑尾之外的副本，公开容量调整后同样清除尾槽。仅使用继承类可见的 `FLength/FItems`，不访问私有 `FLow`，不修改第三方 RTL。HTTP 的两个托管 FIFO 在 FPC 使用该适配器；Epoll/Kqueue 的非托管指针 FIFO 保持标准 TQueue 与原 Notify/Dispose 规则。现有 WS/TLS 的托管 TQueue 也有同类影响，单独接入并验证，不能因本批完成就视为已解决。

`QueueManagedTests` 独立覆盖 interface、string、含 TBytes/string/匿名回调的 record，以及容量扩大/缩减。验证固定深度循环、ToArray 顺序、Clear 后 FPC 物理槽均为默认值、回调捕获在 Clear/析构各释放一次。取消和析构只释放捕获，不擅自执行回调。

```powershell
python run_managed.py fpc64 --raw
python run_managed.py win64 win32 fpc64
python run_managed.py fpc-linux64 --raw --build-only
python run_managed.py fpc-linux64 delphi-linux64 --build-only
```

Linux 使用相同命令加 `--run-only`；`--raw` 原 RTL 的四项红例会返回非零，这是预期结果。`managed-fixed` 保存适配后结果。

## 2026-10-19 结果

- `before-final` 是最终测试源对应的 TList 基线；`fifo` 是首次直接替换 TQueue 的中间版本，FPC 的 request-wrap 为红；`after` 是带最小 FPC 兼容层的最终版本。原四个生产单元保存在 `bin/before-final/production/`。
- 最终普通生命周期回归：Windows Delphi64/32/FPC64 各 7 项，Linux Delphi/FPC 各 8 项，共 37/37。
- 通用托管元素回归：五目标各 4 项，共 20/20。原 FPC Windows/Linux RTL 各四项均红，保留在 `managed-raw`。
- 真实 Epoll 背压：Linux Delphi/FPC 各 6 项，改前和改后均 12/12。相邻 SocketCallbackTests 的发送、回调异常、关闭竞争、关闭后拒绝和注册失败七项，两目标共 14/14。
- Kqueue x64/ARM64 仅编译通过，无 macOS/FreeBSD 运行结论。
- 最终冻结的五个生产源另经根代理重编 HttpFailureTests：Windows Delphi64/32/FPC64、Linux Delphi/FPC 各 88/88，共 440/440，包含真实 TCP、chunk/trailer、无正文及响应关闭竞争；Windows 结果在相邻 `bin/o01-final/`，Linux 结果在该套件对应平台目录。

深度 10000 时每批排空微秒中位数（五个样本）：

| 目标 | 请求 FIFO：前 → 后 | 响应 FIFO：前 → 后 | Epoll 容器：前 → 后 |
| --- | ---: | ---: | ---: |
| Delphi Win64 | 8082.200 → 3929.100 | 43639.100 → 39590.000 | 不适用 |
| FPC Win64 | 8122.300 → 3597.200 | 57208.301 → 55245.098 | 不适用 |
| FPC Linux64 | 9794.568 → 4783.927 | 99357.148 → 95699.547 | 5830.069 → 1170.657 |
| Delphi Linux64 | 11893.578 → 6375.012 | 81301.209 → 76491.236 | 6142.171 → 1426.339 |

深队列收益主要在 client 请求和 Epoll 容器；响应总耗时仍由完整发送/回调路径主导。浅队列不是各目标都变快，例如 FPC Win64 响应深度 1000 本次中位数上升 8.9%；完整原始样本均保留，不据此承诺线上延迟。改前/改后编译记录中 Parser/SSL/其他已记录依赖相同，差异为四个 FIFO 单元及新增适配器；完成回调数组收集方式本批未改。

### FPC Win64 响应深度 1000 的交替复测

针对上面的 +8.9% 单独复测，未重编或修改生产源码。使用同一组 `before-final/fpc64` 与 `after/fpc64` 现有二进制，父进程绑定逻辑 CPU 2，并核验子进程继承相同掩码。四次预热后进行 15 轮配对，奇数轮先前版、偶数轮先后版。每次程序仍执行十批深度 1000 的排空，下面统计的是每批平均耗时；四分位采用 inclusive 定义。

| 版本 | 中位数 ms/批 | Q1～Q3 ms/批 | IQR ms | 折算中位数 μs/响应 |
| --- | ---: | ---: | ---: | ---: |
| 改前 | 5.457900 | 5.370195～5.562290 | 0.192095 | 5.457900 |
| 改后 | 5.759771 | 5.587250～6.258980 | 0.671730 | 5.759771 |

15 轮中 14 轮改后更慢。配对差值中位数为每批 +0.361490 ms、每响应约 +0.361490 μs；配对百分比中位数 +6.34%，两组中位数之比为 +5.53%。第 9 轮改后 10.740140 ms 的离群样本完整保留，未剔除。该回退不能仅归为测量波动，也不能把折算每响应值理解为真实网络请求延迟。

可核对的执行路径差异：原有 FPC `.o` 的反汇编表明，旧 TList.Count 是直接读取字段；新队列在外层 Count、Peek、DoRemove 各执行一次 GetCount 虚调用，并增加 Dequeue 包装调用。旧头删使用 `System.Move` 搬移连续指针块并清零尾槽，并不逐项调整剩余元素的引用计数。深度 1000 的计时排空只省下约 4 MB 指针搬移，而深度 10000 约为 400 MB，固定调用成本与批量搬移收益存在取舍。`TFpcQueue` 的修正仅在入队/容量调整执行；本例入队在计时前，关闭收尾在计时后，不能把该回退归因于兼容层尾槽清理。

以上是已确认的路径差异与合理的成本解释，未做采样 profiler，不能定量断言它解释了全部观测差值。最终保留这一 FPC Win64、中等响应队列深度的性能限制，不宣称所有深度普遍提速，也未为此引入混合容器。每轮整批/每响应绝对耗时、顺序、亲和性、二进制哈希及前后反汇编保存在 `bin/recheck-fpc-response1000/`。
