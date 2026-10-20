program EasyThreadTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, {$IFDEF FPC}DTF.Types,{$ENDIF}
  Utils.SyncObjs, Utils.EasyThread, Utils.EasyTimer;

type
  TObservedThread = class(TEasyThread)
  public
    destructor Destroy; override;
  end;

  IProbe = interface
    ['{F2C1AFBA-8670-4145-9E78-F877C14122CC}']
    procedure Touch;
  end;

  TProbe = class(TInterfacedObject, IProbe)
  public
    destructor Destroy; override;
    procedure Touch;
  end;

  TReleaseThread = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  Easy: IEasyThread;
  Started, ReleaseTask, TaskFinished, DestroyEntered, WrapperDestroyed,
    CaptureReleased, ReleaseFinished: IEvent;
  WrapperCount, CaptureCount, TouchCount: Integer;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if AValue then Exit;
  Writeln('FAIL: ', ParamStr(1), ': ', AMessage);
  Flush(Output);
  // 红基线可能有永远等待自己的工作线程，用独立进程隔离后直接退出。
  Halt(1);
end;

procedure Await(const AEvent: IEvent; const AMessage: string);
begin
  Check(AEvent.WaitFor(2500) = TWaitResult.wrSignaled, AMessage);
end;

destructor TObservedThread.Destroy;
begin
  DestroyEntered.SetEvent;
  inherited;
  AtomicIncrement(WrapperCount);
  WrapperDestroyed.SetEvent;
end;

destructor TProbe.Destroy;
begin
  AtomicIncrement(CaptureCount);
  CaptureReleased.SetEvent;
  inherited;
end;

procedure TProbe.Touch;
begin
  AtomicIncrement(TouchCount);
end;

procedure TReleaseThread.Execute;
begin
  Easy := nil;
  ReleaseFinished.SetEvent;
end;

procedure CreateSelfThread(const AMode: string);
var
  LProbe: IProbe;
begin
  LProbe := TProbe.Create;
  Easy := TObservedThread.Create(
    procedure(const AThread: IEasyThread)
    begin
      Started.SetEvent;
      try
        Await(ReleaseTask, '任务没有得到继续信号');
        if AMode = 'self-terminate' then Check(AThread.Terminated, 'Terminate 状态未传播');
        // 新版回调拿到独立 Control；由工作线程明确释放最后的 wrapper 引用。
        if AMode.StartsWith('self-') then
        begin
          Easy := nil;
          Check(WrapperCount = 1, '工作线程释放wrapper未完成一次析构');
        end;
        LProbe.Touch;
        if AMode = 'self-wait' then AThread.WaitFor;
        if AMode = 'self-exception' then raise Exception.Create('预期的任务异常');
      finally
        TaskFinished.SetEvent;
      end;
    end);
end;

procedure CreateAnonymousThread;
var
  LProbe: IProbe;
begin
  LProbe := TProbe.Create;
  Easy := TObservedThread.Create(
    procedure
    begin
      Started.SetEvent;
      Await(ReleaseTask, '匿名任务没有得到继续信号');
      LProbe.Touch;
      TaskFinished.SetEvent;
    end);
end;

procedure Run(const AMode: string);
var
  LReleaser: TReleaseThread;
  LRaised: Boolean;
begin
  Started := TEvent.Create(True, False);
  ReleaseTask := TEvent.Create(True, False);
  TaskFinished := TEvent.Create(True, False);
  DestroyEntered := TEvent.Create(True, False);
  WrapperDestroyed := TEvent.Create(True, False);
  CaptureReleased := TEvent.Create(True, False);
  ReleaseFinished := TEvent.Create(True, False);
  if AMode.StartsWith('constructor-failure-') then
  begin
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    SetEasyThreadStartHook(procedure begin raise Exception.Create('预期的启动前异常'); end);
    LRaised := False;
    try
      if AMode = 'constructor-failure-self' then CreateSelfThread(AMode)
      else CreateAnonymousThread;
    except
      on E: Exception do
      begin
        Check(E.Message = '预期的启动前异常', '构造失败变成了其他异常: ' + E.Message);
        LRaised := True;
      end;
    end;
    SetEasyThreadStartHook(nil);
    Check(LRaised and (Easy = nil), '构造失败仍发布了对象');
    Await(WrapperDestroyed, '未启动线程的构造失败没有完成析构');
    Await(CaptureReleased, '构造失败遗漏回调资源');
    Check((WrapperCount = 1) and (CaptureCount = 1) and (TouchCount = 0), '构造失败清理次数或任务状态错误');
    Exit;
    {$ELSE}
    Check(False, '构造失败用例需要测试开关');
    {$ENDIF}
  end;
  if (AMode = 'anonymous-external-destroy') or (AMode = 'control-external-destroy') then
  begin
    if AMode = 'control-external-destroy' then CreateSelfThread('external-destroy')
    else CreateAnonymousThread;
    Await(Started, '外部析构任务未启动');
    LReleaser := TReleaseThread.Create(True);
    try
      LReleaser.Start;
      Await(DestroyEntered, '外部线程未进入析构');
      Check(WrapperDestroyed.WaitFor(100) = TWaitResult.wrTimeout, '外部析构没有等待正在执行的任务');
      ReleaseTask.SetEvent;
      Await(ReleaseFinished, '外部析构未完成');
      LReleaser.WaitFor;
    finally
      LReleaser.Free;
    end;
  end else
  begin
    Check((AMode = 'self-natural') or (AMode = 'self-exception')
      or (AMode = 'self-terminate') or (AMode = 'self-wait')
      or (AMode = 'external-wait'), '未知用例');
    CreateSelfThread(AMode);
    Await(Started, '任务未启动');
    if AMode = 'self-terminate' then Easy.Terminate;
    Check(WrapperCount = 0, '任务放行前包装对象提前销毁');
    ReleaseTask.SetEvent;
    Await(TaskFinished, '任务未结束（可能在等待自己）');
    if AMode = 'external-wait' then
    begin
      Easy.WaitFor;
      Easy.WaitFor;
      Easy := nil;
    end;
  end;
  Await(WrapperDestroyed, '包装对象未结束析构（可能在等待自己）');
  Await(CaptureReleased, '线程持有的回调资源未释放');
  Check((WrapperCount = 1) and (CaptureCount = 1), '对象未恰好释放一次');
  Check(TouchCount = 1, '任务未恰好执行一次');
end;

{$I EasyThreadJoinTests.inc}

begin
  SetTextCodePage(Output, 65001);
  Check(ParamCount = 1, '用法: EasyThreadTests <case>');
  if Pos('join-', ParamStr(1)) = 1 then RunJoinCase(ParamStr(1))
  else Run(ParamStr(1));
  Writeln('PASS: ', ParamStr(1));
end.
