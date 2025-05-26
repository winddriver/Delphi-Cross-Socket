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

    function _ReadEnabled: Boolean; inline;
    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer); override;
  end;

  PSendItem = ^TSendItem;
  TSendItem = packed record
    Data: PByte;
    Size: Integer;
    Callback: TCrossConnectionCallback;
  end;

  TSendQueue = class(TList<PSendItem>)
  protected
    procedure Notify(const Value: PSendItem; Action: TCollectionNotification); override;
  end;

  TKqueueConnection = class(TCrossConnectionBase)
  private
    FKqueueHandle: Integer;
    FSendQueue: TSendQueue;
    FKqLock: ILock;
    FInPending, FOutPending: Integer;

    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;

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
  // 由于 KQUEUE 中每个套接字在队列中的 EV_WRITE 和 EV_READ 是分开的两条记录
  // 所以修改套接字的监听事件时不会互相覆盖, 也就是说每个事件都会对应到一次
  // 触发, 这样就可以方便的使用接口的引用计数机制保持连接的有效性, 也不会出现
  // 内存泄漏
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

    procedure Connect(const AHost: string; const APort, ALocalPort: Word;
      const ACallback: TCrossConnectionCallback = nil); override;

    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil); override;

    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(const AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

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

function TKqueueListen._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

function TKqueueListen._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LCrossData: Pointer;
  LEvents: array [0..1] of TKEvent;
  N: Integer;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LCrossData := Pointer(Self);
  N := 0;

  if _ReadEnabled then
  begin
    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));

    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  Result := (kevent(FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);

  {$IFDEF DEBUG}
  if not Result then
    _LogLastOsError('listen kevent, %s', [Socket, Self.DebugInfo]);
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

  inherited;
end;

procedure TKqueueConnection.InternalClose;
begin
  _ClearSendQueue;

  inherited InternalClose;
end;

procedure TKqueueConnection._ClearSendQueue;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
begin
  LConnection := Self;

  _KqLock;
  try
    // 连接释放时, 调用所有发送队列的回调, 告知发送失败
    if (FSendQueue.Count > 0) then
    begin
      for LSendItem in FSendQueue do
        if Assigned(LSendItem.Callback) then
          LSendItem.Callback(LConnection, False);

      FSendQueue.Clear;
    end;

    FreeAndNil(FSendQueue);
  finally
    _KqUnlock;
  end;
end;

procedure TKqueueConnection._KqLock;
begin
  FKqLock.Enter;
end;

procedure TKqueueConnection._KqUnlock;
begin
  FKqLock.Leave;
end;

function TKqueueConnection._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LCrossData: Pointer;
  LEvents: array [0..1] of TKEvent;
  N: Integer;
begin
  if (AIoEvents = []) or IsClosed then Exit(False);

  LCrossData := Pointer(Self);
  N := 0;

  // kqueue中同一个套接字的EVFILT_READ和EVFILT_WRITE事件在队列中会有两条记录
  // 并且可能会在不同的线程中同时被触发, 如果其中一个线程关闭了连接, 在没有
  // 引用计数保护的情况下, 就会导致连接对象被释放, 另一个线程再访问连接对象
  // 就会引起异常, 这里为了保证连接对象的有效性, 在添加事件时手动增加连接对象
  // 的引用计数, 到事件触发时再减少引用计数
  // 注意关闭连接一定要使用shutdown而不能直接close, 否则无法触发kqueue事件,
  // 导致引用计数无法回收

  if (ieRead in AIoEvents) and (AtomicCmpExchange(FInPending, 0, 0) = 0) then
  begin
    Self._AddRef;

    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));

    Inc(N);
  end;

  if (ieWrite in AIoEvents) and (AtomicCmpExchange(FOutPending, 0, 0) = 0) then
  begin
    Self._AddRef;

    EV_SET(@LEvents[N], Socket, EVFILT_WRITE,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));

    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  Result := (kevent(FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);

  if not Result then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('connection kevent, %s', [Self.DebugInfo]);
    {$ENDIF}

    while (N > 0) do
    begin
      Self._Release;
      Dec(N);
    end;

    Self.Close;
  end;
end;

{ TKqueueCrossSocket }

constructor TKqueueCrossSocket.Create(const AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TLock.Create;
end;

destructor TKqueueCrossSocket.Destroy;
begin
  inherited;
end;

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
  LSuccess: Boolean;
begin
  LListen := AListen;
  LListenSocket := LListen.Socket;

  while True do
  begin
    LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);

    // Accept失败
    // EAGAIN 所有就绪的连接都已处理完毕
    // EMFILE 进程的文件句柄已经用完了
    if (LSocket < 0) then
    begin
      LError := GetLastError;

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
      end;

      Break;
    end;

    LClientSocket := LSocket;
    TSocketAPI.SetNonBlock(LClientSocket, True);
    SetKeepAlive(LClientSocket);
    _SetNoSigPipe(LClientSocket);

    LConnection := CreateConnection(Self, LClientSocket, ctAccept, '');
    TriggerConnecting(LConnection);
    TriggerConnected(LConnection);

    // 连接建立后监视Socket的读事件
    LKqConnection := LConnection as TKqueueConnection;
    LKqConnection._KqLock;
    try
      LKqConnection._UpdateIoEvent([ieRead]);
    finally
      LKqConnection._KqUnlock;
    end;
  end;

  // 继续接收新连接
  LKqListen := LListen as TKqueueListen;
  LKqListen._Lock;
  LKqListen._UpdateIoEvent([ieRead]);
  LKqListen._Unlock;
end;

procedure TKqueueCrossSocket._HandleConnect(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LConnectCallback: TCrossConnectionCallback;
  LSuccess: Boolean;
begin
  LConnection := AConnection;

  // Connect失败
  if (TSocketAPI.GetError(LConnection.Socket) <> 0) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError;
    {$ENDIF}
    LConnection.Close;
    Exit;
  end;

  TriggerConnected(LConnection);

  LKqConnection := LConnection as TKqueueConnection;

  LKqConnection._KqLock;
  try
    LSuccess := LKqConnection._UpdateIoEvent([ieRead]);
  finally
    LKqConnection._KqUnlock;
  end;

  if Assigned(LConnectCallback) then
    LConnectCallback(LConnection, LSuccess);
end;

procedure TKqueueCrossSocket._HandleRead(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LRcvd, LError: Integer;
  LSuccess: Boolean;
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

      if (LRcvd < RCV_BUF_SIZE) then Break;
    end;
  finally
    AtomicDecrement(LKqConnection.FInPending);
  end;

  LKqConnection._KqLock;
  try
    LKqConnection._UpdateIoEvent([ieRead]);
  finally
    LKqConnection._KqUnlock;
  end;
end;

procedure TKqueueCrossSocket._HandleWrite(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
  LSent, LError: Integer;
  LSendCbArr: TArray<TCrossConnectionCallback>;
  LSendCb: TCrossConnectionCallback;
begin
  LConnection := AConnection;
  LKqConnection := LConnection as TKqueueConnection;
  LSendCbArr := [];

  AtomicIncrement(LKqConnection.FOutPending);
  LKqConnection._KqLock;
  try
    while True do
    begin
      // 检查队列中有没有数据
      if (LKqConnection.FSendQueue.Count <= 0) then Break;

      // 获取Socket发送队列中的第一条数据
      LSendItem := LKqConnection.FSendQueue.Items[0];

      // 发送数据
      LSent := TSocketAPI.Send(LConnection.Socket, LSendItem.Data^, LSendItem.Size);

      // 对方主动断开连接
      if (LSent = 0) then
      begin
        _Log('Send=0(close), %s', [LConnection.DebugInfo]);

        LConnection.Close;
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

          LConnection.Close;
          Break;
        end;
      end;

      // 全部发送完成
      if (LSent >= LSendItem.Size) then
      begin
        TArrayUtils<TCrossConnectionCallback>.Append(LSendCbArr, LSendItem.Callback);

        // 发送成功, 移除已发送成功的数据
        // 必须先从队列移除已发完的数据项, 然后再执行发送成功的回调
        // 因为回调里可能还会发送新的数据, 如果先执行回调再去移除,
        // 就会错误的将回调中放到队列里的新数据移除
        if (LKqConnection.FSendQueue.Count > 0) then
          LKqConnection.FSendQueue.Delete(0);
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

  // 调用回调
  for LSendCb in LSendCbArr do
    LSendCb(LConnection, True);

  LKqConnection._KqLock;
  try
    if (LKqConnection.FSendQueue.Count > 0) then
      LKqConnection._UpdateIoEvent([ieWrite]);
  finally
    LKqConnection._KqUnlock;
  end;
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
	{$ifdef MACOS}
  TSocketAPI.SetSockOpt<Integer>(ASocket, SOL_SOCKET, SO_NOSIGPIPE, 1);
  {$endif}
end;

procedure TKqueueCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  _OpenIdleHandle;

  FKqueueHandle := kqueue();
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[i] := TIoEventThread.Create(Self);

  _OpenStopHandle;
end;

procedure TKqueueCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (ListensCount > 0) or (ConnectionsCount > 0) do Sleep(1);

  _PostStopCommand;

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    if (FIoThreads[I].ThreadID = LCurrentThreadID) then
      raise ECrossSocket.Create('不能在IO线程中执行StopLoop!');

    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  FileClose(FKqueueHandle);
  _CloseIdleHandle;
  _CloseStopHandle;
end;

procedure TKqueueCrossSocket.Connect(const AHost: string;
  const APort, ALocalPort: Word; const ACallback: TCrossConnectionCallback);

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(const ASocket: TSocket; const AAddr: PRawAddrInfo): Boolean;
    procedure _Failed2;
    begin
      if Assigned(ACallback) then
        ACallback(nil, False);
      TSocketAPI.CloseSocket(ASocket);
    end;
  var
    LSockAddr: TRawSockAddrIn;
    LConnection: ICrossConnection;
    LKqConnection: TKqueueConnection;
  begin
    FillChar(LSockAddr, SizeOf(TRawSockAddrIn), 0);
    LSockAddr.AddrLen := AAddr.ai_addrlen;
    if (AAddr.ai_family = AF_INET6) then
    begin
      LSockAddr.Addr6.sin6_family := AAddr.ai_family;
      LSockAddr.Addr6.sin6_port := htons(ALocalPort);
    end else
    begin
      LSockAddr.Addr.sin_family := AAddr.ai_family;
      LSockAddr.Addr.sin_port := htons(ALocalPort);
    end;
    if (TSocketAPI.Bind(ASocket, @LSockAddr.Addr, LSockAddr.AddrLen) < 0) then
    begin
      {$IFDEF DEBUG}
      _LogLastOsError('TKqueueCrossSocket._Connect.Bind');
      {$ENDIF}
      _Failed2;
      Exit(False);
    end;

    if (TSocketAPI.Connect(ASocket, @LSockAddr.Addr, LSockAddr.AddrLen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      LConnection := CreateConnection(Self, ASocket, ctConnect, AHost, ACallback);
      TriggerConnecting(LConnection);
      LKqConnection := LConnection as TKqueueConnection;

      LKqConnection._KqLock;
      try
        LKqConnection.ConnectStatus := csConnecting;
        if not LKqConnection._UpdateIoEvent([ieWrite]) then
        begin
          LConnection.Close;
          _Failed2;
          Exit(False);
        end;
      finally
        LKqConnection._KqUnlock;
      end;
    end else
    begin
      _Failed2;
      Exit(False);
    end;

    Result := True;
  end;

var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: TSocket;
begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed1;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol);
      if (LSocket = INVALID_HANDLE_VALUE) then
      begin
        _Failed1;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      SetKeepAlive(LSocket);
      _SetNoSigPipe(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
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
  LSuccess: Boolean;

  procedure _Failed;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

begin
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LListenSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol);
      if (LListenSocket = INVALID_HANDLE_VALUE) then
      begin
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
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);
      LKqListen := LListen as TKqueueListen;

      // 监听套接字的读事件
      // 读事件到达表明有新连接
      LKqListen._Lock;
      try
        LSuccess := LKqListen._UpdateIoEvent([ieRead]);
      finally
        LKqListen._Unlock;
      end;

      if not LSuccess then
      begin
        _Failed;

        Exit;
      end;

      // 监听成功
      TriggerListened(LListen);
      if Assigned(ACallback) then
        ACallback(LListen, True);

      // 如果端口传入0，让所有地址统一用首个分配到的端口
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        Psockaddr_in(LAddrInfo.ai_next.ai_addr).sin_port := LListen.LocalPort;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;
end;

procedure TKqueueCrossSocket.Send(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
begin
  // 测试过先发送, 然后将剩余部分放入发送队列的做法
  // 发现会引起内存访问异常, 放到队列里到IO线程中发送则不会有问题
  {$region '放入发送队列'}
  System.New(LSendItem);
  FillChar(LSendItem^, SizeOf(TSendItem), 0);
  LSendItem.Data := ABuf;
  LSendItem.Size := ALen;
  LSendItem.Callback := ACallback;

  LKqConnection := AConnection as TKqueueConnection;

  LKqConnection._KqLock;
  try
    // 将数据放入队列
    LKqConnection.FSendQueue.Add(LSendItem);

    // 由于 kqueue 队列中每个套接字的读写事件是分开的两条记录
    // 所以发送只需要添加写事件即可, 不用管读事件, 否则反而会引起引用计数异常
    LKqConnection._UpdateIoEvent([ieWrite]);
  finally
    LKqConnection._KqUnlock;
  end;
  {$endregion}
end;

function TKqueueCrossSocket.ProcessIoEvent: Boolean;
var
  LRet, I: Integer;
  LEvent: TKEvent;
  LCrossData: TCrossData;
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

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];

    // 收到退出命令
    if (LEvent.uData = SHUTDOWN_FLAG) then Exit(False);

    if (LEvent.uData = nil) then Continue;

    {$region '获取连接或监听对象'}
    LCrossData := TCrossData(LEvent.uData);

    if (LCrossData is TKqueueListen) then
      LListen := LCrossData as ICrossListen
    else
      LListen := nil;

    if (LCrossData is TKqueueConnection) then
      LConnection := LCrossData as ICrossConnection
    else
      LConnection := nil;
    {$endregion}

    {$region 'IO事件处理'}
    if (LListen <> nil) then
    begin
      if (LEvent.Filter = EVFILT_READ) then
        _HandleAccept(LListen);
    end else
    if (LConnection <> nil) then
    begin
      LConnection._Release;

      // kqueue的读写事件同一时间只可能触发一个
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
    {$endregion}
  end;

  Result := True;
end;

end.
