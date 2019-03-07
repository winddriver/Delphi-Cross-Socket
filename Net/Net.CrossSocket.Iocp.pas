{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Iocp;

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Net.Winsock2,
  Net.Wship6,
  Net.SocketAPI,
  Net.CrossSocket.Base;

type
  TIocpListen = class(TAbstractCrossListen)
  end;

  TIocpConnection = class(TAbstractCrossConnection)
  end;

  TIocpCrossSocket = class(TAbstractCrossSocket)
  private const
    SHUTDOWN_FLAG = ULONG_PTR(-1);
    SO_UPDATE_CONNECT_CONTEXT = $7010;
    IPV6_V6ONLY = 27;
    ERROR_ABANDONED_WAIT_0 = $02DF;
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

    TIocpAction = (ioAccept, ioConnect, ioRead, ioWrite);

    PPerIoData = ^TPerIoData;
    TPerIoData = record
      Overlapped: TWSAOverlapped;
      Buffer: TPerIoBufUnion;
      Action: TIocpAction;
      Socket: THandle;
      CrossData: ICrossData;
      Callback: TProc<ICrossConnection, Boolean>;
    end;
  private
    FIocpHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FPerIoDataCount: NativeInt;

    function _NewIoData: PPerIoData; inline;
    procedure _FreeIoData(P: PPerIoData); inline;

    procedure _NewAccept(AListen: ICrossListen);
    function _NewReadZero(AConnection: ICrossConnection): Boolean;

    procedure _HandleAccept(APerIoData: PPerIoData);
    procedure _HandleConnect(APerIoData: PPerIoData);
    procedure _HandleRead(APerIoData: PPerIoData);
    procedure _HandleWrite(APerIoData: PPerIoData);
  protected
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossListen, Boolean> = nil); override;

    procedure Connect(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;

    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;

    function ProcessIoEvent: Boolean; override;
  end;

implementation

{ TIocpCrossSocket }

function TIocpCrossSocket._NewIoData: PPerIoData;
begin
  GetMem(Result, SizeOf(TPerIoData));
  FillChar(Result^, SizeOf(TPerIoData), 0);

  AtomicIncrement(FPerIoDataCount);
end;

procedure TIocpCrossSocket._FreeIoData(P: PPerIoData);
begin
  if (P = nil) then Exit;

  P.CrossData := nil;
  P.Callback := nil;
  FreeMem(P, SizeOf(TPerIoData));

  AtomicDecrement(FPerIoDataCount);
end;

procedure TIocpCrossSocket._NewAccept(AListen: ICrossListen);
var
  LClientSocket: THandle;
  LPerIoData: PPerIoData;
  LBytes: Cardinal;
begin
  LClientSocket := WSASocket(AListen.Family, AListen.SockType, AListen.Protocol,
    nil, 0, WSA_FLAG_OVERLAPPED);
  if (LClientSocket = INVALID_SOCKET) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._NewAccept.WSASocket');
    {$ENDIF}
    Exit;
  end;

  TSocketAPI.SetNonBlock(LClientSocket, True);
  SetKeepAlive(LClientSocket);

  LPerIoData := _NewIoData;
  LPerIoData.Action := ioAccept;
  LPerIoData.Socket := LClientSocket;
  LPerIoData.CrossData := AListen;

  if (not AcceptEx(AListen.Socket, LClientSocket, @LPerIoData.Buffer.AcceptExBuffer, 0,
    SizeOf(TAddrBuffer), SizeOf(TAddrBuffer), LBytes, POverlapped(LPerIoData)))
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._NewAccept.AcceptEx');
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    _FreeIoData(LPerIoData);
  end;
end;

function TIocpCrossSocket._NewReadZero(AConnection: ICrossConnection): Boolean;
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := _NewIoData;
  LPerIoData.Buffer.DataBuf.buf := nil;
  LPerIoData.Buffer.DataBuf.len := 0;
  LPerIoData.Action := ioRead;
  LPerIoData.Socket := AConnection.Socket;
  LPerIoData.CrossData := AConnection;

  LFlags := 0;
  LBytes := 0;
  if (WSARecv(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._NewReadZero.WSARecv');
    {$ENDIF}
    _FreeIoData(LPerIoData);
    Exit(False);
  end;

  Result := True;
end;

procedure TIocpCrossSocket._HandleAccept(APerIoData: PPerIoData);
var
  LListen: ICrossListen;
  LConnection: ICrossConnection;
  LClientSocket, LListenSocket: THandle;
begin
  if (APerIoData.CrossData = nil) then Exit;

  LListen := APerIoData.CrossData as ICrossListen;

  _NewAccept(LListen);

  LClientSocket := APerIoData.Socket;
  LListenSocket := LListen.Socket;

  // 不设置该参数, 会导致 getpeername 调用失败
  if (TSocketAPI.SetSockOpt<THandle>(LClientSocket, SOL_SOCKET,
    SO_UPDATE_ACCEPT_CONTEXT, LListenSocket) < 0) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleAccept.SetSockOpt');
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    Exit;
  end;

  if (CreateIoCompletionPort(LClientSocket, FIocpHandle, ULONG_PTR(LClientSocket), 0) = 0) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleAccept.CreateIoCompletionPort');
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    Exit;
  end;

  LConnection := CreateConnection(Self, LClientSocket, ctAccept);
  TriggerConnecting(LConnection);
  TriggerConnected(LConnection);

  if not _NewReadZero(LConnection) then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleConnect(APerIoData: PPerIoData);
var
  LClientSocket: THandle;
  LConnection: ICrossConnection;
  LSuccess: Boolean;

  procedure _Failed1;
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleConnect');
    {$ENDIF}

    if Assigned(APerIoData.Callback) then
      APerIoData.Callback(nil, False);

    TSocketAPI.CloseSocket(LClientSocket);
  end;
begin
  LClientSocket := APerIoData.Socket;

  if (TSocketAPI.GetError(LClientSocket) <> 0) then
  begin
    _Failed1;
    Exit;
  end;

  // 不设置该参数, 会导致 getpeername 调用失败
  if (TSocketAPI.SetSockOpt<Integer>(LClientSocket, SOL_SOCKET,
    SO_UPDATE_CONNECT_CONTEXT, 1) < 0) then
  begin
    _Failed1;
    Exit;
  end;

  LConnection := CreateConnection(Self, LClientSocket, ctConnect);
  TriggerConnecting(LConnection);

  LSuccess := _NewReadZero(LConnection);
  if LSuccess then
    TriggerConnected(LConnection);

  if Assigned(APerIoData.Callback) then
    APerIoData.Callback(LConnection, LSuccess);

  if not LSuccess then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleRead(APerIoData: PPerIoData);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
begin
  if (APerIoData.CrossData = nil) then
  begin
    if Assigned(APerIoData.Callback) then
      APerIoData.Callback(nil, False);
    Exit;
  end;

  LConnection := APerIoData.CrossData as ICrossConnection;

  while True do
  begin
    LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

    // 对方主动断开连接
    if (LRcvd = 0) then
    begin
      LConnection.Close;
      Exit;
    end;

    if (LRcvd < 0) then
    begin
      LError := GetLastError;

      // 被系统信号中断, 可以重新recv
      if (LError = WSAEINTR) then
        Continue
      // 接收缓冲区中数据已经被取完了
      else if (LError = WSAEWOULDBLOCK) or (LError = WSAEINPROGRESS) then
        Break
      // 接收出错
      else
      begin
        LConnection.Close;
        Exit;
      end;
    end;

    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;

  if not _NewReadZero(LConnection) then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleWrite(APerIoData: PPerIoData);
begin
  if Assigned(APerIoData.Callback) then
    APerIoData.Callback(APerIoData.CrossData as ICrossConnection, True);
end;

procedure TIocpCrossSocket.StartLoop;
var
  I: Integer;
  LCrossSocket: ICrossSocket;
begin
  if (FIoThreads <> nil) then Exit;

  FIocpHandle := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  LCrossSocket := Self;
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[I] := TIoEventThread.Create(LCrossSocket);
end;

procedure TIocpCrossSocket.StopLoop;

  // IO 线程在收到 SHUTDOWN_FLAG 标记之后就会退出
  // 而这时候有可能还有部分操作未完成, 其对应的 PerIoData 结构就无法释放
  // 只需要在这里再次接收完成端口的消息, 就能等到这部分未完成的操作超时或失败
  // 从而释放其对应的 PerIoData 结构
  procedure _FreeMissingPerIoDatas;
  var
    LBytes: Cardinal;
    LSocket: THandle;
    LPerIoData: PPerIoData;
    LConnection: ICrossConnection;
  begin
    while (AtomicCmpExchange(FPerIoDataCount, 0, 0) > 0) do
    begin
      GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), 10);

      if (LPerIoData <> nil) then
      begin
        if Assigned(LPerIoData.Callback) then
        begin
          if (LPerIoData.CrossData <> nil)
            and (LPerIoData.CrossData is TIocpConnection) then
            LConnection := LPerIoData.CrossData as ICrossConnection
          else
            LConnection := nil;

          LPerIoData.Callback(LConnection, False);
        end;

        if (LPerIoData.CrossData <> nil) then
          LPerIoData.CrossData.Close
        else
          TSocketAPI.CloseSocket(LPerIoData.Socket);

        _FreeIoData(LPerIoData);
      end;
    end;
  end;

var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (ListensCount > 0) or (ConnectionsCount > 0) do Sleep(1);

  for I := 0 to Length(FIoThreads) - 1 do
    PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    if (FIoThreads[I].ThreadID = LCurrentThreadID) then
      raise ECrossSocket.Create('不能在IO线程中执行StopLoop!');

    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  _FreeMissingPerIoDatas;
  CloseHandle(FIocpHandle);
end;

procedure TIocpCrossSocket.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
    procedure _Failed2;
    begin
      if Assigned(ACallback) then
        ACallback(nil, False);
      TSocketAPI.CloseSocket(ASocket);
    end;
  var
    LSockAddr: TRawSockAddrIn;
    LPerIoData: PPerIoData;
    LBytes: Cardinal;
  begin
    LSockAddr.AddrLen := AAddr.ai_addrlen;
    Move(AAddr.ai_addr^, LSockAddr.Addr, AAddr.ai_addrlen);
    if (AAddr.ai_family = AF_INET6) then
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

    LPerIoData := _NewIoData;
    LPerIoData.Action := ioConnect;
    LPerIoData.Socket := ASocket;
    LPerIoData.Callback := ACallback;
    if not ConnectEx(ASocket, AAddr.ai_addr, AAddr.ai_addrlen, nil, 0, LBytes, PWSAOverlapped(LPerIoData)) and
      (WSAGetLastError <> WSA_IO_PENDING) then
    begin
      _FreeIoData(LPerIoData);
      _Failed2;
      Exit(False);
    end;

    Result := True;
  end;

begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed1;
    Exit;
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
        Exit;
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      SetKeepAlive(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
end;

function TIocpCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TIocpConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TIocpCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TIocpListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TIocpCrossSocket.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossListen, Boolean>);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: THandle;
  LListen: ICrossListen;
  I: Integer;

  procedure _Failed;
  begin
    if Assigned(ACallback) then
      ACallback(LListen, False);

    if (LListen <> nil) then
      LListen.Close;
  end;

  procedure _Success;
  begin
    TriggerListened(LListen);

    if Assigned(ACallback) then
      ACallback(LListen, True);
  end;
begin
  LListen := nil;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket.Listen.GetAddrInfo');
    {$ENDIF}
    _Failed;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LListenSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
      if (LListenSocket = INVALID_SOCKET) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TIocpCrossSocket.Listen.WSASocket');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LListenSocket, True);
      TSocketAPI.SetReUseAddr(LListenSocket, True);

      if (LAddrInfo.ai_family = AF_INET6) then
        TSocketAPI.SetSockOpt<Integer>(LListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, 1);

      if (TSocketAPI.Bind(LListenSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0)
        or (TSocketAPI.Listen(LListenSocket) < 0) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TIocpCrossSocket.Listen.Bind');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);

      if (CreateIoCompletionPort(LListenSocket, FIocpHandle, ULONG_PTR(LListenSocket), 0) = 0) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TIocpCrossSocket.Listen.CreateIoCompletionPort');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      // 给每个IO线程投递一个AcceptEx
      for I := 1 to GetIoThreads do
        _NewAccept(LListen);

      _Success;

      // 如果端口传入0，让所有地址统一用首个分配到的端口
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        LAddrInfo.ai_next.ai_addr.sin_port := LListen.LocalPort;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;
end;

procedure TIocpCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc<ICrossConnection, Boolean>);
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := _NewIoData;
  LPerIoData.Buffer.DataBuf.buf := ABuf;
  LPerIoData.Buffer.DataBuf.len := ALen;
  LPerIoData.Action := ioWrite;
  LPerIoData.Socket := AConnection.Socket;
  LPerIoData.CrossData := AConnection;
  LPerIoData.Callback := ACallback;

  LFlags := 0;
  LBytes := 0;
  // WSASend 不会出现部分发送的情况, 要么全部失败, 要么全部成功
  // 所以不需要像 kqueue 或 epoll 中调用 send 那样调用完之后还得检查实际发送了多少
  // 唯一需要注意的是: WSASend 会将待发送的数据锁定到非页面内存, 非页面内存资源
  // 是非常紧张的, 所以不要无节制的调用 WSASend, 最好通过回调发送完一批数据再继
  // 续发送下一批
  if (WSASend(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    // 出错多半是 WSAENOBUFS, 也就是投递的 WSASend 过多, 来不及发送
    // 导致非页面内存资源全部被锁定, 要避免这种情况必须上层发送逻辑
    // 保证不能无节制的调用Send发送大量数据, 最好发送完一个再继续下
    // 一个, 本函数提供了发送结果的回调函数, 在回调函数报告发送成功
    // 之后就可以继续下一块数据发送了
    _FreeIoData(LPerIoData);

    if Assigned(ACallback) then
      ACallback(AConnection, False);

    AConnection.Close;
  end;
end;

function TIocpCrossSocket.ProcessIoEvent: Boolean;
var
  LBytes: Cardinal;
  LSocket: THandle;
  LPerIoData: PPerIoData;
  LConnection: ICrossConnection;
  {$IFDEF DEBUG}
  LErrNo: Cardinal;
  {$ENDIF}
begin
  if not GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), INFINITE) then
  begin
    // 出错了, 并且完成数据也都是空的,
    // 这种情况即便重试, 应该也会继续出错, 最好立即终止IO线程
    if (LPerIoData = nil) then
    begin
      {$IFDEF DEBUG}
      LErrNo := GetLastError;
      // 完成端口被关闭时可能会触发 ERROR_INVALID_HANDLE 和 ERROR_ABANDONED_WAIT_0
      if (LErrNo <> ERROR_INVALID_HANDLE)
        and (LErrNo <> ERROR_ABANDONED_WAIT_0)
      then
        _LogLastOsError('TIocpCrossSocket.ProcessIoEvent.GetQueuedCompletionStatus');
      {$ENDIF}
      Exit(False);
    end;

    try
      // WSA_OPERATION_ABORTED, 995, 由于线程退出或应用程序请求，已中止 I/O 操作。
      // WSAENOTSOCK, 10038, 在一个非套接字上尝试了一个操作。
      // ERROR_NETNAME_DELETED, 64, 指定的网络名不再可用
      // ERROR_CONNECTION_REFUSED, 1225, 远程计算机拒绝网络连接。
      if (LPerIoData.CrossData <> nil) then
      begin
        // AcceptEx虽然成功, 但是Socket句柄耗尽了, 再次投递AcceptEx
        if (LPerIoData.Action = ioAccept) then
        begin
          // 关闭监听后会触发该错误, 这种情况不应该继续投递
          if (GetLastError <> WSA_OPERATION_ABORTED) then
            _NewAccept(LPerIoData.CrossData as ICrossListen);
        end else
        begin
          if Assigned(LPerIoData.Callback) then
          begin
            if (LPerIoData.CrossData is TIocpConnection) then
              LConnection := LPerIoData.CrossData as ICrossConnection
            else
              LConnection := nil;

            LPerIoData.Callback(LConnection, False);
          end;

          LPerIoData.CrossData.Close;
        end;
      end else
      begin
        if Assigned(LPerIoData.Callback) then
          LPerIoData.Callback(nil, False);

        TSocketAPI.CloseSocket(LPerIoData.Socket);
      end;
    finally
      _FreeIoData(LPerIoData);
    end;

    // 出错了, 但是完成数据不是空的, 需要重试
    Exit(True);
  end;

  // 主动调用了 StopLoop
  if (LBytes = 0) and (ULONG_PTR(LPerIoData) = SHUTDOWN_FLAG) then Exit(False);

  // 由于未知原因未获取到完成数据, 但是返回的错误代码又是正常
  // 这种情况需要进行重试(返回True之后IO线程会再次调用ProcessIoEvent)
  if (LPerIoData = nil) then Exit(True);

  try
    case LPerIoData.Action of
      ioAccept  : _HandleAccept(LPerIoData);
      ioConnect : _HandleConnect(LPerIoData);
      ioRead    : _HandleRead(LPerIoData);
      ioWrite   : _HandleWrite(LPerIoData);
    end;
  finally
    _FreeIoData(LPerIoData);
  end;

  Result := True;
end;

end.
