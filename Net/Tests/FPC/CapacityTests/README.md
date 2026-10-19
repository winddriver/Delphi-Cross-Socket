# 客户端与基础 Socket 容量回归

对应 O03a。Client 容量及 Connect 关闭/失败边界已作为 `7123233` 独立提交，下面保留该阶段证据；基础 Socket 发送数量/字节限额为后续独立步骤，仅修改 Base 与三个后端，新增结果见末尾 Socket 章节。两阶段均保持既有接口 GUID/方法布局，不修改 Kqueue 的 F05 引用算法。

## 配置与计数

仅在具体类提供 `TCrossHttpClient.MaxPendingRequestsPerServer: Integer`，默认 0（<=0 不限）。不修改 `ICrossHttpClient`、`ICrossHttpClientSocket` 或其他既有接口的方法/GUID布局；类私有布局改变，依赖单元需完整重编译。

```pascal
LClientObject := TCrossHttpClient.Create(2, 4);
LClient := LClientObject;
LClientObject.MaxPendingRequestsPerServer := 64;
// 在首次请求前设置，再通过 LClient 发起请求。
```

每个新建 server 池（既有协议/host/port 分组）快照这个值。运行中更改 Client 属性不会追溯修改已有池，只影响之后新建的池；不能将其理解为即时改变所有 server 的全局开关。

正值时，首次接纳在池的现有锁内预占一次，数量包括排队、连接建立中、已经取出但尚未完成、活动请求。Pop/内部重试保留原额度。数量达到上限时返回本地生成的 503、文本 `Client request limit exceeded`，没有发送 HTTP 错误报文，不读取 provider，也不关闭健康连接。未知 provider/stream 的完整长度不提前探测；这一步限制请求数量，不声称限制调用方所有正文或闭包所占字节。

请求仅持有包含 count 和锁引用的独立状态，不反向持有 server 池，避免池→请求→池的环。默认不限额时不创建状态，也不为每个请求保存额外计数引用。`_ExecCallback` 原子认领完成，先归还额度，再通知用户；nil 回调也结算，回调抛异常或重入不会多退或少退。请求析构仅释放仍未归还的计数引用，不用析构归零冒充完成通知。

## 析构与内部接纳

客户端析构先置 Closing，终止并等待 Timer，再逐 socket 取消排队请求、关闭连接、停止事件循环；取消结果沿用本地 400。单个取消/关闭异常不能跳过其余 socket 的停止。析构中的回调使用原始指针重入时，两个核心 DoRequest 入口只取消一次，不建立新的 `ICrossHttpClient(Self)` 引用以复活零引用对象。

仅检查公开入口还不够：ProcNext 可能已经弹出请求，另一个请求也可能停在最终 Push 前。内部 DoRequest、最终入队、连接预占、实际提交和连接成功路径都检查 Closing；队列锁内决定是否入队，取消在锁外通知。

连接登记与 CloseAll 快照之间也可能交错。HTTP socket 在基类 TriggerConnecting 登记后发现 Closing 就立即 Close。三后端 Connect 在 TriggerConnecting 返回 Closed 时将该地址尝试视为“已处理”，停止外层地址重试，不再投递 ConnectEx/注册写事件、重复 False 或重复关闭已交接给连接的句柄。Epoll/Kqueue 不再在锁内重复写 `csConnecting`，否则前置检查之后的 CloseAll 可能被覆盖；注册返回 False 且连接已经 Closed 也作为已处理退出。

未创建连接对象时，Bind/IOCP关联等失败只回收本次尝试的原始句柄，耗尽地址后由外层统一 False 一次。已创建连接对象并由 Close 结算的同步失败不再重试；IOCP ConnectEx 同步失败也遵循这一规则。此补修只位于 Connect 路径，未改 Accept 或 Kqueue 注册引用算法。

调用方必须在外部 DoRequest 调用返回前用自己的局部 Client 接口保活；不支持另一个线程同时释放最后引用而仍以裸指针继续调用。before-push 测试刻意让析构停留到请求线程返回，验证接纳关闭边界，不测试释放后访问对象。

保持现有停止边界：应用应在非 I/O 工作线程上销毁/StopLoop；本轮不支持在当前 I/O 线程同步等待自身退出，也没有重写用户闭包自身形成的强引用环。

## 测试

组件使用真实 TServerDock/请求对象和队列，只替换连接建立为可控延迟完成。九项覆盖：connecting+queued 总量、nil 回调、回调抛异常、回调重入、取消重入、8 生产线程并发提交 64 请求且只接纳 8 个、不同 server 独立计数、同步连接失败、默认无限制。provider 调用次数必须为零，拒绝项不能触发预读。失败、取消及恢复后的后续请求各通知一次。

真实 TCP 六项覆盖活动请求+排队的共同上限、nil 回调后恢复、回调异常后继续复用、CancelAll 后实际断开并恢复请求、析构取消全部已接纳请求、析构回调通过原始对象指针重入仅被取消且客户端析构一次。

三个额外门控仍运行真实 TCP 和真实析构，只由 `CROSS_CAPACITY_TESTS` 打开同步屏障：

- `client-race-pop`：ProcNext 已 Pop 请求后暂停；析构清空取消快照，再放行请求，不能发出第二个 HTTP 请求。
- `client-race-push`：请求已开始但尚未进入最终 Push；析构清空快照后才放行，必须锁外取消，不能遗留队列项。
- `client-race-register`：真实连接已登记、后端尚未继续投递；析构开始后放行，连接必须关闭且请求只失败一次，不能发布业务请求。Linux 的 connect 系统调用早于登记，允许 TCP 握手已经发生，但不允许发送 HTTP 请求。

测试进程均有限时退出、kill/wait 回收、TCP 对端与输出线程清理。受控的失败测试有时直到 Python 清理对端后才退出，因此报告按等待期限判失败，不依据其末尾出现 PASS 就误认成功。

## 红绿证据

- `bin/before`：原容量缺失版本，Delphi/FPC Win64 各 **7 失败、2 通过**；默认无限制、同步连接失败是正常对照，不算红例。
- `bin/client-before-stop`：已加入容量但仍为旧析构。两个目标的 Stop/Stop-reenter 均失败；CloseAll 的回调可继续启动排队请求，StopLoop 等待连接数归零。部分用例在对端被测试清理后才完成，不能简化为所有请求都静默丢失。
- `bin/client-before-race`：首轮 Closing 仅封公开入口。两个目标的 pop/push/register 三项全部失败，分别观察到 `/1` 被发送、快照后请求没有及时取消、停止后登记连接仍发出 `/0`。
- `bin/client-complete`：Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64，每目标 **9 组件＋9 真实 TCP/竞态，共 90/90**。
- `bin/client-before-gap`：门控放在前置 IsClosed 检查之后，由真实 CloseAllConnections 关闭当前连接；旧 Epoll 在两个 Linux 编译器均出现重复失败通知。最终 `bin/client-complete` 两目标的 `gap.json` **2/2**，关闭后不回写连接状态、不重试/重复 False。
- 相邻 HTTP 定界 Delphi/FPC Win64 **44/44**，O02 超时快照两目标 **12/12**；最终四目标早期失败句柄回收、连接通知异常及100轮连接/关闭竞争 **12/12**。
- Kqueue Delphi OSX64/OSXARM64 编译通过，仅编译，没有 macOS/FreeBSD 运行结论。

构建日志、实际源码 SHA-256、二进制与结果保存在各 `bin/<label>/<target>/`；编译单元仅写 lib。三个阶段的 Client 原始快照各保留在对应标签的 production 目录，旧阶段后端源码以 source.json 哈希为准，不用当前修改后的源码覆盖红色二进制。

Client 阶段最终 Client SHA-256：`9032c29100453e197ce133df0c869bac2444e6709bd39cb37cf14b1e0b91bc64`。IOCP/Epoll/Kqueue 分别为：

```
c8b70b3edf565cac2a7eb4586ee544d934f6efe297ef462eb14b1168f53d2717
fd960054c880304c077257de2dde84330ca2bad0f02e8b1b2fba6f23ff3b8363
3ad73a4ca67560ffc5da009a4b3b983d5ef72093aa997e03636553c7ac89c08e
```

## 运行

在本目录使用现有 Delphi/FPC 工具链：

```powershell
python build.py win64 win32 fpc64 fpc-linux64 linux64 --label client-complete
python run_tests.py bin/client-complete/win64/CapacityTests.exe --output bin/client-complete/win64/results.json
python run_client_network.py bin/client-complete/win64/CapacityTests.exe --output bin/client-complete/win64/network.json
```

其余目标替换路径。交叉构建的 Linux 产物必须在实际 Linux 中运行：

```sh
python3 run_tests.py bin/client-complete/fpc-linux64/CapacityTests --output bin/client-complete/fpc-linux64/results.json
python3 run_client_network.py bin/client-complete/fpc-linux64/CapacityTests --output bin/client-complete/fpc-linux64/network.json
```

基线可用 `--source <snapshot-directory>` 指定单元覆盖，构建脚本自动识别具体类配置属性与门控入口是否存在。正常生产构建不定义测试宏。

## 基础 Socket 配置与所有权

仅具体类 `TCrossSocketBase` 增加两个配置，子类可直接使用，不改 `ICrossSocket`/`ICrossConnection` 布局：

```pascal
LSocketObject := TCrossSocket.Create(2);
LSocket := LSocketObject;
LSocketObject.MaxPendingSendCount := 128;
LSocketObject.MaxPendingSendBytes := 4 * Int64(1024 * 1024);
// 在 Listen/Connect 前配置；新连接构造时复制这些值。
```

两项默认 0，<=0 分别表示不限条数/字节。已有连接保持创建时快照，后续修改 owner 属性只作用于之后创建的连接。测试同时验证“原限额连接在 owner 改0后仍有限额”和“原无限制连接在后来创建限额连接、owner标记改变后仍不限额”。

计数对象只在至少一项限额为正时创建，持锁保存两个 Int64 余额。计费对象是底层每次接纳的正长度 `ALen`，包括队列项和已交给系统但尚未结算的项；不是整个高层 Stream/provider 的预先总长度。TLS、WS 的逻辑队列另有自己的限制，各层数字也不能简单相加当成新分配的内存。

三个后端的公开 `Owner.Send` 都进入同一个检查入口，`DirectSend`/`SendBuf` 也通过这里；没有只约束高层入口而留底层绕过。超额项在锁外 False 一次，基础层不关闭健康 socket；成功、失败、取消完成包装先用原始 `ALen` 归还额度，再调用原回调。部分写只更新发送游标，不提前归还已写出的那一部分；重复完成不能重复归还。nil 用户回调也保存内部完成包装，所以仍正确释放额度。关闭连接不能直接清零 IOCP 在途余额，必须等完成包或停止 drain 结算。

完成包装只持计数状态、原长度和原用户回调，不反向持有连接。创建包装失败会撤回预占并通知 False；底层记录分配或提交失败同样收尾，已入队项交由关闭清队列逐项结算，避免二次通知。裸指针发送仍要求调用方保持数据有效到完成，不因启用限额自动复制缓冲；启用额度时应提供回调以观察拒绝。

无效参数规则明确：负长度、nil连接、nil缓冲且正长度均 False，不记账、不关闭健康连接；零长度在有效且未关闭/断开的连接上同步 True，不占容量。已关闭/断开的零发送 False。Int64 字节上限不转换为 Integer，比较采用减法并检查累计值溢出。

默认双0时不创建额度对象、额度锁或每包包装。入口没有 managed 局部变量；有效正长度在检查基本参数后直接交回原后端处理连接状态。owner 曾创建过限额连接时保留一个只增不减的标记，原无限制连接可能多一次 nil 状态查找，但仍不会创建包装或取得额度锁。类配置及 nil 状态字段会增加少量实例大小，因此不把“无额外额度对象”写成总体零内存开销。

TLS/WS 在底层拒绝后可按原协议错误规则关闭：已生成 TLS 记录序号或已经发出 WS 消息首片时不能丢弃中间字节后继续下一条消息。基础 Socket 自身的超额拒绝不会关闭连接，协议层选择关闭不与此约定冲突。

## Socket 回归与组合边界

首轮真实 Windows 基线在 `bin/socket-before/{win64,fpc64}/socket.json`，各 **7 失败、1 默认不限额对照通过**；Linux 同标签保存 count/partial 红例及默认对照。基础 fixture 使用真实监听、TCP、IOCP/Epoll，不覆盖底层 Send。唯一工作线程停在接收事件屏障，应用侧直接排队，使额度判断和在途时序可重复。

最终 `bin/socket-final`：Delphi Win64/Win32、FPC Win64 各 **18/18**；Delphi/FPC Linux64 各 **20/20**，共 **94/94**。

- 精确条数/字节边界，单项过大，4GiB以上字节配置；拒绝后原连接继续发送。
- 直接 Owner.Send 与高层 SendBytes 两条入口；nil回调也退额。
- 成功回调重入、成功回调抛异常、拒绝回调抛异常；每项最多通知一次，捕获对象最终全部释放。
- 8个生产线程并发提交64项，只接纳8项；核对实际收到的ID集合，下一批容量完整恢复。
- 已接纳后 Close/Stop：Windows 工作线程仍阻塞时余额保持2项/20字节，放行完成包后才归零；Linux未开始项在清队列时取消。
- 实际 RTL 分配失败：仅发送线程的首次分配注入 EOutOfMemory，触发限额包装分配失败，余额归零、False一次、连接仍健康且后续批次成功。MM在finally恢复；这不是磁盘/内核内存耗尽测试。
- 实际系统发送失败：对测试自己拥有的 socket 做写半关闭，再发送；IOCP同步失败、Epoll写事件失败均结算并关闭。
- Linux真实EAGAIN：两个1MiB原始项，小发送/接收缓冲，对端停止读；实际写事件返回后两项仍未完成，余额必须仍是2项/2MiB。之后分别完整排空或中途关闭，检查原字节归还、内容/结果及释放次数。

新测试宏仅提供 `GetPendingSendForTest` 和 `CrossSendRejectedForTest`。前者在启用限额时读取受锁保护的计数；默认不限额返回0并不代表没有在途IO。后者只在真正的 Base Reserve 拒绝后锁外触发，可由组合测试准确定位拒绝层，不改变结果或发送路径。正常生产不包含这些入口。

最终底层源码同时重跑已有 Client 组件/真实TCP/关闭竞态 **90/90**，Linux直接Connect关闭窗口 **2/2**。相邻 SocketCallbackTests 覆盖发送事件/完成异常、pending、关闭取消、100轮Send/Close竞争及注册失败；最终 Windows两个目标各10项、Linux两个目标各11项，共 **42/42**。Kqueue OSX64/OSXARM64仅编译，没有运行结论。

原生TLS与TLS+WS的实际底层额度组合由独立专项执行，保留正常与4KiB限额对照，不用 Send/DirectSend 替身；最终记录分别见 `TlsIoTests` 与 `WebSocketTlsCapacityTests`。限额在建连接前设置，观察真实Base拒绝、上层大写及尾项各一次失败、关闭与余额0；这些独立组合结果不混入本目录的94项。

## 默认路径开销

基准直接调用真实 Owner.Send，每项1字节、nil回调；工作线程被接收屏障暂停，计时只覆盖应用侧连续提交，之后放行并校验对端收到完整字节。Windows窗口包含实际WSASend投递，Epoll窗口包含队列操作和epoll_ctl；不能跨平台直接比较，也不是纯函数开销、吞吐或网络P99。

时间与RTL申请分开进程测量，时间窗口没有MM hook；申请窗口只统计发送线程的GetMem/AllocMem/ReallocMem请求，不统计内核缓冲或进程峰值。Windows线程固定CPU掩码4，Linux为WSL Ubuntu 22.04，未设置亲和性。首个前后样本对剔除，最终9对交替顺序；保存全部原始输出、中位数和IQR。

首版有效默认路径重复读取状态，Linux每10000次提交：FPC 7060.621→7544.841us（+48.4ns/次），Delphi7608.512→8185.061us（+57.7ns/次）。提前默认快路后仍有managed局部初始化/清理成本，分别残留约38.1/30.4ns；将限额对象处理移入私有方法后停止继续微调。三个阶段结果保留在 `socket-bench-first`、`socket-bench-fast`、`socket-bench-final`，原版在 `socket-bench-before`。

最终对照（微秒，括号为IQR）：

| 目标 | 每批条数 | 原版中位数（IQR） | 最终中位数（IQR） | 变化 |
| --- | --- | --- | --- | --- |
| Delphi Win64 | 1000 | 14515.700（620.600） | 14410.200（442.200） | -0.73%，差异在波动内 |
| FPC Win64 | 1000 | 14095.300（111.300） | 14025.601（482.800） | -0.49%，差异在波动内 |
| Delphi Linux64 | 10000 | 7540.609（163.713） | 7778.270（28.613） | +3.15%，+23.8ns/次 |
| FPC Linux64 | 10000 | 7095.326（221.100） | 7286.500（108.991） | +2.69%，+19.1ns/次 |

首轮Windows10000条样本呈明显双峰和大IQR，未把数十毫秒差异归因给几次状态读取；最终改用1000条、9对相同前后二进制，结果只说明此负载下相近，不宣称Windows提速。Linux仍保留小固定成本，接受参数检查、共享调用和提交失败保障的取舍；没有逐指令剖析，也不将剩余回退隐去或重写派发层来追求零纳秒。

RTL申请次数与累计请求字节前后完全一致：Windows每1000条均1000次/152000字节；FPC Linux每10000条均10021次/531664字节；Delphi Linux均10013次/502320字节。这支持默认发送没有新增每包额度锁/闭包分配，不包括连接实例字段增量或OS分配。

这些基准产物在补最后的分配失败/部分写取消用例前建立，前后基准使用相同Pascal测试源；最终生产源码相同，后续只扩充测试。每组source.json保留实际源码，未覆盖旧数据。

最终基础 Socket SHA-256：

```
Base   1dea20133be770f6cc998a08973fa8fa35884f27b35553b9f349474b138e7af8
Iocp   27d4ca2e03cf326d234895b4b3325380271f1eb58539fa768c12486fef7a470e
Epoll  449bb2e36542868a62d7dd2bffd6dd481670540238b6214304e45af1876b1604
Kqueue a4ea5a547ba5fab764430e5a2330716c3a2d9e9ed55fe46f509debe055bcc3c8
```

Socket复现入口：

```powershell
python build.py win64 win32 fpc64 fpc-linux64 linux64 --label socket-final
python run_socket.py bin/socket-final/win64/CapacityTests.exe --output bin/socket-final/win64/socket.json
python run_send_bench.py win64 fpc64 --before socket-bench-before --after socket-bench-final --count 1000 --samples 9
```

Linux运行同名脚本，并额外运行 `--cases socket-partial socket-partial-close`；默认基准用 `--count 10000 --samples 9`。基准会向after目录写send-bench.json，重现历史时应使用新标签，避免覆盖保留的原始结果。

## 最终工程与实际应用检查

以最终 Base `1dea2013…` 及同一份当前生产源码，经 MSBuild 全量构建三个正式 `.dproj`：HttpServer、HttpClient、WebSocketServer 的 Release/Win64 均通过。记录在 `bin/final-formal-win64/<工程>/`，每项保存构建日志、程序 SHA-256 和编译前后确认未变化的 13 个核心单元哈希。构建生成的示例资源已恢复，没有启动 HttpClient 图形界面。

最终 HttpServer 程序另用 `HttpSessionTests/run_demo_upload.py` 做实际应用验收：严格证书/主机名校验下，TLS 1.2/1.3 各两次 multipart 请求，共 12 个文件、24 个 MD5/SHA1 全部正确。回车正常退出，测试进程、8080 监听及本测试上传文件均已清理；结果为 `bin/final-formal-win64/HttpServer/upload-final/results.json`。上传文件的清理由测试脚本完成，未改变示例原有 `AutoDeleteFiles=False`。

同一最终 Base 还通过两组四目标真实组合：原生 TLS **16/16**、TLS+WS **16/16**，最终清单分别是 `TlsIoTests/bin/base-combination-final-manifest.json` 和 `WebSocketTlsCapacityTests/bin/final-base-source.json`。对应正常/限额两个分支均使用最终源码重编；旧版本证据保留，没有用旧程序替代最终复验。
