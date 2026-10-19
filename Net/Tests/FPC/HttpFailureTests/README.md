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
