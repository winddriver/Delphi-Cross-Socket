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
  System.SysUtils,
  System.Classes,
  System.IOUtils,
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

  TCrossMbedTlsConnection = class(TCrossConnection)
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
  public
    constructor Create(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType); override;
    destructor Destroy; override;
  end;

  /// <remarks>
  ///   若要继承该类, 请重载 LogicXXX, 而不是 TriggerXXX
  /// </remarks>
  TCrossMbedTlsSocket = class(TCrossSocket, ICrossSslSocket)
  private const
    SSL_BUF_SIZE = 32768;
  private class threadvar
    FSslInBuf: array [0..SSL_BUF_SIZE-1] of Byte;
  private
    FSrvConf, FCliConf: TMbedtls_SSL_Config;
    FEntropy: TMbedtls_Entropy_Context;
    FCtrDrbg: TMbedtls_CTR_DRBG_Context ;
    FCert: TMbedtls_X509_CRT;
    FPKey: TMbedtls_PK_Context;
    FCache: TMbedtls_SSL_Cache_Context;

    procedure _InitSslConf;
    procedure _FreeSslConf;

    function _MbedCert(const ACertBytes: TBytes): TBytes;
    procedure _UpdateCert;
  protected
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType): ICrossConnection; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload;
    procedure SetCertificate(const ACertStr: string); overload;
    procedure SetCertificateFile(const ACertFile: string);

    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer); overload;
    procedure SetPrivateKey(const APKeyStr: string); overload;
    procedure SetPrivateKeyFile(const APKeyFile: string);
  end;

implementation

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

constructor TCrossMbedTlsConnection.Create(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType);
begin
  inherited;

  mbedtls_ssl_init(@FSsl);

  if (ConnectType = ctAccept) then
    MbedCheck(mbedtls_ssl_setup(@Fssl, @TCrossMbedTlsSocket(Owner).FSrvConf), 'mbedtls_ssl_setup Accept:')
  else
    MbedCheck(mbedtls_ssl_setup(@Fssl, @TCrossMbedTlsSocket(Owner).FCliConf), 'mbedtls_ssl_setup Connect:');

  FSslBIO := SSL_BIO_new(BIO_BIO);
  FAppBIO := SSL_BIO_new(BIO_BIO);
  BIO_make_bio_pair(FSslBIO, FAppBIO);

  mbedtls_ssl_set_bio(@FSsl, FSslBIO, BIO_net_send, BIO_net_recv, nil);
end;

destructor TCrossMbedTlsConnection.Destroy;
begin
  mbedtls_ssl_free(@FSsl);
  BIO_free_all(FSslBIO);
  BIO_free_all(FAppBIO);

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
  LRetCode := mbedtls_ssl_write(@FSsl, ABuffer, ACount);
  if (LRetCode <> ACount) then
  begin
    _Log('mbedtls_ssl_write, %d / %d', [LRetCode, ACount]);
  end;

  // 将待发送数据加密后发送
  if (MbedCheck(LRetCode, 'mbedtls_ssl_write DirectSend:') > 0) then
    _SendBIOPendingData(ACallback);
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

constructor TCrossMbedTlsSocket.Create(AIoThreads: Integer);
begin
  inherited;

  _InitSslConf;
end;

destructor TCrossMbedTlsSocket.Destroy;
begin
  inherited;

  _FreeSslConf;
end;

function TCrossMbedTlsSocket.CreateConnection(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType): ICrossConnection;
begin
  Result := TCrossMbedTlsConnection.Create(AOwner, AClientSocket, AConnectType);
end;

procedure TCrossMbedTlsSocket.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
begin
  MbedCheck(mbedtls_x509_crt_parse(@FCert, ACertBuf, ACertBufSize), 'mbedtls_x509_crt_parse SetCertificate:');

  _UpdateCert;
end;

procedure TCrossMbedTlsSocket.SetCertificate(const ACertStr: string);
var
  LCertBytes: TBytes;
begin
  LCertBytes := TEncoding.ANSI.GetBytes(ACertStr);
  LCertBytes := _MbedCert(LCertBytes);

  SetCertificate(Pointer(LCertBytes), Length(LCertBytes));
end;

procedure TCrossMbedTlsSocket.SetCertificateFile(const ACertFile: string);
var
  LCertBytes: TBytes;
begin
  LCertBytes := TFile.ReadAllBytes(ACertFile);
  LCertBytes := _MbedCert(LCertBytes);

  SetCertificate(Pointer(LCertBytes), Length(LCertBytes));
end;

procedure TCrossMbedTlsSocket.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer);
begin
  MbedCheck(mbedtls_pk_parse_key(@FPKey, APKeyBuf, APKeyBufSize, nil, 0), 'mbedtls_pk_parse_key SetPrivateKey:');

  _UpdateCert;
end;

procedure TCrossMbedTlsSocket.SetPrivateKey(const APKeyStr: string);
var
  LPKeyBytes: TBytes;
begin
  LPKeyBytes := TEncoding.ANSI.GetBytes(APKeyStr);
  LPKeyBytes := _MbedCert(LPKeyBytes);

  SetPrivateKey(Pointer(LPKeyBytes), Length(LPKeyBytes));
end;

procedure TCrossMbedTlsSocket.SetPrivateKeyFile(const APKeyFile: string);
var
  LPKeyBytes: TBytes;
begin
  LPKeyBytes := TFile.ReadAllBytes(APKeyFile);
  LPKeyBytes := _MbedCert(LPKeyBytes);

  SetPrivateKey(Pointer(LPKeyBytes), Length(LPKeyBytes));
end;

procedure TCrossMbedTlsSocket.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnection: TCrossMbedTlsConnection;
begin
  LConnection := AConnection as TCrossMbedTlsConnection;

  // 网络连接已建立, 等待握手
  LConnection.ConnectStatus := csHandshaking;

  if LConnection._SslHandshake then
  begin
    LConnection.ConnectStatus := csConnected;
    inherited TriggerConnected(AConnection);
  end;
end;

procedure TCrossMbedTlsSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnection: TCrossMbedTlsConnection;
  LRetCode: Integer;
begin
  LConnection := AConnection as TCrossMbedTlsConnection;

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
end;

procedure TCrossMbedTlsSocket._FreeSslConf;
begin
  mbedtls_ssl_config_free(@FSrvConf);
  mbedtls_ssl_config_free(@FCliConf);

  mbedtls_x509_crt_free(@FCert);
  mbedtls_pk_free(@FPKey);

  mbedtls_ctr_drbg_free(@FCtrDrbg);
  mbedtls_entropy_free(@FEntropy);
	mbedtls_ssl_cache_free(@FCache);
end;

procedure TCrossMbedTlsSocket._InitSslConf;
begin
  mbedtls_x509_crt_init(@FCert);
  mbedtls_pk_init(@FPKey);
  mbedtls_ctr_drbg_init(@FCtrDrbg);
  mbedtls_entropy_init(@FEntropy);
  mbedtls_ssl_cache_init(@FCache);

  MbedCheck(mbedtls_ctr_drbg_seed(@FCtrDrbg, mbedtls_entropy_func, @FEntropy, nil, 0), 'mbedtls_ctr_drbg_seed:');

  {$region '服务端SSL配置'}
  mbedtls_ssl_config_init(@FSrvConf);
  mbedtls_ssl_conf_rng(@FSrvConf, mbedtls_ctr_drbg_random, @FCtrDrbg);
  mbedtls_ssl_conf_authmode(@FSrvConf, MBEDTLS_SSL_VERIFY_OPTIONAL);
  mbedtls_ssl_conf_session_cache(@FSrvConf, @FCache, mbedtls_ssl_cache_get, mbedtls_ssl_cache_set); // 仅服务端有效
  mbedtls_ssl_conf_ciphersuites(@FSrvConf, PInteger(@DEFAULT_CIPHERSUITES_SERVER));
  mbedtls_ssl_conf_min_version(@FSrvConf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3); // TLS v1.2
  MbedCheck(mbedtls_ssl_config_defaults(@FSrvConf,
    MBEDTLS_SSL_IS_SERVER,
    MBEDTLS_SSL_TRANSPORT_STREAM,
    MBEDTLS_SSL_PRESET_DEFAULT), 'mbedtls_ssl_config_defaults FSrvConf:');
  {$endregion}

  {$region '客户端SSL配置'}
  mbedtls_ssl_config_init(@FCliConf);
  mbedtls_ssl_conf_rng(@FCliConf, mbedtls_ctr_drbg_random, @FCtrDrbg);
  mbedtls_ssl_conf_authmode(@FCliConf, MBEDTLS_SSL_VERIFY_OPTIONAL);
  MbedCheck(mbedtls_ssl_config_defaults(@FCliConf,
    MBEDTLS_SSL_IS_CLIENT,
    MBEDTLS_SSL_TRANSPORT_STREAM,
    MBEDTLS_SSL_PRESET_DEFAULT), 'mbedtls_ssl_config_defaults FCliConf:');
  mbedtls_ssl_conf_ciphersuites(@FCliConf, PInteger(@DEFAULT_CIPHERSUITES_CLIENT));
  {$endregion}
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

  mbedtls_ssl_conf_ca_chain(@FCliConf, @FCert, nil);

  // 尚未加载私钥
  if (FPKey.pk_info = nil) then Exit;

  if (FCert.next <> nil) then
    mbedtls_ssl_conf_ca_chain(@FSrvConf, FCert.next, nil);

  MbedCheck(mbedtls_ssl_conf_own_cert(@FSrvConf, @FCert, @FPKey), 'mbedtls_ssl_conf_own_cert:');
end;

end.
