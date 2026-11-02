program HttpHeaderTests;
{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  SysUtils, Classes, SyncObjs, Net.CrossHttpParams, Net.CrossHttpUtils,
  Net.CrossHttpServer, Net.CrossHttpClient, Net.CrossHttpParser, Net.CrossSocket.Base, Net.SocketAPI,
  Utils.Utils, Utils.StrUtils, Utils.RegEx, Utils.IOUtils;
type
  TRequestAccess = class(TCrossHttpRequest);
  TResponseAccess = class(TCrossHttpClientResponse);
var Checks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then raise Exception.Create(AMessage);
end;

function Bytes(const S: string): TBytes;
begin Result := TEncoding.UTF8.GetBytes(S); end;

// 先编码成 UTF-8，再用 AnsiString 作为字节容器供内存连接 Feed；不经默认代码页重编码。
function Wire(const S: string): AnsiString;
var B: TBytes;
begin B := Bytes(S); SetString(Result, PAnsiChar(Pointer(B)), Length(B)); end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := Length(A) = Length(B);
  if Result and (Length(A) > 0) then Result := CompareMem(Pointer(A), Pointer(B), Length(A));
end;

// 无参数模式使用真实 Parser/路由/队列，只有底层发送替换为内存收集；
// server/client 模式则由 Python runner 驱动真实 TCP，二者的验证边界不同。
{$I ../HttpHotPathTests/HttpTestSupport.inc}

procedure TestEntries;
var H, Other: THttpHeader; B: TBytes; E, F: TParamEntry; Base: TBaseParams;
    Failed: Boolean; Values: TArray<string>; N: Integer;
begin
  H := THttpHeader.Create; Other := THttpHeader.Create;
  try
    B := Bytes('中文'); E := TParamEntry.Create('X', Pointer(B), Length(B));
    B[0] := 0;
    Check(E.Value = '中文', '字节构造文本'); Check(E.HasRawValue, '字节来源');
    Check(SameBytes(E.RawValue, Bytes('中文')), '构造器复制指针内容');
    H.Add(E); H.Add('x', 'second', True); H.Add('X', '', True);
    Check(H.GetHeaderValues('x', Values) and (Length(Values) = 3), '重复项');
    Check(Values[2] = '', '空重复项');
    Check(not H.GetHeaderValues('missing', Values) and (Values = nil), '不存在字段');
    Other.Assign(H); H.Assign(H);
    Check((H.Count = 3) and H.Items[0].HasRawValue, '自赋值');
    F := Other.Items[0]; Check(Pointer(F.RawValue) = Pointer(E.RawValue), 'Assign 共享');
    N := 0;
    for F in H do begin if N = 0 then Check(Pointer(F.RawValue) = Pointer(E.RawValue), '枚举共享'); Inc(N); end;
    // 故意构造 Value/raw 不一致的完整记录，验证容器信任四字段，不自动修正来源。
    E.Name := 'Z'; E.Value := '调用方文本'; H.Items[0] := E;
    Check((H.Items[0].Value = E.Value) and H.Items[0].HasRawValue, '完整记录不修正');
    H.Sort; N := 0;
    while (N < H.Count) and (H.Items[N].Name <> 'Z') do Inc(N);
    Check(N < H.Count, '排序保留项');
    Check(SameBytes(H.Items[N].RawValue, E.RawValue), '排序保留 raw');
    H['z'] := 'new'; Check(not H.Items[N].HasRawValue and (H.Items[N].RawValue = nil), '字符串覆盖失效');
    H.Remove('x'); Check(H.Count = 1, '删除所有重复'); H.Remove(0); Check(H.Count = 0, '按索引删除');
    H.Assign(nil); Check(H.Count = 0, '空来源');
    E := TParamEntry.Create('Empty', nil, 0);
    Check(E.HasRawValue and (E.Value = '') and (E.RawValue = nil), '字节来源空值');
    E := TParamEntry.Create('S', ''); Check(not E.HasRawValue, '字符串来源空值');
    Failed := False; try E := TParamEntry.Create('bad', nil, 1); except on EArgumentException do Failed := True; end;
    Check(Failed, '构造 nil 非零');
    Failed := False; try E := TParamEntry.Create('bad', Pointer(B), -1); except on EArgumentException do Failed := True; end;
    Check(Failed, '构造负长度');
    Base := H; Base.Add('X: old');
    Failed := False; try Base.Add('Y: good'#13#10'bad'); except on EConvertError do Failed := True; end;
    Check(Failed and (H.Count = 1), '基类 Add 失败回滚并抛出');
    Failed := False; try Other.Free; Other := nil; Other := THttpHeader.Create('bad'); except on EConvertError do Failed := True; end;
    Check(Failed, '字符串构造失败抛出');
  finally Other.Free; H.Free; end;
end;

procedure TestDecode;
const Bad: array[0..11] of string = ('bad', ': v', 'Bad Name: v', ' X: v',
  'X : v', 'X: a'#10, 'X: a'#13, 'X: a'#13#13#10, 'X: a'#0,
  'X: a'#127, 'X: a'#13#10#13#10'Y: b', 'X: a'#13#10' folded');
var H: THttpHeader; B, Raw: TBytes; S, ExpectedValue, ErrorClass: string;
    I, C, ConversionErrors: Integer; Failed, Expected: Boolean;
    LOldEntry: TParamEntry;
    LOldCount: Integer;
begin
  H := THttpHeader.Create;
  try
    for I := 0 to 2 do
    begin
      S := 'X: '#9'中文'#9' 中 '#9;
      if I > 0 then S := S + #13#10;
      if I > 1 then S := S + #13#10;
      B := Bytes(S); Check(H.Decode(Pointer(B), Length(B)), '字节结束形式');
      Check(H.Items[0].Value = '中文'#9' 中', '只去首尾 OWS');
      Check(SameBytes(H.Items[0].RawValue, Bytes('中文'#9' 中')), 'raw 去 OWS');
      Check(H.Decode(S) and not H.Items[0].HasRawValue, '字符串来源');
    end;
    Check(H.Decode('X: "  中文  "') and (H['X'] = '"  中文  "'), '引号内空白');
    Check(H.Decode('X: '#$3000'中'#$3000) and (H['X'] = #$3000'中'#$3000), 'Unicode 空白保留');
    for I := Low(Bad) to High(Bad) do
    begin
      B := Bytes('Keep: old'); Check(H.Decode(Pointer(B), Length(B)), '准备旧项'); Raw := H.Items[0].RawValue;
      B := Bytes('Good: yes'#13#10 + Bad[I]);
      Check(not H.Decode(Pointer(B), Length(B), False), '字节非法行整块失败');
      Check((H.Count = 1) and (Pointer(H.Items[0].RawValue) = Pointer(Raw)), '字节追加回滚');
      Check(not H.Decode('Good: yes'#13#10 + Bad[I], False) and (H.Count = 1), '字符串追加回滚');
      Check(not H.Decode(Pointer(B), Length(B)) and (H.Count = 0), '清空模式失败');
    end;
    // 先追加足够多的完整字段覆盖当前扩容路径，再让最后一行失败；旧项不参与回滚。
    B := Bytes('Keep-Original: 中文旧值');
    Check(H.Decode(Pointer(B), Length(B)), '准备扩容回滚旧项');
    LOldEntry := H.Items[0];
    S := '';
    for I := 0 to 31 do
      S := S + 'X-Field-' + IntToStr(I) + ': value' + IntToStr(I) + #13#10;
    B := Bytes(S + 'Broken: value'#13);
    Check(not H.Decode(Pointer(B), Length(B), False), '多字段追加后末行失败');
    Check((H.Count = 1) and (H.Items[0].Name = LOldEntry.Name)
      and (H.Items[0].Value = LOldEntry.Value) and H.Items[0].HasRawValue
      and (LOldEntry.Name = 'Keep-Original') and (LOldEntry.Value = '中文旧值'), '扩容回滚保留旧名称和值');
    Check((Pointer(H.Items[0].RawValue) = Pointer(LOldEntry.RawValue))
      and SameBytes(H.Items[0].RawValue, Bytes('中文旧值')), '扩容回滚保留旧 raw 身份和内容');
    // 删除字节来源项后再追加文本/空值，旧尾项的来源标志不能泄漏到新字段。
    B := Bytes('Removed: 原始字节'#13#10'Removed-Empty:');
    Check(H.Decode(Pointer(B), Length(B), False) and (H.Count = 3)
      and H.Items[1].HasRawValue and H.Items[2].HasRawValue, '准备删除字节来源尾项');
    H.Remove(2); H.Remove(1);
    Check(H.Decode('Text: new'#13#10'Empty:', False) and (H.Count = 3), '删除后追加字符串和空值');
    Check((H.Items[1].Name = 'Text') and (H.Items[1].Value = 'new')
      and not H.Items[1].HasRawValue and (H.Items[1].RawValue = nil)
      and (H.Items[2].Name = 'Empty') and (H.Items[2].Value = '')
      and not H.Items[2].HasRawValue and (H.Items[2].RawValue = nil), '重用集合不继承已删项 raw 来源');
    Check((H.Items[0].Name = LOldEntry.Name) and (H.Items[0].Value = LOldEntry.Value)
      and (Pointer(H.Items[0].RawValue) = Pointer(LOldEntry.RawValue)), '删除和文本追加保留旧项');
    // 先前的大批追加及删除后继续追加，再次失败只回滚本次内容，不改变已有三项。
    LOldCount := H.Count;
    B := Bytes('Later-A: more'#13#10'Later-B: '#$FEFF'字节'#13#10'Broken: value'#13);
    Check(not H.Decode(Pointer(B), Length(B), False), '集合重用后追加失败');
    Check((H.Count = LOldCount) and (H.Items[0].Name = LOldEntry.Name)
      and (H.Items[0].Value = LOldEntry.Value) and H.Items[0].HasRawValue
      and (Pointer(H.Items[0].RawValue) = Pointer(LOldEntry.RawValue))
      and SameBytes(H.Items[0].RawValue, Bytes('中文旧值'))
      and (H.Items[1].Name = 'Text') and (H.Items[1].Value = 'new')
      and not H.Items[1].HasRawValue and (H.Items[1].RawValue = nil)
      and (H.Items[2].Name = 'Empty') and (H.Items[2].Value = '')
      and not H.Items[2].HasRawValue and (H.Items[2].RawValue = nil), '重用后回滚保留计数、raw 身份和文本项');
    // 语法是否合法按字节判断；文本或异常预期则以同一 raw 调用 GetString 的结果为准，
    // 不把平台默认编码差异误当成新解析器应该统一替换/拒绝字节的规则。
    ConversionErrors := 0;
    for C := 0 to 255 do
    begin
      B := Bytes('X: a'); SetLength(B, Length(B) + 1); B[High(B)] := C;
      Expected := (C = 9) or ((C >= 32) and (C <> 127));
      if Expected then
      begin
        if (C = 9) or (C = 32) then Raw := Bytes('a') else begin SetLength(Raw, 2); Raw[0] := 97; Raw[1] := C; end;
        ErrorClass := '';
        try ExpectedValue := TUtils.GetString(Raw);
        except on E: Exception do ErrorClass := E.ClassName; end;
        if ErrorClass <> '' then
        begin
          // GetString 的默认编码回退依赖 RTL/平台；既有转换异常也必须保持。
          Inc(ConversionErrors); Failed := False;
          try H.Decode(Pointer(B), Length(B));
          except on E: Exception do Failed := E.ClassName = ErrorClass; end;
          Check(Failed and (H.Count = 0), '复用 GetString 异常并回滚');
        end
        else begin
          Check(H.Decode(Pointer(B), Length(B)), '逐字节语法 ' + IntToStr(C));
          Check(SameBytes(H.Items[0].RawValue, Raw), '逐字节 raw');
          Check(H.Items[0].Value = ExpectedValue, '复用 GetString 语义');
        end;
      end
      else Check(not H.Decode(Pointer(B), Length(B)), '拒绝控制字节 ' + IntToStr(C));
    end;
    Writeln('GETSTRING_CONVERSION_ERRORS ', ConversionErrors);
    B := [$58, $3A, $20, $EF, $BB, $BF, $E4, $B8, $AD];
    Check(H.Decode(Pointer(B), Length(B)) and (H['X'] = '中'), '值内 UTF8 BOM');
    Check(Length(H.Items[0].RawValue) = 6, 'raw 不剥离 BOM');
    B := Bytes('X: exact'); SetLength(B, Length(B) + 1); B[High(B)] := 0;
    Check(H.Decode(Pointer(B), Length(B) - 1), '按显式长度解析');
    Failed := False; try H.Decode(nil, 1); except on EArgumentException do Failed := True; end;
    Check(Failed and (H['X'] = 'exact'), '参数错误不修改');
    Failed := False; try H.Decode(Pointer(B), -1); except on EArgumentException do Failed := True; end;
    Check(Failed and (H.Count = 1), '负长度不修改');
    Check(H.Decode(nil, 0, False) and (H.Count = 1), '零字节追加');
    Check(H.Decode(Pointer(1), 0) and (H.Count = 0), '零长度不解引用');
    Check(H.Decode('') and H.Decode(#13#10), '空集合有效');
  finally H.Free; end;
end;

procedure TestEncode;
const Bad: array[0..8] of string = (#13, #10, #0, #127, #$D800, #$DC00,
  #$D800#$D800, #$DC00#$D800, #$D800'a');
var H: THttpHeader; I: Integer; Failed: Boolean; S, LErrorMessage: string; B: TBytes;
begin
  H := THttpHeader.Create;
  try
    B := Bytes('X: old'); Check(H.Decode(Pointer(B), Length(B)), '原始项');
    H['X'] := '中文'#$D83D#$DE00#$FFFD;
    S := H.Encode; Check(S = 'X: 中文'#$D83D#$DE00#$FFFD#13#10#13#10, '按当前字符串编码');
    for I := Low(Bad) to High(Bad) do
    begin
      H['X'] := Bad[I]; Failed := False;
      try S := H.Encode; except on EConvertError do Failed := True; end;
      Check(Failed and (H.Count = 1) and (H['X'] = Bad[I]), '非法输出不改容器');
    end;
    H.Clear; H.Add('bad name', 'v'); Failed := False;
    try S := H.Encode; except on EConvertError do Failed := True; end;
    Check(Failed and (H.Count = 1), '非法名称抛出');
    // 字段合法性先于整块 UTF-16 检查：早遇到坏代理也不能遮蔽后续的字段/CTL 错误。
    for I := 0 to 2 do
    begin
      H.Clear; H.Add('X', #$D800);
      case I of
        0: H.Add('bad name', 'v');
        1: H['X'] := #$D800#0;
      end;
      Failed := False; LErrorMessage := '';
      try S := H.Encode;
      except on E: EConvertError do begin Failed := True; LErrorMessage := E.Message; end; end;
      if I = 2 then
        Check(Failed and (LErrorMessage = 'Invalid UTF-16 in HTTP header'), '仅坏代理保留 UTF-16 错误')
      else Check(Failed and (LErrorMessage = 'Invalid HTTP header field'), '多错保留字段错误优先级 ' + IntToStr(I));
    end;
  finally H.Free; end;
end;

// EncodeHeader/CheckUtf16 只负责 UTF-16 完整性与无 BOM UTF-8，NUL 等字段限制由调用方另验。
procedure TestHeaderEncoding;
const
  ValidTails: array[0..7] of string = ('', 'A', #0#9#13#10#127, #$0080,
    '中文', #$FEFF, #$FFFD, #$D83D#$DE00);
  InvalidTails: array[0..6] of string = (#$D800, #$DC00, #$D800#$D800,
    #$DC00#$D800, #$D800'a', #$D800#0, #$D800#$D800#$DC00);
var
  LPrefixLength, I, LSuffix: Integer;
  S, LError: string;
  B, LOther, LExpected: TBytes;
  LFailed: Boolean;
begin
  // 前缀奇偶及长度让非 ASCII/代理对落在不同双码元位置，尾部同时覆盖奇偶长度。
  for LPrefixLength := 0 to 7 do
    for I := Low(ValidTails) to High(ValidTails) do
      for LSuffix := 0 to 1 do
      begin
        S := StringOfChar('a', LPrefixLength) + ValidTails[I];
        if LSuffix <> 0 then S := S + 'z';
        LExpected := TEncoding.UTF8.GetBytes(S);
        TCrossHttpUtils.CheckUtf16(S);
        B := TCrossHttpUtils.EncodeHeader(S);
        Check(SameBytes(B, LExpected) and SameBytes(TEncoding.UTF8.GetBytes(S), LExpected),
          '整头 UTF8 与标准编码一致且输入不变 ' + IntToStr(LPrefixLength) + '/' + IntToStr(I) + '/' + IntToStr(LSuffix));
      end;
  for LPrefixLength := 0 to 7 do
    for I := Low(InvalidTails) to High(InvalidTails) do
    begin
      S := StringOfChar('a', LPrefixLength) + InvalidTails[I];
      LFailed := False; LError := '';
      try TCrossHttpUtils.CheckUtf16(S);
      except on E: EConvertError do begin LFailed := True; LError := E.Message; end; end;
      Check(LFailed and (LError = 'Invalid UTF-16 in HTTP header'),
        '公开 UTF16 检查拒绝坏代理 ' + IntToStr(LPrefixLength) + '/' + IntToStr(I));
      LFailed := False; LError := '';
      try B := TCrossHttpUtils.EncodeHeader(S);
      except on E: EConvertError do begin LFailed := True; LError := E.Message; end; end;
      Check(LFailed and (LError = 'Invalid UTF-16 in HTTP header'),
        '整头编码拒绝坏代理 ' + IntToStr(LPrefixLength) + '/' + IntToStr(I));
    end;
  // 两次结果不能共享可写存储；ASCII 与非 ASCII 两条结果路径都验证。
  for I := 0 to 1 do
  begin
    if I = 0 then S := 'ABC'#0 else S := '中文'#$D83D#$DE00;
    LExpected := TEncoding.UTF8.GetBytes(S);
    B := TCrossHttpUtils.EncodeHeader(S); LOther := TCrossHttpUtils.EncodeHeader(S);
    Check((Length(B) > 0) and (Pointer(B) <> Pointer(LOther)), '整头编码结果独立分配');
    B[0] := B[0] xor $FF;
    Check(SameBytes(LOther, LExpected) and SameBytes(TEncoding.UTF8.GetBytes(S), LExpected),
      '修改结果不影响另一结果及输入');
  end;
end;

// 完整请求快照必须独立复制；这一合同与 TParamEntry.RawValue 的数组共享语义不同。
procedure TestRequest;
const OldIID: TGUID = '{B26B7E7B-6B24-4D86-AB58-EBC20722CFDD}';
var F: TFixture; B, Snapshot, Copy1: TBytes; Intf: IInterface; Req: ICrossHttpRequest;
begin
  F := TFixture.Create;
  try
    B := Bytes('GET /中文/%252F?q=%26%3D&raw=中文&plus=a+b&bad=%XY HTTP/1.1'#13#10'Host: localhost'#13#10'X: 中文'#13#10#13#10);
    Check(TRequestAccess(F.Request as TCrossHttpRequest).ParseHeader(Pointer(B), Length(B)), '请求解析');
    Check(F.Request.Path = '/中文/%2F', 'path 只解码一次');
    Check((F.Request.Query['q'] = '&=') and (F.Request.Query['raw'] = '中文')
      and (F.Request.Query['plus'] = 'a b') and (F.Request.Query['bad'] = '%XY'), 'query 边界和既有规则');
    Check(Pos('%252F', F.Request.RequestCmdLine) > 0, '命令行保留百分号');
    Snapshot := Copy(B); Copy1 := F.Request.RawRequestHeader; Copy1[0] := 0; B[0] := 0;
    F.Request.Header['X'] := 'changed';
    Check(SameBytes(F.Request.RawRequestHeader, Snapshot), '快照独立于 getter/源缓冲/字段修改');
    Check(Supports(F.Request, ICrossHttpRequest, Req), '新 GUID');
    Check(not Supports(F.Request, OldIID, Intf), '旧 GUID 不支持'); Req := nil;
    B := Bytes('GET / HTTP/1.1'#13#10'bad'#13#10#13#10);
    Check(not TRequestAccess(F.Request as TCrossHttpRequest).ParseHeader(Pointer(B), Length(B)), '请求拒绝非法字段');
  finally F.Free; end;
end;

procedure TestMultipart;
var M: THttpMultiPartFormData; B, Actual: TBytes; I, N, Used, Chunk: Integer;
    R: TFormDataDecodeResult; FilePath: string;
begin
  for N := 1 to 3 do
  begin
    M := THttpMultiPartFormData.Create;
    try
      M.InitWithBoundary('test'); M.StoragePath := ExtractFilePath(ParamStr(0));
      B := Bytes('--test'#13#10'Content-Disposition: form-data; name="中文"; filename="中文.txt"'#13#10'Content-Type: text/plain'#13#10#13#10'abc'#13#10'--test--'#13#10);
      R := frContinue; I := 0;
      while I < Length(B) do
      begin
        Chunk := Length(B) - I;
        if (N < 3) and (Chunk > N) then Chunk := N;
        R := M.Decode(@B[I], Chunk, Used);
        Check((R <> frFailed) and (Used = Chunk), 'multipart 分块消费');
        Inc(I, Used);
      end;
      Check((R = frComplete) and (M.Count = 1) and (M.Items[0].Name = '中文')
        and (M.Items[0].FileName = '中文.txt'), 'multipart 文件名 UTF8');
      Check(M.Items[0].AsString = 'abc', 'multipart 内容');
    finally M.Free; end;
  end;
  M := THttpMultiPartFormData.Create;
  try
    M.InitWithBoundary('test'); M.StoragePath := ExtractFilePath(ParamStr(0));
    B := Bytes('--test'#13#10'Content-Disposition: form-data; name="x"'#13#10'bad'#13#10#13#10'a'#13#10'--test--'#13#10);
    Check(M.Decode(Pointer(B), Length(B)) = frFailed, 'multipart 整块拒绝非法头');
    Check(M.Count = 0, '失败字段未加入');
  finally M.Free; end;
  M := THttpMultiPartFormData.Create; FilePath := '';
  try
    M.InitWithBoundary('test'); M.StoragePath := ExtractFilePath(ParamStr(0));
    B := Bytes('--test'#13#10'Content-Disposition: form-data; name="x"; filename="x.bin"'#13#10'Content-Type: application/octet-stream'#13#10#13#10);
    I := Length(B); SetLength(B, I + 5);
    B[I] := 0; B[I+1] := $80; B[I+2] := $FF; B[I+3] := 13; B[I+4] := 10;
    Actual := Bytes(#13#10'--test'#13#10'Content-Disposition: form-data; name="bad"'#13#10'Bad Name: x'#13#10#13#10);
    N := Length(B); SetLength(B, N + Length(Actual)); Move(Actual[0], B[N], Length(Actual));
    Check(M.Decode(Pointer(B), Length(B)) = frFailed, '后续 part 非法头');
    Check(M.Count = 1, '已有 part 仍由表单持有');
    FilePath := M.Items[0].FilePath;
    SetLength(Actual, 5); M.Items[0].Value.Position := 0; M.Items[0].Value.ReadBuffer(Actual[0], 5);
    Check((Actual[0] = 0) and (Actual[1] = $80) and (Actual[2] = $FF)
      and (Actual[3] = 13) and (Actual[4] = 10), '文件正文不参与字符转换');
  finally M.Free; end;
  Check((FilePath <> '') and not FileExists(FilePath), '失败释放后清理已生成文件');
end;

procedure TestServerOutput(const Kind: Integer);
var F: TFixture; Calls: Integer; Success: Boolean; Held: ICrossHttpRequest; Snapshot: TBytes;
begin
  F := TFixture.Create; Calls := 0; Success := True;
  try
    F.Server.Get('/test', TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest;
      const S: ICrossHttpResponse; var Handled: Boolean)
      begin
        Handled := True; Held := R; Snapshot := R.RawRequestHeader;
        S.Header['X-Text'] := '中文'#$D83D#$DE00;
        case Kind of
          1: S.Header['X-Text'] := #13#10;
          2: S.Header['X-Text'] := #$D800;
          3: S.StatusText := #$DC00;
          4: S.Cookies.Add(TResponseCookie.Create('x', #13#10));
        end;
        S.SendNoCompress('body', procedure(const C: ICrossConnection; const OK: Boolean)
          begin Inc(Calls); Success := OK; end);
      end));
    F.ConnectionObj.Feed('GET /test HTTP/1.1'#13#10'Host: localhost'#13#10#13#10);
    Check((Calls = 1) and (Success = (Kind = 0)), '服务端发送回调');
    if Kind = 0 then
    begin
      Check(Pos(Wire('X-Text: 中文'#$D83D#$DE00#13#10), F.ConnectionObj.Sent) > 0, '服务端线上 UTF8');
      Check(Pos(AnsiString('Content-Length: 4'), F.ConnectionObj.Sent) > 0, '正文长度');
      F.ConnectionObj.Feed('GET /next HTTP/1.1'#13#10'Host: localhost'#13#10#13#10);
      Check(SameBytes(Held.RawRequestHeader, Snapshot), '后续请求不污染快照');
    end else Check(F.ConnectionObj.Writes = 0, '失败前没有发送任何字节');
    Held := nil;
  finally F.Free; end;
end;

procedure TestControlHeaders;
const
  Names: array[0..11] of string = ('Content-Length', 'Transfer-Encoding',
    'Content-Encoding', 'Accept-Encoding', 'Connection', 'Upgrade', 'Expect',
    'Sec-WebSocket-Key', 'Sec-WebSocket-Version', 'Sec-WebSocket-Accept',
    'Sec-WebSocket-Protocol', 'Sec-WebSocket-Extensions');
var H: THttpHeader; B, Raw: TBytes; Name, Prefix, LCaseName, LAlias: string;
    I, LCaseIndex, LAliasKind: Integer; C: Char;
begin
  H := THttpHeader.Create;
  try
    // 这里仅测控制字节筛查和 OWS，所以统一用 abc；CL 的数字等语义由完整 Parser 用例验证。
    for Name in Names do
    begin
      B := Bytes(Name + ': '#9'abc '#9#13#10);
      Check(H.Decode(Pointer(B), Length(B)), '控制字段 ASCII/OWS');
      Check(SameBytes(H.Items[0].RawValue, Bytes('abc')), 'ASCII raw 保持');
      Raw := H.Items[0].RawValue;
      B := Bytes(Name + ': abc'#13#10 + Name + ': '#$FEFF'abc'#13#10);
      Check(not H.Decode(Pointer(B), Length(B), False), '控制字段拒绝 BOM: ' + Name);
      Check((H.Count = 1) and (Pointer(H.Items[0].RawValue) = Pointer(Raw)), '所有重复项校验并回滚');
      B := Bytes(Name + ': '); SetLength(B, Length(B) + 1); B[High(B)] := $80;
      Check(not H.Decode(Pointer(B), Length(B)) and (H.Count = 0), '控制字段拒绝高位原始字节');
    end;
    // 名称分类必须比较完整 ASCII 名称；大小写、长度和相似前后缀均不能改变 raw 规则。
    for Name in Names do
      for LCaseIndex := 0 to 2 do
      begin
        LCaseName := Name;
        for I := 1 to Length(LCaseName) do
        begin
          C := LCaseName[I];
          if (C >= 'A') and (C <= 'Z') then C := Char(Ord(C) + 32);
          if (LCaseIndex = 1) or ((LCaseIndex = 2) and not Odd(I)) then
            if (C >= 'a') and (C <= 'z') then C := Char(Ord(C) - 32);
          LCaseName[I] := C;
        end;
        B := Bytes(LCaseName + ': abc');
        Check(H.Decode(Pointer(B), Length(B)) and (H.Items[0].Name = LCaseName),
          '控制字段保留输入大小写: ' + LCaseName);
        Raw := H.Items[0].RawValue;
        B := Bytes('Good: yes'#13#10 + LCaseName + ': '#$FEFF'abc');
        Check(not H.Decode(Pointer(B), Length(B), False), '大小写控制字段拒绝 BOM: ' + LCaseName);
        Check((H.Count = 1) and (Pointer(H.Items[0].RawValue) = Pointer(Raw))
          and SameBytes(Raw, Bytes('abc')), '分类失败回滚保留旧 raw');
        B := Bytes(LCaseName + ': '); SetLength(B, Length(B) + 1); B[High(B)] := $80;
        Check(not H.Decode(Pointer(B), Length(B)), '大小写控制字段拒绝高字节: ' + LCaseName);
        for LAliasKind := 0 to 2 do
        begin
          case LAliasKind of
            0: LAlias := 'X-' + LCaseName;
            1: LAlias := LCaseName + '-X';
          else LAlias := Copy(LCaseName, 1, Length(LCaseName) - 1) + 'X';
          end;
          B := Bytes(LAlias + ': '#$FEFF'中文');
          Check(H.Decode(Pointer(B), Length(B)) and (H[LAlias] = '中文'),
            '相似名称仍为普通字段: ' + LAlias);
          Check(SameBytes(H.Items[0].RawValue, Bytes(#$FEFF'中文')), '相似名称保留 BOM raw');
        end;
        if (Name = 'Expect') or (Name = 'Transfer-Encoding') then
        begin
          if Name = 'Expect' then Prefix := 'x=' else Prefix := 'custom; p=';
          B := Bytes(LCaseName + ': ' + Prefix + '"a\"中文"');
          Check(H.Decode(Pointer(B), Length(B)), '大小写控制字段保留 quoted obs-text');
          B := Bytes(LCaseName + ': ' + Prefix + '"abc\');
          Check(not H.Decode(Pointer(B), Length(B)), 'quoted-string 悬空转义拒绝');
        end;
      end;
    for Name in ['Expect', 'Transfer-Encoding'] do
    begin
      if Name = 'Expect' then Prefix := 'x=' else Prefix := 'custom; p=';
      B := Bytes(Name + ': ' + Prefix + '"中文"');
      Check(H.Decode(Pointer(B), Length(B)), '合法引号参数高位字节');
      Check(H[Name] = Prefix + '"中文"', '引号参数仍按 GetString 转换');
      B := Bytes(Name + ': ' + Prefix + '"a\"中文"');
      Check(H.Decode(Pointer(B), Length(B)), '转义引号不终止参数');
      B := Bytes(Name + ': ' + Prefix + '"中文"; ' + #$FEFF + 'x');
      Check(not H.Decode(Pointer(B), Length(B)), '引号外高位字节拒绝');
      B := Bytes(Name + ': ' + Prefix + '"中文');
      Check(not H.Decode(Pointer(B), Length(B)), '未闭合引号拒绝');
    end;
    B := Bytes('X-Test: '#$FEFF'中文'#13#10'Referer: /中文'#13#10#13#10);
    Check(H.Decode(Pointer(B), Length(B)) and (H['X-Test'] = '中文'), '普通字段保持 GetString/BOM');
    Check(SameBytes(H.Items[0].RawValue, Bytes(#$FEFF'中文')), '普通字段 raw 不变');
  finally H.Free; end;
end;

// 从非零、非对齐位置提供显式字节范围；区间外哨兵与输入都只能借用，不能被解析器改写。
procedure TestDecodeBounds;
const
  Offsets: array[0..3] of Integer = (1, 3, 7, 15);
  Inputs: array[0..4] of string = ('X:', 'X:a', 'X: aa', 'X: 中文', 'X: 中文'#13#10#13#10);
  Values: array[0..4] of string = ('', 'a', 'aa', '中文', '中文');
  Tails: array[0..2] of string = (#$D83D#$DE00, #$D800, #$DC00);
var
  H: THttpHeader;
  LPayload, LBuffer, LBefore: TBytes;
  LOffset, I: Integer;
  S, LValue: string;
begin
  H := THttpHeader.Create;
  try
    for LOffset in Offsets do
      for I := Low(Inputs) to High(Inputs) do
      begin
        LPayload := Bytes(Inputs[I]);
        SetLength(LBuffer, LOffset + Length(LPayload) + 5);
        FillChar(LBuffer[0], Length(LBuffer), $7F);
        Move(LPayload[0], LBuffer[LOffset], Length(LPayload));
        LBefore := Copy(LBuffer);
        Check(H.Decode(@LBuffer[LOffset], Length(LPayload)) and (H.Count = 1), '非零偏移按显式长度解码');
        Check((H['X'] = Values[I]) and H.Items[0].HasRawValue
          and SameBytes(H.Items[0].RawValue, Bytes(Values[I])), '偏移区间值和 raw');
        Check(SameBytes(LBuffer, LBefore), '解码不改借用区间及哨兵');
        FillChar(LBuffer[LOffset], Length(LPayload), 0);
        Check((H['X'] = Values[I]) and SameBytes(H.Items[0].RawValue, Bytes(Values[I])),
          '输入复用不影响自有解码结果');
      end;
    for I := Low(Tails) to High(Tails) do
    begin
      LValue := '中文' + Tails[I]; S := 'X: ' + LValue;
      // 字符串 Decode 复制码元，不在入站文本入口增加出站 UTF-16 合法性检查。
      Check(H.Decode(S) and (H['X'] = LValue) and not H.Items[0].HasRawValue,
        '字符串入口保留末尾代理码元');
      S[Length(S)] := 'z';
      Check(H['X'] = LValue, '字符串输入修改不污染字段');
    end;
  finally H.Free; end;
end;

{$IFDEF MSWINDOWS}
// 哨兵只验证语义；不可读保护页同时验证扫描器不会在范围末尾实际读取下一个字节。
procedure TestDecodeGuard;
var
  H: THttpHeader;
  LInfo: TSystemInfo;
  LBase, P: PByte;
  LOldProtect: DWORD;
  B: TBytes;
  N: Integer;
begin
  GetSystemInfo(LInfo);
  LBase := VirtualAlloc(nil, LInfo.dwPageSize * 2, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  if LBase = nil then RaiseLastOSError;
  try
    if not VirtualProtect(LBase + LInfo.dwPageSize, LInfo.dwPageSize, PAGE_NOACCESS, LOldProtect) then
      RaiseLastOSError;
    H := THttpHeader.Create;
    try
      Check(H.Decode(LBase + LInfo.dwPageSize, 0), '零长度保护页不解引用');
      for N := 0 to 17 do
      begin
        B := Bytes('X:' + StringOfChar('a', N));
        P := LBase + LInfo.dwPageSize - Length(B);
        Move(B[0], P^, Length(B));
        Check(H.Decode(P, Length(B)) and (H['X'] = StringOfChar('a', N)), '保护页前完整字段');
        B := Bytes('X:' + StringOfChar('a', N) + #13);
        P := LBase + LInfo.dwPageSize - Length(B);
        Move(B[0], P^, Length(B));
        Check(not H.Decode(P, Length(B)) and (H.Count = 0), '保护页前裸 CR 拒绝而不读越界');
      end;
    finally H.Free; end;
  finally VirtualFree(LBase, 0, MEM_RELEASE); end;
end;
{$ENDIF}

function FileCount(const APath: string): Integer;
var Search: TSearchRec;
begin
  Result := 0;
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faAnyFile, Search) <> 0 then Exit;
  try
    repeat
      if (Search.Name <> '.') and (Search.Name <> '..') then Inc(Result);
    until FindNext(Search) <> 0;
  finally FindClose(Search); end;
end;

// 0 正常；1..3 坏字段头；4 结束边界截断；5 结束行无 CRLF；6 分包尾声；7 空正文。
// 必须经完整 HTTP Parser/路由验证，单独检查 multipart.Decode=frFailed 不足以证明失败传播。
procedure TestMultipartRequest(const ACase: Integer);
var F: TFixture; Calls: Integer; ValidForm: Boolean; Body, Prefix, Tail, Epilogue, Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0)) + 'multipart-reject-' + IntToStr(ACase);
  Check(not DirectoryExists(Dir) and CreateDir(Dir), '创建隔离上传目录');
  Calls := 0; ValidForm := False; F := TFixture.Create;
  try
    F.Server.StoragePath := Dir;
    // 清理断言显式开启自动删除，不改变生产默认配置对上传文件保留的约定。
    F.Server.AutoDeleteFiles := True;
    F.Server.Post('/upload', TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest;
      const S: ICrossHttpResponse; var Handled: Boolean)
      var M: THttpMultiPartFormData;
      begin
        Handled := True; Inc(Calls); M := R.Body as THttpMultiPartFormData;
        ValidForm := (M.Count = 2) and (M.Items[0].FileName = '中文.bin')
          and (M.Items[0].AsString = 'abc') and (M.Items[1].AsString = 'two');
        S.SendNoCompress('ok');
      end));
    Body := '--b'#13#10'Content-Disposition: form-data; name="file"; filename="中文.bin"'#13#10;
    if ACase = 1 then Body := Body + 'Bad Name: x'#13#10;
    Body := Body + 'Content-Type: application/octet-stream'#13#10#13#10'abc'#13#10'--b'#13#10;
    Tail := 'Content-Disposition: form-data; name="text"'#13#10;
    if ACase in [2, 3] then Tail := Tail + 'Bad Name: x'#13#10;
    Tail := Tail + #13#10'two'#13#10'--b--'#13#10;
    case ACase of
      4: Delete(Tail, Length(Tail) - 3, 4);
      5: Delete(Tail, Length(Tail) - 1, 2);
      6: Epilogue := '忽略尾声 --bX';
      7: begin Body := ''; Tail := ''; end;
    end;
    // filename 含中文，Content-Length 必须计算实际 UTF-8 字节数，不能直接用字符串 Length。
    Prefix := 'POST /upload HTTP/1.1'#13#10'Host: localhost'#13#10
      + 'Content-Type: multipart/form-data; boundary=b'#13#10
      + 'Content-Length: ' + IntToStr(Length(Bytes(Body + Tail + Epilogue))) + #13#10#13#10;
    if ACase = 6 then
    begin
      F.ConnectionObj.Feed(Wire(Prefix + Body + Tail));
      F.ConnectionObj.Feed(Wire(Epilogue));
    end else
    if ACase = 3 then
    begin
      F.ConnectionObj.Feed(Wire(Prefix + Body));
      Check((Calls = 0) and (FileCount(Dir) = 1), '失败前已创建文件，尚未发布请求');
      F.ConnectionObj.Feed(Wire(Tail));
    end
    else F.ConnectionObj.Feed(Wire(Prefix + Body + Tail));
    if ACase in [0, 5, 6] then
      Check((Calls = 1) and ValidForm and (Pos(AnsiString('200 OK'), F.ConnectionObj.Sent) > 0), '合法表单完整发布')
    else begin
      Check((Calls = 0) and (Pos(AnsiString('400 Bad Request'), F.ConnectionObj.Sent) > 0), '非法表单必须失败，不发布部分数据');
      Check(F.ConnectionObj.ConnectStatus in [csDisconnected, csClosed], '非法表单断开连接');
    end;
  finally F.Free; end;
  Check(FileCount(Dir) = 0, '关闭后清理上传文件');
  Check(RemoveDir(Dir), '清理隔离上传目录');
end;

// ParamStr(2) 是 runner 创建的独立上传目录；READY/REQUESTS 供父进程同步和核对业务调用数。
procedure Server;
var S: ICrossHttpServer; Ready: TEvent; Port: Word; Calls: Integer; Line: string;
begin
  Calls := 0; Port := 0; Ready := TEvent.Create(nil, True, False, '');
  try
    S := TCrossHttpServer.Create(1, False);
    S.Addr := '127.0.0.1'; S.Port := 0;
    S.StoragePath := ParamStr(2); S.AutoDeleteFiles := True;
    S.Post('/test', TCrossHttpRouterProc(procedure(const R: ICrossHttpRequest;
      const Response: ICrossHttpResponse; var Handled: Boolean)
      var M: THttpMultiPartFormData; B: TBytes;
      begin
        Handled := True; Inc(Calls);
        if R.Body is THttpMultiPartFormData then
        begin
          M := R.Body as THttpMultiPartFormData;
          Check((M.Count = 2) and (M.Items[0].AsString = 'abc')
            and (M.Items[1].AsString = 'two'), 'TCP 表单内容');
        end
        else begin
          Check((R.RawBody <> nil) and (R.RawBody.Size = 3), 'TCP 正文定界');
          SetLength(B, 3); R.RawBody.Position := 0; R.RawBody.ReadBuffer(B[0], 3);
          Check(SameBytes(B, Bytes('abc')), 'TCP 正文内容');
          if R.Header.ExistsParam('X-Text') then
            Check(R.Header['X-Text'] = '中文', 'TCP 普通字段 GetString');
        end;
        Response.SendNoCompress('ok');
      end));
    S.Start(procedure(const L: ICrossListen; const OK: Boolean)
      begin if OK then Port := L.LocalPort; Ready.SetEvent; end);
    Check((Ready.WaitFor(5000) = wrSignaled) and (Port <> 0), '测试服务监听');
    Writeln('READY ', Port); Flush(Output); Readln(Line);
    S.Stop; S := nil;
    Writeln('REQUESTS ', Calls); Flush(Output);
  finally S := nil; Ready.Free; end;
end;

procedure Client;
var C: ICrossHttpClient; Done: TEvent; H: THttpHeader; Calls: Integer; ErrorText, Kind, Method, TextValue: string; AcceptOpaque: Boolean;
begin
  Kind := ParamStr(3); Calls := 0; ErrorText := ''; AcceptOpaque := True;
  // 保留 GetString 的平台行为：同一非 UTF-8 字节可能可转换，也可能抛异常。
  // 此预期只用于普通字段；协议控制字段另由 BOM 拒绝用例验证。
  try TextValue := TUtils.GetString(TBytes.Create($FE));
  except on E: Exception do AcceptOpaque := False; end;
  Done := TEvent.Create(nil, True, False, ''); H := THttpHeader.Create;
  try
    C := TCrossHttpClient.Create;
    H['X-Text'] := '中文'#$D83D#$DE00;
    if Kind = 'invalid-field' then H['X-Text'] := #13#10;
    if Kind = 'invalid-utf16' then H['X-Text'] := #$D800;
    Method := 'GET';
    if Kind = 'head-metadata' then Method := 'HEAD';
    if Kind = 'invalid-method' then Method := 'G'#$DC00;
    C.DoRequest(Method, ParamStr(2), H, Pointer(nil), 0, nil,
      procedure(const R: ICrossHttpClientRequest)
      begin
        // 回调可修改 Query 而不更新原 URL 文本，用它验证发送端没有漏掉动态参数校验。
        if Kind = 'invalid-query' then R.Query['q'] := #$D800;
        if Kind = 'invalid-query-name' then R.Query[#$DC00] := 'q';
        if Kind = 'invalid-query-tail' then
        begin
          R.Query.Add('ok', 'before', True);
          R.Query.Add('bad', #$D800, True);
        end;
        if Kind = 'query-values' then
        begin
          // 多项/重复名/空值经过校验后仍按插入顺序编码，不依赖原URL的query文本。
          R.Query.Add('dup', '中文', True);
          R.Query.Add('dup', '', True);
          R.Query.Add('a b', 'x+y&=/#', True);
          R.Query.Add('emoji', #$D83D#$DE00, True);
        end;
      end,
      procedure(const R: ICrossHttpClientResponse)
      var
        LCookie: TResponseCookie;
        LCookieValues: TArray<string>;
      begin
        Inc(Calls);
        try
          if (Kind = 'valid') or (Kind = 'query-values')
            or ((Kind = 'opaque-response') and AcceptOpaque) then
          begin
            Check((R.StatusCode = 200) and (R.StatusText = '中文'), '客户端状态行 UTF8');
            if (Kind = 'valid') or (Kind = 'query-values') then
              Check((R.Header['X-Text'] = '中文') and R.Header.Items[0].HasRawValue, '客户端字段 UTF8/raw')
            else begin
              Check(SameBytes(R.Header.Items[0].RawValue, TBytes.Create($FE)), '客户端保留非 UTF8 原值');
              Check((R.Content <> nil) and (R.Content.Size = 3), '高位值不破坏正文定界');
            end;
            Check(R.Cookies.Count = 2, '重复 Set-Cookie');
          end else
          if Kind = 'cookie-values' then
          begin
            Check((R.StatusCode = 200) and (R.StatusText = 'OK'), 'Cookie响应状态行');
            Check(R.Cookies.Count = 3, '保留重复及空值Cookie，跳过非法项');
            LCookie := R.Cookies.Items[0];
            Check((LCookie.Name = 'a') and (LCookie.Value = '1'), '第一个Cookie名称和值');
            Check((LCookie.Domain = '127.0.0.1') and (LCookie.Path = '/first'), '首项默认域及显式路径');
            Check(LCookie.HttpOnly and not LCookie.Secure and (LCookie.MaxAge = 0), '首项HttpOnly属性');
            LCookie := R.Cookies.Items[1];
            Check((LCookie.Name = 'a') and (LCookie.Value = '2'), '同名Cookie按原字段顺序保留');
            Check((LCookie.Domain = '127.0.0.1') and (LCookie.Path = '/'), '第二项默认域及路径');
            Check((LCookie.MaxAge = 60) and LCookie.Secure and not LCookie.HttpOnly, '第二项Max-Age和Secure属性');
            LCookie := R.Cookies.Items[2];
            Check((LCookie.Name = 'empty') and (LCookie.Value = ''), '空Cookie值不丢失');
            Check((LCookie.Domain = '127.0.0.1') and (LCookie.Path = '/'), '空值项默认域及路径');
            Check((LCookie.MaxAge = 0) and not LCookie.HttpOnly and not LCookie.Secure, '空值项默认属性');
            // Cookie解析跳过非法项，但完整Header仍保留原字段、值及重复次序。
            Check(R.Header.GetHeaderValues('Set-Cookie', LCookieValues)
              and (Length(LCookieValues) = 5), '原始Set-Cookie字段全部保留');
            Check((LCookieValues[0] = 'a=1; Path=/first; HttpOnly')
              and (LCookieValues[1] = 'a=2; Max-Age=60; Secure')
              and (LCookieValues[2] = 'empty=')
              and (LCookieValues[3] = 'bad name=value')
              and (LCookieValues[4] = 'no-equals'), '原始Set-Cookie值及顺序');
            Check(R.Header['X-Between'] = 'preserved', '普通字段不受Cookie收集影响');
            Check(R.Header.Items[0].HasRawValue
              and SameBytes(R.Header.Items[0].RawValue, Bytes('a=1; Path=/first; HttpOnly')),
              'Set-Cookie保留原始字节');
          end else
          if Kind = 'head-metadata' then
            Check((R.StatusCode = 200) and (R.Header['Transfer-Encoding'] = 'custom; p="中文"')
              and ((R.Content = nil) or (R.Content.Size = 0)), 'HEAD 高位引号 TE 元数据')
          else if Kind = 'empty-response' then
            Check((R.StatusCode = 204) and (R.StatusText = '') and (R.Header.Count = 0), '空原因和空头')
          else Check(R.StatusCode <> 200, '客户端失败回调');
        except on E: Exception do ErrorText := E.Message; end;
        Done.SetEvent;
      end);
    Check(Done.WaitFor(5000) = wrSignaled, '客户端回调超时');
    C.CancelAll; C := nil;
    Check(Calls = 1, '客户端只回调一次'); Check(ErrorText = '', ErrorText);
  finally C := nil; H.Free; Done.Free; end;
end;

{$I HeaderScanWordCases.inc}
{$I StartLineCaseCases.inc}
{$I HeaderNameCases.inc}
{$I HeaderEncodeCases.inc}
{$I ChunkedMetadataCases.inc}
{$I ResponseCookieOutputCases.inc}
{$I ResponseCookieEncodeCases.inc}
{$I BodylessResponseCases.inc}
{$I CompressionChoiceCases.inc}
{$I RequestPathCases.inc}
{$I RequestQueryCases.inc}
{$I RequestCookieScanCases.inc}
{$I RequestCookieEncodeCases.inc}
{$I UrlDecodeCases.inc}
{$I UrlEncodeCases.inc}
{$I QueryEncodeCases.inc}
{$I ParamMutationCases.inc}
{$I ParamAssignCases.inc}
{$I RouteMatchCases.inc}
{$I RoutePathCases.inc}
{$I ParserHeaderCases.inc}
{$I LookupCases.inc}
{$I HtmlEncodeCases.inc}
{$I MultipartHeaderCases.inc}

var I: Integer;
begin
  try
    if ParamStr(1) = 'server' then Server
    else if ParamStr(1) = 'client' then Client
    else begin
      Writeln('entries'); TestEntries; Inc(Checks, RunParamMutationTests);
      Inc(Checks, RunParamAssignTests); Writeln('decode'); TestDecode; Writeln('encode'); TestEncode;
      Writeln('header-encoding'); TestHeaderEncoding; Inc(Checks, RunHeaderEncodeTests);
      Writeln('request'); TestRequest; Writeln('multipart'); TestMultipart;
      Writeln('multipart-headers'); Inc(Checks, RunMultipartHeaderTests);
      Writeln('control-headers'); TestControlHeaders; Inc(Checks, RunChunkedMetadataTests);
      Writeln('decode-bounds'); TestDecodeBounds;
      Writeln('header-scan-word'); Inc(Checks, RunHeaderScanWordTests);
      Writeln('startline-case'); Inc(Checks, RunStartLineCaseTests);
      Writeln('header-names'); Inc(Checks, RunHeaderNameTests);
      Writeln('request-paths'); Inc(Checks, RunRequestPathTests);
      Writeln('route-match'); Inc(Checks, RunRouteMatchTests);
      Writeln('route-path'); Inc(Checks, RunRoutePathTests);
      Writeln('parser-header'); I := RunParserHeaderTests; Inc(Checks, I);
      Writeln('lookups'); Inc(Checks, RunLookupTests);
      Writeln('html-encode'); Inc(Checks, RunHtmlEncodeTests);
      Writeln('request-query'); Inc(Checks, RunRequestQueryTests);
      Inc(Checks, RunRequestCookieScanTests);
      Inc(Checks, RunRequestCookieEncodeTests);
      Writeln('url-decode'); Inc(Checks, RunUrlDecodeTests);
      Writeln('url-encode'); Inc(Checks, RunUrlEncodeTests);
      Writeln('query-encode'); Inc(Checks, RunQueryEncodeTests);
      {$IFDEF MSWINDOWS}Writeln('decode-guard'); TestDecodeGuard;{$ENDIF}
      Writeln('multipart-request'); for I := 0 to 7 do TestMultipartRequest(I);
      Writeln('server-output');
      // Feed会直接累计全局断言；先取得局部计数，避免Inc求值顺序覆盖函数内部的增量。
      Inc(Checks, RunResponseCookieEncodeTests);
      I := RunResponseCookieOutputTests;
      Inc(Checks, I);
      I := RunBodylessResponseTests;
      Inc(Checks, I);
      I := RunCompressionChoiceTests;
      Inc(Checks, I);
      for I := 0 to 4 do TestServerOutput(I);
    end;
    Writeln('PASS checks=', Checks);
  except on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
