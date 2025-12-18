unit Utils.SyncObjs;

{$I zLib.inc}

interface

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

  // 标准锁对象(使用临界区实现, 不占用系统句柄)
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
  // 比 TLock 性能低, 不要用于需要高吞吐量的场景
  TSpinLock = class(TInterfacedObject, ILock)
  private
    FLock: Integer;
  public
    constructor Create;

    procedure Enter;
    function TryEnter: Boolean;
    procedure Leave;
  end;

  // 读写锁(需要占用一个系统句柄)
  TReadWriteLock = class(TInterfacedObject, IReadWriteLock)
  private
    FReadCount: Integer;
    FLock: ILock;
    FWriteEvent: IEvent;
  public
    constructor Create;

    procedure BeginRead;
    function TryBeginRead: Boolean;
    procedure EndRead;

    procedure BeginWrite;
    function TryBeginWrite: Boolean;
    procedure EndWrite;
  end;

  // 可重入的读写锁(需要占用两个系统句柄)
  // 支持写者优先，防止写者饥饿
  TReenterableRWLock = class(TInterfacedObject, IReadWriteLock)
  private
    FLock: ILock;
    FReadEvent, FWriteEvent: IEvent;
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
    function CanWriteAccess(const AThreadID: TThreadID): Boolean; inline;
    function GetThreadReadCount(const AThreadID: TThreadID): Integer; inline;
  public
    constructor Create;
    destructor Destroy; override;

    procedure BeginRead;
    function TryBeginRead: Boolean;
    procedure EndRead;

    procedure BeginWrite;
    function TryBeginWrite: Boolean;
    procedure EndWrite;
  end;

  // 标准事件对象(需要占用一个系统句柄)
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
  // 比 TEvent 性能低, 不要用于需要高吞吐量的场景
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

  // 自定义带计数的事件对象
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

  // 标准带计数的事件对象(需要占用一个系统句柄)
  TCountdownEvent = class(TCustomCountdownEvent)
  public
    constructor Create(const ACount: Integer = 1); reintroduce;
  end;

  // 自旋带计数的事件对象(不占用系统句柄)
  // 比 TCountdownEvent 性能低, 不要用于需要高吞吐量的场景
  TSpinCountdownEvent = class(TCustomCountdownEvent)
  public
    constructor Create(const ACount: Integer = 1); reintroduce;
  end;

implementation

{ TLock }

constructor TLock.Create;
begin
  {$IFDEF MSWINDOWS}
  {
    InitializeCriticalSectionAndSpinCount函数的第二个参数是旋转计数器的初始值。旋转计数器的作用是在尝试进入临界区之前，先进行自旋操作，如果在自旋期间临界区已经可用，那么就可以避免进入内核等待队列，从而提高性能。
    旋转计数器的初始值越大，表示允许更多次的自旋操作。如果临界区的持有时间很短，那么这样的自旋操作可以提高性能。但如果临界区的持有时间很长，那么自旋操作的效果不佳，反而会浪费CPU时间。
    在Windows系统中，旋转计数器的初始值可以设置为0或大于等于2的值。如果设置为0，则表示不进行自旋操作，直接进入内核等待队列。如果设置为大于等于2的值，则表示进行自旋操作的次数。根据微软官方文档，推荐的初始值范围是1000到4000之间。
    因此，在InitializeCriticalSectionAndSpinCount函数中，参数4000的意义是将旋转计数器的初始值设置为4000，表示在尝试进入临界区之前，允许进行最多4000次的自旋操作。这个值可以根据实际情况进行调整，以平衡临界区持有时间和自旋操作的效果。
  }
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
    Dec(FReadCount);
    if (FReadCount = 0) then
      FWriteEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TReadWriteLock.BeginWrite;
begin
  FLock.Enter;
  try
    // 等待所有读者结束
    while (FReadCount > 0) do
    begin
      FLock.Leave;
      FWriteEvent.WaitFor(INFINITE);
      FLock.Enter;
    end;
    // 阻止新的读者进入
    FWriteEvent.ResetEvent;
  except
    FLock.Leave;
    raise;
  end;
  // 注意：成功获取写锁后不释放 FLock，由 EndWrite 释放
end;

procedure TReadWriteLock.EndWrite;
begin
  FWriteEvent.SetEvent;
  FLock.Leave;
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
  // 先尝试获取锁（非阻塞）
  if not FLock.TryEnter then
    Exit(False);

  // 检查是否有读者
  if (FReadCount > 0) then
  begin
    FLock.Leave;
    Exit(False);
  end;

  // 阻止新的读者进入
  FWriteEvent.ResetEvent;

  // 成功获取写锁，不释放 FLock，由 EndWrite 释放
  Result := True;
end;

{ TReenterableRWLock }

constructor TReenterableRWLock.Create;
begin
  inherited Create;

  FLock := TLock.Create;
  FReadEvent := TEvent.Create(True, True);   // 手动重置，初始有信号
  FWriteEvent := TEvent.Create(True, True);  // 手动重置，初始有信号
  FReaderThreads := TDictionary<TThreadID, Integer>.Create;
  FReaders := 0;
  FWriterThreadID := TThreadID(0);
  FWriterCount := 0;
  FWaitingWriters := 0;
end;

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
  if FReaderThreads.TryGetValue(AThreadID, Result) then
  begin
    Dec(Result);
    if (Result > 0) then
      FReaderThreads.AddOrSetValue(AThreadID, Result)
    else
      FReaderThreads.Remove(AThreadID);
  end else
    Result := 0;
end;

function TReenterableRWLock.CanReadAccess(const AThreadID: TThreadID): Boolean;
begin
  // 写者优先：如果有等待中的写者，新的读者不能进入
  // 但已经在读的线程可以重入
  if (FWaitingWriters > 0) and (GetThreadReadCount(AThreadID) = 0) then
    Exit(False);

  // 只要没有其它线程在写, 就可以读
  Result := (FWriterThreadID = 0) or (FWriterThreadID = AThreadID);
end;

function TReenterableRWLock.CanWriteAccess(const AThreadID: TThreadID): Boolean;
begin
  // 只要没有其它线程在写或读, 就可以写
  //   (GetThreadReadCount(AThreadID) > 0) 表示这个线程有读操作
  //   (FReaders = 1) 表示当前有1个线程在读
  //   这两个条件同时满足说明当前正在读的线程就是AThreadID
  Result := ((FWriterThreadID = 0) or (FWriterThreadID = AThreadID)) and
    ((FReaders = 0) or ((GetThreadReadCount(AThreadID) > 0) and (FReaders = 1)));
end;

procedure TReenterableRWLock.BeginRead;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;

  FLock.Enter;
  try
    // 如果当前线程就是写者, 重入
    if IsThreadWriter(LCurThreadID) then
    begin
      if (IncrementThreadReadCount(LCurThreadID) = 1) then
        Inc(FReaders);
      Exit;
    end;

    // 等待其它线程写结束才允许继续读
    while not CanReadAccess(LCurThreadID) do
    begin
      FLock.Leave;
      FReadEvent.WaitFor(INFINITE);
      FLock.Enter;
    end;

    if (IncrementThreadReadCount(LCurThreadID) = 1) then
    begin
      Inc(FReaders);

      // 第一个读开始之后, 其它线程就不可以写了
      // 所以要将写事件置为无信号状态
      if (FReaders = 1) then
        FWriteEvent.ResetEvent;
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

  FLock.Enter;
  try
    // 如果当前线程就是写者, 重入
    if IsThreadWriter(LCurThreadID) then
    begin
      if (IncrementThreadReadCount(LCurThreadID) = 1) then
        Inc(FReaders);
      Exit(True);
    end;

    // 等待其它线程写结束才允许继续读
    if not CanReadAccess(LCurThreadID) then Exit(False);

    if (IncrementThreadReadCount(LCurThreadID) = 1) then
    begin
      Inc(FReaders);

      // 第一个读开始之后, 其它线程就不可以写了
      // 所以要将写事件置为无信号状态
      if (FReaders = 1) then
        FWriteEvent.ResetEvent;
    end;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TReenterableRWLock.EndRead;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;

  FLock.Enter;
  try
    if (DecrementThreadReadCount(LCurThreadID) = 0) then
    begin
      Dec(FReaders);

      // 所有读结束之后, 其它线程就可以写了
      // 所以要将写事件置为有信号状态
      if (FReaders = 0) then
        FWriteEvent.SetEvent;
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
    // 如果当前线程就是写者, 重入
    if IsThreadWriter(LCurThreadID) then
    begin
      Inc(FWriterCount);
      Exit;
    end;

    // 增加等待写者计数，阻止新的读者进入
    Inc(FWaitingWriters);
    try
      // 等待其它所有写或读线程结束才允许继续写
      while not CanWriteAccess(LCurThreadID) do
      begin
        FLock.Leave;
        FWriteEvent.WaitFor(INFINITE);
        FLock.Enter;
      end;
    finally
      // 获取到写锁后，减少等待写者计数
      Dec(FWaitingWriters);
    end;

    FWriterThreadID := LCurThreadID;
    FWriterCount := 1;

    // 开始写之后, 其它所有线程都不能读或写了
    // 所以要把读和写的事件都置为无信号状态
    FReadEvent.ResetEvent;
    FWriteEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

function TReenterableRWLock.TryBeginWrite: Boolean;
var
  LCurThreadID: TThreadID;
begin
  LCurThreadID := GetCurrentThreadID;

  FLock.Enter;
  try
    // 如果当前线程就是写者, 重入
    if IsThreadWriter(LCurThreadID) then
    begin
      Inc(FWriterCount);
      Exit(True);
    end;

    // 等待其它所有写或读线程结束才允许继续写
    if not CanWriteAccess(LCurThreadID) then Exit(False);

    FWriterThreadID := LCurThreadID;
    FWriterCount := 1;

    // 开始写之后, 其它所有线程都不能读或写了
    FReadEvent.ResetEvent;
    FWriteEvent.ResetEvent;

    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TReenterableRWLock.EndWrite;
begin
  FLock.Enter;
  try
    if IsThreadWriter(GetCurrentThreadID) then
    begin
      Dec(FWriterCount);
      if (FWriterCount = 0) then
      begin
        FWriterThreadID := TThreadID(0);

        // 写者优先：如果有等待中的写者，只唤醒写者
        // 否则同时唤醒读者和写者
        if (FWaitingWriters > 0) then
          FWriteEvent.SetEvent
        else
        begin
          FReadEvent.SetEvent;
          FWriteEvent.SetEvent;
        end;
      end;
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
  LStartTick: UInt64;
  LSpinCount: Integer;
  LState: Integer;
begin
  LStartTick := TThread.GetTickCount64;
  LSpinCount := 0;

  while True do
  begin
    // 判断是否收到信号
    if FManualReset then
    begin
      // 手动重置事件：只检查状态，不修改
      // 使用原子读取代替不必要的CAS
      LState := AtomicCmpExchange(FState, 0, 0);  // 原子读取
      if (LState = 1) then
        Exit(TWaitResult.wrSignaled);
    end else
    begin
      // 自动重置事件：原子性地检测并重置，避免竞态条件
      // 如果FState=1，则将其设为0并返回1（表示成功获取信号）
      if (AtomicCmpExchange(FState, 0, 1) = 1) then
        Exit(TWaitResult.wrSignaled);
    end;

    // 超时检查移到前面，避免不必要的Sleep
    if (ATimeout <> INFINITE) then
    begin
      if (TThread.GetTickCount64 - LStartTick >= ATimeout) then
        Exit(TWaitResult.wrTimeout);
    end;

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

{ TCustomCountdownEvent }

constructor TCustomCountdownEvent.Create(const ASpin: Boolean; const ACount: Integer);
begin
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
  FLock.Enter;
  try
    Inc(FCurCount, ACount);
    if (FCurCount > 0) then
      FEvent.ResetEvent
    else
      FEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TCustomCountdownEvent.ResetEvent(const ACount: Integer);
begin
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
    Dec(FCurCount);
    if (FCurCount <= 0) then
      FEvent.SetEvent;
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
