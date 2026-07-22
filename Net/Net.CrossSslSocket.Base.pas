unit Net.CrossSslSocket.Base;

interface

{$I zLib.inc}

uses
  SysUtils,
  Classes,

  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Types,

  Utils.IOUtils,
  Utils.SyncObjs;

type
  ICrossSslConnection = interface(ICrossConnection)
  ['{7B7B1DE2-8EDE-4F10-8193-2769D29C59FB}']
    function GetSsl: Boolean;

    /// <summary>
    ///   获取 SSL 详细信息(在连接成功之后调用)
    /// </summary>
    function GetSslInfo(var ASslInfo: TSslInfo): Boolean;

    /// <summary>
    ///   是否已启用 SSL
    /// </summary>
    property Ssl: Boolean read GetSsl;
  end;

  /// <summary>
  ///   SSL Socket
  /// </summary>
  /// <remarks>
  ///   正确的使用步骤:
  ///   <list type="number">
  ///     <item>
  ///       SetCertificate 或 SetCertificateFile
  ///     </item>
  ///     <item>
  ///       SetPrivateKey 或 SetPrivateKeyFile。mTLS 客户端也必须设置本端证书和私钥
  ///     </item>
  ///     <item>
  ///       需要验证对端时，先 AddCACertificate，再设置 VerifyPeer=True
  ///     </item>
  ///     <item>
  ///       Connect / Listen
  ///     </item>
  ///   </list>
  ///   加密私钥密码当前由 OpenSSL 后端支持；内置 Mbed TLS 2.14.0
  ///   因安全原因会拒绝非空密码。
  ///   首个 SSL 连接创建后，证书、私钥、CA 和 VerifyPeer 均不可再修改。
  /// </remarks>
  ICrossSslSocket = interface(ICrossSocket)
  ['{32750F56-2824-4F5E-B556-1286DACE9188}']
    function GetSsl: Boolean;
    function GetSslMaxPendingWriteBytes: Int64;
    function GetAllowUnsafeLegacyRenegotiation: Boolean;
    function GetVerifyPeer: Boolean;

    procedure SetSslMaxPendingWriteBytes(const AValue: Int64);
    procedure SetAllowUnsafeLegacyRenegotiation(const AValue: Boolean);
    procedure SetVerifyPeer(const AValue: Boolean);

    /// <summary>
    ///   从内存加载证书
    /// </summary>
    /// <param name="ACertBuf">
    ///   证书缓冲区
    /// </param>
    /// <param name="ACertBufSize">
    ///   证书缓冲区大小
    /// </param>
    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload;

    /// <summary>
    ///   从字节数组加载证书
    /// </summary>
    /// <param name="ACertBytes">
    ///   证书字节数组
    /// </param>
    procedure SetCertificate(const ACertBytes: TBytes); overload;

    /// <summary>
    ///   从字符串加载证书
    /// </summary>
    /// <param name="ACertStr">
    ///   证书字符串
    /// </param>
    procedure SetCertificate(const ACertStr: string); overload;

    /// <summary>
    ///   从文件加载证书
    /// </summary>
    /// <param name="ACertFile">
    ///   证书文件
    /// </param>
    procedure SetCertificateFile(const ACertFile: string);

    /// <summary>
    ///   从内存追加用于验证对端证书链的受信任 CA 证书
    /// </summary>
    /// <remarks>
    ///   此方法配置的是对端证书的信任锚，不会设置本端身份：客户端连接
    ///   (ctConnect) 使用它验证服务端证书；服务端连接 (ctAccept) 使用它验证
    ///   mTLS 客户端证书。自签名证书也可以作为信任锚直接添加。本端提交给
    ///   对方的证书和私钥应分别通过 SetCertificate 和 SetPrivateKey 设置。
    ///   应先添加至少一个 CA，再设置 VerifyPeer=True，并且必须在首个 SSL
    ///   连接创建前完成配置。可多次调用以累积 CA，也可一次传入 PEM bundle。
    /// </remarks>
    /// <param name="ABuf">
    ///   CA 证书或 PEM bundle 缓冲区
    /// </param>
    /// <param name="ASize">
    ///   CA 证书缓冲区大小
    /// </param>
    procedure AddCACertificate(const ABuf: Pointer;
      const ASize: Integer); overload;

    /// <summary>
    ///   从字节数组追加用于验证对端证书链的受信任 CA 证书
    /// </summary>
    /// <param name="ABytes">
    ///   CA 证书或 PEM bundle 字节数组
    /// </param>
    procedure AddCACertificate(const ABytes: TBytes); overload;

    /// <summary>
    ///   从字符串追加用于验证对端证书链的受信任 CA 证书
    /// </summary>
    /// <param name="AText">
    ///   CA 证书或 PEM bundle 字符串
    /// </param>
    procedure AddCACertificate(const AText: string); overload;

    /// <summary>
    ///   从文件追加用于验证对端证书链的受信任 CA 证书
    /// </summary>
    /// <param name="AFileName">
    ///   CA 证书或 PEM bundle 文件
    /// </param>
    procedure AddCACertificateFile(const AFileName: string);

    /// <summary>
    ///   从内存加载私钥
    /// </summary>
    /// <param name="APKeyBuf">
    ///   私钥缓冲区
    /// </param>
    /// <param name="APKeyBufSize">
    ///   私钥缓冲区大小
    /// </param>
    /// <param name="APassword">
    ///   加密私钥密码, 空字符串表示未提供密码
    /// </param>
    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer;
      const APassword: string = ''); overload;

    /// <summary>
    ///   从字节数组加载私钥
    /// </summary>
    /// <param name="APKeyBytes">
    ///   私钥字节数组
    /// </param>
    /// <param name="APassword">
    ///   加密私钥密码, 空字符串表示未提供密码
    /// </param>
    procedure SetPrivateKey(const APKeyBytes: TBytes;
      const APassword: string = ''); overload;

    /// <summary>
    ///   从字符串加载私钥
    /// </summary>
    /// <param name="APKeyStr">
    ///   私钥字符串
    /// </param>
    /// <param name="APassword">
    ///   加密私钥密码, 空字符串表示未提供密码
    /// </param>
    procedure SetPrivateKey(const APKeyStr: string;
      const APassword: string = ''); overload;

    /// <summary>
    ///   从文件加载私钥
    /// </summary>
    /// <param name="APKeyFile">
    ///   私钥文件
    /// </param>
    /// <param name="APassword">
    ///   加密私钥密码, 空字符串表示未提供密码
    /// </param>
    procedure SetPrivateKeyFile(const APKeyFile: string;
      const APassword: string = '');

    /// <summary>
    ///   是否已启用 SSL
    /// </summary>
    property Ssl: Boolean read GetSsl;

    /// <summary>
    ///   是否强制验证对端证书。服务端要求客户端证书，客户端同时验证服务端主机名。
    /// </summary>
    property VerifyPeer: Boolean read GetVerifyPeer write SetVerifyPeer;

    /// <summary>
    ///   每条 SSL 连接 pending write 队列的明文字节上限.
    /// </summary>
    /// <remarks>
    ///   当 SSL_write 因 WANT_READ/WANT_WRITE + BIO 空被挂起时, 待写明文进入
    ///   pending 队列等 TriggerReceived 推进 SSL 状态. 队列累计字节超此上限时,
    ///   新的 _SslSend 调用会立即 fail callback (背压保护, 防 OOM).
    ///   默认 4 MB; 设 0 表示不限制 (不推荐).
    ///   仅 OpenSSL backend 当前实现 (MbedTLS 后续阶段补).
    /// </remarks>
    property SslMaxPendingWriteBytes: Int64 read GetSslMaxPendingWriteBytes write SetSslMaxPendingWriteBytes;

    /// <summary>
    ///  允许不安全的旧式重新协商(兼容工商银行ch5.dcep.ccb.com:443).
    /// </summary>
    property AllowUnsafeLegacyRenegotiation: Boolean
      read GetAllowUnsafeLegacyRenegotiation write SetAllowUnsafeLegacyRenegotiation;
  end;

  TCrossSslListenBase = class(TCrossListen);

  TCrossSslConnectionBase = class(TCrossConnection, ICrossSslConnection)
  protected
    function GetSsl: Boolean;
  public
    function GetSslInfo(var ASslInfo: TSslInfo): Boolean; virtual;

    property Ssl: Boolean read GetSsl;
  end;

  TCrossSslSocketBase = class(TCrossSocket, ICrossSslSocket)
  private
    FSsl: Boolean;
    FSslMaxPendingWriteBytes: Int64;
    FAllowUnsafeLegacyRenegotiation: Boolean;
    FVerifyPeer: Boolean;
    FHasCACertificate: Boolean;
    FTlsConfigLocked: Boolean;
    FTlsConfigValid: Boolean;
    FTlsConfigLock: ILock;
  protected
    function GetSsl: Boolean;
    function GetSslMaxPendingWriteBytes: Int64;
    procedure SetSslMaxPendingWriteBytes(const AValue: Int64);
    function GetAllowUnsafeLegacyRenegotiation: Boolean;
    procedure SetAllowUnsafeLegacyRenegotiation(const AValue: Boolean);
    function GetVerifyPeer: Boolean;

    procedure BeginTlsConfigUpdate;
    procedure EndTlsConfigUpdate;
    procedure LockTlsConfiguration;
    procedure InvalidateTlsConfiguration;
    procedure MarkCACertificateAdded;
    procedure ApplyVerifyPeer(const AValue: Boolean); virtual;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); reintroduce; virtual;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload; virtual; abstract;
    procedure SetCertificate(const ACertBytes: TBytes); overload; virtual;
    procedure SetCertificate(const ACertStr: string); overload; virtual;
    procedure SetCertificateFile(const ACertFile: string); virtual;

    procedure AddCACertificate(const ABuf: Pointer;
      const ASize: Integer); overload; virtual;
    procedure AddCACertificate(const ABytes: TBytes); overload; virtual;
    procedure AddCACertificate(const AText: string); overload; virtual;
    procedure AddCACertificateFile(const AFileName: string); virtual;

    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer;
      const APassword: string = ''); overload; virtual; abstract;
    procedure SetPrivateKey(const APKeyBytes: TBytes;
      const APassword: string = ''); overload; virtual;
    procedure SetPrivateKey(const APKeyStr: string;
      const APassword: string = ''); overload; virtual;
    procedure SetPrivateKeyFile(const APKeyFile: string;
      const APassword: string = ''); virtual;

    procedure SetVerifyPeer(const AValue: Boolean); virtual;

    property Ssl: Boolean read GetSsl;
    property VerifyPeer: Boolean read GetVerifyPeer write SetVerifyPeer;
    property SslMaxPendingWriteBytes: Int64 read GetSslMaxPendingWriteBytes write SetSslMaxPendingWriteBytes;

    property AllowUnsafeLegacyRenegotiation: Boolean
      read GetAllowUnsafeLegacyRenegotiation write SetAllowUnsafeLegacyRenegotiation;
  end;

implementation

{ TCrossSslSocketBase }

constructor TCrossSslSocketBase.Create(const AIoThreads: Integer;
  const ASsl: Boolean);
begin
  inherited Create(AIoThreads);

  FSsl := ASsl;
  // pending write 队列默认上限 4 MB (大文件分片 + 防恶意 OOM 平衡)
  FSslMaxPendingWriteBytes := 4 * 1024 * 1024;
  FTlsConfigValid := True;
  FTlsConfigLock := TLock.Create;
end;

procedure TCrossSslSocketBase.BeginTlsConfigUpdate;
begin
  FTlsConfigLock.Enter;
  if FTlsConfigLocked then
  begin
    FTlsConfigLock.Leave;
    raise ECrossSocket.Create('TLS configuration is locked after the first SSL connection.');
  end;
  if not FTlsConfigValid then
  begin
    FTlsConfigLock.Leave;
    raise ECrossSocket.Create('TLS configuration is invalid.');
  end;
end;

procedure TCrossSslSocketBase.EndTlsConfigUpdate;
begin
  FTlsConfigLock.Leave;
end;

procedure TCrossSslSocketBase.LockTlsConfiguration;
begin
  FTlsConfigLock.Enter;
  try
    if not FTlsConfigValid then
      raise ECrossSocket.Create('TLS configuration is invalid.');
    if FVerifyPeer and not FHasCACertificate then
      raise ECrossSocket.Create('At least one CA certificate is required when peer verification is enabled.');
    FTlsConfigLocked := True;
  finally
    FTlsConfigLock.Leave;
  end;
end;

procedure TCrossSslSocketBase.InvalidateTlsConfiguration;
begin
  FTlsConfigValid := False;
end;

procedure TCrossSslSocketBase.MarkCACertificateAdded;
begin
  FHasCACertificate := True;
end;

procedure TCrossSslSocketBase.ApplyVerifyPeer(const AValue: Boolean);
begin
end;

function TCrossSslSocketBase.GetSsl: Boolean;
begin
  Result := FSsl;
end;

function TCrossSslSocketBase.GetSslMaxPendingWriteBytes: Int64;
begin
  Result := FSslMaxPendingWriteBytes;
end;

procedure TCrossSslSocketBase.SetSslMaxPendingWriteBytes(const AValue: Int64);
begin
  FSslMaxPendingWriteBytes := AValue;
end;

function TCrossSslSocketBase.GetAllowUnsafeLegacyRenegotiation: Boolean;
begin
  Result := FAllowUnsafeLegacyRenegotiation;
end;

function TCrossSslSocketBase.GetVerifyPeer: Boolean;
begin
  FTlsConfigLock.Enter;
  try
    Result := FVerifyPeer;
  finally
    FTlsConfigLock.Leave;
  end;
end;

procedure TCrossSslSocketBase.SetAllowUnsafeLegacyRenegotiation(const AValue: Boolean);
begin
  FAllowUnsafeLegacyRenegotiation := AValue;
end;

procedure TCrossSslSocketBase.SetVerifyPeer(const AValue: Boolean);
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    if AValue and not FHasCACertificate then
      raise ECrossSocket.Create(
        'At least one CA certificate is required before enabling peer verification.');
    ApplyVerifyPeer(AValue);
    FVerifyPeer := AValue;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossSslSocketBase.AddCACertificate(const ABuf: Pointer;
  const ASize: Integer);
begin
  if Ssl then
    raise ECrossSocket.CreateFmt('%s does not support CA certificates.',
      [ClassName]);
end;

procedure TCrossSslSocketBase.AddCACertificate(const ABytes: TBytes);
begin
  AddCACertificate(Pointer(ABytes), Length(ABytes));
end;

procedure TCrossSslSocketBase.AddCACertificate(const AText: string);
begin
  AddCACertificate(TEncoding.ANSI.GetBytes(AText));
end;

procedure TCrossSslSocketBase.AddCACertificateFile(const AFileName: string);
begin
  AddCACertificate(TFileUtils.ReadAllBytes(AFileName));
end;

procedure TCrossSslSocketBase.SetCertificate(const ACertBytes: TBytes);
begin
  SetCertificate(Pointer(ACertBytes), Length(ACertBytes));
end;

procedure TCrossSslSocketBase.SetCertificate(const ACertStr: string);
begin
  SetCertificate(TEncoding.ANSI.GetBytes(ACertStr));
end;

procedure TCrossSslSocketBase.SetCertificateFile(const ACertFile: string);
begin
  SetCertificate(TFileUtils.ReadAllBytes(ACertFile));
end;

procedure TCrossSslSocketBase.SetPrivateKey(const APKeyBytes: TBytes;
  const APassword: string);
begin
  SetPrivateKey(Pointer(APKeyBytes), Length(APKeyBytes), APassword);
end;

procedure TCrossSslSocketBase.SetPrivateKey(const APKeyStr: string;
  const APassword: string);
var
  LKeyBytes: TBytes;
begin
  LKeyBytes := TEncoding.ANSI.GetBytes(APKeyStr);
  try
    SetPrivateKey(LKeyBytes, APassword);
  finally
    if Length(LKeyBytes) > 0 then
      FillChar(LKeyBytes[0], Length(LKeyBytes), 0);
  end;
end;

procedure TCrossSslSocketBase.SetPrivateKeyFile(const APKeyFile,
  APassword: string);
var
  LKeyBytes: TBytes;
begin
  LKeyBytes := TFileUtils.ReadAllBytes(APKeyFile);
  try
    SetPrivateKey(LKeyBytes, APassword);
  finally
    if Length(LKeyBytes) > 0 then
      FillChar(LKeyBytes[0], Length(LKeyBytes), 0);
  end;
end;

{ TCrossSslConnectionBase }

function TCrossSslConnectionBase.GetSsl: Boolean;
begin
  Result := TCrossSslSocketBase(Owner).Ssl;
end;

function TCrossSslConnectionBase.GetSslInfo(var ASslInfo: TSslInfo): Boolean;
begin
  Result := False;
end;

end.
