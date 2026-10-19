program EasyTimerTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, Math,
  {$IFDEF FPC}DTF.Diagnostics, DTF.Types,{$ELSE}Diagnostics,{$ENDIF}
  Utils.SyncObjs, Utils.EasyTimer, Utils.EasyThread;

type
  TObservedTimer = class(TEasyTimer)
  public
    destructor Destroy; override;
    procedure FreeInstance; override;
  end;

  IProbe = interface
    ['{DD7A864D-23F9-4F43-994B-D5BE321F33AB}']
    procedure Touch;
  end;

  TProbe = class(TInterfacedObject, IProbe)
  public
    procedure Touch;
    destructor Destroy; override;
  end;

  TReleaseThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TConcurrentCreator = class(TThread)
  public
    Go, FinishedEvent: IEvent;
    ErrorText: string;
    procedure Execute; override;
  end;

var
  Timer: IEasyTimer;
  Entered, ContinueCallback, Fired, DestroyEntered, DestroyFinished, CaptureReleased,
    ReleaseFinished: IEvent;
  Calls, Destroys, Captures: Integer;
  Retired: Pointer;
  RetiredBytes: TBytes;
  Watch: TStopwatch;
  Samples: array[0..99] of Int64;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if ACondition then Exit;
  Writeln('FAIL ', ParamStr(1), ': ', AMessage);
  Flush(Output);
  Halt(1);
end;

procedure Await(const AEvent: IEvent; const AMessage: string);
begin
  Check(AEvent.WaitFor(3000) = TWaitResult.wrSignaled, AMessage);
end;

destructor TObservedTimer.Destroy;
begin
  DestroyEntered.SetEvent;
  inherited;
  AtomicIncrement(Destroys);
  DestroyFinished.SetEvent;
end;

procedure TObservedTimer.FreeInstance;
begin
  // 完成托管字段清理后保留内存，确定性比较线程是否继续写入已析构对象。
  CleanupInstance;
  Retired := Self;
  SetLength(RetiredBytes, InstanceSize);
  Move(PByte(Self)^, RetiredBytes[0], Length(RetiredBytes));
end;

procedure TProbe.Touch;
begin
end;

destructor TProbe.Destroy;
begin
  AtomicIncrement(Captures);
  CaptureReleased.SetEvent;
  inherited;
end;

procedure TReleaseThread.Execute;
begin
  Timer := nil;
  ReleaseFinished.SetEvent;
end;

procedure CreateObserved(const AMode: string; const ADelay, AInterval: Int64;
  const APaused: Boolean = False);
var
  LProbe: IProbe;
begin
  LProbe := TProbe.Create;
  Timer := TObservedTimer.Create('test',
    TProc(procedure
    var
      N: Integer;
    begin
      LProbe.Touch;
      N := AtomicIncrement(Calls);
      if N <= Length(Samples) then Samples[N - 1] := Watch.ElapsedMilliseconds;
      Entered.SetEvent;
      if (AMode = 'self-destroy') or (AMode = 'self-destroy-exception')
        or (AMode = 'external-destroy') or (AMode = 'callback-terminate')
        or (AMode = 'callback-wait') or (AMode = 'heartbeat-callback')
        or (AMode = 'pause-after-first') or (AMode = 'interval-callback') then
        Await(ContinueCallback, '回调未获继续信号');
      if (AMode = 'self-destroy') or (AMode = 'self-destroy-exception') then Timer := nil;
      if AMode = 'callback-wait' then Timer.WaitFor;
      if (AMode = 'callback-terminate') or (AMode = 'callback-wait') then Timer.Terminate;
      if (AMode = 'interval-callback') and (N = 1) then
        (Timer as TEasyTimer).Interval := 3600000;
      Fired.SetEvent;
      if ((AMode = 'exception-continues') and (N = 1)) or (AMode = 'self-destroy-exception') then
        raise Exception.Create('预期的定时回调异常');
    end), ADelay, AInterval, APaused);
end;

procedure CheckReleased;
begin
  Await(DestroyFinished, 'Timer未完成析构');
  Await(CaptureReleased, '线程未释放回调捕获资源');
  Check((Destroys = 1) and (Captures = 1), 'Timer或捕获资源没有释放一次');
  Check((Retired <> nil) and CompareMem(Retired, @RetiredBytes[0], Length(RetiredBytes)),
    '工作线程继续写入已经析构的Timer对象');
  FreeMem(Retired);
  Retired := nil;
  RetiredBytes := nil;
end;

procedure RunBehavior(const AMode: string);
var
  LReleaser: TReleaseThread;
  LBefore, LAfter: UInt64;
  LStart: Int64;
  LRaised: Boolean;
  I: Integer;
begin
  Entered := TEvent.Create(True, False);
  ContinueCallback := TEvent.Create(True, False);
  Fired := TEvent.Create(False, False);
  DestroyEntered := TEvent.Create(True, False);
  DestroyFinished := TEvent.Create(True, False);
  CaptureReleased := TEvent.Create(True, False);
  ReleaseFinished := TEvent.Create(True, False);
  Watch := TStopwatch.StartNew;
  if AMode = 'create-destroy' then
  begin
    for I := 1 to 16 do
    begin
      Timer := TEasyTimer.Create('short-lived', TProc(procedure begin AtomicIncrement(Calls); end),
        Int64(3600000), Int64(3600000), True);
      Timer := nil;
    end;
    Check(Calls = 0, '暂停创建后仍触发');
    Exit;
  end;
  if AMode = 'constructor-failure' then
  begin
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    SetEasyThreadStartHook(procedure begin raise Exception.Create('预期的构造失败'); end);
    LRaised := False;
    try
      CreateObserved(AMode, 1000, 1000);
    except
      on E: Exception do
      begin
        LRaised := True;
        Check(E.Message = '预期的构造失败', '构造失败被清理异常覆盖: ' + E.ClassName + ' ' + E.Message);
      end;
    end;
    SetEasyThreadStartHook(nil);
    Check(LRaised and (Timer = nil), '构造失败仍发布Timer');
    CheckReleased;
    Exit;
    {$ELSE}
    Check(False, '构造失败用例需要测试开关');
    {$ENDIF}
  end;
  if AMode = 'huge-delay' then CreateObserved(AMode, High(Int64), High(Int64))
  else if AMode = 'huge-interval' then CreateObserved(AMode, 0, 3600000)
  else if (AMode = 'heartbeat-idle') or (AMode = 'heartbeat-paused')
    or (AMode = 'terminate-long') or (AMode = 'finished-heartbeat') then
    CreateObserved(AMode, 3600000, 3600000, AMode = 'heartbeat-paused')
  else if AMode = 'pause-resume' then CreateObserved(AMode, 0, 1000, True)
  else if AMode = 'interval-shorter' then CreateObserved(AMode, 0, 3600000)
  else if AMode = 'interval-longer' then CreateObserved(AMode, 0, 200)
  else if AMode = 'interval-paused' then CreateObserved(AMode, 0, 3600000, True)
  else if AMode = 'interval-initial' then CreateObserved(AMode, 250, 3600000)
  else if AMode = 'interval-nonpositive' then CreateObserved(AMode, 0, 3600000)
  else if AMode = 'delay' then CreateObserved(AMode, 180, 1000)
  else CreateObserved(AMode, 0, 40);

  if (AMode = 'huge-delay') or (AMode = 'huge-interval') then
  begin
    if AMode = 'huge-interval' then
    begin
      Await(Fired, '首次回调未触发');
      (Timer as TEasyTimer).Interval := High(Int64);
    end;
    Check(Fired.WaitFor(100) = TWaitResult.wrTimeout, '极大时间参数溢出而提前触发');
    LStart := Watch.ElapsedMilliseconds;
    Timer.Terminate;
    Timer.WaitFor;
    Check(Timer.Finished and (Watch.ElapsedMilliseconds - LStart < 500), '极大等待不能及时终止');
  end else if (AMode = 'interval-shorter') or (AMode = 'interval-nonpositive') then
  begin
    Await(Fired, '首次回调未触发');
    Check(Fired.WaitFor(100) = TWaitResult.wrTimeout, '长周期提前触发');
    LStart := Watch.ElapsedMilliseconds;
    if AMode = 'interval-shorter' then (Timer as TEasyTimer).Interval := 20
    else (Timer as TEasyTimer).Interval := -1;
    Await(Fired, '缩短周期没有唤醒等待');
    Check(Watch.ElapsedMilliseconds - LStart < 500, '修改周期后仍等待旧截止时间');
    if AMode = 'interval-nonpositive' then
    begin
      Await(Fired, '非正周期未继续');
      Check(Samples[2] - Samples[1] >= 8, '非正周期形成忙循环');
    end else Check((Timer as TEasyTimer).Interval = 20, 'Interval读取值错误');
  end else if AMode = 'interval-longer' then
  begin
    Await(Fired, '首次回调未触发');
    (Timer as TEasyTimer).Interval := 3600000;
    Check(Fired.WaitFor(300) = TWaitResult.wrTimeout, '延长周期后仍按旧周期触发');
  end else if AMode = 'interval-paused' then
  begin
    (Timer as TEasyTimer).Interval := 20;
    Check(Fired.WaitFor(100) = TWaitResult.wrTimeout, '修改周期错误恢复暂停状态');
    Timer.Paused := False;
    Await(Fired, '暂停恢复没有触发');
    Await(Fired, '暂停期间的新周期未生效');
  end else if AMode = 'interval-initial' then
  begin
    (Timer as TEasyTimer).Interval := 10;
    Check(Fired.WaitFor(100) = TWaitResult.wrTimeout, 'Interval错误缩短首次Delay');
    Await(Fired, '首次Delay未触发');
    Check(Samples[0] >= 230, '首次Delay过早触发');
  end else if AMode = 'interval-callback' then
  begin
    Await(Entered, '回调未开始');
    ContinueCallback.SetEvent;
    Await(Fired, '回调内修改周期未返回');
    Check(Fired.WaitFor(150) = TWaitResult.wrTimeout, '回调内的新周期未生效');
    (Timer as TEasyTimer).Interval := 20;
    Await(Fired, '再次缩短周期未触发');
  end else if (AMode = 'heartbeat-idle') or (AMode = 'heartbeat-paused') then
  begin
    LBefore := Timer.LastTick;
    Check(Fired.WaitFor(180) = TWaitResult.wrTimeout, '空闲/暂停时触发回调');
    LAfter := Timer.LastTick;
    Check((LAfter > LBefore) and not Timer.IsTimeout(80), '健康等待误报超时或LastTick不前进');
  end else if AMode = 'pause-resume' then
  begin
    Check(Fired.WaitFor(100) = TWaitResult.wrTimeout, '暂停时触发回调');
    LStart := Watch.ElapsedMilliseconds;
    Timer.Paused := False;
    Await(Fired, '恢复后没有触发');
    Check(Watch.ElapsedMilliseconds - LStart < 500, '恢复未及时唤醒');
  end else if AMode = 'terminate-long' then
  begin
    LStart := Watch.ElapsedMilliseconds;
    Timer.Terminate;
    Timer.WaitFor;
    Check(Timer.Finished and (Calls = 0) and (Watch.ElapsedMilliseconds - LStart < 500), '长等待不能及时终止');
  end else if AMode = 'finished-heartbeat' then
  begin
    Timer.Terminate;
    Timer.WaitFor;
    LBefore := Timer.LastTick;
    Fired.WaitFor(150);
    Check(Timer.Finished and (Timer.LastTick = LBefore) and Timer.IsTimeout(80), '完成后心跳未冻结');
  end else if AMode = 'external-destroy' then
  begin
    Await(Entered, '回调未开始');
    LReleaser := TReleaseThread.Create(True);
    try
      LReleaser.Start;
      Await(DestroyEntered, '外部线程未进入析构');
      Check(DestroyFinished.WaitFor(100) = TWaitResult.wrTimeout, '外部析构未等待执行中的回调');
      ContinueCallback.SetEvent;
      Await(ReleaseFinished, '外部析构未返回');
      LReleaser.WaitFor;
    finally
      LReleaser.Free;
    end;
  end else if AMode = 'heartbeat-callback' then
  begin
    Await(Entered, '回调未开始');
    LBefore := Timer.LastTick;
    Check(Fired.WaitFor(150) = TWaitResult.wrTimeout, '受控回调提前结束');
    Check(Timer.IsTimeout(80) and (Timer.LastTick = LBefore), '执行中卡顿没有报告超时');
    Timer.Terminate;
    ContinueCallback.SetEvent;
    Await(Fired, '受控回调未结束');
  end else if AMode = 'pause-after-first' then
  begin
    Await(Entered, '首次回调未开始');
    Timer.Paused := True;
    ContinueCallback.SetEvent;
    Await(Fired, '首次回调未结束');
    Check(Fired.WaitFor(150) = TWaitResult.wrTimeout, 'Pause后仍继续触发');
    Check(Calls = 1, '暂停后回调次数错误');
    Timer.Paused := False;
    Await(Fired, '恢复后没有下一次回调');
  end else
  begin
    if (AMode = 'self-destroy') or (AMode = 'self-destroy-exception')
      or (AMode = 'callback-terminate') or (AMode = 'callback-wait') then
    begin
      Await(Entered, '回调未开始');
      ContinueCallback.SetEvent;
    end;
    Await(Fired, '未触发回调');
    if AMode = 'delay' then Check(Samples[0] >= 160, '初始延迟过早触发');
    if AMode = 'immediate' then Check(Samples[0] < 500, '立即触发过晚');
    if AMode = 'exception-continues' then
    begin
      Await(Fired, '一次异常阻止后续回调');
      Check(Calls >= 2, '异常后未继续');
    end;
  end;
  if Timer <> nil then
  begin
    Timer.Terminate;
    Timer.WaitFor;
    Check(Timer.Finished, 'WaitFor后Finished不是True');
    Timer := nil;
  end;
  CheckReleased;
end;

procedure RunIdle;
var
  LTimers: TArray<IEasyTimer>;
  I, N: Integer;
  LLine: string;
begin
  N := StrToInt(ParamStr(2));
  SetLength(LTimers, N);
  for I := 0 to N - 1 do
    LTimers[I] := TEasyTimer.Create('idle', TProc(procedure begin AtomicIncrement(Calls); end),
      Int64(3600000), Int64(3600000), ParamStr(3) = 'paused');
  Writeln('READY ', N); Flush(Output);
  Readln(LLine);
  for I := 0 to N - 1 do LTimers[I].Terminate;
  for I := 0 to N - 1 do LTimers[I].WaitFor;
  LTimers := nil;
  Writeln('CALLS ', Calls); Flush(Output);
end;

procedure RunTiming;
var
  LInterval: Int64;
  I: Integer;
begin
  LInterval := StrToInt64(ParamStr(2));
  Fired := TEvent.Create(True, False);
  Watch := TStopwatch.StartNew;
  Timer := TEasyTimer.Create('timing',
    TProc(procedure
    var N: Integer;
    begin
      N := AtomicIncrement(Calls);
      if N <= Length(Samples) then Samples[N - 1] := Watch.ElapsedMilliseconds;
      if N >= 50 then Fired.SetEvent;
    end), Int64(150), LInterval);
  Check(Fired.WaitFor(10000) = TWaitResult.wrSignaled, '精度采样超时');
  Timer.Terminate;
  Timer.WaitFor;
  Timer := nil;
  Write('TIMES');
  for I := 0 to 49 do Write(' ', Samples[I]);
  Writeln;
end;

procedure RunBatchWait;
var
  LTimers: TArray<IEasyTimer>;
  I: Integer;
begin
  // 多个已结束 pthread 的存储被回收后，再次 join 比单线程更易暴露无效句柄。
  SetLength(LTimers, 16);
  for I := 0 to High(LTimers) do
    LTimers[I] := TEasyTimer.Create('batch', TProc(procedure begin AtomicIncrement(Calls); end),
      Int64(3600000), Int64(3600000), True);
  for I := 0 to High(LTimers) do LTimers[I].Terminate;
  for I := 0 to High(LTimers) do LTimers[I].WaitFor;
  for I := 0 to High(LTimers) do LTimers[I].WaitFor;
  LTimers := nil;
  Check(Calls = 0, '批量停止仍触发回调');
  Writeln('PASS batch-wait');
end;

procedure TConcurrentCreator.Execute;
var
  LTimer: IEasyTimer;
  LReady: IEvent;
begin
  Go.WaitFor(High(Cardinal));
  try
    LReady := TEvent.Create(True, False);
    LTimer := TEasyTimer.Create('concurrent-first', TProc(procedure begin LReady.SetEvent; end),
      Int64(20), Int64(3600000));
    Check(LReady.WaitFor(3000) = TWaitResult.wrSignaled, '首次并发构造未触发');
    LTimer.Terminate;
    LTimer.WaitFor;
    LTimer := nil;
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
  FinishedEvent.SetEvent;
end;

procedure RunConcurrentCreate;
var
  LCreators: array[0..7] of TConcurrentCreator;
  LGo: IEvent;
  I: Integer;
begin
  // 此入口不先创建测试 Stopwatch，覆盖生产 Timer 首次被多个线程使用的路径。
  LGo := TEvent.Create(True, False);
  for I := Low(LCreators) to High(LCreators) do
  begin
    LCreators[I] := TConcurrentCreator.Create(True);
    LCreators[I].Go := LGo;
    LCreators[I].FinishedEvent := TEvent.Create(True, False);
    LCreators[I].Start;
  end;
  LGo.SetEvent;
  for I := Low(LCreators) to High(LCreators) do
  begin
    Await(LCreators[I].FinishedEvent, '并发构造任务未结束');
    LCreators[I].WaitFor;
    Check(LCreators[I].ErrorText = '', LCreators[I].ErrorText);
    LCreators[I].Free;
  end;
  Writeln('PASS concurrent-create');
end;

begin
  try
    if ParamStr(1) = 'idle' then RunIdle
    else if ParamStr(1) = 'timing' then RunTiming
    else if ParamStr(1) = 'batch-wait' then RunBatchWait
    else if ParamStr(1) = 'concurrent-create' then RunConcurrentCreate
    else
    begin
      RunBehavior(ParamStr(1));
      Writeln('PASS ', ParamStr(1));
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL ', ParamStr(1), ': ', E.ClassName, ' ', E.Message);
      {$IFDEF FPC}DumpExceptionBackTrace(Output);{$ENDIF}
      Halt(1);
    end;
  end;
end.
