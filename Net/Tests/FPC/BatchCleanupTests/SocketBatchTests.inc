{$IFDEF LINUX}
type
  TBatchSocket=class;
  IBatchValue=interface
    ['{C125A942-6D5F-49E6-9DB9-B7D802EC489E}']
    function Index:Integer;
  end;
  TBatchValue=class(TInterfacedObject,IBatchValue)
  public
    Owner:TBatchSocket;
    Number:Integer;
    function Index:Integer;
    destructor Destroy;override;
  end;
  TBatchSocket=class(TCrossSocket)
  private
    FMode:string;
    FCount,FExpected,FSettled,FSuccess,FFailed,FErrors,FDisposed,FReentries:Integer;
    FCycle,FLastCycle,FBatches,FInBatch,FMaxBatch:Integer;
    FSeen:TArray<Integer>;
    FData:TBytes;
    FConnection:ICrossConnection;
    FRelease,FDone,FProbeGate,FProbeDone:IEvent;
    FProbe:TThread;
    FStarted,FFinished:Int64;
    procedure QueueOne(const Index:Integer);
  protected
    function ProcessIoEvent:Boolean;override;
    procedure LogicConnected(const C:ICrossConnection);override;
    procedure LogicReceived(const C:ICrossConnection;const P:Pointer;const N:Integer);override;
  public
    constructor Create(const Mode:string;const Count:Integer);reintroduce;
    destructor Destroy;override;
    procedure Command(const Value:string);
  end;
function TBatchValue.Index:Integer;
begin Result:=Number;end;
destructor TBatchValue.Destroy;
begin AtomicIncrement(Owner.FDisposed);inherited;end;
constructor TBatchSocket.Create(const Mode:string;const Count:Integer);
var I:Integer;ProbeOwner:TBatchSocket;
begin
  FMode:=Mode;FCount:=Count;FExpected:=Count;FLastCycle:=-1;
  if Mode='cancel-mixed' then FExpected:=(Count+1) div 2;
  if Mode='cancel-nil' then FExpected:=0;
  if Mode='write-reentry' then Inc(FExpected);
  SetLength(FSeen,Count+1);SetLength(FData,Count+1);
  for I:=0 to Count do FData[I]:=Byte(I mod 251);
  FRelease:=TEvent.Create(True,False);FDone:=TEvent.Create(True,False);
  FProbeGate:=TEvent.Create(True,False);FProbeDone:=TEvent.Create(True,False);
  inherited Create(1);
  if Mode='cancel-reentry' then begin
    ProbeOwner:=Self;
    FProbe:=TThread.CreateAnonymousThread(procedure
      begin
        Await(ProbeOwner.FProbeGate,'回调未触发锁探针');
        ProbeOwner.Send(ProbeOwner.FConnection,@ProbeOwner.FData[0],1,procedure(const C:ICrossConnection;const OK:Boolean)
          begin if OK then AtomicIncrement(ProbeOwner.FErrors);AtomicIncrement(ProbeOwner.FReentries);end);
        ProbeOwner.FProbeDone.SetEvent;
      end);
    FProbe.FreeOnTerminate:=False;FProbe.Start;
  end;
end;
destructor TBatchSocket.Destroy;
begin
  FRelease.SetEvent;FProbeGate.SetEvent;StopLoop;
  if FProbe<>nil then begin FProbe.WaitFor;FProbe.Free;end;
  inherited;
end;
function TBatchSocket.ProcessIoEvent:Boolean;
begin
  AtomicIncrement(FCycle);Result:=inherited;
  if (FStarted<>0) and (FFinished=0) and (AtomicCmpExchange(FSettled,0,0)=FExpected)
    and (Copy(FMode,1,6)<>'cancel') then begin
    FMaxBatch:=Max(FMaxBatch,FInBatch);FFinished:=Ticks;FDone.SetEvent;
  end;
end;
procedure TBatchSocket.LogicConnected(const C:ICrossConnection);
begin FConnection:=C;inherited;Line('CONNECTED');end;
procedure TBatchSocket.QueueOne(const Index:Integer);
var ObjectValue:TBatchValue;Keep:IBatchValue;
begin
  if (FMode='cancel-nil') or ((FMode='cancel-mixed') and Odd(Index)) then begin
    Send(FConnection,@FData[Index],1,nil);Exit;
  end;
  ObjectValue:=TBatchValue.Create;ObjectValue.Owner:=Self;ObjectValue.Number:=Index;Keep:=ObjectValue;
  Send(FConnection,@FData[Index],1,procedure(const C:ICrossConnection;const OK:Boolean)
    var Id,Cycle:Integer;
    begin
      Id:=Keep.Index;
      if AtomicExchange(FSeen[Id],1)<>0 then AtomicIncrement(FErrors);
      if OK then begin
        if AtomicIncrement(FSuccess)-1<>Id then AtomicIncrement(FErrors);
        Cycle:=AtomicCmpExchange(FCycle,0,0);
        if Cycle<>FLastCycle then begin
          FMaxBatch:=Max(FMaxBatch,FInBatch);FInBatch:=0;Inc(FBatches);FLastCycle:=Cycle;
        end;
        Inc(FInBatch);
      end else AtomicIncrement(FFailed);
      AtomicIncrement(FSettled);
      if Id=0 then begin
        if FMode='write-reentry' then QueueOne(FCount);
        if FMode='cancel-reentry' then begin FProbeGate.SetEvent;Await(FProbeDone,'Socket回调仍持发送队列锁');end;
        if (FMode='write-error') or (FMode='cancel-error') then raise Exception.Create('预期批次回调异常');
      end;
    end);
end;
procedure TBatchSocket.LogicReceived(const C:ICrossConnection;const P:Pointer;const N:Integer);
var I:Integer;
begin
  Check((N=1) and (PAnsiChar(P)^='Q'),'批次启动消息错误');
  for I:=0 to FCount-1 do QueueOne(I);
  Line('QUEUED');Await(FRelease,'批次未放行');
end;
procedure TBatchSocket.Command(const Value:string);
var Deadline:Int64;
begin
  if Value='release' then begin FStarted:=Ticks;FRelease.SetEvent;end
  else if Value='cancel' then begin
    FStarted:=Ticks;FConnection.Close;FFinished:=Ticks;FDone.SetEvent;FRelease.SetEvent;
  end else if Value='done' then begin
    Await(FDone,'批次未完成');Deadline:=Ticks+Frequency*5;
    while AtomicCmpExchange(FDisposed,0,0)<>FExpected do begin
      Check(Ticks<Deadline,'回调捕获未释放');TThread.Sleep(1);end;
    Check((FErrors=0) and (FSettled=FExpected),'批次乱序、重复或遗漏通知');
    if Copy(FMode,1,6)='cancel' then Check((FSuccess=0) and (FFailed=FExpected),'取消结果错误')
    else if FMode<>'write-error' then Check(FFailed=0,'成功批次出现失败');
    if FMode='write-error' then Check(FSuccess>0,'成功回调异常被改判失败');
    if FMode='cancel-reentry' then Check(FReentries=1,'跨线程重入未拒绝一次');
    Line(Format('BENCH socket mode=%s n=%d total_us=%.3f batches=%d max_batch=%d callbacks=%d disposed=%d',
      [FMode,FCount,(FFinished-FStarted)*1000000.0/Frequency,FBatches,FMaxBatch,FSettled,FDisposed]));
  end;
end;
procedure RunSocketBatch(const Mode:string;const N:Integer);
var S:TBatchSocket;Keep:ICrossSocket;Port:Word;Command:string;
begin
  S:=TBatchSocket.Create(Mode,N);Keep:=S;Port:=0;
  try
    S.Listen('127.0.0.1',0,procedure(const L:ICrossListen;const OK:Boolean)
      begin Check(OK,'批次监听失败');Port:=L.LocalPort;end);
    Check(Port<>0,'批次监听端口为空');Line('PORT '+IntToStr(Port));
    while not Eof(Input) do begin Readln(Command);if Command='stop' then Break;S.Command(Command);end;
  finally S.FRelease.SetEvent;S.CloseAll;S.StopLoop;S.FConnection:=nil;Keep:=nil;end;
  Line('STOPPED');
end;
{$ELSE}
procedure RunSocketBatch(const Mode:string;const N:Integer);
begin raise Exception.Create('Socket批次测试要求真实Epoll');end;
{$ENDIF}
