# TLS 输出顺序与终止回归

对应本地计划 A05。分两阶段交付：F04 处理有序密文、挂起写与输出生命周期；F12 随后独立处理读取 fatal / EOF 的传播。本目录当前 F04 结果不能视为 F12 已完成。

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

`--modes` 可选择个别用例。`--source-root` 用于从已保存的同名生产单元快照独立构建红基线，不切换或覆盖工作区源码。日志、实际运行库版本、结果和源码哈希保存在各目标 `bin/` 子目录。

## F04 红色证据与结果

- 首批旧源码：Delphi Win64 / FPC Win64 各 0/3。order12 / order13 的原生对端均报告 `decryption failed or bad record mac`；want12 实际 WANT_READ=2，握手后 callbacks=0。保存于 `bin/baseline/`，含原 SSL 单元快照。
- 首轮实现的边界复核：capacity、disconnected-error、connected-error、received-error 在两目标均失败；修正前源码和日志在 `bin/before-boundaries/`。随后四项转绿，未把它们归为原版的同一次红基线。
- 用旧生产快照重新构建增量测试：active-close、sync-reentry、partial、read-protocol 双目标均失败；分别表现为并行物理写、同步递归、bad MAC、读生成输出为 0。日志在 `bin/extended-baseline/`。
- 完整重新握手检查进一步发现已连接对象在原生 `SSL_is_init_finished` 暂时变 False 后不再读；补一处已连接读入口条件。该次红绿日志在 `bin/read-protocol-full-before/` 和 `bin/read-protocol-full-fixed/`。简化会话恢复的服务端 Finished 可能在前一轮已发送，测试按真实握手完成状态检查，不强制不存在的额外报文。
- 接收顺序审查发现首轮有序密文实现把同批明文推迟到协议输出完成，后续明文可能先交付。真实 TLS 1.2 重新握手输入在双目标复现 `before=B / final=BA`，红基线及生产快照在 `bin/before-read-order/`。独立明文 FIFO 后，在物理完成之前即得到 AB。
- 2026-10-19，F04 最终 15 项：Delphi/FPC Win64 × OpenSSL 3.1.2 与 1.1.1v、Delphi Win32 × OpenSSL 3.5.0、Delphi/FPC Linux64 × 系统 OpenSSL 3，共七组 **15/15，合计 105/105**。Windows 日志在 `bin/f04-ordered-receive3/`、`bin/f04-ordered-receive111/`；Linux 日志在 `bin/{fpc-linux64,delphi-linux64}/`。
- 使用相同最终生产源码完整重编译现有 `TlsCipherSuitesTests`，Delphi/FPC Win64 配置自测均通过；两目标分别运行现有 `Run-TlsCipherHandshakeTests.ps1`，真实 TCP 客户端/服务端握手各 **38/38**。专用二进制、构建哈希与摘要位于 `bin/f04-compat-final/{win64,fpc64}/`；脚本产生的独立日志目录记录在摘要中，所有启动进程均已退出。
- 最终源码、二进制、运行结果及采集时间汇总在 `bin/f04-final-manifest.json`。测试生成文件均位于忽略的 `bin/` / `lib/`，没有修改系统配置或第三方源码。

未验证 macOS/Kqueue 运行、移动端/静态链接、长期压力或吞吐；不修改 MbedTLS。F12 的坏 tag / close_notify 终态仍待独立实现和验收。
