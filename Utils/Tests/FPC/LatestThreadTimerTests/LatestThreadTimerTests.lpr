program LatestThreadTimerTests;
{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes,
  {$IFDEF FPC}DTF.Types, DTF.Diagnostics,{$ELSE}Diagnostics,{$ENDIF}
  Utils.SyncObjs, Utils.AnonymousThread, Utils.EasyThread, Utils.EasyTimer;

type
  TCaseState = class;
  IProbe = interface
    ['{53DCB84D-977D-47C3-B9CB-17844A61CF7C}']
    procedure Touch;
  end;
  TProbe = class(TInterfacedObject, IProbe)
  public
    State: TCaseState;
    constructor Create(const AState: TCaseState);
    destructor Destroy; override;
    procedure Touch;
  end;
  TBlockingProbe = class(TProbe)
  public
    destructor Destroy; override;
  end;
  TObservedThread = class(TEasyThread)
  public
    State: TCaseState;
    destructor Destroy; override;
  end;
  TObservedTimer = class(TEasyTimer)
  public
    State: TCaseState;
    destructor Destroy; override;
    procedure FreeInstance; override;
  end;
  TWaiter = class(TThread)
  public
    Worker: IEasyThread;
    Timeout: Cardinal;
    Started, Returned: IEvent;
    Answer: Boolean;
    Elapsed: Int64;
    ErrorText: string;
    constructor Create(const AWorker: IEasyThread; const ATimeout: Cardinal);
    procedure Execute; override;
  end;
  TCaseState = class
  public
    Worker, Control: IEasyThread;
    Timer: IEasyTimer;
    Started, ContinueWork, DropWrapper, DroppedWrapper, Done, Destroyed, CaptureReleased, RetiredReady: IEvent;
    CaptureDestroyEntered, ReleaseCaptureDestroy: IEvent;
    Mode, Trace: string;
    ActualThreadID, TimerThreadID: TThreadID;
    Identity, ObjectIdentity: Pointer;
    DestroyCount, CaptureCount, TouchCount, BeforeCount, ProcCount, AfterCount, NewAfterCount: Integer;
    Retired: Pointer;
    RetiredBytes: TBytes;
    WorkerTerminationObserved: Boolean;
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    ExpectedWorkerDestroyed: Integer;
    {$ENDIF}
    Watch: TStopwatch;
    Ticks: array[0..2] of Int64;
    constructor Create(const AMode: string);
    destructor Destroy; override;
    procedure MakeWorker(const TypedCallback: Boolean);
    procedure MakeTimer;
    procedure TimerProc;
    procedure BeforeTimer(const ATimer: IEasyTimer);
    procedure AfterTimer(const ATimer: IEasyTimer);
    procedure NewAfterTimer(const ATimer: IEasyTimer);
    procedure CheckIdentity(const ATimer: IEasyTimer);
    procedure CheckReleasedTimer;
  end;

procedure Check(const Value: Boolean; const Text: string);
begin
  if Value then Exit;
  Writeln('FAIL ', ParamStr(1), ': ', Text); Flush(Output);
  // 工作线程断言也直接结束独立测试进程，不让库的回调异常隔离造成假阳性。
  Halt(1);
end;

procedure Await(const Event: IEvent; const Text: string);
begin
  Check(Event.WaitFor(2500) = TWaitResult.wrSignaled, Text);
end;

constructor TProbe.Create(const AState: TCaseState);
begin inherited Create; State := AState; end;
destructor TProbe.Destroy;
begin AtomicIncrement(State.CaptureCount); State.CaptureReleased.SetEvent; inherited; end;
procedure TProbe.Touch;
begin AtomicIncrement(State.TouchCount); end;

destructor TBlockingProbe.Destroy;
begin
  State.CaptureDestroyEntered.SetEvent;
  Await(State.ReleaseCaptureDestroy, 'capture destructor gate was not released');
  inherited;
end;

destructor TObservedThread.Destroy;
var Saved: TCaseState;
begin
  Saved := State;
  inherited;
  if Saved <> nil then begin AtomicIncrement(Saved.DestroyCount); Saved.Destroyed.SetEvent; end;
end;

destructor TObservedTimer.Destroy;
var Saved: TCaseState;
begin
  Saved := State;
  inherited;
  if Saved <> nil then begin AtomicIncrement(Saved.DestroyCount); Saved.Destroyed.SetEvent; end;
end;

procedure TObservedTimer.FreeInstance;
var Saved: TCaseState; Bytes: Integer;
begin
  Saved := State;
  if Saved = nil then begin inherited; Exit; end;
  Bytes := InstanceSize;
  CleanupInstance;
  // 保留已清理对象的内存，检查最后回调返回后是否仍写入已销毁Timer。
  Saved.Retired := Self;
  SetLength(Saved.RetiredBytes, Bytes);
  Move(PByte(Self)^, Saved.RetiredBytes[0], Bytes);
  Saved.RetiredReady.SetEvent;
end;

constructor TWaiter.Create(const AWorker: IEasyThread; const ATimeout: Cardinal);
begin
  inherited Create(True); FreeOnTerminate := False;
  Worker := AWorker; Timeout := ATimeout;
  Started := TEvent.Create(True, False); Returned := TEvent.Create(True, False);
end;
procedure TWaiter.Execute;
var Clock: TStopwatch;
begin
  Started.SetEvent;
  Clock := TStopwatch.StartNew;
  try Answer := Worker.WaitFor(Timeout);
  except on E: Exception do ErrorText := E.ClassName + ': ' + E.Message; end;
  Elapsed := Clock.ElapsedMilliseconds;
  Returned.SetEvent;
end;

constructor TCaseState.Create(const AMode: string);
begin
  inherited Create; Mode := AMode;
  Started := TEvent.Create(True, False); ContinueWork := TEvent.Create(True, False);
  DropWrapper := TEvent.Create(True, False); DroppedWrapper := TEvent.Create(True, False);
  Done := TEvent.Create(True, False); Destroyed := TEvent.Create(True, False);
  CaptureReleased := TEvent.Create(True, False); Watch := TStopwatch.StartNew;
  RetiredReady := TEvent.Create(True, False);
  CaptureDestroyEntered := TEvent.Create(True, False);
  ReleaseCaptureDestroy := TEvent.Create(True, False);
end;

destructor TCaseState.Destroy;
begin
  ContinueWork.SetEvent; DropWrapper.SetEvent; ReleaseCaptureDestroy.SetEvent;
  if Timer <> nil then begin Timer.Terminate; Timer.WaitFor; Timer := nil; end;
  if Worker <> nil then begin Worker.Terminate; Worker.WaitFor; Worker := nil; end;
  Control := nil;
  // 无观察入口的旧源码无法证明后台已结束，保留隔离内存至独立进程退出。
  if (Retired <> nil) and WorkerTerminationObserved then FreeMem(Retired);
  inherited;
end;

procedure TCaseState.MakeWorker(const TypedCallback: Boolean);
var Probe: IProbe; Obj: TObservedThread; Current: TCaseState;
begin
  Current := Self;
  // 工厂返回后仅worker闭包持有Probe；调用方只保存事件，不另持IProbe。
  if Mode = 'thread-capture-cleanup' then Probe := TBlockingProbe.Create(Self)
  else Probe := TProbe.Create(Self);
  if TypedCallback then
    Obj := TObservedThread.Create(TEasyThreadProc(
      procedure(const AControl: IEasyThread)
      begin
        Current.Control := AControl;
        Current.ActualThreadID := TThread.CurrentThread.ThreadID;
        Current.Started.SetEvent;
        if Current.Mode = 'thread-retained-control' then
        begin
          Await(Current.DropWrapper, 'worker drop gate not released');
          Current.Worker := nil;
          Current.DroppedWrapper.SetEvent;
        end;
        Await(Current.ContinueWork, 'worker continuation gate not released');
        // Delphi POSIX WaitFor会在join前清空底层ThreadID，使用任何waiter启动前记录的身份。
        Check(AControl.ThreadID = Current.ActualThreadID, 'control ThreadID differs from callback entry identity');
        if Current.Mode = 'selected-self-wait' then
        begin
          try
            AControl.WaitFor;
            Check(AControl.WaitFor(0), 'self WaitFor(0) must return True');
            Check(AControl.WaitFor(50), 'self finite wait must return True');
            Current.Worker.WaitFor;
            Check(Current.Worker.WaitFor(50), 'wrapper self finite wait must return True');
          except on E: Exception do Check(False, 'selected self wait raised ' + E.ClassName); end;
        end;
        Probe.Touch;
        Current.Done.SetEvent;
      end))
  else
    Obj := TObservedThread.Create(TAnonymousProc(
      procedure
      begin
        Current.ActualThreadID := TThread.CurrentThread.ThreadID;
        Current.Started.SetEvent;
        Await(Current.ContinueWork, 'anonymous continuation gate not released');
        Probe.Touch; Current.Done.SetEvent;
      end));
  Obj.State := Self;
  Worker := Obj;
end;

procedure TCaseState.CheckIdentity(const ATimer: IEasyTimer);
var Base: IInterface; RoundTrip: IEasyTimer;
begin
  Check(Pointer(ATimer) = Identity, 'event argument is not the actual Timer interface');
  Check(Pointer(ATimer as TEasyTimer) = ObjectIdentity, 'event argument belongs to another Timer object');
  // 显式QueryInterface避免隐式接口临时量掩盖最后引用释放，并覆盖基接口映射。
  Check(ATimer.QueryInterface(IInterface, Base) = 0, 'Timer has no base interface');
  Check(Base.QueryInterface(IEasyTimer, RoundTrip) = 0, 'base interface cannot return to Timer');
  Check((Pointer(RoundTrip) = Identity) and (Pointer(RoundTrip as TEasyTimer) = ObjectIdentity),
    'base interface round trip changed Timer identity');
  RoundTrip := nil; Base := nil;
  Check(ATimer.WaitFor(0) and ATimer.WaitFor(1), 'Timer self wait must be a successful no-op');
  Check(ATimer.Name = 'latest-api', 'event Timer properties differ');
  if TimerThreadID = TThreadID(0) then TimerThreadID := TThread.CurrentThread.ThreadID;
  Check(TimerThreadID = TThread.CurrentThread.ThreadID, 'timer stages changed thread');
end;

procedure TCaseState.BeforeTimer(const ATimer: IEasyTimer);
begin
  CheckIdentity(ATimer); Inc(BeforeCount); Trace := Trace + 'B';
  if (Mode = 'timer-hooks') and (BeforeCount = 2) then
    raise Exception.Create('expected Before exception');
  if Mode = 'timer-release-before' then Timer := nil;
end;

procedure TCaseState.AfterTimer(const ATimer: IEasyTimer);
begin
  CheckIdentity(ATimer); Inc(AfterCount); Trace := Trace + 'A';
  if Mode = 'timer-release-after' then Timer := nil;
  if Mode <> 'timer-hooks' then Done.SetEvent;
end;

procedure TCaseState.NewAfterTimer(const ATimer: IEasyTimer);
begin
  CheckIdentity(ATimer); Inc(NewAfterCount); Trace := Trace + 'N';
  ATimer.Terminate;
  Done.SetEvent;
end;

procedure TCaseState.TimerProc;
begin
  if Mode = 'timer-install-after' then TimerThreadID := TThread.CurrentThread.ThreadID;
  Check(TimerThreadID = TThread.CurrentThread.ThreadID, 'Proc and hooks changed thread');
  Inc(ProcCount); Trace := Trace + 'P';
  if Mode = 'timer-timeout-fallback' then
  begin
    Started.SetEvent;
    Await(ContinueWork, 'timer callback gate not released');
    Timer.Terminate;
  end;
  if (Mode = 'timer-hooks') and (BeforeCount = 3) then
  begin
    Timer.AfterExecute := NewAfterTimer;
    raise Exception.Create('expected Proc exception after replacing After');
  end;
  if Mode = 'timer-release-proc' then Timer := nil;
  if Mode = 'timer-install-after' then
  begin
    // 本轮开始时无事件，setter必须立即补周期引用，不能等下一个周期。
    Timer.AfterExecute := AfterTimer;
    Timer := nil;
    Check(DestroyCount = 0, 'first After setter did not keep the current Timer cycle alive');
  end;
end;

procedure TCaseState.MakeTimer;
var Probe: IProbe; Obj: TObservedTimer; Current: TCaseState;
begin
  {$IFDEF CROSS_EASY_THREAD_TESTS}
  ExpectedWorkerDestroyed := GetEasyThreadDestroyedCountForTest + 1;
  {$ENDIF}
  Current := Self; Probe := TProbe.Create(Self);
  // 先暂停，以便身份、事件和观察对象全部就绪后才允许首次执行。
  Obj := TObservedTimer.Create('latest-api', TProc(procedure
    begin Probe.Touch; Current.TimerProc; end), Int64(0), Int64(20), True);
  Obj.State := Self; Timer := Obj; Identity := Pointer(Timer); ObjectIdentity := Pointer(Obj);
  if Mode <> 'timer-install-after' then
  begin
    Timer.BeforeExecute := BeforeTimer; Timer.AfterExecute := AfterTimer;
  end;
end;

procedure TCaseState.CheckReleasedTimer;
{$IFDEF CROSS_EASY_THREAD_TESTS}
var Deadline: TStopwatch;
{$ENDIF}
begin
  Await(Destroyed, 'Timer wrapper did not destroy');
  Await(CaptureReleased, 'Timer callback capture did not release');
  Await(RetiredReady, 'retired Timer snapshot was not ready');
  {$IFDEF CROSS_EASY_THREAD_TESTS}
  Deadline := TStopwatch.StartNew;
  // 轮询真实析构计数；等待时间本身不是worker已停止访问Timer的证据。
  while GetEasyThreadDestroyedCountForTest < ExpectedWorkerDestroyed do
  begin
    Check(Deadline.ElapsedMilliseconds < 2500, 'Timer worker did not actually destroy');
    TThread.Sleep(1);
  end;
  WorkerTerminationObserved := True;
  Writeln('OBSERVATION worker-termination=confirmed'); Flush(Output);
  {$ELSE}
  Writeln('OBSERVATION worker-termination=unavailable; snapshot is not proof of no later access'); Flush(Output);
  {$ENDIF}
  Check((DestroyCount = 1) and (CaptureCount = 1), 'Timer/capture release count differs');
  Check((Retired <> nil) and CompareMem(Retired, @RetiredBytes[0], Length(RetiredBytes)),
    'worker wrote to retired Timer memory');
end;

procedure TestThreadAPI;
var C: TCaseState; I: Integer; Tick: Int64;
begin
  for I := 0 to 1 do
  begin
    C := TCaseState.Create('thread-api');
    try
      C.MakeWorker(I = 1); Await(C.Started, 'worker did not start');
      Check((C.Worker.ThreadID <> TThreadID(0)) and (C.Worker.ThreadID = C.ActualThreadID), 'wrapper ThreadID differs');
      Check(not C.Worker.WaitFor(0), 'zero timeout reported unfinished worker complete');
      Tick := C.Watch.ElapsedMilliseconds;
      Check(not C.Worker.WaitFor(50), 'finite timeout reported unfinished worker complete');
      Check((C.Watch.ElapsedMilliseconds - Tick >= 30) and (C.Watch.ElapsedMilliseconds - Tick < 1000),
        'finite timeout returned prematurely or exceeded bounded budget');
      Check(not C.Worker.Terminated, 'timeout terminated worker');
      if I = 1 then Check((C.Control.ThreadID = C.ActualThreadID) and not C.Control.WaitFor(0), 'control state differs');
      C.ContinueWork.SetEvent; Await(C.Done, 'worker did not finish');
      Check(C.Worker.WaitFor(2500) and C.Worker.WaitFor(0), 'completed/repeated wait did not succeed');
      C.Worker.WaitFor; C.Worker := nil;
      Await(C.Destroyed, 'thread wrapper did not release'); Await(C.CaptureReleased, 'thread capture did not release');
      Check((C.DestroyCount = 1) and (C.CaptureCount = 1) and (C.TouchCount = 1), 'thread lifecycle count differs');
    finally C.Free; end;
  end;
end;

procedure TestSelectedSelfWait;
var C: TCaseState;
begin
  C := TCaseState.Create('selected-self-wait');
  try
    C.MakeWorker(True); Await(C.Started, 'self-wait worker did not start');
    C.ContinueWork.SetEvent; Await(C.Done, 'self wait did not continue');
    Check(C.Worker.WaitFor(2500), 'external wait after self no-op failed');
    C.Worker := nil; Await(C.CaptureReleased, 'self wait retained capture');
    Check(C.TouchCount = 1, 'code after self wait did not execute');
  finally C.Free; end;
end;

procedure TestMixedWaiters;
var C: TCaseState; Infinite, Finite: TWaiter;
begin
  C := TCaseState.Create('thread-mixed'); Infinite := nil; Finite := nil;
  try
    C.MakeWorker(True); Await(C.Started, 'mixed worker did not start');
    Infinite := TWaiter.Create(C.Worker, High(Cardinal)); Infinite.Start;
    Await(Infinite.Started, 'infinite waiter did not enter');
    Check(Infinite.Returned.WaitFor(80) = TWaitResult.wrTimeout, 'infinite wait returned before task');
    Finite := TWaiter.Create(C.Control, 80); Finite.Start;
    Await(Finite.Returned, 'finite wait blocked behind infinite waiter');
    Finite.WaitFor;
    Check((Finite.ErrorText = '') and not Finite.Answer, 'finite mixed wait result differs');
    Check((Finite.Elapsed >= 50) and (Finite.Elapsed < 1000), 'mixed finite waiter did not respect its own timeout');
    Check(not C.Worker.WaitFor(0), 'mixed zero poll completed too early');
    C.Worker.Terminate; Check(C.Worker.Terminated, 'Terminate blocked behind waiter');
    C.ContinueWork.SetEvent; Await(Infinite.Returned, 'infinite waiter did not finish');
    Infinite.WaitFor; Check((Infinite.ErrorText = '') and Infinite.Answer, 'infinite result differs');
    Check(C.Worker.WaitFor(High(Cardinal) - 1), 'large finite wait overflowed');
    Finite.Free; Finite := nil; Infinite.Free; Infinite := nil;
  finally C.ContinueWork.SetEvent; Finite.Free; Infinite.Free; C.Free; end;
end;

procedure TestRetainedControl;
var C: TCaseState; ID: TThreadID;
begin
  C := TCaseState.Create('thread-retained-control');
  try
    C.MakeWorker(True); Await(C.Started, 'retained-control worker did not start');
    ID := C.Control.ThreadID;
    C.DropWrapper.SetEvent; Await(C.DroppedWrapper, 'worker wrapper release did not return');
    Await(C.Destroyed, 'worker wrapper did not destroy');
    Check((C.Worker = nil) and (C.DestroyCount = 1), 'wrapper remained retained by control');
    Check(C.Control.ThreadID = ID, 'retained control lost ThreadID');
    Check(not C.Control.WaitFor(0), 'control reported complete while callback is still gated');
    C.Control.Terminate; Check(C.Control.Terminated, 'retained control Terminate unsafe');
    C.ContinueWork.SetEvent; Await(C.Done, 'detached worker did not continue');
    Check(C.Control.WaitFor(2500) and C.Control.WaitFor(0), 'retained completed control wait unsafe');
    C.Control := nil; Await(C.CaptureReleased, 'detached thread retained callback capture');
    Check((C.CaptureCount = 1) and (C.TouchCount = 1), 'detached callback lifecycle differs');
  finally C.Free; end;
end;

procedure TestThreadCaptureCleanup;
var
  C: TCaseState;
  {$IFDEF CROSS_EASY_THREAD_TESTS}
  ExpectedDestroyed: Integer;
  {$ENDIF}
begin
  C := TCaseState.Create('thread-capture-cleanup');
  try
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    ExpectedDestroyed := GetEasyThreadDestroyedCountForTest + 1;
    {$ENDIF}
    C.MakeWorker(True);
    Await(C.Started, 'capture cleanup worker did not start');
    // MakeWorker的接口局部量已经退出作用域，才允许Proc返回并开始闭包清理。
    C.ContinueWork.SetEvent;
    Await(C.CaptureDestroyEntered, 'worker did not begin releasing its only capture');
    Check((C.Done.WaitFor(0) = TWaitResult.wrSignaled) and (C.TouchCount = 1)
      and (C.CaptureCount = 0), 'capture gate did not follow Proc return');
    Check(not C.Worker.WaitFor(0), 'wrapper reported completion while capture destructor was blocked');
    Check(not C.Control.WaitFor(0), 'control reported completion while capture destructor was blocked');
    Check(not C.Worker.WaitFor(30), 'wrapper finite wait ignored unfinished capture cleanup');
    Check(not C.Control.WaitFor(30), 'control finite wait ignored unfinished capture cleanup');
    Check(C.CaptureCount = 0, 'capture destructor passed its unreleased gate');
    C.ReleaseCaptureDestroy.SetEvent;
    Check(C.Worker.WaitFor(2500) and C.Control.WaitFor(2500), 'finite wait did not complete after capture cleanup');
    Await(C.CaptureReleased, 'capture did not finish releasing');
    C.Worker.WaitFor;
    C.Worker := nil; C.Control := nil;
    Await(C.Destroyed, 'capture cleanup wrapper did not release');
    Check((C.DestroyCount = 1) and (C.CaptureCount = 1) and (C.TouchCount = 1),
      'capture cleanup resource release was not exactly once');
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    Check(GetEasyThreadDestroyedCountForTest = ExpectedDestroyed, 'capture cleanup worker destroy count differs');
    {$ENDIF}
  finally C.ReleaseCaptureDestroy.SetEvent; C.Free; end;
end;

procedure TestTimerHooks;
var C: TCaseState;
begin
  C := TCaseState.Create('timer-hooks');
  try
    C.MakeTimer; C.Timer.Paused := False; Await(C.Done, 'timer hook sequence did not finish');
    Check(C.Timer.WaitFor(2500) and C.Timer.Finished, 'timer hook wait did not finish');
    Check((C.Trace = 'BPABBPN') and (C.BeforeCount = 3) and (C.ProcCount = 2)
      and (C.AfterCount = 1) and (C.NewAfterCount = 1), 'Before/Proc exception or live After replacement differs: ' + C.Trace);
    C.Timer := nil; C.CheckReleasedTimer;
  finally C.Free; end;
end;

procedure TestTimerTimeout;
var C: TCaseState;
begin
  C := TCaseState.Create('timer-timeout-fallback');
  try
    C.MakeTimer; C.Timer.Timeout := 40; C.Timer.Paused := False;
    Await(C.Started, 'timeout callback did not start');
    Check(C.Done.WaitFor(100) = TWaitResult.wrTimeout, 'gated timer completed too early');
    Check(C.Timer.IsTimeout and C.Timer.IsTimeout(0) and C.Timer.IsTimeout(-1), 'configured timeout fallback differs');
    Check(not C.Timer.IsTimeout(3000), 'explicit timeout did not override configuration');
    Check(not C.Timer.WaitFor(0) and not C.Timer.WaitFor(30), 'timer timeout wait completed too early');
    C.Timer.Timeout := 0;
    Check(not C.Timer.IsTimeout and C.Timer.IsTimeout(40), 'disabled/default versus explicit timeout differs');
    C.Timer.Timeout := -1; Check(not C.Timer.IsTimeout, 'negative configured timeout should disable');
    C.ContinueWork.SetEvent; Await(C.Done, 'timeout callback did not finish');
    Check(C.Timer.WaitFor(2500) and C.Timer.WaitFor(0) and C.Timer.Finished, 'timer completed/repeated wait failed');
    C.Timer := nil; C.CheckReleasedTimer;
  finally C.Free; end;
end;

procedure TestSelectedInterval;
var C: TCaseState; Interval: Int64; I: Integer;
begin
  for I := 0 to 1 do
  begin
    if I = 0 then Interval := 0 else Interval := -1;
    C := TCaseState.Create('selected-interval');
    try
      C.Timer := TEasyTimer.Create('selected-interval', TProc(procedure
        var N: Integer;
        begin
          N := AtomicIncrement(C.ProcCount);
          if N <= 3 then C.Ticks[N - 1] := C.Watch.ElapsedMilliseconds;
          if N = 3 then begin C.Timer.Terminate; C.Done.SetEvent; end;
        end), Int64(0), Interval, True);
      C.Timer.Paused := False; Await(C.Done, 'nonpositive interval did not run');
      Check(C.Timer.WaitFor(2500), 'nonpositive interval did not stop');
      Check((C.ProcCount = 3) and (C.Ticks[1] - C.Ticks[0] >= 8)
        and (C.Ticks[2] - C.Ticks[1] >= 8), 'nonpositive interval formed a busy loop');
      C.Timer := nil;
    finally C.Free; end;
  end;
end;

procedure TestTimerRelease(const Stage: string);
var C: TCaseState;
begin
  C := TCaseState.Create('timer-release-' + Stage);
  try
    C.MakeTimer; C.Timer.Paused := False;
    Await(C.Done, 'accepted timer cycle did not finish after last external release');
    C.CheckReleasedTimer;
    Check((C.Timer = nil) and (C.Trace = 'BPA') and (C.BeforeCount = 1)
      and (C.ProcCount = 1) and (C.AfterCount = 1), 'release changed accepted callback order or leaked timer');
  finally C.Free; end;
end;

procedure TestTimerBaseRelease;
var C: TCaseState; Base: IInterface;
begin
  C := TCaseState.Create('timer-base-release'); Base := nil;
  try
    C.MakeTimer;
    Check(C.Timer.Paused and Assigned(C.Timer.BeforeExecute) and Assigned(C.Timer.AfterExecute),
      'base release setup must be paused with hooks');
    Check(C.Timer.QueryInterface(IInterface, Base) = 0, 'cannot retain Timer through base interface');
    C.Timer := nil;
    Check(C.DestroyCount = 0, 'Timer destroyed while base interface remained');
    Base := nil;
    C.CheckReleasedTimer;
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    Check(GetEasyThreadDestroyedCountForTest = C.ExpectedWorkerDestroyed, 'base release worker destroy count differs');
    {$ENDIF}
    Check((C.Trace = '') and (C.TouchCount = 0) and (C.BeforeCount = 0)
      and (C.ProcCount = 0) and (C.AfterCount = 0), 'paused Timer executed while releasing base interface');
  finally Base := nil; C.Free; end;
end;

procedure TestTimerInstallAfter;
var C: TCaseState;
begin
  C := TCaseState.Create('timer-install-after');
  try
    C.MakeTimer;
    Check(not Assigned(C.Timer.BeforeExecute) and not Assigned(C.Timer.AfterExecute),
      'first After installation must start without hooks');
    C.Timer.Paused := False;
    Await(C.Done, 'new After callback did not complete after last external release');
    C.CheckReleasedTimer;
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    Check(GetEasyThreadDestroyedCountForTest = C.ExpectedWorkerDestroyed, 'installed After worker destroy count differs');
    {$ENDIF}
    Check((C.Timer = nil) and (C.Trace = 'PA') and (C.BeforeCount = 0)
      and (C.ProcCount = 1) and (C.AfterCount = 1), 'first After installation changed current callback order');
  finally C.Free; end;
end;

var Mode: string;
begin
  try
    Mode := ParamStr(1);
    if Mode = 'thread-api' then TestThreadAPI
    else if Mode = 'selected-self-wait' then TestSelectedSelfWait
    else if Mode = 'thread-mixed' then TestMixedWaiters
    else if Mode = 'thread-retained-control' then TestRetainedControl
    else if Mode = 'thread-capture-cleanup' then TestThreadCaptureCleanup
    else if Mode = 'timer-hooks' then TestTimerHooks
    else if Mode = 'timer-timeout-fallback' then TestTimerTimeout
    else if Mode = 'selected-nonpositive-interval' then TestSelectedInterval
    else if Mode = 'timer-release-before' then TestTimerRelease('before')
    else if Mode = 'timer-release-proc' then TestTimerRelease('proc')
    else if Mode = 'timer-release-after' then TestTimerRelease('after')
    else if Mode = 'timer-base-release' then TestTimerBaseRelease
    else if Mode = 'timer-install-after' then TestTimerInstallAfter
    else raise Exception.Create('unknown case');
    Writeln('PASS ', Mode);
  except
    on E: Exception do begin Writeln('FAIL ', ParamStr(1), ': ', E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
