program HttpAuthTests;

{$I ..\..\..\..\zLib.inc}

uses
  SysUtils, Classes
  {$IFDEF FPC}
  ,DTF.RTL in '..\..\..\..\DelphiToFPC\DTF.RTL.pas'
  {$ENDIF}
  ,Utils.SyncObjs in '..\..\..\..\Utils\Utils.SyncObjs.pas'
  ,Utils.Base64 in '..\..\..\..\Utils\Utils.Base64.pas'
  ,Utils.Hash in '..\..\..\..\Utils\Utils.Hash.pas'
  ,Utils.Utils in '..\..\..\..\Utils\Utils.Utils.pas'
  ,Net.SocketAPI in '..\..\..\Net.SocketAPI.pas'
  ,Net.CrossSocket.Base in '..\..\..\Net.CrossSocket.Base.pas'
  ,Net.CrossSocket.Iocp in '..\..\..\Net.CrossSocket.Iocp.pas'
  ,Net.CrossSocket in '..\..\..\Net.CrossSocket.pas'
  ,Net.CrossSslSocket.Base in '..\..\..\Net.CrossSslSocket.Base.pas'
  ,Net.CrossSslSocket.OpenSSL in '..\..\..\Net.CrossSslSocket.OpenSSL.pas'
  ,Net.CrossSslSocket in '..\..\..\Net.CrossSslSocket.pas'
  ,Net.CrossServer in '..\..\..\Net.CrossServer.pas'
  ,Net.CrossHttpUtils in '..\..\..\Net.CrossHttpUtils.pas'
  ,Net.CrossHttpParams in '..\..\..\Net.CrossHttpParams.pas'
  ,Net.CrossHttpParser in '..\..\..\Net.CrossHttpParser.pas'
  ,Net.CrossHttpServer in '..\..\..\Net.CrossHttpServer.pas'
  ,Net.CrossHttpMiddleware in '..\..\..\Net.CrossHttpMiddleware.pas'
  ;

const
  TEST_REALM = 'http-auth-tests';

type
  TTestResponse = record
    Status: Integer;
    Authenticate: string;
  end;

  TTestConnection = class(TCrossHttpConnection)
  private
    FClosedForTest: Boolean;
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    SentData: AnsiString;
    procedure Feed(const AData: AnsiString);
    procedure CloseForTest;
  end;

  TAuthFixture = class
  private
    FServer: ICrossHttpServer;
    FBusinessCalls: Integer;
  public
    PasswordHook: TAuthGetPasswordProc;
    RaiseInBusiness: Boolean;
    constructor Create(const ADigest, AUseCallback: Boolean;
      const ARealm: string = TEST_REALM; const AMiddleware: TCrossHttpRouterProc = nil);
    function Request(const ATarget, AAuthorization: string): TTestResponse;
    procedure Expect(const ATarget, AAuthorization: string; const AStatus: Integer;
      const ABusinessCalls: Integer = -1);
    function Challenge: string;
    function BusinessCalls: Integer;
    procedure ClearAuth;
  end;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure TTestConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LData: AnsiString;
begin
  // 仅替代网络写入；请求解析、路由、中间件及响应队列使用真实源码。
  SetString(LData, PAnsiChar(ABuffer), ACount);
  SentData := SentData + LData;
  if Assigned(ACallback) then ACallback(Self, True);
end;

procedure TTestConnection.Feed(const AData: AnsiString);
var
  LBuffer: Pointer;
  LLength, LBefore: Integer;
begin
  LBuffer := PAnsiChar(AData);
  LLength := Length(AData);
  _LockRecv;
  try
    while LLength > 0 do
    begin
      LBefore := LLength;
      ParseRecvData(LBuffer, LLength);
      Check(LLength < LBefore, '解析器未消费输入');
    end;
  finally
    _UnlockRecv;
  end;
end;

procedure TTestConnection.CloseForTest;
begin
  if FClosedForTest then Exit;
  FClosedForTest := True;
  // INVALID_SOCKET 连接需要显式进入真实清理，解除请求/响应引用环。
  ConnectStatus := csClosed;
  InternalClose;
end;

constructor TAuthFixture.Create(const ADigest, AUseCallback: Boolean;
  const ARealm: string; const AMiddleware: TCrossHttpRouterProc);
var
  LPasswordProc: TAuthGetPasswordProc;
begin
  inherited Create;
  FServer := TCrossHttpServer.Create(1, False);
  FServer.Compressible := False;
  LPasswordProc := nil;
  if AUseCallback then
    LPasswordProc :=
      procedure(const ARequest: ICrossHttpRequest; const AUserName: string;
        var ACorrectPassword: string)
      begin
        // 固定测试凭据；未知用户保持旧接口的未赋值行为。
        if Assigned(PasswordHook) then PasswordHook(ARequest, AUserName, ACorrectPassword);
        if AUserName = 'root' then ACorrectPassword := 'secret'
        else
        if AUserName = 'empty' then ACorrectPassword := ''
        else
        if AUserName = 'colon' then ACorrectPassword := 'part:two'
        else
        if AUserName = '中文用户' then ACorrectPassword := '中文密码'
        else
        if AUserName = 'quoted,"user\name' then ACorrectPassword := 'secret';
      end;

  if Assigned(AMiddleware) then
    FServer.Use(AMiddleware)
  else
  if ADigest then
    FServer.Use(TNetCrossMiddleware.AuthenticateDigest(LPasswordProc, ARealm))
  else
    FServer.Use(TNetCrossMiddleware.AuthenticateBasic(LPasswordProc, ARealm));

  FServer.Get('*',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
      var AHandled: Boolean)
    begin
      AtomicIncrement(FBusinessCalls);
      if RaiseInBusiness then raise Exception.Create('业务测试异常');
      AResponse.Send('ok');
    end);
end;

function TAuthFixture.Request(const ATarget, AAuthorization: string): TTestResponse;
var
  LObject: TTestConnection;
  LConnection: ICrossHttpConnection;
  LRequest, LReply, LLine: string;
  LLines: TStringList;
  I, LColon, LHeaderEnd: Integer;
begin
  Result.Status := 0;
  Result.Authenticate := '';
  LObject := TTestConnection.Create(FServer as TCrossHttpServer,
    INVALID_SOCKET, ctAccept, '', nil);
  LConnection := LObject;
  LObject.ConnectStatus := csConnected;
  try
    // 每次请求使用独立连接；同一 fixture 内的 Digest 状态应跨连接保留。
    LRequest := 'GET ' + ATarget + ' HTTP/1.1'#13#10'Host: localhost'#13#10;
    if AAuthorization <> '' then
      LRequest := LRequest + 'Authorization: ' + AAuthorization + #13#10;
    LObject.Feed(AnsiString(LRequest + #13#10));
    LReply := string(LObject.SentData);
    LHeaderEnd := Pos(#13#10#13#10, LReply);
    Check(LHeaderEnd > 0, '没有完整响应头');
    Check(Copy(LReply, 1, 9) = 'HTTP/1.1 ', '意外响应状态行');
    Result.Status := StrToInt(Copy(LReply, 10, 3));
    LLines := TStringList.Create;
    try
      LLines.Text := Copy(LReply, 1, LHeaderEnd - 1);
      for I := 1 to LLines.Count - 1 do
      begin
        LLine := LLines[I];
        LColon := Pos(':', LLine);
        if (LColon > 0) and SameText(Copy(LLine, 1, LColon - 1), 'WWW-Authenticate') then
          Result.Authenticate := Trim(Copy(LLine, LColon + 1, MaxInt));
      end;
    finally
      LLines.Free;
    end;
    Check(LConnection.Pending = 0, '响应队列未完成');
  finally
    LObject.CloseForTest;
    LConnection := nil;
  end;
end;

procedure TAuthFixture.Expect(const ATarget, AAuthorization: string;
  const AStatus, ABusinessCalls: Integer);
var
  LResponse: TTestResponse;
  LCalls, LExpectedCalls: Integer;
begin
  LCalls := FBusinessCalls;
  LResponse := Request(ATarget, AAuthorization);
  Check(LResponse.Status = AStatus,
    Format('预期 %d，实际 %d；业务命中增量 %d',
      [AStatus, LResponse.Status, FBusinessCalls - LCalls]));
  LExpectedCalls := ABusinessCalls;
  if LExpectedCalls < 0 then
  begin
    if AStatus = 200 then LExpectedCalls := 1 else LExpectedCalls := 0;
  end;
  Check(FBusinessCalls = LCalls + LExpectedCalls, '受保护业务调用次数错误');
  if AStatus = 401 then
    Check(LResponse.Authenticate <> '', '401 缺少认证挑战');
end;

function TAuthFixture.BusinessCalls: Integer;
begin
  Result := AtomicCmpExchange(FBusinessCalls, 0, 0);
end;

procedure TAuthFixture.ClearAuth;
begin
  FServer.ClearMiddlewares;
end;

function TAuthFixture.Challenge: string;
var
  LResponse: TTestResponse;
  LBegin, LEnd, LCalls: Integer;
begin
  LCalls := BusinessCalls;
  LResponse := Request('/private', '');
  Check(LResponse.Status = 401, '未认证请求未返回 401');
  Check(BusinessCalls = LCalls, '挑战请求进入业务');
  LBegin := Pos('nonce="', LResponse.Authenticate);
  Check(LBegin > 0, 'Digest 挑战缺少 nonce');
  Result := Copy(LResponse.Authenticate, LBegin + 7, MaxInt);
  LEnd := Pos('"', Result);
  Check(LEnd > 1, 'Digest nonce 为空或未闭合');
  Result := Copy(Result, 1, LEnd - 1);
end;

function Basic(const ACredentials: string): string;
begin
  Result := 'Basic ' + TBase64Utils.Encode(ACredentials);
end;

function MD5Hex(const AValue: string): string;
begin
  Result := TUtils.BytesToHex(Utils.Hash.THashMD5.GetHashBytes(AValue));
end;

function Digest(const AUserName, APassword, ANonce, AUri: string;
  const ANc: string = '00000001'; const ACnonce: string = 'auth-test-client';
  const ARealm: string = TEST_REALM): string;
var
  LResponse: string;

  function Quote(const AValue: string): string;
  begin
    Result := AValue.Replace('\', '\\').Replace('"', '\"');
  end;
begin
  // 标准 qop=auth 公式，实际请求目标由测试单独指定。
  LResponse := MD5Hex(MD5Hex(AUserName + ':' + ARealm + ':' + APassword) +
    ':' + ANonce + ':' + ANc + ':' + ACnonce + ':auth:' + MD5Hex('GET:' + AUri));
  Result := Format('Digest username="%s", realm="%s", nonce="%s", uri="%s", ' +
    'response="%s", qop=auth, nc=%s, cnonce="%s"',
    [Quote(AUserName), Quote(ARealm), ANonce, Quote(AUri), LResponse, ANc, Quote(ACnonce)]);
end;

{$IFDEF CROSS_HTTP_AUTH_TESTS}
{$I HttpAuthStateTests.inc}
{$ENDIF}

procedure RunCase(const AName: string);
var
  LFixture: TAuthFixture;
  LAuth, LNonce, LTarget: string;
  LExpected: Integer;
begin
  {$IFDEF CROSS_HTTP_AUTH_TESTS}
  if RunAdditionalCase(AName) then Exit;
  {$ENDIF}
  LFixture := TAuthFixture.Create(AName.StartsWith('digest-'),
    (AName <> 'basic-nil') and (AName <> 'digest-nil'));
  try
    LExpected := 401;
    LTarget := '/private';
    if AName.StartsWith('basic-') then
    begin
      if AName = 'basic-valid' then
      begin
        LAuth := Basic('root:secret');
        LExpected := 200;
      end else
      if AName = 'basic-empty' then
      begin
        LAuth := Basic('empty:');
        LExpected := 200;
      end else
      if AName = 'basic-colon' then
      begin
        LAuth := Basic('colon:part:two');
        LExpected := 200;
      end else
      if (AName = 'basic-unknown') or (AName = 'basic-nil') then
        LAuth := Basic('missing:' + #0)
      else
      if AName = 'basic-bad-alphabet' then
        LAuth := 'Basic ' + '$' + TBase64Utils.Encode('root:secret')
      else
      if AName = 'basic-bad-padding' then
        LAuth := Basic('root:secret') + '='
      else
      if AName = 'basic-bad-scheme' then
        LAuth := 'BasicX' + TBase64Utils.Encode('root:secret')
      else
      if AName = 'basic-missing-colon' then
        LAuth := Basic('root')
      else
      if AName = 'basic-wrong-password' then
        LAuth := Basic('root:wrong')
      else
        raise Exception.Create('未知测试: ' + AName);
    end else
    if AName.StartsWith('digest-') then
    begin
      LNonce := LFixture.Challenge;
      LAuth := Digest('root', 'secret', LNonce, '/private');
      if AName = 'digest-valid' then
        LExpected := 200
      else
      if (AName = 'digest-unknown') or (AName = 'digest-nil') then
        LAuth := Digest('missing', #0, LNonce, '/private')
      else
      if AName = 'digest-arbitrary-nonce' then
        LAuth := Digest('root', 'secret', 'client-invented-nonce', '/private')
      else
      if AName = 'digest-cross-target' then
        LTarget := '/other'
      else
      if AName = 'digest-replay' then
        LFixture.Expect(LTarget, LAuth, 200)
      else
      if AName = 'digest-bad-scheme' then
        LAuth := 'DigestX' + Copy(LAuth, 8, MaxInt)
      else
      if AName = 'digest-wrong-password' then
        LAuth := Digest('root', 'wrong', LNonce, '/private')
      else
        raise Exception.Create('未知测试: ' + AName);
    end else
      raise Exception.Create('未知测试: ' + AName);
    LFixture.Expect(LTarget, LAuth, LExpected);
  finally
    LFixture.Free;
  end;
end;

begin
  SetTextCodePage(Output, 65001);
  try
    Check(ParamCount = 1, '用法: HttpAuthTests <case>');
    RunCase(ParamStr(1));
    Writeln('PASS: ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', ParamStr(1), ': ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
