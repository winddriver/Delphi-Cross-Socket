unit Net.CrossWebSocketSender;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  SyncObjs,
  Net.CrossSocket.Base,
  Net.CrossWebSocketParser;

type
  TWsSendDone = reference to procedure(const ASuccess: Boolean);
  TWsChunkDataFunc = reference to function(
    const AData: PPointer; const ACount: PNativeInt): Boolean;
  TWsSendState = (wssOpen, wssWaiting, wssSending, wssSent, wssClosed);

  TCrossWebSocketSender = class
  private
    // 由连接拥有，不在成员中持有连接接口，避免循环引用。
    FConnection: TCrossConnectionBase;
    FIsServer: Boolean;
    FLock: TCriticalSection;
    FState: TWsSendState;
    FPending: Integer;
    FClosePayload: TBytes;
    FDisconnectAfterClose: Boolean;
    FCloseStartedAt: UInt64;
    FCloseTimeoutMs: Cardinal;
    function _IsClosing: Boolean;
    function _BeginSend: Boolean;
    procedure _EndSend(const ASuccess: Boolean);
    procedure _Abort;
    // 共用实际发送入口，包括 Close；不承担关闭状态判断。
    procedure SendFrame(const AOpCode: Byte; const AFin: Boolean;
      const AData: Pointer; const ACount: NativeInt; const ACallback: TWsSendDone);
    procedure _RequestClose(const APayload: TBytes; const ADisconnectAfterClose: Boolean);
    procedure _TrySendClose;
    procedure _CloseSent(const ASuccess: Boolean);
  public
    constructor Create(const AConnection: TCrossConnectionBase; const AIsServer: Boolean);
    destructor Destroy; override;
    // 普通帧使用 Send，关闭通过下面的三个关闭入口协调。
    procedure Send(const AOpCode: Byte; const AFin: Boolean;
      const AData: Pointer; const ACount: NativeInt; const ACallback: TWsSendDone = nil);
    procedure SendChunks(const AChunkSource: TWsChunkDataFunc;
      const ACallback: TWsSendDone = nil);
    procedure RequestClose;
    procedure ReceiveClose(const APayload: TBytes);
    procedure FailProtocol(const ACode: Word);
    procedure CheckTimeout;
    property IsClosing: Boolean read _IsClosing;
    // 0 禁用；启用后需由连接调度定期调用 CheckTimeout。
    property CloseTimeoutMs: Cardinal read FCloseTimeoutMs write FCloseTimeoutMs;
  end;

implementation

constructor TCrossWebSocketSender.Create(const AConnection: TCrossConnectionBase;
  const AIsServer: Boolean);
begin
  inherited Create;
  FConnection := AConnection;
  FIsServer := AIsServer;
  FState := wssOpen;
  FLock := TCriticalSection.Create;
end;

destructor TCrossWebSocketSender.Destroy;
begin
  FClosePayload := nil;
  FreeAndNil(FLock);
  inherited;
end;

function TCrossWebSocketSender._IsClosing: Boolean;
begin
  FLock.Enter;
  try
    Result := FState <> wssOpen;
  finally
    FLock.Leave;
  end;
end;

function TCrossWebSocketSender._BeginSend: Boolean;
begin
  FLock.Enter;
  try
    Result := (FState = wssOpen)
      and not (FConnection.ConnectStatus in [csDisconnected, csClosed]);
    if Result then Inc(FPending);
  finally
    FLock.Leave;
  end;
end;

procedure TCrossWebSocketSender._EndSend(const ASuccess: Boolean);
begin
  FLock.Enter;
  try
    Dec(FPending);
    if not ASuccess then
    begin
      FState := wssClosed;
      FClosePayload := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCrossWebSocketSender._Abort;
var
  LConnection: ICrossConnection;
begin
  LConnection := FConnection;
  FLock.Enter;
  try
    FState := wssClosed;
    FClosePayload := nil;
  finally
    FLock.Leave;
  end;
  LConnection.Close;
end;

procedure TCrossWebSocketSender.SendFrame(const AOpCode: Byte; const AFin: Boolean;
  const AData: Pointer; const ACount: NativeInt; const ACallback: TWsSendDone);
var
  LConnection: ICrossConnection;
  LFrame: TBytes;
  LCompleted: Integer;
  LFinish: TCrossConnectionCallback;
begin
  LConnection := FConnection;
  LCompleted := 0;
  LFinish :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LKeepAlive: ICrossConnection;
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      // 完成回调可能关闭连接、释放外部引用，仍须保持当前发送器存活。
      LKeepAlive := LConnection;
      if Assigned(ACallback) then ACallback(ASuccess);
    end;
  try
    if (ACount < 0) or (ACount > High(Integer) - 14) then
      raise ECrossSocket.Create('WebSocket 发送长度超出支持范围');
    if (ACount > 0) and (AData = nil) then
      raise ECrossSocket.Create('非空 WebSocket 载荷需要有效的缓冲区');
    LFrame := TCrossWebSocketParser.MakeFrameData(
      AOpCode, AFin, FIsServer, AData, UInt64(ACount));
    LConnection.SendBytes(LFrame, LFinish);
  except
    // 同步回调已经完成后再抛异常，不会重复结算或通知失败。
    LFinish(LConnection, False);
    raise;
  end;
end;

procedure TCrossWebSocketSender.Send(const AOpCode: Byte; const AFin: Boolean;
  const AData: Pointer; const ACount: NativeInt; const ACallback: TWsSendDone);
var
  LConnection: ICrossConnection;
begin
  LConnection := FConnection;
  if not _BeginSend then
  begin
    if Assigned(ACallback) then ACallback(False);
    Exit;
  end;
  SendFrame(AOpCode, AFin, AData, ACount,
    procedure(const ASuccess: Boolean)
    begin
      try
        _EndSend(ASuccess);
        if not ASuccess then LConnection.Close;
      finally
        try
          if Assigned(ACallback) then ACallback(ASuccess);
        finally
          _TrySendClose;
        end;
      end;
    end);
end;

procedure TCrossWebSocketSender.SendChunks(const AChunkSource: TWsChunkDataFunc;
  const ACallback: TWsSendDone);
var
  LConnection: ICrossConnection;
  LNextOpCode: Byte;
  LSender: TWsSendDone;
begin
  LConnection := FConnection;
  LNextOpCode := WS_OP_BINARY;
  LSender :=
    procedure(const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
      LHasData: Boolean;
      LOpCode: Byte;
    begin
      if not ASuccess
        or (LConnection.ConnectStatus in [csDisconnected, csClosed]) or IsClosing then
      begin
        LSender := nil;
        if Assigned(ACallback) then ACallback(False);
        Exit;
      end;
      LData := nil;
      LCount := 0;
      try
        LHasData := Assigned(AChunkSource);
        if LHasData then LHasData := AChunkSource(@LData, @LCount);
      except
        LSender := nil;
        _Abort;
        raise;
      end;
      if not LHasData or (LData = nil) or (LCount <= 0) then
      begin
        LSender := nil;
        Send(LNextOpCode, True, nil, 0, ACallback);
        Exit;
      end;
      LOpCode := LNextOpCode;
      // 发送前推进，避免同步回调重入时再次发送起始 opcode。
      LNextOpCode := WS_OP_CONTINUATION;
      try
        Send(LOpCode, False, LData, LCount, LSender);
      except
        LSender := nil;
        raise;
      end;
    end;
  LSender(True);
end;

procedure TCrossWebSocketSender._RequestClose(const APayload: TBytes;
  const ADisconnectAfterClose: Boolean);
var
  LConnection: ICrossConnection;
  LDisconnect: Boolean;
begin
  LConnection := FConnection;
  LDisconnect := False;
  FLock.Enter;
  try
    if FState = wssClosed then Exit;
    if ADisconnectAfterClose then FDisconnectAfterClose := True;
    if FState = wssOpen then
    begin
      FClosePayload := Copy(APayload, 0, Length(APayload));
      FState := wssWaiting;
      if FCloseTimeoutMs <> 0 then FCloseStartedAt := TCrossWebSocketParser.TickCount;
    end;
    if (FState = wssSent) and FDisconnectAfterClose then
    begin
      FState := wssClosed;
      LDisconnect := True;
    end;
  finally
    FLock.Leave;
  end;
  if LDisconnect then LConnection.Disconnect else _TrySendClose;
end;

procedure TCrossWebSocketSender._TrySendClose;
var
  LConnection: ICrossConnection;
  LPayload: TBytes;
  LData: Pointer;
begin
  LConnection := FConnection;
  if LConnection.IsClosed then Exit;
  FLock.Enter;
  try
    if (FState <> wssWaiting) or (FPending <> 0) then Exit;
    FState := wssSending;
    LPayload := FClosePayload;
    FClosePayload := nil;
  finally
    FLock.Leave;
  end;
  LData := nil;
  if Length(LPayload) > 0 then LData := @LPayload[0];
  SendFrame(WS_OP_CLOSE, True, LData, Length(LPayload),
    procedure(const ASuccess: Boolean)
    begin
      _CloseSent(ASuccess);
    end);
end;

procedure TCrossWebSocketSender._CloseSent(const ASuccess: Boolean);
var
  LConnection: ICrossConnection;
  LDisconnect: Boolean;
begin
  LConnection := FConnection;
  LDisconnect := False;
  FLock.Enter;
  try
    if FState = wssClosed then Exit;
    if not ASuccess then
      FState := wssClosed
    else
    if FDisconnectAfterClose then
    begin
      FState := wssClosed;
      LDisconnect := True;
    end else
      FState := wssSent;
  finally
    FLock.Leave;
  end;
  if not ASuccess then LConnection.Close
  else
  if LDisconnect then LConnection.Disconnect;
end;

procedure TCrossWebSocketSender.RequestClose;
begin
  _RequestClose(nil, False);
end;

procedure TCrossWebSocketSender.ReceiveClose(const APayload: TBytes);
begin
  _RequestClose(APayload, True);
end;

procedure TCrossWebSocketSender.FailProtocol(const ACode: Word);
var
  LPayload: TBytes;
begin
  SetLength(LPayload, 2);
  LPayload[0] := Byte(ACode shr 8);
  LPayload[1] := Byte(ACode and $FF);
  _RequestClose(LPayload, True);
end;

procedure TCrossWebSocketSender.CheckTimeout;
var
  LConnection: ICrossConnection;
  LExpired: Boolean;
begin
  if FCloseTimeoutMs = 0 then Exit;
  LConnection := FConnection;
  LExpired := False;
  FLock.Enter;
  try
    if (FState in [wssWaiting, wssSending, wssSent])
      and (TCrossWebSocketParser.TickCount - FCloseStartedAt >= UInt64(FCloseTimeoutMs)) then
    begin
      FState := wssClosed;
      FClosePayload := nil;
      LExpired := True;
    end;
  finally
    FLock.Leave;
  end;
  if LExpired then LConnection.Close;
end;

end.
