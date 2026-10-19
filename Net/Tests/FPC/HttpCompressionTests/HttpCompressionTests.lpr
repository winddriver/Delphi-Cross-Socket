program HttpCompressionTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, Math,
  {$IFDEF DELPHI}ZLib,{$ELSE}DTF.StaticZLib,{$ENDIF}
  Net.CrossHttpUtils, Net.CrossHttpParser;

type
  TProbe = class
  public
    Parser: TCrossHttpParser;
    Headers: TStringList;
    Data: AnsiString;
    RejectAt: string;
    RaiseFailure, AbortSuccess: Boolean;
    Begins, Ends, Successes, Failures: Integer;
    RejectAfterBytes: Integer;
    constructor Create(const AMode: TCrossHttpParseMode);
    destructor Destroy; override;
    procedure Header(const P: Pointer; const N: Integer);
    function Values(const AName: string; out AValues: TArray<string>): Boolean;
    procedure BodyBegin;
    procedure BodyData(const P: Pointer; const N: Integer);
    procedure BodyEnd;
    procedure Succeeded;
    procedure Failed(const ACode: Integer; const AError: string);
    procedure Reject(const AWhere: string);
    procedure Feed(const AData: AnsiString; const ASplit: Boolean = False);
  end;

var
  Allocations, Releases, LiveAllocations, PeakAllocations, FailAllocation: Integer;
  LiveBytes, PeakBytes: NativeUInt;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

{$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
function CountAlloc(AOpaque: Pointer; AItems, ASize: Cardinal): Pointer; cdecl;
var
  LSize: NativeUInt;
begin
  Result := nil;
  Inc(Allocations);
  if Allocations = FailAllocation then Exit;
  LSize := NativeUInt(AItems) * ASize;
  try
    GetMem(Result, LSize + SizeOf(NativeUInt));
    PNativeUInt(Result)^ := LSize;
    Result := Pointer(PByte(Result) + SizeOf(NativeUInt));
    FillChar(Result^, LSize, 0);
    Inc(LiveAllocations);
    Inc(LiveBytes, LSize);
    PeakAllocations := Max(PeakAllocations, LiveAllocations);
    if LiveBytes > PeakBytes then PeakBytes := LiveBytes;
  except
    Result := nil;
  end;
end;

procedure CountFree(AOpaque, AAddress: Pointer); cdecl;
var
  P: Pointer;
begin
  if AAddress = nil then Exit;
  P := Pointer(PByte(AAddress) - SizeOf(NativeUInt));
  Dec(LiveBytes, PNativeUInt(P)^);
  Dec(LiveAllocations);
  Inc(Releases);
  FreeMem(P);
end;

procedure ConfigureInflate(var AStream: TZStreamRec);
begin
  AStream.zalloc := CountAlloc;
  AStream.zfree := CountFree;
end;
{$ENDIF}

constructor TProbe.Create(const AMode: TCrossHttpParseMode);
begin
  Headers := TStringList.Create;
  Parser := TCrossHttpParser.Create(AMode);
  Parser.MaxCompressRatio := 0;
  Parser.OnHeaderData := Header;
  Parser.OnGetHeaderValue := Values;
  Parser.OnBodyBegin := BodyBegin;
  Parser.OnBodyData := BodyData;
  Parser.OnBodyEnd := BodyEnd;
  Parser.OnParseSuccess := Succeeded;
  Parser.OnParseFailed := Failed;
end;

destructor TProbe.Destroy;
begin
  try
    FreeAndNil(Parser);
  finally
    Headers.Free;
    inherited;
  end;
end;

procedure TProbe.Header(const P: Pointer; const N: Integer);
var
  LText: AnsiString;
begin
  SetString(LText, PAnsiChar(P), N);
  Headers.Text := string(LText);
end;

function TProbe.Values(const AName: string; out AValues: TArray<string>): Boolean;
var
  LLine: string;
  I, N: Integer;
begin
  AValues := nil;
  for LLine in Headers do
  begin
    I := Pos(':', LLine);
    if (I > 0) and SameText(Copy(LLine, 1, I - 1), AName) then
    begin
      N := Length(AValues);
      SetLength(AValues, N + 1);
      AValues[N] := Trim(Copy(LLine, I + 1, MaxInt));
    end;
  end;
  Result := Length(AValues) > 0;
end;

procedure TProbe.Reject(const AWhere: string);
begin
  if RejectAt = AWhere then
  begin
    // 回调捕获 EAbort 后，失败终态仍然不能被外层覆盖。
    try Parser.Fail(400, 'test rejected ' + AWhere); except on E: EAbort do ; end;
  end;
  if RejectAt = AWhere + '-raise' then raise Exception.Create('test callback exception');
end;

procedure TProbe.BodyBegin;
begin
  Inc(Begins);
  Reject('begin');
end;

procedure TProbe.BodyData(const P: Pointer; const N: Integer);
var
  LText: AnsiString;
begin
  SetString(LText, PAnsiChar(P), N);
  Data := Data + LText;
  if (RejectAfterBytes = 0) or (Length(Data) > RejectAfterBytes) then Reject('data');
end;

procedure TProbe.BodyEnd;
begin
  Inc(Ends);
  Reject('end');
end;

procedure TProbe.Succeeded;
begin
  Inc(Successes);
  if AbortSuccess then Abort;
end;

procedure TProbe.Failed(const ACode: Integer; const AError: string);
begin
  Inc(Failures);
  Writeln('PARSER failure=', ACode, ' ', AError);
  {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
  Check(LiveAllocations = 0, '失败通知发生在原生状态释放之前');
  {$ENDIF}
  if RaiseFailure then raise Exception.Create('test failure callback exception');
end;

procedure TProbe.Feed(const AData: AnsiString; const ASplit: Boolean);
var
  P: Pointer;
  N, I: Integer;
begin
  if ASplit then
  begin
    for I := 1 to Length(AData) do
    begin
      P := @AData[I]; N := 1;
      Parser.Decode(P, N);
    end;
  end else
  begin
    P := PAnsiChar(AData); N := Length(AData);
    while N > 0 do Parser.Decode(P, N);
  end;
end;

function Compressed(const AData: AnsiString; const AGzip: Boolean): AnsiString;
var
  LStream: TZStreamRec;
  LBits, LResult: Integer;
begin
  FillChar(LStream, SizeOf(LStream), 0);
  LBits := 15;
  if AGzip then Inc(LBits, 16);
  Check(deflateInit2(LStream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, LBits, 8,
    Z_DEFAULT_STRATEGY) = Z_OK, '测试数据压缩初始化失败');
  try
    SetLength(Result, Length(AData) * 2 + 1024);
    LStream.next_in := Pointer(PAnsiChar(AData));
    LStream.avail_in := Length(AData);
    LStream.next_out := Pointer(PAnsiChar(Result));
    LStream.avail_out := Length(Result);
    LResult := deflate(LStream, Z_FINISH);
    Check(LResult = Z_STREAM_END, '测试数据压缩未完成');
    SetLength(Result, Length(Result) - LStream.avail_out);
  finally
    deflateEnd(LStream);
  end;
end;

function HeaderText(const AClient: Boolean; const AFraming, AEncoding: string;
  const ASize: Integer): AnsiString;
begin
  if AClient then Result := 'HTTP/1.1 200 OK'#13#10
  else Result := 'POST /data HTTP/1.1'#13#10'Host: localhost'#13#10;
  Result := Result + 'Content-Encoding: ' + AnsiString(AEncoding) + #13#10;
  if AFraming = 'length' then
    Result := Result + 'Content-Length: ' + AnsiString(IntToStr(ASize)) + #13#10
  else if AFraming = 'chunk' then Result := Result + 'Transfer-Encoding: chunked'#13#10
  else Result := Result + 'Connection: close'#13#10;
  Result := Result + #13#10;
end;

procedure RunCase(const ACase: string);
var
  LParts: TArray<string>;
  LProbe: TProbe;
  LClient, LGzip, LFail, LDestroy, LDisconnected: Boolean;
  LFraming, LAction: string;
  LPlain, LZipped, LBody, LHeader, LChunkHeader, LChunkEnd: AnsiString;
  LSize, I: Integer;
  LMode: TCrossHttpParseMode;
begin
  LParts := ACase.Split(['-']);
  Check(Length(LParts) >= 4, '测试参数错误');
  LClient := LParts[0] = 'client';
  LFraming := LParts[1];
  LGzip := LParts[2] = 'gzip';
  LAction := LParts[3];
  LPlain := UTF8Encode('解析器 UTF-8 内容 ') + AnsiString(StringOfChar('x', 2048));
  if LAction = 'large' then
  begin
    SetLength(LPlain, 200000);
    for I := 1 to Length(LPlain) do LPlain[I] := AnsiChar((I * 47 + I div 251) mod 256);
  end;
  if LAction = 'empty' then LPlain := '';
  LZipped := Compressed(LPlain, LGzip);
  LSize := Length(LZipped);
  LFail := (LAction = 'truncated') or (LAction = 'disconnect') or (LAction = 'corrupt')
    or (LAction = 'failraise') or (LAction = 'finishraise') or (LAction = 'destroyraise')
    or (LAction = 'initfail') or (LAction = 'windowfail') or (LAction = 'limit')
    or (LAction = 'ratio') or (LAction = 'headerfinish')
    or (Pos('reject', LAction) = 1) or (Pos('throw', LAction) = 1);
  LDestroy := (LAction = 'destroy') or (LAction = 'destroyraise') or (LAction = 'headerdestroy');
  LDisconnected := (LAction = 'disconnect') or LDestroy;
  if (LAction = 'truncated') or LDisconnected or (LAction = 'finishraise') then
    SetLength(LZipped, Max(1, LSize - 8));
  if (LAction = 'corrupt') or (LAction = 'failraise') then
    LZipped[Length(LZipped)] := AnsiChar(Ord(LZipped[Length(LZipped)]) xor $80);
  if not LDisconnected then LSize := Length(LZipped);
  LHeader := HeaderText(LClient, LFraming, LParts[2], LSize);
  if LFraming = 'chunk' then
  begin
    // 二进制压缩数据不能经过 FPC 的 Unicode 字符串拼接转换。
    LChunkHeader := AnsiString(IntToHex(LSize, 1) + #13#10);
    LChunkEnd := '';
    if not LDisconnected then LChunkEnd := #13#10'0'#13#10#13#10;
    SetLength(LBody, Length(LChunkHeader) + Length(LZipped) + Length(LChunkEnd));
    Move(LChunkHeader[1], LBody[1], Length(LChunkHeader));
    Move(LZipped[1], LBody[Length(LChunkHeader) + 1], Length(LZipped));
    if LChunkEnd <> '' then
      Move(LChunkEnd[1], LBody[Length(LChunkHeader) + Length(LZipped) + 1], Length(LChunkEnd));
  end else LBody := LZipped;
  LMode := pmServer;
  if LClient then LMode := pmClient;
  LProbe := TProbe.Create(LMode);
  try
    if Pos('reject', LAction) = 1 then LProbe.RejectAt := Copy(LAction, 7, MaxInt);
    if Pos('throw', LAction) = 1 then LProbe.RejectAt := Copy(LAction, 6, MaxInt) + '-raise';
    LProbe.RaiseFailure := (LAction = 'failraise') or (LAction = 'finishraise') or (LAction = 'destroyraise');
    LProbe.AbortSuccess := LAction = 'successabort';
    if LAction = 'initfail' then FailAllocation := 1;
    if LAction = 'windowfail' then FailAllocation := 2;
    if LAction = 'limit' then LProbe.Parser.MaxBodyDataSize := 512;
    if LAction = 'ratio' then LProbe.Parser.MaxCompressRatio := 1;
    try
      LProbe.Feed(LHeader);
    except
      on E: Exception do
        if (Pos('throw', LAction) <> 1) and not LProbe.RaiseFailure then raise;
    end;
    {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
    if (LAction <> 'initfail') and (LAction <> 'rejectbegin') and (LAction <> 'throwbegin') then
      Check(LiveAllocations > 0, '红绿探针未进入真实 inflate 活跃状态');
    {$ENDIF}
    try
      if (LAction <> 'headerdestroy') and (LAction <> 'headerfinish') then
        LProbe.Feed(LBody, (LAction = 'split') or (LAction = 'windowfail'));
    except
      on E: Exception do
        if (Pos('throw', LAction) <> 1) and not LProbe.RaiseFailure then raise;
    end;
    if LDestroy then
    begin
      try FreeAndNil(LProbe.Parser); except on E: Exception do if not LProbe.RaiseFailure then raise; end;
      Check(LProbe.Successes = 0, '析构误发布了截断请求');
    end else
    begin
      try LProbe.Parser.Finish; except on E: Exception do if not LProbe.RaiseFailure then raise; end;
      LProbe.Parser.Finish;
      if LFail then
      begin
        Check((LProbe.Failures = 1) and (LProbe.Successes = 0), '截断/失败被接受或通知次数不正确');
        LProbe.Feed('GET /after HTTP/1.1'#13#10#13#10);
        Check((LProbe.Failures = 1) and (LProbe.Successes = 0), '失败后又发布业务');
      end else
      begin
        Check((LProbe.Failures = 0) and (LProbe.Successes = 1) and (LProbe.Ends = 1), '完整压缩消息未成功一次');
        Check(LProbe.Data = LPlain, '解压正文不一致');
        if LAction = 'reuse' then
        begin
          LProbe.Data := '';
          LProbe.Feed(LHeader);
          LProbe.Feed(LBody, True);
          LProbe.Parser.Finish;
          Check((LProbe.Successes = 2) and (LProbe.Failures = 0) and (LProbe.Ends = 2), '复用解析器通知次数错误');
          Check(LProbe.Data = LPlain, '复用解析器后正文错误');
        end;
      end;
    end;
  finally
    LProbe.Free;
  end;
  {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
  Writeln('NATIVE allocations=', Allocations, ' releases=', Releases,
    ' live=', LiveAllocations, ' bytes=', LiveBytes, ' peak=', PeakBytes);
  Check((LiveAllocations = 0) and (LiveBytes = 0), '原生解压分配没有回到基线');
  {$ENDIF}
end;

{$I HttpCompressionMemberTests.inc}

var
  I: Integer;
begin
  try
    {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}SetHttpInflateInitHook(ConfigureInflate);{$ENDIF}
    if ParamStr(1) = 'repeated' then
    begin
      for I := 1 to 50 do
      begin
        RunCase('server-length-gzip-normal');
        RunCase('client-chunk-deflate-disconnect');
        RunCase('server-length-gzip-destroy');
      end;
    end else
    if Pos('members-', ParamStr(1)) = 1 then RunMemberCase(ParamStr(1))
    else RunCase(ParamStr(1));
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL ', ParamStr(1), ': ', E.ClassName, ': ', E.Message);
      Writeln('NATIVE allocations=', Allocations, ' releases=', Releases,
        ' live=', LiveAllocations, ' bytes=', LiveBytes, ' peak=', PeakBytes);
      Halt(1);
    end;
  end;
end.
