# HEAD 请求与参数删除回归

验证 `TBaseParams.Remove(AName)` 删除所有同名项，以及真实客户端发出的 HEAD 请求没有正文定界头和正文。测试工程显式引用仓库源码，构建方式沿用相邻 `HttpRequestLifetimeTests`。

`run_tests.py` 使用 Python 标准库在 `127.0.0.1` 临时端口启动 HTTP/1.1 服务端，检查实际请求头、正文、请求次数与连接复用，不访问外网。HEAD 响应携带 `Content-Length: 2` 但不发送正文，后续 GET 返回两字节 `ok`。客户端检查响应长度与回调次数。

覆盖 14 组：按名称删除重复参数；HEAD 的字节正文、内存流、chunk provider、空正文、调用方与初始化回调的重复 CL/TE、gzip 非空及空正文、deflate 空正文；空 POST/PUT/PATCH、POST 普通及分块正文。每组网络用例同时检查后续 GET 复用同一连接。

测试不覆盖 HTTPS、非 Windows 平台、断网或压力场景。

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
