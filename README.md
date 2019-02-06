# Delphi Cross-platform Socket Communication Library

Author: WiNDDRiVER (soulawing@gmail.com)

## update record

#### 2019.01.15
- Added mbedtls support
  - mbedtls enable method: Open the two compiler switches \_\_CROSS\_SSL\_\_ and \_\_MBED\_TLS\_\_ in the project compilation options, and add the directory under MbedObj to the corresponding platform's Library In path
  - Currently mbedtls support is not stable enough, please do not use it in production environment

#### 2017.08.22
- Code refactoring, a lot of changes, see source code
- Added a few new interfaces, see demos for details.
  - ICrossSocket
  - ICrossSslSocket
  - ICrossServer
  - ICrossSslServer


## Features

- Use different IO models for different platforms:
  - IOCP
  > Windows

  - KQUEUE
  > FreeBSD (MacOSX, iOS...)

  - EPOLL
  > Linux (Linux, Android...)

- Support for high concurrency
 
  - Windows
  > Can run more than 100,000 concurrent numbers, need to modify the registry to adjust the default maximum number of ports

  - Mac
  > Preliminary test, the test environment is OSX 10.9.5 in the virtual machine, even if the system handle limit is modified,
  > You can only open more than 32,000 concurrent connections at most, maybe OSX Server can support higher concurrency

- Support both IPv4 and IPv6

- Zero memory copy

## Passed the test
- Windows
- OSX
- iOS
- Android
- Linux

## Suggested development environment
- To use the full functionality of cross-platform, please use Delphi 10.2 Tokyo and above
- The minimum requirement to support Delphi versions of generic and anonymous functions, specifically from which version to support generic and anonymous functions, I am not too clear

## Known issues
- SSL is not stable on non-Windows platforms, please do not use it in production environments.

## Partial test screenshot

- **HTTP** (the server is ubuntu 16.04 desktop)
![20170607110011](https://user-images.githubusercontent.com/3221597/26860614-61b750b4-4b71-11e7-8afc-74c3ebf16f7e.png)

- **HTTPS** (the server is ubuntu 16.04 desktop)
![20170607142650](https://user-images.githubusercontent.com/3221597/26868229-d8d79f40-4b9a-11e7-927c-bfb3d7e6e55d.png)