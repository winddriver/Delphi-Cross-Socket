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

  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Base,
  Net.OpenSSL;

type
  TCrossOpenSslConnection = class(TCrossSslConnectionBase)
  private
    FSslData: PSSL;
    FBIOIn, FBIOOut: PBIO;

    function _GetSslError(const ARetCode: Integer): Integer;

    procedure _Send(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil);
    procedure _ReadBIOAndSend(const ACallback: TCrossConnectionCallback = nil);
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: THandle;
      const AConnectType: TConnectType; const AConnectedCb: TCrossConnectionCallback); override;
    destructor Destroy; override;
  end;

  /// <remarks>
  ///   若要继承该类, 请重载 LogicXXX, 而不是 TriggerXXX
  /// </remarks>
  TCrossOpenSslSocket = class(TCrossSslSocketBase)
  private const
    SSL_BUF_SIZE = 32768;
  private class threadvar
    FSslInBuf: array [0..SSL_BUF_SIZE-1] of Byte;
  private
    FSslCtx: PSSL_CTX;

    procedure _InitSslCtx;
    procedure _FreeSslCtx;

    procedure _Connected(const AConnection: ICrossConnection);
  protected
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: THandle;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload; override;
    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer); overload; override;
  end;

implementation

{ TCrossOpenSslConnection }

constructor TCrossOpenSslConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: THandle; const AConnectType: TConnectType;
  const AConnectedCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AConnectedCb);

  if Ssl then
  begin
    FSslData := SSL_new(TCrossOpenSslSocket(Owner).FSslCtx);
    FBIOIn := BIO_new(BIO_s_mem());
    FBIOOut := BIO_new(BIO_s_mem());
    SSL_set_bio(FSslData, FBIOIn, FBIOOut);

    if (ConnectType = ctAccept) then
      SSL_set_accept_state(FSslData)   // 服务端连接
    else
      SSL_set_connect_state(FSslData); // 客户端连接
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
  LConnection: ICrossConnection;
  LRetCode: Integer;
begin
  if Ssl then
  begin
    LConnection := Self;

    // 将待发送数据加密
    // SSL_write 默认会将全部数据写入成功才返回,
    // 除非调用 SSL_CTX_set_mode 设置了 SSL_MODE_ENABLE_PARTIAL_WRITE 参数
    // 才会出现部分写入成功即返回的情况。这里并没有设置该参数，所以无需做
    // 部分数据的处理，只需要一次 SSL_Write 调用即可。
    LRetCode := SSL_write(FSslData, ABuffer, ACount);
    if (LRetCode <= 0) then
    begin
      if Assigned(ACallback) then
        ACallback(LConnection, False);
      Exit;
    end;

    _ReadBIOAndSend(ACallback);
  end else
    _Send(ABuffer, ACount, ACallback);
end;

function TCrossOpenSslConnection._GetSslError(const ARetCode: Integer): Integer;
begin
  Result := SSL_get_error(FSslData, ARetCode);
end;

procedure TCrossOpenSslConnection._ReadBIOAndSend(
  const ACallback: TCrossConnectionCallback);
const
  BUF_BLOCK_SIZE = 16384;
var
  LRetCode, LError: Integer;
  LBuffer: TBytesStream;
  P: PByte;
  LCount: Integer;
begin
  LBuffer := TBytesStream.Create;
  LBuffer.Size := BUF_BLOCK_SIZE;
  LCount := 0;

  while True do
  begin
    P := PByte(LBuffer.Memory) + LCount;

    // 从内存 BIO 读取加密后的数据
    LRetCode := BIO_read(FBIOOut, P, BUF_BLOCK_SIZE);
    if (LRetCode <= 0) then
    begin
      LError := _GetSslError(LRetCode);
      Break;
    end;

    Inc(LCount, LRetCode);
    LBuffer.Size := LBuffer.Size + BUF_BLOCK_SIZE;
  end;

  // 如果 BIO 中有需要发出的数据, 则调用 _Send 发送
  if (LCount > 0) then
  begin
    _Send(LBuffer.Memory, LCount,
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        FreeAndNil(LBuffer);

        if Assigned(ACallback) then
          ACallback(AConnection, ASuccess);
      end);
  end else
  begin
    FreeAndNil(LBuffer);
    if Assigned(ACallback) then
      ACallback(Self, False);
  end;
end;

procedure TCrossOpenSslConnection._Send(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  inherited DirectSend(ABuffer, ACount, ACallback);
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
  const AClientSocket: THandle; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossOpenSslConnection.Create(AOwner, AClientSocket, AConnectType, AConnectCb);
end;

procedure TCrossOpenSslSocket._InitSslCtx;
var
  LEcdh: PEC_KEY;
begin
  if (FSslCtx <> nil) then Exit;

  // 创建 SSL/TLS 上下文对象
  // 这里使用 TLS_method(), 该方法会让程序自动协商使用能支持的最高版本 TLS
  FSslCtx := TSSLTools.NewCTX(TLS_method());

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

  {$region '采用新型加密套件进行加密'}
  // 设置 SSL 参数
  SSL_CTX_set_options(FSslCtx,
    // 不使用已经不安全的 SSLv2/SSv3/TLSv1/TLSV1.1
    SSL_OP_NO_SSLv2 or SSL_OP_NO_SSLv3 or SSL_OP_NO_TLSv1 or SSL_OP_NO_TLSv1_1 or
    // 根据服务器偏好选择加密套件
    SSL_OP_CIPHER_SERVER_PREFERENCE
  );

  // 设置加密套件的使用顺序
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

  // 创建一个椭圆曲线密钥对象
  LEcdh := EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  if (LEcdh <> nil) then
  begin
    // 设置 SSL/TLS 上下文临时密钥
    SSL_CTX_set_tmp_ecdh(FSslCtx, LEcdh);
    EC_KEY_free(LEcdh);
  end;
  {$endregion}
end;

procedure TCrossOpenSslSocket._Connected(const AConnection: ICrossConnection);
begin
  inherited TriggerConnected(AConnection);
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
  LRetCode, LError: Integer;
begin
  LConnection := AConnection as TCrossOpenSslConnection;

  if Ssl then
  begin
    LConnection.ConnectStatus := csHandshaking;

    // 开始握手
    // 通常, 客户端连接在这里调用 SSL_do_handshake 就会生成握手数据
    // 而服务端连接, 即便在这里调用了 SSL_do_handshake 也不会生成握手数据
    // 只会返回 SSL_ERROR_WANT_READ, 后面再调用 BIO_read 也会继续返回 SSL_ERROR_WANT_READ
    // 需要在 TriggerReceived 中检查握手状态, 握手没完成就还需要调用 SSL_do_handshake
    LRetCode := SSL_do_handshake(LConnection.FSslData);

    // 这里基本不存在直接返回 1 的情况
    // 因为 SSL 是与内存 BIO 关联的, 而不是 SOCKET
    // 这时候, SSL_do_handshake 会将握手数据写入内存 BIO
    // 后面需要调用 _ReadBIOAndSend 将握手数据发出去
    if (LRetCode = 1) then
      _Connected(AConnection)
    else
    begin
      LError := LConnection._GetSslError(LRetCode);
      LConnection._ReadBIOAndSend(nil);
    end;
  end else
    _Connected(LConnection);
end;

procedure TCrossOpenSslSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
const
  BUF_BLOCK_SIZE = 16384;
var
  LConnection: TCrossOpenSslConnection;
  LRetCode, LError: Integer;
begin
  LConnection := AConnection as TCrossOpenSslConnection;

  if Ssl then
  begin
    // 将收到的加密数据写入内存 BIO, 让 OpenSSL 对其解密
    // 最初收到的数据是握手数据
    // 需要判断握手状态, 然后决定如何使用收到的数据
    LRetCode := BIO_write(LConnection.FBIOIn, ABuf, ALen);
    if (LRetCode <> ALen) then
    begin
      LError := LConnection._GetSslError(LRetCode);
      if SSL_is_fatal_error(LError) then
      begin
        {$IFDEF DEBUG}
        _Log('BIO_write error %d %s', [LError, ssl_error_message(LError)]);
        {$ENDIF}
        LConnection.Close;
      end;
      Exit;
    end;

    // 握手尚未完成
    if not (SSL_is_init_finished(LConnection.FSslData) = TLS_ST_OK) then
    begin
      // 继续握手
      LRetCode := SSL_do_handshake(LConnection.FSslData);

      // 即便上面的 SSL_do_handshake 返回 1
      // BIO 里可能还会有握手的收尾数据需要发送
      // 所以这里无论如何都需要调用一下 _ReadBIOAndSend
      LConnection._ReadBIOAndSend;

      // 握手完成
      if (LRetCode = 1) and (LConnection.ConnectStatus = csHandshaking) then
        _Connected(LConnection);
    end;

    while True do
    begin
      // 读取解密后的数据
      // 如果握手未完成, SSL_read 始终返回 -1
      LRetCode := SSL_read(LConnection.FSslData, @FSslInBuf[0], SSL_BUF_SIZE);

      // 收到了解密后的数据
      if (LRetCode > 0) then
        inherited TriggerReceived(LConnection, @FSslInBuf[0], LRetCode)
      else
        Break;
    end;
  end else
    inherited TriggerReceived(LConnection, ABuf, ALen);
end;

end.
