{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSslSocket.OpenSSL;

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
  Net.CrossSslSocket.Base,
  Net.OpenSSL;

type
  TCrossOpenSslConnection = class(TCrossConnection)
  private
    FSsl: PSSL;
    FBIOIn, FBIOOut: PBIO;
    FSslLock: TObject;

    procedure _SslLock; inline;
    procedure _SslUnlock; inline;

    function _SslHandshake: Boolean;
    procedure _WriteBioToSocket(const ACallback: TCrossConnectionCallback = nil);
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
  TCrossOpenSslSocket = class(TCrossSocket, ICrossSslSocket)
  private const
    SSL_BUF_SIZE = 32768;
  private class threadvar
    FSslInBuf: array [0..SSL_BUF_SIZE-1] of Byte;
  private
    FSslCtx: PSSL_CTX;

    procedure _InitSslCtx;
    procedure _FreeSslCtx;
  protected
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType): ICrossConnection; override;
  public
    constructor Create(const AIoThreads: Integer); override;
    destructor Destroy; override;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload;
    procedure SetCertificate(const ACertStr: string); overload;
    procedure SetCertificateFile(const ACertFile: string);

    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer); overload;
    procedure SetPrivateKey(const APKeyStr: string); overload;
    procedure SetPrivateKeyFile(const APKeyFile: string);
  end;

implementation

{ TCrossOpenSslConnection }

constructor TCrossOpenSslConnection.Create(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType);
begin
  inherited;

  FSslLock := TObject.Create;

  FSsl := SSL_new(TCrossOpenSslSocket(Owner).FSslCtx);
  FBIOIn := BIO_new(BIO_s_mem());
  FBIOOut := BIO_new(BIO_s_mem());
  SSL_set_bio(FSsl, FBIOIn, FBIOOut);

  if (ConnectType = ctAccept) then
    SSL_set_accept_state(FSsl)   // 服务端连接
  else
    SSL_set_connect_state(FSsl); // 客户端连接
end;

destructor TCrossOpenSslConnection.Destroy;
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

procedure TCrossOpenSslConnection._WriteBioToSocket(
  const ACallback: TCrossConnectionCallback);
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
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      FreeAndNil(LBuffer);
      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
  {$endregion}
end;

procedure TCrossOpenSslConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
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

procedure TCrossOpenSslConnection._SslLock;
begin
  TMonitor.Enter(FSslLock);
end;

procedure TCrossOpenSslConnection._SslUnlock;
begin
  TMonitor.Exit(FSslLock);
end;

function TCrossOpenSslConnection._SslHandshake: Boolean;
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

{ TCrossOpenSslSocket }

constructor TCrossOpenSslSocket.Create(const AIoThreads: Integer);
begin
  inherited;

  TSSLTools.LoadSSL;
  _InitSslCtx;
end;

destructor TCrossOpenSslSocket.Destroy;
begin
  inherited;

  _FreeSslCtx;
  TSSLTools.UnloadSSL;
end;

function TCrossOpenSslSocket.CreateConnection(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType): ICrossConnection;
begin
  Result := TCrossOpenSslConnection.Create(AOwner, AClientSocket, AConnectType);
end;

procedure TCrossOpenSslSocket._InitSslCtx;
var
  LEcdh: PEC_KEY;
begin
  if (FSslCtx <> nil) then Exit;

  FSslCtx := TSSLTools.NewCTX(SSLv23_method());

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

procedure TCrossOpenSslSocket._FreeSslCtx;
begin
  if (FSslCtx = nil) then Exit;

  TSSLTools.FreeCTX(FSslCtx);
end;

procedure TCrossOpenSslSocket.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
begin
  TSSLTools.SetCertificate(FSslCtx, ACertBuf, ACertBufSize);
end;

procedure TCrossOpenSslSocket.SetCertificate(const ACertStr: string);
begin
  TSSLTools.SetCertificate(FSslCtx, ACertStr);
end;

procedure TCrossOpenSslSocket.SetCertificateFile(const ACertFile: string);
begin
  TSSLTools.SetCertificateFile(FSslCtx, ACertFile);
end;

procedure TCrossOpenSslSocket.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer);
begin
  TSSLTools.SetPrivateKey(FSslCtx, APKeyBuf, APKeyBufSize);
end;

procedure TCrossOpenSslSocket.SetPrivateKey(const APKeyStr: string);
begin
  TSSLTools.SetPrivateKey(FSslCtx, APKeyStr);
end;

procedure TCrossOpenSslSocket.SetPrivateKeyFile(const APKeyFile: string);
begin
  TSSLTools.SetPrivateKeyFile(FSslCtx, APKeyFile);
end;

procedure TCrossOpenSslSocket.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnection: TCrossOpenSslConnection;
begin
  LConnection := AConnection as TCrossOpenSslConnection;

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

procedure TCrossOpenSslSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnection: TCrossOpenSslConnection;
  ret, error: Integer;
  LBuffer: TBytesStream;
begin
  LConnection := AConnection as TCrossOpenSslConnection;
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
