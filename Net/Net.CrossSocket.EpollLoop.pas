{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.EpollLoop;

// Ubuntu桌面版下似乎有内存泄漏, 但是追查不到到底是哪部分代码造成的
// 甚至无法确定是delphi内置的rtl库还是我所写的代码引起的
// 通过 LeakCheck 库能粗略看出引起内存泄漏的是一个 AnsiString 变量
// 并不能定位到具体的代码
// 但是我自己的代码里根本没有任何地方定义或者使用过类似的变量
// 其它Linux发行版本尚未测试

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Posix.SysSocket, Posix.NetinetIn, Posix.UniStd, Posix.NetDB, Posix.Errno,
  Linux.epoll, Net.SocketAPI, Net.CrossSocket.EventLoop;

type
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
  TEpollLoop = class(TAbstractEventLoop)
  private const
    MAX_EVENT_COUNT = 64;
  private type
    TEpollAction = (epAccept, epConnect, epRead, epWrite);

    PPerIoData = ^TPerIoData;
    TPerIoData = record
      Action: TEpollAction;
      Socket: THandle;
      Callback: TProc<THandle, Boolean>;
    end;

    PSendItem = ^TSendItem;
    TSendItem = record
      Data: PByte;
      Size: Integer;
      Callback: TProc<THandle, Boolean>;
    end;
  private
    FEpollHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;
    FSendQueue: TObjectDictionary<THandle, TList<PSendItem>>;
    class threadvar FEventList: array [0..MAX_EVENT_COUNT-1] of TEPoll_Event;

    function NewIoData: PPerIoData;
    procedure FreeIoData(P: PPerIoData);

    function _EpollCtl(op, fd: Integer; events: Cardinal;
      act: TEpollAction; cb: TProc<THandle, Boolean> = nil): Boolean;

    procedure _ClearSendQueue(ASocketSendQueue: TList<PSendItem>);
    procedure _ClearAllSendQueue;
  protected
    procedure TriggerConnected(ASocket: THandle; AConnectType: Integer); override;
    procedure TriggerDisconnected(ASocket: THandle); override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    function Listen(const AHost: string; APort: Word;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; override;
    function Connect(const AHost: string; APort: Word;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; override;
    function Send(ASocket: THandle; const ABuf; ALen: Integer;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; override;

    function ProcessIoEvent: Boolean; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;
  end;

implementation

{ TEpollLoop }

constructor TEpollLoop.Create(AIoThreads: Integer);
begin
  inherited Create(AIoThreads);

  FSendQueue := TObjectDictionary<THandle, TList<PSendItem>>.Create([doOwnsValues]);
end;

destructor TEpollLoop.Destroy;
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

function TEpollLoop.NewIoData: PPerIoData;
begin
  System.New(Result);
  FillChar(Result^, SizeOf(TPerIoData), 0);
end;

procedure TEpollLoop.FreeIoData(P: PPerIoData);
begin
  System.Dispose(P);
end;

procedure TEpollLoop._ClearSendQueue(ASocketSendQueue: TList<PSendItem>);
var
  LSendItem: PSendItem;
begin
  for LSendItem in ASocketSendQueue do
    System.Dispose(LSendItem);

  ASocketSendQueue.Clear;
end;

procedure TEpollLoop._ClearAllSendQueue;
var
  LPair: TPair<THandle, TList<PSendItem>>;
begin
  for LPair in FSendQueue do
    _ClearSendQueue(LPair.Value);

  FSendQueue.Clear;
end;

function TEpollLoop._EpollCtl(op, fd: Integer; events: Cardinal;
  act: TEpollAction; cb: TProc<THandle, Boolean>): Boolean;
var
  LEvent: TEPoll_Event;
  LPerIoData: PPerIoData;
begin
  LPerIoData := NewIoData;
  LPerIoData.Action := act;
  LPerIoData.Socket := fd;
  LPerIoData.Callback := cb;

  LEvent.Events := events;
  LEvent.Data.ptr := LPerIoData;
  if (epoll_ctl(FEpollHandle, op, fd, @LEvent) < 0) then
  begin
    FreeIoData(LPerIoData);
    Exit(False);
  end;

  Result := True;
end;

procedure TEpollLoop.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  // epoll_create(size)
  // 这个 size 只要传递大于0的任何值都可以
  // 并不是说队列的大小会受限于该值
  // http://man7.org/linux/man-pages/man2/epoll_create.2.html
  FEpollHandle := epoll_create(MAX_EVENT_COUNT);
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    FIoThreads[I] := TIoEventThread.Create(Self);
  end;
end;

procedure TEpollLoop.StopLoop;
var
  I: Integer;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (FListensCount > 0) or (FConnectionsCount > 0) do Sleep(1);

  Posix.UniStd.__close(FEpollHandle);

  for I := 0 to Length(FIoThreads) - 1 do
  begin
    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;
end;

procedure TEpollLoop.TriggerConnected(ASocket: THandle; AConnectType: Integer);
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

procedure TEpollLoop.TriggerDisconnected(ASocket: THandle);
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

function TEpollLoop.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<THandle, Boolean>): Integer;
  procedure _Failed1;
  begin
    {$IFDEF DEBUG}
    __RaiseLastOSError;
    {$ENDIF}

    TriggerConnectFailed(INVALID_HANDLE_VALUE);

    if Assigned(ACallback) then
      ACallback(INVALID_HANDLE_VALUE, False);
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
        ACallback(ASocket, False);
    end;
  begin
    if (TSocketAPI.Connect(ASocket, Addr.ai_addr, Addr.ai_addrlen) = 0)
      or (GetLastError = EINPROGRESS) then
    begin
      // EPOLLOUT 只用作判断 Connect 成功与否
      if not _EpollCtl(EPOLL_CTL_ADD, ASocket, EPOLLOUT or EPOLLONESHOT or EPOLLET, epConnect, ACallback) then
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

      if _Connect(LSocket, LAddrInfo) then Exit(0);

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;

  _Failed1;
  Result := -1;
end;

function TEpollLoop.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<THandle, Boolean>): Integer;
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;

  procedure _Failed;
  begin
    if (LSocket <> INVALID_HANDLE_VALUE) then
      TSocketAPI.CloseSocket(LSocket);

    if Assigned(ACallback) then
      ACallback(LSocket, False);
  end;

  procedure _Success;
  begin
    TriggerListened(LSocket);

    if Assigned(ACallback) then
      ACallback(LSocket, True);
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

      // 监听套接字的读事件
      // 读事件到达表明有新连接
      if not _EpollCtl(EPOLL_CTL_ADD, LSocket, EPOLLIN or EPOLLONESHOT or EPOLLET, epAccept) then
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

function TEpollLoop.Send(ASocket: THandle; const ABuf; ALen: Integer;
  const ACallback: TProc<THandle, Boolean>): Integer;
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
      ACallback(ASocket, False);

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

  // 监视 EPOLLOUT, 当该事件触发时表明网卡发送缓存有空闲空间了
  // 到该事件代码中执行实际的发送动作
  if not _EpollCtl(EPOLL_CTL_MOD, ASocket, EPOLLOUT or EPOLLONESHOT or EPOLLET, epWrite) then
  begin
    _Failed;
    Exit(-1);
  end;

  Result := ALen;
end;

function TEpollLoop.ProcessIoEvent: Boolean;
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

      TriggerConnected(LSocket, CT_ACCEPT);

      // 连接建立后监视新Socket的读事件
      if not _EpollCtl(EPOLL_CTL_ADD, LSocket, EPOLLIN or EPOLLONESHOT or EPOLLET, epRead) then
      begin
        {$IFDEF DEBUG}
        __RaiseLastOSError;
        {$ENDIF}
        if (TSocketAPI.CloseSocket(LSocket) = 0) then
          TriggerDisconnected(LSocket);
        Continue;
      end;
    end;

    // 重新激活 EPOLLIN, 以继续接收新连接
    if not _EpollCtl(EPOLL_CTL_MOD, ASocket, EPOLLIN or EPOLLONESHOT or EPOLLET, epAccept) then
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}
      TSocketAPI.CloseSocket(ASocket);
    end;
  end;

  procedure _HandleRead(ASocket: THandle; APerIoData: PPerIoData);
  var
    LRcvd: Integer;
  begin
    while True do
    begin
      LRcvd := TSocketAPI.Recv(ASocket, FRecvBuf[0], RCV_BUF_SIZE, MSG_NOSIGNAL);

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
    end;

    // 重新激活 EPOLLIN 和 EPOLLOUT, 以继续接收或发送新数据
    // 这里必须同时监视 EPOLLIN 和 EPOLLOUT, 因为在 TriggerReceived 中如果执行了
    // 发送数据的操作, 正好该操作还没来得及触发 epoll_wait, 那么到这里如果只监视
    // EPOLLIN, 就会导致待发送的数据无法被发送
    // 只有在 _HandleRead 中有必要这样做
    if not _EpollCtl(EPOLL_CTL_MOD, ASocket, EPOLLIN or EPOLLOUT or EPOLLONESHOT or EPOLLET, epRead) then
    begin
      if (TSocketAPI.CloseSocket(ASocket) = 0) then
        TriggerDisconnected(ASocket);
    end;
  end;

  procedure _HandleConnect(ASocket: THandle; APerIoData: PPerIoData);
    procedure _Success;
    begin
      TriggerConnected(ASocket, CT_CONNECT);

      if Assigned(APerIoData.Callback) then
        APerIoData.Callback(ASocket, True);
    end;

    procedure _Failed1;
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}

      TSocketAPI.CloseSocket(ASocket);
      TriggerConnectFailed(ASocket);

      if Assigned(APerIoData.Callback) then
        APerIoData.Callback(ASocket, False);
    end;

    procedure _Failed2;
    begin
      {$IFDEF DEBUG}
      __RaiseLastOSError;
      {$ENDIF}

      if (TSocketAPI.CloseSocket(ASocket) = 0) then
        TriggerDisconnected(ASocket);

      if Assigned(APerIoData.Callback) then
        APerIoData.Callback(ASocket, False);
    end;
  begin
    // Connect失败
    if (TSocketAPI.GetError(ASocket) <> 0) then
    begin
      _Failed1;
      Exit;
    end;

    _Success;

    // 连接成功, 监听读事件
    if not _EpollCtl(EPOLL_CTL_MOD, ASocket, EPOLLIN or EPOLLONESHOT or EPOLLET, epRead) then
    begin
      _Failed2;
      Exit;
    end;
  end;

  procedure _HandleWrite(ASocket: THandle; APerIoData: PPerIoData);
  var
    LSocketSendQueue: TList<PSendItem>;
    LSendItem: PSendItem;
    LSent: Integer;
    LCallback: TProc<THandle, Boolean>;

    procedure _ReadContinue;
    begin
      if not _EpollCtl(EPOLL_CTL_MOD, ASocket, EPOLLIN or EPOLLONESHOT or EPOLLET, epRead) then
      begin
        if (TSocketAPI.CloseSocket(ASocket) = 0) then
          TriggerDisconnected(ASocket);
      end;
    end;

    function _WriteContinue: Boolean;
    begin
      Result := _EpollCtl(EPOLL_CTL_MOD, ASocket, EPOLLOUT or EPOLLONESHOT or EPOLLET, epWrite);
      if not Result then
      begin
        if (TSocketAPI.CloseSocket(ASocket) = 0) then
          TriggerDisconnected(ASocket);
      end;
    end;

    procedure _Failed;
    begin
      // 调用回调
      if Assigned(LCallback) then
        LCallback(ASocket, False);
    end;

    procedure _Success;
    begin
      // 发送成功, 移除已发送成功的数据
      System.Dispose(LSendItem);
      if (LSocketSendQueue.Count > 0) then
        LSocketSendQueue.Delete(0);

      // 如果队列中还有数据, 继续发送
      if (LSocketSendQueue.Count > 0) then
        _WriteContinue
      else
        _ReadContinue;

      // 调用回调
      if Assigned(LCallback) then
        LCallback(ASocket, True);
    end;

  begin
    LCallback := nil;

    if (FSendQueue = nil) then
    begin
      _ReadContinue;
      Exit;
    end;

    // 获取Socket发送队列
    System.TMonitor.Enter(FSendQueue);
    try
      if not FSendQueue.TryGetValue(ASocket, LSocketSendQueue) then
      begin
        // 继续监听读事件
        _ReadContinue;
        Exit;
      end;
    finally
      System.TMonitor.Exit(FSendQueue);
    end;

    if (LSocketSendQueue = nil) then
    begin
      _ReadContinue;
      Exit;
    end;

    // 获取Socket发送队列中的第一条数据
    System.TMonitor.Enter(LSocketSendQueue);
    try
      if (LSocketSendQueue.Count <= 0) then
      begin
        // 继续监听读事件
        _ReadContinue;
        Exit;
      end;

      LSendItem := LSocketSendQueue.Items[0];
      LCallback := LSendItem.Callback;

      // 全部发送完成
      if (LSendItem.Size <= 0) then
      begin
        _Success;
        Exit;
      end;

      // 发送数据
      LSent := TSocketAPI.Send(ASocket, LSendItem.Data^, LSendItem.Size, MSG_NOSIGNAL);

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

      // 继续监听 EPOLLOUT 事件
      // EPOLLOUT 触发后继续发送
      if not _WriteContinue then
        _Failed;
    finally
      System.TMonitor.Exit(LSocketSendQueue);
    end;
  end;
var
  LRet, I: Integer;
  LEvent: TEPoll_Event;
  LSocket: THandle;
  LPerIoData: PPerIoData;
begin
  // 如果不指定超时时间, 即使在其它线程将 epoll 句柄关闭, epoll_wait 也不会返回
  LRet := epoll_wait(FEpollHandle, @FEventList[0], MAX_EVENT_COUNT, 100);
  if (LRet < 0) then
  begin
    LRet := GetLastError;
//    Writeln('error:', LRet);
    // EINTR, epoll_wait 调用被系统中断打断, 可以进行重试
    Exit(LRet = EINTR);
  end;

  for I := 0 to LRet - 1 do
  begin
    LEvent := FEventList[I];
    LPerIoData := LEvent.Data.ptr;

    // 异常事件
    if (LEvent.Events and EPOLLERR <> 0) or (LPerIoData = nil) then
    begin
//      Writeln('EPOLLERR, event:', IntToHex(LEvent.Events), ' data:', LEvent.Data.u64);

      if (LPerIoData <> nil) and ((LEvent.Events and EPOLLIN <> 0) or (LEvent.Events and EPOLLOUT <> 0)) then
      begin
        try
          if Assigned(LPerIoData.Callback) then
            LPerIoData.Callback(LSocket, False);

          if (TSocketAPI.CloseSocket(LSocket) = 0) then
            TriggerDisconnected(LSocket);
        finally
          FreeIoData(LPerIoData);
        end;
      end;

      Continue;
    end;

    try
      LSocket := LPerIoData.Socket;

      // 数据可读
      if (LEvent.Events and EPOLLIN <> 0) then
      begin
        case LPerIoData.Action of
          // 有新的客户端连接
          epAccept: _HandleAccept(LSocket, LPerIoData);
        else
          // 收到新数据
          _HandleRead(LSocket, LPerIoData);
        end;
      end;

      // 数据可写
      if (LEvent.Events and EPOLLOUT <> 0) then
      begin
        case LPerIoData.Action of
          // 连接成功
          epConnect: _HandleConnect(LSocket, LPerIoData);
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
