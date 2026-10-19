program HttpChunkTests;

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
    Begins, Ends, Successes, Failures, HeaderCalls: Integer;
    FirstHeaders: string;
    RawHeader, FirstRawHeader: AnsiString;
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
  RawHeader := LText;
  Inc(HeaderCalls);
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
  if Successes = 1 then FirstHeaders := Headers.Text;
  if Successes = 1 then FirstRawHeader := RawHeader;
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

function JoinBytes(const AFirst, ASecond: AnsiString): AnsiString;
begin
  SetLength(Result, Length(AFirst) + Length(ASecond));
  if AFirst <> '' then Move(AFirst[1], Result[1], Length(AFirst));
  if ASecond <> '' then Move(ASecond[1], Result[Length(AFirst) + 1], Length(ASecond));
end;

procedure RunChunkCase(const ACase: string);
var
  LProbe: TProbe;
  LMode: TCrossHttpParseMode;
  LKind, LError: string;
  LClient, LFail, LFinishOnly: Boolean;
  LHeader, LBody, LTrailer, LNext, LPlain, LZipped, LWire: AnsiString;
  LCut, I, LBefore, LSuccessExpected: Integer;
begin
  I := Pos('-', ACase);
  LClient := Copy(ACase, 1, I - 1) = 'client';
  LKind := Copy(ACase, I + 1, MaxInt);
  LFail := Pos('bad-', LKind) = 1;
  LFinishOnly := Pos('bad-eof-', LKind) = 1;
  if LKind = 'bad-gzip-eof-trailer' then LFinishOnly := True;
  LMode := pmServer;
  if LClient then LMode := pmClient;
  if LClient then LHeader := 'HTTP/1.1 200 OK'#13#10
  else LHeader := 'POST /first HTTP/1.1'#13#10'Host: localhost'#13#10;
  LHeader := LHeader + 'Transfer-Encoding: chunked'#13#10 +
    'Authorization: keep-original'#13#10'Cookie: original=1'#13#10;
  LPlain := 'abc';
  LBody := '3'#13#10'abc'#13#10'0'#13#10;
  LTrailer := #13#10;
  if LKind = 'trailer' then LTrailer := 'X-Checksum: abcd'#13#10'X-Empty:'#13#10#13#10;
  if LKind = 'trailer-ows' then LTrailer := 'X-Info:'#9' spaced '#9#13#10#13#10;
  if LKind = 'trailer-obstext' then
  begin
    LTrailer := 'X-Info: ab'#13#10#13#10;
    LTrailer[9] := AnsiChar($80);
    LTrailer[10] := AnsiChar($ff);
  end;
  if LKind = 'protected-fields' then
    LTrailer := 'Content-Length: 999'#13#10'Transfer-Encoding: identity'#13#10 +
      'Authorization: replaced'#13#10'Cookie: replaced=1'#13#10 +
      'Content-Encoding: gzip'#13#10'Connection: close'#13#10#13#10;
  if LKind = 'zero-extension' then LBody := '3'#13#10'abc'#13#10'000;end=yes'#13#10;
  if LKind = 'chunk-extension' then LBody := '1;foo="a;b"'#13#10'a'#13#10'2;bar=baz'#13#10'bc'#13#10'0'#13#10;
  if LKind = 'multiple' then LBody := '1'#13#10'a'#13#10'1'#13#10'b'#13#10'1'#13#10'c'#13#10'0'#13#10;
  if (LKind = 'limit-bytes') or (LKind = 'bad-limit-bytes') or (LKind = 'reuse-bytes') then
  begin
    I := 8185;
    if LFail then Inc(I);
    LTrailer := AnsiString('X: ' + StringOfChar('a', I) + #13#10#13#10);
  end;
  if (LKind = 'limit-fields') or (LKind = 'bad-limit-fields') or (LKind = 'reuse-fields') then
  begin
    LTrailer := '';
    for I := 1 to 100 + Ord(LFail) do
      LTrailer := LTrailer + AnsiString('X-' + IntToStr(I) + ': a'#13#10);
    LTrailer := LTrailer + #13#10;
  end;
  if LKind = 'bad-size-lfcr' then LBody := '3'#10#13'abc'#13#10'0'#13#10;
  if LKind = 'bad-size-lf' then LBody := '3'#10'abc'#13#10'0'#13#10;
  if LKind = 'bad-size-cr-text' then LBody := '3'#13';x=y'#13#10'abc'#13#10'0'#13#10;
  if LKind = 'bad-size-double-cr' then LBody := '3'#13#13#10'abc'#13#10'0'#13#10;
  if LKind = 'bad-size-control' then LBody := #11'3'#13#10'abc'#13#10'0'#13#10;
  if LKind = 'bad-extension-control' then LBody := '3;foo='#11#13#10'abc'#13#10'0'#13#10;
  if LKind = 'bad-data-lfcr' then LBody := '3'#13#10'abc'#10#13'0'#13#10;
  if LKind = 'bad-data-lf' then LBody := '3'#13#10'abc'#10'0'#13#10;
  if LKind = 'bad-data-double-cr' then LBody := '3'#13#10'abc'#13#13#10'0'#13#10;
  if LKind = 'bad-data-cr-text' then LBody := '3'#13#10'abc'#13'X'#10'0'#13#10;
  if LKind = 'bad-zero-lfcr' then LBody := '3'#13#10'abc'#13#10'0'#10#13;
  if LKind = 'bad-final-lfcr' then LTrailer := #10#13;
  if LKind = 'bad-trailer-lf' then LTrailer := 'X: a'#10#13#10;
  if LKind = 'bad-trailer-cr' then LTrailer := 'X: a'#13'b'#13#10#13#10;
  if LKind = 'bad-trailer-fold' then LTrailer := 'X: a'#13#10' folded'#13#10#13#10;
  if LKind = 'bad-trailer-name' then LTrailer := 'X@: a'#13#10#13#10;
  if LKind = 'bad-trailer-space' then LTrailer := 'X : a'#13#10#13#10;
  if LKind = 'bad-trailer-empty-name' then LTrailer := ': a'#13#10#13#10;
  if LKind = 'bad-trailer-no-colon' then LTrailer := 'X a'#13#10#13#10;
  if LKind = 'bad-trailer-nul' then LTrailer := 'X: a'#0#13#10#13#10;
  if LKind = 'bad-trailer-vtab' then LTrailer := 'X: '#11'a'#13#10#13#10;
  if LKind = 'bad-trailer-del' then LTrailer := 'X: a'#127#13#10#13#10;
  if LKind = 'bad-eof-size' then LBody := '3'#13;
  if LKind = 'bad-eof-data' then LBody := '3'#13#10'ab';
  if LKind = 'bad-eof-data-cr' then LBody := '3'#13#10'abc'#13;
  if LKind = 'bad-eof-trailer' then LBody := '3'#13#10'abc'#13#10'0'#13#10'X: a'#13;
  if LKind = 'bad-eof-empty' then LBody := '3'#13#10'abc'#13#10'0'#13#10;
  if LKind = 'bad-eof-final-cr' then LBody := '3'#13#10'abc'#13#10'0'#13#10#13;
  if LFinishOnly then LTrailer := '';
  if (LKind = 'gzip-trailer') or (LKind = 'bad-gzip-truncated')
    or (LKind = 'bad-gzip-trailer') or (LKind = 'gzip-members-trailer')
    or (LKind = 'bad-gzip-eof-trailer') then
  begin
    LHeader := LHeader + 'Content-Encoding: gzip'#13#10;
    LZipped := Compressed(LPlain, True);
    if LKind = 'gzip-members-trailer' then
    begin
      LZipped := JoinBytes(LZipped, Compressed('def', True));
      LPlain := 'abcdef';
    end;
    if LKind = 'bad-gzip-truncated' then SetLength(LZipped, Length(LZipped) - 8);
    LBody := JoinBytes(AnsiString(IntToHex(Length(LZipped), 1) + #13#10), LZipped);
    LBody := JoinBytes(LBody, AnsiString(#13#10'0'#13#10));
    LTrailer := 'X-Checksum: done'#13#10#13#10;
    if LKind = 'bad-gzip-trailer' then LTrailer := 'X: '#0#13#10#13#10;
    if LKind = 'bad-gzip-eof-trailer' then LTrailer := 'X: incomplete'#13;
  end;
  LHeader := LHeader + #13#10;
  if LClient then LNext := 'HTTP/1.1 200 OK'#13#10
  else LNext := 'POST /next HTTP/1.1'#13#10'Host: localhost'#13#10;
  if (LKind = 'reuse-bytes') or (LKind = 'reuse-fields') then
  begin
    LNext := LNext + 'Transfer-Encoding: chunked'#13#10#13#10'4'#13#10'NEXT'#13#10'0'#13#10;
    if LKind = 'reuse-fields' then LNext := JoinBytes(LNext, LTrailer)
    else LNext := LNext + 'X: next'#13#10#13#10;
  end else LNext := LNext + 'Content-Length: 4'#13#10#13#10'NEXT';
  LWire := JoinBytes(JoinBytes(LHeader, LBody), LTrailer);
  if not LFinishOnly then LWire := JoinBytes(LWire, LNext);
  for LCut := -1 to Length(LWire) do
  begin
    LProbe := TProbe.Create(LMode);
    try
      LBefore := LiveAllocations;
      if LKind = 'bad-callback-end' then LProbe.RejectAt := 'end';
      if LKind = 'bad-callback-data' then LProbe.RejectAt := 'data';
      LProbe.RaiseFailure := LKind = 'bad-failure-callback';
      if LProbe.RaiseFailure then LProbe.RejectAt := 'end';
      if LCut < 0 then LProbe.Feed(LWire, True)
      else
      begin
        LProbe.Feed(Copy(LWire, 1, LCut));
        LProbe.Feed(Copy(LWire, LCut + 1, MaxInt));
      end;
      LProbe.Parser.Finish;
      LProbe.Parser.Finish;
      LError := '，拆分=' + IntToStr(LCut);
      if LFail then
      begin
        Check((LProbe.Failures = 1) and (LProbe.Successes = 0), '非法或截断chunk被成功发布' + LError);
        LProbe.Feed(LNext);
        Check((LProbe.Failures = 1) and (LProbe.Successes = 0), 'chunk失败终态被后续请求覆盖' + LError);
      end else
      begin
        LSuccessExpected := 2;
        Check((LProbe.Failures = 0) and (LProbe.Successes = LSuccessExpected)
          and (LProbe.Ends = 2), '合法chunk或后续请求未完成一次' + LError);
        Check((LProbe.Data = JoinBytes(LPlain, 'NEXT')) and (LProbe.HeaderCalls = 2), '正文或头部回调混入trailer' + LError);
        Check(LProbe.FirstRawHeader = LHeader, 'trailer改写原始头部字节');
        Check(Pos('Authorization: keep-original', LProbe.FirstHeaders) > 0, 'trailer改写Authorization');
        Check(Pos('Cookie: original=1', LProbe.FirstHeaders) > 0, 'trailer改写Cookie');
        Check(Pos('Transfer-Encoding: chunked', LProbe.FirstHeaders) > 0, 'trailer改写Transfer-Encoding');
        Check(Pos('Content-Length:', LProbe.FirstHeaders) = 0, 'trailer注入Content-Length');
        Check(Pos('replaced', LProbe.FirstHeaders) = 0, 'trailer污染原始头部');
      end;
      {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
      Check(LiveAllocations = LBefore, 'chunk终态未释放原生解压状态');
      {$ENDIF}
    finally
      LProbe.Free;
    end;
    {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
    Check((LiveAllocations = 0) and (LiveBytes = 0), 'chunk解析器析构遗留原生资源');
    {$ENDIF}
  end;
  Writeln('SPLITS ', Length(LWire) + 2, ' allocations=', Allocations, ' releases=', Releases);
end;

begin
  try
    {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}SetHttpInflateInitHook(ConfigureInflate);{$ENDIF}
    RunChunkCase(ParamStr(1));
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL ', ParamStr(1), ': ', E.ClassName, ': ', E.Message);
      Writeln('NATIVE live=', LiveAllocations, ' bytes=', LiveBytes);
      Halt(1);
    end;
  end;
end.
