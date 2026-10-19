{$IFDEF TLS_LIMITS_BASELINE}
type
  TCrossSslQueueLimits = record
    MaxWriteCount: Integer;
    MaxWriteBytes: Int64;
    MaxCipherCount: Integer;
    MaxCipherBytes: Int64;
    MaxReceivedCount: Integer;
    MaxReceivedBytes: Int64;
  end;
{$ENDIF}

procedure SetTlsLimits(const C: ICrossConnection; const L: TCrossSslQueueLimits);
begin
  {$IFNDEF TLS_LIMITS_BASELINE}
  (C as TCrossOpenSslConnection).SetSslQueueLimits(L);
  {$ENDIF}
end;

procedure CheckTlsUsage(const C: ICrossConnection; const W, WB, X, XB, R, RB: Int64);
{$IF DEFINED(CROSS_OPENSSL_SELFTEST) AND NOT DEFINED(TLS_LIMITS_BASELINE)}
var U: TArray<Int64>;
{$ENDIF}
begin
  {$IF DEFINED(CROSS_OPENSSL_SELFTEST) AND NOT DEFINED(TLS_LIMITS_BASELINE)}
  U := CrossOpenSslSelfTest_QueueUsage(C);
  Check((U[0] = W) and (U[1] = WB) and (U[2] = X)
    and ((XB < 0) or (U[3] = XB)) and (U[4] = R) and (U[5] = RB),
    Format('quota mismatch: %d/%d %d/%d %d/%d', [U[0], U[1], U[2], U[3], U[4], U[5]]));
  {$ENDIF}
end;

procedure LimitSend(const C: ICrossConnection; const S: string; const Calls, Failed: PInteger);
var CB: TCrossConnectionCallback;
begin
  CB := procedure(const AConnection: ICrossConnection; const OK: Boolean)
    begin Inc(Calls^); if not OK then Inc(Failed^); end;
  C.SendBytes(TEncoding.ASCII.GetBytes(S), CB);
end;

procedure TestWriteLimits(const Version: Integer; const Closing: Boolean);
var F: TTlsFixture; L: TCrossSslQueueLimits; Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(Version); Calls := 0; Failed := 0;
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits);
    L.MaxWriteCount := 2; L.MaxWriteBytes := 4;
    L.MaxCipherCount := 4; L.MaxCipherBytes := 1024;
    SetTlsLimits(F.Connection, L);
    F.Socket.DelayWrites := True;
    LimitSend(F.Connection, 'AB', @Calls, @Failed);
    LimitSend(F.Connection, 'CD', @Calls, @Failed);
    LimitSend(F.Connection, 'E', @Calls, @Failed);
    Check((Calls = 1) and (Failed = 1) and not F.Connection.IsClosed,
      'full write queue did not reject only the new item');
    CheckTlsUsage(F.Connection, 2, 4, 1, -1, 0, 0);
    if Closing then
    begin
      F.Connection.Close;
      Check((Calls = 2) and (Failed = 2), 'close settled active plaintext too early');
      CheckTlsUsage(F.Connection, 1, 2, 1, -1, 0, 0);
      F.Socket.CompleteNext(True);
      Check((Calls = 3) and (Failed = 3), 'late completion was not canceled exactly once');
    end else
    begin
      F.Socket.CompleteNext(True);
      LimitSend(F.Connection, 'EF', @Calls, @Failed);
      CheckTlsUsage(F.Connection, 2, 4, 1, -1, 0, 0);
      while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
      Check((Calls = 4) and (Failed = 1), 'quota was not restored after physical completion');
      Check(F.ReadPeer = 'ABCDEF', 'rejected plaintext entered native TLS stream');
    end;
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
    F.Connection.Close;
    Check((F.Connection as TCrossOpenSslConnection).RefCount = 1, 'limited write retained connection');
  finally F.Free; end;
end;

procedure TestWriteLimitWant;
var F: TTlsFixture; L: TCrossSslQueueLimits; Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION); Calls := 0; Failed := 0;
  OriginalWrite := SSL_write; SSL_write := TraceWrite; WantReads := 0;
  try
    L := Default(TCrossSslQueueLimits); L.MaxWriteCount := 1; L.MaxWriteBytes := 1;
    SetTlsLimits(F.Connection, L);
    LimitSend(F.Connection, 'A', @Calls, @Failed);
    LimitSend(F.Connection, 'B', @Calls, @Failed);
    Check((WantReads > 0) and (Calls = 1) and (Failed = 1), 'WANT item escaped total write capacity');
    CheckTlsUsage(F.Connection, 1, 1, 0, 0, 0, 0);
    F.Handshake;
    Check((Calls = 2) and (Failed = 1) and not WrongRetry, 'WANT quota/retry completion changed');
    Check(F.ReadPeer = 'A', 'WANT admission order changed');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally SSL_write := OriginalWrite; F.Free; end;
end;

procedure TestWriteLimitReentry;
var F: TTlsFixture; L: TCrossSslQueueLimits; CB: TCrossConnectionCallback; Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Calls := 0; Failed := 0;
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits); L.MaxWriteCount := 1; L.MaxWriteBytes := 1;
    L.MaxCipherCount := 1; L.MaxCipherBytes := 64;
    SetTlsLimits(F.Connection, L);
    CB := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        Inc(Calls); if not OK then Inc(Failed);
        if Calls < 128 then C.SendBytes(TEncoding.ASCII.GetBytes('A'), CB) else CB := nil;
      end;
    F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), CB);
    Check((Calls = 128) and (Failed = 0), 'completion did not return quota before reentry');
    Check(F.ReadPeer = AnsiString(StringOfChar('A', 128)), 'limited reentry changed plaintext');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally CB := nil; F.Free; end;
end;

procedure TestCipherByteLimit;
var F: TTlsFixture; L: TCrossSslQueueLimits; Calls, Failed: Integer; OutData: TBytes;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Calls := 0; Failed := 0;
  try
    F.Handshake; F.Socket.TakeOutput;
    L := Default(TCrossSslQueueLimits); L.MaxCipherBytes := 1; L.MaxWriteCount := 2;
    SetTlsLimits(F.Connection, L);
    LimitSend(F.Connection, 'A', @Calls, @Failed);
    Check(F.Connection.IsClosed and (Calls = 1) and (Failed = 1), 'oversized native ciphertext did not terminate');
    OutData := F.Socket.TakeOutput;
    Check(Length(OutData) = 0, 'over-budget ciphertext was submitted');
    LimitSend(F.Connection, 'B', @Calls, @Failed);
    Check((Calls = 2) and (Failed = 2), 'send after cipher overflow was admitted');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Free; end;
end;

procedure TestCipherCountLimit;
var F: TTlsFixture; L: TCrossSslQueueLimits; H: TLibHandle; Renegotiate: TRenegotiate;
  Data: TBytes; N, Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_2_VERSION); Calls := 0; Failed := 0;
  H := SafeLoadLibrary(ParamStr(2));
  try
    {$IFDEF FPC}@Renegotiate := GetProcedureAddress(H, 'SSL_renegotiate');
    {$ELSE}@Renegotiate := GetProcAddress(H, 'SSL_renegotiate');{$ENDIF}
    Check(Assigned(Renegotiate), 'native renegotiate unavailable');
    F.Handshake;
    L := Default(TCrossSslQueueLimits); L.MaxCipherCount := 1; L.MaxWriteCount := 2;
    SetTlsLimits(F.Connection, L); F.Socket.DelayWrites := True;
    LimitSend(F.Connection, 'A', @Calls, @Failed);
    LimitSend(F.Connection, 'B', @Calls, @Failed);
    Check(Renegotiate(F.Peer) = 1, 'native renegotiate rejected'); SSL_do_handshake(F.Peer);
    N := BIO_pending(F.PeerOut); SetLength(Data, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @Data[0], N) = N), 'native protocol output missing');
    F.Socket.Inject(F.Connection, Data);
    Check(F.Connection.IsClosed and (Calls = 1) and (Failed = 1), 'protocol output ignored active cipher count');
    CheckTlsUsage(F.Connection, 1, 1, 1, -1, 0, 0);
    F.Socket.CompleteNext(True);
    Check((Calls = 2) and (Failed = 2), 'cipher overflow lost active completion');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Free; FreeLibrary(H); end;
end;

procedure TestReceiveLimit(const Version: Integer; const Overflow: Boolean);
var F: TTlsFixture; L: TCrossSslQueueLimits; S: AnsiString;
begin
  F := TTlsFixture.Create(Version);
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits); L.MaxReceivedCount := 1; L.MaxReceivedBytes := 16384;
    SetTlsLimits(F.Connection, L);
    S := AnsiString(StringOfChar('A', 16384));
    if Overflow then S := S + 'B';
    F.SendPeer(S);
    Check(F.Socket.Plaintext = AnsiString(StringOfChar('A', 16384)), 'receive limit did not retain bounded valid prefix');
    Check(F.Connection.IsClosed = Overflow, 'receive boundary overflow/normal result differs');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
    if not Overflow then
    begin
      if Version = TLS1_3_VERSION then F.KeyUpdate;
      F.SendPeer('C');
      Check(Length(F.Socket.Plaintext) = 16385, 'receive quota not reusable after callback');
    end;
  finally F.Free; end;
end;

procedure TestReceiveActiveLimit(const CountLimit, CloseInside: Boolean);
var F: TTlsFixture; L: TCrossSslQueueLimits; Entered: Boolean;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Entered := False;
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits);
    if CountLimit then L.MaxReceivedCount := 1 else L.MaxReceivedBytes := 1;
    SetTlsLimits(F.Connection, L);
    F.Socket.ReceivedAction := procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        if Entered then Exit; Entered := True;
        CheckTlsUsage(C, 0, 0, 0, 0, 1, 1);
        if CloseInside then C.Close else F.SendPeer('B');
        CheckTlsUsage(C, 0, 0, 0, 0, 1, 1);
      end;
    F.SendPeer('A');
    Check(Entered and F.Connection.IsClosed and (F.Socket.Plaintext = 'A'), 'active receive buffer escaped quota or was repeated');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Socket.ReceivedAction := nil; F.Free; end;
end;

procedure TestLimitConfiguration;
var F: TTlsFixture; L: TCrossSslQueueLimits; Raised: Boolean; Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Calls := 0; Failed := 0;
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits); L.MaxWriteBytes := -1;
    Raised := False;
    try SetTlsLimits(F.Connection, L); except on E: EArgumentException do Raised := True; end;
    Check(Raised, 'negative TLS capacity accepted');
    L.MaxWriteBytes := 1; SetTlsLimits(F.Connection, L);
    F.Socket.DelayWrites := True; LimitSend(F.Connection, 'A', @Calls, @Failed);
    Raised := False;
    try SetTlsLimits(F.Connection, Default(TCrossSslQueueLimits)); except on E: EInvalidOpException do Raised := True; end;
    Check(Raised, 'live capacity changed without accounting existing item');
    F.Socket.CompleteNext(True);
    SetTlsLimits(F.Connection, Default(TCrossSslQueueLimits));
    LimitSend(F.Connection, 'AB', @Calls, @Failed); F.Socket.CompleteNext(True);
    Check((Calls = 2) and (Failed = 0), 'idle capacity change failed');
    L := Default(TCrossSslQueueLimits);
    L.MaxWriteBytes := Int64(1) shl 40;
    L.MaxCipherBytes := Int64(1) shl 40;
    L.MaxReceivedBytes := Int64(1) shl 40;
    SetTlsLimits(F.Connection, L);
    F.SendPeer('A');
    LimitSend(F.Connection, 'AB', @Calls, @Failed); F.Socket.CompleteNext(True);
    Check((Calls = 3) and (Failed = 0) and (F.Socket.Plaintext = 'A'), '64-bit capacity was narrowed or preallocated');
  finally F.Free; end;
end;

procedure TestLimitSnapshot;
var S: TMemoryTlsSocket; C: ICrossConnection; L: TCrossSslQueueLimits; Raised: Boolean;
begin
  S := TMemoryTlsSocket.Create;
  try
    L := Default(TCrossSslQueueLimits); L.MaxCipherBytes := 1;
    {$IFNDEF TLS_LIMITS_BASELINE}S.SslQueueLimits := L;{$ENDIF}
    C := S.StartClient;
    Check(C.IsClosed and (Length(S.TakeOutput) = 0), 'new connection did not snapshot ciphertext capacity');
    Raised := False;
    {$IFNDEF TLS_LIMITS_BASELINE}
    try S.SslQueueLimits := Default(TCrossSslQueueLimits); except on E: Exception do Raised := True; end;
    {$ENDIF}
    Check(Raised, 'socket configuration changed after first TLS connection');
    CheckTlsUsage(C, 0, 0, 0, 0, 0, 0);
  finally if C <> nil then C.Close; C := nil; S.Free; end;
end;

procedure TestLimitWrap;
var F: TTlsFixture; L: TCrossSslQueueLimits; I, Destroyed, Calls, Rejected, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  Destroyed := 0; Calls := 0; Rejected := 0; Failed := 0;
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits); L.MaxWriteCount := 64; L.MaxWriteBytes := 64;
    L.MaxCipherCount := 1; L.MaxCipherBytes := 64;
    SetTlsLimits(F.Connection, L); F.Socket.DelayWrites := True;
    for I := 0 to 63 do AddManagedTlsWrite(F, I, @Destroyed, @Calls);
    for I := 0 to 2047 do
    begin
      LimitSend(F.Connection, 'X', @Rejected, @Failed);
      Check((Rejected = I + 1) and (Failed = I + 1), 'fixed-depth queue admitted over budget');
      F.Socket.CompleteNext(True);
      AddManagedTlsWrite(F, I + 64, @Destroyed, @Calls);
    end;
    CheckTlsUsage(F.Connection, 64, 64, 1, -1, 0, 0);
    Check((Calls = 2048) and (Destroyed = 2048), 'limited wrap retained completed capture');
    F.Connection.Close;
    Check((Calls = 2111) and (Destroyed = 2111), 'limited close retained queued capture');
    CheckTlsUsage(F.Connection, 1, 1, 1, -1, 0, 0);
    F.Socket.CompleteNext(True);
    Check((Calls = 2112) and (Destroyed = 2112), 'limited active completion retained capture');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
    F.Connection := nil;
    Check(F.Socket.DestroyedConnections = 1, 'limited queue retained closed connection');
  finally F.Free; end;
end;

procedure TestLimitConcurrent;
var F: TTlsFixture; L: TCrossSslQueueLimits; Threads: array[0..31] of TWriteThread;
  Started, Joined: array[0..31] of Boolean;
  I, Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); FillChar(Threads, SizeOf(Threads), 0);
  FillChar(Started, SizeOf(Started), 0); FillChar(Joined, SizeOf(Joined), 0);
  try
    F.Handshake;
    L := Default(TCrossSslQueueLimits); L.MaxWriteCount := 8; L.MaxWriteBytes := 8;
    SetTlsLimits(F.Connection, L); F.Socket.DelayWrites := True;
    for I := 0 to High(Threads) do Threads[I] := TWriteThread.Create(F.Connection, 'A');
    for I := 0 to High(Threads) do begin Threads[I].Start; Started[I] := True; end;
    Calls := 0; Failed := 0;
    for I := 0 to High(Threads) do
    begin
      Threads[I].WaitFor; Joined[I] := True; Check(Threads[I].ErrorText = '', Threads[I].ErrorText);
      Inc(Calls, Threads[I].Calls); Inc(Failed, Threads[I].Failures);
    end;
    Check((Calls = 24) and (Failed = 24), 'parallel admission exceeded count/bytes limit');
    CheckTlsUsage(F.Connection, 8, 8, 0, 0, 0, 0);
    F.Connection.Close; while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
    for I := 0 to High(Threads) do
      Check((Threads[I].Calls = 1) and (Threads[I].Failures = 1), 'concurrent close completion mismatch');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally
    F.Connection.Close; while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(False);
    for I := 0 to High(Threads) do
      if Threads[I] <> nil then
      begin
        if not Started[I] then Threads[I].Start;
        // FPC POSIX 的 WaitFor 会 join；不能对已被回收的 pthread 再 join。
        if not Joined[I] then Threads[I].WaitFor;
        Threads[I].Free;
      end;
    F.Free;
  end;
end;

procedure TestLimitTerminal;
var F: TTlsFixture; L: TCrossSslQueueLimits; Data: TBytes; S: AnsiString; N: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    F.Handshake; F.Socket.TakeOutput;
    L := Default(TCrossSslQueueLimits); L.MaxReceivedBytes := 1; L.MaxCipherBytes := 1;
    SetTlsLimits(F.Connection, L);
    S := 'A'; Check(SSL_write(F.Peer, PAnsiChar(S), 1) = 1, 'terminal prefix generation failed');
    SSL_shutdown(F.Peer);
    N := BIO_pending(F.PeerOut); SetLength(Data, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @Data[0], N) = N), 'terminal record missing');
    F.Socket.Inject(F.Connection, Data);
    Check((F.Socket.Plaintext = 'A') and F.Connection.IsClosed, 'full receive quota dropped close_notify prefix');
    Check(Length(F.Socket.TakeOutput) = 0, 'terminal alert bypassed cipher byte capacity');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Free; end;
end;

procedure TestIndependentWriteLimit(const CountOnly: Boolean);
var F: TTlsFixture; L: TCrossSslQueueLimits; Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Calls := 0; Failed := 0;
  try
    F.Handshake; L := Default(TCrossSslQueueLimits);
    if CountOnly then L.MaxWriteCount := 1 else L.MaxWriteBytes := 3;
    SetTlsLimits(F.Connection, L); F.Socket.DelayWrites := True;
    LimitSend(F.Connection, 'AA', @Calls, @Failed);
    LimitSend(F.Connection, 'BB', @Calls, @Failed);
    Check((Calls = 1) and (Failed = 1), 'independent count/byte capacity not enforced');
    F.Socket.CompleteNext(True);
    LimitSend(F.Connection, 'CCC', @Calls, @Failed); F.Socket.CompleteNext(True);
    Check((Calls = 3) and (Failed = 1) and (F.ReadPeer = 'AACCC'), 'independent quota was not reusable');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Free; end;
end;

procedure TestLimitFailure(const Kind: Integer);
var F: TTlsFixture; L: TCrossSslQueueLimits; CB: TCrossConnectionCallback; Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Calls := 0; Failed := 0;
  try
    F.Handshake; L := Default(TCrossSslQueueLimits);
    L.MaxWriteCount := 2; L.MaxCipherCount := 2; L.MaxReceivedCount := 2;
    SetTlsLimits(F.Connection, L);
    if Kind = 0 then
    begin
      F.Socket.FailWrites := True;
      LimitSend(F.Connection, 'A', @Calls, @Failed);
      Check((Calls = 1) and (Failed = 1), 'physical refusal did not settle plaintext');
    end else
    if Kind = 1 then
    begin
      F.Socket.DelayWrites := True;
      CB := procedure(const C: ICrossConnection; const OK: Boolean)
        begin Inc(Calls); if not OK then Inc(Failed); raise Exception.Create('quota callback failure'); end;
      F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), CB);
      LimitSend(F.Connection, 'B', @Calls, @Failed);
      F.Socket.CompleteNext(True);
      Check((Calls = 2) and (Failed = 1), 'throwing quota callback repeated success or lost queued failure');
    end else
    begin
      F.Socket.RaiseReceived := True;
      try F.SendPeer('A'); except on E: Exception do Inc(Calls); end;
      Check(Calls = 1, 'received exception not exercised');
    end;
    Check(F.Connection.IsClosed, 'limited failure did not terminate connection');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally CB := nil; F.Free; end;
end;

procedure TestLimitHandshakeBarrier;
var F: TTlsFixture; L: TCrossSslQueueLimits; I, Calls, Failed: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION); Calls := 0; Failed := 0;
  try
    L := Default(TCrossSslQueueLimits); L.MaxCipherCount := 1; L.MaxWriteCount := 2;
    SetTlsLimits(F.Connection, L); F.Socket.DelayWrites := True;
    LimitSend(F.Connection, 'A', @Calls, @Failed);
    for I := 0 to 19 do
    begin
      F.Step;
      if F.Connection.IsClosed then Break;
    end;
    Check(F.PeerDone and F.Connection.IsClosed and (F.Socket.ConnectedCalls = 0),
      'empty handshake completion barrier escaped item capacity');
    while F.Socket.PendingCount > 0 do F.Socket.CompleteNext(True);
    Check((Calls = 1) and (Failed = 1), 'handshake capacity lost pending write');
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Free; end;
end;

procedure TestLimitTerminalActive;
var F: TTlsFixture; L: TCrossSslQueueLimits; Data: TBytes; N: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    F.Handshake; F.Socket.TakeOutput;
    L := Default(TCrossSslQueueLimits); L.MaxCipherCount := 1; L.MaxCipherBytes := 1024;
    SetTlsLimits(F.Connection, L); F.Socket.DelayWrites := True;
    SSL_shutdown(F.Peer);
    N := BIO_pending(F.PeerOut); SetLength(Data, N);
    Check((N > 0) and (BIO_read(F.PeerOut, @Data[0], N) = N), 'native close_notify missing');
    F.Socket.Inject(F.Connection, Data);
    Check(F.Connection.IsClosed and (F.Socket.PendingCount = 1), 'terminal output was not sent/closed promptly');
    CheckTlsUsage(F.Connection, 0, 0, 1, -1, 0, 0);
    F.Socket.CompleteNext(True);
    CheckTlsUsage(F.Connection, 0, 0, 0, 0, 0, 0);
  finally F.Free; end;
end;
