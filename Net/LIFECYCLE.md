# 生命周期、完成通知与所有权

本文描述当前代码及专项回归已经确认的使用规则，不引入新的公共状态机。范围是本轮验证的 Windows / IOCP、Linux x86_64 / epoll、macOS 14 arm64 / FPC 3.3.1 的基础 Kqueue Socket，以及 Windows/Linux 的默认 OpenSSL 后端；具体编译器、库版本和运行方式以各测试 README 为准。macOS 上层 TLS/HTTP/WS、FreeBSD、MbedTLS、移动端及其他架构没有因此取得运行保证，历史平台支持记录不能代替这些验证。

## 共同规则

- **先确定结果，再调用业务通知。** 已结束的发送或请求不能因迟到完成、重复物理回调、关闭重入或通知自身抛错而再结算一次。这里指已接纳的操作；入队前的参数、流 `Size` / `Seek` 等同步异常仍遵循各入口原有约定，不能推导出“每次调用都会收到回调”。
- **取消不等于物理写已经结束。** 未提交项可以立即取消；在途缓冲、流适配器和必要的连接强引用必须保留到对应物理完成，不能仅因发起 Close 就释放。
- **成功不是对端业务确认。** 发送回调的 True 表示该层发送完成，不表示对端应用已经读取、处理或持久化。关闭期间的结算细节见下表。
- **回调可能同步执行，也可能来自 I/O 线程。** 不保证固定线程或异步切换；不要在回调中等待必须依靠当前回调返回才能推进的工作。界面线程切换和业务对象的并发保护由调用方负责。
- **接口只保活它实际拥有的对象。** 原始对象指针和借用流不会因被闭包捕获就自动获得所有权。调用方应保留所需的接口强引用；显式释放对象后不能再访问原变量。

## Connect 的顺序多地址回退

同一次 `Connect` 按系统解析顺序尝试 IPv4/IPv6 地址。绑定、连接提交或异步连接失败时继续下一地址；地址族/协议不支持也允许回退，创建 socket 时的全局资源错误直接结束。只有连接成功、地址耗尽或主动取消时才执行最终回调，不把单个地址失败提前报告为整次操作失败。

地址列表复制后由一次连接操作持有，各平台共用解析、地址循环与最终结果逻辑。操作通过接口引用保活，不反向强持有连接。失败尝试先从连接表和事件注册中清理，再续试；最终回调及清理通知均沿现有锁外调用规则执行。末次失败若已创建连接，回调保留该关闭连接及其 `LastNetError`；在创建连接之前失败时，回调的连接参数仍可能为 `nil`。`OnDisconnected` 仍按具体尝试对象触发，不能把它当作整次 `Connect` 的最终结果。

普通 `Close` 取消当前连接操作，不启动下一地址。`CloseAllConnections` 同时使解析中、发布前以及两个地址尝试之间的已有操作失效；解析调用本身不会被强制中断，但返回后不得再发布旧连接。关闭全部之后新发起的 `Connect` 仍是新操作，不受上一轮关闭代次影响。调用方仍须保证 socket owner 在并发调用期间存活。

这项功能不增加并行地址竞速或新的每地址超时；挂起的连接仍等待系统结果或调用方取消。TCP 成功后的 TLS 握手失败沿现有 TLS 终态规则处理，不作为换地址的信号。真实回退、关闭屏障、失败信息和堆检查见 [Connect 多地址回归](Tests/FPC/ConnectFallbackTests/README.md)。

## Listen 的登记、通知与停止

监听对象先登记到 owner，再提交 epoll/kqueue 事件或 IOCP AcceptEx，原生提交成功后才认领成功并通知业务。因此 `ListensCount` 可能短暂包含准备中的监听，不能把计数增加当作成功通知。

`CloseAllListens` 同时取消已经开始但尚未登记的旧调用；其后的新 `Listen` 仍可执行。`StopLoop` 开始后拒绝新监听和晚到的接入连接，`StartLoop` 才重新开放；停止再启动不会恢复旧调用。调用方仍须在并发方法调用期间保活 owner；这不提供 StartLoop 与 StopLoop 任意并发调用的保证。

同一次 `Listen` 可针对多个地址分别通知成功，与 `Connect` 的最终一次通知不同。取消先于成功认领时报告失败；成功已经认领后，回调中关闭监听仍保留成功结果。首个成功通知中调用 `CloseAllListens` 会停止剩余地址，不再补发整体失败。已认领的锁外通知可能晚于 StopLoop 返回执行，库不等待所有业务回调结束。

原生句柄提交与关闭使用监听对象锁协调，登记及关闭快照沿用容器锁；业务通知在锁外执行。IOCP 部分 AcceptEx 已提交后初始化失败，会关闭监听并通过真实取消完成回收请求，不提前释放 Overlapped。接入上下文失败也必须补回接受请求，或在补投失败时关闭监听。

Kqueue 接入相同的登记和停止规则，但保留自己的注册表、事件编号及回收算法。屏障测试、实际平台结果和未覆盖范围见 [监听生命周期回归](Tests/FPC/ListenLifecycleTests/README.md)。

## Kqueue 的事件与关闭

Kqueue 的 `udata` 保存 owner 生命周期内不复用的编号。第一次实际注册前，后端私有表保留一份对象接口；同一连接的读写过滤器及重复 `EV_ADD` 共用这一身份，不按注册调用次数累积引用。编号使用本机指针宽度，保留零和停止哨兵；耗尽时注册失败，不回卷复用。

事件返回后，工作线程在短表锁内取得接口，随后解锁处理。Close 撤销注册身份；已经返回但尚未处理的旧事件查找失败后跳过，已经取得接口的工作线程由局部引用保活。`EV_DELETE` 的返回值不再决定对象引用归属。监听的注册、发布和关闭也采用该规则；清理异常不能跳过身份撤销，用户回调及对象最后释放不在注册表锁内执行。

StopLoop 从外部线程关闭对象并等待注册归零、工作线程退出；I/O 线程调用 StopLoop 会在执行关闭操作前报错。应用仍不能在回调中等待依赖该回调返回的停止操作。真实 TCP、对象析构、注册失败和事件在途验证见 [Kqueue 生命周期回归](Tests/FPC/KqueueLifecycleTests/README.md)。

## 各层的关闭与异常行为

| 层 | 已实现的结算规则 | 通知抛异常时 |
| --- | --- | --- |
| Socket 事件边界 | 连接及物理发送通知不因重复清理而重发；异常不能截断同批其他资源收尾 | `_CallConnectionCallback` 捕获并记录；调用者据返回结果决定是否关闭受影响连接，不能概括为“忽略后继续使用” |
| OpenSSL | 逻辑写、密文和明文各按既有顺序推进；TLS 终态不再调用原生读写。因终态拒绝的迟到物理成功可转换成一次 False，在途字节仍保活 | 已接纳写的通知异常被隔离，连接关闭并取消后续逻辑写；已通知的成功不会补发 False。fatal / close_notify 路径已解密的有效前缀与主动取消有不同处理，见 TLS 专项说明 |
| HTTP 服务端响应队列 | ready 与关闭使用同一队列锁决定是否接纳；关闭后的迟发响应被拒绝。关闭取消的在途响应即使迟到物理结果为 True，也只以 False 结算一次 | 用户完成回调和 `DoOnRequestEnd` 分别隔离并记录，不能阻止其余结算或使已完成响应再次失败 |
| HTTP 客户端 | 完成/失败/超时先从当前请求取走回调；结束状态不被迟到响应复活。101 升级不归还 HTTP 空闲池 | 已提交网络请求的响应通知异常被捕获并记录，不追加第二次响应通知；无效 URL 等入队前同步路径的通知异常仍可传播 |
| WebSocket Sender | 普通消息保持完整消息 FIFO，控制帧仅在物理帧边界插入。关闭取消排队消息；未完成分块消息停止续读并失败。此前已在途的完整消息或最终帧仍按其物理结果结算 | 先结算其余项目，再重抛首个同步异常；若从 I/O 事件链进入，外层事件边界可继续隔离。不要假设 WS 同步调用与 HTTP 回调具有相同的异常传播方式 |

HTTP Parser 的失败是终态：回调吞掉 `EAbort`、再次 Decode / Finish 或重入解析，都不能把失败改成成功。HTTP 正文发送策略与连接复用规则另见 [HTTP 状态归属及发送策略](Tests/FPC/HttpFailureTests/README.md)。

实现入口：[Socket 通知隔离](Net.CrossSocket.Base.pas#L1218)、[OpenSSL 逻辑写完成](Net.CrossSslSocket.OpenSSL.pas#L1169)、[HTTP 完成通知](Net.CrossHttpServer.pas#L2907)、[WS 完成与发送泵](Net.CrossWebSocketSender.pas#L330)。这些入口集中各自职责，不要求把它们迁移到一个通用框架。

## 锁边界：队列锁外不等于没有锁

`TCrossSocketBase.TriggerReceived` 在连接的接收锁内同步调用协议接收逻辑，HTTP Parser 回调、路由和 WS 消息事件可能仍处在这条调用链中。发送队列先解锁再执行 provider / 完成通知，只说明它们不持有**该发送队列的状态锁**；若发送由接收回调发起，外层接收锁仍可能存在。见 [TriggerReceived](Net.CrossSocket.Base.pas#L1905) 与 [HTTP 解析入口注释](Net.CrossHttpServer.pas#L3172)。

- HTTP 响应队列、WS Sender 与 OpenSSL 的状态锁保护接纳、顺序和终结；业务取数、通知及关闭工作按各层实现移到该状态锁外。
- 允许的同线程 Close / Send 重入已有回归；这不意味着任意跨线程互等安全。尤其不要持有业务锁等待一个可能反向请求该锁的接收或发送回调。
- 接收回调拿到的原始字节只在约定的回调范围有效。需要跨线程、延后处理时，由调用方复制数据或保留接口明确拥有的数据对象。

## 流和缓冲由谁持有

| 数据入口 | 调用方责任与实现边界 |
| --- | --- |
| `SendBuf` / 裸指针 | 底层只得到地址；数据必须保持有效且不变直到对应发送完成。不能从方法已返回推断内存可释放 |
| 基类 `SendBytes` | 实现保留 `TBytes` 引用直到完成，但不等于内容快照；共享数组在发送期间不得改写。见 [SendBytes](Net.CrossSocket.Base.pas#L2181) |
| WS 普通消息载荷 | Sender 在调用返回前构建自己的帧，排队后可释放调用方原载荷；这是 WS 的已测行为，不能推广到所有发送方法 |
| HTTP / WS 的普通 `TStream` 与 provider | 流为借用，调用方保活到完成通知，并避免同时 Seek、读取、写入或释放。provider 提供的缓冲必须活到相应物理写完成；仅由库内部创建的流，由对应内部收尾负责释放 |
| HTTP / WS 已知长度流 | 正数短读继续推进；仍有预期字节却返回 0 / 负数，或 Read 抛异常，均进入发送失败收尾。原始 Socket `SendStream` 按读到 EOF 结束，没有相同的声明长度契约，不应混为一谈 |
| 接收的 HTTP 请求正文 | `RawBody` 是请求拥有的流，调用方不能单独 Free。保留请求接口可保活已解析数据；连接关闭后请求的连接引用可能已解绑。不要把这解释为停服后仍可使用依赖服务器的 Session 等能力 |

完成通知允许调用方释放其借用流，此前不能释放。在途物理完成、取消和来源异常的覆盖分别见 [HTTP 队列/流测试](Tests/FPC/HttpFailureTests/README.md)、[WS Sender 测试](Tests/FPC/WebSocketFrameTests/README.md) 与 [WS 流测试](Tests/FPC/WebSocketStreamTests/README.md)。临时文件流的刷新失败也不会跳过缓冲、句柄和文件清理，但原异常仍可上抛；不要把析构一律视为不抛异常，见 [文件流清理测试](../Utils/Tests/FPC/FileStreamCleanupTests/README.md)。

**取数时机有区别：** WS 排队流尚未轮到时不调用 Read，但 Size / 初始 Seek 仍可能在调用 Send 时执行。HTTP chunk provider 会先预取首块，压缩包装也可能为生成首块而提前取数；不能把 WS 的不预读规则套到 HTTP。HTTP 无正文策略则抑制 provider / 压缩正文取数。见 [HTTP provider 入口](Net.CrossHttpServer.pas#L5246)。

## 原始请求体落盘

`TCrossHttpServer` 具体类的 `BodyMemoryThreshold` / `BodyTempPath` 在启动监听前配置，既有 `ICrossHttpServer` / `ICrossHttpParser` 接口布局保持。阈值默认 0，保持内存；启用后仅原始二进制正文超过阈值时迁移，URL 编码表单和 multipart 保留各自的处理方式。业务仍在完整请求到达后读取 `TStream`，落盘不表示总正文上限被取消，也不表示开始向业务流式发布。

临时正文属于请求，**请求对象最后一个引用释放时**才关闭并删除文件，不由“响应已经发完”或“业务变量设为 nil”单独决定。请求可被业务直接持有，也可由响应对象间接持有；连接还缓存最近一次完整请求，直到下一次完整请求替换该缓存或连接对象析构。`InternalClose` 会解绑请求对连接的反向引用，但保留最近完整请求的数据，因此网络已关闭、连接接口仍被持有时，文件也可能仍在。未完成请求在失败/断开清理中释放；完整请求仍可由业务保留后继续读取。见 [完整请求缓存](Net.CrossHttpServer.pas#L3257)、[连接析构](Net.CrossHttpServer.pas#L2562) 与 [请求析构](Net.CrossHttpServer.pas#L4609)。

发布业务前调用 `TFastFileStream.FlushBuffer`，使尾部缓存的真实写入错误先进入解析失败流程；随后把读取位置设为 0。该操作只检查用户态缓冲是否写入文件接口，**没有调用 `fsync` 或 `FlushFileBuffers`，不提供断电持久化保证**。见 [正文结束处理](Net.CrossHttpServer.pas#L3076) 与 [SyncBuffer](../Utils/Utils.IOUtils.pas#L281)。需要持久化的业务应把完整正文复制到自己管理的目标并采用自己的持久化流程，不能保留这个自动删除临时文件作为持久存储。

`BodyTempPath` 的配置独立于 multipart 的 `StoragePath`，但这不保证默认物理目录不同：空值沿用程序目录下 `temp`，它也可能是上传文件的默认目录。启用阈值时应明确选择专用、未公开为静态文件路由的目录。POSIX 新文件使用 0600，Windows 沿用目录 ACL；文件权限不替代同进程 HTTP 路由的隔离。临时正文删除不受上传文件的 `AutoDeleteFiles` 设置控制。具体配置、文件错误与引用生命周期验证见 [O03b 测试说明](Tests/FPC/HttpFailureTests/README.md#o03b-原始正文阈值落盘与总量限制)。

## 可选容量设置

容量通过具体类配置，既有接口 GUID/方法表保持；新限额默认 0，沿用不限量行为。类布局与实现已有变化，依赖单元仍须完整重编译。配置及计费范围如下：

| 层 | 配置与生效时机 | 接纳与释放边界 |
| --- | --- | --- |
| 基础 Socket | `MaxPendingSendCount` / `MaxPendingSendBytes`，在新连接建立前设置，每连接取快照 | 统计本层未完成的正长度发送及原始提交长度，包含部分写尚未结束的项目；完成/取消后先归还额度再通知，超限一次 False，健康连接可继续 |
| OpenSSL | `SslQueueLimits`，新连接快照；具体连接的 `SetSslQueueLimits` 只允许空闲调整 | 分别限制逻辑写、密文与接收缓冲的数量/字节；逻辑写接纳前可拒绝，已生成 TLS 记录却无法提交时必须终止，不能丢记录后继续 |
| HTTP 服务端 | `MaxPendingRequests`，新连接快照 | 解析中、排队及在途响应共同计数；超限终止解析并关闭，不插队发送错误响应 |
| HTTP 客户端 | `MaxPendingRequestsPerServer`，首次请求前设置，每个新 server 池取快照 | 排队、连接建立中及活动请求共同计数；超限本地 503，完成前内部重试不重复计费 |
| WebSocket | 两端具体连接的 `SetWebSocketSendQueueLimits`，在开始业务发送前且 Sender 空闲时设置 | 数据消息与控制帧分别限数量/编码后字节；当前流每帧完成归还帧字节，整条消息结束才归还消息数 |

底层字节数以实际交给 Socket 的长度为准，TLS 密文和 WS 帧头/掩码会增加长度。单次发送超过该层上限会被拒绝，限额不会自动切分数据或等待名额；调用方安排后续重试。未知 provider 自己分配的源缓冲、业务保留的已完成请求/响应、OpenSSL 内部堆和内核缓冲不属于这些计数，不能据此推导进程总内存硬上限。只限制 bytes 也不能替代尚未产出数据的排队项目数量限制。

客户端析构先禁止新接纳，再取消队列、关闭连接并停止 I/O；内部已出队但尚未提交的请求也要经过关闭检查。应用应在外部线程销毁客户端/停止 Socket，不能在该实例的 I/O 线程同步等待自身退出；外部调用期间必须用自己的局部接口保活，不能同时释放最后引用又以裸指针继续调用。连接建立前的绑定等失败只回收该次地址尝试，全部尝试失败才统一通知；已创建连接且已由 Close 结算的失败不再次通知。

具体配置、测试和适用范围见 [Socket/客户端容量](Tests/FPC/CapacityTests/README.md)、[HTTP 正文和请求容量](Tests/FPC/HttpFailureTests/README.md)、[TLS 容量](Tests/FPC/TlsIoTests/README.md)、[WS 容量](Tests/FPC/WebSocketCapacityTests/README.md) 与 [真实绑定失败回归](Tests/FPC/ConnectFailureTests/README.md)。

## Session 的显式约束

实现位于 `Net.CrossHttpSessions`；原 `Net.CrossHttpParams` 保留类型别名，旧 uses 路径继续可用。声明归属单元及限定 RTTI 名称已变化，包和预编译单元必须完整重编译；别名不承诺二进制兼容。

`GetSession` / `Sessions[ID]` 与 `ExistsSession` 内部取得写锁，原子完成过期检查、移除和续期；不能包在调用方的读锁内。Add、Remove、Clear、Count、索引及枚举沿用调用方显式加锁约定，`Session.Values` 没有因此获得独立的并发保证。

清理的 `BeforeClearExpiredSessions`、`OnCheckExpiredSession`、`AfterClearExpiredSessions` 在会话写锁内执行；从 `GetSession` 路径调用的 ID 生成器和会话构造同样在写锁内。它们不属于发送层的“锁外业务回调”，不得等待需要同一锁的其他线程，也不得在清理线程中销毁自身 Session 容器。

`TSessionBase.FOwner` 是原始容器指针，`Owner` getter 才把它转为接口。**持有 `ISession` 不会保活容器，Owner 也不是会自动清空的安全弱引用。** 调用方访问 Owner 时必须保持对应 `ISessions` 存活；不能在容器销毁后再从会话取得 Owner。见 [FOwner 声明](Net.CrossHttpSessions.pas#L99) 与 [GetOwner](Net.CrossHttpSessions.pas#L464)。

外部销毁容器时先撤销调用方持有的会话锁；析构发停止信号，在不持有会话锁时等待清理线程真正退出，然后释放字典。清理钩子异常没有“下一轮自动重试”的保证。完整约定及验证见 [Session 测试](Tests/FPC/HttpSessionTests/README.md) 和 [批量清理测试](Tests/FPC/BatchCleanupTests/README.md)。

## EasyThread / EasyTimer

- `Terminate` 是协作终止，不会中断正在执行的用户代码。外部 `WaitFor` / 析构等待任务实际结束；不要在持有任务所需锁时等待。
- EasyThread 的无参及 `High(Cardinal)` 外部等待串行完成一次原生 join，`Finished` 不能替代首次 join。有限 `WaitFor(timeout)` 只等待任务和线程保存的闭包清理，True 不表示已经 native join，超时不会终止任务。工作线程自身无参等待直接返回、有限等待返回 True（no-op）；自身析构把底层线程释放交给 `FreeOnTerminate`。回调收到独立 Control，保留它不会变成悬空线程指针；ThreadID 是缓存身份，不能用来证明线程仍存活。见 [生命周期测试](../Utils/Tests/FPC/EasyThreadTests/README.md)。
- EasyTimer 的工作回调保活独立状态，允许回调内释放 Timer；析构发出停止信号，回调返回后结束。Timer 捕获回调异常后继续后续周期，日志异常不阻断清理；这不同于一次性任务和 Session 清理线程。回调运行在 Timer 状态锁外，但调用方自己的锁仍由调用方负责。
- Timer 的暂停不取消已经接纳的回调；空闲/暂停时视为健康，正在运行的回调可通过超时检查识别卡顿，Finished 后保留最后心跳。见 [Timer 实现](../Utils/Utils.EasyTimer.pas#L125) 与 [测试说明](../Utils/Tests/FPC/EasyTimerTests/README.md)。
- 最新版的 Timeout、BeforeExecute/AfterExecute、超时等待接口已合并。非正周期仍按10ms执行；IsTimeout正参数优先，否则使用Timeout配置。事件参数保留真实Timer身份，事件周期临时保活并在finally锁外释放；Before异常跳过本轮后续，Proc异常仍执行After。非nil事件须在构造后持有接口再安装，事件接收对象由调用方保活。接口布局扩展后须完整重编，详见[最新版合并与跨平台验证](../Utils/Tests/FPC/LatestThreadTimerTests/README.md)。

上述自毁支持不能推广到 Session 容器、任意 TThread 或其他具有后台回调的对象。

## 验证范围

本文件整理既有行为，没有新增运行结果。平台事件异常与收尾见 [SocketCallbackTests](Tests/FPC/SocketCallbackTests/README.md)，HTTP 数据与连接寿命见 [HttpRequestLifetimeTests](Tests/FPC/HttpRequestLifetimeTests/README.md)，OpenSSL 的有序输出、终态、有效前缀和缓冲寿命见 [TlsIoTests](Tests/FPC/TlsIoTests/README.md)。各套件明确区分组件夹具、真实 TCP、原生 TLS、实际运行、仅编译和未覆盖平台，不能把其中一种证据扩大为全部场景保证。

容量配置及其超限策略以各层专项说明为准；后续改变所有权、回调时机或锁边界时，应同步更新本约定及对应回归。

WS 两端具体连接的 `SetWebSocketSendQueueLimits` 使用 `TWsSendQueueLimits`，默认四项为 0，不改变既有接口。计数包含构帧、排队及在途项；字节仅覆盖本层编码后帧（含头部/掩码），不覆盖 provider 源缓冲或下层队列。完整数据消息入队前超限以一次 False 拒绝，健康连接仍可使用；已接纳 provider 的帧超限、控制帧或 Close 预算不足则关闭。额度在结算时先归还再通知，在途内存仍保留到物理完成；配置只允许空闲且未关闭时修改。边界及实际矩阵见 [WS 容量专项](Tests/FPC/WebSocketCapacityTests/README.md)。
