program SslInfoTests;

{$I ../../../../zLib.inc}

uses
  SysUtils, Classes, Net.OpenSSL, Net.CrossSslSocket.Types;

type
  TSslCtrl = function(ASsl: PSSL; ACmd: Integer; AArg: NativeInt;
    AData: Pointer): NativeInt; cdecl;
  TFreeKey = procedure(AKey: PEVP_PKEY); cdecl;
  TKeyBits = function(AKey: PEVP_PKEY): Integer; cdecl;

var
  OriginalCtrl: TSslCtrl;
  OriginalFreeKey: TFreeKey;
  OriginalKeyBits: TKeyBits;
  KeysAcquired, KeysReleased: Integer;
  LastKey: PEVP_PKEY;
  RejectKey, RaiseOnKey: Boolean;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

function ObserveCtrl(ASsl: PSSL; ACmd: Integer; AArg: NativeInt;
  AData: Pointer): NativeInt; cdecl;
begin
  if (ACmd = SSL_CTRL_GET_PEER_TMP_KEY) and RejectKey then
  begin
    // 强制失败且输出不可使用，验证上层必须检查返回值，不能碰输出指针。
    PPEVP_PKEY(AData)^ := Pointer(NativeUInt(1));
    Exit(0);
  end;
  Result := OriginalCtrl(ASsl, ACmd, AArg, AData);
  if (ACmd = SSL_CTRL_GET_PEER_TMP_KEY) and (Result = 1) then
  begin
    LastKey := PPEVP_PKEY(AData)^;
    Inc(KeysAcquired);
  end;
end;

procedure ObserveFreeKey(AKey: PEVP_PKEY); cdecl;
begin
  if (AKey <> nil) and (AKey = LastKey) then Inc(KeysReleased);
  OriginalFreeKey(AKey);
end;

function ObserveKeyBits(AKey: PEVP_PKEY): Integer; cdecl;
begin
  if RaiseOnKey and (AKey = LastKey) then
    raise Exception.Create('临时密钥字段读取测试异常');
  Result := OriginalKeyBits(AKey);
end;

procedure InstallObservers;
begin
  OriginalCtrl := SSL_ctrl;
  OriginalFreeKey := EVP_PKEY_free;
  OriginalKeyBits := EVP_PKEY_get_bits;
  SSL_ctrl := ObserveCtrl;
  EVP_PKEY_free := ObserveFreeKey;
  EVP_PKEY_get_bits := ObserveKeyBits;
end;

procedure RestoreObservers;
begin
  SSL_ctrl := OriginalCtrl;
  EVP_PKEY_free := OriginalFreeKey;
  EVP_PKEY_get_bits := OriginalKeyBits;
end;

procedure TestBeforeHandshake(const AForcedFailure: Boolean);
var
  LCtx: PSSL_CTX;
  LSsl: PSSL;
  LKey: PEVP_PKEY;
  LInfo: TSslInfo;
begin
  LCtx := TSSLTools.NewCTX(TLS_method());
  try
    LSsl := SSL_new(LCtx);
    Check(LSsl <> nil, 'SSL_new 失败');
    try
      LKey := Pointer(NativeUInt($1234));
      Check(SSL_get_peer_tmp_key(LSsl, @LKey) = 0, '未握手却取得临时密钥');
      Check(LKey = Pointer(NativeUInt($1234)), '原生失败路径改变了输出指针');
      Writeln('NATIVE no-key return=0 unchanged-output=0x1234');
      RejectKey := AForcedFailure;
      InstallObservers;
      try
        Check(TSSLTools.GetSslInfo(LSsl, LInfo), '有效 SSL 对象未返回信息');
        Check((LInfo.TmpKeyID = 0) and (LInfo.TmpKeyType = '') and
          (LInfo.TmpKeyBits = 0), '未取得密钥时临时字段不为空');
        Check((KeysAcquired = 0) and (KeysReleased = 0), '失败输出被作为所有权引用处理');
      finally
        RestoreObservers;
      end;
    finally
      SSL_free(LSsl);
    end;
  finally
    TSSLTools.FreeCTX(LCtx);
  end;
end;

procedure Transfer(const AOutput, AInput: PBIO);
var
  LBuffer: array[0..32767] of Byte;
  LCount: Integer;
begin
  while BIO_pending(AOutput) > 0 do
  begin
    LCount := BIO_read(AOutput, @LBuffer[0], SizeOf(LBuffer));
    Check(LCount > 0, '读取握手密文失败');
    Check(BIO_write(AInput, @LBuffer[0], LCount) = LCount, '写入握手密文失败');
  end;
end;

procedure Advance(const ASsl: PSSL; var ADone: Boolean);
var
  LResult, LError: Integer;
begin
  if ADone then Exit;
  ERR_clear_error();
  LResult := SSL_do_handshake(ASsl);
  if LResult = 1 then
    ADone := True
  else
  begin
    LError := SSL_get_error(ASsl, LResult);
    Check(LError in [SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE],
      '真实握手失败: ' + GetOpenSslErrors);
  end;
end;

procedure Inspect(const ASsl: PSSL; const AVersion, ASide: string;
  const AExpectKey, AInjectError: Boolean);
var
  LInfo: TSslInfo;
  I: Integer;
  LRaised: Boolean;
begin
  KeysAcquired := 0;
  KeysReleased := 0;
  LastKey := nil;
  RaiseOnKey := AInjectError;
  InstallObservers;
  try
    for I := 1 to 32 do
    begin
      LRaised := False;
      try
        Check(TSSLTools.GetSslInfo(ASsl, LInfo), '读取协商信息失败');
      except
        on E: Exception do
        begin
          LRaised := E.Message = '临时密钥字段读取测试异常';
          if not LRaised then raise;
        end;
      end;
      Check(LRaised = AInjectError, '字段读取异常未按预期传播');
      Check(KeysAcquired = KeysReleased, Format('临时密钥引用泄漏: acquired=%d released=%d',
        [KeysAcquired, KeysReleased]));
      if not AInjectError then
      begin
        Check(LInfo.SslVersion = AVersion, '协商协议与预期不符');
        Check(LInfo.CurrentCipher <> '', '没有协商套件');
        if AExpectKey then
          Check((LInfo.TmpKeyBits > 0) and (LInfo.TmpKeyType <> ''), '临时密钥信息缺失')
        else
          Check((LInfo.TmpKeyID = 0) and (LInfo.TmpKeyBits = 0), '无临时密钥却读取了字段');
      end;
    end;
    if AExpectKey then Check(KeysAcquired = 32, '未观察到预期的原生临时密钥引用');
    Writeln('INFO ', ASide, ' ', AVersion, ' acquired=', KeysAcquired, ' released=', KeysReleased);
  finally
    RestoreObservers;
    RaiseOnKey := False;
  end;
end;

procedure TestHandshake(const AVersion: Integer; const ANoKey, AInjectError: Boolean);
var
  LCliCtx, LSrvCtx: PSSL_CTX;
  LCli, LSrv: PSSL;
  LCliIn, LCliOut, LSrvIn, LSrvOut: PBIO;
  LCliDone, LSrvDone: Boolean;
  LVersion: string;
  LGroup: AnsiString;
  I: Integer;
begin
  LCliCtx := nil; LSrvCtx := nil; LCli := nil; LSrv := nil;
  try
    LCliCtx := TSSLTools.NewCTX(TLS_method());
    LSrvCtx := TSSLTools.NewCTX(TLS_method());
    Check(SSL_CTX_set_min_proto_version(LCliCtx, AVersion) = 1, '设置客户端协议失败');
    Check(SSL_CTX_set_max_proto_version(LCliCtx, AVersion) = 1, '设置客户端协议上限失败');
    Check(SSL_CTX_set_min_proto_version(LSrvCtx, AVersion) = 1, '设置服务端协议失败');
    Check(SSL_CTX_set_max_proto_version(LSrvCtx, AVersion) = 1, '设置服务端协议上限失败');
    // 固定传统密钥交换组，避免不同版本的默认混合组改变临时密钥可查询性。
    LGroup := 'X25519';
    Check(SSL_CTX_ctrl(LCliCtx, SSL_CTRL_SET_CURVES_LIST, 0, PAnsiChar(LGroup)) = 1,
      '设置客户端密钥交换组失败');
    Check(SSL_CTX_ctrl(LSrvCtx, SSL_CTRL_SET_CURVES_LIST, 0, PAnsiChar(LGroup)) = 1,
      '设置服务端密钥交换组失败');
    if ANoKey then
    begin
      Check(SSL_CTX_set_cipher_list(LCliCtx, 'AES128-GCM-SHA256') = 1, '设置无临时密钥套件失败');
      Check(SSL_CTX_set_cipher_list(LSrvCtx, 'AES128-GCM-SHA256') = 1, '设置服务端无临时密钥套件失败');
    end;
    TSSLTools.SetCertificateFile(LSrvCtx, ParamStr(4));
    TSSLTools.SetPrivateKeyFile(LSrvCtx, ParamStr(5));
    LCli := SSL_new(LCliCtx); LSrv := SSL_new(LSrvCtx);
    Check((LCli <> nil) and (LSrv <> nil), '创建 SSL 失败');
    LCliIn := BIO_new(BIO_s_mem()); LCliOut := BIO_new(BIO_s_mem());
    LSrvIn := BIO_new(BIO_s_mem()); LSrvOut := BIO_new(BIO_s_mem());
    Check((LCliIn <> nil) and (LCliOut <> nil) and (LSrvIn <> nil) and (LSrvOut <> nil), '创建 BIO 失败');
    SSL_set_bio(LCli, LCliIn, LCliOut);
    SSL_set_bio(LSrv, LSrvIn, LSrvOut);
    SSL_set_connect_state(LCli); SSL_set_accept_state(LSrv);
    LCliDone := False; LSrvDone := False;
    for I := 1 to 100 do
    begin
      Advance(LCli, LCliDone); Transfer(LCliOut, LSrvIn);
      Advance(LSrv, LSrvDone); Transfer(LSrvOut, LCliIn);
      if LCliDone and LSrvDone then Break;
    end;
    Check(LCliDone and LSrvDone, '握手未在限定步数内完成');
    if AVersion = TLS1_3_VERSION then LVersion := 'TLSv1.3' else LVersion := 'TLSv1.2';
    Inspect(LCli, LVersion, 'client', not ANoKey, AInjectError);
    // OpenSSL 1.1.1 的服务端查询可能没有临时对端密钥；以原生结果确定预期。
    LastKey := nil;
    I := SSL_get_peer_tmp_key(LSrv, @LastKey);
    if I = 1 then EVP_PKEY_free(LastKey);
    Inspect(LSrv, LVersion, 'server', I = 1, AInjectError and (I = 1));
  finally
    if LCli <> nil then SSL_free(LCli);
    if LSrv <> nil then SSL_free(LSrv);
    if LCliCtx <> nil then TSSLTools.FreeCTX(LCliCtx);
    if LSrvCtx <> nil then TSSLTools.FreeCTX(LSrvCtx);
  end;
end;

procedure TestManagedReset(const ASslInfo: Boolean);
var
  LInfo: TSslInfo;
  LCert: TCertInfo;
  LBefore, LAfter: UInt64;
  I: Integer;
begin
  LBefore := GetHeapStatus.TotalAllocated;
  for I := 1 to 128 do
  begin
    if ASslInfo then
    begin
      LInfo.SslVersion := StringOfChar('S', 32768);
      SetLength(LInfo.CipherList, 1);
      LInfo.CipherList[0] := StringOfChar('C', 32768);
      LInfo.CertInfo.PEM := StringOfChar('P', 32768);
      Check(not TSSLTools.GetSslInfo(nil, LInfo), 'nil SSL 应返回 False');
      Check((LInfo.SslVersion = '') and (Length(LInfo.CipherList) = 0) and
        (LInfo.CertInfo.PEM = ''), 'SSL 信息未重置');
    end else
    begin
      LCert.PEM := StringOfChar('P', 32768);
      SetLength(LCert.DER, 65536);
      SetLength(LCert.Subject, 1);
      LCert.Subject[0].Value := StringOfChar('D', 32768);
      Check(not TSSLTools.GetCertInfo(nil, LCert), 'nil 证书应返回 False');
      Check((LCert.PEM = '') and (Length(LCert.DER) = 0) and
        (Length(LCert.Subject) = 0), '证书信息未重置');
    end;
  end;
  LAfter := GetHeapStatus.TotalAllocated;
  Writeln('MANAGED allocated-before=', LBefore, ' allocated-after=', LAfter);
  Check(LAfter < LBefore + 1024 * 1024, '复用记录丢失了托管字段的引用');
end;

begin
  SetTextCodePage(Output, 65001);
  try
    Check(ParamCount >= 3, '需要 mode、ssl、crypto 参数');
    TSSLTools.LibSSL := ParamStr(2); TSSLTools.LibCRYPTO := ParamStr(3);
    TSSLTools.LoadSSL;
    try
      Writeln('OPENSSL ', IntToHex(OpenSSL_version_num(), 8));
      if ParamStr(1) = 'no-key' then TestBeforeHandshake(False)
      else if ParamStr(1) = 'failed-key' then TestBeforeHandshake(True)
      else if ParamStr(1) = 'tls12' then TestHandshake(TLS1_2_VERSION, False, False)
      else if ParamStr(1) = 'tls13' then TestHandshake(TLS1_3_VERSION, False, False)
      else if ParamStr(1) = 'rsa-no-key' then TestHandshake(TLS1_2_VERSION, True, False)
      else if ParamStr(1) = 'key-error' then TestHandshake(TLS1_3_VERSION, False, True)
      else if ParamStr(1) = 'ssl-reset' then TestManagedReset(True)
      else if ParamStr(1) = 'cert-reset' then TestManagedReset(False)
      else raise Exception.Create('未知测试');
    finally
      TSSLTools.UnloadSSL;
    end;
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL ', ParamStr(1), ' ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
