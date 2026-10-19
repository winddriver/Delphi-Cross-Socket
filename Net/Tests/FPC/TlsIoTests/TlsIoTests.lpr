program TlsIoTests;

{$I ../../../../zLib.inc}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  SysUtils, Classes, Generics.Collections, Utils.SyncObjs,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSslSocket.OpenSSL, Net.OpenSSL,
  Net.CrossWebSocketParser;

type
  TObservedTlsConnection = class(TCrossOpenSslConnection)
  public
    destructor Destroy; override;
  end;
  TPhysicalWrite = record
    Data: TBytes;
    Buffer: Pointer;
    Callback: TCrossConnectionCallback;
    Connection: ICrossConnection;
  end;
  TMemoryTlsSocket = class(TCrossOpenSslSocket)
  private
    FOutputLock: ILock;
    FOutput: TList<TBytes>;
    FPending: TQueue<TPhysicalWrite>;
    procedure SendBenchCipher(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback);
  protected
    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil); override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
  public
    FirstEntered, ReleaseFirst: IEvent;
    BlockFirst, DelayWrites, FailWrites: Boolean;
    RaiseConnected, RaiseReceived, RaiseDisconnected: Boolean;
    ReceivedAction: TCrossConnectionCallback;
    SendCalls, ConnectedCalls, ReceivedCalls, DisconnectedCalls: Integer;
    SendDepth, MaxSendDepth: Integer;
    DestroyedConnections: Integer;
    Plaintext: AnsiString;
    BenchReceive: Boolean;
    BenchBytes: Int64;
    BenchPeer: PSSL;
    BenchPeerInput: PBIO;
    BenchVerifyAll: Boolean;
    BenchCipherBytes, BenchDecryptedBytes: Int64;
    constructor Create; reintroduce;
    destructor Destroy; override;
    function StartClient: ICrossConnection;
    procedure Inject(const AConnection: ICrossConnection; const AData: TBytes);
    function TakeOutput: TBytes;
    procedure CompleteNext(const ASuccess: Boolean);
    function PendingCount: Integer;
  end;

  TTlsFixture = class
  public
    Socket: TMemoryTlsSocket;
    Connection: ICrossConnection;
    PeerCtx: PSSL_CTX;
    Peer: PSSL;
    PeerIn, PeerOut: PBIO;
    PeerDone: Boolean;
    constructor Create(const AVersion: Integer; const AMaxPending: Integer = 0);
    destructor Destroy; override;
    procedure Handshake;
    procedure Step;
    procedure SendPeer(const AText: AnsiString);
    procedure KeyUpdate;
    function ReadPeer: AnsiString;
  end;

  TWriteThread = class(TThread)
  public
    Connection: ICrossConnection;
    Data: TBytes;
    Returned: IEvent;
    Calls, Failures: Integer;
    ErrorText: string;
    constructor Create(const AConnection: ICrossConnection; const AText: string);
    procedure Execute; override;
  end;

  TSslWrite = function(ASsl: PSSL; const ABuf: Pointer; ALen: Integer): Integer; cdecl;
  TRenegotiate = function(ASsl: PSSL): Integer; cdecl;
  TKeyUpdate = function(ASsl: PSSL; ARequested: Integer): Integer; cdecl;

var
  OriginalWrite: TSslWrite;
  WantReads, PartialWrites, WantLength: Integer;
  WantSsl: PSSL;
  WantBuffer: Pointer;
  WrongRetry, UsePartialWrite: Boolean;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

function TraceWrite(ASsl: PSSL; const ABuf: Pointer; ALen: Integer): Integer; cdecl;
begin
  if (WantSsl = ASsl) and (WantBuffer <> nil) then
    if (WantBuffer <> ABuf) or (WantLength <> ALen) then WrongRetry := True;
  if UsePartialWrite then SSL_ctrl(ASsl, SSL_CTRL_MODE, SSL_MODE_ENABLE_PARTIAL_WRITE, nil);
  Result := OriginalWrite(ASsl, ABuf, ALen);
  if (Result > 0) and (Result < ALen) then Inc(PartialWrites);
  if (Result <= 0) and (SSL_get_error(ASsl, Result) = SSL_ERROR_WANT_READ) then
  begin
    Inc(WantReads);
    WantSsl := ASsl; WantBuffer := ABuf; WantLength := ALen;
  end else
  if WantSsl = ASsl then WantBuffer := nil;
end;

constructor TMemoryTlsSocket.Create;
begin
  inherited Create(2, True);
  FOutputLock := TLock.Create;
  FOutput := TList<TBytes>.Create;
  FPending := TQueue<TPhysicalWrite>.Create;
  FirstEntered := TEvent.Create(True, False);
  ReleaseFirst := TEvent.Create(True, False);
end;

destructor TObservedTlsConnection.Destroy;
begin
  Inc((Owner as TMemoryTlsSocket).DestroyedConnections);
  inherited;
end;

destructor TMemoryTlsSocket.Destroy;
begin
  StopLoop;
  FPending.Free;
  FOutput.Free;
  inherited;
end;

procedure TMemoryTlsSocket.Send(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LBytes: TBytes;
  LWrite: TPhysicalWrite;
begin
  Inc(SendDepth);
  if SendDepth > MaxSendDepth then MaxSendDepth := SendDepth;
  try
  if BenchPeer <> nil then
  begin
    SendBenchCipher(AConnection, ABuf, ALen, ACallback);
    Exit;
  end;
  if BlockFirst and (AtomicIncrement(SendCalls) = 1) then
  begin
    // 在 TLS 锁外、真正进入发送队列前卡住首个提交，固定并发交错。
    FirstEntered.SetEvent;
    Check(ReleaseFirst.WaitFor(5000) = TWaitResult.wrSignaled, 'first send release timeout');
  end;
  SetLength(LBytes, ALen);
  if ALen > 0 then Move(ABuf^, LBytes[0], ALen);
  if FailWrites then
  begin
    if Assigned(ACallback) then ACallback(AConnection, False);
    Exit;
  end;
  FOutputLock.Enter;
  try
    FOutput.Add(LBytes);
    if DelayWrites then
    begin
      LWrite.Data := LBytes;
      LWrite.Buffer := ABuf;
      LWrite.Callback := ACallback;
      LWrite.Connection := AConnection;
      FPending.Enqueue(LWrite);
    end;
  finally
    FOutputLock.Leave;
  end;
  if not DelayWrites and Assigned(ACallback) then ACallback(AConnection, True);
  finally
    Dec(SendDepth);
  end;
end;

procedure TMemoryTlsSocket.SendBenchCipher(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LBuffer: array[0..16383] of Byte;
  N, I, LError: Integer;
begin
  // 模拟即时物理交付，真实对端BIO/SSL解密；不增加测试用密文数组复制。
  Check(BIO_write(BenchPeerInput, ABuf, ALen) = ALen, 'output benchmark BIO input failed');
  Inc(BenchCipherBytes, ALen);
  repeat
    ERR_clear_error();
    N := SSL_read(BenchPeer, @LBuffer[0], SizeOf(LBuffer));
    if N <= 0 then
    begin
      LError := SSL_get_error(BenchPeer, N);
      Check(LError = SSL_ERROR_WANT_READ, 'output benchmark peer rejected ciphertext');
      Break;
    end;
    Inc(BenchDecryptedBytes, N);
    Check((LBuffer[0] = $41) and (LBuffer[N - 1] = $41), 'output benchmark plaintext differs');
    if BenchVerifyAll then
      for I := 0 to N - 1 do Check(LBuffer[I] = $41, 'output benchmark plaintext byte differs');
  until False;
  if Assigned(ACallback) then ACallback(AConnection, True);
end;

procedure TMemoryTlsSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  Inc(ConnectedCalls);
  if RaiseConnected then raise Exception.Create('connected test exception');
  inherited;
end;

procedure TMemoryTlsSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LPart: AnsiString;
begin
  Inc(ReceivedCalls);
  if BenchReceive then
  begin
    Check((ALen > 0) and (PByte(ABuf)^ = $41) and (PByte(ABuf)[ALen - 1] = $41), 'benchmark plaintext mismatch');
    Inc(BenchBytes, ALen);
    Exit;
  end;
  SetString(LPart, PAnsiChar(ABuf), ALen);
  Plaintext := Plaintext + LPart;
  if Assigned(ReceivedAction) then ReceivedAction(AConnection, True);
  if RaiseReceived then raise Exception.Create('received test exception');
  inherited;
end;

procedure TMemoryTlsSocket.LogicDisconnected(const AConnection: ICrossConnection);
begin
  Inc(DisconnectedCalls);
  if RaiseDisconnected then raise Exception.Create('disconnected test exception');
  inherited;
end;

function TMemoryTlsSocket.PendingCount: Integer;
begin
  FOutputLock.Enter;
  try Result := FPending.Count; finally FOutputLock.Leave; end;
end;

procedure TMemoryTlsSocket.CompleteNext(const ASuccess: Boolean);
var
  LWrite: TPhysicalWrite;
begin
  FOutputLock.Enter;
  try
    Check(FPending.Count > 0, 'no pending physical write');
    LWrite := FPending.Dequeue;
  finally FOutputLock.Leave; end;
  Check(CompareMem(LWrite.Buffer, @LWrite.Data[0], Length(LWrite.Data)),
    'ciphertext was released before physical completion');
  if Assigned(LWrite.Callback) then LWrite.Callback(LWrite.Connection, ASuccess);
end;

function TMemoryTlsSocket.StartClient: ICrossConnection;
begin
  Result := TObservedTlsConnection.Create(Self, TSocketAPI.NewTcp,
    ctConnect, 'localhost', nil);
  Check(Result.Socket <> INVALID_SOCKET, 'test socket creation failed');
  TriggerConnecting(Result);
  TriggerConnected(Result);
end;

procedure TMemoryTlsSocket.Inject(const AConnection: ICrossConnection; const AData: TBytes);
begin
  if Length(AData) > 0 then TriggerReceived(AConnection, @AData[0], Length(AData));
end;

function TMemoryTlsSocket.TakeOutput: TBytes;
var
  LPart: TBytes;
  N: Integer;
begin
  Result := nil;
  FOutputLock.Enter;
  try
    for LPart in FOutput do
    begin
      N := Length(Result);
      SetLength(Result, N + Length(LPart));
      if Length(LPart) > 0 then Move(LPart[0], Result[N], Length(LPart));
    end;
    FOutput.Clear;
  finally
    FOutputLock.Leave;
  end;
end;

constructor TTlsFixture.Create(const AVersion, AMaxPending: Integer);
var
  LGroup: AnsiString;
begin
  inherited Create;
  Socket := TMemoryTlsSocket.Create;
  if AMaxPending > 0 then Socket.SslMaxPendingWriteBytes := AMaxPending;
  PeerCtx := TSSLTools.NewCTX(TLS_method());
  Check(SSL_CTX_set_min_proto_version(PeerCtx, AVersion) = 1, 'peer minimum version failed');
  Check(SSL_CTX_set_max_proto_version(PeerCtx, AVersion) = 1, 'peer maximum version failed');
  LGroup := 'X25519';
  Check(SSL_CTX_ctrl(PeerCtx, SSL_CTRL_SET_CURVES_LIST, 0, PAnsiChar(LGroup)) = 1, 'peer group failed');
  TSSLTools.SetCertificateFile(PeerCtx, ParamStr(4));
  TSSLTools.SetPrivateKeyFile(PeerCtx, ParamStr(5));
  Peer := SSL_new(PeerCtx);
  PeerIn := BIO_new(BIO_s_mem()); PeerOut := BIO_new(BIO_s_mem());
  Check((Peer <> nil) and (PeerIn <> nil) and (PeerOut <> nil), 'peer allocation failed');
  SSL_set_bio(Peer, PeerIn, PeerOut);
  SSL_set_accept_state(Peer);
  Connection := Socket.StartClient;
end;

destructor TTlsFixture.Destroy;
begin
  if Socket <> nil then
  begin
    Socket.RaiseDisconnected := False;
    if Connection <> nil then Connection.Close;
    while Socket.PendingCount > 0 do Socket.CompleteNext(False);
  end;
  Connection := nil;
  Socket.Free;
  if Peer <> nil then SSL_free(Peer);
  if PeerCtx <> nil then TSSLTools.FreeCTX(PeerCtx);
  inherited;
end;

procedure TTlsFixture.Step;
var
  LBytes: TBytes;
  LResult, LError, N: Integer;
begin
    LBytes := Socket.TakeOutput;
    if Length(LBytes) > 0 then
      Check(BIO_write(PeerIn, @LBytes[0], Length(LBytes)) = Length(LBytes), 'peer input failed');
    if not PeerDone then
    begin
      ERR_clear_error();
      LResult := SSL_do_handshake(Peer);
      PeerDone := LResult = 1;
      if not PeerDone then
      begin
        LError := SSL_get_error(Peer, LResult);
        Check(LError in [SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE], 'peer handshake: ' + GetOpenSslErrors);
      end;
    end;
    N := BIO_pending(PeerOut);
    SetLength(LBytes, N);
    if N > 0 then
    begin
      Check(BIO_read(PeerOut, @LBytes[0], N) = N, 'peer output failed');
      Socket.Inject(Connection, LBytes);
    end;
end;

procedure TTlsFixture.Handshake;
var
  I: Integer;
begin
  for I := 1 to 20 do
  begin
    Step;
    if PeerDone and (Connection.ConnectStatus = csConnected) then Exit;
  end;
  raise Exception.Create('handshake did not complete');
end;

procedure TTlsFixture.SendPeer(const AText: AnsiString);
var
  LBytes: TBytes;
  N: Integer;
begin
  Check(SSL_write(Peer, PAnsiChar(AText), Length(AText)) = Length(AText), 'peer write failed');
  N := BIO_pending(PeerOut);
  SetLength(LBytes, N);
  Check((N > 0) and (BIO_read(PeerOut, @LBytes[0], N) = N), 'peer ciphertext missing');
  Socket.Inject(Connection, LBytes);
end;

procedure TTlsFixture.KeyUpdate;
var
  LHandle: TLibHandle;
  LUpdate: TKeyUpdate;
  LBytes: TBytes;
  N: Integer;
begin
  LHandle := SafeLoadLibrary(ParamStr(2));
  Check(LHandle <> 0, 'key update library reference failed');
  try
    {$IFDEF FPC}
    @LUpdate := GetProcedureAddress(LHandle, 'SSL_key_update');
    {$ELSE}
    @LUpdate := GetProcAddress(LHandle, 'SSL_key_update');
    {$ENDIF}
    Check(Assigned(LUpdate), 'SSL_key_update unavailable');
    Check(LUpdate(Peer, 1) = 1, 'native KeyUpdate request failed');
    Check(SSL_do_handshake(Peer) = 1, 'native KeyUpdate flush failed');
    N := BIO_pending(PeerOut);
    Check(N > 0, 'native KeyUpdate ciphertext missing');
    SetLength(LBytes, N);
    Check(BIO_read(PeerOut, @LBytes[0], N) = N, 'native KeyUpdate output failed');
    Socket.Inject(Connection, LBytes);
  finally
    FreeLibrary(LHandle);
  end;
end;

function TTlsFixture.ReadPeer: AnsiString;
var
  LBytes: TBytes;
  LBuffer: array[0..4095] of AnsiChar;
  LPart: AnsiString;
  N, LError: Integer;
begin
  Result := '';
  LBytes := Socket.TakeOutput;
  if Length(LBytes) > 0 then
    Check(BIO_write(PeerIn, @LBytes[0], Length(LBytes)) = Length(LBytes), 'ciphertext input failed');
  repeat
    ERR_clear_error();
    N := SSL_read(Peer, @LBuffer[0], SizeOf(LBuffer));
    if N > 0 then
    begin
      SetString(LPart, PAnsiChar(@LBuffer[0]), N);
      Result := Result + LPart;
    end else
    begin
      LError := SSL_get_error(Peer, N);
      Check(LError = SSL_ERROR_WANT_READ, 'peer decrypt error: ' + GetOpenSslErrors);
      Break;
    end;
  until False;
end;

constructor TWriteThread.Create(const AConnection: ICrossConnection; const AText: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Connection := AConnection;
  Data := TEncoding.ASCII.GetBytes(AText);
  Returned := TEvent.Create(True, False);
end;

procedure TWriteThread.Execute;
var
  LCallback: TCrossConnectionCallback;
begin
  try
    LCallback :=
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin AtomicIncrement(Calls); if not OK then AtomicIncrement(Failures); end;
    Connection.SendBytes(Data, LCallback);
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
  Returned.SetEvent;
end;

procedure TestOrder(const AVersion: Integer; const APartial: Boolean = False;
  const AKeyUpdate: Boolean = False);
var
  F: TTlsFixture;
  A, B: TWriteThread;
  LText: string;
begin
  F := TTlsFixture.Create(AVersion);
  A := nil; B := nil;
  try
    F.Handshake;
    if AKeyUpdate then F.KeyUpdate;
    OriginalWrite := SSL_write;
    if APartial then
    begin
      UsePartialWrite := True;
      PartialWrites := 0;
      SSL_write := TraceWrite;
      LText := StringOfChar('A', 65536);
    end else LText := 'A';
    F.Socket.BlockFirst := True;
    A := TWriteThread.Create(F.Connection, LText);
    B := TWriteThread.Create(F.Connection, 'B');
    A.Start;
    Check(F.Socket.FirstEntered.WaitFor(5000) = TWaitResult.wrSignaled, 'first submission did not arrive');
    B.Start;
    Check(B.Returned.WaitFor(5000) = TWaitResult.wrSignaled, 'second send blocked on first physical submission');
    F.Socket.ReleaseFirst.SetEvent;
    A.WaitFor; B.WaitFor;
    Check((A.ErrorText = '') and (B.ErrorText = ''), A.ErrorText + B.ErrorText);
    Check((A.Calls = 1) and (B.Calls = 1) and (A.Failures + B.Failures = 0), 'send callback mismatch');
    Check(F.ReadPeer = AnsiString(LText + 'B'), 'plaintext order mismatch');
    if APartial then Check(PartialWrites >= 3, 'native partial write was not exercised');
  finally
    F.Socket.ReleaseFirst.SetEvent;
    if A <> nil then begin if A.Suspended then A.Start; A.WaitFor; A.Free; end;
    if B <> nil then begin if B.Suspended then B.Start; B.WaitFor; B.Free; end;
    if APartial then
    begin
      SSL_write := OriginalWrite;
      UsePartialWrite := False;
    end;
    F.Free;
  end;
end;

procedure TestWant;
var
  F: TTlsFixture;
  LCalls, LFailed: Integer;
  LCallback: TCrossConnectionCallback;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION);
  OriginalWrite := SSL_write;
  WantReads := 0; LCalls := 0; LFailed := 0;
  SSL_write := TraceWrite;
  try
    LCallback :=
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailed); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('B'), LCallback);
    F.Handshake;
    Writeln('NATIVE WANT_READ=', WantReads, ' callbacks=', LCalls);
    Check(WantReads >= 2, 'real OpenSSL WANT_READ path was not exercised');
    Check(not WrongRetry, 'native WANT retry changed buffer or length');
    Check((LCalls = 2) and (LFailed = 0), 'pending write did not resume after handshake');
    Check(F.ReadPeer = 'AB', 'pending plaintext order mismatch');
  finally
    SSL_write := OriginalWrite;
    F.Free;
  end;
end;

procedure TestCapacity;
var
  F: TTlsFixture;
  LCalls, LFailed: Integer;
  LCallback: TCrossConnectionCallback;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION, 1);
  LCalls := 0; LFailed := 0; WantReads := 0;
  OriginalWrite := SSL_write;
  SSL_write := TraceWrite;
  try
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailed); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('AB'), LCallback);
    Writeln('NATIVE capacity WANT_READ=', WantReads, ' callbacks=', LCalls);
    Check(WantReads = 1, 'capacity test did not reach native WANT_READ');
    Check((LCalls = 1) and (LFailed = 1), 'retry slot bypassed pending byte limit');
  finally
    SSL_write := OriginalWrite;
    F.Free;
  end;
end;

procedure TestDisconnectedError;
var
  F: TTlsFixture;
  LCalls, LFailed: Integer;
  LCallback: TCrossConnectionCallback;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LCalls := 0; LFailed := 0;
  try
    F.Handshake;
    F.Socket.FailWrites := True;
    F.Socket.RaiseDisconnected := True;
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailed); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
    Check(F.Socket.DisconnectedCalls = 1, 'disconnect exception was not exercised');
    Check((LCalls = 1) and (LFailed = 1), 'disconnect exception skipped original completion');
  finally
    F.Free;
  end;
end;

procedure TestConnectedError;
var
  F: TTlsFixture;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    F.Socket.RaiseConnected := True;
    try F.Handshake; except on E: Exception do ; end;
    Check(F.Socket.ConnectedCalls = 1, 'connected exception was not exercised exactly once');
    Check(F.Connection.IsClosed, 'cipher completion swallowed connected exception without closing');
  finally
    F.Free;
  end;
end;

procedure TestReceivedError;
var
  F: TTlsFixture;
  I: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    // ClientHello 已同步完成；延迟后续 ClientFinished 的物理通知。
    F.Socket.DelayWrites := True;
    for I := 1 to 20 do
    begin
      F.Step;
      if F.PeerDone then Break;
    end;
    Check(F.PeerDone and (F.Socket.PendingCount > 0), 'delayed handshake path missing');
    F.Socket.RaiseReceived := True;
    F.SendPeer('R');
    while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
    Check(F.Socket.ConnectedCalls = 1, 'connected notification was repeated');
    Check(F.Socket.ReceivedCalls = 1, 'received exception was not exercised');
    Check(F.Connection.IsClosed, 'cipher completion swallowed received exception without closing');
  finally
    F.Free;
  end;
end;

procedure TestActiveClose;
var
  F: TTlsFixture;
  A, B, LFailed: Integer;
  LCallbackA, LCallbackB: TCrossConnectionCallback;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  A := 0; B := 0; LFailed := 0;
  try
    F.Handshake;
    F.Socket.DelayWrites := True;
    LCallbackA := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(A); if not OK then Inc(LFailed); end;
    LCallbackB := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(B); if not OK then Inc(LFailed); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallbackA);
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('B'), LCallbackB);
    Check(F.Socket.PendingCount = 1, 'more than one physical write was submitted');
    F.Connection.Close;
    Check((A = 0) and (B = 1) and (LFailed = 1), 'Close settled an in-flight write too early');
    F.Socket.CompleteNext(True);
    Check((A = 1) and (B = 1) and (LFailed = 2), 'late physical completion was not canceled once');
    Check(F.Connection.IsClosed and (F.Socket.PendingCount = 0), 'late completion restarted closed connection');
    Check((F.Connection as TCrossOpenSslConnection).RefCount = 1, 'cipher/pending callback retained connection');
  finally
    F.Free;
  end;
end;

procedure TestSyncReentry;
var
  F: TTlsFixture;
  LCallback: TCrossConnectionCallback;
  LCalls, LFailed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LCalls := 0; LFailed := 0;
  try
    F.Handshake;
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        Inc(LCalls);
        if not OK then Inc(LFailed);
        if LCalls < 128 then C.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback)
        else LCallback := nil;
      end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
    Check((LCalls = 128) and (LFailed = 0), 'synchronous reentry did not settle');
    Check(F.Socket.MaxSendDepth = 1, 'synchronous callbacks recursively entered physical send');
    Check(F.ReadPeer = AnsiString(StringOfChar('A', 128)), 'reentry payload mismatch');
  finally
    LCallback := nil;
    F.Free;
  end;
end;

procedure SendAndReleaseLast(const F: TTlsFixture);
var
  LCallback: TCrossConnectionCallback;
begin
  LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
    begin
      Check(OK, 'release-last write failed');
      F.Connection.Close;
      F.Connection := nil;
      Check(F.Socket.DestroyedConnections = 0, 'connection destroyed inside completion');
    end;
  F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
end;

procedure TestReleaseLast;
var
  F: TTlsFixture;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    F.Handshake;
    SendAndReleaseLast(F);
    Check(F.Socket.DestroyedConnections = 1, 'completion retained last connection reference');
  finally
    F.Free;
  end;
end;

procedure TestWriteCallbackError;
var
  F: TTlsFixture;
  LFirst, LSecond, LFalse: Integer;
  LCallback: TCrossConnectionCallback;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LFirst := 0; LSecond := 0; LFalse := 0;
  try
    F.Handshake;
    F.Socket.DelayWrites := True;
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        Inc(LFirst);
        if not OK then Inc(LFalse);
        raise Exception.Create('write callback test exception');
      end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LSecond); if not OK then Inc(LFalse); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('B'), LCallback);
    F.Socket.CompleteNext(True);
    Check((LFirst = 1) and (LSecond = 1) and (LFalse = 1), 'write callback failure repeated or lost completion');
    Check(F.Connection.IsClosed, 'write callback failure did not close affected connection');
  finally
    F.Free;
  end;
end;

procedure TestReadProtocol;
var
  F: TTlsFixture;
  LHandle: TLibHandle;
  LRenegotiate: TRenegotiate;
  LBytes: TBytes;
  N, LResult, LError: Integer;
  LByte: Byte;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION);
  LHandle := SafeLoadLibrary(ParamStr(2));
  Check(LHandle <> 0, 'test native library reference failed');
  try
    {$IFDEF FPC}
    @LRenegotiate := GetProcedureAddress(LHandle, 'SSL_renegotiate');
    {$ELSE}
    @LRenegotiate := GetProcAddress(LHandle, 'SSL_renegotiate');
    {$ENDIF}
    Check(Assigned(LRenegotiate), 'SSL_renegotiate unavailable');
    F.Handshake;
    Check(LRenegotiate(F.Peer) = 1, 'native server renegotiation rejected');
    SSL_do_handshake(F.Peer);
    N := BIO_pending(F.PeerOut);
    Check(N > 0, 'native HelloRequest not produced');
    SetLength(LBytes, N);
    Check(BIO_read(F.PeerOut, @LBytes[0], N) = N, 'HelloRequest read failed');
    F.Socket.Inject(F.Connection, LBytes);
    LBytes := F.Socket.TakeOutput;
    Writeln('NATIVE read-generated ciphertext=', Length(LBytes));
    Check(Length(LBytes) > 0, 'SSL_read protocol output was not sent');
    Check(BIO_write(F.PeerIn, @LBytes[0], Length(LBytes)) = Length(LBytes), 'protocol output input failed');
    // 对端实际解密 ClientHello 并产生下一轮握手，不能只断言非空输出。
    ERR_clear_error();
    LResult := SSL_read(F.Peer, @LByte, 1);
    LError := SSL_get_error(F.Peer, LResult);
    Check((LResult <= 0) and (LError in [SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE]),
      'peer rejected read-generated protocol bytes: ' + GetOpenSslErrors);
    N := BIO_pending(F.PeerOut);
    Check(N > 0, 'peer did not answer renegotiation ClientHello');
    SetLength(LBytes, N);
    Check(BIO_read(F.PeerOut, @LBytes[0], N) = N, 'peer renegotiation output failed');
    F.Socket.Inject(F.Connection, LBytes);
    LBytes := F.Socket.TakeOutput;
    Check(Length(LBytes) > 0, 'connected SSL_read did not continue renegotiation');
    Check(BIO_write(F.PeerIn, @LBytes[0], Length(LBytes)) = Length(LBytes), 'client Finished input failed');
    ERR_clear_error();
    LResult := SSL_read(F.Peer, @LByte, 1);
    Check(SSL_get_error(F.Peer, LResult) = SSL_ERROR_WANT_READ, 'peer failed to complete renegotiation');
    Check(SSL_is_init_finished(F.Peer) = 1, 'peer renegotiation is still incomplete');
    N := BIO_pending(F.PeerOut);
    // 会话恢复的简化握手可能已在前一轮发送服务端 Finished。
    if N > 0 then
    begin
      SetLength(LBytes, N);
      Check(BIO_read(F.PeerOut, @LBytes[0], N) = N, 'peer Finished output failed');
      F.Socket.Inject(F.Connection, LBytes);
    end;
    F.SendPeer('R');
    Check((F.Socket.ReceivedCalls = 1) and (F.Socket.ConnectedCalls = 1),
      'renegotiated data was not delivered once without another connected event');
    Check(F.Connection.ConnectStatus = csConnected, 'protocol output unexpectedly closed connection');
  finally
    F.Free;
    FreeLibrary(LHandle);
  end;
end;

procedure TestReadOrder;
var
  F: TTlsFixture;
  LHandle: TLibHandle;
  LRenegotiate: TRenegotiate;
  LBytes: TBytes;
  LData: AnsiString;
  N: Integer;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION);
  LHandle := SafeLoadLibrary(ParamStr(2));
  Check(LHandle <> 0, 'read order library reference failed');
  try
    {$IFDEF FPC}
    @LRenegotiate := GetProcedureAddress(LHandle, 'SSL_renegotiate');
    {$ELSE}
    @LRenegotiate := GetProcAddress(LHandle, 'SSL_renegotiate');
    {$ENDIF}
    Check(Assigned(LRenegotiate), 'SSL_renegotiate unavailable');
    F.Handshake;
    F.Socket.DelayWrites := True;
    Check(LRenegotiate(F.Peer) = 1, 'read order renegotiation rejected');
    SSL_do_handshake(F.Peer);
    LData := 'A';
    Check(SSL_write(F.Peer, PAnsiChar(LData), 1) = 1, 'native application A not written');
    N := BIO_pending(F.PeerOut);
    Check(N > 0, 'native protocol/application A ciphertext missing');
    SetLength(LBytes, N);
    Check(BIO_read(F.PeerOut, @LBytes[0], N) = N, 'native protocol/application A output failed');
    F.Socket.Inject(F.Connection, LBytes);
    Check(F.Socket.PendingCount = 1, 'read-generated ClientHello was not held');
    F.SendPeer('B');
    Writeln('RECEIVE before physical completion=', string(F.Socket.Plaintext));
    Check(F.Socket.Plaintext = 'AB', 'connected receive was delayed behind protocol output');
    while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
    Writeln('RECEIVE final=', string(F.Socket.Plaintext));
    Check(F.Socket.Plaintext = 'AB', 'protocol output reordered plaintext receive callbacks');
  finally
    F.Free;
    FreeLibrary(LHandle);
  end;
end;

{$I TlsTerminalTests.inc}
{$I TlsManagedQueueTests.inc}
{$I TlsQueueLimitTests.inc}
{$I TlsBaseLimitTests.inc}
{$I BufferBench.inc}

begin
  try
    Check(ParamCount = 5, 'mode ssl crypto cert key required');
    TSSLTools.LibSSL := ParamStr(2); TSSLTools.LibCRYPTO := ParamStr(3);
    TSSLTools.LoadSSL;
    try
      Writeln('OPENSSL ', IntToHex(OpenSSL_version_num(), 8));
      if ParamStr(1) = 'order12' then TestOrder(TLS1_2_VERSION)
      else if ParamStr(1) = 'order13' then TestOrder(TLS1_3_VERSION)
      else if ParamStr(1) = 'want12' then TestWant
      else if ParamStr(1) = 'capacity' then TestCapacity
      else if ParamStr(1) = 'disconnected-error' then TestDisconnectedError
      else if ParamStr(1) = 'connected-error' then TestConnectedError
      else if ParamStr(1) = 'received-error' then TestReceivedError
      else if ParamStr(1) = 'active-close' then TestActiveClose
      else if ParamStr(1) = 'sync-reentry' then TestSyncReentry
      else if ParamStr(1) = 'partial' then TestOrder(TLS1_3_VERSION, True)
      else if ParamStr(1) = 'read-protocol' then TestReadProtocol
      else if ParamStr(1) = 'keyupdate-order' then TestOrder(TLS1_3_VERSION, False, True)
      else if ParamStr(1) = 'release-last' then TestReleaseLast
      else if ParamStr(1) = 'write-callback-error' then TestWriteCallbackError
      else if ParamStr(1) = 'read-order' then TestReadOrder
      else if ParamStr(1) = 'bad-tag12' then TestTerminal(TLS1_2_VERSION, False, False)
      else if ParamStr(1) = 'bad-tag13' then TestTerminal(TLS1_3_VERSION, False, False)
      else if ParamStr(1) = 'eof12' then TestTerminal(TLS1_2_VERSION, True, False)
      else if ParamStr(1) = 'eof13' then TestTerminal(TLS1_3_VERSION, True, False)
      else if ParamStr(1) = 'bad-tag-active' then TestTerminal(TLS1_3_VERSION, False, True)
      else if ParamStr(1) = 'eof-active' then TestTerminal(TLS1_3_VERSION, True, True)
      else if ParamStr(1) = 'bad-tag-sync' then TestTerminal(TLS1_3_VERSION, False, False, 1)
      else if ParamStr(1) = 'eof-sync' then TestTerminal(TLS1_3_VERSION, True, False, 1)
      else if ParamStr(1) = 'bad-tag-send-fail' then TestTerminal(TLS1_3_VERSION, False, False, 2)
      else if ParamStr(1) = 'eof-send-fail' then TestTerminal(TLS1_3_VERSION, True, False, 2)
      else if ParamStr(1) = 'terminal-disconnect-error' then TestTerminal(TLS1_3_VERSION, False, False, 0, True)
      else if ParamStr(1) = 'handshake-tag12' then TestHandshakeTerminal
      else if ParamStr(1) = 'terminal-close-race' then TestTerminalCloseRace
      else if ParamStr(1) = 'terminal-release-last' then TestTerminalReleaseLast
      else if ParamStr(1) = 'terminal-prefix-race' then TestTerminalPrefixRace(True)
      else if ParamStr(1) = 'terminal-prefix-io-fail' then TestTerminalPrefixRace(False)
      else if ParamStr(1) = 'terminal-log-reentry' then TestTerminalLogReentry
      else if ParamStr(1) = 'terminal-log-throw' then TestTerminalLogBoundary(True)
      else if ParamStr(1) = 'terminal-log-thread' then TestTerminalLogBoundary(False)
      else if ParamStr(1) = 'managed-wrap' then TestManagedTlsQueue
      else if ParamStr(1) = 'managed-clear-pending' then TestManagedTlsClear(0)
      else if ParamStr(1) = 'managed-clear-cipher' then TestManagedTlsClear(1)
      else if ParamStr(1) = 'managed-clear-plain' then TestManagedTlsClear(2)
      else if ParamStr(1) = 'limits-write12' then TestWriteLimits(TLS1_2_VERSION, False)
      else if ParamStr(1) = 'limits-write13' then TestWriteLimits(TLS1_3_VERSION, False)
      else if ParamStr(1) = 'limits-close' then TestWriteLimits(TLS1_3_VERSION, True)
      else if ParamStr(1) = 'limits-want' then TestWriteLimitWant
      else if ParamStr(1) = 'limits-reentry' then TestWriteLimitReentry
      else if ParamStr(1) = 'limits-cipher-bytes' then TestCipherByteLimit
      else if ParamStr(1) = 'limits-cipher-count' then TestCipherCountLimit
      else if ParamStr(1) = 'limits-receive12' then TestReceiveLimit(TLS1_2_VERSION, False)
      else if ParamStr(1) = 'limits-receive13' then TestReceiveLimit(TLS1_3_VERSION, False)
      else if ParamStr(1) = 'limits-overflow12' then TestReceiveLimit(TLS1_2_VERSION, True)
      else if ParamStr(1) = 'limits-overflow13' then TestReceiveLimit(TLS1_3_VERSION, True)
      else if ParamStr(1) = 'limits-receive-count' then TestReceiveActiveLimit(True, False)
      else if ParamStr(1) = 'limits-receive-active' then TestReceiveActiveLimit(False, False)
      else if ParamStr(1) = 'limits-receive-close' then TestReceiveActiveLimit(True, True)
      else if ParamStr(1) = 'limits-config' then TestLimitConfiguration
      else if ParamStr(1) = 'limits-snapshot' then TestLimitSnapshot
      else if ParamStr(1) = 'limits-wrap' then TestLimitWrap
      else if ParamStr(1) = 'limits-concurrent' then TestLimitConcurrent
      else if ParamStr(1) = 'limits-terminal' then TestLimitTerminal
      else if ParamStr(1) = 'limits-write-count' then TestIndependentWriteLimit(True)
      else if ParamStr(1) = 'limits-write-bytes' then TestIndependentWriteLimit(False)
      else if ParamStr(1) = 'limits-physical-failure' then TestLimitFailure(0)
      else if ParamStr(1) = 'limits-callback-failure' then TestLimitFailure(1)
      else if ParamStr(1) = 'limits-received-failure' then TestLimitFailure(2)
      else if ParamStr(1) = 'limits-handshake-barrier' then TestLimitHandshakeBarrier
      else if ParamStr(1) = 'limits-terminal-active' then TestLimitTerminalActive
      else if ParamStr(1) = 'base-tls-limited' then TestRealBaseTlsLimit(True)
      else if ParamStr(1) = 'base-tls-unlimited' then TestRealBaseTlsLimit(False)
      else if ParamStr(1) = 'bench-ws' then RunWsBufferBench
      else if ParamStr(1) = 'bench-tls12' then RunTlsBufferBench(TLS1_2_VERSION)
      else if ParamStr(1) = 'bench-tls13' then RunTlsBufferBench(TLS1_3_VERSION)
      else if ParamStr(1) = 'probe-bio' then ProbeTlsPending
      else if ParamStr(1) = 'bench-tx12' then RunTlsOutputBench(TLS1_2_VERSION)
      else if ParamStr(1) = 'bench-tx13' then RunTlsOutputBench(TLS1_3_VERSION)
      else if ParamStr(1) = 'bench-control12' then RunTlsBufferBench(TLS1_2_VERSION, True)
      else if ParamStr(1) = 'bench-control13' then RunTlsBufferBench(TLS1_3_VERSION, True)
      else if ParamStr(1) = 'bench-large-rx12' then RunTlsBufferBench(TLS1_2_VERSION, False, True)
      else if ParamStr(1) = 'bench-large-rx13' then RunTlsBufferBench(TLS1_3_VERSION, False, True)
      else if ParamStr(1) = 'bench-large-tx12' then RunTlsOutputBench(TLS1_2_VERSION, True)
      else if ParamStr(1) = 'bench-large-tx13' then RunTlsOutputBench(TLS1_3_VERSION, True)
      else raise Exception.Create('unknown mode');
    finally
      TSSLTools.UnloadSSL;
    end;
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      {$IFDEF FPC}DumpExceptionBackTrace(Output);{$ENDIF}
      Halt(1);
    end;
  end;
end.
