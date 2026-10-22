unit Crypt.SipHash;

{$I zLib.inc}
{$R-}
{$Q-}

// SipHash-2-4 伪随机函数 (PRF), 主要用于哈希表 DoS 防护
// 参考: https://en.wikipedia.org/wiki/SipHash
// 提供两种使用方式:
//   - SipHash24             : 一次性计算 (无状态, 任意数据)
//   - Init / Update / Final  : 流式计算 (TSipHashState 状态记录)
// 算法参数: 2 轮压缩 + 4 轮终结, 128 位密钥, 64 位输出

interface

type
  TSipHashState = record
    V0, V1, V2, V3: UInt64;
    TotalLength: UInt64;
    Buffer: array[0..7] of Byte;
    BufferLength: Integer;
  end;

procedure SipHashInit(var AState: TSipHashState; AKey0, AKey1: UInt64);
procedure SipHashUpdate(var AState: TSipHashState; const AData: PByte; ALength: NativeUInt);
function SipHashFinal(var AState: TSipHashState): UInt64;
function SipHash24(const AData; ALength: NativeUInt; AKey0, AKey1: UInt64): UInt64;

implementation

{$RANGECHECKS OFF}
{$OVERFLOWCHECKS OFF}

function Swap64(x: UInt64): UInt64; forward;

{ 安全读取64位小端序值 }
function ReadLE64(ABuf: Pointer): UInt64; inline;
begin
  {$IFDEF CPU_X86}
  Result := PUInt64(ABuf)^;
  {$ELSEIF defined(CPU_BIG_ENDIAN)}
  if ((NativeUInt(ABuf) and 7) = 0) then
    Result := Swap64(PUInt64(ABuf)^)
  else
  begin
    Move(ABuf^, Result, SizeOf(UInt64));
    Result := Swap64(Result);
  end;
  {$ELSE}
  if ((NativeUInt(ABuf) and 7) = 0) then
    Result := PUInt64(ABuf)^
  else
    Move(ABuf^, Result, SizeOf(UInt64));
  {$ENDIF}
end;

function RotateLeft64(AValue: UInt64; AShift: Integer): UInt64; inline;
begin
  Result := (AValue shl AShift) or (AValue shr (64 - AShift));
end;

procedure SipHashCompressBlocks(var AState: TSipHashState; AData: PByte;
  ABlockCount: NativeUInt);
var
  LV0, LV1, LV2, LV3, LBlock: UInt64;
  LRound: Integer;
begin
  // 调用处保证至少一个整块；局部状态不经 var 轮函数取地址。
  LV0 := AState.V0;
  LV1 := AState.V1;
  LV2 := AState.V2;
  LV3 := AState.V3;
  repeat
    LBlock := ReadLE64(AData);
    LV3 := LV3 xor LBlock;
    for LRound := 1 to 2 do
    begin
      LV0 := LV0 + LV1;
      LV2 := LV2 + LV3;
      LV1 := RotateLeft64(LV1, 13);
      LV3 := RotateLeft64(LV3, 16);
      LV1 := LV1 xor LV0;
      LV3 := LV3 xor LV2;
      LV0 := RotateLeft64(LV0, 32);
      LV2 := LV2 + LV1;
      LV0 := LV0 + LV3;
      LV1 := RotateLeft64(LV1, 17);
      LV3 := RotateLeft64(LV3, 21);
      LV1 := LV1 xor LV2;
      LV3 := LV3 xor LV0;
      LV2 := RotateLeft64(LV2, 32);
    end;
    LV0 := LV0 xor LBlock;
    Inc(AData, 8);
    Dec(ABlockCount);
  until ABlockCount = 0;
  AState.V0 := LV0;
  AState.V1 := LV1;
  AState.V2 := LV2;
  AState.V3 := LV3;
end;

procedure SipHashInit(var AState: TSipHashState; AKey0, AKey1: UInt64);
const
  C0 = UInt64($736f6d6570736575);
  C1 = UInt64($646f72616e646f6d);
  C2 = UInt64($6c7967656e657261);
  C3 = UInt64($7465646279746573);
begin
  AState.V0 := C0 xor AKey0;
  AState.V1 := C1 xor AKey1;
  AState.V2 := C2 xor AKey0;
  AState.V3 := C3 xor AKey1;
  AState.TotalLength := 0;
  AState.BufferLength := 0;
end;

procedure SipHashUpdate(var AState: TSipHashState; const AData: PByte; ALength: NativeUInt);
var
  LData: PByte;
  LBytesToCopy: NativeUInt;
begin
  if (AData = nil) or (ALength <= 0) then Exit;

  LData := AData;
  AState.TotalLength := AState.TotalLength + ALength;

  if AState.BufferLength > 0 then
  begin
    LBytesToCopy := 8 - AState.BufferLength;
    if LBytesToCopy > ALength then
      LBytesToCopy := ALength;

    Move(LData^, AState.Buffer[AState.BufferLength], LBytesToCopy);
    Inc(LData, LBytesToCopy);
    Dec(ALength, LBytesToCopy);
    AState.BufferLength := AState.BufferLength + Integer(LBytesToCopy);

    if AState.BufferLength = 8 then
    begin
      SipHashCompressBlocks(AState, @AState.Buffer[0], 1);
      AState.BufferLength := 0;
    end;
  end;

  if ALength >= 8 then
  begin
    LBytesToCopy := ALength and not NativeUInt(7);
    SipHashCompressBlocks(AState, LData, LBytesToCopy shr 3);
    Inc(LData, LBytesToCopy);
    Dec(ALength, LBytesToCopy);
  end;

  if ALength > 0 then
  begin
    Move(LData^, AState.Buffer, ALength);
    AState.BufferLength := Integer(ALength);
  end;
end;

function SipHashFinal(var AState: TSipHashState): UInt64;
var
  LFinalBlock: UInt64;
  LIdx, LRound: Integer;
  LV0, LV1, LV2, LV3: UInt64;
begin
  LFinalBlock := AState.TotalLength shl 56;

  if AState.BufferLength > 0 then
  begin
    for LIdx := AState.BufferLength to 7 do
      AState.Buffer[LIdx] := 0;
    LFinalBlock := ReadLE64(@AState.Buffer[0]);
    LFinalBlock := LFinalBlock or (UInt64(AState.TotalLength and $FF) shl 56);
  end;

  LV0 := AState.V0;
  LV1 := AState.V1;
  LV2 := AState.V2;
  LV3 := AState.V3;

  LV3 := LV3 xor LFinalBlock;
  for LRound := 1 to 2 do
  begin
    LV0 := LV0 + LV1;
    LV2 := LV2 + LV3;
    LV1 := RotateLeft64(LV1, 13);
    LV3 := RotateLeft64(LV3, 16);
    LV1 := LV1 xor LV0;
    LV3 := LV3 xor LV2;
    LV0 := RotateLeft64(LV0, 32);
    LV2 := LV2 + LV1;
    LV0 := LV0 + LV3;
    LV1 := RotateLeft64(LV1, 17);
    LV3 := RotateLeft64(LV3, 21);
    LV1 := LV1 xor LV2;
    LV3 := LV3 xor LV0;
    LV2 := RotateLeft64(LV2, 32);
  end;
  LV0 := LV0 xor LFinalBlock;

  LV2 := LV2 xor $FF;

  for LRound := 1 to 4 do
  begin
    LV0 := LV0 + LV1;
    LV2 := LV2 + LV3;
    LV1 := RotateLeft64(LV1, 13);
    LV3 := RotateLeft64(LV3, 16);
    LV1 := LV1 xor LV0;
    LV3 := LV3 xor LV2;
    LV0 := RotateLeft64(LV0, 32);
    LV2 := LV2 + LV1;
    LV0 := LV0 + LV3;
    LV1 := RotateLeft64(LV1, 17);
    LV3 := RotateLeft64(LV3, 21);
    LV1 := LV1 xor LV2;
    LV3 := LV3 xor LV0;
    LV2 := RotateLeft64(LV2, 32);
  end;

  AState.V0 := LV0;
  AState.V1 := LV1;
  AState.V2 := LV2;
  AState.V3 := LV3;

  Result := LV0 xor LV1 xor LV2 xor LV3;
end;

function SipHash24(const AData; ALength: NativeUInt; AKey0, AKey1: UInt64): UInt64;
var
  LState: TSipHashState;
begin
  SipHashInit(LState, AKey0, AKey1);
  SipHashUpdate(LState, @AData, ALength);
  Result := SipHashFinal(LState);
end;

{ 64位整数字节序交换 }
function Swap64(x: UInt64): UInt64; inline;
begin
  Result := ((x and UInt64($00000000000000FF)) shl 56) or
            ((x and UInt64($000000000000FF00)) shl 40) or
            ((x and UInt64($0000000000FF0000)) shl 24) or
            ((x and UInt64($00000000FF000000)) shl 8) or
            ((x and UInt64($000000FF00000000)) shr 8) or
            ((x and UInt64($0000FF0000000000)) shr 24) or
            ((x and UInt64($00FF000000000000)) shr 40) or
            ((x and UInt64($FF00000000000000)) shr 56);
end;

end.
