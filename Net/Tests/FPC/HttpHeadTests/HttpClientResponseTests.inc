procedure TestClientResponse(const AMode, AUrl: string);
var
  LClient: ICrossHttpClient;
  LDone: IEvent;
  LCallback: TCrossHttpResponseProc;
  LInit: TCrossHttpRequestInitProc;
  LResponse: ICrossHttpClientResponse;
  LCallbacks: Integer;
  LId, LBody: string;
  LMethod: string;
  LBytes: TBytes;
begin
  LCallbacks := 0;
  LClient := TCrossHttpClient.Create(1);
  LClient.RequestTimeout := 3;
  LDone := TEvent.Create(True, False);
  LCallback :=
    procedure(const R: ICrossHttpClientResponse)
    begin
      AtomicIncrement(LCallbacks);
      LResponse := R;
      LDone.SetEvent;
    end;
  LInit := nil;
  LMethod := THttpMethod.GET;
  if AMode = 'response-head-metadata' then LMethod := THttpMethod.HEAD;
  if AUrl.EndsWith('/request-close') then
    LInit :=
      procedure(const R: ICrossHttpClientRequest)
      begin R.Header['Connection'] := 'example, close'; end;
  try
    LClient.DoRequest(LMethod, AUrl, nil, TBytes(nil), nil, LInit, LCallback);
    Check(LDone.WaitFor(8000) = TWaitResult.wrSignaled, '首个响应超时');
    Check(LResponse <> nil, '缺少响应对象');
    if AMode = 'response-invalid' then
    begin
      Check((LResponse.StatusCode = 400) and (LResponse.Connection = nil),
        '畸形响应仍被当作成功报文或状态不是解析失败');
      Check((LResponse.Content = nil) or (LResponse.Content.Size = 0), '失败响应泄漏了未验证正文');
      Check(LResponse.StatusText <> 'Connection lost', '只靠对端断开报告失败');
      LId := '';
    end
    else
    begin
      if (AMode = 'response-empty') or (AMode = 'response-head-metadata') then
      begin
        if AMode = 'response-empty' then Check(LResponse.StatusCode = 204, '合法无字段204被拒绝')
        else Check(LResponse.StatusCode = 200, '合法HEAD表示元数据被拒绝');
        Check((LResponse.Content = nil) or (LResponse.Content.Size = 0), '204带有正文');
      end
      else
      begin
        Check(LResponse.StatusCode = 200, '合法响应状态错误');
        Check((LResponse.Content <> nil) and (LResponse.Content.Size = 2), '正文定界错误');
        SetLength(LBytes, 2); LResponse.Content.Position := 0;
        LResponse.Content.ReadBuffer(LBytes[0], 2);
        LBody := TEncoding.ASCII.GetString(LBytes);
        Check(LBody = 'ok', '合法正文内容错误');
      end;
      LId := LResponse.Header['X-Connection-Id'];
    end;
    LResponse := nil;
    LDone.ResetEvent;
    LClient.DoRequest(THttpMethod.GET, AUrl + '/after', nil, TBytes(nil), nil, nil, LCallback);
    Check(LDone.WaitFor(8000) = TWaitResult.wrSignaled, '后续请求超时');
    Check((LResponse <> nil) and (LResponse.StatusCode = 200), '后续响应错误');
    Check((LResponse.Content <> nil) and (LResponse.Content.Size = 2), '后续响应混入残留正文');
    if (AMode = 'response-reuse') or (AMode = 'response-head-metadata') then
      Check(LId = LResponse.Header['X-Connection-Id'], '合法长连接未复用');
    if AMode = 'response-close' then
      Check(LId <> LResponse.Header['X-Connection-Id'], '应关闭的连接仍被复用');
    LClient.CancelAll;
    LClient := nil;
    Check(AtomicCmpExchange(LCallbacks, 0, 0) = 2, '响应结果通知重复或遗漏');
  finally
    if LClient <> nil then LClient.CancelAll;
    LClient := nil;
    LCallback := nil; LInit := nil; LResponse := nil;
  end;
end;
