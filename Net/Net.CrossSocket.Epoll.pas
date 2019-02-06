﻿{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Epoll;

interface

{$IF defined(LINUX) or defined(ANDROID)}

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
  Linux.epoll,
  Net.SocketAPI,
  Net.CrossSocket.Base;

type
  TIoEvent = (ieRead, ieWrite);
  TIoEvents = set of TIoEvent;

  TEpollListen = class(TAbstractCrossListen)
  private
    FLock: TObject;
    FIoEvents: TIoEvents;
    FOpCode: Integer;

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

  TEpollConnection = class(TAbstractCrossConnection)
  private
    FLock: TObject;
    FSendQueue: TSendQueue;
    FIoEvents: TIoEvents;
    FConnectCallback: TProc<ICrossConnection, Boolean>; // 用于 Connect 回调
    FOpCode: Integer;

    procedure _Lock; inline;
    procedure _Unlock; inline;

    function _ReadEnabled: Boolean; inline;
    function _WriteEnabled: Boolean; inline;
    function _UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); override;
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
  TEpollCrossSocket = class(TAbstractCrossSocket)
  private const
    MAX_EVENT_COUNT = 2048;
    SHUTDOWN_FLAG   = UInt64(-1);
  private class threadvar
    FEventList: array [0..MAX_EVENT_COUNT-1] of TEPoll_Event;
  private
    FEpollHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FIdleHandle: THandle;
    FIdleLock: TObject;
    FStopHandle: THandle;

    // 利用 eventfd 唤醒并退出IO线程
    procedure _OpenStopHandle; inline;
    procedure _PostStopCommand; inline;
    procedure _CloseStopHandle; inline;

    procedure _OpenIdleHandle; inline;
    procedure _CloseIdleHandle; inline;

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

{ TEpollListen }

constructor TEpollListen.Create(AOwner: ICrossSocket; AListenSocket: THandle;
  AFamily, ASockType, AProtocol: Integer);
begin
  inherited;

  FLock := TObject.Create;
  FOpCode := EPOLL_CTL_ADD;
end;

destructor TEpollListen.Destroy;
begin
  FreeAndNil(FLock);

  inherited;
end;

procedure TEpollListen._Lock;
begin
  System.TMonitor.Enter(FLock);
end;

function TEpollListen._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TEpollListen._Unlock;
begin
  System.TMonitor.Exit(FLock);
end;

function TEpollListen._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LOwner: TEpollCrossSocket;
  LEvent: TEPoll_Event;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LOwner := TEpollCrossSocket(Owner);

  LEvent.Events := EPOLLET or EPOLLONESHOT;
  LEvent.Data.u64 := Self.UID;

  if _ReadEnabled then
    LEvent.Events := LEvent.Events or EPOLLIN;

  Result := (epoll_ctl(LOwner.FEpollHandle, FOpCode, Socket, @LEvent) >= 0);
  FOpCode := EPOLL_CTL_MOD;

  {$IFDEF DEBUG}
  if not Result then
    _Log('listen %d epoll_ctl error %d', [UID, GetLastError]);
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

{ TEpollConnection }

constructor TEpollConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited;

  FSendQueue := TSendQueue.Create;
  FLock := TObject.Create;

  FOpCode := EPOLL_CTL_ADD;
end;

destructor TEpollConnection.Destroy;
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

procedure TEpollConnection._Lock;
begin
  System.TMonitor.Enter(FLock);
end;

function TEpollConnection._ReadEnabled: Boolean;
begin
  Result := (ieRead in FIoEvents);
end;

procedure TEpollConnection._Unlock;
begin
  System.TMonitor.Exit(FLock);
end;

function TEpollConnection._UpdateIoEvent(const AIoEvents: TIoEvents): Boolean;
var
  LOwner: TEpollCrossSocket;
  LEvent: TEPoll_Event;
begin
  FIoEvents := AIoEvents;

  if (FIoEvents = []) or IsClosed then Exit(False);

  LOwner := TEpollCrossSocket(Owner);

  LEvent.Events := EPOLLET or EPOLLONESHOT;
  LEvent.Data.u64 := Self.UID;

  if _ReadEnabled then
    LEvent.Events := LEvent.Events or EPOLLIN;

  if _WriteEnabled then
    LEvent.Events := LEvent.Events or EPOLLOUT;

  Result := (epoll_ctl(LOwner.FEpollHandle, FOpCode, Socket, @LEvent) >= 0);
  FOpCode := EPOLL_CTL_MOD;

  {$IFDEF DEBUG}
  if not Result then
    _Log('connection %.16x epoll_ctl socket=%d events=0x%.8x error %d',
      [UID, LEvent.Events, Socket, GetLastError]);
  {$ENDIF}
end;


function TEpollConnection._WriteEnabled: Boolean;
begin
  Result := (ieWrite in FIoEvents);
end;

{ TEpollCrossSocket }

constructor TEpollCrossSocket.Create(AIoThreads: Integer);
begin
  inherited;

  FIdleLock := TObject.Create;
end;

destructor TEpollCrossSocket.Destroy;
begin
  FreeAndNil(FIdleLock);

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

procedure TEpollCrossSocket._HandleAccept(AListen: ICrossListen);
var
  LListen: ICrossListen;
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
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

    LConnection := CreateConnection(Self, LClientSocket, ctAccept);
    TriggerConnecting(LConnection);
    TriggerConnected(LConnection);

    // 连接建立后监视Socket的读事件
    LEpConnection := LConnection as TEpollConnection;
    LEpConnection._Lock;
    try
      LSuccess := LEpConnection._UpdateIoEvent([ieRead]);
    finally
      LEpConnection._Unlock;
    end;

    if not LSuccess then
      LConnection.Close;
  end;
end;

procedure TEpollCrossSocket._HandleConnect(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LConnectCallback: TProc<ICrossConnection, Boolean>;
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

  LEpConnection := LConnection as TEpollConnection;

  LEpConnection._Lock;
  try
    LConnectCallback := LEpConnection.FConnectCallback;
    LEpConnection.FConnectCallback := nil;
  finally
    LEpConnection._Unlock;
  end;

  TriggerConnected(LConnection);

  if Assigned(LConnectCallback) then
    LConnectCallback(LConnection, True);
end;

procedure TEpollCrossSocket._HandleRead(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
begin
  LConnection := AConnection;

  while True do
  begin
    LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

    // 对方主动断开连接
    if (LRcvd = 0) then
    begin
//      _Log('connection=%.16x socket=%d read 0', [LConnection.UID, LConnection.Socket]);
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
//        _Log('connection=%.16x socket=%d read error %d', [LConnection.UID, LConnection.Socket, GetLastError]);
        LConnection.Close;
        Exit;
      end;
    end;

    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;
end;

procedure TEpollCrossSocket._HandleWrite(AConnection: ICrossConnection);
var
  LConnection: ICrossConnection;
  LEpConnection: TEpollConnection;
  LSendItem: PSendItem;
  LCallback: TProc<ICrossConnection, Boolean>;
  LSent: Integer;
begin
  LConnection := AConnection;
  LEpConnection := LConnection as TEpollConnection;

  LEpConnection._Lock;
  try
    // 队列中没有数据了, 清除 ioWrite 标志
    if (LEpConnection.FSendQueue.Count <= 0) then
    begin
      LEpConnection._UpdateIoEvent([]);
      Exit;
    end;

    // 获取Socket发送队列中的第一条数据
    LSendItem := LEpConnection.FSendQueue.Items[0];

    // 发送数据
    LSent := PosixSend(LConnection.Socket, LSendItem.Data, LSendItem.Size);

    {$region '全部发送完成'}
    if (LSent >= LSendItem.Size) then
    begin
      // 先保存回调函数, 避免后面删除队列后将其释放
      LCallback := LSendItem.Callback;

      // 发送成功, 移除已发送成功的数据
      if (LEpConnection.FSendQueue.Count > 0) then
        LEpConnection.FSendQueue.Delete(0);

      // 队列中没有数据了, 清除 ioWrite 标志
      if (LEpConnection.FSendQueue.Count <= 0) then
        LEpConnection._UpdateIoEvent([]);

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
  finally
    LEpConnection._Unlock;
  end;
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
  Posix.UniStd.__write(FStopHandle, @LStuff, SizeOf(LStuff));
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

procedure TEpollCrossSocket.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossConnection, Boolean>);

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
  var
    LConnection: ICrossConnection;
    LEpConnection: TEpollConnection;
  begin
    if (TSocketAPI.Connect(ASocket, AAddr.ai_addr, AAddr.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      LConnection := CreateConnection(Self, ASocket, ctConnect);
      TriggerConnecting(LConnection);
      LEpConnection := LConnection as TEpollConnection;

      LEpConnection._Lock;
      try
        LEpConnection.ConnectStatus := csConnecting;
        LEpConnection.FConnectCallback := ACallback;
        if not LEpConnection._UpdateIoEvent([ieWrite]) then
        begin
          LConnection.Close;
          Exit(False);
        end;
      finally
        LEpConnection._Unlock;
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

      if _Connect(LSocket, LAddrInfo) then Exit;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
end;

function TEpollCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TEpollConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TEpollCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TEpollListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TEpollCrossSocket.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossListen, Boolean>);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: THandle;
  LListen: ICrossListen;
  LEpListen: TEpollListen;
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
      LEpListen := LListen as TEpollListen;

      // 监听套接字的读事件
      // 读事件到达表明有新连接
      LEpListen._Lock;
      try
        LSuccess := LEpListen._UpdateIoEvent([ieRead]);
      finally
        LEpListen._Unlock;
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

procedure TEpollCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc<ICrossConnection, Boolean>);
var
  LEpConnection: TEpollConnection;
  LSendItem: PSendItem;
begin
  // 测试过先发送, 然后将剩余部分放入发送队列的做法
  // 发现会引起内存访问异常, 放到队列里到IO线程中发送则不会有问题
  {$region '放入发送队列'}
  System.New(LSendItem);
  LSendItem.Data := ABuf;
  LSendItem.Size := ALen;
  LSendItem.Callback := ACallback;

  LEpConnection := AConnection as TEpollConnection;

  LEpConnection._Lock;
  try
    // 将数据放入队列
    LEpConnection.FSendQueue.Add(LSendItem);

    // 由于epoll队列中每个套接字只有一条记录, 为了避免监视发送数据的时候
    // 无法接收数据, 这里必须同时监视读和写
    if not LEpConnection._WriteEnabled then
      LEpConnection._UpdateIoEvent([ieRead, ieWrite]);
  finally
    LEpConnection._Unlock;
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
            if not LListens.TryGetValue(LCrossUID, LListen) then
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
        LEpConnection._Lock;
        try
          if (LEpConnection.FSendQueue.Count > 0) then
            LIoEvents := [ieRead, ieWrite]
          else
            LIoEvents := [ieRead];
          LSuccess := LEpConnection._UpdateIoEvent(LIoEvents);
        finally
          LEpConnection._Unlock;
        end;

        if not LSuccess then
          LConnection.Close;
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
