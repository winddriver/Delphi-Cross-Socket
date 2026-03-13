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

unit CnPemUtils;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：PEM 格式处理及对齐单元
* 单元作者：CnPack 开发组
* 备    注：本单元实现了 PEM 格式的读取与保存，包括加解密机制。
*           另外也实现了 PKCS1/PKCS5/PKCS7/ISO10126 等对齐处理机制。
*           注：不支持 PKCS12 规范的证书及密钥包装格式
* 开发平台：WinXP + Delphi 5.0
* 兼容测试：暂未进行
* 本 地 化：该单元无需本地化处理
* 修改记录：2024.05.27 V1.6
*               增加六个 ISO10126 对齐的处理函数
*           2023.12.14 V1.5
*               增加 SaveMemoryToPemStream 函数但未完整测试
*           2022.03.09 V1.4
*               增加六个 PKCS5 对齐的处理函数
*           2021.05.14 V1.3
*               增加四个 PKCS7 对齐的处理函数
*           2020.03.27 V1.2
*               模拟 Openssl 实现 PEM 的加密写入，只支持部分加密算法与机制
*               目前写入兼容 des/3des/aes128/192/256 PKCS7 对齐，基于 Openssl 1.0.2g
*           2020.03.23 V1.1
*               模拟 Openssl 实现 PEM 的加密读取，只支持部分加密算法与机制
*               目前读取兼容 des/3des/aes128/192/256 PKCS7 对齐，基于 Openssl 1.0.2g
*           2020.03.18 V1.0
*               创建单元，从 CnRSA 中独立出来
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes, CnNative, CnRandom, CnKDF, CnBase64, CnAES, CnDES;

const
  CN_PKCS1_BLOCK_TYPE_PRIVATE_00       = 00;
  {* PKCS1 对齐时的块类型字段值一，默认应用于 RSA 的私钥加密场合}

  CN_PKCS1_BLOCK_TYPE_PRIVATE_FF       = 01;
  {* PKCS1 对齐时的块类型字段值二，默认应用于 RSA 的私钥签名场合}

  CN_PKCS1_BLOCK_TYPE_PUBLIC_RANDOM    = 02;
  {* PKCS1 对齐时的块类型字段值三，默认应用于 RSA 的公钥加密场合}

type
  TCnKeyHashMethod = (ckhMd5, ckhSha256);
  {* PEM 格式支持的杂凑类型}

  TCnKeyEncryptMethod = (ckeNone, ckeDES, cke3DES, ckeAES128, ckeAES192, ckeAES256);
  {* PEM 格式支持的加密类型}

// ======================= PEM 文件读写函数，支持加解密 ========================

function LoadPemFileToMemory(const FileName: string; const ExpectHead: string;
  const ExpectTail: string; MemoryStream: TMemoryStream; const Password: string = '';
  KeyHashMethod: TCnKeyHashMethod = ckhMd5): Boolean;
{* 从 PEM 格式编码的文件中验证指定头尾后读入实际内容并解密进行 Base64 解码。

   参数：
     const FileName: string               - 待读入的文件名
     const ExpectHead: string             - 期望的头部
     const ExpectTail: string             - 期望的尾部
     MemoryStream: TMemoryStream          - 输出的内存流
     const Password: string               - 如果文件被加密，需在此提供密码
     KeyHashMethod: TCnKeyHashMethod      - 文件加密使用的杂凑类型

   返回值：Boolean                        - 返回读入是否成功
}

function LoadPemStreamToMemory(Stream: TStream; const ExpectHead: string;
  const ExpectTail: string; MemoryStream: TMemoryStream; const Password: string = '';
  KeyHashMethod: TCnKeyHashMethod = ckhMd5): Boolean;
{* 从 PEM 格式编码的文件中验证指定头尾后读入实际内容并解密进行 Base64 解码。

   参数：
     Stream: TStream                      - 待读入的流
     const ExpectHead: string             - 期望的头部
     const ExpectTail: string             - 期望的尾部
     MemoryStream: TMemoryStream          - 输出的内存流
     const Password: string               - 如果流被加密，需在此提供密码
     KeyHashMethod: TCnKeyHashMethod      - 流加密使用的杂凑类型

   返回值：Boolean                        - 返回读入是否成功
}

function SaveMemoryToPemFile(const FileName: string; const Head: string; const Tail: string;
  MemoryStream: TMemoryStream; KeyEncryptMethod: TCnKeyEncryptMethod = ckeNone;
  KeyHashMethod: TCnKeyHashMethod = ckhMd5; const Password: string = ''; Append: Boolean = False): Boolean;
{* 将 Stream 的内容进行 Base64 编码后加密分行并补上文件头尾再写入文件，Append 为 True 时表示追加。

   参数：
     const FileName: string                               - 待写入的文件名
     const Head: string                                   - 写入的头部
     const Tail: string                                   - 写入的尾部
     MemoryStream: TMemoryStream                          - 待写入的内容
     KeyEncryptMethod: TCnKeyEncryptMethod                - 设置加密类型，默认不加密
     KeyHashMethod: TCnKeyHashMethod                      - 设置杂凑类型
     const Password: string                               - 设置密码，无需加密则传空
     Append: Boolean                                      - 是否以追加的方式写入

   返回值：Boolean                                        - 返回是否写入成功
}

function SaveMemoryToPemStream(Stream: TStream; const Head: string; const Tail: string;
  MemoryStream: TMemoryStream; KeyEncryptMethod: TCnKeyEncryptMethod = ckeNone;
  KeyHashMethod: TCnKeyHashMethod = ckhMd5; const Password: string = ''; Append: Boolean = False): Boolean;
{* 将 Stream 的内容进行 Base64 编码后加密分行并补上头尾再写入流，Append 为 True 时表示追加。

   参数：
     Stream: TStream                                      - 待写入的流
     const Head: string                                   - 写入的头部
     const Tail: string                                   - 写入的尾部
     MemoryStream: TMemoryStream                          - 待写入的内容
     KeyEncryptMethod: TCnKeyEncryptMethod                - 设置加密类型，默认不加密
     KeyHashMethod: TCnKeyHashMethod                      - 设置杂凑类型，默认不杂凑
     const Password: string                               - 设置密码，无需加密则传空
     Append: Boolean                                      - 是否以追加的方式写入

   返回值：Boolean                                        - 返回是否写入成功
}

// ===================== PKCS1 / PKCS7 Padding 对齐处理函数 ====================

function AddPKCS1Padding(PaddingType: Integer; BlockSize: Integer; Data: Pointer;
  DataByteLen: Integer; OutStream: TStream): Boolean;
{* 将数据块补上填充内容写入 Stream 中，返回成功与否，内部会设置错误码。
   PaddingType 取 0、1、2，BlockLen 字节数如 128 等。格式形如
   EB = 00 || BT || PS || 00 || D
   其中 00 是前导规定字节，BT 是 1 字节的 PaddingType，0 1 2 分别代表 00 FF 随机，
   PS 是填充的多字节内容，再 00 是规定的结尾字节。

   参数：
     PaddingType: Integer                 - 对齐类型，取 0 1 2
     BlockSize: Integer                   - 对齐块的字节长度
     Data: Pointer                        - 待对齐数据块的地址
     DataByteLen: Integer                 - 待对齐数据块的字节长度
     OutStream: TStream                   - 输出流

   返回值：Boolean                        - 返回对齐内容是否增加成功
}

function RemovePKCS1Padding(InData: Pointer; InDataByteLen: Integer; OutBuf: Pointer;
  out OutByteLen: Integer): Boolean;
{* 去除数据块的 PKCS1 的 Padding，返回成功与否。OutBuf 所指区域的可用长度需调用者自行保证。
   如成功，OutLen 返回原文数据长度。

   参数：
     InData: Pointer                      - 待去除对齐的数据块的地址
     InDataByteLen: Integer               - 待去除对齐的数据块的字节长度
     OutBuf: Pointer                      - 输出的容纳去除内容的区域，其长度必须足够
     out OutByteLen: Integer              - 返回去除对齐后的数据长度

   返回值：Boolean                        - 返回对齐内容是否去除成功
}

function GetPKCS7PaddingByteLength(OrignalByteLen: Integer; BlockSize: Integer): Integer;
{* 根据原始长度与块长度计算 PKCS7 对齐后的长度。

   参数：
     OrignalByteLen: Integer              - 原始数据字节长度
     BlockSize: Integer                   - PKCS7 块字节长度

   返回值：Integer                        - 返回 PKCS7 对齐后的总字节长度
}

procedure AddPKCS7Padding(Stream: TMemoryStream; BlockSize: Integer);
{* 给数据末尾加上 PKCS7 规定的填充“几个几”的填充数据。

   参数：
     Stream: TMemoryStream                - 待对齐的内存流内容，对齐内容将追加写入流尾部
     BlockSize: Integer                   - PKCS7 块字节长度

   返回值：（无）
}

procedure RemovePKCS7Padding(Stream: TMemoryStream);
{* 去除 PKCS7 规定的末尾填充“几个几”的填充数据。

   参数：
     Stream: TMemoryStream                - 待去除对齐的内存流

   返回值：（无）}

function StrAddPKCS7Padding(const Str: AnsiString; BlockSize: Integer): AnsiString;
{* 给字符串末尾加上 PKCS7 规定的填充“几个几”的填充数据。

   参数：
     const Str: AnsiString                - 待对齐的字符串
     BlockSize: Integer                   - PKCS7 块字节长度

   返回值：AnsiString                     - 返回对齐后的字符串
}

function StrRemovePKCS7Padding(const Str: AnsiString): AnsiString;
{* 去除 PKCS7 规定的字符串末尾填充“几个几”的填充数据。

   参数：
     const Str: AnsiString                - 待去除对齐的字符串

   返回值：AnsiString                     - 返回去除对齐后的字符串
}

procedure BytesAddPKCS7Padding(var Data: TBytes; BlockSize: Integer);
{* 给字节数组末尾加上 PKCS7 规定的填充“几个几”的填充数据。

   参数：
     var Data: TBytes                     - 待对齐的字节数组，对齐内容将追加在尾部
     BlockSize: Integer                   - PKCS7 块字节长度

   返回值：（无）
}

procedure BytesRemovePKCS7Padding(var Data: TBytes);
{* 去除 PKCS7 规定的字节数组末尾填充“几个几”的填充数据。

   参数：
     var Data: TBytes                     - 待去除对齐的字节数组

   返回值：（无）
}

procedure AddPKCS5Padding(Stream: TMemoryStream);
{* 给数据末尾加上 PKCS5 规定的填充“几个几”的填充数据，遵循 PKCS7 规范但块大小固定为 8 字节。

   参数：
     Stream: TMemoryStream                - 待对齐的内存流，对齐内容将追加在尾部

   返回值：（无）
}

procedure RemovePKCS5Padding(Stream: TMemoryStream);
{* 去除 PKCS7 规定的末尾填充“几个几”的填充数据，遵循 PKCS7 规范但块大小固定为 8 字节。

   参数：
     Stream: TMemoryStream                - 待去除对齐的内存流

   返回值：（无）
}

function StrAddPKCS5Padding(const Str: AnsiString): AnsiString;
{* 给字符串末尾加上 PKCS5 规定的填充“几个几”的填充数据，遵循 PKCS7 规范但块大小固定为 8 字节。

   参数：
     const Str: AnsiString                - 待对齐的字符串

   返回值：AnsiString                     - 返回对齐后的字符串
}

function StrRemovePKCS5Padding(const Str: AnsiString): AnsiString;
{* 去除 PKCS5 规定的字符串末尾填充“几个几”的填充数据，遵循 PKCS7 规范但块大小固定为 8 字节。

   参数：
     const Str: AnsiString                - 待去除对齐的字符串

   返回值：AnsiString                     - 返回去除对齐后的字符串
}

procedure BytesAddPKCS5Padding(var Data: TBytes);
{* 给字节数组末尾加上 PKCS5 规定的填充“几个几”的填充数据，遵循 PKCS7 规范但块大小固定为 8 字节。

   参数：
     var Data: TBytes                     - 待对齐的字节数组，对齐内容将追加在尾部

   返回值：（无）
}

procedure BytesRemovePKCS5Padding(var Data: TBytes);
{* 去除 PKCS7 规定的字节数组末尾填充“几个几”的填充数据，遵循 PKCS7 规范但块大小固定为 8 字节。

   参数：
     var Data: TBytes                     - 待去除对齐的字节数组

   返回值：（无）
}

function GetISO10126PaddingByteLength(OrignalByteLen: Integer; BlockSize: Integer): Integer;
{* 根据原始长度与块长度计算 ISO10126Padding 对齐后的长度。

   参数：
     OrignalByteLen: Integer              - 原始数据字节长度
     BlockSize: Integer                   - ISO10126 块字节长度

   返回值：Integer                        - 返回 PKCS7 对齐后的总字节长度
}

procedure AddISO10126Padding(Stream: TMemoryStream; BlockSize: Integer);
{* 给数据末尾加上 ISO10126Padding 规定的填充“零和几”的填充数据。

   参数：
     Stream: TMemoryStream                - 待对齐的内存流，对齐内容将追加在尾部
     BlockSize: Integer                   - ISO10126 块字节长度

   返回值：（无）
}

procedure RemoveISO10126Padding(Stream: TMemoryStream);
{* 去除 ISO10126Padding 规定的末尾填充“零和几”的填充数据。

   参数：
     Stream: TMemoryStream                - 待去除对齐的内存流

   返回值：（无）
}

function StrAddISO10126Padding(const Str: AnsiString; BlockSize: Integer): AnsiString;
{* 给字符串末尾加上 ISO10126Padding 规定的填充“零和几”的填充数据。

   参数：
     const Str: AnsiString                - 待对齐的字符串
     BlockSize: Integer                   - ISO10126 块字节大小

   返回值：AnsiString                     - 返回对齐后的字符串
}

function StrRemoveISO10126Padding(const Str: AnsiString): AnsiString;
{* 去除 ISO10126Padding 规定的字符串末尾填充“零和几”的填充数据。

   参数：
     const Str: AnsiString                - 待去除对齐的字符串

   返回值：AnsiString                     - 返回去除对齐后的字符串
}

procedure BytesAddISO10126Padding(var Data: TBytes; BlockSize: Integer);
{* 给字节数组末尾加上 ISO10126Padding 规定的填充“零和几”的填充数据。

   参数：
     var Data: TBytes                     - 待对齐的字节数组，对齐内容将追加在尾部
     BlockSize: Integer                   - ISO10126 块字节长度

   返回值：（无）
}

procedure BytesRemoveISO10126Padding(var Data: TBytes);
{* 去除 ISO10126Padding 规定的字节数组末尾填充“零和几”的填充数据。

   参数：
     var Data: TBytes                     - 待去除对齐的字节数组

   返回值：（无）
}

implementation

const
  PKCS1_PADDING_SIZE            = 11; // 一个前导 00、一个类型字节、至少 8 字节内容填充，一个填充后的 00 结尾
  PKCS5_BLOCK_SIZE              = 8;

  ENC_HEAD_PROCTYPE = 'Proc-Type:';
  ENC_HEAD_PROCTYPE_NUM = '4';
  ENC_HEAD_ENCRYPTED = 'ENCRYPTED';
  ENC_HEAD_DEK = 'DEK-Info:';

  ENC_TYPE_AES128 = 'AES-128';
  ENC_TYPE_AES192 = 'AES-192';
  ENC_TYPE_AES256 = 'AES-256';
  ENC_TYPE_DES    = 'DES';
  ENC_TYPE_3DES   = 'DES-EDE3';

  ENC_BLOCK_CBC   = 'CBC';

  ENC_TYPE_STRS: array[TCnKeyEncryptMethod] of string =
    ('', ENC_TYPE_DES, ENC_TYPE_3DES, ENC_TYPE_AES128, ENC_TYPE_AES192, ENC_TYPE_AES256);

  ENC_TYPE_BLOCK_SIZE: array[TCnKeyEncryptMethod] of Byte =
    (0, 8, 8, 16, 16, 16);

function Min(A, B: Integer): Integer;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

function AddPKCS1Padding(PaddingType, BlockSize: Integer; Data: Pointer;
  DataByteLen: Integer; OutStream: TStream): Boolean;
var
  I: Integer;
  B, F: Byte;
begin
  Result := False;
  if (Data = nil) or (DataByteLen <= 0) then
    Exit;

  // 不足以填充
  if DataByteLen > BlockSize - PKCS1_PADDING_SIZE then
    Exit;

  B := 0;
  OutStream.Write(B, 1);       // 写前导字节 00
  B := PaddingType;
  F := BlockSize - DataByteLen - 3; // 3 表示一个前导 00、一个类型字节、一个填充后的 00 结尾

  OutStream.Write(B, 1);
  case PaddingType of
    CN_PKCS1_BLOCK_TYPE_PRIVATE_00:
      begin
        B := 0;
        for I := 1 to F do
          OutStream.Write(B, 1);
      end;
    CN_PKCS1_BLOCK_TYPE_PRIVATE_FF:
      begin
        B := $FF;
        for I := 1 to F do
          OutStream.Write(B, 1);
      end;
    CN_PKCS1_BLOCK_TYPE_PUBLIC_RANDOM:
      begin
        Randomize;
        for I := 1 to F do
        begin
          B := Trunc(Random(255));
          if B = 0 then
            Inc(B);
          OutStream.Write(B, 1);
        end;
      end;
  else
    Exit;
  end;

  B := 0;
  OutStream.Write(B, 1);
  OutStream.Write(Data^, DataByteLen);
  Result := True;
end;

function RemovePKCS1Padding(InData: Pointer; InDataByteLen: Integer; OutBuf: Pointer;
  out OutByteLen: Integer): Boolean;
var
  P: PAnsiChar;
  I, J, Start: Integer;
begin
  Result := False;
  OutByteLen := 0;
  I := 0;

  P := PAnsiChar(InData);
  while P[I] = #0 do // 首字符不一定是 #0，可能已经被去掉了
    Inc(I);

  if I >= InDataByteLen then
    Exit;

  Start := 0;
  case Ord(P[I]) of
    CN_PKCS1_BLOCK_TYPE_PRIVATE_00:
      begin
        // 从 P[I + 1] 开始寻找非 00 便是
        J := I + 1;
        while J < InDataByteLen do
        begin
          if P[J] <> #0 then
          begin
            Start := J;
            Break;
          end;
          Inc(J);
        end;
      end;
    CN_PKCS1_BLOCK_TYPE_PRIVATE_FF,
    CN_PKCS1_BLOCK_TYPE_PUBLIC_RANDOM:
      begin
        // 从 P[I + 1] 开始寻找到第一个 00 后的便是
        J := I + 1;
        while J < InDataByteLen do
        begin
          if P[J] = #0 then
          begin
            Start := J;
            Break;
          end;
          Inc(J);
        end;

        if Start <> 0 then
          Inc(Start);
      end;
  end;

  if Start > 0 then
  begin
    Move(P[Start], OutBuf^, InDataByteLen - Start);
    OutByteLen := InDataByteLen - Start;
    Result := True;
  end;
end;

function GetPKCS7PaddingByteLength(OrignalByteLen: Integer; BlockSize: Integer): Integer;
var
  R: Byte;
begin
  R := OrignalByteLen mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;
  Result := OrignalByteLen + R;
end;

procedure AddPKCS7Padding(Stream: TMemoryStream; BlockSize: Integer);
var
  R: Byte;
  Buf: array[0..255] of Byte;
begin
  R := Stream.Size mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;

  FillChar(Buf[0], R, R);
  Stream.Position := Stream.Size;
  Stream.Write(Buf[0], R);
end;

procedure RemovePKCS7Padding(Stream: TMemoryStream);
var
  L: Byte;
  Len: Cardinal;
  Mem: Pointer;
begin
  // 去掉 Stream 末尾的 9 个 9 这种 Padding
  if Stream.Size > 1 then
  begin
    Stream.Position := Stream.Size - 1;
    Stream.Read(L, 1);

    if Stream.Size - L < 0 then  // 尺寸不靠谱，不干
      Exit;

    Len := Stream.Size - L;
    Mem := GetMemory(Len);
    if Mem <> nil then
    begin
      Move(Stream.Memory^, Mem^, Len);
      Stream.Clear;
      Stream.Write(Mem^, Len);
      FreeMemory(Mem);
    end;
  end;
end;

function StrAddPKCS7Padding(const Str: AnsiString; BlockSize: Integer): AnsiString;
var
  I, L: Integer;
  R: Byte;
begin
  L := Length(Str);
  R := L mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;

  SetLength(Result, L + R);
  if L > 0 then
    Move(Str[1], Result[1], L);

  for I := 1 to R do
    Result[L + I] := AnsiChar(R);
end;

function StrRemovePKCS7Padding(const Str: AnsiString): AnsiString;
var
  L: Integer;
  V: Byte;
begin
  Result := Str;
  if Result = '' then
    Exit;

  L := Length(Result);
  V := Ord(Result[L]);  // 末是几表示加了几

  if V <= L then
    Delete(Result, L - V + 1, V);
end;

procedure AddPKCS5Padding(Stream: TMemoryStream);
begin
  AddPKCS7Padding(Stream, PKCS5_BLOCK_SIZE);
end;

procedure RemovePKCS5Padding(Stream: TMemoryStream);
begin
  RemovePKCS7Padding(Stream);
end;

function StrAddPKCS5Padding(const Str: AnsiString): AnsiString;
begin
  Result := StrAddPKCS7Padding(Str, PKCS5_BLOCK_SIZE);
end;

function StrRemovePKCS5Padding(const Str: AnsiString): AnsiString;
begin
  Result := StrRemovePKCS7Padding(Str);
end;

procedure BytesAddPKCS7Padding(var Data: TBytes; BlockSize: Integer);
var
  R: Byte;
  L, I: Integer;
begin
  L := Length(Data);
  R := L mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;

  SetLength(Data, L + R);
  for I := 0 to R - 1 do
    Data[L + I] := R;
end;

procedure BytesRemovePKCS7Padding(var Data: TBytes);
var
  L: Integer;
  V: Byte;
begin
  L := Length(Data);
  if L = 0 then
    Exit;

  V := Ord(Data[L - 1]);  // 末是几表示加了几个字节

  if V <= L then
    SetLength(Data, L - V);
end;

procedure BytesAddPKCS5Padding(var Data: TBytes);
begin
  BytesAddPKCS7Padding(Data, PKCS5_BLOCK_SIZE);
end;

procedure BytesRemovePKCS5Padding(var Data: TBytes);
begin
  BytesRemovePKCS7Padding(Data);
end;

function GetISO10126PaddingByteLength(OrignalByteLen: Integer; BlockSize: Integer): Integer;
begin
  Result := GetPKCS7PaddingByteLength(OrignalByteLen, BlockSize); // 行为等同，可直接调用
end;

procedure AddISO10126Padding(Stream: TMemoryStream; BlockSize: Integer);
var
  R: Byte;
  Buf: array[0..255] of Byte;
begin
  R := Stream.Size mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;

  FillChar(Buf[0], R, 0);
  Buf[R - 1] := R;
  Stream.Position := Stream.Size;
  Stream.Write(Buf[0], R);
end;

procedure RemoveISO10126Padding(Stream: TMemoryStream);
begin
  RemovePKCS7Padding(Stream); // 行为等同，可直接调用
end;

function StrAddISO10126Padding(const Str: AnsiString; BlockSize: Integer): AnsiString;
var
  I, L: Integer;
  R: Byte;
begin
  L := Length(Str);
  R := L mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;

  SetLength(Result, L + R);
  if L > 0 then
    Move(Str[1], Result[1], L);

  if R > 1 then
  begin
    for I := 1 to R - 1 do
      Result[L + I] := #0;
  end;
  Result[L + R] := AnsiChar(R);
end;

function StrRemoveISO10126Padding(const Str: AnsiString): AnsiString;
begin
  Result := StrRemovePKCS7Padding(Str); // 行为等同，可直接调用
end;

procedure BytesAddISO10126Padding(var Data: TBytes; BlockSize: Integer);
var
  R: Byte;
  L, I: Integer;
begin
  L := Length(Data);
  R := L mod BlockSize;
  R := BlockSize - R;
  if R = 0 then
    R := R + BlockSize;

  SetLength(Data, L + R);
  if R > 1 then
  begin
    for I := 0 to R - 2 do
      Data[L + I] := 0;
  end;
  Data[L - 1 + R] := R;
end;

procedure BytesRemoveISO10126Padding(var Data: TBytes);
begin
  BytesRemovePKCS7Padding(Data); // 行为等同，可直接调用
end;

function EncryptPemStream(KeyHash: TCnKeyHashMethod; KeyEncrypt: TCnKeyEncryptMethod;
  Stream: TStream; const Password: string; out EncryptedHead: string): Boolean;
const
  CRLF = #13#10;
var
  ES: TMemoryStream;
  Keys: array[0..31] of Byte; // 最长的 Key 也只有 32 字节
  IvStr: AnsiString;
  HexIv: string;
  AESKey128: TCnAESKey128;
  AESKey192: TCnAESKey192;
  AESKey256: TCnAESKey256;
  AesIv: TCnAESBuffer;
  DesKey: TCnDESKey;
  Des3Key: TCn3DESKey;
  DesIv: TCnDESIv;
begin
  Result := False;

  // 流加密
  if (KeyEncrypt = ckeNone) or (Password = '') then
    Exit;

  // 生成随机 Iv
  SetLength(IvStr, ENC_TYPE_BLOCK_SIZE[KeyEncrypt]);
  CnRandomFillBytes(@(IvStr[1]), ENC_TYPE_BLOCK_SIZE[KeyEncrypt]);
  HexIv := DataToHex(@(IvStr[1]), ENC_TYPE_BLOCK_SIZE[KeyEncrypt], True); // 要求大写

  EncryptedHead := ENC_HEAD_PROCTYPE + ' ' +  ENC_HEAD_PROCTYPE_NUM + ',' + ENC_HEAD_ENCRYPTED + CRLF;
  EncryptedHead := EncryptedHead + ENC_HEAD_DEK + ' ' + ENC_TYPE_STRS[KeyEncrypt]
    + '-' + ENC_BLOCK_CBC + ',' + HexIv + CRLF;

  ES := TMemoryStream.Create;
  Stream.Position := 0;

  try
    if KeyHash = ckhMd5 then
    begin
      if not CnGetDeriveKey(AnsiString(Password), IvStr, @Keys[0], SizeOf(Keys)) then
        Exit;
    end
    else if KeyHash = ckhSha256 then
    begin
      if not CnGetDeriveKey(AnsiString(Password), IvStr, @Keys[0], SizeOf(Keys), ckdSha256) then
        Exit;
    end
    else
      Exit;

    case KeyEncrypt of
      ckeDES:
        begin
          Move(Keys[0], DesKey[0], SizeOf(TCnDESKey));
          Move(IvStr[1], DesIv[0], SizeOf(TCnDESIv));

          DESEncryptStreamCBC(Stream, Stream.Size, DesKey, DesIv, ES);
          Result := True;
        end;
      cke3DES:
        begin
          Move(Keys[0], Des3Key[0], SizeOf(TCn3DESKey));
          Move(IvStr[1], DesIv[0], SizeOf(TCn3DESIv));

          TripleDESEncryptStreamCBC(Stream, Stream.Size, Des3Key, DesIv, ES);
          Result := True;
        end;
      ckeAES128:
        begin
          Move(Keys[0], AESKey128[0], SizeOf(TCnAESKey128));
          Move(IvStr[1], AesIv[0], SizeOf(TCnAESBuffer));

          EncryptAES128StreamCBC(Stream, Stream.Size, AESKey128, AesIv, ES);
          Result := True;
        end;
      ckeAES192:
        begin
          Move(Keys[0], AESKey192[0], SizeOf(TCnAESKey192));
          Move(IvStr[1], AesIv[0], SizeOf(TCnAESBuffer));

          EncryptAES192StreamCBC(Stream, Stream.Size, AESKey192, AesIv, ES);
          Result := True;
        end;
      ckeAES256:
        begin
          Move(Keys[0], AESKey256[0], SizeOf(TCnAESKey256));
          Move(IvStr[1], AesIv[0], SizeOf(TCnAESBuffer));

          EncryptAES256StreamCBC(Stream, Stream.Size, AESKey256, AesIv, ES);
          Result := True;
        end;
    end;
  finally
    if ES.Size > 0 then
    begin
      // ES 写回 Stream
      Stream.Size := 0;
      Stream.Position := 0;
      ES.SaveToStream(Stream);
      Stream.Position := 0;
    end;
    ES.Free;
  end;
end;

// 拿加密算法、块运算、初始化向量，密码来解开 Base64 编码的 S，再写入 Stream 内
function DecryptPemString(const S, M1, M2, HexIv, Password: string; Stream: TMemoryStream;
  KeyHash: TCnKeyHashMethod): Boolean;
var
  DS: TMemoryStream;
  Keys: array[0..31] of Byte; // 最长的 Key 也只有 32 字节
  AESKey128: TCnAESKey128;
  AESKey192: TCnAESKey192;
  AESKey256: TCnAESKey256;
  IvStr: AnsiString;
  AesIv: TCnAESBuffer;
  DesKey: TCnDESKey;
  Des3Key: TCn3DESKey;
  DesIv: TCnDESIv;
begin
  Result := False;
  DS := nil;

  if (M1 = '') or (M2 = '') or (HexIv = '') or (Password = '') then
    Exit;

  try
    DS := TMemoryStream.Create;
    if ECN_BASE64_OK <> Base64Decode(AnsiString(S), DS, False) then
      Exit;

    DS.Position := 0;
    SetLength(IvStr, HexToData(HexIv));
    if Length(IvStr) > 0 then
      HexToData(HexIv, @IvStr[1]);

    // 根据密码明文与 Salt 以及 Hash 算法计算出加解密的 Key
    FillChar(Keys[0], SizeOf(Keys), 0);
    if KeyHash = ckhMd5 then
    begin
      if not CnGetDeriveKey(AnsiString(Password), IvStr, @Keys[0], SizeOf(Keys)) then
        Exit;
    end
    else if KeyHash = ckhSha256 then
    begin
      if not CnGetDeriveKey(AnsiString(Password), IvStr, @Keys[0], SizeOf(Keys), ckdSha256) then
        Exit;
    end
    else
      Exit;

    // DS 中是密文，要解到 Stream 中
    if (M1 = ENC_TYPE_AES256) and (M2 = ENC_BLOCK_CBC) then
    begin
      // 解开 AES-256-CBC 加密的密文
      Move(Keys[0], AESKey256[0], SizeOf(TCnAESKey256));
      Move(IvStr[1], AesIv[0], Min(SizeOf(TCnAESBuffer), Length(IvStr)));

      DecryptAES256StreamCBC(DS, DS.Size, AESKey256, AesIv, Stream);
      RemovePKCS7Padding(Stream);
      Result := True;
    end
    else if (M1 = ENC_TYPE_AES192) and (M2 = ENC_BLOCK_CBC) then
    begin
      // 解开 AES-192-CBC 加密的密文
      Move(Keys[0], AESKey192[0], SizeOf(TCnAESKey192));
      Move(IvStr[1], AesIv[0], Min(SizeOf(TCnAESBuffer), Length(IvStr)));

      DecryptAES192StreamCBC(DS, DS.Size, AESKey192, AesIv, Stream);
      RemovePKCS7Padding(Stream);
      Result := True;
    end
    else if (M1 = ENC_TYPE_AES128) and (M2 = ENC_BLOCK_CBC) then
    begin
      // 解开 AES-128-CBC 加密的密文，但 D5 下貌似可能碰到编译器的 Bug 导致出 AV。
      Move(Keys[0], AESKey128[0], SizeOf(TCnAESKey128));
      Move(IvStr[1], AesIv[0], Min(SizeOf(TCnAESBuffer), Length(IvStr)));

      DecryptAES128StreamCBC(DS, DS.Size, AESKey128, AesIv, Stream);
      RemovePKCS7Padding(Stream);
      Result := True;
    end
    else if (M1 = ENC_TYPE_DES) and (M2 = ENC_BLOCK_CBC) then
    begin
      // 解开 DES-CBC 加密的密文
      Move(Keys[0], DesKey[0], SizeOf(TCnDESKey));
      Move(IvStr[1], DesIv[0], Min(SizeOf(TCnDESIv), Length(IvStr)));

      DESDecryptStreamCBC(DS, DS.Size, DesKey, DesIv, Stream);
      RemovePKCS7Padding(Stream);
      Result := True;
    end
    else if (M1 = ENC_TYPE_3DES) and (M2 = ENC_BLOCK_CBC) then
    begin
      // 解开 3DES-CBC 加密的密文
      Move(Keys[0], Des3Key[0], SizeOf(TCn3DESKey));
      Move(IvStr[1], DesIv[0], Min(SizeOf(TCn3DESIv), Length(IvStr)));

      TripleDESDecryptStreamCBC(DS, DS.Size, Des3Key, DesIv, Stream);
      RemovePKCS7Padding(Stream);
      Result := True;
    end;
  finally
    DS.Free;
  end;
end;

function LoadPemStreamToMemory(Stream: TStream; const ExpectHead, ExpectTail: string;
  MemoryStream: TMemoryStream; const Password: string; KeyHashMethod: TCnKeyHashMethod): Boolean;
var
  I, J, HeadIndex, TailIndex: Integer;
  S, L1, L2, M1, M2, M3: string;
  Sl: TStringList;
begin
  Result := False;

  if (Stream <> nil) and (Stream.Size > 0) and (ExpectHead <> '') and (ExpectTail <> '') then
  begin
    Sl := TStringList.Create;
    try
      Sl.LoadFromStream(Stream);
      if Sl.Count > 2 then
      begin
        HeadIndex := -1;
        for I := 0 to Sl.Count - 1 do
        begin
          if Trim(Sl[I]) = ExpectHead then
          begin
            HeadIndex := I;
            Break;
          end;
        end;

        if HeadIndex < 0 then
          Exit;

        if HeadIndex > 0 then
          for I := 0 to HeadIndex - 1 do
            Sl.Delete(0);

        // 找到头了，现在找尾巴

        TailIndex := -1;
        for I := 0 to Sl.Count - 1 do
        begin
          if Trim(Sl[I]) = ExpectTail then
          begin
            TailIndex := I;
            Break;
          end;
        end;

        if TailIndex > 0 then // 找到了尾巴，删掉尾巴后面的东西
        begin
          if TailIndex < Sl.Count - 1 then
            for I := Sl.Count - 1 downto TailIndex + 1 do
              Sl.Delete(Sl.Count - 1);
        end
        else
          Exit;

        if Sl.Count < 2 then  // 没内容，退出
          Exit;

        // 头尾验证通过，读前两行判断是否加密
        L1 := Sl[1];
        if Pos(ENC_HEAD_PROCTYPE, L1) = 1 then // 是加密的
        begin
          Delete(L1, 1, Length(ENC_HEAD_PROCTYPE));
          I := Pos(',', L1);
          if I <= 1 then
            Exit;

          if Trim(Copy(L1, 1, I - 1)) <> ENC_HEAD_PROCTYPE_NUM then
            Exit;

          if Trim(Copy(L1, I + 1, MaxInt)) <> ENC_HEAD_ENCRYPTED then
            Exit;

          // ProcType: 4,ENCRYPTED 判断通过

          L2 := Sl[2];
          if Pos(ENC_HEAD_DEK, L2) <> 1 then
            Exit;

          Delete(L2, 1, Length(ENC_HEAD_DEK));
          I := Pos(',', L2);
          if I <= 1 then
            Exit;

          M1 := Trim(Copy(L2, 1, I - 1)); // 得到 AES256-CBC 这种
          M3 := UpperCase(Trim(Copy(L2, I + 1, MaxInt)));  // 得到加密时使用的初始化向量
          I := Pos('-', M1);
          if I <= 1 then
            Exit;
          J := Pos('-', Copy(M1, I + 1, MaxInt));
          if J > 0 then
            I := I + J; // AES-256-CBC

          M2 := UpperCase(Trim(Copy(M1, I + 1, MaxInt)));  // 得到块模式，如 ECB 或 CBC 等
          M1 := UpperCase(Trim(Copy(M1, 1, I - 1)));       // 得到加密算法，如 DES 或 AES 等

          // 头尾和这两行全删掉
          Sl.Delete(Sl.Count - 1);
          Sl.Delete(0);
          Sl.Delete(0);
          Sl.Delete(0);

          S := '';
          for I := 0 to Sl.Count - 1 do
            S := S + Sl[I];

          S := Trim(S);

          Result := DecryptPemString(S, M1, M2, M3, Password, MemoryStream, KeyHashMethod);
        end
        else // 未加密的，拼凑成 Base64 后解密
        begin
          Sl.Delete(Sl.Count - 1);
          Sl.Delete(0);
          S := '';
          for I := 0 to Sl.Count - 1 do
            S := S + Sl[I];

          S := Trim(S);

          // To De Base64 S
          MemoryStream.Clear;
{$IFDEF UNICODE}
          Result := (ECN_BASE64_OK = Base64Decode(AnsiString(S), MemoryStream, False));
{$ELSE}
          Result := (ECN_BASE64_OK = Base64Decode(S, MemoryStream, False));
{$ENDIF}
        end;
      end;
    finally
      Sl.Free;
    end;
  end;
end;

function LoadPemFileToMemory(const FileName, ExpectHead, ExpectTail: string;
  MemoryStream: TMemoryStream; const Password: string; KeyHashMethod: TCnKeyHashMethod): Boolean;
var
  Stream: TStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := LoadPemStreamToMemory(Stream, ExpectHead, ExpectTail, MemoryStream, Password, KeyHashMethod);
  finally
    Stream.Free;
  end;
end;

procedure SplitStringToList(const S: string; List: TStrings);
const
  LINE_WIDTH = 64;
var
  C, R: string;
begin
  if List = nil then
    Exit;

  List.Clear;
  if S <> '' then
  begin
    R := S;
    while R <> '' do
    begin
      C := Copy(R, 1, LINE_WIDTH);
      Delete(R, 1, LINE_WIDTH);
      List.Add(C);
    end;
  end;
end;

function SaveMemoryToPemFile(const FileName, Head, Tail: string;
  MemoryStream: TMemoryStream; KeyEncryptMethod: TCnKeyEncryptMethod;
  KeyHashMethod: TCnKeyHashMethod; const Password: string; Append: Boolean): Boolean;
var
  S, EH: string;
  List, Sl: TStringList;
begin
  Result := False;
  if (MemoryStream <> nil) and (MemoryStream.Size <> 0) then
  begin
    MemoryStream.Position := 0;

    if (KeyEncryptMethod <> ckeNone) and (Password <> '') then
    begin
      // 给 MemoryStream 对齐
      AddPKCS7Padding(MemoryStream, ENC_TYPE_BLOCK_SIZE[KeyEncryptMethod]);

      // 再加密
      if not EncryptPemStream(KeyHashMethod, KeyEncryptMethod, MemoryStream, Password, EH) then
        Exit;
    end;

    if ECN_BASE64_OK = Base64Encode(MemoryStream, S) then
    begin
      List := TStringList.Create;
      try
        SplitStringToList(S, List);

        List.Insert(0, Head);  // 普通头
        if EH <> '' then       // 加密头
          List.Insert(1, EH);
        List.Add(Tail);        // 普通尾

        if Append and FileExists(FileName) then
        begin
          Sl := TStringList.Create;
          try
            Sl.LoadFromFile(FileName);
            Sl.AddStrings(List);
            Sl.SaveToFile(FileName);
          finally
            Sl.Free;
          end;
        end
        else
          List.SaveToFile(FileName);

        Result := True;
      finally
        List.Free;
      end;
    end;
  end;
end;

function SaveMemoryToPemStream(Stream: TStream; const Head, Tail: string;
  MemoryStream: TMemoryStream; KeyEncryptMethod: TCnKeyEncryptMethod;
  KeyHashMethod: TCnKeyHashMethod; const Password: string; Append: Boolean): Boolean;
var
  S, EH: string;
  List: TStringList;
begin
  Result := False;
  if (MemoryStream <> nil) and (MemoryStream.Size <> 0) then
  begin
    MemoryStream.Position := 0;

    if (KeyEncryptMethod <> ckeNone) and (Password <> '') then
    begin
      // 给 MemoryStream 对齐
      AddPKCS7Padding(MemoryStream, ENC_TYPE_BLOCK_SIZE[KeyEncryptMethod]);

      // 再加密
      if not EncryptPemStream(KeyHashMethod, KeyEncryptMethod, MemoryStream, Password, EH) then
        Exit;
    end;

    if ECN_BASE64_OK = Base64Encode(MemoryStream, S) then
    begin
      List := TStringList.Create;
      try
        SplitStringToList(S, List);

        List.Insert(0, Head);  // 普通头
        if EH <> '' then       // 加密头
          List.Insert(1, EH);
        List.Add(Tail);        // 普通尾

        if not Append then
          Stream.Size := 0;

        List.SaveToStream(Stream);

        Result := True;
      finally
        List.Free;
      end;
    end;
  end;
end;

end.
