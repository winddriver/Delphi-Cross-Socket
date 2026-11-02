program ConnectFailureTests;
{$I ../../../../zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes,
  {$IFDEF MSWINDOWS}Net.Winsock2,{$ELSE}
    {$IFDEF FPC}Sockets, BaseUnix,{$ELSE}Posix.SysSocket, Posix.NetinetIn, Posix.ArpaInet, Posix.SysTime,{$ENDIF}
  {$ENDIF}
  Net.SocketAPI, Net.RawSocket, Net.CrossSocket.Base, Net.CrossSocket;

type
  TObservedSocket = class(TCrossSocket)
  public
    CreatedConnections: Integer;
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
  end;

function TObservedSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType; const AHost: string;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Inc(CreatedConnections);
  Result := inherited CreateConnection(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
end;

procedure Check(const Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure TestRawSocket;
var
  LServer, LClient: TRawSocket;
  LAccepted: TSocket;
  LType: Integer;
  LValue: {$IFDEF MSWINDOWS}Cardinal{$ELSE}timeval{$ENDIF};
begin
  LServer := TRawSocket.Create;
  LClient := TRawSocket.Create;
  try
    Check(not LServer.IsValid, '新对象不应持有套接字');
    LServer.Close;
    Check(LServer.Bind('127.0.0.1', 0) = 0, '绑定失败');
    Check((LServer.PeerPort > 0) and (LServer.Listen = 0), '未取得真实监听端口');
    LType := 0;
    Check((TSocketAPI.GetSockOpt<Integer>(LServer.Socket, SOL_SOCKET, SO_TYPE, LType) = 0)
      and (LType = SOCK_STREAM), '无法读取套接字类型');
    Check(TSocketAPI.SetRecvTimeout(LServer.Socket, 1250) = 0, '接收超时设置失败');
    Check(TSocketAPI.SetSendTimeout(LServer.Socket, 1250) = 0, '发送超时设置失败');
    Check(TSocketAPI.GetSockOpt<{$IFDEF MSWINDOWS}Cardinal{$ELSE}timeval{$ENDIF}>(
      LServer.Socket, SOL_SOCKET, SO_RCVTIMEO, LValue) = 0, '读取超时失败');
    {$IFDEF MSWINDOWS}Check(LValue = 1250, '超时毫秒错误');
    {$ELSE}Check((LValue.tv_sec = 1) and (LValue.tv_usec >= 250000) and (LValue.tv_usec < 270000),
      '超时换算错误 ' + IntToStr(LValue.tv_sec) + '/' + IntToStr(LValue.tv_usec));{$ENDIF}
    Check(LClient.Connect('127.0.0.1', LServer.PeerPort) = 0, '连接失败');
    LAccepted := LServer.Accept(nil, nil);
    Check(LAccepted <> INVALID_SOCKET, '无法接入连接');
    TSocketAPI.CloseSocket(LAccepted);
    LClient.Close;
    LServer.Close;
    Check(not LClient.IsValid and not LServer.IsValid, '关闭后句柄仍有效');
  finally
    LClient.Free;
    LServer.Free;
  end;
end;

procedure Run;
var
  Hints: TRawAddrInfo;
  Addresses, Next: PRawAddrInfo;
  Port: Word;
  AddressCount, Calls, Successes, NonNil, I, Attempts: Integer;
  Socket: TObservedSocket;
  Callback: TCrossConnectionCallback;
begin
  TestRawSocket;
  Attempts := StrToIntDef(ParamStr(1), 1);
  Check((Attempts > 0) and (Attempts <= 100), 'attempt count outside test bounds');
  Port := StrToInt(ParamStr(2));
  Check(Port <> 0, 'parent-held exclusive port required');
  Socket := nil;
  Calls := 0; Successes := 0; NonNil := 0;
  try
    // 监听由Python父进程独占持有直到子进程退出；本进程只执行被测Connect。
    Socket := TObservedSocket.Create(1);
    FillChar(Hints, SizeOf(Hints), 0);
    Hints.ai_family := AF_INET;
    Hints.ai_socktype := SOCK_STREAM;
    Hints.ai_protocol := IPPROTO_TCP;
    Addresses := TSocketAPI.GetAddrInfo('127.0.0.1', 0, Hints);
    Check(Addresses <> nil, 'numeric loopback address missing');
    try
      AddressCount := 0; Next := Addresses;
      while Next <> nil do begin Inc(AddressCount); Next := PRawAddrInfo(Next.ai_next); end;
      Check(AddressCount = 1, 'test must use exactly one numeric address');
    finally TSocketAPI.FreeAddrInfo(Addresses); end;
    Callback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        // 必须不抛异常：让外层地址循环继续，不能掩盖第二次通知。
        Inc(Calls);
        if OK then Inc(Successes);
        if C <> nil then Inc(NonNil);
      end;
    for I := 1 to Attempts do Socket.Connect('127.0.0.1', Port, Port, Callback);
    Socket.CloseAll;
    Socket.StopLoop;
    Writeln('OBSERVED attempts=', Attempts, ' callbacks=', Calls, ' successful=', Successes,
      ' nonnil=', NonNil, ' connection_objects=', Socket.CreatedConnections,
      ' numeric_addresses=', AddressCount, ' occupied_local_port=', Port);
    Check((Successes = 0) and (NonNil = 0) and (Socket.CreatedConnections = 0),
      'test did not fail before connection construction');
    Check(Calls = Attempts, 'pre-connection bind failure callback was not exactly once');
  finally
    Callback := nil;
    if Socket <> nil then begin Socket.CloseAll; Socket.StopLoop; Socket.Free; end;
  end;
end;

begin
  try Run; Writeln('PASS connect-failure');
  except on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
