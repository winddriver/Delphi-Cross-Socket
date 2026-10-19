type
  IQueueCapture = interface
    ['{E5D47A65-35C3-4B82-BA6F-05D80C8B0B40}']
    function Id: Integer;
  end;
  TQueueCapture = class(TInterfacedObject, IQueueCapture)
  public
    Number: Integer;
    Destroyed: PInteger;
    function Id: Integer;
    destructor Destroy; override;
  end;
function TQueueCapture.Id: Integer;
begin Result := Number; end;
destructor TQueueCapture.Destroy;
begin Inc(Destroyed^); inherited; end;

procedure AddManagedTlsWrite(const F: TTlsFixture; const AId: Integer;
  const ADestroyed, ACalls: PInteger);
var
  P: TQueueCapture;
  Keep: IQueueCapture;
  LConnection: ICrossConnection;
  LCallback: TCrossConnectionCallback;
begin
  P := TQueueCapture.Create; P.Number := AId; P.Destroyed := ADestroyed; Keep := P;
  LConnection := F.Connection;
  LCallback := procedure(const C: ICrossConnection; const OK: Boolean)
    begin
      Check((Keep.Id = AId) and (C = LConnection), 'managed TLS capture changed');
      Inc(ACalls^);
    end;
  F.Connection.SendBytes(TEncoding.ASCII.GetBytes('A'), LCallback);
end;

procedure TestManagedTlsQueue;
var
  F: TTlsFixture;
  I, LDestroyed, LCalls: Integer;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  LDestroyed := 0; LCalls := 0;
  try
    F.Handshake;
    F.Socket.DelayWrites := True;
    for I := 0 to 63 do AddManagedTlsWrite(F, I, @LDestroyed, @LCalls);
    for I := 0 to 2047 do
    begin
      F.Socket.CompleteNext(True);
      AddManagedTlsWrite(F, I + 64, @LDestroyed, @LCalls);
    end;
    Check((LCalls = 2048) and (LDestroyed = 2048), 'TLS wrap retained completed callback/connection');
    F.Connection.Close;
    Check((LCalls = 2111) and (LDestroyed = 2111), 'TLS close did not immediately release queued captures');
    F.Socket.CompleteNext(True);
    Check((LCalls = 2112) and (LDestroyed = 2112), 'TLS physical completion retained active capture');
    Check((F.Connection as TCrossOpenSslConnection).RefCount = 1, 'TLS queue retained connection after close');
    F.Connection := nil;
    Check(F.Socket.DestroyedConnections = 1, 'TLS queued connection did not destroy');
  finally
    F.Free;
  end;
end;

procedure TestManagedTlsClear(const AKind: Integer);
var F: TTlsFixture;
begin
  F := TTlsFixture.Create(TLS1_3_VERSION);
  try
    F.Handshake;
    {$IFDEF CROSS_OPENSSL_SELFTEST}
    Check(CrossOpenSslSelfTest_QueueClear(F.Connection, AKind), 'TLS Clear retained managed physical tail slots');
    {$ELSE}
    raise Exception.Create('queue-clear requires CROSS_OPENSSL_SELFTEST');
    {$ENDIF}
  finally F.Free; end;
end;
