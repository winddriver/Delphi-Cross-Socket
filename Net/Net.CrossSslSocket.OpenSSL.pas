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
  Generics.Collections,

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
  private type
    // pending write 队列条目: 零拷贝, 仅保存上层传入的指针.
    // 调用方需保证 Buf 在 Callback 触发前持续有效 (异步框架契约).
    // **注意**: Callback 的 AConnection 参数在连接析构时会被传 nil
    //   (避免 refcount 环), 调用方实现 Callback 时必须判空.
    TPendingWrite = record
      Buf: PByte;
      Len: Integer;
      Callback: TCrossConnectionCallback;
    end;
  private
    FSslData: PSSL;
    FBIOIn, FBIOOut: PBIO;
    FLock: ILock;
    // 握手阶段累计输入字节数: 仅在 csHandshaking 时累加, 超过
    // MAX_HANDSHAKE_RECV_BYTES 即视作 DoS 主动 fatal close. 防御
    // "反复发送握手字节耗费 SSL 状态机"型 DoS.
    FHandshakeRecvBytes: Int64;

    // pending write 队列: BIO 空 + WANT_* 时把待写明文挂起,
    // 等 TriggerReceived 推进 SSL 状态后由 _PumpPendingWrites 唤醒.
    // FIFO 顺序保证 SSL 状态机不会被穿插数据弄乱.
    FPendingWrites: TQueue<TPendingWrite>;
    FPendingBytes: Int64;       // 已挂起明文字节数 (用于背压判定)
    FMaxPendingBytes: Int64;    // 上限 (从 Owner 复制, 0 = 不限)
    FPumping: Boolean;          // 正在 pump 标志 (单 pumper 不变量)

    // 注意: _SslLock/_SslUnlock 是 SSL 层独立锁, 非基类 _Lock/_Unlock.
    // 基类通过 _LockRecv/_LockSent 保护 IO 路径, 不经过这里.
    procedure _SslLock; inline;
    procedure _SslUnlock; inline;

    function _BIO_pending: Integer; inline;
    function _BIO_read(Buf: Pointer; Len: Integer): Integer; inline;
    function _BIO_read_all: TBytes; overload;
    function _BIO_write(Buf: Pointer; Len: Integer): Integer; inline;

    function _SSL_read(Buf: Pointer; Len: Integer): Integer; overload; inline;
    function _SSL_read_all: TBytes; overload;
    function _SSL_write(Buf: Pointer; Len: Integer): Integer; inline;

    function _SSL_do_handshake: Integer; inline;
    function _SSL_is_init_finished: Integer; inline;

    function _SSL_get_error(const ARetCode: Integer): Integer; inline;
    function _SSL_handle_error(const ARetCode: Integer; const AOperation: string;
      out AErrCode: Integer): Boolean; overload;
    function _SSL_handle_error(const ARetCode: Integer; const AOperation: string): Boolean; overload;

    // SSL数据发送 (薄入口: 检查 pending queue, 否则交给 _SslSendInner 推进)
    procedure _SslSend(const ABuf: PByte; const ALen: Integer;
      const ACallback: TCrossConnectionCallback);

    // _SslSend 主体: 状态机 + CPS 循环, BIO 空 + WANT_* 时入队挂起
    procedure _SslSendInner(const ABuf: PByte; const ALen: Integer;
      const ACallback: TCrossConnectionCallback);

    // 尝试入队 pending write (必须在 FLock 内调用).
    // 返回 True=已入队 / False=背压拒绝 (调用方应 fail callback).
    function _TryEnqueuePendingWrite(const ABuf: PByte; const ALen: Integer;
      const ACallback: TCrossConnectionCallback): Boolean;

    // 唤醒 pending write 队列首条目, 推进完成后由 callback 触发下一轮 pump.
    // 由 TriggerReceived 在 SSL 状态推进 (BIO_write/SSL_read/握手) 后调用.
    procedure _PumpPendingWrites;

    // 把 queue 中所有挂起条目以 fail 通知上层 (析构 / pump 推进失败时调用),
    // 调用方需保证当前线程不持有 FLock.
    // AConnection 用作 callback 的第一参数: 析构路径传 nil (避免引用计数环)
    // 其他路径传 Self as ICrossConnection.
    procedure _DrainPendingWritesAsFailed(const AConnection: ICrossConnection);

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
    procedure _FinishHandshakeProgress(const ASendSuccess: Boolean;
      const AConnectionObj: TCrossOpenSslConnection;
      const ATriggerConnected: Boolean; var ADecryptedData: TBytes;
      const AFatal: Boolean);
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

{$IFDEF CROSS_OPENSSL_SELFTEST}
function CrossOpenSslSelfTest_PendingCallbackExceptionDoesNotStall(
  out AErrMsg: string): Boolean;
function CrossOpenSslSelfTest_HandshakeSendFailureDoesNotPromote(
  out AErrMsg: string): Boolean;
{$ENDIF}

implementation

const
  /// <summary>
  ///   SSL 握手累计输入字节上限.
  /// </summary>
  /// <remarks>
  ///   TLS 1.3 完整握手 (含证书链 + ALPN + SNI) 通常 8-32 KB.
  ///   含客户端证书的双向 mTLS 极端场景 < 64 KB.
  ///   设 128 KB 留足保护合法场景, 同时阻断"反复发送握手字节耗费 SSL 状态机"
  ///   类的 DoS 攻击 (攻击者不断发送数 KB 数据让服务端反复运行 SSL_do_handshake).
  /// </remarks>
  MAX_HANDSHAKE_RECV_BYTES = 128 * 1024;

{$IFDEF CROSS_OPENSSL_SELFTEST}
function CrossOpenSslSelfTest_PendingCallbackExceptionDoesNotStall(
  out AErrMsg: string): Boolean;
var
  LSocket: TCrossOpenSslSocket;
  LConnection: TCrossOpenSslConnection;
  LConnectionIntf: ICrossConnection;
  LItem: TCrossOpenSslConnection.TPendingWrite;
  LCallbackCount: Integer;
begin
  Result := False;
  AErrMsg := '';
  LSocket := TCrossOpenSslSocket.Create(0, False);
  try
    LConnection := TCrossOpenSslConnection.Create(LSocket, INVALID_SOCKET,
      ctConnect, '', nil);
    LConnectionIntf := LConnection as ICrossConnection;
    LConnection.FLock := TLock.Create;
    LConnection.FPendingWrites := TQueue<TCrossOpenSslConnection.TPendingWrite>.Create;
    try
      try
        LItem.Buf := nil;
        LItem.Len := 0;
        LCallbackCount := 0;
        LItem.Callback :=
          procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
          begin
            Inc(LCallbackCount);
            raise Exception.Create('test callback exception');
          end;
        LConnection.FPendingWrites.Enqueue(LItem);

        LConnection._PumpPendingWrites;

        if LCallbackCount <> 1 then
        begin
          AErrMsg := Format('pending callback expected once, got %d',
            [LCallbackCount]);
          Exit;
        end;

        if LConnection.FPumping then
        begin
          AErrMsg := 'FPumping remained True after callback exception';
          Exit;
        end;

        if LConnection.FPendingWrites.Count <> 0 then
        begin
          AErrMsg := 'pending queue was not drained after callback exception';
          Exit;
        end;

        Result := True;
      finally
        LConnection.FPendingWrites.Free;
        LConnection.FPendingWrites := nil;
      end;
    finally
      LConnectionIntf := nil;
    end;
  finally
    LSocket.Free;
  end;
end;

function CrossOpenSslSelfTest_HandshakeSendFailureDoesNotPromote(
  out AErrMsg: string): Boolean;
var
  LSocket: TCrossOpenSslSocket;
  LConnection: TCrossOpenSslConnection;
  LConnectionIntf: ICrossConnection;
  LDecryptedData: TBytes;
begin
  Result := False;
  AErrMsg := '';
  LSocket := TCrossOpenSslSocket.Create(0, False);
  try
    LConnection := TCrossOpenSslConnection.Create(LSocket, INVALID_SOCKET,
      ctConnect, '', nil);
    LConnectionIntf := LConnection as ICrossConnection;
    try
      SetLength(LDecryptedData, 1);
      LSocket._FinishHandshakeProgress(False, LConnection, True,
        LDecryptedData, False);

      if LConnection.ConnectStatus <> csClosed then
      begin
        AErrMsg := 'connection was not closed after handshake send failure';
        Exit;
      end;

      if LDecryptedData <> nil then
      begin
        AErrMsg := 'decrypted data was retained after handshake send failure';
        Exit;
      end;

      Result := True;
    finally
      LConnectionIntf := nil;
    end;
  finally
    LSocket.Free;
  end;
end;
{$ENDIF}

{ TCrossOpenSslConnection }

constructor TCrossOpenSslConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectedCb: TCrossConnectionCallback);
var
  LHostAnsi: AnsiString;
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectedCb);

  if Ssl then
  begin
    FLock := TLock.Create;

    FSslData := SSL_new(TCrossOpenSslSocket(Owner).FSslCtx);
    if (FSslData = nil) then
      raise ECrossSocket.Create('SSL_new failed');

    FBIOIn := BIO_new(BIO_s_mem());
    FBIOOut := BIO_new(BIO_s_mem());
    if (FBIOIn = nil) or (FBIOOut = nil) then
    begin
      if (FBIOIn <> nil) then BIO_free(FBIOIn);
      if (FBIOOut <> nil) then BIO_free(FBIOOut);
      SSL_free(FSslData);
      FSslData := nil;  // 避免 Destroy 中二次释放
      raise ECrossSocket.Create('BIO_new failed');
    end;

    SSL_set_bio(FSslData, FBIOIn, FBIOOut);

    FPendingWrites := TQueue<TPendingWrite>.Create;
    FMaxPendingBytes := TCrossOpenSslSocket(AOwner).SslMaxPendingWriteBytes;

    if (ConnectType = ctAccept) then
      SSL_set_accept_state(FSslData)   // 服务端连接
    else
    begin
      SSL_set_connect_state(FSslData); // 客户端连接
      LHostAnsi := AnsiString(AHost);
      SSL_set_tlsext_host_name(FSslData, MarshaledAString(LHostAnsi));
    end;
  end;
end;

destructor TCrossOpenSslConnection.Destroy;
begin
  if Ssl then
  begin
    // pending writes 析构 drain: 把所有挂起 callback 以 fail 通知上层,
    // 上层闭包持有的 TBytes 才能释放 (零拷贝契约). 传 nil connection 避免
    // (Self as ICrossConnection) 引起的 refcount 环 → 二次析构.
    if (FPendingWrites <> nil) then
    begin
      _DrainPendingWritesAsFailed(nil);
      FPendingWrites.Free;
    end;

    if (FSslData <> nil) then
    begin
      if (SSL_shutdown(FSslData) = 0) then
        SSL_shutdown(FSslData);
      SSL_free(FSslData);
      FSslData := nil;
    end;
  end;

  inherited Destroy;
end;

procedure TCrossOpenSslConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  if Ssl then
    _SslSend(ABuffer, ACount, ACallback)
  else
    _Send(ABuffer, ACount, ACallback);
end;

function TCrossOpenSslConnection.GetSslInfo(var ASslInfo: TSslInfo): Boolean;
begin
  Result := TSSLTools.GetSslInfo(FSslData, ASslInfo);
end;

procedure TCrossOpenSslConnection._SslLock;
begin
  FLock.Enter;
end;

procedure TCrossOpenSslConnection._SslUnlock;
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

function TCrossOpenSslConnection._BIO_read_all: TBytes;
const
  INITIAL_BUF_SIZE = 16384; // 初始缓冲区大小 16KB
  MAX_BUF_INCREMENT = 65536; // 最大增量 64KB
var
  LReadedCount, LBlockSize, LRetCode: Integer;
  LFreeSpace, LNewSize: Integer;
  P: PByte;
begin
  LReadedCount := 0;
  // 初始分配合理大小的缓冲区
  SetLength(Result, INITIAL_BUF_SIZE);

  while True do
  begin
    // 获取当前可读数据量
    LBlockSize := _BIO_pending;
    if (LBlockSize <= 0) then Break;

    // 计算缓冲区剩余空间
    LFreeSpace := Length(Result) - LReadedCount;

    // 动态扩展缓冲区(按需增长)
    if (LFreeSpace < LBlockSize) then
    begin
      // 指数增长策略: 每次翻倍, 上限为 MAX_BUF_INCREMENT
      LNewSize := Length(Result) * 2;
      if (LNewSize - LReadedCount < LBlockSize) then
        LNewSize := LReadedCount + LBlockSize + MAX_BUF_INCREMENT
      else if (LNewSize > Length(Result) + MAX_BUF_INCREMENT) then
        LNewSize := Length(Result) + MAX_BUF_INCREMENT;
      SetLength(Result, LNewSize);
    end;

    // 指向缓冲区当前写入位置
    P := PByte(@Result[0]) + LReadedCount;

    // 从 BIO 读取数据(最多读取 LBlockSize)
    LRetCode := _BIO_read(P, LBlockSize);

    // BIO_read 返回 <= 0 表示没有更多数据可读
    // 对于内存 BIO，这是正常情况，不需要错误处理
    if (LRetCode <= 0) then
      Break;

    // 更新已读取计数
    Inc(LReadedCount, LRetCode);
  end;

  // 调整数组至实际数据大小
  SetLength(Result, LReadedCount);
end;

function TCrossOpenSslConnection._BIO_write(Buf: Pointer; Len: Integer
  ): Integer;
begin
  Result := BIO_write(FBIOIn, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_read(Buf: Pointer; Len: Integer): Integer;
begin
  Result := SSL_read(FSslData, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_read_all: TBytes;
const
  INITIAL_BUF_SIZE = 16384;  // 初始缓冲区 16KB
  MAX_BUF_INCREMENT = 65536; // 最大增量 64KB
var
  LReadedCount, LRetCode: Integer;
  LFreeSpace, LNewSize: Integer;
  P: PByte;
begin
  LReadedCount := 0;
  // 预分配初始缓冲区
  SetLength(Result, INITIAL_BUF_SIZE);

  while True do
  begin
    // 计算缓冲区剩余空间
    LFreeSpace := Length(Result) - LReadedCount;

    // 动态扩展缓冲区(按需增长)
    if (LFreeSpace < 1024) then  // 预留安全空间
    begin
      // 指数增长策略: 每次翻倍, 上限为 MAX_BUF_INCREMENT
      LNewSize := Length(Result) * 2;
      if (LNewSize > Length(Result) + MAX_BUF_INCREMENT) then
        LNewSize := Length(Result) + MAX_BUF_INCREMENT;
      SetLength(Result, LNewSize);
      LFreeSpace := Length(Result) - LReadedCount;
    end;

    // 指向缓冲区当前写入位置
    P := PByte(@Result[0]) + LReadedCount;

    // 读取数据
    LRetCode := _SSL_read(P, LFreeSpace);

    // 直到读不到数据为止
    if (LRetCode <= 0) then
    begin
      // 随便记录一下, 不一定有错误
      _SSL_handle_error(LRetCode, 'SSL_read');
      Break;
    end;

    // 更新已读取计数
    Inc(LReadedCount, LRetCode);
  end;

  // 调整数组至实际数据大小
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

function TCrossOpenSslConnection._SSL_handle_error(const ARetCode: Integer;
  const AOperation: string; out AErrCode: Integer): Boolean;
var
  LError: Cardinal;
begin
  AErrCode := _SSL_get_error(ARetCode);
  Result := SSL_is_fatal_error(AErrCode);
  if Result then
  begin
    while True do
    begin
      LError := ERR_get_error();
      if (LError = 0) then Break;

      _Log(AOperation + ' error %d %s', [LError, SSL_error_message(LError)]);
    end;
  end;
end;

function TCrossOpenSslConnection._SSL_handle_error(const ARetCode: Integer;
  const AOperation: string): Boolean;
var
  LError: Integer;
begin
  Result := _SSL_handle_error(ARetCode, AOperation, LError);
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

function TCrossOpenSslConnection._TryEnqueuePendingWrite(const ABuf: PByte;
  const ALen: Integer; const ACallback: TCrossConnectionCallback): Boolean;
// 尝试入队 pending write, 必须在 FLock 内调用.
// 返回 True=已入队 / False=背压拒绝 (调用方应 fail callback).
//
// 零拷贝: 仅保存 PByte 指针, 上层调用方需保证 callback 触发前 buffer 有效
// (异步框架契约, 已被 _Send(TBytes) 重载等所遵循).
var
  LItem: TPendingWrite;
begin
  // 背压: 超限则不入队, 由调用方 fail callback (上层闭包持有的 TBytes 可释放)
  if (FMaxPendingBytes > 0)
    and (FPendingBytes + ALen > FMaxPendingBytes) then
    Exit(False);

  LItem.Buf := ABuf;
  LItem.Len := ALen;
  LItem.Callback := ACallback;
  FPendingWrites.Enqueue(LItem);
  Inc(FPendingBytes, ALen);
  Result := True;
end;

procedure TCrossOpenSslConnection._SslSend(const ABuf: PByte;
  const ALen: Integer; const ACallback: TCrossConnectionCallback);
// SSL 数据写入薄入口: 检查 pending queue 顺序约束, 否则直接转 _SslSendInner.
//
// 关键不变量: 若 queue 中已有挂起条目 (或正在 pump), 新调用必须排队保持 FIFO,
// 否则会与 pumping 中的数据穿插, 弄乱 SSL 状态机.
//
// 零拷贝: 仅保存 PByte 指针, 上层调用方需保证 callback 触发前 buffer 有效
// (异步框架契约, 已被 _Send(TBytes) 重载等所遵循).
var
  LConnection: ICrossConnection;
  LEnqueued, LBackpressureFail: Boolean;
begin
  LConnection := Self as ICrossConnection;

  if (ALen <= 0) then
  begin
    if Assigned(ACallback) then
      ACallback(LConnection, True);
    Exit;
  end;

  // 已有挂起或 pumping 中: 排队保持 FIFO, 不与 pumping 数据竞争 SSL 状态
  LEnqueued := False;
  LBackpressureFail := False;

  _SslLock;
  try
    if (FPendingWrites <> nil)
      and ((FPendingWrites.Count > 0) or FPumping) then
    begin
      LEnqueued := _TryEnqueuePendingWrite(ABuf, ALen, ACallback);
      LBackpressureFail := not LEnqueued;
    end;
  finally
    _SslUnlock;
  end;

  if LBackpressureFail then
  begin
    if Assigned(ACallback) then
      ACallback(LConnection, False);
    Exit;
  end;

  if LEnqueued then Exit;  // 等 _PumpPendingWrites 唤醒

  _SslSendInner(ABuf, ALen, ACallback);
end;

procedure TCrossOpenSslConnection._SslSendInner(const ABuf: PByte;
  const ALen: Integer; const ACallback: TCrossConnectionCallback);
// SSL 数据写入主体: 状态机 + CPS 实现.
//
// 设计要点:
//   1. while 真循环替代锁内同步递归:
//      - BIO 空 + 部分写入: Continue 推进, 不再加锁、不再递归.
//      - BIO 空 + WANT_READ/WANT_WRITE: 入队挂起 (步骤 5 实现), 等
//        TriggerReceived 推进 SSL 状态后由 _PumpPendingWrites 唤醒.
//   2. _Send 异步调用 (callback 跨线程触发) 通过 CPS 处理;
//      发起 _Send 前先 _SslUnlock, 破除"锁-网络嵌套".
var
  LConnection: ICrossConnection;
  LCurBuf: PByte;
  LRemaining: Integer;
  LWritten, LErrCode: Integer;
  LEncryptedData: TBytes;
  LFatal, LBackpressureFail: Boolean;
begin
  LConnection := Self as ICrossConnection;

  if (ALen <= 0) then
  begin
    if Assigned(ACallback) then
      ACallback(LConnection, True);
    Exit;
  end;

  LCurBuf := ABuf;
  LRemaining := ALen;

  while (LRemaining > 0) do
  begin
    LEncryptedData := nil;
    LFatal := False;
    LErrCode := 0;

    // ---- 锁内: 仅做 SSL/BIO 状态机操作 ----
    _SslLock;
    try
      LWritten := _SSL_write(LCurBuf, LRemaining);

      if (LWritten > 0) then
      begin
        // 成功写入 (部分或全部), 取出加密后数据准备发送
        LEncryptedData := _BIO_read_all;
      end else
      begin
        // SSL_write 返回 <= 0
        if _SSL_handle_error(LWritten, 'SSL_write', LErrCode) then
          LFatal := True
        else if (LErrCode in [SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE]) then
          // 可重试错误: BIO 仍可能有待 flush 的数据
          LEncryptedData := _BIO_read_all
        else
          // 未识别错误码视为致命
          LFatal := True;
      end;
    finally
      _SslUnlock;
    end;

    // ---- 锁外: 处理结果 / 发起异步 IO ----
    if LFatal then
    begin
      if Assigned(ACallback) then
        ACallback(LConnection, False);
      Exit;
    end;

    if (LEncryptedData <> nil) then
    begin
      // 锁外发起异步发送, TBytes 重载会持有缓冲区到 callback 触发
      _Send(LEncryptedData,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          if not ASuccess then
          begin
            if Assigned(ACallback) then
              ACallback(AConnection, False);
            Exit;
          end;

          if (LWritten > 0) then
          begin
            if (LWritten < LRemaining) then
              // 部分写入, CPS 推进剩余数据 (新栈帧, 非同步递归)
              _SslSend(LCurBuf + LWritten, LRemaining - LWritten, ACallback)
            else if Assigned(ACallback) then
              ACallback(AConnection, True);
          end else
          begin
            // LWritten <= 0 (WANT_READ/WANT_WRITE) + BIO 已 flush:
            //   BIO flush 后 OpenSSL 内部状态可能变化 (例如 WANT_WRITE 的
            //   底层 buffer 被释放), 重试 _SslSend 有机会继续推进.
            //   这是合法的 CPS 递归 (异步 callback, 新栈帧):
            //     若再次 WANT_* + BIO 非空 → 再次 _Send + 重试, 终究会因
            //     BIO 空 + WANT_* 走到主循环失败分支退出, 不会无限递归.
            _SslSend(LCurBuf, LRemaining, ACallback);
          end;
        end);
      Exit; // 等待异步 callback
    end;

    // ---- BIO 空的情况 ----
    if (LWritten > 0) then
    begin
      // 部分写入但 BIO 无输出 (罕见但合法), 真循环推进, 不再加锁递归.
      Inc(LCurBuf, LWritten);
      Dec(LRemaining, LWritten);
      Continue;
    end;

    // BIO 空 + WANT_READ/WANT_WRITE: 真挂起场景.
    // 同步重试无效 (OpenSSL 状态未变化), 必须等 TriggerReceived 注入新数据 →
    // BIO_write 推进 SSL 状态后, _PumpPendingWrites 才能解除阻塞.
    //
    // 入队规则: 零拷贝, 仅保存 (LCurBuf, LRemaining, ACallback);
    // 上层调用方需保证 buffer 在 callback 前持续有效 (异步框架契约).
    // 背压: FPendingBytes 超 FMaxPendingBytes 则不入队, 直接 fail callback.
    _SslLock;
    try
      LBackpressureFail := not _TryEnqueuePendingWrite(LCurBuf, LRemaining, ACallback);
    finally
      _SslUnlock;
    end;

    if LBackpressureFail then
    begin
      if Assigned(ACallback) then
        ACallback(LConnection, False);
    end;
    // 否则: 已入队, 等 _PumpPendingWrites 唤醒后触发 callback
    Exit;
  end;

  // LRemaining = 0, 全部数据已写入
  if Assigned(ACallback) then
    ACallback(LConnection, True);
end;

procedure TCrossOpenSslConnection._PumpPendingWrites;
// 唤醒 pending write 队列首条目, 由 TriggerReceived 在 SSL 状态推进后调用.
//
// 单 pumper 不变量: FPumping 标志确保任意时刻只有一个 pumper 推进 queue,
// 防止并发 pump 引起 SSL 状态机交叉数据.
//
// 推进路径: 取出首条目, 锁外调 _SslSendInner; callback 内清除 FPumping,
// 成功则递归 pump 下一个 (锁外异步, 不会同步深递归), 失败则 drain 剩余条目.
var
  LItem: TPendingWrite;
begin
  _SslLock;
  try
    if FPumping then Exit;
    if (FPendingWrites = nil) or (FPendingWrites.Count = 0) then Exit;
    FPumping := True;
    LItem := FPendingWrites.Dequeue;
    Dec(FPendingBytes, LItem.Len);
  finally
    _SslUnlock;
  end;

  // 锁外推进首个条目, callback 内继续 pump 下一个或 drain.
  // try/except: _SslSendInner 同步阶段若抛异常, 必须复位 FPumping 并
  // drain 剩余条目, 否则 pending write 队列永久死锁.
  try
    _SslSendInner(LItem.Buf, LItem.Len,
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      var
        LCallbackFailed: Boolean;
      begin
        LCallbackFailed := False;
        try
          try
            if Assigned(LItem.Callback) then
              LItem.Callback(AConnection, ASuccess);
          except
            on E: Exception do
            begin
              LCallbackFailed := True;
              _Log('pending write callback error: %s: %s', [E.ClassName, E.Message]);
            end;
          end;
        finally
          _SslLock;
          try
            FPumping := False;
          finally
            _SslUnlock;
          end;

          if LCallbackFailed then
            _DrainPendingWritesAsFailed(AConnection);
        end;

        if LCallbackFailed then Exit;

        if ASuccess then
          _PumpPendingWrites    // 推进下一个 (锁外异步)
        else
          _DrainPendingWritesAsFailed(AConnection);  // 失败: 后续 pending 全 fail
      end);
  except
    _SslLock;
    try
      FPumping := False;
    finally
      _SslUnlock;
    end;

    try
      if Assigned(LItem.Callback) then
        LItem.Callback(nil, False);

      _DrainPendingWritesAsFailed(nil);
    except
      // 吞掉 drain 中可能的异常, 保证原始异常能 raise 出去
    end;
    raise;
  end;
end;

procedure TCrossOpenSslConnection._DrainPendingWritesAsFailed(
  const AConnection: ICrossConnection);
// 把 queue 中所有挂起条目以 fail 通知上层.
//
// 锁内仅做"快速搬运" (Dequeue 到本地 array), 避免锁内调 callback 引起
// 重入 / 死锁. 锁外依次触发 callback, 上层闭包将释放持有的 TBytes.
//
// AConnection 由调用方决定:
//   - 析构路径传 nil: 避免 (Self as ICrossConnection) 引起 refcount 环 → 二次析构
//   - pump 失败路径传 callback 收到的 AConnection (已是有效引用)
var
  LDrained: TArray<TPendingWrite>;
  I, LCount: Integer;
begin
  LDrained := nil;

  _SslLock;
  try
    if (FPendingWrites = nil) or (FPendingWrites.Count = 0) then Exit;
    LCount := FPendingWrites.Count;
    SetLength(LDrained, LCount);
    for I := 0 to LCount - 1 do
      LDrained[I] := FPendingWrites.Dequeue;
    FPendingBytes := 0;
  finally
    _SslUnlock;
  end;

  for I := 0 to High(LDrained) do
    if Assigned(LDrained[I].Callback) then
      LDrained[I].Callback(AConnection, False);
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
  // 先调 inherited 关闭所有连接: 各连接的 SSL_free 只减 CTX 引用计数,
  // 不依赖 CTX 存活 (OpenSSL 保证), 所以 CTX 可以延后释放.
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
var
  LOptions: Integer;
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
  LOptions := SSL_CTX_get_options(FSslCtx)
    // 根据服务器偏好选择加密套件
    or SSL_OP_CIPHER_SERVER_PREFERENCE
    // 允许连接到不支持RI的旧服务器
    or SSL_OP_LEGACY_SERVER_CONNECT;

  // 允许不安全的旧式重新协商(兼容工商银行ch5.dcep.ccb.com:443)
  if AllowUnsafeLegacyRenegotiation then
    LOptions := LOptions or SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION;

  SSL_CTX_set_options(FSslCtx, LOptions);

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

procedure TCrossOpenSslSocket._FinishHandshakeProgress(
  const ASendSuccess: Boolean; const AConnectionObj: TCrossOpenSslConnection;
  const ATriggerConnected: Boolean; var ADecryptedData: TBytes;
  const AFatal: Boolean);
var
  LConnection: ICrossConnection;
begin
  if not ASendSuccess then
  begin
    ADecryptedData := nil;
    if (AConnectionObj <> nil) then
      AConnectionObj.Close;
    Exit;
  end;

  if (AConnectionObj <> nil) then
    LConnection := AConnectionObj as ICrossConnection
  else
    LConnection := nil;

  // 握手完成, 触发已连接事件
  if ATriggerConnected then
    _Connected(LConnection);

  // 收到了解密后的数据
  if (ADecryptedData <> nil) then
  begin
    _Received(LConnection, @ADecryptedData[0], Length(ADecryptedData));
    ADecryptedData := nil;
  end;

  // 握手 fatal: alert 已发出, 关闭连接释放资源
  if AFatal then
  begin
    if (AConnectionObj <> nil) then
      AConnectionObj.Close;
  end else if (AConnectionObj <> nil) then
    AConnectionObj._PumpPendingWrites;
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
  LFatal: Boolean;
begin
  LConnection := AConnection as TCrossOpenSslConnection;

  if Ssl then
  begin
    LHandshakeData := nil;
    LFatal := False;

    LConnection._SslLock;
    try
      LConnection.ConnectStatus := csHandshaking;

      // 开始握手
      // 通常, 客户端连接在这里调用 SSL_do_handshake 就会生成握手数据
      // 而服务端连接, 即便在这里调用了 SSL_do_handshake 也不会生成握手数据
      // 只会返回 SSL_ERROR_WANT_READ, 后面再调用 BIO_read 也会继续返回 SSL_ERROR_WANT_READ
      // 需要在 TriggerReceived 中检查握手状态, 握手没完成就还需要调用 SSL_do_handshake
      LRetCode := LConnection._SSL_do_handshake;
      if (LRetCode <> 1) then
        LFatal := LConnection._SSL_handle_error(LRetCode,
          'SSL_do_handshake(TriggerConnected)');

      // 即使握手 fatal, 也读出 BIO 中可能的 TLS alert 发给对端 (RFC 5246 §7.2)
      LHandshakeData := LConnection._BIO_read_all;
    finally
      LConnection._SslUnlock;
    end;

    if (LHandshakeData <> nil) then
    begin
      // 有 fatal alert 时先尽量发给对端, 发送完成后再关闭连接;
      // 与 TriggerReceived 中的 fatal 握手推进保持同样的关闭顺序.
      LConnection._Send(LHandshakeData,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          if LFatal or (not ASuccess) then
            LConnection.Close;
        end);
    end else
    // 握手 fatal: 锁外关闭连接, 避免连接停滞在 csHandshaking 占用资源.
    // 握手输入字节限制由 TriggerReceived 中累加 + 阈值检查实现.
    if LFatal then
      LConnection.Close;
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
  LFatal: Boolean;
begin
  if Ssl then
  begin
    LConnectionObj := AConnection as TCrossOpenSslConnection;
    LTriggerConnected := False;
    LDecryptedData := nil;
    LHandshakeData := nil;
    LFatal := False;

    LConnectionObj._SslLock;
    try
      // 握手阶段输入字节限制:
      //   仅在握手未完成时累加, 超阈值即视作 DoS 直接 fatal close.
      //   握手成功后切换到正常数据流, 不再受此限制.
      if (LConnectionObj.ConnectStatus = csHandshaking) then
      begin
        Inc(LConnectionObj.FHandshakeRecvBytes, ALen);
        if (LConnectionObj.FHandshakeRecvBytes > MAX_HANDSHAKE_RECV_BYTES) then
          LFatal := True;
      end;

      if not LFatal then
      begin
        // 将收到的加密数据写入内存 BIO, 让 OpenSSL 对其解密
        // 最初收到的数据是握手数据
        // 需要判断握手状态, 然后决定如何使用收到的数据
        LRetCode := LConnectionObj._BIO_write(ABuf, ALen);
        if (LRetCode <> ALen) then
        begin
          // BIO_write 失败 fatal: 标记后到锁外 Close (避免锁内 Close 重入风险)
          if LConnectionObj._SSL_handle_error(LRetCode, 'BIO_write') then
            LFatal := True;
        end else
        // 握手完成
        if (LConnectionObj._SSL_is_init_finished <> 0) then
        begin
          if (LConnectionObj.ConnectStatus = csHandshaking) then
            LTriggerConnected := True;

          // 读取解密后的数据
          LDecryptedData := LConnectionObj._SSL_read_all;
        end else
        if (LConnectionObj.ConnectStatus = csHandshaking) then
        begin
          // 继续握手
          LRetCode := LConnectionObj._SSL_do_handshake;

          if (LRetCode <> 1) then
            // 握手 fatal: 标记后到锁外 Close, 避免连接停滞 csHandshaking
            if LConnectionObj._SSL_handle_error(LRetCode,
                'SSL_do_handshake(TriggerReceived)') then
              LFatal := True;

          // 即使 fatal 也读出 BIO, 含可能的 TLS alert 发给对端 (RFC 5246 §7.2)
          LHandshakeData := LConnectionObj._BIO_read_all;

          // 如果握手完成
          // 读取解密后的数据
          if (LRetCode = 1) then
          begin
            LTriggerConnected := True;
            LDecryptedData := LConnectionObj._SSL_read_all;
          end;
        end;
      end;
    finally
      LConnectionObj._SslUnlock;
    end;

    // 有握手数据
    if (LHandshakeData <> nil) then
    begin
      // 先把握手数据发出去再触发连接事件和数据接收事件;
      // fatal 时 alert 数据也通过这里发送, 发送完成后再 Close (优雅关闭)
      LConnectionObj._Send(LHandshakeData,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          _FinishHandshakeProgress(ASuccess, LConnectionObj, LTriggerConnected,
            LDecryptedData, LFatal);
        end);
    end else
      _FinishHandshakeProgress(True, LConnectionObj, LTriggerConnected,
        LDecryptedData, LFatal);
  end else
    _Received(AConnection, ABuf, ALen);
end;

end.
