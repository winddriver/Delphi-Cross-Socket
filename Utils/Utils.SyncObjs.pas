unit Utils.SyncObjs;

{$I zLib.inc}

interface

// 调用注意事项：
// 1. 普通读锁期间不得直接、间接或在回调中申请写锁；不支持读转写升级。
//    违规 BeginWrite 可能永久等待，不抛升级冲突异常；TryBeginWrite 返回 False。
// 2. 加锁成功后用 try/finally 配对解锁；Try 失败不得解锁。锁须由持有线程释放。
// 3. 接口引用计数只管理寿命，不自动解锁。各线程持有稳定引用，所有使用/等待结束后再释放。
//    对同一共享接口变量的并发赋值仍需外部同步。

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}

  SysUtils,
  Classes,
  Generics.Collections,
  SyncObjs;

type
  TWaitResult = SyncObjs.TWaitResult;

  {$REGION 'Documentation'}
  /// <summary>
  ///   锁
  /// </summary>
  {$ENDREGION}
  ILock = interface
  ['{6BD0498E-E51A-42EF-B830-19D7FADC1452}']
    {$REGION 'Documentation'}
    /// <summary>
    ///   加锁
    /// </summary>
    {$ENDREGION}
    procedure Enter;

    {$REGION 'Documentation'}
    /// <summary>
    ///   尝试加锁
    /// </summary>
    {$ENDREGION}
    function TryEnter: Boolean;

    {$REGION 'Documentation'}
    /// <summary>
    ///   解锁
    /// </summary>
    {$ENDREGION}
    procedure Leave;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   读写锁
  /// </summary>
  {$ENDREGION}
  IReadWriteLock = interface
  ['{D0626383-23CB-4614-AAE7-566EDD539BFD}']
    {$REGION 'Documentation'}
    /// <summary>
    ///   开始读
    /// </summary>
    {$ENDREGION}
    procedure BeginRead;

    {$REGION 'Documentation'}
    /// <summary>
    ///   尝试读
    /// </summary>
    {$ENDREGION}
    function TryBeginRead: Boolean;

    {$REGION 'Documentation'}
    /// <summary>
    ///   结束读
    /// </summary>
    {$ENDREGION}
    procedure EndRead;

    {$REGION 'Documentation'}
    /// <summary>
    ///   开始写
    /// </summary>
    {$ENDREGION}
    procedure BeginWrite;

    {$REGION 'Documentation'}
    /// <summary>
    ///   尝试写
    /// </summary>
    {$ENDREGION}
    function TryBeginWrite: Boolean;

    {$REGION 'Documentation'}
    /// <summary>
    ///   结束写
    /// </summary>
    {$ENDREGION}
    procedure EndWrite;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   事件
  /// </summary>
  {$ENDREGION}
  IEvent = interface
  ['{69BE8CE9-9090-47D4-8108-43DC13DC7206}']
    {$REGION 'Documentation'}
    /// <summary>
    ///   重置事件(让事件进入等待状态)
    /// </summary>
    {$ENDREGION}
    procedure ResetEvent;

    {$REGION 'Documentation'}
    /// <summary>
    ///   唤醒事件(让事件结束等待)
    /// </summary>
    {$ENDREGION}
    procedure SetEvent;

    {$REGION 'Documentation'}
    /// <summary>
    ///   等待事件
    /// </summary>
    /// <param name="ATimeout">
    ///   超时(毫秒)
    /// </param>
    {$ENDREGION}
    function WaitFor(const ATimeout: Cardinal = INFINITE): TWaitResult;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   带计数的事件(每唤醒一次, 计数-1, 计数到0结束等待)
  /// </summary>
  {$ENDREGION}
  ICountdownEvent = interface(IEvent)
  ['{0D470824-936E-4730-9288-1FC1D9B7CE1B}']
    {$REGION 'Documentation'}
    /// <summary>
    ///   重置事件(让事件进入等待状态)
    /// </summary>
    /// <param name="ACount">
    ///   计数器
    /// </param>
    {$ENDREGION}
    procedure ResetEvent(const ACount: Integer);

    {$REGION 'Documentation'}
    /// <summary>
    ///   增加计数
    /// </summary>
    /// <param name="ACount">
    ///   计数器
    /// </param>
    {$ENDREGION}
    procedure AddCount(const ACount: Integer = 1);

    {$REGION 'Documentation'}
    /// <summary>
    ///   当前计数器
    /// </summary>
    {$ENDREGION}
    function GetCurrentCount: Integer;

    {$REGION 'Documentation'}
    /// <summary>
    ///   当前计数器
    /// </summary>
    {$ENDREGION}
    property CurrentCount: Integer read GetCurrentCount;
  end;

  // 可重入临界区。未显式创建事件，平台内部仍可能分配等待资源。
  TLock = class(TInterfacedObject, ILock)
  private
    {$IFDEF DELPHI}
      {$IFDEF MSWINDOWS}
      FCriticalSection: TRTLCriticalSection;
      {$ELSE}
      FCriticalSection: TCriticalSection;
      {$ENDIF}
    {$ELSE}
    FCriticalSection: TRTLCriticalSection;
    {$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;

    procedure Enter;
    function TryEnter: Boolean;
    procedure Leave;
  end;

  // 自旋锁对象(不占用系统句柄)
  // 不可重入；竞争时休眠轮询，释放不会主动唤醒等待者，长等待优先考虑 TLock。
  TSpinLock = class(TInterfacedObject, ILock)
  private
    FLock: Integer;
  public
    constructor Create;

    procedure Enter;
    function TryEnter: Boolean;
    procedure Leave;
  end;

  // 使用一个事件的读者优先锁；不保证写者等待上限，不支持普通读转写。
  // 支持正确嵌套的读中读、写中写和写中读；不跟踪每个读者的线程所有权。
  TReadWriteLock = class(TInterfacedObject, IReadWriteLock)
  private
    FReadCount: Integer;
    FLock: ILock;
    FWriteEvent: IEvent;
  public
    constructor Create; overload;
    {$IFDEF SYNCOBJS_SELFTEST}
    constructor Create(const ALock: ILock; const AWriteEvent: IEvent); overload;
    {$ENDIF}

    procedure BeginRead;
    function TryBeginRead: Boolean;
    procedure EndRead;

    procedure BeginWrite;
    function TryBeginWrite: Boolean;
    procedure EndWrite;
  end;

  // 使用两个事件的可重入读写锁。写者排队后阻挡新读者，不保证 FIFO 或有界等待。
  // 支持读中读、写中写、写中读；已有写者再次写仍是重入，而不是普通读转写。
  // 可先取得读锁再 EndWrite 降级，其他写者等最后一层读退出后才可进入。
  TReenterableRWLock = class(TInterfacedObject, IReadWriteLock)
  private
    FLock: ILock;
    FReadEvent, FWriteEvent: IEvent;
    FReadSignaled, FWriteSignaled: Boolean;
    FReaders: Integer;           // 当前活跃的读者线程数
    FWriterCount: Integer;       // 写者重入计数
    FWaitingWriters: Integer;    // 等待中的写者数量(用于写者优先)
    FWriterThreadID: TThreadID;  // 当前写者线程ID
    FReaderThreads: TDictionary<TThreadID, Integer>;  // 每个读者线程的重入计数

    class function GetCurrentThreadID: TThreadID; static; inline;
    function IsThreadWriter(const AThreadID: TThreadID): Boolean; inline;
    function IncrementThreadReadCount(const AThreadID: TThreadID): Integer;
    function DecrementThreadReadCount(const AThreadID: TThreadID): Integer;
    function CanReadAccess(const AThreadID: TThreadID): Boolean; inline;
    function CanWriteAccess: Boolean; inline;
    function GetThreadReadCount(const AThreadID: TThreadID): Integer; inline;
    procedure UpdateEvents;
  public
    constructor Create; overload;
    {$IFDEF SYNCOBJS_SELFTEST}
    constructor Create(const ALock: ILock; const AReadEvent, AWriteEvent: IEvent); overload;
    {$ENDIF}
    destructor Destroy; override;

    procedure BeginRead;
    function TryBeginRead: Boolean;
    procedure EndRead;

    procedure BeginWrite;
    function TryBeginWrite: Boolean;
    procedure EndWrite;
  end;

  // RTL 事件包装；默认手动重置、初始无信号。等待返回 wrError 不代表收到信号。
  TEvent = class(TInterfacedObject, IEvent)
  private
    FEvent: SyncObjs.TEvent;
  public
    constructor Create(const AManualReset, AInitialState: Boolean); overload;
    constructor Create; overload;
    destructor Destroy; override;

    procedure ResetEvent;
    procedure SetEvent;
    function WaitFor(const ATimeout: Cardinal = INFINITE): TWaitResult;
  end;

  // 自旋事件对象(不占用系统句柄)
  // 轮询事件：不依赖短暂 SetEvent/ResetEvent 传递必达通知；自动事件不累计信号次数。
  TSpinEvent = class(TInterfacedObject, IEvent)
  private
    FState: Integer;
    FManualReset: Boolean;
  public
    constructor Create(const AManualReset, AInitialState: Boolean); overload;
    constructor Create; overload;

    procedure ResetEvent;
    procedure SetEvent;
    function WaitFor(const ATimeout: Cardinal = INFINITE): TWaitResult;
  end;

  // 计数事件：构造/Reset 计数非负，AddCount 必须为正且不溢出；非法参数抛范围异常。
  // 先登记任务再启动，避免登记未完成时提前归零。零后多余 SetEvent 不再减计数。
  // Reset 或零后 AddCount 开启新一轮前，调用方须结束旧轮回调及等待；本对象不区分代次。
  TCustomCountdownEvent = class(TInterfacedObject, ICountdownEvent)
  private
    FLock: ILock;  // 保护计数和事件状态的一致性
    FEvent: IEvent;
    FInitCount, FCurCount: Integer;

    function GetCurrentCount: Integer;
  public
    constructor Create(const ASpin: Boolean; const ACount: Integer = 1);

    procedure ResetEvent; overload;
    procedure ResetEvent(const ACount: Integer); overload;
    procedure SetEvent;
    function WaitFor(const ATimeout: Cardinal = INFINITE): TWaitResult;

    procedure AddCount(const ACount: Integer = 1);
  end;

  // 等待显式使用一个 RTL 事件，计数保护使用临界区。
  TCountdownEvent = class(TCustomCountdownEvent)
  public
    constructor Create(const ACount: Integer = 1); reintroduce;
  end;

  // 等待使用自旋事件，计数保护使用临界区，不能保证完全没有平台等待资源。
  // 共享计数事件的参数/复用契约，等待采用轮询，适用性需按负载测量。
  TSpinCountdownEvent = class(TCustomCountdownEvent)
  public
    constructor Create(const ACount: Integer = 1); reintroduce;
  end;

implementation

// 调用时已持有内部锁。即使底层等待抛异常，也先恢复持锁状态再由上层清理。
procedure WaitForEvent(const ALock: ILock; const AEvent: IEvent);
var
  LResult: TWaitResult;
begin
  ALock.Leave;
  try
    LResult := AEvent.WaitFor(INFINITE);
  finally
    ALock.Enter;
  end;
  // 实际等待失败不能当成取得锁；这不是正常竞争或升级冲突异常。
  if LResult <> wrSignaled then
    raise ESyncObjectException.CreateFmt('同步事件等待失败: %d', [Ord(LResult)]);
end;

{ TLock }

constructor TLock.Create;
begin
  {$IFDEF MSWINDOWS}
  // 4000 为当前短临界区的自旋策略，实际收益取决于负载和平台。
  InitializeCriticalSectionAndSpinCount(FCriticalSection, 4000);
  {$ELSE}
    {$IFDEF DELPHI}
    FCriticalSection := TCriticalSection.Create;
    {$ELSE}
    InitCriticalSection(FCriticalSection);
    {$ENDIF}
  {$ENDIF}
end;

destructor TLock.Destroy;
begin
  {$IFDEF MSWINDOWS}
  DeleteCriticalSection(FCriticalSection);
  {$ELSE}
    {$IFDEF DELPHI}
    FreeAndNil(FCriticalSection);
    {$ELSE}
    DoneCriticalSection(FCriticalSection);
    {$ENDIF}
  {$ENDIF}

  inherited Destroy;
end;

procedure TLock.Enter;
begin
  {$IFDEF MSWINDOWS}
  EnterCriticalSection(FCriticalSection);
  {$ELSE}
    {$IFDEF DELPHI}
    FCriticalSection.Enter;
    {$ELSE}
    EnterCriticalSection(FCriticalSection);
    {$ENDIF}
  {$ENDIF}
end;

function TLock.TryEnter: Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := TryEnterCriticalSection(FCriticalSection);
  {$ELSE}
    {$IFDEF DELPHI}
    Result := FCriticalSection.TryEnter;
    {$ELSE}
    Result := (TryEnterCriticalSection(FCriticalSection) <> 0);
    {$ENDIF}
  {$ENDIF}
end;

procedure TLock.Leave;
begin
  {$IFDEF MSWINDOWS}
  LeaveCriticalSection(FCriticalSection);
  {$ELSE}
    {$IFDEF DELPHI}
    FCriticalSection.Leave;
    {$ELSE}
    LeaveCriticalSection(FCriticalSection);
    {$ENDIF}
  {$ENDIF}
end;

{ TSpinLock }

constructor TSpinLock.Create;
begin
  FLock := 0;
end;

procedure TSpinLock.Enter;
var
  LSpinCount: Integer;
begin
  LSpinCount := 0;

  while not TryEnter do
  begin
    if (LSpinCount < 1000) then
      Inc(LSpinCount);

    // 自旋退避, 避免 CPU 占满
    if (LSpinCount < 100) then
      Sleep(0)
    else if (LSpinCount < 1000) then
      Sleep(1)
    else
      Sleep(5);
  end;
end;

procedure TSpinLock.Leave;
begin
  AtomicExchange(FLock, 0);
end;

function TSpinLock.TryEnter: Boolean;
begin
  Result := (AtomicCmpExchange(FLock, 1, 0) = 0);
end;

{ TReadWriteLock }

constructor TReadWriteLock.Create;
begin
  FLock := TLock.Create;
  FWriteEvent := TEvent.Create;
  FWriteEvent.SetEvent;
  FReadCount := 0;
end;

{$IFDEF SYNCOBJS_SELFTEST}
constructor TReadWriteLock.Create(const ALock: ILock; const AWriteEvent: IEvent);
begin
  inherited Create;
  FLock := ALock;
  FWriteEvent := AWriteEvent;
  FWriteEvent.SetEvent;
end;
{$ENDIF}

procedure TReadWriteLock.BeginRead;
begin
  FLock.Enter;
  try
    Inc(FReadCount);
    if (FReadCount = 1) then
      FWriteEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TReadWriteLock.EndRead;
begin
  FLock.Enter;
  try
    if FReadCount <= 0 then Exit;
    Dec(FReadCount);
    if FReadCount = 0 then FWriteEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TReadWriteLock.BeginWrite;
begin
  FLock.Enter;
  try
    // 自己持有的读锁也计入 FReadCount，因此禁止普通读转写。
    while FReadCount > 0 do
      WaitForEvent(FLock, FWriteEvent);
    FWriteEvent.ResetEvent;
  except
    FLock.Leave;
    raise;
  end;
  // 写期间保留内部锁，最后由调用方 EndWrite。
end;

procedure TReadWriteLock.EndWrite;
begin
  try
    // 保留读锁降级时，不让其他写者在有信号的事件上空转。
    if FReadCount = 0 then FWriteEvent.SetEvent
    else FWriteEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

function TReadWriteLock.TryBeginRead: Boolean;
begin
  Result := FLock.TryEnter;

  if Result then
  begin
    try
      Inc(FReadCount);
      if (FReadCount = 1) then
        FWriteEvent.ResetEvent;
    finally
      FLock.Leave;
    end;
  end;
end;

function TReadWriteLock.TryBeginWrite: Boolean;
begin
  if not FLock.TryEnter then Exit(False);
  try
    if FReadCount > 0 then
    begin
      FLock.Leave;
      Exit(False);
    end;
    FWriteEvent.ResetEvent;
    Result := True;
  except
    FLock.Leave;
    raise;
  end;
end;

{ TReenterableRWLock }

constructor TReenterableRWLock.Create;
begin
  inherited Create;

  FLock := TLock.Create;
  FReadEvent := TEvent.Create(True, True);   // 手动重置，初始有信号
  FWriteEvent := TEvent.Create(True, True);  // 手动重置，初始有信号
  FReaderThreads := TDictionary<TThreadID, Integer>.Create;
  FReadSignaled := True;
  FWriteSignaled := True;
  FReaders := 0;
  FWriterThreadID := TThreadID(0);
  FWriterCount := 0;
  FWaitingWriters := 0;
end;

{$IFDEF SYNCOBJS_SELFTEST}
constructor TReenterableRWLock.Create(const ALock: ILock;
  const AReadEvent, AWriteEvent: IEvent);
begin
  inherited Create;
  FLock := ALock;
  FReadEvent := AReadEvent;
  FWriteEvent := AWriteEvent;
  FReadEvent.SetEvent;
  FWriteEvent.SetEvent;
  FReaderThreads := TDictionary<TThreadID, Integer>.Create;
  FReadSignaled := True;
  FWriteSignaled := True;
end;
{$ENDIF}

destructor TReenterableRWLock.Destroy;
begin
  FreeAndNil(FReaderThreads);

  inherited Destroy;
end;

function TReenterableRWLock.IsThreadWriter(const AThreadID: TThreadID): Boolean;
begin
  Result := (FWriterThreadID = AThreadID) and (FWriterCount > 0);
end;

class function TReenterableRWLock.GetCurrentThreadID: TThreadID;
begin
  Result := TThread.CurrentThread.ThreadID;
end;

function TReenterableRWLock.GetThreadReadCount(const AThreadID: TThreadID): Integer;
begin
  if not FReaderThreads.TryGetValue(AThreadID, Result) then
    Result := 0;
end;

function TReenterableRWLock.IncrementThreadReadCount(const AThreadID: TThreadID): Integer;
begin
  if not FReaderThreads.TryGetValue(AThreadID, Result) then
    Result := 0;
  Inc(Result);
  FReaderThreads.AddOrSetValue(AThreadID, Result);
end;

function TReenterableRWLock.DecrementThreadReadCount(const AThreadID: TThreadID): Integer;
begin
  if not FReaderThreads.TryGetValue(AThreadID, Result) then
    Exit(-1); // 未持有与正常归零不同，不得减少全局读者数。
  Dec(Result);
  if Result > 0 then FReaderThreads.AddOrSetValue(AThreadID, Result)
  else FReaderThreads.Remove(AThreadID);
end;

procedure TReenterableRWLock.UpdateEvents;
var
  LReadSignaled, LWriteSignaled: Boolean;
begin
  LReadSignaled := (FWriterCount = 0) and (FWaitingWriters = 0);
  LWriteSignaled := (FWriterCount = 0) and (FReaders = 0);
  if LReadSignaled <> FReadSignaled then
  begin
    if LReadSignaled then FReadEvent.SetEvent else FReadEvent.ResetEvent;
    FReadSignaled := LReadSignaled;
  end;
  if LWriteSignaled <> FWriteSignaled then
  begin
    if LWriteSignaled then FWriteEvent.SetEvent else FWriteEvent.ResetEvent;
    FWriteSignaled := LWriteSignaled;
  end;
end;

function TReenterableRWLock.CanReadAccess(const AThreadID: TThreadID): Boolean;
begin
  // 写者优先：如果有等待中的写者，新的读者不能进入
  // 但已经在读的线程可以重入
  if (FWaitingWriters > 0) and (GetThreadReadCount(AThreadID) = 0) then
    Exit(False);

  // 只要没有其它线程在写, 就可以读
  Result := (FWriterThreadID = TThreadID(0)) or (FWriterThreadID = AThreadID);
end;

function TReenterableRWLock.CanWriteAccess: Boolean;
begin
  // 已有写者的重入由入口单独处理；普通读者即使唯一也不能升级。
  Result := (FWriterThreadID = TThreadID(0)) and (FReaders = 0);
end;

procedure TReenterableRWLock.BeginRead;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;
  FLock.Enter;
  try
    if not IsThreadWriter(LCurThreadID) then
      while not CanReadAccess(LCurThreadID) do
        WaitForEvent(FLock, FReadEvent);
    if IncrementThreadReadCount(LCurThreadID) = 1 then
    begin
      Inc(FReaders);
      UpdateEvents;
    end;
  finally
    FLock.Leave;
  end;
end;

function TReenterableRWLock.TryBeginRead: Boolean;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;
  if not FLock.TryEnter then Exit(False);
  try
    if not IsThreadWriter(LCurThreadID) and not CanReadAccess(LCurThreadID) then
      Exit(False);
    if IncrementThreadReadCount(LCurThreadID) = 1 then
    begin
      Inc(FReaders);
      UpdateEvents;
    end;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TReenterableRWLock.EndRead;
begin
  FLock.Enter;
  try
    if DecrementThreadReadCount(GetCurrentThreadID) = 0 then
    begin
      Dec(FReaders);
      UpdateEvents;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TReenterableRWLock.BeginWrite;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;
  FLock.Enter;
  try
    if IsThreadWriter(LCurThreadID) then
    begin
      Inc(FWriterCount);
      Exit;
    end;
    Inc(FWaitingWriters);
    try
      UpdateEvents;
      while not CanWriteAccess do
        WaitForEvent(FLock, FWriteEvent);
      FWriterThreadID := LCurThreadID;
      FWriterCount := 1;
    finally
      Dec(FWaitingWriters);
      // 成功时已发布写者，失败时恢复新读者通道，均没有中间可见窗口。
      UpdateEvents;
    end;
  finally
    FLock.Leave;
  end;
end;

function TReenterableRWLock.TryBeginWrite: Boolean;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;
  if not FLock.TryEnter then Exit(False);
  try
    if IsThreadWriter(LCurThreadID) then
    begin
      Inc(FWriterCount);
      Exit(True);
    end;
    if not CanWriteAccess then Exit(False);
    FWriterThreadID := LCurThreadID;
    FWriterCount := 1;
    UpdateEvents;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TReenterableRWLock.EndWrite;
begin
  FLock.Enter;
  try
    if not IsThreadWriter(GetCurrentThreadID) then Exit;
    Dec(FWriterCount);
    if FWriterCount = 0 then
    begin
      FWriterThreadID := TThreadID(0);
      UpdateEvents;
    end;
  finally
    FLock.Leave;
  end;
end;

{ TEvent }

constructor TEvent.Create(const AManualReset, AInitialState: Boolean);
begin
  FEvent := SyncObjs.TEvent.Create(nil, AManualReset, AInitialState, '', False);
end;

constructor TEvent.Create;
begin
  Create(True, False);
end;

destructor TEvent.Destroy;
begin
  FreeAndNil(FEvent);
  inherited;
end;

procedure TEvent.ResetEvent;
begin
  FEvent.ResetEvent;
end;

procedure TEvent.SetEvent;
begin
  FEvent.SetEvent;
end;

function TEvent.WaitFor(const ATimeout: Cardinal): TWaitResult;
begin
  Result := FEvent.WaitFor(ATimeout);
end;

{ TSpinEvent }

constructor TSpinEvent.Create(const AManualReset, AInitialState: Boolean);
begin
  FManualReset := AManualReset;
  if AInitialState then
    FState := 1
  else
    FState := 0;
end;

constructor TSpinEvent.Create;
begin
  Create(True, False);
end;

procedure TSpinEvent.ResetEvent;
begin
  AtomicExchange(FState, 0);
end;

procedure TSpinEvent.SetEvent;
begin
  AtomicExchange(FState, 1);
end;

function TSpinEvent.WaitFor(const ATimeout: Cardinal): TWaitResult;
var
  LStartTick, LElapsed, LRemaining: UInt64;
  LSpinCount: Integer;
  LDelay: Cardinal;
begin
  LStartTick := 0;
  if (ATimeout <> 0) and (ATimeout <> INFINITE) then
    LStartTick := TThread.GetTickCount64;
  LSpinCount := 0;
  while True do
  begin
    if FManualReset then
    begin
      // CAS 提供原子观察，不能直接改成缺少可见性保障的普通字段读取。
      if AtomicCmpExchange(FState, 0, 0) = 1 then Exit(wrSignaled);
    end else
      if AtomicCmpExchange(FState, 0, 1) = 1 then Exit(wrSignaled);
    if ATimeout = 0 then Exit(wrTimeout);
    LRemaining := INFINITE;
    if ATimeout <> INFINITE then
    begin
      LElapsed := TThread.GetTickCount64 - LStartTick;
      if LElapsed >= ATimeout then Exit(wrTimeout);
      LRemaining := ATimeout - LElapsed;
    end;
    if LSpinCount < 1000 then Inc(LSpinCount);
    if LSpinCount < 100 then LDelay := 0
    else if LSpinCount < 1000 then LDelay := 1
    else LDelay := 5;
    if UInt64(LDelay) > LRemaining then LDelay := Cardinal(LRemaining);
    Sleep(LDelay);
  end;
end;

{ TCustomCountdownEvent }

constructor TCustomCountdownEvent.Create(const ASpin: Boolean; const ACount: Integer);
begin
  if ACount < 0 then raise EArgumentOutOfRangeException.Create('初始计数不能为负数');
  FLock := TLock.Create;

  if ASpin then
    FEvent := TSpinEvent.Create
  else
    FEvent := TEvent.Create;

  FInitCount := ACount;
  FCurCount := ACount;

  if (ACount = 0) then
    FEvent.SetEvent;
end;

function TCustomCountdownEvent.GetCurrentCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCurCount;
  finally
    FLock.Leave;
  end;
end;

procedure TCustomCountdownEvent.AddCount(const ACount: Integer);
begin
  if ACount <= 0 then
    raise EArgumentOutOfRangeException.Create('增加计数必须大于零');
  FLock.Enter;
  try
    if ACount > High(Integer) - FCurCount then
      raise EArgumentOutOfRangeException.Create('增加计数超出 Integer 范围');
    if FCurCount = 0 then FEvent.ResetEvent;
    Inc(FCurCount, ACount);
  finally
    FLock.Leave;
  end;
end;

procedure TCustomCountdownEvent.ResetEvent(const ACount: Integer);
begin
  if ACount < 0 then raise EArgumentOutOfRangeException.Create('重置计数不能为负数');
  FLock.Enter;
  try
    FCurCount := ACount;
    FInitCount := ACount;

    if (ACount > 0) then
      FEvent.ResetEvent
    else
      FEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TCustomCountdownEvent.ResetEvent;
begin
  FLock.Enter;
  try
    FCurCount := FInitCount;

    if (FCurCount > 0) then
      FEvent.ResetEvent
    else
      FEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TCustomCountdownEvent.SetEvent;
begin
  FLock.Enter;
  try
    if FCurCount = 0 then Exit;
    Dec(FCurCount);
    if FCurCount = 0 then FEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TCustomCountdownEvent.WaitFor(const ATimeout: Cardinal): TWaitResult;
begin
  Result := FEvent.WaitFor(ATimeout);
end;

{ TCountdownEvent }

constructor TCountdownEvent.Create(const ACount: Integer);
begin
  inherited Create(False, ACount);
end;

{ TSpinCountdownEvent }

constructor TSpinCountdownEvent.Create(const ACount: Integer);
begin
  inherited Create(True, ACount);
end;

end.
