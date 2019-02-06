{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Iocp;

interface

{$IF defined(MSWINDOWS)}

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Net.Winsock2,
  Net.Wship6,
  Net.SocketAPI,
  Net.CrossSocket.Base;

type
  TIocpListen = class(TAbstractCrossListen)
  end;

  TIocpConnection = class(TAbstractCrossConnection)
  end;

  TIocpCrossSocket = class(TAbstractCrossSocket)
  private const
    SHUTDOWN_FLAG = ULONG_PTR(-1);
    SO_UPDATE_CONNECT_CONTEXT = $7010;
    IPV6_V6ONLY = 27;
    ERROR_ABANDONED_WAIT_0 = $02DF;
  private type
    TAddrUnion = record
      case Integer of
        0: (IPv4: TSockAddrIn);
        1: (IPv6: TSockAddrIn6);
    end;

    TAddrBuffer = record
      Addr: TAddrUnion;
      Extra: array [0..15] of Byte;
    end;

    TAcceptExBuffer = array[0..SizeOf(TAddrBuffer) * 2 - 1] of Byte;

    TPerIoBufUnion = record
      case Integer of
        0: (DataBuf: WSABUF);
        // This Buffer is only used to save the terminal address data in AcceptEx, the size is 2 times the address structure.
        1: (AcceptExBuffer: TAcceptExBuffer);
    end;

    TIocpAction = (ioAccept, ioConnect, ioRead, ioWrite);

    PPerIoData = ^TPerIoData;
    TPerIoData = record
      Overlapped: TWSAOverlapped;
      Buffer: TPerIoBufUnion;
      Action: TIocpAction;
      Socket: THandle;
      CrossData: ICrossData;
      Callback: TProc<ICrossConnection, Boolean>;
    end;
  private
    FIocpHandle: THandle;
    FIoThreads: TArray<TIoEventThread>;

    function _NewIoData: PPerIoData; inline;
    procedure _FreeIoData(P: PPerIoData); inline;

    procedure _NewAccept(AListen: ICrossListen);
    function _NewReadZero(AConnection: ICrossConnection): Boolean;

    procedure _HandleAccept(APerIoData: PPerIoData);
    procedure _HandleConnect(APerIoData: PPerIoData);
    procedure _HandleRead(APerIoData: PPerIoData);
    procedure _HandleWrite(APerIoData: PPerIoData);
  protected
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;

    procedure StartLoop; override;
    procedure StopLoop; override;

    procedure Listen(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossListen, Boolean> = nil); override;

    procedure Connect(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;

    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;

    function ProcessIoEvent: Boolean; override;
  end;

implementation

{ TIocpCrossSocket }

function TIocpCrossSocket._NewIoData: PPerIoData;
begin
  System.New(Result);
  FillChar(Result^, SizeOf(TPerIoData), 0);
end;

procedure TIocpCrossSocket._FreeIoData(P: PPerIoData);
begin
  P.CrossData := nil;
  System.Dispose(P);
end;

procedure TIocpCrossSocket._NewAccept(AListen: ICrossListen);
var
  LClientSocket: THandle;
  LPerIoData: PPerIoData;
  LBytes: Cardinal;
begin
  LClientSocket := WSASocket(AListen.Family, AListen.SockType, AListen.Protocol,
    nil, 0, WSA_FLAG_OVERLAPPED);
  if (LClientSocket = INVALID_SOCKET) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._NewAccept.WSASocket');
    {$ENDIF}
    Exit;
  end;

  TSocketAPI.SetNonBlock(LClientSocket, True);
  SetKeepAlive(LClientSocket);

  LPerIoData := _NewIoData;
  LPerIoData.Action := ioAccept;
  LPerIoData.Socket := LClientSocket;
  LPerIoData.CrossData := AListen;
  if (not AcceptEx(AListen.Socket, LClientSocket, @LPerIoData.Buffer.AcceptExBuffer, 0,
    SizeOf(TAddrBuffer), SizeOf(TAddrBuffer), LBytes, POverlapped(LPerIoData)))
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._NewAccept.AcceptEx');
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    _FreeIoData(LPerIoData);
  end;
end;

function TIocpCrossSocket._NewReadZero(AConnection: ICrossConnection): Boolean;
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := _NewIoData;
  LPerIoData.Buffer.DataBuf.buf := nil;
  LPerIoData.Buffer.DataBuf.len := 0;
  LPerIoData.Action := ioRead;
  LPerIoData.Socket := AConnection.Socket;
  LPerIoData.CrossData := AConnection;

  LFlags := 0;
  LBytes := 0;
  if (WSARecv(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._NewReadZero.WSARecv');
    {$ENDIF}
    _FreeIoData(LPerIoData);
    Exit(False);
  end;

  Result := True;
end;

procedure TIocpCrossSocket._HandleAccept(APerIoData: PPerIoData);
var
  LListen: ICrossListen;
  LConnection: ICrossConnection;
  LClientSocket, LListenSocket: THandle;
begin
  LListen := APerIoData.CrossData as ICrossListen;
  _NewAccept(LListen);

  LClientSocket := APerIoData.Socket;
  LListenSocket := LListen.Socket;

  // Do not set this parameter, will cause the getpeername call to fail
  if (TSocketAPI.SetSockOpt<THandle>(LClientSocket, SOL_SOCKET,
    SO_UPDATE_ACCEPT_CONTEXT, LListenSocket) < 0) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleAccept.SetSockOpt');
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    Exit;
  end;

  if (CreateIoCompletionPort(LClientSocket, FIocpHandle, ULONG_PTR(LClientSocket), 0) = 0) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleAccept.CreateIoCompletionPort');
    {$ENDIF}
    TSocketAPI.CloseSocket(LClientSocket);
    Exit;
  end;

  LConnection := CreateConnection(Self, LClientSocket, ctAccept);
  TriggerConnecting(LConnection);
  TriggerConnected(LConnection);

  if not _NewReadZero(LConnection) then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleConnect(APerIoData: PPerIoData);
var
  LClientSocket: THandle;
  LConnection: ICrossConnection;
  LSuccess: Boolean;

  procedure _Failed1;
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket._HandleConnect');
    {$ENDIF}

    TSocketAPI.CloseSocket(LClientSocket);

    if Assigned(APerIoData.Callback) then
      APerIoData.Callback(nil, False);
  end;
begin
  LClientSocket := APerIoData.Socket;

  if (TSocketAPI.GetError(LClientSocket) <> 0) then
  begin
    _Failed1;
    Exit;
  end;

  // Do not set this parameter, will cause the getpeername call to fail
  if (TSocketAPI.SetSockOpt<Integer>(LClientSocket, SOL_SOCKET,
    SO_UPDATE_CONNECT_CONTEXT, 1) < 0) then
  begin
    _Failed1;
    Exit;
  end;

  LConnection := CreateConnection(Self, LClientSocket, ctConnect);
  TriggerConnecting(LConnection);

  LSuccess := _NewReadZero(LConnection);
  if LSuccess then
    TriggerConnected(LConnection)
  else
    LConnection.Close;

  if Assigned(APerIoData.Callback) then
    APerIoData.Callback(LConnection, LSuccess);
end;

procedure TIocpCrossSocket._HandleRead(APerIoData: PPerIoData);
var
  LConnection: ICrossConnection;
  LRcvd, LError: Integer;
begin
  LConnection := APerIoData.CrossData as ICrossConnection;

  while True do
  begin
    LRcvd := TSocketAPI.Recv(LConnection.Socket, FRecvBuf[0], RCV_BUF_SIZE);

    // The other party actively disconnects
    if (LRcvd = 0) then
    begin
      LConnection.Close;
      Exit;
    end;

    if (LRcvd < 0) then
    begin
      LError := GetLastError;

      // Interrupted by the system signal, you can re-recv
      if (LError = WSAEINTR) then
        Continue
      // The data in the receive buffer has been fetched.
      else if (LError = WSAEWOULDBLOCK) or (LError = WSAEINPROGRESS) then
        Break
      // Receive error
      else
      begin
        LConnection.Close;
        Exit;
      end;
    end;

    TriggerReceived(LConnection, @FRecvBuf[0], LRcvd);

    if (LRcvd < RCV_BUF_SIZE) then Break;
  end;

  if not _NewReadZero(LConnection) then
    LConnection.Close;
end;

procedure TIocpCrossSocket._HandleWrite(APerIoData: PPerIoData);
begin
  if Assigned(APerIoData.Callback) then
    APerIoData.Callback(APerIoData.CrossData as ICrossConnection, True);
end;

procedure TIocpCrossSocket.StartLoop;
var
  I: Integer;
begin
  if (FIoThreads <> nil) then Exit;

  FIocpHandle := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  SetLength(FIoThreads, GetIoThreads);
  for I := 0 to Length(FIoThreads) - 1 do
    FIoThreads[I] := TIoEventThread.Create(Self);
end;

procedure TIocpCrossSocket.StopLoop;
var
  I: Integer;
  LCurrentThreadID: TThreadID;
begin
  if (FIoThreads = nil) then Exit;

  CloseAll;

  while (ListensCount > 0) or (ConnectionsCount > 0) do Sleep(1);

  for I := 0 to Length(FIoThreads) - 1 do
    PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));

  LCurrentThreadID := GetCurrentThreadId;
  for I := 0 to Length(FIoThreads) - 1 do
  begin
    if (FIoThreads[I].ThreadID = LCurrentThreadID) then
      raise ECrossSocket.Create('Cannot execute StopLoop in IO thread!');

    FIoThreads[I].WaitFor;
    FreeAndNil(FIoThreads[I]);
  end;
  FIoThreads := nil;

  CloseHandle(FIocpHandle);
end;

procedure TIocpCrossSocket.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LSocket: THandle;

  procedure _Failed1;
  begin
    if Assigned(ACallback) then
      ACallback(nil, False);
  end;

  function _Connect(ASocket: THandle; AAddr: PRawAddrInfo): Boolean;
    procedure _Failed2;
    begin
      TSocketAPI.CloseSocket(ASocket);
      if Assigned(ACallback) then
        ACallback(nil, False);
    end;
  var
    LSockAddr: TRawSockAddrIn;
    LPerIoData: PPerIoData;
    LBytes: Cardinal;
  begin
    LSockAddr.AddrLen := AAddr.ai_addrlen;
    Move(AAddr.ai_addr^, LSockAddr.Addr, AAddr.ai_addrlen);
    if (AAddr.ai_family = AF_INET6) then
    begin
      LSockAddr.Addr6.sin6_addr := in6addr_any;
      LSockAddr.Addr6.sin6_port := 0;
    end else
    begin
      LSockAddr.Addr.sin_addr.S_addr := INADDR_ANY;
      LSockAddr.Addr.sin_port := 0;
    end;
    if (TSocketAPI.Bind(ASocket, @LSockAddr.Addr, LSockAddr.AddrLen) < 0) then
    begin
      _Failed2;
      Exit(False);
    end;

    if (CreateIoCompletionPort(ASocket, FIocpHandle, ULONG_PTR(ASocket), 0) = 0) then
    begin
      _Failed2;
      Exit(False);
    end;

    LPerIoData := _NewIoData;
    LPerIoData.Action := ioConnect;
    LPerIoData.Socket := ASocket;
    LPerIoData.Callback := ACallback;
    if not ConnectEx(ASocket, AAddr.ai_addr, AAddr.ai_addrlen, nil, 0, LBytes, PWSAOverlapped(LPerIoData)) and
      (WSAGetLastError <> WSA_IO_PENDING) then
    begin
      _FreeIoData(LPerIoData);
      _Failed2;
      Exit(False);
    end;

    Result := True;
  end;

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
      LSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
      if (LSocket = INVALID_SOCKET) then
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

function TIocpCrossSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TIocpConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TIocpCrossSocket.CreateListen(AOwner: ICrossSocket;
  AListenSocket: THandle; AFamily, ASockType, AProtocol: Integer): ICrossListen;
begin
  Result := TIocpListen.Create(AOwner, AListenSocket, AFamily, ASockType, AProtocol);
end;

procedure TIocpCrossSocket.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<ICrossListen, Boolean>);
var
  LHints: TRawAddrInfo;
  P, LAddrInfo: PRawAddrInfo;
  LListenSocket: THandle;
  LListen: ICrossListen;
  I: Integer;

  procedure _Failed;
  begin
    if (LListen <> nil) then
      LListen.Close;

    if Assigned(ACallback) then
      ACallback(LListen, False);
  end;

  procedure _Success;
  begin
    TriggerListened(LListen);

    if Assigned(ACallback) then
      ACallback(LListen, True);
  end;
begin
  LListen := nil;
  FillChar(LHints, SizeOf(TRawAddrInfo), 0);

  LHints.ai_flags := AI_PASSIVE;
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  if (LAddrInfo = nil) then
  begin
    {$IFDEF DEBUG}
    _LogLastOsError('TIocpCrossSocket.Listen.GetAddrInfo');
    {$ENDIF}
    _Failed;
    Exit;
  end;

  P := LAddrInfo;
  try
    while (LAddrInfo <> nil) do
    begin
      LListenSocket := WSASocket(LAddrInfo.ai_family, LAddrInfo.ai_socktype,
        LAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
      if (LListenSocket = INVALID_SOCKET) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TIocpCrossSocket.Listen.WSASocket');
        {$ENDIF}
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
        {$IFDEF DEBUG}
        _LogLastOsError('TIocpCrossSocket.Listen.Bind');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      LListen := CreateListen(Self, LListenSocket, LAddrInfo.ai_family,
        LAddrInfo.ai_socktype, LAddrInfo.ai_protocol);

      if (CreateIoCompletionPort(LListenSocket, FIocpHandle, ULONG_PTR(LListenSocket), 0) = 0) then
      begin
        {$IFDEF DEBUG}
        _LogLastOsError('TIocpCrossSocket.Listen.CreateIoCompletionPort');
        {$ENDIF}
        _Failed;
        Exit;
      end;

      // Deliver an AcceptEx to each IO thread
      for I := 1 to GetIoThreads do
        _NewAccept(LListen);

      _Success;

      // If the port passes 0, let all addresses be unified with the first assigned port
      if (APort = 0) and (LAddrInfo.ai_next <> nil) then
        LAddrInfo.ai_next.ai_addr.sin_port := LListen.LocalPort;

      LAddrInfo := PRawAddrInfo(LAddrInfo.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(P);
  end;
end;

procedure TIocpCrossSocket.Send(AConnection: ICrossConnection; ABuf: Pointer;
  ALen: Integer; const ACallback: TProc<ICrossConnection, Boolean>);
var
  LPerIoData: PPerIoData;
  LBytes, LFlags: Cardinal;
begin
  LPerIoData := _NewIoData;
  LPerIoData.Buffer.DataBuf.buf := ABuf;
  LPerIoData.Buffer.DataBuf.len := ALen;
  LPerIoData.Action := ioWrite;
  LPerIoData.Socket := AConnection.Socket;
  LPerIoData.CrossData := AConnection;
  LPerIoData.Callback := ACallback;

  LFlags := 0;
  LBytes := 0;
  // WSASend will not be partially sent, either fail or all succeed
  // So you don’t need to check the actual number sent after calling the call like kqueue or epoll
  // The only thing to note is that WSASend will lock the data to be sent to non-page memory, non-page memory resources.
  // is very nervous, so don't call WSASend in an uncontrolled way, it is best to send a batch of data through the callback and then continue
  // Continue to send the next batch
  if (WSASend(AConnection.Socket, @LPerIoData.Buffer.DataBuf, 1, LBytes, LFlags, PWSAOverlapped(LPerIoData), nil) < 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    // Most of the errors are WSAENOBUFS, that is, too many WSASends are delivered, too late to send
    // Causes all non-page memory resources to be locked. To avoid this, the upper layer must be sent logic.
    // Ensure that you can not send Send a large amount of data in an uncontrolled way, it is best to send one and then continue
    // One, this function provides a callback function that sends the result, and the callback function report is sent successfully.
    // After that, you can continue to send the next piece of data.
    _FreeIoData(LPerIoData);
    AConnection.Close;

    if Assigned(ACallback) then
      ACallback(AConnection, False);
  end;
end;

function TIocpCrossSocket.ProcessIoEvent: Boolean;
var
  LBytes: Cardinal;
  LSocket: THandle;
  LPerIoData: PPerIoData;
  {$IFDEF DEBUG}
  LErrNo: Cardinal;
  {$ENDIF}
begin
  if not GetQueuedCompletionStatus(FIocpHandle, LBytes, ULONG_PTR(LSocket), POverlapped(LPerIoData), INFINITE) then
  begin
    // An error has occurred, and the completion data is also empty.
    // This situation should continue to go wrong even if you try again, it is best to terminate the IO thread immediately.
    if (LPerIoData = nil) then
    begin
      {$IFDEF DEBUG}
      LErrNo := GetLastError;
      // ERROR_INVALID_HANDLE and ERROR_ABANDONED_WAIT_0 may be triggered when the port is closed
      if (LErrNo <> ERROR_INVALID_HANDLE)
        and (LErrNo <> ERROR_ABANDONED_WAIT_0)
      then
        _LogLastOsError('TIocpCrossSocket.ProcessIoEvent.GetQueuedCompletionStatus');
      {$ENDIF}
      Exit(False);
    end;

    try
      // WSA_OPERATION_ABORTED, 995, I/O operation has been aborted due to thread exit or application request.
      // WSAENOTSOCK, 10038, tried an operation on a non-socket.
      // ERROR_NETNAME_DELETED, 64, the specified network name is no longer available
      // ERROR_CONNECTION_REFUSED, 1225, The remote computer rejects the network connection.
      if (LPerIoData.CrossData <> nil) then
      begin
        // If AcceptEx succeeds, but the Socket handle is exhausted, and the AcceptEx is delivered again.
        if (LPerIoData.Action = ioAccept) then
        begin
          // This error is triggered when the listener is turned off. This should not continue to be delivered.
          if (GetLastError <> WSA_OPERATION_ABORTED) then
            _NewAccept(LPerIoData.CrossData as ICrossListen);
        end else
        begin
          LPerIoData.CrossData.Close;
          if Assigned(LPerIoData.Callback)
            and (LPerIoData.CrossData is TIocpConnection) then
            LPerIoData.Callback(LPerIoData.CrossData as ICrossConnection, False);
        end;
      end else
      begin
        TSocketAPI.CloseSocket(LPerIoData.Socket);
        if Assigned(LPerIoData.Callback) then
          LPerIoData.Callback(nil, False);
      end;
    finally
      _FreeIoData(LPerIoData);
    end;

    // An error occurred, but the completion data is not empty and needs to be retried
    Exit(True);
  end;

  // Actively called StopLoop
  if (LBytes = 0) and (ULONG_PTR(LPerIoData) = SHUTDOWN_FLAG) then Exit(False);

  // The completion data was not obtained for unknown reasons, but the returned error code is normal again.
  // This situation needs to be retried (the IO thread will call ProcessIoEvent again after returning True)
  if (LPerIoData = nil) then Exit(True);

  try
    case LPerIoData.Action of
      ioAccept  : _HandleAccept(LPerIoData);
      ioConnect : _HandleConnect(LPerIoData);
      ioRead    : _HandleRead(LPerIoData);
      ioWrite   : _HandleWrite(LPerIoData);
    end;
  finally
    _FreeIoData(LPerIoData);
  end;

  Result := True;
end;

{$ELSE}
implementation
{$ENDIF}
end.
