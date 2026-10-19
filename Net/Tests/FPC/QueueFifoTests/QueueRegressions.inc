procedure Regression(const Name:string);
var D:IServerDock;R:ICrossHttpClientRequest;I,J,Calls,Before,Expected:Integer;
  Threads:array[0..3] of TThread;Last:array[0..3] of Integer;Seen:TArray<Boolean>;
  S:TMemoryServer;Server:ICrossHttpServer;C:TMemoryConnection;Conn:ICrossHttpConnection;
  {$IFDEF LINUX}
  procedure SocketOwnership;
  var Q:TSendQueue;Callbacks:TArray<TCrossConnectionCallback>;Item:PSendItem;
    K,Calls,Before:Integer;B:Byte;
    procedure Add(const AId:Integer);
    var P:TProbe;Probe:IProbe;V:PSendItem;
    begin
      P:=TProbe.Create;P.Value:=AId;Probe:=P;New(V);V.Data:=@B;V.Size:=100;
      V.Callback:=procedure(const Conn:ICrossConnection;const OK:Boolean)
        begin Check(not OK and (Probe.Id=Calls),'Socket取消通知乱序');Inc(Calls);end;
      {$IFDEF FIFO_QUEUE_API}Q.Enqueue(V);{$ELSE}Q.Add(V);{$ENDIF}
      Callbacks[AId]:=V.Callback;
    end;
  begin
    Q:=TSendQueue.Create;Before:=DestroyedProbes;Calls:=0;SetLength(Callbacks,1000);
    try
      for K:=0 to 999 do Add(K);
      {$IFDEF FIFO_QUEUE_API}Item:=Q.Peek;{$ELSE}Item:=Q[0];{$ENDIF}
      Dec(Item.Size);Inc(Item.Data);
      {$IFDEF FIFO_QUEUE_API}Item:=Q.Peek;{$ELSE}Item:=Q[0];{$ENDIF}
      Check((Item.Size=99) and (Item.Data=PByte(@B)+1) and (Q.Count=1000),'部分发送更新改变队列顺序/所有权');
      Q.Clear;
      Check((Q.Count=0) and (DestroyedProbes=Before),'Clear释放了尚待通知的回调捕获');
      for K:=0 to 999 do begin Callbacks[K](nil,False);Callbacks[K]:=nil;end;
      Check((Calls=1000) and (DestroyedProbes-Before=1000),'Clear取消未逐项释放一次');
    finally Q.Free;end;
  end;
  {$ENDIF}
  procedure StartProducer(const Index:Integer);
  begin
    Threads[Index]:=TThread.CreateAnonymousThread(procedure
      var K:Integer;
      begin for K:=0 to 249 do PushRequest(D,Index*250+K);end);
    Threads[Index].FreeOnTerminate:=False;Threads[Index].Start;
  end;
  procedure ReadyResponses;
  var K:Integer;
  begin
    for K:=99 downto 1 do S.Reply(S.Responses[K],K);
    Check(C.WriteCount=0,'后续ready响应越过未ready队首');
    S.Reply(S.Responses[0],0);S.Responses.Clear;
  end;
  procedure StartReady(const Index:Integer);
  begin
    Threads[Index]:=TThread.CreateAnonymousThread(procedure
      var K:Integer;
      begin
        for K:=Index*25 to Index*25+24 do if K<>0 then S.Reply(S.Responses[K],K);
      end);
    Threads[Index].FreeOnTerminate:=False;Threads[Index].Start;
  end;
begin
  if Name='request-concurrent' then begin
    D:=TServerDock.Create(nil,'http','localhost',80,0);Before:=DestroyedRequests;
    SetLength(Seen,1000);for I:=0 to 3 do begin Last[I]:=-1;StartProducer(I);end;
    for I:=0 to 3 do begin Threads[I].WaitFor;Check(Threads[I].FatalException=nil,'请求并发入队异常');Threads[I].Free;end;
    for I:=0 to 999 do begin
      Check(D.PopRequest(R),'并发入队遗漏');J:=(R as TRequest).Id;
      Check(not Seen[J],'并发入队重复');Seen[J]:=True;
      Check((J mod 250)>Last[J div 250],'单个生产者次序被打乱');Last[J div 250]:=J mod 250;R:=nil;
    end;
    Check(not D.PopRequest(R),'并发队列未清空');D:=nil;
    Check(DestroyedRequests-Before=1000,'出队槽位保留请求');
  end else if Name='request-wrap' then begin
    D:=TServerDock.Create(nil,'http','localhost',80,0);Before:=DestroyedRequests;
    for I:=0 to 99 do PushRequest(D,I);
    for I:=0 to 9999 do begin
      Check(D.PopRequest(R) and ((R as TRequest).Id=I),'循环出入队次序错误');R:=nil;
      PushRequest(D,I+100);
    end;
    for I:=10000 to 10099 do begin Check(D.PopRequest(R) and ((R as TRequest).Id=I),'循环队列尾部错误');R:=nil;end;
    Check(not D.PopRequest(R),'循环队列未清空');Check(DestroyedRequests-Before=10100,'循环槽位保留已出队接口');D:=nil;
  end else if Name='request-cancel' then begin
    D:=TServerDock.Create(nil,'http','localhost',80,0);Calls:=0;Before:=DestroyedRequests;
    PushRequest(D,0,procedure(const Response:ICrossHttpClientResponse)
      begin Inc(Calls);Check(Response.StatusCode=499,'取消状态');
        PushRequest(D,3,procedure(const Response2:ICrossHttpClientResponse)begin Inc(Calls);end);
      end);
    PushRequest(D,1,procedure(const Response:ICrossHttpClientResponse)
      begin Inc(Calls);raise Exception.Create('预期取消回调异常');end);
    PushRequest(D,2,procedure(const Response:ICrossHttpClientResponse)begin Inc(Calls);end);
    D.CancelAllRequests(499,'cancel');Check(Calls=3,'异常取消中断其余通知或取消了重入项');
    Check(DestroyedRequests-Before=3,'取消后仍持有原请求');
    D.CancelAllRequests(499,'cancel');D.CancelAllRequests(499,'again');
    Check((Calls=4) and (DestroyedRequests-Before=4),'重入请求未恰好取消一次');D:=nil;
  end else if (Name='response-ready-order') or (Name='response-concurrent') or
    (Name='response-cancel') or (Name='response-lifetime') then begin
    S:=TMemoryServer.Create;Server:=S;S.Hold:=True;S.Depth:=100;
    Before:=DestroyedConnections;C:=TMemoryConnection.Create(S);Conn:=C;
    try
      FillResponses(C,100);Check(C.WriteCount=0,'未ready的队首提前发送');
      if Name='response-concurrent' then begin
        for I:=0 to 3 do StartReady(I);
        for I:=0 to 3 do begin Threads[I].WaitFor;Check(Threads[I].FatalException=nil,'并发ready异常');Threads[I].Free;end;
        Check(C.WriteCount=0,'并发ready越过队首');S.Reply(S.Responses[0],0);S.Responses.Clear;
      end else ReadyResponses;
      Check(C.WriteCount=1,'未串行保留在途响应');
      if (Name='response-cancel') or (Name='response-lifetime') then begin
        C.CloseForTest;
        if Name='response-lifetime' then begin Conn:=nil;Check(DestroyedConnections=Before,'在途连接提前销毁');end;
        C.Drain(False);Expected:=100;
      end
      else begin
        C.Drain;Expected:=0;
      end;
      Check((S.Calls=100) and (S.Failures=Expected),'响应取消/完成重复或遗漏');
      if Name='response-lifetime' then begin C:=nil;Check(DestroyedConnections=Before+1,'队列清空后连接未释放');end;
    finally
      if C<>nil then C.CloseForTest;Conn:=nil;S.Responses.Clear;Server:=nil;
    end;
  {$IFDEF LINUX}end else if Name='socket-ownership' then begin SocketOwnership;{$ENDIF}
  end else raise Exception.Create('未知回归 '+Name);
  Writeln('PASS ',Name);
end;
