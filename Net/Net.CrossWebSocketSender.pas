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
  // 0 表示不限；字节数只统计本发送器持有的编码后帧（含头部和掩码）。
  TWsSendQueueLimits = record
    MaxMessageCount, MaxMessageBytes, MaxControlCount, MaxControlBytes: Int64;
  end;
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
    IsControl, Budgeted, Preparing: Boolean;
    BudgetBytes: Int64;
    NextOpCode: Byte;
    function GetItem: TWsSendItem;
    {$IFDEF CROSS_WS_SENDER_SELFTEST}
    destructor Destroy; override;
    {$ENDIF}
  end;

  TCrossWebSocketSender = class
  private type
    TSendQueue = {$IFDEF FPC}TFpcQueue{$ELSE}TQueue{$ENDIF}<IWsSendItem>;
    TAdmission = (qaAccepted, qaClosed, qaFull);
  private
    FConnection: TCrossConnectionBase;
    FIsServer: Boolean;
    FLock: TCriticalSection;
    FState: TWsSendState;
    FMessages, FControls: TSendQueue;
    FActive, FCurrent: IWsSendItem;
    FPumping, FPending, FSendSuccess: Boolean;
    FClosePayload: TBytes;
    FCloseItem: IWsSendItem;
    FDisconnectAfterClose: Boolean;
    FCloseStartedAt: UInt64;
    FCloseTimeoutMs: Cardinal;
    FQueueLimits: TWsSendQueueLimits;
    FQueueLimitsEnabled: Boolean;
    FMessageCount, FMessageBytes, FControlCount, FControlBytes: Int64;
    FPreparingCount: Int64;
    function _FrameBytes(const ACount: NativeInt): Int64;
    function _ReserveItemLocked(const AItem: TWsSendItem; const ABytes: Int64): Boolean;
    procedure _ReleaseFrameLocked(const AItem: TWsSendItem);
    procedure _ReleaseItemLocked(const AItem: TWsSendItem);
    procedure _DiscardCloseLocked;
    function _BeginFrame(const AItem: TWsSendItem; const ACount: NativeInt): TAdmission;
    function _PrepareFrameBudget(const AItem: TWsSendItem; const ABytes: Int64): Boolean;
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
    // 流为借用；调用方先完成范围调整和首次定位，本方法只读取指定长度。
    procedure SendStream(const AData: TStream; const ACount: Int64;
      const ACallback: TWsSendDone = nil);
    procedure RequestClose;
    procedure ReceiveClose(const APayload: TBytes);
    procedure FailProtocol(const ACode: Word);
    procedure CheckTimeout;
    // 只允许在连接打开、无排队/在途/构帧/发送泵工作时设置；负值拒绝。
    procedure SetQueueLimits(const ALimits: TWsSendQueueLimits);
    {$IFDEF CROSS_WS_SENDER_SELFTEST}
    procedure GetQueueUsageForTest(out AMessageCount, AMessageBytes,
      AControlCount, AControlBytes, APreparingCount: Int64);
    {$ENDIF}
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

uses
  Math;

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
  FCloseItem := nil;
  FreeAndNil(FControls);
  FreeAndNil(FMessages);
  FreeAndNil(FLock);
  inherited;
end;

function WsCapacityFits(const ALimit, AUsed, AExtra: Int64): Boolean; inline;
begin
  Result := (AExtra >= 0) and (AUsed <= High(Int64) - AExtra)
    and ((ALimit = 0) or ((AUsed <= ALimit) and (AExtra <= ALimit - AUsed)));
end;

procedure TCrossWebSocketSender.SetQueueLimits(const ALimits: TWsSendQueueLimits);
begin
  if (ALimits.MaxMessageCount < 0) or (ALimits.MaxMessageBytes < 0)
    or (ALimits.MaxControlCount < 0) or (ALimits.MaxControlBytes < 0) then
    raise EArgumentOutOfRangeException.Create('WebSocket 发送队列限额不能为负数');
  FLock.Enter;
  try
    if (FState <> wssOpen) or FPumping or FPending or (FPreparingCount <> 0)
      or (FConnection.ConnectStatus in [csDisconnected, csClosed])
      or (FMessages.Count <> 0) or (FControls.Count <> 0)
      or (FActive <> nil) or (FCurrent <> nil) or (FCloseItem <> nil)
      or (FMessageCount <> 0) or (FMessageBytes <> 0)
      or (FControlCount <> 0) or (FControlBytes <> 0) then
      raise ECrossSocket.Create('只能在空闲且打开的 WebSocket 发送器上设置队列限额');
    FQueueLimits := ALimits;
    FQueueLimitsEnabled := (ALimits.MaxMessageCount <> 0) or (ALimits.MaxMessageBytes <> 0)
      or (ALimits.MaxControlCount <> 0) or (ALimits.MaxControlBytes <> 0);
  finally FLock.Leave; end;
end;

{$IFDEF CROSS_WS_SENDER_SELFTEST}
procedure TCrossWebSocketSender.GetQueueUsageForTest(out AMessageCount,
  AMessageBytes, AControlCount, AControlBytes, APreparingCount: Int64);
begin
  FLock.Enter;
  try
    AMessageCount := FMessageCount; AMessageBytes := FMessageBytes;
    AControlCount := FControlCount; AControlBytes := FControlBytes;
    APreparingCount := FPreparingCount;
  finally FLock.Leave; end;
end;
{$ENDIF}

function TCrossWebSocketSender._FrameBytes(const ACount: NativeInt): Int64;
begin
  if (ACount < 0) or (ACount > High(Integer) - 14) then
    raise ECrossSocket.Create('WebSocket 发送长度超出支持范围');
  Result := Int64(ACount) + 2;
  if ACount >= 126 then
    if ACount <= $FFFF then Inc(Result, 2) else Inc(Result, 8);
  if not FIsServer then Inc(Result, 4);
end;

function TCrossWebSocketSender._ReserveItemLocked(const AItem: TWsSendItem;
  const ABytes: Int64): Boolean;
begin
  Result := True;
  if not FQueueLimitsEnabled or AItem.Budgeted then Exit;
  if AItem.IsControl then
  begin
    Result := WsCapacityFits(FQueueLimits.MaxControlCount, FControlCount, 1)
      and WsCapacityFits(FQueueLimits.MaxControlBytes, FControlBytes, ABytes);
    if not Result then Exit;
    Inc(FControlCount); Inc(FControlBytes, ABytes);
  end else
  begin
    Result := WsCapacityFits(FQueueLimits.MaxMessageCount, FMessageCount, 1)
      and WsCapacityFits(FQueueLimits.MaxMessageBytes, FMessageBytes, ABytes);
    if not Result then Exit;
    Inc(FMessageCount); Inc(FMessageBytes, ABytes);
  end;
  AItem.Budgeted := True;
  AItem.BudgetBytes := ABytes;
end;

procedure TCrossWebSocketSender._ReleaseFrameLocked(const AItem: TWsSendItem);
begin
  if not AItem.Budgeted then Exit;
  if AItem.IsControl then Dec(FControlBytes, AItem.BudgetBytes)
  else Dec(FMessageBytes, AItem.BudgetBytes);
  AItem.BudgetBytes := 0;
end;

procedure TCrossWebSocketSender._ReleaseItemLocked(const AItem: TWsSendItem);
begin
  if AItem.Preparing then
  begin
    AItem.Preparing := False;
    Dec(FPreparingCount);
  end;
  if not AItem.Budgeted then Exit;
  _ReleaseFrameLocked(AItem);
  AItem.Budgeted := False;
  if AItem.IsControl then Dec(FControlCount) else Dec(FMessageCount);
end;

procedure TCrossWebSocketSender._DiscardCloseLocked;
begin
  if FCloseItem <> nil then _ReleaseItemLocked(FCloseItem.GetItem);
  FCloseItem := nil;
  FClosePayload := nil;
end;

function TCrossWebSocketSender._BeginFrame(const AItem: TWsSendItem;
  const ACount: NativeInt): TAdmission;
begin
  FLock.Enter;
  try
    if (FState <> wssOpen) or (FConnection.ConnectStatus in [csDisconnected, csClosed]) then
      Exit(qaClosed);
    if not _ReserveItemLocked(AItem, _FrameBytes(ACount)) then
    begin
      if AItem.IsControl then FState := wssClosed;
      Exit(qaFull);
    end;
    // 包含未入队的构帧窗口；复用原接纳锁，不让空闲设置越过正在复制的发送。
    Inc(FPreparingCount);
    AItem.Preparing := True;
    Result := qaAccepted;
  finally FLock.Leave; end;
end;

function TCrossWebSocketSender._PrepareFrameBudget(const AItem: TWsSendItem;
  const ABytes: Int64): Boolean;
var
  LExtra: Int64;
  LFull: Boolean;
begin
  // 默认路径不增加锁；发送泵工作期间 SetQueueLimits 不会改变配置。
  if not FQueueLimitsEnabled then Exit(True);
  LFull := False;
  FLock.Enter;
  try
    Result := (FState = wssOpen)
      and not (FConnection.ConnectStatus in [csDisconnected, csClosed]);
    if Result then
    begin
      LExtra := ABytes - AItem.BudgetBytes;
      LFull := not WsCapacityFits(FQueueLimits.MaxMessageBytes, FMessageBytes, LExtra);
      if not LFull then
      begin
        Inc(FMessageBytes, LExtra);
        AItem.BudgetBytes := ABytes;
      end else
      begin
        FState := wssClosed;
        _DiscardCloseLocked;
      end;
    end;
  finally FLock.Leave; end;
  if LFull then raise ECrossSocket.Create('WebSocket 分片超出发送队列字节限额');
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
  // 已入队项只由唯一发送泵终结；尚未入队项仍由当前 Send 调用独占。
  // Close 的待构帧项在锁内转交给泵，不能另行并发调用本方法。
  if LItem.Budgeted or LItem.Preparing then
  begin
    FLock.Enter;
    try
      if LItem.Completed then Exit;
      LItem.Completed := True;
      _ReleaseItemLocked(LItem);
    finally FLock.Leave; end;
  end else
  begin
    if LItem.Completed then Exit;
    LItem.Completed := True;
  end;
  LCallback := LItem.Callback;
  LItem.Callback := nil;
  LItem.Source := nil;
  LItem.Frame := nil;
  if Assigned(LCallback) then LCallback(ASuccess);
end;

procedure TCrossWebSocketSender._Enqueue(const AItem: IWsSendItem;
  const AControl: Boolean);
var
  LAccepted, LFull: Boolean;
  LItem: TWsSendItem;
begin
  LItem := AItem.GetItem;
  LItem.IsControl := AControl;
  LFull := False;
  try
    FLock.Enter;
    try
      if LItem.Preparing then
      begin
        LItem.Preparing := False;
        Dec(FPreparingCount);
      end;
      LAccepted := (FState = wssOpen)
        and not (FConnection.ConnectStatus in [csDisconnected, csClosed]);
      if LAccepted then
      begin
        // 未知 provider 只在接纳时占一个消息位置，不预取数据。
        LFull := not _ReserveItemLocked(LItem, 0);
        LAccepted := not LFull;
        if LFull and AControl then FState := wssClosed;
      end;
      if LAccepted then
        if AControl then FControls.Enqueue(AItem) else FMessages.Enqueue(AItem);
    finally FLock.Leave; end;
  except
    try _Abort; finally _FinishItem(AItem, False); end;
    raise;
  end;
  if LAccepted then _Pump
  else if LFull and AControl then
    try _FinishItem(AItem, False); finally _Abort; end
  else
    _FinishItem(AItem, False);
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
          _DiscardCloseLocked;
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
            _DiscardCloseLocked;
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
            _ReleaseFrameLocked(LItem);
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
          LRef := FCloseItem;
          FCloseItem := nil;
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
          LItem := LRef.GetItem;
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
          try FState := wssClosed; _DiscardCloseLocked; finally FLock.Leave; end;
          try LConnection.Close; except SaveError; end;
        end;
        if LAction <> wpaWrite then
          try _FinishItem(LRef, False); except SaveError; end;
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
          if _PrepareFrameBudget(LItem, _FrameBytes(0)) then
          begin
            LHasData := Assigned(LItem.Source);
            if LHasData then LHasData := LItem.Source(@LData, @LCount);
            LItem.FinalFrame := not LHasData or (LData = nil) or (LCount <= 0);
            if LItem.FinalFrame then LCount := 0;
            // 先按实际帧大小补额，再进行本层复制/编码。
            if _PrepareFrameBudget(LItem, _FrameBytes(LCount)) then
            begin
              if LItem.FinalFrame then
                LItem.Frame := _MakeFrame(LItem.NextOpCode, True, nil, 0)
              else
                LItem.Frame := _MakeFrame(LItem.NextOpCode, False, LData, LCount);
              LItem.NextOpCode := WS_OP_CONTINUATION;
              LItem.FrameReady := True;
            end;
          end;
        except
          SaveError;
          FLock.Enter;
          try FState := wssClosed; _DiscardCloseLocked; finally FLock.Leave; end;
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
  try FState := wssClosed; _DiscardCloseLocked; finally FLock.Leave; end;
  try LConnection.Close; finally _Pump; end;
end;

procedure TCrossWebSocketSender.Send(const AOpCode: Byte; const AFin: Boolean;
  const AData: Pointer; const ACount: NativeInt; const ACallback: TWsSendDone);
var
  LConnection: ICrossConnection;
  LRef: IWsSendItem;
  LItem: TWsSendItem;
  LAdmission: TAdmission;
begin
  LConnection := FConnection;
  LItem := TWsSendItem.Create;
  LRef := LItem;
  LItem.Callback := ACallback;
  LItem.IsControl := (AOpCode and $08) <> 0;
  try
    LAdmission := _BeginFrame(LItem, ACount);
  except
    try _Abort; finally _FinishItem(LRef, False); end;
    raise;
  end;
  if LAdmission <> qaAccepted then
  begin
    // 未接纳消息的回调异常不能被误当成编码失败而关闭健康连接。
    if (LAdmission = qaFull) and LItem.IsControl then
      try _FinishItem(LRef, False); finally _Abort; end
    else
      _FinishItem(LRef, False);
    Exit;
  end;
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

procedure TCrossWebSocketSender.SendStream(const AData: TStream;
  const ACount: Int64; const ACallback: TWsSendDone);
var
  LCount: Int64;
  LBody: TStream;
  LBuffer: TBytes;
begin
  LCount := ACount;
  LBody := AData;
  SetLength(LBuffer, TCrossConnectionBase.SND_BUF_SIZE);
  SendChunks(
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      if LCount <= 0 then Exit(False);
      AData^ := @LBuffer[0];
      ACount^ := LBody.Read(LBuffer[0], Min(LCount, TCrossConnectionBase.SND_BUF_SIZE));
      // 已声明的剩余长度尚未读完，不能把提前 EOF 当成成功终帧。
      if ACount^ <= 0 then
        raise EReadError.Create('WebSocket 数据流在预期长度前结束');
      Dec(LCount, ACount^);
      Result := True;
    end,
    procedure(const ASuccess: Boolean)
    begin
      LBuffer := nil;
      if Assigned(ACallback) then ACallback(ASuccess);
    end);
end;

procedure TCrossWebSocketSender._RequestClose(const APayload: TBytes;
  const ADisconnectAfterClose: Boolean);
var
  LConnection: ICrossConnection;
  LDisconnect, LHardClose: Boolean;
  LItem: TWsSendItem;
  LCloseRef: IWsSendItem;
begin
  LConnection := FConnection;
  LDisconnect := False;
  LHardClose := False;
  try
    FLock.Enter;
    try
      if FState = wssClosed then Exit;
      if LConnection.ConnectStatus in [csDisconnected, csClosed] then
      begin
        // 底层已关闭时只取消已有工作，不再创建不可能发送的 Close 项。
        FState := wssClosed;
        _DiscardCloseLocked;
      end else
      begin
        if ADisconnectAfterClose then FDisconnectAfterClose := True;
        if FState = wssOpen then
        begin
          LItem := TWsSendItem.Create;
          LCloseRef := LItem;
          LItem.IsClose := True;
          LItem.IsControl := True;
          // Close 也占控制预算；不足时硬关闭，不能绕过限额复制载荷。
          LHardClose := not _ReserveItemLocked(LItem, _FrameBytes(Length(APayload)));
          if LHardClose then
            FState := wssClosed
          else
          begin
            FCloseItem := LCloseRef;
            FClosePayload := Copy(APayload, 0, Length(APayload));
            FState := wssWaiting;
            if FCloseTimeoutMs <> 0 then FCloseStartedAt := TCrossWebSocketParser.TickCount;
          end;
        end;
        if (FState = wssSent) and FDisconnectAfterClose then
        begin
          FState := wssClosed;
          LDisconnect := True;
        end;
      end;
    finally FLock.Leave; end;
  except
    _Abort;
    raise;
  end;
  if LHardClose then _Abort
  else if LDisconnect then LConnection.Disconnect
  else _Pump;
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
