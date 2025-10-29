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
