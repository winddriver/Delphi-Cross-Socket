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

{ -----------------------------------------------------------------------------}
{ uTBase64 v1.0 - Simple Base64 encoding/decoding class                        }
{ Base64 described in RFC2045, Page 24, (w) 1996 Freed & Borenstein            }
{ Delphi implementation (w) 1999 Dennis D. Spreen (dennis@spreendigital.de)    }
{ This unit is freeware. Just drop me a line if this unit is useful for you.   }
{ -----------------------------------------------------------------------------}

unit CnBase64;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：Base64 编解码算法实现单元
* 单元作者：詹葵（Solin） solin@21cn.com; http://www.ilovezhuzhu.net
*           wr960204
*           CnPack 开发组 (master@cnpack.org)
*           部分内容基于 Dennis D. Spreen 的 UTBASE64.pas 改写，保留原有版权信息。
* 备    注：本单元实现了标准 Base64 与 Base64URL 的编码与解码功能。
*           Base64URL 规则基于标准 Base64，但把符号 + / 替换成了 - _ 以做到 URL 编解码
*           友好，且删除了尾部的 =
*
* 开发平台：PWin2003Std + Delphi 6.0
* 兼容测试：暂未进行
* 本 地 化：该单元无需本地化处理
* 修改记录：2023.10.04 V1.6
*               删除慢速实现。Base64Encode 与 Base64Decode 支持 Base64URL 的编码与解码
*           2019.12.12 V1.5
*               支持 TBytes
*           2019.04.15 V1.4
*               支持 Win32/Win64/MacOS
*           2018.06.22 V1.3
*               修正解出的原始内容可能包含多余 #0 或原始尾部 #0 被错误移除的问题
*           2016.05.03 V1.2
*               修正字符串中包含 #0 时可能会被截断的问题
*           2006.10.25 V1.1
*               增加 wr960204 的优化版本
*           2003.10.14 V1.0
*               创建单元
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes, CnNative, CnConsts;

const
  ECN_BASE64_OK                        = ECN_OK; // 转换成功
  {* Base64 系列错误码：无错误，值为 0}
  ECN_BASE64_ERROR_BASE                = ECN_CUSTOM_ERROR_BASE + $500;
  {* Base64 系列错误码的基准起始值，为 ECN_CUSTOM_ERROR_BASE 加上 $500}

  ECN_BASE64_LENGTH                    = ECN_BASE64_ERROR_BASE + 1;
  {* Base64 错误码之数据长度非法}

function Base64Encode(InputData: TStream; var OutputData: string;
  URL: Boolean = False): Integer; overload;
{* 对流进行 Base64 编码或 Base64URL 编码，如编码成功返回 ECN_BASE64_OK。

   参数：
     InputData: TStream                   - 待编码的数据流
     var OutputData: string               - 编码后的输出字符串
     URL: Boolean                         - URL 标记。True 则使用 Base64URL 编码，False 则使用标准 Base64 编码

   返回值：Integer                        - 返回编码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Encode(const InputData: AnsiString; var OutputData: string;
  URL: Boolean = False): Integer; overload;
{* 对字符串进行 Base64 编码或 Base64URL 编码，如编码成功返回 ECN_BASE64_OK。

   参数：
     const InputData: AnsiString          - 待编码的字符串
     var OutputData: string               - 编码后的输出字符串
     URL: Boolean                         - URL 标记。True 则使用 Base64URL 编码，False 则使用标准 Base64 编码

   返回值：Integer                        - 返回编码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Encode(InputData: Pointer; DataByteLen: Integer; var OutputData: string;
  URL: Boolean = False): Integer; overload;
{* 对数据块进行 Base64 编码或 Base64URL 编码，如编码成功返回 ECN_BASE64_OK。

   参数：
     InputData: Pointer                   - 待编码的数据块地址
     DataByteLen: Integer                 - 待编码的数据块字节长度
     var OutputData: string               - 编码后的输出字符串
     URL: Boolean                         - URL 标记。True 则使用 Base64URL 编码，False 则使用标准 Base64 编码

   返回值：Integer                        - 返回编码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Encode(InputData: TBytes; var OutputData: string;
  URL: Boolean = False): Integer; overload;
{* 对字节数组进行 Base64 编码或 Base64URL 编码，如编码成功返回 ECN_BASE64_OK。

   参数：
     InputData: TBytes                    - 待编码的字节数组
     var OutputData: string               - 编码后的输出字符串
     URL: Boolean                         - URL 标记。True 则使用 Base64URL 编码，False 则使用标准 Base64 编码

   返回值：Integer                        - 返回编码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Decode(const InputData: string; OutputData: TStream;
  FixZero: Boolean = True): Integer; overload;
{* 对字符串进行 Base64 解码（包括 Base64URL 解码），结果写入流。如解码成功返回 ECN_BASE64_OK。

   参数：
     const InputData: string              - 待解码的字符串
     OutputData: TStream                  - 解码后的输出流
     FixZero: Boolean                     - 是否去除解码结果尾部的 #0

   返回值：Integer                        - 返回解码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Decode(const InputData: string; var OutputData: AnsiString;
  FixZero: Boolean = True): Integer; overload;
{* 对字符串进行 Base64 解码（包括 Base64URL 解码），结果写入字符串。如解码成功返回 ECN_BASE64_OK。

   参数：
     const InputData: string              - 待解码的字符串
     var OutputData: AnsiString           - 解码后的输出字符串
     FixZero: Boolean                     - 是否去除解码结果尾部的 #0

   返回值：Integer                        - 返回解码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Decode(const InputData: string; OutputData: Pointer;
  DataByteLen: Integer; FixZero: Boolean = True): Integer; overload;
{* 对字符串进行 Base64 解码（包括 Base64URL 解码），结果写入内存区。如解码成功返回 ECN_BASE64_OK。

   参数：
     const InputData: string              - 待解码的字符串
     OutputData: Pointer                  - 解码后的输出内存区地址
     DataByteLen: Integer                 - 输出内存区的字节长度，应至少为 1 + (Length(InputData) * 3 / 4)
     FixZero: Boolean                     - 是否去除解码结果尾部的 #0

   返回值：Integer                        - 如 OutputData 传 nil，返回所需的解码区的字节长度。其他情况返回解码是否成功，成功则返回 ECN_BASE64_OK
}

function Base64Decode(const InputData: string; out OutputData: TBytes;
  FixZero: Boolean = True): Integer; overload;
{* 对字符串进行 Base64 解码（包括 Base64URL 解码），结果写入字节数组。如解码成功返回 ECN_BASE64_OK。

   参数：
     const InputData: string              - 待解码的字符串
     out OutputData: TBytes               - 解码后的字节数组
     FixZero: Boolean                     - 是否去除解码结果尾部的 #0

   返回值：Integer                        - 返回解码是否成功，成功则返回 ECN_BASE64_OK
}

implementation

var
  FilterDecodeInput: Boolean = True;

//------------------------------------------------------------------------------
// 编码的参考表
//------------------------------------------------------------------------------

  EnCodeTab: array[0..64] of AnsiChar =
  (
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
    'w', 'x', 'y', 'z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9', '+', '/',
    '=');

  EnCodeTabURL: array[0..64] of AnsiChar =
  (
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
    'w', 'x', 'y', 'z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9', '-', '_',
    '=');

//------------------------------------------------------------------------------
// 解码的参考表
//------------------------------------------------------------------------------

  { 不包含在 Base64 里面的字符直接给零，反正也取不到}
  DecodeTable: array[#0..#127] of Byte =
  (
    Byte('='), 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00,
    00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00,
    00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 62, 00, 62, 00, 63,  // 这里的第一个 62、和 63 是 + 和 /，因而 - 补上 62
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 00, 00, 00, 00, 00, 00,
    00, 00, 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 00, 00, 00, 00, 63,  // _ 补上 63
    00, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 00, 00, 00, 00, 00
  );

function Base64Encode(InputData: TStream; var OutputData: string; URL: Boolean): Integer;
var
  Mem: TMemoryStream;
begin
  Mem := TMemoryStream.Create;
  try
    Mem.CopyFrom(InputData, InputData.Size);
    Result := Base64Encode(Mem.Memory, Mem.Size, OutputData, URL);
  finally
    Mem.Free;
  end;
end;

// 以下为 wr960204 改进的快速 Base64 编解码算法
function Base64Encode(InputData: Pointer; DataByteLen: Integer; var OutputData: string;
  URL: Boolean): Integer;
var
  Times, I: Integer;
  X1, X2, X3, X4: AnsiChar;
  XT: Byte;
begin
  if (InputData = nil) or (DataByteLen <= 0) then
  begin
    Result := ECN_BASE64_LENGTH;
    Exit;
  end;

  if DataByteLen mod 3 = 0 then
    Times := DataByteLen div 3
  else
    Times := DataByteLen div 3 + 1;
  SetLength(OutputData, Times * 4);   // 一次分配整块内存,避免一次次字符串相加,一次次释放分配内存
  FillChar(OutputData[1], Length(OutputData) * SizeOf(Char), 0);

  if URL then
  begin
    for I := 0 to Times - 1 do
    begin
      if DataByteLen >= (3 + I * 3) then
      begin
        X1 := EnCodeTabURL[(Ord(PAnsiChar(InputData)[I * 3]) shr 2)];
        XT := (Ord(PAnsiChar(InputData)[I * 3]) shl 4) and 48;
        XT := XT or (Ord(PAnsiChar(InputData)[1 + I * 3]) shr 4);
        X2 := EnCodeTabURL[XT];
        XT := (Ord(PAnsiChar(InputData)[1 + I * 3]) shl 2) and 60;
        XT := XT or (Ord(PAnsiChar(InputData)[2 + I * 3]) shr 6);
        X3 := EnCodeTabURL[XT];
        XT := (Ord(PAnsiChar(InputData)[2 + I * 3]) and 63);
        X4 := EnCodeTabURL[XT];
      end
      else if DataByteLen >= (2 + I * 3) then
      begin
        X1 := EnCodeTabURL[(Ord(PAnsiChar(InputData)[I * 3]) shr 2)];
        XT := (Ord(PAnsiChar(InputData)[I * 3]) shl 4) and 48;
        XT := XT or (Ord(PAnsiChar(InputData)[1 + I * 3]) shr 4);
        X2 := EnCodeTabURL[XT];
        XT := (Ord(PAnsiChar(InputData)[1 + I * 3]) shl 2) and 60;
        X3 := EnCodeTabURL[XT ];
        X4 := '=';
      end
      else
      begin
        X1 := EnCodeTabURL[(Ord(PAnsiChar(InputData)[I * 3]) shr 2)];
        XT := (Ord(PAnsiChar(InputData)[I * 3]) shl 4) and 48;
        X2 := EnCodeTabURL[XT];
        X3 := '=';
        X4 := '=';
      end;
      OutputData[I shl 2 + 1] := Char(X1);
      OutputData[I shl 2 + 2] := Char(X2);
      OutputData[I shl 2 + 3] := Char(X3);
      OutputData[I shl 2 + 4] := Char(X4);
    end;
  end
  else
  begin
    for I := 0 to Times - 1 do
    begin
      if DataByteLen >= (3 + I * 3) then
      begin
        X1 := EnCodeTab[(Ord(PAnsiChar(InputData)[I * 3]) shr 2)];
        XT := (Ord(PAnsiChar(InputData)[I * 3]) shl 4) and 48;
        XT := XT or (Ord(PAnsiChar(InputData)[1 + I * 3]) shr 4);
        X2 := EnCodeTab[XT];
        XT := (Ord(PAnsiChar(InputData)[1 + I * 3]) shl 2) and 60;
        XT := XT or (Ord(PAnsiChar(InputData)[2 + I * 3]) shr 6);
        X3 := EnCodeTab[XT];
        XT := (Ord(PAnsiChar(InputData)[2 + I * 3]) and 63);
        X4 := EnCodeTab[XT];
      end
      else if DataByteLen >= (2 + I * 3) then
      begin
        X1 := EnCodeTab[(Ord(PAnsiChar(InputData)[I * 3]) shr 2)];
        XT := (Ord(PAnsiChar(InputData)[I * 3]) shl 4) and 48;
        XT := XT or (Ord(PAnsiChar(InputData)[1 + I * 3]) shr 4);
        X2 := EnCodeTab[XT];
        XT := (Ord(PAnsiChar(InputData)[1 + I * 3]) shl 2) and 60;
        X3 := EnCodeTab[XT ];
        X4 := '=';
      end
      else
      begin
        X1 := EnCodeTab[(Ord(PAnsiChar(InputData)[I * 3]) shr 2)];
        XT := (Ord(PAnsiChar(InputData)[I * 3]) shl 4) and 48;
        X2 := EnCodeTab[XT];
        X3 := '=';
        X4 := '=';
      end;
      OutputData[I shl 2 + 1] := Char(X1);
      OutputData[I shl 2 + 2] := Char(X2);
      OutputData[I shl 2 + 3] := Char(X3);
      OutputData[I shl 2 + 4] := Char(X4);
    end;
  end;

  OutputData := Trim(OutputData);
  if URL then
  begin
    // 删除 OutputData 尾部的 = 字符，理论上最多三个
    if (Length(OutputData) > 0) and (OutputData[Length(OutputData)] = '=') then
    begin
      Delete(OutputData, Length(OutputData), 1);
      if (Length(OutputData) > 0) and (OutputData[Length(OutputData)] = '=') then
      begin
        Delete(OutputData, Length(OutputData), 1);
        if (Length(OutputData) > 0) and (OutputData[Length(OutputData)] = '=') then
          Delete(OutputData, Length(OutputData), 1);
      end;
    end;
  end;
  Result := ECN_BASE64_OK;
end;

function Base64Encode(const InputData: AnsiString; var OutputData: string; URL: Boolean): Integer;
begin
  if InputData <> '' then
    Result := Base64Encode(@InputData[1], Length(InputData), OutputData, URL)
  else
    Result := ECN_BASE64_LENGTH;
end;

function Base64Encode(InputData: TBytes; var OutputData: string; URL: Boolean): Integer;
begin
  if Length(InputData) > 0 then
    Result := Base64Encode(@InputData[0], Length(InputData), OutputData, URL)
  else
    Result := ECN_BASE64_LENGTH;
end;

function Base64Decode(const InputData: string; OutputData: TStream; FixZero: Boolean): Integer;
var
  Data: TBytes;
begin
  Result := Base64Decode(InputData, Data, FixZero);
  if (Result = ECN_BASE64_OK) and (Length(Data) > 0) then
  begin
    OutputData.Size := Length(Data);
    OutputData.Position := 0;
    OutputData.Write(Data[0], Length(Data));
  end;
end;

function Base64Decode(const InputData: string; out OutputData: TBytes;
  FixZero: Boolean): Integer;
var
  SrcLen, DstLen, Times, I: Integer;
  X1, X2, X3, X4, XT: Byte;
  C, ToDec: Integer;
  Data: AnsiString;

  function FilterLine(const Source: AnsiString): AnsiString;
  var
    P, PP: PAnsiChar;
    I, FL: Integer;
  begin
    FL := Length(Source);
    if FL > 0 then
    begin
      GetMem(P, FL);                   // 一次分配整块内存,避免一次次字符串相加,一次次释放分配内存
      PP := P;
      FillChar(P^, FL, 0);
      for I := 1 to FL do
      begin
        if Source[I] in ['0'..'9', 'A'..'Z', 'a'..'z', '+', '/', '=', '-', '_'] then
        begin
          PP^ := Source[I];
          Inc(PP);
        end;
      end;
      SetString(Result, P, PP - P);        // 截取有效部分
      FreeMem(P);
    end;
  end;

begin
  if InputData = '' then
  begin
    Result := ECN_BASE64_OK;
    Exit;
  end;
  OutPutData := nil;

  // 在 D5 下不知道怎么的不能用 AnsiString(InputData)，可能会出内存错误，于是区分开来
  if FilterDecodeInput then
  begin
{$IFDEF UNICODE}
    Data := FilterLine(AnsiString(InputData));
{$ELSE}
    Data := FilterLine(InputData);
{$ENDIF}
  end
  else
  begin
{$IFDEF UNICODE}
    Data := AnsiString(InputData);
{$ELSE}
    Data := InputData;
{$ENDIF}
  end;

  // 如果是 Base64URL 编码的结果去掉了尾部的 =，则需要根据长度是否是 4 的倍数而补上
  if (Length(Data) and $03) <> 0 then
    Data := Data + StringOfChar(AnsiChar('='), 4 - (Length(Data) and $03));

  SrcLen := Length(Data);
  DstLen := SrcLen * 3 div 4;
  ToDec := 0;

  // 尾部有一个等号意味着原始数据补了个 #0，两个等号意味着补了两个 #0，需要去掉也就是缩短长度
  // 注意这不等同于原始数据的尾部是 #0 的情况，后者无须去掉
  if Data[SrcLen] = '=' then
  begin
    Inc(ToDec);
    if (SrcLen > 1) and (Data[SrcLen - 1] = '=') then
      Inc(ToDec);
  end;

  SetLength(OutputData, DstLen);  // 一次分配整块内存,避免一次次字符串相加,一次次释放分配内存
  Times := SrcLen div 4;
  C := 0;

  for I := 0 to Times - 1 do
  begin
    X1 := DecodeTable[Data[1 + I shl 2]];
    X2 := DecodeTable[Data[2 + I shl 2]];
    X3 := DecodeTable[Data[3 + I shl 2]];
    X4 := DecodeTable[Data[4 + I shl 2]];
    X1 := X1 shl 2;
    XT := X2 shr 4;
    X1 := X1 or XT;
    X2 := X2 shl 4;
    OutputData[C] := X1;
    Inc(C);
    if X3 = 64 then
      Break;
    XT := X3 shr 2;
    X2 := X2 or XT;
    X3 := X3 shl 6;
    OutputData[C] := X2;
    Inc(C);
    if X4 = 64 then
      Break;
    X3 := X3 or X4;
    OutputData[C] := X3;
    Inc(C);
  end;

  // 根据补的等号数目决定是否删除尾部 #0
  while (ToDec > 0) and (OutputData[DstLen - 1] = 0) do
  begin
    Dec(ToDec);
    Dec(DstLen);
  end;
  SetLength(OutputData, DstLen);

  // 再根据外部要求删除尾部的 #0，其实无太大的实质性作用
  if FixZero then
  begin
    while (DstLen > 0) and (OutputData[DstLen - 1] = 0) do
      Dec(DstLen);
    SetLength(OutputData, DstLen);
  end;

  Result := ECN_BASE64_OK;
end;

function Base64Decode(const InputData: string; var OutputData: AnsiString; FixZero: Boolean): Integer;
var
  Data: TBytes;
begin
  Result := Base64Decode(InputData, Data, FixZero);
  if (Result = ECN_BASE64_OK) and (Length(Data) > 0) then
  begin
    SetLength(OutputData, Length(Data));
    Move(Data[0], OutputData[1], Length(Data));
  end;
end;

function Base64Decode(const InputData: string; OutputData: Pointer;
  DataByteLen: Integer; FixZero: Boolean): Integer;
var
  Data: TBytes;
begin
  Result := Base64Decode(InputData, Data, FixZero);
  if (Result = ECN_BASE64_OK) and (Length(Data) > 0) then
  begin
    if OutputData = nil then
    begin
      Result := Length(Data);
      Exit;
    end;

    if DataByteLen < Length(Data) then
    begin
      Result := ECN_BASE64_LENGTH;
      Exit;
    end;

    Move(Data[0], OutPutData^, Length(Data));
  end;
end;

end.
