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
  EEasyTimer = class(Exception);

  IEasyTimer = interface;
  TTimerEvent = procedure(const ATimer: IEasyTimer) of object;

  IEasyTimer = interface
  ['{3AA98783-0800-4C4E-AA3F-037FC5307196}']
    function GetName: string;
    function GetPaused: Boolean;
    function GetFinished: Boolean;
    function GetLastTick: UInt64;
    function GetTimeout: Integer;
    function GetBeforeExecute: TTimerEvent;
    function GetAfterExecute: TTimerEvent;

    procedure SetPaused(const AValue: Boolean);
    procedure SetTimeout(const AValue: Integer);
    procedure SetBeforeExecute(const AValue: TTimerEvent);
    procedure SetAfterExecute(const AValue: TTimerEvent);

    procedure Terminate;
    procedure WaitFor; overload;
    function WaitFor(const ATimeout: Cardinal): Boolean; overload;

    function IsTimeout(const ATimeout: Integer = -1): Boolean;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
    property Finished: Boolean read GetFinished;
    property LastTick: UInt64 read GetLastTick;
    property Timeout: Integer read GetTimeout write SetTimeout;
    property BeforeExecute: TTimerEvent read GetBeforeExecute write SetBeforeExecute;
    property AfterExecute: TTimerEvent read GetAfterExecute write SetAfterExecute;
  end;

  TEasyTimer = class(TInterfacedObject, {$IFDEF FPC}IUnknown{$ELSE}IInterface{$ENDIF}, IEasyTimer)
  private
    FEasyThread: IEasyThread;
    // 工作线程另持强引用，回调可释放 Timer 本身而不留下悬空 Self。
    FState: IInterface;

    // 两张接口表必须走同一释放门；FPC 基接口按实际 IUnknown 名称映射。
    function {$IFDEF FPC}IUnknown{$ELSE}IInterface{$ENDIF}.QueryInterface = TimerQueryInterface;
    function {$IFDEF FPC}IUnknown{$ELSE}IInterface{$ENDIF}._AddRef = TimerAddRef;
    function {$IFDEF FPC}IUnknown{$ELSE}IInterface{$ENDIF}._Release = TimerRelease;
    function IEasyTimer.QueryInterface = TimerQueryInterface;
    function IEasyTimer._AddRef = TimerAddRef;
    function IEasyTimer._Release = TimerRelease;
    function TimerQueryInterface({$IFDEF FPC}constref{$ELSE}const{$ENDIF} AIID: TGUID;
      out AObject): HResult; {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}cdecl{$ELSE}stdcall{$ENDIF};
    function TimerAddRef: Integer; {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}cdecl{$ELSE}stdcall{$ENDIF};
    function TimerRelease: Integer; {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}cdecl{$ELSE}stdcall{$ENDIF};

    function GetName: string;
    function GetPaused: Boolean;
    function GetFinished: Boolean;
    function GetLastTick: UInt64;
    procedure SetPaused(const AValue: Boolean);
    function GetTimeout: Integer;
    function GetBeforeExecute: TTimerEvent;
    function GetAfterExecute: TTimerEvent;
    procedure SetTimeout(const AValue: Integer);
    procedure SetBeforeExecute(const AValue: TTimerEvent);
    procedure SetAfterExecute(const AValue: TTimerEvent);
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
    procedure AfterConstruction; override;

    procedure Terminate;
    procedure WaitFor; overload;
    // 有限等待任务及捕获清理；自身调用为 True 的 no-op，不代表线程退出。
    function WaitFor(const ATimeout: Cardinal): Boolean; overload;

    function IsTimeout(const ATimeout: Integer = -1): Boolean;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
    property Finished: Boolean read GetFinished;
    // 只调整后续周期，不改变首次 Delay；从上次回调结束起计算，非正值按 10ms。
    property Interval: Int64 read GetInterval write SetInterval;
    // 空闲/暂停视作健康；回调卡顿可由 IsTimeout 检测，Finished 后冻结最后心跳。
    property LastTick: UInt64 read GetLastTick;
    property Timeout: Integer read GetTimeout write SetTimeout;
    // 非 nil 事件须在构造完成后持有 IEasyTimer；接收事件的对象由调用方保活。
    property BeforeExecute: TTimerEvent read GetBeforeExecute write SetBeforeExecute;
    property AfterExecute: TTimerEvent read GetAfterExecute write SetAfterExecute;
  end;

implementation

type
  TEasyTimerState = class(TInterfacedObject)
  private
    FName: string;
    FProc: TProc;
    FDelay, FInterval: Int64;
    FPaused, FFinished, FTerminated, FInCallback: Boolean;
    FTimeout: Integer;
    FBeforeExecute, FAfterExecute: TTimerEvent;
    FOwner: TEasyTimer;
    FCycleTimer: IEasyTimer;
    FLock: ILock;
    FWake: IEvent;
    FClock: TStopwatch;
    FLastMonoTick: Int64;
    FLastWallTick: UInt64;
    procedure _Touch;
    function PinTimerLocked: Boolean;
    procedure CheckEventOwnerLocked(const AOwner: TEasyTimer);
    procedure LogCallbackError(const AError: Exception);
    procedure ExecuteProc;
    procedure TriggerBeforeExecute;
    procedure TriggerAfterExecute;
    procedure FinishCycle;
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

function TEasyTimerState.PinTimerLocked: Boolean;
begin
  if FCycleTimer <> nil then Exit(True);
  // 最后 Release 也在本门撤 Owner；检查后取接口不会复活正在销毁的对象。
  Result := (FOwner <> nil) and (FOwner.RefCount > 0);
  if Result then Result := FOwner.GetInterface(IEasyTimer, FCycleTimer);
end;

procedure TEasyTimerState.CheckEventOwnerLocked(const AOwner: TEasyTimer);
begin
  if (FOwner <> AOwner) or (AOwner.RefCount <= 0) then
    raise EEasyTimer.Create('设置定时器事件前须完成构造并持有 IEasyTimer 接口');
  // Proc 本轮首次设置 After 时补当前周期引用，不能延迟到下一轮。
  if FInCallback and not PinTimerLocked then
    raise EEasyTimer.Create('定时器已结束，无法设置当前周期事件');
end;

procedure TEasyTimerState.LogCallbackError(const AError: Exception);
var LStackTrace: string;
begin
  if AError is EAbort then Exit;
  try
    AppendLog('执行EasyTimer[%s]出现异常: %s, %s', [FName, AError.ClassName, AError.Message]);
    LStackTrace := TUtils.GetStackTrace;
    if LStackTrace <> '' then AppendLog('异常调用堆栈:%s', [LStackTrace]);
  except
    // 日志错误不能截断后续阶段、调度或周期引用的清理。
  end;
end;

procedure TEasyTimerState.ExecuteProc;
begin
  try
    if Assigned(FProc) then FProc();
  except
    on E: Exception do LogCallbackError(E);
  end;
end;

procedure TEasyTimerState.TriggerBeforeExecute;
var LEvent: TTimerEvent;
begin
  FLock.Enter;
  try LEvent := FBeforeExecute; finally FLock.Leave; end;
  // 当前周期 pin 直到 finally 才撤销；回调不持有状态锁。
  if Assigned(LEvent) then LEvent(FCycleTimer);
end;

procedure TEasyTimerState.TriggerAfterExecute;
var LEvent: TTimerEvent;
begin
  // Proc 中替换 After 必须在本轮生效，所以这里才读取回调。
  FLock.Enter;
  try LEvent := FAfterExecute; finally FLock.Leave; end;
  if Assigned(LEvent) then LEvent(FCycleTimer);
end;

procedure TEasyTimerState.FinishCycle;
var LReleaseTimer: IEasyTimer;
begin
  FLock.Enter;
  try
    LReleaseTimer := FCycleTimer;
    FCycleTimer := nil;
    FInCallback := False;
    _Touch;
  finally FLock.Leave; end;
  // 可能在此触发 Timer 自身析构；worker 之后只访问独立 state。
  LReleaseTimer := nil;
end;

procedure TEasyTimerState.Run(const AThread: IEasyThread);
var
  LFirstRun, LRun: Boolean;
  LBaseTick, LElapsed, LDelay, LRemaining: Int64;
  LWait: Cardinal;
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
            if (Assigned(FBeforeExecute) or Assigned(FAfterExecute)) and not PinTimerLocked then
            begin
              // Owner 已由最后 Release 撤销，析构期间不再接纳新周期。
              FTerminated := True;
              Break;
            end;
            LRun := True;
            FInCallback := True;
            _Touch;
          end else
          begin
            LRemaining := LDelay - LElapsed;
            // 32 位 POSIX 的有限等待参数可能转换成有符号 long。
            if LRemaining > High(Integer) then LWait := High(Integer)
            else LWait := Cardinal(LRemaining);
          end;
        end;
      finally FLock.Leave; end;

      if LRun then
      begin
        LFirstRun := False;
        try
          try
            // Before 失败跳过本轮后续；Proc 自身失败隔离后仍调用 After。
            TriggerBeforeExecute;
            ExecuteProc;
            TriggerAfterExecute;
          except
            on E: Exception do LogCallbackError(E);
          end;
        finally
          LBaseTick := FClock.ElapsedMilliseconds;
          FinishCycle;
        end;
      end;
      // 自动重置事件保留先于等待到达的通知，不恢复空闲轮询。
      if not LRun then FWake.WaitFor(LWait);
    end;
  finally
    FinishCycle;
    FLock.Enter;
    try
      FFinished := True;
      _Touch;
    finally FLock.Leave; end;
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
  if AStartTime > 0 then
    Create(AName, AProc, _FullDateTime(AStartTime).MilliSecondsDiffer(Now), AInterval, APaused)
  else
    Create(AName, AProc, Int64(0), AInterval, APaused);
end;

procedure TEasyTimer.AfterConstruction;
var LState: TEasyTimerState;
begin
  if FState = nil then begin inherited; Exit; end;
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    // 构造隐含引用的递减也在同一门内，完成后才发布可获取的 Owner。
    inherited;
    LState.FOwner := Self;
  finally LState.FLock.Leave; end;
end;

destructor TEasyTimer.Destroy;
var LState: TEasyTimerState;
begin
  if FState <> nil then
  begin
    LState := FState as TEasyTimerState;
    LState.FLock.Enter;
    try LState.FOwner := nil; finally LState.FLock.Leave; end;
  end;
  Terminate;
  WaitFor;
  inherited;
end;

function TEasyTimer.TimerQueryInterface({$IFDEF FPC}constref{$ELSE}const{$ENDIF} AIID: TGUID;
  out AObject): HResult;
begin
  Result := inherited QueryInterface(AIID, AObject);
end;

function TEasyTimer.TimerAddRef: Integer;
begin
  Result := inherited _AddRef;
end;

function TEasyTimer.TimerRelease: Integer;
var
  LKeepState: IInterface;
  LState: TEasyTimerState;
  LLast: Boolean;
begin
  Result := 0;
  LKeepState := FState;
  if LKeepState = nil then begin Result := inherited _Release; Exit; end;
  LState := LKeepState as TEasyTimerState;
  LState.FLock.Enter;
  try
    LLast := RefCount = 1;
    if LLast then LState.FOwner := nil
    else Result := inherited _Release;
  finally LState.FLock.Leave; end;
  // >1 的递减必须在门内；最后一次交 RTL 析构/join 必须在门外。
  if LLast then Result := inherited _Release;
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
  LTimeout: Integer;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    if ATimeout > 0 then LTimeout := ATimeout else LTimeout := LState.FTimeout;
    Result := (LTimeout > 0) and (LState.FInCallback or LState.FFinished)
      and (LState.FClock.ElapsedMilliseconds - LState.FLastMonoTick > LTimeout);
  finally LState.FLock.Leave; end;
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

function TEasyTimer.WaitFor(const ATimeout: Cardinal): Boolean;
begin
  if FEasyThread <> nil then Result := FEasyThread.WaitFor(ATimeout)
  else Result := True;
end;

function TEasyTimer.GetTimeout: Integer;
var LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try Result := LState.FTimeout; finally LState.FLock.Leave; end;
end;

function TEasyTimer.GetBeforeExecute: TTimerEvent;
var LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try Result := LState.FBeforeExecute; finally LState.FLock.Leave; end;
end;

function TEasyTimer.GetAfterExecute: TTimerEvent;
var LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try Result := LState.FAfterExecute; finally LState.FLock.Leave; end;
end;

procedure TEasyTimer.SetTimeout(const AValue: Integer);
var LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try LState.FTimeout := AValue; finally LState.FLock.Leave; end;
end;

procedure TEasyTimer.SetBeforeExecute(const AValue: TTimerEvent);
var LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    if Assigned(AValue) then LState.CheckEventOwnerLocked(Self);
    LState.FBeforeExecute := AValue;
  finally LState.FLock.Leave; end;
end;

procedure TEasyTimer.SetAfterExecute(const AValue: TTimerEvent);
var LState: TEasyTimerState;
begin
  LState := FState as TEasyTimerState;
  LState.FLock.Enter;
  try
    if Assigned(AValue) then LState.CheckEventOwnerLocked(Self);
    LState.FAfterExecute := AValue;
  finally LState.FLock.Leave; end;
end;

class function TEasyTimer._FullDateTime(const ADateTime: TDateTime): TDateTime;
var LNow: TDateTime;
begin
  if (Trunc(ADateTime) > 0) then
    Result := ADateTime
  else
  begin
    LNow := Now;
    Result := Trunc(LNow) + Frac(ADateTime);
    if (LNow > Result) then
      Result := Result.AddDays(1);
  end;
end;

initialization
  // RTL 频率参数是共享的懒初始化数据，在单元加载期完成，避免首次并发构造竞争。
  TStopwatch.StartNew;

end.
