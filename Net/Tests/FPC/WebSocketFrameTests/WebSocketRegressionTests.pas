unit WebSocketRegressionTests;
{$I zLib.inc}
interface
procedure RunWebSocketRegressionTests;
implementation
uses SysUtils, Classes, Net.CrossWebSocketParser;
type
  TEvent = record Code: Byte; Data: TBytes; end;
  TEvents = array of TEvent;
  TTextParser = class(TCrossWebSocketParser)
  protected
    function IsValidOpCode(const AOpCode: Byte): Boolean; override;
  end;
  TThrowCloseParser = class(TCrossWebSocketParser)
  protected
    function IsValidCloseCode(const ACode: Word): Boolean; override;
  end;
  TCapture = class
    Parser: TCrossWebSocketParser;
    Events: TEvents;
    Failed: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ACode: Byte; const AData: TBytes);
  end;
function TTextParser.IsValidOpCode(const AOpCode: Byte): Boolean;
begin Result := AOpCode in [1,8,9,10]; end;
function TThrowCloseParser.IsValidCloseCode(const ACode: Word): Boolean;
begin raise Exception.Create('校验钩子异常'); end;
constructor TCapture.Create;
begin
  inherited;
  Parser := TCrossWebSocketParser.Create(
    procedure(const ACode: Byte; const AData: TBytes) begin Add(ACode,AData); end,
    procedure(const AType: TWsMessageType; const AData: TBytes)
    begin if AType=wtText then Add(1,AData) else Add(2,AData); end,
    procedure begin Inc(Failed); end);
end;
destructor TCapture.Destroy;
begin Parser.Free; inherited; end;
procedure TCapture.Add(const ACode: Byte; const AData: TBytes);
var N:Integer;
begin N:=Length(Events); SetLength(Events,N+1); Events[N].Code:=ACode; Events[N].Data:=Copy(AData,0,Length(AData)); end;
function Hex(const AData:TBytes):string;
var I:Integer;
begin Result:='';for I:=0 to High(AData) do Result:=Result+IntToHex(AData[I],2);end;
procedure Feed(const AParser:TCrossWebSocketParser;const AWire:TBytes;const AChunk:Integer);
var LPos,LCount,LRemaining:Integer; LBuf:Pointer;
begin
  LPos:=0;
  while LPos<Length(AWire) do begin
    LCount:=AChunk;if LCount>Length(AWire)-LPos then LCount:=Length(AWire)-LPos;
    LBuf:=@AWire[LPos];LRemaining:=LCount;AParser.Decode(LBuf,LRemaining);
    if (LRemaining<>0) or (LBuf<>Pointer(PByte(@AWire[LPos])+LCount)) then
      raise Exception.Create('解析器没有正确推进输入位置');
    Inc(LPos,LCount);
  end;
end;
procedure AssertTrue(const AValue:Boolean; const AMessage:string);
begin if not AValue then raise Exception.Create(AMessage); end;
function Frame(const ACode:Byte;const AFin,AMasked:Boolean;const AData:TBytes):TBytes;
var LPtr:Pointer;
begin
  LPtr:=nil;if Length(AData)>0 then LPtr:=@AData[0];
  Result:=TCrossWebSocketParser.MakeFrameData(ACode,AFin,not AMasked,LPtr,Length(AData));
end;
function Join(const A,B:TBytes):TBytes;
begin
  Result:=Copy(A,0,Length(A));SetLength(Result,Length(A)+Length(B));
  if Length(B)>0 then Move(B[0],Result[Length(A)],Length(B));
end;
procedure TestStrictParser;
var C:TCapture; P:TCrossWebSocketParser; W,Saved,Before:TBytes; B:Pointer; N,I,Mask,Size,Chunk:Integer;
    Calls,Messages:Integer; Raised:Boolean;
  procedure Bad(const AName:string;const AWire:TBytes;const ACode:Word);
  var L:TBytes;
  begin
    C:=TCapture.Create;
    try
      C.Parser.Role:=wprClient;C.Parser.AllowedRsvBits:=0;C.Parser.CheckTextUtf8:=True;
      Feed(C.Parser,AWire,1);
      AssertTrue(C.Failed=1,AName+': 未失败或重复失败');
      AssertTrue(C.Parser.Stopped and (C.Parser.ErrorCode=ACode),AName+': 错误码不符');
      L:=TBytes.Create($81,1,$41);Feed(C.Parser,L,1);
      AssertTrue((C.Failed=1) and (Length(C.Events)=0),AName+': 终止后仍回调');
    finally C.Free; end;
  end;
begin
  Bad('孤立连续帧',TBytes.Create($80,0),1002);
  Bad('消息交错',TBytes.Create($01,0,$82,0),1002);
  Bad('控制帧分片',TBytes.Create($09,0),1002);
  Bad('控制帧超长',TBytes.Create($89,126,0,126),1002);
  Bad('保留opcode',TBytes.Create($83,0),1002);
  Bad('RSV',TBytes.Create($C1,0),1002);
  Bad('掩码方向',TBytes.Create($81,$80),1002);
  Bad('非最短16位',TBytes.Create($82,126,0,1),1002);
  Bad('非最短64位',TBytes.Create($82,127,0,0,0,0,0,0,0,1),1002);
  Bad('64位最高位',TBytes.Create($82,127,$80,0,0,0,0,0,0,0),1002);
  Bad('过大帧',TBytes.Create($82,127,0,0,0,1,0,0,0,0),1009);
  Bad('Close单字节',TBytes.Create($88,1,0),1002);
  Bad('Close保留状态码',TBytes.Create($88,2,3,$ED),1002);
  Bad('Close非法文本',TBytes.Create($88,3,3,$E8,$FF),1007);
  Bad('文本过长编码',TBytes.Create($81,2,$C0,$80),1007);
  Bad('文本代理码点',TBytes.Create($81,3,$ED,$A0,$80),1007);
  Bad('文本超出Unicode',TBytes.Create($81,4,$F4,$90,$80,$80),1007);
  Bad('文本截断',TBytes.Create($81,2,$E2,$82),1007);
  C:=TCapture.Create;
  try
    C.Parser.CheckTextUtf8:=True;
    W:=TBytes.Create($01,1,$E2,$89,0,$80,2,$82,$AC);
    Feed(C.Parser,W,1);
    AssertTrue((C.Failed=0) and (Length(C.Events)=2) and (Hex(C.Events[1].Data)='E282AC'),'跨帧UTF8');
  finally C.Free; end;
  C:=TCapture.Create;
  try
    C.Parser.MaxMessageSize:=2;
    W:=TBytes.Create($01,2,$41,$42,$80,1,$43);Feed(C.Parser,W,1);
    AssertTrue((C.Failed=1) and (C.Parser.ErrorCode=1009),'累计长度限制');
  finally C.Free; end;
  Messages:=0;Calls:=0;
  P:=TTextParser.Create(nil,
    procedure(const K:TWsMessageType;const D:TBytes) begin Inc(Messages);AssertTrue(Hex(D)='4142','子类消息');end,
    procedure begin Inc(Calls);end);
  try W:=TBytes.Create($01,1,$41,$80,1,$42);Feed(P,W,1);AssertTrue((Messages=1) and (Calls=0),'旧opcode子类兼容');finally P.Free;end;
  Messages:=0;
  P:=TCrossWebSocketParser.Create(
    procedure(const Op:Byte;const D:TBytes) var L:TBytes;begin L:=TBytes.Create($80,1,$42);Feed(P,L,1);end,
    procedure(const K:TWsMessageType;const D:TBytes) begin Inc(Messages);AssertTrue(Hex(D)='4142','重入消息');end,nil);
  try W:=TBytes.Create($01,1,$41,$89,0);Feed(P,W,1);AssertTrue(Messages=1,'控制回调重入');finally P.Free;end;
  Calls:=0;
  P:=TCrossWebSocketParser.Create(nil,
    procedure(const K:TWsMessageType;const D:TBytes) begin Inc(Calls);if Calls=1 then raise Exception.Create('业务异常');end,nil);
  try
    W:=TBytes.Create($81,1,$41,$81,1,$42);B:=@W[0];N:=Length(W);Raised:=False;
    try P.Decode(B,N);except on E:Exception do Raised:=E.Message='业务异常';end;
    AssertTrue(Raised and (N=3) and not P.Stopped,'业务异常不能误报协议失败');
    P.Decode(B,N);AssertTrue((N=0) and (Calls=2),'异常后已消费位置');
  finally P.Free;end;
  P:=TThrowCloseParser.Create(nil,nil,nil);
  try
    W:=TBytes.Create($01,1,$41,$88,2,3,$E8,$80,1,$42);B:=@W[0];N:=Length(W);Raised:=False;
    try P.Decode(B,N);except on E:Exception do Raised:=E.Message='校验钩子异常';end;
    AssertTrue(Raised and P.Stopped and (N=0),'Close校验异常必须终止');
  finally P.Free;end;
  Calls:=0;Messages:=0;
  P:=TCrossWebSocketParser.Create(
    procedure(const Op:Byte;const D:TBytes) begin TThread.Sleep(50);end,
    procedure(const K:TWsMessageType;const D:TBytes) begin Inc(Messages);end,
    procedure begin Inc(Calls);end);
  try
    P.MessageTimeoutMs:=1;W:=TBytes.Create($01,1,$41,$89,0,$80,1,$42);Feed(P,W,Length(W));
    AssertTrue((Calls=1) and (Messages=0) and (P.ErrorCode=1008),'同一输入内消息期限');
  finally P.Free;end;
  // 每个边界覆盖掩码、任意输入切分和输入内容不变。
  for Mask:=0 to 1 do for I:=0 to 5 do begin
    case I of 0:Size:=0;1:Size:=1;2:Size:=125;3:Size:=126;4:Size:=65535;else Size:=65536;end;
    SetLength(Saved,Size);for N:=0 to Size-1 do Saved[N]:=Byte(N and $FF);
    W:=Frame(2,True,Mask=1,Saved);Before:=Copy(W,0,Length(W));
    for Chunk:=1 to 5 do begin
      C:=TCapture.Create;
      try
        if Mask=1 then C.Parser.Role:=wprServer else C.Parser.Role:=wprClient;
        if Chunk=1 then N:=1 else if Chunk=2 then N:=7 else if Chunk=3 then N:=125 else if Chunk=4 then N:=4096 else N:=Length(W);
        Feed(C.Parser,W,N);
        AssertTrue((C.Failed=0) and (Length(C.Events)=1) and (Hex(C.Events[0].Data)=Hex(Saved)),'长度或掩码边界');
      finally C.Free;end;
    end;
    AssertTrue(CompareMem(@W[0],@Before[0],Length(W)),'输入缓冲区不变');
  end;
  Writeln('Strict parser, compatibility and callback tests passed.');
end;

procedure TestLegalMatrix;
const
  Sizes:array[0..6] of Integer=(0,1,3,125,126,256,65536);
  Chunks:array[0..5] of Integer=(0,1,2,7,64,4096);
var
  Wire,Payload:TBytes;
  Expected:TEvents;
  Passed,Mask,Code,Si,Style,Ch,Split,I:Integer;
  procedure AppendFrame(const Op:Byte;const Fin,Masked:Boolean;const D:TBytes);
  begin Wire:=Join(Wire,Frame(Op,Fin,Masked,D));end;
  procedure Expect(const Op:Byte;const D:TBytes);
  var N:Integer;
  begin N:=Length(Expected);SetLength(Expected,N+1);Expected[N].Code:=Op;Expected[N].Data:=Copy(D,0,Length(D));end;
  procedure Build(const Op:Byte;const Masked:Boolean;const Size,Mode:Integer);
  var D:TBytes; A,B,J:Integer;
    procedure Control(const Op:Byte;const D:TBytes);
    begin AppendFrame(Op,True,Masked,D);Expect(Op,D);end;
  begin
    Wire:=nil;Expected:=nil;SetLength(Payload,Size);
    for J:=0 to Size-1 do Payload[J]:=65+(J mod 26);
    if Mode=0 then begin AppendFrame(Op,True,Masked,Payload);Expect(Op,Payload);Exit;end;
    A:=Size div 3;B:=Size div 3;
    if Mode=2 then Control(10,nil);
    AppendFrame(Op,False,Masked,Copy(Payload,0,A));
    if Mode=2 then begin Control(9,TBytes.Create($78));Control(10,nil);end;
    AppendFrame(0,False,Masked,Copy(Payload,A,B));
    if Mode=2 then begin SetLength(D,125);for J:=0 to 124 do D[J]:=65+(J mod 26);Control(9,D);end;
    AppendFrame(0,True,Masked,Copy(Payload,A+B,Size-A-B));Expect(Op,Payload);
    if Mode=2 then Control(9,nil);
  end;
  procedure Verify(const Chunk,FirstSplit:Integer);
  var C:TCapture; J,N:Integer; B:Pointer;
  begin
    C:=TCapture.Create;
    try
      C.Parser.CheckTextUtf8:=True;C.Parser.AllowedRsvBits:=0;
      if FirstSplit>0 then begin
        B:=@Wire[0];N:=FirstSplit;C.Parser.Decode(B,N);
        AssertTrue((N=0) and (B=Pointer(PByte(@Wire[0])+FirstSplit)),'首块输入位置');
        N:=Length(Wire)-FirstSplit;C.Parser.Decode(B,N);AssertTrue(N=0,'次块输入位置');
      end else
      if Chunk=0 then Feed(C.Parser,Wire,Length(Wire)) else Feed(C.Parser,Wire,Chunk);
      AssertTrue((C.Failed=0) and (Length(C.Events)=Length(Expected)),'合法矩阵事件数');
      for J:=0 to High(Expected) do begin
        AssertTrue((C.Events[J].Code=Expected[J].Code)
          and (Length(C.Events[J].Data)=Length(Expected[J].Data)),'合法矩阵事件类型和长度');
        if Length(Expected[J].Data)>0 then
          AssertTrue(CompareMem(@C.Events[J].Data[0],@Expected[J].Data[0],Length(Expected[J].Data)),'合法矩阵载荷');
      end;
      Inc(Passed);
    finally C.Free;end;
  end;
begin
  Passed:=0;
  for Mask:=0 to 1 do for Code:=1 to 2 do for Si:=0 to High(Sizes) do for Style:=0 to 2 do begin
    Build(Code,Mask=1,Sizes[Si],Style);
    for Ch:=0 to High(Chunks) do Verify(Chunks[Ch],0);
    if Length(Wire)<=600 then for Split:=1 to Length(Wire)-1 do Verify(0,Split);
  end;
  RandSeed:=215;
  for I:=1 to 300 do begin
    Build(1+Random(2),Random(2)=1,Random(2048),Random(3));Verify(1+Random(64),0);
  end;
  Writeln('Legal frame/split matrix: ',Passed,' passed.');
end;

procedure RunWebSocketRegressionTests;
var LPassed,LFailed:Integer;
  procedure Check(const AName:string;const AWire:TBytes;const AExpected:string);
  var C:TCapture; I,J:Integer; S:string;
  begin
    for I:=1 to Length(AWire) do begin
      C:=TCapture.Create;
      try
        Feed(C.Parser,AWire,I);S:='';
        for J:=0 to High(C.Events) do S:=S+IntToStr(C.Events[J].Code)+':'+Hex(C.Events[J].Data)+';';
        if (S=AExpected) and (C.Failed=0) then Inc(LPassed) else begin
          Inc(LFailed);if LFailed<=5 then Writeln('FAIL ',AName,' chunk=',I,' actual=',S);
        end;
      finally C.Free; end;
    end;
  end;
begin
  LPassed:=0;LFailed:=0;
  Check('普通分片',TBytes.Create($01,$01,$41,$80,$01,$42),'1:4142;');
  Check('分片间Ping',TBytes.Create($01,$01,$41,$89,$01,$78,$80,$01,$42),'9:78;1:4142;');
  Check('空分片与连续控制帧',TBytes.Create($01,$00,$89,$00,$00,$00,$8A,$01,$79,$80,$00),'9:;10:79;1:;');
  Check('不同掩码',TBytes.Create($01,$81,$01,$02,$03,$04,$40,$89,$81,$05,$06,$07,$08,$7D,$80,$82,$09,$0A,$0B,$0C,$4B,$49),'9:78;1:414243;');
  Check('Close丢弃未完成消息',TBytes.Create($01,$01,$41,$88,$00,$80,$01,$42),'8:;');
  Check('Close后不再交付',TBytes.Create($88,$00,$81,$01,$42),'8:;');
  Writeln('WebSocket regression: ',LPassed,' passed, ',LFailed,' failed');
  if LFailed<>0 then raise Exception.Create('WebSocket回归失败');
  TestStrictParser;
  TestLegalMatrix;
end;
end.
