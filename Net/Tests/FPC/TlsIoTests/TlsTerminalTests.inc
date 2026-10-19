type
  TSslRead = function(ASsl: PSSL; ABuf: Pointer; ALen: Integer): Integer; cdecl;
  TTerminalInputThread = class(TThread)
  public
    Socket: TMemoryTlsSocket;
    Connection: ICrossConnection;
    Data: TBytes;
    ErrorText: string;
    procedure Execute; override;
  end;
var
  TerminalRead: TSslRead;
  TerminalWrite: TSslWrite;
  TerminalHandshake: TRenegotiate;
  TerminalShutdown: TRenegotiate;
  TerminalPeer: PSSL;
  NativeReads, NativeWrites, NativeHandshakes, NativeShutdowns, NativeReadError: Integer;

procedure TTerminalInputThread.Execute;
begin
  try
    Socket.Inject(Connection, Data);
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
end;

function CountRead(ASsl: PSSL; ABuf: Pointer; ALen: Integer): Integer; cdecl;
begin
  if ASsl <> TerminalPeer then Inc(NativeReads);
  Result := TerminalRead(ASsl, ABuf, ALen);
  if (ASsl <> TerminalPeer) and (Result <= 0) then
    NativeReadError := SSL_get_error(ASsl, Result);
end;

function CountWrite(ASsl: PSSL; const ABuf: Pointer; ALen: Integer): Integer; cdecl;
begin
  if ASsl <> TerminalPeer then Inc(NativeWrites);
  Result := TerminalWrite(ASsl, ABuf, ALen);
end;

function CountHandshake(ASsl: PSSL): Integer; cdecl;
begin
  if ASsl <> TerminalPeer then Inc(NativeHandshakes);
  Result := TerminalHandshake(ASsl);
end;

function CountShutdown(ASsl: PSSL): Integer; cdecl;
begin
  if ASsl <> TerminalPeer then Inc(NativeShutdowns);
  Result := TerminalShutdown(ASsl);
end;

procedure TestTerminal(const AVersion: Integer; const ACloseNotify, AActive: Boolean;
  const ATransportMode: Integer = 0; const ARaiseClose: Boolean = False);
var
  F: TTlsFixture;
  LInput, LOutput: TBytes;
  LText: AnsiString;
  N, LResult, LError, LReads, LWrites, LHandshakes: Integer;
  A, B, LFailed, LLate, LReentrant: Integer;
  LCallbackA, LCallbackB, LLateCallback: TCrossConnectionCallback;
  LByte: Byte;
begin
  F := TTlsFixture.Create(AVersion);
  A := 0; B := 0; LFailed := 0; LLate := 0; LReentrant := 0;
  TerminalRead := SSL_read; TerminalWrite := SSL_write;
  TerminalHandshake := SSL_do_handshake;
  TerminalShutdown := SSL_shutdown;
  try
    F.Handshake;
    TerminalPeer := F.Peer;
    NativeReads := 0; NativeWrites := 0; NativeHandshakes := 0; NativeShutdowns := 0;
    NativeReadError := SSL_ERROR_NONE;
    SSL_read := CountRead; SSL_write := CountWrite; SSL_do_handshake := CountHandshake;
    SSL_shutdown := CountShutdown;
    F.Socket.DelayWrites := ATransportMode = 0;
    F.Socket.FailWrites := ATransportMode = 2;
    F.Socket.RaiseDisconnected := ARaiseClose;
    if AActive then
    begin
      LCallbackA := procedure(const C: ICrossConnection; const OK: Boolean)
        begin Inc(A); if not OK then Inc(LFailed); end;
      LCallbackB := procedure(const C: ICrossConnection; const OK: Boolean)
        begin Inc(B); if not OK then Inc(LFailed); end;
      F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallbackA);
      F.Connection.SendBytes(TEncoding.ASCII.GetBytes('B'), LCallbackB);
      Check(F.Socket.PendingCount = 1, 'terminal setup submitted concurrent ciphertext');
      F.Socket.TakeOutput;
    end;
    // 同批有效前缀必须先交付；损坏记录及其后续输入不能被当成应用数据。
    LText := 'P';
    Check(SSL_write(F.Peer, PAnsiChar(LText), 1) = 1, 'terminal prefix write failed');
    if ACloseNotify then
      Check(SSL_shutdown(F.Peer) >= 0, 'native peer close_notify failed')
    else
    begin
      LText := 'X';
      Check(SSL_write(F.Peer, PAnsiChar(LText), 1) = 1, 'terminal damaged write failed');
    end;
    N := BIO_pending(F.PeerOut);
    SetLength(LInput, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @LInput[0], N) = N), 'terminal peer output missing');
    if not ACloseNotify then LInput[N - 1] := LInput[N - 1] xor $80;
    F.Socket.ReceivedAction := procedure(const C: ICrossConnection; const OK: Boolean)
      var LWriteCallback: TCrossConnectionCallback;
      begin
        // 前缀回调仍在 Close 之前，终态标记已必须阻止重入 SSL I/O。
        LReads := NativeReads; LWrites := NativeWrites; LHandshakes := NativeHandshakes;
        F.Socket.Inject(C, LInput);
        LWriteCallback := procedure(const C2: ICrossConnection; const OK2: Boolean)
          begin Inc(LReentrant); Check(not OK2, 'terminal receive reentry send succeeded'); end;
        C.SendBytes(TEncoding.ASCII.GetBytes('reentry'), LWriteCallback);
        F.Socket.TriggerConnected(C);
        Check((NativeReads = LReads) and (NativeWrites = LWrites) and (NativeHandshakes = LHandshakes),
          'receive callback reentered native SSL after terminal result');
      end;
    F.Socket.Inject(F.Connection, LInput);
    Writeln('TERMINAL native_error=', NativeReadError, ' closed=', F.Connection.IsClosed,
      ' physical=', F.Socket.PendingCount, ' received=', string(F.Socket.Plaintext));
    if ACloseNotify then Check(NativeReadError = SSL_ERROR_ZERO_RETURN, 'native EOF was not exercised')
    else Check(NativeReadError = SSL_ERROR_SSL, 'native bad tag was not exercised');
    Check(NativeShutdowns = Ord(ACloseNotify), 'fatal reused SSL_shutdown or EOF reply was repeated');
    Check(F.Connection.IsClosed, 'TLS terminal input left connection open waiting for peer');
    Check(F.Socket.Plaintext = 'P', 'authenticated prefix was lost or invalid data delivered');
    Check(LReentrant = 1, 'terminal receive reentry completion count differs');
    Check(F.Socket.DisconnectedCalls = 1, 'terminal disconnected notification count differs');
    if AActive then
      Check((A = 0) and (B = 1) and (LFailed = 1), 'terminal settled active write before physical completion');
    LReads := NativeReads; LWrites := NativeWrites; LHandshakes := NativeHandshakes;
    LLateCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LLate); Check(not OK, 'post-terminal send succeeded'); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('late'), LLateCallback);
    F.Socket.Inject(F.Connection, LInput);
    F.Socket.TriggerConnected(F.Connection);
    Check((NativeReads = LReads) and (NativeWrites = LWrites) and (NativeHandshakes = LHandshakes),
      'native SSL I/O continued after terminal state');
    Check((LLate = 1) and (F.Socket.Plaintext = 'P'), 'post-terminal callback/input was repeated');
    LOutput := F.Socket.TakeOutput;
    if not AActive and (ATransportMode <> 2) then
    begin
      Check(Length(LOutput) > 0, 'idle terminal did not attempt native alert output');
      Check(BIO_write(F.PeerIn, @LOutput[0], Length(LOutput)) = Length(LOutput), 'terminal alert input failed');
      ERR_clear_error();
      LResult := SSL_read(F.Peer, @LByte, 1);
      LError := SSL_get_error(F.Peer, LResult);
      if ACloseNotify then Check(LError = SSL_ERROR_ZERO_RETURN, 'peer rejected close_notify reply')
      else Check(LError = SSL_ERROR_SSL, 'peer did not receive fatal alert');
    end else
      Check(Length(LOutput) = 0, 'terminal alert bypassed active ciphertext');
    F.Connection.Close;
    while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
    if AActive then
      Check((A = 1) and (B = 1) and (LFailed = 2), 'terminal late physical completion was not canceled once');
    Check(F.Connection.IsClosed and (F.Socket.DisconnectedCalls = 1), 'late completion reopened terminal connection');
    Check((F.Connection as TCrossOpenSslConnection).RefCount = 1, 'terminal completion retained connection');
  finally
    SSL_read := TerminalRead; SSL_write := TerminalWrite; SSL_do_handshake := TerminalHandshake;
    SSL_shutdown := TerminalShutdown;
    F.Socket.ReceivedAction := nil;
    F.Free;
  end;
end;

procedure TestHandshakeTerminal;
var
  F: TTlsFixture;
  LInput, LOutput: TBytes;
  LCallback: TCrossConnectionCallback;
  LCalls, LFailed, N: Integer;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION);
  LCalls := 0; LFailed := 0;
  try
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailed); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('B'), LCallback);
    F.Step;
    Check(F.Connection.ConnectStatus = csHandshaking, 'handshake terminal setup completed too early');
    LOutput := F.Socket.TakeOutput;
    Check((Length(LOutput) > 0) and (BIO_write(F.PeerIn, @LOutput[0], Length(LOutput)) = Length(LOutput)),
      'handshake client Finished missing');
    ERR_clear_error();
    Check(SSL_do_handshake(F.Peer) = 1, 'native server handshake did not complete');
    N := BIO_pending(F.PeerOut);
    SetLength(LInput, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @LInput[0], N) = N), 'server Finished missing');
    LInput[N - 1] := LInput[N - 1] xor $80;
    F.Socket.DelayWrites := True;
    F.Socket.Inject(F.Connection, LInput);
    Check(F.Connection.IsClosed, 'handshake fatal waited for alert completion');
    Check((LCalls = 2) and (LFailed = 2), 'handshake terminal lost pending write completion');
    Check(F.Socket.ConnectedCalls = 0, 'handshake fatal promoted unusable connection');
    Check(F.Socket.PendingCount = 1, 'handshake fatal did not attempt idle alert');
    F.Socket.CompleteNext(True);
    Check((LCalls = 2) and (F.Socket.ConnectedCalls = 0), 'late alert completion promoted failed handshake');
  finally
    F.Free;
  end;
end;

function MakePeerEof(const F: TTlsFixture): TBytes;
var
  LText: AnsiString;
  N: Integer;
begin
  LText := 'P';
  Check(SSL_write(F.Peer, PAnsiChar(LText), 1) = 1, 'race prefix write failed');
  Check(SSL_shutdown(F.Peer) >= 0, 'race close_notify failed');
  N := BIO_pending(F.PeerOut);
  SetLength(Result, N);
  Check((N > 0) and (BIO_read(F.PeerOut, @Result[0], N) = N), 'race EOF output missing');
end;

procedure TestTerminalCloseRace;
var
  F: TTlsFixture;
  LThread: TTerminalInputThread;
  LCallbackA, LCallbackB: TCrossConnectionCallback;
  A, B, LFailed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LThread := nil;
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
    F.Socket.ReceivedAction := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        F.Socket.FirstEntered.SetEvent;
        Check(F.Socket.ReleaseFirst.WaitFor(5000) = TWaitResult.wrSignaled, 'terminal race release timeout');
      end;
    LThread := TTerminalInputThread.Create(True);
    LThread.Socket := F.Socket; LThread.Connection := F.Connection;
    LThread.Data := MakePeerEof(F);
    LThread.Start;
    Check(F.Socket.FirstEntered.WaitFor(5000) = TWaitResult.wrSignaled, 'terminal receive did not reach barrier');
    F.Connection.Close;
    Check((A = 0) and (B = 1), 'concurrent Close released active write too soon');
    F.Socket.CompleteNext(True);
    Check((A = 1) and (B = 1) and (LFailed = 2), 'concurrent terminal/Close completion differs');
    F.Socket.ReleaseFirst.SetEvent;
    LThread.WaitFor;
    Check(LThread.ErrorText = '', LThread.ErrorText);
    Check(F.Connection.IsClosed and (F.Socket.DisconnectedCalls = 1), 'terminal race reopened or double-closed');
    Check(F.Socket.Plaintext = 'P', 'terminal race repeated prefix');
  finally
    F.Socket.ReleaseFirst.SetEvent;
    if LThread <> nil then begin LThread.WaitFor; LThread.Free; end;
    F.Socket.ReceivedAction := nil;
    F.Free;
  end;
end;

procedure TestTerminalReleaseLast;
var
  F: TTlsFixture;
  LInput: TBytes;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    F.Handshake;
    F.Socket.DelayWrites := True;
    F.Socket.ReceivedAction := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        F.Connection := nil;
        Check(F.Socket.DestroyedConnections = 0, 'terminal callback destroyed current connection');
      end;
    LInput := MakePeerEof(F);
    F.Socket.Inject(F.Connection, LInput);
    Check((F.Connection = nil) and (F.Socket.DestroyedConnections = 0), 'terminal alert ownership lost');
    Check(F.Socket.PendingCount = 1, 'terminal alert physical completion missing');
    F.Socket.CompleteNext(True);
    Check(F.Socket.DestroyedConnections = 1, 'terminal alert retained last connection reference');
    Check(F.Socket.DisconnectedCalls = 1, 'terminal release-last disconnected count differs');
  finally
    F.Socket.ReceivedAction := nil;
    F.Free;
  end;
end;

procedure TestTerminalPrefixRace(const APhysicalSuccess: Boolean);
{$IFDEF CROSS_OPENSSL_SELFTEST}
var
  F: TTlsFixture;
  LInput: TBytes;
  LCallback: TCrossConnectionCallback;
  LCalls, LFailed, LHookCalls: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LCalls := 0; LFailed := 0; LHookCalls := 0;
  try
    F.Handshake;
    F.Socket.DelayWrites := True;
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailed); end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('B'), LCallback);
    LInput := MakePeerEof(F);
    CrossOpenSslSelfTest_BeforeReceived := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        CrossOpenSslSelfTest_BeforeReceived := nil;
        Inc(LHookCalls);
        Check(F.Socket.Plaintext = '', 'terminal prefix was already published before barrier');
        F.Socket.CompleteNext(APhysicalSuccess);
      end;
    F.Socket.Inject(F.Connection, LInput);
    Check(LHookCalls = 1, 'terminal prefix scheduling hook missing');
    if APhysicalSuccess then
      Check(F.Socket.Plaintext = 'P', 'TLS-only completion failure discarded authenticated prefix')
    else
      Check(F.Socket.Plaintext = '', 'real transport failure did not cancel pending prefix');
    Check(F.Connection.IsClosed, 'prefix completion race left connection open');
    Check((LCalls = 2) and (LFailed = 2), 'prefix completion race repeated or lost write completion');
    Check(F.Socket.DisconnectedCalls = 1, 'prefix completion race repeated close');
  finally
    CrossOpenSslSelfTest_BeforeReceived := nil;
    F.Free;
  end;
end;
{$ELSE}
begin
  raise Exception.Create('terminal prefix scheduling requires CROSS_OPENSSL_SELFTEST');
end;
{$ENDIF}

procedure TestTerminalLogReentry;
var
  F: TTlsFixture;
  LInput: TBytes;
  LText: AnsiString;
  LEnabled: Boolean;
  LCalls, LFailures, LLogs, N: Integer;
  LCallback: TCrossConnectionCallback;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LEnabled := CrossSocketLogEnabled;
  TerminalWrite := SSL_write;
  LCalls := 0; LFailures := 0; LLogs := 0;
  try
    F.Handshake;
    LText := 'X';
    Check(SSL_write(F.Peer, PAnsiChar(LText), 1) = 1, 'logger bad-tag write failed');
    N := BIO_pending(F.PeerOut);
    SetLength(LInput, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @LInput[0], N) = N), 'logger bad-tag input missing');
    LInput[N - 1] := LInput[N - 1] xor $80;
    TerminalPeer := F.Peer; NativeWrites := 0;
    SSL_write := CountWrite;
    LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailures); end;
    _SetCrossLogger(procedure(const S: string)
      begin
        CrossSocketLogEnabled := False;
        Inc(LLogs);
        F.Connection.SendBytes(TEncoding.ASCII.GetBytes('logger'), LCallback);
      end);
    CrossSocketLogEnabled := True;
    F.Socket.Inject(F.Connection, LInput);
    Check(LLogs = 1, 'fatal logger callback missing');
    Check(NativeWrites = 0, 'fatal logger reentered native SSL_write');
    Check((LCalls = 1) and (LFailures = 1) and F.Connection.IsClosed, 'fatal logger send did not fail once');
  finally
    _SetCrossLogger(nil);
    CrossSocketLogEnabled := LEnabled;
    SSL_write := TerminalWrite;
    F.Free;
  end;
end;

procedure TestTerminalLogBoundary(const AThrow: Boolean);
var
  F: TTlsFixture;
  LInput: TBytes;
  LText, LPrefixAtLog: AnsiString;
  LEnabled, LRaised, LCompletedInLog: Boolean;
  LLogs, N: Integer;
  LThread: TWriteThread;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LEnabled := CrossSocketLogEnabled;
  TerminalWrite := SSL_write;
  LThread := nil;
  LLogs := 0; LRaised := False; LCompletedInLog := False;
  try
    F.Handshake;
    F.Socket.DelayWrites := True;
    LText := 'P';
    Check(SSL_write(F.Peer, PAnsiChar(LText), 1) = 1, 'logger prefix write failed');
    LText := 'X';
    Check(SSL_write(F.Peer, PAnsiChar(LText), 1) = 1, 'logger bad-tag write failed');
    N := BIO_pending(F.PeerOut);
    SetLength(LInput, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @LInput[0], N) = N), 'logger boundary input missing');
    LInput[N - 1] := LInput[N - 1] xor $80;
    TerminalPeer := F.Peer; NativeWrites := 0;
    SSL_write := CountWrite;
    _SetCrossLogger(procedure(const S: string)
      begin
        Inc(LLogs);
        if LLogs > 1 then Exit;
        LPrefixAtLog := F.Socket.Plaintext;
        if AThrow then raise Exception.Create('fatal logger test exception');
        LThread := TWriteThread.Create(F.Connection, 'logger-thread');
        LThread.Start;
        // 只用有界等待检测锁依赖；旧代码超时后退出日志，使后台线程可安全回收。
        LCompletedInLog := LThread.Returned.WaitFor(1500) = TWaitResult.wrSignaled;
      end);
    CrossSocketLogEnabled := True;
    try
      F.Socket.Inject(F.Connection, LInput);
    except
      on E: Exception do LRaised := True;
    end;
    if LThread <> nil then LThread.WaitFor;
    Writeln('LOGGER raised=', LRaised, ' thread_completed=', LCompletedInLog,
      ' prefix=', string(F.Socket.Plaintext), ' calls=', LLogs);
    Check(not LRaised, 'fatal logger exception escaped TLS receive');
    if not AThrow then
    begin
      Check(LCompletedInLog, 'fatal logger waited on Send blocked by SSL lock');
      Check((LThread.Calls = 1) and (LThread.Failures = 1) and (LThread.ErrorText = ''),
        'logger thread send did not fail once');
    end;
    Check((F.Socket.Plaintext = 'P') and (LPrefixAtLog = 'P'), 'fatal logging lost or preceded authenticated prefix');
    Check((LLogs = 1) and (NativeWrites = 0), 'fatal log repeated or native SSL_write resumed');
    Check(F.Connection.IsClosed, 'logger boundary left TLS connection open');
    Check(F.Socket.PendingCount = 1, 'logger boundary skipped best-effort alert');
    while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
    F.Socket.Inject(F.Connection, LInput);
    F.Connection.Close;
    Check((LLogs = 1) and (F.Socket.DisconnectedCalls = 1), 'late terminal work repeated logger/close');
  finally
    _SetCrossLogger(nil);
    CrossSocketLogEnabled := LEnabled;
    SSL_write := TerminalWrite;
    if LThread <> nil then begin LThread.WaitFor; LThread.Free; end;
    F.Free;
  end;
end;
