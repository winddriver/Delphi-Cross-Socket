# HEAD 请求与参数删除回归

验证 `TBaseParams.Remove(AName)` 删除所有同名项，以及真实客户端发出的 HEAD 请求没有正文定界头和正文。测试工程显式引用仓库源码，构建方式沿用相邻 `HttpRequestLifetimeTests`。

`run_tests.py` 使用 Python 标准库在 `127.0.0.1` 临时端口启动 HTTP/1.1 服务端，检查实际请求头、正文、请求次数与连接复用，不访问外网。HEAD 响应携带 `Content-Length: 2` 但不发送正文，后续 GET 返回两字节 `ok`。客户端检查响应长度与回调次数。

覆盖 14 组：按名称删除重复参数；HEAD 的字节正文、内存流、chunk provider、空正文、调用方与初始化回调的重复 CL/TE、gzip 非空及空正文、deflate 空正文；空 POST/PUT/PATCH、POST 普通及分块正文。每组网络用例同时检查后续 GET 复用同一连接。

原 HEAD 专项不覆盖 HTTPS、断网或压力场景；后续 Linux 和临时响应验证见文末。

## 构建与运行

在本目录运行，沿用本机已有依赖和搜索路径，不修改全局 FPC/Lazarus 配置。

```powershell
New-Item -ItemType Directory -Force -Path bin/delphi-win64,lib/delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B `
  '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;..\..\..\..\Utils;D:\Design\Delphi\D13.1\lib\win64\release' `
  '-I..\..\..\..;..\..\..' '-Ebin\delphi-win64' '-N0lib\delphi-win64' `
  HttpHeadTests.dpr
python run_tests.py bin/delphi-win64/HttpHeadTests.exe

& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all --skip-dependencies HttpHeadTests.lpi
python run_tests.py bin/x86_64-win64/HttpHeadTests.exe
```

仅所有用例通过时返回退出码 0；构建输出使用忽略的 `bin/`、`lib/`。

## 2026-10-08 验证结果

- 原实现：Delphi 6/14 通过，8 项失败，复现重复参数残留和 HEAD 请求定界错误。
- 修复后：Delphi 13.1 Win64、FPC 3.3.1 Win64 均全量编译成功，分别 14/14 通过。
- 两套编译器的既有 `HttpRequestLifetimeTests` 各 6/6 通过；Delphi `HttpClient.dproj` Release/Win64 构建成功。
- FPC 存在字符串转换和已有依赖/配置警告，未修改全局工具链配置；不声称零警告。
- 构建和运行日志保存在 `bin/delphi-*.log`、`bin/fpc-*.log`；修改前日志为 `bin/delphi-red-*.log`。

## F08 临时响应回归（2026-10-19）

`run_interim_tests.py` 复用同一个客户端程序，以本地真实 TCP 服务发送 100、102、103 和最终 200。覆盖单个/多个临时响应、逐字节写出、HEAD、发送 POST 正文期间收到 100、最终 gzip 正文以及调用方提供的响应流。每组检查只收到最终响应、临时头不残留、两个请求共两次回调，且后续 GET 仍复用同一条连接。借用流额外检查内容及未被客户端析构。

```powershell
python -B run_interim_tests.py bin/delphi-win64/HttpHeadTests.exe --report bin/f08-delphi-result.json
python -B run_interim_tests.py bin/x86_64-win64/HttpHeadTests.exe --report bin/f08-fpc-result.json
```

原客户端代码使用 Delphi Win64 重新构建，首批 **0/7** 通过，表现为把 100/103 发布为最终响应；基线源码、可执行文件、日志和哈希保存在 `bin/f08-baseline/`。借用流是后续第 8 项，未冒称包含于这 7 项红基线。

修复后 Delphi/FPC Win64、Delphi/FPC Linux64 各 **8/8，共 32/32**。同四目标原有 HEAD 套件各 **14/14**。Linux 使用已有 Ubuntu 22.04 WSL，运行 `python3 -B run_interim_tests.py bin/<target>/HttpHeadTests --report bin/<target>/interim-results.json`；产物目录为 `bin/{delphi-linux64,fpc-linux64}/`。交叉构建使用已有 `dcclinux64`/`ppcrossx64` 和 Ubuntu SDK，搜索路径与相邻 `HttpFailureTests/build_linux.py` 一致，仅替换工程名及本工程输出目录；FPC/POSIX 入口加入 `cthreads`。

生产修复只在解析完成时丢弃非 101 的临时响应对象，保留请求、回调和连接占用。101 继续走原有协议升级路径；现有 WebSocket 套件重新构建后，Delphi/FPC Win64 的组件、11,056 合法帧组合和各 11 个真实回环场景全部通过，包含客户端协议升级。逐字节发送不能保证操作系统按相同粒度交付，因此不称为穷举所有拆包；临时响应专项未运行 HTTPS、macOS 或压力测试。

F10 串联 gzip 补充后新增第 9 项 `hints-gzip-members`：真实 TCP 先返回 103，再将 `o`、`k` 分别压缩为两个连续 gzip 成员作为同一个最终正文，客户端必须收到完整两字节并复用连接。Delphi/FPC Win64 按新 Parser 重编后各 **9/9**，记录为 `bin/f10-members-*-result.json`；这不改写此前四目标 8/8 的历史结果。

## S02 客户端解析与复用决定

`HttpClientResponseTests.inc` 与 `run_response_tests.py` 继续使用真实客户端和 TCP 服务。22 项包含版本/状态码/状态行分隔、非法及溢出 CL、CL/TE 冲突、不支持的传输编码、重复 Connection 和 token 列表、HTTP/1.0 默认关闭及显式保活、请求 close、关闭定界的扩展 token、合法空原因文本/空字段 204/HEAD 表示元数据，以及畸形报文后同包追加合法响应。每项发送后续请求，检查回调两次、正文和连接数量；声明 close 的定长响应故意不由服务端主动关连接，避免掩盖客户端错误复用。

状态归属与相邻 HttpFailureTests 的服务端表一致：

- Response 负责状态行及头部字段解码，失败必须交给 Parser.Fail；不会再以状态 0 或部分解码结果继续成功路径。
- Parser 统一负责 CL/TE 有效性和消息定界。有体响应没有 CL/TE 时，始终读到 EOF；Connection 中的扩展 token 不能把正文变成空正文。无正文响应保留表示元数据例外，不为 HEAD 解码实际不会传输的编码。
- 完成层使用请求 close、已解析的响应保活决定、客户端复用配置和实际闭态决定能否进入空闲池。HTTP/1.0 需显式 keep-alive，所有同名字段中的 close 优先；101 仍由升级协议接管。

规则依据 [RFC 9112 §6.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3) 和 [§9.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.3)。本客户端仅支持 chunked 传输编码；不支持的有体响应编码现在明确失败，不能把编码字节当业务正文交付。失败仍沿用既有本地 400 响应、Connection=nil 的通知约定，没有新增接口或状态机。

首批 19 项红基线在 Delphi/FPC Win64 各 **4 通过、15 失败**，源码快照、二进制及结果为 `bin/s02-client-before/`；后加三个边界未冒称包含于该红基线。最终五目标（Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64）各 **22/22，共 110/110**。同一最终二进制的原 HEAD 各 14/14、临时响应各 9/9，共 70/70 和 45/45；结果保存在 `bin/s02-client-final/<target>/`。

相关 Parser 回归重新构建：Delphi Win64 压缩/串联成员 144/144，FPC Win64 chunk/trailer 100/100。Windows Delphi/FPC 双目标重新构建 WebSocket 握手各 47/47（`../WebSocketFrameTests/bin/s02-client/`）；本批不重复宣称 macOS、TLS 下全部 HTTP 畸形响应或长压通过。

```powershell
python -B build_response_tests.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64 --label response-current
python -B run_response_tests.py bin/response-current/delphi-win64/HttpHeadTests.exe --report bin/response-current/delphi-win64/results.json
```

Linux 在本目录执行相同 runner，使用对应不带 `.exe` 的二进制。构建器接受 `--source-root` 选择隔离源码快照，不覆盖当前生产文件；所有输出仍位于忽略的 bin/lib。测试 uses 改为搜索路径形式，以便该快照选项真实生效。公开签名未改变，类私有字段变化需完整重编。
