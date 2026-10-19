# TLS 输出顺序与终止回归

对应本地计划 A05。分两阶段交付：F04 处理有序密文、挂起写与输出生命周期；F12 在此基础上独立处理读取 fatal / EOF 的传播。下文分别记录两批结果，避免将阶段证据混为一次验证。

## 测试边界

使用真实 OpenSSL 客户端（本库 `TCrossOpenSslSocket` / `TCrossOpenSslConnection`）及真实 OpenSSL 服务端内存 BIO。仅替换 Owner.Send 的物理传输提交/完成时机，固定线程交错；握手、加密、解密、WANT、部分写入、重新握手和 KeyUpdate 都由原生库实际执行，不伪造 SSL 返回值。

此类组件测试不是 TCP 吞吐或内核完成端口压力测试。只创建本地测试 socket，不连接外部服务；测试证书为每个输出目录生成的临时自签名证书。运行器使用独立子进程及超时，终止后等待回收。

## F04 场景

| 用例 | 验证内容 |
| --- | --- |
| order12 / order13 | 首条密文提交用事件卡住，第二线程先从 Send 返回；真实对端最终解密 AB，不能发生 bad record mac |
| want12 | TLS 1.2 握手尚未完成时提交 A/B；实际观察 WANT_READ，重试缓冲及长度保持一致，握手后依序完成 |
| capacity | 当前 WANT 重试也计入原有 SslMaxPendingWriteBytes，上限 1 时不能静默挂起 2 字节 |
| disconnected-error | 物理失败触发关闭，断开通知抛异常不能跳过原发送 False 通知 |
| connected-error / received-error | 排在握手输出之后的业务通知抛异常，受影响连接关闭且不重复连接通知 |
| active-close | Close 取消尚未提交的逻辑写，已提交密文仍有效；迟到物理 True 结算 False 一次，不重启发送，引用计数回落 |
| sync-reentry | 完成回调连续发起 128 次发送，物理发送栈不递归增长，载荷与通知次数正确 |
| partial | 开启原生 SSL_MODE_ENABLE_PARTIAL_WRITE，64 KiB 写实际分段；并发小写不能穿过当前逻辑写 |
| read-protocol | 原生 TLS 1.2 HelloRequest 触发 SSL_read 输出；对端实际解密、完成重新握手并继续传递数据，不能再次报告连接建立 |
| keyupdate-order | 原生 TLS 1.3 KeyUpdate 后再执行受控并发，更新密钥后的记录顺序仍正确 |
| release-last | 完成回调关闭连接并释放最后外部引用，回调执行中对象存活，调用结束后析构一次 |
| write-callback-error | 成功发送通知抛异常，不能再向该请求通知 False；关闭连接并取消下一逻辑写 |
| read-order | 原生 TLS 1.2 HelloRequest 与明文 A 同批输入，延迟 ClientHello 物理完成后输入 B；A/B 必须在物理完成之前按 AB 发布 |

当前有序输出规则：SSL 锁内生成并登记密文，锁外单一物理发送泵提交。普通写保持单个逻辑发送占用；WANT 保留当前重试槽并优先恢复，不能回到队尾。SSL_read 产生的协议输出与握手输出也进入同一密文 FIFO。关闭只立即清理未提交项，物理在途字节由完成闭包持有。

解密后的明文在 SSL 锁内登记顺序，锁外单一发布泵调用接收通知。首次连接通知完成后，明文发布独立于密文发送完成，避免正常接收被慢发送阻塞。此项更改涉及类私有字段，使用方需要完整重新编译。

## 运行

沿用相邻 OpenSslLoadTests / SslInfoTests 的本机工具链和搜索路径，不修改第三方源码或全局配置。

```powershell
python run_tests.py --label f04-ordered-receive3 --targets win64 fpc64 win32
python run_tests.py --label f04-ordered-receive111 --targets win64 fpc64 `
  --ssl D:\Design\Delphi\VclFmxRtl\zLib\Net\Demos\Delphi\HttpClient\bin\Win64\openssl1.1\libssl-1_1-x64.dll `
  --crypto D:\Design\Delphi\VclFmxRtl\zLib\Net\Demos\Delphi\HttpClient\bin\Win64\openssl1.1\libcrypto-1_1-x64.dll
python -B build_linux.py fpc-linux64 delphi-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/TlsIoTests -- `
  python3 -B run_linux.py bin/fpc-linux64/TlsIoTests bin/delphi-linux64/TlsIoTests `
  --cert bin/f04-ordered-receive3/win64/test-cert.pem --key bin/f04-ordered-receive3/win64/test-key.pem
```

`--modes` 可选择个别用例。`--source-root` 用于从已保存的同名生产单元快照独立构建红基线，不切换或覆盖工作区源码。重建没有新调度钩子的旧源时加 `--no-selftest`。日志、实际运行库版本、结果和源码哈希保存在各目标 `bin/` 子目录。

## F04 红色证据与结果

- 首批旧源码：Delphi Win64 / FPC Win64 各 0/3。order12 / order13 的原生对端均报告 `decryption failed or bad record mac`；want12 实际 WANT_READ=2，握手后 callbacks=0。保存于 `bin/baseline/`，含原 SSL 单元快照。
- 首轮实现的边界复核：capacity、disconnected-error、connected-error、received-error 在两目标均失败；修正前源码和日志在 `bin/before-boundaries/`。随后四项转绿，未把它们归为原版的同一次红基线。
- 用旧生产快照重新构建增量测试：active-close、sync-reentry、partial、read-protocol 双目标均失败；分别表现为并行物理写、同步递归、bad MAC、读生成输出为 0。日志在 `bin/extended-baseline/`。
- 完整重新握手检查进一步发现已连接对象在原生 `SSL_is_init_finished` 暂时变 False 后不再读；补一处已连接读入口条件。该次红绿日志在 `bin/read-protocol-full-before/` 和 `bin/read-protocol-full-fixed/`。简化会话恢复的服务端 Finished 可能在前一轮已发送，测试按真实握手完成状态检查，不强制不存在的额外报文。
- 接收顺序审查发现首轮有序密文实现把同批明文推迟到协议输出完成，后续明文可能先交付。真实 TLS 1.2 重新握手输入在双目标复现 `before=B / final=BA`，红基线及生产快照在 `bin/before-read-order/`。独立明文 FIFO 后，在物理完成之前即得到 AB。
- 2026-10-19，F04 最终 15 项：Delphi/FPC Win64 × OpenSSL 3.1.2 与 1.1.1v、Delphi Win32 × OpenSSL 3.5.0、Delphi/FPC Linux64 × 系统 OpenSSL 3，共七组 **15/15，合计 105/105**。Windows 日志在 `bin/f04-ordered-receive3/`、`bin/f04-ordered-receive111/`。Linux 当时输出至 `bin/{fpc-linux64,delphi-linux64}/`，该默认目录后来用于 F12 早期构建；F04 的阶段哈希及结果记录保留在 `bin/f04-final-manifest.json`。
- 使用相同最终生产源码完整重编译现有 `TlsCipherSuitesTests`，Delphi/FPC Win64 配置自测均通过；两目标分别运行现有 `Run-TlsCipherHandshakeTests.ps1`，真实 TCP 客户端/服务端握手各 **38/38**。专用二进制、构建哈希与摘要位于 `bin/f04-compat-final/{win64,fpc64}/`；脚本产生的独立日志目录记录在摘要中，所有启动进程均已退出。
- 最终源码、二进制、运行结果及采集时间汇总在 `bin/f04-final-manifest.json`。测试生成文件均位于忽略的 `bin/` / `lib/`，没有修改系统配置或第三方源码。

## F12 终态规则与测试

读循环显式区分 WANT、正常 close_notify 与 fatal。在同一 SSL 锁内标记终态，禁止后续原生读写/握手；fatal 文本只在锁内保存，终结路径在锁外取走并记录一次。日志异常被隔离，不得打断有效前缀交付或关闭，日志等待另一发送线程也不持有 SSL 锁。正常 close_notify 最多调用一次 SSL_shutdown 生成应答，fatal 不再调用 SSL_shutdown。

已解密的有效前缀仍按明文 FIFO 交付。因 TLS 终态将物理成功转成 False 时，内部收尾等待现有明文发布泵排空；真实传输失败、业务回调异常或用户主动 Close 可以立即取消。空闲且没有更早待发密文时，通过已有物理发送路径尽力提交 alert，随后立即关闭，不等待对端读取。若有在途或更早待发记录，则不跨记录抢发 alert。在途数据与 alert 的缓冲持续保活到真实物理完成，迟到完成只通知一次 False。

| 用例 | 验证内容 |
| --- | --- |
| bad-tag12 / bad-tag13、eof12 / eof13 | 真实 TLS 1.2/1.3 坏 tag 或 close_notify；同批有效前缀 P 先交付；延迟 alert 完成也立即关闭；终态后原生读写/握手计数不增长 |
| bad-tag-active / eof-active | 在途 A 与排队 B 遇到终态；B 立即一次 False，A 保活到迟到物理完成再一次 False |
| bad-tag-sync / eof-sync、bad-tag-send-fail / eof-send-fail | alert 同步成功或物理失败，均一次关闭；不等待对端读取 |
| terminal-disconnect-error | 断开通知抛异常也完成终态收尾 |
| handshake-tag12 | 原生 TLS 1.2 服务端 Finished 坏 tag；握手阶段 WANT 排队 A/B 均一次失败，不能发布 Connected |
| terminal-close-race | 接收线程在有效前缀回调内停住，另一线程主动 Close 并完成在途发送；缓冲、通知次数及闭态均正确 |
| terminal-release-last | 接收回调释放最后外部连接引用；alert 在途时对象存活，物理完成后析构一次 |
| terminal-prefix-race / terminal-prefix-io-fail | 解密登记后、明文发布前完成旧物理发送；TLS-only False 保留 P，真实 I/O False 立即取消 P |
| terminal-log-reentry | fatal 日志内重入 Send，原生 SSL_write 调用数不得增加，重入请求只失败一次 |
| terminal-log-throw | 真实坏 tag 前包含有效前缀 P；日志抛异常不能传播至接收，也不能丢 P 或中断关闭 |
| terminal-log-thread | 日志启动另一线程 Send 并等待完成；该线程及时一次 False，不能被 SSL 锁阻塞，P 已交付 |

前缀竞态的两个用例通过现有 `CROSS_OPENSSL_SELFTEST` 宏下的调度钩子固定交错，只在真实解密登记后调用真实物理完成，不替换原生返回值或结算路径。宏关闭时不增加生产 API 或执行分支；`--no-selftest` 构建会排除这两个依赖钩子的场景。

```powershell
python run_tests.py --label f12-log-final3 --targets win64 fpc64 win32
python run_tests.py --label f12-log-final111 --targets win64 fpc64 `
  --ssl D:\Design\Delphi\VclFmxRtl\zLib\Net\Demos\Delphi\HttpClient\bin\Win64\openssl1.1\libssl-1_1-x64.dll `
  --crypto D:\Design\Delphi\VclFmxRtl\zLib\Net\Demos\Delphi\HttpClient\bin\Win64\openssl1.1\libcrypto-1_1-x64.dll
python run_tests.py --label f12-log-release --no-selftest --targets win64 fpc64
python -B build_linux.py --label f12-log-final3 fpc-linux64 delphi-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/TlsIoTests -- `
  python3 -B run_linux.py bin/f12-log-final3/fpc-linux64/TlsIoTests bin/f12-log-final3/delphi-linux64/TlsIoTests `
  --cert bin/f12-log-final3/win64/test-cert.pem --key bin/f12-log-final3/win64/test-key.pem
```

F12 红绿证据和最终结果：

- `bin/f12-baseline/`：已提交 F04 源码在六个基础终态场景中，Delphi/FPC 各 0/6；实际错误为 SSL_ERROR_SSL 或 ZERO_RETURN，但连接未关闭。目录包含生产源快照。`bin/f12-extra-baseline/` 的握手 Finished 坏 tag 双目标也失败，等待 alert 完成才关闭。
- `bin/f12-before-prefix/`：首轮终态实现丢失有效前缀 P，两个目标均复现；真实物理失败对照正确。`bin/f12-prefix-fixed/` 保存定向绿色结果。
- `bin/f12-before-log/`：日志重入确实再次进入原生 SSL_write，两个目标均红；`bin/f12-log-fixed/` 转绿。
- `bin/f12-before-log-boundary/`：日志抛异常导致 P 丢失，日志跨线程 Send 等待因 SSL 锁超时，两个目标均红；有界等待返回后回收线程，避免红基线留下死锁进程。`bin/f12-log-boundary-fixed/` 转绿，日志只在锁外执行并隔离异常。
- 2026-10-19，最终旧 15 项加新增 19 项，七组均 **34/34，合计 238/238**。OpenSSL 版本及目标组合与 F04 相同，结果位于 `bin/f12-log-final3/` 和 `bin/f12-log-final111/`。额外关闭自测宏后 Delphi/FPC Win64 各 **32/32**，结果位于 `bin/f12-log-release/`。
- 同一最终生产源码完整重编现有 `TlsCipherSuitesTests`，Delphi/FPC Win64 配置自测均通过，真实 TCP 客户端/服务端握手各 **38/38**。二进制、构建哈希及摘要位于 `bin/f12-log-compat/{win64,fpc64}/`，所有测试子进程均已退出。
- 最终二进制与源码（含新增测试 inc）哈希、采集时间和结果汇总在 `bin/f12-final-manifest.json`。

未验证 macOS/Kqueue 运行、移动端/静态链接、长期压力或吞吐；不修改 MbedTLS，也不包含后续缓冲分配优化。此处正常 EOF 指 TLS close_notify，未把内存 BIO 测试视为所有内核断连竞争的覆盖。

## F12 之后的托管队列兼容

在 F12 提交 `9acc87f` 之后单独接入 `37f2f82` 已提供的 `DTF.Generics.TFpcQueue`。仅 FPC 的 pending、cipher、plain 三类队列改用兼容类型；Delphi 保留 TQueue。本批不修改第三方 RTL、不改变协议状态机或缓冲所有权，也未开始 O06 性能优化。

- `managed-wrap`：真实 OpenSSL 连接保持 64 条逻辑写，完成一条再补一条，反复 2048 次；回调捕获独立计数对象和连接。Close 后未提交捕获立即释放，在途一条到物理完成才释放，连接随后析构一次。断言发生在队列/连接对象仍存活时。
- `managed-clear-pending/cipher/plain`：自测宏内对连接自身的三个真实队列固定深度入队/出队，再 Clear；FPC 逐物理槽确认 callback 和 TBytes 都已清空。该组检验容器集成，不能冒充三种协议生产泵的全覆盖；真实发送路径由前一项及既有 34 项验证。
- 通用记录、接口、字符串和容量变化的原 RTL 红证据复用 `../QueueFifoTests/bin/managed-raw/{fpc64,fpc-linux64}/`，本批未重跑或修改该套件。此次实际 TLS 红例在 `bin/managed-before/`：Delphi 4/4，FPC 0/4；FPC 的关闭捕获和三个 Clear 尾槽检查失败。类型切换后全绿。
- 最终七组原 34 加新增 4 项，**38/38，共 266/266**；目标/运行库组合与 F12 相同，产物为 `bin/managed-final3/` 和 `bin/managed-final111/`。关闭测试宏的 Delphi/FPC Win64 各 **33/33**，位于 `bin/managed-release/`。

沿用上述命令，将标签改为 `managed-final3`、`managed-final111`、`managed-release` 即可。源码、实际二进制哈希及本批 WebSocket 组合结果汇总在 `bin/managed-final-manifest.json`。

## O06 首批性能取舍

完整方法、每个负载的中位数/IQR、分配请求和本地调用 P99 见 [BUFFER_BENCHMARK.md](BUFFER_BENCHMARK.md)。最终仅采用 WS 编码时保留帧头清零、去掉显式 payload 清零的单行修改；TLS 空 BIO 提前返回在 Delphi 大块读取中稳定退化，经复核后撤回。最终 SSL 生产源与 `65a5df2` 相同，没有新增缓冲复用或所有权转移。

`BufferBench.inc` 复用本目录真实 TLS fixture，并增加实际 WS 编码基准。性能窗口只在 Windows x64 的显式优化构建中运行；普通正确性运行器不把基准模式加入默认用例集。最终帧编码对照两版都使用同一 SSL 源，Pascal 分配计数用原生线程 ID 排除后台 I/O 线程；计时 pass 没有内存钩子。

最终正确性重编标签：TLS `o06-ws-final3` / `o06-ws-final111` 七组各 **38/38，共 266/266**，关闭测试宏的 `o06-ws-release` 双目标各 **33/33**。包含原生 WANT_READ、重新握手、KeyUpdate、alert/close_notify、物理完成重入、关闭和引用寿命，未遗漏协议输出。

相邻 WebSocketFrameTests 的 `bin/o06-ws-final/` 四目标通过完整组件、每目标 11,056 组合法帧/拆分矩阵与 11 个真实 TCP 回环。前三目标使用此前已冻结的 HTTP 依赖；FPC Linux 初次构建遇到另一任务修改 Server 的中间态，随后在明确稳定窗口重新构建并通过，使用后续 BodyStorage 修复后的 Server/Parser。每个目标的 source.json 记录实际依赖，不称为四目标的 HTTP 源完全相同。

最终源码、二进制与结果汇总为 `bin/o06-final-manifest.json`。被撤回的 TLS 候选和初步采样保留为实验记录，不与最终采用的 WS 收益混合，也不把本地编码/接收微基准等同于网络吞吐或网络 P99。

## O06 独立候选：非空 BIO 精确扩容

在 WS 阶段提交 `ffb9407` 后，仅把 `_BIO_read_all` 的非空扩容目标改为本轮实际需要的 `LReadedCount + LBlockSize`。初始 16 KiB 分配、空 BIO 行为和查询次数保留，不重新引入已否决的提前返回。只测这一种候选，没有缓冲复用、开关或状态机重构。O06 已按 WS 清零、TLS 非空扩容及基准取舍结案；后续容量限制属于独立 O03。

完整方法、两编译器所有写出/接收控制负载的时间、IQR、P99 和累计申请量见 [TLS_OUTPUT_BENCHMARK.md](TLS_OUTPUT_BENCHMARK.md)。写出通过真实 OpenSSL 完成并由原生对端实际解密，覆盖 1 KiB、实际密文 16 KiB/16 KiB+1 边界、输入 16 KiB/64 KiB/1 MiB。分配接口调用次数保持不变；大块输出的累计请求量每次减少 64 KiB，不能等同于实际峰值内存下降。接收 32 B/64 KiB 控制未重现前一候选的明显回退。

独立验证：`tls-output-final3` / `tls-output-final111` 七个库/编译器组合各 **38/38，共 266/266**；关闭自测宏的 `tls-output-release` Delphi/FPC Win64 各 **33/33**。同源重编 `TlsCipherSuitesTests`，双目标配置自测通过、真实 TCP 客户端/服务端握手各 **38/38**，记录在 `bin/tls-output-compat/`。所有测试进程均已退出。

性能基线及原始配对样本位于 `bin/tls-output-baseline/`、`bin/tls-output-{before,after}/`、`bin/tls-output-results/`。最终源码与二进制哈希汇总为 `bin/tls-output-final-manifest.json`；容量限制仍只读设计，本批未改任何队列计费规则或旧 SslMaxPendingWriteBytes 语义。

## O03：可选 TLS 队列容量

在非空 BIO 扩容提交 `6fbd712` 之后独立实施。只增加 OpenSSL 具体类的配置，不改变现有接口 GUID 或方法表，不修改 MbedTLS。六个新限额默认都是 0；既有 `SslMaxPendingWriteBytes` 默认 4 MiB 及 WANT/排队语义保持原样。

```pascal
var
  Limits: TCrossSslQueueLimits;
begin
  Limits := Default(TCrossSslQueueLimits);
  Limits.MaxWriteCount := 64;
  Limits.MaxWriteBytes := 8 * 1024 * 1024;
  Limits.MaxCipherCount := 32;
  Limits.MaxCipherBytes := 2 * 1024 * 1024;
  Limits.MaxReceivedCount := 8;
  Limits.MaxReceivedBytes := 1024 * 1024;
  // Socket 为 TCrossOpenSslSocket；在建立第一个 TLS 连接前配置。
  Socket.SslQueueLimits := Limits;
end;
```

这些示例值仅演示配置，不是所有部署都适用的默认值。连接取得配置快照；若需要调整具体连接，调用 `TCrossOpenSslConnection.SetSslQueueLimits`，必须没有未结算写、密文、接收缓冲或正在执行的相关回调。负数和非空闲调整抛异常，不追补已有项目。字节参数是 Int64；单个 Pascal TBytes 仍受 Integer 索引范围约束，大配置不会预分配对应内存。

| 限额 | 计数归属 | 超额行为 |
| --- | --- | --- |
| MaxWriteCount / MaxWriteBytes | 每次正长度逻辑写的原始明文大小，包含普通队列、WANT 重试和物理在途写；部分写/重试不重复计费 | 接纳前拒绝新项，一次 False，健康连接可继续 |
| MaxCipherCount / MaxCipherBytes | 排队、物理在途及待发送终态通知的实际密文字节；空密文的握手完成项仍占 count | 原生 TLS 已推进后不能丢记录，立即进入终态并关闭；alert 也不能绕过额度 |
| MaxReceivedCount / MaxReceivedBytes | 一次解密结果缓冲为一个项目，包含排队及正在执行接收回调的缓冲 | 分配/增长前限制，满额用一字节栈探测区分协议处理与额外明文；超额保留可交付前缀后关闭 |

额度在实际完成或取消时只归还一次。Close 取消未提交写；在途密文和关联明文直到物理完成仍保活、仍计费。接收回调抛异常或重入 Close 后也会归还额度。默认关闭时不增加写入完成包装闭包或新锁；启用后使用现有 SSL 锁。此配置约束本层有效缓冲和未完成项，不是 OpenSSL 内部堆、调用方保留数据、线程栈或进程 RSS 的硬上限；仅设置 bytes 也不能限制零字节握手项，应结合 count 使用。

`TlsQueueLimitTests.inc` 新增 26 项：独立数量/字节边界、真实 WANT、32 线程接纳、64 深度反复 2048 次 wrap、Close 与迟到物理完成、128 次同步重入、TLS 1.2 重新握手的读输出、空握手完成项、TLS 1.2/1.3 正好 16 KiB 和超额输入、接收回调占用/重入/异常、1 TiB 配置、配置快照、正常 close_notify 的限额/在途释放及底层 False。SSL 状态、记录生成和对端解密都使用真实 OpenSSL；仅物理发送完成的时序由内存 fixture 控制。

旧基线以 `6fbd712` 生产源构建；因旧源码没有新配置 API，`TLS_LIMITS_BASELINE` 只跳过配置调用，并省略不可用的私有计数观测，所有 TLS 操作和行为断言保持。双目标各 15 个边界均为预期失败，最终测试源重编产物在 `bin/limits-before-final2/`，源快照在 `bin/limits-baseline/production/`。这证明旧版的无限接纳行为，不把新增可选功能描述为默认配置下的安全漏洞。

首次 FPC Linux 并发用例失败发生在测试的第二次 `TThread.WaitFor`：gdb 栈为 `__pthread_clockjoin_ex → TThread.WaitFor → TestLimitConcurrent`，32 个线程退出后，重复 join 访问已回收的 pthread。测试已分别记录 Started/Joined，不重复 join；修正后的诊断构建连续十轮通过，记录在 `bin/limits-thread-fix/concurrent-repeat.json`。该问题未修改生产代码。

2026-10-19 最终验证：

- `bin/limits-final2/`：Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64 各 **64/64**；包含原 38 项和新 26 项。
- `bin/limits-final2-111/`：Delphi/FPC Win64 + OpenSSL 1.1.1v 各 **64/64**。七组共 **448/448**；Windows x64 OpenSSL 3.1.2、Win32 3.5.0、Linux 3.0.2。
- `bin/limits-final2-release/`：关闭 `CROSS_OPENSSL_SELFTEST` 后 Delphi/FPC Win64 各 **59/59**，五个仅依赖既有私有钩子的场景排除。容量行为测试全部保留，只省略私有计数观测。
- `bin/limits-compat/`：同源重编现有 `TlsCipherSuitesTests`，双目标配置自测通过、真实 TCP 客户端/服务端握手各 **38/38**；握手脚本记录独立运行目录并在 finally 回收进程。
- 构建、结果、源码与二进制哈希、时间在 `bin/limits-final-manifest.json`；Windows 子进程检查无残留，Linux 每项由 runner 有界等待并回收。未覆盖平台不计入上述数量。

该批提交时底层 Socket 自身容量 API 的真实组合验证尚待独立实现；`limits-physical-failure` 只是物理发送返回 False 的受控路径。后续真实组合结果单列在下节，不追溯修改前述旧证据。WS 容量由独立 Sender 回归验证。没有 macOS/Kqueue 运行、MbedTLS、长期压力或本批性能收益结论。

容量默认关闭的窄范围开销检查见 [TLS_LIMITS_DEFAULT_BENCHMARK.md](TLS_LIMITS_DEFAULT_BENCHMARK.md)：Delphi/FPC Win64、TLS 1.2/1.3、64 KiB/1 MiB 收发均按五对交替测量。分配计数/累计请求量不变；两个首轮偏慢负载经过独占窗口定向复测后未出现稳定回退，全部原始样本保留，未因此调整生产代码。新增基准模式及其哈希单独记录在 `bin/limits-default-manifest.json`，不覆盖此前正确性证据。

## O03：真实 Base 额度与 TLS 组合

`TlsBaseLimitTests.inc` 在同一工程新增两个模式，由 `run_base_limits.py` 驱动真实 TCP 对端。测试的 Socket 直接继承 OpenSSL Socket，只观察连接/接收事件；**不覆盖 Send、DirectSend 或原生 TLS 函数**。`CROSS_CAPACITY_TESTS` 仅记录真实 Base 额度预留失败及只读余额，不替代实际拒绝路径。

每个协议版本先完成正常握手和 PING/PONG 回环。服务端在 ARM 小写入的成功回调内排入 64 KiB 明文和 TAIL，断言回调返回前两项尚未完成；TLS 原有逻辑写占用保证尾项确已入队，避免用关闭后的新请求冒充排队取消。

- 服务端在创建连接前配置 `MaxPendingSendBytes=4096`，新连接取得真实 Base 快照。原生 TLS 1.2 输出 65,652 字节、TLS 1.3 输出 65,624 字节，各触发一次 Base 拒绝；大写入一次 False，TAIL 取消一次 False，连接关闭一次，Base 最终余额 0/0。
- 对端在 PING/PONG 之后只收到 ARM 三字节，再观察到真实 EOF；未收到被拒绝的大明文或 TAIL。关闭后 LATE 写一次 False，Base 拒绝计数不再增长。
- 限额为 0 的同源对照收到完整 ARM + 65,536 个 A + TAIL，并回传 DONE；大写入和尾项均一次成功，连接直到测试主动清理仍可用。
- Python 对端通过数字地址 127.0.0.1 建立 TCP，并显式以 `server_hostname='localhost'` 验证证书身份。使用现有握手测试中有 SAN/CA 约束的自签名证书，保持证书链和主机名验证；未声称证书包含 IP SAN。

2026-10-20，Delphi/FPC Win64、Delphi/FPC Linux64（真实 Ubuntu 22.04 WSL）各运行 TLS 1.2/1.3 × 限额/无限制，**四目标 16/16**。Windows 使用 IOCP/OpenSSL 3.1.2，Linux 使用 Epoll/OpenSSL 3.0.2。所有子进程及回环监听已结束。本轮不重跑未改变的原 64 项或 WS 矩阵；真实 TLS+WS 上层传播由独立 `WebSocketTlsCapacityTests` 分工验收。

产物在 `bin/base-combination/{win64,fpc64,delphi-linux64,fpc-linux64}/`，包括每协议日志、`base-results.json`、构建日志和完整依赖哈希 `base-source.json`。最终汇总为 `bin/base-combination-manifest.json`；该组合针对实际冻结的工作区 Base/三后端，与 TLS 容量旧提交的正确性证据分开。

Base 默认快速路径拆分后，使用最终生产 SHA256 `1dea20133be770f6cc998a08973fa8fa35884f27b35553b9f349474b138e7af8` 再次独立重编四目标，最小组合仍 **16/16**。这一轮位于 `bin/base-combination-final/`，汇总为 `bin/base-combination-final-manifest.json`；保留首轮 Base `d1531540…` 的全部产物及 manifest，不覆盖或混称同一生产版本。最终测试主程序、include、运行器及所有生产依赖哈希均在新 manifest 中。

```powershell
# 证书和私钥参数替换为已有有效自签名测试pair。
python -B run_base_limits.py --label base-combination --targets win64 fpc64 --cert <rsa-cert.pem> --key <rsa-key.pem>
python -B run_base_limits.py --label base-combination --targets fpc-linux64 delphi-linux64 --cert <rsa-cert.pem> --key <rsa-key.pem>
```

Linux 在相同目录用 `python3 -B run_base_limits.py --label base-combination --run bin/base-combination/fpc-linux64/TlsIoTests bin/base-combination/delphi-linux64/TlsIoTests --cert <rsa-cert.pem> --key <rsa-key.pem>` 实际运行。没有验证 macOS/Kqueue、静态链接或其他 OpenSSL 版本；不将这些最小功能用例作为吞吐或全部关闭竞态的证明。
