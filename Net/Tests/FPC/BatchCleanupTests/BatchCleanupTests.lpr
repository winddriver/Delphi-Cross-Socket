program BatchCleanupTests;
{$I zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,cwstring,{$ENDIF}
  SysUtils,Classes,DateUtils,Math,Generics.Collections,Utils.SyncObjs,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  {$IFNDEF SESSION_ONLY}Net.SocketAPI,Net.CrossSocket.Base,Net.CrossSocket,Net.CrossHttpClient,{$ENDIF}
  Net.CrossHttpParams;
type
  TObservedSessions=class(TSessions)
  private
    FLockStart,FCollectStart:Int64;
  protected
    procedure BeforeClearExpiredSessions;override;
    function OnCheckExpiredSession(const ASession:ISession):Boolean;override;
    procedure AfterClearExpiredSessions;override;
  public
    Measuring,RaiseAfter,PauseUnderLock:Boolean;
    LockTicks,CollectTicks,RemoveTicks:Int64;
    BeforeCalls,AfterCalls,Checked,Removed:Integer;
    procedure BeginWrite;override;
    procedure EndWrite;override;
    procedure RemoveSessions(const ASessions:TArray<ISession>);override;
  end;
  TObservedSession=class(TSession)
  public destructor Destroy;override;end;
var Frequency:Int64;Destroyed,ProbeStarted:Integer;
    ProbeOnDestroy:Boolean;Sessions:TObservedSessions;
    ProbeGate,ProbeDone,WriterEntered,WriterRelease,TouchStarted,TouchDone:IEvent;
{$IFDEF POSIX}
type TClockTime=record Sec,Nano:Int64;end;
function ClockTime(AClock:Integer;var ATime:TClockTime):Integer;cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'clock_gettime';
{$ENDIF}
function Ticks:Int64;
{$IFDEF POSIX}var T:TClockTime;{$ENDIF}
begin
  {$IFDEF MSWINDOWS}QueryPerformanceCounter(Result);{$ELSE}
  if ClockTime(1,T)<>0 then Halt(2);Result:=T.Sec*1000000000+T.Nano;{$ENDIF}
end;
procedure Line(const S:string);
begin Writeln(S);Flush(Output);end;
procedure Check(const OK:Boolean;const Msg:string);
begin if not OK then begin Writeln('FAIL ',Msg);Flush(Output);Halt(1);end;end;
procedure Await(const Event:IEvent;const Msg:string);
begin Check(Event.WaitFor(5000)=TWaitResult.wrSignaled,Msg);end;
procedure TObservedSessions.BeginWrite;
begin inherited;if Measuring then FLockStart:=Ticks;end;
procedure TObservedSessions.EndWrite;
begin if Measuring then Inc(LockTicks,Ticks-FLockStart);inherited;end;
procedure TObservedSessions.BeforeClearExpiredSessions;
begin
  Inc(BeforeCalls);if Measuring then FCollectStart:=Ticks;
  if PauseUnderLock then begin WriterEntered.SetEvent;Await(WriterRelease,'写锁门控超时');end;
  inherited;
end;
function TObservedSessions.OnCheckExpiredSession(const ASession:ISession):Boolean;
begin Inc(Checked);Result:=inherited;end;
procedure TObservedSessions.RemoveSessions(const ASessions:TArray<ISession>);
var Started:Int64;
begin
  Started:=Ticks;if Measuring then CollectTicks:=Started-FCollectStart;
  Inc(Removed,Length(ASessions));inherited;
  if Measuring then RemoveTicks:=Ticks-Started;
end;
procedure TObservedSessions.AfterClearExpiredSessions;
begin Inc(AfterCalls);inherited;if RaiseAfter then raise Exception.Create('after cleanup test');end;
destructor TObservedSession.Destroy;
begin
  if ProbeOnDestroy and (AtomicCmpExchange(ProbeStarted,1,0)=0) then begin
    ProbeGate.SetEvent;Await(ProbeDone,'Session析构仍持写锁');
  end;
  AtomicIncrement(Destroyed);inherited;
end;
procedure Add(const S:TSessions;const ID:string;const Expired:Boolean);
var Value:ISession;
begin
  Value:=S.AddSession(ID);Value.ExpiryTime:=60;
  if Expired then Value.LastAccessTime:=IncSecond(Now,-120);
end;
procedure Prepare(const N:Integer;const ExpiredCount:Integer=-1);
var I:Integer;Options:TSessionTestOptions;
begin
  Options:=Default(TSessionTestOptions);Options.CleanupIntervalMs:=60000;SetSessionTestOptions(Options);
  Sessions:=TObservedSessions.Create;Sessions.SessionClass:=TObservedSession;Sessions.ExpiryTime:=60;
  Sessions.BeginWrite;
  try for I:=0 to N-1 do Add(Sessions,IntToStr(I),(ExpiredCount<0) or (I<ExpiredCount));finally Sessions.EndWrite;end;
end;
procedure BenchSessions(const N:Integer);
var Started,Total:Int64;
begin
  {$IFDEF MSWINDOWS}Check(SetThreadAffinityMask(GetCurrentThread,4)<>0,'基准CPU绑定失败');{$ENDIF}
  Prepare(N);
  try
    Sessions.Measuring:=True;Started:=Ticks;ClearExpiredSessionsForTest(Sessions);Total:=Ticks-Started;
    Sessions.Measuring:=False;
    Check((Sessions.Count=0) and (Destroyed=N) and (Sessions.Checked=N),'Session批次未完整处理');
    Writeln(Format('BENCH session n=%d total_us=%.3f lock_us=%.3f collect_us=%.3f remove_us=%.3f',
      [N,Total*1000000.0/Frequency,Sessions.LockTicks*1000000.0/Frequency,
       Sessions.CollectTicks*1000000.0/Frequency,Sessions.RemoveTicks*1000000.0/Frequency]));
  finally Sessions.Free;Sessions:=nil;end;
end;
procedure TestSessions(const Mode:string);
var Reader,Cleaner,Toucher:TThread;Value,Found,Old:ISession;Raised:Boolean;Start,Release:IEvent;
begin
  Prepare(1000);Reader:=nil;Cleaner:=nil;Toucher:=nil;
  ProbeGate:=TEvent.Create(True,False);ProbeDone:=TEvent.Create(True,False);
  WriterEntered:=TEvent.Create(True,False);WriterRelease:=TEvent.Create(True,False);
  TouchStarted:=TEvent.Create(True,False);TouchDone:=TEvent.Create(True,False);
  Start:=TEvent.Create(True,False);Release:=TEvent.Create(True,False);
  try
    if (Mode='session-release') or (Mode='session-exception') then begin
      ProbeOnDestroy:=True;Sessions.RaiseAfter:=Mode='session-exception';
      Reader:=TThread.CreateAnonymousThread(procedure
        begin Await(ProbeGate,'未观察到析构');Sessions.BeginRead;try ProbeDone.SetEvent;finally Sessions.EndRead;end;end);
      Reader.FreeOnTerminate:=False;Reader.Start;Raised:=False;
      try ClearExpiredSessionsForTest(Sessions);except on E:Exception do Raised:=E.Message='after cleanup test';end;
      Check(Raised=Sessions.RaiseAfter,'清理异常传播改变');Reader.WaitFor;
      Check((Destroyed=1000) and (Sessions.Count=0),'异常路径遗漏释放');
    end else if (Mode='session-renew') or (Mode='session-replace') then begin
      Sessions.BeginWrite;
      try Value:=Sessions.AddSession('live');Value.ExpiryTime:=60;Value.LastAccessTime:=IncSecond(Now,-120);
      finally Sessions.EndWrite;end;
      Cleaner:=TThread.CreateAnonymousThread(procedure
        begin Start.SetEvent;Await(Release,'清理未放行');ClearExpiredSessionsForTest(Sessions);end);
      Cleaner.FreeOnTerminate:=False;Cleaner.Start;Await(Start,'清理未启动');
      Sessions.BeginWrite;
      try
        if Mode='session-replace' then begin Old:=Value;Value:=TObservedSession.Create(Sessions,'live');Value.ExpiryTime:=60;Sessions.AddSession('live',Value);end
        else Value.Touch;
      finally Sessions.EndWrite;end;
      Release.SetEvent;Cleaner.WaitFor;Check(Cleaner.FatalException=nil,'并发清理异常');
      Check(Sessions.ExistsSession('live',Found) and (Found=Value),'续期或同ID替换被清理误删');
      Check((Sessions.Count=1) and (Destroyed=1000),'删除了新会话或遗漏过期会话');
    end else if Mode='session-concurrent-touch' then begin
      Sessions.BeginWrite;try Value:=Sessions.AddSession('live');Value.ExpiryTime:=600;finally Sessions.EndWrite;end;
      Sessions.PauseUnderLock:=True;
      Cleaner:=TThread.CreateAnonymousThread(procedure begin ClearExpiredSessionsForTest(Sessions);end);
      Cleaner.FreeOnTerminate:=False;Cleaner.Start;Await(WriterEntered,'未进入清理写锁');
      Toucher:=TThread.CreateAnonymousThread(procedure
        begin TouchStarted.SetEvent;Sessions.BeginWrite;try Value.Touch;finally Sessions.EndWrite;end;TouchDone.SetEvent;end);
      Toucher.FreeOnTerminate:=False;Toucher.Start;Await(TouchStarted,'续期线程未启动');
      Check(TouchDone.WaitFor(20)=TWaitResult.wrTimeout,'续期绕过清理写锁');WriterRelease.SetEvent;
      Cleaner.WaitFor;Toucher.WaitFor;Check((Cleaner.FatalException=nil) and (Toucher.FatalException=nil),'并发续期异常');
      Check(Sessions.ExistsSession('live',Found) and (Found=Value),'并发续期会话丢失');
    end else raise Exception.Create('未知Session用例');
    Check((Sessions.BeforeCalls=1) and (Sessions.AfterCalls=1),'清理钩子次数改变');
    Writeln('PASS ',Mode);
  finally
    ProbeOnDestroy:=False;Release.SetEvent;WriterRelease.SetEvent;ProbeGate.SetEvent;
    Reader.Free;Cleaner.Free;Toucher.Free;Found:=nil;Value:=nil;Old:=nil;Sessions.Free;Sessions:=nil;
  end;
end;

{$I SessionSparseTests.inc}
{$IFNDEF SESSION_ONLY}
{$I SocketBatchTests.inc}
{$I ClientTimeoutTests.inc}
{$ENDIF}

begin
  {$IFDEF MSWINDOWS}QueryPerformanceFrequency(Frequency);{$ELSE}Frequency:=1000000000;{$ENDIF}
  try
    if ParamStr(1)='bench-session' then BenchSessions(StrToInt(ParamStr(2)))
    else if ParamStr(1)='tail-session-idle' then BenchSessionTail
    else if ParamStr(1)='bench-session-sparse' then BenchSparseSessions(StrToInt(ParamStr(2)),False)
    else if ParamStr(1)='alloc-session-sparse' then BenchSparseSessions(StrToInt(ParamStr(2)),True)
    {$IFNDEF SESSION_ONLY}
    else if ParamStr(1)='client' then TestClientTimeout(ParamStr(2),ParamStr(3))
    else if ParamStr(1)='socket' then RunSocketBatch(ParamStr(2),StrToInt(ParamStr(3)))
    {$ENDIF}
    else TestSessions(ParamStr(1));
  except on E:Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
