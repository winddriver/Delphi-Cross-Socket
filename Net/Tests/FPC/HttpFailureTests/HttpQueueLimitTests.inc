procedure TestQueueLimit(const ACase: string);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TQueueConnection;
  LConnection: ICrossHttpConnection;
  LCalls, LFailed, I: Integer;
begin
  LServerObject := TQueueServer.Create;
  LServer := LServerObject;
  {$IFDEF HTTP_QUEUE_LIMIT}
  if ACase <> 'default' then LServerObject.MaxPendingRequests := 2;
  {$ENDIF}
  LObject := TQueueConnection.Create(LServerObject);
  LConnection := LObject;
  LCalls := 0;
  LFailed := 0;
  try
    if ACase = 'closed' then
    begin
      LObject.Cleanup;
      LObject.Feed(GoodRequest('/closed'));
      Check(LConnection.Pending = 0, '关闭后新建了请求队列项');
      Check(LServerObject.Requests.Count = 0, '关闭后发布请求');
      Exit;
    end;
    LObject.Feed(GoodRequest('/first'));
    if ACase = 'active' then
      LServerObject.Responses[0].SendNoCompress('first',
        procedure(const C: ICrossConnection; const OK: Boolean)
        begin
          Inc(LCalls);
          if not OK then Inc(LFailed);
        end);
    if ACase = 'parsing' then
    begin
      LObject.Feed('POST /second HTTP/1.1'#13#10'Host: localhost'#13#10 +
        'Content-Length: 2'#13#10#13#10'a');
      Check((LConnection.Pending = 2) and (LServerObject.Requests.Count = 1),
        '解析中的正文没有占用容量');
      LObject.Feed('b');
    end
    else LObject.Feed(GoodRequest('/second'));
    Check((LConnection.Pending = 2) and (LServerObject.Requests.Count = 2),
      '恰好达到容量时错误拒绝');
    if ACase = 'boundary' then
    begin
      Check(LObject.CloseRequests = 0, '边界请求导致关闭');
      Exit;
    end;
    if ACase = 'release' then
    begin
      LServerObject.Responses[0].SendNoCompress('first');
      LObject.Drain;
      Check(LConnection.Pending = 1, '发送完成未释放容量');
      LObject.Feed(GoodRequest('/third'));
      Check((LConnection.Pending = 2) and (LServerObject.Requests.Count = 3),
        '释放后的容量未能复用');
      Check(LObject.CloseRequests = 0, '正常容量复用导致关闭');
      Exit;
    end;
    if ACase = 'default' then
    begin
      for I := 3 to 20 do LObject.Feed(GoodRequest('/more'));
      Check((LConnection.Pending = 20) and (LObject.CloseRequests = 0),
        '默认配置改变了原有不限量行为');
      Exit;
    end;
    // 没有完整头也必须在开始接纳下一请求时拒绝，不等无限正文到齐。
    LObject.Feed('G');
    Check(LObject.CloseRequests = 1, '超过容量未请求关闭');
    Check(LServerObject.Requests.Count = 2, '超限请求进入业务');
    LObject.Cleanup;
    if ACase = 'active' then
    begin
      Check((LCalls = 0) and (LConnection.Pending = 1), '在途写被提前释放');
      LObject.CompleteOne(True, True);
      Check((LCalls = 1) and (LFailed = 1), '在途取消未唯一失败结算');
    end;
    Check(LConnection.Pending = 0, '取消后容量未归零');
    LObject.Feed(GoodRequest('/tail'));
    Check((LServerObject.Requests.Count = 2) and (LConnection.Pending = 0),
      '超限终态仍接纳尾部请求');
  finally
    LObject.Cleanup;
    LObject.Drain;
    LServerObject.Responses.Clear;
    LConnection := nil;
    LServer := nil;
  end;
end;
