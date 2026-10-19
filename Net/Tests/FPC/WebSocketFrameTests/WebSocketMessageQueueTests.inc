// 使用真实 Sender 和帧编码器，只控制底层物理发送完成时刻。
procedure AddManagedWsWrite(const S:TCrossWebSocketSender;const C:ICrossConnection;
  const Op:Byte;const Calls:PInteger);
var Keep:ICrossConnection; Callback:TWsSendDone; Data:Byte;
begin
  Keep:=C;Data:=$41;
  Callback:=procedure(const OK:Boolean)
    begin Check(Keep<>nil,'WS捕获连接丢失');Inc(Calls^);end;
  S.Send(Op,True,@Data,1,Callback);
end;

procedure RunManagedWsQueue(const Control:Boolean);
{$IFDEF CROSS_WS_SENDER_SELFTEST}
var C:TOwnedSenderConnection;Keep:ICrossConnection;S:TCrossWebSocketSender;
    I,Base,Calls,Destroyed:Integer;Op:Byte;
begin
  C:=TOwnedSenderConnection.Create;Keep:=C;S:=TCrossWebSocketSender.Create(C,True);
  C.Sender:=S;Destroyed:=0;C.Destroyed:=@Destroyed;Calls:=0;
  Base:=CrossWebSocketSenderItemsDestroyed;
  Op:=2;if Control then Op:=9;
  try
    C.AutoComplete:=False;
    for I:=0 to 63 do AddManagedWsWrite(S,Keep,Op,@Calls);
    for I:=0 to 2047 do begin C.Complete(True);AddManagedWsWrite(S,Keep,Op,@Calls);end;
    Check(Calls=2048,'WS wrap完成次数错误');
    Check(CrossWebSocketSenderItemsDestroyed-Base=2048,'WS wrap旧尾槽保留已完成item');
    C.Close;S.RequestClose;
    Check((Calls=2111) and (CrossWebSocketSenderItemsDestroyed-Base=2111),
      'WS关闭未及时释放未提交item');
    C.Complete(True);
    Check((Calls=2112) and (CrossWebSocketSenderItemsDestroyed-Base=2112),
      'WS物理完成后仍保留item，不能靠Sender析构释放');
    Keep:=nil;
    Check(Destroyed=1,'WS捕获连接未释放');
  finally
    if Keep<>nil then begin C.Close;while C.Pending.Count>0 do C.Complete(False);Keep:=nil;end;
  end;
end;
{$ELSE}
begin raise Exception.Create('managed WS test requires CROSS_WS_SENDER_SELFTEST');end;
{$ENDIF}

procedure RunWebSocketMessageQueueTest(const AName:string);
var
  C:TTestConnection; Keep:ICrossConnection; S:TCrossWebSocketSender;
  A,B,D:Byte; ReadsA,ReadsC,CallsA,CallsB,CallsC,I:Integer;
  Order:string; Raised,HookLockFree:Boolean; Frame,Large,Expected,Actual,Part:TBytes; J,N:Integer;
  Started,ReleaseSource:TEvent; Worker:TThread; Destroyed:Integer;
  procedure Drain;
  var Limit:Integer;
  begin Limit:=0;while C.Pending.Count>0 do begin Inc(Limit);Check(Limit<100,'发送泵未停止');C.Complete(True);end;end;
begin
  if AName='managed-message' then begin RunManagedWsQueue(False);Exit;end;
  if AName='managed-control' then begin RunManagedWsQueue(True);Exit;end;
  Destroyed:=0;
  if AName='owner-lifetime' then C:=TOwnedSenderConnection.Create else C:=TTestConnection.Create;
  Keep:=C;S:=TCrossWebSocketSender.Create(C,(AName<>'close-frame-error') and (AName<>'close-frame-timeout'));
  if AName='owner-lifetime' then begin
    TOwnedSenderConnection(C).Sender:=S;TOwnedSenderConnection(C).Destroyed:=@Destroyed;end;
  A:=$41;B:=$42;D:=$43;ReadsA:=0;ReadsC:=0;CallsA:=0;CallsB:=0;CallsC:=0;Order:='';
  try
    if (AName='fifo') or (AName='control') then begin
      C.AutoComplete:=False;
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsA);Result:=ReadsA<=2;if Result then begin P^:=@A;N^:=1;end;end,
        procedure(const OK:Boolean)begin Check(OK,'A失败');Inc(CallsA);Order:=Order+'A';end);
      S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(OK,'B失败');Inc(CallsB);Order:=Order+'B';end);
      B:=$58; // 调用返回即可覆盖原缓冲区，排队项必须已经复制。
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsC);Result:=ReadsC=1;if Result then begin P^:=@D;N^:=1;end;end,
        procedure(const OK:Boolean)begin Check(OK,'C失败');Inc(CallsC);Order:=Order+'C';end);
      if AName='control' then S.Send(9,True,@D,1);
      Check(C.Frames.Count=1,'前条消息尚未完成就提交后条消息/控制帧');
      Check(ReadsC=0,'排队消息提前读取数据源');
      C.Complete(True);
      if AName='control' then begin Frame:=C.Frames[1];Check((Frame[0] and $0F)=9,'控制帧未在分片边界优先发送');end;
      Drain;
      Check((CallsA=1) and (CallsB=1) and (CallsC=1) and (Order='ABC'),'消息完成顺序或次数错误');
      I:=Ord(AName='control');
      Check(C.Frames.Count=6+I,'消息帧数量错误');
      Frame:=C.Frames[0];Check(Frame[0]=$02,'A起始帧');
      Frame:=C.Frames[1+I];Check(Frame[0]=$00,'A连续帧');
      Frame:=C.Frames[2+I];Check(Frame[0]=$80,'A结束帧');
      Frame:=C.Frames[3+I];Check((Frame[0]=$81) and (Frame[2]=$42),'B顺序或排队缓冲区所有权');
      Frame:=C.Frames[4+I];Check(Frame[0]=$02,'C起始帧');
      Frame:=C.Frames[5+I];Check(Frame[0]=$80,'C结束帧');
    end else if AName='sync-depth' then begin
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsA);Result:=ReadsA<=256;if Result then begin P^:=@A;N^:=1;end;end,
        procedure(const OK:Boolean)begin Check(OK,'同步分片失败');Inc(CallsA);end);
      Check((ReadsA=257) and (CallsA=1),'同步分片未完成');
      Check(C.MaxSendDepth<=2,'同步发送按分片递归增长');
    end else if AName='source-error' then begin
      Raised:=False;
      try
        S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
          begin Result:=False;raise Exception.Create('数据源异常');end,
          procedure(const OK:Boolean)begin Check(not OK,'异常数据源成功');Inc(CallsA);end);
      except on E:Exception do Raised:=E.Message='数据源异常';end;
      Check(Raised and (CallsA=1) and (C.CloseCount=1),'数据源异常未准确结算一次失败');
    end else if (AName='local-close') or (AName='peer-close') or
      (AName='protocol-close') or (AName='timeout') or (AName='external-close') or
      (AName='io-failure') or (AName='cancel-error') then begin
      C.AutoComplete:=False;
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsA);P^:=@A;N^:=1;Result:=True;end,
        procedure(const OK:Boolean)begin Check(not OK,'被取消流成功');Inc(CallsA);end);
      S.Send(1,True,@B,1,procedure(const OK:Boolean)
        begin Check(not OK,'被取消字符串成功');Inc(CallsB);
          if AName='cancel-error' then raise Exception.Create('取消回调异常');end);
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsC);P^:=@D;N^:=1;Result:=True;end,
        procedure(const OK:Boolean)begin Check(not OK,'被取消排队流成功');Inc(CallsC);end);
      Raised:=False;
      if AName='peer-close' then S.ReceiveClose(nil)
      else if AName='protocol-close' then S.FailProtocol(1002)
      else if AName='external-close' then C.Close
      else if AName='io-failure' then C.Complete(False)
      else begin
        S.CloseTimeoutMs:=1;
        try S.RequestClose;except on E:Exception do Raised:=E.Message='取消回调异常';end;
        if AName='cancel-error' then Check(Raised,'取消回调异常未传播');
        if AName='timeout' then begin TThread.Sleep(20);S.CheckTimeout;end;
      end;
      if AName<>'io-failure' then begin
        Check(CallsA=0,'在途分片提前结算');
        C.Complete(True);
      end;
      Check((CallsA=1) and (CallsB=1) and (CallsC=1),'关闭未逐项结算一次');
      Check((ReadsA=1) and (ReadsC=0),'关闭仍读取后续/排队数据源');
      if (AName='timeout') or (AName='external-close') or (AName='io-failure') then
        Check((C.CloseCount=1) and (C.Frames.Count=1),'硬关闭后仍发送数据/Close')
      else begin
        Check((C.Frames.Count=2) and (C.CloseCount=0),'优雅关闭缺少唯一Close');
        Frame:=C.Frames[1];Check(Frame[0]=$88,'关闭后发送其他数据');
        if AName='protocol-close' then Check((Frame[2]=3) and (Frame[3]=$EA),'协议错误Close码');
        C.Complete(True);
        if (AName='local-close') or (AName='cancel-error') then begin
          Check(C.DisconnectCount=0,'本地Close未等待对端');S.ReceiveClose(nil);end;
        Check(C.DisconnectCount=1,'双向Close未断开');
      end;
      S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(not OK,'关闭后接纳');Inc(CallsB);end);
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsC);Result:=False;end,
        procedure(const OK:Boolean)begin Check(not OK,'关闭后接纳源');Inc(CallsC);end);
      Check((CallsB=2) and (CallsC=2) and (ReadsC=0),'关闭后拒绝未恰好一次');
      Check(C.BufferChecks>=1,'未检查在途缓冲区');
    end else if (AName='source-error-queued') or (AName='source-close') or
      (AName='source-close-error') then begin
      C.AutoComplete:=False;
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin
          Inc(ReadsA);P^:=@A;N^:=1;Result:=True;
          if ReadsA=2 then begin
            if AName<>'source-error-queued' then S.RequestClose;
            Check(CallsA=0,'数据源尚在使用缓冲区时完成回调已执行');
            if AName<>'source-close' then raise Exception.Create('第二片读取异常');
          end;
        end,procedure(const OK:Boolean)begin Check(not OK,'源终止仍成功');Inc(CallsA);end);
      S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(not OK,'源终止后B成功');Inc(CallsB);
        if AName='source-error-queued' then raise Exception.Create('取消B异常');end);
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsC);Result:=False;end,
        procedure(const OK:Boolean)begin Check(not OK,'源终止后C成功');Inc(CallsC);end);
      Raised:=False;
      try C.Complete(True);except on E:Exception do Raised:=E.Message='第二片读取异常';end;
      Check(Raised=(AName<>'source-close'),'数据源异常被取消回调覆盖');
      Check((CallsA=1) and (CallsB=1) and (CallsC=1) and (ReadsC=0),'源终止未取消所有消息');
      if AName='source-close' then begin
        Check(C.Frames.Count=2,'数据源重入Close后仍发送分片');C.Complete(True);S.ReceiveClose(nil);
        Check(C.DisconnectCount=1,'重入Close握手失败');
      end else Check((C.CloseCount=1) and (C.Frames.Count=1),'源异常后未停止');
    end else if AName='callback-reentry' then begin
      C.AutoComplete:=False;
      S.Send(1,True,@A,1,procedure(const OK:Boolean)
        begin
          Check(OK,'A成功被改为失败');Inc(CallsA);Order:=Order+'A';
          S.Send(1,True,@D,1,procedure(const OK2:Boolean)begin Check(OK2,'C失败');Inc(CallsC);Order:=Order+'C';end);
          raise Exception.Create('A完成异常');
        end);
      S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(OK,'B失败');Inc(CallsB);Order:=Order+'B';end);
      Raised:=False;
      try C.Complete(True);except on E:Exception do Raised:=E.Message='A完成异常';end;
      Check(Raised and (CallsA=1) and (C.Pending.Count=1),'完成异常卡住后续队列');
      Drain;Check((Order='ABC') and (CallsB=1) and (CallsC=1),'重入打乱顺序或重复通知');
      Check(C.CloseCount=0,'业务异常误作物理发送失败');
    end else if AName='large-control' then begin
      C.AutoComplete:=False;
      SetLength(Large,70000);for J:=0 to High(Large) do Large[J]:=Byte(J and $FF);
      Expected:=TCrossWebSocketParser.MakeFrameData(2,True,True,@Large[0],Length(Large));
      Part:=TCrossWebSocketParser.MakeFrameData(9,True,True,@A,1);
      N:=Length(Expected);SetLength(Expected,N+Length(Part));Move(Part[0],Expected[N],Length(Part));
      S.Send(2,True,@Large[0],Length(Large));S.Send(9,True,@A,1);Drain;
      Actual:=nil;
      for J:=0 to C.Frames.Count-1 do begin
        Part:=C.Frames[J];N:=Length(Actual);SetLength(Actual,N+Length(Part));Move(Part[0],Actual[N],Length(Part));end;
      Check((Length(Actual)=Length(Expected)) and CompareMem(@Actual[0],@Expected[0],Length(Expected)),
        '控制帧插入底层拆分的大帧中');
    end else if AName='prepare-close-race' then begin
      C.AutoComplete:=False;Started:=TEvent.Create(nil,True,False,'');ReleaseSource:=TEvent.Create(nil,True,False,'');
      Worker:=TThread.CreateAnonymousThread(procedure
        begin
          S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
            begin
              Inc(ReadsA);Started.SetEvent;
              Check(ReleaseSource.WaitFor(5000)=wrSignaled,'数据源释放超时');
              Check(CallsA=0,'并发关闭提前释放活动数据源');P^:=@A;N^:=1;Result:=True;
            end,procedure(const OK:Boolean)begin Check(not OK,'关闭期间准备的消息成功');Inc(CallsA);end);
        end);
      Worker.FreeOnTerminate:=False;
      try
        Worker.Start;Check(Started.WaitFor(5000)=wrSignaled,'数据源启动超时');
        S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(not OK,'并发关闭B成功');Inc(CallsB);end);
        S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
          begin Inc(ReadsC);Result:=False;end,
          procedure(const OK:Boolean)begin Check(not OK,'并发关闭C成功');Inc(CallsC);end);
        S.ReceiveClose(nil);
        Check(CallsA=0,'源准备阶段提前通知');ReleaseSource.SetEvent;Worker.WaitFor;
        Check(Worker.FatalException=nil,'数据源线程异常');
        Check((CallsA=1) and (CallsB=1) and (CallsC=1) and (ReadsC=0),'并发关闭取消错误');
        Check(C.Frames.Count=1,'关闭后提交了准备中的数据帧');Frame:=C.Frames[0];Check(Frame[0]=$88,'应仅提交Close');
        C.Complete(True);Check(C.DisconnectCount=1,'并发关闭未完成握手');
      finally ReleaseSource.SetEvent;Worker.WaitFor;Worker.Free;ReleaseSource.Free;Started.Free;end;
    end else if AName='owner-lifetime' then begin
      C.AutoComplete:=False;
      S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
        begin Inc(ReadsA);Result:=ReadsA=1;if Result then begin P^:=@A;N^:=1;end;end,
        procedure(const OK:Boolean)begin Check(OK,'无外部引用流失败');Inc(CallsA);end);
      S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(OK,'无外部引用B失败');Inc(CallsB);end);
      Keep:=nil;Check(Destroyed=0,'首帧完成前连接已销毁');
      C.Complete(True);Check(Destroyed=0,'FIN完成前连接已销毁');
      C.Complete(True);Check(Destroyed=0,'队列清空前连接已销毁');
      C.Complete(True);C:=nil;S:=nil;
      Check((Destroyed=1) and (CallsA=1) and (CallsB=1),'发送完成后连接泄漏或重复完成');
    {$IFDEF CROSS_WS_SENDER_SELFTEST}
    end else if (AName='close-frame-error') or (AName='close-frame-timeout') then begin
      C.AutoComplete:=False;HookLockFree:=False;
      Started:=TEvent.Create(nil,True,False,'');ReleaseSource:=TEvent.Create(nil,True,False,'');
      Worker:=TThread.CreateAnonymousThread(procedure
        begin
          Check(Started.WaitFor(5000)=wrSignaled,'构帧失败注入未执行');
          S.Send(1,True,@D,1,procedure(const OK:Boolean)begin Check(not OK,'关闭时跨线程发送成功');end);
          ReleaseSource.SetEvent;
        end);
      Worker.FreeOnTerminate:=False;Worker.Start;
      try
        S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
          begin Inc(ReadsA);P^:=@A;N^:=1;Result:=True;end,
          procedure(const OK:Boolean)begin Check(not OK,'关闭前活动流错误成功');Inc(CallsA);end);
        S.Send(1,True,@B,1,procedure(const OK:Boolean)begin Check(not OK,'关闭后B成功');Inc(CallsB);end);
        S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
          begin Inc(ReadsC);Result:=False;end,
          procedure(const OK:Boolean)begin Check(not OK,'关闭后C成功');Inc(CallsC);end);
        CrossWebSocketSenderBeforeFrame:=procedure(const Op:Byte)
          begin
            if Op<>8 then Exit;
            Started.SetEvent;
            HookLockFree:=ReleaseSource.WaitFor(2000)=wrSignaled;
            if AName='close-frame-timeout' then begin TThread.Sleep(20);S.CheckTimeout;Exit;end;
            raise Exception.Create('Close构帧异常');
          end;
        Check(S.CloseTimeoutMs=0,'用例必须覆盖默认无关闭超时');
        if AName='close-frame-timeout' then S.CloseTimeoutMs:=1;
        S.RequestClose;Raised:=False;
        try C.Complete(True);except on E:Exception do Raised:=E.Message='Close构帧异常';end;
        Worker.WaitFor;
        Check((Raised=(AName='close-frame-error')) and (C.CloseCount=1),'Close构帧失败/超时未实际关闭连接');
        Check(HookLockFree and (Worker.FatalException=nil),'Close构帧仍持有队列锁');
        Check((CallsA=1) and (CallsB=1) and (CallsC=1) and (ReadsC=0),'构帧失败重复/遗漏取消通知');
        Check((C.Frames.Count=1) and (C.Pending.Count=0),'构帧失败仍提交Close');
        S.RequestClose;S.ReceiveClose(nil);Check(C.CloseCount=1,'构帧失败后重复关闭');
      finally
        CrossWebSocketSenderBeforeFrame:=nil;Started.SetEvent;Worker.WaitFor;
        Worker.Free;ReleaseSource.Free;Started.Free;
      end;
    {$ENDIF}
    end else raise Exception.Create('未知用例 '+AName);
    Writeln('PASS ',AName);
  finally
    if C<>nil then begin
      C.Pending.Clear;
      if AName<>'owner-lifetime' then S.Free;
      Keep:=nil;
    end;
  end;
end;
