unit TlsCipherHandshakeTests;

{$I ..\..\..\..\zLib.inc}

interface

procedure RunCipherHandshake;

implementation

uses
  SysUtils, SyncObjs,
  Net.CrossSocket.Base,
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket.Types,
  Net.CrossSslSocket.OpenSSL;

type
  THandshakeObserver = class
  public
    Done: TEvent;
    SslInfo: TSslInfo;
    ErrorText: string;
    Connected: Boolean;
    TransportStarted: Boolean;
    ReceivedBytes: Integer;
    procedure OnConnected(const Sender: TObject; const AConnection: ICrossConnection);
    procedure OnDisconnected(const Sender: TObject; const AConnection: ICrossConnection);
  end;

  THandshakeSocket = class(TCrossOpenSslSocket)
  public
    Observer: THandshakeObserver;
  protected
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;
  end;

procedure THandshakeSocket.TriggerConnected(const AConnection: ICrossConnection);
begin
  Observer.TransportStarted := True;
  inherited;
end;

procedure THandshakeSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  Inc(Observer.ReceivedBytes, ALen);
  inherited;
end;

procedure THandshakeObserver.OnConnected(const Sender: TObject;
  const AConnection: ICrossConnection);
begin
  Connected := True;
  try
    if not CrossOpenSslSelfTest_GetNegotiatedCipher(AConnection,
      SslInfo.SslVersion, SslInfo.CurrentCipher) then
      ErrorText := '未取得真实协商信息';
  except
    on E: Exception do ErrorText := E.Message;
  end;
  Done.SetEvent;
end;

procedure THandshakeObserver.OnDisconnected(const Sender: TObject;
  const AConnection: ICrossConnection);
begin
  Done.SetEvent;
end;

procedure CheckLocked(const AApi: ICrossSslSocket);
var
  LRejected: Boolean;
begin
  LRejected := False;
  try
    AApi.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
  except
    on E: ECrossSocket do LRejected := True;
  end;
  if not LRejected then raise Exception.Create('真实连接后 TLS 1.2 配置未锁定');
  LRejected := False;
  try
    AApi.SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
  except
    on E: ECrossSocket do LRejected := True;
  end;
  if not LRejected then raise Exception.Create('真实连接后 TLS 1.3 配置未锁定');
  LRejected := False;
  try
    AApi.SetMinTlsVersion(tmvTls13);
  except
    on E: ECrossSocket do LRejected := True;
  end;
  if not LRejected then raise Exception.Create('真实连接后最低协议版本未锁定');
  LRejected := False;
  try
    AApi.SetMinTlsVersion(tmvTls12);
  except
    on E: ECrossSocket do LRejected := True;
  end;
  if not LRejected then raise Exception.Create('真实连接后仍可恢复最低协议版本');
end;

procedure RunCipherHandshake;
var
  LObserver: THandshakeObserver;
  LSocket: THandshakeSocket;
  LApi: ICrossSslSocket;
  LPort: Integer;
begin
  // 模式、端口、TLS12名单、TLS13名单、证书、私钥、CA、协议、预期套件。
  // 可选第十项：default、tls13、restore12（先提升再恢复）。
  // 名单参数为 default 时不调用 setter，直接测试初始化默认值。
  if (ParamCount <> 9) and (ParamCount <> 10) then
    raise Exception.Create('握手测试参数数量不正确');
  LPort := StrToInt(ParamStr(2));
  if (LPort <= 0) or (LPort > 65535) then raise Exception.Create('测试端口无效');
  LObserver := THandshakeObserver.Create;
  LObserver.Done := TEvent.Create(nil, True, False, '');
  LApi := nil;
  try
    LSocket := THandshakeSocket.Create(1, True);
    LApi := LSocket;
    LSocket.Observer := LObserver;
    if ParamStr(3) <> 'default' then LApi.SetTls12CipherSuites(ParamStr(3));
    if ParamStr(4) <> 'default' then LApi.SetTls13CipherSuites(ParamStr(4));
    if ParamCount = 10 then
    begin
      if ParamStr(10) = 'tls13' then
        LApi.SetMinTlsVersion(tmvTls13)
      else
      if ParamStr(10) = 'restore12' then
      begin
        LApi.SetMinTlsVersion(tmvTls13);
        LApi.SetMinTlsVersion(tmvTls12);
      end else
      if ParamStr(10) <> 'default' then
        raise Exception.Create('最低协议版本测试参数无效');
    end;
    LApi.SetCertificateFile(ParamStr(5));
    LApi.SetPrivateKeyFile(ParamStr(6));
    LApi.AddCACertificateFile(ParamStr(7));
    LApi.VerifyPeer := True;
    LApi.OnConnected := LObserver.OnConnected;
    LApi.OnDisconnected := LObserver.OnDisconnected;
    if ParamStr(1) = '--server' then
      LApi.Listen('127.0.0.1', Word(LPort),
        procedure(const AListen: ICrossListen; const ASuccess: Boolean)
        begin
          if not ASuccess then
          begin
            LObserver.ErrorText := '测试监听失败';
            LObserver.Done.SetEvent;
          end else
          begin
            Writeln('LISTENING');
            Flush(Output);
          end;
        end)
    else
      LApi.Connect('localhost', Word(LPort));

    if LObserver.Done.WaitFor(10000) <> wrSignaled then
      raise Exception.Create('握手等待超时，不能作为负向通过');
    // 等待 IO 退出后再读取观测值并释放事件，避免迟到回调访问已释放对象。
    LApi.StopLoop;
    if LObserver.ErrorText <> '' then raise Exception.Create(LObserver.ErrorText);
    if ParamStr(9) = 'fail' then
    begin
      if LObserver.Connected or not LObserver.TransportStarted or
        (LObserver.ReceivedBytes = 0) then
        raise Exception.Create('未观察到真实握手拒绝');
      Writeln('HANDSHAKE REJECTED');
    end else
    begin
      if not LObserver.Connected then raise Exception.Create('握手未成功');
      if (LObserver.SslInfo.SslVersion <> ParamStr(8)) or
        (LObserver.SslInfo.CurrentCipher <> ParamStr(9)) then
        raise Exception.Create('实际协商协议或套件与预期不符');
      Writeln('HANDSHAKE ', LObserver.SslInfo.SslVersion, ' ',
        LObserver.SslInfo.CurrentCipher);
    end;
    CheckLocked(LApi);
  finally
    if LApi <> nil then LApi.StopLoop;
    LApi := nil;
    LObserver.Done.Free;
    LObserver.Free;
  end;
end;

end.
