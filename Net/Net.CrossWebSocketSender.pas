unit Net.CrossWebSocketSender;

{$I zLib.inc}

interface

uses
  SysUtils, Classes, SyncObjs, Generics.Collections,
  {$IFDEF FPC}DTF.Generics,{$ENDIF}
  Net.CrossSocket.Base, Net.CrossWebSocketParser;

type
  TWsSendDone = reference to procedure(const ASuccess: Boolean);
  TWsChunkDataFunc = reference to function(
    const AData: PPointer; const ACount: PNativeInt): Boolean;
  TWsSendState = (wssOpen, wssWaiting, wssSending, wssSent, wssClosed);
  TWsPumpAction = (wpaNone, wpaFinish, wpaPrepare, wpaPrepareClose, wpaWrite);

  TWsSendItem = class;
  IWsSendItem = interface
    ['{3116CE92-CBFA-4755-B08C-492D0F8FC822}']
    function GetItem: TWsSendItem;
  end;

  // 接口仅管理排队项寿命；发送器成员不持有连接接口。
  TWsSendItem = class(TInterfacedObject, IWsSendItem)
  public
    Frame: TBytes;
    Source: TWsChunkDataFunc;
    Callback: TWsSendDone;
    IsChunks, IsClose, FrameReady, FinalFrame, Completed: Boolean;
    NextOpCode: Byte;
    function GetItem: TWsSendItem;
    {$IFDEF CROSS_WS_SENDER_SELFTEST}
    destructor Destroy; override;
    {$ENDIF}
  end;

  TCrossWebSocketSender = class
  private type
    TSendQueue = {$IFDEF FPC}TFpcQueue{$ELSE}TQueue{$ENDIF}<IWsSendItem>;
  private
    FConnection: TCrossConnectionBase;
    FIsServer: Boolean;
    FLock: TCriticalSection;
    FState: TWsSendState;
    FMessages, FControls: TSendQueue;
    FActive, FCurrent: IWsSendItem;
    FPumping, FPending, FSendSuccess: Boolean;
    FClosePayload: TBytes;
    FDisconnectAfterClose: Boolean;
    FCloseStartedAt: UInt64;
    FCloseTimeoutMs: Cardinal;
    function _IsClosing: Boolean;
    function _MakeFrame(const AOpCode: Byte; const AFin: Boolean;
      const AData: Pointer; const ACount: NativeInt): TBytes;
    procedure _Enqueue(const AItem: IWsSendItem; const AControl: Boolean);
    procedure _FinishItem(const AItem: IWsSendItem; const ASuccess: Boolean);
    procedure _WriteFrame(const AFrame: TBytes);
    procedure _FrameSent(const ASuccess: Boolean);
    procedure _Pump;
    procedure _Abort;
    procedure _RequestClose(const APayload: TBytes; const ADisconnectAfterClose: Boolean);
  public
    constructor Create(const AConnection: TCrossConnectionBase; const AIsServer: Boolean);
    destructor Destroy; override;
    // 完整数据消息排队；控制帧只在物理帧边界发送。
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

{$IFDEF CROSS_WS_SENDER_SELFTEST}
type
  TWsBeforeFrame = reference to procedure(const AOpCode: Byte);
var
  // 仅专项测试注入构帧失败；正式构建没有该钩子。
  CrossWebSocketSenderBeforeFrame: TWsBeforeFrame;
  CrossWebSocketSenderItemsDestroyed: Integer;
{$ENDIF}

implementation

{$IFDEF CROSS_WS_SENDER_SELFTEST}
destructor TWsSendItem.Destroy;
begin
  AtomicIncrement(CrossWebSocketSenderItemsDestroyed);
  inherited;
end;
{$ENDIF}

function TWsSendItem.GetItem: TWsSendItem;
begin
  Result := Self;
end;

constructor TCrossWebSocketSender.Create(const AConnection: TCrossConnectionBase;
  const AIsServer: Boolean);
begin
  inherited Create;
  FConnection := AConnection;
  FIsServer := AIsServer;
  FState := wssOpen;
  FLock := TCriticalSection.Create;
  FMessages := TSendQueue.Create;
  FControls := TSendQueue.Create;
end;

destructor TCrossWebSocketSender.Destroy;
begin
  FCurrent := nil;
  FActive := nil;
  FClosePayload := nil;
  FreeAndNil(FControls);
  FreeAndNil(FMessages);
  FreeAndNil(FLock);
  inherited;
end;

function TCrossWebSocketSender._IsClosing: Boolean;
begin
  FLock.Enter;
  try Result := FState <> wssOpen; finally FLock.Leave; end;
end;

function TCrossWebSocketSender._MakeFrame(const AOpCode: Byte; const AFin: Boolean;
  const AData: Pointer; const ACount: NativeInt): TBytes;
begin
  {$IFDEF CROSS_WS_SENDER_SELFTEST}
  if Assigned(CrossWebSocketSenderBeforeFrame) then
    CrossWebSocketSenderBeforeFrame(AOpCode);
  {$ENDIF}
  if (ACount < 0) or (ACount > High(Integer) - 14) then
    raise ECrossSocket.Create('WebSocket 发送长度超出支持范围');
  if (ACount > 0) and (AData = nil) then
    raise ECrossSocket.Create('非空 WebSocket 载荷需要有效的缓冲区');
  Result := TCrossWebSocketParser.MakeFrameData(
    AOpCode, AFin, FIsServer, AData, UInt64(ACount));
end;

procedure TCrossWebSocketSender._FinishItem(const AItem: IWsSendItem;
  const ASuccess: Boolean);
var
  LItem: TWsSendItem;
  LCallback: TWsSendDone;
begin
  LItem := AItem.GetItem;
  if LItem.Completed then Exit;
  LItem.Completed := True;
  LCallback := LItem.Callback;
  LItem.Callback := nil;
  LItem.Source := nil;
  LItem.Frame := nil;
  if Assigned(LCallback) then LCallback(ASuccess);
end;

procedure TCrossWebSocketSender._Enqueue(const AItem: IWsSendItem;
  const AControl: Boolean);
var
  LAccepted: Boolean;
begin
  FLock.Enter;
  try
    LAccepted := (FState = wssOpen)
      and not (FConnection.ConnectStatus in [csDisconnected, csClosed]);
    if LAccepted then
      if AControl then FControls.Enqueue(AItem) else FMessages.Enqueue(AItem);
  finally FLock.Leave; end;
  if LAccepted then _Pump else _FinishItem(AItem, False);
end;

procedure TCrossWebSocketSender._WriteFrame(const AFrame: TBytes);
var
  LConnection: ICrossConnection;
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
      // 物理完成之前保活连接；SendBytes 同时持有整帧缓冲区。
      LKeepAlive := LConnection;
      _FrameSent(ASuccess);
    end;
  try
    LConnection.SendBytes(AFrame, LFinish);
  except
    // 同步成功后抛异常不能改成第二次失败通知。
    LFinish(LConnection, False);
    raise;
  end;
end;

procedure TCrossWebSocketSender._FrameSent(const ASuccess: Boolean);
begin
  FLock.Enter;
  try
    FPending := False;
    FSendSuccess := ASuccess;
  finally FLock.Leave; end;
  _Pump;
end;

procedure TCrossWebSocketSender._Pump;
var
  LConnection: ICrossConnection;
  LRef: IWsSendItem;
  LItem: TWsSendItem;
  LAction: TWsPumpAction;
  LSuccess, LClose, LDisconnect, LOwnsPump, LHasData: Boolean;
  LData: Pointer;
  LCount: NativeInt;
  LClosePayload: TBytes;
  LError, LRaise: TObject;
  procedure SaveError;
  begin
    // 先结算其余项目，再传播第一个同步异常，避免异常截断取消队列。
    if LError = nil then LError := TObject(AcquireExceptionObject)
    else if ExceptObject is Exception then
      _LogException('WebSocket sender', Exception(ExceptObject));
  end;
begin
  LConnection := FConnection;
  FLock.Enter;
  try
    if FPumping then Exit;
    FPumping := True;
  finally FLock.Leave; end;
  LOwnsPump := True;
  LError := nil;
  try
    while True do
    begin
      LRef := nil;
      LAction := wpaNone;
      LClose := False;
      LDisconnect := False;
      LSuccess := False;
      FLock.Enter;
      try
        if LConnection.ConnectStatus in [csDisconnected, csClosed] then
        begin
          FState := wssClosed;
          FClosePayload := nil;
        end;
        if (FCurrent <> nil) and not FPending then
        begin
          LRef := FCurrent;
          FCurrent := nil;
          LItem := LRef.GetItem;
          LSuccess := FSendSuccess;
          if not LSuccess then
          begin
            FState := wssClosed;
            FClosePayload := nil;
            LClose := True;
          end;
          if LItem.IsClose then
          begin
            if FState <> wssClosed then
              if FDisconnectAfterClose then
              begin
                FState := wssClosed;
                LDisconnect := True;
              end else FState := wssSent;
            LAction := wpaFinish;
          end
          else if LItem.IsChunks and not LItem.FinalFrame
            and LSuccess and (FState = wssOpen) then
          begin
            LItem.Frame := nil;
            LItem.FrameReady := False;
          end
          else
          begin
            if FActive = LRef then FActive := nil;
            LSuccess := LSuccess and (not LItem.IsChunks or LItem.FinalFrame);
            LAction := wpaFinish;
          end;
        end
        else if (FState <> wssOpen) and (FMessages.Count > 0) then
        begin
          LRef := FMessages.Dequeue;
          LAction := wpaFinish;
        end
        else if (FState = wssClosed) and (FControls.Count > 0) then
        begin
          LRef := FControls.Dequeue;
          LAction := wpaFinish;
        end
        else if FPending then
        begin
          FPumping := False;
          LOwnsPump := False;
          Break;
        end
        else if (FState <> wssOpen) and (FActive <> nil) then
        begin
          LRef := FActive;
          FActive := nil;
          LAction := wpaFinish;
        end
        else if (FState in [wssOpen, wssWaiting]) and (FControls.Count > 0) then
        begin
          LRef := FControls.Dequeue;
          LAction := wpaWrite;
        end
        else if FState = wssOpen then
        begin
          if (FActive = nil) and (FMessages.Count > 0) then
            FActive := FMessages.Dequeue;
          LRef := FActive;
          if LRef <> nil then
            if LRef.GetItem.FrameReady then LAction := wpaWrite else LAction := wpaPrepare;
        end
        else if FState = wssWaiting then
        begin
          // 只预留关闭工作，随机掩码及分配失败也必须在锁外收尾。
          LClosePayload := FClosePayload;
          FClosePayload := nil;
          FState := wssSending;
          LAction := wpaPrepareClose;
        end;
        if LAction = wpaWrite then
        begin
          FCurrent := LRef;
          FPending := True;
        end;
        if (LAction = wpaNone) and (LRef = nil) then
        begin
          FPumping := False;
          LOwnsPump := False;
          Break;
        end;
      finally FLock.Leave; end;
      try
        if LClose then LConnection.Close;
        if LDisconnect then LConnection.Disconnect;
      except SaveError; end;
      if LAction = wpaPrepareClose then
      begin
        LAction := wpaNone;
        try
          LItem := TWsSendItem.Create;
          LRef := LItem;
          LItem.IsClose := True;
          LData := nil;
          if Length(LClosePayload) > 0 then LData := @LClosePayload[0];
          LItem.Frame := _MakeFrame(WS_OP_CLOSE, True, LData, Length(LClosePayload));
          LClosePayload := nil;
          FLock.Enter;
          try
            // 构帧期间可能超时或被外部关闭，不能在终态再提交 Close。
            if (FState = wssSending)
              and not (LConnection.ConnectStatus in [csDisconnected, csClosed]) then
            begin
              FCurrent := LRef;
              FPending := True;
              LAction := wpaWrite;
            end;
          finally FLock.Leave; end;
        except
          SaveError;
          LClosePayload := nil;
          FLock.Enter;
          try FState := wssClosed; FClosePayload := nil; finally FLock.Leave; end;
          try LConnection.Close; except SaveError; end;
        end;
      end;
      if LAction = wpaFinish then
      begin
        try _FinishItem(LRef, LSuccess); except SaveError; end;
      end
      else if LAction = wpaPrepare then
      begin
        LItem := LRef.GetItem;
        LData := nil;
        LCount := 0;
        try
          // 数据源与回调均在锁外；未轮到的流不预读。
          LHasData := Assigned(LItem.Source);
          if LHasData then LHasData := LItem.Source(@LData, @LCount);
          LItem.FinalFrame := not LHasData or (LData = nil) or (LCount <= 0);
          if LItem.FinalFrame then
            LItem.Frame := _MakeFrame(LItem.NextOpCode, True, nil, 0)
          else
            LItem.Frame := _MakeFrame(LItem.NextOpCode, False, LData, LCount);
          LItem.NextOpCode := WS_OP_CONTINUATION;
          LItem.FrameReady := True;
        except
          SaveError;
          FLock.Enter;
          try FState := wssClosed; FClosePayload := nil; finally FLock.Leave; end;
          try LConnection.Close; except SaveError; end;
        end;
      end
      else if LAction = wpaWrite then
      begin
        try _WriteFrame(LRef.GetItem.Frame); except SaveError; end;
      end;
    end;
    if LError <> nil then
    begin
      LRaise := LError;
      LError := nil;
      raise LRaise;
    end;
  finally
    if LOwnsPump then
    begin
      FLock.Enter;
      try FPumping := False; finally FLock.Leave; end;
    end;
    LError.Free;
  end;
end;

procedure TCrossWebSocketSender._Abort;
var
  LConnection: ICrossConnection;
begin
  LConnection := FConnection;
  FLock.Enter;
  try FState := wssClosed; FClosePayload := nil; finally FLock.Leave; end;
  try LConnection.Close; finally _Pump; end;
end;

procedure TCrossWebSocketSender.Send(const AOpCode: Byte; const AFin: Boolean;
  const AData: Pointer; const ACount: NativeInt; const ACallback: TWsSendDone);
var
  LConnection: ICrossConnection;
  LRef: IWsSendItem;
  LItem: TWsSendItem;
begin
  LConnection := FConnection;
  if IsClosing or (LConnection.ConnectStatus in [csDisconnected, csClosed]) then
  begin
    if Assigned(ACallback) then ACallback(False);
    Exit;
  end;
  LItem := TWsSendItem.Create;
  LRef := LItem;
  LItem.Callback := ACallback;
  try
    // 延迟发送仍须在调用返回前复制裸指针载荷。
    LItem.Frame := _MakeFrame(AOpCode, AFin, AData, ACount);
    LItem.FrameReady := True;
  except
    try _Abort; finally _FinishItem(LRef, False); end;
    raise;
  end;
  _Enqueue(LRef, (AOpCode and $08) <> 0);
end;

procedure TCrossWebSocketSender.SendChunks(const AChunkSource: TWsChunkDataFunc;
  const ACallback: TWsSendDone);
var
  LConnection: ICrossConnection;
  LRef: IWsSendItem;
  LItem: TWsSendItem;
begin
  LConnection := FConnection;
  LItem := TWsSendItem.Create;
  LRef := LItem;
  LItem.IsChunks := True;
  LItem.NextOpCode := WS_OP_BINARY;
  LItem.Source := AChunkSource;
  LItem.Callback := ACallback;
  _Enqueue(LRef, False);
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
  finally FLock.Leave; end;
  if LDisconnect then LConnection.Disconnect else _Pump;
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
  FLock.Enter;
  try
    LExpired := (FState in [wssWaiting, wssSending, wssSent])
      and (TCrossWebSocketParser.TickCount - FCloseStartedAt >= UInt64(FCloseTimeoutMs));
  finally FLock.Leave; end;
  if LExpired then _Abort;
end;

end.
