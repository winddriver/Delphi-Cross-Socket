# 2026-11-02 全源码审查修复计划

状态：修复及本轮可用环境验证已完成。基线为 master 65886ac。S01–S06、I01–I23 均有对应代码提交。FreeBSD、移动端及部分 TLS 后端的实机验证边界见执行记录。用户在旁聊明确授权接手剩余修复、验证和提交，本计划一并纳入版本管理。

## 严重问题

| 编号 | 模块与改动 | 验收 |
|---|---|---|
| S01 | CrossHttpServer 中间件遍历所有适用注册，保留注册顺序、匹配参数和回调短路；普通路由继续选择最具体匹配 | HttpAuthTests 覆盖全局 Basic + 局部 NoCache，无凭据返回 401 且不执行业务，有凭据正常；混合处理器、通配和重入 |
| S02 | CrossWebSocketClient 与 CrossHttpClient 共用 TLS 设置、冻结和缓存逻辑 | 对 WSS 做真实升级握手，受信任且名称匹配才成功，错误 CA / 名称失败；HTTPS 和显式关闭验证保持原契约 |
| S03 | CrossHttpParser._OnBodyData 将不支持的 zlib 字典、解压无进展转换为解析失败 | HttpCompressionTests 有界运行，同包及分包只通知失败一次，正常 deflate / gzip 多成员通过 |
| S04 | CrossHttpServer 将 100 Continue 放在对应请求的队列位置，通过请求定界检查后再发 | 管线中首个最终响应、第二个临时响应、第二个最终响应次序正确；客户端等待 100 时无死锁，关闭时正确释放 |
| S05 | BSD.kqueue 按 FreeBSD ABI 声明并清零扩展字段，区分 Darwin；CrossSocket.Kqueue 检查数组步长 | 对照 C 头文件的 sizeof、偏移和批量事件；区分实际运行与静态/交叉验证 |
| S06 | CrossSocket.Iocp 让套接字关闭与 WSASend、接收及重投等句柄使用互斥，完成回调保持锁外 | IocpLifecycleTests 屏障测试并发关闭，迟到完成只结算一次，真实回环回归 |

## 重要问题

| 编号 | 模块与修复 | 验收 |
|---|---|---|
| I01 | IOUtils / CrossHttpRouter 约束静态目录最终打开的对象，应用于 Static、Index、Dir | 普通下载、列目录、根外链接和 junction，拒绝根外读取，考虑检查后替换 |
| I02 | CrossHttpServer / CrossHttpParams 要求 multipart 到达结束边界 | 完整成功、截断失败且不分派、分包和尾部兼容 |
| I03 | CrossHttpServer 在分派前审查 HTTP/1.1 Host 数量和语法 | 缺失、重复、冲突、非法端口拒绝，合法 DNS/IPv6 及 HTTP/1.0 兼容 |
| I04 | CrossSocket.Epoll 在接入回调后按实际待发队列恢复写订阅 | 单线程欢迎串，客户端不先写仍能收到 |
| I05 | CrossSocket.Epoll 区分读 EOF 与全关闭，允许已排队回包完成 | 单线程客户端 shutdown(SHUT_WR) 后完整收到回显，错误及主动取消仍能清理 |
| I06 | CrossSocket.Base.SendBytes 校验完整切片 | 负数、越界、极大整数、末尾空片及有效片 |
| I07 | CrossSocket.Base.SendStream 清理 Read 异常和自引用 | 首读与续读失败均有明确结算和资源回收 |
| I08 | CrossWebSocketClient 将升级请求纳入超时维护 | 无升级响应时仅一次失败通知，成功升级后排除 HTTP 超时 |
| I09 | CrossWebSocketClient.Send/Ping 在锁内取得当前连接强引用 | 并发关闭及重新打开，不访问已解绑连接，回调一次 |
| I10 | Net.OpenSSL.GetCertKeyUsage 读取正确的 NID 并按对应类型释放 | 带和不带 EKU 的 digitalSignature 均报告正确 |
| I11 | Net.OpenSSL 统一 OpenSSL 1.1.1 与 3.x 的对端证书所有权 | 重复 GetSslInfo 保持证书引用配对且不释放借用引用 |
| I12 | CrossSslSocket.MbedTls 正确推进 BIO 短写、原生短写和 WANT 状态 | 超过 16 KiB 的收发逐字节一致；关闭及失败时结算一次；记录可用原生运行库 |
| I13 | Net.SocketAPI.GetSockOpt<T> 初始化长度 | 真实 socket 类型读取正确 |
| I14 | Net.SocketAPI 超时 setter 按 POSIX timeval / Windows 毫秒分支 | SO_RCVTIMEO / SO_SNDTIMEO 调用成功，校验单位 |
| I15 | Net.RawSocket 初始化无效值，正确创建 Bind 的套接字并清理 | 新实例 Bind/Listen，失败、重用和关闭均不误关其它描述符 |
| I16 | Utils.IOUtils.TFastFileStream 维护随机写入的有效缓冲范围 | 直接整块覆盖后小写不复活旧前缀，空洞字节为零 |
| I17 | Utils.Hash.UpdateFromStream 逐块按剩余长度读取 | 指定 32769 字节时哈希和最终 Position 正确，允许正数短读 |
| I18 | Utils.IOUtils.TFileUtils.Move 保留同一文件及替换失败前的目标 | 同路径、别名、目标存在成功/失败均校验内容 |
| I19 | DTF.StreamEx 按 FPC 字符数组基址读取 | AB 的 Peek/Read/EOF，换行和缓冲边界 |
| I20 | Utils.Punycode 按 Unicode 码点编解码 | U+20000、BMP/ASCII 混合和无效输入；与标准向量核对 |
| I21 | Delphi/FPC 上传示例明确返回纯文本 | 验证响应 Content-Type 和带标记文件名 |
| I22 | clear.bat 限定脚本根目录并正确引用目标路径 | 在隔离副本、含空格路径下从其他目录调用，保留外部哨兵 |
| I23 | 后续复核确证的出站 HTTP/WS 请求行注入，校验 method token 与原样 target 中的非法字符 | 正常请求与合法编码不变，恶意输入不得向本地测试对端发出注入的头 |

## 执行和交付

1. 优先使用原专题的 Delphi/FPC 编译与测试入口。先在可触发的旧实现执行最小反例，再验证修复和相邻行为。输出放入忽略的 bin/lib，使用独立标签。
2. 对高风险平台改动做原生 ABI、句柄互斥、回调和失败路径专项复核。平台无法运行时明确记录，不将静态检查计作实机通过。
3. 对并行修改划分代码所有权；同一文件避免交叉覆盖。分批检查 diff、源码编码、工作区和测试结果，按可审阅的根因提交。回滚某项时以相应独立提交为边界。
4. 下方记录执行结果。尚无验证的行不能记为完成。

## 执行记录


- 2026-11-02，I21 验证补充。正式 FPC 上传示例使用 GetHashString(TStream)，当前重载不接受 TStream，构建失败。按 Delphi 示例使用 GetHashStringFromStream，再实际验证两套示例返回的类型与摘要。

| 已验证项 | 本地提交 | 结果 |
|---|---|---|
| S01 | d35d622 | Delphi/FPC Win64 Checked，认证各 60/60；旧实现无凭据进入业务，修后为 401 |
| S02 | 1552594 | Delphi/FPC Win64 各 9/9 真实 HTTPS/WSS 握手，含信任、名称、双向 TLS 和配置冻结 |
| S03 | b9759da | 旧版真实字典流超时；Win64 两编译器各 154/154 |
| S04 | a4fd96b | 两编译器真实管线和等待 100 后发正文的字节顺序正确 |
| S05 | be08da1 | FreeBSD C 头三架构布局及 FPC ELF 符号版本、旧 sysroot 链接验证；Darwin 交叉编译。FreeBSD 实机待验 |
| S06 | 514ccc5 | 三种 IOCP 屏障在旧版本暴露句柄提前关闭，Delphi Win32/Win64 和 FPC Win64 修后各 9/9 |
| I02、I03 | efafc4c、fbf6d67 | 含完整/截断 multipart 和 20 个 Host 的真实回环输入，Delphi/FPC Win64 Checked 通过 |
| I04、I05 | 69a301d、a489b45 | Delphi/FPC Linux64 在 WSL 的全套 SocketCallbackTests 各 25/25，含首发、半关闭及回调续发 |
| I06 | d7ad551 | Delphi Win32/Win64 和 FPC Win64 切片及关闭/发送测试各 3/3 |
| I08、I09、I23 | 2034917、f579989、2fc40ed | Win64 两套编译器实测握手超时、并发关闭/重连以及出站请求行拒绝；握手套件各 59/59 |
| I10、I11 | 7a622d4 | Delphi/FPC Win64 × OpenSSL 1.1.1v/3.1.2 每组 10/10 |
| I13–I15 | 4405579 | Win64 及 Ubuntu WSL Linux64，Delphi/FPC 均用真实 socket 校验 SO_TYPE、超时单位、Bind/Listen/Connect/Accept、重复 Close |
| I16–I20 | 9a31cf0 | 新用例旧实现全部失败，修后 Delphi 4/4、FPC 5/5；原文件流清理各 9/9 |
| I21、I22 | 15ca814、e078158 | 两个 Win64 正式上传示例各 4 次 TLS 1.2/1.3 请求验证正文类型与文件摘要；独立目录验证清理脚本不触及调用者目录及 junction 目标 |

| I01 | 739d561 | Windows 两目标各 19 项功能、20 项页面兼容、14 项资源清理；Linux 两目标各 21、20、14 项。ETag/304、Range/206、MIME 与打开对象后的路径替换均通过 |
| I07 | 4ac11d1 | 三个 Windows 目标各 23/23、两个 WSL Linux 目标各 27/27；覆盖首读失败、续读失败、EOF、回调次数和捕获引用释放 |
| I12 | 27435b4 | Delphi Win32/Win64、原生 Mbed TLS 2.14.0、Python TLS 1.2，对照完整双向 262177 字节；WANT_READ 重试、取消、128 KiB 暂存上限通过 |

### 接手后的复核与修正

- 本机 Delphi 13 对 Length(TBytes) 选择 NativeInt Read 重载，旧签名自定义流未被调用。保留 Integer 常量长度，使 SendStream 调用 Longint 重载，三套 Windows 编译器均通过。
- ETag 测试中的双引号受 Windows 命令行解析影响。测试参数采用百分号编码，夹具解码后再交给真实 HTTP 解析器，随后 304 回归通过。
- 静态目录从已打开句柄读取文件和条目，拒绝所有子级符号链接或 Windows 重解析点，包括指向根内的链接。配置的根目录由应用控制。
- Mbed TLS 对未消费密文设置 128 KiB 上限，超限关闭连接。输入总传输量可大于此上限。原生输出逐块排空，正数短写推进偏移，WANT 保持同一输入位置和长度。
- 整体 HttpFailureTests 在 Delphi/FPC Win64 各 143/143 通过，覆盖响应队列、取消、正文策略、临时文件和失败清理。
- Net.CrossHttpRouteFile 的 Delphi macOS x64/ARM64 单元交叉编译通过，未在 macOS 实机执行。FreeBSD、Android、其它架构和 Mbed TLS 的 FPC/Linux 运行未覆盖。测试未建立长期压力与生产吞吐结论。

### 本轮复跑入口

使用现有脚本，从各测试目录执行。中间的失败诊断标签保留在忽略目录，验收使用下列绿色标签。

- SocketCallbackTests，build.py 的标签 resume-stream-green；Windows 的 win64、win32、fpc64 及 Linux 的 fpc-linux64、delphi-linux64，各自完整执行 run_tests.py，报告在对应目标 results.json。
- HttpDirectoryTests，build_windows.py / build_linux.py 的标签 resume-route-green，含 new-api 和 hooks/resources 构建；run_suite.py 在 Windows 与 Ubuntu 22.04 WSL 分别执行，security、listing、resource 报告保存在 bin。
- HttpFailureTests，run_tests.py --targets win64 fpc64 --label resume-route-integration。
- TlsIoTests，run_mbed_io.py --arch win32/ win64 --objects 对应原生对象目录。Win32 使用本机已有 2.14.0 对象，Win64 使用已有包中 Debug 原生对象；对象包没有作为源码修改提交。

所有源码与对应回归已提交，构建产物按仓库规则保留在忽略的 bin/lib。本计划是 docs/ 忽略规则下单独跟踪的交付文件。
