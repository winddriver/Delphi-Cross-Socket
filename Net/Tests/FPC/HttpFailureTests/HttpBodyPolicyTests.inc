type
  TBodyReadStream = class(TStream)
  private
    FPosition: Int64;
  protected
    function GetSize: Int64; override;
  public
    Reads: Integer;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

function TBodyReadStream.GetSize: Int64;
begin
  Result := 3;
end;

function TBodyReadStream.Read(var Buffer; Count: Longint): Longint;
const
  DATA: AnsiString = 'abc';
begin
  Inc(Reads);
  Result := Min(Count, 3 - FPosition);
  if Result > 0 then Move(DATA[1 + FPosition], Buffer, Result);
  Inc(FPosition, Result);
end;

function TBodyReadStream.Write(const Buffer; Count: Longint): Longint;
begin
  raise Exception.Create('测试流只读');
end;

function TBodyReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent: Inc(FPosition, Offset);
    soEnd: FPosition := 3 + Offset;
  end;
  Result := FPosition;
end;

procedure TestBodyPolicy(const ACase: string);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TMemoryConnection;
  LConnection: ICrossHttpConnection;
  LResponse: ICrossHttpResponse;
  LStream: TBodyReadStream;
  LCallback: TCrossConnectionCallback;
  LSource: TCrossHttpChunkDataFunc;
  LKind, LMethod, LStatus: string;
  LData: TBytes;
  LHeader, LRest, LRequest: AnsiString;
  LCode, LSplit, LCalls, LSourceCalls: Integer;
  LNoBody, LFollowup, LOldLength: Boolean;
begin
  LSplit := Pos('-', ACase);
  LStatus := Copy(ACase, 1, LSplit - 1);
  LKind := Copy(ACase, LSplit + 1, MaxInt);
  LOldLength := LKind.EndsWith('-length');
  if LOldLength then SetLength(LKind, Length(LKind) - Length('-length'));
  LMethod := 'GET';
  LCode := StrToIntDef(LStatus, 200);
  if LStatus = 'head' then LMethod := 'HEAD';
  if (LStatus = 'head204') or (LStatus = 'head304') then
  begin
    LMethod := 'HEAD';
    LCode := StrToInt(Copy(LStatus, 5, 3));
  end;
  if LStatus = 'connect' then LMethod := 'CONNECT';
  LNoBody := LStatus <> '200';
  LFollowup := (LCode >= 200) and (LMethod <> 'CONNECT');
  LServerObject := TQueueServer.Create;
  LServerObject.Compressible := LKind = 'auto';
  LServer := LServerObject;
  LObject := TMemoryConnection.Create(LServerObject);
  LConnection := LObject;
  LStream := TBodyReadStream.Create;
  LCalls := 0;
  LSourceCalls := 0;
  try
    LRequest := AnsiString(LMethod) + ' /body HTTP/1.1'#13#10 +
      'Host: localhost'#13#10'Accept-Encoding: gzip'#13#10#13#10;
    if LFollowup then LRequest := LRequest + GoodRequest('/next');
    LObject.Feed(LRequest);
    Check(LServerObject.Responses.Count = 1 + Ord(LFollowup), '请求注册数错误');
    LResponse := LServerObject.Responses[0];
    LResponse.StatusCode := LCode;
    LResponse.ContentType := 'text/plain';
    if LOldLength then LResponse.Header['Content-Length'] := '4096';
    // 无正文时必须清除调用方遗留的非法定界，HEAD/304 元数据另行检查。
    if (LMethod <> 'HEAD') and (LCode <> 304) and LNoBody then
    begin
      LResponse.Header.Add('Content-Length', '999', True);
      LResponse.Header.Add('content-length', '1000', True);
      LResponse.Header.Add('Transfer-Encoding', 'chunked', True);
    end;
    if LKind = 'metadata' then LResponse.Header['Content-Length'] := '17';
    if LKind = 'metadata-bad' then LResponse.Header['Content-Length'] := '+17';
    if LKind = 'metadata-conflict' then
    begin
      LResponse.Header.Add('Content-Length', '17', True);
      LResponse.Header.Add('content-length', '18', True);
    end;
    LData := TEncoding.ASCII.GetBytes('abc');
    LCallback :=
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        Check(OK, '无正文发送被错误报告为失败');
        Inc(LCalls);
      end;
    LSource :=
      function(const P: PPointer; const N: PNativeInt): Boolean
      begin
        Inc(LSourceCalls);
        Result := LSourceCalls = 1;
        if Result then begin P^ := @LData[0]; N^ := Length(LData); end
        else begin P^ := nil; N^ := 0; end;
      end;
    if LKind = 'preencoded' then
    begin
      // 业务已经提供编码后的表示，不应再次编码或丢失已知长度。
      LResponse.Header['Content-Encoding'] := 'gzip';
      LData := TBytes.Create($1F,$8B,$08,$00,$00,$00,$00,$00,$02,$03,
        $4B,$4C,$4A,$06,$00,$C2,$41,$24,$35,$03,$00,$00,$00);
      LResponse.Send(LData, LCallback);
    end
    else if LKind = 'status' then LResponse.SendStatus(LCode, LCallback)
    else if LKind = 'bytes' then LResponse.SendNoCompress(LData, LCallback)
    else if LKind = 'chunk' then LResponse.SendNoCompress(LSource, LCallback)
    else if LKind = 'stream' then LResponse.SendNoCompress(LStream, LCallback)
    else if LKind = 'gzip' then LResponse.SendZCompress(LSource, ctGZip, LCallback)
    else if LKind = 'gzip-stream' then LResponse.SendZCompress(LStream, ctGZip, LCallback)
    else if LKind = 'identity-stream' then LResponse.SendZCompress(LStream, ctNone, LCallback)
    else if LKind = 'auto' then LResponse.Send(StringOfChar('x', 4096), LCallback)
    else if Pos('metadata', LKind) = 1 then LResponse.SendNoCompress(LSource, LCallback)
    else Check(False, '未知正文场景');
    LObject.CompleteWrites;
    Check(LCalls = 1, '发送完成次数错误');
    LSplit := Pos(#13#10#13#10, LObject.Sent);
    Check(LSplit > 0, '响应头缺失');
    LHeader := Copy(LObject.Sent, 1, LSplit + 3);
    LRest := Copy(LObject.Sent, LSplit + 4, MaxInt);
    if LNoBody then
    begin
      Check(LRest = '', '禁止正文的响应仍输出了字节');
      Check(LSourceCalls = 0, '禁止正文时预取了 provider');
      Check(LStream.Reads = 0, '禁止正文时读取了外部流');
      if LMethod <> 'HEAD' then
        Check(Pos('Transfer-Encoding:', string(LHeader)) = 0, '无正文响应残留分块定界');
      if (LCode < 200) or (LCode = 204) or (LMethod = 'CONNECT') then
        Check(not LResponse.Header.ExistsParam('Content-Length'), '禁止长度头的响应残留长度')
      else if LCode = 205 then
        Check(LResponse.Header['Content-Length'] = '0', '205 必须具有零长度定界')
      else if (LKind = 'metadata') then
        Check(LResponse.Header['Content-Length'] = '17', '304 表示长度被误删')
      else if LKind = 'preencoded' then
        Check(LResponse.Header['Content-Length'] = IntToStr(Length(LData)), '预编码表示长度被误删')
      else if (LMethod = 'HEAD') and (LCode <> 304)
        and ((LKind = 'bytes') or (LKind = 'stream') or (LKind = 'identity-stream')) then
        Check(LResponse.Header['Content-Length'] = '3', 'HEAD 丢失已知表示长度')
      else if (LCode = 304) or (LKind = 'chunk') or (LKind = 'gzip')
        or (LKind = 'gzip-stream') or (LKind = 'auto') then
        Check(not LResponse.Header.ExistsParam('Content-Length'), '未知表示长度被伪造');
      if (LMethod = 'HEAD') and ((LKind = 'gzip') or (LKind = 'gzip-stream') or (LKind = 'auto')) then
        Check(LResponse.Header['Content-Encoding'] = 'gzip', 'HEAD 丢失编码元数据');
    end else
      Check(LRest <> '', '普通响应丢失正文');
    if LFollowup then
    begin
      LObject.Sent := '';
      LServerObject.Responses[1].SendNoCompress('next', LCallback);
      LObject.CompleteWrites;
      Check(Pos('HTTP/1.1 200 ', string(LObject.Sent)) = 1, '后续响应起始位置错误');
      LSplit := Pos(#13#10#13#10, LObject.Sent);
      Check(Copy(LObject.Sent, LSplit + 4, MaxInt) = 'next', '后续响应混入残留字节');
      Check((LCalls = 2) and (LObject.DisconnectRequests = 0), '复用或完成次数错误');
    end;
  finally
    LObject.Cleanup;
    LObject.CompleteWrites;
    LServerObject.Responses.Clear;
    LResponse := nil;
    LCallback := nil;
    LSource := nil;
    LConnection := nil;
    LServer := nil;
    LStream.Free;
  end;
end;
