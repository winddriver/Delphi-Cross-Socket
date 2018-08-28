{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSslSocket;

{
  SSL通讯基本流程:
  1. 当连接建立时进行 SSL 握手, 收到数据时也要检查握手状态
  2. 发送数据: 用 SSL_write 写入原数据, BIO_read 读取加密后的数据进行发送
  3. 接收数据: 用 BIO_write 写入收到的数据, 用 SSL_read 读取解密后的数据

  OpenSSL 的 SSL 对象不是线程安全的!!!!!!!!!!!!!!!!!
  即便初始化 OpenSSL 时设置了那几个线程相关的回调也一样,
  一定要保证同一时间不能有两个或以上的线程访问到同一个 SSL 对象
  或者与其绑定的 BIO 对象

  由于收发数据需要解密及加密, 还需要用临界区保护 SSL 对象,
  所以效率比不使用 SSL 时会下降很多, 这是无法避免的

  传输层安全协议:
  https://zh.wikipedia.org/wiki/%E5%82%B3%E8%BC%B8%E5%B1%A4%E5%AE%89%E5%85%A8%E5%8D%94%E8%AD%B0
}

interface

uses
  System.SysUtils,
  System.Classes,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.OpenSSL;

type
  /// <summary>
  ///   <para>
  ///     加密方法
  ///   </para>
  ///   <para>
  ///     TLS 比 SSL 安全性高一些
  ///   </para>
  ///   <para>
  ///     目前 SSLv2 及 SSLv3 已被淘汰, 在新的 OpenSSL 库中即便使用 SSLxx 也会被自动映射到 TLSxx
  ///   </para>
  ///   <para>
  ///     OpenSSL 1.01+ 支持 TLS1.2
  ///   </para>
  /// </summary>
  /// <remarks>
  ///   <list type="bullet">
  ///     <item>
  ///       若要保持最好的兼容性, 请在服务端使用 SSv23_server, 这种情况服务端会根据客户端的支持情况使用最合适的加密套件,
  ///       同时兼容 TLS1.0 TLS1.1, TLS1.2;
  ///     </item>
  ///     <item>
  ///       若要最高的安全性, 不考虑兼容, 请在服务端使用 TLSv1_2_server
  ///     </item>
  ///   </list>
  /// </remarks>
  TSslMethod = (
    /// <summary>
    ///   OpenSSL 0.9+, 客户端 + 服务端
    /// </summary>
    SSLv23,

    /// <summary>
    ///   OpenSSL 0.9+, 客户端
    /// </summary>
    SSLv23_client,

    /// <summary>
    ///   OpenSSL 0.9+, 服务端
    /// </summary>
    SSLv23_server,

    /// <summary>
    ///   OpenSSL 0.9+, 客户端 + 服务端
    /// </summary>
    TLSv1,

    /// <summary>
    ///   OpenSSL 0.9+, 客户端
    /// </summary>
    TLSv1_client,

    /// <summary>
    ///   OpenSSL 0.9+, 服务端
    /// </summary>
    TLSv1_server,

    /// <summary>
    ///   OpenSSL 1.0.1+, 客户端 + 服务端
    /// </summary>
    TLSv1_2,

    /// <summary>
    ///   OpenSSL 1.0.1+, 客户端
    /// </summary>
    TLSv1_2_client,

    /// <summary>
    ///   OpenSSL 1.0.1+, 服务端
    /// </summary>
    TLSv1_2_server);

  /// <summary>
  ///   SSL Socket
  /// </summary>
  /// <remarks>
  ///   正确的使用步骤:
  ///   <list type="number">
  ///     <item>
  ///       InitSslCtx
  ///     </item>
  ///     <item>
  ///       SetCertificate 或 SetCertificateFile
  ///     </item>
  ///     <item>
  ///       SetPrivateKey 或 SetPrivateKeyFile
  ///     </item>
  ///     <item>
  ///       Connect / Listen
  ///     </item>
  ///   </list>
  /// </remarks>
  ICrossSslSocket = interface(ICrossSocket)
  ['{A4765486-A0F1-4EFD-BC39-FA16AED21A6A}']
    /// <summary>
    ///   OpenSSL 库版本号
    /// </summary>
    function SSLVersion: Longword;

    /// <summary>
    ///   初始化 SSL 上下文对象
    /// </summary>
    /// <param name="ASslMethod">
    ///   加密方法
    /// </param>
    procedure InitSslCtx(ASslMethod: TSslMethod);

    /// <summary>
    ///   释放 SSL 上下文对象
    /// </summary>
    procedure FreeSslCtx;

    /// <summary>
    ///   从内存加载证书
    /// </summary>
    /// <param name="ACertBuf">
    ///   证书缓冲区
    /// </param>
    /// <param name="ACertBufSize">
    ///   证书缓冲区大小
    /// </param>
    procedure SetCertificate(ACertBuf: Pointer; ACertBufSize: Integer); overload;

    /// <summary>
    ///   从字符串加载证书
    /// </summary>
    /// <param name="ACertBuf">
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
    ///   从内存加载私钥
    /// </summary>
    /// <param name="APKeyBuf">
    ///   私钥缓冲区
    /// </param>
    /// <param name="APKeyBufSize">
    ///   私钥缓冲区大小
    /// </param>
    procedure SetPrivateKey(APKeyBuf: Pointer; APKeyBufSize: Integer); overload;

    /// <summary>
    ///   从字符串加载私钥
    /// </summary>
    /// <param name="APKeyBuf">
    ///   私钥字符串
    /// </param>
    procedure SetPrivateKey(const APKeyStr: string); overload;

    /// <summary>
    ///   从文件加载私钥
    /// </summary>
    /// <param name="APKeyFile">
    ///   私钥文件
    /// </param>
    procedure SetPrivateKeyFile(const APKeyFile: string);
  end;

  TCrossSslConnection = class(TCrossConnection)
  private
    FSsl: PSSL;
    FBIOIn, FBIOOut: PBIO;
    FSslLock: TObject;

    procedure _SslLock; inline;
    procedure _SslUnlock; inline;

    function _SslHandshake: Boolean;
    procedure _WriteBioToSocket(const ACallback: TProc<ICrossConnection, Boolean> = nil);
  protected
    procedure DirectSend(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); override;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); override;
    destructor Destroy; override;
  end;

  /// <remarks>
  ///   若要继承该类, 请重载 LogicXXX, 而不是 TriggerXXX
  /// </remarks>
  TCrossSslSocket = class(TCrossSocket, ICrossSslSocket)
  private const
    SSL_BUF_SIZE = 32768;
  private class threadvar
    FSslInBuf: array [0..SSL_BUF_SIZE-1] of Byte;
  private
    FSslCtx: PSSL_CTX;
  protected
    procedure TriggerConnected(AConnection: ICrossConnection); override;
    procedure TriggerReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); override;

    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;

    function SSLVersion: Longword;

    procedure InitSslCtx(ASslMethod: TSslMethod);
    procedure FreeSslCtx;

    procedure SetCertificate(ACertBuf: Pointer; ACertBufSize: Integer); overload;
    procedure SetCertificate(const ACertStr: string); overload;
    procedure SetCertificateFile(const ACertFile: string);

    procedure SetPrivateKey(APKeyBuf: Pointer; APKeyBufSize: Integer); overload;
    procedure SetPrivateKey(const APKeyStr: string); overload;
    procedure SetPrivateKeyFile(const APKeyFile: string);
  end;

implementation

{ TCrossSslConnection }

constructor TCrossSslConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited;

  FSslLock := TObject.Create;

  FSsl := SSL_new(TCrossSslSocket(Owner).FSslCtx);
  FBIOIn := BIO_new(BIO_s_mem());
  FBIOOut := BIO_new(BIO_s_mem());
  SSL_set_bio(FSsl, FBIOIn, FBIOOut);

  if (ConnectType = ctAccept) then
    SSL_set_accept_state(FSsl)   // 服务端连接
  else
    SSL_set_connect_state(FSsl); // 客户端连接
end;

destructor TCrossSslConnection.Destroy;
begin
  _SslLock;
  try
    if (SSL_shutdown(FSsl) = 0) then
      SSL_shutdown(FSsl);
    SSL_free(FSsl);
  finally
    _SslUnlock;
  end;
  FreeAndNil(FSslLock);

  inherited;
end;

procedure TCrossSslConnection._WriteBioToSocket(
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LConnection: ICrossConnection;
  ret, error: Integer;
  LBuffer: TBytesStream;

  procedure _Success;
  begin
    if (LBuffer <> nil) then
      FreeAndNil(LBuffer);
    if Assigned(ACallback) then
      ACallback(LConnection, True);
  end;

  procedure _Failed;
  begin
    if (LBuffer <> nil) then
      FreeAndNil(LBuffer);
    LConnection.Close;
    if Assigned(ACallback) then
      ACallback(LConnection, False);
  end;

begin
  LConnection := Self;
  LBuffer := nil;

  {$region '将BIO中已加密的数据全部读到缓存中'}
  // 从BIO中读取数据这一段必须全读出来再发送
  // 因为SSL对象本身并不是线程安全的, 如果读取数据的同时, 另一个线程尝试操作SSL对象
  // 就会引起异常, 所以这里将读取数据和发送数据分成两部分, 将数据全读出来之后
  // 再调用异步发送, 方便在外层包裹加锁
  ret := BIO_pending(FBIOOut);
  if (ret <= 0) then
  begin
    _Success;
    Exit;
  end;

  LBuffer := TBytesStream.Create(nil);
  while (ret > 0) do
  begin
    LBuffer.Size := LBuffer.Size + ret;

    // 读取加密后的数据
    ret := BIO_read(FBIOOut, PByte(LBuffer.Memory) + LBuffer.Position, ret);
    error := SSL_get_error(FSsl, ret);
    if ssl_is_fatal_error(error) then
    begin
      _Failed;
      Exit;
    end;

    if (ret <= 0) then Break;

    LBuffer.Position := LBuffer.Position + ret;

    // 检查 BIO 中是否有数据
    ret := BIO_pending(FBIOOut);
  end;

  if (LBuffer.Memory = nil) or (LBuffer.Size <= 0) then
  begin
    _Success;
    Exit;
  end;
  {$endregion}

  {$region '发送缓存中已加密的数据'}
  inherited DirectSend(LBuffer.Memory, LBuffer.Size,
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      FreeAndNil(LBuffer);
      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
  {$endregion}
end;

procedure TCrossSslConnection.DirectSend(ABuffer: Pointer; ACount: Integer;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LConnection: ICrossConnection;
  ret, error: Integer;

  procedure _Failed;
  begin
    if Assigned(ACallback) then
      ACallback(LConnection, False);
  end;

begin
  LConnection := Self;

  // 将待发送数据加密
  // SSL_write 默认会将全部数据写入成功才返回,
  // 除非调用 SSL_CTX_set_mode 设置了 SSL_MODE_ENABLE_PARTIAL_WRITE 参数
  // 才会出现部分写入成功即返回的情况。这里并没有设置该参数，所以无需做
  // 部分数据的处理，只需要一次 SSL_Write 调用即可。
  _SslLock;
  try
    ret := SSL_write(FSsl, ABuffer, ACount);
    if (ret > 0) then
      _WriteBioToSocket(ACallback)
    else
    begin
      error := SSL_get_error(FSsl, ret);
      _Log('SSL_write error %d %s', [error, ssl_error_message(error)]);
      case error of
        SSL_ERROR_WANT_READ:;
        SSL_ERROR_WANT_WRITE: _WriteBioToSocket;
      else
        _Failed;
      end;
    end;
  finally
    _SslUnlock;
  end;
end;

procedure TCrossSslConnection._SslLock;
begin
  TMonitor.Enter(FSslLock);
end;

procedure TCrossSslConnection._SslUnlock;
begin
  TMonitor.Exit(FSslLock);
end;

function TCrossSslConnection._SslHandshake: Boolean;
var
  ret, error: Integer;
begin
  Result := False;

  _SslLock;
  try
    // 开始握手
    ret := SSL_do_handshake(FSsl);
    if (ret = 1) then
    begin
      _WriteBioToSocket;
      Exit(True);
    end;

    error := SSL_get_error(FSsl, ret);
    if ssl_is_fatal_error(error) then
    begin
      {$IFDEF DEBUG}
      _Log('SSL_do_handshake error %s', [ssl_error_message(error)]);
      {$ENDIF}
      Close;
    end else
      _WriteBioToSocket;
  finally
    _SslUnlock;
  end;
end;

{ TCrossSslSocket }

constructor TCrossSslSocket.Create(AIoThreads: Integer);
begin
  inherited;

  TSSLTools.LoadSSL;
end;

destructor TCrossSslSocket.Destroy;
begin
  inherited;

  FreeSslCtx;
  TSSLTools.UnloadSSL;
end;

function TCrossSslSocket.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TCrossSslConnection.Create(AOwner, AClientSocket, AConnectType);
end;

procedure TCrossSslSocket.InitSslCtx(ASslMethod: TSslMethod);
var
  LEcdh: PEC_KEY;
begin
  if (FSslCtx <> nil) then Exit;

  case ASslMethod of
    SSLv23:
      FSslCtx := TSSLTools.NewCTX(SSLv23_method());

    SSLv23_client:
      FSslCtx := TSSLTools.NewCTX(SSLv23_client_method());

    SSLv23_server:
      FSslCtx := TSSLTools.NewCTX(SSLv23_server_method());

    TLSv1:
      FSslCtx := TSSLTools.NewCTX(TLSv1_method());

    TLSv1_client:
      FSslCtx := TSSLTools.NewCTX(TLSv1_client_method());

    TLSv1_server:
      FSslCtx := TSSLTools.NewCTX(TLSv1_server_method());

    TLSv1_2:
      FSslCtx := TSSLTools.NewCTX(TLSv1_2_method());

    TLSv1_2_client:
      FSslCtx := TSSLTools.NewCTX(TLSv1_2_client_method());

    TLSv1_2_server:
      FSslCtx := TSSLTools.NewCTX(TLSv1_2_server_method());
  else
    FSslCtx := TSSLTools.NewCTX(SSLv23_method());
  end;

  SSL_CTX_set_verify(FSslCtx, SSL_VERIFY_NONE, nil);

  SSL_CTX_set_mode(FSslCtx, SSL_MODE_AUTO_RETRY);

  {$region '采用新型加密套件进行加密'}
  SSL_CTX_set_options(FSslCtx,
    // 不使用已经不安全的 SSLv2 和 SSv3
    SSL_OP_NO_SSLv2 or SSL_OP_NO_SSLv3 or
    // 启用各种漏洞解决方案(适用于 0.9.7 之前的版本)
    SSL_OP_ALL or
    // 总是使用 SSL_CTX_set_tmp_ecdh/SSL_set_tmp_ecdh 设置的参数创建新 KEY
    SSL_OP_SINGLE_ECDH_USE or
    // 根据服务器偏好选择加密套件
    SSL_OP_CIPHER_SERVER_PREFERENCE
  );

  // 设置加密套件的使用顺序
  SSL_CTX_set_cipher_list(FSslCtx,
    // from nodejs(node_constants.h)
    // #define DEFAULT_CIPHER_LIST_CORE
    'ECDHE-ECDSA-AES128-GCM-SHA256:' +
    'ECDHE-RSA-AES128-GCM-SHA256:' +
    'ECDHE-RSA-AES256-GCM-SHA384:' +
    'ECDHE-ECDSA-AES256-GCM-SHA384:' +
    'DHE-RSA-AES128-GCM-SHA256:' +
    'ECDHE-RSA-AES128-SHA256:' +
    'DHE-RSA-AES128-SHA256:' +
    'ECDHE-RSA-AES256-SHA384:' +
    'DHE-RSA-AES256-SHA384:' +
    'ECDHE-RSA-AES256-SHA256:' +
    'DHE-RSA-AES256-SHA256:' +
    'HIGH:' +
    '!aNULL:' +
    '!eNULL:' +
    '!EXPORT:' +
    '!DES:' +
    '!RC4:' +
    '!MD5:' +
    '!PSK:' +
    '!SRP:' +
    '!CAMELLIA'
  );

  LEcdh := EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  if (LEcdh <> nil) then
  begin
    SSL_CTX_set_tmp_ecdh(FSslCtx, LEcdh);
    EC_KEY_free(LEcdh);
  end;
  {$endregion}
end;

function TCrossSslSocket.SSLVersion: Longword;
begin
  Result := TSSLTools.SSLVersion;
end;

procedure TCrossSslSocket.FreeSslCtx;
begin
  if (FSslCtx = nil) then Exit;

  TSSLTools.FreeCTX(FSslCtx);
end;

procedure TCrossSslSocket.SetCertificate(ACertBuf: Pointer;
  ACertBufSize: Integer);
begin
  TSSLTools.SetCertificate(FSslCtx, ACertBuf, ACertBufSize);
end;

procedure TCrossSslSocket.SetCertificate(const ACertStr: string);
begin
  TSSLTools.SetCertificate(FSslCtx, ACertStr);
end;

procedure TCrossSslSocket.SetCertificateFile(const ACertFile: string);
begin
  TSSLTools.SetCertificateFile(FSslCtx, ACertFile);
end;

procedure TCrossSslSocket.SetPrivateKey(APKeyBuf: Pointer;
  APKeyBufSize: Integer);
begin
  TSSLTools.SetPrivateKey(FSslCtx, APKeyBuf, APKeyBufSize);
end;

procedure TCrossSslSocket.SetPrivateKey(const APKeyStr: string);
begin
  TSSLTools.SetPrivateKey(FSslCtx, APKeyStr);
end;

procedure TCrossSslSocket.SetPrivateKeyFile(const APKeyFile: string);
begin
  TSSLTools.SetPrivateKeyFile(FSslCtx, APKeyFile);
end;

procedure TCrossSslSocket.TriggerConnected(AConnection: ICrossConnection);
var
  LConnection: TCrossSslConnection;
begin
  LConnection := AConnection as TCrossSslConnection;

  LConnection._SslLock;
  try
    // 网络连接已建立, 等待握手
    LConnection.ConnectStatus := csHandshaking;

    // 已完成握手才视为连接真正建立
    if LConnection._SslHandshake then
    begin
      LConnection.ConnectStatus := csConnected;
      inherited TriggerConnected(AConnection);
    end;
  finally
    LConnection._SslUnlock;
  end;
end;

procedure TCrossSslSocket.TriggerReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
var
  LConnection: TCrossSslConnection;
  ret, error: Integer;
  LBuffer: TBytesStream;
begin
  LConnection := AConnection as TCrossSslConnection;
  LConnection._SslLock;
  try
    // 将收到的加密数据写入 BIO, 让 OpenSSL 对其解密
    while True do
    begin
      ret := BIO_write(LConnection.FBIOIn, ABuf, ALen);
//      _Log('recv %d, bio_write %d', [ALen, ret]);
      if (ret > 0) then Break;

      if not BIO_should_retry(LConnection.FBIOIn) then
      begin
        LConnection.Close;
        Exit;
      end;
    end;

    // 未完成初始化, 继续握手
    if not SSL_is_init_finished(LConnection.FSsl) then
    begin
      // 已完成握手才视为连接真正建立
      if LConnection._SslHandshake
        and (LConnection.ConnectStatus = csHandshaking) then
      begin
        LConnection.ConnectStatus := csConnected;
        inherited TriggerConnected(AConnection);
      end;
      Exit;
    end;

    LBuffer := TBytesStream.Create(nil);
    try
      while True do
      begin
        // 貌似每次读出来的数据都不会超过 16K
        ret := SSL_read(LConnection.FSsl, @FSslInBuf[0], SSL_BUF_SIZE);
        if (ret > 0) then
          LBuffer.Write(FSslInBuf[0], ret)
        else
        begin
          error := SSL_get_error(LConnection.FSsl, ret);
//          _Log('SSL_read error %d %s', [error, ssl_error_message(error)]);

          if ssl_is_fatal_error(error) then
          begin
            {$IFDEF DEBUG}
            _Log('SSL_read error %d %s', [error, ssl_error_message(error)]);
            {$ENDIF}
            LConnection.Close;
          end;
          Break;
        end;
      end;

      if (LBuffer.Size > 0) then
        inherited TriggerReceived(AConnection, LBuffer.Memory, LBuffer.Size);
    finally
      FreeAndNil(LBuffer);
    end;
  finally
    LConnection._SslUnlock;
  end;
end;

end.
