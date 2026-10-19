type
  TCapacitySocket=class;
  ICapacityProbe=interface ['{CDDFBB07-F52E-43AA-A4BB-1B2520FAD232}'] function Id:Integer;end;
  TCapacityProbe=class(TInterfacedObject,ICapacityProbe)
  public Owner:TCapacitySocket;Number:Integer;function Id:Integer;destructor Destroy;override;end;
  TCapacitySocket=class(TCrossSocket)
  private
    FMode:string;FConnection,FExtraConnection:ICrossConnection;FRelease:IEvent;FStopper:TThread;
    FData:array[0..127] of TBytes;FSeen,FResult:array[0..127] of Integer;
    FCalls,FDisposed,FExpected,FCycles,FQueuedCycle:Integer;
    procedure QueueOne(const Id,Size:Integer;const NilCallback:Boolean=False;const NullBuffer:Boolean=False;const FailWrap:Boolean=False);
    procedure QueueConcurrent;
    procedure CheckSettled;
    procedure CheckBudget(const Count,Bytes:Int64);
  protected
    function ProcessIoEvent:Boolean;override;
    procedure LogicConnected(const C:ICrossConnection);override;
    procedure LogicReceived(const C:ICrossConnection;const P:Pointer;const N:Integer);override;
  public
    constructor Create(const Mode:string);reintroduce;
    procedure BenchSend;inline;
    procedure RawSend(const Buffer:Pointer;const Count:Integer;const Callback:TCrossConnectionCallback);inline;
    procedure Command(const Value:string);
    procedure Finish;
  end;
procedure QueueSendBench(const S:TCapacitySocket;const Count:Integer;const Allocations:Boolean);forward;
procedure SocketSendWithAllocationFault(const S:TCapacitySocket;const Buffer:Pointer;const Count:Integer;const Callback:TCrossConnectionCallback);forward;
function TCapacityProbe.Id:Integer;
begin Result:=Number;end;
destructor TCapacityProbe.Destroy;
begin AtomicIncrement(Owner.FDisposed);inherited;end;
constructor TCapacitySocket.Create(const Mode:string);
begin
  FMode:=Mode;FRelease:=TEvent.Create(True,False);inherited Create(1);
  {$IFDEF SOCKET_CAPACITY_API}
  MaxPendingSendCount:=2;MaxPendingSendBytes:=0;
  if Mode='socket-bytes' then begin MaxPendingSendCount:=0;MaxPendingSendBytes:=20;end;
  if Mode='socket-reenter' then MaxPendingSendCount:=1;
  if (Mode='socket-default') or (Mode='socket-snapshot-unlimited') or Mode.StartsWith('socket-bench') then MaxPendingSendCount:=0;
  if Mode='socket-concurrent' then MaxPendingSendCount:=8;
  if Mode='socket-oversize' then begin MaxPendingSendCount:=0;MaxPendingSendBytes:=20;end;
  if Mode='socket-large-limit' then MaxPendingSendBytes:=Int64(High(Cardinal))+21;
  if Mode.StartsWith('socket-partial') then MaxPendingSendBytes:=2*1024*1024;
  {$ENDIF}
end;
function TCapacitySocket.ProcessIoEvent:Boolean;
begin Result:=inherited;AtomicIncrement(FCycles);end;
procedure TCapacitySocket.LogicConnected(const C:ICrossConnection);
begin
  inherited;Check(TSocketAPI.SetSndBuf(C.Socket,4096)=0,'设置发送缓冲失败');
  if (FMode='socket-snapshot-unlimited') and (FConnection<>nil) then begin
    FExtraConnection:=C;Line('CONNECTED EXTRA');Exit;
  end;
  FConnection:=C;
  {$IFDEF SOCKET_CAPACITY_API}
  if FMode='socket-snapshot-limited' then MaxPendingSendCount:=0;
  if FMode='socket-snapshot-unlimited' then MaxPendingSendCount:=2;
  {$ENDIF}
  Line('CONNECTED');
end;
procedure TCapacitySocket.LogicReceived(const C:ICrossConnection;const P:Pointer;const N:Integer);
begin
  Check((N=1) and (PAnsiChar(P)^ in ['Q','R']),'容量控制消息错误');
  FRelease.ResetEvent;FQueuedCycle:=AtomicCmpExchange(FCycles,0,0);
  Line('BLOCKED '+PAnsiChar(P)^);Await(FRelease,'发送工作线程未放行');
end;
procedure TCapacitySocket.QueueOne(const Id,Size:Integer;const NilCallback,NullBuffer,FailWrap:Boolean);
var Probe:TCapacityProbe;Hold:ICapacityProbe;Callback:TCrossConnectionCallback;Fixture:TCapacitySocket;
begin
  Fixture:=Self;
  if (Size>0) and not NullBuffer then begin SetLength(FData[Id],Size);FillChar(FData[Id][0],Size,Byte(Id));end
  else FData[Id]:=nil;
  Callback:=nil;
  if not NilCallback then begin
    Probe:=TCapacityProbe.Create;Probe.Owner:=Self;Probe.Number:=Id;Hold:=Probe;
    Callback:=procedure(const C:ICrossConnection;const OK:Boolean)
      var Index:Integer;
      begin
        Index:=Hold.Id;Check(AtomicExchange(Fixture.FSeen[Index],1)=0,'物理发送重复通知');
        if OK then Fixture.FResult[Index]:=1 else Fixture.FResult[Index]:=-1;
        AtomicIncrement(Fixture.FCalls);
        if (Fixture.FMode='socket-reenter') and (Index=0) and OK then Fixture.QueueOne(1,10);
        if ((Fixture.FMode='socket-raise') and (Index=0) and OK) or
          ((Fixture.FMode='socket-reject-raise') and (Index=2) and not OK) then
          raise Exception.Create('预期限额发送回调异常');
      end;
  end;
  if FMode='socket-direct' then FConnection.SendBytes(FData[Id],Callback)
  else if FailWrap then SocketSendWithAllocationFault(Self,Pointer(FData[Id]),Size,Callback)
  else Send(FConnection,Pointer(FData[Id]),Size,Callback);
end;
procedure TCapacitySocket.QueueConcurrent;
var Threads:array[0..7] of TThread;Gate:IEvent;I:Integer;Accepted:string;
  procedure StartProducer(const Index:Integer);
  var Fixture:TCapacitySocket;
  begin
    Fixture:=Self;
    Threads[Index]:=TThread.CreateAnonymousThread(procedure
      var J:Integer;
      begin Await(Gate,'并发发送未放行');for J:=0 to 7 do Fixture.QueueOne(Index*8+J,1);end);
    Threads[Index].FreeOnTerminate:=False;Threads[Index].Start;
  end;
begin
  FExpected:=64;Gate:=TEvent.Create(True,False);
  for I:=0 to 7 do StartProducer(I);Gate.SetEvent;
  for I:=0 to 7 do begin Threads[I].WaitFor;Check(Threads[I].FatalException=nil,'发送生产者异常');Threads[I].Free;end;
  Check(FCalls=56,'并发额度接纳数错误');CheckBudget(8,8);Accepted:='';
  for I:=0 to 63 do if FSeen[I]=0 then Accepted:=Accepted+IntToStr(I)+',';
  Line('ACCEPTED '+Accepted);Line('QUEUED 8');
end;
procedure TCapacitySocket.CheckBudget(const Count,Bytes:Int64);
{$IFDEF SOCKET_CAPACITY_API}var ActualCount,ActualBytes:Int64;{$ENDIF}
begin
  {$IFDEF SOCKET_CAPACITY_API}
  GetPendingSendForTest(FConnection,ActualCount,ActualBytes);
  Check((ActualCount=Count) and (ActualBytes=Bytes),'物理发送额度计数错误');
  {$ENDIF}
end;
procedure TCapacitySocket.CheckSettled;
var Remaining:Integer;
begin
  Remaining:=1000;
  while (AtomicCmpExchange(FCalls,0,0)<>FExpected) or (AtomicCmpExchange(FDisposed,0,0)<>FExpected) do begin
    Check(Remaining>0,'发送通知或捕获释放遗漏');Dec(Remaining);TThread.Sleep(5);
  end;
  CheckBudget(0,0);
end;
procedure TCapacitySocket.BenchSend;
begin Send(FConnection,Pointer(FData[127]),1,nil);end;
procedure TCapacitySocket.RawSend(const Buffer:Pointer;const Count:Integer;const Callback:TCrossConnectionCallback);
begin Send(FConnection,Buffer,Count,Callback);end;
procedure TCapacitySocket.Command(const Value:string);
var I,Remaining,Size0,Size1:Integer;Fixture:TCapacitySocket;
begin
  if Value='queue' then begin
    if FMode.StartsWith('socket-bench') then begin QueueSendBench(Self,StrToIntDef(ParamStr(2),10000),FMode='socket-bench-alloc');Exit;end;
    if FMode='socket-sync-failure' then begin
      FExpected:=1;Check(TSocketAPI.Shutdown(FConnection.Socket,1)=0,'禁用写入失败');QueueOne(0,10);Line('QUEUED 0');Exit;
    end;
    if FMode='socket-concurrent' then begin QueueConcurrent;Exit;end;
    if (FMode='socket-default') or (FMode='socket-snapshot-unlimited') then begin
      FExpected:=32;for I:=0 to 31 do QueueOne(I,10);Check(FCalls=0,'默认无限制拒绝发送');Line('QUEUED 320');Exit;
    end;
    FExpected:=3;Size0:=10;Size1:=10;
    if FMode='socket-nil' then Dec(FExpected);
    if FMode='socket-wrap-failure' then begin
      Inc(FExpected);QueueOne(6,10,False,False,True);Check(FResult[6]=-1,'完成包装分配失败未通知');
      CheckBudget(0,0);Check(not FConnection.IsClosed,'包装拒绝关闭健康连接');
    end;
    if FMode='socket-bytes' then begin Size0:=12;Size1:=8;end;
    if FMode='socket-large-limit' then begin Size0:=21;Size1:=1;end;
    if FMode='socket-oversize' then begin Inc(FExpected);QueueOne(6,21);Check(FResult[6]=-1,'单项超字节限额未拒绝');end;
    if FMode.StartsWith('socket-partial') then begin Size0:=1024*1024;Size1:=Size0;end;
    QueueOne(0,Size0,FMode='socket-nil');
    if FMode<>'socket-reenter' then QueueOne(1,Size1);
    QueueOne(2,1);
    Check((FSeen[2]=1) and (FResult[2]=-1),'满额项未立即拒绝一次');
    if FMode='socket-invalid' then begin
      Inc(FExpected,3);QueueOne(6,-1);QueueOne(7,1,False,True);QueueOne(8,0);
      Check((FResult[6]=-1) and (FResult[7]=-1) and (FResult[8]=1),'无效/零发送结果错误');
    end;
    Check(not FConnection.IsClosed,'额度拒绝关闭健康连接');
    if FMode='socket-reenter' then CheckBudget(1,10) else CheckBudget(2,Size0+Size1);
    Line('QUEUED '+IntToStr(Size0+Size1));
  end else if Value='release' then FRelease.SetEvent
  else if Value='first' then begin CheckSettled;Line('FIRST');end
  else if Value='after' then begin
    if FMode='socket-concurrent' then begin
      Inc(FExpected,9);for I:=64 to 71 do QueueOne(I,1);QueueOne(72,1);
      Check(FResult[72]=-1,'第二批并发额度未生效');
      for I:=64 to 71 do Check(FResult[I]=0,'并发完成后额度未恢复');Line('AFTER');Exit;
    end;
    if FMode='socket-reenter' then begin Inc(FExpected,2);QueueOne(3,10);QueueOne(5,1);end
    else begin Inc(FExpected,3);QueueOne(3,10);QueueOne(4,10);QueueOne(5,1);end;
    Check((FResult[3]=0) and ((FMode='socket-reenter') or (FResult[4]=0)),'上一批未退还额度');
    Check(FResult[5]=-1,'恢复后的新批次越过容量');Line('AFTER');
  end else if Value='probe' then begin
    {$IFDEF LINUX}
    Remaining:=1000;
    while AtomicCmpExchange(FCycles,0,0)<FQueuedCycle+2 do begin
      Check(Remaining>0,'未执行实际写事件');Dec(Remaining);TThread.Sleep(5);
    end;
    Check((FSeen[0]=0) and (FSeen[1]=0),'未形成真实部分写');CheckBudget(2,2*1024*1024);Line('PARTIAL');
    {$ELSE}raise Exception.Create('部分写用例要求Linux EAGAIN');{$ENDIF}
  end else if (Value='close') or (Value='stop-pending') then begin
    if Value='close' then FConnection.Close else begin
      Fixture:=Self;FStopper:=TThread.CreateAnonymousThread(procedure begin Fixture.StopLoop;end);
      FStopper.FreeOnTerminate:=False;FStopper.Start;
      Remaining:=1000;while not FConnection.IsClosed do begin Check(Remaining>0,'停止未关闭连接');Dec(Remaining);TThread.Sleep(5);end;
    end;
    {$IFDEF MSWINDOWS}CheckBudget(2,20);{$ELSE}CheckBudget(0,0);{$ENDIF}
    Line('CLOSING');
  end else if Value='done' then begin
    CheckSettled;
    if FMode='socket-raise' then Check((FResult[0]=1) and FConnection.IsClosed,'成功通知异常处理错误');
    if FMode='socket-sync-failure' then Check((FResult[0]=-1) and FConnection.IsClosed,'实际发送错误未关闭并结算');
    if FMode='socket-partial-close' then Check((FResult[0]=-1) and (FResult[1]=-1) and FConnection.IsClosed,'部分写取消结算错误');
    if FStopper<>nil then begin FStopper.WaitFor;Check(FStopper.FatalException=nil,'停止线程异常');end;
    Line('DONE');
  end;
end;
procedure TCapacitySocket.Finish;
begin
  FRelease.SetEvent;if FStopper<>nil then begin FStopper.WaitFor;FStopper.Free;FStopper:=nil;end;
  CloseAll;StopLoop;FConnection:=nil;FExtraConnection:=nil;
end;
procedure RunSocketCapacity(const Mode:string);
var S:TCapacitySocket;Keep:ICrossSocket;Port:Word;InputLine:string;
begin
  S:=TCapacitySocket.Create(Mode);Keep:=S;Port:=0;
  try
    Keep.Listen('127.0.0.1',0,procedure(const L:ICrossListen;const OK:Boolean)
      begin Check(OK,'容量监听失败');Port:=L.LocalPort;end);
    Check(Port>0,'监听端口为空');Line('PORT '+IntToStr(Port));
    while not Eof(Input) do begin Readln(InputLine);if InputLine='quit' then Break;S.Command(InputLine);end;
  finally S.Finish;Keep:=nil;end;
  Line('STOPPED');
end;
