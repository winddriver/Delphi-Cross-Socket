program KqueueEdgeTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
{$IFNDEF CROSS_KQUEUE_TESTS}{$MESSAGE FATAL '需要 CROSS_KQUEUE_TESTS'}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket.Kqueue, BSD.kqueue;

// 真实系统调用，不替换 kevent。F_GETFD 不需要第三个变参。
function TestDup(const AFD: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'/usr/lib/libSystem.B.dylib'{$ENDIF} name 'dup';
function TestClose(const AFD: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'/usr/lib/libSystem.B.dylib'{$ENDIF} name 'close';
function TestFdFlags(const AFD, ACommand: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'/usr/lib/libSystem.B.dylib'{$ENDIF} name 'fcntl';

const
  TEST_F_GETFD = 1;

type
  TEdgeCounts = class
  public
    Connections, ConnectionEntered, ConnectionDestroyed, Disconnects: Integer;
    Listens, ListenEntered, ListenDestroyed, ListenCalls, ListenSuccess: Integer;
    Sends, SendSuccess, GateTimeout, RegistrationErrors, PublishErrors: Integer;
    StopRejected, StopUnexpected, StopRegisteredBefore, StopRegisteredAfter: Integer;
    FailUpdate: Boolean;
  end;

  TEdgeConnection = class(TKqueueConnection)
  public
    Counts: TEdgeCounts;
    destructor Destroy; override;
  end;

  TEdgeListen = class(TKqueueListen)
  public
    Counts: TEdgeCounts;
    procedure UpdateAddr; override;
    destructor Destroy; override;
  end;

  TEdgeSocket = class(TKqueueCrossSocket)
  private
    FMode: string;
    FCounts: TEdgeCounts;
    FConnection: ICrossConnection;
    FListen: ICrossListen;
    FConnected, FGateEntered, FObserveListen, FListenClaimed: Integer;
    FGate, FResume, FListenFetched, FListenResume: TEvent;
    FListenSocket: TSocket;
    FPayload: Byte;
    FReply: array[0..1] of Byte;
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    function CreateListen(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    procedure TriggerListened(const AListen: ICrossListen); override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
    procedure LogicReceived(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;
    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(const AMode: string; const ACounts: TEdgeCounts); reintroduce;
    destructor Destroy; override;
    function StartListen: Word;
    procedure EventsReady(const AEvents: PKEvent; const ACount: Integer);
    procedure RegisterFailure;
    procedure CloseFetchedListen;
    procedure PublishFailure;
    procedure FinishStopFromIo;
    procedure Stop;
    procedure Report;
  end;

var
  OutputLock: TCriticalSection;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure Line(const AText: string);
begin
  OutputLock.Enter;
  try Writeln(AText); Flush(Output); finally OutputLock.Leave; end;
end;

function SendDone(const ACounts: TEdgeCounts; const APrintDone: Boolean = False): TCrossConnectionCallback;
begin
  Result := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      AtomicIncrement(ACounts.Sends);
      if ASuccess then AtomicIncrement(ACounts.SendSuccess);
      if APrintDone then Line('REPLIED');
    end;
end;

destructor TEdgeConnection.Destroy;
var LCounts: TEdgeCounts;
begin
  LCounts := Counts;
  if LCounts <> nil then AtomicIncrement(LCounts.ConnectionEntered);
  inherited;
  if LCounts <> nil then AtomicIncrement(LCounts.ConnectionDestroyed);
end;

procedure TEdgeListen.UpdateAddr;
begin
  if (Counts <> nil) and Counts.FailUpdate then
  begin
    AtomicIncrement(Counts.PublishErrors);
    raise Exception.Create('edge-update-error');
  end;
  inherited;
end;

destructor TEdgeListen.Destroy;
var LCounts: TEdgeCounts;
begin
  LCounts := Counts;
  if LCounts <> nil then AtomicIncrement(LCounts.ListenEntered);
  inherited;
  if LCounts <> nil then AtomicIncrement(LCounts.ListenDestroyed);
end;

constructor TEdgeSocket.Create(const AMode: string; const ACounts: TEdgeCounts);
begin
  FMode := AMode;
  FCounts := ACounts;
  FPayload := Ord('Q');
  FReply[0] := Ord('O'); FReply[1] := Ord('K');
  FListenSocket := INVALID_SOCKET;
  FGate := TEvent.Create(nil, True, False, '');
  FResume := TEvent.Create(nil, True, False, '');
  FListenFetched := TEvent.Create(nil, True, False, '');
  FListenResume := TEvent.Create(nil, True, False, '');
  inherited Create(1);
end;

destructor TEdgeSocket.Destroy;
begin
  Stop;
  inherited;
  FListenResume.Free; FListenFetched.Free; FResume.Free; FGate.Free;
end;

function TEdgeSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType; const AHost: string;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
var C: TEdgeConnection;
begin
  C := TEdgeConnection.Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
  C.Counts := FCounts;
  AtomicIncrement(FCounts.Connections);
  Result := C;
end;

function TEdgeSocket.CreateListen(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer): ICrossListen;
var L: TEdgeListen;
begin
  L := TEdgeListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
  L.Counts := FCounts;
  FListenSocket := AListenSocket;
  AtomicIncrement(FCounts.Listens);
  Result := L;
end;

procedure TEdgeSocket.TriggerListened(const AListen: ICrossListen);
begin
  inherited;
  if FMode = 'listen-publish-error' then
  begin
    AtomicIncrement(FCounts.PublishErrors);
    raise Exception.Create('edge-publish-error');
  end;
end;

procedure TEdgeSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  FConnection := AConnection;
  AtomicExchange(FConnected, 1);
  inherited;
end;

procedure TEdgeSocket.LogicDisconnected(const AConnection: ICrossConnection);
begin
  AtomicIncrement(FCounts.Disconnects);
  inherited;
end;

procedure TEdgeSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  inherited;
  Check((FMode = 'stop-from-io') and (ALen = 1) and (PByte(ABuf)^ = Ord('R')), '非预期的接收事件');
  FCounts.StopRegisteredBefore := GetRegisteredCountForTest;
  try
    Stop;
    AtomicIncrement(FCounts.StopUnexpected);
  except
    on E: ECrossSocket do AtomicIncrement(FCounts.StopRejected);
    on E: Exception do
    begin
      AtomicIncrement(FCounts.StopUnexpected);
      Line('STOP_ERROR ' + E.ClassName + ': ' + E.Message);
    end;
  end;
  FCounts.StopRegisteredAfter := GetRegisteredCountForTest;
  Check((FCounts.StopRejected = 1) and (FCounts.StopUnexpected = 0), 'IO 自停止未立即以 ECrossSocket 拒绝');
  Check(not AConnection.IsClosed, '自停止拒绝之前已经关闭连接');
  Check((FCounts.StopRegisteredBefore = FCounts.StopRegisteredAfter)
    and (ConnectionsCount = 1) and (ListensCount = 1), '自停止拒绝之前已经改变 owner/注册表');
  Line('STOP_REJECTED alive=1');
  AConnection.SendBuf(@FReply[0], Length(FReply), SendDone(FCounts, True));
end;

function TEdgeSocket.ProcessIoEvent: Boolean;
begin
  Result := inherited ProcessIoEvent;
  if Result and (FMode = 'register-failure') and (AtomicCmpExchange(FConnected, 0, 0) <> 0)
    and (AtomicCmpExchange(FGateEntered, 1, 0) = 0) then
  begin
    FGate.SetEvent;
    Line('GATED');
    if FResume.WaitFor(10000) <> wrSignaled then
    begin
      AtomicIncrement(FCounts.GateTimeout);
      Result := False;
    end;
  end;
end;

function TEdgeSocket.StartListen: Word;
var LPort: Word;
begin
  LPort := 0;
  StartLoop;
  Listen('127.0.0.1', 0,
    procedure(const L: ICrossListen; const OK: Boolean)
    begin
      AtomicIncrement(FCounts.ListenCalls);
      if OK then
      begin
        AtomicIncrement(FCounts.ListenSuccess);
        FListen := L;
        LPort := L.LocalPort;
      end;
    end);
  Check(LPort <> 0, '监听没有成功发布端口');
  if FMode = 'listen-fetched-close' then AtomicExchange(FObserveListen, 1);
  Result := LPort;
end;

procedure TEdgeSocket.EventsReady(const AEvents: PKEvent; const ACount: Integer);
var I: Integer; E: PKEvent;
begin
  if AtomicCmpExchange(FObserveListen, 0, 0) = 0 then Exit;
  E := AEvents;
  for I := 0 to ACount - 1 do
  begin
    // 不读取 udata，不将事件转换为接口，不掩盖已取出事件的寿命问题。
    if (NativeUInt(E^.Ident) = NativeUInt(FListenSocket)) and (E^.Filter = EVFILT_READ)
      and (AtomicCmpExchange(FListenClaimed, 1, 0) = 0) then
    begin
      FListenFetched.SetEvent;
      Line('FETCHED_LISTEN');
      if FListenResume.WaitFor(10000) <> wrSignaled then
        AtomicIncrement(FCounts.GateTimeout);
    end;
    Inc(E);
  end;
end;

procedure TEdgeSocket.RegisterFailure;
var
  C: ICrossConnection;
  LOriginal, LDup, LBeforeErrors: Integer;
begin
  Check(FGate.WaitFor(0) = wrSignaled, 'accept 后屏障尚未命中');
  C := FConnection; FConnection := nil;
  Check(C <> nil, '没有真实 TCP 连接');
  LOriginal := Integer(C.Socket);
  LDup := TestDup(LOriginal);
  Check(LDup >= 0, 'dup 未保留原 TCP socket');
  try
    LBeforeErrors := FCounts.RegistrationErrors;
    // 唯一 worker 已停住。从 close 原 fd 到 Send/Close 收尾之间不创建
    // 文件、socket、事件或线程；日志只写已有 stdout，防止旧数值被重用。
    Check(TestClose(LOriginal) = 0, '关闭受测 fd 失败');
    Check(TestFdFlags(LOriginal, TEST_F_GETFD) = -1, '受测 fd 没有变为无效');
    Send(C, @FPayload, 1, SendDone(FCounts));
    Check(C.IsClosed, '真实 kevent 注册失败没有关闭连接');
    Check((FCounts.Sends = 1) and (FCounts.SendSuccess = 0), '失败发送没有一次 False');
    Check(TestFdFlags(LOriginal, TEST_F_GETFD) = -1, '失败收尾期间原 fd 被意外重用');
    Check(TestFdFlags(LDup, TEST_F_GETFD) >= 0, '失败清理误关了保留的 dup socket');
    {$IFDEF DEBUG}
    Check(FCounts.RegistrationErrors = LBeforeErrors + 1, '未观测到真实 connection kevent 失败日志');
    {$ENDIF}
    Line('REGISTER_FAILED original_invalid=1 dup_alive=1');
  finally
    // 只关闭本测试仍然拥有的 dup；不再次按旧数值关闭原 fd。
    TestClose(LDup);
    C.Close;
    C := nil;
  end;
  FResume.SetEvent;
  Stop;
  Report;
  Check((FCounts.Connections = 1) and (FCounts.Disconnects = 1), '连接或断连次数错误');
  Check((FCounts.ConnectionEntered = 1) and (FCounts.ConnectionDestroyed = 1), '注册失败连接没有析构一次');
end;

procedure TEdgeSocket.CloseFetchedListen;
var L: ICrossListen;
begin
  Check(FListenFetched.WaitFor(0) = wrSignaled, '监听事件尚未被 kevent 取出');
  L := FListen; FListen := nil;
  Check(L <> nil, '没有监听对象');
  L.Close;
  L := nil;
  Check(GetRegisteredCountForTest = 0, '监听关闭后事件注册仍残留');
  Line('CLOSED_LISTEN');
  FListenResume.SetEvent;
  Stop;
  Report;
  Check(FCounts.Connections = 0, '监听关闭后迟到事件仍创建连接');
  Check((FCounts.Listens = 1) and (FCounts.ListenEntered = 1)
    and (FCounts.ListenDestroyed = 1), '监听对象没有析构一次');
end;

procedure TEdgeSocket.PublishFailure;
var
  LExpected, LError: string;
begin
  if FMode = 'listen-update-error' then LExpected := 'edge-update-error'
  else LExpected := 'edge-publish-error';
  FCounts.FailUpdate := FMode = 'listen-update-error';
  LError := '';
  try
    StartListen;
  except
    on E: Exception do LError := E.Message;
  end;
  Check(LError = LExpected, '没有保留预期的监听发布异常: ' + LError);
  Check((FCounts.PublishErrors = 1) and (FCounts.ListenCalls = 0)
    and (FCounts.ListenSuccess = 0), '异常后仍执行监听完成回调或重复发布');
  Check(TestFdFlags(Integer(FListenSocket), TEST_F_GETFD) = -1, '监听发布失败后 socket 仍打开');
  Check((ListensCount = 0) and (GetRegisteredCountForTest = 0), '监听发布异常遗留 owner/注册表记录');
  Stop;
  Report;
  Check((FCounts.Connections = 0) and (FCounts.Listens = 1)
    and (FCounts.ListenEntered = 1) and (FCounts.ListenDestroyed = 1), '监听发布异常未恰好一次析构');
end;

procedure TEdgeSocket.FinishStopFromIo;
begin
  Check((FCounts.StopRejected = 1) and (FCounts.StopUnexpected = 0), '自停止结果错误');
  Check((FCounts.Sends = 1) and (FCounts.SendSuccess = 1), '自停止拒绝后真实回包未成功');
  Check((FConnection <> nil) and not FConnection.IsClosed, '主线程停止前连接已被破坏');
  Stop;
  Report;
  Check((FCounts.Connections = 1) and (FCounts.ConnectionEntered = 1)
    and (FCounts.ConnectionDestroyed = 1) and (FCounts.Disconnects = 1), '主线程停止后连接未恰好一次析构');
end;

procedure TEdgeSocket.Stop;
begin
  if FResume <> nil then FResume.SetEvent;
  if FListenResume <> nil then FListenResume.SetEvent;
  // 自停止检查必须由生产 StopLoop 先执行；测试包装不能预先 CloseAll。
  StopLoop;
  FConnection := nil; FListen := nil;
end;

procedure TEdgeSocket.Report;
begin
  Line('RESULT connections=' + IntToStr(FCounts.Connections)
    + ' connection_entered=' + IntToStr(FCounts.ConnectionEntered)
    + ' connection_destroyed=' + IntToStr(FCounts.ConnectionDestroyed)
    + ' disconnected=' + IntToStr(FCounts.Disconnects)
    + ' listens=' + IntToStr(FCounts.Listens)
    + ' listen_entered=' + IntToStr(FCounts.ListenEntered)
    + ' listen_destroyed=' + IntToStr(FCounts.ListenDestroyed)
    + ' sends=' + IntToStr(FCounts.Sends) + ' send_success=' + IntToStr(FCounts.SendSuccess)
    + ' registration_errors=' + IntToStr(FCounts.RegistrationErrors)
    + ' stop_rejected=' + IntToStr(FCounts.StopRejected)
    + ' stop_unexpected=' + IntToStr(FCounts.StopUnexpected)
    + ' stop_before=' + IntToStr(FCounts.StopRegisteredBefore)
    + ' stop_after=' + IntToStr(FCounts.StopRegisteredAfter)
    + ' owner=' + IntToStr(ConnectionsCount) + ' listen_owner=' + IntToStr(ListensCount)
    + ' registered=' + IntToStr(GetRegisteredCountForTest));
  Check(FCounts.GateTimeout = 0, '事件屏障超时，不属于有效复现');
  Check((ConnectionsCount = 0) and (ListensCount = 0) and (GetRegisteredCountForTest = 0), '最终 owner/注册表未清空');
end;

procedure Run;
var
  LMode, LCommand: string;
  LCounts: TEdgeCounts;
  LSocket: TEdgeSocket;
  LKeep: ICrossSocket;
begin
  LMode := ParamStr(1);
  Check((LMode = 'register-failure') or (LMode = 'listen-fetched-close')
    or (LMode = 'listen-update-error') or (LMode = 'listen-publish-error')
    or (LMode = 'stop-from-io'), '未知测试模式');
  LCounts := TEdgeCounts.Create;
  LSocket := nil;
  try
    _SetCrossLogger(
      procedure(const AText: string)
      begin
        if Pos('connection kevent', AText) > 0 then AtomicIncrement(LCounts.RegistrationErrors);
        Line('LOG ' + AText);
      end);
    CrossSocketLogEnabled := True;
    LSocket := TEdgeSocket.Create(LMode, LCounts);
    LKeep := LSocket;
    CrossKqueueEventsReadyForTest :=
      procedure(const AEvents: PKEvent; const ACount: Integer)
      begin LSocket.EventsReady(AEvents, ACount); end;
    if (LMode = 'listen-update-error') or (LMode = 'listen-publish-error') then
      LSocket.PublishFailure
    else
    begin
      Line('PORT ' + IntToStr(LSocket.StartListen));
      Readln(LCommand);
      Check(LCommand = 'run', '父进程命令错误');
      if LMode = 'register-failure' then LSocket.RegisterFailure
      else if LMode = 'stop-from-io' then LSocket.FinishStopFromIo
      else LSocket.CloseFetchedListen;
    end;
  finally
    if LKeep <> nil then LSocket.Stop;
    CrossKqueueEventsReadyForTest := nil;
    LKeep := nil;
    _SetCrossLogger(nil);
    if (LCounts.Connections = LCounts.ConnectionDestroyed)
      and (LCounts.Listens = LCounts.ListenDestroyed) then LCounts.Free;
  end;
end;

begin
  SetTextCodePage(Output, 65001);
  OutputLock := TCriticalSection.Create;
  try
    try
      Run;
      Line('PASS ' + ParamStr(1));
    except
      on E: Exception do begin Line('FAIL ' + E.ClassName + ': ' + E.Message); Halt(1); end;
    end;
  finally OutputLock.Free; end;
end.
