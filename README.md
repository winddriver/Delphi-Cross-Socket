# Delphi 跨平台 Socket 通讯库

作者: WiNDDRiVER(soulawing@gmail.com)

## 更新记录

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

## 已知问题
- 非Windows平台下的SSL不稳定, 请勿用于生产环境

## 部分测试截图

- **HTTP**(服务端为ubuntu 16.04 desktop)
![20170607110011](https://user-images.githubusercontent.com/3221597/26860614-61b750b4-4b71-11e7-8afc-74c3ebf16f7e.png)

- **HTTPS**(服务端为ubuntu 16.04 desktop)
![20170607142650](https://user-images.githubusercontent.com/3221597/26868229-d8d79f40-4b9a-11e7-927c-bfb3d7e6e55d.png)
