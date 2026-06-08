{******************************************************************************}
{                       CnPack For Delphi/C++Builder                           }
{                     中国人自己的开放源码第三方开发包                         }
{                   (C)Copyright 2001-2026 CnPack 开发组                       }
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

unit CnSM3;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：国家商用密码 SM3 杂凑算法实现单元
* 单元作者：CnPack 开发组（master@cnpack.org)
*           参考国密算法公开文档《SM3 Cryptographic Hash Algorith》
*           http://www.oscca.gov.cn/UpFile/20101222141857786.pdf
*           并参考了部分 goldboar 的 C 代码
* 备    注：本单元实现了国家商用密码 SM3 杂凑算法及对应的 HMAC 算法。
*           实现过程参考国密算法公开文档《SM3 Cryptographic Hash Algorith》。
* 开发平台：Windows 7 + Delphi 5.0
* 兼容测试：PWin9X/2000/XP/7 + Delphi 5/6
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2019.12.12 V1.2
*               支持 TBytes
*           2019.04.15 V1.1
*               支持 Win32/Win64/MacOS
*           2014.09.23 V1.0
*               移植并创建单元
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  Classes, SysUtils, CnNative, CnConsts {$IFDEF MSWINDOWS}, Windows {$ENDIF};

type
  PCnSM3Digest = ^TCnSM3Digest;
  {* SM3 杂凑结果指针}
  TCnSM3Digest = array[0..31] of Byte;
  {* SM3 杂凑结果，32 字节}

  TCnSM3Context = packed record
  {* SM3 的上下文结构}
    Total: array[0..1] of Cardinal;     {!< number of bytes processed  }
    State: array[0..7] of Cardinal;     {!< intermediate digest state  }
    Buffer: array[0..63] of Byte;       {!< data block being processed }
    Ipad: array[0..63] of Byte;         {!< HMAC: inner padding        }
    Opad: array[0..63] of Byte;         {!< HMAC: outer padding        }
  end;
  PCnSM3Context = ^TCnSM3Context;

  TCnSM3CalcProgressFunc = procedure (ATotal, AProgress: Int64;
    var Cancel: Boolean) of object;
  {* SM3 杂凑进度回调事件类型声明}

function SM3(Input: PAnsiChar; ByteLength: Cardinal): TCnSM3Digest;
{* 对数据块进行 SM3 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

function SM3Buffer(const Buffer; Count: Cardinal): TCnSM3Digest;
{* 对数据块进行 SM3 计算。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

function SM3Bytes(const Data: TBytes): TCnSM3Digest;
{* 对字节数组进行 SM3 计算。

   参数：
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

function SM3String(const Str: string): TCnSM3Digest;
{* 对 String 类型数据进行 SM3 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

function SM3StringA(const Str: AnsiString): TCnSM3Digest;
{* 对 AnsiString 类型数据进行 SM3 计算。

   参数：
     const Str: AnsiString                - 待计算的字符串

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

function SM3StringW(const Str: WideString): TCnSM3Digest;
{* 对 WideString 类型字符串进行转换并进行 SM3 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

{$IFDEF UNICODE}

function SM3UnicodeString(const Str: string): TCnSM3Digest;
{* 对 UnicodeString 类型数据进行直接的 SM3 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

{$ELSE}

function SM3UnicodeString(const Str: WideString): TCnSM3Digest;
{* 对 UnicodeString 类型数据进行直接的 SM3 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

{$ENDIF}

function SM3File(const FileName: string; CallBack: TCnSM3CalcProgressFunc = nil): TCnSM3Digest;
{* 对指定文件内容进行 SM3 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSM3CalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

function SM3Stream(Stream: TStream; CallBack: TCnSM3CalcProgressFunc = nil): TCnSM3Digest;
{* 对指定流数据进行 SM3 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSM3CalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSM3Digest                   - 返回的 SM3 杂凑值
}

// 以下三个函数用于外部持续对数据进行零散的 SM3 计算，SM3Update 可多次被调用

procedure SM3Init(var Context: TCnSM3Context);
{* 初始化一轮 SM3 计算上下文，准备计算 SM3 结果

   参数：
     var Context: TCnSM3Context           - 待初始化的 SM3 上下文

   返回值：（无）
}

procedure SM3Update(var Context: TCnSM3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SM3 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSM3Context           - SM3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SM3Final(var Context: TCnSM3Context; var Digest: TCnSM3Digest);
{* 结束本轮计算，将 SM3 结果返回至 Digest 中

   参数：
     var Context: TCnSM3Context           - SM3 上下文
     var Digest: TCnSM3Digest             - 返回的 SM3 杂凑值

   返回值：（无）
}

function SM3Print(const Digest: TCnSM3Digest): string;
{* 以十六进制格式输出 SM3 杂凑值。

   参数：
     const Digest: TCnSM3Digest           - 指定的 SM3 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SM3Match(const D1: TCnSM3Digest; const D2: TCnSM3Digest): Boolean;
{* 比较两个 SM3 杂凑值是否相等。

   参数：
     const D1: TCnSM3Digest               - 待比较的 SM3 杂凑值一
     const D2: TCnSM3Digest               - 待比较的 SM3 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SM3DigestToStr(const Digest: TCnSM3Digest): string;
{* SM3 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSM3Digest           - 待转换的 SM3 杂凑值

   返回值：string                         - 返回的字符串
}

procedure SM3Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSM3Digest);
{* 基于 SM3 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SM3 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SM3 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSM3Digest             - 返回的 SM3 杂凑值

   返回值：（无）
}

function SM3HmacBytes(const Key: TBytes; const Data: TBytes): TCnSM3Digest;
{* 对字节数组进行基于 MD5 的 HMAC 计算。

   参数：
     const Key: TBytes                    - 待参与 SM3 计算的密钥字节数组
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnMD5Digest                   - 返回的 SM3 杂凑值
}

implementation

const
  SM3Padding: array[0..63] of Byte =
    (
      $80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    );

  SM3_T: array[0..63] of Cardinal = (
    $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519,
    $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519, $79CC4519,
    $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A,
    $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A,
    $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A,
    $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A,
    $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A,
    $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A, $7A879D8A
  );

  MAX_FILE_SIZE = 512 * 1024 * 1024;
  // If file size <= this size (bytes), using Mapping, else stream

  HMAC_SM3_BLOCK_SIZE_BYTE = 64;
  HMAC_SM3_OUTPUT_LENGTH_BYTE = 32;

type
  TSM3ProcessData = array[0..63] of Byte;

procedure GetULongBe(var N: Cardinal; B: PAnsiChar; I: Integer); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
var
  D: Cardinal;
begin
  D := (Cardinal(B[I]) shl 24) or (Cardinal(B[I + 1]) shl 16) or
    (Cardinal(B[I + 2]) shl 8) or (Cardinal(B[I + 3]));
  N := D;
end;

procedure PutULongBe(N: Cardinal; B: PAnsiChar; I: Integer); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  B[I] := AnsiChar(N shr 24);
  B[I + 1] := AnsiChar(N shr 16);
  B[I + 2] := AnsiChar(N shr 8);
  B[I + 3] := AnsiChar(N);
end;

function FF0(X, Y, Z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := X xor Y xor Z;
end;

function FF1(X, Y, Z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and Y) or (Y and Z) or (X and Z);
end;

function GG0(X, Y, Z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := X xor Y xor Z;
end;

function GG1(X, Y, Z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and Y) or ((not X) and Z);
end;

function SM3Shl(X: Cardinal; N: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and $FFFFFFFF) shl N;
end;

// 循环左移。注意 N 为 0 或 32 时返回值仍为 X，N 为 33 时返回值等于 N 为 1 时的返回值
function ROTL(X: Cardinal; N: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := SM3Shl(X, N) or (X shr (32 - N));
end;

function P0(X: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := X xor ROTL(X, 9) xor ROTL(X, 17);
end;

function P1(X: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := X xor ROTL(X, 15) xor ROTL(X, 23);
end;

procedure SM3Init(var Context: TCnSM3Context);
begin
  Context.Total[0] := 0;
  Context.Total[1] := 0;

  Context.State[0] := $7380166F;
  Context.State[1] := $4914B2B9;
  Context.State[2] := $172442D7;
  Context.State[3] := $DA8A0600;
  Context.State[4] := $A96F30BC;
  Context.State[5] := $163138AA;
  Context.State[6] := $E38DEE4D;
  Context.State[7] := $B0FB0E4E;

  FillChar(Context.Buffer, SizeOf(Context.Buffer), 0);
end;

// 一次处理 64 字节也就是 512 位数据块
procedure SM3Process(var Context: TCnSM3Context; Data: PAnsiChar);
var
  SS1, SS2, TT1, TT2: Cardinal;
  W: array[0..67] of Cardinal;
  W1: array[0..63] of Cardinal;
  A, B, C, D, E, F, G, H: Cardinal;
  Temp1, Temp2: Cardinal;
  J: Integer;
begin
  GetULongBe(W[ 0], Data,  0);
  GetULongBe(W[ 1], Data,  4);
  GetULongBe(W[ 2], Data,  8);
  GetULongBe(W[ 3], Data, 12);
  GetULongBe(W[ 4], Data, 16);
  GetULongBe(W[ 5], Data, 20);
  GetULongBe(W[ 6], Data, 24);
  GetULongBe(W[ 7], Data, 28);
  GetULongBe(W[ 8], Data, 32);
  GetULongBe(W[ 9], Data, 36);
  GetULongBe(W[10], Data, 40);
  GetULongBe(W[11], Data, 44);
  GetULongBe(W[12], Data, 48);
  GetULongBe(W[13], Data, 52);
  GetULongBe(W[14], Data, 56);
  GetULongBe(W[15], Data, 60);

  for J := 16 to 67 do
  begin
    Temp1 := W[J - 16] xor W[J - 9];
    Temp2 := ROTL(W[J - 3], 15);
    W[J] := P1(Temp1 xor Temp2) xor (ROTL(W[J - 13], 7) xor W[J - 6]);
  end;

  for J := 0 to 63 do
    W1[J] := W[J] xor W[J + 4];

  // 已经处理好俩数组W/W1的值。

  A := Context.State[0];
  B := Context.State[1];
  C := Context.State[2];
  D := Context.State[3];
  E := Context.State[4];
  F := Context.State[5];
  G := Context.State[6];
  H := Context.State[7];

  for J := 0 to 15 do
  begin
    SS1 := ROTL((ROTL(A, 12) + E + ROTL(SM3_T[J], J)), 7);
    SS2 := SS1 xor ROTL(A, 12);
    TT1 := FF0(A, B, C) + D + SS2 + W1[J];
    TT2 := GG0(E, F, G) + H + SS1 + W[J];
    D := C;
    C := ROTL(B, 9);
    B := A;
    A := TT1;
    H := G;
    G := ROTL(F, 19);
    F := E;
    E := P0(TT2);
  end;

  for J := 16 to 63 do
  begin
    SS1 := ROTL((ROTL(A, 12) + E + ROTL(SM3_T[J], J)), 7);
    SS2 := SS1 xor ROTL(A, 12);
    TT1 := FF1(A, B, C) + D + SS2 + W1[J];
    TT2 := GG1(E, F, G) + H + SS1 + W[J];
    D := C;
    C := ROTL(B,9);
    B := A;
    A := TT1;
    H := G;
    G := ROTL(F,19);
    F := E;
    E := P0(TT2);
  end;

  Context.State[0] := Context.State[0] xor A;
  Context.State[1] := Context.State[1] xor B;
  Context.State[2] := Context.State[2] xor C;
  Context.State[3] := Context.State[3] xor D;
  Context.State[4] := Context.State[4] xor E;
  Context.State[5] := Context.State[5] xor F;
  Context.State[6] := Context.State[6] xor G;
  Context.State[7] := Context.State[7] xor H;

  // 本轮无误
end;

procedure SM3UpdateW(var Context: TCnSM3Context; Input: PWideChar; CharLength: Cardinal);
var
{$IFDEF MSWINDOWS}
  pContent: PAnsiChar;
  iLen: Cardinal;
{$ELSE}
  S: string; // 必须是 UnicodeString
  A: AnsiString;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  GetMem(pContent, CharLength * SizeOf(WideChar));
  try
    iLen := WideCharToMultiByte(0, 0, Input, CharLength, // 代码页默认用 0
      PAnsiChar(pContent), CharLength * SizeOf(WideChar), nil, nil);
    SM3Update(Context, pContent, iLen);
  finally
    FreeMem(pContent);
  end;
{$ELSE}  // MacOS 下直接把 UnicodeString 转成 AnsiString 计算，不支持非 Windows 非 Unicode 平台
  S := StrNew(Input);
  A := AnsiString(S);
  SM3Update(Context, @A[1], Length(A));
{$ENDIF}
end;

procedure SM3Update(var Context: TCnSM3Context; Input: PAnsiChar; ByteLength: Cardinal);
var
  Fill, Left: Cardinal;
begin
  if (Input = nil) or (ByteLength <= 0) then
    Exit;

  Left := Context.Total[0] and $3F;
  Fill := 64 - Left;

  Context.Total[0] := Context.Total[0] + ByteLength;
  Context.Total[0] := Context.Total[0] and $FFFFFFFF;

  if Context.Total[0] < ByteLength then
    Context.Total[1] := Context.Total[1] + 1;

  if (Left <> 0) and (ByteLength >= Fill) then
  begin
    Move(Input^, Context.Buffer[Left], Fill);
    SM3Process(Context, @(Context.Buffer[0]));
    Input := Input + Fill;
    ByteLength := ByteLength - Fill;
    Left := 0;
  end;

  while ByteLength >= 64 do
  begin
    SM3Process(Context, Input);
    Input := Input + 64;
    ByteLength := ByteLength - 64;
  end;

  if ByteLength > 0 then
    Move(Input^, Context.Buffer[Left], ByteLength);
end;

procedure SM3Final(var Context: TCnSM3Context; var Digest: TCnSM3Digest);
var
  Last, Padn: Cardinal;
  High, Low: Cardinal;
  MsgLen: array[0..7] of Byte;
begin
  High := (Context.Total[0] shr 29) or (Context.Total[1] shl 3);
  Low := Context.Total[0] shl 3;

  PutULongBe(High, @(MsgLen[0]), 0);
  PutULongBe(Low, @(MsgLen[0]), 4);

  Last := Context.Total[0] and $3F;
  if Last < 56 then
    Padn := 56 - Last
  else
    Padn := 120 - Last;

  SM3Update(Context, @(SM3Padding[0]), Padn);
  SM3Update(Context, @(MsgLen[0]), 8);

  PutULongBe(Context.State[0], @Digest,  0);
  PutULongBe(Context.State[1], @Digest,  4);
  PutULongBe(Context.State[2], @Digest,  8);
  PutULongBe(Context.State[3], @Digest, 12);
  PutULongBe(Context.State[4], @Digest, 16);
  PutULongBe(Context.State[5], @Digest, 20);
  PutULongBe(Context.State[6], @Digest, 24);
  PutULongBe(Context.State[7], @Digest, 28);
end;

function SM3(Input: PAnsiChar; ByteLength: Cardinal): TCnSM3Digest;
var
  Context: TCnSM3Context;
begin
  SM3Init(Context);
  SM3Update(Context, Input, ByteLength);
  SM3Final(Context, Result);
end;

procedure SM3HmacInit(var Context: TCnSM3Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSM3Digest;
begin
  if KeyLength > HMAC_SM3_BLOCK_SIZE_BYTE then
  begin
    Sum := SM3Buffer(Key^, KeyLength);
    KeyLength := HMAC_SM3_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SM3_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SM3_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SM3Init(Context);
  SM3Update(Context, @(Context.Ipad[0]), HMAC_SM3_BLOCK_SIZE_BYTE);
end;

procedure SM3HmacUpdate(var Context: TCnSM3Context; Input: PAnsiChar; Length: Cardinal);
begin
  SM3Update(Context, Input, Length);
end;

procedure SM3HmacFinal(var Context: TCnSM3Context; var Output: TCnSM3Digest);
var
  Len: Integer;
  TmpBuf: TCnSM3Digest;
begin
  Len := HMAC_SM3_OUTPUT_LENGTH_BYTE;
  SM3Final(Context, TmpBuf);
  SM3Init(Context);
  SM3Update(Context, @(Context.Opad[0]), HMAC_SM3_BLOCK_SIZE_BYTE);
  SM3Update(Context, @(TmpBuf[0]), Len);
  SM3Final(Context, Output);
end;

procedure SM3Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSM3Digest);
var
  Context: TCnSM3Context;
begin
  SM3HmacInit(Context, Key, KeyByteLength);
  SM3HmacUpdate(Context, Input, ByteLength);
  SM3HmacFinal(Context, Output);
end;

function SM3HmacBytes(const Key: TBytes; const Data: TBytes): TCnSM3Digest;
var
  Context: TCnSM3Context;
begin
  SM3HmacInit(Context, PAnsiChar(@Key[0]), Length(Key));
  SM3HmacUpdate(Context, PAnsiChar(@Data[0]), Length(Data));
  SM3HmacFinal(Context, Result);
end;

function SM3Buffer(const Buffer; Count: Cardinal): TCnSM3Digest;
var
  Context: TCnSM3Context;
begin
  SM3Init(Context);
  SM3Update(Context, PAnsiChar(@Buffer), Count);
  SM3Final(Context, Result);
end;

function SM3Bytes(const Data: TBytes): TCnSM3Digest;
var
  Context: TCnSM3Context;
begin
  SM3Init(Context);
  SM3Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SM3Final(Context, Result);
end;

function SM3String(const Str: string): TCnSM3Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SM3StringA(AStr);
end;

function SM3StringA(const Str: AnsiString): TCnSM3Digest;
var
  Context: TCnSM3Context;
begin
  SM3Init(Context);
  SM3Update(Context, PAnsiChar(Str), Length(Str));
  SM3Final(Context, Result);
end;

function SM3StringW(const Str: WideString): TCnSM3Digest;
var
  Context: TCnSM3Context;
begin
  SM3Init(Context);
  SM3UpdateW(Context, PWideChar(Str), Length(Str));
  SM3Final(Context, Result);
end;

{$IFDEF UNICODE}
function SM3UnicodeString(const Str: string): TCnSM3Digest;
{$ELSE}
function SM3UnicodeString(const Str: WideString): TCnSM3Digest;
{$ENDIF}
var
  Context: TCnSM3Context;
begin
  SM3Init(Context);
  SM3Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SM3Final(Context, Result);
end;

function InternalSM3Stream(Stream: TStream; const BufSize: Cardinal; var D:
  TCnSM3Digest; CallBack: TCnSM3CalcProgressFunc): Boolean;
var
  Context: TCnSM3Context;
  Buf: PAnsiChar;
  BufLen: Cardinal;
  Size: Int64;
  ReadBytes: Cardinal;
  TotalBytes: Int64;
  SavePos: Int64;
  CancelCalc: Boolean;
begin
  Result := False;
  Size := Stream.Size;
  SavePos := Stream.Position;
  TotalBytes := 0;
  if Size = 0 then Exit;
  if Size < BufSize then BufLen := Size
  else BufLen := BufSize;

  CancelCalc := False;
  SM3Init(Context);
  GetMem(Buf, BufLen);
  try
    Stream.Position := 0;
    repeat
      ReadBytes := Stream.Read(Buf^, BufLen);
      if ReadBytes <> 0 then
      begin
        Inc(TotalBytes, ReadBytes);
        SM3Update(Context, Buf, ReadBytes);
        if Assigned(CallBack) then
        begin
          CallBack(Size, TotalBytes, CancelCalc);
          if CancelCalc then Exit;
        end;
      end;
    until (ReadBytes = 0) or (TotalBytes = Size);
    SM3Final(Context, D);
    Result := True;
  finally
    FreeMem(Buf, BufLen);
    Stream.Position := SavePos;
  end;
end;

function SM3File(const FileName: string;
  CallBack: TCnSM3CalcProgressFunc): TCnSM3Digest;
var
{$IFDEF MSWINDOWS}
  FileHandle: THandle;
  MapHandle: THandle;
  ViewPointer: Pointer;
  Context: TCnSM3Context;
{$ENDIF}
  Stream: TStream;
  FileIsZeroSize: Boolean;

  function FileSizeIsLargeThanMaxOrCanNotMap(const AFileName: string; out IsEmpty: Boolean): Boolean;
{$IFDEF MSWINDOWS}
  var
    H: THandle;
    Info: BY_HANDLE_FILE_INFORMATION;
    Rec : Int64Rec;
{$ENDIF}
  begin
{$IFDEF MSWINDOWS}
    Result := False;
    IsEmpty := False;
    H := CreateFile(PChar(FileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      if not GetFileInformationByHandle(H, Info) then Exit;
    finally
      CloseHandle(H);
    end;
    Rec.Lo := Info.nFileSizeLow;
    Rec.Hi := Info.nFileSizeHigh;
    Result := (Rec.Hi > 0) or (Rec.Lo > MAX_FILE_SIZE);
    IsEmpty := (Rec.Hi = 0) and (Rec.Lo = 0);
{$ELSE}
    Result := True; // 非 Windows 平台返回 True，表示不 Mapping
{$ENDIF}
  end;

begin
  FileIsZeroSize := False;
  if FileSizeIsLargeThanMaxOrCanNotMap(FileName, FileIsZeroSize) then
  begin
    // 大于 2G 的文件可能 Map 失败，或非 Windows 平台，，采用流方式循环处理
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      InternalSM3Stream(Stream, 4096 * 1024, Result, CallBack);
    finally
      Stream.Free;
    end;
  end
  else
  begin
{$IFDEF MSWINDOWS}
    SM3Init(Context);
    FileHandle := CreateFile(PChar(FileName), GENERIC_READ, FILE_SHARE_READ or
                  FILE_SHARE_WRITE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or
                  FILE_FLAG_SEQUENTIAL_SCAN, 0);
    if FileHandle <> INVALID_HANDLE_VALUE then
    begin
      try
        MapHandle := CreateFileMapping(FileHandle, nil, PAGE_READONLY, 0, 0, nil);
        if MapHandle <> 0 then
        begin
          try
            ViewPointer := MapViewOfFile(MapHandle, FILE_MAP_READ, 0, 0, 0);
            if ViewPointer <> nil then
            begin
              try
                SM3Update(Context, ViewPointer, GetFileSize(FileHandle, nil));
              finally
                UnmapViewOfFile(ViewPointer);
              end;
            end
            else
            begin
              raise ECnNativeException.Create(SCnErrorMapViewOfFile + IntToStr(GetLastError));
            end;
          finally
            CloseHandle(MapHandle);
          end;
        end
        else
        begin
          if not FileIsZeroSize then
            raise ECnNativeException.Create(SCnErrorCreateFileMapping + IntToStr(GetLastError));
        end;
      finally
        CloseHandle(FileHandle);
      end;
    end;
    SM3Final(Context, Result);
{$ENDIF}
  end;
end;

function SM3Stream(Stream: TStream;
  CallBack: TCnSM3CalcProgressFunc): TCnSM3Digest;
begin
  InternalSM3Stream(Stream, 4096 * 1024, Result, CallBack);
end;

function SM3Print(const Digest: TCnSM3Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSM3Digest));
end;

function SM3Match(const D1, D2: TCnSM3Digest): Boolean;
begin
  Result := ConstTimeCompareMem(@D1[0], @D2[0], SizeOf(TCnSM3Digest));
end;

function SM3DigestToStr(const Digest: TCnSM3Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSM3Digest));
end;

end.
