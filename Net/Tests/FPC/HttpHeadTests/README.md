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
