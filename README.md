# Delphi 跨平台 Socket 通讯库

作者: WiNDDRiVER(soulawing@gmail.com)

### [English](README.en.md)

<br>

## 更新记录

#### 2025.04.10
- ICrossHttpClient支持绑定本地端口(LocalPort属性)
- ICrossSslConnection支持获取ssl详细信息(GetSSLInfo方法)
- 其它一些小功能改进和修正

#### 2023.09.18
- 支持 FPC 3.3.1
- 支持 OpenSSL 3.x
- 新增 HTTP 客户端 ICrossHttpClient (支持 gzip/deflate 压缩发送)
- 新增 WebSocket 客户端 ICrossWebSocket
- HTTP 服务端支持收取 gzip/deflate 压缩数据
- 部分代码重构
- 一些小问题修正

#### 2020.07.07
- ICrossHttpServer 及 ICrossWebSocketServer 同时支持 http 和 https
  > 感谢 xlnron 的帮助

#### 2019.02.17
- 修复 TIoEventThread 可能引起的内存泄漏的问题
  > 感谢 viniciusfbb 发现并修复了该问题
- 修复 [weak] 引起的内存泄漏问题
  > 与第三方内存管理库搭配使用时会出现内存泄漏，robertodellapasqua 发现了该问题，最终由 pony5551 找到了该问题产生的原因，特此感谢！这应该是 Delphi 的 [weak] 内部实现有缺陷，将 [weak] 替换成 [unsafe] 后该问题得以解决。

#### 2019.01.15
- 增加 mbedtls 支持
  - mbedtls启用方法：在工程编译选项中开启 \_\_CROSS\_SSL\_\_ 和 \_\_MBED\_TLS\_\_ 这两个编译开关, 并且将 MbedObj 下的目录添加到对应平台的 Library path 中
  - 目前 mbedtls 支持还不够稳定, 请勿用于生产环境

#### 2017.08.22
- 代码重构, 做了大量修改, 详见源码
- 增加了几个新的 interface, 用法详见 demos
  - ICrossSocket
  - ICrossSslSocket
  - ICrossServer
  - ICrossSslServer

## TLS / mTLS 配置

- 默认保持原有普通 TLS 行为，不验证对端证书。
- 启用对端验证前，先调用 `AddCACertificate`（可多次调用或传入 PEM bundle），再设置 `VerifyPeer := True`。
- mTLS 服务端还需调用 `SetCertificate`、`SetPrivateKey`；mTLS 客户端同样需要在 `Connect` 或首次 HTTPS 请求前设置自己的证书和私钥。
- 客户端启用验证后会同时验证服务端证书链和 DNS 主机名；初版不加载系统根证书库。
- 首个 SSL 连接创建后，不再允许修改证书、私钥、CA、`VerifyPeer` 或加密套件。

### TLS 1.2 / TLS 1.3 加密套件

OpenSSL 后端支持两个独立配置入口，客户端和服务端均通过 `ICrossSslSocket` 使用：

最低协议版本默认为 TLS 1.2，`SetMinTlsVersion(tmvTls13)` 可将下限提升至 TLS 1.3；组件不固定最高版本，沿用运行库及系统配置的上限。未来协议版本仍需独立验证，不能仅凭取消上限视为已完成适配。

```pascal
LSocket.SetTls12CipherSuites('ECDHE-RSA-AES128-GCM-SHA256');
LSocket.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384');
LSocket.SetMinTlsVersion(tmvTls13); // 可选：最低 TLS 1.3
```

- `SetTls12CipherSuites` 接受 OpenSSL TLS 1.2 规则；`SetTls13CipherSuites` 接受冒号分隔、按优先顺序排列的 TLS 1.3 套件名称。
- 构造时默认使用 `Net.CrossSslSocket.Types` 中的 `DEFAULT_TLS12_CIPHER_SUITES`（ECDHE + AES-GCM/ChaCha20-Poly1305，RSA/ECDSA 共六项）和 `DEFAULT_TLS13_CIPHER_SUITES`（AES-256-GCM、ChaCha20-Poly1305、AES-128-GCM 三项）。
- 新默认不再包含原先的 `HIGH` 扩展、CBC、有限域 DHE 和 TLS 1.3 CCM/CCM_8。仅支持这些套件的端点需要调用方在首次连接前显式配置。
- 空字符串表示不修改当前配置，不恢复默认值，也不禁用协议。恢复某一版本的默认名单时，显式传入对应的 `DEFAULT_TLSxx_CIPHER_SUITES` 常量。
- 名单分别配置，但 TLS 1.2 规则中的 `@SECLEVEL` 会改变整个上下文的安全级别，可能影响 TLS 1.3 握手；恢复名单或调用 TLS 1.3 setter 都不会重置该级别。
- 输入按 OpenSSL 原生规则处理。TLS 1.2 未知项可能被忽略；TLS 1.3 的未知名称在 OpenSSL 1.1.1 中会被拒绝，在 3.x 中可能被忽略。两个 setter 都检查原生返回值，失败后抛 `ESslContextInvalid` 并使整个 socket 的 TLS 配置失效，必须重建对象。
- `SetMinTlsVersion` 接受 `Net.CrossSslSocket.Types` 中的 `TCrossTlsMinVersion`：`tmvTls12`（默认，不可更低）或 `tmvTls13`。OpenSSL 后端设置后回读上下文确认；原生调用失败或回读不一致都抛 `ESslContextInvalid` 并使整个 socket 的 TLS 配置失效。不修改协议上限和两份套件名单。mbedTLS 后端默认将客户端和服务端下限均设为 TLS 1.2；`tmvTls12` 显式应用此下限，`tmvTls13` 明确报不支持。未实现该配置的自定义后端对两个版本均报不支持。启用 SSL 时，最低版本配置也必须在首次连接前完成。
- 必须完成全部配置后再创建 SSL 连接。两个 setter 分别加锁，不提供双版本配置的事务提交。未启用 SSL 时不执行配置；mbedTLS 对两个方法的非空配置明确报告不支持。
- `ICrossSslSocket` 新增方法后，使用者和派生接口所在的 DCU/PPU/BPL/DLL 必须从同一版本源码全量重编译，不支持新旧二进制混用。此处没有增加 `ICrossHttpClient` 的配置转发接口。

可复现的配置和真实握手测试见 [TlsCipherSuitesTests](Net/Tests/FPC/TlsCipherSuitesTests/README.md)。

## 特性

- 针对不同平台使用不同的IO模型:
  - IOCP
  > Windows

  - KQUEUE
  > FreeBSD(MacOSX, iOS...)

  - EPOLL
  > Linux(Linux, Android...)

- 支持极高的并发
 
  - Windows    
  > 能跑10万以上的并发数, 需要修改注册表调整默认的最大端口数

  - Mac    
  > 做了初步测试, 测试环境为虚拟机中的 OSX 10.9.5, 即便修改了系统的句柄数限制,
  > 最多也只能打开32000多个并发连接, 或许 OSX Server 版能支持更高的并发吧

- 同时支持IPv4、IPv6

- 零内存拷贝

## 已通过测试
- Windows
- OSX
- iOS
- Android
- Linux

## 建议开发环境
- 要发挥跨平台的完整功能请使用Delphi 10.2 Tokyo及以上的版本
- 最低要求支持泛型和匿名函数的Delphi版本, 具体是从哪个版本开始支持泛型和匿名函数的我也不是太清楚
- FPC 最好使用3.3.1及以上版本

## 部分测试截图

- **HTTP Benchmark**
![image](https://github.com/user-attachments/assets/f0ca795c-cb73-4bfc-9fc1-3429db32eed9)

- **HTTPS Benchmark**
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/482c19c1-8808-4c93-91da-f8ed2389c2a7)

- **HTTP Server**(Linux-aarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/14bc8b38-3ea3-4ae1-b781-488940024380)

- **HTTP Server**(Linux-loongarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/048a6df0-3e97-4fc4-9cf8-7e48438e1ffa)

- **HTTP Client**(Linux-aarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/5a4e0fca-0e12-4cfa-887c-9e0f20d03b7b)

- **HTTP Client**(Linux-loongarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/93f0f78d-109f-4ec5-9acd-82168772a510)

- **WebSocket Server**(Linux-aarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/30b835eb-eaa9-4c1e-8cc4-14bb165709ca)

- **WebSocket Server**(Linux-loongarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/671942ef-9946-4609-a06d-2f6249b08ac4)

- **WebSocket Client**(Linux-aarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/e3d2ddf9-e281-4471-b0df-7785a8a4c220)

- **WebSocket Client**(Linux-loongarch64)
![image](https://github.com/winddriver/Delphi-Cross-Socket/assets/3221597/3d01e561-d682-4195-91e0-3758fac44467)

- **HTTP**(服务端为ubuntu 16.04 desktop)
![20170607110011](https://user-images.githubusercontent.com/3221597/26860614-61b750b4-4b71-11e7-8afc-74c3ebf16f7e.png)

- **HTTPS**(服务端为ubuntu 16.04 desktop)
![20170607142650](https://user-images.githubusercontent.com/3221597/26868229-d8d79f40-4b9a-11e7-927c-bfb3d7e6e55d.png)
