# TLS 加密套件测试

测试覆盖 `ICrossSslSocket.SetTls12CipherSuites`、`SetTls13CipherSuites`、`SetMinTlsVersion`、默认常量及真实握手。测试工程显式引用本仓库源文件，不编辑任何 FPC 配置文件或全局 Lazarus 配置。

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

当前工程的显式依赖以 Windows 为目标。其他平台需要选择相应 IO 后端。mbedTLS 配置测试需同时定义 `__MBED_TLS__` 和 `CROSS_MBEDTLS_SELFTEST`，但 Windows 版本还需要其静态对象文件；本仓库没有这些对象，不能把 OpenSSL 测试通过称为 mbedTLS 运行通过。该构建通过条件编译的只读入口检查客户端、服务端的默认及显式 TLS 1.2 下限，并验证 TLS 1.3 拒绝和配置锁；这仍不能代替 mbedTLS 的旧协议真实握手拒绝验收。

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
- `SetMinTlsVersion`：默认 TLS 1.2；提升到 TLS 1.3 后回读上下文确认，可恢复 TLS 1.2；协议上限及两份套件名单不变；配置锁定及真实连接后拒绝修改或恢复；注入“原生调用失败”和“返回成功但未生效”两种故障均抛 `ESslContextInvalid` 并禁止后续配置及客户端/服务端 SSL 连接；未实现最低版本配置的基类对两个版本均明确拒绝。
- 既有 pending callback/握手发送失败 selftest 回归。
- 真正生成 RSA 2048 位密钥，验证 OpenSSL 1.1.1 宏兼容封装及 3.x 直接调用。

`CROSS_OPENSSL_SELFTEST` / `CROSS_MBEDTLS_SELFTEST` 只用于测试构建，不用于生产发布。

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

每组 38 个用例：Cross-Socket 客户端/服务端各 19 项，包括九个默认套件逐一握手、双版本自定义正向、双版本不匹配拒绝、CBC/CCM/CCM_8 默认排除，以及最低版本提升至 TLS 1.3 后的 TLS 1.3 成功、TLS 1.2 拒绝和建连前恢复 TLS 1.2 后的成功握手。最低版本用例保留默认套件，避免套件不匹配掩盖协议下限错误。RSA/ECDSA 分别使用匹配证书，双方验证证书；对端固定协议版本，防止回退造成假阳性。负向必须观察到 TCP 建连、收到握手数据并断开；超时不算通过。

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

## PR #207 修订验证（2026-10-08）

在 PR #207 合并后的 `578fd4f` 基础上验证本地修订，使用上面的构建命令与 `Run-TlsCipherHandshakeTests.ps1`：

| 编译器 / Windows x64 | OpenSSL 运行库 | 配置测试 | 真实握手 |
| --- | --- | --- | --- |
| Delphi 13.1 / dcc64 37.0 | 3.1.2 (`30100020`) | PASS | 38/38 |
| FPC 3.3.1 | 3.1.2 (`30100020`) | PASS | 38/38 |
| Delphi 13.1 / dcc64 37.0 | 1.1.1o (`101010FF`) | PASS | 38/38 |
| FPC 3.3.1 | 1.1.1o (`101010FF`) | PASS | 38/38 |

总计 152 次真实握手用例通过，包含四组各六项新增最低版本用例。对端为仓库 OpenSSL CLI 3.1.2，1.1.1o 运行库来自本机现有安装。四组日志为忽略目录 `bin/pr207-{delphi,fpc}-{3,111}-handshake.log`，每份汇总记录本次详细握手日志目录。

mbedTLS 以 `-D__MBED_TLS__;CROSS_MBEDTLS_SELFTEST`、独立 `bin/delphi-mbed` / `lib/delphi-mbed` 目录尝试构建，仍因缺少 `aesni.o`、`aria.o` 等静态对象而失败，见 `bin/pr207-mbed-build.log`。新增的 mbedTLS 配置断言及 TLS 1.0/1.1 拒绝行为尚未运行验证；上述通过数均为 OpenSSL，不包括 mbedTLS。
