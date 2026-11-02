unit Net.RawSocket;

{$I zLib.inc}

interface

uses
  SysUtils, Net.SocketAPI,
  {$IFDEF POSIX}
    {$IFDEF FPC}Sockets, BaseUnix, cNetDB{$ELSE}Posix.Base, Posix.SysSocket, Posix.NetinetIn, Posix.NetDB{$ENDIF}
  {$ELSE}
    Windows, Net.Winsock2, Net.Wship6
  {$ENDIF};

type
  /// <summary>
  ///   简单的套接字操作类
  /// </summary>
  TRawSocket = class
  private
    FSocket: THandle;
    FSockAddr: TRawSockAddrIn;
    FPeerAddr: string;
    FPeerPort: Word;
    function _Open(const AHost: string; APort: Word; ABind: Boolean): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    ///   关闭 Socket
    /// </summary>
    procedure Close;
    /// <summary>
    ///   连接到主机, 支持 IPv6
    /// </summary>
    function Connect(const AHost: string; APort: Word): Integer;
    /// <summary>
    ///   绑定 Socket 到指定地址和端口, 支持 IPv6
    /// </summary>
    function Bind(const Addr: string; APort: Word): Integer;
    /// <summary>
    ///   启动监听
    /// </summary>
    function Listen(backlog: Integer = SOMAXCONN): Integer;
    /// <summary>
    ///   接受一个连接请求, 并分配 Socket
    /// </summary>
    function Accept(Addr: PSockAddr; AddrLen: PInteger): THandle;
    /// <summary>
    ///   接收数据
    /// </summary>
    function Recv(var Buf; len: Integer; flags: Integer = 0): Integer;
    /// <summary>
    ///   发送数据
    /// </summary>
    function Send(const Buf; len: Integer; flags: Integer = 0): Integer;
    /// <summary>
    ///    接收数据从指定地址端口(用于UDP)
    /// </summary>
    function RecvFrom(const Addr: PSockAddr; var AddrLen: Integer; var Buf;
      len: Integer; flags: Integer = 0): Integer;
    /// <summary>
    ///    发送数据到指定地址端口(用于UDP)
    /// </summary>
    function SendTo(const Addr: PSockAddr; AddrLen: Integer; const Buf;
      len: Integer; flags: Integer = 0): Integer;
    /// <summary>
    ///    判断套接字是否有效
    /// </summary>
    function IsValid: Boolean;
    /// <summary>
    ///    套接字句柄
    /// </summary>
    property Socket: THandle read FSocket;
    /// <summary>
    ///    套接字地址信息
    ///    如果是 Connect 到远端的套接字, 则该地址保存的是远端地址信息
    ///    如果是 Bind 到本地的套接字, 则该地址保存的是本地地址信息
    /// </summary>
    property SockAddr: TRawSockAddrIn read FSockAddr;
    property PeerAddr: string read FPeerAddr;
    property PeerPort: Word read FPeerPort;
  end;

implementation

{ TRawSocket }

constructor TRawSocket.Create;
begin
  inherited Create;
  FSocket := THandle(INVALID_SOCKET);
end;

destructor TRawSocket.Destroy;
begin
  Close;
  inherited;
end;

procedure TRawSocket.Close;
begin
  if (FSocket = THandle(INVALID_SOCKET)) then Exit;
  TSocketAPI.CloseSocket(FSocket);
  FSocket := THandle(INVALID_SOCKET);
end;

function TRawSocket._Open(const AHost: string; APort: Word; ABind: Boolean): Integer;
var
  LHints: TRawAddrInfo;
  LAddresses, LAddr: PRawAddrInfo;
  LSocket: TSocket;
  LAddress: TRawSockAddrIn;
  LText: string;
  LPort: Word;
begin
  Result := -1;
  if ABind and IsValid then Exit;
  FillChar(LHints, SizeOf(LHints), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  if ABind then LHints.ai_flags := AI_PASSIVE;
  LAddresses := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if LAddresses = nil then Exit;
  try
    LAddr := LAddresses;
    while LAddr <> nil do
    begin
      LSocket := TSocketAPI.NewSocket(LAddr.ai_family, LAddr.ai_socktype, LAddr.ai_protocol);
      if LSocket <> INVALID_SOCKET then
      try
        if ABind then
          Result := TSocketAPI.Bind(LSocket, PSockAddr(LAddr.ai_addr), LAddr.ai_addrlen)
        else
        begin
          TSocketAPI.SetKeepAlive(LSocket, 5, 3, 5);
          Result := TSocketAPI.Connect(LSocket, PSockAddr(LAddr.ai_addr), LAddr.ai_addrlen);
        end;
        if Result = 0 then
        begin
          FillChar(LAddress, SizeOf(LAddress), 0);
          LAddress.AddrLen := SizeOf(LAddress.Addr6);
          if ABind then
            Result := TSocketAPI.GetSockName(LSocket, @LAddress.Addr, LAddress.AddrLen)
          else
            Result := TSocketAPI.GetPeerName(LSocket, @LAddress.Addr, LAddress.AddrLen);
          if Result = 0 then
          begin
            TSocketAPI.ExtractAddrInfo(@LAddress.Addr, LAddress.AddrLen, LText, LPort);
            Close;
            FSockAddr := LAddress;
            FPeerAddr := LText;
            FPeerPort := LPort;
            FSocket := LSocket;
            LSocket := INVALID_SOCKET;
            Exit;
          end;
        end;
      finally
        if LSocket <> INVALID_SOCKET then TSocketAPI.CloseSocket(LSocket);
      end;
      LAddr := PRawAddrInfo(LAddr.ai_next);
    end;
  finally TSocketAPI.FreeAddrInfo(LAddresses); end;
end;

function TRawSocket.Connect(const AHost: string; APort: Word): Integer;
begin
  Result := _Open(AHost, APort, False);
end;

function TRawSocket.Bind(const Addr: string; APort: Word): Integer;
begin
  Result := _Open(Addr, APort, True);
end;

function TRawSocket.Listen(backlog: Integer): Integer;
begin
  Result := TSocketAPI.Listen(FSocket, backlog);
end;

function TRawSocket.Accept(Addr: PSockAddr; AddrLen: PInteger): THandle;
begin
  Result := TSocketAPI.Accept(FSocket, Addr, AddrLen);
end;

function TRawSocket.Recv(var Buf; len, flags: Integer): Integer;
begin
  Result := TSocketAPI.Recv(FSocket, Buf, len, flags);
end;

function TRawSocket.Send(const Buf; len, flags: Integer): Integer;
begin
  Result := TSocketAPI.Send(FSocket, Buf, len, flags);
end;

function TRawSocket.RecvFrom(const Addr: PSockAddr; var AddrLen: Integer;
  var Buf; len, flags: Integer): Integer;
begin
  Result := TSocketAPI.RecvFrom(FSocket, Addr, AddrLen, Buf, len, flags);
end;

function TRawSocket.SendTo(const Addr: PSockAddr; AddrLen: Integer; const Buf;
  len: Integer; flags: Integer): Integer;
begin
  Result := TSocketAPI.SendTo(FSocket, Addr, AddrLen, Buf, len, flags);
end;

function TRawSocket.IsValid: Boolean;
begin
  Result := TSocketAPI.IsValidSocket(FSocket);
end;

end.
