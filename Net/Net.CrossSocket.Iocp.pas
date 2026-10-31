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

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Windows,

  Net.Winsock2,
  Net.Wship6,
  Net.SocketAPI,
  Net.CrossSocket.Base;

type
  TIocpListen = class(TCrossListenBase)
  end;

  TIocpConnection = class(TCrossConnectionBase)
  end;

  TIocpCrossSocket = class(TCrossSocketBase)
  private const
    SHUTDOWN_FLAG = ULONG_PTR(-1);
    SO_UPDATE_CONNECT_CONTEXT = $7010;
    IPV6_V6ONLY = 27;
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
      Socket: TSocket;
      CrossData: ICrossData;
      Callback: TCrossConnectionCallback;
    end;
  private
    FIocpHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FPerIoDataCount: NativeInt;

    function _NewIoData: PPerIoData; inline;
    procedure _FreeIoData(const P: PPerIoData); inline;

    function _NewAccept(const AListen: ICrossListen): Boolean;
    function _NewReadZero(const AConnection: ICrossConnection): Boolean;

    procedure _HandleAccept(const APerIoData: PPerIoData);
    procedure _HandleConnect(const APerIoData: PPerIoData);
    procedure _HandleRead(const APerIoData: PPerIoData);
    procedure _HandleWrite(const APerIoData: PPerIoData);
  protected
    function CreateListen(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil); override;

    function _ConnectAddr(const AOp: IInterface;
      const AAddr: TCrossConnectAddr): Boolean; override;

    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil); override;

    function ProcessIoEvent: Boolean; override;
    {$IFDEF CROSS_LISTEN_TESTS}
    function GetPendingIoCountForTest: NativeInt;
    {$ENDIF}
  end;

{$IFDEF CROSS_LISTEN_TESTS}
var
  CrossIocpAcceptReadyForTest: TCrossListenTestHook;
{$ENDIF}

implementation

{ TIocpCrossSocket }

{$IFDEF CROSS_LISTEN_TESTS}
function TIocpCrossSocket.GetPendingIoCountForTest: NativeInt;
begin
  Result := AtomicCmpExchange(FPerIoDataCount, 0, 0);
end;
{$ENDIF}

function TIocpCrossSocket._NewIoData: PPerIoData;
begin
  GetMem(Result, SizeOf(TPerIoData));
  FillChar(Result^, SizeOf(TPerIoData), 0);
  System.Initialize(Result^);

  AtomicIncrement(FPerIoDataCount);
end;

procedure TIocpCrossSocket._FreeIoData(const P: PPerIoData);
begin
  if (P = nil) then Exit;

  System.Finalize(P^);
  FreeMem(P, SizeOf(TPerIoData));

  AtomicDecrement(FPerIoDataCount);
end;

function TIocpCrossSocket._NewAccept(const AListen: ICrossListen): Boolean;
var
  LListen: TIocpListen;
  LClientSocket: TSocket;
  LPerIoData: PPerIoData;
  LBytes: Cardinal;
  LError: Integer;
begin
  Result := False;
  LListen := AListen as TIocpListen;
  if AListen.IsClosed or not _CanListen(LListen.Generation) then Exit;
  LClientSocket := WSASocket(AListen.Family, AListen.SockType, AListen.Protocol,
    nil, 0, WSA_FLAG_OVERLAPPED);
  if LClientSocket = INVALID_SOCKET then
  begin
    LError := WSAGetLastError;
    _Log('Accept socket error %d: %s', [LError, SysErrorMessage(LError)]);
    Exit;
  end;
  LPerIoData := nil;
  LError := 0;
  try
    TSocketAPI.SetNonBlock(LClientSocket, True);
    SetKeepAlive(LClientSocket);
    LPerIoData := _NewIoData;
    LPerIoData.Action := ioAccept;
    LPerIoData.Socket := LClientSocket;
    LPerIoData.CrossData := AListen;
    LListen._Lock;
    try
      if AListen.IsClosed or not _CanListen(LListen.Generation) then Exit;
      Result := AcceptEx(AListen.Socket, LClientSocket, @LPerIoData.Buffer.AcceptExBuffer, 0,
        SizeOf(TAddrBuffer), SizeOf(TAddrBuffer), LBytes, POverlapped(LPerIoData));
      if not Result then
      begin
        LError := WSAGetLastError;
        Result := LError = WSA_IO_PENDING;
      end;
      if Result then
      begin
        // 成功提交后由完成包回收，不能提前释放内核仍引用的 Overlapped。
        LPerIoData := nil;
        LClientSocket := INVALID_SOCKET;
      end;
    finally LListen._Unlock; end;
  finally
    if LClientSocket <> INVALID_SOCKET then TSocketAPI.CloseSocket(LClientSocket);
    _FreeIoData(LPerIoData);
  end;
  if not Result and (LError <> 0) then
    _Log('AcceptEx error %d: %s', [LError, SysErrorMessage(LError)]);
end;

function TIocpCrossSocket._NewReadZero(const AConnection: ICrossConnection): Boolean;
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
    _LogLastOsError(Self.ClassName + '._NewReadZero.WSARecv, %s', [AConnection.DebugInfo]);
    {$ENDIF}
    _FreeIoData(LPerIoData);
    Exit(False);
  end;

  Result := True;
end;

procedure TIocpCrossSocket._HandleAccept(const APerIoData: PPerIoData);
var
  LListen: ICrossListen;
  LListenObj: TIocpListen;
  LConnection: ICrossConnection;
  LClientSocket, LListenSocket, LOwnedSocket: TSocket;
  LError: Integer;
begin
  LClientSocket := APerIoData.Socket;
  APerIoData.Socket := INVALID_SOCKET;
  try
    if APerIoData.CrossData = nil then Exit;
    LListen := APerIoData.CrossData as ICrossListen;
    {$IFDEF CROSS_LISTEN_TESTS}
    if Assigned(CrossIocpAcceptReadyForTest) then CrossIocpAcceptReadyForTest(LListen);
    {$ENDIF}
    LListenObj := LListen as TIocpListen;
    LError := 0;
    LListenObj._Lock;
    try
      if LListen.IsClosed or not _CanListen(LListenObj.Generation) then Exit;
      LListenSocket := LListen.Socket;
      if TSocketAPI.SetSockOpt<TSocket>(LClientSocket, SOL_SOCKET,
        SO_UPDATE_ACCEPT_CONTEXT, LListenSocket) < 0 then LError := WSAGetLastError;
    finally LListenObj._Unlock; end;
    // 当前接入失败也要补回接受请求，否则连续失败会耗尽初始投递。
    if not _NewAccept(LListen) then
    begin
      _CloseCrossData(LListen);
      Exit;
    end;
    if LError <> 0 then
    begin
      _Log('Accept context error %d: %s', [LError, SysErrorMessage(LError)]);
      Exit;
    end;
    if not _CanListen(LListenObj.Generation) then Exit;
    if CreateIoCompletionPort(LClientSocket, FIocpHandle, ULONG_PTR(LClientSocket), 0) = 0 then
    begin
      _LogLastOsError(Self.ClassName + '._HandleAccept.CreateIoCompletionPort');
      Exit;
    end;
    // 工厂和虚拟通知在锁外；公共层的停止门闩协调接入连接与关闭快照。
    LOwnedSocket := LClientSocket;
    LClientSocket := INVALID_SOCKET;
    LConnection := CreateConnection(Self, LOwnedSocket, ctAccept, '');
    try
      TriggerConnecting(LConnection);
      if LConnection.IsClosed then Exit;
      TriggerConnected(LConnection);
      if not _NewReadZero(LConnection) then _CloseCrossData(LConnection);
    except
      on E: Exception do
      begin
        _LogException('_HandleAccept', E);
        _CloseCrossData(LConnection);
      end;
    end;
  finally
    if LClientSocket <> INVALID_SOCKET then TSocketAPI.CloseSocket(LClientSocket);
  end;
end;

procedure TIocpCrossSocket._HandleConnect(const APerIoData: PPerIoData);
var
  LClientSocket: TSocket;
  LConnection: ICrossConnection;
  LConnObj: TIocpConnection;
  LSockErr: Integer;
  LFailed, LContextFailed: Boolean;
  LErrorTag: string;
begin
  LClientSocket := APerIoData.Socket;
  LConnection := APerIoData.CrossData as ICrossConnection;
  if (LConnection = nil) then Exit;
  LConnObj := LConnection as TIocpConnection;
  LContextFailed := False;

  // 完成包持有连接接口，但句柄仍可能被 Close 关闭；与实际关闭串行访问。
  LConnObj._Lock;
  try
    if LConnection.IsClosed then Exit;
    LSockErr := TSocketAPI.GetError(LClientSocket);
    LFailed := (LSockErr <> 0);
    if not LFailed then
    begin
      // 不设置该参数, 会导致 getpeername 调用失败
      LFailed := (TSocketAPI.SetSockOpt<Integer>(LClientSocket, SOL_SOCKET,
        SO_UPDATE_CONNECT_CONTEXT, 1) < 0);
      if LFailed then
      begin
        LSockErr := WSAGetLastError;
        LContextFailed := True;
      end;
    end;
    if LFailed then
      LConnection.LastNetError := LSockErr;
  finally
    LConnObj._Unlock;
  end;

  if LFailed then
  begin
    if LContextFailed then LErrorTag := 'SetSockOpt'
    else LErrorTag := 'GetError';
    _Log('%s._HandleConnect.%s: %d, %s',
      [Self.ClassName, LErrorTag, LSockErr, SysErrorMessage(LSockErr)]);
    _ConnectAttemptFailed(LConnection);
    Exit;
  end;

  TriggerConnected(LConnection);

  if not _NewReadZero(LConnection) then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleRead(const APerIoData: PPerIoData);
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
      _Log(Self.ClassName + '.Recv=0(Close), %s', [LConnection.DebugInfo]);
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
        _LogLastOsError(Self.ClassName + '.Recv<0, %s', [LConnection.DebugInfo]);
        LConnection.Close;
        Exit;
      end;
    end;

    {$IFDEF DEBUG}
    _Log('[%s]thread%d, _HandleRead.TriggerReceived准备执行, LRcvd=%d', [
      Self.ClassName, TThread.Current.ThreadID, LRcvd
    ]);
    {$ENDIF}
    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);
    {$IFDEF DEBUG}
    _Log('[%s]thread%d, _HandleRead.TriggerReceived执行完成, LRcvd=%d', [
      Self.ClassName, TThread.Current.ThreadID, LRcvd
    ]);
    {$ENDIF}

    // 回调中可能关闭了连接, 需要检查状态
    if LConnection.IsClosed then Exit;

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;

  if not _NewReadZero(LConnection) then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleWrite(const APerIoData: PPerIoData);
begin
  if not _CallConnectionCallback(APerIoData.Callback,
    APerIoData.CrossData as ICrossConnection, True) then
    _CloseCrossData(APerIoData.CrossData);
end;

procedure TIocpCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  FIocpHandle := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  _StartListening;
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[I] := TIoEventThread.Create(Self);
end;

procedure TIocpCrossSocket.StopLoop;

  // IO 线程在收到 SHUTDOWN_FLAG 标记之后就会退出
  // 而这时候有可能还有部分操作未完成, 其对应的 PerIoData 结构就无法释放
  // 只需要在这里再次接收完成端口的消息, 就能等到这部分未完成的操作超时或失败
  // 从而释放其对应的 PerIoData 结构
  //
  // 超时仍未清零时: 输出错误日志诊断遗留, 仍关闭 IOCP handle (避免 OS 句柄泄漏).
  // 因 IO 线程已退出, 此处与 _HandleXxx 路径互斥, 无 PerIoData 重复释放风险.
  procedure _FreeMissingPerIoDatas;
  const
    DEFAULT_DRAIN_TIMEOUT_MS = 3000;
    POLL_STEP_MS = 10;
  var
    LBytes: Cardinal;
    LSocket: TSocket;
    LPerIoData: PPerIoData;
    LConnection: ICrossConnection;
    LMaxWait, LRemaining: Integer;
  begin
    LMaxWait := DEFAULT_DRAIN_TIMEOUT_MS;
    LRemaining := LMaxWait;

    while (AtomicCmpExchange(FPerIoDataCount, 0, 0) > 0) and (LRemaining > 0) do
    begin
      GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), POLL_STEP_MS);

      if (LPerIoData = nil) then
      begin
        Dec(LRemaining, POLL_STEP_MS);
        Continue;
      end;

      // 线程提前退出时可能留下停止标记，它不持有 PerIoData 或 socket。
      if (ULONG_PTR(LPerIoData) = SHUTDOWN_FLAG) then Continue;

      try
        // AcceptEx 的待接入 socket 尚未移交给连接；其他 socket 由 CrossData
        // 负责关闭，不能再次关闭完成包中保存的旧值（该值可能已被复用）。
        if (LPerIoData.Action = ioAccept) or (LPerIoData.CrossData = nil) then
        begin
          if (LPerIoData.Socket <> INVALID_SOCKET) then
          begin
            TSocketAPI.CloseSocket(LPerIoData.Socket);
            LPerIoData.Socket := INVALID_SOCKET;
          end;
        end;

        if Assigned(LPerIoData.Callback) then
        begin
          if (LPerIoData.CrossData <> nil)
            and (LPerIoData.CrossData is TIocpConnection) then
            LConnection := LPerIoData.CrossData as ICrossConnection
          else
            LConnection := nil;

          _CallConnectionCallback(LPerIoData.Callback, LConnection, False);
        end;

        if (LPerIoData.CrossData <> nil) then
          _CloseCrossData(LPerIoData.CrossData);
      finally
        _FreeIoData(LPerIoData);
      end;
    end;

    // 超时仍未清零: 不静默, 强制 _Log (受 CrossSocketLogEnabled 全局开关控制)
    if (AtomicCmpExchange(FPerIoDataCount, 0, 0) > 0) then
      _Log('[%s][StopLoop] WARNING: drain 超时 %dms, 仍有 %d 个 PerIoData 未回收, 即将关闭 IOCP handle',
        [Self.ClassName, LMaxWait, AtomicCmpExchange(FPerIoDataCount, 0, 0)]);
  end;

var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;
  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
    if FIoThreads[I].ThreadID = LCurrentThreadID then
      raise ECrossSocket.Create('不能在IO线程中执行StopLoop!');
  _StopListening;

  {$IFDEF DEBUG}
  _Log('[%s][StopLoop] 开始停止, 线程数=%d', [
    Self.ClassName, Length(FIoThreads)]);
  {$ENDIF}
  CloseAll;

  {$IFDEF DEBUG}
  _Log('[%s][StopLoop] 等待连接关闭, ListensCount=%d, ConnectionsCount=%d', [
    Self.ClassName, ListensCount, ConnectionsCount
  ]);
  {$ENDIF}
  while (ListensCount > 0) or (ConnectionsCount > 0) do Sleep(1);

  {$IFDEF DEBUG}
  _Log('[%s][StopLoop] 发送 SHUTDOWN_FLAG 唤醒所有线程', [
    Self.ClassName
  ]);
  {$ENDIF}
  for I := 0 to Length(FIoThreads) - 1 do
    PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));

  for I := 0 to Length(FIoThreads) - 1 do
  begin
    {$IFDEF DEBUG}
    _Log('[%s]thread%d[StopLoop] 等待线程 %d 退出', [
      Self.ClassName, FIoThreads[I].ThreadID, I
    ]);
    {$ENDIF}
    FIoThreads[I].WaitFor;
    {$IFDEF DEBUG}
    _Log('[%s]thread%d[StopLoop] 线程 %d 已退出', [
      Self.ClassName, FIoThreads[I].ThreadID, I]);
    {$ENDIF}
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  _FreeMissingPerIoDatas;
  CloseHandle(FIocpHandle);
end;

function TIocpCrossSocket._ConnectAddr(const AOp: IInterface;
  const AAddr: TCrossConnectAddr): Boolean;
var
  LState: TCrossConnectOp;
  LSocket: TSocket;
  LSockAddr: TRawSockAddrIn;
  LPerIoData: PPerIoData;
  LBytes: Cardinal;
  LConnection: ICrossConnection;
  LConnObj: TIocpConnection;
  LRetryOp: IInterface;
  LConnectCb: TCrossConnectionCallback;
  LError: Integer;
  LOwnsSocket, LSubmitted: Boolean;
begin
  LState := AOp as TCrossConnectOp;
  LSocket := WSASocket(AAddr.Family, AAddr.SockType, AAddr.Protocol,
    nil, 0, WSA_FLAG_OVERLAPPED);
  if (LSocket = INVALID_SOCKET) then
  begin
    LError := WSAGetLastError;
    _LogLastOsError(Self.ClassName + '._ConnectAddr.WSASocket');
    if (LError = WSAEAFNOSUPPORT) or (LError = WSAEPROTONOSUPPORT)
      or (LError = WSAESOCKTNOSUPPORT) then Exit(False);
    LState.Complete(nil, False);
    Exit(True);
  end;

  LOwnsSocket := True;
  LPerIoData := nil;
  try
    try
      TSocketAPI.SetNonBlock(LSocket, True);
      SetKeepAlive(LSocket);

      FillChar(LSockAddr, SizeOf(TRawSockAddrIn), 0);
      LSockAddr.AddrLen := AAddr.Addr.AddrLen;
      if (AAddr.Family = AF_INET6) then
      begin
        LSockAddr.Addr6.sin6_family := AAddr.Family;
        LSockAddr.Addr6.sin6_port := htons(LState.LocalPort);
      end else
      begin
        LSockAddr.Addr.sin_family := AAddr.Family;
        LSockAddr.Addr.sin_port := htons(LState.LocalPort);
      end;
      if (TSocketAPI.Bind(LSocket, @LSockAddr.Addr, LSockAddr.AddrLen) < 0) then
      begin
        _LogLastOsError(Self.ClassName + '._ConnectAddr.Bind');
        Exit(False);
      end;

      if (CreateIoCompletionPort(LSocket, FIocpHandle, ULONG_PTR(LSocket), 0) = 0) then
      begin
        _LogLastOsError(Self.ClassName + '._ConnectAddr.CreateIoCompletionPort');
        Exit(False);
      end;

      LConnectCb := LState.CreateCallback();
      // 从构造开始由连接拥有句柄，构造抛错也由其析构回收。
      LOwnsSocket := False;
      LConnection := CreateConnection(Self, LSocket, ctConnect, LState.Host, LConnectCb);
      LConnObj := LConnection as TIocpConnection;
      LConnObj._SetConnectOp(AOp);
      PrepareConnection(LConnection, LState.Host, LState.LogicalPort);
      TriggerConnecting(LConnection);
      if LConnection.IsClosed then Exit(True);

      LPerIoData := _NewIoData;
      LPerIoData.Action := ioConnect;
      LPerIoData.CrossData := LConnection;
      LPerIoData.Socket := LSocket;
      // Close 在实际关闭句柄前也取得此锁，避免提交时旧句柄被释放或复用。
      LConnObj._Lock;
      try
        if LConnection.IsClosed then Exit(True);
        LSubmitted := ConnectEx(LSocket, @AAddr.Addr.Addr, AAddr.Addr.AddrLen,
          nil, 0, LBytes, PWSAOverlapped(LPerIoData));
        if not LSubmitted then
        begin
          LError := WSAGetLastError;
          LSubmitted := (LError = WSA_IO_PENDING);
          if not LSubmitted then
            LConnection.LastNetError := LError;
        end;
        // 完成包接管 PerIoData，可能已经在另一线程完成并释放。
        if LSubmitted then
          LPerIoData := nil;
      finally
        LConnObj._Unlock;
      end;

      if not LSubmitted then
      begin
        _LogLastOsError(Self.ClassName + '._ConnectAddr.ConnectEx');
        _FreeIoData(LPerIoData);
        LPerIoData := nil;
        // 仅失败清理的赢家续试，主动 Close 已取得的终态不能被重试覆盖。
        Exit(not LConnObj._CloseRetryingConnect(LRetryOp));
      end;

      Result := True;
    except
      on E: Exception do
      begin
        if (LConnection <> nil) then
          _CloseCrossData(LConnection);
        raise;
      end;
    end;
  finally
    _FreeIoData(LPerIoData);
    if LOwnsSocket then
      TSocketAPI.CloseSocket(LSocket);
  end;
end;

function TIocpCrossSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TIocpConnection.Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
end;

function TIocpCrossSocket.CreateListen(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TIocpListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TIocpCrossSocket.Listen(const AHost: string; const APort: Word;
  const ACallback: TCrossListenCallback);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: TSocket;
  LListen: ICrossListen;
  I, LGeneration, LError: Integer;
  LListenObj: TIocpListen;
  LAssociated: Boolean;
  LListenSuccess: Boolean;

  procedure _Failed;
  begin
    try
      if not LListenSuccess and Assigned(ACallback) then
        ACallback(LListen, False);
    finally
      if (LListen <> nil) then
        LListen.Close
      else if (LListenSocket <> INVALID_SOCKET) then
      begin
        TSocketAPI.CloseSocket(LListenSocket);
        LListenSocket := INVALID_SOCKET;
      end;
    end;
  end;

  procedure _Success;
  begin
    TriggerListened(LListen);
    if not LListenObj._IsPublished then
    begin
      _Failed;
      Exit;
    end;
    LListenSuccess := True;
    if Assigned(ACallback) then
      ACallback(LListen, True);
  end;
begin
  LListenSocket := INVALID_SOCKET;
  LListenSuccess := False;
  LGeneration := _GetListenGeneration;
  if not _CanListen(LGeneration) then
  begin
    _Failed;
    Exit;
  end;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError(Self.ClassName + '.Listen.GetAddrInfo');
    {$ENDIF}
    _Failed;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      if not _CanListen(LGeneration) then
      begin
        if not LListenSuccess then _Failed;
        Break;
      end;
      LListen := nil;
      LListenSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
      if (LListenSocket = INVALID_SOCKET) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError(Self.ClassName + '.Listen.WSASocket');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LListenSocket, True);
      TSocketAPI.SetReUseAddr(LListenSocket, True);

      if (LAddrInfo.ai_family = AF_INET6) then
        TSocketAPI.SetSockOpt<Integer>(LListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, 1);

      if (TSocketAPI.Bind(LListenSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError(Self.ClassName + '.Listen.Bind');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      if (TSocketAPI.Listen(LListenSocket) < 0) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError(Self.ClassName + '.Listen.Listen');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);

      LListenObj := LListen as TIocpListen;
      try
        if not _RegisterListen(LListen, LGeneration) then
        begin
          _Failed;
          Exit;
        end;
        LError := 0;
        LListenObj._Lock;
        try
          LAssociated := not LListen.IsClosed and _CanListen(LGeneration);
          if LAssociated then
          begin
            LAssociated := CreateIoCompletionPort(LListen.Socket, FIocpHandle,
              ULONG_PTR(LListen.Socket), 0) <> 0;
            if not LAssociated then LError := GetLastError;
          end;
        finally LListenObj._Unlock; end;
        if not LAssociated then
        begin
          try
            if LError <> 0 then _Log('Listen IOCP error %d: %s', [LError, SysErrorMessage(LError)]);
          finally _Failed; end;
          Exit;
        end;
        for I := 1 to GetIoThreads do
          if not _NewAccept(LListen) then
          begin
            // 先前已投递请求由关闭产生真实取消完成，不直接 Free。
            _Failed;
            Exit;
          end;
        _Success;
        if not LListenObj._IsPublished then Exit;
      except
        _CloseCrossData(LListen);
        raise;
      end;

      // 如果端口传入0，让所有地址统一用首个分配到的端口
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        LAddrInfo.ai_next.ai_addr.sin_port := htons(LListen.LocalPort);

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;
end;

procedure TIocpCrossSocket.Send(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
  LPrepared: TCrossConnectionCallback;
  LSubmitted: Boolean;
begin
  if not _PrepareSend(AConnection, ABuf, ALen, ACallback, LPrepared) then Exit;
  LPerIoData := nil;
  LSubmitted := False;
  try
    LPerIoData := _NewIoData;
    LPerIoData.Buffer.DataBuf.buf := ABuf;
    LPerIoData.Buffer.DataBuf.len := ALen;
    LPerIoData.Action := ioWrite;
    LPerIoData.Socket := AConnection.Socket;
    LPerIoData.CrossData := AConnection;
    if Assigned(LPrepared) then LPerIoData.Callback := LPrepared
    else LPerIoData.Callback := ACallback;

    LFlags := 0;
    LBytes := 0;
    // 已投递项由完成包/停止drain结算，关闭连接本身不能提前释放额度或缓冲。
    LSubmitted := (WSASend(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1,
      LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) = 0)
      or (WSAGetLastError = WSA_IO_PENDING);
    {$IFDEF DEBUG}
    if not LSubmitted then
      _LogLastOsError(Self.ClassName + '.WSASend, %s', [AConnection.DebugInfo]);
    {$ENDIF}
  except
    on E: Exception do _LogException('IOCP send submission failed', E);
  end;
  if LSubmitted then Exit;

  try
    if LPerIoData <> nil then _FreeIoData(LPerIoData);
  finally
    if Assigned(LPrepared) then _CallConnectionCallback(LPrepared, AConnection, False)
    else _CallConnectionCallback(ACallback, AConnection, False);
    _CloseCrossData(AConnection);
  end;
end;

function TIocpCrossSocket.ProcessIoEvent: Boolean;
  procedure _ReleasePerIoData(const APerIoData: PPerIoData; const AError: Cardinal);
  var
    LConnection: ICrossConnection;
  begin
    try
      if (APerIoData.CrossData <> nil) then
      begin
        if (APerIoData.Action = ioAccept) then
        begin
          // 失败的 AcceptEx 尚未移交连接，释放该操作独占的 socket。
          if (APerIoData.Socket <> INVALID_SOCKET) then
          begin
            TSocketAPI.CloseSocket(APerIoData.Socket);
            APerIoData.Socket := INVALID_SOCKET;
          end;

          // CancelIoEx 也会产生 995，但不关闭监听；仍打开时需要补投。
          if not APerIoData.CrossData.IsClosed then
          begin
            _Log('[%s]thread%d, _NewAccept', [Self.ClassName, TThread.Current.ThreadID]);
            if not _NewAccept(APerIoData.CrossData as ICrossListen) then
              _CloseCrossData(APerIoData.CrossData);
          end;
        end else
        begin
          {$IFDEF DEBUG}
          _LogLastOsError(
            Format(Self.ClassName + '.ProcessIoEvent.GetQueuedCompletionStatus.CrossDataNotNil(socket=%d, action=%d)',
              [APerIoData.Socket, Ord(APerIoData.Action)])
          );
          {$ENDIF}
          if Assigned(APerIoData.Callback) then
          begin
            if (APerIoData.CrossData is TIocpConnection) then
              LConnection := APerIoData.CrossData as ICrossConnection
            else
              LConnection := nil;

            _CallConnectionCallback(APerIoData.Callback, LConnection, False);
          end;

          if (APerIoData.Action = ioConnect) then
          begin
            LConnection := APerIoData.CrossData as ICrossConnection;
            LConnection.LastNetError := AError;
            _ConnectAttemptFailed(LConnection);
          end else
            _CloseCrossData(APerIoData.CrossData);
        end;
      end else
      begin
        {$IFDEF DEBUG}
        _LogLastOsError(
          Format(Self.ClassName + '.ProcessIoEvent.GetQueuedCompletionStatus.CrossDataIsNil(socket=%d, action=%d)',
            [APerIoData.Socket, Ord(APerIoData.Action)])
        );
        {$ENDIF}
        _CallConnectionCallback(APerIoData.Callback, nil, False);

        if (APerIoData.Socket <> INVALID_SOCKET) then
        begin
          TSocketAPI.CloseSocket(APerIoData.Socket);
          APerIoData.Socket := INVALID_SOCKET;
        end;
      end;
    finally
      _FreeIoData(APerIoData);
    end;
  end;
var
  LBytes: Cardinal;
  LSocket: TSocket;
  LPerIoData: PPerIoData;
  LErrNo: Cardinal;
begin
  if not GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), INFINITE) then
  begin
    // ERROR_INVALID_HANDLE, 6, IOCP句柄被关闭
    // ERROR_ABANDONED_WAIT_0, $02DF, IOCP句柄被关闭
    // WSA_OPERATION_ABORTED, 995, 单个 I/O 被取消，不表示完成端口已关闭。
    // WSAENOTSOCK, 10038, 在一个非套接字上尝试了一个操作。
    // WSAESHUTDOWN, 10058, 套接字已关闭
    // ERROR_NETNAME_DELETED, 64, 指定的网络名不再可用
    // ERROR_CONNECTION_REFUSED, 1225, 远程计算机拒绝网络连接。
    LErrNo := GetLastError;
    {$IFDEF DEBUG}
    _Log('[%s]thread%d, GetQueuedCompletionStatus:%d, %s', [
      Self.ClassName, TThread.Current.ThreadID, LErrNo, SysErrorMessage(LErrNo)
    ]);
    {$ENDIF}

    // 未取得完成包说明等待本身失败（例如完成端口已关闭）。
    if (LPerIoData = nil) then Exit(False);

    // 非空完成包属于一次失败的 I/O，回收它后继续服务其他连接。
    _ReleasePerIoData(LPerIoData, LErrNo);

    Exit(True);
  end;

  // 主动调用了 StopLoop
  if (LBytes = 0) and (ULONG_PTR(LPerIoData) = SHUTDOWN_FLAG) then Exit(False);

  // 由于未知原因未获取到完成数据, 但是返回的错误代码又是正常
  // 这种情况需要进行重试(返回True之后IO线程会再次调用ProcessIoEvent)
  if (LPerIoData = nil) then Exit(True);

  try
    {$IFDEF DEBUG}
    _Log('[%s]thread%d, 准备处理IOCP事件 PerIoData=%p, Action=%d, Bytes=%d', [
      Self.ClassName, TThread.Current.ThreadID, Pointer(LPerIoData), Ord(LPerIoData.Action), LBytes
    ]);
    {$ENDIF}
    try
      case LPerIoData.Action of
        ioAccept  : _HandleAccept(LPerIoData);
        ioConnect : _HandleConnect(LPerIoData);
        ioRead    : _HandleRead(LPerIoData);
        ioWrite   : _HandleWrite(LPerIoData);
      end;
    except
      on E: Exception do
      begin
        _LogException('ProcessIoEvent', E);
        if LPerIoData.CrossData is TIocpConnection then
          _CloseCrossData(LPerIoData.CrossData);
      end;
    end;
    {$IFDEF DEBUG}
    _Log('[%s]thread%d, 处理IOCP事件完成 PerIoData=%p, Action=%d, Bytes=%d', [
      Self.ClassName, TThread.Current.ThreadID, Pointer(LPerIoData), Ord(LPerIoData.Action), LBytes
    ]);
    {$ENDIF}
  finally
    _FreeIoData(LPerIoData);
  end;

  Result := True;
end;

end.
