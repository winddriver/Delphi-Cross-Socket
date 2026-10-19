# WebSocket 分片、关闭和异常输入回归

## 行为与兼容边界

- 数据消息与当前帧的 opcode 分离，Ping/Pong 不改变未完成消息。控制载荷独立，消息正文按块处理，输入缓冲区不修改。
- 保留现有构造方法、接口和事件签名。continuation 向 `IsValidOpCode` 传所属消息的 opcode，`IsValidBodySize` 仍按单帧调用。更新后须全量重编译，不能混用旧 DCU/BPL。
- 独立 `TCrossWebSocketParser` 保留原有掩码、RSV 和文本默认策略；内置客户端/服务端明确设置角色、`AllowedRsvBits=0`、`CheckTextUtf8=True`。允许 RSV 不代表已实现扩展解压；扩展实现应在解码后验证文本。
- 标准端点拒绝错误 mask 方向、未协商 RSV、非法 opcode/分片顺序、分片/超长控制帧、非最短长度编码、长度溢出、非法 Close 状态和 UTF-8。Close/解析失败先终止接收，再通知上层，后续输入不再交付。
- `SendFrame` 共用实际发送实现；关闭流程先停止接纳普通帧，等待此前接纳的完整帧完成，再发送唯一 Close。业务回调在状态锁外执行；主动取消不等同于 I/O 失败。
- `SetWebSocketLimits` 是具体连接类的可选方法，配置累计消息大小、消息期限和关闭期限，默认全为 0，不突然缩小合法消息范围。应在开始接收前配置。
- **未创建后台定时线程。** 启用期限后，调用方必须持有连接接口并定期调用具体连接的 `CheckWebSocketTimeouts`；该方法使用接收锁与解析互斥。仅接收新数据时的检查不能处理完全静默的连接。
- TLS 挂起写在 `Close` 时主动失败结算，防止完成回调的连接保活引用形成环；关闭后禁止重新入队。此修正不等于所有平台普通发送队列的异常处理都已验证。

## 构建与运行

沿用相邻 `HttpRequestLifetimeTests` / `TlsCipherSuitesTests` 的 dcc 和 Lazarus 编译方式。脚本默认使用本机 Delphi 13.1、FPC 3.3.1、Lazarus 和已有 cncrypto 路径；其他机器修改脚本开头的工具路径。脚本不安装依赖、不修改全局配置，只写忽略的 `bin/`、`lib/`。

在本目录运行：

```powershell
python run_tests.py
# 可单独选择目标：
python run_tests.py win64 win32 win32-pieces fpc64
```

Delphi `.dpr` 与 FPC `.lpr` 共用测试代码；FPC 使用已保存的 `.lpi`。`CROSS_OPENSSL_SELFTEST` 仅用于测试构建，生产示例不定义它。`win32-pieces` 额外打开已有 `__LITTLE_PIECE__` 分支。

测试覆盖：

- 原有随机掩码与发送帧边界测试。
- 61 组分片/控制帧/Close 定向回归；基线 6 通过、55 失败。另保留前轮审查的 11,056 组合法帧/任意切分组合，并对文本开启严格 UTF-8 检查。
- 严格异常帧、UTF-8 跨片、旧子类、回调重入/异常后输入位置、Close 校验异常、同一批输入内的消息期限、累计大小限制。
- 0/1/125/126/65535/65536 字节的掩码与非掩码帧，多种输入块大小及输入内容不变。
- 同步/延迟发送、完成后异常、关闭期间分片取消、70 KB 底层分段、16 个线程竞争关闭和超时。
- 真实 SSL 挂起队列的关闭清理：断连通知异常、首个完成回调异常、全部条目结算、引用计数回落及关闭后禁止入队。此项不需要加载 OpenSSL DLL，不冒充真实 TLS 握手。
- Python 标准库通过真实回环 TCP 检查 8 个服务端、3 个客户端场景，包括严格 mask/UTF-8、控制帧穿插、大小上限和双方主动关闭。

## 性能对照

```powershell
python run_bench.py
python run_loopback_bench.py
```

`prepare_baseline.py` 从固定基线 `a2447766434b560e9265f92752e6ff2b3ca9e382` 导出源码到 `bin/baseline`，不切分支，不覆盖已有不同版本的基线目录。基线和当前源码分开全量构建。

- 解析基准：三个编译目标各 17 个场景（含非 ASCII UTF-8 文本），固定单核、预热、交替运行五轮；生成帧不计时。新版开启标准端点校验，逐项校验事件数和载荷长度。结果见 `bin/benchmark-results.json`。
- 端到端基准：Delphi Win32/Win64 的真实回环服务端，比较 32 字节回声、空 Ping、64 KiB 回声，交替运行五轮。结果见 `bin/loopback-benchmark-results.json`。
- 百分比表示耗时变化，不是整个生产服务器的固定吞吐变化；小幅差异应结合各轮样本判断，不能把噪声宣称为提升或退化。

## 验证边界

本轮运行平台为 Windows。Linux、Android、macOS、旧 Delphi 编译器和 mbedTLS 未在本轮运行；没有声称完成长期生产压力测试。配置变化与协议校验的行为修正不保证原有畸形端点继续连接。

项目原有依赖与 FPC 构建仍有警告，本轮不宣称零警告。

## 2026-10-19 实测结果

- Delphi 13.1 Win64、Win32、Win32 分段发送，以及 FPC 3.3.1 Win64：组件回归、每目标 11,056 组合法输入组合、异常与关闭测试均通过；每目标的 11 个真实回环场景均通过。
- Delphi WebSocketClient/WebSocketServer Release/Win64 正式工程构建通过；中间产物通过命令行重定向到本项目忽略目录，未修改第三方源码。
- Delphi Win64 原有 HttpRequestLifetimeTests 6/6 通过；OpenSSL 3.1.2 配置测试通过，真实 TLS 握手 38/38 通过。
- 三个编译目标各 17 个解析场景，共 51 项，五轮中位数全部低于基线。下面的数字为耗时变化，负数表示更快。

| 场景 | Delphi Win64 | Delphi Win32 | FPC Win64 |
| --- | ---: | ---: | ---: |
| binary32 | -69.23% | -70.63% | -63.39% |
| masked64k | -78.78% | -76.70% | -60.89% |
| text32 | -62.76% | -62.30% | -51.72% |
| ping0 | -61.97% | -69.78% | -51.43% |
| masked-bytewise32 | -29.29% | -21.43% | -27.86% |
| unicode-masked-bytewise32 | -25.36% | -14.61% | -21.83% |

- 真实回环端到端：32 字节回声/空 Ping 在约 ±2% 的运行波动范围内；64 KiB 回声耗时下降约 62%–69%。没有把纯解析提升直接等同于服务器吞吐提升。
- 初版的逐字节输入退化已通过正文续收入口、减少重复异常帧和单字节掩码提交顺序调整消除。
