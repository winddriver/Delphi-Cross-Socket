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
  Generics.Collections,
  Utils.SyncObjs,

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket.Types,
  Net.MbedTls;

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
  private type
    TWrite = record
      Data: PByte;
      Count: Integer;
      Callback: TCrossConnectionCallback;
    end;
    TAction = (maIdle, maContinue, maCipher, maConnected, maReceived, maDone, maFailed, maClose);
  private
    FSsl: TMbedtls_SSL_Context;
    FLock: ILock;
    FInput: TBytes;
    FInputHead, FInputCount: Integer;
    FOutput: TMemoryStream;
    FWrites: TQueue<TWrite>;
    FActive: TWrite;
    FHasActive, FPumping, FCipherPending, FClosed: Boolean;
    FStarted, FHandshakeDone, FConnectedNotified, FReadReady: Boolean;
    FRetryWrite, FWriteNeedsInput: Boolean;

    function _Step(out AData: TBytes; out ACallback: TCrossConnectionCallback): TAction;
    procedure _Pump;
    procedure _SendCipher(const AData: TBytes);
    procedure _Receive(const ABuf: Pointer; const ALen: Integer);
  protected
    procedure InternalClose; override;
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
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
    procedure _Connected(const AConnection: ICrossConnection);
    procedure _Received(const AConnection: ICrossConnection; const AData: TBytes);
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
    procedure SetMinTlsVersion(const AVersion: TCrossTlsMinVersion); override;
  end;

{$IFDEF CROSS_MBEDTLS_SELFTEST}
var
  CrossMbedTlsTestWrite: function(const AData: Pointer; const ACount: Integer;
    out AResult: Integer): Boolean;
procedure CrossMbedTlsSelfTest_GetMinProtocolVersions(const ASocket: TCrossMbedTlsSocket;
  out AClientVersion, AServerVersion: Integer);
{$ENDIF}

implementation

{$IFDEF CROSS_MBEDTLS_SELFTEST}
procedure CrossMbedTlsSelfTest_GetMinProtocolVersions(const ASocket: TCrossMbedTlsSocket;
  out AClientVersion, AServerVersion: Integer);
begin
  ASocket.BeginTlsConfigUpdate;
  try
    AClientVersion := (Integer(ASocket.FCliConf.min_major_ver) shl 8) or
      ASocket.FCliConf.min_minor_ver;
    AServerVersion := (Integer(ASocket.FSrvConf.min_major_ver) shl 8) or
      ASocket.FSrvConf.min_minor_ver;
  finally
    ASocket.EndTlsConfigUpdate;
  end;
end;
{$ENDIF}

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

  function _Matches(const AMarker: AnsiString): Boolean;
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

// 读回调返回当前全部可用密文；输出缓冲限制为一个块，真实背压由发送泵恢复。
function MbedRecv(AContext: Pointer; ABuffer: Pointer; ASize: Size_T): Integer; cdecl;
var
  LConnection: TCrossMbedTlsConnection;
begin
  LConnection := TCrossMbedTlsConnection(AContext);
  if LConnection.FInputCount = 0 then Exit(MBEDTLS_ERR_SSL_WANT_READ);
  Result := Length(LConnection.FInput) - LConnection.FInputHead;
  if Result > LConnection.FInputCount then Result := LConnection.FInputCount;
  if ASize < Size_T(Result) then Result := ASize;
  Move(LConnection.FInput[LConnection.FInputHead], ABuffer^, Result);
  Dec(LConnection.FInputCount, Result);
  Inc(LConnection.FInputHead, Result);
  if (LConnection.FInputCount = 0) or
    (LConnection.FInputHead = Length(LConnection.FInput)) then LConnection.FInputHead := 0;
end;

function MbedSend(AContext: Pointer; ABuffer: Pointer; ASize: Size_T): Integer; cdecl;
const
  CIPHER_BLOCK = 16384;
var
  LOutput: TMemoryStream;
begin
  try
    LOutput := TCrossMbedTlsConnection(AContext).FOutput;
    Result := CIPHER_BLOCK - Integer(LOutput.Size);
    if Result = 0 then Exit(MBEDTLS_ERR_SSL_WANT_WRITE);
    if ASize < Size_T(Result) then Result := ASize;
    LOutput.WriteBuffer(ABuffer^, Result);
  except
    Result := MBEDTLS_ERR_SSL_ALLOC_FAILED;
  end;
end;

constructor TCrossMbedTlsConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectedCb: TCrossConnectionCallback);
var
  LHostAnsi: AnsiString;
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectedCb);

  if Ssl then
  begin
    FLock := TLock.Create;
    FOutput := TMemoryStream.Create;
    FWrites := TQueue<TWrite>.Create;
    TCrossMbedTlsSocket(Owner).LockTlsConfiguration;
    mbedtls_ssl_init(@FSsl);

    if (ConnectType = ctAccept) then
      MbedCheck(mbedtls_ssl_setup(@Fssl, @TCrossMbedTlsSocket(Owner).FSrvConf), 'mbedtls_ssl_setup Accept:')
    else
      MbedCheck(mbedtls_ssl_setup(@Fssl, @TCrossMbedTlsSocket(Owner).FCliConf), 'mbedtls_ssl_setup Connect:');

    mbedtls_ssl_set_bio(@FSsl, Self, MbedSend, MbedRecv, nil);

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

destructor TCrossMbedTlsConnection.Destroy;
begin
  if Ssl then
  begin
    mbedtls_ssl_free(@FSsl);
    FWrites.Free;
    FOutput.Free;
  end;
  inherited;
end;

procedure TCrossMbedTlsConnection.InternalClose;
begin
  try
    if FLock <> nil then
    begin
      FLock.Enter;
      try
        FClosed := True;
        FInput := nil;
        FInputHead := 0;
        FInputCount := 0;
        FOutput.Clear;
      finally FLock.Leave; end;
      _Pump;
    end;
  finally
    inherited;
  end;
end;

procedure TCrossMbedTlsConnection._SendCipher(const AData: TBytes);
var
  LData: TBytes;
  LConnection: ICrossConnection;
  LCompleted: Integer;
  LFinish: TCrossConnectionCallback;
begin
  LData := AData;
  LConnection := Self;
  LCompleted := 0;
  LFinish := procedure(const C: ICrossConnection; const OK: Boolean)
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      FLock.Enter;
      try
        FCipherPending := False;
        if not OK then FClosed := True;
      finally FLock.Leave; end;
      LData := nil;
      if not OK then _CloseCrossData(LConnection);
      _Pump;
    end;
  try
    inherited DirectSend(Pointer(LData), Length(LData), LFinish);
  except
    LFinish(LConnection, False);
    raise;
  end;
end;

function TCrossMbedTlsConnection._Step(out AData: TBytes;
  out ACallback: TCrossConnectionCallback): TAction;
var
  LCode: Integer;
begin
  Result := maIdle;
  if (FClosed or IsClosed) then
  begin
    if not FHasActive then
    begin
      if FWrites.Count = 0 then Exit;
      FActive := FWrites.Dequeue;
    end;
    ACallback := FActive.Callback;
    FActive := Default(TWrite);
    FHasActive := False;
    Exit(maFailed);
  end;
  if not FStarted then Exit;

  if FOutput.Size > 0 then
  begin
    if FCipherPending then Exit;
    SetLength(AData, FOutput.Size);
    Move(FOutput.Memory^, AData[0], Length(AData));
    FOutput.Size := 0;
    FCipherPending := True;
    Exit(maCipher);
  end;

  if not FHandshakeDone then
  begin
    if not FReadReady then Exit;
    LCode := mbedtls_ssl_handshake(@FSsl);
    case LCode of
      0: FHandshakeDone := True;
      MBEDTLS_ERR_SSL_WANT_READ: FReadReady := False;
      MBEDTLS_ERR_SSL_WANT_WRITE: if FOutput.Size = 0 then Exit(maClose);
    else Exit(maClose);
    end;
    Exit(maContinue);
  end;
  if not FConnectedNotified then
  begin
    if FCipherPending then Exit;
    FConnectedNotified := True;
    Exit(maConnected);
  end;

  if FReadReady and not FRetryWrite then
  begin
    SetLength(AData, 16384);
    LCode := mbedtls_ssl_read(@FSsl, Pointer(AData), Length(AData));
    if LCode > 0 then
    begin
      SetLength(AData, LCode);
      Exit(maReceived);
    end;
    case LCode of
      MBEDTLS_ERR_SSL_WANT_READ: FReadReady := False;
      MBEDTLS_ERR_SSL_WANT_WRITE: if FOutput.Size = 0 then Exit(maClose);
    else Exit(maClose);
    end;
    Exit(maContinue);
  end;

  if FCipherPending or FWriteNeedsInput then Exit;
  if not FHasActive then
  begin
    if FWrites.Count = 0 then Exit;
    FActive := FWrites.Dequeue;
    FHasActive := True;
  end;
  if FActive.Count <= 0 then
  begin
    ACallback := FActive.Callback;
    FActive := Default(TWrite);
    FHasActive := False;
    Exit(maDone);
  end;

  // WANT 必须用同一指针和长度重试。只有正数返回才允许推进本次写入。
  {$IFDEF CROSS_MBEDTLS_SELFTEST}
  if not Assigned(CrossMbedTlsTestWrite) or
    not CrossMbedTlsTestWrite(FActive.Data, FActive.Count, LCode) then
  {$ENDIF}
    LCode := mbedtls_ssl_write(@FSsl, FActive.Data, FActive.Count);
  FRetryWrite := LCode < 0;
  case LCode of
    MBEDTLS_ERR_SSL_WANT_READ: FWriteNeedsInput := True;
    MBEDTLS_ERR_SSL_WANT_WRITE: if FOutput.Size = 0 then Exit(maClose);
  else
    if (LCode <= 0) or (LCode > FActive.Count) then Exit(maClose);
    Inc(FActive.Data, LCode);
    Dec(FActive.Count, LCode);
  end;
  Result := maContinue;
end;

procedure TCrossMbedTlsConnection._Pump;
var
  LConnection: ICrossConnection;
  LAction: TAction;
  LData: TBytes;
  LCallback: TCrossConnectionCallback;
begin
  LConnection := Self;
  FLock.Enter;
  try
    if FPumping then Exit;
    FPumping := True;
  finally FLock.Leave; end;
  while True do
  begin
    LCallback := nil;
    LData := nil;
    try
      FLock.Enter;
      try
        LAction := _Step(LData, LCallback);
        if LAction = maIdle then
        begin
          FPumping := False;
          Exit;
        end;
        if LAction = maClose then FClosed := True;
      finally FLock.Leave; end;
      case LAction of
        maCipher: _SendCipher(LData);
        maConnected: TCrossMbedTlsSocket(Owner)._Connected(LConnection);
        maReceived: TCrossMbedTlsSocket(Owner)._Received(LConnection, LData);
        maDone, maFailed:
          if not _CallConnectionCallback(LCallback, LConnection, LAction = maDone) then
            _CloseCrossData(LConnection);
        maClose: _CloseCrossData(LConnection);
      end;
    except
      on E: Exception do
      begin
        _LogException('Mbed TLS I/O', E);
        _CloseCrossData(LConnection);
      end;
    end;
  end;
end;

procedure TCrossMbedTlsConnection._Receive(const ABuf: Pointer; const ALen: Integer);
const
  MAX_PENDING_INPUT = 128 * 1024;
var
  LCapacity, LNewCapacity, LFirst, LPosition: Integer;
  LBuffer: TBytes;
  LExceeded: Boolean;
begin
  if ALen <= 0 then Exit;
  LExceeded := False;
  FLock.Enter;
  try
    if FClosed or IsClosed then Exit;
    // 慢业务回调或反方向写阻塞时，只接纳有界的未消费密文。
    LExceeded := ALen > MAX_PENDING_INPUT - FInputCount;
    if LExceeded then
      FClosed := True
    else
    begin
      LCapacity := Length(FInput);
      if ALen > LCapacity - FInputCount then
      begin
        LNewCapacity := LCapacity;
        if LNewCapacity = 0 then LNewCapacity := 16384;
        while LNewCapacity < FInputCount + ALen do LNewCapacity := LNewCapacity * 2;
        SetLength(LBuffer, LNewCapacity);
        LFirst := LCapacity - FInputHead;
        if LFirst > FInputCount then LFirst := FInputCount;
        if LFirst > 0 then Move(FInput[FInputHead], LBuffer[0], LFirst);
        if FInputCount > LFirst then Move(FInput[0], LBuffer[LFirst], FInputCount - LFirst);
        FInput := LBuffer;
        FInputHead := 0;
        LCapacity := LNewCapacity;
      end;
      LPosition := (FInputHead + FInputCount) mod LCapacity;
      LFirst := LCapacity - LPosition;
      if LFirst > ALen then LFirst := ALen;
      Move(ABuf^, FInput[LPosition], LFirst);
      if ALen > LFirst then Move((PByte(ABuf) + LFirst)^, FInput[0], ALen - LFirst);
      Inc(FInputCount, ALen);
      FReadReady := True;
      FWriteNeedsInput := False;
    end;
  finally FLock.Leave; end;
  if LExceeded then _CloseCrossData(Self as ICrossConnection)
  else _Pump;
end;

procedure TCrossMbedTlsConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LWrite: TWrite;
begin
  if not Ssl then
  begin inherited DirectSend(ABuffer, ACount, ACallback); Exit; end;
  if (ACount < 0) or ((ACount > 0) and (ABuffer = nil)) then
  begin _CallConnectionCallback(ACallback, Self, False); Exit; end;
  LWrite.Data := ABuffer;
  LWrite.Count := ACount;
  LWrite.Callback := ACallback;
  FLock.Enter;
  try FWrites.Enqueue(LWrite); finally FLock.Leave; end;
  _Pump;
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

procedure TCrossMbedTlsSocket._Connected(const AConnection: ICrossConnection);
begin
  inherited TriggerConnected(AConnection);
end;

procedure TCrossMbedTlsSocket._Received(const AConnection: ICrossConnection; const AData: TBytes);
begin
  inherited TriggerReceived(AConnection, Pointer(AData), Length(AData));
end;

procedure TCrossMbedTlsSocket.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnection: TCrossMbedTlsConnection;
begin
  if not Ssl then
  begin inherited; Exit; end;
  LConnection := AConnection as TCrossMbedTlsConnection;
  LConnection.FLock.Enter;
  try
    if LConnection.FClosed or (LConnection.ConnectStatus in [csDisconnected, csClosed]) then Exit;
    LConnection.ConnectStatus := csHandshaking;
    LConnection.FStarted := True;
    LConnection.FReadReady := True;
  finally LConnection.FLock.Leave; end;
  LConnection._Pump;
end;

procedure TCrossMbedTlsSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  if Ssl then (AConnection as TCrossMbedTlsConnection)._Receive(ABuf, ALen)
  else inherited;
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
  mbedtls_ssl_conf_min_version(@FCliConf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3); // TLS v1.2
  {$endregion}
end;

procedure TCrossMbedTlsSocket.SetMinTlsVersion(const AVersion: TCrossTlsMinVersion);
begin
  if not Ssl then Exit;

  BeginTlsConfigUpdate;
  try
    if AVersion <> tmvTls12 then
      raise ECrossSocket.Create('Mbed TLS does not support minimum TLS versions above TLS 1.2.');

    mbedtls_ssl_conf_min_version(@FCliConf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);
    mbedtls_ssl_conf_min_version(@FSrvConf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);
  finally
    EndTlsConfigUpdate;
  end;
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
