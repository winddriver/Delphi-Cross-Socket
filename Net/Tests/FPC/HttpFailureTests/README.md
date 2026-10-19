# HTTP 失败终态回归

对应 `docs/plans/2026-10-19-project-improvements.md` 的 F03 / A03。
覆盖失败请求不进入业务、错误后的尾部数据不能成为下一请求、错误响应按序发送，以及真实 TCP 连接最终关闭。

## 构建与运行

沿用相邻 `HttpRequestLifetimeTests`、`HttpHeadTests` 的 Delphi / Lazarus 构建约定，工具路径在 `run_tests.py` 中指定。

仓库根目录：

```powershell
python Net/Tests/FPC/HttpFailureTests/run_tests.py --targets win64 fpc64
```

`--cases` 选择场景，`--label` 区分验证轮次，`--build-only` 只构建，`--no-build` 只运行。
产物、日志、实际生产单元及测试源码 SHA-256 位于忽略的 `bin/<label>/<target>/`；编译单元输出到 `lib/`。

LPR 使用跨平台 Socket 类型。已有其他平台可执行文件时，可以直接运行 `HttpFailureTests parser length`、`HttpFailureTests memory split` 等组件场景，再独立执行网络验证：

```sh
python3 run_network.py /absolute/path/HttpFailureTests
```

## 测试边界

- **解析器组件**：使用真实 `TCrossHttpParser`；回调从输入头部提供字段值。无效 Content-Length、CL/TE 冲突、非法 chunk size、header bare-LF 首次失败后，再次 Decode 和 Finish 不得报告成功或重复失败；后续输入必须消费/丢弃。额外验证成功回调主动 Abort 不会使正常解析器永久失败。
- **回调失败状态**：Header、BodyData、关闭定界响应的 BodyEnd 回调调用具体 Parser 的 Fail 后吞掉 EAbort，以及 Header 回调内重入 Decode 并触发错误。回调返回后失败状态不得被外层解析覆盖；失败通知仍只有一次。
- **服务器组件**：使用真实 HTTP 解析、请求对象和响应队列，只替换 `DirectSend`。默认将完成回调保留到显式执行，以测试错误响应尚未完成时再 Feed。覆盖同包尾部、分包尾部、前序合法响应暂未就绪、Server 直接拒绝头部、Server 的 413 二次检查，以及同步写回调。
- **真实网络**：Python 通过 TCP 发送原始请求，读完响应头和完整正文后，再调用 recv 验证 EOF/复位；不能仅凭 `Connection: close` 判断已断开。分包场景在读完错误响应后继续发送正常请求，最终业务计数必须为 0。正常场景在同一连接验证 GET、HEAD、pipeline 和后续 keep-alive 请求。

组件连接使用 `INVALID_SOCKET`，记录关闭/断开请求，并在测试结束时显式进入 `InternalClose` 清理；不会把它的公开 Close 跳过 socket 清理当成生产问题。实际关闭由网络场景验收。

前序排队场景先提交合法 R1、保留其响应而不调用 Send，再提交非法 R2 和尾部 R3：R1 就绪前没有输出；R1 就绪后先完成 R1 正文，再发送 R2 错误响应并断开；业务仅处理 R1。

413 用例在创建连接之后调低 `Server.MaxPostDataSize`，使 Parser 保留较大的旧上限，确保进入 Server 的二次检查分支。

本批非法 CRLF 用例针对当前已拒绝的 header bare-LF，不扩展为 F20 的 chunk CRLF 顺序/trailer 修复。

每个组件场景在独立子进程运行，15 秒超时后终止并等待回收。网络服务启动、socket 读取和退出都有超时，finally 中停止或终止服务，并回收读取输出的线程；只监听 127.0.0.1 临时端口。

## 原版基线

原生产 Parser/Server 与当时测试源码保存在忽略的 `bin/baseline-sources/`；两套基线可执行文件、哈希和结果在 `bin/baseline/win64/`、`bin/baseline/fpc64/`。

2026-10-19，Delphi Win64 / FPC Win64 的最初 16 个场景均为 **13 项失败、3 项通过**：

- Parser 四种错误在下一次 Decode 时错误报告成功。
- 延迟回调下分包尾部触发错误请求进入业务；前序响应未就绪场景也发生错误发布。
- Server 的 413 二次检查没有终止正常请求发布。
- 同包错误响应完成后未请求断开；真实 TCP 的无效长度、CL/TE 冲突、非法 chunk size 和同包尾部在收到完整 400 后等待关闭超时。
- 真实分包尾部场景业务计数为 2，且继续输出响应。
- 原版通过项是 `memory-header`、`tcp-crlf` 和正常 `tcp-normal`，这些用作相邻回归。

随后增加 `parser-abort`、`parser-callback`（失败通知自身抛异常仍只通知一次）与 `memory-sync`，首轮套件为 19 项。基线 16 项结果不冒称已经覆盖这三个新增场景；修复后结果以对应轮次 `results.json` 为准。

## 修复后 Windows 验证

2026-10-19，按修复后的 Parser/Server 全量重新构建：Delphi Win64、Delphi Win32、FPC Win64 均为 **19/19 通过，共 57/57**。真实错误请求业务计数全部为 0；正常复用/HEAD/pipeline 场景业务计数为 4。

`tcp-split` 在收到完整 400 后继续发送数据，Windows 可能以 `ConnectionResetError` 或 `ConnectionAbortedError` 报告连接已终止；两者均作为实际关闭证据，socket 超时仍判失败。该处理不替代业务计数和完整错误响应检查。

本记录不代表 Linux/macOS 运行结果；跨平台验证需要使用相应编译器和实际后端单独执行。没有吞吐或长时间压力测试。

## 首轮修复后的补充红基线

独立复核后再加入 `reject-header`、`reject-bodydata`、`reject-bodyend`、`reject-reentry`，套件增至 23 项。这四项使用首轮修复新增的具体类 Fail API，不要求在尚无该 API 的原版源码上编译。

Delphi Win64 / FPC Win64 在首轮修复、尚未增加回调返回状态检查的版本上，四项全部失败：回调返回后覆盖了失败状态并报告成功。生产 Parser 快照、可执行文件及日志保存在忽略的 `bin/before-callback-guards/`。最终 23 项结果以完成状态保护后的重新构建记录为准。

回调状态保护完成后，使用最终 Parser/Server 全量重编并运行：Delphi Win64、Delphi Win32、FPC Win64 均为 **23/23 通过，共 69/69**。最终 Windows 日志和哈希在 `bin/final/<target>/`，首轮 19 项绿色结果保留在 `bin/current/<target>/`，没有覆盖两阶段红基线。

## Linux 构建与运行

`build_linux.py` 沿用相邻 SocketCloseOnExecTests/OpenSslLoadTests 的已有交叉工具链、lazutils 和 Ubuntu SDK，不安装或修改工具链。Windows 上在本目录执行：

```powershell
python -B build_linux.py fpc-linux64 delphi-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpFailureTests -- python3 -B run_linux.py bin/fpc-linux64/HttpFailureTests bin/delphi-linux64/HttpFailureTests
```

其他机器按本地路径调整脚本常量及工作目录。也可直接在已有 Linux 主机进入本目录后执行 `python3 -B run_linux.py <可执行文件绝对路径>`。运行入口复用 Windows 的同一场景清单和 TCP 检查，不将交叉编译成功当作运行通过。

2026-10-19，Delphi 13.1 Linux64、FPC 3.3.1 Linux64 在已有 WSL Ubuntu 22.04 中各 **23/23 通过**，包含实际 Epoll 后端的 7 个 TCP 场景。加上三个 Windows 目标，本专项共 **115/115 通过**。每个 Linux 目标的 `bin/<target>/source.json` 保存生产/测试源码哈希，`linux-results.json` 保存可执行文件哈希及逐项结果。

## 相关回归与正式构建

- 当前 Parser/Server 下重新构建，Delphi/FPC Win64 的 HttpHeadTests 各 14/14，HttpRequestLifetimeTests 各 6/6 通过。
- 同两目标的既有 WebSocket 组件、11,056 合法帧组合及 11 个真实回环场景全部通过。
- 正式 WebSocketServer 和 HttpClient 的 Release/Win64 工程构建通过；日志位于 `bin/f03-formal-win64/`，构建生成的示例资源副作用已清理。
- 源文件保持 UTF-8 BOM/CRLF；修改检查使用 `git -c core.whitespace=cr-at-eol diff --check`。仍有既有依赖/字符串转换等警告，未改第三方源码；未进行 macOS/Kqueue 运行、吞吐或长期压力测试。

## A04 / F06、F11 响应队列回归

`HttpResponseQueueTests.inc` 复用上述 `TMemoryConnection` / `TTestServer`，新增 `queue-*` 用例，不另建重复测试工程。它仍使用真实解析器、请求/响应对象和队列，只控制物理写的完成时机。

```powershell
python Net/Tests/FPC/HttpFailureTests/run_tests.py --label queue-current --targets win64 fpc64 --cases `
  queue-late queue-late-nocompress queue-late-release queue-callback queue-request-end `
  queue-cancel-callback queue-active-close queue-source-error
```

- `late` / `late-nocompress`：保存尚未发送的响应，经真实 InternalClose 后首次发送，无异常且一次 False。
- `late-release`：进一步释放外部连接引用并确认连接已经析构，保存的响应仍应安全拒绝发送。
- `callback` / `request-end`：R1 的完成回调或请求结束通知抛异常，R2 仍按序完成；两条完成通知各一次，不把已完成的成功回调改判成第二次 False。
- `cancel-callback`：R1 尚未 ready，因此 R2/R3 只是排队、没有在途物理写。关闭取消时首个 False 通知抛异常，后面的通知仍各一次。
- `active-close`：HTTP 头已完成，真实 TMemoryStream 的正文指针已交给延迟物理写；Close 不能提前调用负责释放流的完成通知。物理完成前流未析构、字节仍有效；迟到的物理 True 应以取消 False 结算一次，不再启动后续写。
- `source-error`：chunk source 第一次返回真实载荷，第二次读取抛异常；响应必须 False 结算并请求关闭，不能永久挂在发送状态。

2026-10-19 修复前基线：Delphi Win64、FPC Win64 各 **0/8**。首 5 项在 `bin/queue-baseline/<target>/`，后 3 项在 `bin/queue-extra-baseline/<target>/`，均从当时尚未修改的 `Net.CrossHttpServer.pas` 重新构建；Server 快照在 `bin/queue-baseline/Net.CrossHttpServer.pas`。

具体失败：三种迟发调用均抛异常；R1 两种回调异常均阻断 R2；排队取消的首个异常阻断后续 False；在途流没有提前释放，但迟到物理完成被错误报告为成功；source 第二次读取异常后没有完成通知。每目标 `source.json` 包含生产源码、主测试及新增 include 的哈希。这些是待修复的红色验收，不是新实现通过结果。

### A04 修复后增量及最终验证

在上述 8 项转绿后，补充 6 项边界：

- `queue-reentry-send`：R1 完成回调使 R2 ready，但 R2 不能越过仍在执行的 R1 完成通知。
- `queue-reentry-close` / `queue-request-end-close`：完成回调或请求结束通知主动关闭，R2 仅取消一次，不能开始发送。
- `queue-duplicate-physical`：同一个物理完成回调被重复执行，不得推进或完成两次。
- `queue-ready-close-race`：64 轮用同一个事件同时释放发送线程和关闭线程，随后处理实际保留的物理完成；每轮通知一次 False、Pending 归零、连接析构一次。
- `queue-logger`：业务完成通知和日志处理器都抛异常，下一响应仍然完成。生产代码复用 A04 平台部分的 `_LogException`，不会让日志异常打断清理。

2026-10-19，最终套件为 **37 项**（原 23 项＋队列 14 项）。从当前工作区完整重编并运行：Delphi Win64、Delphi Win32、FPC Win64、Delphi Linux64、FPC Linux64 均 **37/37**，共 **185/185**。三个 Windows 最终结果在 `bin/a04-final/<target>/`；两 Linux 最终结果在 `bin/{delphi-linux64,fpc-linux64}/linux-results.json`。元数据同时记录 HTTP 生产单元、所依赖的平台/基类及新增 include 的 SHA-256，最终比对与冻结源码一致。

自检又给 `active-close` 加入“物理完成后仍为 Closed”断言，在 `bin/queue-before-closed-guard/` 两目标得到红色结果：旧 Disconnect 先写入 Disconnected 再判断旧状态，造成闭态回退。HTTP 侧补通知后的关闭状态检查，A04 平台部分使用 CAS 阻止 Closed 回退。上述最终 185/185 是两层保护均完成后的重新构建结果；此前 `bin/queue-final-logger/` 仅保留为中间记录。

生产边界：关闭与 ready 接纳在同一队列锁内决定；Response 复用该锁取得连接强引用，关闭后解绑；尚未开始项取消并在锁外通知，活跃项的 source/清理回调保留至物理完成。完成通知异常仅记录，不再次失败已完成请求；通知结束后再决定启动下一项。此轮没有更换 FIFO 容器，没有重构 HTTP 定界，也不宣称覆盖当前解析对象与关闭之间的全部并发情形。公开接口签名保持不变；类的私有布局已变化，使用方须完整重编译。

Linux 启动最初在沙箱内得到 WSL `E_ACCESSDENIED`，经允许的沙箱外调用后完成实测；已有 `/etc/wsl.conf` 的 `network.ipv6` 警告未修改，未影响结果。以上为当前未提交的 A04 HTTP 与平台改动组合验证，不能称为某个旧提交的独立运行结果。

平台最终补齐早期 Connect 失败通知抛异常时的 socket 收尾后，再次全量构建并运行，五目标仍为 **185/185**。Windows 最新日志在 `bin/a04-final-cleanup/<target>/`，Linux 保留上述目标目录；全部生产/测试哈希已与提交前源码核对。当前 Client 的临时响应修复及 Session 独立改动未计入本专项完成数量。

## A07 / F09 无正文响应

`HttpBodyPolicyTests.inc` 继续复用内存物理写与真实 HTTP 对象，覆盖状态发送、字节、流、provider、显式 gzip 和自动压缩。统一检验 HEAD、1xx、204、205、304、成功 CONNECT 的正文抑制，以及后续响应和完成通知；组件里的 CONNECT 仅验证响应定界，不表示新增隧道功能。公开发送方法签名保持不变。

协议依据为 [RFC 9110 §8.6](https://www.rfc-editor.org/rfc/rfc9110.html#section-8.6)、[§15.3.6](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.3.6) 与 [RFC 9112 §6.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3)。正文不能发送时，provider 不预取、流不读取、zlib 不初始化。HEAD 保留已知表示长度；304 或未知长度 HEAD 仅保留业务提供的合法、一致长度。1xx/204/成功 CONNECT 移除 CL/TE，205 使用 CL=0。HEAD/304 的 TE 元数据在协议上允许省略，本实现选择省略，测试不把原 HEAD 自动压缩的 TE 误报成协议违规。

原版 Delphi/FPC Win64 首批各 **7/37 通过、30 项失败**，记录在 `bin/f09-protocol-baseline/`；Server 原始快照保留在 `bin/f09-baseline/Net.CrossHttpServer.pas.snapshot`。HEAD 状态/字节/流/自动压缩及三个正常 200 场景原本通过，不作为缺陷复现。

随后补充长度冲突、非法长度、HEAD 与 204/304 组合、ctNone 流和真实 TCP 场景。`tcp-body` 在同一个连接上连续请求 204、304、HEAD gzip、205 与普通 200，检查无残留字节并在最后请求后真正关闭。独立复核再发现 HEAD 转换为 gzip 时保留旧 CL 的问题：`body-head-{auto,gzip,gzip-stream}-length` 在首轮修复的双目标均失败，邻近的预编码场景通过；快照/日志在 `bin/f09-before-encoded-length/`。最终修复在本次改变表示编码时清掉旧长度，不影响预编码表示。

当前完整套件共 **85 项**（此前 37 项、47 个正文组件场景、1 个新增真实 TCP 场景）。Windows 三目标最新日志在 `bin/f09-final-length/<target>/`，Linux 两目标仍在各自 `bin/<target>/`。生产 Parser/Server、平台依赖和两个 include 的哈希由构建脚本记录；这是共享工作区的组合构建，不将并行 TLS 分工的中间版本算作已完成 TLS 修复。Windows 两目标的既有 WebSocket 组件、11,056 合法帧组合及各 11 个回环场景也通过，含 101 升级。

最终 Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64 各 **85/85，共 425/425 通过**。提交前已核对本批 Server、测试主文件和两个 include 的哈希；Linux 可执行文件哈希也与运行记录一致。未执行 macOS、TLS 下的正文矩阵或性能测试。

## A07 / F20 trailer 的 TCP 集成

新增 `tcp-trailer`、`tcp-trailer-gzip` 和 `tcp-trailer-bad`。前两项在真实 TCP 上发送带 trailer 的明文/压缩分块请求，再在同一连接发送下一请求：业务端验证完整正文 `abc`，认证、Cookie、长度和传输编码等原始头不被 trailer 覆盖，随后响应没有残留字节。非法折行 trailer 必须得到完整 400 后关闭，同包尾部请求不进入业务。

最终五目标完整重编并实际运行，各 **88/88，共 440/440**；Windows 日志为 `bin/f20-integration/<target>/`，Linux 为各目标目录。Parser 组件的严格 CRLF、大小/字段上限、全部拆包位置及原生解压资源验证详见相邻 HttpChunkTests；没有把其拆包次数当作额外 TCP 场景。

## S02 服务端发送策略与状态归属

| 决定 | 唯一归属及使用者 |
| --- | --- |
| 入站消息定界、成功/失败 | Parser；Header 的原始值只是输入，失败状态不能被业务回调恢复为成功 |
| 请求是否允许复用 | 请求解析时读取所有 Connection 字段的 token；close 优先，HTTP/1.0 需要显式 keep-alive |
| 状态行、正文规则与输出头 | Send 接纳前生成头部，正文规则在组合 source 创建时固定；排队后不再读取可变的响应状态/头部生成另一版报文 |
| 正常响应发送后是否关闭 | 头部生成时确定 KeepAlive，队列保存该值；响应头和完成路径消费同一决定 |
| 发送结果 | 物理写、正文读取或编码是否成功；完整发送的 HTTP 500 同样是发送成功，状态码不再充当内部错误标记 |
| 关闭与迟到通知 | 响应队列的 Completed/Closed/active item；未开始项取消，在途缓冲保留到物理完成，结果至多通知一次 |

连接规则依据 [RFC 9112 §9.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.3) 和 [RFC 9110 §7.6.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-7.6.1)。保持本库原有错误响应默认声明 close 的策略，并使 4xx 也真正关闭；请求 close、响应 close 或重复字段中的 close 都不能被手工 keep-alive 覆盖。正常 Upgrade 字段保留，不以重写整个 Connection 字段破坏 101 握手。

响应状态、Header 和 Cookie 应在 Send 前配置；发送接纳后对这些对象的修改不改变已经固定的报文。首次 header 字节由原 source 闭包保活，没有复制整份头部，也没有因冻结而提前读取下一块正文。流和 provider 仍按现有所有权契约存活到完成通知，不能并发修改借用的缓冲。

首次 provider 取数、后续 source、普通流和 gzip 流共用失败收尾。已声明还有数据的流若返回 0/负数会失败并关闭；合法正数短读继续推进。压缩失败通过 source 异常传递，不再把队列状态码改成 500。失败不越过队首响应，回调与 RequestEnd 结果一致，不能继续发送下一响应。

红色证据：`bin/s02-red-final/` 以 `bin/s02-before/production/` 的原 Server 快照重编，两个 Windows 目标均复现响应头/实际关闭不一致、Connection 列表/重复字段、排队后状态变化、500 结果和首次 provider 异常；正常控制用例未算作缺陷。后补流 EOF 的 `bin/s02-eof-before/` 在双目标各 2 失败、2 个合法短读通过，单独保留该阶段边界。

最终新增 15 个策略组件、8 个 source/流组件和 6 个真实 TCP 场景，完整套件 **117 项**。Windows Delphi64/32/FPC64 和 Linux Delphi/FPC 各 **117/117，共 585/585**。Windows 为 `bin/s02-stream-final/`，Linux 为各目标目录。TCP 独立读取完整 404/500/显式 close 响应后等待真实 EOF，同时验证 HTTP/1.0 keep-alive 和列表 close；组件通过延迟完成覆盖队列取消及排队后修改。此处只完成 S02 服务端阶段，客户端头部解析结果传播另批核查。

重新构建红基线可传 `run_tests.py --source-root bin/s02-before/production --label <新标签>`，脚本优先搜索该目录并记录实际选用的 Server 源码；不切换或覆盖工作区生产文件。

## O03b 原始正文阈值落盘与总量限制

在启动监听前配置具体类，不改变 `ICrossHttpServer` 的方法顺序或 GUID：

```pascal
ServerObject.BodyMemoryThreshold := 128 * 1024;
ServerObject.BodyTempPath := 'private-body-temp';
ServerObject.MaxPostDataSize := 64 * 1024 * 1024;
```

`BodyMemoryThreshold` 默认 0，保持原有内存正文。启用后仅 `btBinary` 超过阈值时迁移到临时文件，`RawBody`/`Body` 应按 `TStream` 使用，业务仍在完整请求到达后读取，起始位置为 0。URL 编码表单仍整体解码；multipart 沿用已有文件存储。总正文上限约束解压后的字节数，不因落盘而取消。

`BodyTempPath` 独立于 multipart 的 `StoragePath`；空值沿用现有临时文件工具的程序目录下 `temp`。POSIX 新建临时文件使用 0600，Windows 沿用目录 ACL。临时正文始终自动删除，不受上传文件的 `AutoDeleteFiles` 控制，但要等最后一个请求引用释放：连接也缓存最近一次完整请求，因此仅清空业务变量不保证立即删除。断开/失败的未完成请求随清理删除，已发布请求可由业务继续持有和读取。

发布业务前显式刷新文件流缓存，尾部写入失败返回 500、关闭并阻止业务执行。该刷新确认用户态缓存交给文件写入，不是断电持久化或 `fsync` 保证。原 Parser 的 Integer 接口保持，具体类 `MaxBodyDataSize64` 与其共享 Int64 实际限额；服务器大正文上限不再窄化回绕，头部限额安全夹取至 Integer 范围。

新增 14 个存储场景和 3 个真实文件写入失败场景，完整 HTTP 套件为 134 项。存储场景覆盖默认/阈值两侧、chunked、gzip、表单兼容、目录失败、独立目录、断开、保留请求引用、解码总量和超过 32 位的限额。文件失败使用 Windows 字节锁和 Linux 子进程 `RLIMIT_FSIZE`，验证普通/chunked/gzip 尾部失败不进入业务，文件和句柄最终回收。它们使用真实解析器和 OS 文件操作，物理网络完成由夹具控制，不能当作新增 TCP 上传测试。

红基线分别保留在 `bin/o03-storage-before/`（无阈值功能）和 `bin/o03-flush-before/`（未显式刷新）。后者双 Windows 目标均在三个场景错误发布业务；补充刷新后转绿。最终接口兼容版本保存在 `bin/o03-body-compatible/`，Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64 各 134/134，共 670/670；其中既有 17 个 TCP 场景按原默认配置回归。源码/程序哈希、逐例结果均保存在各目标目录。

`run_storage_memory.py` 使用同一程序接收 32 MiB 原始正文，对比默认内存与 128 KiB 阈值，预热后交替三轮，读取全量字节并验证清理。各目标峰值驻留内存增量中位数（字节）：

| 目标 | 默认内存 | 阈值落盘 |
| --- | ---: | ---: |
| Delphi Win64 | 34,353,152 | 716,800 |
| FPC Win64 | 59,580,416 | 659,456 |
| Delphi Linux64 | 34,074,624 | 520,192 |
| FPC Linux64 | 34,377,728 | 557,056 |

这是进程峰值增量，包含运行时分配差异，不是正文对象精确大小或吞吐比较。Linux 为避开 WSL 挂载盘不呈现 POSIX 权限的差异，将同一程序字节复制到原生临时目录运行，落盘文件均验证为 0600。测量记录为各目标的 `memory.json`。

```powershell
python -B run_tests.py --targets win64 win32 fpc64 --label o03-body-compatible
python -B build_linux.py --label o03-body-compatible fpc-linux64 delphi-linux64
python -B run_storage_memory.py bin/o03-body-compatible/win64/HttpFailureTests.exe --report bin/o03-body-compatible/win64/memory.json
```

Linux 运行仍使用 `run_linux.py`，传入带标签的两个目标路径；内存测量在 Linux 内使用相同 Python 入口。

## O03a HTTP 请求排队容量

启动监听前设置具体类 `ServerObject.MaxPendingRequests := 128`，每个新连接保存独立快照；默认 0 保持不限量，负数会同步拒绝。既有接口声明/GUID 不变。计数包含已经开始解析的请求、等待业务响应的请求、ready 响应和在途响应，不只看排队容器长度。

在创建新请求和正文前检查容量，达到上限仍可完成已接纳的请求；再来一个请求则把 Parser 终结并关闭连接。不会用前一个请求的 Response 发送 503，也不会越过未完成响应插队发错误报文。未开始响应取消并归还计数；在途缓冲保留到物理完成，迟到成功按取消失败结算一次。正常完成后可再次利用空出的名额。此限额约束单连接请求数量，不是所有未知 provider 的字节预算，需与正文上限/落盘和各发送层的容量组合使用。

新增 7 个组件场景：默认行为、恰好上限、超限、正在发送时超限、完成后复用、解析中正文计数，以及关闭后再输入。TCP 场景保持首响应未 ready，连续发送四个请求，验证第三个到来就关闭、前两个进入业务，后两个没有发布，且没有响应插队。

红基线 `bin/o03-capacity-before/` 的 Delphi/FPC Win64 各 3/8 通过、5/8 失败，其中也复现了关闭后的 Decode 仍增加 Pending。修复后 `bin/o03-http-capacity/` 五目标完整套件各 142/142，共 710/710；Windows/Linux 使用真实 IOCP/Epoll 运行 TCP 场景，组件只控制物理完成时机。`HttpQueueLimitTests.inc` 的哈希纳入构建记录。期间其他模块的容量改动仍独立验证，不将这组 HTTP 结果当成 TLS/Socket 新限额的验证。

随后补充 `tcp-storage`，套件清单增至 143 项。这一增量独立重编五目标并各运行一次，共 5/5，产物为 `bin/o03-body-tcp-final/`；此前 142 项结果仍保留，不把本次增量写成又跑了一遍 715 项。客户端通过真实 TCP 分 16 段上传 64 KiB，服务器阈值为 1 KiB，业务确认正文确为文件流、位置为 0 并逐字节验证全部内容；客户端收到完整响应及 EOF，服务端停止并释放连接后确认临时目录为空且可删除。Linux 可用 `run_network.py <程序路径> --cases storage` 复现。
