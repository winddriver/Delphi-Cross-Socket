program TlsCipherSuitesTests;

{$I ..\..\..\..\zLib.inc}

uses
  SysUtils,
  Classes
  {$IFDEF FPC}
  ,DTF.RTL in '..\..\..\..\DelphiToFPC\DTF.RTL.pas'
  ,DTF.Types in '..\..\..\..\DelphiToFPC\DTF.Types.pas'
  ,DTF.Consts in '..\..\..\..\DelphiToFPC\DTF.Consts.pas'
  ,DTF.Character in '..\..\..\..\DelphiToFPC\DTF.Character.pas'
  ,DTF.Diagnostics in '..\..\..\..\DelphiToFPC\DTF.Diagnostics.pas'
  ,DTF.Generics in '..\..\..\..\DelphiToFPC\DTF.Generics.pas'
  {$ENDIF}
  ,Utils.Logger in '..\..\..\..\Utils\Utils.Logger.pas'
  ,Utils.StrUtils in '..\..\..\..\Utils\Utils.StrUtils.pas'
  ,Utils.SyncObjs in '..\..\..\..\Utils\Utils.SyncObjs.pas'
  ,Utils.Rtti in '..\..\..\..\Utils\Utils.Rtti.pas'
  ,Utils.DateTime in '..\..\..\..\Utils\Utils.DateTime.pas'
  ,Utils.AnonymousThread in '..\..\..\..\Utils\Utils.AnonymousThread.pas'
  ,Utils.Utils in '..\..\..\..\Utils\Utils.Utils.pas'
  ,Utils.IOUtils in '..\..\..\..\Utils\Utils.IOUtils.pas'
  ,Net.Winsock2 in '..\..\..\Net.Winsock2.pas'
  ,Net.Wship6 in '..\..\..\Net.Wship6.pas'
  ,Net.SocketAPI in '..\..\..\Net.SocketAPI.pas'
  ,Net.CrossSocket.Base in '..\..\..\Net.CrossSocket.Base.pas'
  ,Net.CrossSocket.Iocp in '..\..\..\Net.CrossSocket.Iocp.pas'
  ,Net.CrossSocket in '..\..\..\Net.CrossSocket.pas'
  ,Net.CrossSslSocket.Types in '..\..\..\Net.CrossSslSocket.Types.pas'
  ,Net.CrossSslSocket.Base in '..\..\..\Net.CrossSslSocket.Base.pas'
  {$IFDEF __MBED_TLS__}
  ,Net.MbedTls in '..\..\..\Net.MbedTls.pas'
  ,Net.MbedBIO in '..\..\..\Net.MbedBIO.pas'
  ,Net.CrossSslSocket.MbedTls in '..\..\..\Net.CrossSslSocket.MbedTls.pas'
  {$ELSE}
  ,Net.OpenSSL in '..\..\..\Net.OpenSSL.pas'
  ,Net.CrossSslSocket.OpenSSL in '..\..\..\Net.CrossSslSocket.OpenSSL.pas'
  ,TlsCipherHandshakeTests in 'TlsCipherHandshakeTests.pas'
  {$ENDIF}
  ,Net.CrossSslSocket in '..\..\..\Net.CrossSslSocket.pas'
  ;

type
  TTestProc = reference to procedure;

  TTestSslSocket = class(TCrossSslSocket)
  public
    procedure FreezeConfiguration;
    procedure CreateSslConnection(const AConnectType: TConnectType);
  end;

  TUnsupportedSslSocket = class(TCrossSslSocketBase)
  public
    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); override;
    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer;
      const APassword: string); override;
  end;

procedure TTestSslSocket.FreezeConfiguration;
begin
  LockTlsConfiguration;
end;

procedure TTestSslSocket.CreateSslConnection(const AConnectType: TConnectType);
var
  LConnection: ICrossConnection;
begin
  LConnection := CreateConnection(Self, INVALID_SOCKET, AConnectType, 'localhost', nil);
end;

procedure TUnsupportedSslSocket.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
begin
end;

procedure TUnsupportedSslSocket.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer; const APassword: string);
begin
end;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure ExpectError(const AClass: ExceptClass; const AProc: TTestProc;
  const AMessage: string);
begin
  try
    AProc();
  except
    on E: Exception do
    begin
      if not E.InheritsFrom(AClass) then raise;
      Exit;
    end;
  end;
  raise Exception.Create(AMessage);
end;

procedure TestDisabled;
var
  LApi: ICrossSslSocket;
begin
  LApi := TTestSslSocket.Create(0, False);
  LApi.SetTls12CipherSuites('');
  LApi.SetTls12CipherSuites('UNKNOWN');
  LApi.SetTls13CipherSuites('');
  LApi.SetTls13CipherSuites('UNKNOWN');
  LApi.SetMinTlsVersion(tmvTls12);
  LApi.SetMinTlsVersion(tmvTls13);
  LApi := nil;
end;

procedure TestDefaultBackendRejection;
var
  LApi: ICrossSslSocket;
begin
  // 不依赖第三方 mbedTLS 对象文件，也验证未覆盖新方法的派生类可实例化。
  LApi := TUnsupportedSslSocket.Create(0, True);
  LApi.SetTls12CipherSuites('');
  LApi.SetTls13CipherSuites('');
  ExpectError(ECrossSocket,
    procedure begin LApi.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES); end,
    '基类未明确拒绝 TLS 1.2 配置');
  ExpectError(ECrossSocket,
    procedure begin LApi.SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES); end,
    '基类未明确拒绝 TLS 1.3 配置');
  // 未实现该配置的后端不能承诺最低版本已生效。
  ExpectError(ECrossSocket,
    procedure begin LApi.SetMinTlsVersion(tmvTls12); end,
    '基类静默接受了未实现的 TLS 1.2 最低版本');
  ExpectError(ECrossSocket,
    procedure begin LApi.SetMinTlsVersion(tmvTls13); end,
    '基类未明确拒绝 TLS 1.3 最低版本');
  LApi := nil;
end;

{$IFNDEF __MBED_TLS__}
function CipherText(const AItems: TArray<string>;
  const ATls13: Boolean): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(AItems) - 1 do
    if (Copy(AItems[I], 1, 4) = 'TLS_') = ATls13 then
    begin
      if Result <> '' then Result := Result + ':';
      Result := Result + AItems[I];
    end;
end;

procedure TestDefaults;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LActual: TArray<string>;
  LReference: PSSL_CTX;
  LMinVersion, LMaxVersion, LExpectedMaxVersion: Integer;
begin
  LReference := TSSLTools.NewCTX(TLS_method());
  Check(LReference <> nil, '无法创建协议范围参考上下文');
  try
    LExpectedMaxVersion := SSL_CTX_get_max_proto_version(LReference);
  finally
    TSSLTools.FreeCTX(LReference);
  end;
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    CrossOpenSslSelfTest_GetProtocolVersions(LObj, LMinVersion, LMaxVersion);
    Check(LMinVersion = TLS1_2_VERSION, '最低协议版本不是 TLS 1.2');
    Check(LMaxVersion = LExpectedMaxVersion, '组件覆盖了运行库的默认协议上限');
    // 尚未调用 setter，检查构造函数确实应用默认常量。
    LActual := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LActual, False) = DEFAULT_TLS12_CIPHER_SUITES,
      '初始化的 TLS 1.2 默认名单或顺序不正确');
    Check(CipherText(LActual, True) = DEFAULT_TLS13_CIPHER_SUITES,
      '初始化的 TLS 1.3 默认名单或顺序不正确');
    Check(Length(LActual) = 9, '默认名单不是 TLS 1.2 六项加 TLS 1.3 三项');

    LApi.SetTls12CipherSuites('ECDHE-RSA-AES128-GCM-SHA256');
    LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256');
    LApi.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
    LApi.SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
    LActual := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LActual, False) = DEFAULT_TLS12_CIPHER_SUITES,
      '未能显式恢复 TLS 1.2 默认名单');
    Check(CipherText(LActual, True) = DEFAULT_TLS13_CIPHER_SUITES,
      '未能显式恢复 TLS 1.3 默认名单');
  finally
    LApi := nil;
  end;
end;

procedure TestOpenSsl;
const
  CIPHER = 'ECDHE-RSA-AES128-GCM-SHA256';
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LBefore, LAfter: TArray<string>;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LBefore := CrossOpenSslSelfTest_GetCipherList(LObj);
    LApi.SetTls12CipherSuites(CIPHER);
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, 'TLS 1.2 列表未生效');
    Check(CipherText(LBefore, True) = CipherText(LAfter, True),
      'TLS 1.3 列表发生变化');

    LApi.SetTls12CipherSuites('');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, '空字符串错误地重置了配置');

    LApi.SetTls12CipherSuites(CIPHER + ':CROSS_SOCKET_UNKNOWN_CIPHER');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, '混合规则未遵循 OpenSSL 语义');

    LApi.SetTls12CipherSuites(CIPHER);
    Check(ERR_get_error() = 0, '成功路径遗留 OpenSSL 错误');

    // 第一种顺序：先配 TLS 1.2，再配 TLS 1.3。
    LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, 'TLS 1.3 setter 改动了 TLS 1.2 名单');
    Check(CipherText(LAfter, True) =
      'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384', 'TLS 1.3 名单或顺序错误');

    LObj.FreezeConfiguration;
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites('HIGH'); end,
      '冻结后仍能修改配置');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256'); end,
      '冻结后仍能修改 TLS 1.3');
    LApi.SetTls12CipherSuites('');
    LApi.SetTls13CipherSuites('');
  finally
    // 引用计数负责销毁，不能再对 LObj 调 Free。
    LApi := nil;
  end;

  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LApi.SetTls12CipherSuites(CIPHER);
    ExpectError(ESslContextInvalid,
      procedure begin LApi.SetTls12CipherSuites('CROSS_SOCKET_UNKNOWN_CIPHER'); end,
      '无匹配套件未使配置失效');
    Check(ERR_get_error() = 0, '失败路径遗留 OpenSSL 错误');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites(CIPHER); end,
      '失效对象错误地接受了后续更新');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256'); end,
      'TLS 1.2 失败后仍接受 TLS 1.3 更新');
    ExpectError(ECrossSocket,
      procedure begin LObj.FreezeConfiguration; end,
      '失效对象仍可进入创建 SSL 连接前的配置检查');
    ExpectError(ECrossSocket,
      procedure begin LObj.CreateSslConnection(ctConnect); end,
      'TLS 1.2 失效后仍能构造客户端 SSL 连接');
    ExpectError(ECrossSocket,
      procedure begin LObj.CreateSslConnection(ctAccept); end,
      'TLS 1.2 失效后仍能构造服务端 SSL 连接');
  finally
    LApi := nil;
  end;
end;

procedure TestTls13;
const
  CIPHER12 = 'ECDHE-RSA-AES128-GCM-SHA256';
  CIPHER13 = 'TLS_AES_128_GCM_SHA256';
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LBefore, LAfter: TArray<string>;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LBefore := CrossOpenSslSelfTest_GetCipherList(LObj);
    LApi.SetTls13CipherSuites(CIPHER13);
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, True) = CIPHER13, 'TLS 1.3 单项配置未生效');
    Check(CipherText(LBefore, False) = CipherText(LAfter, False),
      'TLS 1.3 setter 修改了 TLS 1.2 名单');
    LApi.SetTls13CipherSuites('');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, True) = CIPHER13, 'TLS 1.3 空串改变了名单');

    // 第二种顺序：先配 TLS 1.3，再配 TLS 1.2，最终名单相同。
    LApi.SetTls13CipherSuites(CIPHER13 + ':TLS_AES_256_GCM_SHA384');
    // 必须紧跟 setter 检查，读取名单的测试入口也会清理错误队列。
    Check(ERR_get_error() = 0, 'TLS 1.3 成功路径遗留错误');
    LApi.SetTls12CipherSuites(CIPHER12);
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER12, '反向配置顺序的 TLS 1.2 名单错误');
    Check(CipherText(LAfter, True) = CIPHER13 + ':TLS_AES_256_GCM_SHA384',
      '反向配置顺序的 TLS 1.3 名单错误');
  finally
    LApi := nil;
  end;

  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LApi.SetTls13CipherSuites(CIPHER13);
    ExpectError(ESslContextInvalid,
      procedure begin LApi.SetTls13CipherSuites('CROSS_SOCKET_UNKNOWN_CIPHER'); end,
      'TLS 1.3 无效名称未报告配置失效');
    Check(ERR_get_error() = 0, 'TLS 1.3 失败路径遗留错误');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites(CIPHER13); end,
      '失效对象仍接受 TLS 1.3 更新');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites(CIPHER12); end,
      'TLS 1.3 失败后仍接受 TLS 1.2 更新');
    ExpectError(ECrossSocket,
      procedure begin LObj.FreezeConfiguration; end,
      'TLS 1.3 配置失败后仍能通过连接门禁');
    ExpectError(ECrossSocket,
      procedure begin LObj.CreateSslConnection(ctConnect); end,
      'TLS 1.3 失效后仍能构造客户端 SSL 连接');
    ExpectError(ECrossSocket,
      procedure begin LObj.CreateSslConnection(ctAccept); end,
      'TLS 1.3 失效后仍能构造服务端 SSL 连接');
  finally
    LApi := nil;
  end;
end;

procedure TestTls13MixedNames;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    // 1.1.1 拒绝未知名称，3.x 可忽略；包装层保留对应原生版本语义。
    if TSSLTools.SSLVersion < $30000000 then
      ExpectError(ESslContextInvalid,
        procedure
        begin
          LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256:CROSS_SOCKET_UNKNOWN');
        end, 'OpenSSL 1.1.1 的混合名称错误未向上传递')
    else
    begin
      LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256:CROSS_SOCKET_UNKNOWN');
      Check(CipherText(CrossOpenSslSelfTest_GetCipherList(LObj), True) =
        'TLS_AES_128_GCM_SHA256', 'OpenSSL 3.x 的混合名称未按原生语义处理');
    end;
  finally
    LApi := nil;
  end;
end;

procedure TestMinTlsVersion;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LBefore, LAfter: TArray<string>;
  LMinVersion, LMaxVersion, LMaxBefore: Integer;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    CrossOpenSslSelfTest_GetProtocolVersions(LObj, LMinVersion, LMaxBefore);
    Check(LMinVersion = TLS1_2_VERSION, '默认最低版本不是 TLS 1.2');
    LBefore := CrossOpenSslSelfTest_GetCipherList(LObj);

    LApi.SetMinTlsVersion(tmvTls13);
    CrossOpenSslSelfTest_GetProtocolVersions(LObj, LMinVersion, LMaxVersion);
    Check(LMinVersion = TLS1_3_VERSION, 'TLS 1.3 最低版本未生效');
    Check(LMaxVersion = LMaxBefore, '设置最低版本改变了协议上限');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CipherText(LBefore, False),
      '设置最低版本改变了 TLS 1.2 名单');
    Check(CipherText(LAfter, True) = CipherText(LBefore, True),
      '设置最低版本改变了 TLS 1.3 名单');
    Check(ERR_get_error() = 0, '最低版本成功路径遗留错误');

    // 可恢复默认下限。
    LApi.SetMinTlsVersion(tmvTls12);
    CrossOpenSslSelfTest_GetProtocolVersions(LObj, LMinVersion, LMaxVersion);
    Check(LMinVersion = TLS1_2_VERSION, '无法恢复 TLS 1.2 最低版本');

    // 首个连接后配置锁定。
    LObj.FreezeConfiguration;
    ExpectError(ECrossSocket,
      procedure begin LApi.SetMinTlsVersion(tmvTls13); end,
      '配置锁定后仍可修改最低版本');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetMinTlsVersion(tmvTls12); end,
      '配置锁定后仍可恢复最低版本');
  finally
    LApi := nil;
  end;
end;

procedure TestSecurityLevel;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    // 仅测试全局级别变化，绝不在该实例发起真实网络连接。
    LApi.SetTls12CipherSuites('ECDHE-RSA-AES128-GCM-SHA256:@SECLEVEL=3');
    Check(CrossOpenSslSelfTest_GetSecurityLevel(LObj) = 3,
      'TLS 1.2 规则没有更新安全级别');
    LApi.SetTls13CipherSuites('TLS_AES_256_GCM_SHA384');
    Check(CrossOpenSslSelfTest_GetSecurityLevel(LObj) = 3,
      'TLS 1.3 setter 错误地重置了安全级别');
  finally
    LApi := nil;
  end;
end;

procedure TestErrorQueue;
var
  LApi: ICrossSslSocket;
  LContext: PSSL_CTX;
begin
  LApi := TTestSslSocket.Create(0, True);
  try
    LContext := TSSLTools.NewCTX(TLS_method());
    Check(LContext <> nil, '无法建立错误队列测试上下文');
    try
      Check(SSL_CTX_set_cipher_list(LContext, 'CROSS_SOCKET_UNKNOWN') = 0,
        '无法生成测试错误');
      Check(ERR_peek_last_error() <> 0, '预置错误队列为空');
      LApi.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
      Check(ERR_get_error() = 0, 'TLS 1.2 未清理历史错误');
      Check(SSL_CTX_set_ciphersuites(LContext, 'CROSS_SOCKET_UNKNOWN') = 0,
        '无法生成 TLS 1.3 测试错误');
      Check(ERR_peek_last_error() <> 0, 'TLS 1.3 预置错误队列为空');
      LApi.SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
      Check(ERR_get_error() = 0, 'TLS 1.3 未清理历史错误');
    finally
      TSSLTools.FreeCTX(LContext);
    end;
  finally
    LApi := nil;
  end;
end;

type
  TNewContext = function(AMethod: PSSL_METHOD): PSSL_CTX; cdecl;
  TFreeContext = procedure(AContext: PSSL_CTX); cdecl;
  TSetCiphers = function(AContext: PSSL_CTX; AValue: MarshaledAString): Integer; cdecl;
  TContextCtrl = function(AContext: PSSL_CTX; ACmd: Integer;
    ALArg: NativeInt; APArg: Pointer): NativeInt; cdecl;

var
  OriginalNewContext: TNewContext;
  OriginalFreeContext: TFreeContext;
  OriginalContextCtrl: TContextCtrl;
  ContextsAllocated, ContextsFreed: Integer;

function CountNewContext(AMethod: PSSL_METHOD): PSSL_CTX; cdecl;
begin
  Result := OriginalNewContext(AMethod);
  if Result <> nil then Inc(ContextsAllocated);
end;

procedure CountFreeContext(AContext: PSSL_CTX); cdecl;
begin
  if AContext <> nil then Inc(ContextsFreed);
  OriginalFreeContext(AContext);
end;

function RejectCiphers(AContext: PSSL_CTX; AValue: MarshaledAString): Integer; cdecl;
begin
  Result := 0;
end;

procedure TestInitializationFailure(const ATls13: Boolean);
var
  LOriginalSet: TSetCiphers;
  LApi: ICrossSslSocket;
begin
  // 仅在串行、无 IO 连接的本进程测试中暂换动态函数指针，finally 必须恢复。
  OriginalNewContext := SSL_CTX_new;
  OriginalFreeContext := SSL_CTX_free;
  if ATls13 then LOriginalSet := SSL_CTX_set_ciphersuites
  else LOriginalSet := SSL_CTX_set_cipher_list;
  ContextsAllocated := 0;
  ContextsFreed := 0;
  SSL_CTX_new := CountNewContext;
  SSL_CTX_free := CountFreeContext;
  if ATls13 then SSL_CTX_set_ciphersuites := RejectCiphers
  else SSL_CTX_set_cipher_list := RejectCiphers;
  try
    ExpectError(ESslContextInvalid,
      procedure begin LApi := TTestSslSocket.Create(0, True); end,
      '默认套件失败却仍返回 socket');
    Check((ContextsAllocated = 1) and (ContextsFreed = 1),
      '默认套件初始化失败泄漏上下文');
    Check(ERR_get_error() = 0, '初始化失败遗留错误队列');
  finally
    if ATls13 then SSL_CTX_set_ciphersuites := LOriginalSet
    else SSL_CTX_set_cipher_list := LOriginalSet;
    SSL_CTX_new := OriginalNewContext;
    SSL_CTX_free := OriginalFreeContext;
    LApi := nil;
  end;
  // 确认构造失败后，正常新实例仍能建立、释放。
  LApi := TTestSslSocket.Create(0, True);
  LApi := nil;
end;

function RejectMinimumVersion(AContext: PSSL_CTX; ACmd: Integer;
  ALArg: NativeInt; APArg: Pointer): NativeInt; cdecl;
begin
  if ACmd = SSL_CTRL_SET_MIN_PROTO_VERSION then Exit(0);
  Result := OriginalContextCtrl(AContext, ACmd, ALArg, APArg);
end;

procedure TestMinimumVersionFailure;
var
  LApi: ICrossSslSocket;
begin
  OriginalContextCtrl := SSL_CTX_ctrl;
  OriginalNewContext := SSL_CTX_new;
  OriginalFreeContext := SSL_CTX_free;
  ContextsAllocated := 0;
  ContextsFreed := 0;
  SSL_CTX_new := CountNewContext;
  SSL_CTX_free := CountFreeContext;
  SSL_CTX_ctrl := RejectMinimumVersion;
  try
    ExpectError(ESsl,
      procedure begin LApi := TTestSslSocket.Create(0, True); end,
      '最低版本设置失败却仍返回 socket');
    Check((ContextsAllocated = 1) and (ContextsFreed = 1),
      '最低版本设置失败泄漏上下文');
  finally
    SSL_CTX_ctrl := OriginalContextCtrl;
    SSL_CTX_new := OriginalNewContext;
    SSL_CTX_free := OriginalFreeContext;
    LApi := nil;
  end;
end;

function IgnoreMinimumVersion(AContext: PSSL_CTX; ACmd: Integer;
  ALArg: NativeInt; APArg: Pointer): NativeInt; cdecl;
begin
  // 报告成功但不生效，验证 setter 的回读确认。
  if ACmd = SSL_CTRL_SET_MIN_PROTO_VERSION then Exit(1);
  Result := OriginalContextCtrl(AContext, ACmd, ALArg, APArg);
end;

procedure TestMinTlsVersionSetterFailure(const ASilent: Boolean);
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
begin
  // 构造完成后再替换，只影响 setter 本身。
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  OriginalContextCtrl := SSL_CTX_ctrl;
  if ASilent then SSL_CTX_ctrl := IgnoreMinimumVersion
  else SSL_CTX_ctrl := RejectMinimumVersion;
  try
    ExpectError(ESslContextInvalid,
      procedure begin LApi.SetMinTlsVersion(tmvTls13); end,
      '最低版本设置失败或未生效却未报错');
  finally
    SSL_CTX_ctrl := OriginalContextCtrl;
  end;
  try
    Check(ERR_get_error() = 0, '最低版本失败路径遗留错误');
    // 失败后整个 TLS 配置失效。
    ExpectError(ECrossSocket,
      procedure begin LApi.SetMinTlsVersion(tmvTls12); end,
      '最低版本失败后配置未失效');
    ExpectError(ECrossSocket,
      procedure begin LObj.CreateSslConnection(ctConnect); end,
      '最低版本失效后仍能构造客户端 SSL 连接');
    ExpectError(ECrossSocket,
      procedure begin LObj.CreateSslConnection(ctAccept); end,
      '最低版本失效后仍能构造服务端 SSL 连接');
  finally
    LApi := nil;
  end;
end;

procedure TestExistingSelfTests;
var
  LError: string;
begin
  if not CrossOpenSslSelfTest_PendingCallbackExceptionDoesNotStall(LError) then
    raise Exception.Create(LError);
  if not CrossOpenSslSelfTest_HandshakeSendFailureDoesNotPromote(LError) then
    raise Exception.Create(LError);
end;

procedure TestRsaKeyGeneration;
var
  LContext: PEVP_PKEY_CTX;
  LKey: PEVP_PKEY;
begin
  LContext := EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nil);
  Check(LContext <> nil, '无法创建 RSA 密钥生成上下文');
  LKey := nil;
  try
    Check(EVP_PKEY_keygen_init(LContext) > 0, 'RSA 密钥生成初始化失败');
    Check(EVP_PKEY_CTX_set_rsa_keygen_bits(LContext, 2048) > 0,
      'RSA 密钥位数设置失败');
    Check(EVP_PKEY_keygen(LContext, @LKey) > 0, 'RSA 密钥生成失败');
    Check(EVP_PKEY_get_bits(LKey) = 2048, 'RSA 实际密钥位数不正确');
  finally
    if LKey <> nil then EVP_PKEY_free(LKey);
    EVP_PKEY_CTX_free(LContext);
  end;
end;
{$ELSE}
procedure TestUnsupportedBackend;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LClientVersion, LServerVersion: Integer;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    CrossMbedTlsSelfTest_GetMinProtocolVersions(LObj, LClientVersion, LServerVersion);
    Check((LClientVersion = $0303) and (LServerVersion = $0303),
      'mbedTLS 客户端或服务端默认最低版本不是 TLS 1.2');
    LApi.SetTls12CipherSuites('');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites('HIGH'); end,
      'mbedTLS 未明确报告不支持');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256'); end,
      'mbedTLS 未明确拒绝 TLS 1.3 配置');
    LApi.SetTls12CipherSuites('');
    LApi.SetTls13CipherSuites('');
    LApi.SetMinTlsVersion(tmvTls12);
    CrossMbedTlsSelfTest_GetMinProtocolVersions(LObj, LClientVersion, LServerVersion);
    Check((LClientVersion = $0303) and (LServerVersion = $0303),
      'mbedTLS 客户端或服务端未应用 TLS 1.2 下限');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetMinTlsVersion(tmvTls13); end,
      'mbedTLS 未明确拒绝 TLS 1.3 最低版本');
    // 不支持的版本不会破坏已有 TLS 1.2 配置。
    LApi.SetMinTlsVersion(tmvTls12);
    LObj.FreezeConfiguration;
    ExpectError(ECrossSocket,
      procedure begin LApi.SetMinTlsVersion(tmvTls12); end,
      'mbedTLS 配置锁定后仍接受最低版本配置');
  finally
    LApi := nil;
  end;
end;
{$ENDIF}

begin
  try
    {$IFNDEF __MBED_TLS__}
    if GetEnvironmentVariable('CROSS_SOCKET_TEST_LIBSSL') <> '' then
      TSSLTools.LibSSL := GetEnvironmentVariable('CROSS_SOCKET_TEST_LIBSSL');
    if GetEnvironmentVariable('CROSS_SOCKET_TEST_LIBCRYPTO') <> '' then
      TSSLTools.LibCRYPTO := GetEnvironmentVariable('CROSS_SOCKET_TEST_LIBCRYPTO');
    TSSLTools.LoadSSL;
    try
      Writeln('OPENSSL ', IntToHex(OpenSSL_version_num(), 8));
      if (ParamStr(1) = '--client') or (ParamStr(1) = '--server') then
      begin
        RunCipherHandshake;
        Exit;
      end;
    {$ENDIF}
    TestDisabled;
    TestDefaultBackendRejection;
    {$IFNDEF __MBED_TLS__}
    TestDefaults;
    TestOpenSsl;
    TestTls13;
    TestTls13MixedNames;
    TestMinTlsVersion;
    TestSecurityLevel;
    TestErrorQueue;
    TestInitializationFailure(False);
    TestInitializationFailure(True);
    TestMinimumVersionFailure;
    TestMinTlsVersionSetterFailure(False);
    TestMinTlsVersionSetterFailure(True);
    TestExistingSelfTests;
    TestRsaKeyGeneration;
    {$ELSE}
    TestUnsupportedBackend;
    {$ENDIF}
    Writeln('TlsCipherSuitesTests: PASS');
    {$IFNDEF __MBED_TLS__}
    finally
      TSSLTools.UnloadSSL;
    end;
    {$ENDIF}
  except
    on E: Exception do
    begin
      Writeln('TlsCipherSuitesTests: FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
