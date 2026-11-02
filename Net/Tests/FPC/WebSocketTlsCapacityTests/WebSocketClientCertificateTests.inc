procedure TestClientCertificate(const AName, AProtocol, AHost: string;
  const APrepare, ATrustServer, AVerify, AMutual, AProvideKey, ASuccess: Boolean);
var
  LServer: ICrossWebSocketServer;
  LManager: ICrossWebSocketMgr;
  LWs: ICrossWebSocket;
  LListen, LResult: TEvent;
  LPort: Word;
  LSuccess, LRejected: Boolean;
  LUrl: string;
begin
  LPort := 0;
  LSuccess := False;
  LListen := TEvent.Create(nil, True, False, '');
  LResult := TEvent.Create(nil, True, False, '');
  try
    LServer := TCrossWebSocketServer.Create(1, True);
    LServer.SetCertificateFile(ParamStr(4));
    LServer.SetPrivateKeyFile(ParamStr(5));
    if AMutual then
    begin
      LServer.AddCACertificateFile(ParamStr(6));
      LServer.VerifyPeer := True;
    end;
    LServer.Get('/',
      procedure(const Req: ICrossHttpRequest; const Resp: ICrossHttpResponse; var Handled: Boolean)
      begin Handled := True; Resp.SendStatus(200); end);
    LServer.Addr := '127.0.0.1';
    LServer.Port := 0;
    LServer.Start(procedure(const L: ICrossListen; const OK: Boolean)
      begin if OK then LPort := L.LocalPort; LListen.SetEvent; end);
    Require((LListen.WaitFor(5000) = wrSignaled) and (LPort <> 0), '监听失败');

    LManager := TCrossWebSocketMgr.Create(1);
    if APrepare then LManager.Prepare(['https', 'wss']);
    if ATrustServer then LManager.AddCACertificateFile(ParamStr(4))
    else LManager.AddCACertificateFile(ParamStr(6));
    LManager.VerifyPeer := AVerify;
    if AProvideKey then
    begin
      LManager.SetCertificateFile(ParamStr(6));
      LManager.SetPrivateKeyFile(ParamStr(7), 'test-passphrase');
    end;
    LUrl := AProtocol + '://' + AHost + ':' + IntToStr(LPort) + '/';
    if AProtocol = 'wss' then
    begin
      LWs := LManager.CreateWebSocket(LUrl);
      LWs.OnOpen(procedure begin LSuccess := True; LResult.SetEvent; end);
      LWs.OnClose(procedure begin LResult.SetEvent; end);
      LWs.Open;
    end else
      LManager.DoRequest('GET', LUrl, nil, Pointer(nil), 0, nil, nil,
        procedure(const Resp: ICrossHttpClientResponse)
        begin LSuccess := (Resp <> nil) and (Resp.StatusCode = 200); LResult.SetEvent; end);
    Require(LResult.WaitFor(7000) = wrSignaled, AName + ' 缺少握手结果');
    Require(LSuccess = ASuccess, AName + ' 握手结果不符');
    if APrepare and AVerify and ASuccess and (AProtocol = 'wss') then
    begin
      // WSS 已冻结，先登记的 HTTPS 也不能被失败的 setter 单独改为不验证。
      LRejected := False;
      try LManager.VerifyPeer := False;
      except on E: ECrossSocket do LRejected := True; end;
      Require(LRejected and LManager.VerifyPeer, '首次 WSS 后修改验证策略未失败');
      LResult.ResetEvent;
      LManager.DoRequest('GET', 'https://127.0.0.1:' + IntToStr(LPort) + '/',
        nil, Pointer(nil), 0, nil, nil,
        procedure(const Resp: ICrossHttpClientResponse)
        begin LSuccess := (Resp <> nil) and (Resp.StatusCode = 200); LResult.SetEvent; end);
      Require((LResult.WaitFor(7000) = wrSignaled) and not LSuccess,
        '失败的 setter 改变了 HTTPS 的名称验证');
    end;
    Writeln('PASS ', AName);
  finally
    if LManager <> nil then LManager.CancelAll;
    LWs := nil;
    LManager := nil;
    if LServer <> nil then LServer.Stop;
    LServer := nil;
    LResult.Free;
    LListen.Free;
  end;
end;

procedure RunClientCertificates;
begin
  Require(ParamCount = 7, '需要服务端和客户端各自的证书、私钥');
  TestClientCertificate('wss-trusted', 'wss', 'localhost', False, True, True, False, False, True);
  TestClientCertificate('wss-name', 'wss', '127.0.0.1', True, True, True, False, False, False);
  TestClientCertificate('wss-untrusted', 'wss', 'localhost', False, False, True, False, False, False);
  TestClientCertificate('wss-no-verify', 'wss', '127.0.0.1', True, False, False, False, False, True);
  TestClientCertificate('wss-mutual-prepared', 'wss', 'localhost', True, True, True, True, True, True);
  TestClientCertificate('wss-mutual-before-prepare', 'wss', 'localhost', False, True, True, True, True, True);
  TestClientCertificate('wss-missing-client-cert', 'wss', 'localhost', False, True, True, True, False, False);
  TestClientCertificate('https-trusted', 'https', 'localhost', True, True, True, False, False, True);
  TestClientCertificate('https-untrusted', 'https', 'localhost', False, False, True, False, False, False);
end;
