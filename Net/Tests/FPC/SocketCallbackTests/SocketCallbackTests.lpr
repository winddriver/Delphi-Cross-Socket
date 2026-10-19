program SocketCallbackTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs, Generics.Collections,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket, Utils.AnonymousThread;

type
  TTestSocket = class;

  TSendProbe = class(TThread)
  private
    FOwner: TTestSocket;
    FConnection: ICrossConnection;
  protected
    procedure Execute; override;
  public
    Done: SyncObjs.TEvent;
    ErrorText: string;
    constructor Create(const AOwner: TTestSocket; const AConnection: ICrossConnection);
    destructor Destroy; override;
  end;

  TTestSocket = class(TCrossSocket)
  private
    FMode: string;
    FLock: SyncObjs.TCriticalSection;
    FConnections: TList<ICrossConnection>;
    FResume: SyncObjs.TEvent;
    FCycle: Integer;
    FProbeByte: Byte;
    procedure _Send(const AConnection: ICrossConnection; const AId, ASize: Integer);
  protected
    function ProcessIoEvent: Boolean; override;
    procedure LogicConnected(const AConnection: ICrossConnection); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
    procedure LogicReceived(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;
    procedure LogicSent(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;
  public
    constructor Create(const AMode: string); reintroduce;
    destructor Destroy; override;
    function StartListen: Word;
    function Connection(const AIndex: Integer): ICrossConnection;
    procedure Command(const ACommand: string);
    procedure Stop;
    procedure ConnectTest(const APort: Word; const ACallback: TCrossConnectionCallback);
    procedure SendProbe(const AConnection: ICrossConnection);
    procedure CompleteConnectForTest(const AConnection: ICrossConnection);
    function NewConnectionForTest: ICrossConnection;
    procedure SendForTest(const AConnection: ICrossConnection;
      const ACallback: TCrossConnectionCallback);
    procedure ConnectBoundForTest(const APort: Word; const ACallback: TCrossConnectionCallback);
  end;

{$IFDEF MSWINDOWS}
function CancelIoExForTest(AHandle: THandle; AOverlapped: Pointer): BOOL; stdcall;
  external 'kernel32.dll' name 'CancelIoEx';
function TestHandleCount(AProcess: THandle; var ACount: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'GetProcessHandleCount';
{$ENDIF}

{$IFDEF LINUX}
function TestDup(AFd: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'dup';
function TestDup2(AFd, ATarget: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'dup2';
function TestOpen(APath: PAnsiChar; AFlags: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'open';
function TestClose(AFd: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'close';
{$ENDIF}

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if ACondition then Exit;
  Writeln('FAIL ', AMessage);
  Flush(Output);
  Halt(1);
end;

procedure Print(const AMessage: string);
begin
  Writeln(AMessage);
  Flush(Output);
end;

constructor TTestSocket.Create(const AMode: string);
begin
  FMode := AMode;
  FLock := SyncObjs.TCriticalSection.Create;
  FConnections := TList<ICrossConnection>.Create;
  FResume := SyncObjs.TEvent.Create(nil, True, False, '');
  inherited Create(1);
end;

destructor TTestSocket.Destroy;
begin
  FConnections.Free;
  FResume.Free;
  FLock.Free;
  inherited;
end;

function TTestSocket.ProcessIoEvent: Boolean;
begin
  Inc(FCycle);
  Result := inherited ProcessIoEvent;
end;

procedure TTestSocket.LogicConnected(const AConnection: ICrossConnection);
begin
  FLock.Enter;
  try
    AConnection.Tag := IntToStr(FConnections.Count);
    FConnections.Add(AConnection);
  finally
    FLock.Leave;
  end;
  Print('CONNECTED ' + AConnection.Tag);
  inherited;
  if (FMode = 'accept') and (AConnection.Tag = '0') then
    raise Exception.Create('test connected callback');
end;

procedure TTestSocket.LogicDisconnected(const AConnection: ICrossConnection);
var
  LProbe: TSendProbe;
begin
  if FMode <> 'race' then Print('DISCONNECTED ' + AConnection.Tag);
  inherited;
  if FMode = 'register-failure' then
  begin
    LProbe := TSendProbe.Create(Self, AConnection);
    LProbe.Start;
    Check(LProbe.Done.WaitFor(1000) = wrSignaled, 'callback is running under send queue lock');
    LProbe.WaitFor;
    Check(LProbe.ErrorText = '', LProbe.ErrorText);
    LProbe.Free;
    Print('QUEUE_UNLOCKED');
  end;
  if FMode = 'stop' then raise Exception.Create('test disconnected callback');
end;

procedure TTestSocket._Send(const AConnection: ICrossConnection;
  const AId, ASize: Integer);
var
  LBytes: TBytes;
begin
  SetLength(LBytes, ASize);
  FillChar(LBytes[0], Length(LBytes), Ord('A') + AId - 1);
  AConnection.SendBytes(LBytes,
    procedure(const ACompletedConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      Print('CALLBACK ' + IntToStr(AId) + ' ' + IntToStr(Ord(ASuccess)));
      if (AId = 1) and (FMode <> 'sent-event') and (FMode <> 'pending-send') then
        raise Exception.Create('test send completion callback');
    end);
end;

procedure TTestSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LBytes: TBytes;
  I, LCount: Integer;
begin
  case PAnsiChar(ABuf)^ of
    'B':
      begin
        Print('BLOCKED');
        Check(FResume.WaitFor(8000) = wrSignaled, 'receive gate timeout');
      end;
    'X':
      begin
        Print('BAD ' + IntToStr(FCycle));
        raise Exception.Create('test received callback');
      end;
    'S':
      begin
        if (FMode = 'cancel-sends') or (FMode = 'cancel-error') then
        begin
          Check(TSocketAPI.SetSndBuf(AConnection.Socket, 0) = 0, 'cannot set send buffer');
          if FMode = 'cancel-error' then LCount := 1 else LCount := 3;
          for I := 1 to LCount do _Send(AConnection, I, 4 * 1024 * 1024);
          Print('BLOCKED');
          Check(FResume.WaitFor(8000) = wrSignaled, 'send gate timeout');
        end else
        begin
          _Send(AConnection, 1, 1);
          _Send(AConnection, 2, 1);
        end;
      end;
  else
    begin
      Print('GOOD ' + IntToStr(FCycle));
      SetLength(LBytes, ALen);
      Move(ABuf^, LBytes[0], ALen);
      AConnection.SendBytes(LBytes);
    end;
  end;
end;

procedure TTestSocket.LogicSent(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  inherited;
  if (FMode = 'sent-event') and (ALen = 1) and (PAnsiChar(ABuf)^ = 'A') then
    raise Exception.Create('test sent event');
end;

function TTestSocket.StartListen: Word;
var
  LPort: Word;
begin
  LPort := 0;
  Listen('127.0.0.1', 0,
    procedure(const AListen: ICrossListen; const ASuccess: Boolean)
    begin
      Check(ASuccess, 'listen failed');
      LPort := AListen.LocalPort;
    end);
  Result := LPort;
  Check(Result <> 0, 'listen port missing');
end;

function TTestSocket.Connection(const AIndex: Integer): ICrossConnection;
begin
  FLock.Enter;
  try
    Result := FConnections[AIndex];
  finally
    FLock.Leave;
  end;
end;

procedure TTestSocket.Command(const ACommand: string);
var
  LConnection: ICrossConnection;
  {$IFDEF LINUX}
  LSaved, LNull: Integer;
  {$ENDIF}
begin
  if ACommand = 'bad-ready' then
  begin
    LConnection := Connection(1);
    Check(TSocketAPI.Readable(LConnection.Socket, 3000) = 1, 'bad connection not readable');
    Print('BAD_READY');
  end else
  if ACommand = 'release' then
  begin
    if (FMode = 'batch') and (FResume.WaitFor(0) <> wrSignaled) then
    begin
      LConnection := Connection(2);
      Check(TSocketAPI.Readable(LConnection.Socket, 3000) = 1, 'good connection not readable');
    end;
    FResume.SetEvent;
  end else
  if ACommand = 'register-failure' then
  begin
    {$IFDEF LINUX}
    LConnection := Connection(0);
    LSaved := TestDup(LConnection.Socket);
    Check((LSaved >= 0) and (LSaved <> LConnection.Socket), 'cannot duplicate owned socket');
    LNull := -1;
    try
      LNull := TestOpen('/dev/null', 0);
      Check((LNull >= 0) and (LNull <> LSaved) and (LNull <> LConnection.Socket),
        'cannot prepare owned null descriptor');
      Check(TestDup2(LNull, LConnection.Socket) = LConnection.Socket, 'dup2 failed');
      TestClose(LNull);
      LNull := -1;
      // 原 socket 由 LSaved 保活；epoll_ctl 对 /dev/null 产生真实 OS 错误。
      _Send(LConnection, 1, 1);
    finally
      if LNull >= 0 then TestClose(LNull);
      TestClose(LSaved);
      FResume.SetEvent;
    end;
    {$ELSE}
    Check(False, 'registration failure injection requires Linux');
    {$ENDIF}
  end else
  if ACommand = 'close' then
  begin
    try
      Connection(0).Close;
    except
      on E: Exception do Print('CLOSE_ERROR ' + E.Message);
    end;
    FResume.SetEvent;
  end else
  if ACommand = 'cancel' then
  begin
    LConnection := Connection(0);
    {$IFDEF MSWINDOWS}
    Check(CancelIoExForTest(LConnection.Socket, nil), 'CancelIoEx failed');
    {$ELSE}
    Check(TSocketAPI.Shutdown(LConnection.Socket, 2) = 0, 'shutdown failed');
    {$ENDIF}
    FResume.SetEvent;
  end;
end;

procedure TTestSocket.SendProbe(const AConnection: ICrossConnection);
begin
  // 测试锁边界：直接进入底层 Send，绕过关闭连接的 DirectSend 快速返回。
  // 关闭标记已经置位，探针不会发出网络数据；随后由关闭队列结算失败。
  Send(AConnection, @FProbeByte, 1,
    procedure(const ACompletedConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      Print('PROBE_CALLBACK ' + IntToStr(Ord(ASuccess)));
    end);
end;

constructor TSendProbe.Create(const AOwner: TTestSocket; const AConnection: ICrossConnection);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FConnection := AConnection;
  Done := SyncObjs.TEvent.Create(nil, True, False, '');
end;

destructor TSendProbe.Destroy;
begin
  Done.Free;
  inherited;
end;

procedure TSendProbe.Execute;
begin
  try
    try
      FOwner.SendProbe(FConnection);
    except
      on E: Exception do ErrorText := E.Message;
    end;
  finally
    Done.SetEvent;
  end;
end;

procedure TTestSocket.Stop;
begin
  FResume.SetEvent;
  StopLoop;
  Check(ConnectionsCount = 0, 'connections remained after stop');
  FConnections.Clear;
  Print('STOPPED');
end;

procedure TTestSocket.ConnectTest(const APort: Word;
  const ACallback: TCrossConnectionCallback);
begin
  Connect('127.0.0.1', APort, 0, ACallback);
end;

procedure TTestSocket.CompleteConnectForTest(const AConnection: ICrossConnection);
begin
  // 只竞争成功通知的所有权，不改写连接状态或模拟平台连接事件。
  inherited LogicConnected(AConnection);
end;

function TTestSocket.NewConnectionForTest: ICrossConnection;
begin
  Result := CreateConnection(Self, TSocketAPI.NewTcp, ctConnect, '', nil);
  Result.ConnectStatus := csConnected;
end;

procedure TTestSocket.SendForTest(const AConnection: ICrossConnection;
  const ACallback: TCrossConnectionCallback);
begin
  Send(AConnection, @FProbeByte, 1, ACallback);
end;

procedure TTestSocket.ConnectBoundForTest(const APort: Word;
  const ACallback: TCrossConnectionCallback);
begin
  // 测试驱动在该本地端口持有独占监听，使 Bind 确定失败。
  Connect('127.0.0.1', APort, APort, ACallback);
end;

procedure Serve(const AMode: string);
var
  LSocket: TTestSocket;
  LOwner: ICrossSocket;
  LLine: string;
  LPort: Word;
begin
  LSocket := TTestSocket.Create(AMode);
  LOwner := LSocket;
  LPort := LSocket.StartListen;
  Print('READY ' + IntToStr(LPort));
  repeat
    Readln(LLine);
    if LLine = 'stop' then Break;
    LSocket.Command(LLine);
  until False;
  LSocket.Stop;
  LOwner := nil;
end;

procedure ConnectCallback(const APort: Word);
var
  LSocket: TTestSocket;
  LOwner: ICrossSocket;
  LConnection: ICrossConnection;
  LConnected: SyncObjs.TEvent;
  LSuccesses, LFailures: Integer;
begin
  LSuccesses := 0;
  LFailures := 0;
  LConnected := SyncObjs.TEvent.Create(nil, True, False, '');
  LSocket := TTestSocket.Create('connect');
  LOwner := LSocket;
  LSocket.ConnectTest(APort,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if ASuccess then
      begin
        Inc(LSuccesses);
        LConnection := AConnection;
        LConnected.SetEvent;
        raise Exception.Create('test connect completion callback');
      end else
        Inc(LFailures);
    end);
  Check(LConnected.WaitFor(3000) = wrSignaled, 'connect callback timeout');
  LConnection.Close;
  Check((LSuccesses = 1) and (LFailures = 0), 'successful connect callback repeated as failure');
  LConnection := nil;
  LSocket.Stop;
  LOwner := nil;
  LConnected.Free;
  Print('PASS connect-callback');
end;

procedure CallbackRace(const ASend: Boolean);
var
  LSocket: TTestSocket;
  LOwner: ICrossSocket;
  LConnection: ICrossConnection;
  LStart: SyncObjs.TEvent;
  LCountLock: SyncObjs.TCriticalSection;
  LSuccessThread, LCloseThread: TAnonymousThread;
  LCallback: TCrossConnectionCallback;
  I, LCalls: Integer;
begin
  LSocket := TTestSocket.Create('race');
  LOwner := LSocket;
  LStart := SyncObjs.TEvent.Create(nil, True, False, '');
  LCountLock := SyncObjs.TCriticalSection.Create;
  for I := 1 to 100 do
  begin
    LCalls := 0;
    LStart.ResetEvent;
    LCallback :=
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        if ASend then Check(not ASuccess, 'unconnected test socket send unexpectedly succeeded');
        LCountLock.Enter;
        try
          Inc(LCalls);
        finally
          LCountLock.Leave;
        end;
      end;
    if ASend then
      LConnection := LSocket.NewConnectionForTest
    else
    begin
      LConnection := TCrossConnectionBase.Create(LSocket, TSocketAPI.NewTcp, ctConnect, '', LCallback);
      LConnection.ConnectStatus := csConnecting;
    end;
    LSuccessThread := TAnonymousThread.Create(
      procedure
      begin
        Check(LStart.WaitFor(3000) = wrSignaled, 'race start timeout');
        if ASend then
          LSocket.SendForTest(LConnection, LCallback)
        else
          LSocket.CompleteConnectForTest(LConnection);
      end);
    LCloseThread := TAnonymousThread.Create(
      procedure
      begin
        Check(LStart.WaitFor(3000) = wrSignaled, 'race start timeout');
        LConnection.Close;
      end);
    LSuccessThread.FreeOnTerminate := False;
    LCloseThread.FreeOnTerminate := False;
    LSuccessThread.Start;
    LCloseThread.Start;
    LStart.SetEvent;
    LSuccessThread.WaitFor;
    LCloseThread.WaitFor;
    Check((LSuccessThread.FatalException = nil) and (LCloseThread.FatalException = nil),
      'connect/close race raised an exception');
    LSuccessThread.Free;
    LCloseThread.Free;
    Check(LCalls = 1, 'success/send versus close did not notify exactly once');
    LConnection := nil;
    LCallback := nil;
  end;
  LSocket.Stop;
  LOwner := nil;
  LCountLock.Free;
  LStart.Free;
  Print('PASS callback-race rounds=100');
end;

procedure ClosedConnection(const ASend: Boolean);
var
  LSocket: TTestSocket;
  LOwner: ICrossSocket;
  LConnection: ICrossConnection;
  LCalls: Integer;
begin
  LSocket := TTestSocket.Create('race');
  LOwner := LSocket;
  LConnection := LSocket.NewConnectionForTest;
  LConnection.Close;
  if ASend then
  begin
    LCalls := 0;
    LSocket.SendForTest(LConnection,
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        Check(not ASuccess, 'closed socket send unexpectedly succeeded');
        Inc(LCalls);
      end);
    Check(LCalls = 1, 'closed socket retained an uncompleted send');
  end else
  begin
    LConnection.Disconnect;
    Check(LConnection.IsClosed, 'Disconnect changed closed state');
  end;
  LConnection := nil;
  LSocket.Stop;
  LOwner := nil;
  Print('PASS closed connection');
end;

function OpenHandleCount: Integer;
{$IFDEF MSWINDOWS}
var
  LCount: DWORD;
begin
  Check(TestHandleCount(GetCurrentProcess, LCount), 'cannot count process handles');
  Result := LCount;
end;
{$ELSE}
var
  LSearch: TSearchRec;
begin
  Result := 0;
  Check(FindFirst('/proc/self/fd/*', faAnyFile, LSearch) = 0, 'cannot count process descriptors');
  try
    repeat
      if (LSearch.Name <> '.') and (LSearch.Name <> '..') then Inc(Result);
    until FindNext(LSearch) <> 0;
  finally
    FindClose(LSearch);
  end;
end;
{$ENDIF}

procedure EarlyFailure(const APort: Word);
var
  LSocket: TTestSocket;
  LOwner: ICrossSocket;
  LCallbacks, LErrors, LBefore, LAfter, I: Integer;

  procedure Attempt;
  begin
    try
      LSocket.ConnectBoundForTest(APort,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          Check((AConnection = nil) and not ASuccess, 'expected an early bind failure');
          Inc(LCallbacks);
          raise Exception.Create('test early failure callback');
        end);
    except
      on E: Exception do
      begin
        Check(E.Message = 'test early failure callback', 'unexpected early failure exception');
        Inc(LErrors);
      end;
    end;
  end;

begin
  LCallbacks := 0;
  LErrors := 0;
  LSocket := TTestSocket.Create('race');
  LOwner := LSocket;
  // 先完成地址解析和函数入口预热，不把一次性运行库初始化计作泄漏。
  Attempt;
  LBefore := OpenHandleCount;
  for I := 1 to 20 do Attempt;
  LAfter := OpenHandleCount;
  Print('HANDLES ' + IntToStr(LBefore) + ' ' + IntToStr(LAfter));
  Check((LCallbacks = 21) and (LErrors = 21), 'early callback count changed');
  Check(LAfter <= LBefore, 'early failure callback leaked socket handles');
  LSocket.Stop;
  LOwner := nil;
  Print('PASS early-failure');
end;

begin
  try
    if ParamStr(1) = 'early-failure' then
      EarlyFailure(StrToInt(ParamStr(2)))
    else if ParamStr(1) = 'connect-race' then
      CallbackRace(False)
    else if ParamStr(1) = 'send-close-race' then
      CallbackRace(True)
    else if ParamStr(1) = 'closed-state' then
      ClosedConnection(False)
    else if ParamStr(1) = 'closed-send' then
      ClosedConnection(True)
    else if ParamStr(1) = 'connect-callback' then
      ConnectCallback(StrToInt(ParamStr(2)))
    else
      Serve(ParamStr(1));
  except
    on E: Exception do
    begin
      Print('FAIL ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
