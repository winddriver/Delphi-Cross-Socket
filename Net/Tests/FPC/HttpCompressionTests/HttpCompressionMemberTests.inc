function JoinBytes(const AFirst, ASecond: AnsiString): AnsiString;
begin
  SetLength(Result, Length(AFirst) + Length(ASecond));
  if AFirst <> '' then Move(AFirst[1], Result[1], Length(AFirst));
  if ASecond <> '' then Move(ASecond[1], Result[Length(AFirst) + 1], Length(ASecond));
end;

function ChunkBytes(const AData: AnsiString): AnsiString;
begin
  Result := JoinBytes(JoinBytes(AnsiString(IntToHex(Length(AData), 1) + #13#10), AData), AnsiString(#13#10));
end;

procedure RunMemberCase(const ACase: string);
var
  LParts: TArray<string>;
  LProbe: TProbe;
  LMode: TCrossHttpParseMode;
  LKind, LFraming, LEncoding: string;
  LFirst, LSecond, LExpected, LCompressed, LBody, LHeader, LBad: AnsiString;
  LClient, LFail, LGzip: Boolean;
  LCut, I, LDecodedLimit, LRatioLimit, LAllocBefore: Integer;
begin
  LParts := ACase.Split(['-']);
  Check(Length(LParts) = 4, '串联测试参数错误');
  LClient := LParts[1] = 'client';
  LFraming := LParts[2];
  LKind := LParts[3];
  LGzip := Pos('deflate', LKind) <> 1;
  LEncoding := 'gzip';
  if not LGzip then LEncoding := 'deflate';
  LFirst := UTF8Encode('第一个成员 ') + AnsiString(StringOfChar('x', 2048));
  LSecond := UTF8Encode('第二个成员完整内容 ') + AnsiString(StringOfChar('y', 4096));
  LDecodedLimit := 0;
  LRatioLimit := 0;
  LFail := (LKind = 'truncated') or (LKind = 'corrupt') or (LKind = 'junk')
    or (LKind = 'prefix') or (LKind = 'deflatedouble') or (LKind = 'deflatejunk')
    or (LKind = 'limit') or (LKind = 'ratio') or (LKind = 'rejectsecond') or (LKind = 'failraise');
  if LKind = 'emptyfirst' then LFirst := '';
  if LKind = 'large' then LSecond := AnsiString(StringOfChar('y', 100000));
  if LKind = 'limit' then
  begin
    LFirst := AnsiString(StringOfChar('x', 400));
    LSecond := AnsiString(StringOfChar('y', 400));
    LDecodedLimit := 600;
  end;
  if LKind = 'ratio' then
  begin
    // 单个成员低于检查阈值，累计超过阈值，防止 Reset 清零压缩比统计。
    LFirst := AnsiString(StringOfChar('x', 800));
    LSecond := AnsiString(StringOfChar('y', 800));
    LRatioLimit := 3;
  end;
  LExpected := JoinBytes(LFirst, LSecond);
  LCompressed := Compressed(LFirst, LGzip);
  if LKind = 'emptymiddle' then LCompressed := JoinBytes(LCompressed, Compressed('', True));
  LBad := Compressed(LSecond, LGzip);
  if LKind = 'deflatejunk' then LBad := 'junk';
  if LKind = 'truncated' then SetLength(LBad, Length(LBad) - 8);
  if (LKind = 'corrupt') or (LKind = 'failraise') then
    LBad[Length(LBad)] := AnsiChar(Ord(LBad[Length(LBad)]) xor $80);
  LCompressed := JoinBytes(LCompressed, LBad);
  if LKind = 'junk' then LCompressed := JoinBytes(LCompressed, 'junk');
  if LKind = 'prefix' then LCompressed := JoinBytes(LCompressed, AnsiString(#$1f));
  if LKind = 'many' then
    for I := 1 to 20 do
    begin
      LCompressed := JoinBytes(LCompressed, Compressed(LSecond, True));
      LExpected := JoinBytes(LExpected, LSecond);
    end;
  LHeader := HeaderText(LClient, LFraming, LEncoding, Length(LCompressed));
  LBody := LCompressed;
  if LFraming = 'chunk' then
  begin
    LBody := JoinBytes(JoinBytes(AnsiString(IntToHex(Length(LCompressed), 1) + #13#10), LCompressed),
      AnsiString(#13#10'0'#13#10#13#10));
    if LKind = 'chunkmembers' then
      LBody := JoinBytes(JoinBytes(ChunkBytes(Compressed(LFirst, True)), ChunkBytes(Compressed(LSecond, True))),
        AnsiString('0'#13#10#13#10));
    if LKind = 'tinychunks' then
    begin
      LBody := '';
      for I := 1 to Length(LCompressed) do
        LBody := JoinBytes(LBody, ChunkBytes(Copy(LCompressed, I, 1)));
      LBody := JoinBytes(LBody, AnsiString('0'#13#10#13#10));
    end;
  end;
  LMode := pmServer;
  if LClient then LMode := pmClient;

  // -1 为逐字节输入；其余逐一遍历整个 HTTP 正文的全部两包拆分位置。
  for LCut := -1 to Length(LBody) do
  begin
    LAllocBefore := Allocations;
    LProbe := TProbe.Create(LMode);
    try
      LProbe.Parser.MaxBodyDataSize := LDecodedLimit;
      LProbe.Parser.MaxCompressRatio := LRatioLimit;
      if LKind = 'rejectsecond' then
      begin
        LProbe.RejectAt := 'data';
        LProbe.RejectAfterBytes := Length(LFirst);
      end;
      LProbe.RaiseFailure := LKind = 'failraise';
      LProbe.Feed(LHeader);
      if LCut < 0 then LProbe.Feed(LBody, True)
      else
      begin
        LProbe.Feed(Copy(LBody, 1, LCut));
        LProbe.Feed(Copy(LBody, LCut + 1, MaxInt));
      end;
      LProbe.Parser.Finish;
      LProbe.Parser.Finish;
      if LFail then
      begin
        Check((LProbe.Failures = 1) and (LProbe.Successes = 0) and (LProbe.Ends = 0),
          '后续成员损坏、超限或拒绝没有终结解析，拆分=' + IntToStr(LCut));
        LProbe.Feed('GET /after HTTP/1.1'#13#10#13#10);
        Check((LProbe.Failures = 1) and (LProbe.Successes = 0), '串联失败后又发布业务');
      end else
      begin
        Check((LProbe.Failures = 0) and (LProbe.Successes = 1) and (LProbe.Ends = 1),
          '合法串联成员未成功一次，拆分=' + IntToStr(LCut));
        Check(LProbe.Data = LExpected, '串联成员正文丢失，拆分=' + IntToStr(LCut));
        if LKind = 'reuse' then
        begin
          LProbe.Data := '';
          LProbe.Feed(LHeader);
          LProbe.Feed(LBody, True);
          LProbe.Parser.Finish;
          Check((LProbe.Successes = 2) and (LProbe.Ends = 2) and (LProbe.Failures = 0), '串联消息复用次数错误');
          Check(LProbe.Data = LExpected, '串联消息复用后正文错误');
        end;
      end;
    finally
      LProbe.Free;
    end;
    {$IFDEF CROSS_HTTP_COMPRESSION_TESTS}
    Check((LiveAllocations = 0) and (LiveBytes = 0), '串联解析遗留原生状态');
    if LKind = 'reuse' then
      Check(Allocations - LAllocBefore <= 4, '两条消息重复分配解压状态或窗口')
    else Check(Allocations - LAllocBefore <= 2, '成员切换重复分配解压状态或窗口');
    {$ENDIF}
  end;
  Writeln('SPLITS ', Length(LBody) + 2, ' allocations=', Allocations,
    ' releases=', Releases, ' live=', LiveAllocations, ' bytes=', LiveBytes);
end;
