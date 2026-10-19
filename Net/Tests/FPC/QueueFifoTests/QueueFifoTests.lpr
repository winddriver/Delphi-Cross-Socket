program QueueFifoTests;
{$I zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs, Math, Generics.Collections,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  {$IFDEF LINUX}Net.CrossSocket.Epoll,{$ENDIF}
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket, Net.CrossHttpUtils,
  Net.CrossHttpClient, Net.CrossHttpServer;

const TOTAL_BYTES = 65536;
type
  TRequest = class(TCrossHttpClientRequest)
  public
    Id:Integer;
    destructor Destroy; override;
  end;
  IProbe = interface
    ['{3729A51C-5658-4726-9C72-70BAB79F52D0}']
    function Id:Integer;
  end;
  TProbe = class(TInterfacedObject,IProbe)
  public
    Value:Integer;
    function Id:Integer;
    destructor Destroy; override;
  end;
  TWrite = record
    Buffer:Pointer;
    Count:Integer;
    Callback:TCrossConnectionCallback;
  end;
  TMemoryConnection = class(TCrossHttpConnection)
  private
    FClosed:Boolean;
    FWrites:TQueue<TWrite>;
  protected
    procedure DirectSend(const ABuffer:Pointer;const ACount:Integer;
      const ACallback:TCrossConnectionCallback=nil); override;
  public
    constructor Create(const AServer:TCrossHttpServer); reintroduce;
    destructor Destroy; override;
    procedure Feed(const AData:AnsiString);
    procedure Drain(const ASuccess:Boolean=True);
    procedure CloseForTest;
    function WriteCount:Integer;
  end;
  TMemoryServer = class(TCrossHttpServer)
  protected
    procedure DoOnRequest(const AConnection:ICrossHttpConnection;
      const ARequest:ICrossHttpRequest;const AResponse:ICrossHttpResponse); override;
  public
    Depth,Calls,Failures:Integer;
    Hold:Boolean;
    Responses:TList<ICrossHttpResponse>;
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure Reply(const AResponse:ICrossHttpResponse;const AId:Integer);
  end;

var DestroyedRequests,DestroyedProbes,DestroyedConnections:Integer;
    Frequency:Int64;
{$IFDEF POSIX}
type TClockTime=record Sec,Nano:Int64;end;
function ClockTime(AClock:Integer;var ATime:TClockTime):Integer;cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'clock_gettime';
{$ENDIF}
function Ticks:Int64;
{$IFDEF POSIX}var T:TClockTime;{$ENDIF}
begin
  {$IFDEF MSWINDOWS}QueryPerformanceCounter(Result);{$ELSE}
  if ClockTime(1,T)<>0 then raise Exception.Create('clock_gettime');
  Result:=T.Sec*1000000000+T.Nano;{$ENDIF}
end;
procedure Check(const OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
function HeapAllocated:Int64;
begin
  {$IF DEFINED(FPC) OR DEFINED(MSWINDOWS)}Result:=GetHeapStatus.TotalAllocated;
  {$ELSE}Result:=-1;{$ENDIF} // Delphi Linux RTL 不提供该统计，不能将缺失值当0。
end;
destructor TRequest.Destroy;
begin AtomicIncrement(DestroyedRequests);inherited;end;
function TProbe.Id:Integer;
begin Result:=Value;end;
destructor TProbe.Destroy;
begin AtomicIncrement(DestroyedProbes);inherited;end;
function Request(const AId:Integer;const ACallback:TCrossHttpResponseProc=nil):ICrossHttpClientRequest;
var R:TRequest;
begin
  R:=TRequest.Create('GET','http://localhost/'+IntToStr(AId),nil,Pointer(nil),0,nil,nil,ACallback);
  R.Id:=AId;Result:=R;
end;
procedure PushRequest(const D:IServerDock;const AId:Integer;const ACallback:TCrossHttpResponseProc=nil);
var R:ICrossHttpClientRequest;
begin R:=Request(AId,ACallback);D.PushRequest(R);end;
constructor TMemoryConnection.Create(const AServer:TCrossHttpServer);
begin
  inherited Create(AServer,INVALID_SOCKET,ctAccept,'',nil);
  FWrites:=TQueue<TWrite>.Create;ConnectStatus:=csConnected;
end;
destructor TMemoryConnection.Destroy;
begin FWrites.Free;Inc(DestroyedConnections);inherited;end;
procedure TMemoryConnection.DirectSend(const ABuffer:Pointer;const ACount:Integer;
  const ACallback:TCrossConnectionCallback);
var W:TWrite;
begin W.Buffer:=ABuffer;W.Count:=ACount;W.Callback:=ACallback;FWrites.Enqueue(W);end;
procedure TMemoryConnection.Feed(const AData:AnsiString);
var P:Pointer;N,Before:Integer;
begin
  P:=PAnsiChar(AData);N:=Length(AData);_LockRecv;
  try while N>0 do begin Before:=N;ParseRecvData(P,N);Check(N<Before,'解析停滞');end;
  finally _UnlockRecv;end;
end;
procedure TMemoryConnection.Drain(const ASuccess:Boolean);
var W:TWrite;Count:Integer;Keep:ICrossConnection;
begin
  Keep:=Self;
  Count:=0;
  while FWrites.Count>0 do begin
    Inc(Count);Check(Count<100000,'发送未收敛');W:=FWrites.Dequeue;
    // 真实 SendBytes/SendStream 必须继续持有物理发送的缓冲区。
    if W.Count>0 then Check(W.Buffer<>nil,'失去在途缓冲区');
    W.Callback(Self,ASuccess);W.Callback:=nil;
  end;
end;
function TMemoryConnection.WriteCount:Integer;
begin Result:=FWrites.Count;end;
procedure TMemoryConnection.CloseForTest;
begin
  if FClosed then Exit;FClosed:=True;
  // INVALID_SOCKET不进入公开Close的清理分支，显式执行真实响应队列清理。
  ConnectStatus:=csClosed;InternalClose;
end;
constructor TMemoryServer.Create;
begin inherited Create(1,False);Compressible:=False;Responses:=TList<ICrossHttpResponse>.Create;end;
destructor TMemoryServer.Destroy;
begin Responses.Free;inherited;end;
procedure TMemoryServer.Reply(const AResponse:ICrossHttpResponse;const AId:Integer);
var B:TBytes;Size:Integer;
begin
  Size:=TOTAL_BYTES div Depth;if AId=0 then Inc(Size,TOTAL_BYTES mod Depth);
  SetLength(B,Size);if Size>0 then FillChar(B[0],Size,Byte(AId mod 251));
  AResponse.SendNoCompress(B,procedure(const C:ICrossConnection;const OK:Boolean)
    begin
      if OK then Check(Calls=AId,'HTTP响应通知乱序');
      Inc(Calls);if not OK then Inc(Failures);
    end);
end;
procedure TMemoryServer.DoOnRequest(const AConnection:ICrossHttpConnection;
  const ARequest:ICrossHttpRequest;const AResponse:ICrossHttpResponse);
begin
  if Hold then Responses.Add(AResponse)
  else Reply(AResponse,StrToInt(Copy(ARequest.Path,2,MaxInt)));
end;
procedure FillResponses(const C:TMemoryConnection;const N:Integer);
var I:Integer;
begin
  for I:=0 to N-1 do C.Feed(AnsiString('GET /'+IntToStr(I)+' HTTP/1.1'#13#10'Host: localhost'#13#10#13#10));
end;
procedure BenchClient(const N:Integer;out Elapsed,HeapQueued,HeapDrained:Int64);
var D:IServerDock;R:ICrossHttpClientRequest;I,Before:Integer;Start:Int64;
begin
  D:=TServerDock.Create(nil,'http','localhost',80,0);Before:=DestroyedRequests;
  for I:=0 to N-1 do PushRequest(D,I);
  HeapQueued:=HeapAllocated;Start:=Ticks;
  for I:=0 to N-1 do begin Check(D.PopRequest(R),'请求队列提前清空');Check((R as TRequest).Id=I,'请求乱序');R:=nil;end;
  Elapsed:=Ticks-Start;HeapDrained:=HeapAllocated;
  Check(not D.PopRequest(R),'请求队列未清空');Check(DestroyedRequests-Before=N,'请求槽位保留接口');D:=nil;
end;
procedure BenchServer(const S:TMemoryServer;const N:Integer;out Elapsed,HeapQueued,HeapDrained:Int64);
var C:TMemoryConnection;Keep:ICrossHttpConnection;Start:Int64;
begin
  S.Depth:=N;S.Calls:=0;S.Failures:=0;
  C:=TMemoryConnection.Create(S);Keep:=C;
  try
    FillResponses(C,N);Check(C.Pending=N,'响应队列深度错误');
    HeapQueued:=HeapAllocated;Start:=Ticks;C.Drain;
    Elapsed:=Ticks-Start;HeapDrained:=HeapAllocated;
    Check((S.Calls=N) and (S.Failures=0) and (C.Pending=0),'响应队列结算错误');
  finally C.CloseForTest;Keep:=nil;end;
end;
{$IFDEF LINUX}
procedure BenchSocket(const N:Integer;out Elapsed,HeapQueued,HeapDrained:Int64);
var Q:TSendQueue;Item:PSendItem;I,Calls,Before:Integer;B:TBytes;Cb:TCrossConnectionCallback;Start:Int64;
  procedure Add(const AId:Integer);
  var P:TProbe;Probe:IProbe;V:PSendItem;
  begin
    P:=TProbe.Create;P.Value:=AId;Probe:=P;New(V);V.Data:=@B[0];V.Size:=Length(B) div N;
    V.Callback:=procedure(const C:ICrossConnection;const OK:Boolean)
      begin Check(OK and (Probe.Id=Calls),'Socket通知乱序');Inc(Calls);end;
    {$IFDEF FIFO_QUEUE_API}Q.Enqueue(V);{$ELSE}Q.Add(V);{$ENDIF}
  end;
begin
  Q:=TSendQueue.Create;SetLength(B,TOTAL_BYTES);Calls:=0;Before:=DestroyedProbes;
  try
    for I:=0 to N-1 do Add(I);
    HeapQueued:=HeapAllocated;Start:=Ticks;
    while Q.Count>0 do begin
      {$IFDEF FIFO_QUEUE_API}Item:=Q.Peek;{$ELSE}Item:=Q[0];{$ENDIF}
      Check(Item.Size>=0,'Socket队首被提前释放');Cb:=Item.Callback;
      {$IFDEF FIFO_QUEUE_API}Q.Dequeue;{$ELSE}Q.Delete(0);{$ENDIF}
      // Notify已经Dispose了Item，不能再读取Dequeue的返回指针。
      Cb(nil,True);Cb:=nil;
    end;
    Elapsed:=Ticks-Start;HeapDrained:=HeapAllocated;
    Check((Calls=N) and (DestroyedProbes-Before=N),'Socket队列保留完成回调');
  finally Q.Free;end;
end;
{$ENDIF}
procedure Bench(const Name:string;const N:Integer);
var S:TMemoryServer;Keep:ICrossHttpServer;Elapsed,Total,Queued,Drained:Int64;I,Repeats:Integer;
begin
  Check((N=1) or (N=100) or (N=1000) or (N=10000),'不支持的深度');
  Repeats:=Min(100,Max(1,10000 div N));Total:=0;Queued:=0;Drained:=0;S:=nil;
  if Name='response' then begin S:=TMemoryServer.Create;Keep:=S;end;
  try
    for I:=1 to Repeats do begin
      if Name='request' then BenchClient(N,Elapsed,Queued,Drained)
      else if Name='response' then BenchServer(S,N,Elapsed,Queued,Drained)
      {$IFDEF LINUX}else if Name='socket-container' then BenchSocket(N,Elapsed,Queued,Drained){$ENDIF}
      else raise Exception.Create('未知基准 '+Name);
      Inc(Total,Elapsed);
    end;
    Writeln(Format('BENCH %s depth=%d repeats=%d us=%.3f heap_queued=%d heap_drained=%d',
      [Name,N,Repeats,Total*1000000.0/Frequency/Repeats,Int64(Queued),Int64(Drained)]));
  finally Keep:=nil;end;
end;

{$I QueueRegressions.inc}
{$I QueueSocketTests.inc}

begin
  {$IFDEF MSWINDOWS}QueryPerformanceFrequency(Frequency);{$ELSE}Frequency:=1000000000;{$ENDIF}
  try
    if ParamStr(1)='socket-network' then RunSocketNetwork(StrToInt(ParamStr(2)))
    else if ParamStr(1)='bench' then Bench(ParamStr(2),StrToInt(ParamStr(3)))
    else Regression(ParamStr(1));
  except on E:Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
