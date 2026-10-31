{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Epoll;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,

  {$IFDEF DELPHI}
  Posix.Base,
  Posix.SysSocket,
  Posix.NetinetIn,
  Posix.UniStd,
  Posix.NetDB,
  Posix.Pthread,
  Posix.ArpaInet,
  Posix.Errno,
  Linux.epoll,
  {$ELSE}
  baseunix,
  unix,
  linux,
  syscall,
  sockets,
  netdb,
  cnetdb,
  DTF.RTL,
  {$ENDIF DELPHI}

  Net.SocketAPI,
  Net.CrossSocket.Base,

  Utils.SyncObjs,
  Utils.ArrayUtils;

type
  TIoEvent = (ieRead, ieWrite);
  TIoEvents = set of TIoEvent;

  TEpollListen = class(TCrossListenBase)
  private
    FEpollHandle: Integer;
    FOpCode: Integer;

    function _UpdateIoEvent(const AIoEvents: TIoEvents; out AError: Integer): Boolean;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer); override;
  end;

  PSendItem = ^TSendItem;
  TSendItem = record
    Data: PByte;
    Size: Integer;
    Callback: TCrossConnectionCallback;
  end;

  TSendQueue = class(TQueue<PSendItem>)
  protected
    procedure Notify(const Value: PSendItem; Action: TCollectionNotification); override;
  end;

  TEpollConnection = class(TCrossConnectionBase)
  private
    FEpollHandle: Integer;
    FSendQueue: TSendQueue;
    FEpLock: ILock;
    FOpCode: Integer;
    FInPending, FOutPending: Integer;

    function _UpdateIoEvent(const AIoEvents: TIoEvents; out ACloseRequired: Boolean): Boolean;
    procedure _ClearSendQueue;

    // 为了减少死锁的可能, 不使用父类的 _Lock/_Unlock
    // 因为父类的 _Lock/_Unlock 主要用于连接事件和接收数据事件
    // 这里的 _EpLock/_EpUnlock 主要用于发送队列和Epoll事件
    // 在接收完数据之后马上发送数据, 如果使用同一把锁可能会引起死锁
    procedure _EpLock; inline;
    procedure _EpUnlock; inline;
  protected
    procedure InternalClose; override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;
  end;

  // KQUEUE 与 EPOLL 队列的差异
  //    KQUEUE的队列中, 一个Socket句柄可以有多条记录, 每个事件一条,
  //    这一点和 EPOLL 不一样, EPOLL中每个Socket句柄只会有一条记录
  //    要监测多个事件时, 只需要将多个事件做位运算加在一起调用 epoll_ctl 即可
  //
  // EPOLLONESHOT 是令 epoll 支持线程池的关键
  //    该参数可以令事件触发后就立即被禁用, 避免让同一个Socket的同一个事件
  //    同时被多个工作线程触发, 由于 epoll 中每个 socket 只有一条记录, 所以
  //    一定要注意带上 EPOLLONESHOT 参数的 epoll_ctl, 在 epoll_wait 之后一定要再次
  //    调用 epoll_ctl 增加要监视的事件
  //
  // EPOLL 发送数据
  //    最好的做法是将实际发送数据的动作放到 EPOLLOUT 触发时进行, 该
  //    事件触发表明 Socket 发送缓存有空闲空间了。IOCP 可以直接将待发送的数据及
  //    回调同时扔给 WSASend, 发送完成后去调用回调即可; EPOLL 机制不一样, 在 EPOLL
  //    中没有类似 WSASend 的函数, 只能自行维护发送数据及回调的队列
  //    EPOLL要支持多线程并发发送数据必须创建发送队列, 否则同一个 Socket 的并发发送
  //    极有可能有一部分会被其它发送覆盖掉
  //
  // 由于 EPOLL 中每个套接字在队列中只有一条记录, 也就是说改写套接字的监视事件时
  // 后一次修改会修改之前的, 这就很难使用接口的引用计数机制来保持连接有效性了
  // 这里使用连接UID作为 epoll_ctl 的参数, 在事件触发时通过UID查找连接对象, 这样
  // 同样可以保证事件触发时访问到有效的连接对象, 而且不需要引用计数保证
  TEpollCrossSocket = class(TCrossSocketBase)
  private const
    MAX_EVENT_COUNT = 2048;
    SHUTDOWN_FLAG   = UInt64(-1);
  private class threadvar
    FEventList: array [0..MAX_EVENT_COUNT-1] of TEPoll_Event;
  private
    FEpollHandle: Integer;
    FIoThreads: TArray<TIoEventThread>;
    FIdleHandle, FStopHandle: Integer;
    FIdleLock: ILock;

    // 利用 eventfd 唤醒并退出IO线程
    procedure _OpenStopHandle;
    procedure _PostStopCommand;
    procedure _CloseStopHandle;

    procedure _OpenIdleHandle;
    procedure _CloseIdleHandle;

    procedure _HandleAccept(const AListen: ICrossListen);
    procedure _HandleConnect(const AConnection: ICrossConnection);
    procedure _HandleRead(const AConnection: ICrossConnection);
    procedure _HandleWrite(const AConnection: ICrossConnection);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    function CreateListen(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil); override;

    function _ConnectAddr(const AOp: IInterface;
      const AAddr: TCrossConnectAddr): Boolean; override;

    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;

    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(const AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

implementation

{ create a file descriptor for event notification }
{$IFDEF DELPHI}
function eventfd(initval: Cardinal; flags: Integer): Integer; cdecl;
  external libc name 'eventfd';
{$ELSE}
function eventfd(initval: Cardinal; flags: Integer): Integer;
begin
  Result := do_syscall(syscall_nr_eventfd2, TSysParam(initval), TSysParam(flags));
end;
{$ENDIF}

{ TEpollListen }

constructor TEpollListen.Create(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer);
begin
  inherited;

  FOpCode := EPOLL_CTL_ADD;
  FEpollHandle := TEpollCrossSocket(Owner).FEpollHandle;
end;

function TEpollListen._UpdateIoEvent(const AIoEvents: TIoEvents; out AError: Integer): Boolean;
var
  LEvent: TEPoll_Event;
begin
  AError := 0;
  if (AIoEvents = []) or IsClosed
    or not TEpollCrossSocket(Owner)._CanListen(Generation) then Exit(False);
  LEvent.Events := EPOLLET or EPOLLONESHOT;
  LEvent.Data.u64 := Self.UID;
  if ieRead in AIoEvents then LEvent.Events := LEvent.Events or EPOLLIN;
  Result := epoll_ctl(FEpollHandle, FOpCode, Socket, @LEvent) >= 0;
  if Result then FOpCode := EPOLL_CTL_MOD
  else AError := GetLastError;
end;

{ TSendQueue }

procedure TSendQueue.Notify(const Value: PSendItem;
  Action: TCollectionNotification);
begin
  if (Action = TCollectionNotification.cnRemoved) then
  begin
    if (Value <> nil) then
    begin
      Value.Callback := nil;
      System.Dispose(Value);
    end;
  end;

  inherited;
end;

{ TEpollConnection }

constructor TEpollConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);

  FEpLock := TLock.Create;
  FSendQueue := TSendQueue.Create;

  FEpollHandle := TEpollCrossSocket(Owner).FEpollHandle;
  FOpCode := EPOLL_CTL_ADD;
end;

destructor TEpollConnection.Destroy;
begin
  _ClearSendQueue;

  FreeAndNil(FSendQueue);

  inherited;
end;

procedure TEpollConnection.InternalClose;
begin
  _ClearSendQueue;

  _EpLock;
  try
    epoll_ctl(FEpollHandle, EPOLL_CTL_DEL, Socket, nil);
  finally
    _EpUnlock;
  end;

  inherited InternalClose;
end;

procedure TEpollConnection._ClearSendQueue;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
  LCallbacks: TArray<TCrossConnectionCallback>;
  LCallback: TCrossConnectionCallback;
  LCount, LIndex: NativeInt;
begin
  LConnection := Self;
  LCallbacks := [];

  _EpLock;
  try
    // 连接释放时, 先收集所有回调, 然后在锁外执行
    // 避免回调中再次发送数据导致死锁
    if (FSendQueue.Count > 0) then
    begin
      LCount := 0;
      for LSendItem in FSendQueue do
        if Assigned(LSendItem.Callback) then Inc(LCount);
      SetLength(LCallbacks, LCount);
      LIndex := 0;
      for LSendItem in FSendQueue do
        if Assigned(LSendItem.Callback) then
        begin
          LCallbacks[LIndex] := LSendItem.Callback;
          Inc(LIndex);
        end;

      FSendQueue.Clear;
    end;
  finally
    _EpUnlock;
  end;

  // 在锁外执行回调, 告知发送失败
  for LCallback in LCallbacks do
    _CallConnectionCallback(LCallback, LConnection, False);
end;

procedure TEpollConnection._EpLock;
begin
  FEpLock.Enter;
end;

procedure TEpollConnection._EpUnlock;
begin
  FEpLock.Leave;
end;

function TEpollConnection._UpdateIoEvent(const AIoEvents: TIoEvents;
  out ACloseRequired: Boolean): Boolean;
var
  LEvent: TEPoll_Event;
begin
  ACloseRequired := False;
  if (AIoEvents = []) or IsClosed then Exit(False);

  LEvent.Events := 0;

  if (ieRead in AIoEvents) and (AtomicCmpExchange(FInPending, 0, 0) = 0) then
    LEvent.Events := LEvent.Events or EPOLLIN;

  if (ieWrite in AIoEvents) and (AtomicCmpExchange(FOutPending, 0, 0) = 0) then
    LEvent.Events := LEvent.Events or EPOLLOUT;

  if (LEvent.Events = 0) then Exit(False);

  LEvent.Events := LEvent.Events or EPOLLET or EPOLLONESHOT or EPOLLERR or EPOLLHUP;
  LEvent.Data.u64 := Self.UID;

  Result := (epoll_ctl(FEpollHandle, FOpCode, Socket, @LEvent) >= 0);
  FOpCode := EPOLL_CTL_MOD;

  if not Result then
  begin
    ACloseRequired := True;
    _LogLastOsError('connection epoll_ctl, %s, events=0x%.8x',
      [Self.DebugInfo, LEvent.Events]);
  end;
end;

{ TEpollCrossSocket }

constructor TEpollCrossSocket.Create(const AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TLock.Create;
end;

destructor TEpollCrossSocket.Destroy;
begin
  inherited;
end;

procedure TEpollCrossSocket._CloseIdleHandle;
begin
  FileClose(FIdleHandle);
end;

procedure TEpollCrossSocket._CloseStopHandle;
begin
  FileClose(FStopHandle);
end;

procedure TEpollCrossSocket._HandleAccept(const AListen: ICrossListen);
var
  LListen: TEpollListen;
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LError: Integer;
  LSocket: TSocket;
  LCloseRequired: Boolean;
begin
  LListen := AListen as TEpollListen;
  while True do
  begin
    LListen._Lock;
    try
      if AListen.IsClosed or not _CanListen(LListen.Generation) then Exit;
      LSocket := TSocketAPI.Accept(AListen.Socket, nil, nil);
      LError := 0;
      if LSocket < 0 then
      begin
        LError := GetLastError;
        if LError = EMFILE then
        begin
          FIdleLock.Enter;
          try
            _CloseIdleHandle;
            LSocket := TSocketAPI.Accept(AListen.Socket, nil, nil);
            if LSocket >= 0 then TSocketAPI.CloseSocket(LSocket);
            _OpenIdleHandle;
          finally FIdleLock.Leave; end;
          LSocket := INVALID_SOCKET;
        end;
      end;
    finally LListen._Unlock; end;
    if LSocket < 0 then
    begin
      if (LError <> EAGAIN) and (LError <> EWOULDBLOCK) and (LError <> EMFILE) then
        _Log('Accept error %d: %s', [LError, SysErrorMessage(LError)]);
      Break;
    end;
    if not _CanListen(LListen.Generation) then
    begin
      TSocketAPI.CloseSocket(LSocket);
      Break;
    end;
    // 工厂、配置扩展和用户事件在监听锁外执行。
    TSocketAPI.SetNonBlock(LSocket, True);
    SetKeepAlive(LSocket);
    LConnection := CreateConnection(Self, LSocket, ctAccept, '');
    try
      TriggerConnecting(LConnection);
      if LConnection.IsClosed then Continue;
      TriggerConnected(LConnection);
      LEpConnection := LConnection as TEpollConnection;
      LEpConnection._EpLock;
      try LEpConnection._UpdateIoEvent([ieRead], LCloseRequired);
      finally LEpConnection._EpUnlock; end;
      if LCloseRequired then _CloseCrossData(LConnection);
    except
      on E: Exception do
      begin
        _LogException('_HandleAccept', E);
        _CloseCrossData(LConnection);
      end;
    end;
  end;
end;

procedure TEpollCrossSocket._HandleConnect(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LSockErr: Integer;
begin
  LConnection := AConnection;

  // Connect失败
  LSockErr := TSocketAPI.GetError(LConnection.Socket);
  if (LSockErr <> 0) then
  begin
    LConnection.LastNetError := LSockErr;
    _LogLastOsError(Self.ClassName + '._HandleConnect.GetError');
    _ConnectAttemptFailed(LConnection);
    Exit;
  end;

  TriggerConnected(LConnection);
end;

procedure TEpollCrossSocket._HandleRead(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LRcvd, LError: Integer;
begin
  LConnection := AConnection;
  LEpConnection := LConnection as TEpollConnection;

  AtomicIncrement(LEpConnection.FInPending);
  try
    while True do
    begin
      LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

      // 对方主动断开连接
      if (LRcvd = 0) then
      begin
        _Log('Recv=0(Close), %s', [LConnection.DebugInfo]);
        LConnection.Close;
        Break;
      end;

      if (LRcvd < 0) then
      begin
        LError := GetLastError;

        // 被系统信号中断, 可以重新recv
        if (LError = EINTR) then
        begin
          _LogLastOsError('Recv=EINTR, %s', [LConnection.DebugInfo]);
          Continue
        end else
        // 接收缓冲区中数据已经被取完了
        if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
          Break
        else
        // 接收出错
        begin
          _LogLastOsError('Recv<0, %s', [LConnection.DebugInfo]);
          LConnection.Close;
          Break;
        end;
      end;

      TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

      // 回调中可能关闭了连接, 需要检查状态
      if LConnection.IsClosed then Break;

      if (LRcvd < RCV_BUF_SIZE) then Break;
    end;
  finally
    AtomicDecrement(LEpConnection.FInPending);
  end;
end;

procedure TEpollCrossSocket._HandleWrite(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LSendItem: PSendItem;
  LSent, LError: Integer;
  LSendCbArr: TArray<TCrossConnectionCallback>;
  LSendCb: TCrossConnectionCallback;
  LCallbackCount, I: NativeInt;
  LSendFailed, LCallbackFailed: Boolean;
begin
  LConnection := AConnection;
  LEpConnection := LConnection as TEpollConnection;
  LSendCbArr := [];
  LCallbackCount := 0;
  LSendFailed := False;
  LCallbackFailed := False;

  AtomicIncrement(LEpConnection.FOutPending);
  LEpConnection._EpLock;
  try
    while True do
    begin
      // 检查队列中有没有数据
      if (LEpConnection.FSendQueue.Count <= 0) then Break;

      // 获取Socket发送队列中的第一条数据
      LSendItem := LEpConnection.FSendQueue.Peek;

      // 发送数据
      LSent := TSocketAPI.Send(LConnection.Socket, LSendItem.Data^, LSendItem.Size, MSG_NOSIGNAL);

      // 对方主动断开连接
      if (LSent = 0) then
      begin
        _Log('Send=0(Close), %s', [LConnection.DebugInfo]);
        LSendFailed := True;
        Break;
      end;

      // 连接断开或发送错误
      if (LSent < 0) then
      begin
        LError := GetLastError;

        // 被系统信号中断, 可以重新send
        if (LError = EINTR) then
        begin
          _LogLastOsError('Send=EINTR, %s', [LConnection.DebugInfo]);
          Continue;
        end else
        // 发送缓冲区已被填满了, 需要等下次唤醒发送线程再继续发送
        if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
          Break
        // 发送出错
        else
        begin
          _LogLastOsError('Send<0, %s', [LConnection.DebugInfo]);
          LSendFailed := True;
          Break;
        end;
      end;

      // 全部发送完成
      if (LSent >= LSendItem.Size) then
      begin
        // 首次有完整发送才分配，零完成的 EAGAIN 不产生回调数组。
        if LCallbackCount = 0 then
          SetLength(LSendCbArr, LEpConnection.FSendQueue.Count);
        LSendCbArr[LCallbackCount] := LSendItem.Callback;
        Inc(LCallbackCount);

        // 发送成功, 移除已发送成功的数据
        // 必须先从队列移除已发完的数据项, 然后再执行发送成功的回调
        // 因为回调里可能还会发送新的数据, 如果先执行回调再去移除,
        // 就会错误的将回调中放到队列里的新数据移除
        // Dequeue 的 cnRemoved 通知释放发送项；回调已由上面的数组保活。
        // 此后不能再访问 LSendItem 或使用 Dequeue 返回的指针。
        LEpConnection.FSendQueue.Dequeue;
      end else
      begin
        // 部分发送成功, 在下一次唤醒发送线程时继续处理剩余部分
        Dec(LSendItem.Size, LSent);
        Inc(LSendItem.Data, LSent);
      end;
    end;
  finally
    LEpConnection._EpUnlock;
    AtomicDecrement(LEpConnection.FOutPending);
  end;

  // 关闭和回调均在发送队列锁外，单个回调异常不能跳过其余通知。
  if LSendFailed then _CloseCrossData(LConnection);
  for I := 0 to LCallbackCount - 1 do
  begin
    LSendCb := LSendCbArr[I];
    if not _CallConnectionCallback(LSendCb, LConnection, True) then
      LCallbackFailed := True;
  end;
  if LCallbackFailed then _CloseCrossData(LConnection);
end;

procedure TEpollCrossSocket._OpenIdleHandle;
begin
  FIdleHandle := FileOpen('/dev/null', fmOpenRead);
end;

procedure TEpollCrossSocket._OpenStopHandle;
var
  LEvent: TEPoll_Event;
begin
  FStopHandle := eventfd(0, 0);
  // 这里不使用 EPOLLET
  // 这样可以保证通知退出的命令发出后, 所有IO线程都会收到
  LEvent.Events := EPOLLIN;
  LEvent.Data.u64 := SHUTDOWN_FLAG;
  epoll_ctl(FEpollHandle, EPOLL_CTL_ADD, FStopHandle, @LEvent);
end;

procedure TEpollCrossSocket._PostStopCommand;
var
  LStuff: UInt64;
begin
  LStuff := 1;
  // 往 FStopHandle 写入任意数据, 唤醒工作线程
  FileWrite(FStopHandle, LStuff, SizeOf(LStuff));
end;

procedure TEpollCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  _OpenIdleHandle;

  // epoll_create(size)
  // 这个 size 只要传递大于0的任何值都可以
  // 并不是说队列的大小会受限于该值
  // http://man7.org/linux/man-pages/man2/epoll_create.2.html
  FEpollHandle := epoll_create(MAX_EVENT_COUNT);
  _OpenStopHandle;
  _StartListening;
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[I] := TIoEventThread.Create(Self);
end;

procedure TEpollCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
    if FIoThreads[I].ThreadID = LCurrentThreadID then
      raise ECrossSocket.Create('不能在IO线程中执行StopLoop!');
  _StopListening;
  CloseAll;

  while (FListensCount > 0) or (FConnectionsCount > 0) do Sleep(1);

  _PostStopCommand;

  for I := 0 to Length(FIoThreads) - 1 do
  begin
    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  FileClose(FEpollHandle);
  _CloseIdleHandle;
  _CloseStopHandle;
end;

function TEpollCrossSocket._ConnectAddr(const AOp: IInterface;
  const AAddr: TCrossConnectAddr): Boolean;
var
  LState: TCrossConnectOp;
  LSocket, LClientSocket: TSocket;
  LError: Integer;
  LSockAddr: TRawSockAddrIn;
  LConnection: ICrossConnection;
  LConnectCb: TCrossConnectionCallback;
  LEpConnection: TEpollConnection;
  LRetryOp: IInterface;
  LSuccess, LCloseRequired: Boolean;
begin
  LState := AOp as TCrossConnectOp;
  LSocket := TSocketAPI.NewSocket(AAddr.Family, AAddr.SockType, AAddr.Protocol);
  if (LSocket = INVALID_SOCKET) then
  begin
    LError := GetLastError;
    _LogLastOsError('TEpollCrossSocket._ConnectAddr.NewSocket');
    // 地址族不受支持仍可尝试另一地址；资源不足等全局错误直接结束。
    {$IFDEF DELPHI}
    if (LError = EAFNOSUPPORT) or (LError = EPROTONOSUPPORT) then Exit(False);
    {$ELSE}
    if (LError = ESysEAFNOSUPPORT) or (LError = ESysEPROTONOSUPPORT) then Exit(False);
    {$ENDIF}
    LState.Complete(nil, False);
    Exit(True);
  end;

  try
    TSocketAPI.SetNonBlock(LSocket, True);
    SetKeepAlive(LSocket);

    FillChar(LSockAddr, SizeOf(LSockAddr), 0);
    LSockAddr.AddrLen := AAddr.Addr.AddrLen;
    if (AAddr.Family = AF_INET6) then
    begin
      LSockAddr.Addr6.sin6_family := AAddr.Family;
      LSockAddr.Addr6.sin6_port := htons(LState.LocalPort);
    end else
    begin
      LSockAddr.Addr.sin_family := AAddr.Family;
      LSockAddr.Addr.sin_port := htons(LState.LocalPort);
    end;
    if (TSocketAPI.Bind(LSocket, @LSockAddr.Addr, LSockAddr.AddrLen) < 0) then
    begin
      _LogLastOsError('TEpollCrossSocket._ConnectAddr.Bind');
      Exit(False);
    end;

    if (TSocketAPI.Connect(LSocket, @AAddr.Addr.Addr, AAddr.Addr.AddrLen) <> 0)
      and (GetLastError <> EINPROGRESS) then
    begin
      _LogLastOsError('TEpollCrossSocket._ConnectAddr.Connect');
      Exit(False);
    end;

    LConnectCb := LState.CreateCallback();
    LClientSocket := LSocket;
    LSocket := INVALID_SOCKET;
    LConnection := CreateConnection(Self, LClientSocket, ctConnect,
      LState.Host, LConnectCb);
    try
      LEpConnection := LConnection as TEpollConnection;
      LEpConnection._SetConnectOp(AOp);
      PrepareConnection(LConnection, LState.Host, LState.LogicalPort);
      TriggerConnecting(LConnection);
      // 用户关闭或 CloseAllConnections 已终止整次操作，不再回退。
      if LConnection.IsClosed then Exit(True);
      {$IFDEF CROSS_CAPACITY_TESTS}
      if Assigned(CrossConnectBeforeRegisterForTest) then
        CrossConnectBeforeRegisterForTest(LConnection);
      {$ENDIF}

      LEpConnection._EpLock;
      try
        LSuccess := LEpConnection._UpdateIoEvent([ieWrite], LCloseRequired);
      finally
        LEpConnection._EpUnlock;
      end;
      // 先独占失败清理，锁外关闭旧尝试；只有清理获胜者才能继续下一地址。
      if not LSuccess then
        Exit(not LEpConnection._CloseRetryingConnect(LRetryOp));
      Result := True;
    except
      on E: Exception do
      begin
        _CloseCrossData(LConnection);
        raise;
      end;
    end;
  finally
    if (LSocket <> INVALID_SOCKET) then TSocketAPI.CloseSocket(LSocket);
  end;
end;

function TEpollCrossSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TEpollConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

function TEpollCrossSocket.CreateListen(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TEpollListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TEpollCrossSocket.Listen(const AHost: string; const APort: Word;
  const ACallback: TCrossListenCallback);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: TSocket;
  LListen: ICrossListen;
  LEpListen: TEpollListen;
  LListenSuccess, LUpdateIoEventSuccess: Boolean;
  LGeneration, LError: Integer;

  procedure _Failed;
  begin
    try
      if not LListenSuccess and Assigned(ACallback) then
        ACallback(LListen, False);
    finally
      if (LListen <> nil) then
        LListen.Close
      else if (LListenSocket <> INVALID_SOCKET) then
      begin
        TSocketAPI.CloseSocket(LListenSocket);
        LListenSocket := INVALID_SOCKET;
      end;
    end;
  end;

begin
  LListenSocket := INVALID_SOCKET;
  LListenSuccess := False;
  LGeneration := _GetListenGeneration;
  if not _CanListen(LGeneration) then
  begin
    _Failed;
    Exit;
  end;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TEpollCrossSocket.Listen.GetAddrInfo');
    {$ENDIF}
    _Failed;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      if not _CanListen(LGeneration) then
      begin
        if not LListenSuccess then _Failed;
        Break;
      end;
      LListen := nil;
      LListenSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol);
      if (LListenSocket = INVALID_SOCKET) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TEpollCrossSocket.Listen.NewSocket');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LListenSocket, True);
      TSocketAPI.SetReUsePort(LListenSocket, True);

      if (LAddrInfo.ai_family = AF_INET6) then
        TSocketAPI.SetSockOpt<Integer>(LListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, 1);

      if (TSocketAPI.Bind(LListenSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0)
        or (TSocketAPI.Listen(LListenSocket) < 0) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TEpollCrossSocket.Listen.Bind');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);
      LEpListen := LListen as TEpollListen;

      try
        if not _RegisterListen(LListen, LGeneration) then
        begin
          _Failed;
          Exit;
        end;
        LEpListen._Lock;
        try LUpdateIoEventSuccess := LEpListen._UpdateIoEvent([ieRead], LError);
        finally LEpListen._Unlock; end;
        if not LUpdateIoEventSuccess then
        begin
          try
            if LError <> 0 then _Log('Listen epoll_ctl error %d: %s', [LError, SysErrorMessage(LError)]);
          finally _Failed; end;
          Exit;
        end;
        TriggerListened(LListen);
        if not LEpListen._IsPublished then
        begin
          _Failed;
          Exit;
        end;
        LListenSuccess := True;
        if Assigned(ACallback) then ACallback(LListen, True);
      except
        _CloseCrossData(LListen);
        raise;
      end;

      // 如果端口传入0，让所有地址统一用首个分配到的端口
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        Psockaddr_in(LAddrInfo.ai_next.ai_addr).sin_port := htons(LListen.LocalPort);

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;
end;

procedure TEpollCrossSocket.Send(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LConnection: TEpollConnection;
  LSendItem: PSendItem;
  LPrepared: TCrossConnectionCallback;
  LCloseRequired, LQueued: Boolean;
begin
  if not _PrepareSend(AConnection, ABuf, ALen, ACallback, LPrepared) then Exit;
  LSendItem := nil;
  LQueued := False;
  LCloseRequired := False;
  try
    try
      System.New(LSendItem);
      FillChar(LSendItem^, SizeOf(TSendItem), 0);
      LSendItem.Data := ABuf;
      LSendItem.Size := ALen;
      if Assigned(LPrepared) then LSendItem.Callback := LPrepared
      else LSendItem.Callback := ACallback;
      LConnection := AConnection as TEpollConnection;
      LConnection._EpLock;
      try
        // 与关闭清空队列共用锁，拒绝已关闭连接的迟到入队。
        if not (LConnection.ConnectStatus in [csDisconnected, csClosed]) then
        begin
          LConnection.FSendQueue.Enqueue(LSendItem);
          LQueued := True;
          LConnection._UpdateIoEvent([ieRead, ieWrite], LCloseRequired);
        end;
      finally
        LConnection._EpUnlock;
      end;
    except
      on E: Exception do
      begin
        LCloseRequired := True;
        _LogException('Epoll send submission failed', E);
      end;
    end;
  finally
    if not LQueued and (LSendItem <> nil) then System.Dispose(LSendItem);
  end;
  if not LQueued then
  begin
    if Assigned(LPrepared) then _CallConnectionCallback(LPrepared, AConnection, False)
    else _CallConnectionCallback(ACallback, AConnection, False);
  end;
  // 已入队项由关闭清理逐项通知；未入队项已在上面锁外结算。
  if LCloseRequired then _CloseCrossData(AConnection);
end;

function TEpollCrossSocket.ProcessIoEvent: Boolean;
var
  LRet, I: Integer;
  LEvent: TEPoll_Event;
  LCrossUID: UInt64;
  LCrossTag: Byte;
  LListens: TCrossListens;
  LConnections: TCrossConnections;
  LListen: ICrossListen;
  LEpListen: TEpollListen;
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LCloseRequired, LRearmed: Boolean;
  LListenError: Integer;
  LIoEvents: TIoEvents;
begin
  // 被系统信号打断或者出错会返回-1, 具体需要根据错误代码判断
  LRet := epoll_wait(FEpollHandle, @FEventList[0], MAX_EVENT_COUNT, -1);
  if (LRet < 0) then
  begin
    _LogLastOsError('epoll_wait');
    LRet := GetLastError;
    // EINTR, epoll_wait 调用被系统信号打断, 可以进行重试
    Exit(LRet = EINTR);
  end;

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];

    // 收到退出命令
    if (LEvent.Data.u64 = SHUTDOWN_FLAG) then Exit(False);

    {$region '获取连接或监听对象'}
    LCrossUID := LEvent.Data.u64;
    LCrossTag := GetTagByUID(LCrossUID);
    LListen := nil;
    LConnection := nil;

    {$IFDEF DEBUG}
//    _Log('epoll events %.8x, uid %.16x, tag %d', [LEvent.Events, LEvent.Data.u64, LCrossTag]);
    {$ENDIF}
    case LCrossTag of
      UID_LISTEN:
        begin
          LListens := LockListens;
          try
            if not LListens.TryGetValue(LCrossUID, LListen)
              or (LListen = nil) then
              Continue;
          finally
            UnlockListens;
          end;
        end;

      UID_CONNECTION:
        begin
          LConnections := LockConnections;
          try
            if not LConnections.TryGetValue(LCrossUID, LConnection)
              or (LConnection = nil) then
              Continue;
          finally
            UnlockConnections;
          end;
        end;
    else
      Continue;
    end;
    {$endregion}

    {$region 'IO事件处理'}
    try
      if (LListen <> nil) then
      begin
        try
          if (LEvent.Events and EPOLLIN <> 0) then
            _HandleAccept(LListen);
        finally
          // 单个接入回调失败后仍恢复监听。
          LEpListen := LListen as TEpollListen;
          LEpListen._Lock;
          try
            LRearmed := LEpListen._UpdateIoEvent([ieRead], LListenError);
          finally
            LEpListen._Unlock;
          end;
          if not LRearmed then
          begin
            try
              if LListenError <> 0 then
                _Log('Listen rearm error %d: %s', [LListenError, SysErrorMessage(LListenError)]);
            finally _CloseCrossData(LListen); end;
          end;
        end;
      end else
      if (LConnection <> nil) then
      begin
        // 连接被断开
        if (LEvent.Events and EPOLLERR <> 0)
          or (LEvent.Events and EPOLLHUP <> 0) then
        begin
          _Log('epoll_wait, %s, EPOLLERR=%d, EPOLLHUP=%d', [
            LConnection.DebugInfo,
            LEvent.Events and EPOLLERR,
            LEvent.Events and EPOLLHUP
          ]);
          if (LConnection.ConnectStatus = csConnecting) then
          begin
            LConnection.LastNetError := TSocketAPI.GetError(LConnection.Socket);
            _ConnectAttemptFailed(LConnection);
            Continue;
          end;
          // EPOLLHUP does not discard data that is already buffered: read it
          // first (EPOLLIN in the same event), otherwise the final bytes
          // the peer sent before closing are lost.
          if (LEvent.Events and EPOLLIN <> 0) then
            _HandleRead(LConnection);
          LConnection.Close;
          Continue;
        end;

        // epoll的读写事件同一时间可能两个同时触发
        if (LEvent.Events and EPOLLIN <> 0) then
          _HandleRead(LConnection);

        if (LEvent.Events and EPOLLOUT <> 0) then
        begin
          if (LConnection.ConnectStatus = csConnecting) then
            _HandleConnect(LConnection)
          else
            _HandleWrite(LConnection);
        end;

        // 把更新连接的IO事件放到这里统一处理
        // 当读写同时触发的情况, 可以节省一次IO事件更新
        if not LConnection.IsClosed then
        begin
          LEpConnection := LConnection as TEpollConnection;
          LEpConnection._EpLock;
          try
            if (LEpConnection.FSendQueue.Count > 0) then
              LIoEvents := [ieRead, ieWrite]
            else
              LIoEvents := [ieRead];
            LEpConnection._UpdateIoEvent(LIoEvents, LCloseRequired);
          finally
            LEpConnection._EpUnlock;
          end;
          if LCloseRequired then _CloseCrossData(LConnection);
        end;
      end;
    except
      on E: Exception do
      begin
        _LogException('ProcessIoEvent', E);
        _CloseCrossData(LConnection);
      end;
    end;
    {$endregion}
  end;

  Result := True;
end;

end.
