unit WebSocketSenderTests;
{$I zLib.inc}
interface
procedure RunWebSocketSenderTests;
procedure RunWebSocketMessageQueueTest(const AName:string);
implementation
uses SysUtils, Classes, SyncObjs, Generics.Collections, Net.SocketAPI, Net.CrossSocket.Base,
  Net.CrossWebSocketParser, Net.CrossWebSocketSender
  {$IFNDEF WS_SENDER_ONLY}, Net.CrossWebSocketClient,
  Net.CrossWebSocketServer, Net.CrossSslSocket.OpenSSL{$ENDIF};
type
  TTestConnection = class(TCrossConnectionBase)
  protected
    procedure DirectSend(const ABuffer:Pointer; const ACount:Integer;
      const ACallback:TCrossConnectionCallback); override;
  public
    WriteLock:TCriticalSection;
    Frames:TList<TBytes>;
    Pending:TList<TCrossConnectionCallback>;
    PendingBuffers:TList<Pointer>;
    PendingBytes:TList<TBytes>;
    AutoComplete, RaiseBefore, RaiseAfter:Boolean;
    CloseCount, DisconnectCount, SendDepth, MaxSendDepth, BufferChecks:Integer;
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure Close; override;
    procedure Disconnect; override;
    procedure Complete(const ASuccess:Boolean);
  end;
  TOwnedSenderConnection = class(TTestConnection)
  public
    Sender:TCrossWebSocketSender;
    Destroyed:PInteger;
    destructor Destroy; override;
  end;
destructor TOwnedSenderConnection.Destroy;
begin
  Sender.Free;
  if Destroyed<>nil then Inc(Destroyed^);
  inherited;
end;
constructor TTestConnection.Create;
begin
  inherited Create(nil,INVALID_SOCKET,ctConnect,'',nil);
  ConnectStatus:=csConnected;AutoComplete:=True;
  WriteLock:=TCriticalSection.Create;
  Frames:=TList<TBytes>.Create;Pending:=TList<TCrossConnectionCallback>.Create;
  PendingBuffers:=TList<Pointer>.Create;PendingBytes:=TList<TBytes>.Create;
end;
destructor TTestConnection.Destroy;
begin PendingBytes.Free;PendingBuffers.Free;Pending.Free;Frames.Free;WriteLock.Free;inherited;end;
procedure TTestConnection.Close;
begin if IsClosed then Exit;Inc(CloseCount);ConnectStatus:=csClosed;end;
procedure TTestConnection.Disconnect;
begin if ConnectStatus in [csDisconnected,csClosed] then Exit;Inc(DisconnectCount);ConnectStatus:=csDisconnected;end;
procedure TTestConnection.DirectSend(const ABuffer:Pointer;const ACount:Integer;
  const ACallback:TCrossConnectionCallback);
var LData:TBytes;
begin
  Inc(SendDepth);if SendDepth>MaxSendDepth then MaxSendDepth:=SendDepth;
  try
  if RaiseBefore then raise Exception.Create('发送前异常');
  SetLength(LData,ACount);if ACount>0 then Move(ABuffer^,LData[0],ACount);
  WriteLock.Enter;try Frames.Add(LData);finally WriteLock.Leave;end;
  if AutoComplete then begin if Assigned(ACallback) then ACallback(Self,True);end
  else begin Pending.Add(ACallback);PendingBuffers.Add(ABuffer);PendingBytes.Add(LData);end;
  if RaiseAfter then raise Exception.Create('完成后异常');
  finally Dec(SendDepth);end;
end;
procedure TTestConnection.Complete(const ASuccess:Boolean);
var LCallback:TCrossConnectionCallback;LBytes:TBytes;LBuffer:Pointer;
begin
  if Pending.Count=0 then raise Exception.Create('没有待完成发送');
  LBuffer:=PendingBuffers[0];LBytes:=PendingBytes[0];
  if (Length(LBytes)>0) and not CompareMem(LBuffer,@LBytes[0],Length(LBytes)) then
    raise Exception.Create('物理完成前发送缓冲区被释放或改写');
  Inc(BufferChecks);PendingBuffers.Delete(0);PendingBytes.Delete(0);
  LCallback:=Pending[0];Pending.Delete(0);
  if Assigned(LCallback) then LCallback(Self,ASuccess);
end;
procedure Check(const AValue:Boolean;const AMessage:string);
begin if not AValue then raise Exception.Create(AMessage);end;
{$I WebSocketMessageQueueTests.inc}
procedure RunWebSocketSenderTests;
var C:TTestConnection; Keep:ICrossConnection; S:TCrossWebSocketSender;
    Calls,ReadCount,I,N:Integer; LastSuccess,Raised:Boolean; Data:Byte; Err:string;
    Large,Expected,Actual,Part:TBytes; Threads:array[0..15] of TThread; Start:TEvent;
  procedure Setup;
  begin
    C:=TTestConnection.Create;Keep:=C;S:=TCrossWebSocketSender.Create(C,True);
    Calls:=0;LastSuccess:=False;Data:=$41;
  end;
  procedure Cleanup;
  begin C.Pending.Clear;S.Free;Keep:=nil;end;
  function Op(const AIndex:Integer):Byte;
  var L:TBytes;
  begin L:=C.Frames[AIndex];Result:=L[0] and $0F;end;
begin
  Setup;
  try
    C.AutoComplete:=False;
    S.Send(2,True,@Data,1,procedure(const OK:Boolean)begin Inc(Calls);LastSuccess:=OK;end);
    S.RequestClose;S.ReceiveClose(nil);
    Check((C.Frames.Count=1) and (C.DisconnectCount=0),'Close不能越过未完成数据帧');
    S.Send(2,True,@Data,1,procedure(const OK:Boolean)begin Check(not OK,'关闭后接纳发送');end);
    C.Complete(True);
    Check((Calls=1) and LastSuccess and (C.Frames.Count=2) and (Op(1)=8),'数据结束后发送Close');
    Check(C.DisconnectCount=0,'Close尚未完成就断开');
    C.Complete(True);Check(C.DisconnectCount=1,'双向Close完成未断开');
    S.RequestClose;S.ReceiveClose(nil);Check(C.Frames.Count=2,'重复Close');
  finally Cleanup;end;
  Setup;
  try
    S.RequestClose;Check((C.Frames.Count=1) and (C.DisconnectCount=0),'本地主动关闭须等待对端');
    S.ReceiveClose(nil);Check(C.DisconnectCount=1,'收到对端Close');
  finally Cleanup;end;
  Setup;
  try
    C.AutoComplete:=False;
    S.Send(2,True,@Data,1);S.RequestClose;C.Complete(False);
    Check((C.CloseCount=1) and (C.Frames.Count=1),'I/O失败必须关闭且不再发送Close');
  finally Cleanup;end;
  Setup;
  try
    Raised:=False;
    try S.Send(2,True,@Data,1,procedure(const OK:Boolean)begin Inc(Calls);raise Exception.Create('业务异常');end);
    except on E:Exception do Raised:=E.Message='业务异常';end;
    Check(Raised and (Calls=1) and (C.CloseCount=0),'业务异常导致重复结算');
    S.RequestClose;Check((C.Frames.Count=2) and (Op(1)=8),'业务异常后发送计数未归零');
  finally Cleanup;end;
  for I:=0 to 1 do begin
    Setup;
    try
      C.RaiseBefore:=I=0;C.RaiseAfter:=I=1;Raised:=False;
      try S.Send(2,True,@Data,1,procedure(const OK:Boolean)begin Inc(Calls);LastSuccess:=OK;end);
      except Raised:=True;end;
      Check(Raised and (Calls=1),'同步异常重复通知');
      Check(LastSuccess=(I=1),'同步异常成功/失败错误');
      Check(C.CloseCount=Ord(I=0),'完成后异常被误当I/O失败');
    finally Cleanup;end;
  end;
  Setup;
  try
    ReadCount:=0;
    S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
      begin Inc(ReadCount);Result:=ReadCount<=3;if Result then begin P^:=@Data;N^:=1;end;end,
      procedure(const OK:Boolean)begin Inc(Calls);LastSuccess:=OK;end);
    Check((Calls=1) and LastSuccess and (ReadCount=4) and (C.Frames.Count=4),'同步分片发送');
    Check((Op(0)=2) and (Op(1)=0) and (Op(2)=0) and (Op(3)=0),'同步重入opcode错误');
  finally Cleanup;end;
  Setup;
  try
    C.AutoComplete:=False;ReadCount:=0;
    S.SendChunks(function(const P:PPointer;const N:PNativeInt):Boolean
      begin Inc(ReadCount);P^:=@Data;N^:=1;Result:=True;end,
      procedure(const OK:Boolean)begin Inc(Calls);LastSuccess:=OK;end);
    S.RequestClose;C.Complete(True);
    Check((Calls=1) and not LastSuccess and (ReadCount=1),'关闭仍读取后续分片');
    Check((C.CloseCount=0) and (C.Frames.Count=2) and (Op(1)=8),'取消截断Close');
    C.Complete(True);S.ReceiveClose(nil);Check(C.DisconnectCount=1,'取消后关闭握手');
  finally Cleanup;end;
  Setup;
  try
    C.AutoComplete:=False;S.CloseTimeoutMs:=1;
    S.Send(2,True,@Data,1);S.RequestClose;TThread.Sleep(50);S.CheckTimeout;
    Check(C.CloseCount=1,'挂起发送关闭超时');C.Complete(False);
    Check(C.Frames.Count=1,'超时后仍发送Close');
  finally Cleanup;end;
  Setup;
  try
    S.Send(2,True,@Data,1,procedure(const OK:Boolean)begin S.RequestClose;end);
    Check((C.Frames.Count=2) and (Op(1)=8),'发送回调重入关闭');
  finally Cleanup;end;
  Setup;
  try
    C.AutoComplete:=False;
    SetLength(Large,70000);for I:=0 to High(Large) do Large[I]:=Byte(I and $FF);
    Expected:=TCrossWebSocketParser.MakeFrameData(2,True,True,@Large[0],Length(Large));
    N:=Length(Expected);SetLength(Expected,N+2);Expected[N]:=$88;Expected[N+1]:=0;
    S.Send(2,True,@Large[0],Length(Large));S.ReceiveClose(nil);
    while C.Pending.Count>0 do C.Complete(True);
    Actual:=nil;
    for I:=0 to C.Frames.Count-1 do begin
      Part:=C.Frames[I];N:=Length(Actual);SetLength(Actual,N+Length(Part));
      if Length(Part)>0 then Move(Part[0],Actual[N],Length(Part));
    end;
    Check((Length(Actual)=Length(Expected)) and CompareMem(@Actual[0],@Expected[0],Length(Expected)),
      'Close插入底层拆分的大帧中');
    Check(C.DisconnectCount=1,'大帧后的关闭握手');
  finally Cleanup;end;
  Setup;
  Start:=TEvent.Create(nil,True,False,'');
  try
    for I:=0 to High(Threads) do begin
      Threads[I]:=TThread.CreateAnonymousThread(procedure
        begin
          if Start.WaitFor(5000)<>wrSignaled then raise Exception.Create('并发启动超时');
          S.Send(2,True,@Data,1);S.RequestClose;
        end);
      Threads[I].FreeOnTerminate:=False;Threads[I].Start;
    end;
    Start.SetEvent;
    for I:=0 to High(Threads) do Threads[I].WaitFor;
    for I:=0 to High(Threads) do Check(Threads[I].FatalException=nil,'并发发送线程异常');
    Check(Op(C.Frames.Count-1)=8,'Close未排在最后');
    N:=0;for I:=0 to C.Frames.Count-1 do if Op(I)=8 then Inc(N);
    Check(N=1,'并发发送多个Close');
    S.ReceiveClose(nil);Check(C.DisconnectCount=1,'并发关闭未完成');
  finally
    for I:=0 to High(Threads) do Threads[I].Free;
    Start.Free;Cleanup;
  end;
  {$IF Defined(CROSS_OPENSSL_SELFTEST) and not Defined(WS_SENDER_ONLY)}
  Check(CrossOpenSslSelfTest_CloseDrainsPendingWrites(Err),Err);
  Check(CrossOpenSslSelfTest_PendingCallbackExceptionDoesNotStall(Err),Err);
  {$ENDIF}
  Writeln('WebSocket sender, close ordering and lifetime tests passed.');
end;
end.
