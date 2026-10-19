# HTTP 压缩生命周期回归

计划 A07/F10。独立 Parser 组件使用真实 gzip/deflate 数据及真实 zlib；不依赖 Socket、HTTP Server、Client 或 TLS。

`CROSS_HTTP_COMPRESSION_TESTS` 只允许测试为 inflate 设置 zalloc/zfree。记录原生分配和释放，不以进程工作集猜测泄漏。红基线保留旧解析算法，仅加入此观测入口。

## 覆盖范围

- 服务端定长/chunked，客户端定长/chunked/关闭定界；gzip 与 zlib 包装的 deflate，完整数据和逐字节输入。
- HTTP 定界结束但压缩尾部被截断、连接在定界前中断、直接析构、仅收到头部便结束/析构。
- CRC 错误、空内容的合法压缩流、超过一个输出缓冲的大正文、解压正文超限。
- 关闭定界成功回调主动 Abort 后重复 Finish，仍只成功一次；定长成功回调 Abort 保持既有行为。
- 开始/数据/结束回调明确拒绝或抛异常，失败通知抛异常；失败后再输入请求不能恢复成成功，重复 Finish 不重复通知。
- 初始化及窗口分配失败（真实 zalloc 返回 nil）；同一 Parser 复用；同一进程 50 轮、共 150 次正常解析/中断/析构，每次活动分配与字节数回到零。

每个场景在独立子进程中运行，外部超时 10 秒，不靠延时争取时序。二进制 chunked 数据用 Move 组合，避免 FPC 的 Unicode 字符串拼接改变压缩字节。

## 构建和运行

以下工作目录均为本目录。沿用相邻测试已安装的 Delphi 13.1 / FPC 3.3.1 与 Ubuntu SDK，不安装依赖、不修改系统配置。

```powershell
python run_tests.py --build delphi-win64 --label final --report bin/final-delphi-win64.json
python run_tests.py --build fpc-win64 --label final --report bin/final-fpc-win64.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpCompressionTests -- python3 -B run_tests.py bin/delphi-linux64/HttpCompressionTests --report bin/final-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpCompressionTests -- python3 -B run_tests.py bin/fpc-linux64/HttpCompressionTests --report bin/final-fpc-linux64.json
```

`.dpr` 包含公共 `.lpr`，`.lpi` 供 Lazarus 构建。Windows runner 使用与相邻工程相同的编译器和路径进行完整重编译，Linux 脚本为交叉构建；上述 WSL 命令才是实际 Linux 运行。

关闭测试入口的生产分支：

```powershell
python run_tests.py --build delphi-win64 --label production --production --report bin/production-delphi-win64.json
python run_tests.py --build fpc-win64 --label production --production --report bin/production-fpc-win64.json
python build_linux.py --production delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpCompressionTests -- python3 -B run_tests.py bin/production-delphi-linux64/HttpCompressionTests --production --report bin/production-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpCompressionTests -- python3 -B run_tests.py bin/production-fpc-linux64/HttpCompressionTests --production --report bin/production-fpc-linux64.json
```

生产分支执行 82 项行为回归；两个分配故障注入用例及原生分配计数仅在测试宏启用时可用。所有依赖均需完整重编译，避免混用宏不同的单元。

## 2026-10-19 红绿结果

| 目标 | 原 65 项红基线 | 最终测试构建 | 无测试宏生产构建 |
| --- | --- | --- | --- |
| Delphi Windows Win64 | 33/65 | 84/84 | 82/82 |
| FPC Windows Win64 | 33/65 | 84/84 | 82/82 |
| Delphi Linux64（WSL Ubuntu 22.04） | 33/65 | 84/84 | 82/82 |
| FPC Linux64（WSL Ubuntu 22.04） | 33/65 | 84/84 | 82/82 |

旧版定长/chunked 消息半途析构，实际留下两个原生分配、39,920 字节，释放次数为零；修复后每个场景及重复执行都归零。旧版截断压缩尾部仍调用成功，修复后在成功前拒绝。以上数字是测试进程中的 zlib 分配，不是工作集估算或速度提升。

额外兼容回归 `bin/abort-red-delphi-win64.json` 为 82/84：新 Finish 曾将成功回调的 EAbort 误报为 500；与 Decode 对齐后，gzip/deflate 关闭定界及定长对照全部通过。

有效红基线保存在 `bin/red2-<target>/`，重跑需加 `--baseline`，仅运行旧二进制包含的 65 项。早期 `baseline-*`、`red-*` 属于测试数据编码排查过程，不能用作最终红基线统计。`bin/baseline-parser.pas` 保存只加观测钩子的旧生产算法；各构建目录 `source.json`、结果 JSON 记录源码/可执行文件哈希，构建日志在 `build.log`。

## 生命周期与边界

- `Finish` 保留客户端关闭定界正常 EOF 的完成入口；定长/chunked 正文尚未结束时显式 Finish 进入失败态。正文完整但压缩流未到 `Z_STREAM_END` 也必须失败。
- 析构保留既有的关闭定界 Finish 行为；对于其他未完成消息只释放状态，不新增失败通知，因为服务端连接此时可能已释放响应队列。所有路径均先撤销 inflate 所有权并清理，再通知；回调异常不妨碍资源清理。
- 本批只处理已有单个压缩流的完整性与资源，不扩展串联 gzip member 或尾随编码字节的既有处理。未验证 Win32/ARM、实际 TCP/TLS 压缩传输、操作系统 OOM 或长期压力。初始化/窗口失败是通过真实分配器确定性注入，不能等同于完整系统内存压力。
- 共享工作区存在其他分工修改，不把此批可执行文件称为纯 HEAD；本工程本身不引用正在修改的 TLS/Socket 单元。原 F03/HTTP 集成回归由主代理协调合并验证。

主代理按最终 Parser 重编 HTTP 集成套件，Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64 均 **85/85，共 425/425 通过**，涵盖 F03 失败终态、队列生命周期、无正文响应和真实 TCP。Windows 记录位于相邻 HttpFailureTests 的 `bin/f10-integration/`，Linux 记录位于其目标目录。串联 gzip 与尾随损坏数据已独立复现，作为后续补充批次继续处理，不计入本批单流结果。
