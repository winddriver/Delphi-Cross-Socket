# TLS 加密套件测试

测试覆盖 `ICrossSslSocket.SetTls12CipherSuites`、`SetTls13CipherSuites`、默认常量及真实握手。测试工程显式引用本仓库源文件，不编辑任何 FPC 配置文件或全局 Lazarus 配置。

## 构建

在本目录执行，工具路径按本机实际安装替换：

```powershell
& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all TlsCipherSuitesTests.lpi
```

`.lpr` 的 `uses ... in` 和 `.lpi` 同步列出项目源码。`-vu/-vt` 日志应显示项目单元来自本仓库，包括依赖 `Utils.Logger`；不能将另一份 zLib 的同名单元当成测试对象。系统 RTL/Lazarus 依赖继续使用已有配置。输出位于本目录 `bin/`、`lib/`。

Delphi 与 FPC 共用同一程序，`.dpr` 仅包含 `.lpr`：

```powershell
New-Item -ItemType Directory -Force -Path bin\delphi-win64,lib\delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B -DCROSS_OPENSSL_SELFTEST `
  '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;..\..\..\..\Utils;D:\Design\Delphi\D13.1\lib\win64\release' `
  '-I..\..\..\..;..\..\..' '-Ebin\delphi-win64' '-N0lib\delphi-win64' `
  TlsCipherSuitesTests.dpr
```

当前工程的显式依赖以 Windows 为目标。其他平台需要选择相应 IO 后端。mbedTLS 可定义 `__MBED_TLS__`，但 Windows 版本还需要其静态对象文件；本仓库没有这些对象，不能把 OpenSSL 测试通过称为 mbedTLS 运行通过。

## 配置测试

为当前测试进程指定匹配的 OpenSSL DLL；这两个环境变量只由测试程序读取，不改变组件配置接口或用户全局环境：

```powershell
$env:CROSS_SOCKET_TEST_LIBSSL = (Resolve-Path '..\..\..\Tools\OpenSSL\libssl-3-x64.dll').Path
$env:CROSS_SOCKET_TEST_LIBCRYPTO = (Resolve-Path '..\..\..\Tools\OpenSSL\libcrypto-3-x64.dll').Path
& '.\bin\x86_64-win64-openssl\TlsCipherSuitesTests.exe'
& '.\bin\delphi-win64\TlsCipherSuitesTests.exe'
```

验证其他运行库时替换上述路径；SSL/Crypto 必须版本和位数匹配。程序先打印 `OpenSSL_version_num`，最后打印 `TlsCipherSuitesTests: PASS`，失败退出码为 1。

覆盖内容：

- 原生上下文的九项默认名单和顺序、显式恢复默认、两版本名单独立、两种配置顺序。
- 最低版本为 TLS 1.2，最大版本与新建原生上下文一致；最低版本设置失败时构造失败且上下文释放。
- 空字符串、SSL 关闭、未知名称、重复配置、真实连接创建后的锁。
- OpenSSL 1.1.1 与 3.x 对 TLS 1.3 混合未知名称的不同原生行为。
- 失败后两个 setter 和实际客户端/服务端 SSL 连接构造均被拒绝。
- `@SECLEVEL` 的上下文级影响、成功/失败路径错误队列和预置历史错误。
- 串行替换原生 setter 指针注入初始化失败，统计上下文分配/释放，验证无部分可用对象及上下文泄漏；测试总是在 finally 恢复函数指针。
- 未实现套件配置的自定义派生类可以实例化，并由公共基类明确拒绝非空配置。
- `SetMinTlsVersion`：默认 TLS 1.2；提升到 TLS 1.3 后回读上下文确认，可恢复 TLS 1.2；协议上限及两份套件名单不变；配置锁定及真实连接后拒绝修改；注入“原生调用失败”和“返回成功但未生效”两种故障均抛 `ESslContextInvalid` 并使配置失效；基类与 mbedTLS 对 TLS 1.3 明确拒绝、对 TLS 1.2 不操作。
- 既有 pending callback/握手发送失败 selftest 回归。
- 真正生成 RSA 2048 位密钥，验证 OpenSSL 1.1.1 宏兼容封装及 3.x 直接调用。

`CROSS_OPENSSL_SELFTEST` 只用于测试构建，不用于生产发布。

## 真实握手

需要 PowerShell 7 与可执行的 OpenSSL CLI。默认使用仓库内的 CLI 和 3.x DLL；脚本只绑定本机回环地址，生成一次性测试证书，日志和证书保存在忽略的 `bin/handshake-*/`：

```powershell
& .\Run-TlsCipherHandshakeTests.ps1
& .\Run-TlsCipherHandshakeTests.ps1 -TestExe '.\bin\delphi-win64\TlsCipherSuitesTests.exe'

# 另一个 OpenSSL 版本：CLI 用作互操作对端，组件使用指定 DLL。
& .\Run-TlsCipherHandshakeTests.ps1 `
  -LibSsl 'D:\path\libssl-1_1-x64.dll' `
  -LibCrypto 'D:\path\libcrypto-1_1-x64.dll'
```

每组 32 个用例：Cross-Socket 客户端/服务端各 16 项，包括九个默认套件逐一握手、双版本自定义正向、双版本不匹配拒绝、CBC/CCM/CCM_8 默认排除。RSA/ECDSA 分别使用匹配证书，双方验证证书；对端固定协议版本，防止回退造成假阳性。负向必须观察到 TCP 建连、收到握手数据并断开；超时不算通过。

测试只需要真实连接的协议和当前套件，因此通过条件编译的只读入口调用 `SSL_get_version` / `SSL_get_current_cipher`。没有以测试 stub 模拟握手，也没有依赖完整证书信息解析。

## 已验证结果（2026-09-06）

| 编译器 / Windows x64 | OpenSSL 运行库 | 配置测试 | 真实握手 |
| --- | --- | --- | --- |
| FPC 3.3.1 | 3.1.2 (`30100020`) | PASS | 32/32 |
| FPC 3.3.1 | 1.1.1v (`1010116F`) | PASS | 32/32 |
| Delphi 13.1 / dcc64 37.0 | 3.1.2 | PASS | 32/32 |
| Delphi 13.1 / dcc64 37.0 | 1.1.1v | PASS | 32/32 |

互操作对端使用仓库内 OpenSSL CLI 3.1.2；矩阵中的运行库版本指 Cross-Socket 进程实际加载的版本。更高 3.x、其他平台及静态 OpenSSL 链接未在本轮运行。

既有 HttpClient 示例使用 `lazbuild --build-all --skip-dependencies --build-mode=Windows-X64 HttpClient.lpi` 全量构建通过；跳过重建已经安装的 Lazarus 包，避免写全局包缓存。编译器对现有单元有警告/提示，日志保留，未扩大范围修改。

mbedTLS 的 Delphi 构建受缺失 `aesni.o` 等静态对象阻塞；基类拒绝行为已独立验证。另发现原有 `GetSslInfo` 在服务端读取未取得的临时对端密钥时存在访问异常，本次未修改该无关解析路径，不能将当前套件测试等同于完整 `GetSslInfo` 回归通过。
