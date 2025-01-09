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

    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
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

  TSendQueue = class(TList<PSendItem>)
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

    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
    procedure _ClearSendQueue;

    // 为了减少死锁的可能, 不使用父类的 _Lock/_Unlock
    // 因为父类的 _Lock/_Unlock 主要用于连接事件和接收数据事件
    // 这里的 _EpLock/_EpUnlock 主要用于发送队列和Epoll事件
    // 在接收完数据之后马上发送数据, 如果使用同一把锁可能会引起死锁
    procedure _EpLock; inline;
    procedure _EpUnlock; inline;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

    procedure Close; override;
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
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    function CreateListen(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil); override;

    procedure Connect(const AHost: string; const APort: Word;
      const ACallback: TCrossConnectionCallback = nil); override;

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

function TEpollListen._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LEvent: TEPoll_Event;
begin
  if (AIoEvents = []) or IsClosed then Exit(False);

  LEvent.Events := EPOLLET or EPOLLONESHOT;
  LEvent.Data.u64 := Self.UID;

  if (ieRead in AIoEvents) then
    LEvent.Events := LEvent.Events or EPOLLIN;

  Result := (epoll_ctl(FEpollHandle, FOpCode, Socket, @LEvent) >= 0);
  FOpCode := EPOLL_CTL_MOD;

  if not Result then
    _LogLastOsError('listen epoll_ctl, %s', [Self.DebugInfo]);
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
  const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AConnectCb);

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

procedure TEpollConnection.Close;
begin
  _EpLock;
  try
    if (GetConnectStatus = csClosed) then Exit;

    _ClearSendQueue;

    epoll_ctl(FEpollHandle, EPOLL_CTL_DEL, Socket, nil);

    inherited Close;
  finally
    _EpUnlock;
  end;
end;

procedure TEpollConnection._ClearSendQueue;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
begin
  LConnection := Self;

  _EpLock;
  try
    // 连接释放时, 调用所有发送队列的回调, 告知发送失败
    if (FSendQueue.Count > 0) then
    begin
      for LSendItem in FSendQueue do
        if Assigned(LSendItem.Callback) then
          LSendItem.Callback(LConnection, False);

      FSendQueue.Clear;
    end;
  finally
    _EpUnlock;
  end;
end;

procedure TEpollConnection._EpLock;
begin
  FEpLock.Enter;
end;

procedure TEpollConnection._EpUnlock;
begin
  FEpLock.Leave;
end;

function TEpollConnection._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LEvent: TEPoll_Event;
begin
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
    _LogLastOsError('connection epoll_ctl, %s, events=0x%.8x',
      [Self.DebugInfo, LEvent.Events]);
    Close;
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
  LListen: ICrossListen;
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
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

      if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
      begin
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

    LConnection := CreateConnection(Self, LClientSocket, ctAccept);
    TriggerConnecting(LConnection);
    TriggerConnected(LConnection);

    // 连接建立后监视Socket的读事件
    LEpConnection := LConnection as TEpollConnection;
    LEpConnection._EpLock;
    try
      LSuccess := LEpConnection._UpdateIoEvent([ieRead]);
    finally
      LEpConnection._EpUnlock;
    end;

    if not LSuccess then
      LConnection.Close;
  end;
end;

procedure TEpollCrossSocket._HandleConnect(const AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
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
begin
  LConnection := AConnection;
  LEpConnection := LConnection as TEpollConnection;
  LSendCbArr := [];

  AtomicIncrement(LEpConnection.FOutPending);
  LEpConnection._EpLock;
  try
    while True do
    begin
      // 检查队列中有没有数据
      if (LEpConnection.FSendQueue.Count <= 0) then Break;

      // 获取Socket发送队列中的第一条数据
      LSendItem := LEpConnection.FSendQueue.Items[0];

      // 发送数据
      LSent := TSocketAPI.Send(LConnection.Socket, LSendItem.Data^, LSendItem.Size, MSG_NOSIGNAL);

      // 对方主动断开连接
      if (LSent = 0) then
      begin
        _Log('Send=0(Close), %s', [LConnection.DebugInfo]);
        LConnection.Close;
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
        if (LEpConnection.FSendQueue.Count > 0) then
          LEpConnection.FSendQueue.Delete(0);
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

  // 调用回调
  for LSendCb in LSendCbArr do
    LSendCb(LConnection, True);
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
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[I] := TIoEventThread.Create(Self);

  _OpenStopHandle;
end;

procedure TEpollCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (FListensCount > 0) or (FConnectionsCount > 0) do Sleep(1);

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

  FileClose(FEpollHandle);
  _CloseIdleHandle;
  _CloseStopHandle;
end;

procedure TEpollCrossSocket.Connect(const AHost: string; const APort: Word;
  const ACallback: TCrossConnectionCallback);

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: TSocket; AAddr: PRawAddrInfo): Boolean;
  var
    LConnection: ICrossConnection;
    LEpConnection: TEpollConnection;
  begin
    if (TSocketAPI.Connect(ASocket, AAddr.ai_addr, AAddr.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      LConnection := CreateConnection(Self, ASocket, ctConnect, ACallback);
      TriggerConnecting(LConnection);
      LEpConnection := LConnection as TEpollConnection;

      LEpConnection._EpLock;
      try
        LEpConnection.ConnectStatus := csConnecting;
        if not LEpConnection._UpdateIoEvent([ieWrite]) then
        begin
          if Assigned(ACallback) then
            ACallback(LConnection, False);
          Exit(False);
        end;
      finally
        LEpConnection._EpUnlock;
      end;
    end else
    begin
      _LogLastOsError('Connect');

      if Assigned(ACallback) then
        ACallback(nil, False);
      TSocketAPI.CloseSocket(ASocket);
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
      if (LSocket = INVALID_SOCKET) then
      begin
        _LogLastOsError('NewSocket');

        _Failed1;
        Exit;
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      SetKeepAlive(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
end;

function TEpollCrossSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TEpollConnection.Create(AOwner, AClientSocket, AConnectType, AConnectCb);
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

  procedure _Failed;
  begin
    _LogLastOsError('Listen');

    if not LListenSuccess and Assigned(ACallback) then
      ACallback(nil, False);
  end;

begin
  LListenSuccess := False;
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
      if (LListenSocket = INVALID_SOCKET) then
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
      LEpListen := LListen as TEpollListen;

      // 监听套接字的读事件
      // 读事件到达表明有新连接
      LEpListen._Lock;
      try
        LUpdateIoEventSuccess := LEpListen._UpdateIoEvent([ieRead]);
      finally
        LEpListen._Unlock;
      end;

      if not LUpdateIoEventSuccess then
      begin
        _Failed;
        Exit;
      end;

      // 监听成功
      LListenSuccess := True;
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

procedure TEpollCrossSocket.Send(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LEpConnection: TEpollConnection;
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

  LEpConnection := AConnection as TEpollConnection;

  LEpConnection._Eplock;
  try
    // 将数据放入队列
    LEpConnection.FSendQueue.Add(LSendItem);

    // 由于epoll队列中每个套接字只有一条记录, 为了避免监视发送数据的时候
    // 无法接收数据, 这里必须同时监视读和写
    LEpConnection._UpdateIoEvent([ieRead, ieWrite]);
  finally
    LEpConnection._EpUnlock;
  end;
  {$endregion}
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
  LSuccess: Boolean;
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
    if (LListen <> nil) then
    begin
      if (LEvent.Events and EPOLLIN <> 0) then
        _HandleAccept(LListen);

      // 继续接收新连接
      LEpListen := LListen as TEpollListen;
      LEpListen._Lock;
      LEpListen._UpdateIoEvent([ieRead]);
      LEpListen._Unlock;
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
          LEpConnection._UpdateIoEvent(LIoEvents);
        finally
          LEpConnection._EpUnlock;
        end;
      end;
    end;
    {$endregion}
  end;

  Result := True;
end;

end.
