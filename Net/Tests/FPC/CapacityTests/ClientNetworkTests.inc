type
  TCountedClient=class(TCrossHttpClient)
  public
    Destroyed:PInteger;
    destructor Destroy;override;
  end;
  TNetworkClient=class
  public
    Client:ICrossHttpClient;ClientObject:TCrossHttpClient;
    Calls,Destroyed:Integer;ReenterOnCancel:Boolean;Seen,Codes:array[0..7] of Integer;
    Changed:IEvent;FirstConnection,LastConnection:ICrossHttpClientConnection;
    Url:string;
    constructor Create(const AUrl:string;const Limit:Integer);
    destructor Destroy;override;
    procedure Request(const Id:Integer;const NoCallback:Boolean=False;const RaiseCallback:Boolean=False);
    procedure WaitCount(const N:Integer);
  end;
destructor TCountedClient.Destroy;
var Counter:PInteger;
begin Counter:=Destroyed;try inherited;finally if Counter<>nil then AtomicIncrement(Counter^);end;end;
constructor TNetworkClient.Create(const AUrl:string;const Limit:Integer);
begin
  Url:=AUrl;Changed:=TEvent.Create(True,False);ClientObject:=TCountedClient.Create(2,1);TCountedClient(ClientObject).Destroyed:=@Destroyed;Client:=ClientObject;
  {$IFDEF CAPACITY_API}ClientObject.MaxPendingRequestsPerServer:=Limit;{$ENDIF}
  Client.RequestTimeout:=5;
end;
destructor TNetworkClient.Destroy;
begin if Client<>nil then Client.CancelAll;FirstConnection:=nil;LastConnection:=nil;Client:=nil;inherited;end;
procedure TNetworkClient.Request(const Id:Integer;const NoCallback,RaiseCallback:Boolean);
var Fixture:TNetworkClient;Callback:TCrossHttpResponseProc;
begin
  Fixture:=Self;Callback:=nil;
  if not NoCallback then Callback:=procedure(const Response:ICrossHttpClientResponse)
    begin
      Check(AtomicExchange(Fixture.Seen[Id],1)=0,'真实TCP请求重复通知');
      Fixture.Codes[Id]:=Response.StatusCode;AtomicIncrement(Fixture.Calls);Fixture.Changed.SetEvent;
      if Fixture.ReenterOnCancel and (Id=1) and (Response.StatusCode=400) then
        // 原始对象指针重入，不能通过新建接口引用复活零引用的析构对象。
        Fixture.ClientObject.DoRequest('GET',Fixture.Url+'/5',nil,TBytes(nil),nil,nil,
          procedure(const R:ICrossHttpClientResponse)
          begin
            Check(AtomicExchange(Fixture.Seen[5],1)=0,'析构重入重复通知');
            Fixture.Codes[5]:=R.StatusCode;AtomicIncrement(Fixture.Calls);Fixture.Changed.SetEvent;
          end);
      if RaiseCallback then raise Exception.Create('预期真实回调异常');
    end;
  Client.DoRequest('GET',Url+'/'+IntToStr(Id),nil,TBytes(nil),nil,
    procedure(const R:ICrossHttpClientRequest)
    begin
      Fixture.LastConnection:=R.Connection;
      if Fixture.FirstConnection=nil then Fixture.FirstConnection:=R.Connection;
    end,Callback);
end;
procedure TNetworkClient.WaitCount(const N:Integer);
var Remaining:Integer;
begin
  Remaining:=500;
  while AtomicCmpExchange(Calls,0,0)<N do begin
    Check(Remaining>0,'真实TCP完成通知超时');Dec(Remaining);Changed.WaitFor(10);Changed.ResetEvent;
  end;
end;
procedure TestClientNetwork(const Mode,Url:string);
var F:TNetworkClient;Command:string;I:Integer;
begin
  F:=TNetworkClient.Create(Url,2);
  try
    F.ReenterOnCancel:=Mode='client-tcp-stop-reenter';
    if Mode='client-tcp-nil' then begin
      {$IFDEF CAPACITY_API}F.ClientObject.MaxPendingRequestsPerServer:=1;{$ENDIF}
      F.Request(0,True);Line('READY');
      I:=500;
      while (F.FirstConnection=nil) or (F.FirstConnection.RequestStatus<>rsIdle) do begin
        Check(I>0,'nil回调请求未结束');Dec(I);TThread.Sleep(10);
      end;
      // _EndRequest在置idle之后执行，给连接池状态一致性收尾留下门控。
      TThread.Sleep(10);F.Request(3);F.WaitCount(1);Check(F.Codes[3]=200,'nil回调后额度未恢复');
    end else begin
      F.Request(0,False,Mode='client-tcp-raise');F.Request(1);F.Request(2);
      Check(F.Codes[2]=503,'活动请求与队列没有共用容量');Line('READY');
      if (Mode='client-tcp-cancel') or Mode.StartsWith('client-tcp-stop') then begin
        Readln(Command);Check(Command='cancel','缺少取消门控');
        if Mode.StartsWith('client-tcp-stop') then F.Client:=nil else F.Client.CancelAll;
        F.WaitCount(3);Check((F.Codes[0]=400) and (F.Codes[1]=400),'取消遗漏已接纳请求');Line('CLEARED');
        if Mode.StartsWith('client-tcp-stop') then begin
          Check(F.Destroyed=1,'客户端析构次数错误');
          if F.ReenterOnCancel then begin F.WaitCount(4);Check(F.Codes[5]=400,'析构重入重新接纳');end;
          Exit;
        end;
      end else begin
        F.WaitCount(3);Check((F.Codes[0]=200) and (F.Codes[1]=200),'已接纳请求失败');
      end;
      F.Request(3);F.WaitCount(4);Check(F.Codes[3]=200,'容量释放后新请求失败');
    end;
    if Mode<>'client-tcp-cancel' then Check(F.FirstConnection=F.LastConnection,'拒绝或回调异常关闭健康连接');
  finally F.Free;end;
end;
