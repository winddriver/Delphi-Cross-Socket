program ConnectFallbackTests;
{$I ../../../../zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  {$IFDEF MSWINDOWS}Net.Winsock2,{$ELSE}
    {$IFDEF FPC}Sockets, BaseUnix,{$ELSE}Posix.SysSocket, Posix.NetinetIn,{$ENDIF}
  {$ENDIF}
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket;

type
  TObservedConnection = class(TCrossConnection)
    destructor Destroy; override;
  end;

  TObservedSocket = class(TCrossSocket)
  public
    Addresses: TArray<TCrossConnectAddr>;
    GateEntered: TEvent;
    ResumeConnect: TEvent;
    PublishedConnection: ICrossConnection;
    PausePublished: Boolean;
    PauseBeforePublish: Boolean;
    PauseResolve: Boolean;
    PauseConnected: Boolean;
    PauseDisconnected: Boolean;
    FailRegistration: Boolean;
    GateCalls: Integer;
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    function ResolveConnectAddrs(const AHost: string;
      const APort: Word): TArray<TCrossConnectAddr>; override;
    procedure TriggerConnecting(const AConnection: ICrossConnection); override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
    procedure WaitAtGate(const AConnection: ICrossConnection);
  end;

  TAttempt = class
  public
    Done: TEvent;
    Calls, Successes, Failures, ClosedOnSuccess: Integer;
    NilOnFailure, OpenOnFailure, ZeroErrorOnFailure: Integer;
    RaiseOnSuccess: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Callback: TCrossConnectionCallback;
  end;

  TConnectThread = class(TThread)
  public
    Socket: TObservedSocket;
    Attempt: TAttempt;
    Done: TEvent;
    ErrorText: string;
    procedure Execute; override;
  end;

var
  CreatedConnections, DestroyedConnections, GateTimeouts: Integer;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

destructor TObservedConnection.Destroy;
begin
  try
    inherited;
  finally
    AtomicIncrement(DestroyedConnections);
  end;
end;

function TObservedSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType; const AHost: string;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TObservedConnection.Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
  AtomicIncrement(CreatedConnections);
end;

function TObservedSocket.ResolveConnectAddrs(const AHost: string;
  const APort: Word): TArray<TCrossConnectAddr>;
begin
  if PauseResolve then
  begin
    PauseResolve := False;
    WaitAtGate(nil);
  end;
  Result := Addresses;
end;

procedure TObservedSocket.WaitAtGate(const AConnection: ICrossConnection);
begin
  PublishedConnection := AConnection;
  GateEntered.SetEvent;
  if ResumeConnect.WaitFor(10000) <> wrSignaled then AtomicIncrement(GateTimeouts);
end;

procedure TObservedSocket.TriggerConnecting(const AConnection: ICrossConnection);
begin
  if PauseBeforePublish then
  begin
    PauseBeforePublish := False;
    WaitAtGate(AConnection);
  end;
  inherited;
  if AtomicIncrement(GateCalls) = 1 then
  begin
    if FailRegistration then
      // 错误注入：只关原始句柄，让真实注册API失败；不能声称重现了资源耗尽。
      TSocketAPI.CloseSocket(AConnection.Socket);
    if PausePublished then WaitAtGate(AConnection);
  end;
end;

procedure TObservedSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  if PauseConnected then WaitAtGate(AConnection);
  inherited;
end;

procedure TObservedSocket.LogicDisconnected(const AConnection: ICrossConnection);
begin
  inherited;
  if PauseDisconnected then
  begin
    PauseDisconnected := False;
    WaitAtGate(AConnection);
  end;
end;

constructor TAttempt.Create;
begin
  inherited;
  Done := TEvent.Create(nil, True, False, '');
end;

destructor TAttempt.Destroy;
begin
  Done.Free;
  inherited;
end;

function TAttempt.Callback: TCrossConnectionCallback;
var
  LAttempt: TAttempt;
begin
  LAttempt := Self;
  Result := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 回调不做断言，所有迟到/重复通知都计数，停止IO线程后统一检查。
      AtomicIncrement(LAttempt.Calls);
      if ASuccess then
      begin
        AtomicIncrement(LAttempt.Successes);
        if (AConnection = nil) or AConnection.IsClosed then
          AtomicIncrement(LAttempt.ClosedOnSuccess);
        if AConnection <> nil then AConnection.Close;
      end else
      begin
        AtomicIncrement(LAttempt.Failures);
        if AConnection = nil then
          AtomicIncrement(LAttempt.NilOnFailure)
        else
        begin
          if not AConnection.IsClosed then AtomicIncrement(LAttempt.OpenOnFailure);
          if AConnection.LastNetError = 0 then AtomicIncrement(LAttempt.ZeroErrorOnFailure);
        end;
      end;
      LAttempt.Done.SetEvent;
      if ASuccess and LAttempt.RaiseOnSuccess then
        raise Exception.Create('intentional connect callback exception');
    end;
end;

procedure TConnectThread.Execute;
begin
  try
    Socket.Connect('fixed-addresses.invalid', 1, 0, Attempt.Callback());
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
  Done.SetEvent;
end;

function Address(const AHost: string; const APort: Word): TCrossConnectAddr;
var
  LHints: TRawAddrInfo;
  LInfo: PRawAddrInfo;
begin
  FillChar(LHints, SizeOf(LHints), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LInfo := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  Check(LInfo <> nil, 'numeric loopback resolution failed');
  try
    Check(LInfo.ai_next = nil, 'numeric address must have one result');
    Result := Default(TCrossConnectAddr);
    Result.Family := LInfo.ai_family;
    Result.SockType := LInfo.ai_socktype;
    Result.Protocol := LInfo.ai_protocol;
    Result.Addr.AddrLen := LInfo.ai_addrlen;
    Move(LInfo.ai_addr^, Result.Addr.Addr, LInfo.ai_addrlen);
  finally
    TSocketAPI.FreeAddrInfo(LInfo);
  end;
end;

procedure Run;
var
  LMode: string;
  LSocket: TObservedSocket;
  LThread: TConnectThread;
  LAttempts: array of TAttempt;
  LGood4, LGood6, LBad4, LBad6, LUnsupported: TCrossConnectAddr;
  LCount, LExpectedCreated, LExpectedSuccess, LCalls, LSuccess, LClosed, I: Integer;
  LTimedOut, LStopped: Boolean;
begin
  CrossSocketLogEnabled := False;
  LMode := ParamStr(1);
  LGood4 := Address('127.0.0.1', StrToInt(ParamStr(2)));
  LGood6 := Address('::1', StrToInt(ParamStr(3)));
  LBad4 := Address('127.0.0.1', StrToInt(ParamStr(4)));
  LBad6 := Address('::1', StrToInt(ParamStr(5)));
  LCount := 1;
  LExpectedCreated := 1;
  LExpectedSuccess := 1;
  LSocket := nil;
  LThread := nil;
  LTimedOut := False;
  LStopped := False;
  try
    LSocket := TObservedSocket.Create(2);
    LSocket.GateEntered := TEvent.Create(nil, True, False, '');
    LSocket.ResumeConnect := TEvent.Create(nil, True, False, '');
    LSocket.Addresses := [LGood4];
    if LMode = 'v6-refused-v4-success' then
    begin
      LSocket.Addresses := [LBad6, LGood4];
      LExpectedCreated := 2;
    end else
    if LMode = 'v4-refused-v6-success' then
    begin
      LSocket.Addresses := [LBad4, LGood6];
      LExpectedCreated := 2;
    end else
    if LMode = 'all-refused' then
    begin
      LSocket.Addresses := [LBad4, LBad6];
      LExpectedCreated := 2;
      LExpectedSuccess := 0;
    end else
    if LMode = 'unsupported-family-fallback' then
    begin
      LUnsupported := LGood4;
      LUnsupported.Family := -1;
      LSocket.Addresses := [LUnsupported, LGood4];
    end else
    if LMode = 'close-during-resolution' then
    begin
      LSocket.PauseResolve := True;
      LExpectedCreated := 0;
      LExpectedSuccess := 0;
    end else
    if LMode = 'close-before-publish' then
    begin
      LSocket.PauseBeforePublish := True;
      LExpectedSuccess := 0;
    end else
    if LMode = 'connect-after-close-all' then
      LSocket.CloseAllConnections
    else
    if LMode = 'external-close-published' then
    begin
      LSocket.Addresses := [LGood4, LGood6];
      LSocket.PausePublished := True;
      LExpectedSuccess := 0;
    end else
    if LMode = 'close-before-callback' then
    begin
      LSocket.PauseConnected := True;
      // 已取得成功通知权的实现允许成功；检查单次通知和最终释放。
      LExpectedSuccess := -1;
    end else
    if LMode = 'close-between-attempts' then
    begin
      LSocket.Addresses := [LBad4, LGood6];
      LSocket.PauseDisconnected := True;
      LExpectedSuccess := 0;
    end else
    if LMode = 'register-failure-fallback' then
    begin
      LSocket.Addresses := [LGood4, LGood6];
      LSocket.FailRegistration := True;
      LExpectedCreated := 2;
    end else
    if LMode = 'destroy-200' then
    begin
      LCount := 200;
      LExpectedCreated := LCount;
    end else
      Check((LMode = 'callback-close') or (LMode = 'callback-raises'), 'unknown test mode');

    SetLength(LAttempts, LCount);
    for I := 0 to LCount - 1 do
    begin
      LAttempts[I] := TAttempt.Create;
      LAttempts[I].RaiseOnSuccess := LMode = 'callback-raises';
      if LSocket.PausePublished or LSocket.PauseConnected or LSocket.PauseDisconnected or
        LSocket.PauseResolve or LSocket.PauseBeforePublish then
      begin
        LThread := TConnectThread.Create(True);
        LThread.Socket := LSocket;
        LThread.Attempt := LAttempts[I];
        LThread.Done := TEvent.Create(nil, True, False, '');
        LThread.Start;
        Check(LSocket.GateEntered.WaitFor(10000) = wrSignaled, 'connection did not reach gate');
        // 主线程Close完成以后才放行，避免依赖Sleep或碰运气触发竞态。
        if (LMode = 'close-between-attempts') or (LMode = 'close-during-resolution') or
          (LMode = 'close-before-publish') then
          LSocket.CloseAllConnections
        else
          LSocket.PublishedConnection.Close;
        LSocket.PublishedConnection := nil;
        LSocket.ResumeConnect.SetEvent;
        Check(LThread.Done.WaitFor(10000) = wrSignaled, 'Connect caller did not finish');
        LThread.WaitFor;
        Check(LThread.ErrorText = '', 'Connect thread exception: ' + LThread.ErrorText);
      end else
        LSocket.Connect('fixed-addresses.invalid', 1, 0, LAttempts[I].Callback());
      if LAttempts[I].Done.WaitFor(10000) <> wrSignaled then
      begin
        LTimedOut := True;
        Break;
      end;
    end;

    LSocket.CloseAll;
    LSocket.StopLoop;
    LStopped := True;
    LCalls := 0;
    LSuccess := 0;
    LClosed := 0;
    for I := 0 to LCount - 1 do
      if LAttempts[I] <> nil then
      begin
        Inc(LCalls, LAttempts[I].Calls);
        Inc(LSuccess, LAttempts[I].Successes);
        Inc(LClosed, LAttempts[I].ClosedOnSuccess);
      end;
    Writeln('OBSERVED mode=', LMode, ' operations=', LCount, ' callbacks=', LCalls,
      ' successful=', LSuccess, ' closed_on_success=', LClosed,
      ' created=', CreatedConnections, ' destroyed=', DestroyedConnections,
      ' remaining=', LSocket.ConnectionsCount, ' gate_timeouts=', GateTimeouts);
    Check(not LTimedOut, 'callback timed out');
    Check(GateTimeouts = 0, 'test gate timed out');
    for I := 0 to LCount - 1 do
      Check(LAttempts[I].Calls = 1, 'operation callback count is not exactly one');
    if LExpectedSuccess >= 0 then
      Check(LSuccess = LCount * LExpectedSuccess, 'unexpected success/failure result');
    if LMode = 'all-refused' then
    begin
      Writeln('OBSERVED failure_connection nil=', LAttempts[0].NilOnFailure,
        ' open=', LAttempts[0].OpenOnFailure, ' zero_error=', LAttempts[0].ZeroErrorOnFailure);
      Check(LAttempts[0].NilOnFailure = 0, 'final async failure lost connection');
      Check(LAttempts[0].OpenOnFailure = 0, 'final async failure connection is not closed');
      Check(LAttempts[0].ZeroErrorOnFailure = 0, 'final async failure lost LastNetError');
    end;
    if LMode <> 'close-before-callback' then
      Check(LClosed = 0, 'success callback received an already closed connection');
    Check(CreatedConnections = LExpectedCreated, 'unexpected number of address attempts');
    Check(LSocket.ConnectionsCount = 0, 'owner still contains closed connections');
    Check(DestroyedConnections = CreatedConnections, 'connection objects were not released after StopLoop');
  finally
    if LSocket <> nil then
    begin
      if LSocket.ResumeConnect <> nil then LSocket.ResumeConnect.SetEvent;
      if LThread <> nil then
      begin
        LThread.WaitFor;
        LThread.Done.Free;
        LThread.Free;
      end;
      LSocket.PublishedConnection := nil;
      if not LStopped then
      begin
        LSocket.CloseAll;
        LSocket.StopLoop;
      end;
      LSocket.GateEntered.Free;
      LSocket.ResumeConnect.Free;
      LSocket.Free;
    end;
    for I := 0 to Length(LAttempts) - 1 do LAttempts[I].Free;
  end;
end;

begin
  try
    Run;
    Writeln('PASS connect-fallback ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
