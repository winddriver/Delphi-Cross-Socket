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

unit CnSHA1;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：SHA1 杂凑算法实现单元
* 单元作者：CnPack 开发组 (master@cnpack.org)
*           从匿名/佚名代码移植而来并补充部分功能。
* 备    注：本单元实现了 SHA1 杂凑算法及对应的 HMAC 算法。
* 开发平台：PWin2000Pro + Delphi 5.0
* 兼容测试：PWin9X/2000/XP + Delphi 5/6
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2022.04.26 V1.5
*               修改 LongWord 与 Integer 地址转换以支持 MacOS64
*           2019.12.12 V1.4
*               支持 TBytes
*           2019.04.15 V1.3
*               支持 Win32/Win64/MacOS32
*           2015.08.14 V1.2
*               汇编切换至 Pascal 以支持跨平台
*           2014.10.22 V1.1
*               加入 HMAC 方法
*           2010.07.14 V1.0
*               创建单元。
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes {$IFDEF MSWINDOWS}, Windows {$ENDIF}, CnNative, CnConsts;

type
  PCnSHA1Digest = ^TCnSHA1Digest;
  TCnSHA1Digest = array[0..19] of Byte;
  {* SHA1 杂凑结果，20 字节}

  TCnSHA1Context = record
  {* SHA1 的上下文结构}
    Hash: array[0..4] of Cardinal;
    Hi, Lo: Cardinal;
    Buffer: array[0..63] of Byte;
    Index: Integer;
    Ipad: array[0..63] of Byte;      {!< HMAC: inner padding        }
    Opad: array[0..63] of Byte;      {!< HMAC: outer padding        }
  end;

  TCnSHA1CalcProgressFunc = procedure (ATotal, AProgress: Int64;
    var Cancel: Boolean) of object;
  {* SHA1 杂凑进度回调事件类型声明}

function SHA1(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA1Digest;
{* 对数据块进行 SHA1 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

function SHA1Buffer(const Buffer; Count: Cardinal): TCnSHA1Digest;
{* 对数据块进行 SHA1 计算。

   参数：
     const Buffer                         - 待计算的数据块地址
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

function SHA1Bytes(Data: TBytes): TCnSHA1Digest;
{* 对字节数组进行 SHA1 计算。

   参数：
     Data: TBytes                         - 待计算的字节数组

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

function SHA1String(const Str: string): TCnSHA1Digest;
{* 对 String 类型数据进行 SHA1 计算。注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

function SHA1StringA(const Str: AnsiString): TCnSHA1Digest;
{* 对 AnsiString 类型字符串进行 SHA1 计算，直接计算内部内容，无编码处理。

   参数：
     const Str: AnsiString                - 待计算的字符串

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

function SHA1StringW(const Str: WideString): TCnSHA1Digest;
{* 对 WideString 类型字符串进行转换并进行 SHA1 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

{$IFDEF UNICODE}

function SHA1UnicodeString(const Str: string): TCnSHA1Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA1 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

{$ELSE}

function SHA1UnicodeString(const Str: WideString): TCnSHA1Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA1 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

{$ENDIF}

function SHA1File(const FileName: string;
  CallBack: TCnSHA1CalcProgressFunc = nil): TCnSHA1Digest;
{* 对指定文件内容进行 SHA1 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHA1CalcProgressFunc    - 计算进度回调函数，默认为空

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

function SHA1Stream(Stream: TStream;
  CallBack: TCnSHA1CalcProgressFunc = nil): TCnSHA1Digest;
{* 对指定流数据进行 SHA1 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHA1CalcProgressFunc    - 计算进度回调函数，默认为空

   返回值：TCnSHA1Digest                  - 返回的 SHA1 杂凑值
}

// 以下三个函数用于外部持续对数据进行零散的 SHA1 计算，SHA1Update 可多次被调用

procedure SHA1Init(var Context: TCnSHA1Context);
{* 初始化一轮 SHA1 计算上下文，准备计算 SHA1 结果。

   参数：
     var Context: TCnSHA1Context          - 待初始化的 SHA1 上下文

   返回值：（无）
}

procedure SHA1Update(var Context: TCnSHA1Context; Input: PAnsiChar; ByteLength: Integer);
{* 以初始化后的上下文对一块数据进行 SHA1 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA1Context          - SHA1 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Integer                  - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA1Final(var Context: TCnSHA1Context; var Digest: TCnSHA1Digest);
{* 结束本轮计算，将 SHA1 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA1Context          - SHA1 上下文
     var Digest: TCnSHA1Digest            - 返回的 SHA1 杂凑值

   返回值：（无）
}

function SHA1Print(const Digest: TCnSHA1Digest): string;
{* 以十六进制格式输出 SHA1 杂凑值。

   参数：
     const Digest: TCnSHA1Digest          - 指定的 SHA1 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA1Match(const D1: TCnSHA1Digest; const D2: TCnSHA1Digest): Boolean;
{* 比较两个 SHA1 杂凑值是否相等。

   参数：
     const D1: TCnSHA1Digest              - 待比较的 SHA1 杂凑值一
     const D2: TCnSHA1Digest              - 待比较的 SHA1 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA1DigestToStr(const Digest: TCnSHA1Digest): string;
{* SHA1 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA1Digest          - 待转换的 SHA1 杂凑值

   返回值：string                         - 返回的字符串
}

procedure SHA1Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA1Digest);
{* 基于 SHA1 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA1 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA1 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA1Digest            - 返回的 SHA1 杂凑值

   返回值：（无）
}

implementation

const
  MAX_FILE_SIZE = 512 * 1024 * 1024;
  // If file size <= this size (bytes), using Mapping, else stream

  HMAC_SHA1_BLOCK_SIZE_BYTE = 64;
  HMAC_SHA1_OUTPUT_LENGTH_BYTE = 20;

function LRot32(X: Cardinal; C: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := X shl (C and 31) + X shr (32 - C and 31);
end;

function F1(x, y, z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := z xor (x and (y xor z));
end;

function F2(x, y, z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := x xor y xor z;
end;

function F3(x, y, z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (x and y) or (z and (x or y));
end;

function RB(A: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (A shr 24) or ((A shr 8) and $FF00) or ((A shl 8) and $FF0000) or (A shl 24);
end;

procedure SHA1Compress(var Data: TCnSHA1Context);
var
  A, B, C, D, E, T: Cardinal;
  W: array[0..79] of Cardinal;
  I: Integer;
begin
  Move(Data.Buffer, W, Sizeof(Data.Buffer));
  for I := 0 to 15 do
    W[I] := RB(W[I]);
  for I := 16 to 79 do
    W[I] := LRot32(W[I - 3] xor W[I - 8] xor W[I - 14] xor W[I - 16], 1);
  A := Data.Hash[0];
  B := Data.Hash[1];
  C := Data.Hash[2];
  D := Data.Hash[3];
  E := Data.Hash[4];
  for I := 0 to 19 do
  begin
    T := LRot32(A, 5) + F1(B, C, D) + E + W[I] + $5A827999;
    E := D;
    D := C;
    C := LRot32(B, 30);
    B := A;
    A := T;
  end;
  for I := 20 to 39 do
  begin
    T := LRot32(A, 5) + F2(B, C, D) + E + W[I] + $6ED9EBA1;
    E := D;
    D := C;
    C := LRot32(B, 30);
    B := A;
    A := T;
  end;
  for I := 40 to 59 do
  begin
    T := LRot32(A, 5) + F3(B, C, D) + E + W[I] + $8F1BBCDC;
    E := D;
    D := C;
    C := LRot32(B, 30);
    B := A;
    A := T;
  end;
  for I := 60 to 79 do
  begin
    T := LRot32(A, 5) + F2(B, C, D) + E + W[I] + $CA62C1D6;
    E := D;
    D := C;
    C := LRot32(B, 30);
    B := A;
    A := T;
  end;
  Data.Hash[0] := Data.Hash[0] + A;
  Data.Hash[1] := Data.Hash[1] + B;
  Data.Hash[2] := Data.Hash[2] + C;
  Data.Hash[3] := Data.Hash[3] + D;
  Data.Hash[4] := Data.Hash[4] + E;
  FillChar(W, Sizeof(W), 0);
  FillChar(Data.Buffer, Sizeof(Data.Buffer), 0);
end;

procedure SHA1Init(var Context: TCnSHA1Context);
begin
  Context.Hi := 0;
  Context.Lo := 0;
  Context.Index := 0;
  FillChar(Context.Buffer, Sizeof(Context.Buffer), 0);
  Context.Hash[0] := $67452301;
  Context.Hash[1] := $EFCDAB89;
  Context.Hash[2] := $98BADCFE;
  Context.Hash[3] := $10325476;
  Context.Hash[4] := $C3D2E1F0;
end;

procedure SHA1UpdateLen(var Context: TCnSHA1Context; Len: Integer);
var
  I: Cardinal;
  K: Integer;
begin
  for K := 0 to 7 do
  begin
    I := Context.Lo;
    Inc(Context.Lo, Len);
    if Context.Lo < I then
      Inc(Context.Hi);
  end;
end;

procedure SHA1Update(var Context: TCnSHA1Context; Input: PAnsiChar; ByteLength: Integer);
begin
  SHA1UpdateLen(Context, ByteLength);
  while ByteLength > 0 do
  begin
    Context.Buffer[Context.Index] := PByte(Input)^;
    Inc(PByte(Input));
    Inc(Context.Index);
    Dec(ByteLength);
    if Context.Index = 64 then
    begin
      Context.Index := 0;
      SHA1Compress(Context);
    end;
  end;
end;

procedure SHA1UpdateW(var Context: TCnSHA1Context; Input: PWideChar; CharLength: Cardinal);
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
    SHA1Update(Context, pContent, iLen);
  finally
    FreeMem(pContent);
  end;
{$ELSE}  // MacOS 下直接把 UnicodeString 转成 AnsiString 计算，不支持非 Windows 非 Unicode 平台
  S := StrNew(Input);
  A := AnsiString(S);
  SHA1Update(Context, @A[1], Length(A));
{$ENDIF}
end;

procedure SHA1Final(var Context: TCnSHA1Context; var Digest: TCnSHA1Digest);
type
  PDWord = ^Cardinal;
begin
  Context.Buffer[Context.Index] := $80;
  if Context.Index >= 56 then
    SHA1Compress(Context);
  PDWord(@Context.Buffer[56])^ := RB(Context.Hi);
  PDWord(@Context.Buffer[60])^ := RB(Context.Lo);
  SHA1Compress(Context);
  Context.Hash[0] := RB(Context.Hash[0]);
  Context.Hash[1] := RB(Context.Hash[1]);
  Context.Hash[2] := RB(Context.Hash[2]);
  Context.Hash[3] := RB(Context.Hash[3]);
  Context.Hash[4] := RB(Context.Hash[4]);
  Move(Context.Hash, Digest, Sizeof(Digest));
end;

// 对数据块进行 SHA1 计算
function SHA1(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA1Digest;
var
  Context: TCnSHA1Context;
begin
  SHA1Init(Context);
  SHA1Update(Context, Input, ByteLength);
  SHA1Final(Context, Result);
end;

// 对数据块进行 SHA1 计算
function SHA1Buffer(const Buffer; Count: Cardinal): TCnSHA1Digest;
var
  Context: TCnSHA1Context;
begin
  SHA1Init(Context);
  SHA1Update(Context, PAnsiChar(Buffer), Count);
  SHA1Final(Context, Result);
end;

function SHA1Bytes(Data: TBytes): TCnSHA1Digest;
var
  Context: TCnSHA1Context;
begin
  SHA1Init(Context);
  SHA1Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA1Final(Context, Result);
end;

// 对 String 类型数据进行 SHA1 计算
function SHA1String(const Str: string): TCnSHA1Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA1StringA(AStr);
end;

// 对 AnsiString 类型数据进行 SHA1 计算
function SHA1StringA(const Str: AnsiString): TCnSHA1Digest;
var
  Context: TCnSHA1Context;
begin
  SHA1Init(Context);
  SHA1Update(Context, PAnsiChar(Str), Length(Str));
  SHA1Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHA1 计算
function SHA1StringW(const Str: WideString): TCnSHA1Digest;
var
  Context: TCnSHA1Context;
begin
  SHA1Init(Context);
  SHA1UpdateW(Context, PWideChar(Str), Length(Str));
  SHA1Final(Context, Result);
end;

{$IFDEF UNICODE}
function SHA1UnicodeString(const Str: string): TCnSHA1Digest;
{$ELSE}
function SHA1UnicodeString(const Str: WideString): TCnSHA1Digest;
{$ENDIF}
var
  Context: TCnSHA1Context;
begin
  SHA1Init(Context);
  SHA1Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA1Final(Context, Result);
end;

function InternalSHA1Stream(Stream: TStream; const BufSize: Cardinal; var D:
  TCnSHA1Digest; CallBack: TCnSHA1CalcProgressFunc = nil): Boolean;
var
  Context: TCnSHA1Context;
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
  SHA1Init(Context);
  GetMem(Buf, BufLen);
  try
    Stream.Position := 0;
    repeat
      ReadBytes := Stream.Read(Buf^, BufLen);
      if ReadBytes <> 0 then
      begin
        Inc(TotalBytes, ReadBytes);
        SHA1Update(Context, Buf, ReadBytes);
        if Assigned(CallBack) then
        begin
          CallBack(Size, TotalBytes, CancelCalc);
          if CancelCalc then Exit;
        end;
      end;
    until (ReadBytes = 0) or (TotalBytes = Size);
    SHA1Final(Context, D);
    Result := True;
  finally
    FreeMem(Buf, BufLen);
    Stream.Position := SavePos;
  end;
end;

// 对指定流进行 SHA1 计算
function SHA1Stream(Stream: TStream;
  CallBack: TCnSHA1CalcProgressFunc = nil): TCnSHA1Digest;
begin
  InternalSHA1Stream(Stream, 4096 * 1024, Result, CallBack);
end;

// 对指定文件数据进行 SHA1 计算
function SHA1File(const FileName: string;
  CallBack: TCnSHA1CalcProgressFunc): TCnSHA1Digest;
var
{$IFDEF MSWINDOWS}
  FileHandle: THandle;
  MapHandle: THandle;
  ViewPointer: Pointer;
  Context: TCnSHA1Context;
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
    // 大于 2G 的文件可能 Map 失败，或非 Windows 平台，采用流方式循环处理
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      InternalSHA1Stream(Stream, 4096 * 1024, Result, CallBack);
    finally
      Stream.Free;
    end;
  end
  else
  begin
{$IFDEF MSWINDOWS}
    SHA1Init(Context);
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
                SHA1Update(Context, ViewPointer, GetFileSize(FileHandle, nil));
              finally
                UnmapViewOfFile(ViewPointer);
              end;
            end
            else
            begin
              raise Exception.Create(SCnErrorMapViewOfFile + IntToStr(GetLastError));
            end;
          finally
            CloseHandle(MapHandle);
          end;
        end
        else
        begin
          if not FileIsZeroSize then
            raise Exception.Create(SCnErrorCreateFileMapping + IntToStr(GetLastError));
        end;
      finally
        CloseHandle(FileHandle);
      end;
    end;
    SHA1Final(Context, Result);
{$ENDIF}
  end;
end;

// 以十六进制格式输出 SHA1 杂凑值
function SHA1Print(const Digest: TCnSHA1Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA1Digest));
end;

// 比较两个 SHA1 杂凑值是否相等
function SHA1Match(const D1, D2: TCnSHA1Digest): Boolean;
var
  I: Integer;
begin
  I := 0;
  Result := True;
  while Result and (I < 20) do
  begin
    Result := D1[I] = D2[I];
    Inc(I);
  end;
end;

// SHA1 杂凑值转 string
function SHA1DigestToStr(const Digest: TCnSHA1Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA1Digest));
end;

procedure SHA1HmacInit(var Ctx: TCnSHA1Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA1Digest;
begin
  if KeyLength > HMAC_SHA1_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA1Buffer(Key, KeyLength);
    KeyLength := HMAC_SHA1_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Ctx.Ipad, HMAC_SHA1_BLOCK_SIZE_BYTE, $36);
  FillChar(Ctx.Opad, HMAC_SHA1_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Ctx.Ipad[I] := Byte(Ctx.Ipad[I] xor Byte(Key[I]));
    Ctx.Opad[I] := Byte(Ctx.Opad[I] xor Byte(Key[I]));
  end;

  SHA1Init(Ctx);
  SHA1Update(Ctx, @(Ctx.Ipad[0]), HMAC_SHA1_BLOCK_SIZE_BYTE);
end;

procedure SHA1HmacUpdate(var Ctx: TCnSHA1Context; Input: PAnsiChar; Length: Cardinal);
begin
  SHA1Update(Ctx, Input, Length);
end;

procedure SHA1HmacFinal(var Ctx: TCnSHA1Context; var Output: TCnSHA1Digest);
var
  Len: Integer;
  TmpBuf: TCnSHA1Digest;
begin
  Len := HMAC_SHA1_OUTPUT_LENGTH_BYTE;
  SHA1Final(Ctx, TmpBuf);
  SHA1Init(Ctx);
  SHA1Update(Ctx, @(Ctx.Opad[0]), HMAC_SHA1_BLOCK_SIZE_BYTE);
  SHA1Update(Ctx, @(TmpBuf[0]), Len);
  SHA1Final(Ctx, Output);
end;

procedure SHA1Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA1Digest);
var
  Ctx: TCnSHA1Context;
begin
  SHA1HmacInit(Ctx, Key, KeyByteLength);
  SHA1HmacUpdate(Ctx, Input, ByteLength);
  SHA1HmacFinal(Ctx, Output);
end;

end.
