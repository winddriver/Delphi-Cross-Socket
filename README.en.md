# Delphi Cross Platform Socket Communication Library

Author: WiNDDRiVER(soulawing@gmail.com)

### [中文](README.md)

## Donate
If you find this project useful, please consider making a donation.

[PaypalMe](https://www.paypal.me/winddriver)

<br>

## Update list

#### 2023.09.18
- Supports FPC 3.3.1
- Supports OpenSSL 3.x
- Added HTTP client ICrossHttpClient (Supports sending data compressed with gzip/deflate)
- Added WebSocket client ICrossWebSocket
- The HTTP server supports receiving gzip/deflate compressed data
- Partial code refactoring
- Some minor bug fixes

#### 2020.07.07
- ICrossHttpServer and ICrossWebSocketServer support both http and https
  > Thanks to xlnron for his help

#### 2019.02.17
- Fix the problem of memory leakage caused by TIoEventThread
  > thank viniciusfbb for finding and fixing the problem
- Fix memory leak caused by [weak]
  > when used with a third-party memory management library, there will be a memory leak. robertodellapasqua found the problem and pony5551 finally found the cause of the problem. Thank you very much! This should be a defect in Delphi's [weak] internal implementation. The problem was solved after replacing [weak] with [unsafe]
  
#### 2019.01.15
- increase mbedtls support
  - mbedtls enabling method: turn on \_\_CROSS\_SSL\_\_ and \_\_MBED\_TLS\_\_ in the engineering compilation option, and add the directory under MbedObj to the Library path of the corresponding platform
  - mbedtls support is not stable at present, please do not use it in production environment
  
  #### 2017.08.22
  - code refactoring, with many modifications, see source code for details
  - Several new interface have been added. See demos for usage
    - ICrossSocket
    - ICrossSslSocket
    - ICrossServer
    - ICrossSslServer
    
## Features
- Use different IO models for different platforms:
  - IOCP
  > Windows
  
  - KQUEUE
  > FreeBSD(MacOSX, iOS...)
  
  - EPOLL
  > Linux(Linux, Android...)
  
  - Supports extremely high concurrency
  
    - Windows
    > can run more than 100000 concurrent number, need to modify the registry to adjust the default maximum port number
    
    - Mac
    > preliminary tests were conducted. the test environment was OSX 10.9.5 in the virtual machine. even if the limit on the number of handles in the system was modified,
    > can only open more than 32000 concurrent connections at most, perhaps OSX Server version can support higher concurrency

  - IPv4 and IPv6 are supported at the same time.
  - Zero Memory Copy
  
## Passed the test
  - Windows
  - OSX
  - iOS
  - Android
  - Linux

## Suggested Development Environment
  - To give full play to cross-platform functions, please use Delphi 10.2 Tokyo or higher
  - The minimum requirement is to support the Delphi version of generic and anonymous functions. I am not sure from which version generic and anonymous functions are supported.
  - It is recommended to use FPC version 3.3.1 or higher
  
## Some Test Screenshots

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
