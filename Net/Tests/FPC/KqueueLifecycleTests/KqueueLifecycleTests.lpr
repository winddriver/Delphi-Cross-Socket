program KqueueLifecycleTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket.Kqueue, BSD.kqueue;

type
  TLifetimeCounts = class
  public
    Created, DestroyEntered, DestroyCompleted, Disconnected: Integer;
    SendCalls, SendSuccess, SendDuplicates, ReceiveCalls, GateTimeout: Integer;
    ExpectedSends: Integer;
    SendSeen: TArray<Integer>;
    SendsDone: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure PrepareSends(const ACount: Integer);
  end;

  TTrackedConnection = class(TKqueueConnection)
  public
    Counts: TLifetimeCounts;
    destructor Destroy; override;
    function ReferenceCountForTest: Integer;
  end;

  TTestSocket = class(TKqueueCrossSocket)
  private
    FCounts: TLifetimeCounts;
    FConnection: ICrossConnection;
    FConnected, FGateEntered: Integer;
    FGate, FResume: TEvent;
    FReadFetched, FWriteFetched, FReadResume, FWriteResume: TEvent;
    FReadClaimed, FWriteClaimed, FObserveEvents: Integer;
    FReadThread, FWriteThread: NativeUInt;
    FTargetSocket: TSocket;
    FWantRead, FWantWrite: Boolean;
    FPayload: Byte;
    procedure QueueSends(const AConnection: ICrossConnection; const ACount: Integer);
    procedure CheckFinished(const AExpectedSends, AExpectedSuccess: Integer);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
    procedure LogicReceived(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;
    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(const ACounts: TLifetimeCounts; const AWorkers: Integer); reintroduce;
    destructor Destroy; override;
    function StartListen: Word;
    procedure Exercise(const AMode: string; const ASendCount: Integer);
    procedure ExerciseFetched(const AMode: string);
    procedure EventsReady(const AEvents: PKEvent; const ACount: Integer);
    procedure Stop;
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
  try
    Writeln(AText);
    Flush(Output);
  finally
    OutputLock.Leave;
  end;
end;

constructor TLifetimeCounts.Create;
begin
  inherited;
  SendsDone := TEvent.Create(nil, True, False, '');
end;

destructor TLifetimeCounts.Destroy;
begin
  SendsDone.Free;
  inherited;
end;

procedure TLifetimeCounts.PrepareSends(const ACount: Integer);
begin
  ExpectedSends := ACount;
  SetLength(SendSeen, ACount);
  SendsDone.ResetEvent;
end;

function MakeSendCallback(const ACounts: TLifetimeCounts;
  const AIndex: Integer): TCrossConnectionCallback;
begin
  // 独立闭包仅保存 ledger 与序号，不捕获连接接口或 fixture 局部变量。
  Result := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if AtomicIncrement(ACounts.SendSeen[AIndex]) <> 1 then
        AtomicIncrement(ACounts.SendDuplicates);
      if ASuccess then AtomicIncrement(ACounts.SendSuccess);
      if AtomicIncrement(ACounts.SendCalls) = ACounts.ExpectedSends then
        ACounts.SendsDone.SetEvent;
    end;
end;

destructor TTrackedConnection.Destroy;
var
  LCounts: TLifetimeCounts;
begin
  LCounts := Counts;
  if LCounts <> nil then AtomicIncrement(LCounts.DestroyEntered);
  inherited;
  if LCounts <> nil then AtomicIncrement(LCounts.DestroyCompleted);
end;

function TTrackedConnection.ReferenceCountForTest: Integer;
begin
  Result := RefCount;
end;

constructor TTestSocket.Create(const ACounts: TLifetimeCounts; const AWorkers: Integer);
begin
  FCounts := ACounts;
  FPayload := Ord('Q');
  FGate := TEvent.Create(nil, True, False, '');
  FResume := TEvent.Create(nil, True, False, '');
  FReadFetched := TEvent.Create(nil, True, False, '');
  FWriteFetched := TEvent.Create(nil, True, False, '');
  FReadResume := TEvent.Create(nil, True, False, '');
  FWriteResume := TEvent.Create(nil, True, False, '');
  inherited Create(AWorkers);
end;

destructor TTestSocket.Destroy;
begin
  Stop;
  FConnection := nil;
  inherited;
  FWriteResume.Free;
  FReadResume.Free;
  FWriteFetched.Free;
  FReadFetched.Free;
  FResume.Free;
  FGate.Free;
end;

function TTestSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType; const AHost: string;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
var
  LConnection: TTrackedConnection;
begin
  LConnection := TTrackedConnection.Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
  LConnection.Counts := FCounts;
  AtomicIncrement(FCounts.Created);
  Result := LConnection;
end;

procedure TTestSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  FConnection := AConnection;
  FTargetSocket := AConnection.Socket;
  AtomicExchange(FConnected, 1);
  inherited;
end;

procedure TTestSocket.LogicDisconnected(const AConnection: ICrossConnection);
begin
  AtomicIncrement(FCounts.Disconnected);
  inherited;
end;

procedure TTestSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  AtomicIncrement(FCounts.ReceiveCalls);
  inherited;
end;

function TTestSocket.ProcessIoEvent: Boolean;
begin
  Result := inherited ProcessIoEvent;
  // 先让整个 accept 批次返回，确保 inherited 中的临时接口已释放，
  // READ 已经注册；单 worker 在进入下一次 kevent 前停住。
  if Result and (AtomicCmpExchange(FConnected, 0, 0) <> 0)
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

function TTestSocket.StartListen: Word;
var
  LReady: TEvent;
  LPort: Word;
begin
  LReady := TEvent.Create(nil, True, False, '');
  LPort := 0;
  try
    StartLoop;
    Listen('127.0.0.1', 0,
      procedure(const AListen: ICrossListen; const ASuccess: Boolean)
      begin
        if AListen = nil then
          Line('LISTEN success=' + IntToStr(Ord(ASuccess)) + ' listen=nil')
        else
          Line('LISTEN success=' + IntToStr(Ord(ASuccess))
            + ' port=' + IntToStr(AListen.LocalPort)
            + ' socket=' + IntToStr(AListen.Socket));
        if ASuccess and (AListen <> nil) then LPort := AListen.LocalPort;
        LReady.SetEvent;
      end);
    Check((LReady.WaitFor(5000) = wrSignaled) and (LPort <> 0), '监听失败');
    Result := LPort;
  finally
    LReady.Free;
  end;
end;

procedure TTestSocket.QueueSends(const AConnection: ICrossConnection; const ACount: Integer);
var
  I: Integer;
begin
  FCounts.PrepareSends(ACount);
  for I := 0 to ACount - 1 do
    Send(AConnection, @FPayload, 1, MakeSendCallback(FCounts, I));
end;

procedure TTestSocket.CheckFinished(const AExpectedSends, AExpectedSuccess: Integer);
var
  I: Integer;
begin
  Line('RESULT created=' + IntToStr(FCounts.Created)
    + ' entered=' + IntToStr(FCounts.DestroyEntered)
    + ' destroyed=' + IntToStr(FCounts.DestroyCompleted)
    + ' disconnected=' + IntToStr(FCounts.Disconnected)
    + ' calls=' + IntToStr(FCounts.SendCalls)
    + ' success=' + IntToStr(FCounts.SendSuccess)
    + ' duplicates=' + IntToStr(FCounts.SendDuplicates)
    + ' received=' + IntToStr(FCounts.ReceiveCalls)
    {$IFDEF CROSS_KQUEUE_TESTS}
    + ' registered=' + IntToStr(GetRegisteredCountForTest)
    {$ENDIF}
    + ' owner=' + IntToStr(ConnectionsCount));
  Check(FCounts.GateTimeout = 0, '屏障超时，不能作为有效复现');
  Check((FCounts.Created = 1) and (FCounts.Disconnected = 1), '连接创建/关闭通知不唯一');
  Check(ConnectionsCount = 0, '连接仍留在 owner 表中');
  {$IFDEF CROSS_KQUEUE_TESTS}
  Check(GetRegisteredCountForTest = 0, '关闭后事件注册表仍持有对象');
  {$ENDIF}
  Check((FCounts.SendCalls = AExpectedSends) and (FCounts.SendSuccess = AExpectedSuccess), '发送完成结果或次数错误');
  Check(FCounts.SendDuplicates = 0, '同一发送重复结算');
  for I := 0 to Length(FCounts.SendSeen) - 1 do
    Check(FCounts.SendSeen[I] = 1, '某个发送没有恰好一次完成');
  Check(FCounts.ReceiveCalls = 0, '关闭后迟到 READ 仍进入业务');
  Check((FCounts.DestroyEntered = 1) and (FCounts.DestroyCompleted = 1), 'owner 已清空，但连接没有恰好一次析构');
end;

procedure TTestSocket.Exercise(const AMode: string; const ASendCount: Integer);
var
  LConnection: ICrossConnection;
  LBefore, LAfter, LExpectedSends, LExpectedSuccess, I: Integer;
  LCommand: string;
begin
  Check(FGate.WaitFor(5000) = wrSignaled, '工作线程未进入 accept 后屏障');
  LConnection := FConnection;
  Check(LConnection <> nil, '没有真实连接');
  FConnection := nil;
  LExpectedSends := 0;
  LExpectedSuccess := 0;
  LBefore := (LConnection as TTrackedConnection).ReferenceCountForTest;
  if (AMode = 'queued-sends') or (AMode = 'queued-sends-drain') then
  begin
    LExpectedSends := ASendCount;
    QueueSends(LConnection, ASendCount);
  end;
  LAfter := (LConnection as TTrackedConnection).ReferenceCountForTest;
  Line('REFS before=' + IntToStr(LBefore) + ' after=' + IntToStr(LAfter)
    + ' delta=' + IntToStr(LAfter - LBefore));
  if AMode = 'queued-sends-drain' then
  begin
    LExpectedSuccess := ASendCount;
    FResume.SetEvent;
    Check(FCounts.SendsDone.WaitFor(5000) = wrSignaled, '排队数据没有全部完成');
    Line('DRAINED');
    // 父进程逐字节验证实际接收内容后才允许主动关闭。
    Readln(LCommand);
    Check(LCommand = 'close', '发送完成后的关闭命令错误');
  end;
  LConnection.Close;
  if AMode = 'repeated-close' then
    for I := 1 to 31 do LConnection.Close;
  LConnection := nil;
  FResume.SetEvent;
  StopLoop;
  CheckFinished(LExpectedSends, LExpectedSuccess);
  if LExpectedSends > 0 then
    Check(LAfter - LBefore <= 1, '同一 WRITE 注册重复累积连接引用');
end;

procedure TTestSocket.EventsReady(const AEvents: PKEvent; const ACount: Integer);
var
  I: Integer;
  LEvent: PKEvent;
begin
  if AtomicCmpExchange(FObserveEvents, 0, 0) = 0 then Exit;
  LEvent := AEvents;
  for I := 0 to ACount - 1 do
  begin
    // 只按 native fd/filter 选择屏障，不读取 uData，不取得任何连接强引用。
    if NativeUInt(LEvent^.Ident) = NativeUInt(FTargetSocket) then
    begin
      if FWantRead and (LEvent^.Filter = EVFILT_READ)
        and (AtomicCmpExchange(FReadClaimed, 1, 0) = 0) then
      begin
        FReadThread := NativeUInt(TThread.Current.ThreadID);
        FReadFetched.SetEvent;
        Line('FETCHED_READ thread=' + IntToStr(Int64(FReadThread)));
        if FReadResume.WaitFor(10000) <> wrSignaled then
          AtomicIncrement(FCounts.GateTimeout);
      end;
      if FWantWrite and (LEvent^.Filter = EVFILT_WRITE)
        and (AtomicCmpExchange(FWriteClaimed, 1, 0) = 0) then
      begin
        FWriteThread := NativeUInt(TThread.Current.ThreadID);
        FWriteFetched.SetEvent;
        Line('FETCHED_WRITE thread=' + IntToStr(Int64(FWriteThread)));
        if FWriteResume.WaitFor(10000) <> wrSignaled then
          AtomicIncrement(FCounts.GateTimeout);
      end;
    end;
    Inc(LEvent);
  end;
end;

procedure TTestSocket.ExerciseFetched(const AMode: string);
var
  LConnection: ICrossConnection;
  LExpectedSends: Integer;
  LCommand: string;
begin
  Check(FGate.WaitFor(5000) = wrSignaled, '工作线程未进入 accept 后屏障');
  LConnection := FConnection;
  Check(LConnection <> nil, '没有真实连接');
  FConnection := nil;
  FWantRead := AMode <> 'fetched-write-close';
  FWantWrite := AMode <> 'fetched-read-close';
  LExpectedSends := 0;
  AtomicExchange(FObserveEvents, 1);
  if FWantWrite then
  begin
    LExpectedSends := 1;
    QueueSends(LConnection, 1);
  end;
  FResume.SetEvent;
  Line('PREPARED');
  // 父进程只在真实 kevent 已返回预期过滤器后发关闭命令。
  Readln(LCommand);
  Check(LCommand = 'close', '事件取出后的关闭命令错误');
  if FWantRead then Check(FReadFetched.WaitFor(0) = wrSignaled, 'READ 事件尚未取出');
  if FWantWrite then Check(FWriteFetched.WaitFor(0) = wrSignaled, 'WRITE 事件尚未取出');
  if FWantRead and FWantWrite then
    Check(FReadThread <> FWriteThread, '读写并未由不同 worker 取出');
  LConnection.Close;
  LConnection := nil;
  Line('CLOSED_FETCHED');
  FReadResume.SetEvent;
  FWriteResume.SetEvent;
  StopLoop;
  AtomicExchange(FObserveEvents, 0);
  CheckFinished(LExpectedSends, 0);
end;

procedure TTestSocket.Stop;
begin
  if FResume <> nil then FResume.SetEvent;
  if FReadResume <> nil then FReadResume.SetEvent;
  if FWriteResume <> nil then FWriteResume.SetEvent;
  StopLoop;
end;

procedure Run;
var
  LCounts: TLifetimeCounts;
  LSocket: TTestSocket;
  LKeep: ICrossSocket;
  LMode, LCommand: string;
  LSendCount, LWorkers: Integer;
  LFetched: Boolean;
begin
  _SetCrossLogger(
    procedure(const AText: string)
    begin
      Line('LOG ' + AText);
    end);
  CrossSocketLogEnabled := True;
  try
    LMode := ParamStr(1);
    LFetched := Copy(LMode, 1, 8) = 'fetched-';
    Check((LMode = 'idle-close') or (LMode = 'queued-sends') or (LMode = 'repeated-close')
      or (LMode = 'queued-sends-drain') or (LMode = 'fetched-read-close')
      or (LMode = 'fetched-write-close') or (LMode = 'fetched-read-write-close'), '未知测试模式');
    {$IFNDEF CROSS_KQUEUE_TESTS}
    Check(not LFetched, '事件在途用例需要 CROSS_KQUEUE_TESTS');
    {$ENDIF}
    LSendCount := StrToIntDef(ParamStr(2), 64);
    Check((LSendCount > 0) and (LSendCount <= 1024), '发送数量必须在 1..1024');
    if LMode = 'fetched-read-write-close' then LWorkers := 2 else LWorkers := 1;
    LCounts := TLifetimeCounts.Create;
    LSocket := nil;
    try
      LSocket := TTestSocket.Create(LCounts, LWorkers);
      LKeep := LSocket;
      {$IFDEF CROSS_KQUEUE_TESTS}
      CrossKqueueEventsReadyForTest :=
        procedure(const AEvents: PKEvent; const ACount: Integer)
        begin
          LSocket.EventsReady(AEvents, ACount);
        end;
      {$ENDIF}
      Line('PORT ' + IntToStr(LSocket.StartListen));
      Readln(LCommand);
      Check(LCommand = 'run', '父进程命令错误');
      if LFetched then LSocket.ExerciseFetched(LMode)
      else LSocket.Exercise(LMode, LSendCount);
    finally
      if LKeep <> nil then LSocket.Stop;
      {$IFDEF CROSS_KQUEUE_TESTS}
      CrossKqueueEventsReadyForTest := nil;
      {$ENDIF}
      LKeep := nil;
      // 红例不人工调用 _Release；遗留连接的 ledger 保留至独立进程退出。
      if LCounts.Created = LCounts.DestroyCompleted then LCounts.Free;
    end;
  finally
    _SetCrossLogger(nil);
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
  finally
    OutputLock.Free;
  end;
end.
