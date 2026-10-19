# Chunked 与 Trailer 回归

计划 A07/F20。独立 Parser 工程，不引用 HTTP Server/Client 或 TLS。

## 行为与兼容

- chunk-size 行、chunk-data 后的结束符和 trailer 行都严格要求 CRLF，拒绝 LFCR、bare LF、重复 CR 和 CR 后夹杂字符。大小行原始控制字节在 Trim 或忽略扩展前拒绝；保留原有 64 字节大小行上限与未知扩展忽略策略。
- 终块后进入独立 `psTrailer`。该枚举追加在末尾，原有枚举值不变；最终空行完成后才调用正文结束/解析成功。显式 Finish 遇到未结束的 trailer 仍是失败，不可被后续输入恢复为成功。
- trailer 总量最多 **8,192 字节**，包含每行 CRLF 和最终空行；最多 **100 个字段**。两个限额都是每条消息重新计数的内部固定上限，不新增公开配置接口。
- 字段名逐字节按 token 校验；值允许 SP、HTAB 和 obs-text，拒绝 NUL、其他控制字符与 DEL；不先 Trim 原始数据。拒绝名称前空白、冒号前空白、空名、缺冒号和 obs-fold。
- 合法 trailer 校验后全部丢弃，不建立字段集合、不调用 OnHeaderData，也不覆盖原始头部。包括 Content-Length、Transfer-Encoding、Authorization、Cookie、Content-Encoding 和 Connection。没有新增读取 trailer 的公开 API；依据 [RFC 9112 §7.1.2](https://www.rfc-editor.org/rfc/rfc9112.html#section-7.1.2) 允许接收方丢弃这些字段。

## 验证范围

100 组场景分别运行在服务端和客户端模式：正常/多个 chunk、扩展、空或多个 trailer、OWS/原始 obs-text、畸形换行/字段/控制字节、8,192/8,193 字节与 100/101 字段边界、各状态半途 EOF、回调拒绝/异常、原头部字节完全不变，以及后续定长或 chunked 消息复用。

每组遍历逐字节输入和整个 HTTP 消息（包括终块、trailer 与后续消息）的全部两包拆分位置，合计 **74,431 次拆分输入**。每组是独立进程，外部超时 20 秒，不使用等待来碰时序。上限复用场景确认下一条消息重新拥有完整的字节/字段预算。

压缩组合使用真实 gzip/串联 gzip：合法 trailer 后成功一次并复用；gzip 截断、非法 trailer 或 trailer 尚未结束则失败；借用 `CROSS_HTTP_COMPRESSION_TESTS` 的真实 zalloc/zfree 观测，确认原生解压状态全部释放。正式构建关闭该宏，仍执行全部 100 项行为断言。

## 构建和运行

以下工作目录均为本目录，沿用相邻测试已安装的 Delphi 13.1、FPC 3.3.1 和 Ubuntu 22.04 SDK，不安装新依赖、不改系统配置。

```powershell
python run_tests.py --build delphi-win64 --label final --report bin/final-delphi-win64.json
python run_tests.py --build fpc-win64 --label final --report bin/final-fpc-win64.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpChunkTests -- python3 -B run_tests.py bin/delphi-linux64/HttpChunkTests --report bin/final-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpChunkTests -- python3 -B run_tests.py bin/fpc-linux64/HttpChunkTests --report bin/final-fpc-linux64.json
```

`.dpr` 包含公共 `.lpr`，`.lpi` 可从 Lazarus 构建。脚本全量重编依赖，交叉编译后仍用 WSL 实际运行 Linux 文件。

```powershell
python run_tests.py --build delphi-win64 --label production --production --report bin/production-delphi-win64.json
python run_tests.py --build fpc-win64 --label production --production --report bin/production-fpc-win64.json
python build_linux.py --production delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpChunkTests -- python3 -B run_tests.py bin/production-delphi-linux64/HttpChunkTests --report bin/production-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpChunkTests -- python3 -B run_tests.py bin/production-fpc-linux64/HttpChunkTests --report bin/production-fpc-linux64.json
```

## 2026-10-19 结果与边界

| 目标 | 原 92 项红基线 | 最终测试构建 | 无测试宏生产构建 |
| --- | --- | --- | --- |
| Delphi Windows Win64 | 64/92 | 100/100 | 100/100 |
| FPC Windows Win64 | 64/92 | 100/100 | 100/100 |
| Delphi Linux64（WSL） | 64/92 | 100/100 | 100/100 |
| FPC Linux64（WSL） | 64/92 | 100/100 | 100/100 |

- 旧版接受 LFCR、CR 后夹带扩展和大小行控制字符，也拒绝合法 trailer。原 92 项中 28 项失败；转绿后增加 8 项上限复用、串联 gzip + trailer 和 gzip 完整但 trailer 中断的组合场景。
- 红基线为 `bin/red-<target>/`；重跑加 `--baseline`，只运行原 92 项。构建目录中的 `source.json` 与结果 JSON 分别记录源码和可执行文件哈希；最终冻结信息在 `bin/final-source.json`。
- 使用本批 Parser 重新完整构建并运行相邻 HttpCompressionTests，Delphi/FPC Windows/Linux 四目标各 **144/144**；结果为该目录 `bin/f20-<target>.json`。本批不修改其测试源码。
- 未运行 Win32、ARM、实际网络 trailer 或长期压力；组件输入走真实 Parser，不能等同于 TCP/TLS 集成。HTTP/响应队列集成由主代理协调，不把静态审查或交叉编译当成实际运行。共享工作区还有其他批次改动，不称为纯 HEAD 构建。
