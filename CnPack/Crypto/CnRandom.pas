{******************************************************************************}
{                       CnPack For Delphi/C++Builder                           }
{                     中国人自己的开放源码第三方开发包                         }
{                   (C)Copyright 2001-2025 CnPack 开发组                       }
{                   ------------------------------------                       }
{                                                                              }
{            本开发包是开源的自由软件，您可以遵照 CnPack 的发布协议来修        }
{        改和重新发布这一程序。                                                }
{                                                                              }
{            发布这一开发包的目的是希望它有用，但没有任何担保。甚至没有        }
{        适合特定目的而隐含的担保。更详细的情况请参阅 CnPack 发布协议。        }
{                                                                              }
{            您应该已经和开发包一起收到一份 CnPack 发布协议的副本。如果        }
{        还没有，可访问我们的网站：                                            }
{                                                                              }
{            网站地址：https://www.cnpack.org                                  }
{            电子邮件：master@cnpack.org                                       }
{                                                                              }
{******************************************************************************}

unit CnRandom;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：随机数填充单元
* 单元作者：CnPack 开发组 (master@cnpack.org)
* 备    注：本单元封装了 Windows 平台及 MacOS/Linux 平台下的安全随机数发生器
*           对外提供安全随机数填充功能。
* 开发平台：Win7 + Delphi 5.0
* 兼容测试：Win32/Win64/MacOS/Linux + Unicode/NonUnicode
* 本 地 化：该单元无需本地化处理
* 修改记录：2023.01.15 V1.3
*               非 Windows 下全改用 urandom 以支持 Linux
*           2023.01.08 V1.2
*               修正 Win64 下 API 声明参数有误的问题
*           2022.08.22 V1.1
*               优先使用操作系统提供的随机数发生器
*           2020.03.27 V1.0
*               创建单元，从 CnPrime 中独立出来
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils {$IFDEF MSWINDOWS}, Windows {$ENDIF}, Classes, CnNative;

type
  ECnRandomAPIError = class(Exception);

function RandomUInt64: TUInt64;
{* 返回 UInt64 范围内的随机数，在不支持 UInt64 的平台上用 Int64 代替。

   参数：
     （无）

   返回值：TUInt64                        - 返回 UInt64 范围内的随机数
}

function RandomUInt64LessThan(HighValue: TUInt64): TUInt64;
{* 返回大于等于 0 且小于指定 UInt64 值的随机数。

   参数：
     HighValue: TUInt64                   - 指定 UInt64 的随机数上限

   返回值：TUInt64                        - 返回大于等于 0 且小于指定 HighValue 的随机数
}

function RandomInt64: Int64;
{* 返回大于等于 0 且小于 Int64 上限的随机数。

   参数：
     （无）

   返回值：Int64                          - 返回大于等于 0 且小于 Int64 上限的随机数
}

function RandomInt64LessThan(HighValue: Int64): Int64;
{* 返回大于等于 0 且小于指定 Int64 值的随机数，调用者需自行保证 HighValue 大于 0。

   参数：
     HighValue: Int64                     - 指定 Int64 的随机数上限

   返回值：Int64                          - 返回大于等于 0 且小于指定 HighValue 的随机数
}

function RandomUInt32: Cardinal;
{* 返回 UInt32 范围内的随机数。

   参数：
     （无）

   返回值：Cardinal                       - 返回 UInt32 范围内的随机数
}

function RandomUInt32LessThan(HighValue: Cardinal): Cardinal;
{* 返回大于等于 0 且小于指定 UInt32 值的随机数。

   参数：
     HighValue: Cardinal                  - 指定 UInt32 的随机数上限

   返回值：Cardinal                       - 返回大于等于 0 且小于指定 HighValue 的随机数
}

function RandomInt32: Integer;
{* 返回大于等于 0 且小于 Int32 上限的随机数。

   参数：
     （无）

   返回值：Integer                        - 返回大于等于 0 且小于 Int32 上限的随机数
}

function RandomInt32LessThan(HighValue: Integer): Integer;
{* 返回大于等于 0 且小于指定 Int32 的随机数，调用者需自行保证 HighValue 大于 0。

   参数：
     HighValue: Integer                   - 指定 Int32 的随机数上限

   返回值：Integer                        - 返回大于等于 0 且小于指定 HighValue 的随机数
}

function CnKnuthShuffle(ArrayBase: Pointer; ElementByteSize: Integer;
  ElementCount: Integer): Boolean;
{* 高德纳洗牌算法，将 ArrayBase 所指的元素尺寸为 ElementSize 的 ElementCount 个元素均匀洗牌。

   参数：
     ArrayBase: Pointer                   - 待洗牌的内存块地址
     ElementByteSize: Integer             - 待洗牌的每个内存元素也就是每一张牌的字节大小
     ElementCount: Integer                - 内存元素也就是牌的数量

   返回值：Boolean                        - 返回洗牌是否成功
}

function CnRandomFillBytes(Buf: PAnsiChar; BufByteLen: Integer): Boolean;
{* 使用 Windows API 或 /dev/random 设备实现区块随机填充，内部单次初始化随机数引擎并释放。

   参数：
     Buf: PAnsiChar                       - 待填充的内存块地址
     BufByteLen: Integer                  - 待填充的内存块的字节长度

   返回值：Boolean                        - 返回随机填充是否成功
}

function CnRandomFillBytes2(Buf: PAnsiChar; BufByteLen: Integer): Boolean;
{* 使用 Windows API 或 /dev/urandom 设备实现区块随机填充，
   Windows 下使用已预先初始化好的引擎以提速。

   参数：
     Buf: PAnsiChar                       - 待填充的内存块地址
     BufByteLen: Integer                  - 待填充的内存块的字节长度

   返回值：Boolean                        - 返回随机填充是否成功
}

implementation

{$IFDEF MSWINDOWS}

const
  ADVAPI32 = 'advapi32.dll';

  CRYPT_VERIFYCONTEXT = $F0000000;
  CRYPT_NEWKEYSET = $8;
  CRYPT_DELETEKEYSET = $10;

  PROV_RSA_FULL = 1;
  NTE_BAD_KEYSET = $80090016;

function CryptAcquireContext(phProv: PHandle; pszContainer: PAnsiChar;
  pszProvider: PAnsiChar; dwProvType: LongWord; dwFlags: LongWord): BOOL;
  stdcall; external ADVAPI32 name 'CryptAcquireContextA';

function CryptReleaseContext(hProv: THandle; dwFlags: LongWord): BOOL;
  stdcall; external ADVAPI32 name 'CryptReleaseContext';

function CryptGenRandom(hProv: THandle; dwLen: LongWord; pbBuffer: PAnsiChar): BOOL;
  stdcall; external ADVAPI32 name 'CryptGenRandom';

var
  FHProv: THandle = 0;

{$ELSE}

const
  DEV_FILE = '/dev/urandom';

{$ENDIF}

function CnRandomFillBytes(Buf: PAnsiChar; BufByteLen: Integer): Boolean;
var
{$IFDEF MSWINDOWS}
  HProv: THandle;
  Res: DWORD;
  B: Boolean;
{$ELSE}
  F: TFileStream;
{$ENDIF}
begin
  Result := False;
{$IFDEF MSWINDOWS}
  // 使用 Windows API 实现区块随机填充
  HProv := 0;
  B := CryptAcquireContext(@HProv, nil, nil, PROV_RSA_FULL, 0);
  if not B then
    B := CryptAcquireContext(@HProv, nil, nil, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT);

  if not B then
  begin
    Res := GetLastError;
    if Res = NTE_BAD_KEYSET then // KeyContainer 不存在，用新建的方式
    begin
      if not CryptAcquireContext(@HProv, nil, nil, PROV_RSA_FULL, CRYPT_NEWKEYSET) then
        raise ECnRandomAPIError.CreateFmt('Error CryptAcquireContext NewKeySet $%8.8x', [GetLastError]);
    end
    else
        raise ECnRandomAPIError.CreateFmt('Error CryptAcquireContext $%8.8x', [Res]);
  end;

  if HProv <> 0 then
  begin
    try
      Result := CryptGenRandom(HProv, BufByteLen, Buf);
      if not Result then
        raise ECnRandomAPIError.CreateFmt('Error CryptGenRandom $%8.8x', [GetLastError]);
    finally
      CryptReleaseContext(HProv, 0);
    end;
  end;
{$ELSE}
  // MacOS/Linux 下的随机填充实现，采用读取 /dev/urandom 内容的方式，不阻塞
  F := nil;
  try
    F := TFileStream.Create(DEV_FILE, fmOpenRead);
    Result := F.Read(Buf^, BufByteLen) = BufByteLen;
  finally
    F.Free;
  end;
{$ENDIF}
end;

function CnRandomFillBytes2(Buf: PAnsiChar; BufByteLen: Integer): Boolean;
{$IFNDEF MSWINDOWS}
var
  F: TFileStream;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  Result := CryptGenRandom(FHProv, BufByteLen, Buf);
{$ELSE}
  // MacOS/Linux 下的随机填充实现，采用读取 /dev/urandom 内容的方式，不阻塞
  F := nil;
  try
    F := TFileStream.Create(DEV_FILE, fmOpenRead);
    Result := F.Read(Buf^, BufByteLen) = BufByteLen;
  finally
    F.Free;
  end;
{$ENDIF}
end;

function RandomUInt64: TUInt64;
var
  HL: array[0..1] of Cardinal;
begin
  // 优先用系统的随机数发生器
  if not CnRandomFillBytes2(@HL[0], SizeOf(TUInt64)) then
  begin
    // 直接 Random * High(TUInt64) 可能会精度不够导致 Lo 全 FF，因此分开处理
    Randomize;
    HL[0] := Trunc(Random * High(Cardinal) - 1) + 1;
    HL[1] := Trunc(Random * High(Cardinal) - 1) + 1;
  end;

  Result := (TUInt64(HL[0]) shl 32) + HL[1];
end;

function RandomUInt64LessThan(HighValue: TUInt64): TUInt64;
begin
  Result := UInt64Mod(RandomUInt64, HighValue);
end;

function RandomInt64LessThan(HighValue: Int64): Int64;
var
  HL: array[0..1] of Cardinal;
begin
  // 优先用系统的随机数发生器
  if not CnRandomFillBytes2(@HL[0], SizeOf(Int64)) then
  begin
    // 直接 Random * High(Int64) 可能会精度不够导致 Lo 全 FF，因此分开处理
    Randomize;
    HL[0] := Trunc(Random * High(Integer) - 1) + 1;   // Int64 最高位不能是 1，避免负数
    HL[1] := Trunc(Random * High(Cardinal) - 1) + 1;
  end
  else
    HL[0] := HL[0] mod (Cardinal(High(Integer)) + 1);    // Int64 最高位不能是 1，避免负数

  Result := (Int64(HL[0]) shl 32) + HL[1];
  Result := Result mod HighValue; // 未处理 HighValue 小于等于 0 的情形
end;

function RandomInt64: Int64;
begin
  Result := RandomInt64LessThan(High(Int64));
end;

function RandomUInt32: Cardinal;
var
  D: Cardinal;
begin
  // 优先用系统的随机数发生器
  if not CnRandomFillBytes2(@D, SizeOf(Cardinal)) then
  begin
    Randomize;
    D := Trunc(Random * High(Cardinal) - 1) + 1;
  end;

  Result := D;
end;

function RandomUInt32LessThan(HighValue: Cardinal): Cardinal;
begin
  Result := RandomUInt32 mod HighValue;
end;

function RandomInt32: Integer;
begin
  Result := RandomInt32LessThan(High(Integer));
end;

function RandomInt32LessThan(HighValue: Integer): Integer;
var
  D: Cardinal;
begin
  // 优先用系统的随机数发生器
  if not CnRandomFillBytes2(@D, SizeOf(Cardinal)) then
  begin
    Randomize;
    D := Trunc(Random * High(Integer) - 1) + 1;
  end
  else
    D := D mod (Cardinal(High(Integer)) + 1);

  Result := Integer(Int64(D) mod Int64(HighValue)); // 未处理 HighValue 小于等于 0 的情形
end;

function CnKnuthShuffle(ArrayBase: Pointer; ElementByteSize: Integer;
  ElementCount: Integer): Boolean;
var
  I, R: Integer;
  B1, B2: Pointer;
begin
  Result := False;
  if (ArrayBase = nil) or (ElementByteSize <= 0) or (ElementCount < 0) then // 超大的数组先不处理
    Exit;

  Result := True;
  if ElementCount <= 1 then // 没元素或只有一个元素时不用洗
    Exit;

  for I := ElementCount - 1 downto 0 do
  begin
    R := RandomInt32LessThan(I + 1);  // 0 到 I 这个闭区间内的随机数，所以上限要加 1
    B1 := Pointer(TCnNativeUInt(ArrayBase) + TCnNativeUInt(I * ElementByteSize));
    B2 := Pointer(TCnNativeUInt(ArrayBase) + TCnNativeUInt(R * ElementByteSize));
    MemorySwap(B1, B2, ElementByteSize);
  end;
  Result := True;
end;

{$IFDEF MSWINDOWS}

procedure StartRandom;
var
  Res: DWORD;
  B: Boolean;
begin
  FHProv := 0;
  B := CryptAcquireContext(@FHProv, nil, nil, PROV_RSA_FULL, 0);
  if not B then
    B := CryptAcquireContext(@FHProv, nil, nil, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT);

  if not B then
  begin
    Res := GetLastError;
    if Res = NTE_BAD_KEYSET then // KeyContainer 不存在，用新建的方式
    begin
      if not CryptAcquireContext(@FHProv, nil, nil, PROV_RSA_FULL, CRYPT_NEWKEYSET) then
        raise ECnRandomAPIError.CreateFmt('Error CryptAcquireContext NewKeySet $%8.8x', [GetLastError]);
    end
    else
        raise ECnRandomAPIError.CreateFmt('Error CryptAcquireContext $%8.8x', [Res]);
  end;
end;

procedure StopRandom;
begin
  if FHProv <> 0 then
  begin
    CryptReleaseContext(FHProv, 0);
    FHProv := 0;
  end;
end;

initialization
  StartRandom;

finalization
  StopRandom;

{$ENDIF}

end.
