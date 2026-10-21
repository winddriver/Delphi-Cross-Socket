type
  TMethodHandler = class
  public
    Calls: Integer;
    procedure Handle(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
      var AHandled: Boolean);
  end;

  TRouteWorker = class(TThread)
  private
    FRouter: IRouter;
    FResponse: ICrossHttpResponse;
    FGate: THandle;
  protected
    procedure Execute; override;
  public
    ErrorText: string;
    constructor Create(const ARouter: IRouter; const AResponse: ICrossHttpResponse; const AGate: THandle);
  end;

  TLifetimeProbe = class(TInterfacedObject)
    destructor Destroy; override;
  end;

var DestroyedProbes: Integer;
threadvar RouteCalls: Integer;

procedure TMethodHandler.Handle(const ARequest: ICrossHttpRequest;
  const AResponse: ICrossHttpResponse; var AHandled: Boolean);
begin
  Inc(Calls);
  Inc(RouteCalls);
end;

destructor TLifetimeProbe.Destroy;
begin
  Inc(DestroyedProbes);
  inherited;
end;

function TrackedHandler: TCrossHttpRouterProc;
var LKeep: IInterface;
begin
  LKeep := TLifetimeProbe.Create;
  Result := procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
    var AHandled: Boolean)
    begin
      if LKeep = nil then raise Exception.Create('闭包提前释放');
      Inc(RouteCalls);
    end;
end;

procedure AddTrackedHandler(const ARouter: IRouter);
begin
  // 独立栈帧让编译器持有的匿名函数临时引用在检查析构前释放。
  ARouter.AddRouterProc(TrackedHandler());
end;

constructor TRouteWorker.Create(const ARouter: IRouter; const AResponse: ICrossHttpResponse;
  const AGate: THandle);
begin
  inherited Create(True);
  FRouter := ARouter;
  FResponse := AResponse;
  FGate := AGate;
end;

procedure TRouteWorker.Execute;
var I: Integer; LHandled: Boolean;
begin
  try
    if WaitForSingleObject(FGate, 10000) <> WAIT_OBJECT_0 then raise Exception.Create('启动等待超时');
    for I := 1 to 3000 do
    begin
      RouteCalls := 0;
      LHandled := False;
      FRouter.Execute(nil, FResponse, LHandled);
      if (RouteCalls < 1) or (RouteCalls > 65) then raise Exception.Create('并发快照内容不完整');
    end;
  except on E: Exception do ErrorText := E.ClassName + ': ' + E.Message; end;
end;

procedure TestRouter;
var
  LFixture: TFixture;
  LRouter: IRouter;
  LRouterObj: TRouter;
  LMethod: TMethodHandler;
  LHandled, LAdded: Boolean;
  LOrder: string;
  LWorkers: array[0..3] of TRouteWorker;
  LGate: THandle;
  I, LUnexpected: Integer;
begin
  LFixture := TFixture.Create;
  LMethod := TMethodHandler.Create;
  try
    LRouter := TRouter.Create('GET');
    LRouter.AddRouterProc(LMethod.Handle);
    LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean) begin LOrder := LOrder + 'a'; end));
    LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean) begin LOrder := LOrder + 'b'; end));
    LHandled := False;
    LRouter.Execute(LFixture.Request, LFixture.Response, LHandled);
    Check((LOrder = 'ab') and (LMethod.Calls = 1), '匿名函数/对象方法执行顺序');
    LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean) begin H := True; end));
    LHandled := False;
    LRouter.Execute(LFixture.Request, LFixture.Response, LHandled);
    Check(LHandled and (LMethod.Calls = 1), 'Handled 必须在对象方法前短路');

    LRouter := TRouter.Create('GET');
    LRouterObj := LRouter as TRouter;
    LAdded := False;
    LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean)
      begin
        Inc(RouteCalls);
        if not LAdded then
        begin
          LAdded := True;
          LRouterObj.AddRouterProc(TCrossHttpRouterProc(procedure(const R2: ICrossHttpRequest; const S2: ICrossHttpResponse;
            var H2: Boolean) begin Inc(RouteCalls); end));
          LRouterObj.AddRouterProc(LMethod.Handle);
        end;
      end));
    RouteCalls := 0; LHandled := False;
    LRouter.Execute(LFixture.Request, LFixture.Response, LHandled);
    Check(RouteCalls = 1, '回调注册修改了正在执行的快照');
    RouteCalls := 0; LHandled := False;
    LRouter.Execute(LFixture.Request, LFixture.Response, LHandled);
    Check(RouteCalls = 3, '下一次执行未看到新增处理器');

    LRouter := TRouter.Create('GET');
    DestroyedProbes := 0;
    AddTrackedHandler(LRouter);
    LHandled := False;
    LRouter.Execute(LFixture.Request, LFixture.Response, LHandled);
    Check(DestroyedProbes = 0, '处理器闭包提前析构');
    LRouter := nil;
    Check(DestroyedProbes = 1, '路由释放未释放闭包');

    LUnexpected := 0;
    LFixture.Server.Get('/sent', TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean) begin S.Send('ok'); end));
    LFixture.Server.Get('/sent', TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean) begin Inc(LUnexpected); end));
    LFixture.ConnectionObj.Feed('GET /sent HTTP/1.1'#13#10'Host: localhost'#13#10#13#10);
    Check(Pos('200 OK', string(LFixture.ConnectionObj.Sent)) > 0, '响应错误');
    Check(LFixture.ConnectionObj.Writes = 2, '头体分离发送被改变');
    Check(LUnexpected = 0, 'Sent 未短路');

    // 并发测试使用无共享写入的匿名处理器，线程各自记录本轮调用次数。
    LRouter := TRouter.Create('GET');
    LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
      var H: Boolean) begin Inc(RouteCalls); end));
    LGate := CreateEvent(nil, True, False, nil);
    Check(LGate <> 0, '启动事件创建失败');
    try
      for I := 0 to High(LWorkers) do
      begin
        LWorkers[I] := TRouteWorker.Create(LRouter, LFixture.Response, LGate);
        LWorkers[I].Start;
      end;
      SetEvent(LGate);
      for I := 1 to 64 do
        LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
          var H: Boolean) begin Inc(RouteCalls); end));
      for I := 0 to High(LWorkers) do
      begin
        Check(WaitForSingleObject(LWorkers[I].Handle, 15000) = WAIT_OBJECT_0, '并发路由超时');
        LWorkers[I].WaitFor;
        Check(LWorkers[I].ErrorText = '', LWorkers[I].ErrorText);
        LWorkers[I].Free;
      end;
    finally CloseHandle(LGate); end;
  finally
    LRouter := nil;
    LMethod.Free;
    LFixture.Free;
  end;
end;

procedure BenchmarkRouter(const ACount: Integer; const AAllocations: Boolean);
var
  LRouter: IRouter;
  I: Integer;
  LHandled: Boolean;
  LStart, LEnd, LFrequency: Int64;
begin
  LRouter := TRouter.Create('GET');
  LRouter.AddRouterProc(TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest; const S: ICrossHttpResponse;
    var H: Boolean) begin Inc(RouteCalls); H := True; end));
  Check(SetThreadAffinityMask(GetCurrentThread, 4) <> 0, '绑定基准 CPU 失败');
  QueryPerformanceFrequency(LFrequency);
  RouteCalls := 0;
  if AAllocations then BeginCounting;
  try
    QueryPerformanceCounter(LStart);
    for I := 1 to ACount do
    begin
      LHandled := False;
      LRouter.Execute(nil, nil, LHandled);
    end;
    QueryPerformanceCounter(LEnd);
  finally if AAllocations then EndCounting; end;
  Check(RouteCalls = ACount, '路由调用数量错误');
  Writeln(Format('METRIC n=%d us=%.3f calls=%d bytes=%d',
    [ACount, (LEnd - LStart) * 1000000.0 / LFrequency, AllocationCalls, AllocationBytes]));
end;
