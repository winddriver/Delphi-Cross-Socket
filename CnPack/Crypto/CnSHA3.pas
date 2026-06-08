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

unit CnSHA3;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：SHA3 杂凑算法实现单元
* 单元作者：CnPack 开发组 (master@cnpack.org)
*           从匿名/佚名 Keccak C 代码与 Pascal 代码混合移植而来并补充部分功能。
* 备    注：本单元实现了 SHA3 系列杂凑算法及对应的 HMAC 算法，包括 SHA3-224/256/384/512
*           及可变长度摘要的 SHAKE128/SHAKE256等。
*
*           SHA3 规范来自 NIST.FIPS.202
*           SHA-3 Standard: Permutation-Based Hash and Extendable-Output Functions
*           其中额外定义了 Bit 串到 Byte 串的转换。
*           简而言之就是 Bit 串长度能够整除 8 时每 8 个 Bit 按位倒置就是一个字节，字节间的顺序保持不变。
*
* 开发平台：PWinXP + Delphi 5.0
* 兼容测试：PWinXP/7 + Delphi 5/6
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2025.11.06 V1.5
*               加入 SHAKE128/SHAKE256 的 Absorb/Squeeze 机制，允许连续输出摘要
*           2023.08.02 V1.4
*               加入 SHAKE128/SHAKE256 的可变长度摘要的计算
*           2022.04.26 V1.3
*               修改 LongWord 与 Integer 地址转换以支持 MacOS64
*           2019.12.12 V1.2
*               支持 TBytes
*           2019.04.15 V1.1
*               支持 Win32/Win64/MacOS
*           2017.11.10 V1.0
*               创建单元。
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes {$IFDEF MSWINDOWS}, Windows {$ENDIF}, CnNative, CnConsts;

const
  CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH = 32;
  {* SHAKE128 默认杂凑结果的字节长度}

  CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH = 64;
  {* SHAKE256 默认杂凑结果的字节长度}

type
  PCnSHA3GeneralDigest = ^TCnSHA3GeneralDigest;
  {* SHA3 系列通用的杂凑结果指针}
  TCnSHA3GeneralDigest = array[0..63] of Byte;
  {* SHA3 系列通用的杂凑结果，以最大的 64 字节为准}

  PCnSHA3_224Digest = ^TCnSHA3_224Digest;
  {* SHA3_224 杂凑结果指针}
  TCnSHA3_224Digest = array[0..27] of Byte;
  {* SHA3_224 杂凑结果，28 字节}

  PCnSHA3_256Digest = ^TCnSHA3_256Digest;
  {* SHA3_256 杂凑结果指针}
  TCnSHA3_256Digest = array[0..31] of Byte;
  {* SHA3_256 杂凑结果，32 字节}

  PCnSHA3_384Digest = ^TCnSHA3_384Digest;
  {* SHA3_384 杂凑结果指针}
  TCnSHA3_384Digest = array[0..47] of Byte;
  {* SHA3_384 杂凑结果，48 字节}

  PCnSHA3_512Digest = ^TCnSHA3_512Digest;
  {* SHA3_512 杂凑结果指针}
  TCnSHA3_512Digest = array[0..63] of Byte;
  {* SHA3_512 杂凑结果，64 字节}

  TCnSHA3Context = packed record
  {* SHA3 系列通用的上下文结构}
    State: array[0..24] of Int64;
    Index: Cardinal;
    DigestLen: Cardinal;
    Round: Cardinal;
    BlockLen: Cardinal;
    Squeezed: Cardinal;
    SqueezeCount: Cardinal;
    Block: array[0..255] of Byte;
    Ipad: array[0..143] of Byte;      {!< HMAC: inner padding        }
    Opad: array[0..143] of Byte;      {!< HMAC: outer padding        }
  end;

  TCnSHA3CalcProgressFunc = procedure(ATotal, AProgress: Int64; var Cancel:
    Boolean) of object;
  {* SHA3 系列通用的计算进度回调事件类型声明}

function SHA3_224(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_224Digest;
{* 对数据块进行 SHA3_224 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_256Digest;
{* 对数据块进行 SHA3_256 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_384Digest;
{* 对数据块进行 SHA3_384 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_512Digest;
{* 对数据块进行 SHA3_512 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHA3_224Buffer(const Buffer; Count: Cardinal): TCnSHA3_224Digest;
{* 对数据块进行 SHA3_224 计算。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256Buffer(const Buffer; Count: Cardinal): TCnSHA3_256Digest;
{* 对数据块进行 SHA3_256 计算。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384Buffer(const Buffer; Count: Cardinal): TCnSHA3_384Digest;
{* 对数据块进行 SHA3_384 计算。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512Buffer(const Buffer; Count: Cardinal): TCnSHA3_512Digest;
{* 对数据块进行 SHA3_512 计算。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128Buffer(const Buffer; Count: Cardinal;
  DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对数据块进行杂凑长度可变的 SHAKE128 计算，返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256Buffer(const Buffer; Count: Cardinal;
 DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对数据块进行杂凑长度可变的 SHAKE128 计算，返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Buffer                         - 待计算的数据块
     Count: Cardinal                      - 待计算的数据块字节长度
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

function SHA3_224Bytes(const Data: TBytes): TCnSHA3_224Digest;
{* 对字节数组进行 SHA3_224 计算。

   参数：
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256Bytes(const Data: TBytes): TCnSHA3_256Digest;
{* 对字节数组进行 SHA3_256 计算。

   参数：
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384Bytes(const Data: TBytes): TCnSHA3_384Digest;
{* 对字节数组进行 SHA3_384 计算。

   参数：
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512Bytes(const Data: TBytes): TCnSHA3_512Digest;
{* 对字节数组进行 SHA3_512 计算。

   参数：
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128Bytes(const Data: TBytes; DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对字节数组进行杂凑长度可变的 SHAKE128 计算，返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Data: TBytes                   - 待计算的字节数组
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256Bytes(const Data: TBytes; DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对字节数组进行杂凑长度可变的 SHAKE256 计算，返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Data: TBytes                   - 待计算的字节数组
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

function SHA3_224String(const Str: string): TCnSHA3_224Digest;
{* 对 String 类型数据进行 SHA3_224 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256String(const Str: string): TCnSHA3_256Digest;
{* 对 String 类型数据进行 SHA3_256 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384String(const Str: string): TCnSHA3_384Digest;
{* 对 String 类型数据进行 SHA3_384 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512String(const Str: string): TCnSHA3_512Digest;
{* 对 String 类型数据进行 SHA3_512 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128String(const Str: string; DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 String 类型数据进行杂凑长度可变的 SHAKE128 计算，返回长度为 DigestByteLength 的字节数组作为杂凑结果。
   注意 D2009 或以上版本的 string 为 UnicodeString，代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256String(const Str: string; DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 String 类型数据进行杂凑长度可变的 SHAKE256 计算，返回长度为 DigestByteLength 的字节数组作为杂凑结果。
   注意 D2009 或以上版本的 string 为 UnicodeString，代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

function SHA3_224StringA(const Str: AnsiString): TCnSHA3_224Digest;
{* 对 AnsiString 类型数据进行 SHA3_224 计算。

   参数：
     const Str: AnsiString                - 待计算的字符串

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_224StringW(const Str: WideString): TCnSHA3_224Digest;
{* 对 WideString 类型数据进行 SHA3_224 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256StringA(const Str: AnsiString): TCnSHA3_256Digest;
{* 对 AnsiString 类型数据进行 SHA3_256 计算。

   参数：
     const Str: AnsiString                - 待计算的字符串

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_256StringW(const Str: WideString): TCnSHA3_256Digest;
{* 对 WideString类型数据进行 SHA3_256 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384StringA(const Str: AnsiString): TCnSHA3_384Digest;
{* 对 AnsiString 类型数据进行 SHA3_384 计算。

   参数：
     const Str: AnsiString                - 待计算的字符串

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_384StringW(const Str: WideString): TCnSHA3_384Digest;
{* 对 WideString 类型数据进行 SHA3_384 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512StringA(const Str: AnsiString): TCnSHA3_512Digest;
{* 对 AnsiString 类型数据进行 SHA3_512 计算。

   参数：
     const Str: AnsiString                - 待计算的字符串
                                            
   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHA3_512StringW(const Str: WideString): TCnSHA3_512Digest;
{* 对 WideString 类型数据进行 SHA512 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128StringA(const Str: AnsiString;
  DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 AnsiString 类型数据进行杂凑长度可变的直接 SHAKE128 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Str: AnsiString                - 待计算的字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE128StringW(const Str: WideString;
  DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 WideString 类型数据进行杂凑长度可变的直接 SHAKE128 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256StringA(const Str: AnsiString; DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 AnsiString 类型数据进行杂凑长度可变的直接 SHAKE128 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Str: AnsiString                - 待计算的字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

function SHAKE256StringW(const Str: WideString; DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 WideString 类型数据进行杂凑长度可变的直接 SHAKE256 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

{$IFDEF UNICODE}

function SHA3_224UnicodeString(const Str: string): TCnSHA3_224Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_224 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256UnicodeString(const Str: string): TCnSHA3_256Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_256 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384UnicodeString(const Str: string): TCnSHA3_384Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_384 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512UnicodeString(const Str: string): TCnSHA3_512Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_512 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128UnicodeString(const Str: string;
  DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 UnicodeString 类型数据进行杂凑长度可变的直接 SHAKE128 计算，直接计算内部 UTF16 内容，不进行转换。
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Str: string                    - 待计算的宽字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256UnicodeString(const Str: string;
  DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 UnicodeString 类型数据进行杂凑长度可变的直接 SHAKE256 计算，直接计算内部 UTF16 内容，不进行转换。
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Str: string                    - 待计算的宽字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

{$ELSE}

function SHA3_224UnicodeString(const Str: WideString): TCnSHA3_224Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_224 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256UnicodeString(const Str: WideString): TCnSHA3_256Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_256 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384UnicodeString(const Str: WideString): TCnSHA3_384Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_384 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512UnicodeString(const Str: WideString): TCnSHA3_512Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA3_512 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128UnicodeString(const Str: WideString;
  DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 UnicodeString 类型数据进行杂凑长度可变的直接 SHAKE128 计算，直接计算内部 UTF16 内容，不进行转换。
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Str: WideString                - 待计算的宽字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256UnicodeString(const Str: WideString;
  DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH): TBytes;
{* 对 UnicodeString 类型数据进行杂凑长度可变的直接 SHAKE256 计算，直接计算内部 UTF16 内容，不进行转换。
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const Str: WideString                - 待计算的宽字符串
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

{$ENDIF}

function SHA3_224File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc =
  nil): TCnSHA3_224Digest;
{* 对指定文件内容进行 SHA3_224 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_224Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc = nil):
  TCnSHA3_224Digest;
{* 对指定流数据进行 SHA3_224 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_224Digest              - 返回的 SHA3_224 杂凑值
}

function SHA3_256File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc =
  nil): TCnSHA3_256Digest;
{* 对指定文件内容进行 SHA3_256 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_256Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc = nil):
  TCnSHA3_256Digest;
{* 对指定流数据进行 SHA3_256 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc =
  nil): TCnSHA3_384Digest;
{* 对指定文件内容进行 SHA3_384 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_384Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc = nil):
  TCnSHA3_384Digest;
{* 对指定流数据进行 SHA3_384 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc =
  nil): TCnSHA3_512Digest;
{* 对指定文件内容进行 SHA3_512 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHA3_512Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc = nil):
  TCnSHA3_512Digest;
{* 对指定流数据进行 SHA3_512 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

function SHAKE128File(const FileName: string;
  DigestByteLength: Cardinal  = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH;
  CallBack: TCnSHA3CalcProgressFunc = nil): TBytes;
{* 对指定文件内容进行杂凑长度可变的 SHAKE128 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const FileName: string               - 待计算的文件名
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TBytes                         - 返回 SHAKE128杂凑值
}

function SHAKE128Stream(Stream: TStream;
  DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH;
  CallBack: TCnSHA3CalcProgressFunc = nil): TBytes;
{* 对指定数据流进行杂凑长度可变的 SHAKE128 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     Stream: TStream                      - 待计算的流内容
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TBytes                         - 返回 SHAKE128 杂凑值
}

function SHAKE256File(const FileName: string;
  DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH;
  CallBack: TCnSHA3CalcProgressFunc = nil): TBytes;
{* 对指定文件内容进行杂凑长度可变的 SHAKE256 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     const FileName: string               - 待计算的文件名
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

function SHAKE256Stream(Stream: TStream;
  DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH;
  CallBack: TCnSHA3CalcProgressFunc = nil): TBytes;
{* 对指定数据流进行杂凑长度可变的 SHAKE256 计算，
   返回长度为 DigestByteLength 的字节数组作为杂凑结果。

   参数：
     Stream: TStream                      - 待计算的流内容
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度
     CallBack: TCnSHA3CalcProgressFunc    - 进度回调函数，默认为空

   返回值：TBytes                         - 返回 SHAKE256 杂凑值
}

// 以下三个函数用于外部持续对数据进行零散的 SHA3_224 计算，SHA3_224Update 可多次被调用

procedure SHA3_224Init(var Context: TCnSHA3Context);
{* 初始化一轮 SHA3_224 计算上下文，准备计算 SHA3_224 结果。

   参数：
     var Context: TCnSHA3Context          - 待初始化的通用 SHA3 上下文

   返回值：（无）
}

procedure SHA3_224Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA3_224 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA3_224Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_224Digest);
{* 结束本轮计算，将 SHA3_224 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     var Digest: TCnSHA3_224Digest        - 返回的 SHA3_224 杂凑值

   返回值：（无）
}

// 以下三个函数用于外部持续对数据进行零散的 SHA3_256 计算，SHA3_256Update 可多次被调用

procedure SHA3_256Init(var Context: TCnSHA3Context);
{* 初始化一轮 SHA3_256 计算上下文，准备计算 SHA3_256 结果。

   参数：
     var Context: TCnSHA3Context          -  待初始化的通用 SHA3 上下文

   返回值：（无）
}

procedure SHA3_256Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA3_256 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA3_256Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_256Digest);
{* 结束本轮计算，将 SHA3_256 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     var Digest: TCnSHA3_256Digest        - 返回的 SHA3_256 杂凑值

   返回值：（无）
}

// 以下三个函数用于外部持续对数据进行零散的 SHA3_384 计算，SHA3_384Update 可多次被调用

procedure SHA3_384Init(var Context: TCnSHA3Context);
{* 初始化一轮 SHA3_384 计算上下文，准备计算 SHA3_384 结果。

   参数：
     var Context: TCnSHA3Context          - 待初始化的通用 SHA3 上下文

   返回值：（无）
}

procedure SHA3_384Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA3_384 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA3_384Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_384Digest);
{* 结束本轮计算，将 SHA3_384 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     var Digest: TCnSHA3_384Digest        - 返回的 SHA3_384 杂凑值

   返回值：（无）
}

// 以下三个函数用于外部持续对数据进行零散的 SHA3_512 计算，SHA3_512Update 可多次被调用

procedure SHA3_512Init(var Context: TCnSHA3Context);
{* 初始化一轮 SHA3_512 计算上下文，准备计算 SHA3_512 结果

   参数：
     var Context: TCnSHA3Context          - 待初始化的通用 SHA3 上下文

   返回值：（无）
}

procedure SHA3_512Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA3_512 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA3_512Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_512Digest);
{* 结束本轮计算，将 SHA3_512 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     var Digest: TCnSHA3_512Digest        - 返回的 SHA3_512 杂凑值

   返回值：（无）
}

// 以下几个函数用于外部持续对数据进行零散的 SHAKE128 计算，SHAKE128Update 可多次被调用

procedure SHAKE128Init(var Context: TCnSHA3Context; DigestByteLength: Cardinal = CN_SHAKE128_DEF_DIGEST_BYTE_LENGTH);
{* 初始化一轮 SHAKE128 计算上下文，准备计算 SHAKE128 结果，
   DigestByteLength 为所需的杂凑的字节长度。

   参数：
     var Context: TCnSHA3Context          - 待初始化的通用 SHA3 上下文
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：（无）
}

procedure SHAKE128Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHAKE128 计算，等同于 SHAKE128Absorb。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：（无）
}

procedure SHAKE128Absorb(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHAKE128 计算，等同于 SHAKE128Update。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：（无）
}

procedure SHAKE128Final(var Context: TCnSHA3Context; out Digest: TBytes);
{* 结束本轮计算，将 SHAKE128 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     out Digest: TBytes                   - 返回的 SHAKE128 杂凑值

   返回值：（无）
}

function SHAKE128Squeeze(var Context: TCnSHA3Context; DigestByteLength: Integer): TBytes;
{* 不结束本轮计算，将 SHAKE128 结果返回 DigestByteLength 字节长的内容，
   后续还可继续 Squeeze，但不能 Absorb 了。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     DigestByteLength: Integer            - 需要返回的 SHAKE128 杂凑字节长度

   返回值：TBytes                         - 返回的 SHAKE128 杂凑值
}

// 以下几个函数用于外部持续对数据进行零散的 SHAKE128 计算，SHAKE128Update 可多次被调用

procedure SHAKE256Init(var Context: TCnSHA3Context; DigestByteLength: Cardinal = CN_SHAKE256_DEF_DIGEST_BYTE_LENGTH);
{* 初始化一轮 SHAKE256 计算上下文，准备计算 SHAKE256 结果，
   DigestByteLength 为所需的杂凑的字节长度。

   参数：
     var Context: TCnSHA3Context          - 待初始化的通用 SHA3 上下文
     DigestByteLength: Cardinal           - 所需的杂凑结果字节长度

   返回值：（无）
}

procedure SHAKE256Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHAKE256 计算，等同于 SHAKE256Absorb。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：（无）
}

procedure SHAKE256Absorb(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHAKE256 计算，等同于 SHAKE256Update。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：（无）
}

procedure SHAKE256Final(var Context: TCnSHA3Context; out Digest: TBytes);
{* 结束本轮计算，将 SHAKE256 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     out Digest: TBytes                   - 返回的 SHAKE256 杂凑值

   返回值：（无）
}

function SHAKE256Squeeze(var Context: TCnSHA3Context; DigestByteLength: Integer): TBytes;
{* 不结束本轮计算，将 SHAKE256 结果返回 DigestByteLength 字节长的内容，
   后续还可继续 Squeeze，但不能 Absorb 了。

   参数：
     var Context: TCnSHA3Context          - 通用 SHA3 上下文
     DigestByteLength: Integer            - 需要返回的 SHAKE256 杂凑字节长度

   返回值：TBytes                         - 返回的 SHAKE256 杂凑值
}

function SHA3_224Print(const Digest: TCnSHA3_224Digest): string;
{* 以十六进制格式输出 SHA3_224 杂凑值。

   参数：
     const Digest: TCnSHA3_224Digest      - 指定的 SHA3_224 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA3_256Print(const Digest: TCnSHA3_256Digest): string;
{* 以十六进制格式输出 SHA3_256 杂凑值。

   参数：
     const Digest: TCnSHA3_256Digest      - 指定的 SHA3_256 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA3_384Print(const Digest: TCnSHA3_384Digest): string;
{* 以十六进制格式输出 SHA3_384 杂凑值。
   参数：
     const Digest: TCnSHA3_384Digest      - 指定的 SHA3_384 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA3_512Print(const Digest: TCnSHA3_512Digest): string;
{* 以十六进制格式输出 SHA3_512 杂凑值。

   参数：
     const Digest: TCnSHA3_512Digest      - 指定的 SHA3_512 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHAKE128Print(const Digest: TBytes): string;
{* 以十六进制格式输出 SHAKE128 杂凑值。

   参数：
     const Digest: TBytes                 - 指定的 SHAKE128 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHAKE256Print(const Digest: TBytes): string;
{* 以十六进制格式输出 SHAKE256 杂凑值。

   参数：
     const Digest: TBytes                 - 指定的 SHAKE128 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA3_224Match(const D1: TCnSHA3_224Digest; const D2: TCnSHA3_224Digest): Boolean;
{* 比较两个 SHA3_224 杂凑值是否相等。

   参数：
     const D1: TCnSHA3_224Digest          - 待比较的 SHA3_224 杂凑值一
     const D2: TCnSHA3_224Digest          - 待比较的 SHA3_224 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA3_256Match(const D1: TCnSHA3_256Digest; const D2: TCnSHA3_256Digest): Boolean;
{* 比较两个 SHA3_256 杂凑值是否相等。

   参数：
     const D1: TCnSHA3_256Digest          - 待比较的 SHA3_256 杂凑值一
     const D2: TCnSHA3_256Digest          - 待比较的 SHA3_256 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA3_384Match(const D1: TCnSHA3_384Digest; const D2: TCnSHA3_384Digest): Boolean;
{* 比较两个 SHA3_384 杂凑值是否相等。

   参数：
     const D1: TCnSHA3_384Digest          - 待比较的 SHA3_384 杂凑值一
     const D2: TCnSHA3_384Digest          - 待比较的 SHA3_384 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA3_512Match(const D1: TCnSHA3_512Digest; const D2: TCnSHA3_512Digest): Boolean;
{* 比较两个 SHA3_512 杂凑值是否相等。

   参数：
     const D1: TCnSHA3_512Digest          - 待比较的 SHA3_512 杂凑值一
     const D2: TCnSHA3_512Digest          - 待比较的 SHA3_512 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHAKE128Match(const D1: TBytes; const D2: TBytes): Boolean;
{* 比较两个 SHAKE128 杂凑值是否相等。

   参数：
     const D1: TBytes                     - 待比较的 SHAKE128 杂凑值一
     const D2: TBytes                     - 待比较的 SHAKE128 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHAKE256Match(const D1: TBytes; const D2: TBytes): Boolean;
{* 比较两个 SHAKE256 杂凑值是否相等。

   参数：
     const D1: TBytes                     - 待比较的 SHAKE256 杂凑值一
     const D2: TBytes                     - 待比较的 SHAKE256 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA3_224DigestToStr(const Digest: TCnSHA3_224Digest): string;
{* SHA3_224 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA3_224Digest      - 待转换的 SHA3_224 杂凑值

   返回值：string                         - 返回的字符串
}

function SHA3_256DigestToStr(const Digest: TCnSHA3_256Digest): string;
{* SHA3_256 杂凑值内容直接转 string，每字节对应一字符。
 |<PRE>
   Digest: TSHA3_256Digest   - 需要
 |</PRE>

   参数：
     const Digest: TCnSHA3_256Digest      - 待转换的 SHA3_256 杂凑值

   返回值：string                         - 返回的字符串
}

function SHA3_384DigestToStr(const Digest: TCnSHA3_384Digest): string;
{* SHA3_384 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA3_384Digest      - 待转换的 SHA3_384 杂凑值

   返回值：string                         - 返回的字符串
}

function SHA3_512DigestToStr(const Digest: TCnSHA3_512Digest): string;
{* SHA3_512 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA3_512Digest      - 待转换的 SHA3_512 杂凑值

   返回值：string                         - 返回的字符串
}

function SHAKE128DigestToStr(const Digest: TBytes): string;
{* SHAKE128 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TBytes                 - 待转换的 SHAKE128 杂凑值

   返回值：string                         - 返回的字符串
}

function SHAKE256DigestToStr(const Digest: TBytes): string;
{* SHAKE256 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TBytes                 - 待转换的 SHAKE256 杂凑值

   返回值：string                         - 返回的字符串
}

procedure SHA3_224Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_224Digest);
{* 基于 SHA3_224 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA3_224 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA3_224 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA3_224Digest        - 返回的 SHA3_224 杂凑值

   返回值：（无）
}

procedure SHA3_256Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_256Digest);
{* 基于 SHA3_256 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA3_256 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA3_256 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA3_256Digest        - 返回的 SHA3_256 杂凑值

   返回值：（无）
}

procedure SHA3_384Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_384Digest);
{* 基于 SHA3_384 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA3_384 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA3_384 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA3_384Digest        - 返回的 SHA3_384 杂凑值

   返回值：（无）
}

procedure SHA3_512Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_512Digest);
{* 基于 SHA3_512 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA3_512 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA3_512 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA3_512Digest        - 返回的 SHA3_512 杂凑值

   返回值：（无）
}

function SHA3_224HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_224Digest;
{* 对字节数组进行基于 SHA3_224 的 HMAC 计算。

   参数：
     const Key: TBytes                         - 待参与 SHA3_224 计算的密钥字节数组
     const Data: TBytes                        - 待计算的字节数组

   返回值：TCnSHA3_224Digest                   - 返回的 SHA3_224 杂凑值
}

function SHA3_256HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_256Digest;
{* 对字节数组进行基于 SHA3_256 的 HMAC 计算。

   参数：
     const Key: TBytes                    - 待参与 SHA3_256 计算的密钥字节数组
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_256Digest              - 返回的 SHA3_256 杂凑值
}

function SHA3_384HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_384Digest;
{* 对字节数组进行基于 SHA3_384 的 HMAC 计算。

   参数：
     const Key: TBytes                    - 待参与 SHA3_384 计算的密钥字节数组
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_384Digest              - 返回的 SHA3_384 杂凑值
}

function SHA3_512HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_512Digest;
{* 对字节数组进行基于 SHA3_512 的 HMAC 计算。

   参数：
     const Key: TBytes                    - 待参与 SHA3_512 计算的密钥字节数组
     const Data: TBytes                   - 待计算的字节数组

   返回值：TCnSHA3_512Digest              - 返回的 SHA3_512 杂凑值
}

implementation

type
  TSHA3Type = (stSHA3_224, stSHA3_256, stSHA3_384, stSHA3_512, stSHAKE128, stSHAKE256);

const
  MAX_FILE_SIZE = 512 * 1024 * 1024;
  STREAM_BUF_SIZE = 4096 * 1024;
  // If file size <= this size (bytes), using Mapping, else stream

  SHA3_ROUNDS = 24;
  SHA3_STATE_LEN = 25;

  SHA3_224_OUTPUT_LENGTH_BYTE = 28;
  SHA3_256_OUTPUT_LENGTH_BYTE = 32;
  SHA3_384_OUTPUT_LENGTH_BYTE = 48;
  SHA3_512_OUTPUT_LENGTH_BYTE = 64;

  SHA3_224_BLOCK_SIZE_BYTE = 144;
  SHA3_256_BLOCK_SIZE_BYTE = 136;
  SHA3_384_BLOCK_SIZE_BYTE = 104;
  SHA3_512_BLOCK_SIZE_BYTE = 72;

  SHAKE128_BLOCK_SIZE_BYTE = 168;
  SHAKE256_BLOCK_SIZE_BYTE = 136;

  HMAC_SHA3_224_BLOCK_SIZE_BYTE = SHA3_224_BLOCK_SIZE_BYTE;
  HMAC_SHA3_256_BLOCK_SIZE_BYTE = SHA3_256_BLOCK_SIZE_BYTE;
  HMAC_SHA3_384_BLOCK_SIZE_BYTE = SHA3_384_BLOCK_SIZE_BYTE;
  HMAC_SHA3_512_BLOCK_SIZE_BYTE = SHA3_512_BLOCK_SIZE_BYTE;

  HMAC_SHA3_224_OUTPUT_LENGTH_BYTE = SHA3_224_OUTPUT_LENGTH_BYTE;
  HMAC_SHA3_256_OUTPUT_LENGTH_BYTE = SHA3_256_OUTPUT_LENGTH_BYTE;
  HMAC_SHA3_384_OUTPUT_LENGTH_BYTE = SHA3_384_OUTPUT_LENGTH_BYTE;
  HMAC_SHA3_512_OUTPUT_LENGTH_BYTE = SHA3_512_OUTPUT_LENGTH_BYTE;

  KECCAKF_ROUND_CONSTS: array[0..23] of TUInt64 = (
    $0000000000000001, $0000000000008082, $800000000000808A,
    $8000000080008000, $000000000000808B, $0000000080000001,
    $8000000080008081, $8000000000008009, $000000000000008A,
    $0000000000000088, $0000000080008009, $000000008000000A,
    $000000008000808B, $800000000000008B, $8000000000008089,
    $8000000000008003, $8000000000008002, $8000000000000080,
    $000000000000800A, $800000008000000A, $8000000080008081,
    $8000000000008080, $0000000080000001, $8000000080008008
  );

  KECCAKF_ROT_CONSTS: array[0..23] of Integer = (
    1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
  );

  KECCAKF_PILN: array[0..23] of Integer = (
    10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4,
    15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1
  );

function ROTL64(Q: TUInt64; N: Integer): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (Q shl N) xor (Q shr (64 - N));
end;

// 一轮 SHA3 计算，输入是 Block 内容，输出是 State 内容
procedure SHA3_Transform(var Context: TCnSHA3Context);
type
  PUInt64Array = ^TUInt64Array;
  TUInt64Array = array[0..4095] of TUInt64;
var
  I, J, R, L: Integer;
  P: PUInt64Array;
  T: TUInt64;
  BC: array[0..4] of TUInt64;
begin
  P := PUInt64Array(@(Context.Block[0]));
  I := 0;
  L := Integer(Context.BlockLen div 8);
  while I < L do
  begin
    Context.State[I] := Context.State[I] xor P^[I];
    Inc(I);
  end;

  for R := 0 to Context.Round - 1 do
  begin
    // Theta
    for I := 0 to 4 do
    begin
      BC[I] := Context.State[I] xor Context.State[I + 5] xor Context.State[I + 10]
        xor Context.State[I + 15] xor Context.State[I + 20];
    end;
    for I := 0 to 4 do
    begin
      T := BC[(I + 4) mod 5] xor ROTL64(BC[(I + 1) mod 5], 1);
      for J := 0 to 4 do
        Context.State[5 * J + I] := Context.State[5 * J + I] xor T;
    end;

    // Rho Pi
    T := Context.State[1];
    for I := 0 to 23 do
    begin
      J := KECCAKF_PILN[I];
      BC[0] := Context.State[J];
      Context.State[J] := ROTL64(T, KECCAKF_ROT_CONSTS[I]);
      T := BC[0];
    end;

    // Chi
    for J := 0 to 4 do
    begin
      for I := 0 to 4 do
        BC[I] := Context.State[5 * J + I];

      for I := 0 to 4 do
        Context.State[5 * J + I] := Context.State[5 * J + I] xor
          ((not BC[(I + 1) mod 5]) and BC[(I + 2) mod 5]);
    end;

    // Iota
    Context.State[0] := Context.State[0] xor KECCAKF_ROUND_CONSTS[R];
  end;
end;

procedure SHA3Init(var Context: TCnSHA3Context; SHA3Type: TSHA3Type;
  DigestByteLength: Cardinal = 0);
begin
  FillChar(Context.State, SizeOf(Context.State), 0);
  FillChar(Context.Block, SizeOf(Context.Block), 0);
  Context.Index := 0;
  Context.Squeezed := 0;
  Context.SqueezeCount := 0;
  Context.Round := SHA3_ROUNDS;

  case SHA3Type of
  stSHA3_224:
    begin
      Context.BlockLen := SHA3_224_BLOCK_SIZE_BYTE;
      Context.DigestLen := SHA3_224_OUTPUT_LENGTH_BYTE;
    end;
  stSHA3_256:
    begin
      Context.BlockLen := SHA3_256_BLOCK_SIZE_BYTE;
      Context.DigestLen := SHA3_256_OUTPUT_LENGTH_BYTE;
    end;
  stSHA3_384:
    begin
      Context.BlockLen := SHA3_384_BLOCK_SIZE_BYTE;
      Context.DigestLen := SHA3_384_OUTPUT_LENGTH_BYTE;
    end;
  stSHA3_512:
    begin
      Context.BlockLen := SHA3_512_BLOCK_SIZE_BYTE;
      Context.DigestLen := SHA3_512_OUTPUT_LENGTH_BYTE;
    end;
  stSHAKE128:
    begin
      Context.BlockLen := SHAKE128_BLOCK_SIZE_BYTE;
      Context.DigestLen := DigestByteLength;
    end;
  stSHAKE256:
    begin
      Context.BlockLen := SHAKE256_BLOCK_SIZE_BYTE;
      Context.DigestLen := DigestByteLength;
    end;
  end;
end;

procedure SHA3Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
var
  R, Idx: Cardinal;
begin
  Idx := Context.Index;                                 // Index 是 Block 中的初始位置指针
  repeat
    if ByteLength < Context.BlockLen - Idx then
      R := ByteLength                                   // 填不满
    else
      R := Context.BlockLen - Idx;                      // 填满可能还有剩

    FillChar(Context.Block[Idx], SizeOf(Context.Block) - Idx, 0);  // 确保尾巴为 0
    Move(Input^, Context.Block[Idx], R);                // 且 Block 的前半部分不被覆盖

    if (Idx + R) < Context.BlockLen then                // 如果没填满则本轮不计算
    begin                                               // 只更新 Index 位置指针
      Idx := Idx + R;
      Break;
    end;

    SHA3_Transform(Context);
    Dec(ByteLength, R);
    Idx := 0;
    Inc(Input, R);
  until False;
  Context.Index := Idx;
end;

procedure SHA3UpdateW(var Context: TCnSHA3Context; Input: PWideChar; CharLength: Cardinal);
var
{$IFDEF MSWINDOWS}
  Content: PAnsiChar;
  Len: Cardinal;
{$ELSE}
  S: string; // 必须是 UnicodeString
  A: AnsiString;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  GetMem(Content, CharLength * SizeOf(WideChar));
  try
    Len := WideCharToMultiByte(0, 0, Input, CharLength, // 代码页默认用 0
      PAnsiChar(Content), CharLength * SizeOf(WideChar), nil, nil);
    SHA3Update(Context, Content, Len);
  finally
    FreeMem(Content);
  end;
{$ELSE}  // MacOS 下直接把 UnicodeString 转成 AnsiString 计算，不支持非 Windows 非 Unicode 平台
  S := StrNew(Input);
  A := AnsiString(S);
  SHA3Update(Context, @A[1], Length(A));
{$ENDIF}
end;

// SHA3_224/256/384/512 专用
procedure SHA3Final(var Context: TCnSHA3Context; var Digest: TCnSHA3GeneralDigest); overload;
begin
  Context.Block[Context.Index] := 6;
  Context.Block[Context.BlockLen - 1] := Context.Block[Context.BlockLen - 1] or $80;
  SHA3_Transform(Context);
  Move(Context.State[0], Digest[0], Context.DigestLen);
end;

// SHAKE128 和 SHAKE256 专用
procedure SHA3Final(var Context: TCnSHA3Context; out Digest: TBytes); overload;
var
  Idx, DL: Cardinal;
begin
  Context.Block[Context.Index] := $1F;
  Context.Block[Context.BlockLen - 1] := Context.Block[Context.BlockLen - 1] or $80;
  SHA3_Transform(Context);

  SetLength(Digest, Context.DigestLen);
  if Context.DigestLen <= Context.BlockLen then
    Move(Context.State[0], Digest[0], Context.DigestLen)
  else
  begin
    DL := Context.DigestLen;
    Idx := 0;

    while DL >= Context.BlockLen do
    begin
      Move(Context.State[0], Digest[Idx], Context.BlockLen);
      Inc(Idx, Context.BlockLen);
      Dec(DL, Context.BlockLen);

      if DL > 0 then
      begin
        FillChar(Context.Block[0], SizeOf(Context.Block), 0);
        SHA3_Transform(Context);
      end;
    end;

    if DL > 0 then
      Move(Context.State[0], Digest[Idx], DL);
  end;
end;

function SHAKE3Squeeze(var Context: TCnSHA3Context; DigestByteLength: Integer): TBytes;
var
  Idx, DL: Cardinal;
  BlockLen: Cardinal;
  BytesToCopy: Cardinal;
begin
  if DigestByteLength <= 0 then
  begin
    Result := nil;
    Exit;
  end;

  BlockLen := Context.BlockLen;

  // 如果是第一次进入，先完成 Absorb 阶段
  if Context.Squeezed = 0 then
  begin
    Context.Block[Context.Index] := $1F;
    Context.Block[Context.BlockLen - 1] := Context.Block[Context.BlockLen - 1] or $80;
    SHA3_Transform(Context);
    Context.Squeezed := 1;     // 标记已经完成吸收阶段
    Context.SqueezeCount := 0; // 重置挤压计数
  end;

  // 初始化输出数组
  SetLength(Result, DigestByteLength);
  DL := DigestByteLength;
  Idx := 0;

  // 从当前状态提取数据
  while DL > 0 do
  begin
    // 计算当前块中剩余可提取的字节数
    BytesToCopy := BlockLen - Context.SqueezeCount;
    if BytesToCopy > DL then
      BytesToCopy := DL;

    // 从状态中提取数据
    Move(PByteArray(@Context.State[0])[Context.SqueezeCount], Result[Idx], BytesToCopy);

    // 更新计数器和指针
    Inc(Context.SqueezeCount, BytesToCopy);
    Inc(Idx, BytesToCopy);
    Dec(DL, BytesToCopy);

    // 如果当前块已用完，需要变换状态获取下一个块
    if (DL > 0) and (Context.SqueezeCount >= BlockLen) then
    begin
      FillChar(Context.Block[0], SizeOf(Context.Block), 0);
      SHA3_Transform(Context);
      Context.SqueezeCount := 0; // 重置为新的状态块的开始
    end;
  end;
end;

procedure SHA3_224Init(var Context: TCnSHA3Context);
begin
  SHA3Init(Context, stSHA3_224);
end;

procedure SHA3_224Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_224Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_224Digest);
var
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Final(Context, Res);
  Move(Res[0], Digest[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

procedure SHA3_256Init(var Context: TCnSHA3Context);
begin
  SHA3Init(Context, stSHA3_256);
end;

procedure SHA3_256Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_256Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_256Digest);
var
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Final(Context, Res);
  Move(Res[0], Digest[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

procedure SHA3_384Init(var Context: TCnSHA3Context);
begin
  SHA3Init(Context, stSHA3_384);
end;

procedure SHA3_384Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_384Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_384Digest);
var
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Final(Context, Res);
  Move(Res[0], Digest[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

procedure SHA3_512Init(var Context: TCnSHA3Context);
begin
  SHA3Init(Context, stSHA3_512);
end;

procedure SHA3_512Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_512Final(var Context: TCnSHA3Context; var Digest: TCnSHA3_512Digest);
var
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Final(Context, Res);
  Move(Res[0], Digest[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

procedure SHAKE128Init(var Context: TCnSHA3Context; DigestByteLength: Cardinal);
begin
  SHA3Init(Context, stSHAKE128, DigestByteLength);
end;

procedure SHAKE128Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHAKE128Absorb(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHAKE128Final(var Context: TCnSHA3Context; out Digest: TBytes);
begin
  SHA3Final(Context, Digest);
end;

function SHAKE128Squeeze(var Context: TCnSHA3Context; DigestByteLength: Integer): TBytes;
begin
  Result := SHAKE3Squeeze(Context, DigestByteLength);
end;

procedure SHAKE256Init(var Context: TCnSHA3Context; DigestByteLength: Cardinal);
begin
  SHA3Init(Context, stSHAKE256, DigestByteLength);
end;

procedure SHAKE256Update(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHAKE256Absorb(var Context: TCnSHA3Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHAKE256Final(var Context: TCnSHA3Context; out Digest: TBytes);
begin
  SHA3Final(Context, Digest);
end;

function SHAKE256Squeeze(var Context: TCnSHA3Context; DigestByteLength: Integer): TBytes;
begin
  Result := SHAKE3Squeeze(Context, DigestByteLength);
end;

// 对数据块进行 SHA3_224位计算
function SHA3_224(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_224Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, Input, ByteLength);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_256位计算
function SHA3_256(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_256Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, Input, ByteLength);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_384位计算
function SHA3_384(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_384Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, Input, ByteLength);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_512位计算
function SHA3_512(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA3_512Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, Input, ByteLength);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_224 计算
function SHA3_224Buffer(const Buffer; Count: Cardinal): TCnSHA3_224Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, PAnsiChar(@Buffer), Count);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_256 计算
function SHA3_256Buffer(const Buffer; Count: Cardinal): TCnSHA3_256Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, PAnsiChar(@Buffer), Count);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_384 计算
function SHA3_384Buffer(const Buffer; Count: Cardinal): TCnSHA3_384Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, PAnsiChar(@Buffer), Count);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHA3_512 计算
function SHA3_512Buffer(const Buffer; Count: Cardinal): TCnSHA3_512Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, PAnsiChar(@Buffer), Count);
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

// 对数据块进行 SHAKE128 计算
function SHAKE128Buffer(const Buffer; Count: Cardinal; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE128Init(Context, DigestByteLength);
  SHAKE128Update(Context, PAnsiChar(@Buffer), Count);
  SHAKE128Final(Context, Result);
end;

// 对数据块进行 SHAKE256 计算
function SHAKE256Buffer(const Buffer; Count: Cardinal; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE256Init(Context, DigestByteLength);
  SHAKE256Update(Context, PAnsiChar(@Buffer), Count);
  SHAKE256Final(Context, Result);
end;

// 对字节数组进行 SHA3_224 计算
function SHA3_224Bytes(const Data: TBytes): TCnSHA3_224Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

// 对字节数组进行 SHA3_256 计算
function SHA3_256Bytes(const Data: TBytes): TCnSHA3_256Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

// 对字节数组进行 SHA3_384 计算
function SHA3_384Bytes(const Data: TBytes): TCnSHA3_384Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

// 对字节数组进行 SHA3_512 计算
function SHA3_512Bytes(const Data: TBytes): TCnSHA3_512Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

// 对字节数组进行 SHAKE128 计算
function SHAKE128Bytes(const Data: TBytes; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE128Init(Context, DigestByteLength);
  SHAKE128Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHAKE128Final(Context, Result);
end;

// 对字节数组进行 SHAKE256 计算
function SHAKE256Bytes(const Data: TBytes; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE256Init(Context, DigestByteLength);
  SHAKE256Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHAKE256Final(Context, Result);
end;

// 对 String 类型数据进行 SHA3_224 计算
function SHA3_224String(const Str: string): TCnSHA3_224Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA3_224StringA(AStr);
end;

// 对 String 类型数据进行 SHA3_256 计算
function SHA3_256String(const Str: string): TCnSHA3_256Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA3_256StringA(AStr);
end;

// 对 String 类型数据进行 SHA3_384 计算
function SHA3_384String(const Str: string): TCnSHA3_384Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA3_384StringA(AStr);
end;

// 对 String 类型数据进行 SHA3_512 计算
function SHA3_512String(const Str: string): TCnSHA3_512Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA3_512StringA(AStr);
end;

// 对 String 类型数据进行 SHAKE128 计算
function SHAKE128String(const Str: string; DigestByteLength: Cardinal): TBytes;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHAKE128StringA(AStr, DigestByteLength);
end;

// 对 String 类型数据进行 SHAKE256 计算
function SHAKE256String(const Str: string; DigestByteLength: Cardinal): TBytes;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHAKE256StringA(AStr, DigestByteLength);
end;

// 对 UnicodeString 类型数据进行直接的 SHA3_224 计算，不进行转换
{$IFDEF UNICODE}
function SHA3_224UnicodeString(const Str: string): TCnSHA3_224Digest;
{$ELSE}
function SHA3_224UnicodeString(const Str: WideString): TCnSHA3_224Digest;
{$ENDIF}
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

// 对 UnicodeString 类型数据进行直接的 SHA3_256 计算，不进行转换
{$IFDEF UNICODE}
function SHA3_256UnicodeString(const Str: string): TCnSHA3_256Digest;
{$ELSE}
function SHA3_256UnicodeString(const Str: WideString): TCnSHA3_256Digest;
{$ENDIF}
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

// 对 UnicodeString 类型数据进行直接的 SHA3_384 计算，不进行转换
{$IFDEF UNICODE}
function SHA3_384UnicodeString(const Str: string): TCnSHA3_384Digest;
{$ELSE}
function SHA3_384UnicodeString(const Str: WideString): TCnSHA3_384Digest;
{$ENDIF}
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

// 对 UnicodeString 类型数据进行直接的 SHA3_512 计算，不进行转换
{$IFDEF UNICODE}
function SHA3_512UnicodeString(const Str: string): TCnSHA3_512Digest;
{$ELSE}
function SHA3_512UnicodeString(const Str: WideString): TCnSHA3_512Digest;
{$ENDIF}
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

// 对 UnicodeString 类型数据进行直接的 SHAKE128 计算，不进行转换
{$IFDEF UNICODE}
function SHAKE128UnicodeString(const Str: string; DigestByteLength: Cardinal): TBytes;
{$ELSE}
function SHAKE128UnicodeString(const Str: WideString; DigestByteLength: Cardinal): TBytes;
{$ENDIF}
var
  Context: TCnSHA3Context;
begin
  SHAKE128Init(Context, DigestByteLength);
  SHAKE128Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHAKE128Final(Context, Result);
end;

// 对 UnicodeString 类型数据进行直接的 SHAKE256 计算，不进行转换
{$IFDEF UNICODE}
function SHAKE256UnicodeString(const Str: string; DigestByteLength: Cardinal): TBytes;
{$ELSE}
function SHAKE256UnicodeString(const Str: WideString; DigestByteLength: Cardinal): TBytes;
{$ENDIF}
var
  Context: TCnSHA3Context;
begin
  SHAKE256Init(Context, DigestByteLength);
  SHAKE256Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHAKE256Final(Context, Result);
end;

// 对 AnsiString 类型数据进行SHA224 计算
function SHA3_224StringA(const Str: AnsiString): TCnSHA3_224Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, PAnsiChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

// 对 WideString 类型数据进行 SHA3_224 计算
function SHA3_224StringW(const Str: WideString): TCnSHA3_224Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_224);
  SHA3UpdateW(Context, PWideChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_224_OUTPUT_LENGTH_BYTE);
end;

// 对 AnsiString 类型数据进行 SHA3_256 计算
function SHA3_256StringA(const Str: AnsiString): TCnSHA3_256Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, PAnsiChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

// 对 WideString 类型数据进行 SHA3_256 计算
function SHA3_256StringW(const Str: WideString): TCnSHA3_256Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_256);
  SHA3UpdateW(Context, PWideChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_256_OUTPUT_LENGTH_BYTE);
end;

// 对 AnsiString 类型数据进行 SHA3_384 计算
function SHA3_384StringA(const Str: AnsiString): TCnSHA3_384Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, PAnsiChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

// 对 WideString 类型数据进行 SHA3_384 计算
function SHA3_384StringW(const Str: WideString): TCnSHA3_384Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_384);
  SHA3UpdateW(Context, PWideChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_384_OUTPUT_LENGTH_BYTE);
end;

// 对 AnsiString 类型数据进行 SHA3_512 计算
function SHA3_512StringA(const Str: AnsiString): TCnSHA3_512Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, PAnsiChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

// 对 WideString 类型数据进行 SHA3_512 计算
function SHA3_512StringW(const Str: WideString): TCnSHA3_512Digest;
var
  Context: TCnSHA3Context;
  Res: TCnSHA3GeneralDigest;
begin
  SHA3Init(Context, stSHA3_512);
  SHA3UpdateW(Context, PWideChar(Str), Length(Str));
  SHA3Final(Context, Res);
  Move(Res[0], Result[0], SHA3_512_OUTPUT_LENGTH_BYTE);
end;

// 对 AnsiString 类型数据进行 SHAKE128 计算
function SHAKE128StringA(const Str: AnsiString; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE128Init(Context, DigestByteLength);
  SHAKE128Update(Context, PAnsiChar(Str), Length(Str));
  SHAKE128Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHAKE128 计算
function SHAKE128StringW(const Str: WideString; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE128Init(Context, DigestByteLength);
  SHA3UpdateW(Context, PWideChar(Str), Length(Str)); // SHAKE128UpdateW = SHA3UpdateW
  SHAKE128Final(Context, Result);
end;

// 对 AnsiString 类型数据进行 SHAKE256 计算
function SHAKE256StringA(const Str: AnsiString; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE256Init(Context, DigestByteLength);
  SHAKE256Update(Context, PAnsiChar(Str), Length(Str));
  SHAKE256Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHAKE256 计算
function SHAKE256StringW(const Str: WideString; DigestByteLength: Cardinal): TBytes;
var
  Context: TCnSHA3Context;
begin
  SHAKE256Init(Context, DigestByteLength);
  SHA3UpdateW(Context, PWideChar(Str), Length(Str)); // SHAKE256UpdateW = SHA3UpdateW
  SHAKE256Final(Context, Result);
end;

// SHA3Type 只能是 stSHA3_224, stSHA3_256, stSHA3_384, stSHA3_512
function InternalSHA3Stream(Stream: TStream; const BufSize: Cardinal; var D:
  TCnSHA3GeneralDigest; SHA3Type: TSHA3Type; CallBack: TCnSHA3CalcProgressFunc): Boolean; overload;
var
  Buf: PAnsiChar;
  BufLen: Cardinal;
  Size: Int64;
  ReadBytes: Cardinal;
  TotalBytes: Int64;
  SavePos: Int64;
  CancelCalc: Boolean;
  Context: TCnSHA3Context;
begin
  Result := False;
  Size := Stream.Size;
  SavePos := Stream.Position;
  TotalBytes := 0;
  if Size = 0 then
    Exit;
  if Size < BufSize then
    BufLen := Size
  else
    BufLen := BufSize;

  CancelCalc := False;
  SHA3Init(Context, SHA3Type);

  GetMem(Buf, BufLen);
  try
    Stream.Position := 0;
    repeat
      ReadBytes := Stream.Read(Buf^, BufLen);
      if ReadBytes <> 0 then
      begin
        Inc(TotalBytes, ReadBytes);
        SHA3Update(Context, Buf, ReadBytes);

        if Assigned(CallBack) then
        begin
          CallBack(Size, TotalBytes, CancelCalc);
          if CancelCalc then
            Exit;
        end;
      end;
    until (ReadBytes = 0) or (TotalBytes = Size);
    SHA3Final(Context, D);
    Result := True;
  finally
    FreeMem(Buf, BufLen);
    Stream.Position := SavePos;
  end;
end;

// SHA3Type 只能是 stSHAKE128 或 stSHAKE256
function InternalSHA3Stream(Stream: TStream; const BufSize: Cardinal;
  SHA3Type: TSHA3Type; DigestByteLength: Cardinal; out D: TBytes;
  CallBack: TCnSHA3CalcProgressFunc): Boolean; overload;
var
  Buf: PAnsiChar;
  BufLen: Cardinal;
  Size: Int64;
  ReadBytes: Cardinal;
  TotalBytes: Int64;
  SavePos: Int64;
  CancelCalc: Boolean;
  Context: TCnSHA3Context;
begin
  Result := False;
  Size := Stream.Size;
  SavePos := Stream.Position;
  TotalBytes := 0;
  if Size = 0 then
    Exit;
  if Size < BufSize then
    BufLen := Size
  else
    BufLen := BufSize;

  CancelCalc := False;
  SHA3Init(Context, SHA3Type, DigestByteLength);

  GetMem(Buf, BufLen);
  try
    Stream.Position := 0;
    repeat
      ReadBytes := Stream.Read(Buf^, BufLen);
      if ReadBytes <> 0 then
      begin
        Inc(TotalBytes, ReadBytes);
        SHA3Update(Context, Buf, ReadBytes);

        if Assigned(CallBack) then
        begin
          CallBack(Size, TotalBytes, CancelCalc);
          if CancelCalc then
            Exit;
        end;
      end;
    until (ReadBytes = 0) or (TotalBytes = Size);
    SHA3Final(Context, D);
    Result := True;
  finally
    FreeMem(Buf, BufLen);
    Stream.Position := SavePos;
  end;
end;

// 对指定流进行 SHA3_224 计算
function SHA3_224Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_224Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  InternalSHA3Stream(Stream, STREAM_BUF_SIZE, Dig, stSHA3_224, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_224Digest));
end;

// 对指定流进行 SHA3_256 计算
function SHA3_256Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_256Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  InternalSHA3Stream(Stream, STREAM_BUF_SIZE, Dig, stSHA3_256, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_256Digest));
end;

// 对指定流进行 SHA3_384 计算
function SHA3_384Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_384Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  InternalSHA3Stream(Stream, STREAM_BUF_SIZE, Dig, stSHA3_384, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_384Digest));
end;

// 对指定流进行 SHA3_512 计算
function SHA3_512Stream(Stream: TStream; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_512Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  InternalSHA3Stream(Stream, STREAM_BUF_SIZE, Dig, stSHA3_512, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_512Digest));
end;

// 对指定数据流进行杂凑长度可变的 SHAKE128 计算
function SHAKE128Stream(Stream: TStream; DigestByteLength: Cardinal;
  CallBack: TCnSHA3CalcProgressFunc): TBytes;
begin
  InternalSHA3Stream(Stream, STREAM_BUF_SIZE, stSHAKE128, DigestByteLength, Result, CallBack);
end;

// 对指定数据流进行杂凑长度可变的 SHAKE256 计算
function SHAKE256Stream(Stream: TStream; DigestByteLength: Cardinal;
  CallBack: TCnSHA3CalcProgressFunc): TBytes;
begin
  InternalSHA3Stream(Stream, STREAM_BUF_SIZE, stSHAKE256, DigestByteLength, Result, CallBack);
end;

function FileSizeIsLargeThanMaxOrCanNotMap(const AFileName: string; out IsEmpty: Boolean): Boolean;
{$IFDEF MSWINDOWS}
var
  H: THandle;
  Info: BY_HANDLE_FILE_INFORMATION;
  Rec: Int64Rec;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  Result := False;
  IsEmpty := False;
  H := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ, nil,
    OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    if not GetFileInformationByHandle(H, Info) then
      Exit;
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

function InternalSHA3File(const FileName: string; SHA3Type: TSHA3Type;
  CallBack: TCnSHA3CalcProgressFunc): TCnSHA3GeneralDigest; overload;
var
{$IFDEF MSWINDOWS}
  Context: TCnSHA3Context;
  FileHandle: THandle;
  MapHandle: THandle;
  ViewPointer: Pointer;
{$ENDIF}
  Stream: TStream;
  FileIsZeroSize: Boolean;
begin
  FileIsZeroSize := False;
  if FileSizeIsLargeThanMaxOrCanNotMap(FileName, FileIsZeroSize) then
  begin
    // 大于 2G 的文件可能 Map 失败，采用流方式循环处理
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      InternalSHA3Stream(Stream, STREAM_BUF_SIZE, Result, SHA3Type, CallBack);
    finally
      Stream.Free;
    end;
  end
  else
  begin
{$IFDEF MSWINDOWS}
    SHA3Init(Context, SHA3Type);
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
                SHA3Update(Context, ViewPointer, GetFileSize(FileHandle, nil));
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
    SHA3Final(Context, Result);
{$ENDIF}
  end;
end;

function InternalSHA3File(const FileName: string; SHA3Type: TSHA3Type;
  DigestByteLength: Cardinal; CallBack: TCnSHA3CalcProgressFunc): TBytes; overload;
var
{$IFDEF MSWINDOWS}
  Context: TCnSHA3Context;
  FileHandle: THandle;
  MapHandle: THandle;
  ViewPointer: Pointer;
{$ENDIF}
  Stream: TStream;
  FileIsZeroSize: Boolean;
begin
  FileIsZeroSize := False;
  if FileSizeIsLargeThanMaxOrCanNotMap(FileName, FileIsZeroSize) then
  begin
    // 大于 2G 的文件可能 Map 失败，采用流方式循环处理
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      InternalSHA3Stream(Stream, STREAM_BUF_SIZE, SHA3Type, DigestByteLength, Result, CallBack);
    finally
      Stream.Free;
    end;
  end
  else
  begin
{$IFDEF MSWINDOWS}
    SHA3Init(Context, SHA3Type, DigestByteLength);
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
                SHA3Update(Context, ViewPointer, GetFileSize(FileHandle, nil));
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
    SHA3Final(Context, Result);
{$ENDIF}
  end;
end;

// 对指定文件内容进行 SHA3_224 计算
function SHA3_224File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_224Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  Dig := InternalSHA3File(FileName, stSHA3_224, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_224Digest));
end;

// 对指定文件内容进行 SHA3_256 计算
function SHA3_256File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_256Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  Dig := InternalSHA3File(FileName, stSHA3_256, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_256Digest));
end;

// 对指定文件内容进行 SHA3_384 计算
function SHA3_384File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_384Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  Dig := InternalSHA3File(FileName, stSHA3_384, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_384Digest));
end;

// 对指定文件内容进行 SHA3_512 计算
function SHA3_512File(const FileName: string; CallBack: TCnSHA3CalcProgressFunc):
  TCnSHA3_512Digest;
var
  Dig: TCnSHA3GeneralDigest;
begin
  Dig := InternalSHA3File(FileName, stSHA3_512, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA3_512Digest));
end;

// 对指定文件内容进行杂凑长度可变的 SHAKE128 计算
function SHAKE128File(const FileName: string; DigestByteLength: Cardinal;
  CallBack: TCnSHA3CalcProgressFunc): TBytes;
begin
  Result := InternalSHA3File(FileName, stSHAKE128, DigestByteLength, CallBack);
end;

// 对指定文件内容进行杂凑长度可变的 SHAKE256 计算
function SHAKE256File(const FileName: string; DigestByteLength: Cardinal;
  CallBack: TCnSHA3CalcProgressFunc): TBytes;
begin
  Result := InternalSHA3File(FileName, stSHAKE256, DigestByteLength, CallBack);
end;

// 以十六进制格式输出 SHA3_224 杂凑值
function SHA3_224Print(const Digest: TCnSHA3_224Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA3_224Digest));
end;

// 以十六进制格式输出 SHA3_256 杂凑值
function SHA3_256Print(const Digest: TCnSHA3_256Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA3_256Digest));
end;

// 以十六进制格式输出 SHA3_384 杂凑值
function SHA3_384Print(const Digest: TCnSHA3_384Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA3_384Digest));
end;

// 以十六进制格式输出 SHA3_512 杂凑值
function SHA3_512Print(const Digest: TCnSHA3_512Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA3_512Digest));
end;

// 以十六进制格式输出 SHAKE128 杂凑值
function SHAKE128Print(const Digest: TBytes): string;
begin
  Result := BytesToHex(Digest);
end;

// 以十六进制格式输出 SHAKE256 杂凑值
function SHAKE256Print(const Digest: TBytes): string;
begin
  Result := BytesToHex(Digest);
end;

// 比较两个 SHA3_224 杂凑值是否相等
function SHA3_224Match(const D1, D2: TCnSHA3_224Digest): Boolean;
begin
  Result := ConstTimeCompareMem(@D1[0], @D2[0], SizeOf(TCnSHA3_224Digest));
end;

// 比较两个 SHA3_256 杂凑值是否相等
function SHA3_256Match(const D1, D2: TCnSHA3_256Digest): Boolean;
begin
  Result := ConstTimeCompareMem(@D1[0], @D2[0], SizeOf(TCnSHA3_256Digest));
end;

// 比较两个 SHA3_384 杂凑值是否相等
function SHA3_384Match(const D1, D2: TCnSHA3_384Digest): Boolean;
begin
  Result := ConstTimeCompareMem(@D1[0], @D2[0], SizeOf(TCnSHA3_384Digest));
end;

// 比较两个 SHA3_512 杂凑值是否相等
function SHA3_512Match(const D1, D2: TCnSHA3_512Digest): Boolean;
begin
  Result := ConstTimeCompareMem(@D1[0], @D2[0], SizeOf(TCnSHA3_512Digest));
end;

// 比较两个 SHAKE128 杂凑值是否相等
function SHAKE128Match(const D1, D2: TBytes): Boolean;
begin
  Result := ConstTimeCompareBytes(D1, D2);
end;

// 比较两个 SHAKE256 杂凑值是否相等
function SHAKE256Match(const D1, D2: TBytes): Boolean;
begin
  Result := ConstTimeCompareBytes(D1, D2);
end;

// SHA3_224 杂凑值转 string
function SHA3_224DigestToStr(const Digest: TCnSHA3_224Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA3_224Digest));
end;

// SHA3_256 杂凑值转 string
function SHA3_256DigestToStr(const Digest: TCnSHA3_256Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA3_256Digest));;
end;

// SHA3_384 杂凑值转 string
function SHA3_384DigestToStr(const Digest: TCnSHA3_384Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA3_384Digest));
end;

// SHA3_512 杂凑值转 string
function SHA3_512DigestToStr(const Digest: TCnSHA3_512Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA3_512Digest));
end;

// SHAKE128 杂凑值转 string
function SHAKE128DigestToStr(const Digest: TBytes): string;
begin
  Result := BytesToString(Digest);
end;

// SHAKE256 杂凑值转 string
function SHAKE256DigestToStr(const Digest: TBytes): string;
begin
  Result := BytesToString(Digest);
end;

procedure SHA3_224HmacInit(var Context: TCnSHA3Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA3_224Digest;
begin
  if KeyLength > HMAC_SHA3_224_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA3_224Buffer(Key^, KeyLength);
    KeyLength := HMAC_SHA3_224_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA3_224_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA3_224_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, @(Context.Ipad[0]), HMAC_SHA3_224_BLOCK_SIZE_BYTE);
end;

procedure SHA3_256HmacInit(var Context: TCnSHA3Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA3_256Digest;
begin
  if KeyLength > HMAC_SHA3_256_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA3_256Buffer(Key^, KeyLength);
    KeyLength := HMAC_SHA3_256_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA3_256_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA3_256_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, @(Context.Ipad[0]), HMAC_SHA3_256_BLOCK_SIZE_BYTE);
end;

procedure SHA3_384HmacInit(var Context: TCnSHA3Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA3_384Digest;
begin
  if KeyLength > HMAC_SHA3_384_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA3_384Buffer(Key^, KeyLength);
    KeyLength := HMAC_SHA3_384_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA3_384_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA3_384_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, @(Context.Ipad[0]), HMAC_SHA3_384_BLOCK_SIZE_BYTE);
end;

procedure SHA3_512HmacInit(var Context: TCnSHA3Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA3_512Digest;
begin
  if KeyLength > HMAC_SHA3_512_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA3_512Buffer(Key^, KeyLength);
    KeyLength := HMAC_SHA3_512_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA3_512_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA3_512_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, @(Context.Ipad[0]), HMAC_SHA3_512_BLOCK_SIZE_BYTE);
end;

procedure SHA3_224HmacUpdate(var Context: TCnSHA3Context; Input: PAnsiChar;
  ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_256HmacUpdate(var Context: TCnSHA3Context; Input: PAnsiChar;
  ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_384HmacUpdate(var Context: TCnSHA3Context; Input: PAnsiChar;
  ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_512HmacUpdate(var Context: TCnSHA3Context; Input: PAnsiChar;
  ByteLength: Cardinal);
begin
  SHA3Update(Context, Input, ByteLength);
end;

procedure SHA3_224HmacFinal(var Context: TCnSHA3Context; var Output: TCnSHA3GeneralDigest);
var
  Len: Integer;
  TmpBuf: TCnSHA3GeneralDigest;
begin
  Len := HMAC_SHA3_224_OUTPUT_LENGTH_BYTE;
  SHA3Final(Context, TmpBuf);
  SHA3Init(Context, stSHA3_224);
  SHA3Update(Context, @(Context.Opad[0]), HMAC_SHA3_224_BLOCK_SIZE_BYTE);
  SHA3Update(Context, @(TmpBuf[0]), Len);
  SHA3Final(Context, Output);
end;

procedure SHA3_256HmacFinal(var Context: TCnSHA3Context; var Output: TCnSHA3GeneralDigest);
var
  Len: Integer;
  TmpBuf: TCnSHA3GeneralDigest;
begin
  Len := HMAC_SHA3_256_OUTPUT_LENGTH_BYTE;
  SHA3Final(Context, TmpBuf);
  SHA3Init(Context, stSHA3_256);
  SHA3Update(Context, @(Context.Opad[0]), HMAC_SHA3_256_BLOCK_SIZE_BYTE);
  SHA3Update(Context, @(TmpBuf[0]), Len);
  SHA3Final(Context, Output);
end;

procedure SHA3_384HmacFinal(var Context: TCnSHA3Context; var Output: TCnSHA3GeneralDigest);
var
  Len: Integer;
  TmpBuf: TCnSHA3GeneralDigest;
begin
  Len := HMAC_SHA3_384_OUTPUT_LENGTH_BYTE;
  SHA3Final(Context, TmpBuf);
  SHA3Init(Context, stSHA3_384);
  SHA3Update(Context, @(Context.Opad[0]), HMAC_SHA3_384_BLOCK_SIZE_BYTE);
  SHA3Update(Context, @(TmpBuf[0]), Len);
  SHA3Final(Context, Output);
end;

procedure SHA3_512HmacFinal(var Context: TCnSHA3Context; var Output: TCnSHA3GeneralDigest);
var
  Len: Integer;
  TmpBuf: TCnSHA3GeneralDigest;
begin
  Len := HMAC_SHA3_512_OUTPUT_LENGTH_BYTE;
  SHA3Final(Context, TmpBuf);
  SHA3Init(Context, stSHA3_512);
  SHA3Update(Context, @(Context.Opad[0]), HMAC_SHA3_512_BLOCK_SIZE_BYTE);
  SHA3Update(Context, @(TmpBuf[0]), Len);
  SHA3Final(Context, Output);
end;

procedure SHA3_224Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_224Digest);
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_224HmacInit(Context, Key, KeyByteLength);
  SHA3_224HmacUpdate(Context, Input, ByteLength);
  SHA3_224HmacFinal(Context, Dig);
  Move(Dig[0], Output[0], Context.DigestLen);
end;

procedure SHA3_256Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_256Digest);
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_256HmacInit(Context, Key, KeyByteLength);
  SHA3_256HmacUpdate(Context, Input, ByteLength);
  SHA3_256HmacFinal(Context, Dig);
  Move(Dig[0], Output[0], Context.DigestLen);
end;

procedure SHA3_384Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_384Digest);
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_384HmacInit(Context, Key, KeyByteLength);
  SHA3_384HmacUpdate(Context, Input, ByteLength);
  SHA3_384HmacFinal(Context, Dig);
  Move(Dig[0], Output[0], Context.DigestLen);
end;

procedure SHA3_512Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA3_512Digest);
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_512HmacInit(Context, Key, KeyByteLength);
  SHA3_512HmacUpdate(Context, Input, ByteLength);
  SHA3_512HmacFinal(Context, Dig);
  Move(Dig[0], Output[0], Context.DigestLen);
end;

function SHA3_224HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_224Digest;
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_224HmacInit(Context, PAnsiChar(@Key[0]), Length(Key));
  SHA3_224HmacUpdate(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3_224HmacFinal(Context, Dig);
  Move(Dig[0], Result[0], Context.DigestLen);
end;

function SHA3_256HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_256Digest;
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_256HmacInit(Context, PAnsiChar(@Key[0]), Length(Key));
  SHA3_256HmacUpdate(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3_256HmacFinal(Context, Dig);
  Move(Dig[0], Result[0], Context.DigestLen);
end;

function SHA3_384HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_384Digest;
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_384HmacInit(Context, PAnsiChar(@Key[0]), Length(Key));
  SHA3_384HmacUpdate(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3_384HmacFinal(Context, Dig);
  Move(Dig[0], Result[0], Context.DigestLen);
end;

function SHA3_512HmacBytes(const Key: TBytes; const Data: TBytes): TCnSHA3_512Digest;
var
  Context: TCnSHA3Context;
  Dig: TCnSHA3GeneralDigest;
begin
  SHA3_512HmacInit(Context, PAnsiChar(@Key[0]), Length(Key));
  SHA3_512HmacUpdate(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA3_512HmacFinal(Context, Dig);
  Move(Dig[0], Result[0], Context.DigestLen);
end;

end.
