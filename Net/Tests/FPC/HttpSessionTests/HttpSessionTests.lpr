program HttpSessionTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, DateUtils, Utils.SyncObjs,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossHttpSessions, Net.CrossHttpParams, Net.CrossHttpServer;

type
  TObservedSessions = class(TSessions)
  protected
    procedure BeforeClearExpiredSessions; override;
  public
    destructor Destroy; override;
  end;

  TGateSession = class(TSession)
  protected
    procedure SetLastAccessTime(const AValue: TDateTime); override;
  end;

  TSessionAction = (saGet, saExists, saReadLock, saDestroy);
  TActionThread = class(TThread)
  private
    FSessions: TSessions;
    FAction: TSessionAction;
    FID: string;
  protected
    procedure Execute; override;
  public
    Done: IEvent;
    Found: Boolean;
    Session: ISession;
    ErrorText: string;
    constructor Create(const ASessions: TSessions; const AAction: TSessionAction;
      const AID: string = 'known');
  end;

  TMemoryConnection = class(TCrossHttpConnection)
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    Sent: AnsiString;
    procedure Feed(const AText: AnsiString);
    procedure Cleanup;
  end;

var
  Mode: string;
  WorkerReady, WorkerEntered, WorkerRelease, WorkerExited, DestroyWaiting,
    TouchEntered, TouchRelease, ReadAttempt, ReadEntered: IEvent;
  SessionDestroyCount, WorkerExitCount, NextID: Integer;
  BlockTouch: Boolean;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if AValue then Exit;
  Writeln('FAIL: ', Mode, ': ', AMessage);
  Flush(Output);
  // 旧版可能已经释放仍被后台线程访问的对象，失败进程不再释放阻塞门。
  Halt(1);
end;

procedure Await(const AEvent: IEvent; const AMessage: string);
begin
  Check(AEvent.WaitFor(3000) = TWaitResult.wrSignaled, AMessage);
end;

function NewID: string;
begin
  Result := 'server-' + IntToStr(AtomicIncrement(NextID));
end;

constructor TActionThread.Create(const ASessions: TSessions; const AAction: TSessionAction;
  const AID: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSessions := ASessions;
  FAction := AAction;
  FID := AID;
  Done := TEvent.Create(True, False);
end;

procedure TActionThread.Execute;
begin
  try
    case FAction of
      saGet: Session := FSessions.Sessions[FID];
      saExists: Found := FSessions.ExistsSession(FID, Session);
      saReadLock:
        begin
          ReadAttempt.SetEvent;
          FSessions.BeginRead;
          try ReadEntered.SetEvent; finally FSessions.EndRead; end;
        end;
      saDestroy: FSessions.Free;
    end;
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
  Done.SetEvent;
end;

destructor TObservedSessions.Destroy;
begin
  inherited;
  AtomicIncrement(SessionDestroyCount);
end;

procedure TObservedSessions.BeforeClearExpiredSessions;
begin
  if Mode = 'lifecycle-locked' then
  begin
    WorkerEntered.SetEvent;
    Await(WorkerRelease, '清理锁没有得到释放信号');
  end;
  if Mode = 'lifecycle-exception' then raise Exception.Create('预期的清理异常');
end;

procedure TGateSession.SetLastAccessTime(const AValue: TDateTime);
begin
  if BlockTouch then
  begin
    TouchEntered.SetEvent;
    Await(TouchRelease, '更新时间没有得到继续信号');
  end;
  inherited;
end;

procedure InitEvents;
{$IFDEF CROSS_SESSION_TESTS}
var
  LOptions: TSessionTestOptions;
{$ENDIF}
begin
  WorkerReady := TEvent.Create(True, False);
  WorkerEntered := TEvent.Create(True, False);
  WorkerRelease := TEvent.Create(True, False);
  WorkerExited := TEvent.Create(True, False);
  DestroyWaiting := TEvent.Create(True, False);
  TouchEntered := TEvent.Create(True, False);
  TouchRelease := TEvent.Create(True, False);
  ReadAttempt := TEvent.Create(True, False);
  ReadEntered := TEvent.Create(True, False);
  {$IFDEF CROSS_SESSION_TESTS}
  LOptions := Default(TSessionTestOptions);
  if Mode = 'constructor-failure' then
    LOptions.BeforeStart := procedure begin raise Exception.Create('预期的启动前异常'); end;
  LOptions.BeforeThreadStart :=
    procedure
    begin
      if Mode = 'lifecycle-start' then
      begin
        WorkerEntered.SetEvent;
        Check(WorkerRelease.WaitFor(10000) = TWaitResult.wrSignaled, '线程入口没有得到继续信号');
      end;
    end;
  LOptions.AfterThreadStart := procedure begin WorkerReady.SetEvent; end;
  LOptions.BeforeDestroyWait := procedure begin DestroyWaiting.SetEvent; end;
  LOptions.AfterThreadExit :=
    procedure
    begin
      AtomicIncrement(WorkerExitCount);
      WorkerExited.SetEvent;
    end;
  LOptions.BeforeCleanup :=
    procedure
    begin
      if Mode = 'lifecycle-prelock' then
      begin
        WorkerEntered.SetEvent;
        Check(WorkerRelease.WaitFor(10000) = TWaitResult.wrSignaled, '清理前没有得到继续信号');
      end;
    end;
  if Mode.StartsWith('lifecycle-') and (Mode <> 'lifecycle-idle') then LOptions.CleanupIntervalMs := 1;
  SetSessionTestOptions(LOptions);
  {$ENDIF}
end;

function CreateSessions: TObservedSessions;
begin
  Result := TObservedSessions.Create(function: string begin Result := NewID; end);
  {$IFDEF CROSS_SESSION_TESTS}
  if Mode <> 'lifecycle-start' then Await(WorkerReady, '清理线程没有启动');
  {$ENDIF}
end;

procedure TestSemantics;
var
  LSessions: TObservedSessions;
  LOld, LValue, LFound: ISession;
  LLastAccess: TDateTime;
  LRaised: Boolean;
begin
  LSessions := CreateSessions;
  try
    if Mode = 'bad-id-generator' then
    begin
      LSessions.NewGUIDFunc := function: string begin Result := ''; end;
      LRaised := False;
      try LValue := LSessions.Sessions['attacker']; except on E: Exception do LRaised := True; end;
      Check(LRaised and (LSessions.Count = 0), '空 ID 生成器没有明确失败');
      LSessions.NewGUIDFunc := function: string begin Result := 'attacker'; end;
      LRaised := False;
      try LValue := LSessions.Sessions['attacker']; except on E: Exception do LRaised := True; end;
      Check(LRaised and (LSessions.Count = 0), '生成器再次接纳客户端指定 ID');
      LSessions.NewGUIDFunc := function: string begin Result := NewID; end;
      LValue := LSessions.Sessions['attacker'];
      Check((LValue.SessionID <> '') and (LValue.SessionID <> 'attacker'), '生成器失败后锁未释放或无法恢复');
      Exit;
    end;
    if Mode = 'unknown-id' then
    begin
      LValue := LSessions.Sessions['attacker'];
      Check((LValue.SessionID <> 'attacker') and (LValue.SessionID <> ''), '采用了客户端未知 ID');
      Check(not LSessions.ExistsSession('attacker'), '仍然保存客户端未知 ID');
      Exit;
    end;
    if Mode = 'id-collision' then
    begin
      LOld := LSessions.AddSession('server-1');
      LOld['role'] := 'old';
      LValue := LSessions.Sessions['attacker'];
      Check((LValue.SessionID <> 'attacker') and (LValue.SessionID <> 'server-1'), '新 ID 没有避开现有会话');
      Check(LSessions.Sessions['server-1'] = LOld, '生成 ID 覆盖了已有会话');
      Exit;
    end;
    LOld := LSessions.AddSession('known');
    LOld['role'] := 'admin';
    LOld.ExpiryTime := 10;
    LLastAccess := IncSecond(Now, -30);
    if (Mode = 'expired-get') or (Mode = 'expired-exists') then LOld.LastAccessTime := LLastAccess;
    if Mode = 'expired-get' then
    begin
      LValue := LSessions.Sessions['known'];
      Check((LValue <> LOld) and (LValue.SessionID <> 'known'), '过期会话被复活');
      Check(LValue['role'] = '', '新会话继承了旧认证数据');
      Check(LOld.LastAccessTime = LLastAccess, '过期对象仍被刷新');
    end else
    if Mode = 'expired-exists' then
    begin
      LFound := LOld;
      Check(not LSessions.ExistsSession('known', LFound), 'ExistsSession 复活了过期会话');
      Check((LFound = nil) and (LSessions.Count = 0), '过期输出或字典未清理');
      Check(LOld.LastAccessTime = LLastAccess, '过期对象仍被刷新');
    end else
    if Mode = 'imported-id' then
      Check(LSessions.Sessions['known'] = LOld, '显式导入 ID 被替换')
    else
    if Mode = 'touch-valid' then
    begin
      LOld.LastAccessTime := IncSecond(Now, -2);
      Check(LSessions.ExistsSession('known', LFound) and (LFound = LOld), '有效会话未找到');
      Check(SecondsBetween(Now, LOld.LastAccessTime) <= 1, '有效会话没有续期');
    end else
    if Mode = 'writer-reentry' then
    begin
      LSessions.BeginWrite;
      try
        Check(LSessions.Sessions['known'] = LOld, '写锁内获取错误');
        Check(LSessions.ExistsSession('known', LFound), '写锁内检查错误');
      finally
        LSessions.EndWrite;
      end;
    end else
      Check(False, '未知语义用例');
  finally
    LOld := nil;
    LValue := nil;
    LFound := nil;
    LSessions.Free;
  end;
end;

procedure TestLockedTouch;
var
  LSessions: TObservedSessions;
  LSession: ISession;
  LGetter, LReader: TActionThread;
begin
  LSessions := CreateSessions;
  LSessions.SessionClass := TGateSession;
  LSession := LSessions.AddSession('known');
  BlockTouch := True;
  if Mode = 'get-touch-locked' then LGetter := TActionThread.Create(LSessions, saGet)
  else LGetter := TActionThread.Create(LSessions, saExists);
  LReader := TActionThread.Create(LSessions, saReadLock);
  try
    LGetter.Start;
    Await(TouchEntered, '获取没有执行更新时间');
    LReader.Start;
    Await(ReadAttempt, '读取线程未启动');
    Check(ReadEntered.WaitFor(150) = TWaitResult.wrTimeout, '更新时间不在会话写锁内');
    TouchRelease.SetEvent;
    Await(LGetter.Done, '获取没有完成');
    Await(LReader.Done, '读取没有完成');
    Check((LGetter.ErrorText = '') and (LReader.ErrorText = ''), '获取/读取线程异常');
    Check(LGetter.Session = LSession, '获取没有返回已导入的会话');
    LGetter.WaitFor;
    LReader.WaitFor;
  finally
    BlockTouch := False;
    LGetter.Free;
    LReader.Free;
    LSession := nil;
    LSessions.Free;
  end;
end;

procedure TestConcurrentGet;
var
  LSessions: TObservedSessions;
  LOne, LTwo: TActionThread;
  LExisting: ISession;
  LID: string;
begin
  LSessions := CreateSessions;
  LID := 'attacker';
  if Mode = 'concurrent-known' then
  begin
    LID := 'known';
    LExisting := LSessions.AddSession(LID);
  end;
  LOne := TActionThread.Create(LSessions, saGet, LID);
  LTwo := TActionThread.Create(LSessions, saGet, LID);
  try
    LOne.Start;
    LTwo.Start;
    Await(LOne.Done, '第一个获取未完成');
    Await(LTwo.Done, '第二个获取未完成');
    Check((LOne.ErrorText = '') and (LTwo.ErrorText = ''), '并发获取异常');
    if LID = 'known' then Check((LOne.Session = LExisting) and (LTwo.Session = LExisting), '有效 ID 重复发布')
    else Check((LOne.Session.SessionID <> 'attacker') and (LTwo.Session.SessionID <> 'attacker')
      and (LOne.Session <> LTwo.Session), '未知客户端 ID 被共享为固定会话');
    LOne.WaitFor;
    LTwo.WaitFor;
  finally
    LOne.Free;
    LTwo.Free;
    LExisting := nil;
    LSessions.Free;
  end;
end;

procedure TestLifecycle;
var
  LSessions: TObservedSessions;
  LDestroyer: TActionThread;
  LDelay: Cardinal;
  LRaised: Boolean;
begin
  {$IFNDEF CROSS_SESSION_TESTS}
  Check(False, '生命周期用例需要 CROSS_SESSION_TESTS');
  {$ENDIF}
  if Mode = 'constructor-failure' then
  begin
    LRaised := False;
    try
      LSessions := CreateSessions;
    except
      on E: Exception do
      begin
        Check(E.Message = '预期的启动前异常', '构造失败变成其他异常: ' + E.Message);
        LRaised := True;
      end;
    end;
    Check(LRaised and (SessionDestroyCount = 1), '未启动线程构造失败未完成唯一析构');
    Exit;
  end;
  LSessions := CreateSessions;
  LSessions.ExpiryTime := 1;
  if Mode = 'lifecycle-exception' then
  begin
    Await(WorkerExited, '异常后线程没有退出');
    LSessions.Free;
    Check((WorkerExitCount = 1) and (SessionDestroyCount = 1), '异常后未释放一次');
    Exit;
  end;
  if Mode <> 'lifecycle-idle' then Await(WorkerEntered, '没有进入受控线程阶段');
  LDestroyer := TActionThread.Create(LSessions, saDestroy);
  try
    LDestroyer.Start;
    Await(DestroyWaiting, '析构没有进入等待阶段');
    if Mode <> 'lifecycle-idle' then
    begin
      LDelay := 150;
      if Mode = 'lifecycle-prelock' then LDelay := 6000;
      Check(LDestroyer.Done.WaitFor(LDelay) = TWaitResult.wrTimeout, '清理线程尚未结束，容器已释放');
      WorkerRelease.SetEvent;
    end;
    Await(LDestroyer.Done, '清理线程结束后析构仍未完成');
    Check(LDestroyer.ErrorText = '', LDestroyer.ErrorText);
    Check((WorkerExitCount = 1) and (SessionDestroyCount = 1), '线程/容器未恰好结束一次');
    LDestroyer.WaitFor;
  finally
    LDestroyer.Free;
  end;
end;

procedure TMemoryConnection.DirectSend(const ABuffer: Pointer; const ACount: Integer;
  const ACallback: TCrossConnectionCallback);
var LData: AnsiString;
begin
  SetString(LData, PAnsiChar(ABuffer), ACount);
  Sent := Sent + LData;
  if Assigned(ACallback) then ACallback(Self, True);
end;

procedure TMemoryConnection.Feed(const AText: AnsiString);
var LBuffer: Pointer; LLength, LBefore: Integer;
begin
  LBuffer := PAnsiChar(AText);
  LLength := Length(AText);
  _LockRecv;
  try
    while LLength > 0 do
    begin
      LBefore := LLength;
      ParseRecvData(LBuffer, LLength);
      Check(LLength < LBefore, 'HTTP 解析未消费输入');
    end;
  finally _UnlockRecv; end;
end;

procedure TMemoryConnection.Cleanup;
begin
  ConnectStatus := csClosed;
  InternalClose;
end;

procedure TestHttpCookie;
var
  LSessions: ISessions;
  LServer: ICrossHttpServer;
  LConnection: ICrossHttpConnection;
  LObject: TMemoryConnection;
  LImported: ISession;
  LID, LSeenID: string;
begin
  LSessions := CreateSessions;
  LID := 'attacker';
  if Mode <> 'http-unknown-cookie' then
  begin
    LID := 'known';
    LImported := LSessions.AddSession(LID);
    LImported['role'] := 'admin';
    if Mode = 'http-expired-cookie' then
    begin
      LImported.ExpiryTime := 10;
      LImported.LastAccessTime := IncSecond(Now, -30);
    end;
  end;
  LServer := TCrossHttpServer.Create(1, False);
  LServer.Sessions := LSessions;
  LServer.SessionIDCookieName := 'test-session';
  LServer.Get('/', procedure(const ARequest: ICrossHttpRequest;
    const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      LSeenID := ARequest.Session.SessionID;
      AResponse.Send('ok');
    end);
  LObject := TMemoryConnection.Create(LServer as TCrossHttpServer, INVALID_SOCKET, ctAccept, '', nil);
  LConnection := LObject;
  LObject.ConnectStatus := csConnected;
  try
    LObject.Feed(AnsiString('GET / HTTP/1.1'#13#10'Host: localhost'#13#10 +
      'Cookie: test-session=' + LID + #13#10#13#10));
    Check(Pos('HTTP/1.1 200 ', string(LObject.Sent)) = 1, '请求没有正常响应');
    if Mode = 'http-known-cookie' then
      Check((LSeenID = 'known') and (Pos('Set-Cookie:', string(LObject.Sent)) = 0), '有效 Cookie 被替换')
    else
    begin
      Check((LSeenID <> '') and (LSeenID <> LID), '未知/过期 Cookie ID 未轮换');
      Check(Pos('test-session=' + LSeenID, string(LObject.Sent)) > 0, '新会话 ID 没有写回 Cookie');
    end;
  finally
    LObject.Cleanup;
    LConnection := nil;
    LServer := nil;
    LImported := nil;
    LSessions := nil;
  end;
end;

procedure TestUnitCompatibility;
var
  LOld: Net.CrossHttpParams.ISessions;
  LNew: Net.CrossHttpSessions.ISessions;
  LItem: Net.CrossHttpParams.ISession;
  LClass: Net.CrossHttpParams.TSessionClass;
begin
  Check(TypeInfo(Net.CrossHttpParams.ISession) = TypeInfo(Net.CrossHttpSessions.ISession),
    '旧新Session接口不是同一个类型');
  Check(TypeInfo(Net.CrossHttpParams.ISessions) = TypeInfo(Net.CrossHttpSessions.ISessions),
    '旧新容器接口不是同一个类型');
  LNew := Net.CrossHttpSessions.TSessions.Create;
  LOld := LNew;
  LClass := Net.CrossHttpParams.TSession;
  LOld.SessionClass := LClass;
  LOld.BeginWrite;
  try
    LItem := LOld.AddSession('compatibility');
    LItem['key'] := 'value';
  finally
    LOld.EndWrite;
  end;
  Check(LNew['compatibility']['key'] = 'value', '新旧路径未共享同一会话实例');
  LItem := nil;
  LOld := nil;
  LNew := nil;
end;

begin
  SetTextCodePage(Output, 65001);
  Mode := ParamStr(1);
  Check(ParamCount = 1, '用法: HttpSessionTests <case>');
  InitEvents;
  if Mode = 'unit-compatibility' then TestUnitCompatibility
  else if Mode.StartsWith('lifecycle-') or (Mode = 'constructor-failure') then TestLifecycle
  else
  if Mode.StartsWith('http-') then TestHttpCookie
  else
  if Mode.StartsWith('concurrent-') then TestConcurrentGet
  else
  if Mode.EndsWith('-touch-locked') then TestLockedTouch
  else TestSemantics;
  Writeln('PASS: ', Mode);
end.
