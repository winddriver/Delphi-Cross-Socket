type
  TDeferredSocket=class(TCrossHttpClientSocket)
  private FCallbacks:TList<TCrossConnectionCallback>;FGuard:ILock;
  public
    ConnectCalls:Integer;SyncFailure:Boolean;
    constructor Create(const Client:TCrossHttpClient);reintroduce;
    destructor Destroy;override;
    procedure StartLoop;override;
    procedure StopLoop;override;
    procedure Connect(const Host:string;const Port,LocalPort:Word;const Callback:TCrossConnectionCallback=nil);override;
    function FailNext:Boolean;
  end;
  TClientFixture=class
  public
    Client:TCrossHttpClient;KeepClient:ICrossHttpClient;
    Socket:TDeferredSocket;KeepSocket:ICrossHttpClientSocket;
    Seen,Codes:array[0..255] of Integer;
    Calls,Rejected,ProviderCalls:Integer;
    constructor Create(const Limit:Integer);
    destructor Destroy;override;
    procedure Request(const Id:Integer;const NilCallback:Boolean=False;
      const RaiseCallback:Boolean=False;const ReenterId:Integer=-1;const Host:string='localhost');
    procedure Drain;
  end;
constructor TDeferredSocket.Create(const Client:TCrossHttpClient);
begin FCallbacks:=TList<TCrossConnectionCallback>.Create;FGuard:=TLock.Create;
  inherited Create(Client,1,1,0,False,True,True,ctNone);end;
destructor TDeferredSocket.Destroy;
begin FCallbacks.Free;inherited;end;
procedure TDeferredSocket.StartLoop;
begin end;
procedure TDeferredSocket.StopLoop;
begin end;
procedure TDeferredSocket.Connect(const Host:string;const Port,LocalPort:Word;const Callback:TCrossConnectionCallback);
begin
  AtomicIncrement(ConnectCalls);
  if SyncFailure then begin if Assigned(Callback) then Callback(nil,False);Exit;end;
  FGuard.Enter;try FCallbacks.Add(Callback);finally FGuard.Leave;end;
end;
function TDeferredSocket.FailNext:Boolean;
var Callback:TCrossConnectionCallback;
begin
  FGuard.Enter;
  try
    Result:=FCallbacks.Count>0;if not Result then Exit;
    Callback:=FCallbacks[0];FCallbacks.Delete(0);
  finally FGuard.Leave;end;
  if Assigned(Callback) then Callback(nil,False);
end;
constructor TClientFixture.Create(const Limit:Integer);
begin
  Client:=TCrossHttpClient.Create(1,1);KeepClient:=Client;
  {$IFDEF CAPACITY_API}Client.MaxPendingRequestsPerServer:=Limit;{$ENDIF}
  Socket:=TDeferredSocket.Create(Client);KeepSocket:=Socket;
end;
destructor TClientFixture.Destroy;
begin Socket.CancelAllRequests;Drain;KeepSocket:=nil;Socket:=nil;KeepClient:=nil;Client:=nil;inherited;end;
procedure TClientFixture.Drain;
var Guard:Integer;
begin Guard:=0;while Socket.FailNext do begin Inc(Guard);Check(Guard<1000,'连接失败重试未结束');end;end;
procedure TClientFixture.Request(const Id:Integer;const NilCallback,RaiseCallback:Boolean;
  const ReenterId:Integer;const Host:string);
var R:ICrossHttpClientRequest;Callback:TCrossHttpResponseProc;Fixture:TClientFixture;
begin
  Fixture:=Self;Callback:=nil;
  if not NilCallback then Callback:=procedure(const Response:ICrossHttpClientResponse)
    begin
      Check(AtomicExchange(Fixture.Seen[Id],1)=0,'同一请求重复通知');
      Fixture.Codes[Id]:=Response.StatusCode;AtomicIncrement(Fixture.Calls);
      if Response.StatusCode=503 then AtomicIncrement(Fixture.Rejected);
      if ReenterId>=0 then Fixture.Request(ReenterId);
      if RaiseCallback then raise Exception.Create('预期容量回调异常');
    end;
  R:=TCrossHttpClientRequest.Create('POST','http://'+Host+'/'+IntToStr(Id),nil,
    function(const Data:PPointer;const Size:PNativeInt):Boolean
    begin AtomicIncrement(Fixture.ProviderCalls);Data^:=nil;Size^:=0;Result:=False;end,
    nil,nil,Callback);
  Socket.DoRequest(R);
end;
procedure TestClientCapacity(const Mode:string);
var F:TClientFixture;Limit,I,J:Integer;Threads:array[0..7] of TThread;Gate:IEvent;
  procedure Producer(const Index:Integer);
  begin
    Threads[Index]:=TThread.CreateAnonymousThread(procedure
      var K:Integer;
      begin Await(Gate,'生产者未放行');for K:=0 to 7 do F.Request(Index*8+K);end);
    Threads[Index].FreeOnTerminate:=False;Threads[Index].Start;
  end;
begin
  Limit:=2;
  if Mode='client-default' then Limit:=0;
  if Mode='client-concurrent' then Limit:=8;
  if Mode='client-cancel' then Limit:=3;
  if (Mode='client-nil') or (Mode='client-raise') or (Mode='client-reenter') or
     (Mode='client-separate') or (Mode='client-sync-fail') then Limit:=1;
  F:=TClientFixture.Create(Limit);
  try
    if Mode='client-default' then begin
      for I:=0 to 99 do F.Request(I);
      Check(F.Rejected=0,'默认无限制改变');F.Drain;Check(F.Calls=100,'默认队列遗漏通知');
    end else if Mode='client-concurrent' then begin
      Gate:=TEvent.Create(True,False);for I:=0 to High(Threads) do Producer(I);Gate.SetEvent;
      for I:=0 to High(Threads) do begin Threads[I].WaitFor;Check(Threads[I].FatalException=nil,'并发接纳异常');Threads[I].Free;end;
      Check((F.Rejected=56) and (F.Socket.ConnectCalls=1),'并发超额接纳或丢失连接预占');F.Drain;
      Check(F.Calls=64,'并发请求通知遗漏');
    end else if Mode='client-sync-fail' then begin
      F.Socket.SyncFailure:=True;for I:=0 to 19 do F.Request(I);
      Check((F.Calls=20) and (F.Rejected=0),'同步连接失败未归还额度');
    end else if Mode='client-separate' then begin
      F.Request(0,False,False,-1,'localhost');F.Request(1,False,False,-1,'other.local');F.Request(2);
      Check((F.Socket.ConnectCalls=2) and (F.Codes[2]=503),'不同server错误共享额度');F.Drain;
      Check(F.Calls=3,'独立server通知遗漏');
    end else if Mode='client-cancel' then begin
      F.Request(0);F.Request(1,False,False,4);F.Request(2,False,True);F.Request(3);
      Check(F.Codes[3]=503,'取消前未拒绝满额请求');F.Socket.CancelAllRequests;
      Check((F.Seen[1]=1) and (F.Seen[2]=1) and (F.Seen[4]=0),'取消回调重入未接纳或提前通知');
      F.Drain;Check((F.Calls=5) and (F.Rejected=1),'取消/重入计数未一次结算');
    end else if Mode='client-count' then begin
      F.Request(0);F.Request(1);F.Request(2);
      Check((F.Codes[2]=503) and (F.Socket.ConnectCalls=1),'未统计connecting加排队请求');
      Check(F.Socket.FailNext,'缺少首个连接请求');Check(F.Socket.ConnectCalls=2,'Pop重试重复计费');
      F.Drain;F.Request(3);Check(F.Seen[3]=0,'完成后没有容量');F.Drain;
      Check((F.Calls=4) and (F.Rejected=1),'完成通知错误');
    end else if (Mode='client-nil') or (Mode='client-raise') or (Mode='client-reenter') then begin
      J:=-1;if Mode='client-reenter' then J:=2;
      F.Request(0,Mode='client-nil',Mode='client-raise',J);F.Request(1);
      Check(F.Codes[1]=503,'满额请求未立即503');Check(F.Socket.FailNext,'缺少待连接请求');
      if Mode<>'client-reenter' then F.Request(2);
      Check(F.Seen[2]=0,'回调前未归还额度');F.Drain;
      if Mode='client-nil' then Check(F.Calls=2,'nil回调额度丢失') else Check(F.Calls=3,'异常或重入通知错误');
      Check(F.Rejected=1,'回收后仍拒绝请求');
    end else raise Exception.Create('未知客户端容量用例');
    Check(F.ProviderCalls=0,'未接入请求提前读取provider');
  finally F.Free;end;
end;
