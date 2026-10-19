type
  TProgressStream=class(TMemoryStream)
  public
    Changed:IEvent;
    constructor Create;
    function Write(const Buffer;Count:LongInt):LongInt;override;
  end;
constructor TProgressStream.Create;
begin inherited;Changed:=TEvent.Create(True,False);end;
function TProgressStream.Write(const Buffer;Count:LongInt):LongInt;
begin Result:=inherited;Changed.SetEvent;end;
procedure TestClientTimeout(const Mode,Url:string);
var
  Client:ICrossHttpClient;ClientObj:TCrossHttpClient;
  FirstConnection,SecondConnection:ICrossHttpClientConnection;
  Done,Collected,ContinueScan,Scanned,InitEntered,ContinueInit:IEvent;
  Callback:TCrossHttpResponseProc;
  Init:TCrossHttpRequestInitProc;
  Scanner,Requester:TThread;
  Body:TProgressStream;
  Calls,Code,CollectedCalls:Integer;
  Command:string;
  procedure Request(const Path:string;const AStream:TStream);
  begin Client.DoRequest('GET',Url+Path,nil,TBytes(nil),AStream,Init,Callback);end;
  procedure WaitDone(const ExpectedCode:Integer);
  begin Await(Done,'HTTP完成未通知');Check(Code=ExpectedCode,'HTTP结果='+IntToStr(Code));Done.ResetEvent;end;
  procedure StartScan;
  begin
    Scanner:=TThread.CreateAnonymousThread(procedure
      begin
        ProcHttpTimeoutForTest(ClientObj,procedure
          begin AtomicIncrement(CollectedCalls);Collected.SetEvent;Await(ContinueScan,'未放行超时快照');end);
        Scanned.SetEvent;
      end);
    Scanner.FreeOnTerminate:=False;Scanner.Start;Await(Collected,'未收集到超时候选');
    Line('COLLECTED');
  end;
  procedure FinishScan;
  begin ContinueScan.SetEvent;Await(Scanned,'扫描未完成');Scanner.WaitFor;Check(Scanner.FatalException=nil,'扫描线程异常');Line('SCANNED');end;
begin
  Calls:=0;Code:=0;CollectedCalls:=0;Scanner:=nil;Requester:=nil;
  Done:=TEvent.Create(True,False);Collected:=TEvent.Create(True,False);
  ContinueScan:=TEvent.Create(True,False);Scanned:=TEvent.Create(True,False);
  InitEntered:=TEvent.Create(True,False);ContinueInit:=TEvent.Create(True,False);
  Body:=TProgressStream.Create;ClientObj:=TCrossHttpClient.Create(1);Client:=ClientObj;
  StopHttpTimeoutTimerForTest(ClientObj);Client.RequestTimeout:=1;Client.Idleout:=1;
  Init:=procedure(const R:ICrossHttpClientRequest)
    begin
      if FirstConnection=nil then FirstConnection:=R.Connection else SecondConnection:=R.Connection;
      if (Mode='idle-reserved') and (SecondConnection<>nil) then begin
        InitEntered.SetEvent;Await(ContinueInit,'预占请求未放行');
      end;
    end;
  Callback:=procedure(const R:ICrossHttpClientResponse)
    begin Code:=R.StatusCode;AtomicIncrement(Calls);Done.SetEvent;end;
  try
    Request('/first',Body);
    if Copy(Mode,1,8)='request-' then Await(Body.Changed,'未收到首段响应') else WaitDone(200);
    if Mode='idle-reserved' then begin
      Requester:=TThread.CreateAnonymousThread(procedure begin Client.DoRequest('GET',Url+'/second',nil,TBytes(nil),nil,Init,Callback);end);
      Requester.FreeOnTerminate:=False;Requester.Start;Await(InitEntered,'未预占空闲连接');
      TThread.Sleep(1100);ProcHttpTimeoutForTest(ClientObj,procedure begin Inc(CollectedCalls);end);
      Check(CollectedCalls=0,'仍在初始化的预占连接被判为空闲');
      Check(not FirstConnection.IsClosed,'预占请求被关闭');ContinueInit.SetEvent;
      Requester.WaitFor;Check(Requester.FatalException=nil,'请求线程异常');Line('SCANNED');WaitDone(200);
    end else begin
      TThread.Sleep(1100);
      if (Mode='idle-expire') or (Mode='request-expire') then begin
        ProcHttpTimeoutForTest(ClientObj,nil);
        if Mode='request-expire' then WaitDone(408)
        else begin Check(FirstConnection.IsClosed,'真正空闲连接未关闭');Request('/second',nil);Line('SCANNED');WaitDone(200);end;
      end else begin
        StartScan;
        if Mode='request-progress' then begin
          Body.Changed.ResetEvent;Line('CHANGE');Readln(Command);Check(Command='changed','缺少正文进展命令');
          Await(Body.Changed,'新正文未到解析器');FinishScan;WaitDone(200);
        end else begin
          if Mode='request-reuse' then begin Line('CHANGE');WaitDone(200);end;
          Request('/second',nil);Check(SecondConnection=FirstConnection,'候选未实际被复用');
          Line('SECOND');FinishScan;WaitDone(200);
        end;
      end;
    end;
    if Mode='request-progress' then Check(Calls=1,'正文进展通知重复')
    else if Mode='request-expire' then Check(Calls=1,'真正超时通知重复')
    else Check(Calls=2,'复用通知重复或遗漏');
    if Mode='idle-expire' then Check(SecondConnection<>FirstConnection,'真正过期连接被复用')
    else if (Mode<>'request-expire') then Check(not FirstConnection.IsClosed,'新活动连接被旧快照关闭');
    Line('PASS '+Mode);
  finally
    ContinueScan.SetEvent;ContinueInit.SetEvent;Scanner.Free;Requester.Free;
    Client.CancelAll;FirstConnection:=nil;SecondConnection:=nil;Client:=nil;ClientObj:=nil;
    Callback:=nil;Init:=nil;Body.Free;
  end;
end;
