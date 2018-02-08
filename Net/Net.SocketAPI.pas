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

interface

uses
  System.SysUtils,
  {$IFDEF POSIX}
  Posix.Base, Posix.UniStd, Posix.SysSocket, Posix.ArpaInet, Posix.NetinetIn,
  Posix.NetDB, Posix.NetinetTCP, Posix.Fcntl, Posix.SysSelect, Posix.StrOpts,
  Posix.SysTime, Posix.Errno
  {$IFDEF LINUX}
  ,Linuxapi.KernelIoctl
  {$ENDIF}
  {$ELSE}
  Winapi.Windows, Net.Winsock2, Net.Wship6
  {$ENDIF};

type
  TRawSockAddrIn = packed record
    AddrLen: Integer;
    case Integer of
      0: (Addr: sockaddr_in);
      1: (Addr6: sockaddr_in6);
  end;

  {$IFDEF POSIX}
  TRawAddrInfo = Posix.NetDB.addrinfo;
  {$ELSE}
  TRawAddrInfo = Net.Winsock2.ADDRINFOW;
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
    class function CloseSocket(ASocket: THandle): Integer; static;

    /// <summary>
    ///   停止套接字(SD_RECEIVE=0, SD_SEND=1, SD_BOTH=2)
    /// </summary>
    class function Shutdown(ASocket: THandle; AHow: Integer = 2): Integer; static;

    /// <summary>
    ///   接受一个连接请求, 并分配 Socket
    /// </summary>
    class function Accept(ASocket: THandle; Addr: PSockAddr; AddrLen: PInteger): THandle; static;

    /// <summary>
    ///   绑定套接字到指定地址和端口, 支持 IPv6
    /// </summary>
    class function Bind(ASocket: THandle; Addr: PSockAddr; AddrLen: Integer): Integer; static;

    /// <summary>
    ///   连接到主机, 支持 IPv6
    /// </summary>
    class function Connect(ASocket: THandle; Addr: PSockAddr; AddrLen: Integer): Integer; static;

    /// <summary>
    ///   启动监听
    /// </summary>
    class function Listen(ASocket: THandle; backlog: Integer = SOMAXCONN): Integer; overload; static;

    /// <summary>
    ///   接收数据
    /// </summary>
    class function Recv(ASocket: THandle; var Buf; len: Integer; flags: Integer = 0): Integer; static;

    /// <summary>
    ///   发送数据
    /// </summary>
    class function Send(ASocket: THandle; const Buf; len: Integer; flags: Integer = 0): Integer; static;

    /// <summary>
    ///    接收数据从指定地址端口(用于UDP)
    /// </summary>
    class function RecvFrom(ASocket: THandle; const Addr: PSockAddr;
      var AddrLen: Integer; var Buf; len: Integer; flags: Integer = 0): Integer; static;

    /// <summary>
    ///    发送数据到指定地址端口(用于UDP)
    /// </summary>
    class function SendTo(ASocket: THandle; const Addr: PSockAddr;
      AddrLen: Integer; const Buf; len: Integer; flags: Integer = 0): Integer; static;

    /// <summary>
    ///   返回与套接字关联的远程协议地址
    /// </summary>
    class function GetPeerName(ASocket: THandle; Addr: PSockAddr;
      var AddrLen: Integer): Integer; static;

    /// <summary>
    ///   返回与套接字关联的本地协议地址
    /// </summary>
    class function GetSockName(ASocket: THandle; Addr: PSockAddr;
      var AddrLen: Integer): Integer; static;

    /// <summary>
    ///   获取套接字参数
    /// </summary>
    class function GetSockOpt(ASocket: THandle; ALevel, AOptionName: Integer;
       var AOptionValue; var AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   获取套接字参数
    /// </summary>
    class function GetSockOpt<T>(ASocket: THandle; ALevel, AOptionName: Integer;
       var AOptionValue: T): Integer; overload; static;

    /// <summary>
    ///   设置套接字参数
    /// </summary>
    class function SetSockOpt(ASocket: THandle; ALevel, AOptionName: Integer;
      const AOptionValue; AOptionLen: Integer): Integer; overload; static;

    /// <summary>
    ///   设置套接字参数
    /// </summary>
    class function SetSockOpt<T>(ASocket: THandle; ALevel, AOptionName: Integer;
      const AOptionValue: T): Integer; overload; static;

    /// <summary>
    ///   检查套接字错误码
    /// </summary>
    class function GetError(ASocket: THandle): Integer; static;

    /// <summary>
    ///   设置非阻塞模式
    /// </summary>
    class function SetNonBlock(ASocket: THandle; ANonBlock: Boolean = True): Integer; static;

    /// <summary>
    ///   设置地址重用模式
    /// </summary>
    class function SetReUseAddr(ASocket: THandle; AReUseAddr: Boolean = True): Integer; static;

    /// <summary>
    ///   设置心跳参数
    /// </summary>
    class function SetKeepAlive(ASocket: THandle; AIdleSeconds, AInterval, ACount: Integer): Integer; static;

    /// <summary>
    ///   开启TCP_NODELAY
    /// </summary>
    class function SetTcpNoDelay(ASocket: THandle; ANoDelay: Boolean = True): Integer; static;

    /// <summary>
    ///   设置发送缓冲区大小
    /// </summary>
    class function SetSndBuf(ASocket: THandle; ABufSize: Integer): Integer; static;

    /// <summary>
    ///   设置接收缓冲区大小
    /// </summary>
    class function SetRcvBuf(ASocket: THandle; ABufSize: Integer): Integer; static;

    /// <summary>
    ///   设置Linger参数(在closesocket()调用, 但是还有数据没发送完毕时容许逗留的秒数)
    /// </summary>
    class function SetLinger(ASocket: THandle; const AOnOff: Boolean; ALinger: Integer): Integer; static;

    /// <summary>
    ///   设置广播SO_BROADCAST
    /// </summary>
    class function SetBroadcast(ASocket: THandle; ABroadcast: Boolean = True): Integer; static;

    /// <summary>
    ///    设置接收超时(单位为ms)
    /// </summary>
    class function SetRecvTimeout(ASocket: THandle; ATimeout: Cardinal): Integer; static;

    /// <summary>
    ///    设置发送超时(单位为ms)
    /// </summary>
    class function SetSendTimeout(ASocket: THandle; ATimeout: Cardinal): Integer; static;

    /// <summary>
    ///   查看接收队列
    ///   ATimeout < 0 阻塞
    ///   ATimeout = 0 非阻塞立即返回
    ///   ATimeout > 0 等待超时时间
    /// </summary>
    class function Readable(ASocket: THandle; ATimeout: Integer): Integer; static;

    /// <summary>
    ///   查看发送队列
    ///   ATimeout < 0 阻塞
    ///   ATimeout = 0 非阻塞立即返回
    ///   ATimeout > 0 等待超时时间
    /// </summary>
    class function Writeable(ASocket: THandle; ATimeout: Integer): Integer; static;

    /// <summary>
    ///   缓存中已接收的字节数
    /// </summary>
    class function RecvdCount(ASocket: THandle): Integer; static;

    /// <summary>
    ///   解析地址信息, 支持 IPv6
    /// </summary>
    class function GetAddrInfo(const AHostName, AServiceName: string;
      const AHints: TRawAddrInfo): PRawAddrInfo; overload; static;

    /// <summary>
    ///   解析地址信息, 支持 IPv6
    /// </summary>
    class function GetAddrInfo(const AHostName: string; APort: Word;
      const AHints: TRawAddrInfo): PRawAddrInfo; overload; static;

    /// <summary>
    ///   释放 GetAddrInfo 返回的数据
    /// </summary>
    class procedure FreeAddrInfo(ARawAddrInfo: PRawAddrInfo); static;

    /// <summary>
    ///   从 SockAddr 结构中解析出 IP 和 端口, 支持 IPv6
    /// </summary>
    class procedure ExtractAddrInfo(const AAddr: PSockAddr; AAddrLen: Integer;
      var AIP: string; var APort: Word); static;

    /// <summary>
    ///   将域名解析为 IP 地址, 支持 IPv6
    /// </summary>
    class function GetIpAddrByHost(const AHost: string): string; static;

    /// <summary>
    ///    套接字是否有效
    /// </summary>
    class function IsValidSocket(ASocket: THandle): Boolean; static;
  end;

implementation

{ TSocketAPI }

class function TSocketAPI.NewSocket(const ADomain, AType,
  AProtocol: Integer): THandle;
begin
  Result :=
    {$IFDEF POSIX}
    Posix.SysSocket.
    {$ELSE}
    Net.Winsock2.
    {$ENDIF}
    socket(ADomain, AType, AProtocol);

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

class function TSocketAPI.Readable(ASocket: THandle; ATimeout: Integer): Integer;
var
  {$IFDEF POSIX}
  LFDSet: fd_set;
  LTime_val: timeval;
  {$ELSE}
  LFDSet: TFDSet;
  LTime_val: TTimeval;
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

  {$IFDEF POSIX}
  FD_ZERO(LFDSet);
  _FD_SET(ASocket, LFDSet);
  Result := Posix.SysSelect.select(0, @LFDSet, nil, nil, P);
  {$ELSE}
  FD_ZERO(LFDSet);
  FD_SET(ASocket, LFDSet);
  Result := Net.Winsock2.select(0, @LFDSet, nil, nil, P);
  {$ENDIF}
end;

class function TSocketAPI.Recv(ASocket: THandle; var Buf; len,
  flags: Integer): Integer;
begin
  Result :=
    {$IFDEF POSIX}
    Posix.SysSocket.
    {$ELSE}
    Net.Winsock2.
    {$ENDIF}
    recv(ASocket, Buf, len, flags);
end;

class function TSocketAPI.RecvdCount(ASocket: THandle): Integer;
{$IFNDEF POSIX}
var
  LTemp : Cardinal;
{$ENDIF}
begin
  {$IFDEF POSIX}
  Result := ioctl(ASocket, FIONREAD);
  {$ELSE}
  if ioctlsocket(ASocket, FIONREAD, LTemp) = SOCKET_ERROR then
    Result := -1
  else
    Result := LTemp;
  {$ENDIF}
end;

class function TSocketAPI.RecvFrom(ASocket: THandle; const Addr: PSockAddr;
  var AddrLen: Integer; var Buf; len, flags: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.recvfrom(ASocket, Buf, len, flags, Addr^, Cardinal(AddrLen));
  {$ELSE}
  Result := Net.Winsock2.recvfrom(ASocket, Buf, len, flags, Addr, @AddrLen);
  {$ENDIF}
end;

class function TSocketAPI.Accept(ASocket: THandle; Addr: PSockAddr;
  AddrLen: PInteger): THandle;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.accept(ASocket, Addr^, Cardinal(AddrLen^));
  {$ELSE}
  Result := Net.Winsock2.accept(ASocket, Addr, AddrLen);
  {$ENDIF}
end;

class function TSocketAPI.Bind(ASocket: THandle; Addr: PSockAddr;
  AddrLen: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.bind(ASocket, Addr^, AddrLen);
  {$ELSE}
  Result := Net.Winsock2.bind(ASocket, Addr, AddrLen);
  {$ENDIF}
end;

class function TSocketAPI.CloseSocket(ASocket: THandle): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.UniStd.__close(ASocket);
  {$ELSE}
  Result := Net.Winsock2.closesocket(ASocket);
  {$ENDIF}
end;

class function TSocketAPI.Shutdown(ASocket: THandle; AHow: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.shutdown(ASocket, AHow);
  {$ELSE}
  Result := Net.Winsock2.shutdown(ASocket, AHow);
  {$ENDIF}
end;

class function TSocketAPI.Connect(ASocket: THandle; Addr: PSockAddr;
  AddrLen: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.connect(ASocket, Addr^, AddrLen);
  {$ELSE}
  Result := Net.Winsock2.connect(ASocket, Addr, AddrLen);
  {$ENDIF}

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

  {$IFDEF POSIX}
  if (AHostName <> '') then
    LHost := M.AsAnsi(AHostName).ToPointer
  else
    LHost := nil;
  if (AServiceName <> '') then
    LService := M.AsAnsi(AServiceName).ToPointer
  else
    LService := nil;
  LRet := Posix.NetDB.getaddrinfo(LHost, LService, AHints, Paddrinfo(LAddrInfo));
  {$ELSE}
  if (AHostName <> '') then
    LHost := M.OutString(AHostName).ToPointer
  else
    LHost := nil;
  if (AServiceName <> '') then
    LService := M.OutString(AServiceName).ToPointer
  else
    LService := nil;
  LRet := Net.Wship6.getaddrinfo(LHost, LService, @AHints, @LAddrInfo);
  {$ENDIF}

  if (LRet <> 0) then Exit;

  Result := LAddrInfo;
end;

class function TSocketAPI.GetAddrInfo(const AHostName: string; APort: Word;
  const AHints: TRawAddrInfo): PRawAddrInfo;
begin
  Result := GetAddrInfo(AHostName, APort.ToString, AHints);
end;

class function TSocketAPI.GetError(ASocket: THandle): Integer;
var
  LRet, LErrLen: Integer;
begin
  LErrLen := SizeOf(Integer);
  LRet := TSocketAPI.GetSockOpt(ASocket, SOL_SOCKET, SO_ERROR, Result, LErrLen);
  if (LRet <> 0) then
    Result := LRet;
end;

class procedure TSocketAPI.FreeAddrInfo(ARawAddrInfo: PRawAddrInfo);
begin
  {$IFDEF POSIX}
  Posix.NetDB.freeaddrinfo(ARawAddrInfo^);
  {$ELSE}
  Net.Wship6.freeaddrinfo(PAddrInfoW(ARawAddrInfo));
  {$ENDIF}
end;

class procedure TSocketAPI.ExtractAddrInfo(const AAddr: PSockAddr;
  AAddrLen: Integer; var AIP: string; var APort: Word);
var
  M: TMarshaller;
  LIP, LServInfo: TPtrWrapper;
begin
  LIP := M.AllocMem(NI_MAXHOST);
  LServInfo := M.AllocMem(NI_MAXSERV);
  {$IFDEF POSIX}
  getnameinfo(AAddr^, AAddrLen, LIP.ToPointer, NI_MAXHOST, LServInfo.ToPointer, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
  AIP := TMarshal.ReadStringAsAnsi(LIP);
  APort := TMarshal.ReadStringAsAnsi(LServInfo).ToInteger;
  {$ELSE}
  getnameinfo(AAddr, AAddrLen, LIP.ToPointer, NI_MAXHOST, LServInfo.ToPointer, NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
  AIP := TMarshal.ReadStringAsUnicode(LIP);
  APort := TMarshal.ReadStringAsUnicode(LServInfo).ToInteger;
  {$ENDIF}
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

class function TSocketAPI.GetPeerName(ASocket: THandle; Addr: PSockAddr;
  var AddrLen: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.getpeername(ASocket, Addr^, Cardinal(AddrLen));
  {$ELSE}
  Result := Net.Winsock2.getpeername(ASocket, Addr, AddrLen);
  {$ENDIF}
end;

class function TSocketAPI.GetSockName(ASocket: THandle; Addr: PSockAddr;
  var AddrLen: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.getsockname(ASocket, Addr^, Cardinal(AddrLen));
  {$ELSE}
  Result := Net.Winsock2.getsockname(ASocket, Addr, AddrLen);
  {$ENDIF}
end;

class function TSocketAPI.GetSockOpt(ASocket: THandle; ALevel, AOptionName: Integer;
  var AOptionValue; var AOptionLen: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.getsockopt(ASocket, ALevel, AOptionName, AOptionValue, Cardinal(AOptionLen));
  {$ELSE}
  Result := Net.Winsock2.getsockopt(ASocket, ALevel, AOptionName, PAnsiChar(@AOptionValue), AOptionLen);
  {$ENDIF}
end;

class function TSocketAPI.GetSockOpt<T>(ASocket: THandle; ALevel,
  AOptionName: Integer; var AOptionValue: T): Integer;
var
  LOptionLen: Integer;
begin
  Result := GetSockOpt(ASocket, ALevel, AOptionName, AOptionValue, LOptionLen);
end;

class function TSocketAPI.IsValidSocket(ASocket: THandle): Boolean;
begin
  Result := (ASocket <> INVALID_HANDLE_VALUE);
end;

class function TSocketAPI.Listen(ASocket: THandle; backlog: Integer): Integer;
begin
  Result :=
    {$IFDEF POSIX}
    Posix.SysSocket.
    {$ELSE}
    Net.Winsock2.
    {$ENDIF}
    listen(ASocket, backlog);

  {$IFDEF DEBUG}
//  if (Result <> 0) then
//    RaiseLastOSError;
  {$ENDIF}
end;

class function TSocketAPI.Send(ASocket: THandle; const Buf; len,
  flags: Integer): Integer;
begin
  Result :=
    {$IFDEF POSIX}
    Posix.SysSocket.
    {$ELSE}
    Net.Winsock2.
    {$ENDIF}
    send(ASocket, Buf, len, flags);
end;

class function TSocketAPI.SendTo(ASocket: THandle; const Addr: PSockAddr;
  AddrLen: Integer; const Buf; len, flags: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.sendto(ASocket, Buf, len, flags, Addr^, AddrLen);
  {$ELSE}
  Result := Net.Winsock2.sendto(ASocket, Buf, len, flags, Addr, AddrLen);
  {$ENDIF}
end;

class function TSocketAPI.SetBroadcast(ASocket: THandle;
  ABroadcast: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if ABroadcast then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_BROADCAST, LOptVal, SizeOf(Integer));
end;

class function TSocketAPI.SetKeepAlive(ASocket: THandle; AIdleSeconds,
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

class function TSocketAPI.SetLinger(ASocket: THandle;
  const AOnOff: Boolean; ALinger: Integer): Integer;
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

class function TSocketAPI.SetNonBlock(ASocket: THandle;
  ANonBlock: Boolean): Integer;
var
  LFlag: Cardinal;
begin
  {$IFDEF POSIX}
  LFlag := fcntl(ASocket, F_GETFL);
  if ANonBlock then
    LFlag := LFlag and not O_SYNC or O_NONBLOCK
  else
    LFlag := LFlag and not O_NONBLOCK or O_SYNC;
  Result := fcntl(ASocket, F_SETFL, LFlag);
  {$ELSE}
  if ANonBlock then
    LFlag := 1
  else
    LFlag := 0;
  Result := ioctlsocket(ASocket, FIONBIO, LFlag);
  {$ENDIF}
end;

class function TSocketAPI.SetReUseAddr(ASocket: THandle;
  AReUseAddr: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if AReUseAddr then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_REUSEADDR, LOptVal, SizeOf(Integer));
end;

class function TSocketAPI.SetRcvBuf(ASocket: THandle;
  ABufSize: Integer): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_RCVBUF, ABufSize, SizeOf(Integer));
end;

class function TSocketAPI.SetRecvTimeout(ASocket: THandle;
  ATimeout: Cardinal): Integer;
begin
  Result := SetSockOpt(ASocket,
    SOL_SOCKET, SO_RCVTIMEO, ATimeout, SizeOf(Cardinal));
end;

class function TSocketAPI.SetSendTimeout(ASocket: THandle;
  ATimeout: Cardinal): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket,
    SOL_SOCKET, SO_SNDTIMEO, ATimeout, SizeOf(Cardinal));
end;

class function TSocketAPI.SetSndBuf(ASocket: THandle;
  ABufSize: Integer): Integer;
begin
  Result := TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_SNDBUF, ABufSize, SizeOf(Integer));
end;

class function TSocketAPI.SetSockOpt(ASocket: THandle; ALevel, AOptionName: Integer;
  const AOptionValue; AOptionLen: Integer): Integer;
begin
  {$IFDEF POSIX}
  Result := Posix.SysSocket.setsockopt(ASocket, ALevel, AOptionName, AOptionValue, Cardinal(AOptionLen));
  {$ELSE}
  Result := Net.Winsock2.setsockopt(ASocket, ALevel, AOptionName, PAnsiChar(@AOptionValue), AOptionLen);
  {$ENDIF}
end;

class function TSocketAPI.SetSockOpt<T>(ASocket: THandle; ALevel,
  AOptionName: Integer; const AOptionValue: T): Integer;
begin
  Result := SetSockOpt(ASocket, ALevel, AOptionName, AOptionValue, SizeOf(T));
end;

class function TSocketAPI.SetTcpNoDelay(ASocket: THandle;
  ANoDelay: Boolean): Integer;
var
  LOptVal: Integer;
begin
  if ANoDelay then
    LOptVal := 1
  else
    LOptVal := 0;
  Result := TSocketAPI.SetSockOpt(ASocket, IPPROTO_TCP, TCP_NODELAY, LOptVal, SizeOf(Integer));
end;

class function TSocketAPI.Writeable(ASocket: THandle;
  ATimeout: Integer): Integer;
var
  {$IFDEF POSIX}
  LFDSet: fd_set;
  LTime_val: timeval;
  {$ELSE}
  LFDSet: TFDSet;
  LTime_val: TTimeval;
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

  {$IFDEF POSIX}
  FD_ZERO(LFDSet);
  _FD_SET(ASocket, LFDSet);
  Result := Posix.SysSelect.select(0, nil, @LFDSet, nil, P);
  {$ELSE}
  FD_ZERO(LFDSet);
  FD_SET(ASocket, LFDSet);
  Result := Net.Winsock2.select(0, nil, @LFDSet, nil, P);
  {$ENDIF}
end;

end.
