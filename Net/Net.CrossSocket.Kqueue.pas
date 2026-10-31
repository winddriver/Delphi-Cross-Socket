{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Kqueue;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,

  {$IFDEF DELPHI}
  Posix.SysSocket,
  Posix.NetinetIn,
  Posix.UniStd,
  Posix.NetDB,
  Posix.Pthread,
  Posix.ArpaInet,
  Posix.Errno,
  {$ELSE}
  baseunix,
  unix,
  sockets,
  netdb,
  DTF.RTL,
  {$ENDIF}

  BSD.kqueue,

  Net.SocketAPI,
  Net.CrossSocket.Base,

  Utils.SyncObjs,
  Utils.ArrayUtils;

{$IFDEF BSD}
const
	IPV6_V6ONLY = 27;
{$ENDIF}

type
  {$IFDEF FPC}
  TPipeDescriptors = {packed} record
    ReadDes: Integer;
    WriteDes: Integer;
  end;
  PPipeDescriptors = ^TPipeDescriptors;
  {$ENDIF}

  TIoEvent = (ieRead, ieWrite);
  TIoEvents = set of TIoEvent;

  TKqueueListen = class(TCrossListenBase)
  private
    FKqueueHandle: Integer;
    FIoEvents: TIoEvents;
    FEventId: NativeUInt;
    FClosing: Integer;

    function _ReadEnabled: Boolean; inline;
    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
  protected
    function GetIsClosed: Boolean; override;
  public
    procedure Close; override;
    constructor Create(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer); override;
  end;

  PSendItem = ^TSendItem;
  TSendItem = packed record
    Data: PByte;
    Size: Integer;
    Callback: TCrossConnectionCallback;
  end;

  TSendQueue = class(TQueue<PSendItem>)
  protected
    procedure Notify(const Value: PSendItem; Action: TCollectionNotification); override;
  end;

  TKqueueConnection = class(TCrossConnectionBase)
  private
    FKqueueHandle: Integer;
    FSendQueue: TSendQueue;
    FKqLock: ILock;
    FInPending, FOutPending: Integer;
    FEventId: NativeUInt;

    function _UpdateIoEvent(const AIoEvents: TIoEvents; out ACloseRequired: Boolean): Boolean;

    procedure _ClearSendQueue;

    procedure _KqLock; inline;
    procedure _KqUnlock; inline;
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
  // EV_DISPATCH 和 EV_CLEAR 是令 kqueue 支持线程池的关键
  //    该参数组合可以令事件触发后就立即被禁用, 避免让同一个Socket的同一个事件
  //    同时被多个工作线程触发
  //
  // EVFILT_READ
  //    用于监测接收缓冲区是否可读了
  //    对于监听Socket来说,表示有新的连接到来
  //    对于已连接的Socket来说,表示有数据到达接收缓冲区
  //    为了支持线程池, 必须带上参数 EV_CLEAR or EV_DISPATCH
  //    该参数组合表示, 该事件一旦触发立即清除该事件的状态并禁用它
  //    处理完连接或者读取数据之后再投递一次 EVFILT_READ, 带上参数
  //    EV_ENABLE or EV_CLEAR or EV_DISPATCH, 让事件继续监测
  //
  // EVFILT_WRITE
  //    用于监测发送缓冲区是否可写了
  //    对于Connect中的Socket,投递EV_ENABLE,等到事件触发时表示连接已建立
  //    对于已连接的Socket,在Send之后立即投递EVFILT_WRITE,等到事件触发时表示发送完成
  //    对于EVFILT_WRITE都应该带上EV_ONESHOT参数,让该事件只会被触发一次
  //    否则,只要发送缓冲区是空的,该事件就会一直触发,这并没有什么意义
  //    我们只需要用EVFILT_WRITE去监测连接或者发送是否成功
  //
  // KQUEUE 发送数据
  //    最好的做法是将实际发送数据的动作放到 EVFILT_WRITE 触发时进行, 该
  //    事件触发表明 Socket 发送缓存有空闲空间了。IOCP可以直接将待发送的数据及
  //    回调同时扔给 WSASend, 发送完成后去调用回调即可; KQUEUE 机制不一样, 在 KQUEUE
  //    中没有类似 WSASend 的函数, 只能自行维护发送数据及回调的队列
  //    EPOLL要支持多线程并发发送数据必须创建发送队列, 否则同一个 Socket 的并发发送
  //    极有可能有一部分会被其它发送覆盖掉
  //
  // 同一套接字的读写过滤器分别注册；重复 EV_ADD 会更新原有过滤器。
  // udata 只携带不复用的编号，对象由注册表和派发时取得的接口保活。
  TKqueueCrossSocket = class(TCrossSocketBase)
  private const
    MAX_EVENT_COUNT = 2048;
    SHUTDOWN_FLAG   = Pointer(-1);
  private class threadvar
    FEventList: array [0..MAX_EVENT_COUNT-1] of TKEvent;
  private
    FKqueueHandle: Integer;
    FIoThreads: TArray<TIoEventThread>;
    FIdleHandle: THandle;
    FIdleLock: ILock;
    FStopHandle: TPipeDescriptors;
    FRegisteredData: TDictionary<NativeUInt, ICrossData>;
    FRegisteredLock: ILock;
    FLastEventId: NativeUInt;
    FStopping: Boolean;

    function _RegisterData(const AData: ICrossData; var AId: NativeUInt): Boolean;
    procedure _UnregisterData(var AId: NativeUInt);
    function _FindRegisteredData(const AId: NativeUInt): ICrossData;
    procedure _CloseRegisteredData;
    function _RegisteredCount: Integer;

    // 利用 pipe 唤醒并退出IO线程
    procedure _OpenStopHandle; inline;
    procedure _PostStopCommand; inline;
    procedure _CloseStopHandle; inline;

    procedure _OpenIdleHandle; inline;
    procedure _CloseIdleHandle; inline;

    // 在向一个已经关闭的套接字发送数据时系统会直接抛出EPIPE异常导致程序非正常退出
    // LINUX下可以在send时带上MSG_NOSIGNAL参数就能避免这种情况的发生
    // OSX中可以通过设置套接字的SO_NOSIGPIPE参数达到同样的目的
    procedure _SetNoSigPipe(ASocket: TSocket); inline;

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

    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil); override;

    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(const AIoThreads: Integer); override;
    destructor Destroy; override;
    {$IFDEF CROSS_KQUEUE_TESTS}
    function GetRegisteredCountForTest: Integer;
    {$ENDIF}
  end;

{$IFDEF CROSS_KQUEUE_TESTS}
type
  TCrossKqueueEventsReadyForTest = reference to procedure(
    const AEvents: PKEvent; const ACount: Integer);
var
  CrossKqueueEventsReadyForTest: TCrossKqueueEventsReadyForTest;
{$ENDIF}

implementation

{$IFDEF FPC}
function pipe(var PipeDes: TPipeDescriptors): Integer; cdecl; external 'c' name 'pipe';
function __read(Handle: Integer; Buffer: Pointer; Count: size_t): ssize_t; cdecl; external 'c' name 'read';
function __write(Handle: Integer; Buffer: Pointer; Count: size_t): ssize_t; cdecl; external 'c' name 'write';
function __close(Handle: Integer): Integer; cdecl; external 'c' name 'close';
{$ENDIF}

{ TKqueueListen }

constructor TKqueueListen.Create(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer);
begin
  inherited;
  FKqueueHandle := TKqueueCrossSocket(AOwner).FKqueueHandle;
end;

procedure TKqueueListen.Close;
var
  LSelf: ICrossListen;
begin
  LSelf := Self;
  try
    _Lock;
    try
      // 与 arm 共用锁；实际关闭和用户回调在解锁之后执行。
      AtomicExchange(FClosing, 1);
      TKqueueCrossSocket(Owner)._UnregisterData(FEventId);
    finally
      _Unlock;
    end;
  finally
    inherited Close;
  end;
end;

function TKqueueListen.GetIsClosed: Boolean;
begin
  if (AtomicCmpExchange(FClosing, 0, 0) <> 0) then Exit(True);
  Result := inherited GetIsClosed;
end;

function TKqueueListen._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

function TKqueueListen._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LEvent: TKEvent;
begin
  FIoEvents := AIoEvents;
  if not _ReadEnabled or IsClosed
    or not TKqueueCrossSocket(Owner)._CanListen(Generation) then Exit(False);

  try
    // 在提交之前入表，事件即使立即返回也能取得接口。
    if not TKqueueCrossSocket(Owner)._RegisterData(Self, FEventId) then
      Exit(False);
    EV_SET(@LEvent, Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(FEventId));
    Result := (kevent(FKqueueHandle, @LEvent, 1, nil, 0, nil) >= 0);
  except
    on E: Exception do
    begin
      _LogException('Listen event registration', E);
      Result := False;
    end;
  end;

  {$IFDEF DEBUG}
  if not Result then
    _LogLastOsError('listen kevent, %s', [Self.DebugInfo]);
  {$ENDIF}
end;

{ TSendQueue }

procedure TSendQueue.Notify(const Value: PSendItem;
  Action: TCollectionNotification);
begin
  inherited;

  if (Action = TCollectionNotification.cnRemoved) then
  begin
    if (Value <> nil) then
    begin
      Value.Callback := nil;
      System.Dispose(Value);
    end;
  end;
end;

{ TKqueueConnection }

constructor TKqueueConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);

  FKqLock := TLock.Create;
  FSendQueue := TSendQueue.Create;

  FKqueueHandle := TKqueueCrossSocket(AOwner).FKqueueHandle;
end;

destructor TKqueueConnection.Destroy;
begin
  _ClearSendQueue;
  FreeAndNil(FSendQueue);

  inherited;
end;

procedure TKqueueConnection.InternalClose;
var
  LEvent: TKEvent;
begin
  try
    _ClearSendQueue;
  finally
    try
      _KqLock;
      try
        // Close 已置关闭状态；撤销身份后，已返回的旧事件只会查找失败。
        TKqueueCrossSocket(Owner)._UnregisterData(FEventId);
        EV_SET(@LEvent, Socket, EVFILT_READ, EV_DELETE, 0, 0, nil);
        kevent(FKqueueHandle, @LEvent, 1, nil, 0, nil);
        EV_SET(@LEvent, Socket, EVFILT_WRITE, EV_DELETE, 0, 0, nil);
        kevent(FKqueueHandle, @LEvent, 1, nil, 0, nil);
      finally
        _KqUnlock;
      end;
    finally
      inherited InternalClose;
    end;
  end;
end;

procedure TKqueueConnection._ClearSendQueue;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
  LCallbacks: TArray<TCrossConnectionCallback>;
  LCallback: TCrossConnectionCallback;
  LCount, LIndex: NativeInt;
begin
  LConnection := Self;
  LCallbacks := [];

  _KqLock;
  try
    // 连接释放时, 先收集所有回调, 然后在锁外执行
    // 避免回调中再次发送数据导致死锁
    if (FSendQueue <> nil) and (FSendQueue.Count > 0) then
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
    _KqUnlock;
  end;

  // 在锁外执行回调, 告知发送失败
  for LCallback in LCallbacks do
    _CallConnectionCallback(LCallback, LConnection, False);
end;

procedure TKqueueConnection._KqLock;
begin
  FKqLock.Enter;
end;

procedure TKqueueConnection._KqUnlock;
begin
  FKqLock.Leave;
end;

function TKqueueConnection._UpdateIoEvent(const AIoEvents: TIoEvents;
  out ACloseRequired: Boolean): Boolean;
var
  LEvents: array [0..1] of TKEvent;
  N, I: Integer;
begin
  ACloseRequired := False;
  if (AIoEvents = []) or IsClosed then Exit(False);
  N := 0;

  if (ieRead in AIoEvents) and (AtomicCmpExchange(FInPending, 0, 0) = 0) then
  begin
    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, nil);
    Inc(N);
  end;

  if (ieWrite in AIoEvents) and (AtomicCmpExchange(FOutPending, 0, 0) = 0) then
  begin
    EV_SET(@LEvents[N], Socket, EVFILT_WRITE,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, nil);
    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  try
    Result := TKqueueCrossSocket(Owner)._RegisterData(Self, FEventId);
    if Result then
    begin
      for I := 0 to N - 1 do LEvents[I].uData := Pointer(FEventId);
      Result := (kevent(FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);
    end;
  except
    on E: Exception do
    begin
      _LogException('Connection event registration', E);
      Result := False;
    end;
  end;

  if not Result then
  begin
    // 调用方在队列锁外 Close；注册表的唯一引用由关闭路径收回。
    ACloseRequired := True;
    {$IFDEF DEBUG}
    _LogLastOsError('connection kevent, %s', [Self.DebugInfo]);
    {$ENDIF}
  end;
end;

{ TKqueueCrossSocket }

constructor TKqueueCrossSocket.Create(const AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TLock.Create;
  FRegisteredLock := TLock.Create;
  FRegisteredData := TDictionary<NativeUInt, ICrossData>.Create;
end;

destructor TKqueueCrossSocket.Destroy;
begin
  try
    _CloseRegisteredData;
  finally
    FreeAndNil(FRegisteredData);
    inherited;
  end;
end;

function TKqueueCrossSocket._RegisterData(const AData: ICrossData;
  var AId: NativeUInt): Boolean;
begin
  FRegisteredLock.Enter;
  try
    if FStopping or AData.IsClosed or (AData.Socket = INVALID_SOCKET) then Exit(False);
    if (AId <> 0) then Exit(True);
    // 0 表示未注册，最大值用于停止命令。编号耗尽后禁止回卷复用。
    if (FLastEventId >= High(NativeUInt) - 1) then Exit(False);
    Inc(FLastEventId);
    FRegisteredData.Add(FLastEventId, AData);
    AId := FLastEventId;
    Result := True;
  finally
    FRegisteredLock.Leave;
  end;
end;

procedure TKqueueCrossSocket._UnregisterData(var AId: NativeUInt);
var
  LData: ICrossData;
begin
  if (AId = 0) then Exit;
  FRegisteredLock.Enter;
  try
    // 本地接口保证 Remove 不会在表锁内触发对象析构。
    if FRegisteredData.TryGetValue(AId, LData) then
      FRegisteredData.Remove(AId);
    AId := 0;
  finally
    FRegisteredLock.Leave;
  end;
end;

function TKqueueCrossSocket._FindRegisteredData(const AId: NativeUInt): ICrossData;
begin
  Result := nil;
  FRegisteredLock.Enter;
  try
    FRegisteredData.TryGetValue(AId, Result);
  finally
    FRegisteredLock.Leave;
  end;
end;

procedure TKqueueCrossSocket._CloseRegisteredData;
var
  LSnapshot: TArray<ICrossData>;
  LData: ICrossData;
begin
  if (FRegisteredData = nil) then Exit;
  FRegisteredLock.Enter;
  try
    FStopping := True;
    LSnapshot := FRegisteredData.Values.ToArray;
  finally
    FRegisteredLock.Leave;
  end;
  // 包括首次 arm 后尚未进入 owner 列表的对象，逐项在锁外关闭。
  for LData in LSnapshot do _CloseCrossData(LData);
end;

function TKqueueCrossSocket._RegisteredCount: Integer;
begin
  FRegisteredLock.Enter;
  try
    Result := FRegisteredData.Count;
  finally
    FRegisteredLock.Leave;
  end;
end;

{$IFDEF CROSS_KQUEUE_TESTS}
function TKqueueCrossSocket.GetRegisteredCountForTest: Integer;
begin
  Result := _RegisteredCount;
end;
{$ENDIF}

procedure TKqueueCrossSocket._CloseIdleHandle;
begin
  FileClose(FIdleHandle);
end;

procedure TKqueueCrossSocket._CloseStopHandle;
begin
  FileClose(FStopHandle.ReadDes);
  FileClose(FStopHandle.WriteDes);
end;

procedure TKqueueCrossSocket._HandleAccept(const AListen: ICrossListen);
var
  LListen: ICrossListen;
  LKqListen: TKqueueListen;
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LError: Integer;
  LSocket, LListenSocket, LClientSocket: TSocket;
  LCloseRequired, LRearmed: Boolean;
begin
  LListen := AListen;
  LListenSocket := LListen.Socket;

  while True do
  begin
    if LListen.IsClosed then Exit;
    LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);

    // Accept失败
    // EAGAIN 所有就绪的连接都已处理完毕
    // EMFILE 进程的文件句柄已经用完了
    if (LSocket < 0) then
    begin
      LError := GetLastError;

      // 所有就绪的连接都已处理完毕, 正常情况
      if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
      begin
        // 空处理, 仅用于区分 EMFILE 和其他错误
      end else
      // 当句柄用完了的时候, 释放事先占用的临时句柄
      // 然后再次 accept, 然后将 accept 的句柄关掉
      // 这样可以保证在文件句柄耗尽的时候依然能响应连接请求
      // 并立即将新到的连接关闭
      if (LError = EMFILE) then
      begin
        FIdleLock.Enter;
        try
          _CloseIdleHandle;
          LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);
          TSocketAPI.CloseSocket(LSocket);
          _OpenIdleHandle;
        finally
          FIdleLock.Leave;
        end;
      end else
        _LogLastOsError('Accept');

      Break;
    end;

    LClientSocket := LSocket;
    TSocketAPI.SetNonBlock(LClientSocket, True);
    SetKeepAlive(LClientSocket);
    _SetNoSigPipe(LClientSocket);

    LConnection := CreateConnection(Self, LClientSocket, ctAccept, '');
    try
      TriggerConnecting(LConnection);
      TriggerConnected(LConnection);

      // 连接建立后监视Socket的读事件
      LKqConnection := LConnection as TKqueueConnection;
      LKqConnection._KqLock;
      try
        LKqConnection._UpdateIoEvent([ieRead], LCloseRequired);
      finally
        LKqConnection._KqUnlock;
      end;
      if LCloseRequired then _CloseCrossData(LConnection);
    except
      on E: Exception do
      begin
        _LogException('_HandleAccept', E);
        _CloseCrossData(LConnection);
      end;
    end;
  end;

  // 继续接收新连接
  LKqListen := LListen as TKqueueListen;
  LKqListen._Lock;
  try
    LRearmed := LKqListen._UpdateIoEvent([ieRead]);
  finally
    LKqListen._Unlock;
  end;
  if not LRearmed then _CloseCrossData(LListen);
end;

procedure TKqueueCrossSocket._HandleConnect(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSockErr: Integer;
  LCloseRequired: Boolean;
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

  LKqConnection := LConnection as TKqueueConnection;

  LKqConnection._KqLock;
  try
    LKqConnection._UpdateIoEvent([ieRead], LCloseRequired);
  finally
    LKqConnection._KqUnlock;
  end;
  if LCloseRequired then _CloseCrossData(LConnection);
end;

procedure TKqueueCrossSocket._HandleRead(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LRcvd, LError: Integer;
  LCloseRequired: Boolean;
begin
  LConnection := AConnection;
  LKqConnection := LConnection as TKqueueConnection;

  AtomicIncrement(LKqConnection.FInPending);
  try
    while True do
    begin
      LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

      // 对方主动断开连接
      if (LRcvd = 0) then
      begin
        _Log('Recv=0(Close), %s', [LConnection.DebugInfo]);
        LConnection.Close;
        Exit;
      end;

      if (LRcvd < 0) then
      begin
        LError := GetLastError;

        // 被系统信号中断, 可以重新recv
        if (LError = EINTR) then
          Continue
        // 接收缓冲区中数据已经被取完了
        else if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
          Break
        else
        // 接收出错
        begin
          _LogLastOsError('Recv<0, %s', [LConnection.DebugInfo]);
          LConnection.Close;
          Exit;
        end;
      end;

      TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

      // 回调中可能关闭了连接, 需要检查状态
      if LConnection.IsClosed then Exit;

      if (LRcvd < RCV_BUF_SIZE) then Break;
    end;
  finally
    AtomicDecrement(LKqConnection.FInPending);
  end;

  LKqConnection._KqLock;
  try
    LKqConnection._UpdateIoEvent([ieRead], LCloseRequired);
  finally
    LKqConnection._KqUnlock;
  end;
  if LCloseRequired then _CloseCrossData(LConnection);
end;

procedure TKqueueCrossSocket._HandleWrite(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
  LSent, LError: Integer;
  LSendCbArr: TArray<TCrossConnectionCallback>;
  LSendCb: TCrossConnectionCallback;
  LCallbackCount, I: NativeInt;
  LSendFailed, LCallbackFailed: Boolean;
  LCloseRequired: Boolean;
begin
  LConnection := AConnection;
  LKqConnection := LConnection as TKqueueConnection;
  LSendCbArr := [];
  LCallbackCount := 0;
  LSendFailed := False;
  LCallbackFailed := False;

  AtomicIncrement(LKqConnection.FOutPending);
  LKqConnection._KqLock;
  try
    while True do
    begin
      // 检查队列中有没有数据
      if (LKqConnection.FSendQueue = nil) or (LKqConnection.FSendQueue.Count <= 0) then Break;

      // 获取Socket发送队列中的第一条数据
      LSendItem := LKqConnection.FSendQueue.Peek;

      // 发送数据
      {$IFNDEF MACOS}
      LSent := TSocketAPI.Send(LConnection.Socket, LSendItem.Data^, LSendItem.Size, MSG_NOSIGNAL);
      {$ELSE}
      LSent := TSocketAPI.Send(LConnection.Socket, LSendItem.Data^, LSendItem.Size);
      {$ENDIF}

      // 对方主动断开连接
      if (LSent = 0) then
      begin
        _Log('Send=0(close), %s', [LConnection.DebugInfo]);

        LSendFailed := True;
        Break;
      end;

      // 连接断开或发送错误
      if (LSent < 0) then
      begin
        LError := GetLastError;

        // 被系统信号中断, 可以重新send
        if (LError = EINTR) then
          Continue
        // 发送缓冲区已被填满了, 需要等下次唤醒发送线程再继续发送
        else if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
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
          SetLength(LSendCbArr, LKqConnection.FSendQueue.Count);
        LSendCbArr[LCallbackCount] := LSendItem.Callback;
        Inc(LCallbackCount);

        // 发送成功, 移除已发送成功的数据
        // 必须先从队列移除已发完的数据项, 然后再执行发送成功的回调
        // 因为回调里可能还会发送新的数据, 如果先执行回调再去移除,
        // 就会错误的将回调中放到队列里的新数据移除
        // Dequeue 的 cnRemoved 通知释放发送项；回调已由上面的数组保活。
        // 此后不能再访问 LSendItem 或使用 Dequeue 返回的指针。
        LKqConnection.FSendQueue.Dequeue;
      end else
      begin
        // 部分发送成功, 在下一次唤醒发送线程时继续处理剩余部分
        Dec(LSendItem.Size, LSent);
        Inc(LSendItem.Data, LSent);
      end;
    end;
  finally
    LKqConnection._KqUnlock;
    AtomicDecrement(LKqConnection.FOutPending);
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

  LCloseRequired := False;
  LKqConnection._KqLock;
  try
    if (LKqConnection.FSendQueue <> nil) and (LKqConnection.FSendQueue.Count > 0) then
      LKqConnection._UpdateIoEvent([ieWrite], LCloseRequired);
  finally
    LKqConnection._KqUnlock;
  end;
  if LCloseRequired then _CloseCrossData(LConnection);
end;

procedure TKqueueCrossSocket._OpenIdleHandle;
begin
  FIdleHandle := FileOpen('/dev/null', fmOpenRead);
end;

procedure TKqueueCrossSocket._OpenStopHandle;
var
  LEvent: TKEvent;
begin
  pipe(FStopHandle);

  // 这里不使用 EV_ONESHOT
  // 这样可以保证通知退出的命令发出后, 所有IO线程都会收到
  EV_SET(@LEvent, FStopHandle.ReadDes, EVFILT_READ,
    EV_ADD, 0, 0, SHUTDOWN_FLAG);
  kevent(FKqueueHandle, @LEvent, 1, nil, 0, nil);
end;

procedure TKqueueCrossSocket._PostStopCommand;
var
  LStuff: UInt64;
begin
  LStuff := 1;
  // 往 FStopHandle.WriteDes 写入任意数据, 唤醒工作线程
  __write(FStopHandle.WriteDes, @LStuff, SizeOf(LStuff));
end;

procedure TKqueueCrossSocket._SetNoSigPipe(ASocket: TSocket);
begin
	{$if defined(MACOS) or defined(FREEBSD)}
  TSocketAPI.SetSockOpt<Integer>(ASocket, SOL_SOCKET, SO_NOSIGPIPE, 1);
  {$endif}
end;

procedure TKqueueCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  FRegisteredLock.Enter;
  try
    FStopping := False;
  finally
    FRegisteredLock.Leave;
  end;
  _OpenIdleHandle;

  FKqueueHandle := kqueue();
  _OpenStopHandle;
  _StartListening;
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[i] := TIoEventThread.Create(Self);
end;

procedure TKqueueCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then
  begin
    _StopListening;
    _CloseRegisteredData;
    Exit;
  end;

  // 先拒绝当前工作线程，避免关闭/注册表等待依赖自身继续运行。
  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
    if (FIoThreads[I].ThreadID = LCurrentThreadID) then
      raise ECrossSocket.Create('不能在IO线程中执行StopLoop!');

  _StopListening;
  FRegisteredLock.Enter;
  try
    FStopping := True;
  finally
    FRegisteredLock.Leave;
  end;
  CloseAll;
  _CloseRegisteredData;

  // 另一线程可能已移除 owner 记录，但仍在关闭回调中；等它撤销注册后再停线程。
  while (ListensCount > 0) or (ConnectionsCount > 0)
    or (_RegisteredCount > 0) do Sleep(1);

  _PostStopCommand;

  for I := 0 to Length(FIoThreads) - 1 do
  begin
    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  FileClose(FKqueueHandle);
  _CloseIdleHandle;
  _CloseStopHandle;
end;

function TKqueueCrossSocket._ConnectAddr(const AOp: IInterface;
  const AAddr: TCrossConnectAddr): Boolean;
var
  LState: TCrossConnectOp;
  LSocket, LClientSocket: TSocket;
  LError: Integer;
  LSockAddr: TRawSockAddrIn;
  LConnection: ICrossConnection;
  LConnectCb: TCrossConnectionCallback;
  LKqConnection: TKqueueConnection;
  LRetryOp: IInterface;
  LSuccess, LCloseRequired: Boolean;
begin
  LState := AOp as TCrossConnectOp;
  LSocket := TSocketAPI.NewSocket(AAddr.Family, AAddr.SockType, AAddr.Protocol);
  if (LSocket = INVALID_SOCKET) then
  begin
    LError := GetLastError;
    _LogLastOsError('TKqueueCrossSocket._ConnectAddr.NewSocket');
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
    _SetNoSigPipe(LSocket);
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
      _LogLastOsError('TKqueueCrossSocket._ConnectAddr.Bind');
      Exit(False);
    end;

    if (TSocketAPI.Connect(LSocket, @AAddr.Addr.Addr, AAddr.Addr.AddrLen) <> 0)
      and (GetLastError <> EINPROGRESS) then
    begin
      _LogLastOsError('TKqueueCrossSocket._ConnectAddr.Connect');
      Exit(False);
    end;

    LConnectCb := LState.CreateCallback();
    LClientSocket := LSocket;
    LSocket := INVALID_SOCKET;
    LConnection := CreateConnection(Self, LClientSocket, ctConnect,
      LState.Host, LConnectCb);
    try
      LKqConnection := LConnection as TKqueueConnection;
      LKqConnection._SetConnectOp(AOp);
      PrepareConnection(LConnection, LState.Host, LState.LogicalPort);
      TriggerConnecting(LConnection);
      // 用户关闭或 CloseAllConnections 已终止整次操作，不再回退。
      if LConnection.IsClosed then Exit(True);
      {$IFDEF CROSS_CAPACITY_TESTS}
      if Assigned(CrossConnectBeforeRegisterForTest) then
        CrossConnectBeforeRegisterForTest(LConnection);
      {$ENDIF}

      LKqConnection._KqLock;
      try
        LSuccess := LKqConnection._UpdateIoEvent([ieWrite], LCloseRequired);
      finally
        LKqConnection._KqUnlock;
      end;
      // 先独占失败清理，锁外关闭旧尝试；只有清理获胜者才能继续下一地址。
      if not LSuccess then
        Exit(not LKqConnection._CloseRetryingConnect(LRetryOp));
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

function TKqueueCrossSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TKqueueConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

function TKqueueCrossSocket.CreateListen(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TKqueueListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TKqueueCrossSocket.Listen(const AHost: string; const APort: Word;
  const ACallback: TCrossListenCallback);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: TSocket;
  LListen: ICrossListen;
  LKqListen: TKqueueListen;
  LListenSuccess, LUpdateIoEventSuccess: Boolean;
  LGeneration: Integer;

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
    _LogLastOsError('TKqueueCrossSocket.Listen.GetAddrInfo');
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
        _LogLastOsError('TKqueueCrossSocket.Listen.NewSocket');
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
        _LogLastOsError('TKqueueCrossSocket.Listen.Bind');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);
      LKqListen := LListen as TKqueueListen;

      try
        if not _RegisterListen(LListen, LGeneration) then
        begin
          _Failed;
          Exit;
        end;
        // 监听套接字的读事件
        // 读事件到达表明有新连接
        LKqListen._Lock;
        try
          LUpdateIoEventSuccess := LKqListen._UpdateIoEvent([ieRead]);
        finally
          LKqListen._Unlock;
        end;

        if not LUpdateIoEventSuccess then
        begin
          _Failed;

          Exit;
        end;

        TriggerListened(LListen);
        if not LKqListen._IsPublished then
        begin
          // 注册后被 StopLoop 关闭、未能发布，仍走失败通知和清理。
          _Failed;
          Exit;
        end;
        // 已成功发布后用户回调主动 Close，仍保留原成功通知语义。
        LListenSuccess := True;
        if Assigned(ACallback) then
          ACallback(LListen, True);
      except
        on E: Exception do
        begin
          _CloseCrossData(LListen);
          raise;
        end;
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

procedure TKqueueCrossSocket.Send(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LConnection: TKqueueConnection;
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
      LConnection := AConnection as TKqueueConnection;
      LConnection._KqLock;
      try
        // 与关闭清空队列共用锁，拒绝已关闭连接的迟到入队。
        if not (LConnection.ConnectStatus in [csDisconnected, csClosed]) then
        begin
          LConnection.FSendQueue.Enqueue(LSendItem);
          LQueued := True;
          LConnection._UpdateIoEvent([ieWrite], LCloseRequired);
        end;
      finally
        LConnection._KqUnlock;
      end;
    except
      on E: Exception do
      begin
        LCloseRequired := True;
        _LogException('Kqueue send submission failed', E);
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

function TKqueueCrossSocket.ProcessIoEvent: Boolean;
var
  LRet, I: Integer;
  LEvent: TKEvent;
  LCrossData: ICrossData;
  LListen: ICrossListen;
  LConnection: ICrossConnection;
begin
  LRet := kevent(FKqueueHandle, nil, 0, @FEventList[0], MAX_EVENT_COUNT, nil);
  if (LRet < 0) then
  begin
    LRet := GetLastError;
    // EINTR, kevent 调用被系统信号打断, 可以进行重试
    Exit(LRet = EINTR);
  end;

  {$IFDEF CROSS_KQUEUE_TESTS}
  if Assigned(CrossKqueueEventsReadyForTest) then
    CrossKqueueEventsReadyForTest(@FEventList[0], LRet);
  {$ENDIF}

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];

    // 收到退出命令
    if (LEvent.uData = SHUTDOWN_FLAG) then Exit(False);

    if (LEvent.uData = nil) then Continue;

    {$region '获取连接或监听对象'}
    // 清理上一项接口发生在表锁外；取得接口后不再依赖事件中的裸地址。
    LListen := nil;
    LConnection := nil;
    LCrossData := nil;
    LCrossData := _FindRegisteredData(NativeUInt(LEvent.uData));
    if (LCrossData = nil) or LCrossData.IsClosed then Continue;
    Supports(LCrossData, ICrossListen, LListen);
    Supports(LCrossData, ICrossConnection, LConnection);
    {$endregion}

    {$region 'IO事件处理'}
    try
      if (LListen <> nil) then
      begin
        if (LEvent.Filter = EVFILT_READ) then
          _HandleAccept(LListen);
      end else
      if (LConnection <> nil) then
      begin
        if (LEvent.Filter = EVFILT_READ) then
          _HandleRead(LConnection)
        else if (LEvent.Filter = EVFILT_WRITE) then
        begin
          if (LConnection.ConnectStatus = csConnecting) then
            _HandleConnect(LConnection)
          else
            _HandleWrite(LConnection);
        end;
      end;
    except
      on E: Exception do
      begin
        _LogException('ProcessIoEvent', E);
        _CloseCrossData(LCrossData);
      end;
    end;
    {$endregion}
  end;

  Result := True;
end;

end.
