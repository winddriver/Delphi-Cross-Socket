# 生命周期、完成通知与所有权

本文描述当前代码及专项回归已经确认的使用规则，不引入新的公共状态机。范围是本轮验证的 Windows / IOCP、Linux x86_64 / epoll，以及默认 OpenSSL 后端；具体编译器、库版本和运行方式以各测试 README 为准。Kqueue 的运行时行为、MbedTLS、移动端及其他架构不属于本轮保证，历史平台支持记录不能代替这些验证。

## 共同规则

- **先确定结果，再调用业务通知。** 已结束的发送或请求不能因迟到完成、重复物理回调、关闭重入或通知自身抛错而再结算一次。这里指已接纳的操作；入队前的参数、流 `Size` / `Seek` 等同步异常仍遵循各入口原有约定，不能推导出“每次调用都会收到回调”。
- **取消不等于物理写已经结束。** 未提交项可以立即取消；在途缓冲、流适配器和必要的连接强引用必须保留到对应物理完成，不能仅因发起 Close 就释放。
- **成功不是对端业务确认。** 发送回调的 True 表示该层发送完成，不表示对端应用已经读取、处理或持久化。关闭期间的结算细节见下表。
- **回调可能同步执行，也可能来自 I/O 线程。** 不保证固定线程或异步切换；不要在回调中等待必须依靠当前回调返回才能推进的工作。界面线程切换和业务对象的并发保护由调用方负责。
- **接口只保活它实际拥有的对象。** 原始对象指针和借用流不会因被闭包捕获就自动获得所有权。调用方应保留所需的接口强引用；显式释放对象后不能再访问原变量。

## 各层的关闭与异常行为

| 层 | 已实现的结算规则 | 通知抛异常时 |
| --- | --- | --- |
| Socket 事件边界 | 连接及物理发送通知不因重复清理而重发；异常不能截断同批其他资源收尾 | `_CallConnectionCallback` 捕获并记录；调用者据返回结果决定是否关闭受影响连接，不能概括为“忽略后继续使用” |
| OpenSSL | 逻辑写、密文和明文各按既有顺序推进；TLS 终态不再调用原生读写。因终态拒绝的迟到物理成功可转换成一次 False，在途字节仍保活 | 写通知异常被隔离，连接关闭并取消后续逻辑写；已通知的成功不会补发 False。fatal / close_notify 路径已解密的有效前缀与主动取消有不同处理，见 TLS 专项说明 |
| HTTP 服务端响应队列 | ready 与关闭使用同一队列锁决定是否接纳；关闭后的迟发响应被拒绝。关闭取消的在途响应即使迟到物理结果为 True，也只以 False 结算一次 | 用户完成回调和 `DoOnRequestEnd` 分别隔离并记录，不能阻止其余结算或使已完成响应再次失败 |
| HTTP 客户端 | 完成/失败/超时先从当前请求取走回调；结束状态不被迟到响应复活。101 升级不归还 HTTP 空闲池 | 已提交网络请求的响应通知异常被捕获并记录，不追加第二次响应通知；无效 URL 等入队前同步路径的通知异常仍可传播 |
| WebSocket Sender | 普通消息保持完整消息 FIFO，控制帧仅在物理帧边界插入。关闭取消排队消息；未完成分块消息停止续读并失败。此前已在途的完整消息或最终帧仍按其物理结果结算 | 先结算其余项目，再重抛首个同步异常；若从 I/O 事件链进入，外层事件边界可继续隔离。不要假设 WS 同步调用与 HTTP 回调具有相同的异常传播方式 |

HTTP Parser 的失败是终态：回调吞掉 `EAbort`、再次 Decode / Finish 或重入解析，都不能把失败改成成功。HTTP 正文发送策略与连接复用规则另见 [HTTP 状态归属及发送策略](Tests/FPC/HttpFailureTests/README.md)。

实现入口：[Socket 通知隔离](Net.CrossSocket.Base.pas#L951)、[OpenSSL 逻辑写完成](Net.CrossSslSocket.OpenSSL.pas#L1169)、[HTTP 完成通知](Net.CrossHttpServer.pas#L2907)、[WS 完成与发送泵](Net.CrossWebSocketSender.pas#L324)。这些入口集中各自职责，不要求把它们迁移到一个通用框架。

## 锁边界：队列锁外不等于没有锁

`TCrossSocketBase.TriggerReceived` 在连接的接收锁内同步调用协议接收逻辑，HTTP Parser 回调、路由和 WS 消息事件可能仍处在这条调用链中。发送队列先解锁再执行 provider / 完成通知，只说明它们不持有**该发送队列的状态锁**；若发送由接收回调发起，外层接收锁仍可能存在。见 [TriggerReceived](Net.CrossSocket.Base.pas#L1507) 与 [HTTP 解析入口注释](Net.CrossHttpServer.pas#L3172)。

- HTTP 响应队列、WS Sender 与 OpenSSL 的状态锁保护接纳、顺序和终结；业务取数、通知及关闭工作按各层实现移到该状态锁外。
- 允许的同线程 Close / Send 重入已有回归；这不意味着任意跨线程互等安全。尤其不要持有业务锁等待一个可能反向请求该锁的接收或发送回调。
- 接收回调拿到的原始字节只在约定的回调范围有效。需要跨线程、延后处理时，由调用方复制数据或保留接口明确拥有的数据对象。

## 流和缓冲由谁持有

| 数据入口 | 调用方责任与实现边界 |
| --- | --- |
| `SendBuf` / 裸指针 | 底层只得到地址；数据必须保持有效且不变直到对应发送完成。不能从方法已返回推断内存可释放 |
| 基类 `SendBytes` | 实现保留 `TBytes` 引用直到完成，但不等于内容快照；共享数组在发送期间不得改写。见 [SendBytes](Net.CrossSocket.Base.pas#L2012) |
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

## Session 的显式约束

实现位于 `Net.CrossHttpSessions`；原 `Net.CrossHttpParams` 保留类型别名，旧 uses 路径继续可用。声明归属单元及限定 RTTI 名称已变化，包和预编译单元必须完整重编译；别名不承诺二进制兼容。

`GetSession` / `Sessions[ID]` 与 `ExistsSession` 内部取得写锁，原子完成过期检查、移除和续期；不能包在调用方的读锁内。Add、Remove、Clear、Count、索引及枚举沿用调用方显式加锁约定，`Session.Values` 没有因此获得独立的并发保证。

清理的 `BeforeClearExpiredSessions`、`OnCheckExpiredSession`、`AfterClearExpiredSessions` 在会话写锁内执行；从 `GetSession` 路径调用的 ID 生成器和会话构造同样在写锁内。它们不属于发送层的“锁外业务回调”，不得等待需要同一锁的其他线程，也不得在清理线程中销毁自身 Session 容器。

`TSessionBase.FOwner` 是原始容器指针，`Owner` getter 才把它转为接口。**持有 `ISession` 不会保活容器，Owner 也不是会自动清空的安全弱引用。** 调用方访问 Owner 时必须保持对应 `ISessions` 存活；不能在容器销毁后再从会话取得 Owner。见 [FOwner 声明](Net.CrossHttpSessions.pas#L99) 与 [GetOwner](Net.CrossHttpSessions.pas#L464)。

外部销毁容器时先撤销调用方持有的会话锁；析构发停止信号，在不持有会话锁时等待清理线程真正退出，然后释放字典。清理钩子异常没有“下一轮自动重试”的保证。完整约定及验证见 [Session 测试](Tests/FPC/HttpSessionTests/README.md) 和 [批量清理测试](Tests/FPC/BatchCleanupTests/README.md)。

## EasyThread / EasyTimer

- `Terminate` 是协作终止，不会中断正在执行的用户代码。外部 `WaitFor` / 析构等待任务实际结束；不要在持有任务所需锁时等待。
- EasyThread 的外部等待串行完成一次原生 join，`Finished` 不能替代首次 join。工作线程自身 WaitFor 直接返回；自身析构把底层线程释放交给 `FreeOnTerminate`，不等待自己。见 [WaitFor](../Utils/Utils.EasyThread.pas#L152) 和 [生命周期测试](../Utils/Tests/FPC/EasyThreadTests/README.md)。
- EasyTimer 的工作回调保活独立状态，允许回调内释放 Timer；析构发出停止信号，回调返回后结束。Timer 捕获回调异常后继续后续周期，日志异常不阻断清理；这不同于一次性任务和 Session 清理线程。回调运行在 Timer 状态锁外，但调用方自己的锁仍由调用方负责。
- Timer 的暂停不取消已经接纳的回调；空闲/暂停时视为健康，正在运行的回调可通过超时检查识别卡顿，Finished 后保留最后心跳。见 [Timer 实现](../Utils/Utils.EasyTimer.pas#L125) 与 [测试说明](../Utils/Tests/FPC/EasyTimerTests/README.md)。

上述自毁支持不能推广到 Session 容器、任意 TThread 或其他具有后台回调的对象。

## 验证范围

本文件整理既有行为，没有新增运行结果。平台事件异常与收尾见 [SocketCallbackTests](Tests/FPC/SocketCallbackTests/README.md)，HTTP 数据与连接寿命见 [HttpRequestLifetimeTests](Tests/FPC/HttpRequestLifetimeTests/README.md)，OpenSSL 的有序输出、终态、有效前缀和缓冲寿命见 [TlsIoTests](Tests/FPC/TlsIoTests/README.md)。各套件明确区分组件夹具、真实 TCP、原生 TLS、实际运行、仅编译和未覆盖平台，不能把其中一种证据扩大为全部场景保证。

容量配置及其超限策略以各层专项说明为准；后续改变所有权、回调时机或锁边界时，应同步更新本约定及对应回归。

WS 两端具体连接的 `SetWebSocketSendQueueLimits` 使用 `TWsSendQueueLimits`，默认四项为 0，不改变既有接口。计数包含构帧、排队及在途项；字节仅覆盖本层编码后帧（含头部/掩码），不覆盖 provider 源缓冲或下层队列。完整数据消息入队前超限以一次 False 拒绝，健康连接仍可使用；已接纳 provider 的帧超限、控制帧或 Close 预算不足则关闭。额度在结算时先归还再通知，在途内存仍保留到物理完成；配置只允许空闲且未关闭时修改。边界及实际矩阵见 [WS 容量专项](Tests/FPC/WebSocketCapacityTests/README.md)。
