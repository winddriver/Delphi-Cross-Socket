program ListenLifecycleTests;
{$I ../../../../zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  {$IFDEF MSWINDOWS}Windows, Net.Winsock2, Net.CrossSocket.Iocp,{$ENDIF}
  {$IF DEFINED(POSIX) AND DEFINED(DELPHI)}Posix.SysSocket, Posix.NetinetIn, Posix.NetDB,{$ENDIF}
  {$IF DEFINED(POSIX) AND DEFINED(FPC)}
  Sockets, {$IFDEF LINUX}cnetdb,{$ELSE}NetDB, DTF.RTL,{$ENDIF}
  {$ENDIF}
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket;

type
  TTestSocket = class;
  TStats = class
    Mode: string;
    Entered, Resume, Accepted, StopSnapshot: TEvent;
    Created, Destroyed, ConnectionsCreated, ConnectionsDestroyed: Integer;
    Calls, Successes, Failures, Accepts, Gates, Timeouts: Integer;
    StopRejected, OpenAfterReject, StopRequested: Integer;
    Port: Word;
    constructor Create;
    destructor Destroy; override;
  end;
  TTrackedListen = class(TCrossListen)
    destructor Destroy; override;
    procedure UpdateAddr; override;
  end;
  TTrackedConnection = class(TCrossConnection)
    destructor Destroy; override;
  end;
  TTestSocket = class(TCrossSocket)
  protected
    function CreateListen(const AOwner: TCrossSocketBase; const ASocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; override;
    function CreateConnection(const AOwner: TCrossSocketBase; const ASocket: TSocket;
      const AType: TConnectType; const AHost: string;
      const ACallback: TCrossConnectionCallback): ICrossConnection; override;
    procedure TriggerListened(const AListen: ICrossListen); override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    function ProcessIoEvent: Boolean; override;
    procedure CloseAllConnections; override;
  public
    procedure Gate;
    procedure BeginListen;
    procedure Stop;
    procedure Restart;
    function Pending: NativeInt;
  end;
  TStopThread = class(TThread)
    Socket: TTestSocket;
    Done: TEvent;
    CloseOnly: Boolean;
    ErrorText: string;
    procedure Execute; override;
  end;
  TListenThread = class(TThread)
    Socket: TTestSocket;
    ErrorText: string;
    procedure Execute; override;
  end;

var
  Stats: TStats;
  OutputLock: SyncObjs.TCriticalSection;

{$IFDEF MSWINDOWS}
var
  OriginalAccept: LPFN_ACCEPTEX;
  OriginalSetOption: LPFN_SETSOCKOPT;
  NativeAcceptCalls, NativeAcceptSubmitted: Integer;
  ContextCalls, ContextFailures: Integer;

function ObservedSetOption(const ASocket: TSocket; const ALevel, AName: Integer;
  AValue: PAnsiChar; const ALength: Integer): Integer; stdcall;
var
  LInvalid: TSocket;
begin
  if (Stats.Mode = 'accept-context-error') and (AName = SO_UPDATE_ACCEPT_CONTEXT)
    and (AtomicIncrement(ContextCalls) <= 2) then
  begin
    LInvalid := INVALID_SOCKET;
    Result := OriginalSetOption(ASocket, ALevel, AName, PAnsiChar(@LInvalid), SizeOf(LInvalid));
    if Result <> 0 then AtomicIncrement(ContextFailures);
  end else
    Result := OriginalSetOption(ASocket, ALevel, AName, AValue, ALength);
end;

function ObservedAccept(AListen, AClient: TSocket; ABuffer: Pointer;
  AReceiveLength, ALocalLength, ARemoteLength: DWORD; var ABytes: DWORD;
  AOverlapped: POverlapped): BOOL; stdcall;
var
  LCall, LError: Integer;
begin
  LCall := AtomicIncrement(NativeAcceptCalls);
  if (Stats.Mode = 'partial-accept-error') and (LCall = 2) then
    AListen := INVALID_SOCKET;
  Result := OriginalAccept(AListen, AClient, ABuffer, AReceiveLength,
    ALocalLength, ARemoteLength, ABytes, AOverlapped);
  LError := WSAGetLastError;
  if Result or (LError = WSA_IO_PENDING) then AtomicIncrement(NativeAcceptSubmitted);
  WSASetLastError(LError);
end;
{$ENDIF}

{$IFDEF LINUX}
function TestDup2(AFrom, ATo: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'dup2';
function TestOpen(APath: PAnsiChar; AFlags: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'open';
function TestClose(AFd: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'close';
{$ENDIF}

procedure Line(const AText: string);
begin
  OutputLock.Enter;
  try Writeln(AText); Flush(Output);
  finally OutputLock.Leave; end;
end;

procedure Check(const AValue: Boolean; const AText: string);
begin
  if not AValue then
  begin
    Line('FAIL ' + AText);
    // 旧版可能遗留内核仍持有的操作，失败进程直接退出，避免无效的析构展开。
    Halt(1);
  end;
end;

constructor TStats.Create;
begin
  inherited;
  Entered := TEvent.Create(nil, True, False, '');
  Resume := TEvent.Create(nil, True, False, '');
  Accepted := TEvent.Create(nil, False, False, '');
  StopSnapshot := TEvent.Create(nil, True, False, '');
end;

destructor TStats.Destroy;
begin
  Entered.Free; Resume.Free; Accepted.Free; StopSnapshot.Free;
  inherited;
end;

destructor TTrackedListen.Destroy;
begin
  try inherited;
  finally AtomicIncrement(Stats.Destroyed); end;
end;

procedure TTrackedListen.UpdateAddr;
begin
  if Stats.Mode = 'update-raises' then raise Exception.Create('test update failure');
  inherited;
end;

destructor TTrackedConnection.Destroy;
begin
  try inherited;
  finally AtomicIncrement(Stats.ConnectionsDestroyed); end;
end;

function TTestSocket.CreateListen(const AOwner: TCrossSocketBase; const ASocket: TSocket;
  const AFamily, ASockType, AProtocol: Integer): ICrossListen;
{$IFDEF LINUX}
var LNull: Integer;
{$ENDIF}
begin
  Result := TTrackedListen.Create(AOwner, ASocket, AFamily, ASockType, AProtocol);
  AtomicIncrement(Stats.Created);
  if (Stats.Mode = 'close-before-register') or (Stats.Mode = 'stop-before-register')
    or (Stats.Mode = 'restart-old-listen') then Gate;
  if (Stats.Mode = 'register-error') or (Stats.Mode = 'logger-raises')
    or (Stats.Mode = 'logger-reenter') then
  begin
    // Linux 保持原编号被占用，避免 logger 创建线程时复用已关闭的 fd。
    {$IFDEF LINUX}
    LNull := TestOpen('/dev/null', 0);
    Check(LNull >= 0, 'open /dev/null failed');
    try Check(TestDup2(LNull, Integer(Result.Socket)) >= 0, 'dup2 failed');
    finally TestClose(LNull); end;
    {$ELSE}
    TSocketAPI.CloseSocket(Result.Socket);
    {$ENDIF}
  end;
end;

function TTestSocket.CreateConnection(const AOwner: TCrossSocketBase; const ASocket: TSocket;
  const AType: TConnectType; const AHost: string;
  const ACallback: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TTrackedConnection.Create(AOwner, ASocket, AType, AHost, ACallback);
  AtomicIncrement(Stats.ConnectionsCreated);
  if Stats.Mode = 'accept-before-publish-stop' then Gate;
end;

procedure TTestSocket.Gate;
begin
  if AtomicIncrement(Stats.Gates) <> 1 then Exit;
  Stats.Entered.SetEvent;
  if Stats.Resume.WaitFor(15000) <> wrSignaled then AtomicIncrement(Stats.Timeouts);
end;

procedure TTestSocket.TriggerListened(const AListen: ICrossListen);
begin
  if (Stats.Mode = 'early-event') or (Stats.Mode = 'close-before-publish')
    or (Stats.Mode = 'stop-before-publish') then
  begin
    AListen.UpdateAddr;
    Stats.Port := AListen.LocalPort;
    Gate;
  end;
  inherited;
  if Stats.Mode = 'publish-raises' then raise Exception.Create('test publish failure');
  if Stats.Mode = 'close-callback' then AListen.Close;
  if Stats.Mode = 'close-all-callback' then CloseAllListens;
end;

procedure TTestSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  inherited;
  if Stats.Mode = 'io-stop' then
  begin
    try StopLoop;
    except on E: ECrossSocket do AtomicIncrement(Stats.StopRejected); end;
    if not AConnection.IsClosed and (ListensCount = 1) then
      AtomicIncrement(Stats.OpenAfterReject);
  end;
  AtomicIncrement(Stats.Accepts);
  Stats.Accepted.SetEvent;
end;

function TTestSocket.ProcessIoEvent: Boolean;
begin
  Result := inherited ProcessIoEvent;
  if Result and (Stats.Mode = 'early-event') then Line('BATCH');
end;

procedure TTestSocket.CloseAllConnections;
begin
  inherited;
  if AtomicCmpExchange(Stats.StopRequested, 0, 0) <> 0 then
    Stats.StopSnapshot.SetEvent;
end;

procedure TStopThread.Execute;
begin
  try
    if CloseOnly then Socket.CloseAllListens else Socket.Stop;
  except on E: Exception do ErrorText := E.ClassName + ': ' + E.Message; end;
  Done.SetEvent;
end;

procedure TTestSocket.BeginListen;
var
  LHost: string;
  LHints: TRawAddrInfo;
  LAddresses, LAddress: PRawAddrInfo;
  LAddressCount: Integer;
begin
  LHost := '127.0.0.1';
  if Stats.Mode = 'ipv6' then LHost := '::1';
  if Stats.Mode = 'close-all-callback' then
  begin
    LHost := '';
    FillChar(LHints, SizeOf(LHints), 0);
    LHints.ai_flags := AI_PASSIVE;
    LHints.ai_family := AF_UNSPEC;
    LHints.ai_socktype := SOCK_STREAM;
    LHints.ai_protocol := IPPROTO_TCP;
    LAddresses := TSocketAPI.GetAddrInfo(LHost, Word(0), LHints);
    LAddressCount := 0;
    LAddress := LAddresses;
    try
      while LAddress <> nil do
      begin
        Inc(LAddressCount);
        LAddress := PRawAddrInfo(LAddress.ai_next);
      end;
    finally TSocketAPI.FreeAddrInfo(LAddresses); end;
    Line('LISTEN_ADDRESSES ' + IntToStr(LAddressCount));
    Check(LAddressCount >= 2, 'multi-address listen prerequisite missing');
  end;
  Listen(LHost, 0,
    procedure(const AListen: ICrossListen; const AOK: Boolean)
    begin
      AtomicIncrement(Stats.Calls);
      if AOK then
      begin
        AtomicIncrement(Stats.Successes);
        Stats.Port := AListen.LocalPort;
      end else
        AtomicIncrement(Stats.Failures);
    end);
end;

procedure TTestSocket.Stop;
begin
  StopLoop;
end;

procedure TTestSocket.Restart;
begin
  StartLoop;
end;

function TTestSocket.Pending: NativeInt;
begin
  {$IFDEF MSWINDOWS}
  Result := GetPendingIoCountForTest;
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

procedure TListenThread.Execute;
begin
  try Socket.BeginListen;
  except on E: Exception do ErrorText := E.ClassName + ': ' + E.Message; end;
end;

procedure WaitAccepted(const ACount: Integer);
var
  I: Integer;
begin
  for I := 1 to 80 do
  begin
    if AtomicCmpExchange(Stats.Accepts, 0, 0) >= ACount then Exit;
    Stats.Accepted.WaitFor(50);
  end;
end;

procedure Run;
var
  LSocket: TTestSocket;
  LKeep: ICrossSocket;
  LThread: TListenThread;
  LStopThread: TStopThread;
  {$IFDEF MSWINDOWS}
  LProbe: TSocket;
  LGuid: TGUID;
  LProc: Pointer;
  LBytes: DWORD;
  LAcceptsBeforeStop: Integer;
  {$ENDIF}
  LMode, LCommand, LError: string;
  LExpectedSuccess, LPendingAfterStop: Integer;
  LBeforeCallbacks: Integer;
begin
  CrossSocketLogEnabled := False;
  LMode := ParamStr(1);
  Stats := TStats.Create;
  Stats.Mode := LMode;
  LExpectedSuccess := 1;
  LPendingAfterStop := 0;
  LSocket := TTestSocket.Create(2);
  LKeep := LSocket;
  LThread := nil;
  {$IFDEF MSWINDOWS}
  LProbe := TSocketAPI.NewSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  Check(LProbe <> INVALID_SOCKET, 'extension probe socket failed');
  LGuid := WSAID_ACCEPTEX;
  LProc := nil;
  try
    Check(WSAIoctl(LProbe, SIO_GET_EXTENSION_FUNCTION_POINTER, @LGuid, SizeOf(LGuid),
      @LProc, SizeOf(LProc), @LBytes, nil, nil) = 0, 'AcceptEx lookup failed');
    Check(TSocketAPI.SetSockOpt<Integer>(LProbe, SOL_SOCKET, SO_KEEPALIVE, 1) = 0,
      'setsockopt lookup failed');
  finally TSocketAPI.CloseSocket(LProbe); end;
  OriginalAccept := LPFN_ACCEPTEX(LProc);
  AcceptEx := ObservedAccept;
  OriginalSetOption := Net.Winsock2.setsockopt;
  Net.Winsock2.setsockopt := ObservedSetOption;
  CrossIocpAcceptReadyForTest := procedure(const AListen: ICrossListen)
    begin if Stats.Mode = 'late-accept-stop' then LSocket.Gate; end;
  {$ENDIF}
  CrossListenRegisteredForTest := procedure(const AListen: ICrossListen)
    begin if Stats.Mode = 'close-before-arm' then LSocket.Gate; end;
  if (LMode = 'logger-raises') or (LMode = 'logger-reenter') then
  begin
    CrossSocketLogEnabled := True;
    _SetCrossLogger(procedure(const AText: string)
      var LWorker: TStopThread;
      begin
        if LMode = 'logger-raises' then raise Exception.Create('test logger failure');
        LWorker := TStopThread.Create(True);
        LWorker.FreeOnTerminate := False;
        LWorker.Socket := LSocket;
        LWorker.CloseOnly := True;
        LWorker.Done := TEvent.Create(nil, True, False, '');
        LWorker.Start;
        Check(LWorker.Done.WaitFor(3000) = wrSignaled, 'logger ran under an internal lock');
        LWorker.WaitFor;
        Check(LWorker.ErrorText = '', 'logger reentry failed');
        LWorker.Done.Free;
        LWorker.Free;
      end);
  end;

  if (LMode = 'early-event') or (LMode = 'close-before-publish')
    or (LMode = 'stop-before-publish') or (LMode = 'close-before-register')
    or (LMode = 'stop-before-register') or (LMode = 'restart-old-listen')
    or (LMode = 'close-before-arm') then
  begin
    LThread := TListenThread.Create(True);
    LThread.FreeOnTerminate := False;
    LThread.Socket := LSocket;
    LThread.Start;
    Check(Stats.Entered.WaitFor(10000) = wrSignaled, 'listen gate not reached');
    if LMode = 'early-event' then
    begin
      Line('PUBLISH ' + IntToStr(Stats.Port));
      Readln(LCommand);
      Check(LCommand = 'publish', 'expected publish');
    end else
    begin
      LExpectedSuccess := 0;
      if (LMode = 'close-before-publish') or (LMode = 'close-before-register')
        or (LMode = 'close-before-arm') then
        LSocket.CloseAllListens
      else
      begin
        LSocket.Stop;
        LPendingAfterStop := LSocket.Pending;
        if LMode = 'restart-old-listen' then LSocket.Restart;
      end;
    end;
    Stats.Resume.SetEvent;
    LThread.WaitFor;
    LError := LThread.ErrorText;
    LThread.Free;
    LThread := nil;
  end else
  begin
    try LSocket.BeginListen;
    except on E: Exception do LError := E.ClassName + ': ' + E.Message; end;
  end;

  if (LMode = 'early-event') or (LMode = 'normal') or (LMode = 'ipv6')
    or (LMode = 'io-stop') or (LMode = 'accept-before-publish-stop')
    or (LMode = 'late-accept-stop') or (LMode = 'accept-context-error') then
  begin
    Line('READY ' + IntToStr(Stats.Port));
    Readln(LCommand);
    Check(LCommand = 'verify', 'expected verify');
    if (LMode = 'accept-before-publish-stop') or (LMode = 'late-accept-stop') then
    begin
      Check(Stats.Entered.WaitFor(8000) = wrSignaled, 'accept gate not reached');
      {$IFDEF MSWINDOWS}LAcceptsBeforeStop := NativeAcceptCalls;{$ENDIF}
      AtomicExchange(Stats.StopRequested, 1);
      LStopThread := TStopThread.Create(True);
      LStopThread.FreeOnTerminate := False;
      LStopThread.Socket := LSocket;
      LStopThread.Done := TEvent.Create(nil, True, False, '');
      LStopThread.Start;
      Check(Stats.StopSnapshot.WaitFor(8000) = wrSignaled, 'stop snapshot not reached');
      Stats.Resume.SetEvent;
      Check(LStopThread.Done.WaitFor(10000) = wrSignaled, 'stop did not finish');
      LStopThread.WaitFor;
      Check(LStopThread.ErrorText = '', 'stop thread exception');
      LStopThread.Done.Free;
      LStopThread.Free;
      LPendingAfterStop := LSocket.Pending;
      Check(Stats.Accepts = 0, 'accepted a connection after stop snapshot');
      {$IFDEF MSWINDOWS}
      Check(NativeAcceptCalls = LAcceptsBeforeStop, 'AcceptEx was reposted after listener closed');
      {$ENDIF}
    end else
    if (LMode = 'io-stop') or (LMode = 'accept-context-error') then
      WaitAccepted(1)
    else
      WaitAccepted(2);
  end;

  if (LMode = 'update-raises') or (LMode = 'publish-raises')
    or (LMode = 'logger-raises') then
  begin
    if LMode = 'update-raises' then
      Check(LError = 'Exception: test update failure', 'expected UpdateAddr exception: ' + LError)
    else if LMode = 'publish-raises' then
      Check(LError = 'Exception: test publish failure', 'expected publication exception: ' + LError)
    else
      Check(LError = 'Exception: test logger failure', 'expected logger exception: ' + LError);
    Check(Stats.Successes = 0, 'exception was followed by success callback');
    Check(LSocket.ListensCount = 0, 'setup exception leaked owner reference');
  end else
  begin
    Check(LError = '', 'unexpected exception ' + LError);
    if (LMode = 'register-error') or (LMode = 'logger-reenter')
      or (LMode = 'partial-accept-error') then LExpectedSuccess := 0;
    Line(Format('OBSERVED callbacks=%d successes=%d failures=%d listens=%d pending_after_stop=%d accepts=%d',
      [Stats.Calls, Stats.Successes, Stats.Failures, LSocket.ListensCount, LPendingAfterStop, Stats.Accepts]));
    Check(Stats.Calls = 1, 'listen result count changed');
    Check(Stats.Successes = LExpectedSuccess, 'unexpected listen result');
    Check(LPendingAfterStop = 0, 'StopLoop left pending I/O');
  end;
  Check(Stats.Timeouts = 0, 'gate timed out');
  if (LMode = 'early-event') or (LMode = 'normal') or (LMode = 'ipv6') then
    Check(Stats.Accepts = 2, 'first or subsequent client was not accepted');
  if LMode = 'io-stop' then
    Check((Stats.StopRejected = 1) and (Stats.OpenAfterReject = 1),
      'I/O-thread StopLoop changed resources before rejection');
  {$IFDEF MSWINDOWS}
  if LMode = 'accept-context-error' then
  begin
    Check(ContextFailures = 2, 'native context error prerequisite failed');
    Check(Stats.Accepts = 1, 'context errors exhausted accept slots');
    Check(NativeAcceptSubmitted >= 5, 'context error did not replenish accepts');
  end;
  {$ENDIF}
  if LMode = 'close-all-callback' then
    Check((Stats.Created = 1) and (LSocket.ListensCount = 0),
      'CloseAllListens allowed another address to be published');

  if (LMode = 'close-before-register') or (LMode = 'close-before-publish')
    or (LMode = 'restart-old-listen') or (LMode = 'close-before-arm') then
  begin
    Check(LSocket.ListensCount = 0, 'cancelled listen remained published');
    // 新调用采用新代次，不能被先前关闭全部永久禁止。
    Stats.Mode := 'normal';
    LBeforeCallbacks := Stats.Successes;
    LSocket.BeginListen;
    Check(Stats.Successes = LBeforeCallbacks + 1, 'new listen was rejected');
  end;
  LSocket.Stop;
  Check(LSocket.Pending = 0, 'pending I/O did not drain');
  Check((LSocket.ListensCount = 0) and (LSocket.ConnectionsCount = 0), 'owner tables not empty');
  {$IFDEF MSWINDOWS}
  if LMode = 'partial-accept-error' then
    Check((NativeAcceptCalls = 2) and (NativeAcceptSubmitted = 1), 'partial submit precondition failed');
  Line(Format('NATIVE_ACCEPT calls=%d submitted=%d', [NativeAcceptCalls, NativeAcceptSubmitted]));
  AcceptEx := OriginalAccept;
  Net.Winsock2.setsockopt := OriginalSetOption;
  CrossIocpAcceptReadyForTest := nil;
  {$ENDIF}
  CrossListenRegisteredForTest := nil;
  _SetCrossLogger(nil);
  LKeep := nil;
  Check(Stats.Created = Stats.Destroyed, 'listen object leak');
  Check(Stats.ConnectionsCreated = Stats.ConnectionsDestroyed, 'connection object leak');
  Line(Format('RELEASED listens=%d/%d connections=%d/%d',
    [Stats.Destroyed, Stats.Created, Stats.ConnectionsDestroyed, Stats.ConnectionsCreated]));
  Stats.Free;
  Line('PASS ' + LMode);
end;

begin
  OutputLock := SyncObjs.TCriticalSection.Create;
  try
    try Run;
    except on E: Exception do begin Line('FAIL ' + E.ClassName + ': ' + E.Message); Halt(1); end; end;
  finally OutputLock.Free; end;
end.
