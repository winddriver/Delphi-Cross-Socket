{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSslSocket.MbedTls;

{$I zLib.inc}

{
  SSL通讯基本流程:
  1. 当连接建立时进行 SSL 握手, 收到数据时也要检查握手状态
  2. 发送数据: 用 SSL_write 写入原数据, BIO_read 读取加密后的数据进行发送
  3. 接收数据: 用 BIO_write 写入收到的数据, 用 SSL_read 读取解密后的数据

  传输层安全协议:
  https://zh.wikipedia.org/wiki/%E5%82%B3%E8%BC%B8%E5%B1%A4%E5%AE%89%E5%85%A8%E5%8D%94%E8%AD%B0
}

interface

uses
  SysUtils,
  Classes,

  Net.SocketAPI,
  Net.CrossProxy,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Base,
  Net.MbedTls,
  Net.MbedBIO;

const
  DEFAULT_CIPHERSUITES_SERVER: array [0..12] of Integer = (
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,

    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,

    MBEDTLS_TLS_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_RSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_RSA_WITH_AES_256_CBC_SHA,

    0);

  DEFAULT_CIPHERSUITES_CLIENT: array [0..18] of Integer = (
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,

    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,

    MBEDTLS_TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_DHE_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_DHE_RSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_DHE_RSA_WITH_AES_256_CBC_SHA,

    MBEDTLS_TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA,

    MBEDTLS_TLS_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_RSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_RSA_WITH_AES_256_CBC_SHA,

    MBEDTLS_TLS_RSA_WITH_3DES_EDE_CBC_SHA,

    0);

type
  EMbedTls = class(Exception)
  private
    FCode: Integer;
  public
    constructor Create(const ACode: Integer; const AMessage: string); reintroduce; overload;
    constructor Create(const ACode: Integer; const AFmt: string; const AArgs: array of const); reintroduce; overload;

    property Code: Integer read FCode;
  end;

  TCrossMbedTlsConnection = class(TCrossSslConnectionBase)
  private
    FSsl: TMbedtls_SSL_Context;
    FSslBIO, FAppBIO: PBIO;

    procedure _Lock; inline;
    procedure _Unlock; inline;

    function _SslHandshake: Boolean;
    procedure _SendBIOPendingData(const ACallback: TCrossConnectionCallback = nil);
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
    procedure SendProxyBytes(const ABytes: TBytes); override;
  public
    constructor Create(const AOwner: TCrossSocketBase;
      const AClientSocket: TSocket; const AConnectType: TConnectType;
      const AHost: string; const AConnectedCb: TCrossConnectionCallback); override;
    destructor Destroy; override;
  end;

  /// <remarks>
  ///   若要继承该类, 请重载 LogicXXX, 而不是 TriggerXXX
  /// </remarks>
  TCrossMbedTlsSocket = class(TCrossSslSocketBase)
  private const
    SSL_BUF_SIZE = 32768;
  private class threadvar
    FSslInBuf: array [0..SSL_BUF_SIZE-1] of Byte;
  private
    FSrvConf, FCliConf: TMbedtls_SSL_Config;
    FEntropy: TMbedtls_Entropy_Context;
    FCtrDrbg: TMbedtls_CTR_DRBG_Context ;
    FCert: TMbedtls_X509_CRT;
    FCACert: TMbedtls_X509_CRT;
    FCAData: TBytes;
    FPKey: TMbedtls_PK_Context;
    FCache: TMbedtls_SSL_Cache_Context;

    procedure _InitSslConf;
    procedure _FreeSslConf;

    function _MbedCert(const ACertBytes: TBytes): TBytes;
    procedure _UpdateCert;
  protected
    procedure ApplyVerifyPeer(const AValue: Boolean); override;
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: TCrossSocketBase;
      const AClientSocket: TSocket; const AConnectType: TConnectType;
      const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload; override;
    procedure SetCertificate(const ACertBytes: TBytes); overload; override;

    procedure AddCACertificate(const ABuf: Pointer;
      const ASize: Integer); overload; override;

    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer;
      const APassword: string); overload; override;
    procedure SetPrivateKey(const APKeyBytes: TBytes;
      const APassword: string); overload; override;
  end;

implementation

procedure ValidateCertificatePemBundle(const ABuf: Pointer;
  const ASize: Integer);
const
  PEM_BEGIN: AnsiString = '-----BEGIN CERTIFICATE-----';
  PEM_END: AnsiString = '-----END CERTIFICATE-----';
var
  LData: PByte;
  LSize, LPos, LCertCount: Integer;

  function _IsWhiteSpace(const AValue: Byte): Boolean; inline;
  begin
    Result := AValue in [9, 10, 13, 32];
  end;

  function _Matches(const AMarker: AnsiString): Boolean; inline;
  begin
    Result := (LPos + Length(AMarker) <= LSize)
      and CompareMem(PByte(NativeUInt(LData) + NativeUInt(LPos)),
        PAnsiChar(AMarker), Length(AMarker));
  end;

begin
  if (ABuf = nil) or (ASize <= 0) then
    raise EMbedTls.Create(MBEDTLS_ERR_X509_BAD_INPUT_DATA,
      'CA certificate data is empty.');

  LData := ABuf;
  LSize := ASize;
  while (LSize > 0) and ((LData[LSize - 1] = 0)
    or _IsWhiteSpace(LData[LSize - 1])) do
    Dec(LSize);
  if LSize = 0 then
    raise EMbedTls.Create(MBEDTLS_ERR_X509_BAD_INPUT_DATA,
      'CA certificate data is empty.');

  LPos := 0;
  LCertCount := 0;
  while LPos < LSize do
  begin
    while (LPos < LSize) and _IsWhiteSpace(LData[LPos]) do
      Inc(LPos);
    if LPos = LSize then Break;
    if not _Matches(PEM_BEGIN) then
      raise EMbedTls.Create(MBEDTLS_ERR_X509_BAD_INPUT_DATA,
        'CA certificate bundle contains invalid trailing data.');
    Inc(LPos, Length(PEM_BEGIN));

    while (LPos < LSize) and not _Matches(PEM_END) do
      Inc(LPos);
    if not _Matches(PEM_END) then
      raise EMbedTls.Create(MBEDTLS_ERR_X509_BAD_INPUT_DATA,
        'CA certificate bundle contains an incomplete certificate.');
    Inc(LPos, Length(PEM_END));
    Inc(LCertCount);
  end;

  if LCertCount = 0 then
    raise EMbedTls.Create(MBEDTLS_ERR_X509_BAD_INPUT_DATA,
      'CA certificate data contains no certificate.');
end;

{ EMbedTls }

constructor EMbedTls.Create(const ACode: Integer; const AMessage: string);
var
  LMessage: string;
begin
  FCode := ACode;

  if (AMessage <> '') then
    LMessage := AMessage + MbedErrToStr(ACode)
  else
    LMessage := MbedErrToStr(ACode);

  inherited Create(LMessage);
end;

constructor EMbedTls.Create(const ACode: Integer; const AFmt: string;
  const AArgs: array of const);
begin
  Create(ACode, Format(AFmt, AArgs));
end;

function MbedCheck(const ACode: Integer; const AErrMsg: string = ''): Integer;
begin
  Result := ACode;

  if (ACode >= 0) then Exit;

  case ACode of
    MBEDTLS_ERR_SSL_WANT_READ, MBEDTLS_ERR_SSL_WANT_WRITE:;
  else
    raise EMbedTls.Create(ACode, AErrMsg);
  end;
end;

{ TCrossMbedTlsConnection }

constructor TCrossMbedTlsConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectedCb: TCrossConnectionCallback);
var
  LHostAnsi: AnsiString;
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectedCb);

  if Ssl then
  begin
    TCrossMbedTlsSocket(Owner).LockTlsConfiguration;
    mbedtls_ssl_init(@FSsl);

    if (ConnectType = ctAccept) then
      MbedCheck(mbedtls_ssl_setup(@Fssl, @TCrossMbedTlsSocket(Owner).FSrvConf), 'mbedtls_ssl_setup Accept:')
    else
      MbedCheck(mbedtls_ssl_setup(@Fssl, @TCrossMbedTlsSocket(Owner).FCliConf), 'mbedtls_ssl_setup Connect:');

    FSslBIO := SSL_BIO_new(BIO_BIO);
    FAppBIO := SSL_BIO_new(BIO_BIO);
    BIO_make_bio_pair(FSslBIO, FAppBIO);

    mbedtls_ssl_set_bio(@FSsl, FSslBIO, BIO_net_send, BIO_net_recv, nil);

    if ConnectType = ctConnect then
    begin
      if (AHost = '') and TCrossMbedTlsSocket(Owner).VerifyPeer then
        raise ECrossSocket.Create(
          'A host name is required when peer verification is enabled.');
      if AHost <> '' then
      begin
        LHostAnsi := AnsiString(AHost);
        MbedCheck(mbedtls_ssl_set_hostname(@FSsl,
          MarshaledAString(LHostAnsi)), 'mbedtls_ssl_set_hostname:');
      end;
    end;
  end;
end;

procedure TCrossMbedTlsConnection.SendProxyBytes(const ABytes: TBytes);
var
  LBytes: TBytes;
begin
  if Length(ABytes) = 0 then
    Exit;

  LBytes := ABytes;
  inherited DirectSend(@LBytes[0], Length(LBytes),
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LBytes := nil;
    end);
end;

destructor TCrossMbedTlsConnection.Destroy;
begin
  if Ssl then
  begin
    mbedtls_ssl_free(@FSsl);
    BIO_free_all(FSslBIO);
    BIO_free_all(FAppBIO);
  end;

  inherited;
end;

procedure TCrossMbedTlsConnection._Lock;
begin
  // mbedtls 的多线程支持比 openssl 完善
  // 调用 mbedtls_threading_set_alt 设置了相应的线程同步函数之后不用再自己
  // _Lock _Unlock 了
//  System.TMonitor.Enter(Self);
end;

procedure TCrossMbedTlsConnection._SendBIOPendingData(
  const ACallback: TCrossConnectionCallback);
var
  LConnection: ICrossConnection;
  LRetCode: Integer;
  LBuffer: TBytesStream;

  procedure _Success;
  begin
    if (LBuffer <> nil) then
      FreeAndNil(LBuffer);
    if Assigned(ACallback) then
      ACallback(LConnection, True);
  end;

begin
  LConnection := Self;
  LBuffer := nil;

  {$region '将BIO中已加密的数据全部读到缓存中'}
  // 检查 BIO 中是否有数据
  LRetCode := BIO_ctrl_pending(FAppBIO);
  if (LRetCode <= 0) then
  begin
    _Success;
    Exit;
  end;

  LBuffer := TBytesStream.Create(nil);
  while (LRetCode > 0) do
  begin
    LBuffer.Size := LBuffer.Size + LRetCode;

    // 读取加密后的数据
    LRetCode := BIO_read(FAppBIO, PByte(LBuffer.Memory) + LBuffer.Position, LRetCode);
    if (LRetCode <= 0) then Break;

    LBuffer.Position := LBuffer.Position + LRetCode;

    // 检查 BIO 中是否还有数据
    LRetCode := BIO_ctrl_pending(FAppBIO);
  end;

  if (LBuffer.Memory = nil) or (LBuffer.Size <= 0) then
  begin
    _Success;
    Exit;
  end;
  {$endregion}

  {$region '发送缓存中已加密的数据'}
  inherited DirectSend(LBuffer.Memory, LBuffer.Size,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      FreeAndNil(LBuffer);
      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
  {$endregion}
end;

procedure TCrossMbedTlsConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LRetCode: Integer;
begin
  if Ssl then
  begin
    LRetCode := mbedtls_ssl_write(@FSsl, ABuffer, ACount);
    if (LRetCode <> ACount) then
    begin
      _Log('mbedtls_ssl_write, %d / %d', [LRetCode, ACount]);
    end;

    // 将待发送数据加密后发送
    if (MbedCheck(LRetCode, 'mbedtls_ssl_write DirectSend:') > 0) then
      _SendBIOPendingData(ACallback);
  end else
    inherited DirectSend(ABuffer, ACount, ACallback);
end;

function TCrossMbedTlsConnection._SslHandshake: Boolean;
begin
  // 开始握手
  Result := (MbedCheck(mbedtls_ssl_handshake(@FSsl), 'mbedtls_ssl_handshake _SslHandshake:') = 0);
  _SendBIOPendingData;
end;

procedure TCrossMbedTlsConnection._Unlock;
begin
//  System.TMonitor.Exit(Self);
end;

{ TCrossMbedTlsSocket }

constructor TCrossMbedTlsSocket.Create(const AIoThreads: Integer;
  const ASsl: Boolean);
begin
  inherited Create(AIoThreads, ASsl);

  if Ssl then
    _InitSslConf;
end;

destructor TCrossMbedTlsSocket.Destroy;
begin
  inherited Destroy;

  if Ssl then
    _FreeSslConf;
end;

function TCrossMbedTlsSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossMbedTlsConnection.Create(AOwner, AClientSocket, AConnectType,
    AHost, AConnectCb);
end;

procedure TCrossMbedTlsSocket.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
var
  LCode: Integer;
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    LCode := mbedtls_x509_crt_parse(@FCert, ACertBuf, ACertBufSize);
    if LCode <> 0 then
      raise EMbedTls.Create(LCode,
        'mbedtls_x509_crt_parse SetCertificate:');
    _UpdateCert;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossMbedTlsSocket.SetCertificate(const ACertBytes: TBytes);
var
  LCertBytes: TBytes;
begin
  if Ssl then
  begin
    LCertBytes := _MbedCert(ACertBytes);
    SetCertificate(Pointer(LCertBytes), Length(LCertBytes));
  end;
end;

procedure TCrossMbedTlsSocket.AddCACertificate(const ABuf: Pointer;
  const ASize: Integer);
var
  LNewData: TBytes;
  LNewCACert: TMbedtls_X509_CRT;
  LOldSize, LNewSize, LCode: Integer;
begin
  if not Ssl then Exit;
  ValidateCertificatePemBundle(ABuf, ASize);

  BeginTlsConfigUpdate;
  try
    LOldSize := Length(FCAData);
    while (LOldSize > 0) and (FCAData[LOldSize - 1] = 0) do
      Dec(LOldSize);
    LNewSize := ASize;
    while (LNewSize > 0)
      and (PByte(NativeUInt(ABuf) + NativeUInt(LNewSize - 1))^ = 0) do
      Dec(LNewSize);
    if LNewSize = 0 then
      raise EMbedTls.Create(MBEDTLS_ERR_X509_BAD_INPUT_DATA,
        'CA certificate data is empty.');

    SetLength(LNewData, LOldSize + LNewSize + 3);
    if LOldSize > 0 then
      Move(FCAData[0], LNewData[0], LOldSize);
    LNewData[LOldSize] := 13;
    LNewData[LOldSize + 1] := 10;
    Move(ABuf^, LNewData[LOldSize + 2], LNewSize);
    LNewData[High(LNewData)] := 0;

    FillChar(LNewCACert, SizeOf(LNewCACert), 0);
    mbedtls_x509_crt_init(@LNewCACert);
    try
      LCode := mbedtls_x509_crt_parse(@LNewCACert, Pointer(LNewData),
        Length(LNewData));
      if LCode <> 0 then
        raise EMbedTls.Create(LCode,
          'mbedtls_x509_crt_parse AddCACertificate:');

      mbedtls_x509_crt_free(@FCACert);
      FCACert := LNewCACert;
      FillChar(LNewCACert, SizeOf(LNewCACert), 0);
      FCAData := LNewData;

      mbedtls_ssl_conf_ca_chain(@FSrvConf, @FCACert, nil);
      mbedtls_ssl_conf_ca_chain(@FCliConf, @FCACert, nil);
      MarkCACertificateAdded;
    finally
      mbedtls_x509_crt_free(@LNewCACert);
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossMbedTlsSocket.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer; const APassword: string);
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    if (APKeyBuf = nil) or (APKeyBufSize <= 0) then
      raise EMbedTls.Create(MBEDTLS_ERR_PK_BAD_INPUT_DATA,
        'Private key data is empty.');
    if APassword <> '' then
      raise EMbedTls.Create(MBEDTLS_ERR_PK_FEATURE_UNAVAILABLE,
        'Encrypted private keys are disabled for bundled Mbed TLS 2.14.0.');

    MbedCheck(mbedtls_pk_parse_key(@FPKey, APKeyBuf, APKeyBufSize, nil, 0), 'mbedtls_pk_parse_key SetPrivateKey:');
    _UpdateCert;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossMbedTlsSocket.SetPrivateKey(const APKeyBytes: TBytes;
  const APassword: string);
var
  LPKeyBytes: TBytes;
begin
  if Ssl then
  begin
    LPKeyBytes := _MbedCert(APKeyBytes);
    try
      SetPrivateKey(Pointer(LPKeyBytes), Length(LPKeyBytes), APassword);
    finally
      if Length(LPKeyBytes) > 0 then
        FillChar(LPKeyBytes[0], Length(LPKeyBytes), 0);
    end;
  end;
end;

procedure TCrossMbedTlsSocket.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnection: TCrossMbedTlsConnection;
  LProxyData: TBytes;
begin
  LConnection := AConnection as TCrossMbedTlsConnection;

  if LConnection.ProxyUsesTlsTransport then
  begin
    _Log('HTTPS proxy TLS transport requires the OpenSSL backend.');
    LConnection.Close;
    Exit;
  end;

  if LConnection.ProxyNeedsHandshake then
  begin
    if LConnection.ProxyStart(LProxyData) then
      LConnection.SendProxyBytes(LProxyData);
    Exit;
  end;

  if Ssl then
  begin
    // 网络连接已建立, 等待握手
    LConnection.ConnectStatus := csHandshaking;

    if LConnection._SslHandshake then
    begin
      LConnection.ConnectStatus := csConnected;
      inherited TriggerConnected(LConnection);
    end;
  end else
    inherited TriggerConnected(LConnection);
end;

procedure TCrossMbedTlsSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnection: TCrossMbedTlsConnection;
  LRetCode: Integer;
  LProxyData, LRemain: TBytes;
  LProxyResult: TCrossProxyFeedResult;
begin
  LConnection := AConnection as TCrossMbedTlsConnection;

  if LConnection.ProxyNeedsHandshake then
  begin
    LProxyResult := LConnection.ProxyFeed(ABuf, ALen, LProxyData, LRemain);
    case LProxyResult of
      cpfrSendData:
        LConnection.SendProxyBytes(LProxyData);
      cpfrComplete:
        begin
          TriggerConnected(AConnection);
          if Length(LRemain) > 0 then
            TriggerReceived(AConnection, @LRemain[0], Length(LRemain));
        end;
      cpfrFailed:
        LConnection.Close;
    end;
    Exit;
  end;

  if Ssl then
  begin
    LConnection._Lock;
    try
      // 将收到的加密数据写入 BIO
      LRetCode := BIO_write(LConnection.FAppBIO, ABuf, ALen);
      if (LRetCode <= 0) then
      begin
        _Log('BIO_write, error: %d', [LRetCode]);
        LConnection.Close;
        Exit;
      end;

      if (LRetCode <> ALen) then
      begin
        _Log('BIO_write, %d / %d', [LRetCode, ALen]);
      end;

      // 握手
      if (LConnection.ConnectStatus = csHandshaking) then
      begin
        // 已完成握手才视为连接真正建立
        if LConnection._SslHandshake then
        begin
          LConnection.ConnectStatus := csConnected;
          inherited TriggerConnected(AConnection);
        end else
          Exit;
      end;

      while True do
      begin
        // 读取解密后的数据
        LRetCode := mbedtls_ssl_read(@LConnection.FSsl, @FSslInBuf, SSL_BUF_SIZE);

        if (LRetCode > 0) then
        begin
          inherited TriggerReceived(AConnection, @FSslInBuf, LRetCode);
        end else
        begin
          case LRetCode of
            MBEDTLS_ERR_SSL_WANT_READ, MBEDTLS_ERR_SSL_WANT_WRITE:;
          else
            _Log('mbedtls_ssl_read, error: %d', [LRetCode]);
            LConnection.Close;
          end;
          Break;
        end;
      end;
    finally
      LConnection._Unlock;
    end;
  end else
    inherited TriggerReceived(AConnection, ABuf, ALen);
end;

procedure TCrossMbedTlsSocket._FreeSslConf;
begin
  mbedtls_ssl_config_free(@FSrvConf);
  mbedtls_ssl_config_free(@FCliConf);

  mbedtls_x509_crt_free(@FCert);
  mbedtls_x509_crt_free(@FCACert);
  mbedtls_pk_free(@FPKey);

  mbedtls_ctr_drbg_free(@FCtrDrbg);
  mbedtls_entropy_free(@FEntropy);
	mbedtls_ssl_cache_free(@FCache);
end;

procedure TCrossMbedTlsSocket._InitSslConf;
begin
  mbedtls_x509_crt_init(@FCert);
  mbedtls_x509_crt_init(@FCACert);
  mbedtls_pk_init(@FPKey);
  mbedtls_ctr_drbg_init(@FCtrDrbg);
  mbedtls_entropy_init(@FEntropy);
  mbedtls_ssl_cache_init(@FCache);

  MbedCheck(mbedtls_ctr_drbg_seed(@FCtrDrbg, mbedtls_entropy_func, @FEntropy, nil, 0), 'mbedtls_ctr_drbg_seed:');

  {$region '服务端SSL配置'}
  mbedtls_ssl_config_init(@FSrvConf);
  MbedCheck(mbedtls_ssl_config_defaults(@FSrvConf,
    MBEDTLS_SSL_IS_SERVER,
    MBEDTLS_SSL_TRANSPORT_STREAM,
    MBEDTLS_SSL_PRESET_DEFAULT), 'mbedtls_ssl_config_defaults FSrvConf:');
  mbedtls_ssl_conf_rng(@FSrvConf, mbedtls_ctr_drbg_random, @FCtrDrbg);
  mbedtls_ssl_conf_authmode(@FSrvConf, MBEDTLS_SSL_VERIFY_NONE);
  mbedtls_ssl_conf_session_cache(@FSrvConf, @FCache, mbedtls_ssl_cache_get, mbedtls_ssl_cache_set); // 仅服务端有效
  mbedtls_ssl_conf_ciphersuites(@FSrvConf, PInteger(@DEFAULT_CIPHERSUITES_SERVER));
  mbedtls_ssl_conf_min_version(@FSrvConf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3); // TLS v1.2
  {$endregion}

  {$region '客户端SSL配置'}
  mbedtls_ssl_config_init(@FCliConf);
  MbedCheck(mbedtls_ssl_config_defaults(@FCliConf,
    MBEDTLS_SSL_IS_CLIENT,
    MBEDTLS_SSL_TRANSPORT_STREAM,
    MBEDTLS_SSL_PRESET_DEFAULT), 'mbedtls_ssl_config_defaults FCliConf:');
  mbedtls_ssl_conf_rng(@FCliConf, mbedtls_ctr_drbg_random, @FCtrDrbg);
  mbedtls_ssl_conf_authmode(@FCliConf, MBEDTLS_SSL_VERIFY_NONE);
  mbedtls_ssl_conf_ciphersuites(@FCliConf, PInteger(@DEFAULT_CIPHERSUITES_CLIENT));
  {$endregion}
end;

procedure TCrossMbedTlsSocket.ApplyVerifyPeer(const AValue: Boolean);
var
  LAuthMode: Integer;
begin
  if AValue then
    LAuthMode := MBEDTLS_SSL_VERIFY_REQUIRED
  else
    LAuthMode := MBEDTLS_SSL_VERIFY_NONE;

  mbedtls_ssl_conf_authmode(@FSrvConf, LAuthMode);
  mbedtls_ssl_conf_authmode(@FCliConf, LAuthMode);
end;

function TCrossMbedTlsSocket._MbedCert(const ACertBytes: TBytes): TBytes;
begin
  // PEM格式的证书需要以#0结尾
  if (ACertBytes = nil)
    or (ACertBytes[High(ACertBytes)] = 0) then
    Result := ACertBytes
  else
    Result := ACertBytes + [0];
end;

procedure TCrossMbedTlsSocket._UpdateCert;
begin
  // 尚未加载证书
  if (FCert.version = 0) then Exit;

  // 尚未加载私钥
  if (FPKey.pk_info = nil) then Exit;

  MbedCheck(mbedtls_ssl_conf_own_cert(@FSrvConf, @FCert, @FPKey), 'mbedtls_ssl_conf_own_cert:');
  MbedCheck(mbedtls_ssl_conf_own_cert(@FCliConf, @FCert, @FPKey), 'mbedtls_ssl_conf_own_cert client:');
end;

end.
