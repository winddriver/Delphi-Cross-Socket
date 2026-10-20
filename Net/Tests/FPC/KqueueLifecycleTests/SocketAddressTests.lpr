program SocketAddressTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils,
  {$IFDEF MSWINDOWS}Net.Winsock2,{$ELSE}
    {$IFDEF FPC}BaseUnix, Sockets, NetDB,{$ELSE}
    Posix.SysSocket, Posix.NetinetIn, Posix.ArpaInet, Posix.NetDB,{$ENDIF}
  {$ENDIF}
  Net.SocketAPI;

procedure Check(const Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure TestLayout;
var Info: TRawAddrInfo; CanonOffset, AddrOffset, NextOffset: NativeUInt;
begin
  CanonOffset := NativeUInt(@Info.ai_canonname) - NativeUInt(@Info);
  AddrOffset := NativeUInt(@Info.ai_addr) - NativeUInt(@Info);
  NextOffset := NativeUInt(@Info.ai_next) - NativeUInt(@Info);
  Writeln('ABI pointer=', SizeOf(Pointer), ' addrinfo=', SizeOf(Info),
    ' addrlen=', SizeOf(Info.ai_addrlen), ' canon=', CanonOffset,
    ' addr=', AddrOffset, ' next=', NextOffset);
  {$IF DEFINED(FPC) AND DEFINED(DARWIN)}
  Check(SizeOf(Info.ai_addrlen) = 4, 'Darwin socklen_t must be 32 bits');
  if SizeOf(Pointer) = 8 then
    Check((SizeOf(Info) = 48) and (CanonOffset = 24) and (AddrOffset = 32)
      and (NextOffset = 40), 'Darwin 64-bit addrinfo does not match netdb.h')
  else
    Check((SizeOf(Info) = 32) and (CanonOffset = 20) and (AddrOffset = 24)
      and (NextOffset = 28), 'Darwin 32-bit addrinfo does not match netdb.h');
  Check((Net.SocketAPI.NI_NOFQDN = 1) and (Net.SocketAPI.NI_NUMERICHOST = 2)
    and (Net.SocketAPI.NI_NAMEREQD = 4) and (Net.SocketAPI.NI_NUMERICSERV = 8)
    and (Net.SocketAPI.NI_DGRAM = $10), 'Darwin NI flags do not match netdb.h');
  {$ENDIF}
end;

procedure TestNumericExtract;
var Addr: TRawSockAddrIn; IP: string; Port: Word; I: Integer;
begin
  // 独立构造sockaddr，不经过自定义addrinfo布局；80/443必须返回数字而非服务名。
  FillChar(Addr, SizeOf(Addr), 0);
  {$IF DEFINED(DARWIN)}Addr.Addr.sin_len := SizeOf(Addr.Addr);{$ENDIF}
  Addr.Addr.sin_family := AF_INET;
  Addr.Addr.sin_addr.s_addr := htonl($7f000001);
  for I := 0 to 1 do
  begin
    if I = 0 then Addr.Addr.sin_port := htons(80) else Addr.Addr.sin_port := htons(443);
    IP := ''; Port := 0;
    TSocketAPI.ExtractAddrInfo(@Addr.Addr, SizeOf(Addr.Addr), IP, Port);
    Check(IP = '127.0.0.1', 'numeric host differs');
    if I = 0 then Check(Port = 80, 'port 80 resolved as a service name')
    else Check(Port = 443, 'port 443 resolved as a service name');
    Writeln('NUMERIC ', IP, ':', Port);
  end;
end;

procedure TestLoopback(const Family: Integer; const Host: string);
var
  Hints: TRawAddrInfo;
  Info: PRawAddrInfo;
  BoundAddr, PeerAddr: TRawSockAddrIn;
  Listener, Client, Peer: TSocket;
  BoundLen, PeerLen, ConnectResult: Integer;
  IP: string;
  Port: Word;
  Sent, Received: Byte;
begin
  Listener := INVALID_SOCKET; Client := INVALID_SOCKET; Peer := INVALID_SOCKET;
  FillChar(Hints, SizeOf(Hints), 0);
  Hints.ai_family := Family;
  Hints.ai_socktype := SOCK_STREAM;
  Hints.ai_protocol := IPPROTO_TCP;
  Hints.ai_flags := 0;
  Info := TSocketAPI.GetAddrInfo(Host, 0, Hints);
  Check(Info <> nil, 'numeric getaddrinfo failed: ' + Host);
  try
    Check((Info.ai_family = Family) and (Info.ai_addr <> nil)
      and (Info.ai_addrlen > 0), 'addrinfo returned unusable sockaddr: ' + Host);
    IP := ''; Port := 1;
    TSocketAPI.ExtractAddrInfo(Info.ai_addr, Info.ai_addrlen, IP, Port);
    Check((IP = Host) and (Port = 0), 'numeric addrinfo roundtrip differs: ' + Host);
    Listener := TSocketAPI.NewSocket(Family, SOCK_STREAM, IPPROTO_TCP);
    Check(Listener <> INVALID_SOCKET, 'listener socket failed');
    Check(TSocketAPI.Bind(Listener, Info.ai_addr, Info.ai_addrlen) = 0, 'real bind failed: ' + Host);
    Check(TSocketAPI.Listen(Listener) = 0, 'real listen failed: ' + Host);
    FillChar(BoundAddr, SizeOf(BoundAddr), 0); BoundLen := SizeOf(BoundAddr.Addr6);
    Check(TSocketAPI.GetSockName(Listener, @BoundAddr.Addr, BoundLen) = 0, 'getsockname failed');
    TSocketAPI.ExtractAddrInfo(@BoundAddr.Addr, BoundLen, IP, Port);
    Check((IP = Host) and (Port <> 0), 'bound numeric address missing');

    Client := TSocketAPI.NewSocket(Family, SOCK_STREAM, IPPROTO_TCP);
    Check(Client <> INVALID_SOCKET, 'client socket failed');
    Check(TSocketAPI.SetNonBlock(Client, True) = 0, 'nonblocking connect setup failed');
    ConnectResult := TSocketAPI.Connect(Client, @BoundAddr.Addr, BoundLen);
    if ConnectResult <> 0 then
      Check((TSocketAPI.Writeable(Client, 3000) > 0) and (TSocketAPI.GetError(Client) = 0),
        'real connect failed: ' + Host);
    Check(TSocketAPI.Readable(Listener, 3000) > 0, 'real accept timeout');
    FillChar(PeerAddr, SizeOf(PeerAddr), 0); PeerLen := SizeOf(PeerAddr.Addr6);
    Peer := TSocketAPI.Accept(Listener, @PeerAddr.Addr, @PeerLen);
    Check(Peer <> INVALID_SOCKET, 'real accept failed');
    Sent := $5a;
    Check(TSocketAPI.Send(Client, Sent, 1) = 1, 'client send failed');
    Check(TSocketAPI.Readable(Peer, 3000) > 0, 'server receive timeout');
    Check((TSocketAPI.Recv(Peer, Received, 1) = 1) and (Received = Sent), 'server data differs');
    Sent := $a5;
    Check(TSocketAPI.Send(Peer, Sent, 1) = 1, 'server send failed');
    Check(TSocketAPI.Readable(Client, 3000) > 0, 'client receive timeout');
    Check((TSocketAPI.Recv(Client, Received, 1) = 1) and (Received = Sent), 'client data differs');
    Writeln('LOOPBACK ', IP, ':', Port, ' connect/accept/echo OK');
  finally
    if Peer <> INVALID_SOCKET then TSocketAPI.CloseSocket(Peer);
    if Client <> INVALID_SOCKET then TSocketAPI.CloseSocket(Client);
    if Listener <> INVALID_SOCKET then TSocketAPI.CloseSocket(Listener);
    TSocketAPI.FreeAddrInfo(Info);
  end;
end;

var Mode: string;
begin
  try
    Mode := ParamStr(1);
    if Mode = '' then Mode := 'all';
    Check((Mode = 'all') or (Mode = 'abi') or (Mode = 'numeric')
      or (Mode = 'ipv4') or (Mode = 'ipv6'), 'mode must be all/abi/numeric/ipv4/ipv6');
    if (Mode = 'all') or (Mode = 'abi') then TestLayout;
    if (Mode = 'all') or (Mode = 'numeric') then TestNumericExtract;
    if (Mode = 'all') or (Mode = 'ipv4') then TestLoopback(AF_INET, '127.0.0.1');
    if (Mode = 'all') or (Mode = 'ipv6') then TestLoopback(AF_INET6, '::1');
    Writeln('PASS socket-address ', Mode);
  except
    on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
