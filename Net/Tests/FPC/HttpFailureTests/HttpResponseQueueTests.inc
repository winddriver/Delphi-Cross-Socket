type
  TQueueConnection = class(TMemoryConnection)
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    DestroyedCount: PInteger;
    CallbackErrors, WriteCount, LastWriteSize: Integer;
    LastWrite: Pointer;
    destructor Destroy; override;
    procedure CompleteOne(const ASuccess: Boolean; const ARepeat: Boolean = False);
    procedure Drain;
  end;

  TQueueStream = class(TMemoryStream)
  public
    DestroyedCount: PInteger;
    destructor Destroy; override;
  end;

  TQueueAction = reference to procedure;
  TQueueRaceThread = class(TThread)
  protected
    procedure Execute; override;
  public
    Gate: IEvent;
    Action: TQueueAction;
    ErrorText: string;
  end;

  TQueueServer = class(TTestServer)
  protected
    procedure DoOnRequest(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse); override;
    procedure DoOnRequestEnd(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
      const ASuccess: Boolean); override;
  public
    Responses: TList<ICrossHttpResponse>;
    RaiseFirstEnd, CloseFirstEnd: Boolean;
    Ends, FailedEnds: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

destructor TQueueConnection.Destroy;
begin
  if DestroyedCount <> nil then Inc(DestroyedCount^);
  inherited;
end;

procedure TQueueConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  Inc(WriteCount);
  LastWrite := ABuffer;
  LastWriteSize := ACount;
  inherited;
end;

procedure TQueueConnection.CompleteOne(const ASuccess, ARepeat: Boolean);
var
  LCallback: TCrossConnectionCallback;
begin
  Check(FCallbacks.Count > 0, 'no pending physical write');
  LCallback := FCallbacks.Dequeue();
  try
    LCallback(Self, ASuccess);
    if ARepeat then LCallback(Self, ASuccess);
  except
    on E: Exception do Inc(CallbackErrors);
  end;
end;

procedure TQueueRaceThread.Execute;
begin
  try
    if Gate.WaitFor(5000) <> TWaitResult.wrSignaled then
      raise Exception.Create('queue race start timeout');
    Action();
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
end;

destructor TQueueStream.Destroy;
begin
  if DestroyedCount <> nil then Inc(DestroyedCount^);
  inherited;
end;

procedure TQueueConnection.Drain;
var
  LCallback: TCrossConnectionCallback;
  LCount: Integer;
begin
  LCount := 0;
  while FCallbacks.Count > 0 do
  begin
    Inc(LCount);
    Check(LCount < 100, 'queue physical callbacks did not settle');
    LCallback := FCallbacks.Dequeue();
    try
      LCallback(Self, True);
    except
      // 模拟 I/O 线程的外层异常隔离；队列自身仍必须推进下一条。
      on E: Exception do Inc(CallbackErrors);
    end;
    LCallback := nil;
  end;
end;

constructor TQueueServer.Create;
begin
  inherited;
  Compressible := False;
  Responses := TList<ICrossHttpResponse>.Create;
end;

destructor TQueueServer.Destroy;
begin
  Responses.Free;
  inherited;
end;

procedure TQueueServer.DoOnRequest(const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse);
begin
  Requests.Add(ARequest.Path);
  Responses.Add(AResponse);
end;

procedure TQueueServer.DoOnRequestEnd(const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
  const ASuccess: Boolean);
begin
  Inc(Ends);
  if not ASuccess then Inc(FailedEnds);
  if RaiseFirstEnd and (ARequest.Path = '/first') then
    raise Exception.Create('request-end test exception');
  if CloseFirstEnd and (ARequest.Path = '/first') then
    (AConnection as TMemoryConnection).Cleanup;
  inherited;
end;

procedure TestQueueReadyCloseRace;
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TQueueConnection;
  LConnection: ICrossHttpConnection;
  LResponse: ICrossHttpResponse;
  LSender, LCloser: TQueueRaceThread;
  LGate: IEvent;
  LCalls, LFailures, LDestroyed, I: Integer;
begin
  LServerObject := TQueueServer.Create;
  LServer := LServerObject;
  for I := 1 to 64 do
  begin
    LCalls := 0; LFailures := 0; LDestroyed := 0;
    LObject := TQueueConnection.Create(LServerObject);
    LObject.DestroyedCount := @LDestroyed;
    LConnection := LObject;
    LObject.Feed(GoodRequest('/race'));
    LResponse := LServerObject.Responses[0];
    LServerObject.Responses.Clear;
    LGate := TEvent.Create(True, False);
    LSender := TQueueRaceThread.Create(True);
    LCloser := TQueueRaceThread.Create(True);
    LSender.FreeOnTerminate := False;
    LCloser.FreeOnTerminate := False;
    LSender.Gate := LGate; LCloser.Gate := LGate;
    LSender.Action :=
      procedure
      begin
        LResponse.SendNoCompress('RACE',
          procedure(const C: ICrossConnection; const OK: Boolean)
          begin
            AtomicIncrement(LCalls);
            if not OK then AtomicIncrement(LFailures);
          end);
      end;
    LCloser.Action := procedure begin LObject.Cleanup; end;
    LSender.Start; LCloser.Start; LGate.SetEvent;
    LSender.WaitFor; LCloser.WaitFor;
    Check(LSender.ErrorText = '', 'ready/Close send error: ' + LSender.ErrorText);
    Check(LCloser.ErrorText = '', 'ready/Close close error: ' + LCloser.ErrorText);
    LSender.Free; LCloser.Free;
    LObject.Drain;
    Check((LCalls = 1) and (LFailures = 1), 'ready/Close did not settle once');
    Check(LObject.Pending = 0, 'ready/Close pending count did not return to zero');
    LResponse := nil;
    LConnection := nil;
    Check(LDestroyed = 1, 'ready/Close left connection references');
  end;
  LServer := nil;
end;

procedure TestResponseQueue(const AKind: string);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TQueueConnection;
  LConnection: ICrossHttpConnection;
  LResponse: ICrossHttpResponse;
  LCalls, LFirstCalls, LSecondCalls, LFailures, LDestroyed: Integer;
  LStream: TQueueStream;
  LStreamDestroyed, LWrites, LReadCalls: Integer;
  LBody: AnsiString;
  LRaised, LOldLogging: Boolean;
  LLogCalls: Integer;
begin
  if AKind = 'ready-close-race' then
  begin
    TestQueueReadyCloseRace;
    Exit;
  end;
  LCalls := 0; LFirstCalls := 0; LSecondCalls := 0;
  LFailures := 0; LDestroyed := 0;
  LStream := nil; LStreamDestroyed := 0; LReadCalls := 0;
  LOldLogging := CrossSocketLogEnabled;
  LLogCalls := 0;
  if AKind = 'logger' then
  begin
    CrossSocketLogEnabled := True;
    _SetCrossLogger(procedure(const S: string)
      begin Inc(LLogCalls); raise Exception.Create('logger test exception'); end);
  end;
  LServerObject := TQueueServer.Create;
  LServer := LServerObject;
  LObject := TQueueConnection.Create(LServerObject);
  LObject.DestroyedCount := @LDestroyed;
  LConnection := LObject;
  try
    LObject.Feed(GoodRequest('/first'));
    Check(LServerObject.Responses.Count = 1, 'first queued response missing');
    if AKind.StartsWith('late') then
    begin
      LResponse := LServerObject.Responses[0];
      LServerObject.Responses.Clear;
      LObject.Cleanup;
      if AKind = 'late-release' then
      begin
        LConnection := nil;
        LObject := nil;
        Check(LDestroyed = 1, 'closed connection was retained before late Send');
      end;
      LRaised := False;
      try
        if AKind = 'late-nocompress' then
          LResponse.SendNoCompress('late',
            procedure(const C: ICrossConnection; const OK: Boolean)
            begin Inc(LCalls); if not OK then Inc(LFailures); end)
        else
          LResponse.Send('late',
            procedure(const C: ICrossConnection; const OK: Boolean)
            begin Inc(LCalls); if not OK then Inc(LFailures); end);
      except
        on E: Exception do LRaised := True;
      end;
      Check(not LRaised, 'late response raised after InternalClose');
      Check((LCalls = 1) and (LFailures = 1), 'late response did not notify False exactly once');
    end else
    if AKind = 'cancel-callback' then
    begin
      // R1 尚未 ready，R2/R3 只排队，不存在在途物理写。
      LObject.Feed(GoodRequest('/second') + GoodRequest('/third'));
      LServerObject.Responses[1].SendNoCompress('SECOND',
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          Inc(LFirstCalls);
          if not OK then Inc(LFailures);
          raise Exception.Create('cancel completion test exception');
        end);
      LServerObject.Responses[2].SendNoCompress('THIRD',
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin Inc(LSecondCalls); if not OK then Inc(LFailures); end);
      try LObject.Cleanup; except on E: Exception do ; end;
      Check((LFirstCalls = 1) and (LSecondCalls = 1) and (LFailures = 2),
        'first canceled callback prevented later cancellation');
      Check(LObject.WriteCount = 0, 'canceling queued response started physical write');
    end else
    if AKind = 'active-close' then
    begin
      LBody := 'physical-buffer-must-stay-alive';
      LStream := TQueueStream.Create;
      LStream.DestroyedCount := @LStreamDestroyed;
      LStream.WriteBuffer(PAnsiChar(LBody)^, Length(LBody));
      LStream.Position := 0;
      LServerObject.Responses[0].SendNoCompress(LStream,
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          Inc(LCalls);
          if not OK then Inc(LFailures);
          LStream.Free;
          LStream := nil;
        end);
      LObject.CompleteOne(True); // 头部写完成，现在正文指针已交给物理发送。
      Check((LObject.LastWriteSize = Length(LBody)) and (LObject.FCallbacks.Count = 1),
        'body write was not pending');
      LWrites := LObject.WriteCount;
      LObject.Cleanup;
      Check((LCalls = 0) and (LStreamDestroyed = 0),
        'Close released an in-flight source before physical completion');
      Check(CompareMem(LObject.LastWrite, PAnsiChar(LBody), Length(LBody)),
        'in-flight body buffer changed before physical completion');
      LObject.CompleteOne(True); // 已关闭连接的迟到成功，不能重新推进正文。
      Check(LObject.IsClosed, 'late physical completion changed closed connection status');
      Check((LCalls = 1) and (LFailures = 1) and (LStreamDestroyed = 1),
        'late physical completion did not settle cancellation exactly once');
      Check((LObject.WriteCount = LWrites) and (LObject.FCallbacks.Count = 0),
        'late physical completion restarted a closed response');
    end else
    if AKind = 'source-error' then
    begin
      LBody := 'FIRST-CHUNK';
      LServerObject.Responses[0].SendNoCompress(
        function(const P: PPointer; const N: PNativeInt): Boolean
        begin
          Inc(LReadCalls);
          if LReadCalls > 1 then raise Exception.Create('source read test exception');
          P^ := PAnsiChar(LBody);
          N^ := Length(LBody);
          Result := True;
        end,
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin Inc(LCalls); if not OK then Inc(LFailures); end);
      LObject.Drain;
      Check(LReadCalls = 2, 'source error branch was not reached');
      Check((LCalls = 1) and (LFailures = 1), 'source exception left response unsettled');
      Check(LObject.CloseRequests + LObject.DisconnectRequests > 0,
        'source exception left connection open');
    end else
    if (AKind = 'callback') or (AKind = 'logger') or (AKind = 'request-end')
      or (AKind = 'reentry-send') or (AKind = 'reentry-close')
      or (AKind = 'request-end-close') or (AKind = 'duplicate-physical') then
    begin
      LObject.Feed(GoodRequest('/second'));
      Check(LServerObject.Responses.Count = 2, 'second queued response missing');
      LServerObject.RaiseFirstEnd := AKind = 'request-end';
      LServerObject.CloseFirstEnd := AKind = 'request-end-close';
      LServerObject.Responses[0].SendNoCompress('FIRST',
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          Inc(LFirstCalls);
          if not OK then Inc(LFailures);
          if (AKind = 'callback') or (AKind = 'logger') then
            raise Exception.Create('completion test exception');
          if AKind = 'reentry-close' then LObject.Cleanup;
          if AKind = 'reentry-send' then
          begin
            LWrites := LObject.WriteCount;
            LServerObject.Responses[1].SendNoCompress('SECOND',
              procedure(const C2: ICrossConnection; const OK2: Boolean)
              begin Inc(LSecondCalls); if not OK2 then Inc(LFailures); end);
            Check(LObject.WriteCount = LWrites, 'reentrant send overtook completion notification');
          end;
        end);
      if AKind <> 'reentry-send' then
        LServerObject.Responses[1].SendNoCompress('SECOND',
          procedure(const C: ICrossConnection; const OK: Boolean)
          begin Inc(LSecondCalls); if not OK then Inc(LFailures); end);
      if AKind = 'duplicate-physical' then LObject.CompleteOne(True, True);
      LObject.Drain;
      Check(LFirstCalls = 1, 'first completion was repeated');
      if (AKind = 'reentry-close') or (AKind = 'request-end-close') then
      begin
        Check((LSecondCalls = 1) and (LFailures = 1), 'reentrant close did not cancel next response');
        Check(Pos(AnsiString('SECOND'), LObject.Sent) = 0, 'response started after reentrant close');
      end else
      begin
        Check((LSecondCalls = 1) and (LFailures = 0), 'callback exception stalled or failed next response');
        Check((Pos(AnsiString('FIRST'), LObject.Sent) > 0) and
          (Pos(AnsiString('SECOND'), LObject.Sent) > Pos(AnsiString('FIRST'), LObject.Sent)),
          'response order was not preserved');
      end;
      Check(LServerObject.Ends = 2, 'request-end notifications missing or repeated');
      if AKind = 'logger' then Check(LLogCalls > 0, 'failing logger was not called');
    end else
      Check(False, 'unknown queue case');
  finally
    LResponse := nil;
    LServerObject.Responses.Clear;
    if LObject <> nil then LObject.Cleanup;
    LConnection := nil;
    LServer := nil;
    if AKind = 'logger' then
    begin
      _SetCrossLogger(nil);
      CrossSocketLogEnabled := LOldLogging;
    end;
  end;
end;
