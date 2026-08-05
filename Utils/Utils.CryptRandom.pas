unit Utils.CryptRandom;
{*
  加密随机数生成工具单元
  
  提供跨平台的加密安全随机数生成功能
  - Windows: 使用 BCryptGenRandom 或 SystemFunction036 (RtlGenRandom)
  - Linux: 优先使用 getrandom, 不可用时回退 /dev/urandom
  - macOS/iOS/Android/FreeBSD: 使用 arc4random_buf
  - 其他 POSIX: 使用 /dev/urandom
  - Windows/Linux/其他 POSIX 的底层失败返回 False
  - arc4random_buf 平台遵循系统“始终成功”契约并返回 True
  
  注意: 不使用 Pascal 自带的 Random/RandomRange 等函数，因为:
  1. 内置随机数生成器使用伪随机算法(如线性同余)，可预测性强
  2. 加密场景需要密码学安全的随机数(CSPRNG)，内置函数不满足要求
  3. 本单元使用操作系统提供的加密级随机数源，确保不可预测性
*}

{$I zLib.inc}

{$IF defined(MACOS) or defined(IOS) or defined(ANDROID) or defined(FREEBSD)}
  {$DEFINE CRYPT_USE_ARC4RANDOM}
{$ENDIF}
{$IF defined(LINUX) and not defined(CRYPT_USE_ARC4RANDOM)}
  {$DEFINE CRYPT_USE_GETRANDOM}
{$ENDIF}

interface

/// <summary>
///   使用操作系统提供的密码学安全随机数生成器填充缓冲区。
/// </summary>
/// <param name="ABuf">
///   接收随机字节的目标存储区。调用者必须保证该存储区至少包含
///   ASize 个可写字节。
/// </param>
/// <param name="ASize">
///   要写入的字节数。负数直接返回 False；零直接返回 True，且不会
///   访问或修改 ABuf。
/// </param>
/// <returns>
///   成功填满全部 ASize 个字节时返回 True；底层随机源不可用或读取
///   失败时返回 False。正长度调用失败时，ABuf 的内容未定义，可能已被
///   部分修改，调用者不得使用其中的数据。
/// </returns>
/// <remarks>
///   本函数使用各平台的系统 CSPRNG，不受 Randomize 或 RandSeed 影响，
///   也绝不回退到 Pascal 的 Random。Windows 使用 BCryptGenRandom，并在
///   失败时回退到 SystemFunction036；Linux 优先使用 getrandom，并回退到
///   /dev/urandom；macOS、iOS、Android 和 FreeBSD 使用 arc4random_buf；
///   其他 POSIX 平台使用 /dev/urandom。
/// </remarks>
function TryFillCryptRandomBytes(var ABuf; const ASize: Integer): Boolean;

/// <summary>
///   生成位于 [0, ARange) 的密码学安全随机整数。
/// </summary>
/// <remarks>
///   ARange 必须大于 0。无效范围或系统 CSPRNG 失败时返回 False
///   并将 AValue 置为 0。本函数不受 Randomize 或 RandSeed 影响。
/// </remarks>
function TryCryptRandom(const ARange: Integer;
  out AValue: Integer): Boolean; overload;

/// <summary>
///   在两个边界之间生成密码学安全随机整数。
/// </summary>
/// <remarks>
///   返回归一化后的半开区间 [Min(ARangeFrom, ARangeTo),
///   Max(ARangeFrom, ARangeTo))，支持负数、跨零和反向边界。两个边界
///   相等时直接成功返回该值。系统 CSPRNG 失败时返回 False
///   并将 AValue 置为 0。本函数不受 Randomize 或 RandSeed 影响。
/// </remarks>
function TryCryptRandom(const ARangeFrom, ARangeTo: Integer;
  out AValue: Integer): Boolean; overload;

/// <summary>
///   生成位于 [0, 1) 的密码学安全随机浮点数。
/// </summary>
/// <remarks>
///   使用 53 个随机位构造 Double。系统 CSPRNG 失败时返回 False
///   并将 AValue 置为 0。本函数不受 Randomize 或 RandSeed 影响。
/// </remarks>
function TryCryptRandom(out AValue: Double): Boolean; overload;

implementation

uses
  SysUtils,
  Classes
  {$IFDEF MSWINDOWS}
  , Windows
  {$ENDIF}
  {$IF DEFINED(DELPHI) AND NOT DEFINED(MSWINDOWS)}
  , Posix.Base
  {$ENDIF}
  {$IFDEF CRYPT_USE_GETRANDOM}
    {$IFDEF DELPHI}
  , Posix.Dlfcn
    {$ELSE}
  , dl
    {$ENDIF}
  {$ENDIF}
  ;

{$IFDEF CRYPT_USE_ARC4RANDOM}
  {$IFDEF FPC}{$LINKLIB c}{$ENDIF}
procedure arc4random_buf(ABuf: Pointer; ASize: NativeUInt); cdecl;
  external {$IFDEF DELPHI}libc name _PU + 'arc4random_buf'{$ENDIF};
{$ENDIF}

{$IFDEF MSWINDOWS}
const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;
  STATUS_SUCCESS = 0;

type
  TBCryptGenRandom = function(hAlgorithm: Pointer; pbBuffer: Pointer;
    cbBuffer, dwFlags: Cardinal): LongInt; stdcall;
  TSystemFunction036 = function(RandomBuffer: Pointer;
    RandomBufferLength: Cardinal): LongBool; stdcall;

var
  GBCryptModule: HMODULE;
  GAdvapiModule: HMODULE;
  GBCryptGenRandom: TBCryptGenRandom;
  GSystemFunction036: TSystemFunction036;

procedure InitCryptRandomLibraries;
begin
  GBCryptModule := LoadLibrary('bcrypt.dll');
  if (GBCryptModule <> 0) then
    GBCryptGenRandom := TBCryptGenRandom(GetProcAddress(GBCryptModule, 'BCryptGenRandom'));

  GAdvapiModule := LoadLibrary('advapi32.dll');
  if (GAdvapiModule <> 0) then
    GSystemFunction036 := TSystemFunction036(GetProcAddress(GAdvapiModule, 'SystemFunction036'));
end;

procedure DoneCryptRandomLibraries;
begin
  GBCryptGenRandom := nil;
  GSystemFunction036 := nil;

  if (GBCryptModule <> 0) then
  begin
    FreeLibrary(GBCryptModule);
    GBCryptModule := 0;
  end;

  if (GAdvapiModule <> 0) then
  begin
    FreeLibrary(GAdvapiModule);
    GAdvapiModule := 0;
  end;
end;

function TryFillByBCrypt(const ABuf: Pointer; const ASize: Cardinal): Boolean;
begin
  if not Assigned(GBCryptGenRandom) then Exit(False);

  Result := GBCryptGenRandom(nil, ABuf, ASize, BCRYPT_USE_SYSTEM_PREFERRED_RNG) = STATUS_SUCCESS;
end;

function TryFillBySystemFunction036(const ABuf: Pointer; const ASize: Cardinal): Boolean;
begin
  if not Assigned(GSystemFunction036) then Exit(False);

  Result := GSystemFunction036(ABuf, ASize);
end;
{$ENDIF}

{$IFDEF CRYPT_USE_GETRANDOM}
type
  TGetRandom = function(ABuf: Pointer; ASize: NativeUInt;
    AFlags: Cardinal): NativeInt; cdecl;

var
  GGetRandom: TGetRandom;

procedure InitCryptRandomLinux;
begin
  GGetRandom := TGetRandom(dlsym(RTLD_DEFAULT, 'getrandom'));
end;

function TryFillByGetRandom(const ABuf: Pointer;
  const ASize: Integer): Boolean;
var
  LRead: NativeInt;
  LTotal: Integer;
  P: PByte;
begin
  Result := False;
  if not Assigned(GGetRandom) then Exit;

  LTotal := 0;
  P := ABuf;
  while LTotal < ASize do
  begin
    LRead := GGetRandom(P, NativeUInt(ASize - LTotal), 0);
    if (LRead <= 0) or (LRead > ASize - LTotal) then Exit;

    Inc(P, Integer(LRead));
    Inc(LTotal, Integer(LRead));
  end;

  Result := True;
end;
{$ENDIF}

{$IF not defined(MSWINDOWS) and not defined(CRYPT_USE_ARC4RANDOM)}
function TryFillByUrandom(const ABuf: Pointer;
  const ASize: Integer): Boolean;
var
  LStream: TFileStream;
  LRead: Integer;
  LTotal: Integer;
  P: PByte;
begin
  Result := False;
  try
    LStream := TFileStream.Create('/dev/urandom',
      fmOpenRead or fmShareDenyNone);
    try
      LTotal := 0;
      P := ABuf;
      while LTotal < ASize do
      begin
        LRead := LStream.Read(P^, ASize - LTotal);
        if LRead <= 0 then Exit;

        Inc(P, LRead);
        Inc(LTotal, LRead);
      end;

      Result := True;
    finally
      LStream.Free;
    end;
  except
    Result := False;
  end;
end;
{$ENDIF}

function TryFillCryptRandomBytes(var ABuf; const ASize: Integer): Boolean;
begin
  if (ASize < 0) then Exit(False);
  if (ASize = 0) then Exit(True);

{$IFDEF MSWINDOWS}
  Result := TryFillByBCrypt(@ABuf, Cardinal(ASize));
  if not Result then
    Result := TryFillBySystemFunction036(@ABuf, Cardinal(ASize));
{$ELSEIF defined(CRYPT_USE_ARC4RANDOM)}
  arc4random_buf(@ABuf, NativeUInt(ASize));
  Result := True;
{$ELSEIF defined(CRYPT_USE_GETRANDOM)}
  Result := TryFillByGetRandom(@ABuf, ASize);
  if not Result then
    Result := TryFillByUrandom(@ABuf, ASize);
{$ELSE}
  Result := TryFillByUrandom(@ABuf, ASize);
{$ENDIF}
end;

{
  将一个均匀的 32 位随机数无偏地映射到 [0, ASpan)。

  UInt32 共有 2^32 个等概率取值。如果 2^32 不能被 ASpan 整除，
  直接使用 LRandom mod ASpan 会使较小的余数比其他余数多一个
  映射来源，产生“模偏差”。

  LLimit 是不大于 2^32 的最大 ASpan 倍数。只接受小于 LLimit
  的随机数，就能将可接受区间分成整数个长度为 ASpan 的完整块；
  每个余数在每个块中恰好出现一次，因此最后取模不会有偏差。

  例如 ASpan=10 时，2^32 mod 10=6；舍弃 UInt32 末尾的 6 个
  取值后，余数 0..9 具有完全相同的出现次数。

  单次 UInt32 只能覆盖最多 2^32 个状态，而当前公共 Integer
  重载的最大可能跨度为 2^32-1，因此 ASpan 上限为 High(UInt32)。
}
function TryCryptRandomOffset(const ASpan: UInt64;
  out AOffset: UInt64): Boolean;
const
  // UInt32 可能取值的总数，比 High(UInt32) 大 1。
  UINT32_VALUE_COUNT: UInt64 = $100000000;
var
  LLimit: UInt64;
  LRandom: UInt32;
begin
  AOffset := 0;
  if (ASpan = 0) or (ASpan > High(UInt32)) then Exit(False);

  LRandom := 0;
  // 舍弃 [LLimit, 2^32) 这个不足一个 ASpan 的尾部区间。
  LLimit := UINT32_VALUE_COUNT - (UINT32_VALUE_COUNT mod ASpan);
  repeat
    if not TryFillCryptRandomBytes(LRandom, SizeOf(LRandom)) then
      Exit(False);
  until UInt64(LRandom) < LLimit;

  AOffset := UInt64(LRandom) mod ASpan;
  Result := True;
end;

function TryCryptRandom(const ARange: Integer;
  out AValue: Integer): Boolean;
var
  LOffset: UInt64;
begin
  AValue := 0;
  if ARange <= 0 then Exit(False);
  if ARange = 1 then Exit(True);
  if not TryCryptRandomOffset(UInt64(ARange), LOffset) then Exit(False);

  AValue := Integer(LOffset);
  Result := True;
end;

function TryCryptRandom(const ARangeFrom, ARangeTo: Integer;
  out AValue: Integer): Boolean;
var
  LLower: Int64;
  LOffset: UInt64;
  LSpan: UInt64;
  LUpper: Int64;
begin
  AValue := 0;
  if ARangeFrom = ARangeTo then
  begin
    AValue := ARangeFrom;
    Exit(True);
  end;

  if ARangeFrom < ARangeTo then
  begin
    LLower := ARangeFrom;
    LUpper := ARangeTo;
  end else
  begin
    LLower := ARangeTo;
    LUpper := ARangeFrom;
  end;

  LSpan := UInt64(LUpper - LLower);
  if not TryCryptRandomOffset(LSpan, LOffset) then Exit(False);

  AValue := Integer(LLower + Int64(LOffset));
  Result := True;
end;

{
  IEEE 754 Double 的有效精度为 53 个二进制位（包含隐含的最高位）。
  64 位 CSPRNG 输出右移 11 位后，得到均匀分布在
  [0, 2^53-1] 上的整数 K。

  将 K 乘以 2^-53，可得到精确对齐 Double 有效位数的离散值
  K/2^53。最大值为 1-2^-53，所以结果一定位于 [0, 1)，永远
  不会因为除以最大整数而产生 1.0。

  CSPRNG 的每个输出位都是均匀且不可预测的，因此舍弃 11 个低位
  只是为了匹配 Double 的精度，不会降低剩余 53 位的均匀性。
}
function TryCryptRandom(out AValue: Double): Boolean;
const
  // 2^-53；二的整数次幂可被二进制浮点数精确表示。
  DOUBLE_RANDOM_UNIT: Double = 1.0 / 9007199254740992.0;
var
  LRandom: UInt64;
begin
  AValue := 0;
  LRandom := 0;
  if not TryFillCryptRandomBytes(LRandom, SizeOf(LRandom)) then Exit(False);

  AValue := Double(LRandom shr 11) * DOUBLE_RANDOM_UNIT;
  Result := True;
end;

initialization
{$IFDEF MSWINDOWS}
  InitCryptRandomLibraries;
{$ENDIF}
{$IFDEF CRYPT_USE_GETRANDOM}
  InitCryptRandomLinux;
{$ENDIF}

finalization
{$IFDEF MSWINDOWS}
  DoneCryptRandomLibraries;
{$ENDIF}

end.
