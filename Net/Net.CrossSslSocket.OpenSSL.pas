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
  {$IFDEF FPC}DTF.Generics,{$ENDIF}

  Net.SocketAPI,
  Net.CrossProxy,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Types,
  Net.CrossSslSocket.Base,
  Net.OpenSSL,

  Utils.SyncObjs,
  Utils.Utils;

type

  // 只统计本层持有的未完成项及有效字节；0 不限制，不包含 OpenSSL 内部堆。
  TCrossSslQueueLimits = record
    MaxWriteCount: Integer;
    MaxWriteBytes: Int64;
    MaxCipherCount: Integer;
    MaxCipherBytes: Int64;
    MaxReceivedCount: Integer;
    MaxReceivedBytes: Int64;
  end;

  { TCrossOpenSslConnection }

  TCrossOpenSslConnection = class(TCrossSslConnectionBase)
  private type
    TSslReadResult = (srWant, srClosed, srFatal);
    // pending write 队列条目: 零拷贝, 仅保存上层传入的指针.
    // 调用方需保证 Buf 在 Callback 触发前持续有效 (异步框架契约).
    // **注意**: Callback 的 AConnection 参数在连接析构时会被传 nil
    //   (避免 refcount 环), 调用方实现 Callback 时必须判空.
    TPendingWrite = record
      Buf: PByte;
      Len: Integer;
      Callback: TCrossConnectionCallback;
    end;
    TCipherWrite = record
      Data: TBytes;
      Callback: TCrossConnectionCallback;
    end;
    TPendingWriteQueue = {$IFDEF FPC}TFpcQueue{$ELSE}TQueue{$ENDIF}<TPendingWrite>;
    TCipherWriteQueue = {$IFDEF FPC}TFpcQueue{$ELSE}TQueue{$ENDIF}<TCipherWrite>;
    TReceivedQueue = {$IFDEF FPC}TFpcQueue{$ELSE}TQueue{$ENDIF}<TBytes>;
  private
    FSslData: PSSL;
    FBIOIn, FBIOOut: PBIO;
    FProxySslData: PSSL;
    FProxyBIOIn, FProxyBIOOut: PBIO;
    FProxyTlsStarted: Boolean;
    FProxyTlsReady: Boolean;
    FLock: ILock;
    // 握手阶段累计输入字节数: 仅在 csHandshaking 时累加, 超过
    // MAX_HANDSHAKE_RECV_BYTES 即视作 DoS 主动 fatal close. 防御
    // "反复发送握手字节耗费 SSL 状态机"型 DoS.
    FHandshakeRecvBytes: Int64;

    // pending write 队列: BIO 空 + WANT_* 时把待写明文挂起,
    // 等 TriggerReceived 推进 SSL 状态后由 _PumpPendingWrites 唤醒.
    // FIFO 顺序保证 SSL 状态机不会被穿插数据弄乱.
    FPendingWrites: TPendingWriteQueue;
    FPendingBytes: Int64;       // 已挂起明文字节数 (用于背压判定)
    FMaxPendingBytes: Int64;    // 上限 (从 Owner 复制, 0 = 不限)
    FPumping: Boolean;          // 正在 pump 标志 (单 pumper 不变量)
    FStartingWrites, FResumePending: Boolean;
    FRetryWrite: TPendingWrite;
    FHasRetryWrite: Boolean;
    FCipherWrites: TCipherWriteQueue;
    FCipherSending, FCipherPumping, FCipherClosed: Boolean;
    FReceivedData: TReceivedQueue;
    FDeliveringData, FConnectedPublished: Boolean;
    FTlsEnded: Boolean;
    FTerminalData: TBytes;
    FFatalLog: string;
    FQueueLimits: TCrossSslQueueLimits;
    FWriteCount, FCipherCount, FReceivedCount: Integer;
    FWriteBytes, FCipherBytes, FReceivedBytes: Int64;
    FTerminalCounted: Boolean;

    function _LimitWriteCallback(const ASize: Integer;
      const ACallback: TCrossConnectionCallback): TCrossConnectionCallback;
    function _HasCipherCapacity(const ASize: Integer): Boolean;
    procedure _CapacityFailedLocked(const AName: string);

    // 注意: _SslLock/_SslUnlock 是 SSL 层独立锁, 非基类 _Lock/_Unlock.
    // 基类通过 _LockRecv/_LockSent 保护 IO 路径, 不经过这里.
    procedure _SslLock; inline;
    procedure _SslUnlock; inline;

    function _BIO_pending: Integer; inline;
    function _BIO_read(Buf: Pointer; Len: Integer): Integer; inline;
    function _BIO_read_all: TBytes; overload;
    function _BIO_write(Buf: Pointer; Len: Integer): Integer; inline;
    function _BIO_read_all(const ABIO: PBIO): TBytes; overload;
    function _SSL_read_all(const ASslData: PSSL): TBytes; overload;
    function _SSL_read(Buf: Pointer; Len: Integer): Integer; overload; inline;
    function _SSL_read_all(out AReadResult: TSslReadResult): TBytes; overload;
    function _SSL_read_all(const ASslData: PSSL;
      out AReadResult: TSslReadResult): TBytes; overload;
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
    procedure _StartPendingWrite(const AItem: TPendingWrite);

    // 尝试入队 pending write (必须在 FLock 内调用).
    // 返回 True=已入队 / False=背压拒绝 (调用方应 fail callback).
    function _TryEnqueuePendingWrite(const ABuf: PByte; const ALen: Integer;
      const ACallback: TCrossConnectionCallback): Boolean;

    // 唤醒 pending write 队列首条目, 推进完成后由 callback 触发下一轮 pump.
    // 由 TriggerReceived 在 SSL 状态推进 (BIO_write/SSL_read/握手) 后调用.
    procedure _PumpPendingWrites(const AResume: Boolean = False);

    function _QueueCipherLocked(const AData: TBytes;
      const ACallback: TCrossConnectionCallback): Boolean;
    procedure _PumpCipherWrites;
    procedure _SendCipherItem(const AItem: TCipherWrite);
    procedure _DrainCipherWritesAsFailed(const AConnection: ICrossConnection);
    procedure _PumpReceivedData;
    procedure _SetTlsEndedLocked(const AReplyClose: Boolean);
    procedure _FinishTls;
    procedure _LogTlsError;

    // 把 queue 中所有挂起条目以 fail 通知上层 (析构 / pump 推进失败时调用),
    // 调用方需保证当前线程不持有 FLock.
    // AConnection 用作 callback 的第一参数: 析构路径传 nil (避免引用计数环)
    // 其他路径传 Self as ICrossConnection.
    procedure _DrainPendingWritesAsFailed(const AConnection: ICrossConnection);

    procedure _RawSend(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil);
    procedure _ProxyTlsSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil);
    function _StartProxyTls(out AHandshakeData: TBytes): Boolean;
    function _FeedProxyTls(const ABuf: Pointer; const ALen: Integer;
      out APlainData, AHandshakeData: TBytes; out AHandshakeCompleted: Boolean): Boolean;

    procedure _Send(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure _Send(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil); overload;
  protected
    procedure InternalClose; override;
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
    procedure SendProxyBytes(const ABytes: TBytes); override;
    function ProxyTlsStarted: Boolean;
    function ProxyTlsReady: Boolean;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectedCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

    function GetSslInfo(var ASslInfo: TSslInfo): Boolean; override;
    // 仅可在没有未完成收发的空闲连接上调整；不会追补已有缓冲。
    procedure SetSslQueueLimits(const AValue: TCrossSslQueueLimits);
  end;

  /// <remarks>
  ///   若要继承该类, 请重载 LogicXXX, 而不是 TriggerXXX
  /// </remarks>

  { TCrossOpenSslSocket }

  TCrossOpenSslSocket = class(TCrossSslSocketBase)
  private
    FSslCtx: PSSL_CTX;
    FTlsRuntimeLoaded: Boolean;
    FSslLoaded: Boolean;
    FQueueLimits: TCrossSslQueueLimits;
    procedure SetSslQueueLimits(const AValue: TCrossSslQueueLimits);

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
    procedure _ProcessReceivedPayload(const AConnection: ICrossConnection;
      const APayload: Pointer; const APayloadLen: Integer);
    procedure _FinishProxyTlsReceive(const AConnection: ICrossConnection;
      const ASuccess: Boolean; const APlainData: TBytes;
      const AHandshakeCompleted: Boolean);
  protected
    procedure ApplyVerifyPeer(const AValue: Boolean); override;
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload; override;
    procedure AddCACertificate(const ABuf: Pointer;
      const ASize: Integer); overload; override;
    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer;
      const APassword: string); overload; override;
    procedure EnsureSslCtx;
    procedure SetTls12CipherSuites(const ACipherRules: string); override;
    procedure SetTls13CipherSuites(const ACipherSuites: string); override;
    procedure SetMinTlsVersion(const AVersion: TCrossTlsMinVersion); override;
    // 在建立第一个 TLS 连接前配置；每个连接取得独立快照。
    property SslQueueLimits: TCrossSslQueueLimits read FQueueLimits write SetSslQueueLimits;
  end;

{$IFDEF CROSS_OPENSSL_SELFTEST}
function CrossOpenSslSelfTest_GetCipherList(
  const ASocket: TCrossOpenSslSocket): TArray<string>;
function CrossOpenSslSelfTest_GetSecurityLevel(
  const ASocket: TCrossOpenSslSocket): Integer;
procedure CrossOpenSslSelfTest_GetProtocolVersions(
  const ASocket: TCrossOpenSslSocket; out AMinVersion, AMaxVersion: Integer);
function CrossOpenSslSelfTest_GetNegotiatedCipher(
  const AConnection: ICrossConnection; out AVersion, ACipher: string): Boolean;
function CrossOpenSslSelfTest_CloseDrainsPendingWrites(out AErrMsg: string): Boolean;
function CrossOpenSslSelfTest_PendingCallbackExceptionDoesNotStall(
  out AErrMsg: string): Boolean;
function CrossOpenSslSelfTest_HandshakeSendFailureDoesNotPromote(
  out AErrMsg: string): Boolean;
function CrossOpenSslSelfTest_QueueClear(const AConnection: ICrossConnection;
  const AKind: Integer): Boolean;
function CrossOpenSslSelfTest_QueueUsage(const AConnection: ICrossConnection): TArray<Int64>;
var
  // 只固定解密登记后、明文发布前的调度时序，不替换原生 TLS 或发送完成。
  CrossOpenSslSelfTest_BeforeReceived: TCrossConnectionCallback;
{$ENDIF}

implementation

{$IFDEF CROSS_OPENSSL_SELFTEST}
function CrossOpenSslSelfTest_QueueUsage(const AConnection: ICrossConnection): TArray<Int64>;
var C: TCrossOpenSslConnection;
begin
  C := AConnection as TCrossOpenSslConnection;
  C._SslLock;
  try
    SetLength(Result, 6);
    Result[0] := C.FWriteCount; Result[1] := C.FWriteBytes;
    Result[2] := C.FCipherCount; Result[3] := C.FCipherBytes;
    Result[4] := C.FReceivedCount; Result[5] := C.FReceivedBytes;
  finally C._SslUnlock; end;
end;
{$ENDIF}

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
{$IFDEF FPC}
type
  TQueueSlotView<T> = class(TQueue<T>)
    function Slot(const AIndex: Integer): T;
    function SlotCount: Integer;
  end;
function TQueueSlotView<T>.Slot(const AIndex: Integer): T;
begin Result := FItems[AIndex]; end;
function TQueueSlotView<T>.SlotCount: Integer;
begin Result := Length(FItems); end;
{$ENDIF}

function CrossOpenSslSelfTest_QueueClear(const AConnection: ICrossConnection;
  const AKind: Integer): Boolean;
var
  C: TCrossOpenSslConnection;
  P: TCrossOpenSslConnection.TPendingWrite;
  W: TCrossOpenSslConnection.TCipherWrite;
  B: TBytes;
  I: Integer;
  {$IFDEF FPC}
  PV: TQueueSlotView<TCrossOpenSslConnection.TPendingWrite>;
  WV: TQueueSlotView<TCrossOpenSslConnection.TCipherWrite>;
  BV: TQueueSlotView<TBytes>;
  {$ENDIF}
begin
  C := AConnection as TCrossOpenSslConnection;
  C._SslLock;
  try
    // 使用连接自身的三种托管队列；保持固定深度，强制触发 RTL 搬移而非仅析构释放。
    P := Default(TCrossOpenSslConnection.TPendingWrite);
    W := Default(TCrossOpenSslConnection.TCipherWrite);
    P.Callback := procedure(const X: ICrossConnection; const OK: Boolean) begin end;
    W.Callback := P.Callback;
    B := TBytes.Create(1, 2, 3);
    W.Data := B;
    for I := 0 to 2111 do
    begin
      if I >= 64 then
        case AKind of
          0: C.FPendingWrites.Dequeue;
          1: C.FCipherWrites.Dequeue;
          2: C.FReceivedData.Dequeue;
        end;
      case AKind of
        0: C.FPendingWrites.Enqueue(P);
        1: C.FCipherWrites.Enqueue(W);
        2: C.FReceivedData.Enqueue(B);
      end;
    end;
    case AKind of
      0: C.FPendingWrites.Clear;
      1: C.FCipherWrites.Clear;
      2: C.FReceivedData.Clear;
    end;
    P := Default(TCrossOpenSslConnection.TPendingWrite);
    W := Default(TCrossOpenSslConnection.TCipherWrite);
    B := nil;
    Result := True;
    {$IFDEF FPC}
    PV := TQueueSlotView<TCrossOpenSslConnection.TPendingWrite>(C.FPendingWrites);
    WV := TQueueSlotView<TCrossOpenSslConnection.TCipherWrite>(C.FCipherWrites);
    BV := TQueueSlotView<TBytes>(C.FReceivedData);
    case AKind of
      0: for I := 0 to PV.SlotCount - 1 do
         begin
           P := PV.Slot(I);
           if Assigned(P.Callback) then Exit(False);
         end;
      1: for I := 0 to WV.SlotCount - 1 do
         begin
           W := WV.Slot(I);
           if (Length(W.Data) > 0) or Assigned(W.Callback) then Exit(False);
         end;
      2: for I := 0 to BV.SlotCount - 1 do
         if Length(BV.Slot(I)) > 0 then Exit(False);
    end;
    {$ENDIF}
  finally
    C._SslUnlock;
  end;
end;

function CrossOpenSslSelfTest_GetCipherList(
  const ASocket: TCrossOpenSslSocket): TArray<string>;
var
  LSsl: PSSL;
begin
  // 仅供首次连接前的配置测试使用；不对生产代码公开上下文指针。
  ASocket.BeginTlsConfigUpdate;
  try
    ERR_clear_error();
    LSsl := SSL_new(ASocket.FSslCtx);
    if LSsl = nil then
      raise ESsl.CreateFmt('SSL_new failed in cipher test: %s',
        [GetOpenSslErrors]);
    try
      Result := TSSLTools.GetCipherList(LSsl);
    finally
      SSL_free(LSsl);
      ERR_clear_error();
    end;
  finally
    ASocket.EndTlsConfigUpdate;
  end;
end;

function CrossOpenSslSelfTest_GetSecurityLevel(
  const ASocket: TCrossOpenSslSocket): Integer;
begin
  ASocket.BeginTlsConfigUpdate;
  try
    Result := SSL_CTX_get_security_level(ASocket.FSslCtx);
  finally
    ASocket.EndTlsConfigUpdate;
  end;
end;

procedure CrossOpenSslSelfTest_GetProtocolVersions(
  const ASocket: TCrossOpenSslSocket; out AMinVersion, AMaxVersion: Integer);
begin
  ASocket.BeginTlsConfigUpdate;
  try
    AMinVersion := SSL_CTX_get_min_proto_version(ASocket.FSslCtx);
    AMaxVersion := SSL_CTX_get_max_proto_version(ASocket.FSslCtx);
  finally
    ASocket.EndTlsConfigUpdate;
  end;
end;

function CrossOpenSslSelfTest_GetNegotiatedCipher(
  const AConnection: ICrossConnection; out AVersion, ACipher: string): Boolean;
var
  LConnection: TCrossOpenSslConnection;
begin
  AVersion := '';
  ACipher := '';
  LConnection := AConnection as TCrossOpenSslConnection;
  Result := (LConnection.FSslData <> nil) and
    (SSL_is_init_finished(LConnection.FSslData) = 1);
  if not Result then Exit;
  // 只观测本次测试所需的协商结果，不解析证书或临时密钥。
  AVersion := UTF8ToString(SSL_get_version(LConnection.FSslData));
  ACipher := UTF8ToString(SSL_get_cipher_name(LConnection.FSslData));
end;

type
  TPendingCloseObserver = class
    procedure Disconnected(const ASender: TObject; const AConnection: ICrossConnection);
  end;

procedure TPendingCloseObserver.Disconnected(const ASender: TObject;
  const AConnection: ICrossConnection);
begin
  raise Exception.Create('测试断连通知异常');
end;

function CrossOpenSslSelfTest_CloseDrainsPendingWrites(out AErrMsg: string): Boolean;
var
  LSocket: TCrossOpenSslSocket;
  LConnection: TCrossOpenSslConnection;
  LConnectionIntf: ICrossConnection;
  LObserver: TPendingCloseObserver;
  LCallbackCount: Integer;
  LUnexpectedSuccess, LRaised: Boolean;
  LByte: Byte;
  procedure EnqueueCallback(const AIndex: Integer);
  var
    LKeepAlive: ICrossConnection;
    LCallback: TCrossConnectionCallback;
  begin
    // 独立过程使编译器的匿名函数临时引用在入队后立即释放。
    LKeepAlive := LConnectionIntf;
    LCallback := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        Inc(LCallbackCount);
        if ASuccess or (LKeepAlive = nil) then LUnexpectedSuccess := True;
        if AIndex = 0 then raise Exception.Create('测试挂起写完成异常');
      end;
    LConnection._SslLock;
    try
      if not LConnection._TryEnqueuePendingWrite(@LByte, 1, LCallback) then
        raise Exception.Create('挂起写未入队');
    finally
      LConnection._SslUnlock;
    end;
  end;
begin
  Result := False;
  AErrMsg := '';
  LSocket := TCrossOpenSslSocket.Create(0, False);
  LObserver := TPendingCloseObserver.Create;
  try
    LSocket.OnDisconnected := LObserver.Disconnected;
    LConnection := TCrossOpenSslConnection.Create(LSocket,
      TSocketAPI.NewTcp, ctConnect, '', nil);
    LConnectionIntf := LConnection;
    LConnection.FLock := TLock.Create;
    LConnection.FPendingWrites := TCrossOpenSslConnection.TPendingWriteQueue.Create;
    try
      try
        if LConnection.Socket = INVALID_SOCKET then raise Exception.Create('测试套接字创建失败');
        LConnection.ConnectStatus := csConnected;
        LCallbackCount := 0;
        LUnexpectedSuccess := False;
        LByte := 0;
        EnqueueCallback(0);
        EnqueueCallback(1);
        if LConnection.RefCount < 3 then raise Exception.Create('未建立挂起回调保活引用');
        LRaised := False;
        try LConnection.Close; except
          on E: Exception do LRaised := E.Message = '测试断连通知异常';
        end;
        if not LRaised then raise Exception.Create('断连通知异常未按原契约传播');
        if (LCallbackCount <> 2) or LUnexpectedSuccess then
          raise Exception.Create('挂起回调未全部结算为失败');
        if (LConnection.FPendingWrites.Count <> 0) or (LConnection.FPendingBytes <> 0)
          or (LConnection.Socket <> INVALID_SOCKET) then
          raise Exception.Create('关闭后仍残留队列或句柄');
        LConnection._SslLock;
        try
          if LConnection._TryEnqueuePendingWrite(@LByte, 1, nil) then
            raise Exception.Create('关闭后仍允许挂起入队');
        finally LConnection._SslUnlock; end;
        if LConnection.RefCount <> 1 then raise Exception.CreateFmt('close refcount=%d', [LConnection.RefCount]);
        Result := True;
      except
        on E: Exception do AErrMsg := E.ClassName + ': ' + E.Message;
      end;
    finally
      LConnection.FPendingWrites.Free;
      LConnection.FPendingWrites := nil;
      LConnectionIntf := nil;
    end;
  finally
    LSocket.Free;
    LObserver.Free;
  end;
end;

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
    LConnection.FPendingWrites := TCrossOpenSslConnection.TPendingWriteQueue.Create;
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

procedure ValidateSslQueueLimits(const AValue: TCrossSslQueueLimits);
begin
  if (AValue.MaxWriteCount < 0) or (AValue.MaxWriteBytes < 0)
    or (AValue.MaxCipherCount < 0) or (AValue.MaxCipherBytes < 0)
    or (AValue.MaxReceivedCount < 0) or (AValue.MaxReceivedBytes < 0) then
    raise EArgumentException.Create('TLS queue limits must not be negative');
end;

procedure TCrossOpenSslConnection.SetSslQueueLimits(const AValue: TCrossSslQueueLimits);
begin
  ValidateSslQueueLimits(AValue);
  if not Ssl then raise EInvalidOpException.Create('TLS is disabled');
  _SslLock;
  try
    if FPumping or FStartingWrites or FHasRetryWrite or FCipherSending
      or FCipherPumping or FDeliveringData or (FPendingWrites.Count <> 0)
      or (FCipherWrites.Count <> 0) or (FReceivedData.Count <> 0)
      or (FWriteCount <> 0) or (FCipherCount <> 0) or (FReceivedCount <> 0)
      or (Length(FTerminalData) <> 0) or FTlsEnded or FCipherClosed then
      raise EInvalidOpException.Create('TLS queue limits require an idle connection');
    FQueueLimits := AValue;
  finally
    _SslUnlock;
  end;
end;

function TCrossOpenSslConnection._LimitWriteCallback(const ASize: Integer;
  const ACallback: TCrossConnectionCallback): TCrossConnectionCallback;
var
  LCompleted: Integer;
begin
  LCompleted := 0;
  Result :=
    procedure(const C: ICrossConnection; const OK: Boolean)
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      _SslLock;
      try
        Dec(FWriteCount);
        Dec(FWriteBytes, ASize);
      finally
        _SslUnlock;
      end;
      if Assigned(ACallback) then ACallback(C, OK);
    end;
end;

function TCrossOpenSslConnection._HasCipherCapacity(const ASize: Integer): Boolean;
begin
  Result := ((FQueueLimits.MaxCipherCount = 0)
      or (FCipherCount < FQueueLimits.MaxCipherCount))
    and ((FQueueLimits.MaxCipherBytes = 0)
      or (ASize <= FQueueLimits.MaxCipherBytes - FCipherBytes));
end;

procedure TCrossOpenSslConnection._CapacityFailedLocked(const AName: string);
begin
  // 原生 TLS 状态已经推进，不能丢弃本条记录后继续使用同一序列。
  FTlsEnded := True;
  if FFatalLog = '' then FFatalLog := 'TLS ' + AName + ' queue capacity exceeded';
end;

constructor TCrossOpenSslConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectedCb: TCrossConnectionCallback);
var
  LHostAnsi: AnsiString;
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectedCb);

  if Ssl then
  begin
    TCrossOpenSslSocket(Owner).LockTlsConfiguration;
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

    FPendingWrites := TPendingWriteQueue.Create;
    FCipherWrites := TCipherWriteQueue.Create;
    FReceivedData := TReceivedQueue.Create;
    FMaxPendingBytes := TCrossOpenSslSocket(AOwner).SslMaxPendingWriteBytes;
    FQueueLimits := TCrossOpenSslSocket(AOwner).FQueueLimits;

    if (ConnectType = ctAccept) then
      SSL_set_accept_state(FSslData)   // 服务端连接
    else
    begin
      SSL_set_connect_state(FSslData); // 客户端连接
      LHostAnsi := AnsiString(AHost);
      SSL_set_tlsext_host_name(FSslData, MarshaledAString(LHostAnsi));
      if TCrossOpenSslSocket(Owner).VerifyPeer then
      begin
        if AHost = '' then
          raise ECrossSocket.Create('A host name is required when peer verification is enabled.');
        ERR_clear_error();
        if SSL_set1_host(FSslData, PAnsiChar(LHostAnsi)) <= 0 then
          raise ECrossSocket.CreateFmt('SSL_set1_host failed: %s.',
            [GetOpenSslErrors]);
      end;
    end;
  end;
end;

procedure TCrossOpenSslConnection.SendProxyBytes(const ABytes: TBytes);
begin
  _Send(ABytes);
end;

function TCrossOpenSslConnection.ProxyTlsStarted: Boolean;
begin
  Result := FProxyTlsStarted;
end;

function TCrossOpenSslConnection.ProxyTlsReady: Boolean;
begin
  Result := FProxyTlsReady;
end;

destructor TCrossOpenSslConnection.Destroy;
begin
  if (FPendingWrites <> nil) then
  begin
    // pending writes 析构 drain: 把所有挂起 callback 以 fail 通知上层,
    // 上层闭包持有的 TBytes 才能释放 (零拷贝契约). 传 nil connection 避免
    // (Self as ICrossConnection) 引起的 refcount 环 → 二次析构.
    _DrainPendingWritesAsFailed(nil);
    FPendingWrites.Free;
  end;
  if FCipherWrites <> nil then
  begin
    _DrainCipherWritesAsFailed(nil);
    FCipherWrites.Free;
  end;
  FReceivedData.Free;

  if (FSslData <> nil) then
  begin
    if (SSL_shutdown(FSslData) = 0) then
      SSL_shutdown(FSslData);
    SSL_free(FSslData);
    FSslData := nil;
  end;

  if (FProxySslData <> nil) then
  begin
    if FProxyTlsReady and (SSL_shutdown(FProxySslData) = 0) then
      SSL_shutdown(FProxySslData);
    SSL_free(FProxySslData);
    FProxySslData := nil;
  end;

  inherited Destroy;
end;

procedure TCrossOpenSslConnection.InternalClose;
var
  LData: TBytes;
begin
  try
    if FLock <> nil then
    begin
      _SslLock;
      try
        FCipherClosed := True;
        FTlsEnded := True;
        if FTerminalCounted then
        begin
          Dec(FCipherCount);
          Dec(FCipherBytes, Length(FTerminalData));
          FTerminalCounted := False;
        end;
        FTerminalData := nil;
        if FReceivedData <> nil then
        begin
          if (FQueueLimits.MaxReceivedCount > 0) or (FQueueLimits.MaxReceivedBytes > 0) then
            while FReceivedData.Count > 0 do
            begin
              LData := FReceivedData.Dequeue;
              Dec(FReceivedCount);
              Dec(FReceivedBytes, Length(LData));
            end
          else FReceivedData.Clear;
        end;
      finally
        _SslUnlock;
      end;
    end;
    _LogTlsError;
    // Close 已持有连接引用，先结算挂起写，解除回调对连接的保活引用。
    if FPendingWrites <> nil then
      _DrainPendingWritesAsFailed(Self as ICrossConnection);
    if FCipherWrites <> nil then
      _DrainCipherWritesAsFailed(Self as ICrossConnection);
  finally
    inherited InternalClose;
  end;
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
  if FLock = nil then
    FLock := TLock.Create;
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
  ERR_clear_error();
  Result := BIO_read(FBIOOut, Buf, Len);
end;

function TCrossOpenSslConnection._BIO_read_all: TBytes;
begin
  Result := _BIO_read_all(FBIOOut);
end;

function TCrossOpenSslConnection._BIO_read_all(const ABIO: PBIO): TBytes;
const
  INITIAL_BUF_SIZE = 16384; // 初始缓冲区大小 16KB
var
  LReadedCount, LBlockSize, LRetCode: Integer;
  LFreeSpace, LNewSize: Integer;
  P: PByte;
begin
  LReadedCount := 0;
  if (FQueueLimits.MaxCipherCount > 0) or (FQueueLimits.MaxCipherBytes > 0) then
  begin
    LBlockSize := _BIO_pending;
    if LBlockSize <= 0 then Exit(nil);
    if not _HasCipherCapacity(LBlockSize) then
    begin
      _CapacityFailedLocked('ciphertext');
      Exit(nil);
    end;
    SetLength(Result, LBlockSize);
  end else
    SetLength(Result, INITIAL_BUF_SIZE);

  while True do
  begin
    // 获取当前可读数据量
    LBlockSize := BIO_pending(ABIO);
    if (LBlockSize <= 0) then Break;

    // 计算缓冲区剩余空间
    LFreeSpace := Length(Result) - LReadedCount;

    // 动态扩展缓冲区(按需增长)
    if (LFreeSpace < LBlockSize) then
    begin
      // 内存 BIO 已报告当前全部待读字节，只扩到本轮实际需要的长度。
      LNewSize := LReadedCount + LBlockSize;
      SetLength(Result, LNewSize);
    end;

    // 指向缓冲区当前写入位置
    P := PByte(@Result[0]) + LReadedCount;

    // 从 BIO 读取数据(最多读取 LBlockSize)
    LRetCode := BIO_read(ABIO, P, LBlockSize);

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
  ERR_clear_error();
  Result := BIO_write(FBIOIn, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_read(Buf: Pointer; Len: Integer): Integer;
begin
  ERR_clear_error();
  Result := SSL_read(FSslData, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_read_all(
  const ASslData: PSSL): TBytes;
var
  LReadResult: TSslReadResult;
begin
  Result := _SSL_read_all(ASslData, LReadResult);
end;

function TCrossOpenSslConnection._SSL_read_all(
  out AReadResult: TSslReadResult): TBytes;
begin
  Result := _SSL_read_all(FSslData, AReadResult);
end;

function TCrossOpenSslConnection._SSL_read_all(const ASslData: PSSL;
  out AReadResult: TSslReadResult): TBytes;
const
  INITIAL_BUF_SIZE = 16384;  // 初始缓冲区 16KB
  MAX_BUF_INCREMENT = 65536; // 最大增量 64KB
var
  LReadedCount, LRetCode, LError: Integer;
  LFreeSpace, LNewSize: Integer;
  LAvailable: Int64;
  LProbe: Byte;
  LProbing: Boolean;
  P: PByte;
begin
  LReadedCount := 0;
  AReadResult := srWant;
  LAvailable := High(Integer);
  if FQueueLimits.MaxReceivedBytes > 0 then
    LAvailable := FQueueLimits.MaxReceivedBytes - FReceivedBytes;
  if LAvailable > High(Integer) then LAvailable := High(Integer);
  if (FQueueLimits.MaxReceivedCount > 0)
    and (FReceivedCount >= FQueueLimits.MaxReceivedCount) then LAvailable := 0;
  if LAvailable > INITIAL_BUF_SIZE then LNewSize := INITIAL_BUF_SIZE
  else LNewSize := Integer(LAvailable);
  SetLength(Result, LNewSize);

  while True do
  begin
    // 计算缓冲区剩余空间
    LFreeSpace := Length(Result) - LReadedCount;

    // 动态扩展缓冲区(按需增长)
    if (LFreeSpace < 1024) and (Length(Result) < LAvailable) then
    begin
      // 指数增长策略: 每次翻倍, 上限为 MAX_BUF_INCREMENT
      if Length(Result) > MAX_BUF_INCREMENT then LNewSize := MAX_BUF_INCREMENT
      else LNewSize := Length(Result);
      if LNewSize > LAvailable - Length(Result) then
        LNewSize := Integer(LAvailable - Length(Result));
      Inc(LNewSize, Length(Result));
      SetLength(Result, LNewSize);
      LFreeSpace := Length(Result) - LReadedCount;
    end;

    // 指向缓冲区当前写入位置
    LProbing := LFreeSpace = 0;
    if LProbing then
    begin
      // 满额仍允许处理 WANT、KeyUpdate 和 close_notify；只探测一个栈字节。
      P := @LProbe;
      LFreeSpace := 1;
    end else P := PByte(@Result[0]) + LReadedCount;

    // 读取数据
    LRetCode := SSL_read(ASslData, P, LFreeSpace);

    // 直到读不到数据为止
    if (LRetCode <= 0) then
    begin
      if _SSL_handle_error(LRetCode, 'SSL_read', LError) then
        AReadResult := srFatal
      else
      if LError = SSL_ERROR_ZERO_RETURN then
        AReadResult := srClosed;
      Break;
    end;

    if LProbing then
    begin
      _CapacityFailedLocked('received plaintext');
      AReadResult := srFatal;
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
  ERR_clear_error();
  Result := SSL_write(FSslData, Buf, Len);
end;

function TCrossOpenSslConnection._SSL_do_handshake: Integer;
begin
  ERR_clear_error();
  Result := SSL_do_handshake(FSslData);
end;

function TCrossOpenSslConnection._SSL_is_init_finished: Integer;
begin
  ERR_clear_error();
  Result := SSL_is_init_finished(FSslData);
end;

function TCrossOpenSslConnection._SSL_get_error(const ARetCode: Integer): Integer;
begin
  Result := SSL_get_error(FSslData, ARetCode);
end;

function TCrossOpenSslConnection._SSL_handle_error(const ARetCode: Integer;
  const AOperation: string; out AErrCode: Integer): Boolean;
var
  LErrorText: string;
begin
  AErrCode := _SSL_get_error(ARetCode);
  Result := SSL_is_fatal_error(AErrCode);
  if Result then
  begin
    LErrorText := GetOpenSslErrors;
    // 锁内只保存诊断并禁止后续 SSL I/O；用户日志由锁外终结路径调用。
    _SetTlsEndedLocked(False);
    if FFatalLog = '' then FFatalLog := AOperation + ' ' + LErrorText;
  end;
end;

function TCrossOpenSslConnection._SSL_handle_error(const ARetCode: Integer;
  const AOperation: string): Boolean;
var
  LError: Integer;
begin
  Result := _SSL_handle_error(ARetCode, AOperation, LError);
end;

function TCrossOpenSslConnection._StartProxyTls(
  out AHandshakeData: TBytes): Boolean;
var
  LHostAnsi: AnsiString;
  LRetCode: Integer;
begin
  Result := False;
  AHandshakeData := nil;
  if not ProxyUsesTlsTransport or FProxyTlsStarted then
    Exit;

  TCrossOpenSslSocket(Owner).EnsureSslCtx;
  TCrossOpenSslSocket(Owner).LockTlsConfiguration;
  _SslLock;
  try
    FProxyTlsStarted := True;
    FProxySslData := SSL_new(TCrossOpenSslSocket(Owner).FSslCtx);
    if FProxySslData = nil then
      raise ECrossSocket.Create('SSL_new for HTTPS proxy failed.');

    FProxyBIOIn := BIO_new(BIO_s_mem());
    FProxyBIOOut := BIO_new(BIO_s_mem());
    if (FProxyBIOIn = nil) or (FProxyBIOOut = nil) then
    begin
      if FProxyBIOIn <> nil then
        BIO_free(FProxyBIOIn);
      if FProxyBIOOut <> nil then
        BIO_free(FProxyBIOOut);
      FProxyBIOIn := nil;
      FProxyBIOOut := nil;
      SSL_free(FProxySslData);
      FProxySslData := nil;
      raise ECrossSocket.Create('BIO_new for HTTPS proxy failed.');
    end;
    SSL_set_bio(FProxySslData, FProxyBIOIn, FProxyBIOOut);

    SSL_set_connect_state(FProxySslData);
    LHostAnsi := AnsiString(ProxySettings.Host);
    SSL_set_tlsext_host_name(FProxySslData, MarshaledAString(LHostAnsi));
    if TCrossOpenSslSocket(Owner).VerifyPeer then
    begin
      if LHostAnsi = '' then
        raise ECrossSocket.Create(
          'A HTTPS proxy host name is required when peer verification is enabled.');
      ERR_clear_error();
      if SSL_set1_host(FProxySslData, PAnsiChar(LHostAnsi)) <= 0 then
        raise ECrossSocket.CreateFmt('SSL_set1_host for HTTPS proxy failed: %s.',
          [GetOpenSslErrors]);
    end;

    LRetCode := SSL_do_handshake(FProxySslData);
    if (LRetCode <> 1) and SSL_is_fatal_error(
      SSL_get_error(FProxySslData, LRetCode)) then
      raise ECrossSocket.CreateFmt('HTTPS proxy TLS handshake failed: %s.',
        [GetOpenSslErrors]);
    AHandshakeData := _BIO_read_all(FProxyBIOOut);
    Result := Length(AHandshakeData) > 0;
    if not Result then
      raise ECrossSocket.CreateFmt(
        'HTTPS proxy TLS produced no handshake bytes (ret=%d): %s',
        [LRetCode, GetOpenSslErrors]);
  finally
    _SslUnlock;
  end;
end;

function TCrossOpenSslConnection._FeedProxyTls(const ABuf: Pointer;
  const ALen: Integer; out APlainData, AHandshakeData: TBytes;
  out AHandshakeCompleted: Boolean): Boolean;
var
  LRetCode: Integer;
begin
  Result := False;
  APlainData := nil;
  AHandshakeData := nil;
  AHandshakeCompleted := False;
  if (not FProxyTlsStarted) or (FProxySslData = nil) or
    (ABuf = nil) or (ALen <= 0) then
    Exit;

  _SslLock;
  try
    LRetCode := BIO_write(FProxyBIOIn, ABuf, ALen);
    if LRetCode <> ALen then
      Exit;

    if not FProxyTlsReady then
    begin
      LRetCode := SSL_do_handshake(FProxySslData);
      if (LRetCode <> 1) and SSL_is_fatal_error(
        SSL_get_error(FProxySslData, LRetCode)) then
      begin
        _Log('HTTPS proxy TLS handshake failed: ' + GetOpenSslErrors);
        Exit;
      end;
      AHandshakeData := _BIO_read_all(FProxyBIOOut);
      if SSL_is_init_finished(FProxySslData) = 0 then
      begin
        Result := True;
        Exit;
      end;
      FProxyTlsReady := True;
      AHandshakeCompleted := True;
    end;

    APlainData := _SSL_read_all(FProxySslData);
    Result := True;
  finally
    _SslUnlock;
  end;
end;

procedure TCrossOpenSslConnection._RawSend(const ABytes: TBytes;
  const ACallback: TCrossConnectionCallback);
var
  LBytes: TBytes;
begin
  if Length(ABytes) = 0 then
  begin
    if Assigned(ACallback) then
      ACallback(Self, True);
    Exit;
  end;

  LBytes := ABytes;
  inherited DirectSend(@LBytes[0], Length(LBytes),
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LBytes := nil;
      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossOpenSslConnection._ProxyTlsSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LRetCode, LWritten: Integer;
  LEncryptedData: TBytes;
  LFatal: Boolean;
begin
  if (ACount <= 0) then
  begin
    if Assigned(ACallback) then
      ACallback(Self, True);
    Exit;
  end;

  LEncryptedData := nil;
  LFatal := False;
  LWritten := 0;
  _SslLock;
  try
    LRetCode := SSL_write(FProxySslData, ABuffer, ACount);
    if LRetCode > 0 then
      LWritten := LRetCode
    else
      LFatal := SSL_is_fatal_error(SSL_get_error(FProxySslData, LRetCode));
    LEncryptedData := _BIO_read_all(FProxyBIOOut);
  finally
    _SslUnlock;
  end;

  if LFatal or (LEncryptedData = nil) then
  begin
    if Assigned(ACallback) then
      ACallback(Self, False);
    Exit;
  end;

  _RawSend(LEncryptedData,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if not ASuccess then
      begin
        if Assigned(ACallback) then
          ACallback(AConnection, False);
        Exit;
      end;
      if LWritten < ACount then
        _ProxyTlsSend(PByte(ABuffer) + LWritten, ACount - LWritten, ACallback)
      else if Assigned(ACallback) then
        ACallback(AConnection, True);
    end);
end;

procedure TCrossOpenSslConnection._Send(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  if FProxyTlsReady then
    _ProxyTlsSend(ABuffer, ACount, ACallback)
  else
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
  _Send(Pointer(@LBytes[0]), Length(LBytes),
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
  // 与队列操作共用 SSL 锁，关闭后不得因在途 pump 再次入队。
  if FTlsEnded or FCipherClosed or (FPendingWrites = nil) or (ConnectStatus in [csDisconnected, csClosed]) then
    Exit(False);
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
var
  LConnection: ICrossConnection;
  LItem: TPendingWrite;
  LQueued, LRejected: Boolean;
  LCallback: TCrossConnectionCallback;
begin
  LConnection := Self;
  LQueued := False;
  LCallback := ACallback;
  _SslLock;
  try
    LRejected := FTlsEnded or FCipherClosed or (ConnectStatus in [csDisconnected, csClosed]);
    if not LRejected and (ALen > 0) then
    begin
      if (FQueueLimits.MaxWriteCount > 0) or (FQueueLimits.MaxWriteBytes > 0) then
      begin
        LRejected := ((FQueueLimits.MaxWriteCount > 0)
            and (FWriteCount >= FQueueLimits.MaxWriteCount))
          or ((FQueueLimits.MaxWriteBytes > 0)
            and (ALen > FQueueLimits.MaxWriteBytes - FWriteBytes));
        if not LRejected then
        begin
          LCallback := _LimitWriteCallback(ALen, ACallback);
          Inc(FWriteCount);
          Inc(FWriteBytes, ALen);
        end;
      end;
      if not LRejected then
      if FPumping or FHasRetryWrite or (FPendingWrites.Count > 0) then
      begin
        LQueued := _TryEnqueuePendingWrite(ABuf, ALen, LCallback);
        LRejected := not LQueued;
      end else
        FPumping := True;
    end;
  finally
    _SslUnlock;
  end;
  if LRejected or (ALen <= 0) then
  begin
    _CallConnectionCallback(LCallback, LConnection, not LRejected);
    Exit;
  end;
  if LQueued then Exit;
  LItem.Buf := ABuf;
  LItem.Len := ALen;
  LItem.Callback := LCallback;
  _StartPendingWrite(LItem);
end;

procedure TCrossOpenSslConnection._StartPendingWrite(const AItem: TPendingWrite);
var
  LConnection: ICrossConnection;
  LFinish: TCrossConnectionCallback;
  LCompleted: Integer;
begin
  LConnection := Self;
  LCompleted := 0;
  LFinish :=
    procedure(const C: ICrossConnection; const OK: Boolean)
    var
      LNotified, LTlsEnded: Boolean;
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      LNotified := False;
      try
        LNotified := _CallConnectionCallback(AItem.Callback, C, OK);
      finally
        _SslLock;
        try
          FPumping := False;
          LTlsEnded := FTlsEnded;
        finally
          _SslUnlock;
        end;
        if OK and LNotified then
          _PumpPendingWrites
        else
        if LTlsEnded and LNotified then
          _FinishTls
        else
          _CloseCrossData(LConnection);
      end;
    end;
  try
    _SslSendInner(AItem.Buf, AItem.Len, LFinish);
  except
    on E: Exception do
    begin
      _LogException('SSL write failed', E);
      LFinish(LConnection, False);
    end;
  end;
end;

procedure TCrossOpenSslConnection._SslSendInner(const ABuf: PByte;
  const ALen: Integer; const ACallback: TCrossConnectionCallback);
var
  LConnection: ICrossConnection;
  LCurBuf: PByte;
  LRemaining, LWritten, LError: Integer;
  LData: TBytes;
  LFatal, LQueued, LWaiting: Boolean;
  LAfterCipher: TCrossConnectionCallback;
begin
  LConnection := Self;
  LCurBuf := ABuf;
  LRemaining := ALen;
  while LRemaining > 0 do
  begin
    LFatal := False;
    LQueued := False;
    LWaiting := False;
    LData := nil;
    LAfterCipher :=
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        if not OK then
        begin
          _CallConnectionCallback(ACallback, C, False);
          Exit;
        end;
        try
          // 同一 SSL_write 的剩余部分/重试不回到普通队列尾部。
          if LWritten > 0 then
            _SslSendInner(LCurBuf + LWritten, LRemaining - LWritten, ACallback)
          else
            _SslSendInner(LCurBuf, LRemaining, ACallback);
        except
          on E: Exception do
          begin
            _LogException('SSL write continuation failed', E);
            _CallConnectionCallback(ACallback, C, False);
            _CloseCrossData(LConnection);
          end;
        end;
      end;
    _SslLock;
    try
      if FTlsEnded or FCipherClosed or (ConnectStatus in [csDisconnected, csClosed]) then
        LFatal := True
      else
      begin
        LWritten := _SSL_write(LCurBuf, LRemaining);
        if LWritten <= 0 then
        begin
          LFatal := _SSL_handle_error(LWritten, 'SSL_write', LError);
          if not LFatal and not (LError in [SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE]) then
            LFatal := True;
        end;
        if not LFatal then
        begin
          LData := _BIO_read_all;
          if FTlsEnded then LFatal := True else
          if Length(LData) > 0 then
          begin
            // 密文生成和入队不可分开，否则并发调用可能倒置 TLS 记录序号。
            LQueued := _QueueCipherLocked(LData, LAfterCipher);
            LFatal := not LQueued;
          end else
          if LWritten <= 0 then
          begin
            // 在同一次 SSL 锁内登记等待，避免接收线程在登记前唤醒而丢失进展。
            if (FMaxPendingBytes > 0)
              and (FPendingBytes + LRemaining > FMaxPendingBytes) then
              LFatal := True
            else
            begin
              FRetryWrite.Buf := LCurBuf;
              FRetryWrite.Len := LRemaining;
              FRetryWrite.Callback := ACallback;
              FHasRetryWrite := True;
              Inc(FPendingBytes, LRemaining);
              FResumePending := False;
              FPumping := False;
              LWaiting := True;
            end;
          end;
        end;
        if LFatal then _SetTlsEndedLocked(False);
      end;
    finally
      _SslUnlock;
    end;
    if LFatal then
    begin
      try
        _FinishTls;
      finally
        _CallConnectionCallback(ACallback, LConnection, False);
      end;
      Exit;
    end;
    if LWaiting then Exit;
    if LQueued then
    begin
      _PumpCipherWrites;
      Exit;
    end;
    Inc(LCurBuf, LWritten);
    Dec(LRemaining, LWritten);
  end;
  _CallConnectionCallback(ACallback, LConnection,
    not FTlsEnded and not (ConnectStatus in [csDisconnected, csClosed]));
end;

procedure TCrossOpenSslConnection._PumpPendingWrites(const AResume: Boolean);
var
  LItem: TPendingWrite;
  LRetry: Boolean;
begin
  _SslLock;
  try
    if AResume then FResumePending := True;
    if FStartingWrites then Exit;
    FStartingWrites := True;
  finally
    _SslUnlock;
  end;
  try
    while True do
    begin
      _SslLock;
      try
        if FPumping or FTlsEnded or FCipherClosed or (ConnectStatus in [csDisconnected, csClosed])
          or ((not FHasRetryWrite) and ((FPendingWrites = nil) or (FPendingWrites.Count = 0)))
          or (FHasRetryWrite and not FResumePending) then
        begin
          FStartingWrites := False;
          Exit;
        end;
        LRetry := FHasRetryWrite;
        if LRetry then
        begin
          LItem := FRetryWrite;
          Dec(FPendingBytes, LItem.Len);
          FRetryWrite := Default(TPendingWrite);
          FHasRetryWrite := False;
          FResumePending := False;
        end else
        begin
          LItem := FPendingWrites.Dequeue;
          Dec(FPendingBytes, LItem.Len);
        end;
        FPumping := True;
      finally
        _SslUnlock;
      end;
      if LRetry then
      begin
        try
          _SslSendInner(LItem.Buf, LItem.Len, LItem.Callback);
        except
          on E: Exception do
          begin
            _LogException('SSL write retry failed', E);
            _CallConnectionCallback(LItem.Callback, Self, False);
          end;
        end;
      end else
        _StartPendingWrite(LItem);
    end;
  except
    _SslLock;
    try FStartingWrites := False; finally _SslUnlock; end;
    raise;
  end;
end;

function TCrossOpenSslConnection._QueueCipherLocked(const AData: TBytes;
  const ACallback: TCrossConnectionCallback): Boolean;
var
  LItem: TCipherWrite;
begin
  Result := not FTlsEnded and not FCipherClosed and not (ConnectStatus in [csDisconnected, csClosed]);
  if not Result then Exit;
  if not _HasCipherCapacity(Length(AData)) then
  begin
    _CapacityFailedLocked('ciphertext');
    Exit(False);
  end;
  LItem.Data := AData;
  LItem.Callback := ACallback;
  FCipherWrites.Enqueue(LItem);
  if (FQueueLimits.MaxCipherCount > 0) or (FQueueLimits.MaxCipherBytes > 0) then
  begin
    Inc(FCipherCount);
    Inc(FCipherBytes, Length(AData));
  end;
end;

procedure TCrossOpenSslConnection._SendCipherItem(const AItem: TCipherWrite);
var
  LConnection: ICrossConnection;
  LFinish: TCrossConnectionCallback;
  LCompleted: Integer;
begin
  LConnection := Self;
  LCompleted := 0;
  LFinish :=
    procedure(const C: ICrossConnection; const OK: Boolean)
    var
      LSuccess, LTlsEnded: Boolean;
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      _SslLock;
      try
        if (FQueueLimits.MaxCipherCount > 0) or (FQueueLimits.MaxCipherBytes > 0) then
        begin
          Dec(FCipherCount);
          Dec(FCipherBytes, Length(AItem.Data));
        end;
        LTlsEnded := FTlsEnded;
        LSuccess := OK and not FTlsEnded and not FCipherClosed
          and not (LConnection.ConnectStatus in [csDisconnected, csClosed]);
      finally
        _SslUnlock;
      end;
      try
        if not LSuccess then
        begin
          // 仅因 TLS 终态转换的 False 必须保留已解密前缀；真实 I/O 失败立即关闭。
          if OK and LTlsEnded then _FinishTls
          else _CloseCrossData(LConnection);
        end;
        if not _CallConnectionCallback(AItem.Callback, C, LSuccess) then
          _CloseCrossData(LConnection);
      finally
        _SslLock;
        try FCipherSending := False; finally _SslUnlock; end;
        _PumpCipherWrites;
      end;
    end;
  try
    if Length(AItem.Data) = 0 then
      LFinish(LConnection, True)
    else
      _Send(AItem.Data, LFinish);
  except
    on E: Exception do
    begin
      _LogException('SSL ciphertext send failed', E);
      LFinish(LConnection, False);
    end;
  end;
end;

procedure TCrossOpenSslConnection._PumpCipherWrites;
var
  LItem: TCipherWrite;
  LConnection: ICrossConnection;
begin
  LConnection := Self;
  _SslLock;
  try
    if FCipherPumping then Exit;
    FCipherPumping := True;
  finally
    _SslUnlock;
  end;
  try
    while True do
    begin
      _SslLock;
      try
        if FTlsEnded or FCipherClosed or FCipherSending or (FCipherWrites.Count = 0) then
        begin
          FCipherPumping := False;
          Exit;
        end;
        LItem := FCipherWrites.Dequeue;
        FCipherSending := True;
      finally
        _SslUnlock;
      end;
      // 同步完成只复位 Sending；重入 Pump 看见 Pumping 后返回，由本循环继续。
      _SendCipherItem(LItem);
    end;
  except
    _SslLock;
    try FCipherPumping := False; finally _SslUnlock; end;
    LConnection.Close;
    raise;
  end;
end;

procedure TCrossOpenSslConnection._PumpReceivedData;
var
  LConnection: ICrossConnection;
  LData: TBytes;
  LFinished, LTerminate: Boolean;
begin
  LConnection := Self;
  _SslLock;
  try
    if FDeliveringData then Exit;
    FDeliveringData := True;
  finally
    _SslUnlock;
  end;
  try
    while True do
    begin
      _SslLock;
      try
        LFinished := not FConnectedPublished or FCipherClosed
          or (ConnectStatus in [csDisconnected, csClosed]) or (FReceivedData.Count = 0);
        LTerminate := FTlsEnded and not FCipherClosed;
        if LFinished then
        begin
          FDeliveringData := False;
        end else
          LData := FReceivedData.Dequeue;
      finally
        _SslUnlock;
      end;
      if LFinished then
      begin
        if LTerminate then _FinishTls;
        Exit;
      end;
      // 明文独立按解密顺序发布，不等待已连接会话的协议输出或慢发送。
      try
        TCrossOpenSslSocket(Owner)._Received(LConnection, @LData[0], Length(LData));
      finally
        if (FQueueLimits.MaxReceivedCount > 0) or (FQueueLimits.MaxReceivedBytes > 0) then
        begin
          _SslLock;
          try
            Dec(FReceivedCount);
            Dec(FReceivedBytes, Length(LData));
          finally
            _SslUnlock;
          end;
        end;
        LData := nil;
      end;
    end;
  except
    _SslLock;
    try FDeliveringData := False; finally _SslUnlock; end;
    _CloseCrossData(LConnection);
    raise;
  end;
end;

procedure TCrossOpenSslConnection._SetTlsEndedLocked(const AReplyClose: Boolean);
begin
  if FTlsEnded then Exit;
  FTlsEnded := True;
  // 仅正常 close_notify 可回送关闭通知；fatal 后不能再调用 SSL_shutdown。
  if AReplyClose then
  begin
    ERR_clear_error();
    SSL_shutdown(FSslData);
  end;
  FTerminalData := _BIO_read_all;
  if (Length(FTerminalData) > 0)
    and ((FQueueLimits.MaxCipherCount > 0) or (FQueueLimits.MaxCipherBytes > 0)) then
  begin
    Inc(FCipherCount);
    Inc(FCipherBytes, Length(FTerminalData));
    FTerminalCounted := True;
  end;
end;

procedure TCrossOpenSslConnection._FinishTls;
var
  LConnection: ICrossConnection;
  LItem: TCipherWrite;
  LSend, LDefer: Boolean;
begin
  LConnection := Self;
  _SslLock;
  try
    if FCipherClosed then Exit;
    LSend := False;
    LDefer := FConnectedPublished and (FDeliveringData or (FReceivedData.Count > 0));
    if not LDefer then
    begin
      // 不能跳过已生成的记录抢发 alert，也不能等待对端读取才关闭。
      LSend := (Length(FTerminalData) > 0) and not FCipherSending
        and (FCipherWrites.Count = 0);
      if LSend then
      begin
        LItem.Data := FTerminalData;
        LItem.Callback := nil;
        FCipherSending := True;
      end;
      if FTerminalCounted then
      begin
        // 发送时转移至物理项；不能发送时就在这里归还终态缓冲的额度。
        if not LSend then
        begin
          Dec(FCipherCount);
          Dec(FCipherBytes, Length(FTerminalData));
        end;
        FTerminalCounted := False;
      end;
      FTerminalData := nil;
      FCipherClosed := True;
    end;
  finally
    _SslUnlock;
  end;
  if LDefer then
  begin
    // 发布泵自身或另一个线程会在前缀全部交付后再次进入本方法。
    _PumpReceivedData;
    Exit;
  end;
  _LogTlsError;
  try
    if LSend then _SendCipherItem(LItem);
  finally
    // 在途 alert/数据仍由物理完成闭包保活；此处只取消未提交项。
    _CloseCrossData(LConnection);
  end;
end;

procedure TCrossOpenSslConnection._LogTlsError;
var
  LText: string;
begin
  if FLock = nil then Exit;
  _SslLock;
  try
    LText := FFatalLog;
    FFatalLog := '';
  finally
    _SslUnlock;
  end;
  if LText = '' then Exit;
  // 日志可以重入或等待另一发送线程；不能持有 SSL 锁，也不能中断前缀/关闭收尾。
  try
    _Log(LText);
  except
    // 不再通过同一个用户日志记录日志异常，避免递归。
  end;
end;

procedure TCrossOpenSslConnection._DrainCipherWritesAsFailed(const AConnection: ICrossConnection);
var
  LItems: TArray<TCipherWrite>;
  I: Integer;
begin
  _SslLock;
  try
    FCipherClosed := True;
    SetLength(LItems, FCipherWrites.Count);
    for I := 0 to High(LItems) do
    begin
      LItems[I] := FCipherWrites.Dequeue;
      if (FQueueLimits.MaxCipherCount > 0) or (FQueueLimits.MaxCipherBytes > 0) then
      begin
        Dec(FCipherCount);
        Dec(FCipherBytes, Length(LItems[I].Data));
      end;
    end;
    // 已交给物理发送的条目由其完成闭包持有，不能在这里释放缓冲。
  finally
    _SslUnlock;
  end;
  for I := 0 to High(LItems) do
    _CallConnectionCallback(LItems[I].Callback, AConnection, False);
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
    if FPendingWrites = nil then Exit;
    LCount := FPendingWrites.Count;
    if FHasRetryWrite then Inc(LCount);
    if LCount = 0 then Exit;
    SetLength(LDrained, LCount);
    I := 0;
    if FHasRetryWrite then
    begin
      LDrained[0] := FRetryWrite;
      FRetryWrite := Default(TPendingWrite);
      FHasRetryWrite := False;
      Inc(I);
    end;
    while I < LCount do
    begin
      LDrained[I] := FPendingWrites.Dequeue;
      Inc(I);
    end;
    FPendingBytes := 0;
  finally
    _SslUnlock;
  end;

  for I := 0 to High(LDrained) do
    if Assigned(LDrained[I].Callback) then
      try
        LDrained[I].Callback(AConnection, False);
      except
        // 单个完成通知异常不能阻止后续条目释放保活引用。
        on E: Exception do
          _LogException('SSL pending callback failed', E);
      end;
end;

{ TCrossOpenSslSocket }

procedure TCrossOpenSslSocket.SetSslQueueLimits(const AValue: TCrossSslQueueLimits);
begin
  ValidateSslQueueLimits(AValue);
  BeginTlsConfigUpdate;
  try
    FQueueLimits := AValue;
  finally
    EndTlsConfigUpdate;
  end;
end;

constructor TCrossOpenSslSocket.Create(const AIoThreads: Integer; const ASsl: Boolean);
begin
  inherited Create(AIoThreads, ASsl);

  if Ssl then
    EnsureSslCtx;
end;

destructor TCrossOpenSslSocket.Destroy;
begin
  // 先调 inherited 关闭所有连接: 各连接的 SSL_free 只减 CTX 引用计数,
  // 不依赖 CTX 存活 (OpenSSL 保证), 所以 CTX 可以延后释放.
  inherited Destroy;

  if FTlsRuntimeLoaded or FSslLoaded then
  begin
    _FreeSslCtx;
    FSslLoaded := False;
    TSSLTools.UnloadSSL;
  end;
end;

procedure TCrossOpenSslSocket.EnsureSslCtx;
begin
  if not FTlsRuntimeLoaded then
  begin
    TSSLTools.LoadSSL;
    FTlsRuntimeLoaded := True;
    FSslLoaded := True;
  end;
  _InitSslCtx;
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
  // 限制最低版本，最高版本沿用运行库及系统配置。
  ERR_clear_error();
  if SSL_CTX_set_min_proto_version(FSslCtx, TLS1_2_VERSION) <> 1 then
    raise ESsl.CreateFmt('Failed to set minimum TLS version: %s.',
      [GetOpenSslErrors]);

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

  SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
  SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
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

  if (AConnectionObj <> nil) and (AConnectionObj.ConnectStatus in [csDisconnected, csClosed]) then
  begin
    ADecryptedData := nil;
    Exit;
  end;
  if (AConnectionObj <> nil) and AConnectionObj.FTlsEnded then
  begin
    ADecryptedData := nil;
    AConnectionObj._PumpReceivedData;
    Exit;
  end;
  // 多个接收批次可能排在握手输出之后，连接通知仍只能发布一次。
  if ATriggerConnected and (AConnectionObj <> nil)
    and (AConnectionObj.ConnectStatus = csHandshaking) then
    _Connected(LConnection);
  if (AConnectionObj <> nil) and (AConnectionObj.ConnectStatus in [csDisconnected, csClosed]) then
  begin
    ADecryptedData := nil;
    Exit;
  end;

  if AConnectionObj <> nil then
  begin
    AConnectionObj._SslLock;
    try
      if AConnectionObj.ConnectStatus = csConnected then
        AConnectionObj.FConnectedPublished := True;
      if ADecryptedData <> nil then
      begin
        AConnectionObj.FReceivedData.Enqueue(ADecryptedData);
        ADecryptedData := nil;
      end;
    finally
      AConnectionObj._SslUnlock;
    end;
    AConnectionObj._PumpReceivedData;
  end;

  // 握手 fatal: alert 已发出, 关闭连接释放资源
  if AFatal then
  begin
    if (AConnectionObj <> nil) then
      AConnectionObj.Close;
  end else if (AConnectionObj <> nil) then
    AConnectionObj._PumpPendingWrites(True);
end;

procedure TCrossOpenSslSocket._FreeSslCtx;
begin
  if (FSslCtx = nil) then Exit;

  TSSLTools.FreeCTX(FSslCtx);
end;

procedure TCrossOpenSslSocket.ApplyVerifyPeer(const AValue: Boolean);
begin
  if AValue then
    SSL_CTX_set_verify(FSslCtx,
      SSL_VERIFY_PEER or SSL_VERIFY_FAIL_IF_NO_PEER_CERT, nil)
  else
    SSL_CTX_set_verify(FSslCtx, SSL_VERIFY_NONE, nil);
end;

procedure TCrossOpenSslSocket.AddCACertificate(const ABuf: Pointer;
  const ASize: Integer);
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    try
      TSSLTools.AddCACertificate(FSslCtx, ABuf, ASize);
      MarkCACertificateAdded;
    except
      on E: ESslContextInvalid do
      begin
        InvalidateTlsConfiguration;
        raise;
      end;
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossOpenSslSocket.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    TSSLTools.SetCertificate(FSslCtx, ACertBuf, ACertBufSize);
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossOpenSslSocket.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer; const APassword: string);
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    TSSLTools.SetPrivateKey(FSslCtx, APKeyBuf, APKeyBufSize, APassword);
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossOpenSslSocket.SetTls12CipherSuites(const ACipherRules: string);
var
  LAnsi: AnsiString;
  LError: string;
begin
  if not Ssl or (ACipherRules = '') then Exit;

  BeginTlsConfigUpdate;
  try
    if FSslCtx = nil then
    begin
      InvalidateTlsConfiguration;
      raise ESslContextInvalid.Create('SetTls12CipherSuites: SSL context is nil.');
    end;

    LAnsi := AnsiString(ACipherRules);
    ERR_clear_error();
    try
      if SSL_CTX_set_cipher_list(FSslCtx, PAnsiChar(LAnsi)) <> 1 then
      begin
        // 原生 API 可能已改变名单或安全级别，失败后禁止继续创建连接。
        InvalidateTlsConfiguration;
        LError := GetOpenSslErrors;
        raise ESslContextInvalid.CreateFmt(
          'SetTls12CipherSuites failed; recreate the socket before using TLS: %s.',
          [LError]);
      end;
    finally
      // 清理本次调用的错误状态，避免污染同线程后续 OpenSSL 操作。
      ERR_clear_error();
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossOpenSslSocket.SetTls13CipherSuites(const ACipherSuites: string);
var
  LAnsi: AnsiString;
  LError: string;
begin
  // 明确选择空串不操作，不使用原生 API 的空列表语义。
  if not Ssl or (ACipherSuites = '') then Exit;

  BeginTlsConfigUpdate;
  try
    if FSslCtx = nil then
    begin
      InvalidateTlsConfiguration;
      raise ESslContextInvalid.Create('SetTls13CipherSuites: SSL context is nil.');
    end;

    LAnsi := AnsiString(ACipherSuites);
    ERR_clear_error();
    try
      if SSL_CTX_set_ciphersuites(FSslCtx, PAnsiChar(LAnsi)) <> 1 then
      begin
        // 两版本统一采用原生更新失败后重建对象的保守契约。
        InvalidateTlsConfiguration;
        LError := GetOpenSslErrors;
        raise ESslContextInvalid.CreateFmt(
          'SetTls13CipherSuites failed; recreate the socket before using TLS: %s.',
          [LError]);
      end;
    finally
      ERR_clear_error();
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossOpenSslSocket.SetMinTlsVersion(const AVersion: TCrossTlsMinVersion);
var
  LVersion, LActual: Integer;
  LError: string;
begin
  if not Ssl then Exit;

  case AVersion of
    tmvTls13: LVersion := TLS1_3_VERSION;
  else
    LVersion := TLS1_2_VERSION;
  end;

  BeginTlsConfigUpdate;
  try
    if FSslCtx = nil then
    begin
      InvalidateTlsConfiguration;
      raise ESslContextInvalid.Create('SetMinTlsVersion: SSL context is nil.');
    end;

    ERR_clear_error();
    try
      if SSL_CTX_set_min_proto_version(FSslCtx, LVersion) <> 1 then
      begin
        InvalidateTlsConfiguration;
        LError := GetOpenSslErrors;
        raise ESslContextInvalid.CreateFmt(
          'SetMinTlsVersion failed; recreate the socket before using TLS: %s.',
          [LError]);
      end;

      // 回读确认：返回成功但未生效时同样视为失败，避免静默弱于配置。
      LActual := SSL_CTX_get_min_proto_version(FSslCtx);
      if LActual <> LVersion then
      begin
        InvalidateTlsConfiguration;
        raise ESslContextInvalid.CreateFmt(
          'SetMinTlsVersion: the context reports minimum $%.4x after setting $%.4x; ' +
          'recreate the socket before using TLS.', [LActual, LVersion]);
      end;
    finally
      ERR_clear_error();
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossOpenSslSocket.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnection: TCrossOpenSslConnection;
  LRetCode, LError: Integer;
  LHandshakeData: TBytes;
  LFatal, LQueued: Boolean;
  LProxyData: TBytes;
begin
  LConnection := AConnection as TCrossOpenSslConnection;

  if LConnection.ProxyUsesTlsTransport and not LConnection.ProxyTlsStarted then
  begin
    if LConnection._StartProxyTls(LProxyData) then
      LConnection._RawSend(LProxyData,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          if not ASuccess then
            LConnection.Close;
        end)
    else
      LConnection.Close;
    Exit;
  end;

  if LConnection.ProxyNeedsHandshake then
  begin
    if LConnection.ProxyStart(LProxyData) then
      LConnection.SendProxyBytes(LProxyData);
    Exit;
  end;

  if not Ssl then
  begin
    _Connected(LConnection);
    Exit;
  end;
  LFatal := False;
  LQueued := False;
  LConnection._SslLock;
  try
    if LConnection.FTlsEnded or LConnection.FCipherClosed or (LConnection.ConnectStatus in [csDisconnected, csClosed]) then Exit;
    LConnection.ConnectStatus := csHandshaking;
    LRetCode := LConnection._SSL_do_handshake;
    if LRetCode <> 1 then
    begin
      LFatal := LConnection._SSL_handle_error(LRetCode, 'SSL_do_handshake(TriggerConnected)', LError);
      LFatal := LFatal or (LError = SSL_ERROR_ZERO_RETURN);
    end;
    if LFatal then
      LConnection._SetTlsEndedLocked(False)
    else
      LHandshakeData := LConnection._BIO_read_all;
    if Length(LHandshakeData) > 0 then
      LQueued := LConnection._QueueCipherLocked(LHandshakeData,
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          if LFatal or not OK then LConnection.Close;
        end);
    LFatal := LFatal or LConnection.FTlsEnded;
  finally
    LConnection._SslUnlock;
  end;
  if LFatal then
  begin
    LConnection._FinishTls;
    Exit;
  end;
  if LQueued then LConnection._PumpCipherWrites
  else
  if LFatal or (Length(LHandshakeData) > 0) then LConnection.Close;
end;

procedure TCrossOpenSslSocket._ProcessReceivedPayload(
  const AConnection: ICrossConnection; const APayload: Pointer;
  const APayloadLen: Integer);
var
  LConnectionObj: TCrossOpenSslConnection;
  LRetCode, LError: Integer;
  LReadResult: TCrossOpenSslConnection.TSslReadResult;
  LTriggerConnected, LQueued, LFatal, LHandshakeDone, LInitialHandshake: Boolean;
  LDecryptedData, LHandshakeData: TBytes;
  LProxyData, LRemain: TBytes;
  LProxyResult: TCrossProxyFeedResult;
begin
  LConnectionObj := AConnection as TCrossOpenSslConnection;
  if (APayload = nil) or (APayloadLen <= 0) then
    Exit;

  if LConnectionObj.ProxyNeedsHandshake then
  begin
    LProxyResult := LConnectionObj.ProxyFeed(APayload, APayloadLen,
      LProxyData, LRemain);
    case LProxyResult of
      cpfrSendData:
        LConnectionObj.SendProxyBytes(LProxyData);
      cpfrComplete:
        begin
          TriggerConnected(AConnection);
          if Length(LRemain) > 0 then
            _ProcessReceivedPayload(AConnection, @LRemain[0], Length(LRemain));
        end;
      cpfrFailed:
        LConnectionObj.Close;
    end;
    Exit;
  end;

  if not Ssl then
  begin
    _Received(AConnection, APayload, APayloadLen);
    Exit;
  end;
  LTriggerConnected := False;
  LQueued := False;
  LFatal := False;
  LDecryptedData := nil;
  LHandshakeData := nil;
  LReadResult := srWant;
  LConnectionObj._SslLock;
  try
    if LConnectionObj.FTlsEnded or LConnectionObj.FCipherClosed
      or (LConnectionObj.ConnectStatus in [csDisconnected, csClosed]) then Exit;
    LHandshakeDone := LConnectionObj._SSL_is_init_finished <> 0;
    if (LConnectionObj.ConnectStatus = csHandshaking) and not LHandshakeDone then
    begin
      Inc(LConnectionObj.FHandshakeRecvBytes, APayloadLen);
      if LConnectionObj.FHandshakeRecvBytes > MAX_HANDSHAKE_RECV_BYTES then
        LFatal := True;
    end;
    if not LFatal then
    begin
      LRetCode := LConnectionObj._BIO_write(APayload, APayloadLen);
      if LRetCode <> APayloadLen then
        LFatal := LConnectionObj._SSL_handle_error(LRetCode, 'BIO_write')
      else
      if LHandshakeDone or (LConnectionObj.ConnectStatus = csConnected) then
      begin
        LTriggerConnected := LConnectionObj.ConnectStatus = csHandshaking;
        LDecryptedData := LConnectionObj._SSL_read_all(LReadResult);
      end else
      if LConnectionObj.ConnectStatus = csHandshaking then
      begin
        LRetCode := LConnectionObj._SSL_do_handshake;
        if LRetCode <> 1 then
        begin
          LFatal := LConnectionObj._SSL_handle_error(
            LRetCode, 'SSL_do_handshake(TriggerReceived)', LError);
          LFatal := LFatal or (LError = SSL_ERROR_ZERO_RETURN);
        end else
        begin
          LTriggerConnected := True;
          LDecryptedData := LConnectionObj._SSL_read_all(LReadResult);
        end;
      end;
    end;
    LFatal := LFatal or (LReadResult <> srWant);
    if LFatal then
      LConnectionObj._SetTlsEndedLocked(LReadResult = srClosed);
    if LDecryptedData <> nil then
    begin
      LConnectionObj.FReceivedData.Enqueue(LDecryptedData);
      if (LConnectionObj.FQueueLimits.MaxReceivedCount > 0)
        or (LConnectionObj.FQueueLimits.MaxReceivedBytes > 0) then
      begin
        Inc(LConnectionObj.FReceivedCount);
        Inc(LConnectionObj.FReceivedBytes, Length(LDecryptedData));
      end;
      LDecryptedData := nil;
    end;
    if not LFatal then LHandshakeData := LConnectionObj._BIO_read_all;
    LFatal := LFatal or LConnectionObj.FTlsEnded;
    LInitialHandshake := not LConnectionObj.FConnectedPublished;
    if not LFatal and LInitialHandshake then
      LQueued := LConnectionObj._QueueCipherLocked(LHandshakeData,
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          _FinishHandshakeProgress(OK, LConnectionObj, LTriggerConnected, LDecryptedData, LFatal);
        end)
    else
    if Length(LHandshakeData) > 0 then
      LQueued := LConnectionObj._QueueCipherLocked(LHandshakeData,
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          if LFatal or not OK then _CloseCrossData(C);
        end);
    LFatal := LFatal or LConnectionObj.FTlsEnded;
  finally
    LConnectionObj._SslUnlock;
  end;
  {$IFDEF CROSS_OPENSSL_SELFTEST}
  if Assigned(CrossOpenSslSelfTest_BeforeReceived) then
    CrossOpenSslSelfTest_BeforeReceived(AConnection, True);
  {$ENDIF}
  if LFatal then
  begin
    LConnectionObj._PumpReceivedData;
    Exit;
  end;
  if LInitialHandshake then
  begin
    if LQueued then LConnectionObj._PumpCipherWrites
    else _FinishHandshakeProgress(True, LConnectionObj, LTriggerConnected, LDecryptedData, LFatal);
  end else
  begin
    LConnectionObj._PumpReceivedData;
    if not LFatal then LConnectionObj._PumpPendingWrites(True);
    if LQueued then LConnectionObj._PumpCipherWrites
    else if LFatal then _CloseCrossData(AConnection);
  end;
end;

procedure TCrossOpenSslSocket._FinishProxyTlsReceive(
  const AConnection: ICrossConnection; const ASuccess: Boolean;
  const APlainData: TBytes; const AHandshakeCompleted: Boolean);
var
  LConnectionObj: TCrossOpenSslConnection;
begin
  LConnectionObj := AConnection as TCrossOpenSslConnection;
  if not ASuccess then
  begin
    LConnectionObj.Close;
    Exit;
  end;
  if AHandshakeCompleted then
    TriggerConnected(AConnection);
  if Length(APlainData) > 0 then
    _ProcessReceivedPayload(AConnection, @APlainData[0], Length(APlainData));
end;

procedure TCrossOpenSslSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnectionObj: TCrossOpenSslConnection;
  LPlainData, LHandshakeData: TBytes;
  LHandshakeCompleted: Boolean;
begin
  LConnectionObj := AConnection as TCrossOpenSslConnection;
  if LConnectionObj.ProxyUsesTlsTransport then
  begin
    if not LConnectionObj._FeedProxyTls(ABuf, ALen, LPlainData,
      LHandshakeData, LHandshakeCompleted) then
    begin
      LConnectionObj.Close;
      Exit;
    end;

    if Length(LHandshakeData) > 0 then
      LConnectionObj._RawSend(LHandshakeData,
        procedure(const AInnerConnection: ICrossConnection;
          const ASuccess: Boolean)
        begin
          _FinishProxyTlsReceive(AInnerConnection, ASuccess, LPlainData,
            LHandshakeCompleted);
        end)
    else
      _FinishProxyTlsReceive(AConnection, True, LPlainData,
        LHandshakeCompleted);
  end else
    _ProcessReceivedPayload(AConnection, ABuf, ALen);
end;

end.
