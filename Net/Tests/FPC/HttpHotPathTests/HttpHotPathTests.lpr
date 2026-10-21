program HttpHotPathTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes, Windows, Net.CrossHttpParams, Net.CrossHttpServer,
  Net.CrossHttpUtils, Net.CrossSocket.Base, Net.SocketAPI, Utils.StrUtils;

type
  {$IFDEF FPC}
  TBenchManager = TMemoryManager;
  TBenchSize = PtrUInt;
  {$ELSE}
  TBenchManager = TMemoryManagerEx;
  TBenchSize = NativeInt;
  {$ENDIF}

var
  Checks: Integer;
  OriginalManager, CountingManager: TBenchManager;
  AllocationCalls, AllocationBytes: Int64;
threadvar
  Tracking: Boolean;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then raise Exception.Create(AMessage);
end;

function CountGetMem(ASize: TBenchSize): Pointer;
begin
  if Tracking then begin Inc(AllocationCalls); Inc(AllocationBytes, ASize); end;
  Result := OriginalManager.GetMem(ASize);
end;

function CountAllocMem(ASize: TBenchSize): Pointer;
begin
  if Tracking then begin Inc(AllocationCalls); Inc(AllocationBytes, ASize); end;
  Result := OriginalManager.AllocMem(ASize);
end;

function CountReallocMem({$IFDEF FPC}var{$ENDIF} P: Pointer; ASize: TBenchSize): Pointer;
begin
  if Tracking and (ASize > 0) then begin Inc(AllocationCalls); Inc(AllocationBytes, ASize); end;
  Result := OriginalManager.ReallocMem(P, ASize);
end;

procedure BeginCounting;
begin
  GetMemoryManager(OriginalManager);
  CountingManager := OriginalManager;
  CountingManager.GetMem := CountGetMem;
  CountingManager.AllocMem := CountAllocMem;
  CountingManager.ReallocMem := CountReallocMem;
  AllocationCalls := 0;
  AllocationBytes := 0;
  SetMemoryManager(CountingManager);
  Tracking := True;
end;

procedure EndCounting;
begin
  Tracking := False;
  SetMemoryManager(OriginalManager);
end;

{$I HttpTestSupport.inc}
{$I RouterTests.inc}

// 独立保留修改前算法，供语义差分验证，不参与性能计时。
function ReferenceToken(const AValue: string): Boolean;
var I: Integer;
begin
  if AValue = '' then Exit(False);
  for I := 1 to Length(AValue) do
    case AValue[I] of
      'A'..'Z', 'a'..'z', '0'..'9', '!', '#', '$', '%', '&', '''', '*', '+', '-', '.', '^', '_', '`', '|', '~': ;
    else Exit(False);
    end;
  Result := True;
end;

function ReferenceContains(const AHeader: THttpHeader; const AName, AToken: string): Boolean;
var LHeader: TNameValue; LToken, LValue: string;
begin
  if not ReferenceToken(AToken) then Exit(False);
  for LHeader in AHeader do
    if TStrUtils.SameText(LHeader.Name, AName) then
      for LToken in LHeader.Value.Split([',']) do
      begin
        LValue := LToken.Trim;
        if ReferenceToken(LValue) and TStrUtils.SameText(LValue, AToken) then Exit(True);
      end;
  Result := False;
end;

procedure TestTokens;
var
  LHeader: THttpHeader;
  I, J: Integer;
  LValue: string;
  procedure Same(const AToken: string);
  begin
    Check(LHeader.ContainsToken('Connection', AToken) =
      ReferenceContains(LHeader, 'Connection', AToken), 'token 差分失败: ' + AToken);
  end;
begin
  LHeader := THttpHeader.Create;
  try
    Check(not LHeader.ContainsToken('Connection', 'close'), '缺失字段');
    LHeader.Add('Connection', ' keep-alive, CLOSE ');
    LHeader.Add('cOnNeCtIoN', 'upgrade', True);
    Check(LHeader.ContainsToken('CONNECTION', 'close'), '大小写和空白');
    Check(LHeader.ContainsToken('Connection', 'upgrade'), '重复字段');
    Check(not LHeader.ContainsToken('Connection', 'keep'), '不能匹配 token 前缀');
    for I := 0 to 255 do
    begin
      LHeader['Connection'] := Char(I) + 'close' + Char(I);
      Same('close'); Same('upgrade'); Same(''); Same('cl ose');
      LHeader['Connection'] := 'cl' + Char(I) + 'ose, keep-alive';
      Same('close'); Same('keep-alive');
    end;
    LHeader['Connection'] := #$212A'eep-alive, close'#$00A0;
    Same('keep-alive'); Same('close'); Same(#$212A'eep-alive');
    RandSeed := 20261021;
    for I := 1 to 4000 do
    begin
      LValue := '';
      for J := 1 to Random(60) do LValue := LValue + Char(Random(300));
      case I mod 4 of
        0: LValue := LValue + ', close';
        1: LValue := ' keep-alive ,' + LValue;
        2: LValue := LValue + ',UPGRADE,';
      end;
      LHeader['Connection'] := LValue;
      Same('close'); Same('keep-alive'); Same('upgrade');
    end;
  finally LHeader.Free; end;
end;

procedure TestHeaderValues;
var
  LHeader: THttpHeader;
  LValues, LSaved: TArray<string>;
  I: Integer;
begin
  LHeader := THttpHeader.Create;
  try
    SetLength(LValues, 1);
    LValues[0] := 'previous';
    Check(not LHeader.GetHeaderValues('Cookie', LValues), '空头返回值');
    Check(Length(LValues) = 0, '空头未清理输出');
    LHeader.Add('Host', 'localhost');
    LHeader.Add('Cookie', 'first');
    LHeader.Add('X-Other', 'ignore');
    LHeader.Add('COOKIE', '', True);
    LHeader.Add('cookie', 'last', True);
    Check(LHeader.GetHeaderValues('cOoKiE', LValues), '大小写查询');
    Check((Length(LValues) = 3) and (LValues[0] = 'first') and
      (LValues[1] = '') and (LValues[2] = 'last'), '重复字段顺序或空值');
    LSaved := LValues;
    Check(not LHeader.GetHeaderValues('Missing', LValues), '无匹配返回值');
    Check(Length(LValues) = 0, '无匹配未清理已有输出');
    Check((Length(LSaved) = 3) and (LSaved[0] = 'first'), '影响外部持有的旧数组');
    for I := 1 to 1000 do
    begin
      Check(LHeader.GetHeaderValues('HOST', LValues), '单字段重复查询');
      Check((Length(LValues) = 1) and (LValues[0] = 'localhost'), '单字段内容');
      Check(not LHeader.GetHeaderValues('Absent', LValues), '重复无匹配查询');
      Check(Length(LValues) = 0, '输出数组残留');
    end;
  finally LHeader.Free; end;
  Check((Length(LSaved) = 3) and (LSaved[2] = 'last'), '结果不应依赖原对象寿命');
end;

procedure Benchmark(const AName: string; const ACount: Integer; const AAllocations: Boolean);
var
  LHeader: THttpHeader;
  I, LHits: Integer;
  LStart, LEnd, LFrequency: Int64;
  LValues: TArray<string>;
begin
  if AName = 'router' then
  begin
    BenchmarkRouter(ACount, AAllocations);
    Exit;
  end;
  Check(ACount > 0, '无效循环数');
  LHeader := THttpHeader.Create;
  try
    LHeader.Add('Host', 'localhost');
    LHeader.Add('User-Agent', 'ApacheBench/2.3');
    LHeader.Add('Connection', 'keep-alive');
    LHeader.Add('Accept', '*/*');
    LHeader.Add('X-First', 'a');
    LHeader.Add('X-Last', 'b');
    if (AName = 'present') or (AName = 'duplicates') then LHeader.Add('Cookie', 'first');
    if AName = 'duplicates' then
    begin
      LHeader.Add('COOKIE', '', True);
      LHeader.Add('Cookie', 'last', True);
    end;
    Check(SetThreadAffinityMask(GetCurrentThread, 4) <> 0, '绑定基准 CPU 失败');
    QueryPerformanceFrequency(LFrequency);
    LHits := 0;
    if AAllocations then BeginCounting;
    try
      QueryPerformanceCounter(LStart);
      for I := 1 to ACount do
      begin
        if AName = 'tokens' then
        begin
          if LHeader.ContainsToken('Connection', 'close') then Inc(LHits);
          if LHeader.ContainsToken('Connection', 'keep-alive') then Inc(LHits);
          if LHeader.ContainsToken('Missing', 'close') then Inc(LHits);
        end else
        if AName = 'missing' then
        begin
          if LHeader.GetHeaderValues('Cookie', LValues) then Inc(LHits);
          if LHeader.GetHeaderValues('Content-Length', LValues) then Inc(LHits);
        end else
        if (AName = 'present') or (AName = 'duplicates') then
        begin
          if LHeader.GetHeaderValues('Cookie', LValues) then Inc(LHits);
        end else
          raise Exception.Create('未知基准: ' + AName);
      end;
      QueryPerformanceCounter(LEnd);
    finally
      if AAllocations then EndCounting;
    end;
    if AName = 'missing' then Check((LHits = 0) and (Length(LValues) = 0), '无匹配结果错误')
    else Check(LHits = ACount, '查询命中数错误');
    if AName = 'present' then Check((Length(LValues) = 1) and (LValues[0] = 'first'), '单字段结果错误');
    if AName = 'duplicates' then Check((Length(LValues) = 3) and
      (LValues[1] = '') and (LValues[2] = 'last'), '多字段结果错误');
    Writeln(Format('METRIC n=%d us=%.3f calls=%d bytes=%d',
      [ACount, (LEnd - LStart) * 1000000.0 / LFrequency, AllocationCalls, AllocationBytes]));
  finally LHeader.Free; end;
end;

begin
  try
    FormatSettings.DecimalSeparator := '.';
    if ParamStr(1) = 'bench' then
      Benchmark(ParamStr(2), StrToInt(ParamStr(3)), ParamStr(4) = 'alloc')
    else
    if ParamStr(1) = 'tokens' then TestTokens
    else
    if ParamStr(1) = 'headers' then TestHeaderValues
    else
    if ParamStr(1) = 'router' then TestRouter
    else raise Exception.Create('未知测试');
    Writeln('PASS ', ParamStr(1), ' checks=', Checks);
  except
    on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
