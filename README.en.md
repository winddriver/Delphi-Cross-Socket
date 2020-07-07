# Delphi Cross Platform Socket Communication Library

Author: WiNDDRiVER(soulawing@gmail.com)

### [中文](README.md)

## Donate
If you find this project useful, please consider making a donation.

[PaypalMe](https://www.paypal.me/winddriver)

<br>

## Update list

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
  - To give full play to cross-platform functions, please use Delphi 10.2 Tokyo and above
  - The minimum requirement is to support the Delphi version of generic and anonymous functions. I am not sure from which version generic and anonymous functions are supported.
  
## Known Issues
  - SSL under non - Windows platform is unstable, please do not use it in production environment
  
## Some Test Screenshots
- **HTTP**(ubuntu 16.04 desktop for server) 
![20170607110011](https://user-images.githubusercontent.com/3221597/26860614-61b750b4-4b71-11e7-8afc-74c3ebf16f7e.png)
  
- **HTTPS**(ubuntu 16.04 desktop for server)
![20170607142650](https://user-images.githubusercontent.com/3221597/26868229-d8d79f40-4b9a-11e7-927c-bfb3d7e6e55d.png)
