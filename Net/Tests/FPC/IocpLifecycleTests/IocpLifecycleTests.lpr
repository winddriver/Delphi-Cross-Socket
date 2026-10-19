program IocpLifecycleTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes, SyncObjs, Generics.Collections, Windows,
  Net.Winsock2, Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket.Iocp;

const
  WAIT_MS = 3000;

type
  TTestState = class
  public
    Lock: SyncObjs.TCriticalSection;
    Changed, WorkersEnded: TEvent;
    Reads: TDictionary<TSocket, Integer>;
    Latest: ICrossConnection;
    Created, Destroyed, Started, Ended, SendCallbacks, PendingSends, SendCalls: Integer;
    ExitFirst, ExitClaimed: Integer;
    DeferredSocket: TSocket;
    DeferredCloseCalls: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure ClearLatest;
    function TakeConnection: ICrossConnection;
    procedure WaitRead(const ASocket: TSocket);
  end;

  TTrackedConnection = class(TIocpConnection)
  private
    FState: TTestState;
  public
    constructor Create(const AOwner: TCrossSocketBase; const ASocket: TSocket;
      const AType: TConnectType; const AHost: string;
      const ACallback: TCrossConnectionCallback; const AState: TTestState); reintroduce;
    destructor Destroy; override;
  end;

  TTestSocket = class(TIocpCrossSocket)
  private
    FState: TTestState;
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const ASocket: TSocket;
      const AType: TConnectType; const AHost: string;
      const ACallback: TCrossConnectionCallback): ICrossConnection; override;
    function ProcessIoEvent: Boolean; override;
    procedure TriggerIoThreadBegin(const AThread: TIoEventThread); override;
    procedure TriggerIoThreadEnd(const AThread: TIoEventThread); override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    procedure LogicReceived(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;
  public
    constructor Create(const AState: TTestState); reintroduce;
    function StartListen: ICrossListen;
    procedure StartConnect(const APort: Word);
    procedure Stop;
  end;

  TDeferredCloseThread = class(TThread)
  private
    FState: TTestState;
  protected
    procedure Execute; override;
  public
    constructor Create(const AState: TTestState);
  end;

var
  GState: TTestState;
  GRecv: LPFN_WSARECV;
  GSend: LPFN_WSASEND;
  GClose: LPFN_CLOSESOCKET;

function CancelIoExForTest(AHandle: THandle; AOverlapped: Pointer): BOOL; stdcall;
  external 'kernel32.dll' name 'CancelIoEx';

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if ACondition then Exit;
  // 失败进程立即退出，避免旧版 StopLoop 在异常展开中卡住。
  Writeln('FAIL ', AMessage);
  Flush(Output);
  Halt(1);
end;

constructor TTestState.Create;
begin
  inherited;
  Lock := SyncObjs.TCriticalSection.Create;
  Changed := TEvent.Create(nil, False, False, '');
  WorkersEnded := TEvent.Create(nil, True, False, '');
  Reads := TDictionary<TSocket, Integer>.Create;
  DeferredSocket := INVALID_SOCKET;
end;

destructor TTestState.Destroy;
begin
  Latest := nil;
  Reads.Free;
  WorkersEnded.Free;
  Changed.Free;
  Lock.Free;
  inherited;
end;

procedure TTestState.ClearLatest;
begin
  Lock.Enter;
  try
    Latest := nil;
  finally
    Lock.Leave;
  end;
end;

function TTestState.TakeConnection: ICrossConnection;
var
  LDeadline: UInt64;
begin
  LDeadline := GetTickCount64 + WAIT_MS;
  repeat
    Lock.Enter;
    try
      Result := Latest;
      Latest := nil;
    finally
      Lock.Leave;
    end;
    if Result <> nil then Exit;
    Check(GetTickCount64 < LDeadline, 'connected timeout; ended=' + IntToStr(Ended));
    Changed.WaitFor(20);
  until False;
end;

procedure TTestState.WaitRead(const ASocket: TSocket);
var
  LFound: Boolean;
  LDeadline: UInt64;
begin
  LDeadline := GetTickCount64 + WAIT_MS;
  repeat
    Lock.Enter;
    try
      LFound := Reads.ContainsKey(ASocket);
    finally
      Lock.Leave;
    end;
    if LFound then Exit;
    Check(GetTickCount64 < LDeadline, 'zero-byte WSARecv was not pending');
    Changed.WaitFor(20);
  until False;
end;

constructor TTrackedConnection.Create(const AOwner: TCrossSocketBase;
  const ASocket: TSocket; const AType: TConnectType; const AHost: string;
  const ACallback: TCrossConnectionCallback; const AState: TTestState);
begin
  FState := AState;
  inherited Create(AOwner, ASocket, AType, AHost, ACallback);
  FState.Lock.Enter;
  try
    // 操作系统会复用句柄；新连接不能继承上一次连接的读取观测。
    FState.Reads.Remove(ASocket);
  finally
    FState.Lock.Leave;
  end;
  InterlockedIncrement(FState.Created);
end;

destructor TTrackedConnection.Destroy;
begin
  InterlockedIncrement(FState.Destroyed);
  inherited;
end;

constructor TTestSocket.Create(const AState: TTestState);
begin
  FState := AState;
  inherited Create(2);
end;

function TTestSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const ASocket: TSocket; const AType: TConnectType; const AHost: string;
  const ACallback: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TTrackedConnection.Create(AOwner, ASocket, AType, AHost, ACallback, FState);
end;

function TTestSocket.ProcessIoEvent: Boolean;
begin
  // 仅边界用例提前退出一个工作线程，制造多余停止哨兵。
  if (FState.ExitFirst <> 0) and
    (InterlockedCompareExchange(FState.ExitClaimed, 1, 0) = 0) then Exit(False);
  Result := inherited ProcessIoEvent;
end;

procedure TTestSocket.TriggerIoThreadBegin(const AThread: TIoEventThread);
begin
  InterlockedIncrement(FState.Started);
  inherited;
end;

procedure TTestSocket.TriggerIoThreadEnd(const AThread: TIoEventThread);
begin
  if InterlockedIncrement(FState.Ended) = 2 then FState.WorkersEnded.SetEvent;
  FState.Changed.SetEvent;
  inherited;
end;

procedure TTestSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  inherited;
  FState.Lock.Enter;
  try
    FState.Latest := AConnection;
  finally
    FState.Lock.Leave;
  end;
  FState.Changed.SetEvent;
end;

procedure TTestSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LBytes: TBytes;
begin
  SetLength(LBytes, ALen);
  Move(ABuf^, LBytes[0], ALen);
  AConnection.SendBytes(LBytes);
end;

function TTestSocket.StartListen: ICrossListen;
var
  LListen: ICrossListen;
begin
  Listen('127.0.0.1', 0,
    procedure(const AListen: ICrossListen; const ASuccess: Boolean)
    begin
      Check(ASuccess, 'listen failed');
      LListen := AListen;
    end);
  Result := LListen;
  Check(Result <> nil, 'listen callback missing');
end;

procedure TTestSocket.StartConnect(const APort: Word);
begin
  Connect('127.0.0.1', APort, 0, nil);
end;

procedure TTestSocket.Stop;
begin
  StopLoop;
end;

function ObserveRecv(const s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
  var lpNumberOfBytesRecvd: DWORD; var lpFlags: DWORD; AOverlapped: LPWSAOVERLAPPED;
  lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
var
  LError: Integer;
begin
  Result := GRecv(s, lpBuffers, dwBufferCount, lpNumberOfBytesRecvd, lpFlags,
    AOverlapped, lpCompletionRoutine);
  LError := WSAGetLastError;
  if (Result = SOCKET_ERROR) and (LError = WSA_IO_PENDING) and
    (dwBufferCount = 1) and (lpBuffers.len = 0) then
  begin
    GState.Lock.Enter;
    try
      GState.Reads.AddOrSetValue(s, 1);
    finally
      GState.Lock.Leave;
    end;
    GState.Changed.SetEvent;
  end;
  WSASetLastError(LError);
end;

function ObserveSend(const s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD;
  var lpNumberOfBytesSent: DWORD; dwFlags: DWORD; AOverlapped: LPWSAOVERLAPPED;
  lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): Integer; stdcall;
var
  LError: Integer;
begin
  InterlockedIncrement(GState.SendCalls);
  Result := GSend(s, lpBuffers, dwBufferCount, lpNumberOfBytesSent, dwFlags,
    AOverlapped, lpCompletionRoutine);
  LError := WSAGetLastError;
  if (Result = SOCKET_ERROR) and (LError = WSA_IO_PENDING) then
  begin
    InterlockedIncrement(GState.PendingSends);
  end else
  if Result = SOCKET_ERROR then
    Writeln('INFO send-error=', LError);
  WSASetLastError(LError);
end;

function ObserveClose(const s: TSocket): Integer; stdcall;
begin
  if s = GState.DeferredSocket then
  begin
    InterlockedIncrement(GState.DeferredCloseCalls);
    // 真实关闭由工作线程结束屏障之后的辅助线程完成。
    Exit(0);
  end;
  Result := GClose(s);
end;

procedure InstallObservers;
var
  LBytes, LFlags: DWORD;
  LSocket: TSocket;
begin
  // 先解析 lazy stub，防止首次调用覆盖测试观测器。
  LBytes := 0;
  LFlags := 0;
  Net.Winsock2.WSARecv(INVALID_SOCKET, nil, 0, LBytes, LFlags, nil, nil);
  Net.Winsock2.WSASend(INVALID_SOCKET, nil, 0, LBytes, 0, nil, nil);
  LSocket := TSocketAPI.NewTcp;
  Net.Winsock2.closesocket(LSocket);
  GRecv := Net.Winsock2.WSARecv;
  GSend := Net.Winsock2.WSASend;
  GClose := Net.Winsock2.closesocket;
  Net.Winsock2.WSARecv := ObserveRecv;
  Net.Winsock2.WSASend := ObserveSend;
  Net.Winsock2.closesocket := ObserveClose;
end;

function NativeListen(out APort: Word): TSocket;
var
  LAddr: TSockAddrIn;
  LLen: Integer;
begin
  Result := TSocketAPI.NewTcp;
  Check(Result <> INVALID_SOCKET, 'native socket failed');
  FillChar(LAddr, SizeOf(LAddr), 0);
  LAddr.sin_family := AF_INET;
  LAddr.sin_addr.S_addr := inet_addr('127.0.0.1');
  Check(TSocketAPI.Bind(Result, @LAddr, SizeOf(LAddr)) = 0, 'native bind failed');
  Check(TSocketAPI.Listen(Result) = 0, 'native listen failed');
  LLen := SizeOf(LAddr);
  Check(TSocketAPI.GetSockName(Result, @LAddr, LLen) = 0, 'native getsockname failed');
  APort := ntohs(LAddr.sin_port);
end;

function NativeConnect(const APort: Word): TSocket;
var
  LAddr: TSockAddrIn;
begin
  Result := TSocketAPI.NewTcp;
  FillChar(LAddr, SizeOf(LAddr), 0);
  LAddr.sin_family := AF_INET;
  LAddr.sin_addr.S_addr := inet_addr('127.0.0.1');
  LAddr.sin_port := htons(APort);
  Check(TSocketAPI.Connect(Result, @LAddr, SizeOf(LAddr)) = 0, 'native connect failed');
end;

function ConnectOwned(const AServer: TTestSocket; const AListener: TSocket;
  const APort: Word; out AConnection: ICrossConnection): TSocket;
begin
  GState.ClearLatest;
  AServer.StartConnect(APort);
  Result := TSocketAPI.Accept(AListener, nil, nil);
  Check(Result <> INVALID_SOCKET, 'native accept failed');
  AConnection := GState.TakeConnection;
  GState.WaitRead(AConnection.Socket);
end;

procedure Ping(const ASocket: TSocket; const AValue: Byte);
var
  LReply: Byte;
begin
  Check(TSocketAPI.Send(ASocket, AValue, 1) = 1, 'ping send failed');
  Check(TSocketAPI.Readable(ASocket, WAIT_MS) = 1,
    'echo timeout; ended=' + IntToStr(GState.Ended));
  Check(TSocketAPI.Recv(ASocket, LReply, 1) = 1, 'echo receive failed');
  Check(LReply = AValue, 'echo payload mismatch');
end;

procedure CheckReleased(const AServer: TTestSocket);
begin
  GState.ClearLatest;
  AServer.Stop;
  Check(GState.Ended = 2, 'workers did not all stop');
  Check(GState.Created = GState.Destroyed,
    Format('connection leak: created=%d destroyed=%d', [GState.Created, GState.Destroyed]));
  AServer.Free;
end;

procedure Churn(const ACancel: Boolean);
var
  LServer: TTestSocket;
  LListen, LPeer, LKeepPeer: TSocket;
  LPort: Word;
  LConnection, LKeep: ICrossConnection;
  I: Integer;
begin
  LServer := TTestSocket.Create(GState);
  LListen := NativeListen(LPort);
  LKeepPeer := ConnectOwned(LServer, LListen, LPort, LKeep);
  for I := 1 to 100 do
  begin
    LPeer := ConnectOwned(LServer, LListen, LPort, LConnection);
    if ACancel then
      Check(CancelIoExForTest(LConnection.Socket, nil), 'CancelIoEx connection failed');
    LConnection.Close;
    LConnection := nil;
    GClose(LPeer);
    Ping(LKeepPeer, Byte(I));
    Check(GState.Ended = 0, 'normal close ended an IO worker at iteration ' + IntToStr(I));
  end;
  LPeer := ConnectOwned(LServer, LListen, LPort, LConnection);
  Ping(LPeer, 201);
  LConnection := nil;
  LKeep := nil;
  CheckReleased(LServer);
  GClose(LPeer);
  GClose(LKeepPeer);
  GClose(LListen);
  Writeln('PASS churn closes=100 workers=2');
end;

procedure ListenCancellation(const ACloseListener: Boolean);
var
  LServer: TTestSocket;
  LFirst, LSecond: ICrossListen;
  LPeer, LKeepPeer: TSocket;
  LConnection: ICrossConnection;
begin
  LServer := TTestSocket.Create(GState);
  LFirst := LServer.StartListen;
  LSecond := LServer.StartListen;
  LKeepPeer := NativeConnect(LSecond.LocalPort);
  LConnection := GState.TakeConnection;
  GState.WaitRead(LConnection.Socket);
  LConnection := nil;
  if ACloseListener then
    LFirst.Close
  else
    Check(CancelIoExForTest(LFirst.Socket, nil), 'CancelIoEx listener failed');
  Ping(LKeepPeer, 41);
  if ACloseListener then
    LPeer := NativeConnect(LSecond.LocalPort)
  else
    LPeer := NativeConnect(LFirst.LocalPort);
  LConnection := GState.TakeConnection;
  GState.WaitRead(LConnection.Socket);
  Ping(LPeer, 42);
  Check(GState.Ended = 0, 'listener cancellation ended an IO worker');
  LConnection := nil;
  LFirst := nil;
  LSecond := nil;
  CheckReleased(LServer);
  GClose(LPeer);
  GClose(LKeepPeer);
  Writeln('PASS listener cancellation');
end;

procedure PendingStop;
const
  COUNT = 4;
var
  LServer: TTestSocket;
  LListen: TSocket;
  LPeers: array[0..COUNT - 1] of TSocket;
  LConnections: array[0..COUNT - 1] of ICrossConnection;
  LBytes: TBytes;
  LPort: Word;
  I: Integer;
begin
  LServer := TTestSocket.Create(GState);
  LListen := NativeListen(LPort);
  SetLength(LBytes, 8 * 1024 * 1024);
  for I := 0 to COUNT - 1 do
  begin
    LPeers[I] := ConnectOwned(LServer, LListen, LPort, LConnections[I]);
    TSocketAPI.SetRcvBuf(LPeers[I], 4096);
    Check(TSocketAPI.SetSndBuf(LConnections[I].Socket, 0) = 0,
      'cannot disable send buffering');
    LConnections[I].SendBytes(LBytes,
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        InterlockedIncrement(GState.SendCallbacks);
      end);
    LConnections[I] := nil;
  end;
  Writeln('INFO sends=', GState.SendCalls, ' pending=', GState.PendingSends,
    ' completed-before-stop=', GState.SendCallbacks);
  Check(GState.PendingSends > 0, 'test did not create pending WSASend');
  CheckReleased(LServer);
  Check(GState.SendCallbacks = COUNT, 'send callbacks missing or repeated');
  for I := 0 to COUNT - 1 do GClose(LPeers[I]);
  GClose(LListen);
  Writeln('PASS pending-stop sends=', COUNT, ' callbacks=', GState.SendCallbacks);
end;

constructor TDeferredCloseThread.Create(const AState: TTestState);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FState := AState;
end;

procedure TDeferredCloseThread.Execute;
begin
  // 此时停止哨兵已投递；保留的真实读取取消完成排在哨兵之后。
  if FState.WorkersEnded.WaitFor(5000) = wrSignaled then
    GClose(FState.DeferredSocket);
end;

procedure ExtraSentinel;
var
  LServer: TTestSocket;
  LListen, LPeer: TSocket;
  LPort: Word;
  LConnection: ICrossConnection;
  LCloser: TDeferredCloseThread;
  LDeadline: UInt64;
begin
  GState.ExitFirst := 1;
  LServer := TTestSocket.Create(GState);
  LListen := NativeListen(LPort);
  LPeer := ConnectOwned(LServer, LListen, LPort, LConnection);
  GState.DeferredSocket := LConnection.Socket;
  LConnection := nil;
  LDeadline := GetTickCount64 + WAIT_MS;
  while InterlockedCompareExchange(GState.Ended, 0, 0) <> 1 do
  begin
    Check(GetTickCount64 < LDeadline, 'controlled worker did not exit');
    GState.Changed.WaitFor(20);
  end;
  LCloser := TDeferredCloseThread.Create(GState);
  LCloser.Start;
  CheckReleased(LServer);
  LCloser.WaitFor;
  LCloser.Free;
  Check(GState.DeferredCloseCalls = 1, 'closed connection handle was closed twice');
  GClose(LPeer);
  GClose(LListen);
  Writeln('PASS extra-sentinel callbacks=0 closes=1');
end;

begin
  try
    GState := TTestState.Create;
    InstallObservers;
    if ParamStr(1) = 'churn' then Churn(False) else
    if ParamStr(1) = 'connection-cancel' then Churn(True) else
    if ParamStr(1) = 'listen-close' then ListenCancellation(True) else
    if ParamStr(1) = 'listen-cancel' then ListenCancellation(False) else
    if ParamStr(1) = 'pending-stop' then PendingStop else
    if ParamStr(1) = 'extra-sentinel' then ExtraSentinel else
      Check(False, 'unknown test case');
    Net.Winsock2.WSARecv := GRecv;
    Net.Winsock2.WSASend := GSend;
    Net.Winsock2.closesocket := GClose;
    GState.Free;
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Flush(Output);
      Halt(1);
    end;
  end;
end.
