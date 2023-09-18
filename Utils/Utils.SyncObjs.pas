unit Utils.SyncObjs;

{$I zLib.inc}

interface

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ELSE POSIX}
    {$IFDEF DELPHI}
    Posix.Pthread,
    Posix.Semaphore,
    {$ENDIF}
  {$ENDIF}

  SysUtils,
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

  TLock = class(TInterfacedObject, ILock)
  private
    /// 重新实现的临界区
    /// 因为 Delphi 自带的临界区在非 Windows 环境会依赖 System.TMonitor,
    /// 而 System.TMonitor 的实现太过臃肿, 不够优雅, 所以自己重新实现了一个
    {$IFDEF DELPHI}
      {$IFDEF MSWINDOWS}
      FCriticalSection: TRTLCriticalSection;
      {$ELSE}
      FSemaphore: sem_t;
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

  TEvent = class(TInterfacedObject, IEvent)
  private
    FEvent: SyncObjs.TEvent;
  public
    constructor Create;
    destructor Destroy; override;

    procedure ResetEvent;
    procedure SetEvent;
    function WaitFor(const ATimeout: Cardinal = INFINITE): TWaitResult;
  end;

  TCountdownEvent = class(TInterfacedObject, ICountdownEvent)
  private
    FEvent: IEvent;
    FInitCount, FCurCount: Integer;

    function GetCurrentCount: Integer;
  public
    constructor Create(const ACount: Integer = 1);

    procedure ResetEvent; overload;
    procedure ResetEvent(const ACount: Integer); overload;
    procedure SetEvent;
    function WaitFor(const ATimeout: Cardinal = INFINITE): TWaitResult;

    procedure AddCount(const ACount: Integer = 1);
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
    sem_init(FSemaphore, 0, 1);
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
    sem_destroy(FSemaphore);
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
    sem_wait(FSemaphore);
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
    Result := (sem_trywait(FSemaphore) = 0);
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
    sem_post(FSemaphore);
    {$ELSE}
    LeaveCriticalSection(FCriticalSection);
    {$ENDIF}
  {$ENDIF}
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
  FWriteEvent.WaitFor(INFINITE);
  FLock.Enter;
end;

procedure TReadWriteLock.EndWrite;
begin
  FLock.Leave;
  FWriteEvent.SetEvent;
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
  Result := (FWriteEvent.WaitFor(0) = wrSignaled);

  if Result then
    FLock.Enter;
end;

{ TEvent }

constructor TEvent.Create;
begin
  FEvent := SyncObjs.TEvent.Create();
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

{ TCountdownEvent }

constructor TCountdownEvent.Create(const ACount: Integer);
begin
  FInitCount := ACount;
  FCurCount := ACount;
  FEvent := TEvent.Create;

  if (ACount = 0) then
    FEvent.SetEvent;
end;

function TCountdownEvent.GetCurrentCount: Integer;
begin
  Result := FCurCount;
end;

procedure TCountdownEvent.AddCount(const ACount: Integer);
begin
  if (TInterlocked.Add(FCurCount, ACount) > 0) then
    FEvent.ResetEvent
  else
    FEvent.SetEvent;
end;

procedure TCountdownEvent.ResetEvent(const ACount: Integer);
begin
  AtomicExchange(FCurCount, ACount);
  AtomicExchange(FInitCount, ACount);

  if (ACount > 0) then
    FEvent.ResetEvent
  else
    FEvent.SetEvent;
end;

procedure TCountdownEvent.ResetEvent;
begin
  ResetEvent(FInitCount);
end;

procedure TCountdownEvent.SetEvent;
begin
  if (AtomicDecrement(FCurCount) <= 0) then
    FEvent.SetEvent;
end;

function TCountdownEvent.WaitFor(const ATimeout: Cardinal): TWaitResult;
begin
  Result := FEvent.WaitFor(ATimeout);
end;

end.
