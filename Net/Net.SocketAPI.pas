{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.SocketAPI;

{$I zLib.inc}

interface

uses
  SysUtils

  {$IFDEF MSWINDOWS}
  ,Windows
  ,Net.Winsock2
  ,Net.Wship6
  {$ENDIF MSWINDOWS}

  {$IFDEF DELPHI}
  {$IFDEF POSIX}
  ,Posix.Base
  ,Posix.UniStd
  ,Posix.SysSocket
  ,Posix.ArpaInet
  ,Posix.NetinetIn
  ,Posix.NetDB
  ,Posix.NetinetTCP
  ,Posix.Fcntl
  ,Posix.SysSelect
  ,Posix.StrOpts
  ,Posix.SysTime
  ,Posix.Errno
  {$IFDEF LINUX}
  ,Linuxapi.KernelIoctl
  {$ENDIF LINUX}
  {$ENDIF POSIX}
  {$ELSE}
  ,DTF.RTL
  {$IFDEF POSIX}
  ,BaseUnix
  ,Unix
  ,Sockets
  ,netdb
  ,termio
  {$IFDEF LINUX}
  ,Linux
  {$ENDIF LINUX}
  {$ENDIF POSIX}
  {$ENDIF DELPHI}
  ;

const
  SOCKET_ERROR         = -1;
  INVALID_HANDLE_VALUE = THandle(-1);
  INVALID_SOCKET       = INVALID_HANDLE_VALUE;

  {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}
  NI_MAXHOST = 1025;
  NI_MAXSERV = 32;

  {$IF DEFINED(FREEBSD)}
  NI_NOFQDN       = $00000001;
  NI_NUMERICHOST  = $00000002;
  NI_NAMEREQD     = $00000004;
  NI_NUMERICSERV  = $00000008;
  NI_DGRAM        = $00000010;
  NI_NUMERICSCOPE = $00000020;
  {$ELSE}
  NI_NUMERICHOST = 1;
  NI_NUMERICSERV = 2;
  NI_NOFQDN      = 4;
  NI_NAMEREQD    = 8;
  NI_DGRAM       = 16;
  {$ENDIF}

  {$IF DEFINED(BSD) OR DEFINED(FREEBSD) OR DEFINED(DRAGONFLY)}
  O_SHLOCK    =   $10;        { Open with shared file lock }
  O_EXLOCK    =   $20;        { Open with exclusive file lock }
  O_ASYNC     =   $40;        { Signal pgrp when data ready }
  O_FSYNC     =   $80;        { Synchronous writes }
  O_SYNC      =   $80;        { POSIX synonym for O_FSYNC }
  O_NOFOLLOW  =  $100;        { Don't follow symlinks }
  O_DIRECT    =$10000;        { Attempt to bypass buffer cache }
  {$ENDIF}

  {$IF DEFINED(LINUX) OR DEFINED(ANDROID)}
  {$IF DEFINED(CPUSPARC) OR DEFINED(CPUSPARC64)}
  O_APPEND  =          8;
  O_CREAT   =       $200;
  O_TRUNC   =       $400;
  O_EXCL    =       $800;
  O_SYNC    =      $2000;
  O_NONBLOCK =     $4000;
  O_NDELAY  =      O_NONBLOCK OR 4;
  O_NOCTTY  =      $8000;
  O_DIRECTORY =   $10000;
  O_NOFOLLOW =    $20000;
  O_DIRECT  =    $100000;
  {$ELSE : NOT (CPUSPARC OR CPUSPARC64)}
  {$IFDEF CPUMIPS}
  O_CREAT   =       $100;
  O_EXCL    =       $400;
  O_NOCTTY  =       $800;
  O_TRUNC   =       $200;
  O_APPEND  =         $8;
  O_NONBLOCK =       $80;
  O_NDELAY  =     O_NONBLOCK;
  O_SYNC    =        $10;
  O_DIRECT  =      $8000;
  O_DIRECTORY =   $10000;
  O_NOFOLLOW =    $20000;
  {$ELSE : NOT CPUMIPS}
  O_CREAT   =        $40;
  O_EXCL    =        $80;
  O_NOCTTY  =       $100;
  O_TRUNC   =       $200;
  O_APPEND  =       $400;
  O_NONBLOCK =      $800;
  O_NDELAY  =     O_NONBLOCK;
  O_SYNC    =      $1000;
  O_DIRECT  =      $4000;
  O_DIRECTORY =   $10000;
  O_NOFOLLOW =    $20000;
  {$ENDIF NOT CPUMIPS}
  {$ENDIF NOT (CPUSPARC OR CPUSPARC64)}
  {$ENDIF LINUX}

  {$ENDIF}

  {$IFDEF LINUX}
  SO_REUSEPORT = 15;
  {$ENDIF}

type
  {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}

  {$IF DEFINED(LINUX) OR DEFINED(OPENBSD) OR DEFINED(DARWIN)}
  {$DEFINE FIRST_ADDR_THEN_CANONNAME}
  {$ENDIF}

  {$IF DEFINED(FREEBSD) OR DEFINED(NETBSD) OR DEFINED(DRAGONFLY) OR DEFINED(SOLARIS) OR DEFINED(ANDROID)}
  {$DEFINE FIRST_CANONNAME_THEN_ADDR}
  {$ENDIF}

  {$IF NOT DEFINED(FIRST_CANONNAME_THEN_ADDR) AND NOT DEFINED(FIRST_ADDR_THEN_CANONNAME)}
  {$ERROR FATAL 'PLEASE CONSULT THE NETDB.H FILE FOR YOUR SYSTEM TO DETERMINE THE ORDER OF AI_ADDR AND AI_CANONNAME'}
  {$ENDIF}

  PAddrInfo = ^addrinfo;
  addrinfo = record
    ai_flags: cInt;     {* AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST *}
    ai_family: cInt;    {* PF_xxx *}
    ai_socktype: cInt;  {* SOCK_xxx *}
    ai_protocol: cInt;  {* 0 or IPPROTO_xxx for IPv4 and IPv6 *}
    ai_addrlen: TSocklen;  {* length of ai_addr *}
    {$ifdef FIRST_CANONNAME_THEN_ADDR}
    ai_canonname: PAnsiChar;   {* canonical name for hostname *}
    ai_addr: psockaddr;	   {* binary address *}
    {$endif}
    {$ifdef FIRST_ADDR_THEN_CANONNAME}
    ai_addr: psockaddr;	   {* binary address *}
    ai_canonname: PAnsiChar;   {* canonical name for hostname *}
    {$endif}
    ai_next: PAddrInfo;	   {* next structure in linked list *}
    end;
  TAddrInfo = addrinfo;
  PPAddrInfo = ^PAddrInfo;
  {$ENDIF}

  TRawSockAddrIn = packed record
    AddrLen: Integer;
    case Integer of
      0: (Addr: sockaddr_in);
      1: (Addr6: sockaddr_in6);
  end;

  {$IFDEF POSIX}
  TRawAddrInfo = addrinfo;
  {$ELSE}
  TRawAddrInfo = Net.Winsock2.{$IFDEF UNICODE}TAddrInfoW{$ELSE}TAddrInfo{$ENDIF};
  {$ENDIF}
  PRawAddrInfo = ^TRawAddrInfo;

  /// <summary>
  ///   套接字基础接口封装
  /// </summary>
  TSocketAPI = class
  public
    /// <summary>
    ///   新建套接字
    /// </summary>
    class function NewSocket(const ADomain, AType, AProtocol: Integer): THandle; static;

    /// <summary>
    ///   新建 Tcp 套接字
    /// </summary>
    class function NewTcp: THandle; static;

    /// <summary>
    ///   新建 Udp 套接字
    /// </summary>
    class function NewUdp: THandle; static;

    /// <summary>
    ///   关闭套接字
    /// </summary>
    class function CloseSocket(const ASocket: THandle): Integer; static;

    /// <summary>
    ///   停止套接字(SD_RECEIVE=0, SD_SEND=1, SD_BOTH=2)
    /// </summary>
    class function Shutdown(const ASocket: THandle; const AHow: Integer = 2): Integer; static;

    /// <summary>
    ///   接受一个连接请求, 并分配 Socket
    /// </summary>
    class function Accept(const ASocket: THandle; const Addr: PSockAddr; const AddrLen: PInteger): THandle; static;

    /// <summary>
    ///   绑定套接字到指定地址和端口, 支持 IPv6
    /// </summary>
    class function Bind(const ASocket: THandle; const Addr: PSockAddr; const AddrLen: Integer): Integer; static;

    /// <summary>
    ///   连接到主机, 支持 IPv6
    /// </summary>
    class function Connect(const ASocket: THandle; const Addr: PSockAddr; const AddrLen: Integer): Integer; static;

    /// <summary>
    ///   启动监听
    /// </summary>
    class function Listen(const ASocket: THandle; const backlog: Integer = SOMAXCONN): Integer; overload; static;

    /// <summary>
    ///   接收数据
    /// </summary>
    class function Recv(const ASocket: THandle; var Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///   发送数据
    /// </summary>
    class function Send(const ASocket: THandle; const Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///    接收数据从指定地址端口(用于UDP)
    /// </summary>
    class function RecvFrom(const ASocket: THandle; const Addr: PSockAddr;
      var AddrLen: Integer; var Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///    发送数据到指定地址端口(用于UDP)
    /// </summary>
    class function SendTo(const ASocket: THandle; const Addr: PSockAddr;
      const AddrLen: Integer; const Buf; const len: Integer; const flags: Integer = 0): Integer; static;

    /// <summary>
    ///   返回与套接字关联的远程协议地址
    /// </summary>
    class function GetPeerName(const ASocket: THandle; const Addr: PSockAddr;
      var AddrLen: Integer): Integer; static;

    /// <summary>
    ///   返回与套接字关联的本地协议地址
    /// </summary>
    class function GetSockName(const ASocket: THandle; const Addr: PSockAddr;
      var AddrLen: Integer): Integer; static;

    /// <summary>
    ///   获取套接字参数
    /// </summary>
    class function GetSockOpt(const ASocket: THandle; const ALevel, AOptionName: Integer;
       var AOptionValue; var AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   获取套接字参数
    /// </summary>
    class function GetSockOpt<T>(const ASocket: THandle; const ALevel, AOptionName: Integer;
       var AOptionValue: T): Integer; overload; static;

    /// <summary>
    ///   设置套接字参数
    /// </summary>
    class function SetSockOpt(const ASocket: THandle; const ALevel, AOptionName: Integer;
      const AOptionValue: Pointer; AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   设置套接字参数
    /// </summary>
    class function SetSockOpt(const ASocket: THandle; const ALevel, AOptionName: Integer;
      const AOptionValue; AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   设置套接字参数
    /// </summary>
    class function SetSockOpt<T>(const ASocket: THandle; const ALevel, AOptionName: Integer;
      const AOptionValue: T): Integer; overload; static;

    /// <summary>
    ///   检查套接字错误码
    /// </summary>
    class function GetError(const ASocket: THandle): Integer; static;

    /// <summary>
    ///   设置非阻塞模式
    /// </summary>
    class function SetNonBlock(const ASocket: THandle; const ANonBlock: Boolean = True): Integer; static;

    /// <summary>
    ///   设置地址重用模式
    /// </summary>
    class function SetReUseAddr(const ASocket: THandle; const AReUseAddr: Boolean = True): Integer; static;

    /// <summary>
    ///   设置端口重用模式(POSIX)
    /// </summary>
    class function SetReUsePort(const ASocket: THandle; const AReUsePort: Boolean = True): Integer; static;

    /// <summary>
    ///   设置心跳参数
    /// </summary>
    class function SetKeepAlive(const ASocket: THandle; const AIdleSeconds, AInterval, ACount: Integer): Integer; static;

    /// <summary>
    ///   开启TCP_NODELAY
    /// </summary>
    class function SetTcpNoDelay(const ASocket: THandle; const ANoDelay: Boolean = True): Integer; static;

    /// <summary>
    ///   设置发送缓冲区大小
    /// </summary>
    class function SetSndBuf(const ASocket: THandle; const ABufSize: Integer): Integer; static;

    /// <summary>
    ///   设置接收缓冲区大小
    /// </summary>
    class function SetRcvBuf(const ASocket: THandle; const ABufSize: Integer): Integer; static;

    /// <summary>
    ///   设置Linger参数(在closesocket()调用, 但是还有数据没发送完毕时容许逗留的秒数)
    /// </summary>
    class function SetLinger(const ASocket: THandle; const AOnOff: Boolean; const ALinger: Integer): Integer; static;

    /// <summary>
    ///   设置广播SO_BROADCAST
    /// </summary>
    class function SetBroadcast(const ASocket: THandle; const ABroadcast: Boolean = True): Integer; static;

    /// <summary>
    ///    设置接收超时(单位为ms)
    /// </summary>
    class function SetRecvTimeout(const ASocket: THandle; const ATimeout: Cardinal): Integer; static;

    /// <summary>
    ///    设置发送超时(单位为ms)
    /// </summary>
    class function SetSendTimeout(const ASocket: THandle; const ATimeout: Cardinal): Integer; static;

    /// <summary>
    ///   查看接收队列
    ///   ATimeout < 0 阻塞
    ///   ATimeout = 0 非阻塞立即返回
    ///   ATimeout > 0 等待超时时间
    /// </summary>
    class function Readable(const ASocket: THandle; const ATimeout: Integer): Integer; static;

    /// <summary>
    ///   查看发送队列
    ///   ATimeout < 0 阻塞
    ///   ATimeout = 0 非阻塞立即返回
    ///   ATimeout > 0 等待超时时间
    /// </summary>
    class function Writeable(const ASocket: THandle; const ATimeout: Integer): Integer; static;

    /// <summary>
    ///   缓存中已接收的字节数
    /// </summary>
    class function RecvdCount(const ASocket: THandle): Integer; static;

    /// <summary>
    ///   解析地址信息, 支持 IPv6
    /// </summary>
    class function GetAddrInfo(const AHostName, AServiceName: string;
      const AHints: TRawAddrInfo): PRawAddrInfo; overload; static;

    /// <summary>
    ///   解析地址信息, 支持 IPv6
    /// </summary>
    class function GetAddrInfo(const AHostName: string; const APort: Word;
      const AHints: TRawAddrInfo): PRawAddrInfo; overload; static;

    /// <summary>
    ///   释放 GetAddrInfo 返回的数据
    /// </summary>
    class procedure FreeAddrInfo(const ARawAddrInfo: PRawAddrInfo); static;

    /// <summary>
    ///   从 SockAddr 结构中解析出 IP 和 端口, 支持 IPv6
    /// </summary>
    class procedure ExtractAddrInfo(const AAddr: PSockAddr; const AAddrLen: Integer;
      var AIP: string; var APort: Word); static;

    /// <summary>
    ///   将域名解析为 IP 地址, 支持 IPv6
    /// </summary>
    class function GetIpAddrByHost(const AHost: string): string; static;

    /// <summary>
    ///    套接字是否有效
    /// </summary>
    class function IsValidSocket(const ASocket: THandle): Boolean; static;
  end;

implementation

{$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}
{$LINKLIB c}
function getaddrinfo(hostname, servname: MarshaledAString;
  hints: PAddrInfo; res: PPAddrInfo): Integer; cdecl; external;
procedure freeaddrinfo(ai: PRawAddrInfo); cdecl; external;

function getnameinfo(sa: PSockAddr; salen: TSockLen; host: PAnsiChar; hostlen: TSize;
  serv: PAnsiChar; servlen: TSize; flags: cInt): cInt; cdecl; external;
{$ENDIF}

{ TSocketAPI }

class function TSocketAPI.NewSocket(const ADomain, AType,
  AProtocol: Integer): THandle;
begin
  {$IFDEF DELPHI}
  Result :=
    {$IFDEF MSWINDOWS}
    Net.Winsock2.
    {$ELSE}
    Posix.SysSocket.
    {$ENDIF MSWINDOWS}
    socket(ADomain, AType, AProtocol);
  {$ELSE DELPHI}
  Result :=
    {$IFDEF MSWINDOWS}
    Net.Winsock2.socket
    {$ELSE}
    Sockets.fpSocket
    {$ENDIF MSWINDOWS}
    (ADomain, AType, AProtocol);
  {$ENDIF DELPHI}

  {$IFDEF DEBUG}
  if not IsValidSocket(Result) then
    RaiseLastOSError;
  {$ENDIF}
end;

class function TSocketAPI.NewTcp: THandle;
begin
  Result := TSocketAPI.NewSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
end;

class function TSocketAPI.NewUdp: THandle;
begin
  Result := TSocketAPI.NewSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
end;

class function TSocketAPI.Readable(const ASocket: THandle; const ATimeout: Integer): Integer;
var
  {$IFDEF MSWINDOWS}
  LFDSet: TFDSet;
  LTime_val: TTimeval;
  {$ELSE}
  LFDSet: {$IFDEF DELPHI}fd_set{$ELSE}TFDSet{$ENDIF};
  LTime_val: timeval;
  {$ENDIF}
  P: PTimeVal;
begin
  if (ATimeout >= 0) then
  begin
    LTime_val.tv_sec := ATimeout div 1000;
    LTime_val.tv_usec :=  1000 * (ATimeout mod 1000);
    P := @LTime_val;
  end else
    P := nil;

  {$IFDEF MSWINDOWS}
  FD_ZERO(LFDSet);
  FD_SET(ASocket, LFDSet);
  Result := Net.Winsock2.select(0, @LFDSet, nil, nil, P);
  {$ELSE MSWINDOWS}
  {$IFDEF DELPHI}
  FD_ZERO(LFDSet);
  _FD_SET(ASocket, LFDSet);
  Result := Posix.SysSelect.select(0, @LFDSet, nil, nil, P);
  {$ELSE DELPHI}
  fpFD_ZERO(LFDSet);
  fpFD_SET(ASocket, LFDSet);
  Result := fpSelect(0, @LFDSet, nil, nil, P);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.Recv(const ASocket: THandle; var Buf; const len,
  flags: Integer): Integer;
begin
  Result :=
    {$IFDEF DELPHI}
    {$IFDEF MSWINDOWS}
    Net.Winsock2.
    {$ELSE}
    Posix.SysSocket.
    {$ENDIF}
    recv(ASocket, Buf, len, flags);
    {$ELSE DELPHI}
    {$IFDEF MSWINDOWS}
    Net.Winsock2.recv(ASocket, Buf, len, flags);
    {$ELSE}
    fprecv(ASocket, @Buf, len, flags);
    {$ENDIF}
    {$ENDIF DELPHI}
end;

class function TSocketAPI.RecvdCount(const ASocket: THandle): Integer;
{$IF DEFINED(MSWINDOWS) OR DEFINED(FPC)}
var
  LTemp : Cardinal;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if ioctlsocket(ASocket, FIONREAD, LTemp) = SOCKET_ERROR then
    Result := -1
  else
    Result := LTemp;
  {$ELSE}
  {$IFDEF DELPHI}
   Result := ioctl(ASocket, FIONREAD);
  {$ELSE}
  if fpioctl(ASocket, FIONREAD, @LTemp) = SOCKET_ERROR then
    Result := -1
  else
    Result := LTemp;
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.RecvFrom(const ASocket: THandle; const Addr: PSockAddr;
  var AddrLen: Integer; var Buf; const len, flags: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.recvfrom(ASocket, Buf, len, flags, Addr, @AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.recvfrom(ASocket, Buf, len, flags, Addr^, socklen_t(AddrLen));
  {$ELSE}
  Result := fprecvfrom(ASocket, @Buf, len, flags, Addr, @AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.Accept(const ASocket: THandle; const Addr: PSockAddr;
  const AddrLen: PInteger): THandle;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.accept(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.accept(ASocket, Addr^, socklen_t(AddrLen^));
  {$ELSE}
  Result := fpaccept(ASocket, Addr, psocklen(AddrLen));
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.Bind(const ASocket: THandle; const Addr: PSockAddr;
  const AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.bind(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.bind(ASocket, Addr^, AddrLen);
  {$ELSE}
  Result := fpbind(ASocket, Addr, AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.CloseSocket(const ASocket: THandle): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.closesocket(ASocket);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.UniStd.__close(ASocket);
  {$ELSE}
  Result := Sockets.CloseSocket(ASocket);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.Shutdown(const ASocket: THandle; const AHow: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.shutdown(ASocket, AHow);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.shutdown(ASocket, AHow);
  {$ELSE}
  Result := fpshutdown(ASocket, AHow);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.Connect(const ASocket: THandle; const Addr: PSockAddr;
  const AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.connect(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.connect(ASocket, Addr^, AddrLen);
  {$ELSE}
  Result := fpconnect(ASocket, Addr, AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}

  {$IFDEF DEBUG}
//  if (Result <> 0) and (GetLastError <> EINPROGRESS) then
//    RaiseLastOSError;
  {$ENDIF}
end;

class function TSocketAPI.GetAddrInfo(const AHostName, AServiceName: string;
  const AHints: TRawAddrInfo): PRawAddrInfo;
var
  M: TMarshaller;
  LHost, LService: Pointer;
  LRet: Integer;
  LAddrInfo: PRawAddrInfo;
begin
  Result := nil;

  {$IFDEF MSWINDOWS}
  if (AHostName <> '') then
    LHost := M.OutString(AHostName).ToPointer
  else
    LHost := nil;
  if (AServiceName <> '') then
    LService := M.OutString(AServiceName).ToPointer
  else
    LService := nil;
  LRet := Net.Wship6.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
  {$ELSE}
  if (AHostName <> '') then
    LHost := M.AsAnsi(AHostName).ToPointer
  else
    LHost := nil;
  if (AServiceName <> '') then
    LService := M.AsAnsi(AServiceName).ToPointer
  else
    LService := nil;
  {$IFDEF DELPHI}
  LRet := Posix.NetDB.getaddrinfo(LHost, LService, AHints, Paddrinfo(LAddrInfo));
  {$ELSE}
  //LRet := cNetDB.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
  LRet := Net.SocketAPI.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}

  if (LRet <> 0) then Exit;

  Result := LAddrInfo;
end;

class function TSocketAPI.GetAddrInfo(const AHostName: string; const APort: Word;
  const AHints: TRawAddrInfo): PRawAddrInfo;
begin
  Result := GetAddrInfo(AHostName, APort.ToString, AHints);
end;

class function TSocketAPI.GetError(const ASocket: THandle): Integer;
var
  LRet, LErrLen: Integer;
begin
  LErrLen := SizeOf(Integer);
  LRet := TSocketAPI.GetSockOpt(ASocket, SOL_SOCKET, SO_ERROR, Result, LErrLen);
  if (LRet <> 0) then
    Result := LRet;
end;

class procedure TSocketAPI.FreeAddrInfo(const ARawAddrInfo: PRawAddrInfo);
begin
  {$IFDEF MSWINDOWS}
  Net.Wship6.freeaddrinfo(PAddrInfoW(ARawAddrInfo));
  {$ELSE}
  {$IFDEF DELPHI}
  Posix.NetDB.freeaddrinfo(ARawAddrInfo^);
  {$ELSE}
  //cNetDB.freeaddrinfo(ARawAddrInfo);
  Net.SocketAPI.freeaddrinfo(ARawAddrInfo);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class procedure TSocketAPI.ExtractAddrInfo(const AAddr: PSockAddr;
  const AAddrLen: Integer; var AIP: string; var APort: Word);
var
  M: TMarshaller;
  LIP, LServInfo: TPtrWrapper;
begin
  LIP := M.AllocMem(NI_MAXHOST);
  LServInfo := M.AllocMem(NI_MAXSERV);
  {$IFDEF MSWINDOWS}
  getnameinfo(AAddr, AAddrLen, LIP.ToPointer, NI_MAXHOST, LServInfo.ToPointer, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
  AIP := TMarshal.ReadStringAsUnicode(LIP);
  APort := TMarshal.ReadStringAsUnicode(LServInfo).ToInteger;
  {$ELSE}
  {$IFDEF DELPHI}
  getnameinfo(AAddr^, AAddrLen, LIP.ToPointer, NI_MAXHOST, LServInfo.ToPointer, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
  {$ELSE}
  getnameinfo(AAddr, AAddrLen, LIP.ToPointer, NI_MAXHOST, LServInfo.ToPointer, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
  {$ENDIF DELPHI}
  AIP := TMarshal.ReadStringAsAnsi(LIP);
  APort := TMarshal.ReadStringAsAnsi(LServInfo).ToInteger;
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.GetIpAddrByHost(const AHost: string): string;
var
  LHints: TRawAddrInfo;
  LAddrInfo: PRawAddrInfo;
  LPort: Word;
begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LAddrInfo := GetAddrInfo(AHost, '', LHints);
  if (LAddrInfo = nil) then Exit('');
  ExtractAddrInfo(LAddrInfo.ai_addr, LAddrInfo.ai_addrlen, Result, LPort);
  FreeAddrInfo(LAddrInfo);
end;

class function TSocketAPI.GetPeerName(const ASocket: THandle; const Addr: PSockAddr;
  var AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.getpeername(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.getpeername(ASocket, Addr^, socklen_t(AddrLen));
  {$ELSE}
  Result := fpgetpeername(ASocket, Addr, @AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.GetSockName(const ASocket: THandle; const Addr: PSockAddr;
  var AddrLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.getsockname(ASocket, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.getsockname(ASocket, Addr^, socklen_t(AddrLen));
  {$ELSE}
  Result := fpgetsockname(ASocket, Addr, @AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.GetSockOpt(const ASocket: THandle; const ALevel, AOptionName: Integer;
  var AOptionValue; var AOptionLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.getsockopt(ASocket, ALevel, AOptionName, PAnsiChar(@AOptionValue), AOptionLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.getsockopt(ASocket, ALevel, AOptionName, AOptionValue, socklen_t(AOptionLen));
  {$ELSE}
  Result := fpgetsockopt(ASocket, ALevel, AOptionName, @AOptionValue, @AOptionLen);
  {$ENDIF DELPHI}
  {$ENDIF}
end;

class function TSocketAPI.GetSockOpt<T>(const ASocket: THandle; const ALevel,
  AOptionName: Integer; var AOptionValue: T): Integer;
var
  LOptionLen: Integer;
begin
  Result := GetSockOpt(ASocket, ALevel, AOptionName, AOptionValue, LOptionLen);
end;

class function TSocketAPI.IsValidSocket(const ASocket: THandle): Boolean;
begin
  Result := (ASocket <> INVALID_SOCKET);
end;

class function TSocketAPI.Listen(const ASocket: THandle; const backlog: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.listen(ASocket, backlog);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.listen(ASocket, backlog);
  {$ELSE}
  Result := fplisten(ASocket, backlog);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}

  {$IFDEF DEBUG}
//  if (Result <> 0) then
//    RaiseLastOSError;
  {$ENDIF}
end;

class function TSocketAPI.Send(const ASocket: THandle; const Buf; const len,
  flags: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.send(ASocket, Buf, len, flags);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.send(ASocket, Buf, len, flags);
  {$ELSE}
  Result := fpsend(ASocket, @Buf, len, flags);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.SendTo(const ASocket: THandle; const Addr: PSockAddr;
  const AddrLen: Integer; const Buf; const len, flags: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.sendto(ASocket, Buf, len, flags, Addr, AddrLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.sendto(ASocket, Buf, len, flags, Addr^, AddrLen);
  {$ELSE}
  Result := fpsendto(ASocket, @Buf, len, flags, Addr, AddrLen);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.SetBroadcast(const ASocket: THandle;
  const ABroadcast: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if ABroadcast then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_BROADCAST, LOptVal, SizeOf(Integer));
end;

class function TSocketAPI.SetKeepAlive(const ASocket: THandle; const AIdleSeconds,
  AInterval, ACount: Integer): Integer;
var
  LOptVal: Integer;
  {$IFDEF MSWINDOWS}
  LKeepAlive: tcp_keepalive;
  LBytes: Cardinal;
  {$ENDIF}
begin
  LOptVal := 1;
  Result := SetSockOpt(ASocket, SOL_SOCKET, SO_KEEPALIVE, LOptVal, SizeOf(Integer));
  if (Result < 0) then Exit;

  {$IFDEF MSWINDOWS}
  // Windows 下重试次数为 3 次, 无法修改
  LKeepAlive.onoff := 1;
  LKeepAlive.keepalivetime := AIdleSeconds * 1000;
  LKeepAlive.keepaliveinterval := AInterval * 1000;
  LBytes := 0;
  Result := WSAIoctl(ASocket, SIO_KEEPALIVE_VALS, @LKeepAlive, SizeOf(tcp_keepalive),
    nil, 0, @LBytes, nil, nil);
  {$ELSEIF defined(MACOS)}
  // MAC 下 TCP_KEEPALIVE 相当于 Linux 中的 TCP_KEEPIDLE
  // 暂不支持 TCP_KEEPINTVL 和 TCP_KEEPCNT
  // OSX 10.9.5下默认的心跳参数
  // sysctl -A | grep net.inet.tcp.*keep
  // **************************************
  // net.inet.tcp.keepidle: 7200000
  // net.inet.tcp.keepintvl: 75000
  // net.inet.tcp.keepinit: 75000
  // net.inet.tcp.keepcnt: 8
  // net.inet.tcp.always_keepalive: 0
  // **************************************
  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPALIVE, AIdleSeconds, SizeOf(Integer));
  {$ELSEIF defined(LINUX) or defined(ANDROID)}
  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPIDLE, AIdleSeconds, SizeOf(Integer));
  if (Result < 0) then Exit;

  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPINTVL, AInterval, SizeOf(Integer));
  if (Result < 0) then Exit;

  Result := SetSockOpt(ASocket, IPPROTO_TCP, TCP_KEEPCNT, ACount, SizeOf(Integer));
  if (Result < 0) then Exit;
  {$ENDIF}
end;

class function TSocketAPI.SetLinger(const ASocket: THandle;
  const AOnOff: Boolean; const ALinger: Integer): Integer;
var
  LLinger: linger;
begin
  if AOnOff then
    LLinger.l_onoff := 1
  else
    LLinger.l_onoff := 0;
  LLinger.l_linger := ALinger;
  Result := SetSockOpt(ASocket, SOL_SOCKET, SO_LINGER, LLinger, SizeOf(linger));
end;

class function TSocketAPI.SetNonBlock(const ASocket: THandle;
  const ANonBlock: Boolean): Integer;
var
  LFlag: Cardinal;
begin
  {$IFDEF MSWINDOWS}
  if ANonBlock then
    LFlag := 1
  else
    LFlag := 0;
  Result := ioctlsocket(ASocket, FIONBIO, LFlag);
  {$ELSE}
  {$IFDEF DELPHI}
  LFlag := fcntl(ASocket, F_GETFL);
  if ANonBlock then
    LFlag := LFlag and not O_SYNC or O_NONBLOCK
  else
    LFlag := LFlag and not O_NONBLOCK or O_SYNC;
  Result := fcntl(ASocket, F_SETFL, LFlag);
  {$ELSE}
  LFlag := fpfcntl(ASocket, F_GETFL);
  if ANonBlock then
    LFlag := LFlag and not O_SYNC or O_NONBLOCK
  else
    LFlag := LFlag and not O_NONBLOCK or O_SYNC;
  Result := fpfcntl(ASocket, F_SETFL, LFlag);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.SetReUseAddr(const ASocket: THandle;
  const AReUseAddr: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if AReUseAddr then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_REUSEADDR, LOptVal, SizeOf(Integer));
end;

class function TSocketAPI.SetReUsePort(const ASocket: THandle;
  const AReUsePort: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if AReUsePort then
    LOptVal := 1
  else
    LOptVal := 0;
  {$IFDEF LINUX}
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_REUSEPORT, LOptVal, SizeOf(Integer));
  {$ELSE}
  Result := -1;
  {$ENDIF}
end;

class function TSocketAPI.SetRcvBuf(const ASocket: THandle;
  const ABufSize: Integer): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_RCVBUF, ABufSize, SizeOf(Integer));
end;

class function TSocketAPI.SetRecvTimeout(const ASocket: THandle;
  const ATimeout: Cardinal): Integer;
begin
  Result := SetSockOpt(ASocket,
    SOL_SOCKET, SO_RCVTIMEO, ATimeout, SizeOf(Cardinal));
end;

class function TSocketAPI.SetSendTimeout(const ASocket: THandle;
  const ATimeout: Cardinal): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket,
    SOL_SOCKET, SO_SNDTIMEO, ATimeout, SizeOf(Cardinal));
end;

class function TSocketAPI.SetSndBuf(const ASocket: THandle;
  const ABufSize: Integer): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_SNDBUF, ABufSize, SizeOf(Integer));
end;

class function TSocketAPI.SetSockOpt(const ASocket: THandle; const ALevel,
  AOptionName: Integer; const AOptionValue: Pointer;
  AOptionLen: Integer): Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Net.Winsock2.setsockopt(ASocket, ALevel, AOptionName, AOptionValue, AOptionLen);
  {$ELSE}
  {$IFDEF DELPHI}
  Result := Posix.SysSocket.setsockopt(ASocket, ALevel, AOptionName, AOptionValue^, Cardinal(AOptionLen));
  {$ELSE}
  Result := fpsetsockopt(ASocket, ALevel, AOptionName, AOptionValue, Cardinal(AOptionLen));
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

class function TSocketAPI.SetSockOpt(const ASocket: THandle; const ALevel,
  AOptionName: Integer; const AOptionValue; AOptionLen: Integer): Integer;
begin
  SetSockOpt(ASocket, ALevel, AOptionName, @AOptionValue, AOptionLen);
end;

class function TSocketAPI.SetSockOpt<T>(const ASocket: THandle; const ALevel,
  AOptionName: Integer; const AOptionValue: T): Integer;
begin
  Result := SetSockOpt(ASocket, ALevel, AOptionName, AOptionValue, SizeOf(T));
end;

class function TSocketAPI.SetTcpNoDelay(const ASocket: THandle;
  const ANoDelay: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if ANoDelay then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, IPPROTO_TCP, TCP_NODELAY, LOptVal, SizeOf(Integer));
end;

class function TSocketAPI.Writeable(const ASocket: THandle;
  const ATimeout: Integer): Integer;
var
  {$IFDEF MSWINDOWS}
  LFDSet: TFDSet;
  LTime_val: TTimeval;
  {$ELSE}
  LFDSet: {$IFDEF DELPHI}fd_set{$ELSE}TFDSet{$ENDIF};
  LTime_val: timeval;
  {$ENDIF}
  P: PTimeVal;
begin
  if (ATimeout >= 0) then
  begin
    LTime_val.tv_sec := ATimeout div 1000;
    LTime_val.tv_usec :=  1000 * (ATimeout mod 1000);
    P := @LTime_val;
  end else
    P := nil;

  {$IFDEF MSWINDOWS}
  FD_ZERO(LFDSet);
  FD_SET(ASocket, LFDSet);
  Result := Net.Winsock2.select(0, nil, @LFDSet, nil, P);
  {$ELSE}
  {$IFDEF DELPHI}
  FD_ZERO(LFDSet);
  _FD_SET(ASocket, LFDSet);
  Result := Posix.SysSelect.select(0, nil, @LFDSet, nil, P);
  {$ELSE}
  fpFD_ZERO(LFDSet);
  fpFD_SET(ASocket, LFDSet);
  Result := fpselect(0, nil, @LFDSet, nil, P);
  {$ENDIF DELPHI}
  {$ENDIF MSWINDOWS}
end;

end.
