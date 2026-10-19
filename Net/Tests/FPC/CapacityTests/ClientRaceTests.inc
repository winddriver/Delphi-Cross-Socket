{$IFDEF CLIENT_RACE_HOOK}
procedure TestClientClosingRace(const Mode,Url:string);
var F:TNetworkClient;Paused,Closing,AllowWork,AllowDestroy,DestroyedDone:IEvent;
    Requester,Destroyer:TThread;Keep:ICrossHttpClient;Stage:string;Expected:Integer;
begin
  F:=TNetworkClient.Create(Url,2);Requester:=nil;Destroyer:=nil;
  Paused:=TEvent.Create(True,False);Closing:=TEvent.Create(True,False);
  AllowWork:=TEvent.Create(True,False);AllowDestroy:=TEvent.Create(True,False);DestroyedDone:=TEvent.Create(True,False);
  if Mode='client-race-pop' then Stage:='after-pop'
  else if Mode='client-race-push' then Stage:='before-push' else Stage:='registered';
  SetClientAdmissionTestHook(procedure(const Name:string;const Request:ICrossHttpClientRequest)
    begin
      if (Name=Stage) and ((Request=nil) or (Request.Path='/1')) then begin
        Paused.SetEvent;Await(AllowWork,'未放行内部接纳');
      end;
      if Name='after-cancel' then begin Closing.SetEvent;Await(AllowDestroy,'未放行析构收尾');end;
    end);
  try
    if Stage='registered' then begin
      Requester:=TThread.CreateAnonymousThread(procedure begin F.Request(0);end);
      Requester.FreeOnTerminate:=False;Requester.Start;
    end else begin
      F.Request(0);
      if Stage='before-push' then begin
        Requester:=TThread.CreateAnonymousThread(procedure begin F.Request(1);end);
        Requester.FreeOnTerminate:=False;Requester.Start;
      end else F.Request(1);
    end;
    Await(Paused,'未进入目标接纳边界');
    Keep:=F.Client;F.Client:=nil;
    Destroyer:=TThread.CreateAnonymousThread(procedure begin Keep:=nil;DestroyedDone.SetEvent;end);
    Destroyer.FreeOnTerminate:=False;Destroyer.Start;
    Await(Closing,'析构未经过取消快照');AllowWork.SetEvent;
    Expected:=1;if Stage='after-pop' then Expected:=2;
    F.WaitCount(Expected);
    if Stage='registered' then Check(F.Codes[0]=400,'停止后登记的连接仍发布请求')
    else Check(F.Codes[1]=400,'已弹出或迟到入队请求未取消');
    AllowDestroy.SetEvent;Await(DestroyedDone,'关闭期间重新接入导致停止挂起');
    Destroyer.WaitFor;Check(Destroyer.FatalException=nil,'析构线程异常');
    if Requester<>nil then begin Requester.WaitFor;Check(Requester.FatalException=nil,'请求线程异常');end;
    Check(F.Destroyed=1,'竞争析构次数错误');
  finally
    AllowWork.SetEvent;AllowDestroy.SetEvent;Requester.Free;Destroyer.Free;
    SetClientAdmissionTestHook(nil);F.Free;
  end;
end;
{$ELSE}
procedure TestClientClosingRace(const Mode,Url:string);
begin raise Exception.Create('此源码没有接纳门控入口');end;
{$ENDIF}
