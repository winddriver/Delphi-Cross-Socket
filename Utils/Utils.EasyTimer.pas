unit Utils.EasyTimer;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  DateUtils,
  {$IFDEF FPC}
  DTF.Types,
  DTF.Diagnostics,
  {$ELSE}
  System.Diagnostics,
  {$ENDIF}

  Utils.EasyThread,
  Utils.DateTime,
  Utils.SyncObjs,
  Utils.Utils,
  Utils.Logger;

type
  IEasyTimer = interface
  ['{3AA98783-0800-4C4E-AA3F-037FC5307196}']
    function GetName: string;
    function GetPaused: Boolean;
    function GetFinished: Boolean;
    function GetLastTick: UInt64;
    procedure SetPaused(const AValue: Boolean);

    procedure Terminate;
    procedure WaitFor;

    function IsTimeout(const ATimeout: Integer): Boolean;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
    property Finished: Boolean read GetFinished;
    // 活线程空闲/暂停时为当前观察时间；回调中为开始前心跳，Finished 后冻结。
    property LastTick: UInt64 read GetLastTick;
  end;

  TEasyTimer = class(TInterfacedObject, IEasyTimer)
  private
    FEasyThread: IEasyThread;
    // 工作线程另持强引用，回调可释放 Timer 本身而不留下悬空 Self。
    FState: IInterface;

    function GetName: string;
    function GetPaused: Boolean;
    function GetFinished: Boolean;
    function GetLastTick: UInt64;
    procedure SetPaused(const AValue: Boolean);
    function GetInterval: Int64;
    procedure SetInterval(const AValue: Int64);

    class function _FullDateTime(const ADateTime: TDateTime): TDateTime; static;
  public
    constructor Create(const AName: string; const AProc: TProc;
      const ADelay, AInterval: Int64; const APaused: Boolean = False); overload;
    constructor Create(const AName: string; const AProc: TProc;
      const AInterval: Int64; const APaused: Boolean = False); overload;
    constructor Create(const AName: string; const AProc: TProc;
      const AStartTime: TDateTime; const AInterval: Int64;
      const APaused: Boolean = False); overload;
    destructor Destroy; override;

    procedure Terminate;
    procedure WaitFor;

    function IsTimeout(const ATimeout: Integer): Boolean;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
    property Finished: Boolean read GetFinished;
    // 只调整后续周期，不改变首次 Delay；从上次回调结束起计算，非正值按 10ms。
    property Interval: Int64 read GetInterval write SetInterval;
    // 空闲/暂停视作健康；回调卡顿可由 IsTimeout 检测，Finished 后冻结最后心跳。
    property LastTick: UInt64 read GetLastTick;
  end;

implementation

type
  TEasyTimerState = class(TInterfacedObject)
  private
    FName: string;
    FProc: TProc;
    FDelay, FInterval: Int64;
    FPaused, FFinished, FTerminated, FInCallback: Boolean;
    FLock: ILock;
    FWake: IEvent;
    FClock: TStopwatch;
    FLastMonoTick: Int64;
    FLastWallTick: UInt64;
    procedure _Touch;
  public
    constructor Create(const AName: string; const AProc: TProc;
      const ADelay, AInterval: Int64; const APaused: Boolean);
    procedure Run(const AThread: IEasyThread);
  end;

constructor TEasyTimerState.Create(const AName: string; const AProc: TProc;
  const ADelay, AInterval: Int64; const APaused: Boolean);
begin
  FLock := TLock.Create;
  FWake := TEvent.Create(False, False);
  FName := AName;
  FProc := AProc;
  FDelay := ADelay;
  FInterval := AInterval;
  FPaused := APaused;
  FClock := TStopwatch.StartNew;
  _Touch;
end;

procedure TEasyTimerState._Touch;
begin
  FLastMonoTick := FClock.ElapsedMilliseconds;
  FLastWallTick := Now.ToMilliseconds;
end;

procedure TEasyTimerState.Run(const AThread: IEasyThread);
var
  LFirstRun, LRun: Boolean;
  LBaseTick, LElapsed, LDelay, LRemaining: Int64;
  LWait: Cardinal;
  LStackTrace: string;
begin
  LFirstRun := True;
  LBaseTick := FClock.ElapsedMilliseconds;
  try
    while True do
    begin
      LRun := False;
      LWait := High(Cardinal);
      FLock.Enter;
      try
        if FTerminated or AThread.Terminated then Break;
        if not FPaused then
        begin
          if LFirstRun then LDelay := FDelay else LDelay := FInterval;
          if not LFirstRun and (LDelay <= 0) then LDelay := 10;
          LElapsed := FClock.ElapsedMilliseconds - LBaseTick;
          if LElapsed >= LDelay then
          begin
            LRun := True;
            FInCallback := True;
            _Touch;
          end else
          begin
            LRemaining := LDelay - LElapsed;
            // 部分 32 位 POSIX 等待实现会转为有符号 long，不能传入更大的有限值。
            if LRemaining > High(Integer) then LWait := High(Integer)
            else LWait := Cardinal(LRemaining);
          end;
        end;
      finally
        FLock.Leave;
      end;

      if LRun then
      begin
        LFirstRun := False;
        try
          try
            if Assigned(FProc) then FProc();
          except
            on E: Exception do
              if not (E is EAbort) then
              begin
                try
                  AppendLog('执行EasyTimer[%s]出现异常: %s, %s', [FName, E.ClassName, E.Message]);
                  LStackTrace := TUtils.GetStackTrace;
                  if LStackTrace <> '' then AppendLog('异常调用堆栈:%s', [LStackTrace]);
                except
                  // 日志异常也不能阻止定时器继续运行和最终释放。
                end;
              end;
          end;
        finally
          LBaseTick := FClock.ElapsedMilliseconds;
          FLock.Enter;
          try
            FInCallback := False;
            _Touch;
          finally
            FLock.Leave;
          end;
        end;
      end;

      // 自动重置事件保留先于 WaitFor 到达的信号，不丢失暂停、调周期或终止通知。
      if not LRun then FWake.WaitFor(LWait);
    end;
  finally
    FLock.Enter;
    try
      FInCallback := False;
      FFinished := True;
      _Touch;
    finally
      FLock.Leave;
    end;
  end;
end;

{ TEasyTimer }

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const ADelay, AInterval: Int64; const APaused: Boolean = False);
var
  LState: IInterface;
begin
  LState := TEasyTimerState.Create(AName, AProc, ADelay, AInterval, APaused);
  FState := LState;
  FEasyThread := TEasyThread.Create(
    procedure(const AEasyThread: IEasyThread)
    begin
      (LState as TEasyTimerState).Run(AEasyThread);
    end);
end;

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const AInterval: Int64; const APaused: Boolean = False);
begin
  Create(AName, AProc, 0, AInterval, APaused);
end;

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const AStartTime: TDateTime; const AInterval: Int64;
  const APaused: Boolean = False);
begin
  Create(AName, AProc,
    _FullDateTime(AStartTime).MilliSecondsDiffer(Now),
    AInterval, APaused);
end;

destructor TEasyTimer.Destroy;
begin
  Terminate;
  WaitFor;

  inherited;
end;

function TEasyTimer.GetFinished: Boolean;
var
  LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    Result := LState.FFinished;
  finally
    LState.FLock.Leave;
  end;
end;

function TEasyTimer.GetLastTick: UInt64;
var
  LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    if LState.FInCallback or LState.FFinished then Result := LState.FLastWallTick
    else Result := Now.ToMilliseconds;
  finally
    LState.FLock.Leave;
  end;
end;

function TEasyTimer.GetName: string;
begin
  Result := (FState as TEasyTimerState).FName;
end;

function TEasyTimer.GetPaused: Boolean;
var
  LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    Result := LState.FPaused;
  finally
    LState.FLock.Leave;
  end;
end;

function TEasyTimer.IsTimeout(const ATimeout: Integer): Boolean;
var
  LState: TEasyTimerState;
begin
  Result := False;
  if (ATimeout <= 0) then Exit;

  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    Result := (LState.FInCallback or LState.FFinished)
      and (LState.FClock.ElapsedMilliseconds - LState.FLastMonoTick > ATimeout);
  finally
    LState.FLock.Leave;
  end;
end;

procedure TEasyTimer.SetPaused(const AValue: Boolean);
var
  LState: TEasyTimerState;
  LChanged: Boolean;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    LChanged := LState.FPaused <> AValue;
    LState.FPaused := AValue;
  finally
    LState.FLock.Leave;
  end;
  if LChanged then LState.FWake.SetEvent;
end;

function TEasyTimer.GetInterval: Int64;
var
  LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    Result := LState.FInterval;
  finally
    LState.FLock.Leave;
  end;
end;

procedure TEasyTimer.SetInterval(const AValue: Int64);
var
  LState: TEasyTimerState;
  LChanged: Boolean;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    LChanged := LState.FInterval <> AValue;
    LState.FInterval := AValue;
  finally
    LState.FLock.Leave;
  end;
  if LChanged then LState.FWake.SetEvent;
end;

procedure TEasyTimer.Terminate;
var
  LState: TEasyTimerState;
begin
  if FState <> nil then
  begin
    LState := FState as TEasyTimerState;
    LState.FLock.Enter;
    try
      LState.FTerminated := True;
    finally
      LState.FLock.Leave;
    end;
    LState.FWake.SetEvent;
  end;
  if FEasyThread <> nil then FEasyThread.Terminate;
end;

procedure TEasyTimer.WaitFor;
begin
  if FEasyThread <> nil then FEasyThread.WaitFor;
end;

class function TEasyTimer._FullDateTime(const ADateTime: TDateTime): TDateTime;
begin
  if (Trunc(ADateTime) > 0) then
    Result := ADateTime
  else
  begin
    Result := Trunc(Now) + Frac(ADateTime);
    if (Now > Result) then
      Result := Result.AddDays(1);
  end;
end;

initialization
  // RTL 频率参数是共享的懒初始化数据，在单元加载期完成，避免首次并发构造竞争。
  TStopwatch.StartNew;

end.
