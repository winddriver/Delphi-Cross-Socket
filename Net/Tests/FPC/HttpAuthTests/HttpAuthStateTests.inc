type
  TAuthRequestThread = class(TThread)
  private
    FFixture: TAuthFixture;
    FAuthorization: string;
  protected
    procedure Execute; override;
  public
    Response: TTestResponse;
    ErrorText: string;
    constructor Create(const AFixture: TAuthFixture; const AAuthorization: string);
  end;

var
  AuthTestNow: UInt64;
  AuthDestroyed: Integer;
  AuthDirectProc: TCrossHttpRouterProc;

procedure InstallDirectAuth(const APasswordProc: TAuthGetPasswordProc; const ARealm: string);
begin
  // 独立作用域清除工厂返回值的编译器临时接口，确保后续真的是最后一个引用。
  AuthDirectProc := TNetCrossMiddleware.AuthenticateDigest(APasswordProc, ARealm);
end;

constructor TAuthRequestThread.Create(const AFixture: TAuthFixture;
  const AAuthorization: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FFixture := AFixture;
  FAuthorization := AAuthorization;
end;

procedure TAuthRequestThread.Execute;
begin
  try
    Response := FFixture.Request('/private', FAuthorization);
  except
    on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TestConcurrentDigest(const AOutOfOrder: Boolean);
var
  LFixture: TAuthFixture;
  LFirst, LSecond: TAuthRequestThread;
  LEntered, LRelease: IEvent;
  LArrived: Integer;
  LNonce: string;
begin
  LFixture := TAuthFixture.Create(True, True);
  LFirst := nil;
  LSecond := nil;
  LEntered := TEvent.Create(True, False);
  LRelease := TEvent.Create(True, False);
  LArrived := 0;
  try
    LNonce := LFixture.Challenge;
    LFixture.PasswordHook :=
      procedure(const ARequest: ICrossHttpRequest; const AUserName: string;
        var ACorrectPassword: string)
      begin
        if AOutOfOrder then
        begin
          if Pos('nc=00000001', ARequest.Header['Authorization']) > 0 then
          begin
            LEntered.SetEvent;
            Check(LRelease.WaitFor(5000) = TWaitResult.wrSignaled, '低 nc 请求等待超时');
          end;
        end else
        begin
          if AtomicIncrement(LArrived) = 2 then LRelease.SetEvent;
          Check(LRelease.WaitFor(5000) = TWaitResult.wrSignaled, '两个请求未同时到达密码回调');
        end;
      end;
    LFirst := TAuthRequestThread.Create(LFixture, Digest('root', 'secret', LNonce, '/private'));
    if AOutOfOrder then
      LSecond := TAuthRequestThread.Create(LFixture,
        Digest('root', 'secret', LNonce, '/private', '00000002'))
    else
      LSecond := TAuthRequestThread.Create(LFixture, Digest('root', 'secret', LNonce, '/private'));
    LFirst.Start;
    if AOutOfOrder then
      Check(LEntered.WaitFor(5000) = TWaitResult.wrSignaled, '首请求未进入密码回调');
    LSecond.Start;
    LSecond.WaitFor;
    if AOutOfOrder then
    begin
      Check(LSecond.ErrorText = '', LSecond.ErrorText);
      Check(LSecond.Response.Status = 200, '高 nc 先到达却未认证成功');
      LRelease.SetEvent;
    end;
    LFirst.WaitFor;
    Check(LFirst.ErrorText = '', LFirst.ErrorText);
    Check(LSecond.ErrorText = '', LSecond.ErrorText);
    if AOutOfOrder then
    begin
      Check(LFirst.Response.Status = 200, '乱序低 nc 被误判重放');
      Check(LFixture.BusinessCalls = 2, '两个不同 nc 没有各进入一次业务');
    end else
    begin
      Check(((LFirst.Response.Status = 200) and (LSecond.Response.Status = 401))
        or ((LFirst.Response.Status = 401) and (LSecond.Response.Status = 200)),
        '重复 nc 并发提交没有且仅有一个通过');
      Check(LFixture.BusinessCalls = 1, '重复 nc 进入业务多次');
    end;
  finally
    LRelease.SetEvent;
    if LFirst <> nil then
    begin
      if LFirst.Suspended then LFirst.Start;
      LFirst.WaitFor;
      LFirst.Free;
    end;
    if LSecond <> nil then
    begin
      if LSecond.Suspended then LSecond.Start;
      LSecond.WaitFor;
      LSecond.Free;
    end;
    LFixture.Free;
  end;
end;

function RunAdditionalCase(const AName: string): Boolean;
var
  LOptions: THttpAuthTestOptions;
  LFixture: TAuthFixture;
  LResponse: TTestResponse;
  LAuth, LNonce, LOtherNonce, LNewestNonce, LTarget, LRealm: string;
  LBytes: TBytes;
  LRaised, LReentered: Boolean;
  LMiddleware, LCopy: TCrossHttpRouterProc;
begin
  Result := (AName = 'basic-invalid-utf8') or (AName = 'basic-control')
    or (AName = 'basic-truncated') or (AName = 'basic-duplicate-header')
    or (AName = 'basic-unicode') or (AName = 'basic-realm')
    or (AName = 'basic-realm-control') or (AName = 'basic-callback-error')
    or (AName = 'digest-wrong-realm') or (AName = 'digest-wrong-qop')
    or (AName = 'digest-wrong-algorithm') or (AName = 'digest-bad-response')
    or (AName = 'digest-bad-nc') or (AName = 'digest-zero-nc')
    or (AName = 'digest-duplicate-param') or (AName = 'digest-userhash-false')
    or (AName = 'digest-userhash-true') or (AName = 'digest-userhash-invalid')
    or (AName = 'digest-username-star') or (AName = 'digest-username-colon')
    or (AName = 'digest-quoted-values') or (AName = 'digest-raw-target')
    or (AName = 'digest-realm') or (AName = 'digest-expired')
    or (AName = 'digest-expires-during-lookup') or (AName = 'digest-random-failure')
    or (AName = 'digest-random-collision') or (AName = 'digest-nonce-capacity')
    or (AName = 'digest-use-capacity') or (AName = 'digest-total-capacity')
    or (AName = 'digest-wrong-then-correct') or (AName = 'digest-business-error')
    or (AName = 'digest-nc-case-replay')
    or (AName = 'digest-callback-error') or (AName = 'digest-reentrant-callback')
    or (AName = 'digest-concurrent-same') or (AName = 'digest-concurrent-order')
    or (AName = 'digest-closure-copy') or (AName = 'digest-clear-auth-success')
    or (AName = 'digest-clear-auth-challenge') or (AName = 'digest-release-last-closure');
  if not Result then Exit;
  if (AName = 'digest-concurrent-same') or (AName = 'digest-concurrent-order') then
  begin
    TestConcurrentDigest(AName = 'digest-concurrent-order');
    Exit;
  end;

  LOptions := Default(THttpAuthTestOptions);
  AuthTestNow := 1000;
  AuthDestroyed := 0;
  LOptions.Clock := function: UInt64 begin Result := AuthTestNow; end;
  LOptions.OnDestroy := procedure begin AtomicIncrement(AuthDestroyed); end;
  if (AName = 'digest-expired') or (AName = 'digest-expires-during-lookup') then
    LOptions.NonceLifetimeMs := 100;
  if AName = 'digest-nonce-capacity' then LOptions.MaxNonces := 2;
  if AName = 'digest-use-capacity' then LOptions.MaxUsesPerNonce := 2;
  if AName = 'digest-total-capacity' then LOptions.MaxTotalUses := 2;
  if AName = 'digest-random-failure' then
    LOptions.Random := function: TBytes begin Result := nil; end;
  if AName = 'digest-random-collision' then
    LOptions.Random :=
      function: TBytes
      begin
        SetLength(Result, 32);
        FillChar(Result[0], Length(Result), 7);
      end;
  SetHttpAuthTestOptions(LOptions);
  LFixture := nil;
  try
    if AName = 'basic-realm-control' then
    begin
      LRaised := False;
      try
        LMiddleware := TNetCrossMiddleware.AuthenticateBasic(nil, 'bad' + #13 + 'realm');
      except
        on E: EArgumentException do LRaised := True;
      end;
      Check(LRaised, '认证域控制字符未被拒绝');
      Exit;
    end;
    LRealm := TEST_REALM;
    if (AName = 'basic-realm') or (AName = 'digest-realm') then LRealm := 'test"realm\name';
    if AName = 'digest-closure-copy' then
    begin
      LMiddleware := TNetCrossMiddleware.AuthenticateDigest(
        procedure(const ARequest: ICrossHttpRequest; const AUserName: string;
          var ACorrectPassword: string)
        begin
          if AUserName = 'root' then ACorrectPassword := 'secret';
        end, LRealm);
      LCopy := LMiddleware;
      LMiddleware := nil;
      LFixture := TAuthFixture.Create(True, True, LRealm, LCopy);
      LCopy := nil;
    end else
    if AName = 'digest-release-last-closure' then
    begin
      LReentered := False;
      InstallDirectAuth(
        procedure(const ARequest: ICrossHttpRequest; const AUserName: string;
          var ACorrectPassword: string)
        begin
          LReentered := True;
          AuthDirectProc := nil;
          LFixture.ClearAuth;
          Check(AuthDestroyed = 0, '调用中的认证状态提前析构');
          if AUserName = 'root' then ACorrectPassword := 'secret';
        end, LRealm);
      LMiddleware :=
        procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
          var AHandled: Boolean)
        begin
          AuthDirectProc(ARequest, AResponse, AHandled);
        end;
      LFixture := TAuthFixture.Create(True, True, LRealm, LMiddleware);
      LMiddleware := nil;
    end else
      LFixture := TAuthFixture.Create(AName.StartsWith('digest-'), True, LRealm);

    if AName.StartsWith('basic-') then
    begin
      if (AName = 'basic-invalid-utf8') or (AName = 'basic-control') then
        LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
          const AUserName: string; var ACorrectPassword: string)
          begin raise Exception.Create('非法输入不应调用密码查询'); end;
      if AName = 'basic-invalid-utf8' then
      begin
        LBytes := [$C0, $AF, Ord(':'), Ord('x')];
        LAuth := 'Basic ' + TBase64Utils.Encode(LBytes);
        LFixture.Expect('/private', LAuth, 401);
      end else
      if AName = 'basic-control' then LFixture.Expect('/private', Basic('root:secret' + #0), 401)
      else
      if AName = 'basic-truncated' then
      begin
        LAuth := Basic('root:secret');
        LFixture.Expect('/private', Copy(LAuth, 1, Length(LAuth) - 1), 401);
      end else
      if AName = 'basic-duplicate-header' then
        LFixture.Expect('/private', Basic('root:secret') + #13#10'Authorization: ' + Basic('root:secret'), 401)
      else
      if AName = 'basic-unicode' then LFixture.Expect('/private', Basic('中文用户:中文密码'), 200)
      else
      if AName = 'basic-realm' then
      begin
        LResponse := LFixture.Request('/private', '');
        Check(LResponse.Status = 401, '没有认证挑战');
        Check(Pos('test\"realm\\name', LResponse.Authenticate) > 0, '认证域没有按 quoted-string 转义');
        LFixture.Expect('/private', Basic('root:secret'), 200);
      end else
      if AName = 'basic-callback-error' then
      begin
        LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
          const AUserName: string; var ACorrectPassword: string)
          begin raise Exception.Create('密码查询测试异常'); end;
        LFixture.Expect('/private', Basic('root:secret'), 500);
        LFixture.PasswordHook := nil;
        LFixture.Expect('/private', Basic('root:secret'), 200);
      end;
      Exit;
    end;

    if AName = 'digest-random-failure' then
    begin
      LFixture.Expect('/private', '', 503);
      Exit;
    end;
    LNonce := LFixture.Challenge;
    LAuth := Digest('root', 'secret', LNonce, '/private');
    if AName = 'digest-wrong-realm' then
      LFixture.Expect('/private', LAuth.Replace('realm="' + TEST_REALM + '"', 'realm="other"'), 401)
    else
    if AName = 'digest-wrong-qop' then LFixture.Expect('/private', LAuth.Replace('qop=auth', 'qop=auth-int'), 401)
    else
    if AName = 'digest-wrong-algorithm' then LFixture.Expect('/private', LAuth + ', algorithm=SHA-256', 401)
    else
    if AName = 'digest-bad-response' then
      LFixture.Expect('/private', LAuth.Replace('response="', 'response="z'), 401)
    else
    if AName = 'digest-bad-nc' then LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', 'xyz'), 401)
    else
    if AName = 'digest-zero-nc' then LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '00000000'), 401)
    else
    if AName = 'digest-duplicate-param' then LFixture.Expect('/private', LAuth + ', username="root"', 401)
    else
    if AName = 'digest-userhash-false' then LFixture.Expect('/private', LAuth + ', userhash=false', 200)
    else
    if AName = 'digest-userhash-true' then LFixture.Expect('/private', LAuth + ', userhash=true', 401)
    else
    if AName = 'digest-userhash-invalid' then LFixture.Expect('/private', LAuth + ', userhash=invalid', 401)
    else
    if AName = 'digest-username-star' then LFixture.Expect('/private', LAuth + ', username*=UTF-8''''root', 401)
    else
    if AName = 'digest-username-colon' then
    begin
      LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
        const AUserName: string; var ACorrectPassword: string)
        begin if AUserName = 'root:extra' then ACorrectPassword := 'secret'; end;
      LFixture.Expect('/private', Digest('root:extra', 'secret', LNonce, '/private'), 401);
    end
    else
    if AName = 'digest-quoted-values' then
      LFixture.Expect('/private?x=1,2', Digest('quoted,"user\name', 'secret', LNonce, '/private?x=1,2'), 200)
    else
    if AName = 'digest-raw-target' then
    begin
      LTarget := '/%E4%B8%AD%2F+a?value=%26';
      LFixture.Expect(LTarget, Digest('root', 'secret', LNonce, LTarget), 200);
      LFixture.Expect(LTarget, Digest('root', 'secret', LNonce, '/中/ a?value=&', '00000002'), 401);
    end else
    if AName = 'digest-realm' then
    begin
      LResponse := LFixture.Request('/private', '');
      Check(Pos('test\"realm\\name', LResponse.Authenticate) > 0, 'Digest realm 未正确转义');
      LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '00000001', 'auth-test-client', LRealm), 200);
    end
    else
    if AName = 'digest-expired' then
    begin
      Inc(AuthTestNow, 100);
      LFixture.Expect('/private', LAuth, 401);
    end else
    if AName = 'digest-expires-during-lookup' then
    begin
      LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
        const AUserName: string; var ACorrectPassword: string)
        begin Inc(AuthTestNow, 100); end;
      LFixture.Expect('/private', LAuth, 401);
    end else
    if AName = 'digest-random-collision' then LFixture.Expect('/private', '', 503)
    else
    if AName = 'digest-nonce-capacity' then
    begin
      Inc(AuthTestNow);
      LOtherNonce := LFixture.Challenge;
      Inc(AuthTestNow);
      LNewestNonce := LFixture.Challenge;
      Check(LNonce <> LOtherNonce, '随机 nonce 重复');
      LFixture.Expect('/private', LAuth, 401);
      LFixture.Expect('/private', Digest('root', 'secret', LNewestNonce, '/private'), 200);
    end else
    if AName = 'digest-use-capacity' then
    begin
      LFixture.Expect('/private', LAuth, 200);
      LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '00000002'), 200);
      LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '00000003'), 401);
      LFixture.Expect('/private', LAuth, 401);
      LOtherNonce := LFixture.Challenge;
      LFixture.Expect('/private', Digest('root', 'secret', LOtherNonce, '/private'), 200);
    end else
    if AName = 'digest-total-capacity' then
    begin
      LFixture.Expect('/private', LAuth, 200);
      LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '00000002'), 200);
      Inc(AuthTestNow);
      LOtherNonce := LFixture.Challenge;
      LFixture.Expect('/private', Digest('root', 'secret', LOtherNonce, '/private'), 200);
      LFixture.Expect('/private', LAuth, 401);
      LFixture.Expect('/private', Digest('root', 'secret', LOtherNonce, '/private'), 401);
    end else
    if AName = 'digest-wrong-then-correct' then
    begin
      LFixture.Expect('/private', Digest('root', 'wrong', LNonce, '/private'), 401);
      LFixture.Expect('/private', LAuth, 200);
    end else
    if AName = 'digest-nc-case-replay' then
    begin
      LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '0000000a'), 200);
      LFixture.Expect('/private', Digest('root', 'secret', LNonce, '/private', '0000000A'), 401);
    end else
    if AName = 'digest-business-error' then
    begin
      LFixture.RaiseInBusiness := True;
      LFixture.Expect('/private', LAuth, 500, 1);
      LFixture.RaiseInBusiness := False;
      LFixture.Expect('/private', LAuth, 401);
    end else
    if AName = 'digest-callback-error' then
    begin
      LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
        const AUserName: string; var ACorrectPassword: string)
        begin raise Exception.Create('密码查询测试异常'); end;
      LFixture.Expect('/private', LAuth, 500);
      LFixture.PasswordHook := nil;
      LFixture.Expect('/private', LAuth, 200);
    end else
    if AName = 'digest-reentrant-callback' then
    begin
      LReentered := False;
      LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
        const AUserName: string; var ACorrectPassword: string)
        var LNested: TTestResponse;
        begin
          LNested := LFixture.Request('/private', '');
          Check(LNested.Status = 401, '回调内重入认证失败');
          LReentered := True;
        end;
      LFixture.Expect('/private', LAuth, 200);
      Check(LReentered, '未执行重入回调');
    end else
    if (AName = 'digest-clear-auth-success') or (AName = 'digest-clear-auth-challenge') then
    begin
      LFixture.PasswordHook := procedure(const ARequest: ICrossHttpRequest;
        const AUserName: string; var ACorrectPassword: string)
        begin
          LFixture.ClearAuth;
          Check(AuthDestroyed = 0, '认证执行中被提前析构');
        end;
      if AName = 'digest-clear-auth-success' then LFixture.Expect('/private', LAuth, 200)
      else LFixture.Expect('/private', Digest('root', 'wrong', LNonce, '/private'), 401);
      Check(AuthDestroyed = 1, '清除路由后认证状态未释放一次');
    end else
    if AName = 'digest-closure-copy' then
    begin
      LFixture.Expect('/private', LAuth, 200);
      Check(AuthDestroyed = 0, '闭包副本未保活状态');
      LFixture.ClearAuth;
      Check(AuthDestroyed = 1, '最后闭包释放后状态未析构');
    end else
    if AName = 'digest-release-last-closure' then
    begin
      LFixture.Expect('/private', Digest('root', 'wrong', LNonce, '/private'), 401);
      Check(LReentered, '直接认证没有进入密码回调');
      Check(not Assigned(AuthDirectProc), '直接认证闭包仍有全局引用');
      Check(AuthDestroyed = 1, '直接调用后认证状态析构次数: ' + IntToStr(AuthDestroyed));
    end else
      raise Exception.Create('额外用例未实现: ' + AName);
  finally
    AuthDirectProc := nil;
    LMiddleware := nil;
    LCopy := nil;
    LFixture.Free;
    LOptions := Default(THttpAuthTestOptions);
    SetHttpAuthTestOptions(LOptions);
  end;
end;
