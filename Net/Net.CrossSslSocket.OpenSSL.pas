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
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Types,
  Net.CrossSslSocket.Base,
  Net.OpenSSL,

  Utils.SyncObjs,
  Utils.Utils;

type

  { TCrossOpenSslConnection }

  TCrossOpenSslConnection = class(TCrossSslConnectionBase)
  private
    FSslData: PSSL;
    FBIOIn, FBIOOut: PBIO;
    FLock: ILock;

    procedure _Lock; inline;
    procedure _Unlock; inline;

    function _BIO_pending: Integer; inline;
    function _BIO_read(Buf: Pointer; Len: Integer): Integer; overload; inline;
    function _BIO_read: TBytes; overload;
    function _BIO_write(Buf: Pointer; Len: Integer): Integer; inline;

    function _SSL_pending: Integer; inline;
    function _SSL_read(Buf: Pointer; Len: Integer): Integer; overload; inline;
    function _SSL_read: TBytes; overload;
    function _SSL_write(Buf: Pointer; Len: Integer): Integer; inline;

    function _SSL_do_handshake: Integer; inline;
    function _SSL_is_init_finished: Integer; inline;

    function _SSL_get_error(const ARetCode: Integer): Integer; inline;
    function _SSL_print_error(const ARetCode: Integer; const ATitle: string): Boolean;

    procedure _Send(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure _Send(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil); overload;
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectedCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

    function GetSslInfo(var ASslInfo: TSslInfo): Boolean; override;
  end;

  /// <remarks>
  ///   若要继承该类, 请重载 LogicXXX, 而不是 TriggerXXX
  /// </remarks>

  { TCrossOpenSslSocket }

  TCrossOpenSslSocket = class(TCrossSslSocketBase)
  private
    FSslCtx: PSSL_CTX;

    procedure _InitSslCtx;
    procedure _FreeSslCtx;

    // https://gitlab.com/freepascal.org/fpc/source/-/issues/40403
    // FPC编译器有BUG: 无法在匿名函数中使用 inherited 正确访问到 Self 上下文对象
    // 不过可以单独定义一个方法去绕过这个BUG, 下面的 _Connected 和 _Received 就是为此定义的
    procedure _Connected(const AConnection: ICrossConnection);
    procedure _Received(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer);
  protected
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload; override;
    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer); overload; override;
  end;

implementation

{ TCrossOpenSslConnection }

constructor TCrossOpenSslConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectedCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectedCb);

  if Ssl then
  begin
    FLock := TLock.Create;
    FSslData := SSL_new(TCrossOpenSslSocket(Owner).FSslCtx);
    FBIOIn := BIO_new(BIO_s_mem());
    FBIOOut := BIO_new(BIO_s_mem());
    SSL_set_bio(FSslData, FBIOIn, FBIOOut);

    if (ConnectType = ctAccept) then
      SSL_set_accept_state(FSslData)   // 服务端连接
    else
    begin
      SSL_set_connect_state(FSslData); // 客户端连接
      SSL_set_tlsext_host_name(FSslData, MarshaledAString(AnsiString(AHost)));
    end;
  end;
end;

destructor TCrossOpenSslConnection.Destroy;
begin
  if Ssl then
  begin
    if (SSL_shutdown(FSslData) = 0) then
      SSL_shutdown(FSslData);
    SSL_free(FSslData);
  end;

  inherited Destroy;
end;

procedure TCrossOpenSslConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  P: PByte;
  LCount, LRetCode: Integer;
  LEncryptedData: TBytes;
begin
  if Ssl then
  begin
    P := PByte(ABuffer);
    LCount := ACount;

    _Lock;
    try
      // 将待发送数据加密
      while (LCount > 0) do
      begin
        // 如果调用 SSL_write 时写入的数据大小超过了SSL记录的大小限制，
        // SSL库会尽力将尽可能多的数据写入到记录中，但仅限于单个记录的最大大小
        // 所以如果数据比较大, 需要分多次写入
        // TLS1.2 记录大小限制为16K
        // TLS1.3 记录大小限制为1.5K
        LRetCode := _SSL_write(P, LCount);
        if (LRetCode <= 0) then
        begin
          if _SSL_print_error(LRetCode, 'SSL_write') then
          begin
            if Assigned(ACallback) then
              ACallback(Self, False);
            Exit;
          end else
            Continue;
        end;

        Dec(LCount, LRetCode);
        Inc(P, LRetCode);
      end;

      LEncryptedData := _BIO_read;
    finally
      _Unlock;
    end;

    _Send(LEncryptedData, ACallback);
  end else
    _Send(ABuffer, ACount, ACallback);
end;

function TCrossOpenSslConnection.GetSslInfo(var ASslInfo: TSslInfo): Boolean;
begin
  Result := TSSLTools.GetSslInfo(FSslData, ASslInfo);
end;

procedure TCrossOpenSslConnection._Lock;
begin
  FLock.Enter;
end;

procedure TCrossOpenSslConnection._Unlock;
begin
  FLock.Leave;
end;

function TCrossOpenSslConnection._BIO_pending: Integer;
begin
  Result := BIO_pending(FBIOOut);
end;

function TCrossOpenSslConnection._BIO_read(Buf: Pointer; Len: Integer): Integer;
begin
  Result := BIO_read(FBIOOut, Buf, Len);
end;

function TCrossOpenSslConnection._BIO_read: TBytes;
var
  LReadedCount, LBlockSize, LRetCode: Integer;
  P: PByte;
begin
  LReadedCount := 0;
  Result := nil;

  while True do
  begin
    LBlockSize := _BIO_pending;
    if (LBlockSize <= 0) then Break;

    SetLength(Result, Length(Result) + LBlockSize);
    P := PByte(@Result[0]) + LReadedCount;

    // 从内存 BIO 读取加密后的数据
    LRetCode := _BIO_read(P, LBlockSize);

    if (LRetCode <= 0) then
    begin
      _SSL_print_error(LRetCode, 'BIO_read');
      Break;
    end;

    Inc(LReadedCount, LRetCode);
  end;
end;

function TCrossOpenSslConnection._BIO_write(Buf: Pointer; Len: Integer
  ): Integer;
begin
  Result := BIO_write(FBIOIn, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_pending: Integer;
begin
  Result := SSL_pending(FSslData);
end;

function TCrossOpenSslConnection._SSL_read(Buf: Pointer; Len: Integer): Integer;
begin
  Result := SSL_read(FSslData, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_read: TBytes;
const
  BLOCK_SIZE = 4096;
var
  LReadedCount, LBlockSize, LRetCode: Integer;
  P: PByte;
begin
  LReadedCount := 0;
  Result := nil;

  while True do
  begin
    if (LReadedCount >= Length(Result)) then
      SetLength(Result, Length(Result) + BLOCK_SIZE);

    P := PByte(@Result[0]) + LReadedCount;

    LBlockSize := Length(Result) - LReadedCount;

    // 读取解密后的数据
    // 如果握手未完成, SSL_read 始终返回 -1
    LRetCode := _SSL_read(P, LBlockSize);

    if (LRetCode <= 0) then
    begin
      _SSL_print_error(LRetCode, 'SSL_read');
      Break;
    end;

    Inc(LReadedCount, LRetCode);
  end;

  SetLength(Result, LReadedCount);
end;

function TCrossOpenSslConnection._SSL_write(Buf: Pointer; Len: Integer
  ): Integer;
begin
  Result := SSL_write(FSslData, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_do_handshake: Integer;
begin
  Result := SSL_do_handshake(FSslData);
end;

function TCrossOpenSslConnection._SSL_is_init_finished: Integer;
begin
  Result := SSL_is_init_finished(FSslData);
end;

function TCrossOpenSslConnection._SSL_get_error(const ARetCode: Integer): Integer;
begin
  Result := SSL_get_error(FSslData, ARetCode);
end;

function TCrossOpenSslConnection._SSL_print_error(const ARetCode: Integer; const ATitle: string): Boolean;
var
  LRet: Integer;
  LError: Cardinal;
begin
  LRet := _SSL_get_error(ARetCode);
  Result := SSL_is_fatal_error(LRet);
  if Result then
  begin
    while True do
    begin
      LError := ERR_get_error();
      if (LError = 0) then Break;

      _Log(ATitle + ' error %d %s', [LError, SSL_error_message(LError)]);
    end;
  end;
end;

procedure TCrossOpenSslConnection._Send(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  inherited DirectSend(ABuffer, ACount, ACallback);
end;

procedure TCrossOpenSslConnection._Send(const ABytes: TBytes;
  const ACallback: TCrossConnectionCallback);
var
  LBytes: TBytes;
begin
  if (ABytes = nil) then
  begin
    if Assigned(ACallback) then
      ACallback(Self, False);
    Exit;
  end;

  LBytes := ABytes;
  _Send(@LBytes[0], Length(LBytes),
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LBytes := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

{ TCrossOpenSslSocket }

constructor TCrossOpenSslSocket.Create(const AIoThreads: Integer; const ASsl: Boolean);
begin
  inherited Create(AIoThreads, ASsl);

  if Ssl then
  begin
    TSSLTools.LoadSSL;
    _InitSslCtx;
  end;
end;

destructor TCrossOpenSslSocket.Destroy;
begin
  inherited Destroy;

  if Ssl then
  begin
    _FreeSslCtx;
    TSSLTools.UnloadSSL;
  end;
end;

function TCrossOpenSslSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossOpenSslConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

procedure TCrossOpenSslSocket._InitSslCtx;
begin
  if (FSslCtx <> nil) then Exit;

  // 创建 SSL/TLS 上下文对象
  // 这里使用 TLS_method(), 该方法会让程序自动协商使用能支持的最高版本 TLS
  FSslCtx := TSSLTools.NewCTX(TLS_method());

  SSL_CTX_set_min_proto_version(FSslCtx, TLS1_2_VERSION);
  SSL_CTX_set_max_proto_version(FSslCtx, TLS1_3_VERSION);

  // 设置证书验证方式
  // SSL_VERIFY_NONE 不进行证书验证，即不验证服务器的证书
  // SSL_VERIFY_PEER 验证服务器的证书，但不强制要求证书的合法性（即使证书验证失败，仍然允许连接）。
  // SSL_VERIFY_FAIL_IF_NO_PEER_CERT 要求服务器提供证书，并验证其合法性。如果服务器未提供证书或证书验证失败，连接将失败。
  // SSL_VERIFY_CLIENT_ONCE 仅对客户端进行一次证书验证，不进行追加验证。通常与SSL_VERIFY_PEER一起使用。
  // 这些选项可以根据需要组合使用，以满足特定的证书验证需求。
  SSL_CTX_set_verify(FSslCtx, SSL_VERIFY_NONE, nil);

  // 设置工作模式
  // SSL_MODE_ENABLE_PARTIAL_WRITE：启用部分写入模式。在此模式下，SSL_write 可以部分写入数据而无需阻塞，适用于非阻塞I/O操作。
  // SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER：接受可移动的写缓冲区。在此模式下，可以使用不同的写缓冲区重复调用 SSL_write，而无需重新初始化连接。
  // SSL_MODE_AUTO_RETRY：自动重试。在此模式下，OpenSSL 会自动处理可重试的操作，例如握手操作，而无需应用程序显式重试。
  // SSL_MODE_NO_AUTO_CHAIN：禁用自动证书链。在此模式下，OpenSSL 不会尝试自动构建证书链，需要应用程序显式设置证书链。
  // SSL_MODE_RELEASE_BUFFERS：释放缓冲区。在此模式下，SSL_write 操作完成后，OpenSSL 会立即释放缓冲区，而不是等待更多数据。
  // SSL_MODE_ENABLE_FALSE_START：启用False Start模式。False Start 是一种优化机制，允许客户端在不等待服务器确认的情况下开始发送数据，以加速连接建立。
  // 这些模式选项可以根据需要进行组合使用，以满足特定的SSL/TLS连接需求。
  SSL_CTX_set_mode(FSslCtx, SSL_MODE_AUTO_RETRY);

  // 设置 SSL 参数
  SSL_CTX_set_options(FSslCtx,
    SSL_CTX_get_options(FSslCtx) or
    // 根据服务器偏好选择加密套件
    SSL_OP_CIPHER_SERVER_PREFERENCE or
    // 允许连接到不支持RI的旧服务器
    SSL_OP_LEGACY_SERVER_CONNECT or
    // 允许不安全的旧式重新协商(兼容工商银行ch5.dcep.ccb.com:443)
    SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION);

  {$region '采用新型加密套件进行加密'}
  // TLSv1.3及以上加密套件设置(OpenSSL 1.1.1+)
  SSL_CTX_set_ciphersuites(FSslCtx,
    'TLS_AES_256_GCM_SHA384' +
    ':TLS_CHACHA20_POLY1305_SHA256' +
    ':TLS_AES_128_GCM_SHA256' +
    ':TLS_AES_128_CCM_SHA256' +
    ':TLS_AES_128_CCM_8_SHA256'
  );

  // TLS 1.2及以下加密套件设置
  SSL_CTX_set_cipher_list(FSslCtx,
    // from nodejs(node_constants.h)
    // #define DEFAULT_CIPHER_LIST_CORE
    'TLS_AES_256_GCM_SHA384:' +
    'TLS_CHACHA20_POLY1305_SHA256:' +
    'TLS_AES_128_GCM_SHA256:' +
    'ECDHE-RSA-AES128-GCM-SHA256:' +
    'ECDHE-ECDSA-AES128-GCM-SHA256:' +
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
  {$endregion}
end;

procedure TCrossOpenSslSocket._Connected(const AConnection: ICrossConnection);
begin
  inherited TriggerConnected(AConnection);
end;

procedure TCrossOpenSslSocket._Received(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  inherited TriggerReceived(AConnection, ABuf, ALen);
end;

procedure TCrossOpenSslSocket._FreeSslCtx;
begin
  if (FSslCtx = nil) then Exit;

  TSSLTools.FreeCTX(FSslCtx);
end;

procedure TCrossOpenSslSocket.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
begin
  if Ssl then
    TSSLTools.SetCertificate(FSslCtx, ACertBuf, ACertBufSize);
end;

procedure TCrossOpenSslSocket.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer);
begin
  if Ssl then
    TSSLTools.SetPrivateKey(FSslCtx, APKeyBuf, APKeyBufSize);
end;

procedure TCrossOpenSslSocket.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnection: TCrossOpenSslConnection;
  LRetCode: Integer;
  LHandshakeData: TBytes;
begin
  LConnection := AConnection as TCrossOpenSslConnection;

  if Ssl then
  begin
    LHandshakeData := nil;

    LConnection._Lock;
    try
      LConnection.ConnectStatus := csHandshaking;

      // 开始握手
      // 通常, 客户端连接在这里调用 SSL_do_handshake 就会生成握手数据
      // 而服务端连接, 即便在这里调用了 SSL_do_handshake 也不会生成握手数据
      // 只会返回 SSL_ERROR_WANT_READ, 后面再调用 BIO_read 也会继续返回 SSL_ERROR_WANT_READ
      // 需要在 TriggerReceived 中检查握手状态, 握手没完成就还需要调用 SSL_do_handshake
      LRetCode := LConnection._SSL_do_handshake;
      if (LRetCode <> 1) then
        LConnection._SSL_print_error(LRetCode, 'SSL_do_handshake(TriggerConnected)');

      LHandshakeData := LConnection._BIO_read;
    finally
      LConnection._Unlock;
    end;

    if (LHandshakeData <> nil) then
      LConnection._Send(LHandshakeData);
  end else
    _Connected(LConnection);
end;

procedure TCrossOpenSslSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnectionObj: TCrossOpenSslConnection;
  LRetCode: Integer;
  LTriggerConnected: Boolean;
  LDecryptedData, LHandshakeData: TBytes;
begin
  if Ssl then
  begin
    LConnectionObj := AConnection as TCrossOpenSslConnection;
    LTriggerConnected := False;
    LDecryptedData := nil;
    LHandshakeData := nil;

    LConnectionObj._Lock;
    try
      // 将收到的加密数据写入内存 BIO, 让 OpenSSL 对其解密
      // 最初收到的数据是握手数据
      // 需要判断握手状态, 然后决定如何使用收到的数据
      LRetCode := LConnectionObj._BIO_write(ABuf, ALen);
      if (LRetCode <> ALen) then
      begin
        if LConnectionObj._SSL_print_error(LRetCode, 'BIO_write') then
          LConnectionObj.Close;
        Exit;
      end;

      // 握手完成
      if (LConnectionObj._SSL_is_init_finished = TLS_ST_OK) then
      begin
        if (LConnectionObj.ConnectStatus = csHandshaking) then
          LTriggerConnected := True;

        // 读取解密后的数据
        LDecryptedData := LConnectionObj._SSL_read;
      end else
      if (LConnectionObj.ConnectStatus = csHandshaking) then
      begin
        // 继续握手
        LRetCode := LConnectionObj._SSL_do_handshake;

        if (LRetCode <> 1) then
          LConnectionObj._SSL_print_error(LRetCode, 'SSL_do_handshake(TriggerReceived)');

        // 读取握手数据
        LHandshakeData := LConnectionObj._BIO_read;

        // 如果握手完成
        // 读取解密后的数据
        if (LRetCode = 1) then
        begin
          LTriggerConnected := True;
          LDecryptedData := LConnectionObj._SSL_read;
        end;
      end;
    finally
      LConnectionObj._Unlock;
    end;

    // 有握手数据
    if (LHandshakeData <> nil) then
    begin
      // 先把握手数据发出去再触发连接事件和数据接收事件
      LConnectionObj._Send(LHandshakeData,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          // 握手完成, 触发已连接事件
          if LTriggerConnected then
            _Connected(AConnection);

          // 收到了解密后的数据
          if (LDecryptedData <> nil) then
          begin
            _Received(AConnection, @LDecryptedData[0], Length(LDecryptedData));
            LDecryptedData := nil;
          end;
        end);
    end else
    begin
      // 握手完成, 触发已连接事件
      if LTriggerConnected then
        _Connected(AConnection);

      // 收到了解密后的数据
      if (LDecryptedData <> nil) then
        _Received(AConnection, @LDecryptedData[0], Length(LDecryptedData));
    end;
  end else
    _Received(AConnection, ABuf, ALen);
end;

end.
