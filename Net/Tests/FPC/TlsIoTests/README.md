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
