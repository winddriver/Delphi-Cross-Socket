{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com) QQ:21305383         }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.IocpLoop;

interface

uses
  System.SysUtils, System.Classes, Net.SocketAPI, Net.CrossSocket.EventLoop,
  Winapi.Windows, Net.Winsock2, Net.Wship6;

type
  TIocpLoop = class(TAbstractEventLoop)
  private const
    SHUTDOWN_FLAG = ULONG_PTR(-1);
    SO_UPDATE_CONNECT_CONTEXT = $7010;
  private type
    TAddrUnion = record
      case Integer of
        0: (IPv4: TSockAddrIn);
        1: (IPv6: TSockAddrIn6);
    end;

    TAddrBuffer = record
      Addr: TAddrUnion;
      Extra: array [0..15] of Byte;
    end;

    TAcceptExBuffer = array[0..SizeOf(TAddrBuffer) * 2 - 1] of Byte;

    TPerIoBufUnion = record
      case Integer of
        0: (DataBuf: WSABUF);
        // 这个Buffer只用于AcceptEx保存终端地址数据，大小为2倍地址结构
        1: (AcceptExBuffer: TAcceptExBuffer);
    end;

    TIocpAction = (ioAccept, ioConnect, ioReadZero, ioSend);

    PPerIoData = ^TPerIoData;
    TPerIoData = record
      Overlapped: TWSAOverlapped;
      Buffer: TPerIoBufUnion;
      Action: TIocpAction;
      Socket: THandle;
      Callback: TProc<Boolean>;

      case Integer of
        1: (Accept:
              record
                ai_family, ai_socktype, ai_protocol: Integer;
              end);
    end;
  private
    FIocpHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FIoThreadHandles: TArray<THandle>;

    function NewIoData: PPerIoData;
    procedure FreeIoData(P: PPerIoData);

    procedure NewAccept(ASocket: THandle; ai_family, ai_socktype, ai_protocol: Integer);
    function NewReadZero(ASocket: THandle): Boolean;

    procedure RequestAcceptComplete(ASocket: THandle; APerIoData: PPerIoData);
    procedure RequestConnectComplete(ASocket: THandle; APerIoData: PPerIoData);
    procedure RequestReadZeroComplete(ASocket: THandle; APerIoData: PPerIoData);
    procedure RequestSendComplete(ASocket: THandle; APerIoData: PPerIoData);
  protected
    procedure TriggerConnected(ASocket: THandle; AConnectType: Integer); override;
    procedure TriggerDisconnected(ASocket: THandle); override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    function Listen(const AHost: string; APort: Word;
      const ACallback: TProc<Boolean> = nil): Integer; override;
    function Connect(const AHost: string; APort: Word;
      const ACallback: TProc<Boolean> = nil): Integer; override;
    function Send(ASocket: THandle; const ABuf; ALen: Integer;
      const ACallback: TProc<Boolean> = nil): Integer; override;

    function ProcessIoEvent: Boolean; override;
  end;

implementation

{ TIocpLoop }

function TIocpLoop.NewIoData: PPerIoData;
begin
  System.New(Result);
  FillChar(Result^, SizeOf(TPerIoData), 0);
end;

procedure TIocpLoop.FreeIoData(P: PPerIoData);
begin
  System.Dispose(P);
end;

procedure TIocpLoop.NewAccept(ASocket: THandle; ai_family, ai_socktype,
  ai_protocol: Integer);
var
  LClientSocket: THandle;
  LPerIoData: PPerIoData;
  LBytes: Cardinal;
begin
  LClientSocket := WSASocket(ai_family, ai_socktype, ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
  if (LClientSocket = INVALID_SOCKET) then
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}
    Exit;
  end;

  TSocketAPI.SetNonBlock(LClientSocket, True);
  TSocketAPI.SetReUseAddr(LClientSocket, True);
  SetKeepAlive(LClientSocket);

  LPerIoData := NewIoData;
  LPerIoData.Action := ioAccept;
  LPerIoData.Socket := LClientSocket;
  LPerIoData.Accept.ai_family := ai_family;
  LPerIoData.Accept.ai_socktype := ai_socktype;
  LPerIoData.Accept.ai_protocol := ai_protocol;
  if (not AcceptEx(ASocket, LClientSocket, @LPerIoData.Buffer.AcceptExBuffer, 0,
    SizeOf(TAddrBuffer), SizeOf(TAddrBuffer), LBytes, POverlapped(LPerIoData)))
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    FreeIoData(LPerIoData);
  end;
end;

function TIocpLoop.NewReadZero(ASocket: THandle): Boolean;
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := NewIoData;
  LPerIoData.Buffer.DataBuf.buf := nil;
  LPerIoData.Buffer.DataBuf.len := 0;
  LPerIoData.Action := ioReadZero;
  LPerIoData.Socket := ASocket;

  LFlags := 0;
  LBytes := 0;
  if (WSARecv(ASocket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    FreeIoData(LPerIoData);
    Exit(False);
  end;

  Result := True;
end;

procedure TIocpLoop.RequestAcceptComplete(ASocket: THandle;
  APerIoData: PPerIoData);
begin
  NewAccept(ASocket, APerIoData.Accept.ai_family, APerIoData.Accept.ai_socktype,
    APerIoData.Accept.ai_protocol);

  if (TSocketAPI.SetSockOpt(APerIoData.Socket, SOL_SOCKET,
    SO_UPDATE_ACCEPT_CONTEXT, ASocket, SizeOf(THandle)) < 0) then
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}
    TSocketAPI.CloseSocket(APerIoData.Socket);
    Exit;
  end;

  if (CreateIoCompletionPort(APerIoData.Socket, FIocpHandle, ULONG_PTR(APerIoData.Socket), 0) = 0) then
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}
    TSocketAPI.CloseSocket(APerIoData.Socket);
    Exit;
  end;

  if NewReadZero(APerIoData.Socket) then
    TriggerConnected(APerIoData.Socket, CT_ACCEPT)
  else
    TSocketAPI.CloseSocket(APerIoData.Socket);
end;

procedure TIocpLoop.RequestConnectComplete(ASocket: THandle;
  APerIoData: PPerIoData);
  procedure _Success;
  begin
    TriggerConnected(ASocket, CT_CONNECT);
    if Assigned(APerIoData.Callback) then
      APerIoData.Callback(True);
  end;

  procedure _Failed;
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}
    TSocketAPI.CloseSocket(ASocket);
    TriggerConnectFailed(ASocket);
    if Assigned(APerIoData.Callback) then
      APerIoData.Callback(False);
  end;
var
  LOptVal: Integer;
begin
  if (TSocketAPI.GetError(ASocket) <> 0) then
  begin
    _Failed;
    Exit;
  end;

  // 不设置该参数, 会导致 getpeername 调用失败
  LOptVal := 1;
  if (TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET,
    SO_UPDATE_CONNECT_CONTEXT, LOptVal, SizeOf(Integer)) < 0) then
  begin
    _Failed;
    Exit;
  end;

  if NewReadZero(ASocket) then
    _Success
  else
    _Failed;
end;

procedure TIocpLoop.RequestReadZeroComplete(ASocket: THandle;
  APerIoData: PPerIoData);
var
  LRcvd: Integer;
begin
  while True do
  begin
    LRcvd := TSocketAPI.Recv(ASocket, FRecvBuf[0], RCV_BUF_SIZE);

    // 对方主动断开连接
    if (LRcvd = 0) then
    begin
      if (TSocketAPI.CloseSocket(ASocket) = 0) then
        TriggerDisconnected(ASocket);
      Exit;
    end;

    if (LRcvd < 0) then
    begin
      // 需要重试
      if _Again(GetLastError) then Break;

      if (TSocketAPI.CloseSocket(ASocket) = 0) then
        TriggerDisconnected(ASocket);

      Exit;
    end;

    TriggerReceived(ASocket, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;

  if not NewReadZero(ASocket) then
  begin
    if (TSocketAPI.CloseSocket(ASocket) = 0) then
      TriggerDisconnected(ASocket);
  end;
end;

procedure TIocpLoop.RequestSendComplete(ASocket: THandle;
  APerIoData: PPerIoData);
begin
  if Assigned(APerIoData.Callback) then
  begin
    APerIoData.Callback(True);
    APerIoData.Callback := nil;
  end;
end;

procedure TIocpLoop.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  FIocpHandle := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  SetLength(FIoThreads, GetIoThreads);
  SetLength(FIoThreadHandles, Length(FIoThreads));
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    FIoThreads[I] := TIoEventThread.Create(Self);
    FIoThreadHandles[I] := FIoThreads[I].Handle;
  end;
end;

procedure TIocpLoop.StopLoop;
var
  I: Integer;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (FListensCount > 0) or (FConnectionsCount > 0) do Sleep(1);

  for I := 0 to Length(FIoThreads) - 1 do
    PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));
  WaitForMultipleObjects(Length(FIoThreadHandles), Pointer(FIoThreadHandles), True, INFINITE);
  CloseHandle(FIocpHandle);
  for I := 0 to Length(FIoThreads) - 1 do
    FreeAndNil(FIoThreads[I]);
  FIoThreads := nil;
  FIoThreadHandles := nil;
end;

procedure TIocpLoop.TriggerConnected(ASocket: THandle; AConnectType: Integer);
begin
end;

procedure TIocpLoop.TriggerDisconnected(ASocket: THandle);
begin
end;

function TIocpLoop.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<Boolean>): Integer;
  procedure _Failed1;
  begin
    TriggerConnectFailed(INVALID_HANDLE_VALUE);
    if Assigned(ACallback) then
      ACallback(False);
  end;

  function _Connect(ASocket: THandle; Addr: PRawAddrInfo): Boolean;
    procedure _Failed2;
    begin
      TSocketAPI.CloseSocket(ASocket);
      TriggerConnectFailed(ASocket);
      if Assigned(ACallback) then
        ACallback(False);
    end;
  var
    LSockAddr: TRawSockAddrIn;
    LPerIoData: PPerIoData;
    LBytes: Cardinal;
  begin
    LSockAddr.AddrLen := Addr.ai_addrlen;
    Move(Addr.ai_addr^, LSockAddr.Addr, Addr.ai_addrlen);
    if (Addr.ai_family = AF_INET6) then
    begin
      LSockAddr.Addr6.sin6_addr := in6addr_any;
      LSockAddr.Addr6.sin6_port := 0;
    end else
    begin
      LSockAddr.Addr.sin_addr.S_addr := INADDR_ANY;
      LSockAddr.Addr.sin_port := 0;
    end;
    if (TSocketAPI.Bind(ASocket, @LSockAddr.Addr, LSockAddr.AddrLen) < 0) then
    begin
      _Failed2;
      Exit(False);
    end;

    if (CreateIoCompletionPort(ASocket, FIocpHandle, ULONG_PTR(ASocket), 0) = 0) then
    begin
      _Failed2;
      Exit(False);
    end;

    LPerIoData := NewIoData;
    LPerIoData.Action := ioConnect;
    LPerIoData.Socket := ASocket;
    LPerIoData.Callback := ACallback;
    if not ConnectEx(ASocket, Addr.ai_addr, Addr.ai_addrlen, nil, 0, LBytes, PWSAOverlapped(LPerIoData)) and
      (WSAGetLastError <> WSA_IO_PENDING) then
    begin
      FreeIoData(LPerIoData);
      _Failed2;
      Exit(False);
    end;

    Result := True;
  end;
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;
begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed1;
    Exit(-1);
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
      if (LSocket = INVALID_SOCKET) then
      begin
        _Failed1;
        Exit(-1);
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      TSocketAPI.SetReUseAddr(LSocket, True);
      SetKeepAlive(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit(0);

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
  Result := -1;
end;

function TIocpLoop.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<Boolean>): Integer;
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;
  I: Integer;

  procedure _Failed;
  begin
    if (LSocket <> INVALID_HANDLE_VALUE) then
      TSocketAPI.CloseSocket(LSocket);

    if Assigned(ACallback) then
      ACallback(False);
  end;

  procedure _Success;
  begin
    if Assigned(ACallback) then
      ACallback(True);

    TriggerListened(LSocket);
  end;

begin
  LSocket := INVALID_SOCKET;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed;
    Exit(-1);
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
      if (LSocket = INVALID_SOCKET) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        _Failed;
        Exit(-1);
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      TSocketAPI.SetReUseAddr(LSocket, True);

      if (TSocketAPI.Bind(LSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        _Failed;
        Exit(-1);
      end;

      if (TSocketAPI.Listen(LSocket) < 0) then
      begin
        _Failed;
        Exit(-1);
      end;

      if (CreateIoCompletionPort(LSocket, FIocpHandle, ULONG_PTR(LSocket), 0) = 0) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        _Failed;
        Exit(-1);
      end;

      // 给每个IO线程投递一个AcceptEx
      for I := 1 to GetIoThreads do
        NewAccept(LSocket, LAddrInfo.ai_family, LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);

      _Success;

      // 如果端口传入0，让所有地址统一用首个分配到的端口
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        LAddrInfo.ai_next.ai_addr.sin_port := LAddrInfo.ai_addr.sin_port;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  Result := 0;
end;

function TIocpLoop.Send(ASocket: THandle; const ABuf; ALen: Integer;
  const ACallback: TProc<Boolean>): Integer;
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := NewIoData;
  LPerIoData.Buffer.DataBuf.buf := @ABuf;
  LPerIoData.Buffer.DataBuf.len := ALen;
  LPerIoData.Action := ioSend;
  LPerIoData.Socket := ASocket;
  LPerIoData.Callback := ACallback;

  LFlags := 0;
  LBytes := 0;
  // WSASend 不会出现部分发送的情况, 要么全部失败, 要么全部成功
  // 所以不需要像 kqueue 或 epoll 中调用 send 那样调用完之后还得检查实际发送了多少
  // 唯一需要注意的是: WSASend 会将待发送的数据锁定到非页面内存, 非页面内存资源
  // 是非常紧张的, 所以不要无节制的调用 WSASend, 最好通过回调发送完一批数据再继
  // 续发送下一批
  if (WSASend(ASocket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    if Assigned(LPerIoData.Callback) then
      LPerIoData.Callback(False);

    // 出错多半是 WSAENOBUFS, 也就是投递的 WSASend 过多, 来不及发送
    // 导致非页面内存资源全部被锁定, 要避免这种情况必须上层发送逻辑
    // 保证不能无节制的调用Send发送大量数据, 最好发送完一个再继续下
    // 一个, 本函数提供了发送结果的回调函数, 在回调函数报告发送成功
    // 之后就可以继续下一块数据发送了
    FreeIoData(LPerIoData);
    if (TSocketAPI.CloseSocket(ASocket) = 0) then
      TriggerDisconnected(ASocket);
    Exit(-1);
  end;

  Result := ALen;
end;

function TIocpLoop.ProcessIoEvent: Boolean;
var
  LBytes: Cardinal;
  LSocket: THandle;
  LPerIoData: PPerIoData;
begin
  if not GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), INFINITE) then
  begin
    // 出错了, 并且完成数据也都是空的,
    // 这种情况即便重试, 应该也会继续出错, 最好立即终止IO线程
    if (LSocket = 0) or (LPerIoData = nil) then
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}
      Exit(False);
    end;

    try
      case LPerIoData.Action of
        ioAccept:
          // WSA_OPERATION_ABORTED, 995, 由于线程退出或应用程序请求，已中止 I/O 操作。
          // WSAENOTSOCK, 10038, 在一个非套接字上尝试了一个操作。
          // 在主动关闭监听的socket时会出现该错误, 这时候只需要简单的关掉
          // AcceptEx对应的客户端socket即可
          TSocketAPI.CloseSocket(LPerIoData.Socket);

        ioConnect:
          // ERROR_CONNECTION_REFUSED, 1225, 远程计算机拒绝网络连接。
          if (TSocketAPI.CloseSocket(LSocket) = 0) then
          begin
            TriggerConnectFailed(LSocket);
            if Assigned(LPerIoData.Callback) then
              LPerIoData.Callback(False);
          end;

        ioReadZero:
          if (TSocketAPI.CloseSocket(LSocket) = 0) then
            TriggerDisconnected(LSocket);

        ioSend:
          begin
            if Assigned(LPerIoData.Callback) then
            begin
              LPerIoData.Callback(False);
              LPerIoData.Callback := nil;
            end;

            if (TSocketAPI.CloseSocket(LSocket) = 0) then
              TriggerDisconnected(LSocket);
          end;
      end;
    finally
      FreeIoData(LPerIoData);
    end;

    // 出错了, 但是完成数据不是空的, 需要重试
    Exit(True);
  end;

  // 主动调用了 StopLoop
  if (LBytes = 0) and (ULONG_PTR(LPerIoData) = SHUTDOWN_FLAG) then Exit(False);

  // 由于未知原因未获取到完成数据, 但是返回的错误代码又是正常
  // 这种情况需要进行重试(返回True之后IO线程会再次调用ProcessIoEvent)
  if (LSocket = 0) or (LPerIoData = nil) then Exit(True);

  try
    case LPerIoData.Action of
      ioAccept  : RequestAcceptComplete(LSocket, LPerIoData);
      ioConnect : RequestConnectComplete(LSocket, LPerIoData);
      ioReadZero: RequestReadZeroComplete(LSocket, LPerIoData);
      ioSend    : RequestSendComplete(LSocket, LPerIoData);
    end;
  finally
    FreeIoData(LPerIoData);
  end;

  Result := True;
end;

end.
