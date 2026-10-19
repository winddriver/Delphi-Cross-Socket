# 客户端容量与关闭接纳回归

对应 O03a 的 HTTP Client 部分。当前生产范围为 `Net.CrossHttpClient.pas` 和 IOCP/Epoll/Kqueue 的 Connect 关闭/失败结算边界；Base 只增加条件测试门控，正常构建不含该入口。基础 Socket 的发送数量/字节限额是后续独立步骤，本目录当前结果不代表那部分已完成。

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

最终 Client SHA-256：`9032c29100453e197ce133df0c869bac2444e6709bd39cb37cf14b1e0b91bc64`。IOCP/Epoll/Kqueue 分别为：

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
