{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.KqueueLoop;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Posix.SysSocket, Posix.NetinetIn, Posix.UniStd, Posix.NetDB, Posix.Errno,
  BSD.kqueue, Net.SocketAPI, Net.CrossSocket.EventLoop;

type
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
  TKqueueLoop = class(TAbstractEventLoop)
  private const
    MAX_EVENT_COUNT = 64;
  private type
    TKqueueAction = (kqAccept, kqConnect, kqRead, kqWrite);

    PPerIoData = ^TPerIoData;
    TPerIoData = record
      Action: TKqueueAction;
      Socket: THandle;
      Callback: TProc<Boolean>;
    end;

    PSendItem = ^TSendItem;
    TSendItem = record
      Data: PByte;
      Size: Integer;
      Callback: TProc<Boolean>;
    end;
  private
    FKqueueHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FSendQueue: TObjectDictionary<THandle, TList<PSendItem>>;
    class threadvar FEventList: array [0..MAX_EVENT_COUNT-1] of TKEvent;

    function NewIoData: PPerIoData;
    procedure FreeIoData(P: PPerIoData);
    procedure SetNoSigPipe(ASocket: THandle);

    function _KqueueCtl(op: word; fd: THandle; events: SmallInt;
      act: TKqueueAction; cb: TProc<Boolean> = nil): Boolean;

    procedure _ClearSendQueue(ASocketSendQueue: TList<PSendItem>);
    procedure _ClearAllSendQueue;
  protected
    procedure TriggerConnected(ASocket: THandle; AConnectType: Integer); override;
    procedure TriggerDisconnected(ASocket: THandle); override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    function Listen(const AHost: string; APort: Word;
      const ACallback: TProc<Boolean> = nil): Integer; override;
    function Connect(const AHost: string; APort: Word;
      const ACallback: TProc<Boolean> = nil): Integer; override;
    function Send(ASocket: THandle; const ABuf; ALen: Integer;
      const ACallback: TProc<Boolean> = nil): Integer; override;

    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

implementation

{ TKqueueLoop }

constructor TKqueueLoop.Create(AIoThreads: Integer);
begin
  inherited Create(AIoThreads);

  FSendQueue := TObjectDictionary<THandle, TList<PSendItem>>.Create([doOwnsValues]);
end;

destructor TKqueueLoop.Destroy;
begin
  System.TMonitor.Enter(FSendQueue);
  try
    _ClearAllSendQueue;
  finally
    System.TMonitor.Exit(FSendQueue);
  end;
  FreeAndNil(FSendQueue);

  inherited Destroy;
end;

function TKqueueLoop.NewIoData: PPerIoData;
begin
  System.New(Result);
  FillChar(Result^, SizeOf(TPerIoData), 0);
end;

procedure TKqueueLoop.FreeIoData(P: PPerIoData);
begin
  System.Dispose(P);
end;

procedure TKqueueLoop._ClearSendQueue(ASocketSendQueue: TList<PSendItem>);
var
  LSendItem: PSendItem;
begin
  for LSendItem in ASocketSendQueue do
    System.Dispose(LSendItem);

  ASocketSendQueue.Clear;
end;

procedure TKqueueLoop._ClearAllSendQueue;
var
  LPair: TPair<THandle, TList<PSendItem>>;
begin
  for LPair in FSendQueue do
    _ClearSendQueue(LPair.Value);

  FSendQueue.Clear;
end;

function TKqueueLoop._KqueueCtl(op: word; fd: THandle; events: SmallInt;
  act: TKqueueAction; cb: TProc<Boolean>): Boolean;
var
  LEvent: TKEvent;
  LPerIoData: PPerIoData;
begin
  LPerIoData := NewIoData;
  LPerIoData.Action := act;
  LPerIoData.Socket := fd;
  LPerIoData.Callback := cb;

  EV_SET(@LEvent, fd, events, op, 0, 0, Pointer(LPerIoData));
  if (kevent(FKqueueHandle, @LEvent, 1, nil, 0, nil) < 0) then
  begin
    FreeIoData(LPerIoData);
    Exit(False);
  end;

  Result := True;
end;

procedure TKqueueLoop.SetNoSigPipe(ASocket: THandle);
var
  LOptVal: Integer;
begin
  LOptVal := 1;
  TSocketAPI.SetSockOpt(ASocket, SOL_SOCKET, SO_NOSIGPIPE, LOptVal, SizeOf(Integer));
end;

procedure TKqueueLoop.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  FKqueueHandle := kqueue();
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[i] := TIoEventThread.Create(Self);
end;

procedure TKqueueLoop.StopLoop;
var
  I: Integer;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (FListensCount > 0) or (FConnectionsCount > 0) do Sleep(1);

  Posix.UniStd.__close(FKqueueHandle);

  for I := 0 to Length(FIoThreads) - 1 do
  begin
    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;
end;

procedure TKqueueLoop.TriggerConnected(ASocket: THandle; AConnectType: Integer);
var
  LSocketSendQueue: TList<PSendItem>;
begin
  // 获取Socket发送队列
  System.TMonitor.Enter(FSendQueue);
  try
    if not FSendQueue.TryGetValue(ASocket, LSocketSendQueue) then
    begin
      LSocketSendQueue := TList<PSendItem>.Create;
      FSendQueue.AddOrSetValue(ASocket, LSocketSendQueue);
    end;
  finally
    System.TMonitor.Exit(FSendQueue);
  end;
end;

procedure TKqueueLoop.TriggerDisconnected(ASocket: THandle);
var
  LSocketSendQueue: TList<PSendItem>;
begin
  // 移除Socket发送队列
  System.TMonitor.Enter(FSendQueue);
  try
    if FSendQueue.TryGetValue(ASocket, LSocketSendQueue) then
    begin
      // 清除当前Socket的所有发送队列
      _ClearSendQueue(LSocketSendQueue);
      FSendQueue.Remove(ASocket);
    end;
  finally
    System.TMonitor.Exit(FSendQueue);
  end;
end;

function TKqueueLoop.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<Boolean>): Integer;
  procedure _Failed1;
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}
    TriggerConnectFailed(INVALID_HANDLE_VALUE);
    if Assigned(ACallback) then
      ACallback(False);
  end;

  function _Connect(ASocket: THandle; Addr: PRawAddrInfo): Boolean;
    procedure _Failed2;
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}
      TSocketAPI.CloseSocket(ASocket);
      TriggerConnectFailed(ASocket);
      if Assigned(ACallback) then
        ACallback(False);
    end;
  begin
    if (TSocketAPI.Connect(ASocket, Addr.ai_addr, Addr.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      // EVFILT_WRITE 只用作判断 Connect 成功与否
      // 所以设置 EV_ONESHOT 标志, 令其触发后立即自动从 kqueue 队列中删除
      if not _KqueueCtl(EV_ADD or EV_ONESHOT, ASocket, EVFILT_WRITE, kqConnect, ACallback) then
      begin
        _Failed2;
        Exit(False);
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
    Exit(-1);
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
        Exit(-1);
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      TSocketAPI.SetReUseAddr(LSocket, True);
      SetKeepAlive(LSocket);
      SetNoSigPipe(LSocket);

      if _Connect(LSocket, LAddrInfo) then Exit(0);

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
  Result := -1;
end;

function TKqueueLoop.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<Boolean>): Integer;
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;

  procedure _Failed;
  begin
    if (LSocket <> INVALID_HANDLE_VALUE) then
      TSocketAPI.CloseSocket(LSocket);

    if Assigned(ACallback) then
      ACallback(False);
  end;

  procedure _Success;
  begin
    if Assigned(ACallback) then
      ACallback(True);

    TriggerListened(LSocket);
  end;

begin
  LSocket := INVALID_HANDLE_VALUE;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    _Failed;
    Exit(-1);
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol);
      if (LSocket = INVALID_HANDLE_VALUE) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        _Failed;
        Exit(-1);
      end;

      TSocketAPI.SetNonBlock(LSocket, True);
      TSocketAPI.SetReUseAddr(LSocket, True);
      SetNoSigPipe(LSocket);

      if (TSocketAPI.Bind(LSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) < 0) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        _Failed;
        Exit(-1);
      end;

      if (TSocketAPI.Listen(LSocket) < 0) then
      begin
        _Failed;
        Exit(-1);
      end;

      // 监听成功之后, 开始监视读事件
      // 监听Socket的读事件触发表示有新连接到达
      if not _KqueueCtl(EV_ADD or EV_CLEAR or EV_DISPATCH, LSocket, EVFILT_READ, kqAccept, nil) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        _Failed;
        Exit(-1);
      end;

      _Success;

      // 如果端口传入0，让所有地址统一用首个分配到的端口
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        Psockaddr_in(LAddrInfo.ai_next.ai_addr).sin_port := Psockaddr_in(LAddrInfo.ai_addr).sin_port;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  Result := 0;
end;

function TKqueueLoop.Send(ASocket: THandle; const ABuf; ALen: Integer;
  const ACallback: TProc<Boolean>): Integer;
var
  LSocketSendQueue: TList<PSendItem>;
  LSendItem: PSendItem;

  procedure _Failed;
  begin
    System.TMonitor.Enter(LSocketSendQueue);
    try
      _ClearSendQueue(LSocketSendQueue);
    finally
      System.TMonitor.Exit(LSocketSendQueue);
    end;

    if Assigned(ACallback) then
      ACallback(False);

    if (TSocketAPI.CloseSocket(ASocket) = 0) then
      TriggerDisconnected(ASocket);
  end;

begin
  // 获取Socket发送队列
  System.TMonitor.Enter(FSendQueue);
  try
    if not FSendQueue.TryGetValue(ASocket, LSocketSendQueue) then
    begin
      LSocketSendQueue := TList<PSendItem>.Create;
      FSendQueue.AddOrSetValue(ASocket, LSocketSendQueue);
    end;
  finally
    System.TMonitor.Exit(FSendQueue);
  end;

  // 将要发送的数据及回调放入Socket发送队列中
  LSendItem := System.New(PSendItem);
  LSendItem.Data := @ABuf;
  LSendItem.Size := ALen;
  LSendItem.Callback := ACallback;
  System.TMonitor.Enter(LSocketSendQueue);
  try
    LSocketSendQueue.Add(LSendItem);
  finally
    System.TMonitor.Exit(LSocketSendQueue);
  end;

  // 监视 EVFILT_WRITE, 当该事件触发时表明网卡发送缓存有空闲空间了
  // 到该事件代码中执行实际的发送动作
  if not _KqueueCtl(EV_ADD or EV_ONESHOT, ASocket, EVFILT_WRITE, kqWrite) then
  begin
    _Failed;
    Exit(-1);
  end;

  Result := ALen;
end;

function TKqueueLoop.ProcessIoEvent: Boolean;
  procedure _HandleAccept(ASocket: THandle; APerIoData: PPerIoData);
  var
    LRet: Integer;
    LSocket: THandle;
  begin
    while True do
    begin
      LRet := TSocketAPI.Accept(ASocket, nil, nil);

      // Accept失败
      // EAGAIN 需要重试
      // EMFILE 进程的文件句柄已经用完了
      if (LRet <= 0) then
      begin
//        LRet := GetLastError;
//        Writeln('accept failed:', LRet);
        Break;
      end;

      LSocket := LRet;
      TSocketAPI.SetNonBlock(LSocket, True);
      TSocketAPI.SetReUseAddr(LSocket, True);
      SetKeepAlive(LSocket);
      SetNoSigPipe(LSocket);

      // 连接建立后监视新Socket的读事件
      if not _KqueueCtl(EV_ADD or EV_CLEAR or EV_DISPATCH, LSocket, EVFILT_READ, kqRead) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        TSocketAPI.CloseSocket(LSocket);
        Continue;
      end;

      TriggerConnected(LSocket, CT_ACCEPT);
    end;

    // 重新激活 EVFILT_READ, 以继续接收新连接
    if not _KqueueCtl(EV_ENABLE or EV_CLEAR or EV_DISPATCH, ASocket, EVFILT_READ, kqAccept) then
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}
      TSocketAPI.CloseSocket(ASocket)
    end;
  end;

  procedure _HandleRead(ASocket: THandle; ACount: Integer; APerIoData: PPerIoData);
  var
    LRcvd: Integer;
  begin
    // 对方主动断开连接
    if (ACount <= 0) then
    begin
      if (TSocketAPI.CloseSocket(ASocket) = 0) then
        TriggerDisconnected(ASocket);
      Exit;
    end;

    while (ACount > 0) do
    begin
      LRcvd := TSocketAPI.Recv(ASocket, FRecvBuf[0], RCV_BUF_SIZE);

      // 对方主动断开连接
      if (LRcvd = 0) then
      begin
        if (TSocketAPI.CloseSocket(ASocket) = 0) then
          TriggerDisconnected(ASocket);
        Break;
      end;

      if (LRcvd < 0) then
      begin
        // 需要重试
        if _Again(GetLastError) then Break;

        if (TSocketAPI.CloseSocket(ASocket) = 0) then
          TriggerDisconnected(ASocket);

        Exit;
      end;

      TriggerReceived(ASocket, @FRecvBuf[0], LRcvd);

      if (LRcvd < RCV_BUF_SIZE) then Break;

      Dec(ACount, LRcvd);
    end;

    // 重新激活 EVFILT_READ, 以继续接收新数据
    if not _KqueueCtl(EV_ENABLE or EV_CLEAR or EV_DISPATCH, ASocket, EVFILT_READ, kqRead, nil) then
    begin
      if (TSocketAPI.CloseSocket(ASocket) = 0) then
        TriggerDisconnected(ASocket);
    end;
  end;

  procedure _HandleConnect(ASocket: THandle; APerIoData: PPerIoData);
    procedure _Success;
    begin
      if Assigned(APerIoData.Callback) then
        APerIoData.Callback(True);

      TriggerConnected(ASocket, CT_CONNECT);
    end;

    procedure _Failed;
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}
      TSocketAPI.CloseSocket(ASocket);

      if Assigned(APerIoData.Callback) then
        APerIoData.Callback(False);

      TriggerConnectFailed(ASocket);
    end;
  begin
    // Connect失败
    if (TSocketAPI.GetError(ASocket) <> 0) then
    begin
      _Failed;
      Exit;
    end;

    _Success;

    // 连接成功, 增加读事件
    if not _KqueueCtl(EV_ADD or EV_CLEAR or EV_DISPATCH, ASocket, EVFILT_READ, kqRead, nil) then
    begin
      _Failed;
      Exit;
    end;
  end;

  procedure _HandleWrite(ASocket: THandle; APerIoData: PPerIoData);
  var
    LSocketSendQueue: TList<PSendItem>;
    LSendItem: PSendItem;
    LSent: Integer;
    LCallback: TProc<Boolean>;

    function _WriteContinue: Boolean;
    begin
      Result := _KqueueCtl(EV_ADD or EV_ONESHOT, ASocket, EVFILT_WRITE, kqWrite);
      if not Result then
      begin
        // 关闭Socket
        if (TSocketAPI.CloseSocket(ASocket) = 0) then
          TriggerDisconnected(ASocket);
      end;
    end;

    procedure _Failed;
    begin
      // 调用回调
      if Assigned(LCallback) then
        LCallback(False);
    end;

    procedure _Success;
    begin
      // 发送成功, 移除已发送成功的数据
      System.Dispose(LSendItem);
      if (LSocketSendQueue.Count > 0) then
        LSocketSendQueue.Delete(0);

      // 如果队列中还有数据, 继续发送
      if (LSocketSendQueue.Count > 0) then
        _WriteContinue;

      // 调用回调
      if Assigned(LCallback) then
        LCallback(True);
    end;

  begin
    LCallback := nil;

    // 获取Socket发送队列
    if (FSendQueue = nil) then Exit;
    System.TMonitor.Enter(FSendQueue);
    try
      if not FSendQueue.TryGetValue(ASocket, LSocketSendQueue) then
        Exit;
    finally
      System.TMonitor.Exit(FSendQueue);
    end;

    // 获取Socket发送队列中的第一条数据
    if (LSocketSendQueue = nil) then Exit;
    System.TMonitor.Enter(LSocketSendQueue);
    try
      if (LSocketSendQueue.Count <= 0) then
        Exit;

      LSendItem := LSocketSendQueue.Items[0];
      LCallback := LSendItem.Callback;

      // 全部发送完成
      if (LSendItem.Size <= 0) then
      begin
        _Success;
        Exit;
      end;

      // 发送数据
      LSent := TSocketAPI.Send(ASocket, LSendItem.Data^, LSendItem.Size);

      // 发送成功
      if (LSent > 0) then
      begin
        Inc(LSendItem.Data, LSent);
        Dec(LSendItem.Size, LSent);
      end else
      // 连接断开或发送错误
      if (LSent = 0) or not _Again(GetLastError) then
      begin
        if (TSocketAPI.CloseSocket(ASocket) = 0) then
          TriggerDisconnected(ASocket);
        _Failed;
        Exit;
      end;

      // 继续监听 EVFILT_WRITE 事件
      // EVFILT_WRITE 触发后继续发送
      if not _WriteContinue then
        _Failed;
    finally
      System.TMonitor.Exit(LSocketSendQueue);
    end;
  end;
var
  LRet, I: Integer;
  LEvent: TKEvent;
  LPerIoData: PPerIoData;
  LSocket: THandle;
begin
  LRet := kevent(FKqueueHandle, nil, 0, @FEventList[0], MAX_EVENT_COUNT, nil);
  if (LRet < 0) then
  begin
    LRet := GetLastError;
    Writeln('error:', LRet);
    // EINTR, kevent 调用被系统中断打断, 可以进行重试
    Exit(LRet = EINTR);
  end;

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];
    LPerIoData := LEvent.uData;

    if (LPerIoData = nil) then Continue;

    try
      LSocket := LPerIoData.Socket;

      // 异常事件
      if (LEvent.Flags and EV_ERROR <> 0) then
      begin
        Writeln('event:', IntToHex(LEvent.Filter), ' socket:', LPerIoData.Socket, ' flags:', IntToHex(LEvent.Flags), ' action:', Integer(LPerIoData.Action));

        if Assigned(LPerIoData.Callback) then
          LPerIoData.Callback(False);

        if (TSocketAPI.CloseSocket(LSocket) = 0) then
          TriggerDisconnected(LSocket);

        Continue;
      end;

      // 数据可读
      if (LEvent.Filter = EVFILT_READ) then
      begin
        case LPerIoData.Action of
          // 有新的客户端连接
          kqAccept: _HandleAccept(LSocket, LPerIoData);
        else
          // 收到新数据
          _HandleRead(LSocket, LEvent.Data, LPerIoData);
        end;
      end;

      // 数据可写
      if (LEvent.Filter = EVFILT_WRITE) then
      begin
        case LPerIoData.Action of
          // 连接成功
          kqConnect: _HandleConnect(LSocket, LPerIoData);
        else
          // 可以发送数据
          _HandleWrite(LSocket, LPerIoData);
        end;
      end;
    finally
      FreeIoData(LPerIoData);
    end;
  end;

  Result := True;
end;

end.
