unit Utils.EasyThread;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Types,

  Utils.AnonymousThread,
  Utils.SyncObjs;

type
  EEasyThread = class(Exception);

  IEasyThread = interface;

  TEasyThreadProc = reference to procedure(const AEasyThread: IEasyThread);

  IEasyThread = interface
  ['{0515FF7C-50A4-4A49-B2C4-F38A52BC97EB}']
    function GetTerminated: Boolean;
    function GetThreadID: TThreadID;

    procedure Terminate;
    procedure WaitFor; overload;
    function WaitFor(const ATimeout: Cardinal): Boolean; overload;

    property Terminated: Boolean read GetTerminated;
    property ThreadID: TThreadID read GetThreadID;
  end;

  TEasyThread = class(TInterfacedObject, IEasyThread)
  private
    FControl: IEasyThread;

    function GetTerminated: Boolean;
    function GetThreadID: TThreadID;
  public
    constructor Create(const AEasyThreadProc: TAnonymousProc); overload;
    constructor Create(const AEasyThreadProc: TEasyThreadProc); overload;
    destructor Destroy; override;

    procedure Terminate;
    procedure WaitFor; overload;
    function WaitFor(const ATimeout: Cardinal): Boolean; overload;

    property Terminated: Boolean read GetTerminated;
    property ThreadID: TThreadID read GetThreadID;
  end;

{$IFDEF CROSS_EASY_THREAD_TESTS}
procedure SetEasyThreadStartHook(const AHook: TAnonymousProc);
function GetEasyThreadDestroyedCountForTest: Integer;
{$ENDIF}

implementation

const
  EASY_THREAD_INFINITE = High(Cardinal);

type
  TEasyThreadControl = class;

  TEasyWorkerThread = class(TThread)
  private
    FControl: IEasyThread;
    FProc: TAnonymousProc;
    FControlProc: TEasyThreadProc;
    procedure _ClearCallbacks;
  protected
    procedure Execute; override;
  public
    constructor Create(const AControl: IEasyThread;
      const AProc: TAnonymousProc; const AControlProc: TEasyThreadProc);
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    destructor Destroy; override;
    {$ENDIF}
  end;

  TEasyThreadControl = class(TInterfacedObject, IEasyThread)
  private
    FThread: TEasyWorkerThread;
    FThreadID: TThreadID;
    FTerminated, FEntered, FJoined: Integer;
    FThreadStarted: Boolean;
    FWaitLock: ILock;
    FCompleted: IEvent;

    function _IsWorkerThread: Boolean;
    function GetTerminated: Boolean;
    function GetThreadID: TThreadID;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const AProc: TAnonymousProc; const AControlProc: TEasyThreadProc);
    procedure Terminate;
    procedure WaitFor; overload;
    function WaitFor(const ATimeout: Cardinal): Boolean; overload;
  end;

{$IFDEF CROSS_EASY_THREAD_TESTS}
var
  GEasyThreadStartHook: TAnonymousProc;
  GEasyThreadDestroyedCount: Integer;

function GetEasyThreadDestroyedCountForTest: Integer;
begin
  Result := AtomicCmpExchange(GEasyThreadDestroyedCount, 0, 0);
end;

procedure SetEasyThreadStartHook(const AHook: TAnonymousProc);
begin
  GEasyThreadStartHook := AHook;
end;
{$ENDIF}

{ TEasyWorkerThread }

constructor TEasyWorkerThread.Create(const AControl: IEasyThread;
  const AProc: TAnonymousProc; const AControlProc: TEasyThreadProc);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FControl := AControl;
  FProc := AProc;
  FControlProc := AControlProc;
end;

{$IFDEF CROSS_EASY_THREAD_TESTS}
destructor TEasyWorkerThread.Destroy;
begin
  inherited;
  AtomicIncrement(GEasyThreadDestroyedCount);
end;
{$ENDIF}

procedure TEasyWorkerThread._ClearCallbacks;
begin
  // 用户捕获的接口析构可能阻塞或重入，不能在等待锁内释放。
  try
    FProc := nil;
  finally
    FControlProc := nil;
  end;
end;

procedure TEasyWorkerThread.Execute;
var
  LControl: IEasyThread;
  LControlObj: TEasyThreadControl;
begin
  LControl := FControl;
  FControl := nil;
  LControlObj := LControl as TEasyThreadControl;
  AtomicExchange(LControlObj.FEntered, 1);
  try
    if LControl.Terminated then Terminate;
    // 已启动的任务仍须进入自身 finally；由任务观察 Terminated 协作退出。
    if Assigned(FProc) then
      FProc()
    else if Assigned(FControlProc) then
      FControlProc(LControl);
  finally
    try
      _ClearCallbacks;
    finally
      // 有限等待只承诺任务和线程持有的闭包清理完成，不代表原生 join。
      LControlObj.FCompleted.SetEvent;
      // 最后一个 Control 引用可在此释放；其析构只移交 FreeOnTerminate。
      LControl := nil;
    end;
  end;
end;

{ TEasyThreadControl }

constructor TEasyThreadControl.Create;
begin
  inherited Create;
  FWaitLock := TLock.Create;
  FCompleted := TEvent.Create(True, False);
end;

procedure TEasyThreadControl.Start(const AProc: TAnonymousProc;
  const AControlProc: TEasyThreadProc);
var
  LThread: TEasyWorkerThread;
begin
  FThread := TEasyWorkerThread.Create(Self, AProc, AControlProc);
  FThreadID := FThread.ThreadID;
  try
    {$IFDEF CROSS_EASY_THREAD_TESTS}
    if Assigned(GEasyThreadStartHook) then GEasyThreadStartHook();
    {$ENDIF}
    FThreadStarted := True;
    FThread.Start;
  except
    // 未启动的线程不会执行 finally，必须显式拆掉 Control/线程捕获环。
    FThreadStarted := False;
    LThread := FThread;
    FThread := nil;
    LThread.Terminate;
    try
      try
        LThread._ClearCallbacks;
      finally
        LThread.FControl := nil;
      end;
    finally
      try
        LThread.Free;
      finally
        FCompleted.SetEvent;
      end;
    end;
    raise;
  end;
end;

destructor TEasyThreadControl.Destroy;
begin
  Terminate;
  if FThread <> nil then
  begin
    if _IsWorkerThread then
    begin
      // Execute 尚未返回，不能等待或释放当前 TThread。
      FThread.FreeOnTerminate := True;
      FThread := nil;
    end else
    begin
      WaitFor;
      FreeAndNil(FThread);
    end;
  end;
  inherited;
end;

function TEasyThreadControl._IsWorkerThread: Boolean;
begin
  // 比较仍由 Control 持有的对象身份，不以可能复用的原生 ID 判定自身。
  Result := (FThread <> nil) and (FThread = TThread.CurrentThread);
end;

function TEasyThreadControl.GetTerminated: Boolean;
begin
  Result := (AtomicCmpExchange(FTerminated, 0, 0) <> 0);
end;

function TEasyThreadControl.GetThreadID: TThreadID;
begin
  // POSIX 的 WaitFor 可能清空底层 ThreadID，公开身份仍使用创建时的缓存。
  Result := FThreadID;
end;

procedure TEasyThreadControl.Terminate;
begin
  AtomicExchange(FTerminated, 1);
  // RTL 会跳过已 Terminate 线程的 Execute；入口前只标记协作状态，
  // 保证已启动任务仍执行自身收尾，随后在锁外清掉全部捕获。
  if (FThread <> nil) and (AtomicCmpExchange(FEntered, 0, 0) <> 0) then
    FThread.Terminate;
end;

procedure TEasyThreadControl.WaitFor;
begin
  if (FThread = nil) or not FThreadStarted then Exit;
  // 自身等待是 no-op；必须先于等待锁，避免和外部 join 者互等。
  if _IsWorkerThread then Exit;
  if TThread.CurrentThread.ThreadID = MainThreadID then
  begin
    // 其他线程可能正 join 一个等待主线程 Synchronize 的工作线程。
    while not FWaitLock.TryEnter do CheckSynchronize(10);
  end else
    FWaitLock.Enter;
  try
    if AtomicCmpExchange(FJoined, 0, 0) = 0 then
    begin
      FThread.WaitFor;
      AtomicExchange(FJoined, 1);
    end;
  finally
    FWaitLock.Leave;
  end;
end;

function TEasyThreadControl.WaitFor(const ATimeout: Cardinal): Boolean;
var
  LStart, LElapsed: UInt64;
  LRemaining: Cardinal;
  LWaitResult: TWaitResult;
begin
  LStart := TThread.GetTickCount64;
  // True 在自身调用时仅表示 no-op，不能据此认定当前线程已经退出。
  if _IsWorkerThread then Exit(True);
  if ATimeout = EASY_THREAD_INFINITE then
  begin
    Self.WaitFor;
    Exit(True);
  end;

  repeat
    LElapsed := TThread.GetTickCount64 - LStart;
    if LElapsed >= ATimeout then LRemaining := 0
    else LRemaining := ATimeout - Cardinal(LElapsed);
    // 兼容单次等待使用有符号毫秒的 RTL；大有限值分段，仍共用一个截止时间。
    if LRemaining > Cardinal(High(Integer)) then LRemaining := High(Integer);
    // 不进入 join 锁、不执行 CheckSynchronize；timeout=0 也查询一次完成事件。
    LWaitResult := FCompleted.WaitFor(LRemaining);
    case LWaitResult of
      TWaitResult.wrSignaled: Exit(True);
      TWaitResult.wrTimeout:
        if TThread.GetTickCount64 - LStart >= ATimeout then Exit(False);
    else
      raise EEasyThread.Create('等待线程完成事件失败');
    end;
  until False;
end;

{ TEasyThread }

constructor TEasyThread.Create(const AEasyThreadProc: TAnonymousProc);
var
  LControlObj: TEasyThreadControl;
begin
  LControlObj := TEasyThreadControl.Create;
  FControl := LControlObj;
  LControlObj.Start(AEasyThreadProc, nil);
end;

constructor TEasyThread.Create(const AEasyThreadProc: TEasyThreadProc);
var
  LControlObj: TEasyThreadControl;
begin
  LControlObj := TEasyThreadControl.Create;
  FControl := LControlObj;
  LControlObj.Start(nil, AEasyThreadProc);
end;

destructor TEasyThread.Destroy;
begin
  try
    Terminate;
    // 外部析构真实 join；自身调用由 Control.WaitFor 的 no-op 安全跳过。
    WaitFor;
  finally
    FControl := nil;
    inherited;
  end;
end;

function TEasyThread.GetTerminated: Boolean;
begin
  Result := (FControl = nil) or FControl.Terminated;
end;

function TEasyThread.GetThreadID: TThreadID;
begin
  if FControl <> nil then Result := FControl.ThreadID
  else Result := TThreadID(0);
end;

procedure TEasyThread.Terminate;
begin
  if FControl <> nil then FControl.Terminate;
end;

procedure TEasyThread.WaitFor;
begin
  if FControl <> nil then FControl.WaitFor;
end;

function TEasyThread.WaitFor(const ATimeout: Cardinal): Boolean;
begin
  if FControl <> nil then Result := FControl.WaitFor(ATimeout)
  else Result := True;
end;

end.
