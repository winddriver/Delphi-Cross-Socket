type
  TJoinWaiter = class(TThread)
  public
    Worker: IEasyThread;
    Ready, Go, Returned: IEvent;
    ErrorText: string;
    procedure Execute; override;
  end;

  TReuseThread = class(TThread)
  public
    OldID: TThreadID;
    Matched: Boolean;
    procedure Execute; override;
  end;

var
  WaitAttempts, WaitReturns: Integer;
  AllWaiting: IEvent;

procedure TJoinWaiter.Execute;
begin
  Ready.SetEvent;
  Go.WaitFor(High(Cardinal));
  if AtomicIncrement(WaitAttempts) = 8 then AllWaiting.SetEvent;
  try
    Worker.WaitFor;
    Worker.WaitFor;
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
  AtomicIncrement(WaitReturns);
  Returned.SetEvent;
end;

procedure TReuseThread.Execute;
begin
  Matched := TThread.CurrentThread.ThreadID = OldID;
  if Matched then Easy := nil;
end;

procedure CreateJoinWorker(const ASelfWait: Boolean);
var
  LProbe: IProbe;
begin
  LProbe := TProbe.Create;
  Easy := TObservedThread.Create(
    procedure(const AWorker: IEasyThread)
    begin
      Started.SetEvent;
      Await(ReleaseTask, '并发等待任务未获继续信号');
      Check(AWorker.Terminated, 'Terminate被等待锁阻挡');
      if ASelfWait then AWorker.WaitFor;
      LProbe.Touch;
      TaskFinished.SetEvent;
    end);
end;

procedure RunJoinCase(const AMode: string);
var
  LTimers: TArray<IEasyTimer>;
  LWaiters: array[0..7] of TJoinWaiter;
  LGo: IEvent;
  LReuse: TReuseThread;
  LOldID: TThreadID;
  LMatched: Boolean;
  I, N: Integer;
begin
  if (AMode = 'join-timers16') or (AMode = 'join-timers64') then
  begin
    N := StrToInt(Copy(AMode, 12, MaxInt));
    SetLength(LTimers, N);
    for I := 0 to N - 1 do
      LTimers[I] := TEasyTimer.Create('join-batch', TProc(procedure begin end),
        Int64(3600000), Int64(3600000), True);
    for I := 0 to N - 1 do LTimers[I].Terminate;
    for I := 0 to N - 1 do LTimers[I].WaitFor;
    for I := 0 to N - 1 do LTimers[I].WaitFor;
    LTimers := nil;
    Exit;
  end;

  Started := TEvent.Create(True, False);
  ReleaseTask := TEvent.Create(True, False);
  TaskFinished := TEvent.Create(True, False);
  DestroyEntered := TEvent.Create(True, False);
  WrapperDestroyed := TEvent.Create(True, False);
  CaptureReleased := TEvent.Create(True, False);
  ReleaseFinished := TEvent.Create(True, False);
  if AMode = 'join-id-reuse' then
  begin
    CreateSelfThread('id-reuse');
    Await(Started, '原任务未开始');
    LOldID := Easy.ThreadID;
    ReleaseTask.SetEvent;
    Easy.WaitFor;
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    Check(GetEasyThreadDestroyedCountForTest = 0, 'wrapper仍持有Control时底层worker提前析构');
    {$ENDIF}
    LMatched := False;
    for I := 1 to 64 do
    begin
      LReuse := TReuseThread.Create(True);
      try
        LReuse.OldID := LOldID;
        LReuse.Start;
        LReuse.WaitFor;
        LMatched := LReuse.Matched;
      finally
        LReuse.Free;
      end;
      if LMatched then Break;
    end;
    Check(LMatched, '目标平台本轮未复用线程ID，不能声称覆盖该时序');
    Await(WrapperDestroyed, '已结束线程的包装对象未析构');
    Await(CaptureReleased, 'ID复用被误认为自身线程，遗漏底层TThread释放');
    Check((WrapperCount = 1) and (CaptureCount = 1), 'ID复用清理次数错误');
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    // Proc已在Execute尾部清理，必须另外观察底层TThread实际析构。
    Check(GetEasyThreadDestroyedCountForTest = 1, 'ID复用遗漏或重复释放底层worker');
    {$ENDIF}
    Exit;
  end;

  AllWaiting := TEvent.Create(True, False);
  LGo := TEvent.Create(True, False);
  CreateJoinWorker(AMode = 'join-worker-self');
  Await(Started, '并发等待任务未开始');
  for I := Low(LWaiters) to High(LWaiters) do
  begin
    LWaiters[I] := TJoinWaiter.Create(True);
    LWaiters[I].Worker := Easy;
    LWaiters[I].Ready := TEvent.Create(True, False);
    LWaiters[I].Returned := TEvent.Create(True, False);
    LWaiters[I].Go := LGo;
    LWaiters[I].Start;
  end;
  for I := Low(LWaiters) to High(LWaiters) do Await(LWaiters[I].Ready, '等待者未就绪');
  LGo.SetEvent;
  Await(AllWaiting, '等待者未同时进入WaitFor');
  Check(AtomicCmpExchange(WaitReturns, 0, 0) = 0, '任务未结束时WaitFor提前返回');
  Easy.Terminate;
  Check(Easy.Terminated, 'Terminate被等待锁阻挡');
  ReleaseTask.SetEvent;
  for I := Low(LWaiters) to High(LWaiters) do
  begin
    Await(LWaiters[I].Returned, '多个WaitFor竞争后没有全部返回');
    LWaiters[I].WaitFor;
    Check(LWaiters[I].ErrorText = '', 'WaitFor异常: ' + LWaiters[I].ErrorText);
    LWaiters[I].Free;
  end;
  Easy.WaitFor;
  Easy := nil;
  Await(WrapperDestroyed, '并发等待后包装对象未析构');
  Await(CaptureReleased, '并发等待后回调捕获未释放');
  Check((WaitReturns = 8) and (WrapperCount = 1) and (CaptureCount = 1), '并发等待收尾次数错误');
end;
