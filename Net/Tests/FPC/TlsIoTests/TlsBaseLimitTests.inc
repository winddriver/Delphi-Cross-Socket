{$IFDEF CROSS_CAPACITY_TESTS}
type
  // 使用真实后端；不覆盖Send、DirectSend或原生TLS函数。
  TBaseLimitTlsSocket = class(TCrossOpenSslSocket)
  private
    FGuard: ILock;
    FChanged: IEvent;
    FConnection, FRejectedConnection: ICrossConnection;
    FPayload: TBytes;
    FReceived: AnsiString;
    FError: string;
    FConnected, FClosed, FPingCalls, FPingFailed, FArmCalls, FArmFailed: Integer;
    FBigCalls, FBigFailed, FTailCalls, FTailFailed, FLateCalls: Integer;
    FRejected, FRejectedBytes: Integer;
    FRoundTrip, FPeerConfirmed, FQueuedBeforeReturn: Boolean;
    procedure RecordError(const S: string);
    procedure ArmComplete(const C: ICrossConnection; const OK: Boolean);
  protected
    procedure LogicConnected(const C: ICrossConnection); override;
    procedure LogicReceived(const C: ICrossConnection; const Buffer: Pointer;
      const Count: Integer); override;
    procedure LogicDisconnected(const C: ICrossConnection); override;
  public
    constructor Create; reintroduce;
    procedure Rejected(const C: ICrossConnection; const Count: Integer);
    procedure Verify(const Limited: Boolean);
    procedure ReleaseConnections;
  end;

constructor TBaseLimitTlsSocket.Create;
begin
  inherited Create(2, True);
  FGuard := TLock.Create;
  FChanged := TEvent.Create(True, False);
  SetLength(FPayload, 65536);
  FillChar(FPayload[0], Length(FPayload), Ord('A'));
end;

procedure TBaseLimitTlsSocket.RecordError(const S: string);
begin
  FGuard.Enter;
  try if FError = '' then FError := S; finally FGuard.Leave; end;
  FChanged.SetEvent;
end;

procedure TBaseLimitTlsSocket.LogicConnected(const C: ICrossConnection);
begin
  FGuard.Enter;
  try FConnection := C; Inc(FConnected); finally FGuard.Leave; end;
  try
    C.SendBytes(TEncoding.ASCII.GetBytes('PING'),
      procedure(const Connection: ICrossConnection; const OK: Boolean)
      begin
        FGuard.Enter;
        try Inc(FPingCalls); if not OK then Inc(FPingFailed); finally FGuard.Leave; end;
        FChanged.SetEvent;
      end);
  except on E: Exception do RecordError(E.ClassName + ': ' + E.Message); end;
end;

procedure TBaseLimitTlsSocket.LogicReceived(const C: ICrossConnection;
  const Buffer: Pointer; const Count: Integer);
var Part: AnsiString; Arm: Boolean;
begin
  Arm := False;
  SetString(Part, PAnsiChar(Buffer), Count);
  FGuard.Enter;
  try
    FReceived := FReceived + Part;
    if not FRoundTrip and (Length(FReceived) >= 4) then
    begin
      if Copy(FReceived, 1, 4) <> 'PONG' then FError := 'small TLS echo differs';
      FRoundTrip := True;
      Arm := FError = '';
    end;
    if FReceived = 'PONGDONE' then FPeerConfirmed := True;
  finally FGuard.Leave; end;
  try
    if Arm then
      C.SendBytes(TEncoding.ASCII.GetBytes('ARM'),
        procedure(const Connection: ICrossConnection; const OK: Boolean)
        begin ArmComplete(Connection, OK); end);
  except on E: Exception do RecordError(E.ClassName + ': ' + E.Message); end;
  FChanged.SetEvent;
end;

procedure TBaseLimitTlsSocket.ArmComplete(const C: ICrossConnection; const OK: Boolean);
begin
  FGuard.Enter;
  try Inc(FArmCalls); if not OK then Inc(FArmFailed); finally FGuard.Leave; end;
  if not OK then begin RecordError('small arm write failed'); Exit; end;
  try
    // 当前逻辑写尚未退出完成通知，TLS的FPumping仍占用；两项先真正排入逻辑队列。
    C.SendBytes(FPayload,
      procedure(const Connection: ICrossConnection; const Success: Boolean)
      begin
        FGuard.Enter;
        try Inc(FBigCalls); if not Success then Inc(FBigFailed); finally FGuard.Leave; end;
        FChanged.SetEvent;
      end);
    C.SendBytes(TEncoding.ASCII.GetBytes('TAIL'),
      procedure(const Connection: ICrossConnection; const Success: Boolean)
      begin
        FGuard.Enter;
        try Inc(FTailCalls); if not Success then Inc(FTailFailed); finally FGuard.Leave; end;
        FChanged.SetEvent;
      end);
    FGuard.Enter;
    try FQueuedBeforeReturn := (FBigCalls = 0) and (FTailCalls = 0); finally FGuard.Leave; end;
  except on E: Exception do RecordError(E.ClassName + ': ' + E.Message); end;
  FChanged.SetEvent;
end;

procedure TBaseLimitTlsSocket.LogicDisconnected(const C: ICrossConnection);
begin
  FGuard.Enter;
  try Inc(FClosed); finally FGuard.Leave; end;
  FChanged.SetEvent;
end;

procedure TBaseLimitTlsSocket.Rejected(const C: ICrossConnection; const Count: Integer);
begin
  FGuard.Enter;
  try
    Inc(FRejected); FRejectedBytes := Count; FRejectedConnection := C;
  finally FGuard.Leave; end;
  FChanged.SetEvent;
end;

procedure TBaseLimitTlsSocket.Verify(const Limited: Boolean);
var I: Integer; Finished: Boolean; Count, Bytes: Int64; C: ICrossConnection;
begin
  Finished := False;
  for I := 0 to 1499 do
  begin
    FGuard.Enter;
    try
      Check(FError = '', FError);
      Finished := (FBigCalls = 1) and (FTailCalls = 1)
        and ((Limited and (FClosed = 1)) or (not Limited and FPeerConfirmed));
    finally FGuard.Leave; end;
    if Finished then Break;
    FChanged.WaitFor(10); FChanged.ResetEvent;
  end;
  Check(Finished, 'real TLS/base completion timeout');
  FGuard.Enter;
  try
    Check((FConnected = 1) and (FPingCalls = 1) and (FPingFailed = 0)
      and FRoundTrip and (FArmCalls = 1) and (FArmFailed = 0), 'normal handshake/small exchange failed');
    Check(FQueuedBeforeReturn, 'large/tail items were not queued before physical rejection');
    C := FConnection;
    if Limited then
    begin
      Check((FRejected = 1) and (FRejectedBytes > 4096) and (FRejectedConnection = C),
        'expected actual Base ciphertext reservation rejection');
      Check((FBigFailed = 1) and (FTailFailed = 1) and C.IsClosed,
        'TLS did not fail once/close/cancel queued plaintext');
    end else
      Check((FRejected = 0) and (FBigFailed = 0) and (FTailFailed = 0)
        and not C.IsClosed, 'unlimited control failed or closed');
  finally FGuard.Leave; end;
  GetPendingSendForTest(C, Count, Bytes);
  Check((Count = 0) and (Bytes = 0), 'Base physical quota remained charged');
  if Limited then
  begin
    C.SendBytes(TEncoding.ASCII.GetBytes('LATE'),
      procedure(const Connection: ICrossConnection; const Success: Boolean)
      begin
        if Success then RecordError('closed TLS accepted later plaintext');
        Inc(FLateCalls);
      end);
    Check((FLateCalls = 1) and (FError = '') and (FRejected = 1), 'late send retried native/base output');
  end;
  Writeln('BASE_TLS limited=', Limited, ' roundtrip=', FRoundTrip, ' queued=', FQueuedBeforeReturn,
    ' big=', FBigCalls, '/', FBigFailed, ' tail=', FTailCalls, '/', FTailFailed,
    ' base_rejected=', FRejected, ' ciphertext_bytes=', FRejectedBytes,
    ' closed=', FClosed, ' quota=', Count, '/', Bytes);
  Flush(Output);
end;

procedure TBaseLimitTlsSocket.ReleaseConnections;
begin
  FConnection := nil;
  FRejectedConnection := nil;
end;

procedure TestRealBaseTlsLimit(const Limited: Boolean);
var Socket: TBaseLimitTlsSocket; Port: Word;
begin
  Socket := TBaseLimitTlsSocket.Create;
  try
    if Limited then Socket.MaxPendingSendBytes := 4096;
    Socket.SetCertificateFile(ParamStr(4));
    Socket.SetPrivateKeyFile(ParamStr(5));
    CrossSendRejectedForTest := procedure(const C: ICrossConnection; const Count: Integer)
      begin Socket.Rejected(C, Count); end;
    Port := 0;
    Socket.Listen('127.0.0.1', 0,
      procedure(const Listener: ICrossListen; const OK: Boolean)
      begin Check(OK, 'real TLS listener failed'); Port := Listener.LocalPort; end);
    Check(Port <> 0, 'real TLS port missing');
    Writeln('PORT ', Port); Flush(Output);
    Socket.Verify(Limited);
  finally
    Socket.CloseAll;
    Socket.StopLoop;
    CrossSendRejectedForTest := nil;
    Socket.ReleaseConnections;
    Socket.Free;
  end;
end;
{$ELSE}
procedure TestRealBaseTlsLimit(const Limited: Boolean);
begin
  raise Exception.Create('real base quota test requires CROSS_CAPACITY_TESTS');
end;
{$ENDIF}
