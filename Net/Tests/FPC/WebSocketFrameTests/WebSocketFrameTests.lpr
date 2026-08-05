program WebSocketFrameTests;

{$I zLib.inc}

uses
  SysUtils
  ,Classes
  ,Net.CrossWebSocketParser
  ;

procedure Fail(const AMessage: string);
begin
  raise Exception.Create(AMessage);
end;

procedure AssertTrue(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    Fail(AMessage);
end;

procedure AssertBytesEqual(const AExpected, AActual: TBytes;
  const AMessage: string);
var
  I: Integer;
begin
  AssertTrue(Length(AExpected) = Length(AActual),
    Format('%s: length expected %d, actual %d', [
      AMessage, Length(AExpected), Length(AActual)]));
  for I := 0 to Length(AExpected) - 1 do
    AssertTrue(AExpected[I] = AActual[I],
      Format('%s: byte %d expected %d, actual %d', [
        AMessage, I, AExpected[I], AActual[I]]));
end;

function MakeData(const ASize: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, ASize);
  for I := 0 to ASize - 1 do
    Result[I] := Byte(I and $FF);
end;

procedure ReadFrameInfo(const AFrame: TBytes; out AMasked: Boolean;
  out AMaskOffset, APayloadOffset: Integer; out APayloadSize: UInt64);
var
  LPayload: Byte;
begin
  AssertTrue(Length(AFrame) >= 2, 'frame header is incomplete');

  AMasked := (AFrame[1] and $80) <> 0;
  LPayload := AFrame[1] and $7F;
  AMaskOffset := 2;
  if LPayload < 126 then
    APayloadSize := LPayload
  else
  if LPayload = 126 then
  begin
    AssertTrue(Length(AFrame) >= 4, '16-bit frame header is incomplete');
    APayloadSize := UInt64(AFrame[2]) shl 8 or AFrame[3];
    Inc(AMaskOffset, 2);
  end else
  begin
    AssertTrue(Length(AFrame) >= 10, '64-bit frame header is incomplete');
    APayloadSize := UInt64(AFrame[2]) shl 56
      or UInt64(AFrame[3]) shl 48
      or UInt64(AFrame[4]) shl 40
      or UInt64(AFrame[5]) shl 32
      or UInt64(AFrame[6]) shl 24
      or UInt64(AFrame[7]) shl 16
      or UInt64(AFrame[8]) shl 8
      or UInt64(AFrame[9]);
    Inc(AMaskOffset, 8);
  end;

  APayloadOffset := AMaskOffset;
  if AMasked then
    Inc(APayloadOffset, 4);
end;

function MakeFrame(const AOpCode: Byte; const AFin, AIsServer: Boolean;
  const AData: TBytes): TBytes;
var
  LData: Pointer;
begin
  if Length(AData) > 0 then
    LData := @AData[0]
  else
    LData := nil;
  Result := TCrossWebSocketParser.MakeFrameData(AOpCode, AFin, AIsServer,
    LData, Length(AData));
end;

procedure VerifyClientFrame(const AOpCode: Byte; const AFin: Boolean;
  const AData: TBytes);
var
  LFrame, LUnmasked: TBytes;
  LMasked: Boolean;
  LMaskOffset, LPayloadOffset, I: Integer;
  LPayloadSize: UInt64;
begin
  LFrame := MakeFrame(AOpCode, AFin, False, AData);
  ReadFrameInfo(LFrame, LMasked, LMaskOffset, LPayloadOffset, LPayloadSize);

  AssertTrue(LMasked, 'client frame must be masked');
  AssertTrue(LPayloadSize = UInt64(Length(AData)),
    'client frame payload length is incorrect');
  AssertTrue(Length(LFrame) = LPayloadOffset + Length(AData),
    'client frame total length is incorrect');

  SetLength(LUnmasked, Length(AData));
  for I := 0 to Length(AData) - 1 do
    LUnmasked[I] := LFrame[LPayloadOffset + I]
      xor LFrame[LMaskOffset + (I mod 4)];
  AssertBytesEqual(AData, LUnmasked, 'client frame payload');
end;

procedure TestFreshMaskingKeys;
const
  FRAME_COUNT = 16;
var
  LData, LFrame: TBytes;
  LFirstKey: array[0..3] of Byte;
  LMasked, LAllKeysEqual: Boolean;
  LMaskOffset, LPayloadOffset, I, J: Integer;
  LPayloadSize: UInt64;
begin
  LData := MakeData(32);
  LAllKeysEqual := True;
  for I := 0 to FRAME_COUNT - 1 do
  begin
    LFrame := MakeFrame(WS_OP_BINARY, True, False, LData);
    ReadFrameInfo(LFrame, LMasked, LMaskOffset, LPayloadOffset, LPayloadSize);
    AssertTrue(LMasked, 'client frame must be masked');

    if I = 0 then
      for J := 0 to 3 do
        LFirstKey[J] := LFrame[LMaskOffset + J]
    else
      for J := 0 to 3 do
        if LFirstKey[J] <> LFrame[LMaskOffset + J] then
        begin
          LAllKeysEqual := False;
          Break;
        end;
  end;

  AssertTrue(not LAllKeysEqual,
    'client frames must not reuse one connection-level masking key');
end;

procedure TestClientFrameKinds;
var
  LData: TBytes;
begin
  LData := MakeData(7);
  VerifyClientFrame(WS_OP_TEXT, True, LData);
  VerifyClientFrame(WS_OP_BINARY, False, LData);
  VerifyClientFrame(WS_OP_CONTINUATION, True, LData);
  VerifyClientFrame(WS_OP_CLOSE, True, nil);
  VerifyClientFrame(WS_OP_PING, True, nil);
  VerifyClientFrame(WS_OP_PONG, True, nil);
end;

procedure TestPayloadBoundaries;
const
  SIZES: array[0..3] of Integer = (125, 126, 65535, 65536);
var
  I: Integer;
begin
  for I := Low(SIZES) to High(SIZES) do
    VerifyClientFrame(WS_OP_BINARY, True, MakeData(SIZES[I]));
end;

procedure TestServerFrame;
var
  LData, LFrame, LPayload: TBytes;
  LMasked: Boolean;
  LMaskOffset, LPayloadOffset: Integer;
  LPayloadSize: UInt64;
begin
  LData := MakeData(32);
  LFrame := MakeFrame(WS_OP_BINARY, True, True, LData);
  ReadFrameInfo(LFrame, LMasked, LMaskOffset, LPayloadOffset, LPayloadSize);

  AssertTrue(not LMasked, 'server frame must not be masked');
  AssertTrue(LPayloadSize = UInt64(Length(LData)),
    'server frame payload length is incorrect');
  LPayload := Copy(LFrame, LPayloadOffset, Length(LData));
  AssertBytesEqual(LData, LPayload, 'server frame payload');
end;

procedure VerifyParserAccepts(const AFrame, AExpected: TBytes;
  const ADescription: string);
var
  LParser: TCrossWebSocketParser;
  LActual: TBytes;
  LBuffer: Pointer;
  LLength: Integer;
  LReceived, LFailed: Boolean;
begin
  LReceived := False;
  LFailed := False;
  LParser := TCrossWebSocketParser.Create(
    nil,
    procedure(const AType: TWsMessageType; const AData: TBytes)
    begin
      LReceived := True;
      LActual := Copy(AData, 0, Length(AData));
    end,
    procedure
    begin
      LFailed := True;
    end);
  try
    LBuffer := @AFrame[0];
    LLength := Length(AFrame);
    LParser.Decode(LBuffer, LLength);

    AssertTrue(not LFailed, ADescription + ': parser rejected frame');
    AssertTrue(LReceived, ADescription + ': parser did not emit message');
    AssertBytesEqual(AExpected, LActual, ADescription + ': decoded payload');
  finally
    LParser.Free;
  end;
end;

procedure TestPermissiveDecode;
var
  LData: TBytes;
begin
  LData := MakeData(16);
  VerifyParserAccepts(MakeFrame(WS_OP_BINARY, True, True, LData), LData,
    'unmasked frame');
  VerifyParserAccepts(MakeFrame(WS_OP_BINARY, True, False, LData), LData,
    'masked frame');
end;

begin
  try
    TestFreshMaskingKeys;
    TestClientFrameKinds;
    TestPayloadBoundaries;
    TestServerFrame;
    TestPermissiveDecode;
    Writeln('All WebSocket frame tests passed.');
  except
    on E: Exception do
    begin
      Writeln(StdErr, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
