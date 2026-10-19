program WebSocketCapacityTests;
{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs, Generics.Collections,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossWebSocketParser, Net.CrossWebSocketSender;

type
  {$IFDEF WS_QUEUE_LIMITS}
  TLimits = TWsSendQueueLimits;
  {$ELSE}
  TLimits = record
    MaxMessageCount, MaxMessageBytes, MaxControlCount, MaxControlBytes: Int64;
  end;
  {$ENDIF}
  TPending = record
    Buffer: Pointer;
    CopyData: TBytes;
    Callback: TCrossConnectionCallback;
  end;
  TTestConnection = class(TCrossConnectionBase)
  public
    Lock: TCriticalSection;
    Frames: TList<TBytes>;
    Pending: TList<TPending>;
    RejectWrites: Boolean;
    CloseCount, DisconnectCount, CheckedBuffers: Integer;
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure DirectSend(const Buffer: Pointer; const Count: Integer;
      const Callback: TCrossConnectionCallback); override;
    procedure Close; override;
    procedure Disconnect; override;
    procedure Complete(const OK: Boolean);
  end;

procedure Check(const Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

constructor TTestConnection.Create;
begin
  inherited Create(nil, INVALID_SOCKET, ctConnect, '', nil);
  ConnectStatus := csConnected;
  Lock := TCriticalSection.Create;
  Frames := TList<TBytes>.Create;
  Pending := TList<TPending>.Create;
end;

destructor TTestConnection.Destroy;
begin
  Pending.Free; Frames.Free; Lock.Free;
  inherited;
end;

procedure TTestConnection.DirectSend(const Buffer: Pointer; const Count: Integer;
  const Callback: TCrossConnectionCallback);
var Item: TPending;
begin
  if RejectWrites then
  begin
    // 模拟下层在接纳前拒绝（如 TLS 队列已满），遵守一次 False 完成约定。
    if Assigned(Callback) then Callback(Self, False);
    Exit;
  end;
  SetLength(Item.CopyData, Count);
  if Count > 0 then Move(Buffer^, Item.CopyData[0], Count);
  Item.Buffer := Buffer; Item.Callback := Callback;
  Lock.Enter;
  try Frames.Add(Item.CopyData); Pending.Add(Item); finally Lock.Leave; end;
end;

procedure TTestConnection.Close;
begin
  Lock.Enter;
  try
    if IsClosed then Exit;
    Inc(CloseCount); ConnectStatus := csClosed;
  finally Lock.Leave; end;
end;

procedure TTestConnection.Disconnect;
begin
  Lock.Enter;
  try
    if ConnectStatus in [csDisconnected, csClosed] then Exit;
    Inc(DisconnectCount); ConnectStatus := csDisconnected;
  finally Lock.Leave; end;
end;

procedure TTestConnection.Complete(const OK: Boolean);
var Item: TPending;
begin
  Lock.Enter;
  try
    Check(Pending.Count > 0, '没有待完成的物理写');
    Item := Pending[0]; Pending.Delete(0);
  finally Lock.Leave; end;
  Check((Length(Item.CopyData) = 0) or CompareMem(Item.Buffer, @Item.CopyData[0], Length(Item.CopyData)),
    '额度提前归还时破坏了在途帧缓冲');
  Inc(CheckedBuffers);
  if Assigned(Item.Callback) then Item.Callback(Self, OK);
end;

procedure Configure(const Sender: TCrossWebSocketSender; const Limits: TLimits);
begin
  {$IFDEF WS_QUEUE_LIMITS}Sender.SetQueueLimits(Limits);{$ENDIF}
end;

procedure Usage(const Sender: TCrossWebSocketSender; const MC, MB, CC, CB: Int64;
  const Preparing: Int64 = 0);
{$IF DEFINED(WS_QUEUE_LIMITS) AND DEFINED(CROSS_WS_SENDER_SELFTEST)}
var A, B, C, D, E: Int64;
begin
  Sender.GetQueueUsageForTest(A, B, C, D, E);
  Check((A = MC) and (B = MB) and (C = CC) and (D = CB),
    Format('预算错误: %d/%d/%d/%d，预期 %d/%d/%d/%d', [A,B,C,D,MC,MB,CC,CB]));
  Check(E = Preparing, '构帧准备计数错误');
end;
{$ELSE}
begin
  // 红基线没有计数观察入口，只用实际接纳/通知/帧判断缺失的限额行为。
end;
{$ENDIF}

procedure Run(const Name: string);
var
  C: TTestConnection;
  Keep: ICrossConnection;
  S: TCrossWebSocketSender;
  Limits: TLimits;
  Calls: array[0..7] of Integer;
  Success: array[0..7] of Boolean;
  Data: array[0..15] of Byte;
  Reads, FramesMade, BeforeFrames, I, N, Accepted, Rejected: Integer;
  Raised, ServerSide: Boolean;
  Frame, Large: TBytes;
  ExpectedSize: UInt64;
  SavedCallback: TCrossConnectionCallback;
  Gate, Started, ReleaseGate: TEvent;
  Workers: array[0..15] of TThread;
  Joined: array[0..15] of Boolean;
  procedure JoinWorkers;
  var J: Integer;
  begin
    for J := 0 to High(Workers) do
      if (Workers[J] <> nil) and not Joined[J] then
      begin Workers[J].WaitFor; Joined[J] := True; end;
  end;
  procedure SendData(const Index: Integer; const Op: Byte; const Size: Integer);
  begin
    S.Send(Op, True, @Data[0], Size,
      procedure(const OK: Boolean) begin Inc(Calls[Index]); Success[Index] := OK; end);
  end;
  procedure SendSource(const Index, FirstSize, SecondSize: Integer);
  var LocalReads: Integer;
  begin
    LocalReads := 0;
    S.SendChunks(
      function(const P: PPointer; const Count: PNativeInt): Boolean
      begin
        Inc(Reads); Inc(LocalReads);
        P^ := @Data[0]; Count^ := 0;
        if LocalReads = 1 then Count^ := FirstSize;
        if LocalReads = 2 then Count^ := SecondSize;
        Result := Count^ > 0;
      end,
      procedure(const OK: Boolean) begin Inc(Calls[Index]); Success[Index] := OK; end);
  end;
  procedure Drain;
  var Steps: Integer;
  begin
    Steps := 0;
    while C.Pending.Count > 0 do
    begin Inc(Steps); Check(Steps < 1024, '发送泵未停止'); C.Complete(True); end;
  end;
begin
  if (Name = 'frame-overflow') or (Name = 'header-only') then
  begin
    Data[0] := $5a;
    ExpectedSize := (UInt64(1) shl 32) + 1;
    for I := 0 to 1 do
    begin
      if Name = 'frame-overflow' then
      begin
        Raised := False;
        try Frame := TCrossWebSocketParser.MakeFrameData(2, True, I = 0, @Data[0], ExpectedSize);
        except on E: ECrossSocket do Raised := True; end;
        Check(Raised, '实体UInt64长度被窄化后仍成功编码');
      end else
      begin
        Frame := TCrossWebSocketParser.MakeFrameData(2, True, I = 0, nil, ExpectedSize);
        Check(Length(Frame) = 10 + Ord(I = 1) * 4, 'nil载荷的header-only行为改变');
        Check((Frame[2] = 0) and (Frame[5] = 1) and (Frame[9] = 1), '64位头长度错误');
      end;
    end;
    Exit;
  end;
  C := TTestConnection.Create; Keep := C;
  ServerSide := (Name <> 'client-bytes') and (Name <> 'mask-error');
  S := TCrossWebSocketSender.Create(C, ServerSide);
  Limits := Default(TLimits);
  FillChar(Calls, SizeOf(Calls), 0); FillChar(Success, SizeOf(Success), 0);
  FillChar(Data, SizeOf(Data), $41); Reads := 0; FramesMade := 0;
  FillChar(Workers, SizeOf(Workers), 0); FillChar(Joined, SizeOf(Joined), 0);
  Gate := nil; Started := nil; ReleaseGate := nil; Accepted := 0; Rejected := 0;
  {$IFDEF CROSS_WS_SENDER_SELFTEST}
  CrossWebSocketSenderBeforeFrame := procedure(const Op: Byte) begin AtomicIncrement(FramesMade); end;
  {$ENDIF}
  try
    if Name = 'default' then
    begin
      Configure(S, Limits);
      for I := 1 to 128 do SendData(0, 2, 1);
      Check((Calls[0] = 0) and (C.Frames.Count = 1), '默认行为提前拒绝消息');
      Drain; Check((Calls[0] = 128) and Success[0], '默认无限制行为改变');
    end else
    if (Name = 'message-count') or (Name = 'message-bytes') or (Name = 'client-bytes') then
    begin
      if Name = 'message-count' then Limits.MaxMessageCount := 2
      else if ServerSide then Limits.MaxMessageBytes := 6 else Limits.MaxMessageBytes := 14;
      Configure(S, Limits);
      SendData(0, 2, 1); SendData(1, 2, 1); BeforeFrames := FramesMade;
      SendData(2, 2, 1);
      Check((Calls[2] = 1) and not Success[2], '容量满的消息没有拒绝一次False');
      Check(FramesMade = BeforeFrames, '拒绝前已经构帧/复制');
      Check(C.CloseCount = 0, '普通消息满错误关闭连接');
      N := 3; if not ServerSide then N := 7;
      Usage(S, 2, 2*N, 0, 0);
      C.Complete(True); Usage(S, 1, N, 0, 0);
      SendData(3, 2, 1); Usage(S, 2, 2*N, 0, 0); Drain;
      Check((Calls[0] = 1) and (Calls[1] = 1) and (Calls[3] = 1)
        and Success[0] and Success[1] and Success[3], '完成后容量未恢复');
    end else
    if Name = 'provider-count' then
    begin
      Limits.MaxMessageCount := 2; Configure(S, Limits);
      SendData(0, 2, 1); SendSource(1, 1, 0); SendSource(2, 1, 0);
      Check((Calls[2] = 1) and not Success[2] and (Reads = 0), 'provider未按数量限额拒绝或被预读');
      Check(C.CloseCount = 0, '未接纳provider却关闭连接');
      Drain; Check((Reads = 2) and Success[1] and (Calls[1] = 1), '已接纳provider未完成');
    end else
    if Name = 'provider-frame' then
    begin
      Limits.MaxMessageBytes := 3; Configure(S, Limits);
      SendSource(0, 1, 1); Usage(S, 1, 3, 0, 0);
      C.Complete(True); Usage(S, 1, 3, 0, 0);
      C.Complete(True); Usage(S, 1, 2, 0, 0);
      C.Complete(True);
      Check((Calls[0] = 1) and Success[0] and (Reads = 3), '分片帧额度没有逐帧复用');
    end else
    if Name = 'provider-overflow' then
    begin
      Limits.MaxMessageBytes := 3; Configure(S, Limits);
      SendSource(0, 1, 4); SendSource(1, 1, 0);
      Raised := False;
      try C.Complete(True); except on E: ECrossSocket do Raised := True; end;
      Check(Raised and (C.CloseCount = 1) and (C.Frames.Count = 1), '分片超限后未停止并关闭');
      Check((Calls[0] = 1) and not Success[0] and (Calls[1] = 1) and not Success[1]
        and (Reads = 2), '分片超限未取消后续provider');
    end else
    if Name = 'control-count' then
    begin
      Limits.MaxControlCount := 1; Configure(S, Limits);
      SendData(0, 2, 1); SendData(1, 9, 1); BeforeFrames := FramesMade;
      SendData(2, 10, 1);
      Check((Calls[2] = 1) and not Success[2] and (FramesMade = BeforeFrames), '控制超限仍构帧或未拒绝');
      Check((C.CloseCount = 1) and (Calls[1] = 1) and not Success[1] and (Calls[0] = 0), '控制超限关闭/在途寿命错误');
      Usage(S, 1, 3, 0, 0); C.Complete(True);
      Check((Calls[0] = 1) and Success[0], '已在途完整消息被重复或错误结算');
    end else
    if Name = 'close-budget' then
    begin
      Limits.MaxControlBytes := 1; Configure(S, Limits); SendData(0, 2, 1);
      S.RequestClose;
      Check((C.CloseCount = 1) and (Calls[0] = 0) and (C.Frames.Count = 1), 'Close无预算时未硬关闭或提前释放');
      Usage(S, 1, 3, 0, 0); C.Complete(True);
    end else
    if Name = 'close-wait' then
    begin
      Limits.MaxControlCount := 1; Limits.MaxControlBytes := 2; Configure(S, Limits);
      SendData(0, 2, 1); S.RequestClose; Usage(S, 1, 3, 1, 2);
      Check(C.Frames.Count = 1, 'Close越过物理在途帧');
      C.Complete(True); Usage(S, 0, 0, 1, 2);
      S.ReceiveClose(nil); C.Complete(True);
      Check((C.DisconnectCount = 1) and (C.Frames.Count = 2), 'Close预算或握手完成错误');
    end else
    if Name = 'invalid-config' then
    begin
      for I := 0 to 3 do
      begin
        Limits := Default(TLimits);
        case I of
          0: Limits.MaxMessageCount := -1;
          1: Limits.MaxMessageBytes := -1;
          2: Limits.MaxControlCount := -1;
          3: Limits.MaxControlBytes := -1;
        end;
        Raised := False;
        try Configure(S, Limits); except on E: EArgumentOutOfRangeException do Raised := True; end;
        Check(Raised, '负限额没有拒绝');
      end;
      Limits := Default(TLimits); Limits.MaxMessageCount := 1; Configure(S, Limits);
      SendData(0, 2, 1); Raised := False;
      try Configure(S, Limits); except on E: ECrossSocket do Raised := True; end;
      Check(Raised, '发送中更改容量被允许');
      Drain;
      C.Close; Raised := False;
      try Configure(S, Limits); except on E: ECrossSocket do Raised := True; end;
      Check(Raised, '已关闭连接允许修改配置');
    end else
    if (Name = 'message-reentry') or (Name = 'accepted-callback-error') then
    begin
      Limits.MaxMessageCount := 1; Limits.MaxMessageBytes := 3; Configure(S, Limits);
      S.Send(2, True, @Data[0], 1,
        procedure(const OK: Boolean)
        begin
          Check(OK, '第一条完成失败'); Inc(Calls[0]); Usage(S, 0, 0, 0, 0);
          S.Send(2, True, @Data[0], 1,
            procedure(const NextOK: Boolean) begin Inc(Calls[1]); Success[1] := NextOK; end);
          if Name = 'accepted-callback-error' then raise Exception.Create('completed-error');
        end);
      Raised := False;
      try C.Complete(True); except on E: Exception do Raised := E.Message = 'completed-error'; end;
      Check(Raised = (Name = 'accepted-callback-error'), '完成异常处理改变');
      Check((Calls[0] = 1) and (Calls[1] = 0) and (C.Pending.Count = 1), '回调前没有归还容量');
      Usage(S, 1, 3, 0, 0); Drain;
      Check((Calls[1] = 1) and Success[1] and (C.CloseCount = 0), '完成回调异常破坏健康后续发送');
    end else
    if Name = 'rejected-callback-error' then
    begin
      Limits.MaxMessageCount := 1; Configure(S, Limits); SendData(0, 2, 1);
      Raised := False;
      try
        S.Send(2, True, @Data[0], 1,
          procedure(const OK: Boolean)
          begin Inc(Calls[1]); Check(not OK, '拒绝项成功'); raise Exception.Create('rejected-error'); end);
      except on E: Exception do Raised := E.Message = 'rejected-error'; end;
      Check(Raised and (Calls[1] = 1) and (C.CloseCount = 0), '拒绝通知异常错误关闭健康连接');
      Usage(S, 1, 3, 0, 0); Drain; SendData(2, 2, 1); Drain;
      Check(Success[0] and Success[2] and (Calls[2] = 1), '拒绝通知异常遗漏归还/后续发送');
    end else
    if (Name = 'provider-first-overflow') or (Name = 'provider-no-space') then
    begin
      Limits.MaxMessageBytes := 3;
      if Name = 'provider-no-space' then Limits.MaxMessageBytes := 1;
      Configure(S, Limits); Raised := False;
      try SendSource(0, 4, 0); except on E: ECrossSocket do Raised := True; end;
      Check(Raised and (C.CloseCount = 1) and (C.Frames.Count = 0)
        and (Calls[0] = 1) and not Success[0], '首帧无预算后仍继续/未关闭');
      if Name = 'provider-no-space' then Check(Reads = 0, '最小帧头无预算仍调用provider')
      else Check(Reads = 1, '首帧实际大小失败后仍重复取数');
      Check(FramesMade = 0, '预算失败后仍进入帧编码');
    end else
    if Name = 'provider-close' then
    begin
      Limits.MaxMessageBytes := 3; Limits.MaxControlBytes := 2; Configure(S, Limits);
      S.SendChunks(
        function(const P: PPointer; const Count: PNativeInt): Boolean
        begin Inc(Reads); S.RequestClose; P^ := @Data[0]; Count^ := 1; Result := True; end,
        procedure(const OK: Boolean) begin Inc(Calls[0]); Success[0] := OK; end);
      Check((Reads = 1) and (Calls[0] = 1) and not Success[0] and (C.Frames.Count = 1), 'provider重入Close后仍发送数据');
      Frame := C.Frames[0]; Check(Frame[0] = $88, '重入Close没有只提交Close帧');
      Usage(S, 0, 0, 1, 2); S.ReceiveClose(nil); Drain;
      Check(C.DisconnectCount = 1, '重入Close未完成');
    end else
    if Name = 'source-error' then
    begin
      Limits.MaxMessageCount := 3; Limits.MaxMessageBytes := 12; Configure(S, Limits);
      S.SendChunks(
        function(const P: PPointer; const Count: PNativeInt): Boolean
        begin
          Inc(Reads); if Reads = 2 then raise EReadError.Create('source-error');
          P^ := @Data[0]; Count^ := 1; Result := True;
        end,
        procedure(const OK: Boolean) begin Inc(Calls[0]); Success[0] := OK; end);
      S.Send(2, True, @Data[0], 1,
        procedure(const OK: Boolean)
        begin Inc(Calls[1]); Check(not OK, '源异常后排队消息成功'); raise Exception.Create('cancel-error'); end);
      SendSource(2, 1, 0); Raised := False;
      try C.Complete(True); except on E: EReadError do Raised := E.Message = 'source-error'; end;
      Check(Raised and (Reads = 2) and (C.CloseCount = 1), '源异常被取消异常覆盖或继续读取');
      Check((Calls[0] = 1) and not Success[0] and (Calls[1] = 1) and (Calls[2] = 1)
        and not Success[2], '源异常没有取消全部已占预算消息');
    end else
    if Name = 'control-bytes' then
    begin
      Limits.MaxControlBytes := 3; Configure(S, Limits);
      SendData(0, 2, 1); SendData(1, 9, 1); Usage(S, 1, 3, 1, 3);
      BeforeFrames := FramesMade; SendData(2, 10, 1);
      Check((Calls[2] = 1) and not Success[2] and (FramesMade = BeforeFrames)
        and (C.CloseCount = 1), '控制字节预算超限未前置拒绝并关闭');
      Usage(S, 1, 3, 0, 0); C.Complete(True);
    end else
    if Name = 'control-reentry' then
    begin
      Limits.MaxControlCount := 1; Limits.MaxControlBytes := 3; Configure(S, Limits);
      S.Send(9, True, @Data[0], 1,
        procedure(const OK: Boolean)
        begin
          Check(OK, '首控制帧失败'); Inc(Calls[0]); Usage(S, 0, 0, 0, 0);
          S.Send(10, True, @Data[0], 1,
            procedure(const NextOK: Boolean) begin Inc(Calls[1]); Success[1] := NextOK; end);
        end);
      C.Complete(True); Usage(S, 0, 0, 1, 3); Drain;
      Check((Calls[0] = 1) and (Calls[1] = 1) and Success[1] and (C.CloseCount = 0), '控制完成回调未复用额度');
    end else
    if Name = 'close-count' then
    begin
      Limits.MaxControlCount := 1; Configure(S, Limits);
      SendData(0, 9, 1); S.RequestClose;
      Check((C.CloseCount = 1) and (C.Frames.Count = 1) and (Calls[0] = 0), 'Close绕过活动控制帧数量预算');
      Usage(S, 0, 0, 1, 3); C.Complete(True);
      Check((Calls[0] = 1) and Success[0], '在途控制帧结算错误');
    end else
    if Name = 'active-close' then
    begin
      Limits.MaxMessageCount := 2; Limits.MaxMessageBytes := 6; Configure(S, Limits);
      SendData(0, 2, 1); SendData(1, 2, 1); S.RequestClose;
      Usage(S, 1, 3, 1, 2); C.Close; S.RequestClose;
      Check((Calls[0] = 0) and (Calls[1] = 1) and not Success[1], '关闭提前结算在途帧或未取消排队项');
      Usage(S, 1, 3, 0, 0); C.Complete(True);
      Check((Calls[0] = 1) and Success[0], '迟到完成没有仅结算一次');
    end else
    if Name = 'io-failure' then
    begin
      Limits.MaxMessageCount := 2; Limits.MaxMessageBytes := 6; Configure(S, Limits);
      SendData(0, 2, 1); SendData(1, 2, 1); C.Complete(False);
      Check((C.CloseCount = 1) and (Calls[0] = 1) and not Success[0]
        and (Calls[1] = 1) and not Success[1], '物理写失败没有退额并取消后续');
    end else
    if Name = 'lower-layer-reject' then
    begin
      Limits.MaxMessageCount := 1; Limits.MaxMessageBytes := 3; Configure(S, Limits);
      C.RejectWrites := True; SendData(0, 2, 1);
      Check((Calls[0] = 1) and not Success[0] and (C.CloseCount = 1)
        and (C.Frames.Count = 0), '底层拒绝没有一次失败并退额');
      SendData(1, 2, 1); Check((Calls[1] = 1) and not Success[1], '底层拒绝后仍接纳消息');
    end else
    if Name = 'wide-limits' then
    begin
      Limits.MaxMessageCount := Int64(High(Cardinal)) + 1;
      Limits.MaxMessageBytes := Int64(High(Cardinal)) + 3;
      Configure(S, Limits); SendData(0, 2, 1); SendData(1, 2, 1);
      Check((Calls[0] = 0) and (Calls[1] = 0), '64位限额发生窄化');
      Usage(S, 2, 6, 0, 0); Drain;
      Check(Success[0] and Success[1], '64位限额下的合法消息失败');
    end else
    if Name = 'duplicate-completion' then
    begin
      Limits.MaxMessageCount := 1; Configure(S, Limits); SendData(0, 2, 1);
      SavedCallback := C.Pending[0].Callback; C.Complete(True); SavedCallback(C, True); SavedCallback := nil;
      Check((Calls[0] = 1) and Success[0] and (C.CloseCount = 0), '重复物理完成重复退额/通知');
    end else
    if Name = 'fixed-depth' then
    begin
      Limits.MaxMessageCount := 8; Limits.MaxMessageBytes := 24; Configure(S, Limits);
      for I := 1 to 8 do SendData(0, 2, 1);
      for I := 1 to 512 do begin C.Complete(True); SendData(0, 2, 1); Usage(S, 8, 24, 0, 0); end;
      Drain; Check((Calls[0] = 520) and Success[0] and (C.CloseCount = 0), '固定深度反复复用导致额度累积');
    end else
    if Name = 'header-boundaries' then
    begin
      for I := 0 to 3 do
      begin
        case I of 0:N:=125; 1:N:=126; 2:N:=65535; else N:=65536; end;
        SetLength(Large, N); FillChar(Large[0], N, $41);
        ExpectedSize := N + 2;
        if N >= 126 then if N <= $ffff then Inc(ExpectedSize, 2) else Inc(ExpectedSize, 8);
        Limits.MaxMessageBytes := ExpectedSize; Configure(S, Limits);
        Calls[0] := 0; Calls[1] := 0;
        S.Send(2, True, @Large[0], N, procedure(const OK: Boolean) begin Inc(Calls[0]); Success[0] := OK; end);
        Large := nil; SendData(1, 2, 1);
        Check((Calls[1] = 1) and not Success[1], '扩展帧头未计入容量');
        Usage(S, 1, ExpectedSize, 0, 0); Drain;
        Check((Calls[0] = 1) and Success[0], '扩展头边界帧失败');
      end;
    end else
    if Name = 'concurrent-limit' then
    begin
      Limits.MaxMessageCount := 4; Limits.MaxMessageBytes := 12; Configure(S, Limits);
      Gate := TEvent.Create(nil, True, False, '');
      for I := 0 to High(Workers) do
      begin
        Workers[I] := TThread.CreateAnonymousThread(
          procedure
          begin
            Check(Gate.WaitFor(5000) = wrSignaled, '并发发送启动超时');
            S.Send(2, True, @Data[0], 1,
              procedure(const OK: Boolean)
              begin if OK then AtomicIncrement(Accepted) else AtomicIncrement(Rejected); end);
          end);
        Workers[I].FreeOnTerminate := False; Workers[I].Start;
      end;
      Gate.SetEvent; JoinWorkers;
      for I := 0 to High(Workers) do Check(Workers[I].FatalException = nil, '并发接纳线程异常');
      Check((Rejected = 12) and (Accepted = 0) and (C.Frames.Count = 1), '并发预留越过总限额');
      Usage(S, 4, 12, 0, 0); Drain;
      Check((Accepted = 4) and (Rejected = 12), '并发发送结算次数错误');
    end else
    if (Name = 'encode-error') or (Name = 'mask-error') or (Name = 'close-frame-error') then
    begin
      {$IFDEF CROSS_WS_SENDER_SELFTEST}
      Limits.MaxMessageCount := 1;
      Limits.MaxMessageBytes := 3; if not ServerSide then Limits.MaxMessageBytes := 7;
      Limits.MaxControlCount := 1; Limits.MaxControlBytes := 2; Configure(S, Limits);
      if Name = 'mask-error' then
      begin
        {$IFDEF WS_QUEUE_LIMITS}CrossWebSocketMaskFailureForTest := True;{$ELSE}
        raise Exception.Create('掩码失败入口只存在于新专项构建');{$ENDIF}
      end else
        CrossWebSocketSenderBeforeFrame := procedure(const Op: Byte)
          begin
            if ((Name = 'encode-error') and (Op = 2)) or ((Name = 'close-frame-error') and (Op = 8)) then
              raise ECrossSocket.Create('frame-error');
          end;
      Raised := False;
      try
        if Name = 'close-frame-error' then begin SendData(0, 2, 1); S.RequestClose; C.Complete(True); end
        else SendData(0, 2, 1);
      except on E: ECrossSocket do Raised := (E.Message = 'frame-error') or (Pos('CSPRNG unavailable', E.Message) > 0); end;
      Check(Raised and (C.CloseCount = 1), '构帧/掩码失败未终止连接');
      if Name <> 'close-frame-error' then
        Check((Calls[0] = 1) and not Success[0] and (C.Frames.Count = 0), '构帧失败错误发送或漏通知');
      {$ELSE}raise Exception.Create('该用例需要专项测试入口');{$ENDIF}
    end else
    if (Name = 'settings-preparing') or (Name = 'encoding-close') then
    begin
      {$IFDEF CROSS_WS_SENDER_SELFTEST}
      if Name = 'encoding-close' then
      begin Limits.MaxMessageCount := 1; Limits.MaxMessageBytes := 3; Configure(S, Limits); end;
      Started := TEvent.Create(nil, True, False, '');
      ReleaseGate := TEvent.Create(nil, True, False, '');
      CrossWebSocketSenderBeforeFrame := procedure(const Op: Byte)
        begin
          if Op <> 2 then Exit;
          Started.SetEvent;
          Check(ReleaseGate.WaitFor(5000) = wrSignaled, '构帧未被放行');
        end;
      Workers[0] := TThread.CreateAnonymousThread(
        procedure
        begin
          S.Send(2, True, @Data[0], 1,
            procedure(const OK: Boolean) begin Inc(Calls[0]); Success[0] := OK; end);
        end);
      Workers[0].FreeOnTerminate := False; Workers[0].Start;
      Check(Started.WaitFor(5000) = wrSignaled, '构帧未开始');
      if Name = 'settings-preparing' then
      begin
        Usage(S, 0, 0, 0, 0, 1);
        Limits.MaxMessageCount := 1; Raised := False;
        try Configure(S, Limits); except on E: ECrossSocket do Raised := True; end;
        Check(Raised, '未入队构帧被误判为空闲，配置发生竞争');
      end else
      begin
        Usage(S, 1, 3, 0, 0, 1); C.Close; S.RequestClose;
        Check(Calls[0] = 0, '构帧尚在使用输入时提前通知取消');
        Usage(S, 1, 3, 0, 0, 1);
      end;
      ReleaseGate.SetEvent; JoinWorkers;
      Check(Workers[0].FatalException = nil, '构帧线程出现异常');
      CrossWebSocketSenderBeforeFrame := nil;
      if Name = 'settings-preparing' then begin Drain; Configure(S, Limits); SendData(1, 2, 1); SendData(2, 2, 1); Drain;
        Check((Calls[2] = 1) and not Success[2] and Success[1], '真正空闲后的配置不生效'); end
      else Check((Calls[0] = 1) and not Success[0] and (C.Frames.Count = 0), '构帧后关闭未归还/拒绝');
      {$ELSE}raise Exception.Create('该用例需要专项测试入口');{$ENDIF}
    end else
      raise Exception.Create('未知用例: ' + Name);
    Usage(S, 0, 0, 0, 0);
  finally
    if Gate <> nil then Gate.SetEvent;
    if ReleaseGate <> nil then ReleaseGate.SetEvent;
    JoinWorkers;
    {$IFDEF CROSS_WS_SENDER_SELFTEST}CrossWebSocketSenderBeforeFrame := nil;{$ENDIF}
    {$IF DEFINED(WS_QUEUE_LIMITS) AND DEFINED(CROSS_WS_SENDER_SELFTEST)}CrossWebSocketMaskFailureForTest := False;{$ENDIF}
    C.Close;
    try S.RequestClose; except on E: Exception do ; end;
    while C.Pending.Count > 0 do try C.Complete(False); except on E: Exception do ; end;
    S.Free; Keep := nil;
    for I := 0 to High(Workers) do Workers[I].Free;
    ReleaseGate.Free; Started.Free; Gate.Free;
  end;
end;

begin
  SetTextCodePage(Output, 65001);
  try Run(ParamStr(1)); Writeln('PASS ', ParamStr(1));
  except on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
