program HttpFailureTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, Math, Generics.Collections, Utils.SyncObjs, Net.CrossHttpUtils,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossHttpParser,
  Net.CrossHttpServer;

type
  TParserProbe = class
  public
    Headers: TStringList;
    Failures, Successes: Integer;
    AbortOnSuccess, RaiseOnFailure: Boolean;
    Parser: TCrossHttpParser;
    RejectAt: string;
    procedure Header(const AData: Pointer; const ASize: Integer);
    procedure BodyData(const AData: Pointer; const ASize: Integer);
    procedure BodyEnd;
    procedure Reject;
    function Values(const AName: string; out AValues: TArray<string>): Boolean;
    procedure Failed(const ACode: Integer; const AError: string);
    procedure Succeeded;
  end;

  TMemoryConnection = class(TCrossHttpConnection)
  private
    FCallbacks: TQueue<TCrossConnectionCallback>;
    FCleaned: Boolean;
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    Sent: AnsiString;
    DelayWrites: Boolean;
    CloseRequests, DisconnectRequests: Integer;
    constructor Create(const AServer: TCrossHttpServer); reintroduce;
    destructor Destroy; override;
    procedure Feed(const AData: AnsiString);
    procedure CompleteWrites;
    procedure Close; override;
    procedure Disconnect; override;
    procedure Cleanup;
  end;

  TTestServer = class(TCrossHttpServer)
  protected
    procedure DoOnRequest(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse); override;
  public
    Requests: TStringList;
    HoldFirst, BodyPolicy: Boolean;
    Held: ICrossHttpResponse;
    constructor Create; reintroduce;
    destructor Destroy; override;
  end;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if AValue then Exit;
  Writeln('FAIL ', AMessage);
  Flush(Output);
  Halt(1);
end;

function GoodRequest(const APath: AnsiString): AnsiString;
begin
  Result := 'GET ' + APath + ' HTTP/1.1'#13#10'Host: localhost'#13#10#13#10;
end;

function BadRequest(const AKind: string): AnsiString;
const
  PREFIX = 'POST /bad HTTP/1.1'#13#10'Host: localhost'#13#10;
begin
  if AKind = 'length' then
    Result := PREFIX + 'Content-Length: abc'#13#10#13#10
  else if AKind = 'conflict' then
    Result := PREFIX + 'Content-Length: 0'#13#10'Transfer-Encoding: chunked'#13#10#13#10
  else if AKind = 'chunk' then
    Result := PREFIX + 'Transfer-Encoding: chunked'#13#10#13#10'xyz'#13#10
  else if AKind = 'crlf' then
    Result := 'GET /bad HTTP/1.1'#13#10'Host: localhost'#10#13#10
  else if AKind = 'header' then
    Result := PREFIX + 'X-Test: a'#0'b'#13#10#13#10
  else if AKind = 'limit' then
    Result := PREFIX + 'Content-Type: application/octet-stream'#13#10 +
      'Content-Length: 8'#13#10#13#10'abcdefgh'
  else
    raise Exception.Create('Unknown invalid request');
end;

procedure TParserProbe.Header(const AData: Pointer; const ASize: Integer);
var
  LText: AnsiString;
  LNested: AnsiString;
  LBuffer: Pointer;
  LLength: Integer;
begin
  SetString(LText, PAnsiChar(AData), ASize);
  Headers.Text := string(LText);
  if RejectAt = 'header' then Reject;
  if RejectAt = 'reentry' then
  begin
    // 外层 Header 完成回调尚未返回，内层 Decode 因 bare-LF 失败。
    LNested := #10;
    LBuffer := PAnsiChar(LNested);
    LLength := Length(LNested);
    Parser.Decode(LBuffer, LLength);
  end;
end;

procedure TParserProbe.BodyData(const AData: Pointer; const ASize: Integer);
begin
  if RejectAt = 'bodydata' then Reject;
end;

procedure TParserProbe.BodyEnd;
begin
  if RejectAt = 'bodyend' then Reject;
end;

procedure TParserProbe.Reject;
begin
  try
    Parser.Fail(400, 'test callback rejected input');
  except
    on E: EAbort do ; // 回调可以吞异常，但不能撤销 Parser 已进入的失败状态。
  end;
end;

function TParserProbe.Values(const AName: string;
  out AValues: TArray<string>): Boolean;
var
  LLine: string;
  P, N: Integer;
begin
  AValues := nil;
  for LLine in Headers do
  begin
    P := Pos(':', LLine);
    if (P > 0) and SameText(Copy(LLine, 1, P - 1), AName) then
    begin
      N := Length(AValues);
      SetLength(AValues, N + 1);
      AValues[N] := Trim(Copy(LLine, P + 1, MaxInt));
    end;
  end;
  Result := Length(AValues) > 0;
end;

procedure TParserProbe.Failed(const ACode: Integer; const AError: string);
begin
  Inc(Failures);
  Check(ACode = 400, 'unexpected parser failure code');
  if RaiseOnFailure then raise Exception.Create('test failure callback exception');
end;

procedure TParserProbe.Succeeded;
begin
  Inc(Successes);
  if AbortOnSuccess then Abort;
end;

procedure TestParser(const AKind: string);
var
  LProbe: TParserProbe;
  LParser: ICrossHttpParser;
  LData: AnsiString;
  LBuffer: Pointer;
  LLength: Integer;
begin
  LProbe := TParserProbe.Create;
  LProbe.Headers := TStringList.Create;
  LProbe.AbortOnSuccess := AKind = 'abort';
  LProbe.RaiseOnFailure := AKind = 'callback';
  LParser := TCrossHttpParser.Create(pmServer);
  LParser.OnHeaderData := LProbe.Header;
  LParser.OnGetHeaderValue := LProbe.Values;
  LParser.OnParseFailed := LProbe.Failed;
  LParser.OnParseSuccess := LProbe.Succeeded;
  if LProbe.AbortOnSuccess then
    LData := GoodRequest('/first')
  else if LProbe.RaiseOnFailure then
    LData := BadRequest('length')
  else
    LData := BadRequest(AKind);
  LBuffer := PAnsiChar(LData);
  LLength := Length(LData);
  LParser.Decode(LBuffer, LLength);
  if not LProbe.AbortOnSuccess then
    Check((LProbe.Failures = 1) and (LProbe.Successes = 0), 'initial failure was not exclusive');
  LData := GoodRequest('/tail');
  LBuffer := PAnsiChar(LData);
  LLength := Length(LData);
  LParser.Decode(LBuffer, LLength);
  LParser.Finish;
  if LProbe.AbortOnSuccess then
    Check((LProbe.Successes = 2) and (LProbe.Failures = 0),
      'successful callback Abort incorrectly poisoned parser')
  else
  begin
    Check(LProbe.Successes = 0, 'failed parser later emitted success');
    Check(LProbe.Failures = 1, 'failure callback repeated');
  end;
  Check(LLength = 0, 'failed parser retained trailing input');
  LParser := nil;
  LProbe.Headers.Free;
  LProbe.Free;
end;

procedure TestCallbackFailure(const AStage: string);
var
  LProbe: TParserProbe;
  LParser: ICrossHttpParser;
  LData: AnsiString;
  LBuffer: Pointer;
  LLength: Integer;
begin
  LProbe := TParserProbe.Create;
  LProbe.Headers := TStringList.Create;
  LProbe.RejectAt := AStage;
  if AStage = 'bodyend' then
    LParser := TCrossHttpParser.Create(pmClient)
  else
    LParser := TCrossHttpParser.Create(pmServer);
  LProbe.Parser := LParser as TCrossHttpParser;
  LParser.OnHeaderData := LProbe.Header;
  LParser.OnGetHeaderValue := LProbe.Values;
  LParser.OnBodyData := LProbe.BodyData;
  LParser.OnBodyEnd := LProbe.BodyEnd;
  LParser.OnParseFailed := LProbe.Failed;
  LParser.OnParseSuccess := LProbe.Succeeded;
  if AStage = 'bodyend' then
    LData := 'HTTP/1.1 200 OK'#13#10'Connection: close'#13#10#13#10'x'
  else
    LData := 'POST /first HTTP/1.1'#13#10'Host: localhost'#13#10 +
      'Content-Length: 1'#13#10#13#10'x';
  LBuffer := PAnsiChar(LData);
  LLength := Length(LData);
  LParser.Decode(LBuffer, LLength);
  LParser.Finish;
  Check(LProbe.Failures = 1, 'callback rejection did not fail exactly once');
  Check(LProbe.Successes = 0, 'callback return overwrote failed parser state');
  LData := GoodRequest('/tail');
  LBuffer := PAnsiChar(LData);
  LLength := Length(LData);
  LParser.Decode(LBuffer, LLength);
  LParser.Finish;
  Check((LProbe.Failures = 1) and (LProbe.Successes = 0) and (LLength = 0),
    'callback rejection did not remain terminal');
  LParser := nil;
  LProbe.Headers.Free;
  LProbe.Free;
end;

constructor TMemoryConnection.Create(const AServer: TCrossHttpServer);
begin
  inherited Create(AServer, INVALID_SOCKET, ctAccept, '', nil);
  FCallbacks := TQueue<TCrossConnectionCallback>.Create;
  DelayWrites := True;
  ConnectStatus := csConnected;
end;

destructor TMemoryConnection.Destroy;
begin
  FCallbacks.Free;
  inherited;
end;

procedure TMemoryConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LPart: AnsiString;
begin
  SetString(LPart, PAnsiChar(ABuffer), ACount);
  Sent := Sent + LPart;
  // 仅替换网络写入；调用者显式完成，保持真实响应队列的异步边界。
  if Assigned(ACallback) then
  begin
    if DelayWrites then
      FCallbacks.Enqueue(ACallback)
    else
      ACallback(Self, True);
  end;
end;

procedure TMemoryConnection.Feed(const AData: AnsiString);
var
  LBuffer: Pointer;
  LLength, LBefore: Integer;
begin
  LBuffer := PAnsiChar(AData);
  LLength := Length(AData);
  _LockRecv;
  try
    while LLength > 0 do
    begin
      LBefore := LLength;
      ParseRecvData(LBuffer, LLength);
      Check(LLength < LBefore, 'parser made no progress after failure; requests=' +
        IntToStr((Owner as TTestServer).Requests.Count));
    end;
  finally
    _UnlockRecv;
  end;
end;

procedure TMemoryConnection.CompleteWrites;
var
  LCallback: TCrossConnectionCallback;
  N: Integer;
begin
  N := 0;
  while FCallbacks.Count > 0 do
  begin
    Inc(N);
    Check(N < 100, 'response callbacks did not settle');
    LCallback := FCallbacks.Dequeue();
    LCallback(Self, True);
  end;
end;

procedure TMemoryConnection.Close;
begin
  Inc(CloseRequests);
  inherited;
end;

procedure TMemoryConnection.Disconnect;
begin
  Inc(DisconnectRequests);
  inherited;
end;

procedure TMemoryConnection.Cleanup;
begin
  if FCleaned then Exit;
  FCleaned := True;
  // INVALID_SOCKET 的公开 Close 不进入 InternalClose，这里只负责组件测试清理。
  ConnectStatus := csClosed;
  InternalClose;
end;

constructor TTestServer.Create;
begin
  inherited Create(2, False);
  Requests := TStringList.Create;
end;

destructor TTestServer.Destroy;
begin
  Held := nil;
  Requests.Free;
  inherited;
end;

procedure TTestServer.DoOnRequest(const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse);
var
  LBody: TBytes;
  I, LCount, LTotal: Integer;
begin
  Requests.Add(ARequest.Path);
  if ARequest.Path = '/storage-tcp' then
  begin
    Check((ARequest.RawBody <> nil) and not (ARequest.RawBody is TMemoryStream),
      'TCP正文未切换到文件流');
    Check((ARequest.RawBody.Size = 65536) and (ARequest.RawBody.Position = 0),
      'TCP正文尺寸或初始位置错误');
    SetLength(LBody, 4096);
    LTotal := 0;
    repeat
      LCount := ARequest.RawBody.Read(LBody[0], Length(LBody));
      for I := 0 to LCount - 1 do Check(LBody[I] = Ord('x'), 'TCP正文内容错误');
      Inc(LTotal, LCount);
    until LCount = 0;
    Check(LTotal = 65536, 'TCP正文未完整读取');
    AResponse.SendNoCompress('stored');
  end
  else if ARequest.Path.StartsWith('/policy-') then
  begin
    if ARequest.Path = '/policy-404' then AResponse.StatusCode := 404;
    if ARequest.Path = '/policy-500' then AResponse.StatusCode := 500;
    if ARequest.Path = '/policy-close' then AResponse.Header['Connection'] := 'keep-alive, close';
    AResponse.SendNoCompress('policy',
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        Check(OK, '完整错误响应被报告为发送失败');
        Writeln('POLICY_SEND_OK');
        Flush(Output);
      end);
  end
  else if ARequest.Path = '/trailer' then
  begin
    Check(ARequest.Header['Authorization'] = 'original', 'trailer 改写了认证头');
    Check(ARequest.Header['Cookie'] = 'original=1', 'trailer 改写了 Cookie');
    Check(ARequest.Header['Transfer-Encoding'] = 'chunked', 'trailer 改写了定界头');
    Check(not ARequest.Header.ExistsParam('Content-Length'), 'trailer 注入了长度头');
    Check(not ARequest.Header.ExistsParam('X-Trailer'), 'trailer 被合并到原始头');
    Check((ARequest.RawBody <> nil) and (ARequest.RawBody.Size = 3), 'trailer 正文尺寸错误');
    SetLength(LBody, 3);
    ARequest.RawBody.Position := 0;
    ARequest.RawBody.ReadBuffer(LBody[0], 3);
    Check(TEncoding.ASCII.GetString(LBody) = 'abc', 'trailer 正文内容错误');
    AResponse.SendNoCompress(LBody);
  end
  else if BodyPolicy and (ARequest.Path = '/204') then
    AResponse.SendStatus(204)
  else if BodyPolicy and (ARequest.Path = '/304') then
    AResponse.SendStatus(304)
  else if BodyPolicy and (ARequest.Path = '/205') then
    AResponse.SendStatus(205)
  else if BodyPolicy and (ARequest.Path = '/head-gzip') then
    AResponse.SendZCompress('abc', ctGZip)
  else if HoldFirst and (ARequest.Path = '/first') then
    Held := AResponse
  else
    AResponse.Send(ARequest.Path);
end;

procedure TestMemory(const AMode: string);
var
  LServerObject: TTestServer;
  LServer: ICrossHttpServer;
  LConnection: ICrossHttpConnection;
  LObject: TMemoryConnection;
  LExpected: Integer;
  LFirst, LError: Integer;
  LKind, LStatus: string;
begin
  LServerObject := TTestServer.Create;
  LServer := LServerObject;
  LObject := TMemoryConnection.Create(LServerObject);
  LObject.DelayWrites := AMode <> 'sync';
  LConnection := LObject;
  LExpected := 0;
  LKind := 'length';
  LStatus := '400';
  if AMode = 'header' then LKind := 'header';
  if AMode = 'limit' then
  begin
    LKind := 'limit';
    LStatus := '413';
    // Parser 已保存构造时的上限；调低 Server 的值以覆盖其二次校验。
    LServerObject.MaxPostDataSize := 4;
  end;
  if AMode = 'queued' then
  begin
    LServerObject.HoldFirst := True;
    LObject.Feed(GoodRequest('/first'));
    LExpected := 1;
  end;
  if AMode = 'same' then
    LObject.Feed(BadRequest('length') + GoodRequest('/tail'))
  else
  begin
    LObject.Feed(BadRequest(LKind));
    if LObject.DelayWrites then
      Check(LObject.CloseRequests + LObject.DisconnectRequests = 0,
        'closed before queued error response completed');
    LObject.Feed(GoodRequest('/tail'));
  end;
  Check(LServerObject.Requests.Count = LExpected, 'failed request or tail reached business');
  if AMode = 'queued' then
  begin
    Check(LObject.Sent = '', 'error response overtook earlier response');
    Check(LServerObject.Held <> nil, 'earlier response missing');
    LServerObject.Held.Send('/first');
    LServerObject.Held := nil;
  end;
  LObject.CompleteWrites;
  LError := Pos(AnsiString('HTTP/1.1 ' + LStatus + ' '), LObject.Sent);
  Check(LError > 0, 'error response missing');
  Check(LObject.CloseRequests + LObject.DisconnectRequests > 0,
    'error response completed without requesting disconnect');
  if AMode = 'queued' then
  begin
    LFirst := Pos(AnsiString('HTTP/1.1 200 '), LObject.Sent);
    Check((LFirst > 0) and (LFirst < LError), 'response status order changed');
    Check(Pos(AnsiString('/first'), LObject.Sent) < LError, 'first body not completed before error');
  end;
  Check(Pos(AnsiString('/tail'), LObject.Sent) = 0, 'tail response emitted');
  LObject.Cleanup;
  LConnection := nil;
  LServer := nil;
end;

procedure Serve;
var
  LServer: TTestServer;
  LServerRef: ICrossHttpServer;
  LPort: Word;
  LLine: string;
  LDirectory: string;
  LId: TGUID;
begin
  LServer := TTestServer.Create;
  LServerRef := LServer;
  LPort := 0;
  LServer.Addr := '127.0.0.1';
  LServer.BodyPolicy := ParamStr(2) = 'body';
  if ParamStr(2) = 'capacity' then
  begin
    LServer.HoldFirst := True;
    {$IFDEF HTTP_QUEUE_LIMIT}
    LServer.MaxPendingRequests := 2;
    {$ENDIF}
  end;
  LDirectory := '';
  if ParamStr(2) = 'storage' then
  begin
    CreateGUID(LId);
    LDirectory := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'tcpbody-' + GUIDToString(LId);
    ForceDirectories(LDirectory);
    {$IFDEF HTTP_BODY_STORAGE}
    LServer.BodyMemoryThreshold := 1024;
    {$ENDIF}
    {$IFDEF HTTP_BODY_TEMP_PATH}
    LServer.BodyTempPath := LDirectory;
    {$ENDIF}
  end;
  LServer.Port := 0;
  LServer.Start(
    procedure(const AListen: ICrossListen; const ASuccess: Boolean)
    begin
      Check(ASuccess, 'listen failed');
      LPort := AListen.LocalPort;
    end);
  Check(LPort <> 0, 'listen callback missing');
  Writeln('READY ', LPort);
  Flush(Output);
  Readln(LLine);
  LServer.Stop;
  Writeln('TOTAL ', LServer.Requests.Count);
  Flush(Output);
  LServerRef := nil;
  if LDirectory <> '' then
  begin
    Check(RemoveDir(LDirectory), 'TCP断开后临时正文未清理');
    Writeln('STORAGE_CLEAN');
    Flush(Output);
  end;
end;

{$I HttpResponseQueueTests.inc}
{$I HttpBodyPolicyTests.inc}
{$I HttpSendPolicyTests.inc}
{$I HttpBodyStorageTests.inc}
{$I HttpBodyFlushTests.inc}
{$I HttpQueueLimitTests.inc}

begin
  try
    if ParamStr(1) = 'server' then Serve else
    begin
      if ParamStr(1) = 'parser' then
        TestParser(ParamStr(2))
      else if ParamStr(1) = 'reject' then
        TestCallbackFailure(ParamStr(2))
      else if ParamStr(1) = 'memory' then
        TestMemory(ParamStr(2))
      else if ParamStr(1) = 'queue' then
        TestResponseQueue(ParamStr(2))
      else if ParamStr(1) = 'body' then
        TestBodyPolicy(ParamStr(2))
      else if ParamStr(1) = 'policy' then
        TestSendPolicy(ParamStr(2))
      else if ParamStr(1) = 'source' then
        TestSendSourceFailure(ParamStr(2))
      else if ParamStr(1) = 'storage' then
        TestBodyStorage(ParamStr(2))
      else if ParamStr(1) = 'flush' then
        TestBodyFlush(ParamStr(2))
      else if ParamStr(1) = 'capacity' then
        TestQueueLimit(ParamStr(2))
      else
        Check(False, 'unknown mode');
      Writeln('PASS ', ParamStr(1), ' ', ParamStr(2));
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Flush(Output);
      Halt(1);
    end;
  end;
end.
