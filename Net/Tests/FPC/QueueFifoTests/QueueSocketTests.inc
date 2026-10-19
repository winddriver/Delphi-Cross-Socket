{$IFDEF LINUX}
const NETWORK_BYTES=16*1024*1024;
type
  TNetworkSocket=class(TCrossSocket)
  private
    FDepth,FCalls,FSuccesses,FFailures,FErrors,FCycles,FQueuedCycle:Integer;
    FSeen:TArray<Integer>;
    FConnection:ICrossConnection;
    procedure QueueItem(const AId:Integer);
  protected
    function ProcessIoEvent:Boolean; override;
    procedure LogicConnected(const C:ICrossConnection); override;
    procedure LogicReceived(const C:ICrossConnection;const P:Pointer;const N:Integer); override;
  public
    constructor Create(const ADepth:Integer); reintroduce;
    procedure Probe;
    procedure Completed;
  end;
procedure PrintLine(const S:string);
begin Writeln(S);Flush(Output);end;
constructor TNetworkSocket.Create(const ADepth:Integer);
begin FDepth:=ADepth;FQueuedCycle:=-1;SetLength(FSeen,ADepth);inherited Create(1);end;
function TNetworkSocket.ProcessIoEvent:Boolean;
begin Result:=inherited ProcessIoEvent;AtomicIncrement(FCycles);end;
procedure TNetworkSocket.LogicConnected(const C:ICrossConnection);
begin FConnection:=C;inherited;PrintLine('CONNECTED');end;
procedure TNetworkSocket.QueueItem(const AId:Integer);
var B:TBytes;Size:Integer;ObjectProbe:TProbe;Keep:IProbe;
begin
  Size:=NETWORK_BYTES div FDepth;if AId=0 then Inc(Size,NETWORK_BYTES mod FDepth);
  SetLength(B,Size);FillChar(B[0],Size,Byte(AId mod 251));
  ObjectProbe:=TProbe.Create;ObjectProbe.Value:=AId;Keep:=ObjectProbe;
  FConnection.SendBytes(B,procedure(const C:ICrossConnection;const OK:Boolean)
    begin
      if AtomicExchange(FSeen[Keep.Id],1)<>0 then AtomicIncrement(FErrors);
      if OK then begin
        if AtomicIncrement(FSuccesses)-1<>AId then AtomicIncrement(FErrors);
      end else AtomicIncrement(FFailures);
      AtomicIncrement(FCalls);
    end);
end;
procedure TNetworkSocket.LogicReceived(const C:ICrossConnection;const P:Pointer;const N:Integer);
var I:Integer;
begin
  Check((N=1) and (PAnsiChar(P)^='Q'),'网络测试输入错误');
  Check(TSocketAPI.SetSndBuf(C.Socket,4096)=0,'设置小发送缓冲区失败');
  FQueuedCycle:=AtomicCmpExchange(FCycles,0,0);
  for I:=0 to FDepth-1 do QueueItem(I);
  PrintLine('QUEUED '+IntToStr(FDepth));
end;
procedure TNetworkSocket.Probe;
var Deadline:Int64;
begin
  Deadline:=Ticks+5*Frequency;
  // 第一次返回是收包/排队；第二次是实际EPOLLOUT处理，队列仍未排空即经历EAGAIN。
  while AtomicCmpExchange(FCycles,0,0)<FQueuedCycle+2 do begin
    Check(Ticks<Deadline,'写事件未执行');TThread.Sleep(1);end;
  Check(not FConnection.IsClosed,'写事件错误关闭连接');
  Check(AtomicCmpExchange(FCalls,0,0)<FDepth,'未形成真实背压');
  PrintLine('EAGAIN '+IntToStr(AtomicCmpExchange(FCalls,0,0)));
end;
procedure TNetworkSocket.Completed;
var Deadline:Int64;
begin
  Deadline:=Ticks+5*Frequency;
  while (AtomicCmpExchange(FCalls,0,0)<>FDepth) or
    (AtomicCmpExchange(DestroyedProbes,0,0)<>FDepth) do begin
    Check(Ticks<Deadline,'网络发送未逐项完成/释放');TThread.Sleep(1);end;
  Check(FErrors=0,'网络发送乱序或重复通知');
  PrintLine(Format('DONE %d %d %d',[FCalls,FSuccesses,FFailures]));
end;
procedure RunSocketNetwork(const N:Integer);
var S:TNetworkSocket;Keep:ICrossSocket;Port:Word;Line:string;
begin
  Check((N=100) or (N=1000) or (N=10000),'网络队列深度错误');
  DestroyedProbes:=0;S:=TNetworkSocket.Create(N);Keep:=S;Port:=0;
  try
    S.Listen('127.0.0.1',0,procedure(const L:ICrossListen;const OK:Boolean)
      begin Check(OK,'监听失败');Port:=L.LocalPort;end);
    Check(Port<>0,'监听端口缺失');PrintLine('PORT '+IntToStr(Port));
    while not Eof(Input) do begin
      Readln(Line);
      if Line='probe' then S.Probe
      else if Line='close' then S.FConnection.Close
      else if Line='done' then S.Completed
      else if Line='stop' then Break;
    end;
  finally S.CloseAll;S.StopLoop;S.FConnection:=nil;Keep:=nil;end;
  PrintLine('STOPPED');
end;
{$ELSE}
procedure RunSocketNetwork(const N:Integer);
begin raise Exception.Create('Epoll网络用例只能在Linux运行');end;
{$ENDIF}
