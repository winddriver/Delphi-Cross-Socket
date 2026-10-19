program OpenSslLoadTests;

{$I ../../../../zLib.inc}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, Utils.SyncObjs, Net.OpenSSL,
  Net.CrossSslSocket.Types, Net.CrossSslSocket.OpenSSL;

var
  SslFile, CryptoFile, BrokenFile, Mode: string;
  InitEntered, ContinueInit, ReleaseLoads, DestroyEntered, ContinueDestroy: IEvent;
  InitCalls: Integer;

procedure Check(AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

function TryLoad(out AError: string; AExpected: ExceptClass = nil): Boolean;
begin
  // 测试辅助函数：生产 API 始终使用 procedure/异常语义。
  AError := '';
  try
    TSSLTools.LoadSSL;
    Result := True;
  except
    on E: ESsl do
    begin
      if AExpected <> nil then
        Check(E.ClassType = AExpected, '加载异常类型被替换: ' + E.ClassName);
      AError := E.Message;
      Result := False;
    end;
  end;
end;

procedure Configure;
begin
  TSSLTools.LibPath := '';
  TSSLTools.LibSSL := SslFile;
  TSSLTools.LibCRYPTO := CryptoFile;
end;

procedure CheckEmpty;
begin
  Check(TSSLTools.SSLVersion = 0, '卸载后版本未归零');
  Check(not Assigned(OPENSSL_cleanup), '清理后仍保留 OPENSSL_cleanup 地址');
  Check(not Assigned(OPENSSL_init_crypto), '清理后仍保留 crypto 地址');
  Check(not Assigned(SSL_new), '清理后仍保留 SSL 地址');
  Check(not Assigned(TLS_method), '清理后仍保留 TLS_method 地址');
end;

procedure CheckReady;
var LContext: PSSL_CTX;
begin
  Check(Assigned(SSL_CTX_new) and Assigned(TLS_method), 'LoadSSL 提前返回空函数表');
  LContext := TSSLTools.NewCTX;
  Check(LContext <> nil, '无法创建真实 SSL_CTX');
  TSSLTools.FreeCTX(LContext);
end;

procedure TestFailure;
var LError: string; LExpected: ExceptClass;
begin
  if Mode = 'missing-crypto' then TSSLTools.LibCRYPTO := CryptoFile + '.missing'
  else if Mode = 'missing-proc' then TSSLTools.LibCRYPTO := BrokenFile
  else if Mode = 'auto-name' then
  begin
    TSSLTools.LibPath := ExtractFilePath(CryptoFile);
    TSSLTools.LibCRYPTO := '';
    TSSLTools.LibSSL := 'missing-ssl-library';
  end else
    TSSLTools.LibSSL := SslFile + '.missing';
  if Mode = 'missing-proc' then LExpected := ESslInvalidProc
  else LExpected := ESslInvalidLib;
  Check(not TryLoad(LError, LExpected), '错误库配置被当作加载成功');
  Check(LError <> '', '加载失败没有诊断信息');
  CheckEmpty;
  if Mode = 'auto-name' then Check(TSSLTools.LibCRYPTO = '', '失败后自动库名未恢复');
  if Mode = 'failure-exit' then Exit;
  Configure;
  Check(TryLoad(LError), LError);
  CheckReady;
  TSSLTools.UnloadSSL;
  CheckEmpty;
end;

procedure TestReferences;
var LError: string;
begin
  Check(TryLoad(LError), LError);
  Check(TryLoad(LError), LError);
  TSSLTools.UnloadSSL;
  CheckReady;
  // 活跃引用期间改配置，现有函数表继续可用。
  TSSLTools.LibSSL := SslFile + '.missing';
  CheckReady;
  TSSLTools.UnloadSSL;
  CheckEmpty;
  TSSLTools.UnloadSSL;
  Check(not TryLoad(LError), '新的库配置未在下一次加载生效');
  CheckEmpty;
  Configure;
  Check(TryLoad(LError), LError);
  CheckReady;
  TSSLTools.UnloadSSL;
  CheckEmpty;
end;

{$IFDEF NEW_SSL_LOAD}
function FailInit(AOptions: UInt64; ASettings: Pointer): Integer; cdecl;
begin
  Result := 0;
end;

function FailContext(AMethod: PSSL_METHOD): PSSL_CTX; cdecl;
begin
  Result := nil;
end;

procedure InitHook;
begin
  AtomicIncrement(InitCalls);
  if Mode = 'init-ssl-fail' then @OPENSSL_init_ssl := @FailInit
  else if Mode = 'init-crypto-fail' then @OPENSSL_init_crypto := @FailInit
  else if Mode = 'context-fail' then @SSL_CTX_new := @FailContext
  else if Mode = 'unexpected' then raise EAbort.Create('unexpected-load-test')
  else if Mode = 'concurrent' then
  begin
    InitEntered.SetEvent;
    Check(ContinueInit.WaitFor(10000) = TWaitResult.wrSignaled, '等待继续初始化超时');
  end;
end;

procedure TestInitFailure;
var LError: string; LRaised: Boolean; LSocket: TCrossOpenSslSocket;
begin
  TSSLTools.OnBeforeInitForTest := InitHook;
  try
    if Mode = 'unexpected' then
    begin
      LRaised := False;
      try TryLoad(LError); except on E: EAbort do LRaised := True; end;
      Check(LRaised, '非预期异常被转换为 False');
    end else if Mode = 'context-fail' then
    begin
      LRaised := False;
      try
        LSocket := TCrossOpenSslSocket.Create(1, True);
        LSocket.Free;
      except on E: ESsl do LRaised := True; end;
      Check(LRaised, '上下文创建失败未报告');
    end else
    begin
      Check(not TryLoad(LError, ESsl), '初始化返回零却报告成功');
      Check(Pos('OPENSSL_init_', LError) > 0, '未保留初始化失败位置');
    end;
    CheckEmpty;
  finally
    TSSLTools.OnBeforeInitForTest := nil;
  end;
  Check(TryLoad(LError), LError);
  CheckReady;
  TSSLTools.UnloadSSL;
  CheckEmpty;
end;

type
  TLoadThread = class(TThread)
  public
    Started, Returned: IEvent;
    ErrorText: string;
    constructor Create;
    procedure Execute; override;
  end;

constructor TLoadThread.Create;
begin
  inherited Create(True);
  Started := TEvent.Create(True, False);
  Returned := TEvent.Create(True, False);
end;

procedure TLoadThread.Execute;
var LError: string; LLoaded: Boolean; i: Integer;
begin
  LLoaded := False;
  if Mode = 'load-unload' then
  begin
    try
      for i := 1 to 64 do
      begin
        LLoaded := TryLoad(LError);
        Check(LLoaded, LError);
        try
          CheckReady;
        finally
          TSSLTools.UnloadSSL;
          LLoaded := False;
        end;
      end;
    except on E: Exception do ErrorText := E.Message; end;
    Exit;
  end;
  try
    Started.SetEvent;
    LLoaded := TryLoad(LError);
    Check(LLoaded, LError);
    CheckReady;
  except on E: Exception do ErrorText := E.Message; end;
  Returned.SetEvent;
  if ReleaseLoads.WaitFor(10000) <> TWaitResult.wrSignaled then
    ErrorText := '等待释放加载引用超时';
  if LLoaded then TSSLTools.UnloadSSL;
end;

procedure TestConcurrent;
var LThreads: array[0..15] of TLoadThread; i: Integer;
begin
  InitEntered := TEvent.Create(True, False);
  ContinueInit := TEvent.Create(True, False);
  ReleaseLoads := TEvent.Create(True, False);
  for i := 0 to High(LThreads) do LThreads[i] := TLoadThread.Create;
  TSSLTools.OnBeforeInitForTest := InitHook;
  try
    LThreads[0].Start;
    Check(InitEntered.WaitFor(10000) = TWaitResult.wrSignaled, '首个线程没有开始初始化');
    for i := 1 to High(LThreads) do LThreads[i].Start;
    for i := 1 to High(LThreads) do
    begin
      Check(LThreads[i].Started.WaitFor(10000) = TWaitResult.wrSignaled, '工作线程未启动');
      Check(LThreads[i].Returned.WaitFor(10) = TWaitResult.wrTimeout, '初始化完成前有调用者返回');
    end;
    ContinueInit.SetEvent;
    for i := 0 to High(LThreads) do
    begin
      Check(LThreads[i].Returned.WaitFor(10000) = TWaitResult.wrSignaled, '加载等待超时');
      Check(LThreads[i].ErrorText = '', LThreads[i].ErrorText);
    end;
    Check(InitCalls = 1, '重复初始化');
    CheckReady;
  finally
    ContinueInit.SetEvent; ReleaseLoads.SetEvent;
    for i := 0 to High(LThreads) do
    begin
      LThreads[i].WaitFor;
      Check(LThreads[i].ErrorText = '', LThreads[i].ErrorText);
      LThreads[i].Free;
    end;
    TSSLTools.OnBeforeInitForTest := nil;
  end;
  CheckEmpty;
end;

procedure TestLoadUnload;
var LThreads: array[0..15] of TLoadThread; i: Integer; LError: string;
begin
  LError := '';
  for i := 0 to High(LThreads) do LThreads[i] := TLoadThread.Create;
  for i := 0 to High(LThreads) do LThreads[i].Start;
  for i := 0 to High(LThreads) do
  begin
    LThreads[i].WaitFor;
    if LThreads[i].ErrorText <> '' then LError := LThreads[i].ErrorText;
    LThreads[i].Free;
  end;
  Check(LError = '', LError);
  CheckEmpty;
end;

type
  TFailedSocket = class(TCrossOpenSslSocket)
  public
    destructor Destroy; override;
  end;
  TFailedThread = class(TThread)
  public
    ErrorText: string;
    procedure Execute; override;
  end;

destructor TFailedSocket.Destroy;
begin
  DestroyEntered.SetEvent;
  Check(ContinueDestroy.WaitFor(10000) = TWaitResult.wrSignaled, '等待失败对象继续析构超时');
  inherited Destroy;
end;

procedure TFailedThread.Execute;
var LSocket: TFailedSocket;
begin
  try
    LSocket := TFailedSocket.Create(1, True);
    LSocket.Free;
    ErrorText := '错误配置构造成功';
  except
    on E: ESslInvalidLib do ErrorText := '';
    on E: Exception do ErrorText := E.Message;
  end;
end;

procedure TestFailedOwner;
var LThread: TFailedThread; LSocket: TCrossOpenSslSocket;
begin
  DestroyEntered := TEvent.Create(True, False);
  ContinueDestroy := TEvent.Create(True, False);
  TSSLTools.LibSSL := SslFile + '.missing';
  LThread := TFailedThread.Create(True); LSocket := nil;
  try
    LThread.Start;
    Check(DestroyEntered.WaitFor(10000) = TWaitResult.wrSignaled, '失败构造未进入析构');
    Configure;
    LSocket := TCrossOpenSslSocket.Create(1, True);
    ContinueDestroy.SetEvent;
    LThread.WaitFor;
    Check(LThread.ErrorText = '', LThread.ErrorText);
    CheckReady;
    LSocket.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
  finally
    ContinueDestroy.SetEvent; LThread.WaitFor; LThread.Free; LSocket.Free;
  end;
  CheckEmpty;
end;
{$ENDIF}

begin
  try
    Mode := ParamStr(1); SslFile := ParamStr(2); CryptoFile := ParamStr(3); BrokenFile := ParamStr(4);
    Configure;
    if Mode = 'references' then TestReferences
    {$IFDEF NEW_SSL_LOAD}
    else if Mode = 'concurrent' then TestConcurrent
    else if Mode = 'load-unload' then TestLoadUnload
    else if Mode = 'failed-owner' then TestFailedOwner
    else if (Mode = 'init-ssl-fail') or (Mode = 'init-crypto-fail') or
      (Mode = 'unexpected') or (Mode = 'context-fail') then TestInitFailure
    {$ENDIF}
    else TestFailure;
    Writeln('PASS ', Mode);
  except
    on E: Exception do begin Writeln('FAIL ', Mode, ': ', E.Message); Halt(1); end;
  end;
end.
