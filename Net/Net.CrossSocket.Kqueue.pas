﻿{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Kqueue;

interface

{$IF defined(MACOS) or defined(IOS)}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Posix.SysSocket,
  Posix.NetinetIn,
  Posix.UniStd,
  Posix.NetDB,
  Posix.Pthread,
  Posix.Errno,
  BSD.kqueue,
  Net.SocketAPI,
  Net.CrossSocket.Base;

type
  TIoEvent = (ieRead, ieWrite);
  TIoEvents = set of TIoEvent;

  TKqueueListen = class(TAbstractCrossListen)
  private
    FLock: TObject;
    FIoEvents: TIoEvents;

    procedure _Lock; inline;
    procedure _Unlock; inline;

    function _ReadEnabled: Boolean; inline;
    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer); override;
    destructor Destroy; override;
  end;

  PSendItem = ^TSendItem;
  TSendItem = record
    Data: PByte;
    Size: Integer;
    Callback: TProc<ICrossConnection, Boolean>;
  end;

  TSendQueue = class(TList<PSendItem>)
  protected
    procedure Notify(const Value: PSendItem; Action: TCollectionNotification); override;
  end;

  TKqueueConnection = class(TAbstractCrossConnection)
  private
    FLock: TObject;
    FSendQueue: TSendQueue;
    FIoEvents: TIoEvents;
    FConnectCallback: TProc<ICrossConnection, Boolean>; // 用于 Connect 回调

    procedure _Lock; inline;
    procedure _Unlock; inline;

    function _ReadEnabled: Boolean; inline;
    function _WriteEnabled: Boolean; inline;
    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); override;
    destructor Destroy; override;

    procedure Close; override;
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
  TKqueueCrossSocket = class(TAbstractCrossSocket)
  private const
    MAX_EVENT_COUNT = 2048;
    SHUTDOWN_FLAG   = Pointer(-1);
  private class threadvar
    FEventList: array [0..MAX_EVENT_COUNT-1] of TKEvent;
  private
    FKqueueHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FIdleHandle: THandle;
    FIdleLock: TObject;
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
    procedure _SetNoSigPipe(ASocket: THandle); inline;

    procedure _HandleAccept(AListen: ICrossListen);
    procedure _HandleConnect(AConnection: ICrossConnection);
    procedure _HandleRead(AConnection: ICrossConnection);
    procedure _HandleWrite(AConnection: ICrossConnection);
  protected
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossListen, Boolean> = nil); override;

    procedure Connect(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;

    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;

    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

implementation

{$I Net.Posix.inc}

{ TKqueueListen }

constructor TKqueueListen.Create(AOwner: ICrossSocket; AListenSocket: THandle;
  AFamily, ASockType, AProtocol: Integer);
begin
  inherited;

  FLock := TObject.Create;
end;

destructor TKqueueListen.Destroy;
begin
  FreeAndNil(FLock);

  inherited;
end;

procedure TKqueueListen._Lock;
begin
  System.TMonitor.Enter(FLock);
end;

function TKqueueListen._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TKqueueListen._Unlock;
begin
  System.TMonitor.Exit(FLock);
end;

function TKqueueListen._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LOwner: TKqueueCrossSocket;
  LCrossData: Pointer;
  LEvents: array [0..1] of TKEvent;
  N: Integer;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LOwner := TKqueueCrossSocket(Owner);
  LCrossData := Pointer(Self);
  N := 0;

  if _ReadEnabled then
  begin
    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));

    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  Result := (kevent(LOwner.FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);

  {$IFDEF DEBUG}
  if not Result then
    _Log('listen %d kevent error %d', [Socket, GetLastError]);
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

constructor TKqueueConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited;

  FSendQueue := TSendQueue.Create;
  FLock := TObject.Create;
end;

destructor TKqueueConnection.Destroy;
var
  LConnection: ICrossConnection;
  LSendItem: PSendItem;
begin
  LConnection := Self;

  _Lock;
  try
    // 连接释放时, 调用连接回调, 告知连接失败
    // 连接成功后 FConnectCallback 会被置为 nil,
    // 所以如果这里 FConnectCallback 不等于 nil, 则表示连接释放时仍未连接成功
    if Assigned(FConnectCallback) then
    begin
      FConnectCallback(LConnection, False);
      FConnectCallback := nil;
    end;

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
    _Unlock;
  end;

  FreeAndNil(FLock);

  inherited;
end;

procedure TKqueueConnection.Close;
begin
  if (_SetConnectStatus(csClosed) = csClosed) then Exit;

  // shutdown可以触发套接字在kqueue中的事件
  // 而直接close会将套接字从kqueue队列中移除, 不会触发任何事件
  // 这就会导致连接对象在放入kqueue队列时增加的引用计数无法回收, 导致内存泄漏
  // 使用shutdown触发事件后再释放连接可以确保不会产生内存泄露
  TSocketAPI.Shutdown(Socket, 2);
end;

procedure TKqueueConnection._Lock;
begin
  System.TMonitor.Enter(FLock);
end;

function TKqueueConnection._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TKqueueConnection._Unlock;
begin
  System.TMonitor.Exit(FLock);
end;

function TKqueueConnection._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LOwner: TKqueueCrossSocket;
  LCrossData: Pointer;
  LEvents: array [0..1] of TKEvent;
  N: Integer;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LOwner := TKqueueCrossSocket(Owner);
  LCrossData := Pointer(Self);
  N := 0;

  // kqueue中同一个套接字的EVFILT_READ和EVFILT_WRITE事件在队列中会有两条记录
  // 并且可能会在不同的线程中同时被触发, 如果其中一个线程关闭了连接, 在没有
  // 引用计数保护的情况下, 就会导致连接对象被释放, 另一个线程再访问连接对象
  // 就会引起异常, 这里为了保证连接对象的有效性, 在添加事件时手动增加连接对象
  // 的引用计数, 到事件触发时再减少引用计数
  // 注意关闭连接一定要使用shutdown而不能直接close, 否则无法触发kqueue事件,
  // 导致引用计数无法回收

  if _ReadEnabled then
  begin
    Self._AddRef;

    EV_SET(@LEvents[N], Socket, EVFILT_READ,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));

    Inc(N);
  end;

  if _WriteEnabled then
  begin
    Self._AddRef;

    EV_SET(@LEvents[N], Socket, EVFILT_WRITE,
      EV_ADD or EV_ONESHOT or EV_CLEAR or EV_DISPATCH, 0, 0, Pointer(LCrossData));

    Inc(N);
  end;

  if (N <= 0) then Exit(False);

  Result := (kevent(LOwner.FKqueueHandle, @LEvents, N, nil, 0, nil) >= 0);

  if not Result then
  begin
    {$IFDEF DEBUG}
    _Log('connection %d kevent error %d', [Socket, GetLastError]);
    {$ENDIF}

    while (N > 0) do
    begin
      Self._Release;
      Dec(N);
    end;
  end;
end;

function TKqueueConnection._WriteEnabled: Boolean;
begin
  Result := (ieWrite in FIoEvents);
end;

{ TKqueueCrossSocket }

constructor TKqueueCrossSocket.Create(AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TObject.Create;
end;

destructor TKqueueCrossSocket.Destroy;
begin
  FreeAndNil(FIdleLock);

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

procedure TKqueueCrossSocket._HandleAccept(AListen: ICrossListen);
var
  LListen: ICrossListen;
  LKqListen: TKqueueListen;
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSocket, LError: Integer;
  LListenSocket, LClientSocket: THandle;
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
        System.TMonitor.Enter(FIdleLock);
        try
          _CloseIdleHandle;
          LSocket := TSocketAPI.Accept(LListenSocket, nil, nil);
          TSocketAPI.CloseSocket(LSocket);
          _OpenIdleHandle;
        finally
          System.TMonitor.Exit(FIdleLock);
        end;
      end;

      Break;
    end;

    LClientSocket := LSocket;
    TSocketAPI.SetNonBlock(LClientSocket, True);
    SetKeepAlive(LClientSocket);
    _SetNoSigPipe(LClientSocket);

    LConnection := CreateConnection(Self, LClientSocket, ctAccept);
    TriggerConnecting(LConnection);
    TriggerConnected(LConnection);

    // 连接建立后监视Socket的读事件
    LKqConnection := LConnection as TKqueueConnection;
    LKqConnection._Lock;
    try
      LSuccess := LKqConnection._UpdateIoEvent([ieRead]);
    finally
      LKqConnection._Unlock;
    end;

    if not LSuccess then
      TriggerDisconnected(LConnection);
  end;

  // 继续接收新连接
  LKqListen := LListen as TKqueueListen;
  LKqListen._Lock;
  LKqListen._UpdateIoEvent([ieRead]);
  LKqListen._Unlock;
end;

procedure TKqueueCrossSocket._HandleConnect(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LConnectCallback: TProc<ICrossConnection, Boolean>;
  LSuccess: Boolean;
begin
  LConnection := AConnection;

  // Connect失败
  if (TSocketAPI.GetError(LConnection.Socket) <> 0) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError;
    {$ENDIF}
    TriggerDisconnected(LConnection);
    Exit;
  end;

  LKqConnection := LConnection as TKqueueConnection;

  LKqConnection._Lock;
  try
    LConnectCallback := LKqConnection.FConnectCallback;
    LKqConnection.FConnectCallback := nil;
    LSuccess := LKqConnection._UpdateIoEvent([ieRead]);
  finally
    LKqConnection._Unlock;
  end;

  if LSuccess then
    TriggerConnected(LConnection)
  else
    TriggerDisconnected(LConnection);

  if Assigned(LConnectCallback) then
    LConnectCallback(LConnection, LSuccess);
end;

procedure TKqueueCrossSocket._HandleRead(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
  LKqConnection: TKqueueConnection;
  LSuccess: Boolean;
begin
  LConnection := AConnection;

  while True do
  begin
    LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

    // 对方主动断开连接
    if (LRcvd = 0) then
    begin
//      _Log('%d close on read 0, ref %d', [LConnection.Socket, TInterfacedObject(LConnection).RefCount]);
      TriggerDisconnected(LConnection);
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
//        _Log('%d close on read error %d, ref %d', [LConnection.Socket, GetLastError, TInterfacedObject(LConnection).RefCount]);
        TriggerDisconnected(LConnection);
        Exit;
      end;
    end;

    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;

  LKqConnection := LConnection as TKqueueConnection;
  LKqConnection._Lock;
  try
    LSuccess := LKqConnection._UpdateIoEvent([ieRead]);
  finally
    LKqConnection._Unlock;
  end;

  if not LSuccess then
    TriggerDisconnected(LConnection);
end;

procedure TKqueueCrossSocket._HandleWrite(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
  LCallback: TProc<ICrossConnection, Boolean>;
  LSent: Integer;
begin
  LConnection := AConnection;
  LKqConnection := LConnection as TKqueueConnection;

  LKqConnection._Lock;
  try
    // 队列中没有数据了, 清除 ioWrite 标志
    if (LKqConnection.FSendQueue.Count <= 0) then
    begin
      LKqConnection._UpdateIoEvent([]);
      Exit;
    end;

    // 获取Socket发送队列中的第一条数据
    LSendItem := LKqConnection.FSendQueue.Items[0];

    // 发送数据
    LSent := PosixSend(LConnection.Socket, LSendItem.Data, LSendItem.Size);

    {$region '全部发送完成'}
    if (LSent >= LSendItem.Size) then
    begin
      // 先保存回调函数, 避免后面删除队列后将其释放
      LCallback := LSendItem.Callback;

      // 发送成功, 移除已发送成功的数据
      if (LKqConnection.FSendQueue.Count > 0) then
        LKqConnection.FSendQueue.Delete(0);

      // 队列中没有数据了, 清除 ioWrite 标志
      if (LKqConnection.FSendQueue.Count <= 0) then
        LKqConnection._UpdateIoEvent([]);

      if Assigned(LCallback) then
        LCallback(LConnection, True);

      Exit;
    end;
    {$endregion}

    {$region '连接断开或发送错误'}
    // 发送失败的回调会在连接对象的destroy方法中被调用
    if (LSent < 0) then Exit;
    {$endregion}

    {$region '部分发送成功,在下一次唤醒发送线程时继续处理剩余部分'}
    Dec(LSendItem.Size, LSent);
    Inc(LSendItem.Data, LSent);
    {$endregion}

    LKqConnection._UpdateIoEvent([ieWrite]);
  finally
    LKqConnection._Unlock;
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
  Posix.UniStd.__write(FStopHandle.WriteDes, @LStuff, SizeOf(LStuff));
end;

procedure TKqueueCrossSocket._SetNoSigPipe(ASocket: THandle);
begin
  TSocketAPI.SetSockOpt<Integer>(ASocket, SOL_SOCKET, SO_NOSIGPIPE, 1);
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

procedure TKqueueCrossSocket.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossConnection, Boolean>);

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
  var
    LConnection: ICrossConnection;
    LKqConnection: TKqueueConnection;
  begin
    if (TSocketAPI.Connect(ASocket, AAddr.ai_addr, AAddr.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      LConnection := CreateConnection(Self, ASocket, ctConnect);
      TriggerConnecting(LConnection);
      LKqConnection := LConnection as TKqueueConnection;

      LKqConnection._Lock;
      try
        LKqConnection.ConnectStatus := csConnecting;
        LKqConnection.FConnectCallback := ACallback;
        if not LKqConnection._UpdateIoEvent([ieWrite]) then
        begin
          TriggerDisconnected(LConnection);
          Exit(False);
        end;
      finally
        LKqConnection._Unlock;
      end;
    end else
    begin
      TSocketAPI.CloseSocket(ASocket);
      if Assigned(ACallback) then
        ACallback(nil, False);
      Exit(False);
    end;

    Result := True;
  end;

var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;
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

function TKqueueCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TKqueueConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TKqueueCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TKqueueListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TKqueueCrossSocket.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossListen, Boolean>);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: THandle;
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
      TSocketAPI.SetReUseAddr(LListenSocket, True);

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

procedure TKqueueCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc<ICrossConnection, Boolean>);
var
  LKqConnection: TKqueueConnection;
  LSendItem: PSendItem;
begin
  // 测试过先发送, 然后将剩余部分放入发送队列的做法
  // 发现会引起内存访问异常, 放到队列里到IO线程中发送则不会有问题
  {$region '放入发送队列'}
  System.New(LSendItem);
  LSendItem.Data := ABuf;
  LSendItem.Size := ALen;
  LSendItem.Callback := ACallback;

  LKqConnection := AConnection as TKqueueConnection;

  LKqConnection._Lock;
  try
    // 将数据放入队列
    LKqConnection.FSendQueue.Add(LSendItem);

    // 由于 kqueue 队列中每个套接字的读写事件是分开的两条记录
    // 所以发送只需要添加写事件即可, 不用管读事件, 否则反而会引起引用计数异常
    if not LKqConnection._WriteEnabled then
      LKqConnection._UpdateIoEvent([ieWrite]);
  finally
    LKqConnection._Unlock;
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

{$ELSE}
implementation
{$ENDIF}
end.
