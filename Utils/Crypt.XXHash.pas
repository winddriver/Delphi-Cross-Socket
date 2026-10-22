unit Crypt.XXHash;

{$I zLib.inc}
{$R-}
{$Q-}

{

  XXHash 高速非加密哈希算法实现

  - XXH32 (32 位):  单次  XXH32        流式  XXH32_init / XXH32_update / XXH32_final
  - XXH64 (64 位):  单次  XXH64        流式  XXH64_init / XXH64_update / XXH64_final
  - XXH3  (64 位):  单次  XXH3_64bits  流式  XXH3_64bits_init / XXH3_64bits_update / XXH3_64bits_final
  - XXH3  (128 位): 单次  XXH3_128bits 流式  XXH3_128bits_init / XXH3_128bits_update / XXH3_128bits_final

  支持默认种子、自定义种子 (seed) 及自定义密钥 (secret) 三种初始化方式

  注意:
  - 本算法为非加密哈希，不可用于密码存储、MAC、数字签名等安全场景
  - 流式 API (init/update/final) 非线程安全，多线程共享同一状态需外部同步
  - 外部密钥 (secret) 的生命周期必须覆盖从 init 到 final 的完整过程
}

interface

type
  { XXH32 哈希状态记录 }
  TXXH32_state_t = record
    TotalLen: UInt64;           // 总输入长度
    V1, V2, V3, V4: UInt32;     // 32位累加器
    Buf: array [0..15] of Byte; // 未处理数据缓冲区
    BufSize: UInt32;            // 缓冲区当前大小
  end;

  { XXH64 哈希状态记录 }
  TXXH64_state_t = record
    TotalLen: UInt64;           // 总输入长度
    V1, V2, V3, V4: UInt64;     // 64位累加器
    Buf: array [0..31] of Byte; // 未处理数据缓冲区
    BufSize: UInt32;            // 缓冲区当前大小
  end;

  { XXH3 哈希状态记录 }
  TXXH3_state_t = record
    acc: array[0..7] of UInt64;                // 8个64位累加器
    customSecret: array[0..191] of Byte;       // 自定义密钥缓冲区
    buffer: array[0..255] of Byte;             // 256字节内部缓冲区
    bufferedSize: UInt32;                      // 缓冲区中数据大小
    reserved32: UInt32;                        // 32位保留字段
    nbStripesSoFar: NativeInt;                 // 已处理的条带数
    totalLen: UInt64;                          // 总数据长度
    nbStripesPerBlock: NativeInt;              // 每个块的条带数
    secretLimit: NativeInt;                    // 密钥限制
    seed: UInt64;                              // 种子值
    reserved64: UInt64;                        // 64位保留字段
    extSecret: PByte;                          // 外部密钥指针（生命周期需覆盖 init→update→final）
  end;

  { 64位哈希值类型 }
  TXXH3_hash64_t = UInt64;

  { 128位哈希值类型 }
  TXXH3_hash128_t = record
    low64: UInt64;   // 低64位
    high64: UInt64;  // 高64位
  end;

const
  { 32位质数常量 }
  XXH_PRIME32_1 = UInt32($9E3779B1);
  XXH_PRIME32_2 = UInt32($85EBCA77);
  XXH_PRIME32_3 = UInt32($C2B2AE3D);
  XXH_PRIME32_4 = UInt32($27D4EB2F);
  XXH_PRIME32_5 = UInt32($165667B1);

  { 64位质数常量 }
  XXH_PRIME64_1 = UInt64($9E3779B185EBCA87);
  XXH_PRIME64_2 = UInt64($C2B2AE3D27D4EB4F);
  XXH_PRIME64_3 = UInt64($165667B19E3779F9);
  XXH_PRIME64_4 = UInt64($85EBCA77C2B2AE63);
  XXH_PRIME64_5 = UInt64($27D4EB2F165667C5);

  { 算法常量 }
  XXH_STRIPE_LEN = 64;                         // 条带长度
  XXH_SECRET_CONSUME_RATE = 8;                 // 密钥消耗率
  XXH3_SECRET_DEFAULT_SIZE = 192;              // 默认密钥大小
  XXH3_SECRET_SIZE_MIN = 136;                  // 最小密钥大小
  XXH3_INTERNALBUFFER_SIZE = 256;              // 内部缓冲区大小
  XXH3_MIDSIZE_MAX = 240;                      // 中等数据最大大小
  XXH_PRIME_MX2   = UInt64($9FB21C651E98DF25);  // PRIME32_1 * PRIME32_2

  { 默认密钥数据 }
  XXH3_kSecret: array[0..191] of Byte = (
    $b8, $fe, $6c, $39, $23, $a4, $4b, $be, $7c, $01, $81, $2c, $f7, $21, $ad, $1c,
    $de, $d4, $6d, $e9, $83, $90, $97, $db, $72, $40, $a4, $a4, $b7, $b3, $67, $1f,
    $cb, $79, $e6, $4e, $cc, $c0, $e5, $78, $82, $5a, $d0, $7d, $cc, $ff, $72, $21,
    $b8, $08, $46, $74, $f7, $43, $24, $8e, $e0, $35, $90, $e6, $81, $3a, $26, $4c,
    $3c, $28, $52, $bb, $91, $c3, $00, $cb, $88, $d0, $65, $8b, $1b, $53, $2e, $a3,
    $71, $64, $48, $97, $a2, $0d, $f9, $4e, $38, $19, $ef, $46, $a9, $de, $ac, $d8,
    $a8, $fa, $76, $3f, $e3, $9c, $34, $3f, $f9, $dc, $bb, $c7, $c7, $0b, $4f, $1d,
    $8a, $51, $e0, $4b, $cd, $b4, $59, $31, $c8, $9f, $7e, $c9, $d9, $78, $73, $64,
    $ea, $c5, $ac, $83, $34, $d3, $eb, $c3, $c5, $81, $a0, $ff, $fa, $13, $63, $eb,
    $17, $0d, $dd, $51, $b7, $f0, $da, $49, $d3, $16, $55, $26, $29, $d4, $68, $9e,
    $2b, $16, $be, $58, $7d, $47, $a1, $fc, $8f, $f8, $b8, $d1, $7a, $d0, $31, $ce,
    $45, $cb, $3a, $8f, $95, $16, $04, $28, $af, $d7, $fb, $ca, $bb, $4b, $40, $7e
  );

{ 64位哈希函数 }
function XXH3_64bits(input: Pointer; len: NativeInt): TXXH3_hash64_t; overload;
function XXH3_64bits(input: Pointer; len: NativeInt; seed: UInt64): TXXH3_hash64_t; overload;
function XXH3_64bits_withSecret(input: Pointer; len: NativeInt; secret: Pointer; secretSize: NativeInt): TXXH3_hash64_t;

{ 128位哈希函数 }
function XXH3_128bits(input: Pointer; len: NativeInt): TXXH3_hash128_t; overload;
function XXH3_128bits(input: Pointer; len: NativeInt; seed: UInt64): TXXH3_hash128_t; overload;
function XXH3_128bits_withSecret(input: Pointer; len: NativeInt; secret: Pointer; secretSize: NativeInt): TXXH3_hash128_t;

{ 64位增量计算接口 }
procedure XXH3_64bits_init(var state: TXXH3_state_t);
procedure XXH3_64bits_init_withSeed(var state: TXXH3_state_t; seed: UInt64);
procedure XXH3_64bits_update(var state: TXXH3_state_t; input: Pointer; len: NativeInt);
function XXH3_64bits_final(var state: TXXH3_state_t): TXXH3_hash64_t;

{ 128位增量计算接口 }
procedure XXH3_128bits_init(var state: TXXH3_state_t);
procedure XXH3_128bits_init_withSeed(var state: TXXH3_state_t; seed: UInt64);
procedure XXH3_128bits_update(var state: TXXH3_state_t; input: Pointer; len: NativeInt);
function XXH3_128bits_final(var state: TXXH3_state_t): TXXH3_hash128_t;

{ XXH32 初始化哈希状态 }
procedure XXH32_init(var AState: TXXH32_state_t; ASeed: UInt32 = 0);

{ XXH32 更新哈希状态 (处理新数据块) }
procedure XXH32_update(var AState: TXXH32_state_t; AInput: Pointer; AInputSize: NativeInt);

{ XXH32 计算最终哈希值 }
function XXH32_final(var AState: TXXH32_state_t): UInt32;

{ XXH32 单次哈希计算 (完整数据) }
function XXH32(AInput: Pointer; AInputSize: NativeInt; ASeed: UInt32 = 0): UInt32;

{ XXH64 初始化哈希状态 }
procedure XXH64_init(var AState: TXXH64_state_t; ASeed: UInt64 = 0);

{ XXH64 更新哈希状态 (处理新数据块) }
procedure XXH64_update(var AState: TXXH64_state_t; AInput: Pointer; AInputSize: NativeInt);

{ XXH64 计算最终哈希值 }
function XXH64_final(var AState: TXXH64_state_t): UInt64;

{ XXH64 单次哈希计算 (完整数据) }
function XXH64(AInput: Pointer; AInputSize: NativeInt; ASeed: UInt64 = 0): UInt64;

implementation

uses
  SysUtils;

{ 32位循环左移 }
function XXH_rotl32(AValue: UInt32; ACount: Integer): UInt32; inline;
begin
  Result := (AValue shl ACount) or (AValue shr (32 - ACount));
end;

function XXH_swap32(x: UInt32): UInt32; forward;
function XXH_swap64(x: UInt64): UInt64; forward;

{ 安全读取32位小端序值 }
function XXH_readLE32(ABuf: Pointer): UInt32; inline;
begin
  { x86 原生 LE + 硬件非对齐；大端需字节交换；其他 LE 对齐判断 }
  {$IFDEF CPU_X86}
  Result := PUInt32(ABuf)^;
  {$ELSEIF defined(CPU_BIG_ENDIAN)}
  if ((NativeUInt(ABuf) and 3) = 0) then
    Result := XXH_swap32(PUInt32(ABuf)^)
  else
  begin
    Move(ABuf^, Result, SizeOf(UInt32));
    Result := XXH_swap32(Result);
  end;
  {$ELSE}
  if ((NativeUInt(ABuf) and 3) = 0) then
    Result := PUInt32(ABuf)^
  else
    Move(ABuf^, Result, SizeOf(UInt32));
  {$ENDIF}
end;

{ 安全读取64位小端序值 }
function XXH_readLE64(ABuf: Pointer): UInt64; inline;
begin
  { x86 原生 LE + 硬件非对齐；大端需字节交换；其他 LE 对齐判断 }
  {$IFDEF CPU_X86}
  Result := PUInt64(ABuf)^;
  {$ELSEIF defined(CPU_BIG_ENDIAN)}
  if ((NativeUInt(ABuf) and 7) = 0) then
    Result := XXH_swap64(PUInt64(ABuf)^)
  else
  begin
    Move(ABuf^, Result, SizeOf(UInt64));
    Result := XXH_swap64(Result);
  end;
  {$ELSE}
  if ((NativeUInt(ABuf) and 7) = 0) then
    Result := PUInt64(ABuf)^
  else
    Move(ABuf^, Result, SizeOf(UInt64));
  {$ENDIF}
end;

{ 32位哈希轮函数 }
function XXHash32Round(ACc, AInput: UInt32): UInt32; inline;
begin
  Result := XXH_rotl32(ACc + (AInput * XXH_PRIME32_2), 13) * XXH_PRIME32_1;
end;

{ 64位循环左移 }
function XXH_rotl64(AValue: UInt64; ACount: Integer): UInt64; inline;
begin
  Result := (AValue shl ACount) or (AValue shr (64 - ACount));
end;

{ 哈希轮函数 }
function XXHash64Round(ACc, AInput: UInt64): UInt64; inline;
begin
  Result := XXH_rotl64(ACc + (AInput * XXH_PRIME64_2), 31) * XXH_PRIME64_1;
end;

{ 合并轮函数 }
function XXHash64MergeRound(ACc, AValue: UInt64): UInt64; inline;
begin
  AValue := XXHash64Round(0, AValue);
  Result := (ACc xor AValue) * XXH_PRIME64_1 + XXH_PRIME64_4;
end;

{ 校验输入参数有效性 }
procedure ValidateInput(AInput: Pointer; AInputSize: NativeInt); inline;
begin
  if AInputSize < 0 then
    raise EArgumentException.Create('Invalid input size');
  if (AInput = nil) and (AInputSize > 0) then
    raise EArgumentException.Create('Input is nil');
end;

{ 32位处理尾部数据 }
function XXHash32Finalize(AHash: UInt32; ABuf: PByte; ABufSize: Integer): UInt32;
begin
  while ABufSize >= 4 do
  begin
    AHash := AHash + (XXH_readLE32(ABuf) * XXH_PRIME32_3);
    AHash := XXH_rotl32(AHash, 17) * XXH_PRIME32_4;
    Inc(ABuf, 4);
    Dec(ABufSize, 4);
  end;

  while ABufSize > 0 do
  begin
    AHash := AHash + (ABuf^ * XXH_PRIME32_5);
    AHash := XXH_rotl32(AHash, 11) * XXH_PRIME32_1;
    Inc(ABuf);
    Dec(ABufSize);
  end;

  { 雪崩处理 }
  AHash := AHash xor (AHash shr 15);
  AHash := AHash * XXH_PRIME32_2;
  AHash := AHash xor (AHash shr 13);
  AHash := AHash * XXH_PRIME32_3;
  Result := AHash xor (AHash shr 16);
end;

{ 初始化32位哈希状态 }
procedure XXH32_init(var AState: TXXH32_state_t; ASeed: UInt32);
begin
  FillChar(AState, SizeOf(TXXH32_state_t), 0);
  AState.V1 := ASeed + XXH_PRIME32_1 + XXH_PRIME32_2;
  AState.V2 := ASeed + XXH_PRIME32_2;
  AState.V3 := ASeed;
  AState.V4 := ASeed - XXH_PRIME32_1;
end;

{ 更新32位哈希状态 }
procedure XXH32_update(var AState: TXXH32_state_t; AInput: Pointer; AInputSize: NativeInt);
var
  LPtr, LEndPtr: PByte;
  LBuffered: UInt32;
begin
  ValidateInput(AInput, AInputSize);

  if AInputSize = 0 then Exit;

  LPtr := AInput;
  AState.TotalLen := AState.TotalLen + UInt64(AInputSize);

  { 1. 填充缓冲区直到16字节 }
  LBuffered := AState.BufSize;
  if AInputSize >= NativeInt(16 - LBuffered) then
  begin
    { 复制到缓冲区 }
    if LBuffered > 0 then
    begin
      Move(LPtr^, AState.Buf[LBuffered], 16 - LBuffered);
      Inc(LPtr, 16 - LBuffered);
      Dec(AInputSize, 16 - LBuffered);
      AState.BufSize := 0;

      { 处理完整缓冲区 }
      AState.V1 := XXHash32Round(AState.V1, XXH_readLE32(@AState.Buf[0]));
      AState.V2 := XXHash32Round(AState.V2, XXH_readLE32(@AState.Buf[4]));
      AState.V3 := XXHash32Round(AState.V3, XXH_readLE32(@AState.Buf[8]));
      AState.V4 := XXHash32Round(AState.V4, XXH_readLE32(@AState.Buf[12]));
    end;

    { 2. 处理完整16字节块 }
    LEndPtr := LPtr + (AInputSize and (not NativeInt(15)));
    while LPtr < LEndPtr do
    begin
      AState.V1 := XXHash32Round(AState.V1, XXH_readLE32(LPtr));
      AState.V2 := XXHash32Round(AState.V2, XXH_readLE32(LPtr + 4));
      AState.V3 := XXHash32Round(AState.V3, XXH_readLE32(LPtr + 8));
      AState.V4 := XXHash32Round(AState.V4, XXH_readLE32(LPtr + 12));
      Inc(LPtr, 16);
    end;
    AInputSize := AInputSize and 15;
  end;

  { 3. 剩余数据存入缓冲区 }
  if AInputSize > 0 then
  begin
    Move(LPtr^, AState.Buf[AState.BufSize], AInputSize);
    AState.BufSize := AState.BufSize + UInt32(AInputSize);
  end;
end;

{ 计算32位最终哈希值 }
function XXH32_final(var AState: TXXH32_state_t): UInt32;
var
  LHash32: UInt32;
begin
  if AState.TotalLen >= 16 then
  begin
    LHash32 := XXH_rotl32(AState.V1, 1) +
               XXH_rotl32(AState.V2, 7) +
               XXH_rotl32(AState.V3, 12) +
               XXH_rotl32(AState.V4, 18);
  end else
  begin
    LHash32 := AState.V3 + XXH_PRIME32_5;
  end;

  LHash32 := LHash32 + UInt32(AState.TotalLen);
  Result := XXHash32Finalize(LHash32, @AState.Buf[0], AState.BufSize);
end;

{ 单次32位哈希计算 }
function XXH32(AInput: Pointer; AInputSize: NativeInt; ASeed: UInt32): UInt32;
var
  LState: TXXH32_state_t;
begin
  XXH32_init(LState, ASeed);
  XXH32_update(LState, AInput, AInputSize);
  Result := XXH32_final(LState);
end;

{ 处理尾部数据 }
function XXHash64Finalize(AHash: UInt64; ABuf: PByte; ABufSize: Integer): UInt64;
begin
  while ABufSize >= 8 do
  begin
    AHash := AHash xor XXHash64Round(0, XXH_readLE64(ABuf));
    AHash := XXH_rotl64(AHash, 27) * XXH_PRIME64_1 + XXH_PRIME64_4;
    Inc(ABuf, 8);
    Dec(ABufSize, 8);
  end;

  if ABufSize >= 4 then
  begin
    AHash := AHash xor (UInt64(XXH_readLE32(ABuf)) * XXH_PRIME64_1);
    AHash := XXH_rotl64(AHash, 23) * XXH_PRIME64_2 + XXH_PRIME64_3;
    Inc(ABuf, 4);
    Dec(ABufSize, 4);
  end;

  while ABufSize > 0 do
  begin
    AHash := AHash xor (ABuf^ * XXH_PRIME64_5);
    AHash := XXH_rotl64(AHash, 11) * XXH_PRIME64_1;
    Inc(ABuf);
    Dec(ABufSize);
  end;

  { 雪崩处理 }
  AHash := AHash xor (AHash shr 33);
  AHash := AHash * XXH_PRIME64_2;
  AHash := AHash xor (AHash shr 29);
  AHash := AHash * XXH_PRIME64_3;
  Result := AHash xor (AHash shr 32);
end;

{ 初始化增量哈希状态 }
procedure XXH64_init(var AState: TXXH64_state_t; ASeed: UInt64);
begin
  FillChar(AState, SizeOf(TXXH64_state_t), 0);
  AState.V1 := ASeed + XXH_PRIME64_1;
  AState.V1 := AState.V1 + XXH_PRIME64_2;
  AState.V2 := ASeed + XXH_PRIME64_2;
  AState.V3 := ASeed;
  AState.V4 := ASeed - XXH_PRIME64_1;
end;

{ 更新哈希状态 (核心函数) }
procedure XXH64_update(var AState: TXXH64_state_t; AInput: Pointer; AInputSize: NativeInt);
var
  LPtr, LEndPtr: PByte;
  LBuffered: UInt32;
begin
  ValidateInput(AInput, AInputSize);

  if AInputSize = 0 then Exit;

  LPtr := AInput;
  AState.TotalLen := AState.TotalLen + UInt64(AInputSize);

  { 1. 填充缓冲区直到32字节 }
  LBuffered := AState.BufSize;
  if AInputSize >= NativeInt(32 - LBuffered) then
  begin
    { 复制到缓冲区 }
    if LBuffered > 0 then
    begin
      Move(LPtr^, AState.Buf[LBuffered], 32 - LBuffered);
      Inc(LPtr, 32 - LBuffered);
      Dec(AInputSize, 32 - LBuffered);
      AState.BufSize := 0;

      { 处理完整缓冲区 }
      AState.V1 := XXHash64Round(AState.V1, XXH_readLE64(@AState.Buf[0]));
      AState.V2 := XXHash64Round(AState.V2, XXH_readLE64(@AState.Buf[8]));
      AState.V3 := XXHash64Round(AState.V3, XXH_readLE64(@AState.Buf[16]));
      AState.V4 := XXHash64Round(AState.V4, XXH_readLE64(@AState.Buf[24]));
    end;

    { 2. 处理完整32字节块 }
    LEndPtr := LPtr + (AInputSize and (not NativeInt(31)));
    while LPtr < LEndPtr do
    begin
      AState.V1 := XXHash64Round(AState.V1, XXH_readLE64(LPtr));
      AState.V2 := XXHash64Round(AState.V2, XXH_readLE64(LPtr + 8));
      AState.V3 := XXHash64Round(AState.V3, XXH_readLE64(LPtr + 16));
      AState.V4 := XXHash64Round(AState.V4, XXH_readLE64(LPtr + 24));
      Inc(LPtr, 32);
    end;
    AInputSize := AInputSize and 31;
  end;

  { 3. 剩余数据存入缓冲区 }
  if AInputSize > 0 then
  begin
    Move(LPtr^, AState.Buf[AState.BufSize], AInputSize);
    AState.BufSize := AState.BufSize + UInt32(AInputSize);
  end;
end;

{ 计算最终哈希值 }
function XXH64_final(var AState: TXXH64_state_t): UInt64;
var
  LHash64: UInt64;
begin
  { 合并所有累加器 }
  if AState.TotalLen >= 32 then
  begin
    LHash64 := XXH_rotl64(AState.V1, 1) +
               XXH_rotl64(AState.V2, 7) +
               XXH_rotl64(AState.V3, 12) +
               XXH_rotl64(AState.V4, 18);

    LHash64 := XXHash64MergeRound(LHash64, AState.V1);
    LHash64 := XXHash64MergeRound(LHash64, AState.V2);
    LHash64 := XXHash64MergeRound(LHash64, AState.V3);
    LHash64 := XXHash64MergeRound(LHash64, AState.V4);
  end else
  begin
    LHash64 := AState.V3 + XXH_PRIME64_5; { 未达32字节，使用初始种子 }
  end;

  LHash64 := LHash64 + AState.TotalLen;

  { 处理缓冲区剩余数据 }
  Result := XXHash64Finalize(LHash64, @AState.Buf[0], AState.BufSize);
end;

{ 单次哈希计算 (完整数据) }
function XXH64(AInput: Pointer; AInputSize: NativeInt; ASeed: UInt64): UInt64;
var
  LState: TXXH64_state_t;
begin
  XXH64_init(LState, ASeed);
  XXH64_update(LState, AInput, AInputSize);
  Result := XXH64_final(LState);
end;


{ 校验密钥参数有效性 }
procedure ValidateSecret(secret: Pointer; secretSize: NativeInt); inline;
begin
  if secretSize < XXH3_SECRET_SIZE_MIN then
    raise EArgumentException.Create('Invalid secret size');
  if secret = nil then
    raise EArgumentException.Create('Secret is nil');
end;

{ 写入小端序64位整数到目标地址 }
procedure XXH_writeLE64(dst: Pointer; v64: UInt64); inline;
begin
  { x86 原生 LE + 硬件非对齐；大端需字节交换；其他 LE 对齐判断 }
  {$IFDEF CPU_X86}
  PUInt64(dst)^ := v64;
  {$ELSEIF defined(CPU_BIG_ENDIAN)}
  if (NativeInt(dst) and 7) = 0 then
    PUInt64(dst)^ := XXH_swap64(v64)
  else
  begin
    PByte(dst)[0] := Byte(v64);
    PByte(dst)[1] := Byte(v64 shr 8);
    PByte(dst)[2] := Byte(v64 shr 16);
    PByte(dst)[3] := Byte(v64 shr 24);
    PByte(dst)[4] := Byte(v64 shr 32);
    PByte(dst)[5] := Byte(v64 shr 40);
    PByte(dst)[6] := Byte(v64 shr 48);
    PByte(dst)[7] := Byte(v64 shr 56);
  end;
  {$ELSE}
  if (NativeInt(dst) and 7) = 0 then
    PUInt64(dst)^ := v64
  else
  begin
    PByte(dst)[0] := Byte(v64);
    PByte(dst)[1] := Byte(v64 shr 8);
    PByte(dst)[2] := Byte(v64 shr 16);
    PByte(dst)[3] := Byte(v64 shr 24);
    PByte(dst)[4] := Byte(v64 shr 32);
    PByte(dst)[5] := Byte(v64 shr 40);
    PByte(dst)[6] := Byte(v64 shr 48);
    PByte(dst)[7] := Byte(v64 shr 56);
  end;
  {$ENDIF}
end;

{ 32位整数字节序交换 }
function XXH_swap32(x: UInt32): UInt32; inline;
begin
  Result := ((x and UInt32($000000FF)) shl 24) or
            ((x and UInt32($0000FF00)) shl 8) or
            ((x and UInt32($00FF0000)) shr 8) or
            ((x and UInt32($FF000000)) shr 24);
end;

{ 64位整数字节序交换 }
function XXH_swap64(x: UInt64): UInt64; inline;
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

{ 32位乘法生成64位结果 }
function XXH_mult32to64(x, y: UInt64): UInt64; inline;
begin
  Result := UInt64(UInt32(x)) * UInt64(UInt32(y));
end;

{ 64位异或移位操作 }
function XXH_xorshift64(v64: UInt64; shift: Integer): UInt64; inline;
begin
  Result := v64 xor (v64 shr shift);
end;

{ RRMXMX混合函数，用于短输入哈希 }
function XXH3_rrmxmx(h64: UInt64; len: UInt64): UInt64; inline;
begin
  h64 := h64 xor XXH_rotl64(h64, 49) xor XXH_rotl64(h64, 24);
  h64 := h64 * XXH_PRIME_MX2;
  h64 := h64 xor ((h64 shr 35) + len);
  h64 := h64 * XXH_PRIME_MX2;
  Result := XXH_xorshift64(h64, 28);
end;

{ 64位乘法生成128位结果 }
function XXH_mult64to128(lhs, rhs: UInt64): TXXH3_hash128_t; inline;
var
  lo_lo, hi_lo, lo_hi, hi_hi: UInt64;
  cross: UInt64;
begin
  lo_lo := XXH_mult32to64(lhs and UInt64($FFFFFFFF), rhs and UInt64($FFFFFFFF));
  hi_lo := XXH_mult32to64(lhs shr 32, rhs and UInt64($FFFFFFFF));
  lo_hi := XXH_mult32to64(lhs and UInt64($FFFFFFFF), rhs shr 32);
  hi_hi := XXH_mult32to64(lhs shr 32, rhs shr 32);

  cross := (lo_lo shr 32) + (hi_lo and UInt64($FFFFFFFF)) + lo_hi;
  Result.low64 := (cross shl 32) or (lo_lo and UInt64($FFFFFFFF));
  Result.high64 := (hi_lo shr 32) + (cross shr 32) + hi_hi;
end;

{ 128位乘法折叠为64位 }
function XXH3_mul128_fold64(lhs, rhs: UInt64): UInt64; inline;
var
  product: TXXH3_hash128_t;
begin
  product := XXH_mult64to128(lhs, rhs);
  Result := product.low64 xor product.high64;
end;

{ XXH64雪崩函数 }
function XXH64_avalanche(h64: UInt64): UInt64; inline;
begin
  h64 := h64 xor (h64 shr 33);
  h64 := h64 * XXH_PRIME64_2;
  h64 := h64 xor (h64 shr 29);
  h64 := h64 * XXH_PRIME64_3;
  h64 := h64 xor (h64 shr 32);
  Result := h64;
end;

{ XXH3雪崩函数 }
function XXH3_avalanche(h64: UInt64): UInt64; inline;
begin
  h64 := XXH_xorshift64(h64, 37);
  h64 := h64 * UInt64($165667919E3779F9);
  Result := XXH_xorshift64(h64, 32);
end;

{ 混合16字节数据块 }
function XXH3_mix16B(const input, secret: PByte; seed64: UInt64): UInt64; inline;
var
  input_lo, input_hi: UInt64;
begin
  input_lo := XXH_readLE64(input);
  input_hi := XXH_readLE64(input + 8);
  Result := XXH3_mul128_fold64(
    input_lo xor (XXH_readLE64(secret) + seed64),
    input_hi xor (XXH_readLE64(secret + 8) - seed64)
  );
end;

{ 内部状态重置函数 }
procedure XXH3_reset_internal(var state: TXXH3_state_t; seed: UInt64;
  secret: Pointer; secretSize: NativeInt);
begin
  { 清零运行时状态字段 }
  state.bufferedSize := 0;
  state.reserved32 := $12345678;  // 初始化哨兵
  state.nbStripesSoFar := 0;
  state.totalLen := 0;

  { 初始化累加器 }
  state.acc[0] := XXH_PRIME32_3;
  state.acc[1] := XXH_PRIME64_1;
  state.acc[2] := XXH_PRIME64_2;
  state.acc[3] := XXH_PRIME64_3;
  state.acc[4] := XXH_PRIME64_4;
  state.acc[5] := XXH_PRIME32_2;
  state.acc[6] := XXH_PRIME64_5;
  state.acc[7] := XXH_PRIME32_1;

  { 设置种子和密钥 }
  state.seed := seed;
  state.extSecret := secret;
  state.secretLimit := secretSize - XXH_STRIPE_LEN;
  state.nbStripesPerBlock := state.secretLimit div XXH_SECRET_CONSUME_RATE;
end;

{ 重置64位哈希状态 }
procedure XXH3_64bits_init(var state: TXXH3_state_t);
begin
  XXH3_reset_internal(state, 0, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE);
end;

{ 使用种子生成自定义密钥 }
procedure XXH3_initCustomSecret_scalar(customSecret: Pointer; seed64: UInt64);
var
  i: Integer;
  lo, hi: UInt64;
begin
  for i := 0 to (XXH3_SECRET_DEFAULT_SIZE div 16) - 1 do
  begin
    lo := XXH_readLE64(@XXH3_kSecret[i * 16]) + seed64;
    hi := XXH_readLE64(@XXH3_kSecret[i * 16 + 8]) - seed64;
    XXH_writeLE64(PByte(customSecret) + i * 16, lo);
    XXH_writeLE64(PByte(customSecret) + i * 16 + 8, hi);
  end;
end;

{ 使用种子重置64位哈希状态 }
procedure XXH3_64bits_init_withSeed(var state: TXXH3_state_t; seed: UInt64);
begin
  if seed = 0 then
    XXH3_64bits_init(state)
  else
  begin
    if (state.reserved32 <> $12345678) or (seed <> state.seed) then
      XXH3_initCustomSecret_scalar(@state.customSecret, seed);
    XXH3_reset_internal(state, seed, nil, XXH3_SECRET_DEFAULT_SIZE);
  end;
end;

{ 累加单个512位条带(8个64位通道) }
procedure XXH3_accumulate_512_scalar(acc, input, secret: Pointer);
var
  i: NativeInt;
  data_val, data_key: UInt64;
  data_key_lo, data_key_hi: UInt32;
  input_ptr, secret_ptr, acc_ptr: PByte;
begin
  input_ptr := input;
  secret_ptr := secret;
  acc_ptr := acc;

  for i := 0 to 7 do
  begin
    data_val := XXH_readLE64(input_ptr);
    data_key := data_val xor XXH_readLE64(secret_ptr);
    data_key_lo := UInt32(data_key);
    data_key_hi := UInt32(data_key shr 32);

    PUInt64(acc_ptr + (i xor 1) * SizeOf(UInt64))^ :=
      PUInt64(acc_ptr + (i xor 1) * SizeOf(UInt64))^ + data_val;
    PUInt64(acc_ptr + i * SizeOf(UInt64))^ :=
      PUInt64(acc_ptr + i * SizeOf(UInt64))^ + UInt64(data_key_lo) * UInt64(data_key_hi);

    input_ptr := input_ptr + 8;
    secret_ptr := secret_ptr + 8;
  end;
end;

{ 扰动累加器数组，防止累加溢出退化 }
procedure XXH3_scrambleAcc_scalar(acc, secret: Pointer);
var
  xacc: PUInt64;
  i: NativeInt;
  key64: UInt64;
  secret_ptr: PByte;
begin
  xacc := acc;
  secret_ptr := secret;

  for i := 0 to 7 do
  begin
    key64 := XXH_readLE64(secret_ptr);
    xacc^ := ((xacc^ xor (xacc^ shr 47)) xor key64) * XXH_PRIME32_1;
    Inc(xacc);
    secret_ptr := secret_ptr + 8;
  end;
end;

{ 累加多个条带 }
procedure XXH3_accumulate(acc: PUInt64; const input, secret: PByte; nbStripes: NativeInt);
var
  n: NativeInt;
  in_ptr, sec_ptr: PByte;
begin
  in_ptr := input;
  sec_ptr := secret;

  for n := 0 to nbStripes - 1 do
  begin
    XXH3_accumulate_512_scalar(acc, in_ptr, sec_ptr);
    in_ptr := in_ptr + XXH_STRIPE_LEN;
    sec_ptr := sec_ptr + XXH_SECRET_CONSUME_RATE;
  end;
end;

{ 消费条带并处理块边界扰动 }
procedure XXH3_consumeStripes(acc: PUInt64; var nbStripesSoFar: NativeInt;
  nbStripesPerBlock: NativeInt; const input: PByte; nbStripes: NativeInt;
  const secret: PByte; secretLimit: NativeInt);
var
  nbStripesToEndofBlock, nbStripesAfterBlock: NativeInt;
begin
  if nbStripesPerBlock - nbStripesSoFar <= nbStripes then
  begin
    nbStripesToEndofBlock := nbStripesPerBlock - nbStripesSoFar;
    nbStripesAfterBlock := nbStripes - nbStripesToEndofBlock;

    XXH3_accumulate(acc, input, secret + nbStripesSoFar * XXH_SECRET_CONSUME_RATE, nbStripesToEndofBlock);
    XXH3_scrambleAcc_scalar(acc, secret + secretLimit);
    XXH3_accumulate(acc, input + nbStripesToEndofBlock * XXH_STRIPE_LEN, secret, nbStripesAfterBlock);

    nbStripesSoFar := nbStripesAfterBlock;
  end else
  begin
    XXH3_accumulate(acc, input, secret + nbStripesSoFar * XXH_SECRET_CONSUME_RATE, nbStripes);
    nbStripesSoFar := nbStripesSoFar + nbStripes;
  end;
end;

{ 增量更新XXH3内部状态 }
procedure XXH3_update(var state: TXXH3_state_t; input: PByte; len: NativeInt);
var
  bEnd, secret: PByte;
  loadSize: NativeInt;
  limit: PByte;
begin
  bEnd := input + len;

  if state.extSecret = nil then
    secret := @state.customSecret
  else
    secret := state.extSecret;

  state.totalLen := state.totalLen + UInt64(len);

  { 1. 数据量不足，仅追加到缓冲区 }
  if state.bufferedSize + NativeUInt(len) <= XXH3_INTERNALBUFFER_SIZE then
  begin
    Move(input^, state.buffer[state.bufferedSize], len);
    state.bufferedSize := state.bufferedSize + UInt32(len);
    Exit;
  end;

  { 2. 先填满缓冲区并处理 }
  if state.bufferedSize > 0 then
  begin
    loadSize := XXH3_INTERNALBUFFER_SIZE - state.bufferedSize;
    Move(input^, state.buffer[state.bufferedSize], loadSize);
    Inc(input, loadSize);

    XXH3_consumeStripes(@state.acc, state.nbStripesSoFar,
      state.nbStripesPerBlock, @state.buffer,
      XXH3_INTERNALBUFFER_SIZE div XXH_STRIPE_LEN, secret,
      state.secretLimit);

    state.bufferedSize := 0;
  end;

  { 3. 循环处理完整的256字节块 }
  if input + XXH3_INTERNALBUFFER_SIZE < bEnd then
  begin
    limit := bEnd - XXH3_INTERNALBUFFER_SIZE;

    while input < limit do
    begin
      XXH3_consumeStripes(@state.acc, state.nbStripesSoFar,
        state.nbStripesPerBlock, input,
        XXH3_INTERNALBUFFER_SIZE div XXH_STRIPE_LEN, secret,
        state.secretLimit);

      input := input + XXH3_INTERNALBUFFER_SIZE;
    end;

    { 保留最后一个条带到缓冲区末尾，供摘要阶段使用 }
    Move((input - XXH_STRIPE_LEN)^, state.buffer[SizeOf(state.buffer) - XXH_STRIPE_LEN], XXH_STRIPE_LEN);
  end;

  { 4. 剩余数据存入缓冲区 }
  if input < bEnd then
  begin
    Move(input^, state.buffer, NativeInt(bEnd - input));
    state.bufferedSize := UInt32(bEnd - input);
  end;
end;

{ 64位增量更新(含输入校验) }
procedure XXH3_64bits_update(var state: TXXH3_state_t; input: Pointer; len: NativeInt);
begin
  ValidateInput(input, len);
  if len = 0 then Exit;
  XXH3_update(state, input, len);
end;

{ 混合两个累加器值 }
function XXH3_mix2Accs(const acc: PUInt64; const secret: PByte): UInt64; inline;
var
  p1, p2: PUInt64;
begin
  p1 := acc;
  p2 := PUInt64(PByte(acc) + SizeOf(UInt64));
  Result := XXH3_mul128_fold64(
    p1^ xor XXH_readLE64(secret),
    p2^ xor XXH_readLE64(secret + 8)
  );
end;

{ 合并所有累加器为最终哈希值 }
function XXH3_mergeAccs(const acc: PUInt64; const secret: PByte; start: UInt64): UInt64; inline;
var
  result64: UInt64;
  i: NativeInt;
begin
  result64 := start;
  for i := 0 to 3 do
  begin
    result64 := result64 + XXH3_mix2Accs(
      PUInt64(PByte(acc) + 16 * i), secret + 16 * i);
  end;
  Result := XXH3_avalanche(result64);
end;

{ 长输入摘要：从内部缓冲区提取并累加剩余条带 }
procedure XXH3_digest_long(acc: PUInt64; var state: TXXH3_state_t; const secret: PByte);
var
  nbStripes: NativeInt;
  nbStripesSoFar: NativeInt;
  lastStripe: array[0..63] of Byte;
  catchupSize: NativeInt;
begin
  Move(state.acc, acc^, SizeOf(state.acc));

  if state.bufferedSize >= XXH_STRIPE_LEN then
  begin
    nbStripes := (state.bufferedSize - 1) div XXH_STRIPE_LEN;
    nbStripesSoFar := state.nbStripesSoFar;

    XXH3_consumeStripes(acc, nbStripesSoFar, state.nbStripesPerBlock,
      @state.buffer, nbStripes, secret, state.secretLimit);

    XXH3_accumulate_512_scalar(acc, @state.buffer[state.bufferedSize - XXH_STRIPE_LEN],
      secret + state.secretLimit - 7);
  end else
  begin
    catchupSize := XXH_STRIPE_LEN - state.bufferedSize;
    Move(state.buffer[SizeOf(state.buffer) - catchupSize], lastStripe, catchupSize);
    Move(state.buffer, lastStripe[catchupSize], state.bufferedSize);

    XXH3_accumulate_512_scalar(acc, @lastStripe, secret + state.secretLimit - 7);
  end;
end;

{ 64位增量计算最终值 }
function XXH3_64bits_final(var state: TXXH3_state_t): TXXH3_hash64_t;
var
  secret: PByte;
  acc: array[0..7] of UInt64;
begin
  { 选择密钥来源 }
  if state.extSecret = nil then
    secret := @state.customSecret
  else
    secret := state.extSecret;

  if state.totalLen > XXH3_MIDSIZE_MAX then
  begin
    XXH3_digest_long(@acc, state, secret);
    Result := XXH3_mergeAccs(@acc, secret + 11, state.totalLen * XXH_PRIME64_1);
  end
  else if state.seed <> 0 then
    Result := XXH3_64bits(@state.buffer[0], state.totalLen, state.seed)
  else
    Result := XXH3_64bits_withSecret(@state.buffer[0], state.totalLen, secret, state.secretLimit + XXH_STRIPE_LEN);
end;

{ 64位哈希(默认种子0) }
function XXH3_64bits(input: Pointer; len: NativeInt): TXXH3_hash64_t;
begin
  Result := XXH3_64bits(input, len, 0);
end;

function XXH3_len_0to16_64b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash64_t; forward;
function XXH3_len_17to128_64b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash64_t; forward;
function XXH3_len_129to240_64b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash64_t; forward;
function XXH3_hashLong_64b_internal(const input: Pointer; len: NativeInt; const secret: Pointer; secretSize: NativeInt): TXXH3_hash64_t; forward;

{ 64位哈希(带种子，按长度分派) }
function XXH3_64bits(input: Pointer; len: NativeInt; seed: UInt64): TXXH3_hash64_t;
var
  customSecret: array[0..XXH3_SECRET_DEFAULT_SIZE - 1] of Byte;
begin
  ValidateInput(input, len);
  { 按数据长度选择最优分支 }
  if len <= 16 then
    Result := XXH3_len_0to16_64b(input, len, @XXH3_kSecret, seed)
  else if len <= 128 then
    Result := XXH3_len_17to128_64b(input, len, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE, seed)
  else if len <= XXH3_MIDSIZE_MAX then
    Result := XXH3_len_129to240_64b(input, len, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE, seed)
  else
  if seed = 0 then
    Result := XXH3_hashLong_64b_internal(input, len, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE)
  else
  begin
    XXH3_initCustomSecret_scalar(@customSecret, seed);
    Result := XXH3_hashLong_64b_internal(input, len, @customSecret, SizeOf(customSecret));
  end;
end;

{ 64位哈希(自定义密钥) }
function XXH3_64bits_withSecret(input: Pointer; len: NativeInt; secret: Pointer; secretSize: NativeInt): TXXH3_hash64_t;
begin
  ValidateInput(input, len);
  ValidateSecret(secret, secretSize);
  if len <= 16 then
    Result := XXH3_len_0to16_64b(input, len, secret, 0)
  else if len <= 128 then
    Result := XXH3_len_17to128_64b(input, len, secret, secretSize, 0)
  else if len <= XXH3_MIDSIZE_MAX then
    Result := XXH3_len_129to240_64b(input, len, secret, secretSize, 0)
  else
    Result := XXH3_hashLong_64b_internal(input, len, secret, secretSize);
end;

{ 128位哈希(默认种子0) }
function XXH3_128bits(input: Pointer; len: NativeInt): TXXH3_hash128_t;
begin
  Result := XXH3_128bits(input, len, 0);
end;

function XXH3_len_0to16_128b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash128_t; forward;
function XXH3_len_17to128_128b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash128_t; forward;
function XXH3_len_129to240_128b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash128_t; forward;
function XXH3_hashLong_128b_internal(const input: Pointer; len: NativeInt; const secret: Pointer; secretSize: NativeInt): TXXH3_hash128_t; forward;

{ 128位哈希(带种子，按长度分派) }
function XXH3_128bits(input: Pointer; len: NativeInt; seed: UInt64): TXXH3_hash128_t;
var
  customSecret: array[0..XXH3_SECRET_DEFAULT_SIZE - 1] of Byte;
begin
  ValidateInput(input, len);
  { 按数据长度选择最优分支 }
  if len <= 16 then
    Result := XXH3_len_0to16_128b(input, len, @XXH3_kSecret, seed)
  else if len <= 128 then
    Result := XXH3_len_17to128_128b(input, len, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE, seed)
  else if len <= XXH3_MIDSIZE_MAX then
    Result := XXH3_len_129to240_128b(input, len, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE, seed)
  else
  if seed = 0 then
    Result := XXH3_hashLong_128b_internal(input, len, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE)
  else
  begin
    XXH3_initCustomSecret_scalar(@customSecret, seed);
    Result := XXH3_hashLong_128b_internal(input, len, @customSecret, SizeOf(customSecret));
  end;
end;

{ 128位哈希(自定义密钥) }
function XXH3_128bits_withSecret(input: Pointer; len: NativeInt; secret: Pointer; secretSize: NativeInt): TXXH3_hash128_t;
begin
  ValidateInput(input, len);
  ValidateSecret(secret, secretSize);
  if len <= 16 then
    Result := XXH3_len_0to16_128b(input, len, secret, 0)
  else if len <= 128 then
    Result := XXH3_len_17to128_128b(input, len, secret, secretSize, 0)
  else if len <= XXH3_MIDSIZE_MAX then
    Result := XXH3_len_129to240_128b(input, len, secret, secretSize, 0)
  else
    Result := XXH3_hashLong_128b_internal(input, len, secret, secretSize);
end;

{ 重置128位哈希状态 }
procedure XXH3_128bits_init(var state: TXXH3_state_t);
begin
  XXH3_reset_internal(state, 0, @XXH3_kSecret, XXH3_SECRET_DEFAULT_SIZE);
end;

{ 使用种子重置128位哈希状态 }
procedure XXH3_128bits_init_withSeed(var state: TXXH3_state_t; seed: UInt64);
begin
  if seed = 0 then
    XXH3_128bits_init(state)
  else
  begin
    if (state.reserved32 <> $12345678) or (seed <> state.seed) then
      XXH3_initCustomSecret_scalar(@state.customSecret, seed);
    XXH3_reset_internal(state, seed, nil, XXH3_SECRET_DEFAULT_SIZE);
  end;
end;

{ 128位增量更新(含输入校验) }
procedure XXH3_128bits_update(var state: TXXH3_state_t; input: Pointer; len: NativeInt);
begin
  ValidateInput(input, len);
  if len = 0 then Exit;
  XXH3_update(state, input, len);
end;

{ 128位增量计算最终值 }
function XXH3_128bits_final(var state: TXXH3_state_t): TXXH3_hash128_t;
var
  secret: PByte;
  acc: array[0..7] of UInt64;
begin
  { 选择密钥来源 }
  if state.extSecret = nil then
    secret := @state.customSecret
  else
    secret := state.extSecret;

  if state.totalLen > XXH3_MIDSIZE_MAX then
  begin
    XXH3_digest_long(@acc, state, secret);
    Result.low64 := XXH3_mergeAccs(@acc, secret + 11, state.totalLen * XXH_PRIME64_1);
    Result.high64 := XXH3_mergeAccs(@acc,
      secret + state.secretLimit + XXH_STRIPE_LEN - 64 - 11,
      not(state.totalLen * XXH_PRIME64_2));
  end
  else if state.seed <> 0 then
    Result := XXH3_128bits(@state.buffer[0], state.totalLen, state.seed)
  else
    Result := XXH3_128bits_withSecret(@state.buffer[0], state.totalLen, secret, state.secretLimit + XXH_STRIPE_LEN);
end;

{ 64位长度分派函数 }

{ 1~3字节短输入64位哈希 }
function XXH3_len_1to3_64b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash64_t;
var
  c1, c2, c3: Byte;
  combined: UInt32;
  bitflip: UInt64;
begin
  c1 := input[0];
  c2 := input[len shr 1];
  c3 := input[len - 1];
  combined := (UInt32(c1) shl 16) or (UInt32(c2) shl 24) or UInt32(c3) or (UInt32(len) shl 8);
  bitflip := (XXH_readLE32(secret) xor XXH_readLE32(secret + 4)) + seed;
  Result := XXH64_avalanche(UInt64(combined) xor bitflip);
end;

{ 4~8字节短输入64位哈希 }
function XXH3_len_4to8_64b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash64_t;
var
  input1, input2: UInt32;
  input64, bitflip, keyed: UInt64;
begin
  seed := seed xor (UInt64(XXH_swap32(UInt32(seed))) shl 32);
  input1 := XXH_readLE32(input);
  input2 := XXH_readLE32(input + len - 4);
  input64 := UInt64(input2) or (UInt64(input1) shl 32);
  bitflip := (XXH_readLE64(secret + 8) xor XXH_readLE64(secret + 16)) - seed;
  keyed := input64 xor bitflip;
  Result := XXH3_rrmxmx(keyed, len);
end;

{ 9~16字节短输入64位哈希 }
function XXH3_len_9to16_64b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash64_t;
var
  bitflip1, bitflip2: UInt64;
  input_lo, input_hi: UInt64;
  acc: UInt64;
begin
  bitflip1 := (XXH_readLE64(secret + 24) xor XXH_readLE64(secret + 32)) + seed;
  bitflip2 := (XXH_readLE64(secret + 40) xor XXH_readLE64(secret + 48)) - seed;
  input_lo := XXH_readLE64(input) xor bitflip1;
  input_hi := XXH_readLE64(input + len - 8) xor bitflip2;
  acc := UInt64(len) + XXH_swap64(input_lo) + input_hi + XXH3_mul128_fold64(input_lo, input_hi);
  Result := XXH3_avalanche(acc);
end;

{ 0~16字节分派入口 }
function XXH3_len_0to16_64b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash64_t;
begin
  if len = 0 then
    Result := XXH64_avalanche(seed xor (XXH_readLE64(secret + 56) xor XXH_readLE64(secret + 64)))
  else if len < 4 then
    Result := XXH3_len_1to3_64b(input, len, secret, seed)
  else if len <= 8 then
    Result := XXH3_len_4to8_64b(input, len, secret, seed)
  else
    Result := XXH3_len_9to16_64b(input, len, secret, seed);
end;

{ 17~128字节中等输入64位哈希 }
function XXH3_len_17to128_64b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash64_t;
var
  acc: UInt64;
begin
  acc := UInt64(len) * XXH_PRIME64_1;

  if len > 32 then
  begin
    if len > 64 then
    begin
      if len > 96 then
      begin
        acc := acc + XXH3_mix16B(input + 48, secret + 96, seed);
        acc := acc + XXH3_mix16B(input + len - 64, secret + 112, seed);
      end;
      acc := acc + XXH3_mix16B(input + 32, secret + 64, seed);
      acc := acc + XXH3_mix16B(input + len - 48, secret + 80, seed);
    end;
    acc := acc + XXH3_mix16B(input + 16, secret + 32, seed);
    acc := acc + XXH3_mix16B(input + len - 32, secret + 48, seed);
  end;

  acc := acc + XXH3_mix16B(input, secret, seed);
  acc := acc + XXH3_mix16B(input + len - 16, secret + 16, seed);

  Result := XXH3_avalanche(acc);
end;

{ 129~240字节中等输入64位哈希 }
function XXH3_len_129to240_64b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash64_t;
var
  acc: UInt64;
  i, nbRounds: Integer;
begin
  acc := UInt64(len) * XXH_PRIME64_1;

  for i := 0 to 7 do
    acc := acc + XXH3_mix16B(input + 16 * i, secret + 16 * i, seed);

  acc := XXH3_avalanche(acc);

  nbRounds := len div 16;
  for i := 8 to nbRounds - 1 do
    acc := acc + XXH3_mix16B(input + 16 * i, secret + 16 * (i - 8) + 3, seed);

  acc := acc + XXH3_mix16B(input + len - 16, secret + XXH3_SECRET_SIZE_MIN - 17, seed);

  Result := XXH3_avalanche(acc);
end;

{ 长输入64位哈希(条带累加+扰动循环) }
function XXH3_hashLong_64b_internal(const input: Pointer; len: NativeInt; const secret: Pointer; secretSize: NativeInt): TXXH3_hash64_t;
var
  acc: array[0..7] of UInt64;
  nbStripesPerBlock, block_len, nb_blocks, nbStripes: NativeInt;
  n: NativeInt;
  p: PByte;
begin
  acc[0] := XXH_PRIME32_3;
  acc[1] := XXH_PRIME64_1;
  acc[2] := XXH_PRIME64_2;
  acc[3] := XXH_PRIME64_3;
  acc[4] := XXH_PRIME64_4;
  acc[5] := XXH_PRIME32_2;
  acc[6] := XXH_PRIME64_5;
  acc[7] := XXH_PRIME32_1;
  nbStripesPerBlock := (secretSize - XXH_STRIPE_LEN) div XXH_SECRET_CONSUME_RATE;
  block_len := XXH_STRIPE_LEN * nbStripesPerBlock;
  nb_blocks := (len - 1) div block_len;

  for n := 0 to nb_blocks - 1 do
  begin
    XXH3_accumulate(@acc, PByte(input) + n * block_len, secret, nbStripesPerBlock);
    XXH3_scrambleAcc_scalar(@acc, PByte(secret) + secretSize - XXH_STRIPE_LEN);
  end;

  nbStripes := ((len - 1) - (block_len * nb_blocks)) div XXH_STRIPE_LEN;
  XXH3_accumulate(@acc, PByte(input) + nb_blocks * block_len, secret, nbStripes);

  p := PByte(input) + len - XXH_STRIPE_LEN;
  XXH3_accumulate_512_scalar(@acc, p, PByte(secret) + secretSize - XXH_STRIPE_LEN - 7);

  Result := XXH3_mergeAccs(@acc, PByte(secret) + 11, UInt64(len) * XXH_PRIME64_1);
end;

{ 128位长度分派函数 }

{ 混合两段32字节数据 }
procedure XXH128_mix32B(var acc: TXXH3_hash128_t; input_1, input_2, secret: PByte; seed: UInt64);
begin
  acc.low64 := acc.low64 + XXH3_mix16B(input_1, secret, seed);
  acc.low64 := acc.low64 xor (XXH_readLE64(input_2) + XXH_readLE64(input_2 + 8));
  acc.high64 := acc.high64 + XXH3_mix16B(input_2, secret + 16, seed);
  acc.high64 := acc.high64 xor (XXH_readLE64(input_1) + XXH_readLE64(input_1 + 8));
end;

{ 1~3字节短输入128位哈希 }
function XXH3_len_1to3_128b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash128_t;
var
  c1, c2, c3: Byte;
  combinedl, combinedh: UInt32;
  bitflipl, bitfliph: UInt64;
  keyed_lo, keyed_hi: UInt64;
begin
  c1 := input[0];
  c2 := input[len shr 1];
  c3 := input[len - 1];
  combinedl := (UInt32(c1) shl 16) or (UInt32(c2) shl 24) or UInt32(c3) or (UInt32(len) shl 8);
  combinedh := XXH_rotl32(XXH_swap32(combinedl), 13);

  bitflipl := (XXH_readLE32(secret) xor XXH_readLE32(secret + 4)) + seed;
  bitfliph := (XXH_readLE32(secret + 8) xor XXH_readLE32(secret + 12)) - seed;

  keyed_lo := UInt64(combinedl) xor bitflipl;
  keyed_hi := UInt64(combinedh) xor bitfliph;

  Result.low64 := XXH64_avalanche(keyed_lo);
  Result.high64 := XXH64_avalanche(keyed_hi);
end;

{ 4~8字节短输入128位哈希 }
function XXH3_len_4to8_128b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash128_t;
var
  input_lo, input_hi: UInt32;
  input64, bitflip, keyed: UInt64;
  m128: TXXH3_hash128_t;
begin
  seed := seed xor (UInt64(XXH_swap32(UInt32(seed))) shl 32);
  input_lo := XXH_readLE32(input);
  input_hi := XXH_readLE32(input + len - 4);
  input64 := UInt64(input_lo) or (UInt64(input_hi) shl 32);
  bitflip := (XXH_readLE64(secret + 16) xor XXH_readLE64(secret + 24)) + seed;
  keyed := input64 xor bitflip;

  m128 := XXH_mult64to128(keyed, XXH_PRIME64_1 + (UInt64(len) shl 2));
  m128.high64 := m128.high64 + (m128.low64 shl 1);
  m128.low64 := m128.low64 xor (m128.high64 shr 3);
  m128.low64 := XXH_xorshift64(m128.low64, 35);
  m128.low64 := m128.low64 * XXH_PRIME_MX2;
  m128.low64 := XXH_xorshift64(m128.low64, 28);
  m128.high64 := XXH3_avalanche(m128.high64);

  Result := m128;
end;

{ 9~16字节短输入128位哈希 }
function XXH3_len_9to16_128b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash128_t;
var
  bitflipl, bitfliph: UInt64;
  input_lo, input_hi: UInt64;
  m128: TXXH3_hash128_t;
begin
  bitflipl := (XXH_readLE64(secret + 32) xor XXH_readLE64(secret + 40)) - seed;
  bitfliph := (XXH_readLE64(secret + 48) xor XXH_readLE64(secret + 56)) + seed;
  input_lo := XXH_readLE64(input);
  input_hi := XXH_readLE64(input + len - 8);

  m128 := XXH_mult64to128(input_lo xor input_hi xor bitflipl, XXH_PRIME64_1);
  m128.low64 := m128.low64 + UInt64(len - 1) shl 54;
  input_hi := input_hi xor bitfliph;

  {$IFDEF CPU32}
  if SizeOf(Pointer) < SizeOf(UInt64) then
    m128.high64 := m128.high64 + (input_hi and $FFFFFFFF00000000) +
                   XXH_mult32to64(UInt32(input_hi), XXH_PRIME32_2)
  else
  {$ENDIF}
    m128.high64 := m128.high64 + input_hi +
                   XXH_mult32to64(UInt32(input_hi), XXH_PRIME32_2 - 1);

  m128.low64 := m128.low64 xor XXH_swap64(m128.high64);

  Result := XXH_mult64to128(m128.low64, XXH_PRIME64_2);
  Result.high64 := Result.high64 + (m128.high64 * XXH_PRIME64_2);
  Result.low64 := XXH3_avalanche(Result.low64);
  Result.high64 := XXH3_avalanche(Result.high64);
end;

{ 0~16字节分派入口 }
function XXH3_len_0to16_128b(const input: PByte; len: NativeInt; const secret: PByte; seed: UInt64): TXXH3_hash128_t;
begin
  if len = 0 then
  begin
    Result.low64 := XXH64_avalanche(seed xor (XXH_readLE64(secret + 64) xor XXH_readLE64(secret + 72)));
    Result.high64 := XXH64_avalanche(seed xor (XXH_readLE64(secret + 80) xor XXH_readLE64(secret + 88)));
  end
  else if len < 4 then
    Result := XXH3_len_1to3_128b(input, len, secret, seed)
  else if len <= 8 then
    Result := XXH3_len_4to8_128b(input, len, secret, seed)
  else
    Result := XXH3_len_9to16_128b(input, len, secret, seed);
end;

{ 17~128字节中等输入128位哈希 }
function XXH3_len_17to128_128b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash128_t;
var
  acc: TXXH3_hash128_t;
begin
  acc.low64 := UInt64(len) * XXH_PRIME64_1;
  acc.high64 := 0;

  if len > 32 then
  begin
    if len > 64 then
    begin
      if len > 96 then
        XXH128_mix32B(acc, input + 48, input + len - 64, secret + 96, seed);
      XXH128_mix32B(acc, input + 32, input + len - 48, secret + 64, seed);
    end;
    XXH128_mix32B(acc, input + 16, input + len - 32, secret + 32, seed);
  end;
  XXH128_mix32B(acc, input, input + len - 16, secret, seed);

  Result.low64 := acc.low64 + acc.high64;
  Result.high64 := (acc.low64 * XXH_PRIME64_1) + (acc.high64 * XXH_PRIME64_4) +
                   ((UInt64(len) - seed) * XXH_PRIME64_2);
  Result.low64 := XXH3_avalanche(Result.low64);
  Result.high64 := UInt64(0) - XXH3_avalanche(Result.high64);
end;

{ 129~240字节中等输入128位哈希 }
function XXH3_len_129to240_128b(const input: PByte; len: NativeInt; const secret: PByte; secretSize: NativeInt; seed: UInt64): TXXH3_hash128_t;
var
  acc: TXXH3_hash128_t;
  i, nbRounds: Integer;
begin
  acc.low64 := UInt64(len) * XXH_PRIME64_1;
  acc.high64 := 0;

  for i := 0 to 3 do
    XXH128_mix32B(acc, input + 32 * i, input + 32 * i + 16, secret + 32 * i, seed);

  acc.low64 := XXH3_avalanche(acc.low64);
  acc.high64 := XXH3_avalanche(acc.high64);

  nbRounds := len div 32;
  for i := 4 to nbRounds - 1 do
    XXH128_mix32B(acc, input + 32 * i, input + 32 * i + 16,
                        secret + 3 + 32 * (i - 4), seed);

  XXH128_mix32B(acc, input + len - 16, input + len - 32,
                      secret + XXH3_SECRET_SIZE_MIN - 33, UInt64(0) - seed);

  Result.low64 := acc.low64 + acc.high64;
  Result.high64 := (acc.low64 * XXH_PRIME64_1) + (acc.high64 * XXH_PRIME64_4) +
                   ((UInt64(len) - seed) * XXH_PRIME64_2);
  Result.low64 := XXH3_avalanche(Result.low64);
  Result.high64 := UInt64(0) - XXH3_avalanche(Result.high64);
end;

{ 长输入128位哈希(条带累加+扰动循环) }
function XXH3_hashLong_128b_internal(const input: Pointer; len: NativeInt; const secret: Pointer; secretSize: NativeInt): TXXH3_hash128_t;
var
  acc: array[0..7] of UInt64;
  nbStripesPerBlock, block_len, nb_blocks, nbStripes: NativeInt;
  n: NativeInt;
  p: PByte;
begin
  acc[0] := XXH_PRIME32_3;
  acc[1] := XXH_PRIME64_1;
  acc[2] := XXH_PRIME64_2;
  acc[3] := XXH_PRIME64_3;
  acc[4] := XXH_PRIME64_4;
  acc[5] := XXH_PRIME32_2;
  acc[6] := XXH_PRIME64_5;
  acc[7] := XXH_PRIME32_1;
  { 计算每个块的条带数和块大小 }
  nbStripesPerBlock := (secretSize - XXH_STRIPE_LEN) div XXH_SECRET_CONSUME_RATE;
  block_len := XXH_STRIPE_LEN * nbStripesPerBlock;
  nb_blocks := (len - 1) div block_len;

  { 处理完整的数据块 }
  for n := 0 to nb_blocks - 1 do
  begin
    XXH3_accumulate(@acc, PByte(input) + n * block_len, secret, nbStripesPerBlock);
    XXH3_scrambleAcc_scalar(@acc, PByte(secret) + secretSize - XXH_STRIPE_LEN);
  end;

  { 处理剩余的部分条带 }
  nbStripes := ((len - 1) - (block_len * nb_blocks)) div XXH_STRIPE_LEN;
  XXH3_accumulate(@acc, PByte(input) + nb_blocks * block_len, secret, nbStripes);

  { 处理最后一个条带 }
  p := PByte(input) + len - XXH_STRIPE_LEN;
  XXH3_accumulate_512_scalar(@acc, p, PByte(secret) + secretSize - XXH_STRIPE_LEN - 7);

  { 合并累加器生成128位最终哈希值 }
  Result.low64 := XXH3_mergeAccs(@acc, PByte(secret) + 11, UInt64(len) * XXH_PRIME64_1);
  Result.high64 := XXH3_mergeAccs(@acc, PByte(secret) + secretSize - 64 - 11, not(UInt64(len) * XXH_PRIME64_2));
end;

end.
