unit Crypt.MurmurHash;

{$I zLib.inc}
{$R-}
{$Q-}

// MurmurHash3 非加密哈希算法
// 参考: https://en.wikipedia.org/wiki/MurmurHash
// 提供三种变体:
//   - MurmurHash3_x86_32   : 32 位输出 (x86 优化)
//   - MurmurHash3_x86_128  : 128 位输出 (x86 优化, 返回 TArray<UInt32>)
//   - MurmurHash3_x64_128  : 128 位输出 (x64 优化, 返回 TArray<UInt64>)
// 每种变体均提供一次性计算函数和流式 (Init/Update/Final) 接口
// Final 不修改上下文，可重复读取摘要，之后仍可继续 Update；新计算需调用 Init。
// 每次 Update 最多接收 High(UInt32) 字节，x64_128 使用 64 位累计长度。
// x64_128 上下文的 Length 已扩展为 UInt64，使用该记录的单元需重新编译。

interface

type
  // Fixed-size numeric words in H1, H2[, H3, H4] order; no managed fields.
  TMurmurHash3_x86_128Digest = array[0..3] of UInt32;
  TMurmurHash3_x64_128Digest = array[0..1] of UInt64;

  TMurmurHash3_x86_32Context = record
    H1: UInt32;
    Length: UInt32;
    Tail: array [0 .. 3] of Byte;
    Count: UInt32;
  end;

  TMurmurHash3_x86_128Context = record
    H1, H2, H3, H4: UInt32;
    Length: UInt32;
    Tail: array [0 .. 15] of Byte;
    Count: UInt32;
  end;

  TMurmurHash3_x64_128Context = record
    H1, H2: UInt64;
    Length: UInt64;
    Tail: array [0 .. 15] of Byte;
    Count: UInt32;
  end;

// 无分配接口：结果为固定数组；FinalDigest 不修改上下文。
// Digest 对 nil + 非零长度返回全零；原有动态数组接口仍返回 nil。
function MurmurHash3_x86_128Digest(AData: Pointer; ALength: UInt32;
  ASeed: UInt32 = 0): TMurmurHash3_x86_128Digest;
function MurmurHash3_x64_128Digest(AData: Pointer; ALength: UInt32;
  ASeed: UInt32 = 0): TMurmurHash3_x64_128Digest;
function MurmurHash3_x86_128FinalDigest(
  const AContext: TMurmurHash3_x86_128Context): TMurmurHash3_x86_128Digest;
function MurmurHash3_x64_128FinalDigest(
  const AContext: TMurmurHash3_x64_128Context): TMurmurHash3_x64_128Digest;

function MurmurHash3_x86_32(AData: Pointer; ALength: UInt32; ASeed: UInt32 = 0): UInt32;
function MurmurHash3_x86_128(AData: Pointer; ALength: UInt32; ASeed: UInt32 = 0): TArray<UInt32>;
function MurmurHash3_x64_128(AData: Pointer; ALength: UInt32; ASeed: UInt32 = 0): TArray<UInt64>;

procedure MurmurHash3_x86_32Init(var AContext: TMurmurHash3_x86_32Context; ASeed: UInt32 = 0);
procedure MurmurHash3_x86_32Update(var AContext: TMurmurHash3_x86_32Context; AData: Pointer; ALength: UInt32);
function MurmurHash3_x86_32Final(var AContext: TMurmurHash3_x86_32Context): UInt32;

procedure MurmurHash3_x86_128Init(var AContext: TMurmurHash3_x86_128Context; ASeed: UInt32 = 0);
procedure MurmurHash3_x86_128Update(var AContext: TMurmurHash3_x86_128Context; AData: Pointer; ALength: UInt32);
function MurmurHash3_x86_128Final(var AContext: TMurmurHash3_x86_128Context): TArray<UInt32>;

procedure MurmurHash3_x64_128Init(var AContext: TMurmurHash3_x64_128Context; ASeed: UInt32 = 0);
procedure MurmurHash3_x64_128Update(var AContext: TMurmurHash3_x64_128Context; AData: Pointer; ALength: UInt32);
function MurmurHash3_x64_128Final(var AContext: TMurmurHash3_x64_128Context): TArray<UInt64>;

implementation

type
  PMurmurHash3_x86_128Digest = ^TMurmurHash3_x86_128Digest;
  PMurmurHash3_x64_128Digest = ^TMurmurHash3_x64_128Digest;

const
  C1_32  = UInt32($CC9E2D51);
  C2_32  = UInt32($1B873593);
  C1_128 = UInt32($239B961B);
  C2_128 = UInt32($AB0E9789);
  C3_128 = UInt32($38B34AE5);
  C4_128 = UInt32($A1E38B93);
  C1_x64 = UInt64($87C37B91114253D5);
  C2_x64 = UInt64($4CF5AD432745937F);

function FMix32(AH: UInt32): UInt32; inline;
begin
  AH := AH xor (AH shr 16);
  AH := AH * $85EBCA6B;
  AH := AH xor (AH shr 13);
  AH := AH * $C2B2AE35;
  AH := AH xor (AH shr 16);
  Result := AH;
end;

function FMix64(AH: UInt64): UInt64; inline;
begin
  AH := AH xor (AH shr 33);
  AH := AH * $FF51AFD7ED558CCD;
  AH := AH xor (AH shr 33);
  AH := AH * $C4CEB9FE1A85EC53;
  AH := AH xor (AH shr 33);
  Result := AH;
end;

function Swap32(x: UInt32): UInt32; forward;
function Swap64(x: UInt64): UInt64; forward;

function Rotl32(const AValue: UInt32; AShift: Byte): UInt32; inline;
begin
  Result := (AValue shl AShift) or (AValue shr (32 - AShift));
end;

function Rotl64(const AValue: UInt64; AShift: Byte): UInt64; inline;
begin
  Result := (AValue shl AShift) or (AValue shr (64 - AShift));
end;

function ReadLE32(ABuf: Pointer): UInt32; inline;
begin
  { x86 原生 LE + 硬件非对齐；大端需字节交换；其他 LE 对齐判断 }
  {$IFDEF CPU_X86}
  Result := PUInt32(ABuf)^;
  {$ELSEIF defined(CPU_BIG_ENDIAN)}
  if ((NativeUInt(ABuf) and 3) = 0) then
    Result := Swap32(PUInt32(ABuf)^)
  else
  begin
    Move(ABuf^, Result, SizeOf(UInt32));
    Result := Swap32(Result);
  end;
  {$ELSE}
  if ((NativeUInt(ABuf) and 3) = 0) then
    Result := PUInt32(ABuf)^
  else
    Move(ABuf^, Result, SizeOf(UInt32));
  {$ENDIF}
end;

function ReadLE64(ABuf: Pointer): UInt64; inline;
begin
  { x86 原生 LE + 硬件非对齐；大端需字节交换；其他 LE 对齐判断 }
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

{ 32位整数字节序交换 }
function Swap32(x: UInt32): UInt32; inline;
begin
  Result := ((x and UInt32($000000FF)) shl 24) or
            ((x and UInt32($0000FF00)) shl 8) or
            ((x and UInt32($00FF0000)) shr 8) or
            ((x and UInt32($FF000000)) shr 24);
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

function MurmurHash3_x86_32(AData: Pointer; ALength: UInt32; ASeed: UInt32): UInt32;
var
  LContext: TMurmurHash3_x86_32Context;
begin
  if (AData = nil) and (ALength > 0) then begin Result := 0; Exit; end;
  MurmurHash3_x86_32Init(LContext, ASeed);
  MurmurHash3_x86_32Update(LContext, AData, ALength);
  Result := MurmurHash3_x86_32Final(LContext);
end;

function MurmurHash3_x86_128(AData: Pointer; ALength: UInt32; ASeed: UInt32): TArray<UInt32>;
var
  LContext: TMurmurHash3_x86_128Context;
begin
  if (AData = nil) and (ALength > 0) then begin Result := nil; Exit; end;
  MurmurHash3_x86_128Init(LContext, ASeed);
  MurmurHash3_x86_128Update(LContext, AData, ALength);
  Result := MurmurHash3_x86_128Final(LContext);
end;

function MurmurHash3_x86_128Digest(AData: Pointer; ALength: UInt32;
  ASeed: UInt32): TMurmurHash3_x86_128Digest;
var
  LContext: TMurmurHash3_x86_128Context;
begin
  if (AData = nil) and (ALength > 0) then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Exit;
  end;
  MurmurHash3_x86_128Init(LContext, ASeed);
  MurmurHash3_x86_128Update(LContext, AData, ALength);
  Result := MurmurHash3_x86_128FinalDigest(LContext);
end;

function MurmurHash3_x64_128(AData: Pointer; ALength: UInt32; ASeed: UInt32): TArray<UInt64>;
var
  LContext: TMurmurHash3_x64_128Context;
begin
  if (AData = nil) and (ALength > 0) then begin Result := nil; Exit; end;
  MurmurHash3_x64_128Init(LContext, ASeed);
  MurmurHash3_x64_128Update(LContext, AData, ALength);
  Result := MurmurHash3_x64_128Final(LContext);
end;

function MurmurHash3_x64_128Digest(AData: Pointer; ALength: UInt32;
  ASeed: UInt32): TMurmurHash3_x64_128Digest;
var
  LContext: TMurmurHash3_x64_128Context;
begin
  if (AData = nil) and (ALength > 0) then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Exit;
  end;
  MurmurHash3_x64_128Init(LContext, ASeed);
  MurmurHash3_x64_128Update(LContext, AData, ALength);
  Result := MurmurHash3_x64_128FinalDigest(LContext);
end;

procedure MurmurHash3_x86_32Init(var AContext: TMurmurHash3_x86_32Context;
  ASeed: UInt32 = 0);
begin
  AContext.H1 := ASeed;
  AContext.Length := 0;
  AContext.Count := 0;
  FillChar(AContext.Tail[0], SizeOf(AContext.Tail), 0);
end;

procedure MurmurHash3_x86_32Block(var AContext: TMurmurHash3_x86_32Context;
  ABlock: PByte); inline;
var
  LData: UInt32;
begin
  LData := ReadLE32(ABlock);
  LData := LData * C1_32;
  LData := Rotl32(LData, 15);
  LData := LData * C2_32;
  AContext.H1 := AContext.H1 xor LData;
  AContext.H1 := Rotl32(AContext.H1, 13);
  AContext.H1 := AContext.H1 * 5 + $E6546B64;
end;

procedure MurmurHash3_x86_32Update(var AContext: TMurmurHash3_x86_32Context;
  AData: Pointer; ALength: UInt32);
var
  LData: PByte;
  LRemaining: UInt32;
begin
  if (AData = nil) or (ALength <= 0) then Exit;

  LData := AData;
  LRemaining := ALength;

  if (AContext.Count > 0) then
  begin
    while (LRemaining > 0) and (AContext.Count < 4) do
    begin
      AContext.Tail[AContext.Count] := LData^;
      Inc(LData);
      Dec(LRemaining);
      Inc(AContext.Count);
      Inc(AContext.Length);
    end;

    if (AContext.Count = 4) then
    begin
      MurmurHash3_x86_32Block(AContext, @AContext.Tail[0]);

      AContext.Count := 0;
    end;
  end;

  while (LRemaining >= 4) do
  begin
    MurmurHash3_x86_32Block(AContext, LData);

    Inc(LData, 4);
    Dec(LRemaining, 4);
    Inc(AContext.Length, 4);
  end;

  if (LRemaining > 0) then
  begin
    Inc(AContext.Length, LRemaining);
    AContext.Count := LRemaining;
    Move(LData^, AContext.Tail[0], LRemaining);
  end;
end;

function MurmurHash3_x86_32Final(var AContext: TMurmurHash3_x86_32Context): UInt32;
var
  LH1, LK: UInt32;
begin
  LH1 := AContext.H1;

  if (AContext.Count > 0) then
  begin
    LK := 0;

    case AContext.Count of
      3:
        begin
          LK := LK xor (UInt32(AContext.Tail[2]) shl 16);
          LK := LK xor (UInt32(AContext.Tail[1]) shl 8);
          LK := LK xor UInt32(AContext.Tail[0]);
        end;

      2:
        begin
          LK := LK xor (UInt32(AContext.Tail[1]) shl 8);
          LK := LK xor UInt32(AContext.Tail[0]);
        end;

      1:
        begin
          LK := LK xor UInt32(AContext.Tail[0]);
        end;
    end;

    LK := LK * C1_32;
    LK := Rotl32(LK, 15);
    LK := LK * C2_32;
    LH1 := LH1 xor LK;
  end;

  LH1 := LH1 xor AContext.Length;
  LH1 := FMix32(LH1);

  Result := LH1;
end;

procedure MurmurHash3_x86_128Init(var AContext: TMurmurHash3_x86_128Context;
  ASeed: UInt32 = 0);
begin
  AContext.H1 := ASeed;
  AContext.H2 := ASeed;
  AContext.H3 := ASeed;
  AContext.H4 := ASeed;
  AContext.Length := 0;
  AContext.Count := 0;
  FillChar(AContext.Tail[0], SizeOf(AContext.Tail), 0);
end;

procedure MurmurHash3_x86_128Block(var AContext: TMurmurHash3_x86_128Context;
  ABlock: PByte); inline;
var
  LK1, LK2, LK3, LK4: UInt32;
begin
  LK1 := ReadLE32(ABlock + 0);
  LK2 := ReadLE32(ABlock + 4);
  LK3 := ReadLE32(ABlock + 8);
  LK4 := ReadLE32(ABlock + 12);

  LK1 := LK1 * C1_128;
  LK1 := Rotl32(LK1, 15);
  LK1 := LK1 * C2_128;
  AContext.H1 := AContext.H1 xor LK1;
  AContext.H1 := Rotl32(AContext.H1, 19);
  AContext.H1 := AContext.H1 + AContext.H2;
  AContext.H1 := AContext.H1 * 5 + $561CCD1B;

  LK2 := LK2 * C2_128;
  LK2 := Rotl32(LK2, 16);
  LK2 := LK2 * C3_128;
  AContext.H2 := AContext.H2 xor LK2;
  AContext.H2 := Rotl32(AContext.H2, 17);
  AContext.H2 := AContext.H2 + AContext.H3;
  AContext.H2 := AContext.H2 * 5 + $0BCAA747;

  LK3 := LK3 * C3_128;
  LK3 := Rotl32(LK3, 17);
  LK3 := LK3 * C4_128;
  AContext.H3 := AContext.H3 xor LK3;
  AContext.H3 := Rotl32(AContext.H3, 15);
  AContext.H3 := AContext.H3 + AContext.H4;
  AContext.H3 := AContext.H3 * 5 + $96CD1C35;

  LK4 := LK4 * C4_128;
  LK4 := Rotl32(LK4, 18);
  LK4 := LK4 * C1_128;
  AContext.H4 := AContext.H4 xor LK4;
  AContext.H4 := Rotl32(AContext.H4, 13);
  AContext.H4 := AContext.H4 + AContext.H1;
  AContext.H4 := AContext.H4 * 5 + $32AC3B17;
end;

procedure MurmurHash3_x86_128Update(var AContext: TMurmurHash3_x86_128Context;
  AData: Pointer; ALength: UInt32);
var
  LData: PByte;
  LRemaining, LNeeded: UInt32;
  {$IF not (defined(DELPHI) and defined(CPUX86))}
  LH1, LH2, LH3, LH4, LK1, LK2, LK3, LK4: UInt32;
  {$ENDIF}
begin
  if (AData = nil) or (ALength <= 0) then Exit;

  Inc(AContext.Length, ALength);
  LData := AData;
  LRemaining := ALength;

  if (AContext.Count > 0) then
  begin
    LNeeded := 16 - AContext.Count;
    if LNeeded > LRemaining then LNeeded := LRemaining;
    Move(LData^, AContext.Tail[AContext.Count], LNeeded);
    Inc(LData, LNeeded);
    Dec(LRemaining, LNeeded);
    Inc(AContext.Count, LNeeded);

    if AContext.Count = 16 then
    begin
      MurmurHash3_x86_128Block(AContext, @AContext.Tail[0]);
      AContext.Count := 0;
    end;
  end;

  {$IF defined(DELPHI) and defined(CPUX86)}
  // Delphi Win32 performs better with the context-based loop.
  while LRemaining >= 16 do
  begin
    MurmurHash3_x86_128Block(AContext, LData);
    Inc(LData, 16);
    Dec(LRemaining, 16);
  end;
  {$ELSE}
  // Keep the running hash in locals throughout the full-block loop.
  if LRemaining >= 16 then
  begin
    LH1 := AContext.H1;
    LH2 := AContext.H2;
    LH3 := AContext.H3;
    LH4 := AContext.H4;
    while LRemaining >= 16 do
    begin
      LK1 := ReadLE32(LData + 0);
      LK2 := ReadLE32(LData + 4);
      LK3 := ReadLE32(LData + 8);
      LK4 := ReadLE32(LData + 12);

      LK1 := LK1 * C1_128;
      LK1 := Rotl32(LK1, 15);
      LK1 := LK1 * C2_128;
      LH1 := LH1 xor LK1;
      LH1 := Rotl32(LH1, 19);
      LH1 := LH1 + LH2;
      LH1 := LH1 * 5 + $561CCD1B;

      LK2 := LK2 * C2_128;
      LK2 := Rotl32(LK2, 16);
      LK2 := LK2 * C3_128;
      LH2 := LH2 xor LK2;
      LH2 := Rotl32(LH2, 17);
      LH2 := LH2 + LH3;
      LH2 := LH2 * 5 + $0BCAA747;

      LK3 := LK3 * C3_128;
      LK3 := Rotl32(LK3, 17);
      LK3 := LK3 * C4_128;
      LH3 := LH3 xor LK3;
      LH3 := Rotl32(LH3, 15);
      LH3 := LH3 + LH4;
      LH3 := LH3 * 5 + $96CD1C35;

      LK4 := LK4 * C4_128;
      LK4 := Rotl32(LK4, 18);
      LK4 := LK4 * C1_128;
      LH4 := LH4 xor LK4;
      LH4 := Rotl32(LH4, 13);
      LH4 := LH4 + LH1;
      LH4 := LH4 * 5 + $32AC3B17;
      Inc(LData, 16);
      Dec(LRemaining, 16);
    end;
    AContext.H1 := LH1;
    AContext.H2 := LH2;
    AContext.H3 := LH3;
    AContext.H4 := LH4;
  end;
  {$ENDIF}

  if (LRemaining > 0) then
  begin
    AContext.Count := LRemaining;
    Move(LData^, AContext.Tail[0], LRemaining);
  end;
end;

function MurmurHash3_x86_128Final(var AContext: TMurmurHash3_x86_128Context): TArray<UInt32>;
begin
  Result := nil;
  SetLength(Result, 4);
  // The four words have the same layout; write directly into the allocated result.
  PMurmurHash3_x86_128Digest(@Result[0])^ := MurmurHash3_x86_128FinalDigest(AContext);
end;

function MurmurHash3_x86_128FinalDigest(
  const AContext: TMurmurHash3_x86_128Context): TMurmurHash3_x86_128Digest;
var
  LH1, LH2, LH3, LH4: UInt32;
  LK1, LK2, LK3, LK4: UInt32;
begin
  LH1 := AContext.H1;
  LH2 := AContext.H2;
  LH3 := AContext.H3;
  LH4 := AContext.H4;

  if (AContext.Count > 0) then
  begin
    LK1 := 0;
    LK2 := 0;
    LK3 := 0;
    LK4 := 0;

    case AContext.Count of
      15:
        begin
          LK4 := LK4 xor (UInt32(AContext.Tail[14]) shl 16);
          LK4 := LK4 xor (UInt32(AContext.Tail[13]) shl 8);
          LK4 := LK4 xor UInt32(AContext.Tail[12]);
          LK4 := LK4 * C4_128;
          LK4 := Rotl32(LK4, 18);
          LK4 := LK4 * C1_128;
          LH4 := LH4 xor LK4;

          LK3 := LK3 xor (UInt32(AContext.Tail[11]) shl 24);
          LK3 := LK3 xor (UInt32(AContext.Tail[10]) shl 16);
          LK3 := LK3 xor (UInt32(AContext.Tail[9]) shl 8);
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      14:
        begin
          LK4 := LK4 xor (UInt32(AContext.Tail[13]) shl 8);
          LK4 := LK4 xor UInt32(AContext.Tail[12]);
          LK4 := LK4 * C4_128;
          LK4 := Rotl32(LK4, 18);
          LK4 := LK4 * C1_128;
          LH4 := LH4 xor LK4;

          LK3 := LK3 xor (UInt32(AContext.Tail[11]) shl 24);
          LK3 := LK3 xor (UInt32(AContext.Tail[10]) shl 16);
          LK3 := LK3 xor (UInt32(AContext.Tail[9]) shl 8);
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      13:
        begin
          LK4 := LK4 xor UInt32(AContext.Tail[12]);
          LK4 := LK4 * C4_128;
          LK4 := Rotl32(LK4, 18);
          LK4 := LK4 * C1_128;
          LH4 := LH4 xor LK4;

          LK3 := LK3 xor (UInt32(AContext.Tail[11]) shl 24);
          LK3 := LK3 xor (UInt32(AContext.Tail[10]) shl 16);
          LK3 := LK3 xor (UInt32(AContext.Tail[9]) shl 8);
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      12:
        begin
          LK3 := LK3 xor (UInt32(AContext.Tail[11]) shl 24);
          LK3 := LK3 xor (UInt32(AContext.Tail[10]) shl 16);
          LK3 := LK3 xor (UInt32(AContext.Tail[9]) shl 8);
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      11:
        begin
          LK3 := LK3 xor (UInt32(AContext.Tail[10]) shl 16);
          LK3 := LK3 xor (UInt32(AContext.Tail[9]) shl 8);
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      10:
        begin
          LK3 := LK3 xor (UInt32(AContext.Tail[9]) shl 8);
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      9:
        begin
          LK3 := LK3 xor UInt32(AContext.Tail[8]);
          LK3 := LK3 * C3_128;
          LK3 := Rotl32(LK3, 17);
          LK3 := LK3 * C4_128;
          LH3 := LH3 xor LK3;

          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      8:
        begin
          LK2 := LK2 xor (UInt32(AContext.Tail[7]) shl 24);
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      7:
        begin
          LK2 := LK2 xor (UInt32(AContext.Tail[6]) shl 16);
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      6:
        begin
          LK2 := LK2 xor (UInt32(AContext.Tail[5]) shl 8);
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      5:
        begin
          LK2 := LK2 xor UInt32(AContext.Tail[4]);
          LK2 := LK2 * C2_128;
          LK2 := Rotl32(LK2, 16);
          LK2 := LK2 * C3_128;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      4:
        begin
          LK1 := LK1 xor (UInt32(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      3:
        begin
          LK1 := LK1 xor (UInt32(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      2:
        begin
          LK1 := LK1 xor (UInt32(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;

      1:
        begin
          LK1 := LK1 xor UInt32(AContext.Tail[0]);
          LK1 := LK1 * C1_128;
          LK1 := Rotl32(LK1, 15);
          LK1 := LK1 * C2_128;
          LH1 := LH1 xor LK1;
        end;
    end;
  end;

  LH1 := LH1 xor AContext.Length;
  LH2 := LH2 xor AContext.Length;
  LH3 := LH3 xor AContext.Length;
  LH4 := LH4 xor AContext.Length;

  LH1 := LH1 + LH2 + LH3 + LH4;
  LH2 := LH2 + LH1;
  LH3 := LH3 + LH1;
  LH4 := LH4 + LH1;

  LH1 := FMix32(LH1);
  LH2 := FMix32(LH2);
  LH3 := FMix32(LH3);
  LH4 := FMix32(LH4);

  LH1 := LH1 + LH2 + LH3 + LH4;
  LH2 := LH2 + LH1;
  LH3 := LH3 + LH1;
  LH4 := LH4 + LH1;

  Result[0] := LH1;
  Result[1] := LH2;
  Result[2] := LH3;
  Result[3] := LH4;
end;

procedure MurmurHash3_x64_128Init(var AContext: TMurmurHash3_x64_128Context;
  ASeed: UInt32 = 0);
begin
  AContext.H1 := ASeed;
  AContext.H2 := ASeed;
  AContext.Length := 0;
  AContext.Count := 0;
  FillChar(AContext.Tail[0], SizeOf(AContext.Tail), 0);
end;

procedure MurmurHash3_x64_128Block(var AContext: TMurmurHash3_x64_128Context; ABlock: PByte); inline;
var
  LK1, LK2: UInt64;
begin
  LK1 := ReadLE64(ABlock);
  LK2 := ReadLE64(ABlock + 8);

  LK1 := LK1 * C1_x64;
  LK1 := Rotl64(LK1, 31);
  LK1 := LK1 * C2_x64;
  AContext.H1 := AContext.H1 xor LK1;
  AContext.H1 := Rotl64(AContext.H1, 27);
  AContext.H1 := AContext.H1 + AContext.H2;
  AContext.H1 := AContext.H1 * 5 + $52DCE729;

  LK2 := LK2 * C2_x64;
  LK2 := Rotl64(LK2, 33);
  LK2 := LK2 * C1_x64;
  AContext.H2 := AContext.H2 xor LK2;
  AContext.H2 := Rotl64(AContext.H2, 31);
  AContext.H2 := AContext.H2 + AContext.H1;
  AContext.H2 := AContext.H2 * 5 + $38495AB5;
end;

procedure MurmurHash3_x64_128Update(var AContext: TMurmurHash3_x64_128Context;
  AData: Pointer; ALength: UInt32);
var
  LData: PByte;
  LRemaining, LNeeded: UInt32;
  LH1, LH2, LK1, LK2: UInt64;
begin
  if (AData = nil) or (ALength <= 0) then Exit;

  Inc(AContext.Length, ALength);
  LData := AData;
  LRemaining := ALength;

  if (AContext.Count > 0) then
  begin
    LNeeded := 16 - AContext.Count;
    if LNeeded > LRemaining then LNeeded := LRemaining;
    Move(LData^, AContext.Tail[AContext.Count], LNeeded);
    Inc(LData, LNeeded);
    Dec(LRemaining, LNeeded);
    Inc(AContext.Count, LNeeded);

    if AContext.Count = 16 then
    begin
      MurmurHash3_x64_128Block(AContext, @AContext.Tail[0]);

      AContext.Count := 0;
    end;
  end;

  // Keep the running hash in locals throughout the full-block loop.
  if LRemaining >= 16 then
  begin
    LH1 := AContext.H1;
    LH2 := AContext.H2;
    while LRemaining >= 16 do
    begin
      LK1 := ReadLE64(LData);
      LK2 := ReadLE64(LData + 8);

      LK1 := LK1 * C1_x64;
      LK1 := Rotl64(LK1, 31);
      LK1 := LK1 * C2_x64;
      LH1 := LH1 xor LK1;
      LH1 := Rotl64(LH1, 27);
      LH1 := LH1 + LH2;
      LH1 := LH1 * 5 + $52DCE729;

      LK2 := LK2 * C2_x64;
      LK2 := Rotl64(LK2, 33);
      LK2 := LK2 * C1_x64;
      LH2 := LH2 xor LK2;
      LH2 := Rotl64(LH2, 31);
      LH2 := LH2 + LH1;
      LH2 := LH2 * 5 + $38495AB5;
      Inc(LData, 16);
      Dec(LRemaining, 16);
    end;
    AContext.H1 := LH1;
    AContext.H2 := LH2;
  end;

  if (LRemaining > 0) then
  begin
    AContext.Count := LRemaining;
    Move(LData^, AContext.Tail[0], LRemaining);
  end;
end;

function MurmurHash3_x64_128Final(var AContext: TMurmurHash3_x64_128Context): TArray<UInt64>;
begin
  Result := nil;
  SetLength(Result, 2);
  // The two words have the same layout; write directly into the allocated result.
  PMurmurHash3_x64_128Digest(@Result[0])^ := MurmurHash3_x64_128FinalDigest(AContext);
end;

function MurmurHash3_x64_128FinalDigest(
  const AContext: TMurmurHash3_x64_128Context): TMurmurHash3_x64_128Digest;
var
  LH1, LH2: UInt64;
  LK1, LK2: UInt64;
begin
  LH1 := AContext.H1;
  LH2 := AContext.H2;

  if (AContext.Count > 0) then
  begin
    LK1 := 0;
    LK2 := 0;

    case AContext.Count of
      15:
        begin
          LK2 := LK2 xor (UInt64(AContext.Tail[14]) shl 48);
          LK2 := LK2 xor (UInt64(AContext.Tail[13]) shl 40);
          LK2 := LK2 xor (UInt64(AContext.Tail[12]) shl 32);
          LK2 := LK2 xor (UInt64(AContext.Tail[11]) shl 24);
          LK2 := LK2 xor (UInt64(AContext.Tail[10]) shl 16);
          LK2 := LK2 xor (UInt64(AContext.Tail[9]) shl 8);
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      14:
        begin
          LK2 := LK2 xor (UInt64(AContext.Tail[13]) shl 40);
          LK2 := LK2 xor (UInt64(AContext.Tail[12]) shl 32);
          LK2 := LK2 xor (UInt64(AContext.Tail[11]) shl 24);
          LK2 := LK2 xor (UInt64(AContext.Tail[10]) shl 16);
          LK2 := LK2 xor (UInt64(AContext.Tail[9]) shl 8);
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      13:
        begin
          LK2 := LK2 xor (UInt64(AContext.Tail[12]) shl 32);
          LK2 := LK2 xor (UInt64(AContext.Tail[11]) shl 24);
          LK2 := LK2 xor (UInt64(AContext.Tail[10]) shl 16);
          LK2 := LK2 xor (UInt64(AContext.Tail[9]) shl 8);
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      12:
        begin
          LK2 := LK2 xor (UInt64(AContext.Tail[11]) shl 24);
          LK2 := LK2 xor (UInt64(AContext.Tail[10]) shl 16);
          LK2 := LK2 xor (UInt64(AContext.Tail[9]) shl 8);
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      11:
        begin
          LK2 := LK2 xor (UInt64(AContext.Tail[10]) shl 16);
          LK2 := LK2 xor (UInt64(AContext.Tail[9]) shl 8);
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      10:
        begin
          LK2 := LK2 xor (UInt64(AContext.Tail[9]) shl 8);
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      9:
        begin
          LK2 := LK2 xor UInt64(AContext.Tail[8]);
          LK2 := LK2 * C2_x64;
          LK2 := Rotl64(LK2, 33);
          LK2 := LK2 * C1_x64;
          LH2 := LH2 xor LK2;

          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      8:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[7]) shl 56);
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      7:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[6]) shl 48);
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      6:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[5]) shl 40);
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      5:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[4]) shl 32);
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      4:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[3]) shl 24);
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      3:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[2]) shl 16);
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      2:
        begin
          LK1 := LK1 xor (UInt64(AContext.Tail[1]) shl 8);
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;

      1:
        begin
          LK1 := LK1 xor UInt64(AContext.Tail[0]);
          LK1 := LK1 * C1_x64;
          LK1 := Rotl64(LK1, 31);
          LK1 := LK1 * C2_x64;
          LH1 := LH1 xor LK1;
        end;
    end;

  end;

  LH1 := LH1 xor AContext.Length;
  LH2 := LH2 xor AContext.Length;

  LH1 := LH1 + LH2;
  LH2 := LH2 + LH1;

  LH1 := FMix64(LH1);
  LH2 := FMix64(LH2);

  LH1 := LH1 + LH2;
  LH2 := LH2 + LH1;

  Result[0] := LH1;
  Result[1] := LH2;
end;

end.
