procedure TestSendPolicy(const ACase: string);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TMemoryConnection;
  LConnection: ICrossHttpConnection;
  LResponse: ICrossHttpResponse;
  LRequest, LHeader, LOutput, LVersion: AnsiString;
  LCode, LSplit, LCalls, LNextCalls: Integer;
  LClose, LSuccess, LNextSuccess, LNoBody: Boolean;
begin
  LCode := 200;
  LClose := False;
  LNoBody := False;
  LVersion := 'HTTP/1.1';
  LHeader := '';
  if ACase = '404' then begin LCode := 404; LClose := True; end;
  if ACase = '500' then begin LCode := 500; LClose := True; end;
  if ACase = 'request-list' then
  begin LHeader := 'Connection: keep-alive, CLOSE'#13#10; LClose := True; end;
  if ACase = 'request-duplicates' then
  begin LHeader := 'Connection: keep-alive'#13#10'Connection: close'#13#10; LClose := True; end;
  if ACase.StartsWith('http10') then
  begin
    LVersion := 'HTTP/1.0';
    LClose := True;
    if ACase = 'http10-list' then
    begin LHeader := 'Connection: example, keep-alive'#13#10; LClose := False; end;
    if ACase = 'http10-close' then
      LHeader := 'Connection: keep-alive, close'#13#10;
  end;
  if ACase = 'snapshot-204' then begin LCode := 204; LNoBody := True; end;
  LServerObject := TQueueServer.Create;
  LServer := LServerObject;
  LObject := TMemoryConnection.Create(LServerObject);
  LConnection := LObject;
  LCalls := 0;
  LNextCalls := 0;
  LSuccess := False;
  LNextSuccess := False;
  try
    LRequest := GoodRequest('/blocker') + 'GET /policy ' + LVersion + #13#10 +
      'Host: localhost'#13#10 + LHeader + #13#10 + GoodRequest('/next');
    LObject.Feed(LRequest);
    Check(LServerObject.Responses.Count = 3, '策略请求未全部登记');
    LResponse := LServerObject.Responses[1];
    LResponse.StatusCode := LCode;
    if (ACase = 'header-close') or (ACase = 'snapshot-close') then
    begin LResponse.Header['Connection'] := 'close'; LClose := True; end;
    if ACase = 'header-list' then
    begin LResponse.Header['Connection'] := 'example, CLOSE'; LClose := True; end;
    if ACase = 'header-duplicates' then
    begin
      LResponse.Header.Add('Connection', 'keep-alive', True);
      LResponse.Header.Add('connection', 'close', True);
      LClose := True;
    end;
    if ACase = 'header-nontoken' then LResponse.Header['Connection'] := 'x-close';
    if ACase = 'request-list' then LResponse.Header['Connection'] := 'keep-alive';
    LResponse.SendNoCompress('payload',
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); LSuccess := OK; end);
    LServerObject.Responses[2].SendNoCompress('next',
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LNextCalls); LNextSuccess := OK; end);
    Check(LObject.Sent = '', '响应越过未就绪队首');
    // Send 接纳后修改外部对象，不能改变已经选定的线缆状态、正文和关闭决定。
    if ACase = 'snapshot-200' then LResponse.StatusCode := 204;
    if ACase = 'snapshot-204' then LResponse.StatusCode := 200;
    if ACase = 'snapshot-connection' then LResponse.Header['Connection'] := 'close';
    if ACase = 'snapshot-close' then LResponse.Header['Connection'] := 'keep-alive';
    LServerObject.Responses[0].SendNoCompress('blocker');
    LObject.CompleteWrites;
    // 无真实 socket 的组件连接需要显式完成内核断开后的清理阶段。
    if LObject.DisconnectRequests > 0 then LObject.Cleanup;
    Check((LCalls = 1) and LSuccess, '完整发送响应应恰好一次成功，HTTP状态不是传输失败');
    Check(LNextCalls = 1, '后续响应通知遗漏或重复');
    Check(LNextSuccess = not LClose, '后续响应与关闭决定不一致');
    Check(LObject.DisconnectRequests = Ord(LClose), '实际关闭次数与策略不一致');
    LSplit := Pos('blocker', LObject.Sent);
    Check(LSplit > 0, '缺少队首正文');
    LOutput := Copy(LObject.Sent, LSplit + Length('blocker'), MaxInt);
    Check(Pos(LVersion + ' ' + AnsiString(IntToStr(LCode)) + ' ', LOutput) = 1,
      '接纳后的状态被迟到修改改变');
    LSplit := Pos(#13#10#13#10, LOutput);
    LHeader := Copy(LOutput, 1, LSplit + 3);
    LOutput := Copy(LOutput, LSplit + 4, MaxInt);
    Check((Pos('connection: close'#13#10, AnsiString(LowerCase(string(LHeader)))) > 0) = LClose,
      'Connection响应头与实际关闭不一致');
    if LNoBody then Check(Pos('payload', LOutput) = 0, '无正文策略被迟到修改改变')
    else Check(Pos('payload', LOutput) = 1, '普通正文丢失');
    Check(LConnection.Pending = 0, '收尾后仍有挂起请求');
  finally
    LObject.Cleanup;
    LObject.CompleteWrites;
    LServerObject.Responses.Clear;
    LResponse := nil;
    LConnection := nil;
    LServer := nil;
  end;
end;

type
  TPolicyBodyStream = class(TBodyReadStream)
  public
    Truncated: Boolean;
    function GetSize: Int64; override;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

function TPolicyBodyStream.GetSize: Int64;
begin
  if Truncated then Result := 8 else Result := 3;
end;

function TPolicyBodyStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := inherited Read(Buffer, Min(Count, 1));
end;

procedure TestSendSourceFailure(const ACase: string);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TMemoryConnection;
  LConnection: ICrossHttpConnection;
  LSource: TCrossHttpChunkDataFunc;
  LCallback: TCrossConnectionCallback;
  LData: TBytes;
  LStream: TPolicyBodyStream;
  LShort: Boolean;
  LReads, LCalls, LFailures, I: Integer;
begin
  LServerObject := TQueueServer.Create;
  LServer := LServerObject;
  LObject := TMemoryConnection.Create(LServerObject);
  LConnection := LObject;
  LReads := 0; LCalls := 0; LFailures := 0;
  LStream := nil;
  LShort := ACase.EndsWith('short');
  SetLength(LData, 65536);
  for I := 0 to High(LData) do LData[I] := Byte((I * 31 + (I shr 8)) and 255);
  try
    LObject.Feed(GoodRequest('/blocker') + GoodRequest('/source') + GoodRequest('/next'));
    LSource :=
      function(const P: PPointer; const N: PNativeInt): Boolean
      begin
        Inc(LReads);
        if ACase.EndsWith('first') or (LReads = 2) then
          raise EReadError.Create('受控正文读取失败');
        P^ := @LData[0]; N^ := Length(LData); Result := True;
      end;
    LCallback :=
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin Inc(LCalls); if not OK then Inc(LFailures); end;
    if ACase.Contains('stream') then
    begin
      LStream := TPolicyBodyStream.Create;
      LStream.Truncated := not LShort;
      if ACase.StartsWith('gzip') then
        LServerObject.Responses[1].SendZCompress(LStream, ctGZip, LCallback)
      else LServerObject.Responses[1].SendNoCompress(LStream, LCallback);
    end
    else if ACase.StartsWith('gzip') then
      LServerObject.Responses[1].SendZCompress(LSource, ctGZip, LCallback)
    else LServerObject.Responses[1].SendNoCompress(LSource, LCallback);
    LServerObject.Responses[2].SendNoCompress('forbidden-next', LCallback);
    Check((LCalls = 0) and (LObject.Sent = ''), '失败项越过前序响应或提前通知');
    LServerObject.Responses[0].SendNoCompress('blocker');
    LObject.CompleteWrites;
    Check(LObject.DisconnectRequests = Ord(not LShort), '正文失败或合法短读的关闭决定错误');
    if not LShort then LObject.Cleanup;
    Check((LCalls = 2) and (LFailures = 2 * Ord(not LShort)), '发送及取消结果或次数不正确');
    Check((LServerObject.Ends = 3) and (LServerObject.FailedEnds = LFailures), '请求终结结果与发送结果不一致');
    Check((Pos('forbidden-next', LObject.Sent) > 0) = LShort, '后续响应与前序完整性不一致');
    if ACase = 'plain-stream-short' then
      Check(Pos(#13#10#13#10'abcHTTP/1.1', LObject.Sent) > 0, '合法短读未填满声明正文');
    Check(LConnection.Pending = 0, '失败后挂起计数未归零');
  finally
    LObject.Cleanup;
    LObject.CompleteWrites;
    LServerObject.Responses.Clear;
    LSource := nil; LCallback := nil;
    LConnection := nil; LServer := nil;
    LStream.Free;
  end;
end;
