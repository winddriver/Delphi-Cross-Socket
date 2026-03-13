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

unit CnSHA2;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：SHA2 杂凑算法实现单元
* 单元作者：CnPack 开发组 (master@cnpack.org)
*           从匿名/佚名 C 代码与 Pascal 代码混合移植而来并补充部分功能。
* 备    注：本单元实现了 SHA2 系列杂凑算法及对应的 HMAC 算法，包括 SHA224/256/384/512。
*           注：Delphi 5/6/7 本单元用了有符号 Int64 代替无符号 UInt64 来计算 SHA512/384，
*           原因是基于补码规则，有无符号数的加减移位以及溢出的舍弃机制等都相同，唯一不
*           同的是比较，而本单元中没有类似的比较。
* 开发平台：PWinXP + Delphi 5.0
* 兼容测试：PWinXP/7 + Delphi 5/6
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2022.04.26 V1.4
*               修改 LongWord 与 Integer 地址转换以支持 MacOS64
*           2019.04.15 V1.3
*               支持 Win32/Win64/MacOS32
*           2017.10.31 V1.2
*               修正 SHA512/384 HMAC 计算错误的问题
*           2016.09.30 V1.1
*               实现 SHA512/384。D567下用有符号 Int64 代替无符号 UInt64
*           2016.09.27 V1.0
*               创建单元。
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes {$IFDEF MSWINDOWS}, Windows {$ENDIF}, CnNative, CnConsts;

type
  PCnSHAGeneralDigest = ^TCnSHAGeneralDigest;
  TCnSHAGeneralDigest = array[0..63] of Byte;

  PCnSHA224Digest = ^TCnSHA224Digest;
  TCnSHA224Digest = array[0..27] of Byte;
  {* SHA224 杂凑结果，28 字节}

  PCnSHA256Digest = ^TCnSHA256Digest;
  TCnSHA256Digest = array[0..31] of Byte;
  {* SHA256 杂凑结果，32 字节}

  PCnSHA384Digest = ^TCnSHA384Digest;
  TCnSHA384Digest = array[0..47] of Byte;
  {* SHA384 杂凑结果，48 字节}

  PCnSHA512Digest = ^TCnSHA512Digest;
  TCnSHA512Digest = array[0..63] of Byte;
  {* SHA512 杂凑结果，64 字节}

  TCnSHA256Context = packed record
  {* SHA256 的上下文结构}
    DataLen: Cardinal;
    Data: array[0..63] of Byte;
    BitLen: Int64;
    State: array[0..7] of Cardinal;
    Ipad: array[0..63] of Byte;      {!< HMAC: inner padding        }
    Opad: array[0..63] of Byte;      {!< HMAC: outer padding        }
  end;

  TCnSHA224Context = TCnSHA256Context;
  {* SHA224 的上下文结构}

  TCnSHA512Context = packed record
  {* SHA512 的上下文结构}
    DataLen: Cardinal;
    Data: array[0..127] of Byte;
    TotalLen: Int64;
    State: array[0..7] of Int64;
    Ipad: array[0..127] of Byte;      {!< HMAC: inner padding        }
    Opad: array[0..127] of Byte;      {!< HMAC: outer padding        }
  end;

  TCnSHA384Context = TCnSHA512Context;
  {* SHA512 的上下文结构}

  TCnSHACalcProgressFunc = procedure(ATotal, AProgress: Int64; var Cancel:
    Boolean) of object;
  {* 各类 SHA2 系列杂凑进度回调事件类型声明}

function SHA224(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA224Digest;
{* 对数据块进行 SHA224 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA256Digest;
{* 对数据块进行 SHA256 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA384Digest;
{* 对数据块进行 SHA384 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA512Digest;
{* 对数据块进行 SHA512 计算。

   参数：
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

function SHA224Buffer(const Buffer; Count: Cardinal): TCnSHA224Digest;
{* 对数据块进行 SHA224 计算。

   参数：
     const Buffer                         - 待计算的数据块地址
     Count: Cardinal                      - 待计算的数据块字节长度

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256Buffer(const Buffer; Count: Cardinal): TCnSHA256Digest;
{* 对数据块进行 SHA256 计算。

   参数：
     const Buffer                         - 待计算的数据块地址
     Count: Cardinal                      -

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384Buffer(const Buffer; Count: Cardinal): TCnSHA384Digest;
{* 对数据块进行 SHA384 计算。

   参数：
     const Buffer                         - 待计算的数据块地址
     Count: Cardinal                      -

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512Buffer(const Buffer; Count: Cardinal): TCnSHA512Digest;
{* 对数据块进行 SHA512 计算。

   参数：
     const Buffer                         - 待计算的数据块地址
     Count: Cardinal                      -

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

function SHA224Bytes(Data: TBytes): TCnSHA224Digest;
{* 对字节数组进行 SHA224 计算。

   参数：
     Data: TBytes                         - 待计算的字节数组

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256Bytes(Data: TBytes): TCnSHA256Digest;
{* 对字节数组进行 SHA256 计算。

   参数：
     Data: TBytes                         - 待计算的字节数组

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384Bytes(Data: TBytes): TCnSHA384Digest;
{* 对字节数组进行 SHA384 计算。
   参数：
     Data: TBytes                         - 待计算的字节数组

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512Bytes(Data: TBytes): TCnSHA512Digest;
{* 对字节数组进行 SHA512 计算。

   参数：
     Data: TBytes                         - 待计算的字节数组

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

function SHA224String(const Str: string): TCnSHA224Digest;
{* 对 String 类型数据进行 SHA224 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256String(const Str: string): TCnSHA256Digest;
{* 对 String 类型数据进行 SHA256 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384String(const Str: string): TCnSHA384Digest;
{* 对 String 类型数据进行 SHA384 计算，注意 D2009或以上版本的string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512String(const Str: string): TCnSHA512Digest;
{* 对 String 类型数据进行 SHA512 计算，注意 D2009 或以上版本的 string 为 UnicodeString，
   代码中会将其强行转换成 AnsiString 进行计算。

   参数：
     const Str: string                    - 待计算的字符串

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}


function SHA224StringA(const Str: AnsiString): TCnSHA224Digest;
{* 对 AnsiString 类型数据进行 SHA224 计算。

   参数：
     const Str: AnsiString                -

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA224StringW(const Str: WideString): TCnSHA224Digest;
{* 对 WideString 类型数据进行 SHA224 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256StringA(const Str: AnsiString): TCnSHA256Digest;
{* 对 AnsiString 类型数据进行 SHA256 计算。

   参数：
     const Str: AnsiString                -

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA256StringW(const Str: WideString): TCnSHA256Digest;
{* 对 WideString 类型数据进行 SHA256 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384StringA(const Str: AnsiString): TCnSHA384Digest;
{* 对 AnsiString 类型数据进行 SHA384 计算。

   参数：
     const Str: AnsiString                -

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA384StringW(const Str: WideString): TCnSHA384Digest;
{* 对 WideString 类型数据进行 SHA384 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512StringA(const Str: AnsiString): TCnSHA512Digest;
{* 对 AnsiString 类型数据进行 SHA512 计算。

   参数：
     const Str: AnsiString                -

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

function SHA512StringW(const Str: WideString): TCnSHA512Digest;
{* 对 WideString 类型数据进行 SHA512 计算。
   计算前 Windows 下会调用 WideCharToMultyByte 转换为 AnsiString 类型，
   其他平台会直接转换为 AnsiString 类型，再进行计算。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

{$IFDEF UNICODE}

function SHA224UnicodeString(const Str: string): TCnSHA224Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA224 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256UnicodeString(const Str: string): TCnSHA256Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA256 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384UnicodeString(const Str: string): TCnSHA384Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA384 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512UnicodeString(const Str: string): TCnSHA512Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA512 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: string                    - 待计算的宽字符串

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

{$ELSE}

function SHA224UnicodeString(const Str: WideString): TCnSHA224Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA224 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256UnicodeString(const Str: WideString): TCnSHA256Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA256 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384UnicodeString(const Str: WideString): TCnSHA384Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA384 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512UnicodeString(const Str: WideString): TCnSHA512Digest;
{* 对 UnicodeString 类型数据进行直接的 SHA512 计算，直接计算内部 UTF16 内容，不进行转换。

   参数：
     const Str: WideString                - 待计算的宽字符串

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

{$ENDIF}

function SHA224File(const FileName: string; CallBack: TCnSHACalcProgressFunc =
  nil): TCnSHA224Digest;
{* 对指定文件内容进行 SHA256 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA224Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA224Digest;
{* 对指定流数据进行 SHA224 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA224Digest                - 返回的 SHA224 杂凑值
}

function SHA256File(const FileName: string; CallBack: TCnSHACalcProgressFunc =
  nil): TCnSHA256Digest;
{* 对指定文件内容进行 SHA256 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA256Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA256Digest;
{* 对指定流数据进行 SHA256 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA256Digest                - 返回的 SHA256 杂凑值
}

function SHA384File(const FileName: string; CallBack: TCnSHACalcProgressFunc =
  nil): TCnSHA384Digest;
{* 对指定文件内容进行 SHA384 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA384Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA384Digest;
{* 对指定流数据进行 SHA384 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA384Digest                - 返回的 SHA384杂凑值
}

function SHA512File(const FileName: string; CallBack: TCnSHACalcProgressFunc =
  nil): TCnSHA512Digest;
{* 对指定文件内容进行 SHA512 计算。

   参数：
     const FileName: string               - 待计算的文件名
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

function SHA512Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA512Digest;
{* 对指定流数据进行 SHA512 计算。

   参数：
     Stream: TStream                      - 待计算的流内容
     CallBack: TCnSHACalcProgressFunc     - 进度回调函数，默认为空

   返回值：TCnSHA512Digest                - 返回的 SHA512 杂凑值
}

// 以下三个函数用于外部持续对数据进行零散的 SHA224 计算，SHA224Update 可多次被调用

procedure SHA224Init(var Context: TCnSHA224Context);
{* 初始化一轮 SHA224 计算上下文，准备计算 SHA224 结果。

   参数：
     var Context: TCnSHA224Context        - 待初始化的 SHA224 上下文

   返回值：（无）
}

procedure SHA224Update(var Context: TCnSHA224Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA224 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA224Context        - SHA224 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA224Final(var Context: TCnSHA224Context; var Digest: TCnSHA224Digest);
{* 结束本轮计算，将 SHA224 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA224Context        - SHA224 上下文
     var Digest: TCnSHA224Digest          - 返回的 SHA224 杂凑值

   返回值：（无）
}

// 以下三个函数用于外部持续对数据进行零散的 SHA256 计算，SHA256Update 可多次被调用

procedure SHA256Init(var Context: TCnSHA256Context);
{* 初始化一轮 SHA256 计算上下文，准备计算 SHA256 结果。

   参数：
     var Context: TCnSHA256Context        - 待初始化的 SHA256 上下文

   返回值：（无）
}

procedure SHA256Update(var Context: TCnSHA256Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA256 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA256Context        - SHA256 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA256Final(var Context: TCnSHA256Context; var Digest: TCnSHA256Digest);
{* 结束本轮计算，将 SHA256 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA256Context        - SHA256 上下文
     var Digest: TCnSHA256Digest          - 返回的 SHA256 杂凑值

   返回值：（无）
}

// 以下三个函数用于外部持续对数据进行零散的 SHA384 计算，SHA384Update 可多次被调用

procedure SHA384Init(var Context: TCnSHA384Context);
{* 初始化一轮 SHA384 计算上下文，准备计算 SHA384 结果。

   参数：
     var Context: TCnSHA384Context        - 待初始化的 SHA384 上下文

   返回值：（无）
}

procedure SHA384Update(var Context: TCnSHA384Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA384 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA384Context        - SHA384 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA384Final(var Context: TCnSHA384Context; var Digest: TCnSHA384Digest);
{* 结束本轮计算，将 SHA384 结果返回至 Digest 中。

   参数：
     var Context: TCnSHA384Context        - SHA384 上下文
     var Digest: TCnSHA384Digest          - 返回的 SHA384 杂凑值

   返回值：（无）
}

// 以下三个函数用于外部持续对数据进行零散的 SHA512 计算，SHA512Update 可多次被调用

procedure SHA512Init(var Context: TCnSHA512Context);
{* 初始化一轮 SHA512 计算上下文，准备计算 SHA512 结果。

   参数：
     var Context: TCnSHA512Context        - 待初始化的 SHA512 上下文

   返回值：（无）
}

procedure SHA512Update(var Context: TCnSHA512Context; Input: PAnsiChar; ByteLength: Cardinal);
{* 以初始化后的上下文对一块数据进行 SHA512 计算。
   可多次调用以连续计算不同的数据块，无需将不同的数据块拼凑在连续的内存中。

   参数：
     var Context: TCnSHA512Context        - SHA512 上下文
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块的字节长度

   返回值：（无）
}

procedure SHA512Final(var Context: TCnSHA512Context; var Digest: TCnSHA512Digest);
{* 结束本轮计算，将 SHA512 结果返回至 Digest 中

   参数：
     var Context: TCnSHA512Context        - SHA512 上下文
     var Digest: TCnSHA512Digest          - 返回的 SHA512 杂凑值

   返回值：（无）
}

function SHA224Print(const Digest: TCnSHA224Digest): string;
{* 以十六进制格式输出 SHA224 杂凑值。

   参数：
     const Digest: TCnSHA224Digest        - 指定的 SHA224 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA256Print(const Digest: TCnSHA256Digest): string;
{* 以十六进制格式输出 SHA256 杂凑值。

   参数：
     const Digest: TCnSHA256Digest        - 指定的 SHA256 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA384Print(const Digest: TCnSHA384Digest): string;
{* 以十六进制格式输出 SHA384 杂凑值。

   参数：
     const Digest: TCnSHA384Digest        - 指定的 SHA384 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA512Print(const Digest: TCnSHA512Digest): string;
{* 以十六进制格式输出 SHA512 杂凑值。

   参数：
     const Digest: TCnSHA512Digest        - 指定的 SHA512 杂凑值

   返回值：string                         - 返回十六进制字符串
}

function SHA224Match(const D1: TCnSHA224Digest; const D2: TCnSHA224Digest): Boolean;
{* 比较两个 SHA224 杂凑值是否相等。

   参数：
     const D1: TCnSHA224Digest            - 待比较的 SHA224 杂凑值一
     const D2: TCnSHA224Digest            - 待比较的 SHA224 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA256Match(const D1: TCnSHA256Digest; const D2: TCnSHA256Digest): Boolean;
{* 比较两个 SHA256 杂凑值是否相等。

   参数：
     const D1: TCnSHA256Digest            - 待比较的 SHA256 杂凑值一
     const D2: TCnSHA256Digest            - 待比较的 SHA256 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA384Match(const D1: TCnSHA384Digest; const D2: TCnSHA384Digest): Boolean;
{* 比较两个 SHA384 杂凑值是否相等。

   参数：
     const D1: TCnSHA384Digest            - 待比较的 SHA384 杂凑值一
     const D2: TCnSHA384Digest            - 待比较的 SHA384 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA512Match(const D1: TCnSHA512Digest; const D2: TCnSHA512Digest): Boolean;
{* 比较两个 SHA512 杂凑值是否相等。

   参数：
     const D1: TCnSHA512Digest            - 待比较的 SHA512 杂凑值一
     const D2: TCnSHA512Digest            - 待比较的 SHA512 杂凑值二

   返回值：Boolean                        - 返回是否相等
}

function SHA224DigestToStr(const Digest: TCnSHA224Digest): string;
{* SHA224 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA224Digest        - 待转换的 SHA224 杂凑值

   返回值：string                         - 返回的字符串
}

function SHA256DigestToStr(const Digest: TCnSHA256Digest): string;
{* SHA256 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA256Digest        - 待转换的 SHA256 杂凑值

   返回值：string                         - 返回的字符串
}

function SHA384DigestToStr(const Digest: TCnSHA384Digest): string;
{* SHA384 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA384Digest        - 待转换的 SHA384 杂凑值

   返回值：string                         - 返回的字符串
}

function SHA512DigestToStr(const Digest: TCnSHA512Digest): string;
{* SHA512 杂凑值内容直接转 string，每字节对应一字符。

   参数：
     const Digest: TCnSHA512Digest        - 待转换的 SHA512 杂凑值

   返回值：string                         - 返回的字符串
}

procedure SHA224Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA224Digest);
{* 基于 SHA224 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA224 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA224 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA224Digest          - 返回的 SHA224 杂凑值

   返回值：（无）
}

procedure SHA256Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA256Digest);
{* 基于 SHA256 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA256 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA256 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA256Digest          - 返回的 SHA256 杂凑值

   返回值：（无）
}

procedure SHA384Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA384Digest);
{* 基于 SHA384 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA384 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA384 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA384Digest          - 返回的 SHA384 杂凑值

   返回值：（无）
}

procedure SHA512Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA512Digest);
{* 基于 SHA512 的 HMAC（Hash-based Message Authentication Code）计算，
   在普通数据的计算上加入密钥的概念，也叫加盐。

   参数：
     Key: PAnsiChar                       - 待参与 SHA512 计算的密钥数据块地址
     KeyByteLength: Integer               - 待参与 SHA512 计算的密钥数据块字节长度
     Input: PAnsiChar                     - 待计算的数据块地址
     ByteLength: Cardinal                 - 待计算的数据块字节长度
     var Output: TCnSHA512Digest          - 返回的 SHA512 杂凑值

   返回值：（无）
}

implementation

const
  HMAC_SHA2_224_256_BLOCK_SIZE_BYTE = 64;
  HMAC_SHA2_384_512_BLOCK_SIZE_BYTE = 128;

  HMAC_SHA2_224_OUTPUT_LENGTH_BYTE = 28;
  HMAC_SHA2_256_OUTPUT_LENGTH_BYTE = 32;
  HMAC_SHA2_384_OUTPUT_LENGTH_BYTE = 48;
  HMAC_SHA2_512_OUTPUT_LENGTH_BYTE = 64;

type
  TSHA2Type = (stSHA2_224, stSHA2_256, stSHA2_384, stSHA2_512);

const
  MAX_FILE_SIZE = 512 * 1024 * 1024;
  // If file size <= this size (bytes), using Mapping, else stream

  KEYS256: array[0..63] of Cardinal = ($428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5,
    $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5, $D807AA98, $12835B01, $243185BE,
    $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174, $E49B69C1, $EFBE4786,
    $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA, $983E5152,
    $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E,
    $92722C85, $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624,
    $F40E3585, $106AA070, $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3,
    $4ED8AA4A, $5B9CCA4F, $682E6FF3, $748F82EE, $78A5636F, $84C87814, $8CC70208,
    $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);

  KEYS512: array[0..79] of TUInt64 = ($428A2F98D728AE22, $7137449123EF65CD,
    $B5C0FBCFEC4D3B2F, $E9B5DBA58189DBBC, $3956C25BF348B538, $59F111F1B605D019,
    $923F82A4AF194F9B, $AB1C5ED5DA6D8118, $D807AA98A3030242, $12835B0145706FBE,
    $243185BE4EE4B28C, $550C7DC3D5FFB4E2, $72BE5D74F27B896F, $80DEB1FE3B1696B1,
    $9BDC06A725C71235, $C19BF174CF692694, $E49B69C19EF14AD2, $EFBE4786384F25E3,
    $0FC19DC68B8CD5B5, $240CA1CC77AC9C65, $2DE92C6F592B0275, $4A7484AA6EA6E483,
    $5CB0A9DCBD41FBD4, $76F988DA831153B5, $983E5152EE66DFAB, $A831C66D2DB43210,
    $B00327C898FB213F, $BF597FC7BEEF0EE4, $C6E00BF33DA88FC2, $D5A79147930AA725,
    $06CA6351E003826F, $142929670A0E6E70, $27B70A8546D22FFC, $2E1B21385C26C926,
    $4D2C6DFC5AC42AED, $53380D139D95B3DF, $650A73548BAF63DE, $766A0ABB3C77B2A8,
    $81C2C92E47EDAEE6, $92722C851482353B, $A2BFE8A14CF10364, $A81A664BBC423001,
    $C24B8B70D0F89791, $C76C51A30654BE30, $D192E819D6EF5218, $D69906245565A910,
    $F40E35855771202A, $106AA07032BBD1B8, $19A4C116B8D2D0C8, $1E376C085141AB53,
    $2748774CDF8EEB99, $34B0BCB5E19B48A8, $391C0CB3C5C95A63, $4ED8AA4AE3418ACB,
    $5B9CCA4F7763E373, $682E6FF3D6B2B8A3, $748F82EE5DEFB2FC, $78A5636F43172F60,
    $84C87814A1F0AB72, $8CC702081A6439EC, $90BEFFFA23631E28, $A4506CEBDE82BDE9,
    $BEF9A3F7B2C67915, $C67178F2E372532B, $CA273ECEEA26619C, $D186B8C721C0C207,
    $EADA7DD6CDE0EB1E, $F57D4F7FEE6ED178, $06F067AA72176FBA, $0A637DC5A2C898A6,
    $113F9804BEF90DAE, $1B710B35131C471B, $28DB77F523047D84, $32CAAB7B40C72493,
    $3C9EBE0A15C9BEBC, $431D67C49C100D4C, $4CC5D4BECB3E42B6, $597F299CFC657E2A,
    $5FCB6FAB3AD6FAEC, $6C44198C4A475817);

function ROTRight256(A, B: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (A shr B) or (A shl (32 - B));
end;

function ROTRight512(X: TUInt64; Y: Integer): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X shr Y) or (X shl (64 - Y));
end;

function SHR512(X: TUInt64; Y: Integer): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and $FFFFFFFFFFFFFFFF) shr Y;
end;

function CH256(X, Y, Z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and Y) xor ((not X) and Z);
end;

function CH512(X, Y, Z: TUInt64): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (((Y xor Z) and X) xor Z);
end;

function MAJ256(X, Y, Z: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and Y) xor (X and Z) xor (Y and Z);
end;

function MAJ512(X, Y, Z: TUInt64): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ((X or Y) and Z) or (X and Y);
end;

function EP0256(X: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight256(X, 2) xor ROTRight256(X, 13) xor ROTRight256(X, 22);
end;

function EP1256(X: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight256(X, 6) xor ROTRight256(X, 11) xor ROTRight256(X, 25);
end;

function SIG0256(X: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight256(X, 7) xor ROTRight256(X, 18) xor (X shr 3);
end;

function SIG1256(X: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight256(X, 17) xor ROTRight256(X, 19) xor (X shr 10);
end;

function SIG0512(X: TUInt64): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight512(X, 28) xor ROTRight512(X, 34) xor ROTRight512(X, 39);
end;

function SIG1512(X: TUInt64): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight512(X, 14) xor ROTRight512(X, 18) xor ROTRight512(X, 41);
end;

function Gamma0512(X: TUInt64): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight512(X, 1) xor ROTRight512(X, 8) xor SHR512(X, 7);
end;

function Gamma1512(X: TUInt64): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := ROTRight512(X, 19) xor ROTRight512(X, 61) xor SHR512(X, 6);
end;

procedure SHA256Transform(var Context: TCnSHA256Context; Data: PAnsiChar);
var
  A, B, C, D, E, F, G, H, T1, T2: Cardinal;
  M: array[0..63] of Cardinal;
  I, J: Integer;
begin
  I := 0;
  J := 0;
  while I < 16 do
  begin
    M[I] := (Cardinal(Data[J]) shl 24) or (Cardinal(Data[J + 1]) shl 16) or (Cardinal(Data
      [J + 2]) shl 8) or Cardinal(Data[J + 3]);
    Inc(I);
    Inc(J, 4);
  end;

  while I < 64 do
  begin
    M[I] := SIG1256(M[I - 2]) + M[I - 7] + SIG0256(M[I - 15]) + M[I - 16];
    Inc(I);
  end;

  A := Context.State[0];
  B := Context.State[1];
  C := Context.State[2];
  D := Context.State[3];
  E := Context.State[4];
  F := Context.State[5];
  G := Context.State[6];
  H := Context.State[7];

  I := 0;
  while I < 64 do
  begin
    T1 := H + EP1256(E) + CH256(E, F, G) + KEYS256[I] + M[I];
    T2 := EP0256(A) + MAJ256(A, B, C);
    H := G;
    G := F;
    F := E;
    E := D + T1;
    D := C;
    C := B;
    B := A;
    A := T1 + T2;
    Inc(I);
  end;

  Context.State[0] := Context.State[0] + A;
  Context.State[1] := Context.State[1] + B;
  Context.State[2] := Context.State[2] + C;
  Context.State[3] := Context.State[3] + D;
  Context.State[4] := Context.State[4] + E;
  Context.State[5] := Context.State[5] + F;
  Context.State[6] := Context.State[6] + G;
  Context.State[7] := Context.State[7] + H;
end;

{$WARNINGS OFF}

procedure SHA512Transform(var Context: TCnSHA512Context; Data: PAnsiChar; BlockCount: Integer);
var
  A, B, C, D, E, F, G, H, T1, T2: TUInt64;
  M: array[0..79] of TUInt64;
  I, J, K: Integer;
  OrigData: PAnsiChar;
begin
  OrigData := Data;
  for K := 0 to BlockCount - 1 do
  begin
    Data := PAnsiChar(TCnNativeInt(OrigData) + (K shl 7));

    I := 0;
    J := 0;
    while I < 16 do
    begin
      M[I] := (TUInt64(Data[J]) shl 56) or (TUInt64(Data[J + 1]) shl 48) or
        (TUInt64(Data[J + 2]) shl 40) or (TUInt64(Data[J + 3]) shl 32) or
        (TUInt64(Data[J + 4]) shl 24) or (TUInt64(Data[J + 5]) shl 16) or
        (TUInt64(Data[J + 6]) shl 8) or TUInt64(Data[J + 7]);
      Inc(I);
      Inc(J, 8);
    end;

    while I < 80 do
    begin
      M[I] := Gamma1512(M[I - 2]) + M[I - 7] + Gamma0512(M[I - 15]) + M[I - 16];
      Inc(I);
    end;

    A := Context.State[0];
    B := Context.State[1];
    C := Context.State[2];
    D := Context.State[3];
    E := Context.State[4];
    F := Context.State[5];
    G := Context.State[6];
    H := Context.State[7];

    I := 0;
    while I < 80 do
    begin
      T1 := H + SIG1512(E) + CH512(E, F, G) + KEYS512[I] + M[I];
      T2 := SIG0512(A) + MAJ512(A, B, C);
      H := G;
      G := F;
      F := E;
      E := D + T1;
      D := C;
      C := B;
      B := A;
      A := T1 + T2;
      Inc(I);
    end;

    // 以下有符号无符号相加有 Warning，但无影响
    Context.State[0] := Context.State[0] + A;
    Context.State[1] := Context.State[1] + B;
    Context.State[2] := Context.State[2] + C;
    Context.State[3] := Context.State[3] + D;
    Context.State[4] := Context.State[4] + E;
    Context.State[5] := Context.State[5] + F;
    Context.State[6] := Context.State[6] + G;
    Context.State[7] := Context.State[7] + H;
  end;
end;

{$WARNINGS ON}

procedure SHA224Init(var Context: TCnSHA224Context);
begin
  Context.DataLen := 0;
  Context.BitLen := 0;
  Context.State[0] := $C1059ED8;
  Context.State[1] := $367CD507;
  Context.State[2] := $3070DD17;
  Context.State[3] := $F70E5939;
  Context.State[4] := $FFC00B31;
  Context.State[5] := $68581511;
  Context.State[6] := $64F98FA7;
  Context.State[7] := $BEFA4FA4;
  FillChar(Context.Data, SizeOf(Context.Data), 0);
end;

procedure SHA224Update(var Context: TCnSHA224Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA256Update(Context, Input, ByteLength);
end;

procedure SHA256UpdateW(var Context: TCnSHA256Context; Input: PWideChar; CharLength: Cardinal); forward;

procedure SHA224UpdateW(var Context: TCnSHA224Context; Input: PWideChar; CharLength: Cardinal);
begin
  SHA256UpdateW(Context, Input, CharLength);
end;

procedure SHA224Final(var Context: TCnSHA224Context; var Digest: TCnSHA224Digest);
var
  Dig: TCnSHA256Digest;
begin
  SHA256Final(Context, Dig);
  Move(Dig[0], Digest[0], SizeOf(TCnSHA224Digest));
end;

procedure SHA256Init(var Context: TCnSHA256Context);
begin
  Context.DataLen := 0;
  Context.BitLen := 0;
  Context.State[0] := $6A09E667;
  Context.State[1] := $BB67AE85;
  Context.State[2] := $3C6EF372;
  Context.State[3] := $A54FF53A;
  Context.State[4] := $510E527F;
  Context.State[5] := $9B05688C;
  Context.State[6] := $1F83D9AB;
  Context.State[7] := $5BE0CD19;
  FillChar(Context.Data, SizeOf(Context.Data), 0);
end;

procedure SHA256Update(var Context: TCnSHA256Context; Input: PAnsiChar; ByteLength: Cardinal);
var
  I: Integer;
begin
  for I := 0 to ByteLength - 1 do
  begin
    Context.Data[Context.DataLen] := Byte(Input[I]);
    Inc(Context.DataLen);
    if Context.DataLen = 64 then
    begin
      SHA256Transform(Context, @Context.Data[0]);
      Context.BitLen := Context.BitLen + 512;
      Context.DataLen := 0;
    end;
  end;
end;

procedure SHA256UpdateW(var Context: TCnSHA256Context; Input: PWideChar; CharLength: Cardinal);
var
{$IFDEF MSWINDOWS}
  Content: PAnsiChar;
  iLen: Cardinal;
{$ELSE}
  S: string; // 必须是 UnicodeString
  A: AnsiString;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  GetMem(Content, CharLength * SizeOf(WideChar));
  try
    iLen := WideCharToMultiByte(0, 0, Input, CharLength, // 代码页默认用 0
      PAnsiChar(Content), CharLength * SizeOf(WideChar), nil, nil);
    SHA256Update(Context, Content, iLen);
  finally
    FreeMem(Content);
  end;
{$ELSE}  // MacOS 下直接把 UnicodeString 转成 AnsiString 计算，不支持非 Windows 非 Unicode 平台
  S := StrNew(Input);
  A := AnsiString(S);
  SHA256Update(Context, @A[1], Length(A));
{$ENDIF}
end;

procedure SHA256Final(var Context: TCnSHA256Context; var Digest: TCnSHA256Digest);
var
  I: Integer;
begin
  I := Context.DataLen;
  Context.Data[I] := $80;
  Inc(I);

  if Context.Datalen < 56 then
  begin
    while I < 56 do
    begin
      Context.Data[I] := 0;
      Inc(I);
    end;
  end
  else
  begin
    while I < 64 do
    begin
      Context.Data[I] := 0;
      Inc(I);
    end;

    SHA256Transform(Context, @(Context.Data[0]));
    FillChar(Context.Data, 56, 0);
  end;

  Context.BitLen := Context.BitLen + Context.DataLen * 8;
  Context.Data[63] := Context.Bitlen;
  Context.Data[62] := Context.Bitlen shr 8;
  Context.Data[61] := Context.Bitlen shr 16;
  Context.Data[60] := Context.Bitlen shr 24;
  Context.Data[59] := Context.Bitlen shr 32;
  Context.Data[58] := Context.Bitlen shr 40;
  Context.Data[57] := Context.Bitlen shr 48;
  Context.Data[56] := Context.Bitlen shr 56;
  SHA256Transform(Context, @(Context.Data[0]));

  for I := 0 to 3 do
  begin
    Digest[I] := (Context.State[0] shr (24 - I * 8)) and $000000FF;
    Digest[I + 4] := (Context.State[1] shr (24 - I * 8)) and $000000FF;
    Digest[I + 8] := (Context.State[2] shr (24 - I * 8)) and $000000FF;
    Digest[I + 12] := (Context.State[3] shr (24 - I * 8)) and $000000FF;
    Digest[I + 16] := (Context.State[4] shr (24 - I * 8)) and $000000FF;
    Digest[I + 20] := (Context.State[5] shr (24 - I * 8)) and $000000FF;
    Digest[I + 24] := (Context.State[6] shr (24 - I * 8)) and $000000FF;
    Digest[I + 28] := (Context.State[7] shr (24 - I * 8)) and $000000FF;
  end;
end;

{$WARNINGS OFF}

procedure SHA384Init(var Context: TCnSHA384Context);
begin
  Context.DataLen := 0;
  Context.TotalLen := 0;
  Context.State[0] := $CBBB9D5DC1059ED8;
  Context.State[1] := $629A292A367CD507;
  Context.State[2] := $9159015A3070DD17;
  Context.State[3] := $152FECD8F70E5939;
  Context.State[4] := $67332667FFC00B31;
  Context.State[5] := $8EB44A8768581511;
  Context.State[6] := $DB0C2E0D64F98FA7;
  Context.State[7] := $47B5481DBEFA4FA4;
  FillChar(Context.Data, SizeOf(Context.Data), 0);
end;

{$WARNINGS ON}

procedure SHA384Update(var Context: TCnSHA384Context; Input: PAnsiChar; ByteLength: Cardinal);
begin
  SHA512Update(Context, Input, ByteLength);
end;

procedure SHA512UpdateW(var Context: TCnSHA512Context; Input: PWideChar; CharLength: Cardinal); forward;

procedure SHA384UpdateW(var Context: TCnSHA384Context; Input: PWideChar; CharLength: Cardinal);
begin
  SHA512UpdateW(Context, Input, CharLength);
end;

procedure SHA384Final(var Context: TCnSHA384Context; var Digest: TCnSHA384Digest);
var
  Dig: TCnSHA512Digest;
begin
  SHA512Final(Context, Dig);
  Move(Dig[0], Digest[0], SizeOf(TCnSHA384Digest));
end;

{$WARNINGS OFF}

procedure SHA512Init(var Context: TCnSHA512Context);
begin
  Context.DataLen := 0;
  Context.TotalLen := 0;
  Context.State[0] := $6A09E667F3BCC908;
  Context.State[1] := $BB67AE8584CAA73B;
  Context.State[2] := $3C6EF372FE94F82B;
  Context.State[3] := $A54FF53A5F1D36F1;
  Context.State[4] := $510E527FADE682D1;
  Context.State[5] := $9B05688C2B3E6C1F;
  Context.State[6] := $1F83D9ABFB41BD6B;
  Context.State[7] := $5BE0CD19137E2179;
  FillChar(Context.Data, SizeOf(Context.Data), 0);
end;

{$WARNINGS ON}

procedure SHA512Update(var Context: TCnSHA512Context; Input: PAnsiChar; ByteLength: Cardinal);
var
  TempLength, RemainLength, NewLength, BlockCount: Cardinal;
begin
  TempLength := 128 - Context.DataLen;
  if ByteLength < TempLength then
    RemainLength := ByteLength
  else
    RemainLength := TempLength;

  Move(Input^, Context.Data[Context.DataLen], RemainLength);
  if Context.DataLen + ByteLength < 128 then
  begin
    Inc(Context.DataLen, ByteLength);
    Exit;
  end;

  NewLength := Cardinal(ByteLength) - RemainLength;
  BlockCount := NewLength div 128;
  Input := PAnsiChar(TCnNativeUInt(Input) + RemainLength);

  SHA512Transform(Context, @Context.Data[0], 1);
  SHA512Transform(Context, Input, BlockCount);

  RemainLength := NewLength mod 128;
  Input := PAnsiChar(TCnNativeUInt(Input) + (BlockCount shl 7));
  Move(Input^, Context.Data[Context.DataLen], RemainLength);

  Context.DataLen := RemainLength;
  Inc(Context.TotalLen, (BlockCount + 1) shl 7);
end;

procedure SHA512UpdateW(var Context: TCnSHA512Context; Input: PWideChar; CharLength: Cardinal);
var
{$IFDEF MSWINDOWS}
  Content: PAnsiChar;
  iLen: Cardinal;
{$ELSE}
  S: string; // 必须是 UnicodeString
  A: AnsiString;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  GetMem(Content, CharLength * SizeOf(WideChar));
  try
    iLen := WideCharToMultiByte(0, 0, Input, CharLength, // 代码页默认用 0
      PAnsiChar(Content), CharLength * SizeOf(WideChar), nil, nil);
    SHA512Update(Context, Content, iLen);
  finally
    FreeMem(Content);
  end;
{$ELSE}  // MacOS 下直接把 UnicodeString 转成 AnsiString 计算，不支持非 Windows 非 Unicode 平台
  S := StrNew(Input);
  A := AnsiString(S);
  SHA512Update(Context, @A[1], Length(A));
{$ENDIF}
end;

procedure SHA512Final(var Context: TCnSHA512Context; var Digest: TCnSHA512Digest);
var
  I: Integer;
  BlockCount, BitLength, PmLength: Cardinal;
begin
  if (Context.DataLen mod 128) > 111 then
    BlockCount := 2
  else
    BlockCount := 1;

  BitLength := (Context.TotalLen + Context.DataLen) shl 3;
  PmLength := BlockCount shl 7;
  FillChar(Context.Data[Context.DataLen], PmLength - Context.DataLen, 0);
  Context.Data[Context.DataLen] := $80;

  Context.Data[PmLength - 1] := Byte(BitLength);
  Context.Data[PmLength - 2] := Byte(BitLength shr 8);
  Context.Data[PmLength - 3] := Byte(BitLength shr 16);
  Context.Data[PmLength - 4] := Byte(BitLength shr 24);

  SHA512Transform(Context, @(Context.Data[0]), BlockCount);

  for I := 0 to 7 do
  begin
    Digest[I] := (Context.State[0] shr (56 - I * 8)) and $000000FF;
    Digest[I + 8] := (Context.State[1] shr (56 - I * 8)) and $000000FF;
    Digest[I + 16] := (Context.State[2] shr (56 - I * 8)) and $000000FF;
    Digest[I + 24] := (Context.State[3] shr (56 - I * 8)) and $000000FF;
    Digest[I + 32] := (Context.State[4] shr (56 - I * 8)) and $000000FF;
    Digest[I + 40] := (Context.State[5] shr (56 - I * 8)) and $000000FF;
    Digest[I + 48] := (Context.State[6] shr (56 - I * 8)) and $000000FF;
    Digest[I + 56] := (Context.State[7] shr (56 - I * 8)) and $000000FF;
  end;
end;

// 对数据块进行 SHA224 计算
function SHA224(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA224Digest;
var
  Context: TCnSHA224Context;
begin
  SHA224Init(Context);
  SHA224Update(Context, Input, ByteLength);
  SHA224Final(Context, Result);
end;

// 对数据块进行 SHA256 计算
function SHA256(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA256Digest;
var
  Context: TCnSHA256Context;
begin
  SHA256Init(Context);
  SHA256Update(Context, Input, ByteLength);
  SHA256Final(Context, Result);
end;

// 对数据块进行 SHA384 计算
function SHA384(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA384Digest;
var
  Context: TCnSHA384Context;
begin
  SHA384Init(Context);
  SHA384Update(Context, Input, ByteLength);
  SHA384Final(Context, Result);
end;

// 对数据块进行 SHA512 计算
function SHA512(Input: PAnsiChar; ByteLength: Cardinal): TCnSHA512Digest;
var
  Context: TCnSHA512Context;
begin
  SHA512Init(Context);
  SHA512Update(Context, Input, ByteLength);
  SHA512Final(Context, Result);
end;

// 对数据块进行 SHA224 计算
function SHA224Buffer(const Buffer; Count: Cardinal): TCnSHA224Digest;
var
  Context: TCnSHA224Context;
begin
  SHA224Init(Context);
  SHA224Update(Context, PAnsiChar(Buffer), Count);
  SHA224Final(Context, Result);
end;

// 对数据块进行 SHA256 计算
function SHA256Buffer(const Buffer; Count: Cardinal): TCnSHA256Digest;
var
  Context: TCnSHA256Context;
begin
  SHA256Init(Context);
  SHA256Update(Context, PAnsiChar(Buffer), Count);
  SHA256Final(Context, Result);
end;

// 对数据块进行 SHA384 计算
function SHA384Buffer(const Buffer; Count: Cardinal): TCnSHA384Digest;
var
  Context: TCnSHA384Context;
begin
  SHA384Init(Context);
  SHA384Update(Context, PAnsiChar(Buffer), Count);
  SHA384Final(Context, Result);
end;

// 对数据块进行 SHA512 计算
function SHA512Buffer(const Buffer; Count: Cardinal): TCnSHA512Digest;
var
  Context: TCnSHA512Context;
begin
  SHA512Init(Context);
  SHA512Update(Context, PAnsiChar(Buffer), Count);
  SHA512Final(Context, Result);
end;

// 对字节数组进行 SHA224 计算
function SHA224Bytes(Data: TBytes): TCnSHA224Digest;
var
  Context: TCnSHA224Context;
begin
  SHA224Init(Context);
  SHA224Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA224Final(Context, Result);
end;

// 对字节数组进行 SHA256 计算
function SHA256Bytes(Data: TBytes): TCnSHA256Digest;
var
  Context: TCnSHA256Context;
begin
  SHA256Init(Context);
  SHA256Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA256Final(Context, Result);
end;

// 对字节数组进行 SHA384 计算
function SHA384Bytes(Data: TBytes): TCnSHA384Digest;
var
  Context: TCnSHA384Context;
begin
  SHA384Init(Context);
  SHA384Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA384Final(Context, Result);
end;

// 对字节数组进行 SHA512 计算
function SHA512Bytes(Data: TBytes): TCnSHA512Digest;
var
  Context: TCnSHA512Context;
begin
  SHA512Init(Context);
  SHA512Update(Context, PAnsiChar(@Data[0]), Length(Data));
  SHA512Final(Context, Result);
end;

// 对 String 类型数据进行 SHA224 计算
function SHA224String(const Str: string): TCnSHA224Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA224StringA(AStr);
end;

// 对 String 类型数据进行 SHA256 计算
function SHA256String(const Str: string): TCnSHA256Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA256StringA(AStr);
end;

// 对 String 类型数据进行 SHA384 计算
function SHA384String(const Str: string): TCnSHA384Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA384StringA(AStr);
end;

// 对 String 类型数据进行 SHA512 计算
function SHA512String(const Str: string): TCnSHA512Digest;
var
  AStr: AnsiString;
begin
  AStr := AnsiString(Str);
  Result := SHA512StringA(AStr);
end;

// 对 UnicodeString 类型数据进行直接的 SHA224 计算，不进行转换
{$IFDEF UNICODE}
function SHA224UnicodeString(const Str: string): TCnSHA224Digest;
{$ELSE}
function SHA224UnicodeString(const Str: WideString): TCnSHA224Digest;
{$ENDIF}
var
  Context: TCnSHA224Context;
begin
  SHA224Init(Context);
  SHA224Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA224Final(Context, Result);
end;

// 对 UnicodeString 类型数据进行直接的 SHA256 计算，不进行转换
{$IFDEF UNICODE}
function SHA256UnicodeString(const Str: string): TCnSHA256Digest;
{$ELSE}
function SHA256UnicodeString(const Str: WideString): TCnSHA256Digest;
{$ENDIF}
var
  Context: TCnSHA256Context;
begin
  SHA256Init(Context);
  SHA256Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA256Final(Context, Result);
end;  

// 对 UnicodeString 类型数据进行直接的 SHA384 计算，不进行转换
{$IFDEF UNICODE}
function SHA384UnicodeString(const Str: string): TCnSHA384Digest;
{$ELSE}
function SHA384UnicodeString(const Str: WideString): TCnSHA384Digest;
{$ENDIF}
var
  Context: TCnSHA384Context;
begin
  SHA384Init(Context);
  SHA384Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA384Final(Context, Result);
end;  

// 对 UnicodeString 类型数据进行直接的 SHA512 计算，不进行转换
{$IFDEF UNICODE}
function SHA512UnicodeString(const Str: string): TCnSHA512Digest;
{$ELSE}
function SHA512UnicodeString(const Str: WideString): TCnSHA512Digest;
{$ENDIF}
var
  Context: TCnSHA512Context;
begin
  SHA512Init(Context);
  SHA512Update(Context, PAnsiChar(@Str[1]), Length(Str) * SizeOf(WideChar));
  SHA512Final(Context, Result);
end;

// 对 AnsiString 类型数据进行 SHA224 计算
function SHA224StringA(const Str: AnsiString): TCnSHA224Digest;
var
  Context: TCnSHA224Context;
begin
  SHA224Init(Context);
  SHA224Update(Context, PAnsiChar(Str), Length(Str));
  SHA224Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHA224 计算
function SHA224StringW(const Str: WideString): TCnSHA224Digest;
var
  Context: TCnSHA224Context;
begin
  SHA224Init(Context);
  SHA224UpdateW(Context, PWideChar(Str), Length(Str));
  SHA224Final(Context, Result);
end;

// 对 AnsiString 类型数据进行 SHA256 计算
function SHA256StringA(const Str: AnsiString): TCnSHA256Digest;
var
  Context: TCnSHA256Context;
begin
  SHA256Init(Context);
  SHA256Update(Context, PAnsiChar(Str), Length(Str));
  SHA256Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHA256 计算
function SHA256StringW(const Str: WideString): TCnSHA256Digest;
var
  Context: TCnSHA256Context;
begin
  SHA256Init(Context);
  SHA256UpdateW(Context, PWideChar(Str), Length(Str));
  SHA256Final(Context, Result);
end;

// 对 AnsiString 类型数据进行 SHA384 计算
function SHA384StringA(const Str: AnsiString): TCnSHA384Digest;
var
  Context: TCnSHA384Context;
begin
  SHA384Init(Context);
  SHA384Update(Context, PAnsiChar(Str), Length(Str));
  SHA384Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHA384 计算
function SHA384StringW(const Str: WideString): TCnSHA384Digest;
var
  Context: TCnSHA384Context;
begin
  SHA384Init(Context);
  SHA384UpdateW(Context, PWideChar(Str), Length(Str));
  SHA384Final(Context, Result);
end;

// 对 AnsiString 类型数据进行 SHA512 计算
function SHA512StringA(const Str: AnsiString): TCnSHA512Digest;
var
  Context: TCnSHA512Context;
begin
  SHA512Init(Context);
  SHA512Update(Context, PAnsiChar(Str), Length(Str));
  SHA512Final(Context, Result);
end;

// 对 WideString 类型数据进行 SHA512 计算
function SHA512StringW(const Str: WideString): TCnSHA512Digest;
var
  Context: TCnSHA512Context;
begin
  SHA512Init(Context);
  SHA512UpdateW(Context, PWideChar(Str), Length(Str));
  SHA512Final(Context, Result);
end;

function InternalSHAStream(Stream: TStream; const BufSize: Cardinal; var D:
  TCnSHAGeneralDigest; SHA2Type: TSHA2Type; CallBack: TCnSHACalcProgressFunc = nil): Boolean;
var
  Buf: PAnsiChar;
  BufLen: Cardinal;
  Size: Int64;
  ReadBytes: Cardinal;
  TotalBytes: Int64;
  SavePos: Int64;
  CancelCalc: Boolean;

  Context224: TCnSHA224Context;
  Context256: TCnSHA256Context;
  Context384: TCnSHA384Context;
  Context512: TCnSHA512Context;
  Dig224: TCnSHA224Digest;
  Dig256: TCnSHA256Digest;
  Dig384: TCnSHA384Digest;
  Dig512: TCnSHA512Digest;

  procedure _SHAInit;
  begin
    case SHA2Type of
      stSHA2_224:
        SHA224Init(Context224);
      stSHA2_256:
        SHA256Init(Context256);
      stSHA2_384:
        SHA384Init(Context384);
      stSHA2_512:
        SHA512Init(Context512);
    end;
  end;

  procedure _SHAUpdate;
  begin
    case SHA2Type of
      stSHA2_224:
        SHA224Update(Context224, Buf, ReadBytes);
      stSHA2_256:
        SHA256Update(Context256, Buf, ReadBytes);
      stSHA2_384:
        SHA384Update(Context384, Buf, ReadBytes);
      stSHA2_512:
        SHA512Update(Context512, Buf, ReadBytes);
    end;
  end;

  procedure _SHAFinal;
  begin
    case SHA2Type of
      stSHA2_224:
        SHA224Final(Context224, Dig224);
      stSHA2_256:
        SHA256Final(Context256, Dig256);
      stSHA2_384:
        SHA384Final(Context384, Dig384);
      stSHA2_512:
        SHA512Final(Context512, Dig512);
    end;
  end;

  procedure _CopyResult;
  begin
    case SHA2Type of
      stSHA2_224:
        Move(Dig224[0], D[0], SizeOf(TCnSHA224Digest));
      stSHA2_256:
        Move(Dig256[0], D[0], SizeOf(TCnSHA256Digest));
      stSHA2_384:
        Move(Dig384[0], D[0], SizeOf(TCnSHA384Digest));
      stSHA2_512:
        Move(Dig512[0], D[0], SizeOf(TCnSHA512Digest));
    end;
  end;

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
  _SHAInit;
 
  GetMem(Buf, BufLen);
  try
    Stream.Position := 0;
    repeat
      ReadBytes := Stream.Read(Buf^, BufLen);
      if ReadBytes <> 0 then
      begin
        Inc(TotalBytes, ReadBytes);
        _SHAUpdate;

        if Assigned(CallBack) then
        begin
          CallBack(Size, TotalBytes, CancelCalc);
          if CancelCalc then
            Exit;
        end;
      end;
    until (ReadBytes = 0) or (TotalBytes = Size);
    _SHAFinal;
    _CopyResult;
    Result := True;
  finally
    FreeMem(Buf, BufLen);
    Stream.Position := SavePos;
  end;
end;

// 对指定流进行 SHA224 计算
function SHA224Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA224Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  InternalSHAStream(Stream, 4096 * 1024, Dig, stSHA2_224, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA224Digest));
end;

// 对指定流进行 SHA256 计算
function SHA256Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA256Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  InternalSHAStream(Stream, 4096 * 1024, Dig, stSHA2_256, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA256Digest));
end;

// 对指定流进行 SHA384 计算
function SHA384Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA384Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  InternalSHAStream(Stream, 4096 * 1024, Dig, stSHA2_384, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA384Digest));
end;

// 对指定流进行 SHA512 计算
function SHA512Stream(Stream: TStream; CallBack: TCnSHACalcProgressFunc = nil):
  TCnSHA512Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  InternalSHAStream(Stream, 4096 * 1024, Dig, stSHA2_512, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA512Digest));
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

function InternalSHAFile(const FileName: string; SHA2Type: TSHA2Type;
  CallBack: TCnSHACalcProgressFunc): TCnSHAGeneralDigest;
var
  Context224: TCnSHA224Context;
  Context256: TCnSHA256Context;
  Context384: TCnSHA384Context;
  Context512: TCnSHA512Context;
  Dig224: TCnSHA224Digest;
  Dig256: TCnSHA256Digest;
  Dig384: TCnSHA384Digest;
  Dig512: TCnSHA512Digest;

{$IFDEF MSWINDOWS}
  FileHandle: THandle;
  MapHandle: THandle;
  ViewPointer: Pointer;
{$ENDIF}
  Stream: TStream;
  FileIsZeroSize: Boolean;

  procedure _SHAInit;
  begin
    case SHA2Type of
      stSHA2_224:
        SHA224Init(Context224);
      stSHA2_256:
        SHA256Init(Context256);
      stSHA2_384:
        SHA384Init(Context384);
      stSHA2_512:
        SHA512Init(Context512);
    end;
  end;

{$IFDEF MSWINDOWS}
  procedure _SHAUpdate;
  begin
    case SHA2Type of
      stSHA2_224:
        SHA224Update(Context224, ViewPointer, GetFileSize(FileHandle, nil));
      stSHA2_256:
        SHA256Update(Context256, ViewPointer, GetFileSize(FileHandle, nil));
      stSHA2_384:
        SHA384Update(Context384, ViewPointer, GetFileSize(FileHandle, nil));
      stSHA2_512:
        SHA512Update(Context512, ViewPointer, GetFileSize(FileHandle, nil));
    end;
  end;
{$ENDIF}

  procedure _SHAFinal;
  begin
    case SHA2Type of
      stSHA2_224:
        SHA224Final(Context224, Dig224);
      stSHA2_256:
        SHA256Final(Context256, Dig256);
      stSHA2_384:
        SHA384Final(Context384, Dig384);
      stSHA2_512:
        SHA512Final(Context512, Dig512);
    end;
  end;

  procedure _CopyResult(var D: TCnSHAGeneralDigest);
  begin
    case SHA2Type of
      stSHA2_224:
        Move(Dig224[0], D[0], SizeOf(TCnSHA224Digest));
      stSHA2_256:
        Move(Dig256[0], D[0], SizeOf(TCnSHA256Digest));
      stSHA2_384:
        Move(Dig384[0], D[0], SizeOf(TCnSHA384Digest));
      stSHA2_512:
        Move(Dig512[0], D[0], SizeOf(TCnSHA512Digest));
    end;
  end;

begin
  FileIsZeroSize := False;
  if FileSizeIsLargeThanMaxOrCanNotMap(FileName, FileIsZeroSize) then
  begin
    // 大于 2G 的文件可能 Map 失败，或非 Windows 平台，采用流方式循环处理
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      InternalSHAStream(Stream, 4096 * 1024, Result, SHA2Type, CallBack);
    finally
      Stream.Free;
    end;
  end
  else
  begin
{$IFDEF MSWINDOWS}
    _SHAInit;
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
                _SHAUpdate;
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
    _SHAFinal;
    _CopyResult(Result);
{$ENDIF}
  end;
end;

// 对指定文件数据进行 SHA224 计算
function SHA224File(const FileName: string; CallBack: TCnSHACalcProgressFunc):
  TCnSHA224Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  Dig := InternalSHAFile(FileName, stSHA2_224, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA224Digest));
end;

// 对指定文件数据进行 SHA256 计算
function SHA256File(const FileName: string; CallBack: TCnSHACalcProgressFunc):
  TCnSHA256Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  Dig := InternalSHAFile(FileName, stSHA2_256, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA256Digest));
end;

// 对指定文件数据进行 SHA384 计算
function SHA384File(const FileName: string; CallBack: TCnSHACalcProgressFunc):
  TCnSHA384Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  Dig := InternalSHAFile(FileName, stSHA2_384, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA384Digest));
end;

// 对指定文件数据进行 SHA512 计算
function SHA512File(const FileName: string; CallBack: TCnSHACalcProgressFunc):
  TCnSHA512Digest;
var
  Dig: TCnSHAGeneralDigest;
begin
  Dig := InternalSHAFile(FileName, stSHA2_512, CallBack);
  Move(Dig[0], Result[0], SizeOf(TCnSHA512Digest));
end;

// 以十六进制格式输出 SHA224 杂凑值
function SHA224Print(const Digest: TCnSHA224Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA224Digest));
end;

// 以十六进制格式输出 SHA256 杂凑值
function SHA256Print(const Digest: TCnSHA256Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA256Digest));
end;

// 以十六进制格式输出 SHA384 杂凑值
function SHA384Print(const Digest: TCnSHA384Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA384Digest));
end;

// 以十六进制格式输出 SHA512 杂凑值
function SHA512Print(const Digest: TCnSHA512Digest): string;
begin
  Result := DataToHex(@Digest[0], SizeOf(TCnSHA512Digest));
end;

// 比较两个 SHA224 杂凑值是否相等
function SHA224Match(const D1, D2: TCnSHA224Digest): Boolean;
var
  I: Integer;
begin
  I := 0;
  Result := True;
  while Result and (I < 28) do
  begin
    Result := D1[I] = D2[I];
    Inc(I);
  end;
end;

// 比较两个 SHA256 杂凑值是否相等
function SHA256Match(const D1, D2: TCnSHA256Digest): Boolean;
var
  I: Integer;
begin
  I := 0;
  Result := True;
  while Result and (I < 32) do
  begin
    Result := D1[I] = D2[I];
    Inc(I);
  end;
end;

// 比较两个 SHA384 杂凑值是否相等
function SHA384Match(const D1, D2: TCnSHA384Digest): Boolean;
var
  I: Integer;
begin
  I := 0;
  Result := True;
  while Result and (I < 48) do
  begin
    Result := D1[I] = D2[I];
    Inc(I);
  end;
end;

// 比较两个 SHA512 杂凑值是否相等
function SHA512Match(const D1, D2: TCnSHA512Digest): Boolean;
var
  I: Integer;
begin
  I := 0;
  Result := True;
  while Result and (I < 64) do
  begin
    Result := D1[I] = D2[I];
    Inc(I);
  end;
end;

// SHA224 杂凑值转 string
function SHA224DigestToStr(const Digest: TCnSHA224Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA224Digest));
end;

// SHA256 杂凑值转 string
function SHA256DigestToStr(const Digest: TCnSHA256Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA256Digest));
end;

// SHA384 杂凑值转 string
function SHA384DigestToStr(const Digest: TCnSHA384Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA384Digest));
end;

// SHA512 杂凑值转 string
function SHA512DigestToStr(const Digest: TCnSHA512Digest): string;
begin
  Result := MemoryToString(@Digest[0], SizeOf(TCnSHA512Digest));
end;

procedure SHA224HmacInit(var Context: TCnSHA224Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA224Digest;
begin
  if KeyLength > HMAC_SHA2_224_256_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA224Buffer(Key, KeyLength);
    KeyLength := HMAC_SHA2_224_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA2_224_256_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA2_224_256_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA224Init(Context);
  SHA224Update(Context, @(Context.Ipad[0]), HMAC_SHA2_224_256_BLOCK_SIZE_BYTE);
end;

procedure SHA224HmacUpdate(var Context: TCnSHA224Context; Input: PAnsiChar; Length:
  Cardinal);
begin
  SHA224Update(Context, Input, Length);
end;

procedure SHA224HmacFinal(var Context: TCnSHA224Context; var Output: TCnSHA224Digest);
var
  Len: Integer;
  TmpBuf: TCnSHA224Digest;
begin
  Len := HMAC_SHA2_224_OUTPUT_LENGTH_BYTE;
  SHA224Final(Context, TmpBuf);
  SHA224Init(Context);
  SHA224Update(Context, @(Context.Opad[0]), HMAC_SHA2_224_256_BLOCK_SIZE_BYTE);
  SHA224Update(Context, @(TmpBuf[0]), Len);
  SHA224Final(Context, Output);
end;

procedure SHA256HmacInit(var Context: TCnSHA256Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA256Digest;
begin
  if KeyLength > HMAC_SHA2_224_256_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA256Buffer(Key, KeyLength);
    KeyLength := HMAC_SHA2_256_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA2_224_256_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA2_224_256_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA256Init(Context);
  SHA256Update(Context, @(Context.Ipad[0]), HMAC_SHA2_224_256_BLOCK_SIZE_BYTE);
end;

procedure SHA256HmacUpdate(var Context: TCnSHA256Context; Input: PAnsiChar; Length:
  Cardinal);
begin
  SHA256Update(Context, Input, Length);
end;

procedure SHA256HmacFinal(var Context: TCnSHA256Context; var Output: TCnSHA256Digest);
var
  Len: Integer;
  TmpBuf: TCnSHA256Digest;
begin
  Len := HMAC_SHA2_256_OUTPUT_LENGTH_BYTE;
  SHA256Final(Context, TmpBuf);
  SHA256Init(Context);
  SHA256Update(Context, @(Context.Opad[0]), HMAC_SHA2_224_256_BLOCK_SIZE_BYTE);
  SHA256Update(Context, @(TmpBuf[0]), Len);
  SHA256Final(Context, Output);
end;

procedure SHA224Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA224Digest);
var
  Context: TCnSHA224Context;
begin
  SHA224HmacInit(Context, Key, KeyByteLength);
  SHA224HmacUpdate(Context, Input, ByteLength);
  SHA224HmacFinal(Context, Output);
end;

procedure SHA256Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA256Digest);
var
  Context: TCnSHA256Context;
begin
  SHA256HmacInit(Context, Key, KeyByteLength);
  SHA256HmacUpdate(Context, Input, ByteLength);
  SHA256HmacFinal(Context, Output);
end;

procedure SHA384HmacInit(var Context: TCnSHA384Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA384Digest;
begin
  if KeyLength > HMAC_SHA2_384_512_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA384Buffer(Key, KeyLength);
    KeyLength := HMAC_SHA2_384_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA2_384_512_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA2_384_512_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA384Init(Context);
  SHA384Update(Context, @(Context.Ipad[0]), HMAC_SHA2_384_512_BLOCK_SIZE_BYTE);
end;

procedure SHA384HmacUpdate(var Context: TCnSHA384Context; Input: PAnsiChar;
  Length: Cardinal);
begin
  SHA384Update(Context, Input, Length);
end;

procedure SHA384HmacFinal(var Context: TCnSHA384Context; var Output: TCnSHA384Digest);
var
  Len: Integer;
  TmpBuf: TCnSHA384Digest;
begin
  Len := HMAC_SHA2_384_OUTPUT_LENGTH_BYTE;
  SHA384Final(Context, TmpBuf);
  SHA384Init(Context);
  SHA384Update(Context, @(Context.Opad[0]), HMAC_SHA2_384_512_BLOCK_SIZE_BYTE);
  SHA384Update(Context, @(TmpBuf[0]), Len);
  SHA384Final(Context, Output);
end;

procedure SHA384Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA384Digest);
var
  Context: TCnSHA384Context;
begin
  SHA384HmacInit(Context, Key, KeyByteLength);
  SHA384HmacUpdate(Context, Input, ByteLength);
  SHA384HmacFinal(Context, Output);
end;

procedure SHA512HmacInit(var Context: TCnSHA512Context; Key: PAnsiChar; KeyLength: Integer);
var
  I: Integer;
  Sum: TCnSHA512Digest;
begin
  if KeyLength > HMAC_SHA2_384_512_BLOCK_SIZE_BYTE then
  begin
    Sum := SHA512Buffer(Key, KeyLength);
    KeyLength := HMAC_SHA2_512_OUTPUT_LENGTH_BYTE;
    Key := @(Sum[0]);
  end;

  FillChar(Context.Ipad, HMAC_SHA2_384_512_BLOCK_SIZE_BYTE, $36);
  FillChar(Context.Opad, HMAC_SHA2_384_512_BLOCK_SIZE_BYTE, $5C);

  for I := 0 to KeyLength - 1 do
  begin
    Context.Ipad[I] := Byte(Context.Ipad[I] xor Byte(Key[I]));
    Context.Opad[I] := Byte(Context.Opad[I] xor Byte(Key[I]));
  end;

  SHA512Init(Context);
  SHA512Update(Context, @(Context.Ipad[0]), HMAC_SHA2_384_512_BLOCK_SIZE_BYTE);
end;

procedure SHA512HmacUpdate(var Context: TCnSHA512Context; Input: PAnsiChar;
  Length: Cardinal);
begin
  SHA512Update(Context, Input, Length);
end;

procedure SHA512HmacFinal(var Context: TCnSHA512Context; var Output: TCnSHA512Digest);
var
  Len: Integer;
  TmpBuf: TCnSHA512Digest;
begin
  Len := HMAC_SHA2_512_OUTPUT_LENGTH_BYTE;
  SHA512Final(Context, TmpBuf);
  SHA512Init(Context);
  SHA512Update(Context, @(Context.Opad[0]), HMAC_SHA2_384_512_BLOCK_SIZE_BYTE);
  SHA512Update(Context, @(TmpBuf[0]), Len);
  SHA512Final(Context, Output);
end;

procedure SHA512Hmac(Key: PAnsiChar; KeyByteLength: Integer; Input: PAnsiChar;
  ByteLength: Cardinal; var Output: TCnSHA512Digest);
var
  Context: TCnSHA512Context;
begin
  SHA512HmacInit(Context, Key, KeyByteLength);
  SHA512HmacUpdate(Context, Input, ByteLength);
  SHA512HmacFinal(Context, Output);
end;

end.
