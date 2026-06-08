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

unit CnWideStrings;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：WideStrings 单元，支持 Win32/64 和 Posix
* 单元作者：CnPack 开发组
* 备    注：该单元实现了简化的 TCnWideStringList 类与部分 Unicode 字符处理函数，
*           以及扩展的 UTF-8 到 UTF-16 的编解码函数，支持 UTF-16 中的四字节字符与 UTF8-MB4
*
*           另外，本单元在处理 Ansi 字符串和 Utf16 宽字符串互转时，涉及
*           一个宽字符的字节数量、所占光标列宽、所占显示宽度倍数三个概念
*           后两者往往等同（不排除特殊情况），而和前者不能等同，故此需要区分 ByteLength 和 DisplayLength
*           获取字符的字节数量，和 IDE 行为无关，独立成 ByteLength 系列函数
*           但计算所占光标列宽或所占显示宽度倍数，则要求和 IDE 行为有关（和 IDE 版本有关）
*           因而独立成 DisplayLength 系列函数，并允许不同地方传入不同的 Calculator 进行计算
*
*           补充：Lazarus IDE 中编译时使用 LConvEncoding 进行转换，似乎靠谱点儿。
*
* 开发平台：WinXP SP3 + Delphi 5.0
* 兼容测试：
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2025.08.06 V1.3
*               Ansi 转换为 Utf8 支持 FPC
*           2024.08.01 V1.3
*               允许外界指定宽字符的显示宽度计算回调，以满足部分自定义绘制情形
*               并独立区分出 Ansi 的 ByteLength 和 DisplayLength 系列函数
*               判断显示宽度、光标列等，需要用 DisplayLength 系列函数
*               如 IDE 有特殊要求，还得传入定制化的 Calculator
*           2022.11.25 V1.2
*               从 CnGB18030 中搬移过来部分 Unicode 处理函数
*           2022.11.10 V1.1
*               UTF-8 编码解码支持 UTF8-MB4 与 UTF-16 中的四字节字符
*           2010.01.16 by ZhouJingyu
*               初始化提交
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

// {$DEFINE UTF16_BE}

// Delphi 默认 UTF16-LE，如果要处理 UTF16-BE 字符串，需要定义 UTF16_BE

uses
  {$IFDEF MSWINDOWS} Windows, {$ENDIF} SysUtils, Classes, CnNative
  {$IFDEF LAZARUS}, LConvEncoding {$ENDIF};

const
  CN_INVALID_CODEPOINT = $FFFFFFFF;
  {* 非法的码点值}

  CN_ALTERNATIVE_CHAR  = '?';
  {* 编码转换遇到错误时的默认替换字符}

type
  ECnWideStringException = class(Exception);
  {* 宽字符串相关异常}

{$IFDEF UNICODE}
  TCnWideString = string;
{$ELSE}
  TCnWideString = WideString;
{$ENDIF}

  TCnCodePoint = type Cardinal;
  {* 字符码值，或者叫码点，不等于表达的编码方式}

  TCn2CharRec = packed record
  {* 双字节字符结构}
    P1: AnsiChar;
    P2: AnsiChar;
  end;
  PCn2CharRec = ^TCn2CharRec;

  TCn4CharRec = packed record
  {* 四字节字符结构}
    P1: AnsiChar;
    P2: AnsiChar;
    P3: AnsiChar;
    P4: AnsiChar;
  end;
  PCn4CharRec = ^TCn4CharRec;

{ TCnWideStringList }

  TCnWideListFormat = (wlfAnsi, wlfUtf8, wlfUnicode);
  {* 加载与保存时支持的三种编码，Ansi、Utf8、Utf16}

  TCnWideStringList = class;
  TCnWideStringListSortCompare = function(List: TCnWideStringList; Index1, Index2: Integer): Integer;

  PCnWideStringItem = ^TCnWideStringItem;
  TCnWideStringItem = record
    FString: WideString;
    FObject: TObject;
  end;

  TCnWideStringList = class(TPersistent)
  {* WideString 版的 TStringList 实现，Load/Save 时有编码的处理}
  private
    FList: TList;
    FUseSingleLF: Boolean;
    FLoadFormat: TCnWideListFormat;
    FWriteBOM: Boolean;
    function GetName(Index: Integer): WideString;
    function GetValue(const Name: WideString): WideString;
    procedure SetValue(const Name, Value: WideString);
    procedure QuickSort(L, R: Integer; SCompare: TCnWideStringListSortCompare);
    function GetObject(Index: Integer): TObject;
    procedure PutObject(Index: Integer; const Value: TObject);
  protected
    function Get(Index: Integer): WideString; virtual;
    function GetCount: Integer; virtual;
    function GetTextStr: WideString; virtual;
    procedure Put(Index: Integer; const S: WideString); virtual;
    procedure SetTextStr(const Value: WideString); virtual;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const S: WideString): Integer; virtual;
    procedure AddStrings(Strings: TCnWideStringList); virtual;
    function AddObject(const S: WideString; AObject: TObject): Integer; virtual;
    procedure Assign(Source: TPersistent); override;
    procedure Clear; virtual;
    procedure Delete(Index: Integer); virtual; 
    procedure Exchange(Index1, Index2: Integer); virtual;
    function IndexOf(const S: WideString): Integer; virtual;
    function IndexOfName(const Name: WideString): Integer;
    procedure Insert(Index: Integer; const S: WideString); virtual;
    procedure LoadFromFile(const FileName: WideString); virtual;
    procedure LoadFromStream(Stream: TStream); virtual;
    procedure SaveToFile(const FileName: WideString; AFormat: TCnWideListFormat = wlfUnicode); virtual;
    procedure SaveToStream(Stream: TStream; AFormat: TCnWideListFormat = wlfUnicode); virtual;
    procedure CustomSort(Compare: TCnWideStringListSortCompare); virtual;
    procedure Sort; virtual;
    property Count: Integer read GetCount;
    property Names[Index: Integer]: WideString read GetName;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property Values[const Name: WideString]: WideString read GetValue write SetValue;
    property Strings[Index: Integer]: WideString read Get write Put; default;
    property Text: WideString read GetTextStr write SetTextStr;

    property UseSingleLF: Boolean read FUseSingleLF write FUseSingleLF;
    {* 控制 GetTextStr 时使用的换行是否是单个 #10 而不是常规的 #13#10}
    property LoadFormat: TCnWideListFormat read FLoadFormat;
    {* LoadFromStream 时识别出的格式}
    property WriteBOM: Boolean read FWriteBOM write FWriteBOM;
    {* 是否写 BOM 头}
  end;

  TCnWideCharDisplayWideLengthCalculator = function(AWChar: WideChar): Boolean;
  {* 针对宽字符的显示宽度计算回调函数类型，不同的 Delphi IDE 编辑器中需要不同的实现}

function CnUtf8EncodeWideString(const S: TCnWideString): AnsiString;
{* 对 WideString 进行 UTF-8 编码并将内容放到 AnsiString 中返回，不做 Ansi 转换避免丢字符，
   支持四字节 UTF-16 字符与 UTF8-MB4。

   参数：
     const S: WideString/UnicodeString    - 待转换的宽字符串

   返回值：AnsiString                     - 返回 UTF-8 字符串
}

function CnUtf8DecodeToWideString(const S: AnsiString): TCnWideString;
{* 对内容是 UTF-8 编码的 AnsiString 进行 UTF-8 解码得到 WideString，不做 Ansi 转换避免丢字符，
   支持四字节 UTF-16 字符与 UTF8-MB4。

   参数：
     const S: AnsiString                  - 待转换的 UTF-8 字符串

   返回值：WideString/UnicodeString       - 返回的宽字符串
}

function GetUtf16HighByte(Rec: PCn2CharRec): Byte; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 得到一个 UTF-16 双字节字符的高位字节值。

   参数：
     Rec: PCn2CharRec                     - 待获取的双字节字符结构指针

   返回值：Byte                           - 返回高位字节值
}

function GetUtf16LowByte(Rec: PCn2CharRec): Byte; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 得到一个 UTF-16 双字节字符的低位字节值。

   参数：
     Rec: PCn2CharRec                     - 待获取的双字节字符结构指针

   返回值：Byte                           - 返回低位字节值
}

procedure SetUtf16HighByte(B: Byte; Rec: PCn2CharRec); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 设置一个 UTF-16 双字节字符的高位字节值。

   参数：
     B: Byte                              - 待设置的高位字节值
     Rec: PCn2CharRec                     - 待设置的双字节字符结构指针

   返回值：（无）
}

procedure SetUtf16LowByte(B: Byte; Rec: PCn2CharRec); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 设置一个 UTF-16 双字节字符的低位字节值

   参数：
     B: Byte                              - 待设置的低位字节值
     Rec: PCn2CharRec                     - 待设置的双字节字符结构指针

   返回值：（无）
}

function GetCharLengthFromUtf8(Utf8Str: PAnsiChar): Integer;
{* 计算一 UTF-8（可能是 UTF8-MB4）字符串的字符数。

   参数：
     Utf8Str: PAnsiChar                   - 待计算的 UTF-8 字符串地址

   返回值：Integer                        - 返回该字符串的字符数
}

function GetCharLengthFromUtf16(Utf16Str: PWideChar): Integer;
{* 计算一 UTF-16（可能混合 Unicode 扩展平面里的四字节字符）字符串的字符数。

   参数：
     Utf16Str: PWideChar                  - 待计算的 UTF-16 字符串地址

   返回值：Integer                        - 返回该字符串的字符数
}

function GetByteWidthFromUtf8(Utf8Str: PAnsiChar): Integer;
{* 计算一 UTF-8（可能是 UTF8-MB4）字符串的当前字符占多少字节。

   参数：
     Utf8Str: PAnsiChar                   - 待计算的 UTF-8 字符串地址

   返回值：Integer                        - 返回该字符串的字节数
}

function GetByteWidthFromUtf16(Utf16Str: PWideChar): Integer;
{* 计算一 UTF-16（可能混合 Unicode 扩展平面里的四字节字符）字符串的当前字符占多少字节。

   参数：
     Utf16Str: PWideChar                  - 待计算的 UTF-16 字符串地址

   返回值：Integer                        - 返回该字符串的字节数
}

function GetCodePointFromUtf16Char(Utf16Str: PWideChar): TCnCodePoint;
{* 计算一个 UTF-16 字符的编码值（也叫代码位置），注意 Utf16Str 可能指向一个双字节字符，也可能指向一个四字节字符

   参数：
     Utf16Str: PWideChar                  - 待计算的 UTF-16 字符地址

   返回值：TCnCodePoint                   - 返回该字符的编码值
}

function GetCodePointFromUtf164Char(PtrTo4Char: Pointer): TCnCodePoint;
{* 计算一个四字节 UTF-16 字符的编码值（也叫代码位置）。

   参数：
     PtrTo4Char: Pointer                  - 待计算的四字节 UTF-16 字符地址

   返回值：TCnCodePoint                   - 返回该字符的编码值
}

function GetUtf16CharFromCodePoint(CP: TCnCodePoint; PtrToChars: Pointer): Integer;
{* 计算一个 Unicode 编码值的二字节或四字节表示，如果 PtrToChars 指向的位置不为空，
   则将结果放在 PtrToChars 所指的二字节或四字节区域，如果码点非法，则返回 1 并设 PtrToChars 为 #0#0。
   调用者在 CP 超过 $FFFF 时须保证 PtrToChars 所指的区域至少四字节，反之二字节即可。
   返回 1 或 2，分别表示处理的是二字节或四字节。

   参数：
     CP: TCnCodePoint                     - 待计算的 Unicode 编码值
     PtrToChars: Pointer                  - 如果非 nil，则放置转换后的结果

   返回值：Integer                        - 返回 1 代表该字符占二字节，返回 2 代表四字节
}

// =============================================================================
//
// 以下函数涉及宽字符串与 UTF-8 转换时的计算，逻辑比较固定
//
// =============================================================================

function CalcUtf8LengthFromWideString(Text: PWideChar): Integer;
{* 计算宽字符串的 UTF-8 长度，等于 Utf8Encode 后取 Length，但不进行实际转换。

   参数：
     Text: PWideChar                      - 待计算的宽字符串地址

   返回值：Integer                        - 返回 UTF-8 字节长度
}

function CalcUtf8LengthFromWideChar(AChar: WideChar): Integer; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 计算一个 WideChar 转换成 UTF-8 后的字符长度。

   参数：
     AChar: WideChar                      - 待计算的宽字符

   返回值：Integer                        - 返回 UTF-8 字节长度
}

function CalcUtf8LengthFromWideStringOffset(Text: PWideChar; WideOffset: Integer): Integer;
{* 计算 Unicode 宽字符串从 1 到 WideOffset 的子串的 UTF-8 长度，WideOffset 从 1 开始。如果 WideOffset 是 0 则返回 0。
   等于 Copy(1, WideOffset) 后的子串转 UTF-8 取 Length，但不进行实际转换。

   参数：
     Text: PWideChar                      - 待计算的宽字符串地址
     WideOffset: Integer                  - 以宽字符为单位的偏移量

   返回值：Integer                        - 返回该宽字符串从 1 到 WideOffset 的子串的 UTF-8 长度
}

function CalcUtf8LengthFromWideStringAnsiOffset(Text: PWideChar; AnsiOffset: Integer): Integer;
{* 计算 Unicode 宽字符串转成 Ansi 后从 1 到 AnsiOffset 的子串的 UTF-8 长度，AnsiOffset 从 1 开始。如果 AnsiOffset 是 0 则返回 0。
   等于转 Ansi 后 Copy(1, AnsiOffset) 后的子串转回 Unicode 宽字符串再转 UTF-8 取 Length，但不进行实际转换。

   参数：
     Text: PWideChar                      - 待计算的宽字符串地址
     AnsiOffset: Integer                  - 以 Ansi 字符为单位的偏移量

   返回值：Integer                        - 返回该宽字符串转成 Ansi 后从 1 到 AnsiOffset 的子串的 UTF-8 长度
}

function CalcUtf8LengthFromUtf8HeadChar(AChar: AnsiChar): Integer;
{* 计算一个 UTF-8 前导字符所代表的字符长度。

   参数：
     AChar: AnsiChar                      - 待计算的 UTF-8 字符

   返回值：Integer                        - 返回字符长度
}

function CalcUtf8StringLengthFromWideOffset(Utf8Text: PAnsiChar; WideOffset: Integer): Integer;
{* 计算 UTF-8 字符串转换成 WideSting 后指定 Wide 子串长度对应的 UTF-8 字符串长度，WideOffset 从 1 开始。
   等于转 WideString 后 Copy(1, WideOffset) 再转回 UTF-8 再取 Length，但不用 UTF-8/WideString 互转，以避免额外的编码问题。

   参数：
     Utf8Text: PAnsiChar                  - 待计算的 UTF-8 字符串地址
     WideOffset: Integer                  - 以宽字符为单位的偏移量

   返回值：Integer                        - 返回该 UTF-8 字符串转换成 WideSting 后指定从 1 到 WideOffset 子串所对应的 UTF-8 字符串长度
}

// =============================================================================
//
// 以下函数涉及宽字符串与 Ansi 转换时的字节数量、所占光标列宽/所占显示宽度倍数等的计算
//
// =============================================================================

function WideCharIsWideLength(const AWChar: WideChar): Boolean; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 粗略判断一个 Unicode 宽字符是否占两个字符宽度，默认的简陋实现，与 IDE 版本及行为无关。
   是以下函数中的 TCnWideCharDisplayWideLengthCalculator 参数的默认实现。

   参数：
     const AWChar: WideChar               - 待判断的宽字符

   返回值：Boolean                        - 返回是否占两个字符宽度
}

function CalcAnsiByteLengthFromWideString(Text: PWideChar): Integer;
{* 计算 Unicode 宽字符串的 Ansi 字节长度，等于转 Ansi 后的 Length，但不用转 Ansi，以防止纯英文平台下丢字符。
   大于 $FF 的 UTF-16 字符当作 2 字节，否则为 1 字节。

   参数：
     Text: PWideChar                      - 待计算的宽字符串地址

   返回值：Integer                        - 返回转换后的 Ansi 字符串长度
}

function CalcAnsiDisplayLengthFromWideString(Text: PWideChar;
  Calculator: TCnWideCharDisplayWideLengthCalculator = nil): Integer;
{* 计算 Unicode 宽字符串的 Ansi 显示长度，等于转 Ansi 后的显示 Length，但不用转 Ansi，以防止纯英文平台下丢字符。
   以传入的 Calculator 来计算显示的字符宽度，不传时采用默认判断。

   参数：
     Text: PWideChar                                      - 待计算的宽字符串地址
     Calculator: TCnWideCharDisplayWideLengthCalculator   - 针对宽字符的显示宽度计算回调函数，不同的 Delphi IDE 编辑器中有不同的特殊规则

   返回值：Integer                                        - 返回转换后的 Ansi 字符串显示长度
}

function CalcAnsiByteLengthFromWideStringOffset(Text: PWideChar; WideOffset: Integer): Integer;
{* 计算 Unicode 宽字符串从 1 到 WideOffset 的子串的 Ansi 字节长度，WideOffset 从 1 开始。
   等于 Copy(1, WideOffset) 后的子串转 Ansi 字节取 Length，但不用实际转 Ansi，以防止纯英文平台下丢字符。
   大于 $FF 的 UTF-16 字符当作 2 字节，否则为 1 字节。

   参数：
     Text: PWideChar                      - 待计算的宽字符串地址
     WideOffset: Integer                  - 以宽字符为单位的偏移量

   返回值：Integer                        - 返回该宽字符串从 1 到 WideOffset 子串的 Ansi 字节长度
}

function CalcAnsiDisplayLengthFromWideStringOffset(Text: PWideChar; WideOffset: Integer;
  Calculator: TCnWideCharDisplayWideLengthCalculator = nil): Integer;
{* 计算 Unicode 宽字符串从 1 到 WideOffset 的子串的 Ansi 显示长度，WideOffset 从 1 开始。
   等于 Copy(1, WideOffset) 后的子串转 Ansi 取 Length，但不用实际转 Ansi，以防止纯英文平台下丢字符
   以传入的 Calculator 来计算显示的字符宽度，不传时采用默认判断。

   参数：
     Text: PWideChar                                      - 待计算的宽字符串地址
     WideOffset: Integer                                  - 针对字符的宽度计算回调，不同的 Delphi IDE 编辑器中有不同的特殊规则
     Calculator: TCnWideCharDisplayWideLengthCalculator   - 针对宽字符的显示宽度计算回调函数，不同的 Delphi IDE 编辑器中有不同的特殊规则

   返回值：Integer                                        - 返回该宽字符串从 1 到 WideOffset 子串的 Ansi 显示长度
}

function CalcWideStringByteLengthFromAnsiOffset(Text: PWideChar; AnsiOffset: Integer;
  AllowExceedEnd: Boolean = False): Integer;
{* 计算 Unicode 宽字符串指定 Ansi 子串长度对应的 Unicode 子串的字节长度，AnsiOffset 从 1 开始。
   等于内容转 Ansi 后的 Copy(1, AnsiOffset) 再转换回 Unicode 再取 Length，但不用 Ansi/Unicode 互转，以防止纯英文平台下丢字符
   注意 Ansi 后的 Copy 可能会割裂双字节字符。
   AllowExceedEnd 为 False 时，计算到 #0 便会终止，不包括 #0。为 True 时，以补空格方式计算。
   大于 $FF 的 UTF-16 字符当作 2 字节，否则为 1 字节。

   参数：
     Text: PWideChar                      - 待计算的宽字符串地址
     AnsiOffset: Integer                  - 以单字节字符为单位的偏移量
     AllowExceedEnd: Boolean              - 是否遇到 #0 时终止

   返回值：Integer                        - 返回该宽字符串转换为 Ansi 后从 1 到 AnsiOffset 子串长度对应的 Unicode 字符串的字节长度
}

function CalcWideStringDisplayLengthFromAnsiOffset(Text: PWideChar; AnsiOffset: Integer;
  AllowExceedEnd: Boolean = False; Calculator: TCnWideCharDisplayWideLengthCalculator = nil): Integer;
{* 计算 Unicode 宽字符串指定 Ansi 子串长度对应的 Unicode 子串长度，AnsiOffset 从 1 开始。
   等于显示转 Ansi 后的 Copy(1, AnsiOffset) 再转换回 Unicode 再取 Length，但不用 Ansi/Unicode 互转，以防止纯英文平台下丢字符
   注意 Ansi 后的 Copy 可能会割裂双字节字符。
   AllowExceedEnd 为 False 时，计算到 #0 便会终止，不包括 #0。为 True 时，以补空格方式计算
   以传入的 Calculator 来计算显示的字符宽度，不传时采用默认判断。

   参数：
     Text: PWideChar                                      - 待计算的宽字符串地址
     AnsiOffset: Integer                                  - 以单字节字符为单位的偏移量
     AllowExceedEnd: Boolean                              - 是否遇到 #0 时终止
     Calculator: TCnWideCharDisplayWideLengthCalculator   - 针对宽字符的显示宽度计算回调函数，不同的 Delphi IDE 编辑器中有不同的特殊规则

   返回值：Integer                                        - 返回该宽字符串转换为 Ansi 后从 1 到 AnsiOffset 子串长度对应的 Unicode 字符串的显示长度
}

function CalcUtf8LengthFromWideStringAnsiDisplayOffset(Text: PWideChar; AnsiDisplayOffset: Integer;
  Calculator: TCnWideCharDisplayWideLengthCalculator = nil): Integer;
{* 计算 Unicode 宽字符串转成显示相关的 Ansi 后从 1 到 AnsiOffset 的子串的 UTF-8 长度，AnsiDisplayOffset 从 1 开始。如果 AnsiDisplayOffset 是 0 则返回 0。
   等于转显示相关的 Ansi 后 Copy(1, AnsiDisplayOffset) 后的子串转回 Unicode 宽字符串再转 UTF-8 取 Length，但不进行实际转换。

   参数：
     Text: PWideChar                                      - 待计算的宽字符串地址
     AnsiDisplayOffset: Integer                           - 以显示相关的 Ansi 字符为单位的偏移量
     Calculator: TCnWideCharDisplayWideLengthCalculator   - 针对宽字符的显示宽度计算回调函数，不同的 Delphi IDE 编辑器中有不同的特殊规则

   返回值：Integer                                        - 返回该宽字符串转成显示相关的 Ansi 后从 1 到 AnsiDisplayOffset 的子串的 UTF-8 长度
}

function ConvertUtf16ToAlterDisplayAnsi(WideText: PWideChar; AlterChar: AnsiChar = ' ';
  Calculator: TCnWideCharDisplayWideLengthCalculator = nil): AnsiString;
{* 手动将宽字符串转换成显示用的 Ansi，把其中的宽字符按 Calculator 的判断替换成一个或两个 AlterChar，
   不传时采用默认判断。用于纯英文环境下的字符显示宽度计算，但不支持四字节字符。

   参数：
     WideText: PWideChar                                  - 待转换的宽字符串地址
     AlterChar: AnsiChar                                  - 替换字符
     Calculator: TCnWideCharDisplayWideLengthCalculator   - 针对宽字符的显示宽度计算回调函数，不同的 Delphi IDE 编辑器中有不同的特殊规则

   返回值：AnsiString                                     - 返回转换后的字符串
}

function ConvertUtf8ToAlterDisplayAnsi(Utf8Text: PAnsiChar; AlterChar: AnsiChar = ' ';
  Calculator: TCnWideCharDisplayWideLengthCalculator = nil): AnsiString;
{* 手动将 UTF-8 字符串转换成显示用的 Ansi，把其中的宽字符按 Calculator 的判断替换成一个或两个 AlterChar，
   不传时采用默认判断。用于纯英文环境下的字符显示宽度计算，但不支持四字节字符。

   参数：
     Utf8Text: PAnsiChar                                  - 待转换的 UTF-8 字符串地址
     AlterChar: AnsiChar                                  - 替换字符
     Calculator: TCnWideCharDisplayWideLengthCalculator   - 针对宽字符的显示宽度计算回调函数，不同的 Delphi IDE 编辑器中有不同的特殊规则

   返回值：AnsiString                                     - 返回转换后的字符串
}

function CnUtf8ToAnsi(const Text: AnsiString): AnsiString;
{* Ansi 版的转换 UTF-8 到 Ansi 字符串，以解决 Unicode 版本下 Utf8ToAnsi 是 UnicodeString 的问题。

   参数：
     const Text: AnsiString               - 待转换的 UTF-8 字符串

   返回值：AnsiString                     - 返回转换后的字符串
}

function CnUtf8ToAnsi2(const Text: string): string;
{* Ansi 版的转换 UTF-8 到 string，以解决 Unicode 版本下 Utf8ToAnsi 是 UnicodeString 的问题。

   参数：
     const Text: string                   - 待转换的 UTF-8 字符串

   返回值：string                         - 返回转换后的字符串
}

function CnAnsiToUtf8(const Text: AnsiString): AnsiString;
{* Ansi 版的转换 Ansi 字符串到 UTF-8 字符串，以解决 Unicode 版本下 AnsiToUtf8 是 UnicodeString 的问题。

   参数：
     const Text: AnsiString               - 待转换的 Ansi 字符串

   返回值：AnsiString                     - 返回转换后的 UTF-8 字符串
}

function CnAnsiToUtf82(const Text: string): string;
{* Ansi 版的转换 Ansi 字符串到 UTF-8 字符串，以解决 Unicode 版本下 AnsiToUtf8 是 UnicodeString 的问题。

   参数：
     const Text: string                   - 待转换的 Ansi 字符串

   返回值：string                         - 返回转换后的 UTF-8 字符串
}

{$IFDEF COMPILER5}

function WideCompareText(const S1, S2: WideString): Integer;
{* Delphi 5 中没有宽字符串比较函数，此处补充实现一个。

   参数：
     const S1: WideString                 - 待比较的宽字符串一
     const S2: WideString                 - 待比较的宽字符串二

   返回值：Integer                        - 返回比较结果

}

{$ENDIF}

// =============================================================================
//
// 文件编码检测相关
//
// =============================================================================

type
  TCnFileEncoding = (cfeUnknown, cfeUtf8, cfeUtf8Bom, cfeUtf16LE, cfeUtf16BE, cfeAnsi);
  {* 文件编码类型。

     cfeUnknown                           - 未知编码
     cfeUtf8                              - UTF-8 无 BOM
     cfeUtf8Bom                           - UTF-8 with BOM
     cfeUtf16LE                           - UTF-16 Little Endian
     cfeUtf16BE                           - UTF-16 Big Endian
     cfeAnsi                              - 系统代码页编码（非 Unicode）
  }

function CnDetectFileEncoding(const Bytes: TBytes): TCnFileEncoding;
{* 从字节数组检测文件编码。检测优先级：BOM → UTF-8 启发式 → Ansi。
   仅检查前 4 字节的 BOM 标记，无 BOM 时做 UTF-8 合法性检查。

   参数：
     const Bytes: TBytes                  - 文件内容的字节数组

   返回值：TCnFileEncoding                - 检测到的编码类型
}

function CnIsValidUtf8(const Bytes: TBytes): Boolean;
{* 启发式判断字节数组是否为合法的 UTF-8 序列。遍历每个字节检查 UTF-8 编码规范：
   - 单字节：0xxxxxxx
   - 双字节：110xxxxx 10xxxxxx
   - 三字节：1110xxxx 10xxxxxx 10xxxxxx
   - 四字节：11110xxx 10xxxxxx 10xxxxxx 10xxxxxx

   参数：
     const Bytes: TBytes                  - 待检测的字节数组

   返回值：Boolean                        - True 表示合法 UTF-8 序列
}

function CnStripBomBytes(const Bytes: TBytes): TBytes;
{* 移除字节数组开头的 BOM 前缀（UTF-8 BOM #EF#BB#BF / UTF-16 LE BOM #FF#FE / UTF-16 BE BOM #FE#FF）。
   无 BOM 时返回原始数组副本。

   参数：
     const Bytes: TBytes                  - 原始字节数组

   返回值：TBytes                         - 去除 BOM 后的字节数组
}

// =============================================================================
//
// TBytes 与 string 编码转换（跨 Delphi 版本安全的 UTF-8 工具）
//
// =============================================================================

function CnUtf8BytesToString(const Bytes: TBytes): string;
{* 将 UTF-8 编码的字节数组转换为 string，支持 Unicode 和非 Unicode 编译器。
   注意 Delphi 2007 或以下版本最终转换成 AnsiString 时可能丢字符。

   参数：
     const Bytes: TBytes                  - UTF-8 编码的字节数组

   返回值：string                         - 转换后的字符串
}

function CnStringToUtf8Bytes(const S: string): TBytes;
{* 将 string 转换为 UTF-8 编码的字节数组，支持 Unicode 和非 Unicode 编译器。

   参数：
     const S: string                      - 待转换的字符串

   返回值：TBytes                         - UTF-8 编码的字节数组
}

implementation

const
  SLineBreak = #13#10;
  SLineBreakLF = #10;

  CN_UTF16_4CHAR_PREFIX1_LOW  = $D8;
  CN_UTF16_4CHAR_PREFIX1_HIGH = $DC;
  CN_UTF16_4CHAR_PREFIX2_LOW  = $DC;
  CN_UTF16_4CHAR_PREFIX2_HIGH = $E0;

  CN_UTF16_4CHAR_HIGH_MASK    = $3;
  CN_UTF16_4CHAR_SPLIT_MASK   = $3FF;

  CN_UTF16_EXT_BASE           = $10000;

resourcestring
  SCnErrorInvalidUtf8CharLength = 'More than UTF8-MB4 NOT Support.';
  SCnErrorInvalidModeLength = 'More than UTF32 NOT Support.';

{ TCnWideStringList }

function WideCompareText(const S1, S2: WideString): Integer;
begin
{$IFDEF MSWINDOWS}
  Result := CompareStringW(LOCALE_USER_DEFAULT, NORM_IGNORECASE, PWideChar(S1),
    Length(S1), PWideChar(S2), Length(S2)) - 2;
{$ELSE}
  Result := WideCompareStr(S1, S2);
{$ENDIF}
end;

function TCnWideStringList.Add(const S: WideString): Integer;
begin
  Result := Count;
  Insert(Count, S);
end;

function TCnWideStringList.AddObject(const S: WideString;
  AObject: TObject): Integer;
begin
  Result := Add(S);
  PutObject(Result, AObject);
end;

procedure TCnWideStringList.AddStrings(Strings: TCnWideStringList);
var
  I: Integer;
begin
  for I := 0 to Strings.Count - 1 do
    Add(Strings[I]);
end;

procedure TCnWideStringList.Assign(Source: TPersistent);
begin
  if Source is TCnWideStringList then
  begin
    Clear;
    AddStrings(TCnWideStringList(Source));
    FLoadFormat := TCnWideStringList(Source).LoadFormat;
    FUseSingleLF := TCnWideStringList(Source).UseSingleLF;
    FWriteBOM := TCnWideStringList(Source).WriteBOM;
    Exit;
  end;
  inherited Assign(Source);
end;

procedure TCnWideStringList.Clear;
var
  I: Integer;
  P: PCnWideStringItem;
begin
  for I := 0 to Count - 1 do
  begin
    P := PCnWideStringItem(FList[I]);
    Dispose(P);
  end;
  FList.Clear;
end;

constructor TCnWideStringList.Create;
begin
  inherited;
  FList := TList.Create;
  FLoadFormat := wlfUnicode;
  FWriteBOM := True;
end;

procedure TCnWideStringList.CustomSort(Compare: TCnWideStringListSortCompare);
begin
  if Count > 1 then
    QuickSort(0, Count - 1, Compare);
end;

procedure TCnWideStringList.Delete(Index: Integer);
var
  P: PCnWideStringItem;
begin
  P := PCnWideStringItem(FList[Index]);
  FList.Delete(Index);
  Dispose(P);
end;

destructor TCnWideStringList.Destroy;
begin
  Clear;
  FList.Free;
  inherited;
end;

procedure TCnWideStringList.Exchange(Index1, Index2: Integer);
begin
  FList.Exchange(Index1, Index2);
end;

function TCnWideStringList.Get(Index: Integer): WideString;
begin
  Result := PCnWideStringItem(FList[Index])^.FString;
end;

function TCnWideStringList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TCnWideStringList.GetName(Index: Integer): WideString;
var
  P: Integer;
begin
  Result := Get(Index);
  P := Pos('=', Result);
  if P <> 0 then
    SetLength(Result, P - 1) else
    SetLength(Result, 0);
end;

function TCnWideStringList.GetObject(Index: Integer): TObject;
begin
  Result := PCnWideStringItem(FList[Index])^.FObject;
end;

function TCnWideStringList.GetTextStr: WideString;
var
  I, L, Size, C: Integer;
  P: PwideChar;
  S, LB: WideString;
begin
  C := GetCount;
  Size := 0;

  if FUseSingleLF then
    LB := SLineBreakLF
  else
    LB := SLineBreak;

  for I := 0 to C - 1 do Inc(Size, Length(Get(I)) + Length(LB));
  SetString(Result, nil, Size);
  P := Pointer(Result);
  for I := 0 to C - 1 do
  begin
    S := Get(I);
    L := Length(S);
    if L <> 0 then
    begin
      System.Move(Pointer(S)^, P^, L * SizeOf(WideChar));
      Inc(P, L);
    end;
    L := Length(LB);
    if L <> 0 then
    begin
      System.Move(Pointer(LB)^, P^, L * SizeOf(WideChar));
      Inc(P, L);
    end;
  end;
end;

function TCnWideStringList.GetValue(const Name: WideString): WideString;
var
  I: Integer;
begin
  I := IndexOfName(Name);
  if I >= 0 then
    Result := Copy(Get(I), Length(Name) + 2, MaxInt) else
    Result := '';
end;

function TCnWideStringList.IndexOf(const S: WideString): Integer;
begin
  for Result := 0 to GetCount - 1 do
  begin
    if WideCompareText(Get(Result), S) = 0 then
      Exit;
  end;
  Result := -1;
end;

function TCnWideStringList.IndexOfName(const Name: WideString): Integer;
var
  P: Integer;
  S: string;
begin
  for Result := 0 to GetCount - 1 do
  begin
    S := Get(Result);
    P := Pos('=', S);
    if (P <> 0) and (WideCompareText(Copy(S, 1, P - 1), Name) = 0) then
      Exit;
  end;
  Result := -1;
end;

procedure TCnWideStringList.Insert(Index: Integer; const S: WideString);
var
  P: PCnWideStringItem;
begin
  New(P);
  P^.FString := S;
  FList.Insert(Index, P);
end;

procedure TCnWideStringList.LoadFromFile(const FileName: WideString);
var
  Stream: TStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TCnWideStringList.LoadFromStream(Stream: TStream);
var
  Size, Len: Integer;
  S: WideString;
  HeaderStr, SA: AnsiString;
begin
  Size := Stream.Size - Stream.Position;
  if Size >= 3 then
  begin
    SetLength(HeaderStr, 3);
    Stream.Read(Pointer(HeaderStr)^, 3);
    if HeaderStr = #$EF#$BB#$BF then // UTF-8 BOM
    begin
      SetLength(SA, Size - 3);
      Stream.Read(Pointer(SA)^, Size - 3);
{$IFDEF MSWINDOWS}
      Len := MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(SA), -1, nil, 0);
      SetLength(S, Len);
      MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(SA), -1, PWideChar(S), Len);
{$ELSE}
  {$IFDEF FPC}
      S := CnUtf8DecodeToWideString(SA);
  {$ELSE}
      S := UTF8ToWideString(SA);
  {$ENDIF}
{$ENDIF}
      SetTextStr(S);

      FLoadFormat := wlfUtf8;
      Exit;
    end;
    Stream.Position := Stream.Position - 3;  
  end;

  if Size >= 2 then
  begin
    SetLength(HeaderStr, 2);
    Stream.Read(Pointer(HeaderStr)^, 2);
    if HeaderStr = #$FF#$FE then // UTF-16 BOM
    begin
      SetLength(S, (Size - 2) div SizeOf(WideChar));
      Stream.Read(Pointer(S)^, (Size - 2) div SizeOf(WideChar) * SizeOf(WideChar));
      SetTextStr(S);

      FLoadFormat := wlfUnicode;
      Exit;
    end;
    Stream.Position := Stream.Position - 2;  
  end;
      
  SetString(SA, nil, Size);
  Stream.Read(Pointer(SA)^, Size);
  SetTextStr({$IFDEF UNICODE}string{$ENDIF}(SA));
  FLoadFormat := wlfAnsi;
end;

procedure TCnWideStringList.Put(Index: Integer; const S: WideString);
var
  P: PCnWideStringItem;
begin
  P := PCnWideStringItem(FList[Index]);
  P^.FString := S;
end;

procedure TCnWideStringList.PutObject(Index: Integer; const Value: TObject);
begin
  PCnWideStringItem(FList[Index])^.FObject := Value;
end;

procedure TCnWideStringList.QuickSort(L, R: Integer;
  SCompare: TCnWideStringListSortCompare);
var
  I, J, P: Integer;
begin
  repeat
    I := L;
    J := R;
    P := (L + R) shr 1;
    repeat
      while SCompare(Self, I, P) < 0 do Inc(I);
      while SCompare(Self, J, P) > 0 do Dec(J);
      if I <= J then
      begin
        Exchange(I, J);
        if P = I then
          P := J
        else if P = J then
          P := I;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then QuickSort(L, J, SCompare);
    L := I;
  until I >= R;
end;

procedure TCnWideStringList.SaveToFile(const FileName: WideString; AFormat: TCnWideListFormat);
var
  Stream: TStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(Stream, AFormat);
  finally
    Stream.Free;
  end;
end;

procedure TCnWideStringList.SaveToStream(Stream: TStream; AFormat: TCnWideListFormat);
var
  S: WideString;
  HeaderStr, SA: AnsiString;
  Len: Integer;
begin
  S := GetTextStr;
  if AFormat = wlfAnsi then
  begin
    SA := AnsiString(S);
    Stream.WriteBuffer(Pointer(SA)^, Length(SA) * SizeOf(AnsiChar));
  end
  else if AFormat = wlfUtf8 then
  begin
    if FWriteBOM then
    begin
      HeaderStr := #$EF#$BB#$BF;
      Stream.WriteBuffer(Pointer(HeaderStr)^, Length(HeaderStr) * SizeOf(AnsiChar));
    end;
{$IFDEF MSWINDOWS}
    Len := WideCharToMultiByte(CP_UTF8, 0, PWideChar(S), -1, nil, 0, nil, nil);
    SetLength(SA, Len);
    WideCharToMultiByte(CP_UTF8, 0, PWideChar(S), -1, PAnsiChar(SA), Len, nil, nil);
{$ELSE}
    SA := UTF8Encode(S);
{$ENDIF}
    Stream.WriteBuffer(Pointer(SA)^, Length(SA) * SizeOf(AnsiChar) - 1);
  end
  else if AFormat = wlfUnicode then
  begin
    if FWriteBOM then
    begin
      HeaderStr := #$FF#$FE;
      Stream.WriteBuffer(Pointer(HeaderStr)^, Length(HeaderStr) * SizeOf(AnsiChar));
    end;
    Stream.WriteBuffer(Pointer(S)^, Length(S) * SizeOf(WideChar));
  end;
end;

procedure TCnWideStringList.SetTextStr(const Value: WideString);
var
  P, Start: PWideChar;
  S: WideString;
begin
  Clear;
  P := Pointer(Value);
  if P <> nil then
  begin
    while P^ <> #0 do
    begin
      Start := P;
      while not (Ord(P^) in [0, 10, 13]) do Inc(P);
      SetString(S, Start, P - Start);
      Add(S);
      if P^ = #13 then Inc(P);
      if P^ = #10 then Inc(P);
    end;
  end;
end;

procedure TCnWideStringList.SetValue(const Name, Value: WideString);
var
  I: Integer;
begin
  I := IndexOfName(Name);
  if Value <> '' then
  begin
    if I < 0 then I := Add('');
    Put(I, Name + '=' + Value);
  end
  else
  begin
    if I >= 0 then Delete(I);
  end;
end;

function StringListCompareStrings(List: TCnWideStringList; Index1, Index2: Integer): Integer;
begin
  Result := WideCompareText(PCnWideStringItem(List.FList[Index1])^.FString,
    PCnWideStringItem(List.FList[Index2])^.FString);
end;

procedure TCnWideStringList.Sort;
begin
  CustomSort(StringListCompareStrings);
end;

// D5 下没有内置 UTF-8/Ansi 转换函数，且低版本即使有也不支持 UTF8-MB4，因此写个替代品
// 为调用者简明起见，SourceChars 传双字节宽字符个数即可
function InternalUnicodeToUtf8(Dest: PAnsiChar; MaxDestBytes: Cardinal;
  Source: PWideChar; SourceChars: Cardinal): Cardinal;
var
  I, Cnt: Cardinal;
  C: Cardinal;
begin
  Result := 0;
  if Source = nil then
    Exit;

  Cnt := 0;
  I := 0;
  if Dest <> nil then
  begin
    while (I < SourceChars) and (Cnt < MaxDestBytes) do
    begin
      if (SourceChars - I >= 2) and (GetByteWidthFromUtf16(@(Source[I])) = 4) then
      begin
        // 本字符是四字节，要特殊编码
        C := GetCodePointFromUtf164Char(PAnsiChar(@(Source[I])));
        Inc(I, 2); // 步进两个 WideChar
      end
      else
      begin
        C := Cardinal(Source[I]);
        Inc(I); // 步进一个 WideChar
      end;

      if C <= $7F then
      begin
        Dest[Cnt] := AnsiChar(C);
        Inc(Cnt);
      end
      else if C > $FFFF then
      begin
        if Cnt + 4 > MaxDestBytes then
          Break;

        Dest[Cnt] := AnsiChar($F0 or (C shr 18));
        Dest[Cnt + 1] := AnsiChar($80 or ((C shr 12) and $3F));
        Dest[Cnt + 2] := AnsiChar($80 or ((C shr 6) and $3F));
        Dest[Cnt + 3] := AnsiChar($80 or (C and $3F));
        Inc(Cnt, 4);
      end
      else if C > $7FF then
      begin
        if Cnt + 3 > MaxDestBytes then
          Break;
        Dest[Cnt] := AnsiChar($E0 or (C shr 12));
        Dest[Cnt + 1] := AnsiChar($80 or ((C shr 6) and $3F));
        Dest[Cnt + 2] := AnsiChar($80 or (C and $3F));
        Inc(Cnt, 3);
      end
      else //  $7F < Source[i] <= $7FF
      begin
        if Cnt + 2 > MaxDestBytes then
          Break;
        Dest[Cnt] := AnsiChar($C0 or (C shr 6));
        Dest[Cnt + 1] := AnsiChar($80 or (C and $3F));
        Inc(Cnt, 2);
      end;
    end;

    if Cnt >= MaxDestBytes then
      Cnt := MaxDestBytes - 1;
    Dest[Cnt] := #0;
  end
  else
  begin
    while I < SourceChars do
    begin
      if (SourceChars - I >= 2) and (GetByteWidthFromUtf16(@(Source[I])) = 4) then
      begin
        // 本字符是四字节，要特殊编码
        C := GetCodePointFromUtf164Char(PAnsiChar(@(Source[I])));
        Inc(I, 2); // 步进两个 WideChar
      end
      else
      begin
        C := Cardinal(Source[I]);
        Inc(I);
      end;

      if C > $7F then
      begin
        if C > $7FF then
        begin
          if C > $FFFF then
            Inc(Cnt);
          Inc(Cnt);
        end;
        Inc(Cnt);
      end;
      Inc(Cnt);
    end;
  end;
  Result := Cnt + 1;
end;

function InternalUtf8ToUnicode(Dest: PWideChar; MaxDestChars: Cardinal;
  Source: PAnsiChar; SourceBytes: Cardinal): Cardinal;
var
  K: Integer;
  I, Cnt: Cardinal;
  C: Byte;
  WC: Cardinal;
begin
  if Source = nil then
  begin
    Result := 0;
    Exit;
  end;

  Result := Cardinal(-1);
  Cnt := 0;
  I := 0;
  if Dest <> nil then
  begin
    while (I < SourceBytes) and (Cnt < MaxDestChars) do
    begin
      WC := Cardinal(Source[I]);
      Inc(I);

      if (WC and $80) <> 0 then
      begin
        if I >= SourceBytes then                // 不完整
          Exit;

        if (WC and $F0) = $F0 then              // 四字节（未限定第四位必须是 0），单独处理，再步进三个字符，拼成字符值，再算成四字节的 UTF-16 编码
        begin
          if SourceBytes - I < 3 then           // 不够四字节则出错退出
            Exit;

          // WC 是第一个字节，取低三位（未限定第四位必须是 0），后面仨字节各取低六位，得到码点
          WC := ((WC and $7) shl 18) + ((Cardinal(Source[I]) and $3F) shl 12)
            + ((Cardinal(Source[I + 1]) and $3F) shl 6) + (Cardinal(Source[I + 2]) and $3F);

          // 根据码点生成 UTF-16 字符，并步进 Cnt
          K := GetUtf16CharFromCodePoint(WC, @(Dest[Cnt]));
          if K = 2 then // 生成了四字节字符，先步进一个 WideChar，下一个放 if 后步进
            Inc(Cnt);
          Inc(I, 3);
        end
        else
        begin
          WC := WC and $3F;
          if (WC and $20) <> 0 then
          begin
            C := Byte(Source[I]);
            Inc(I);
            if (C and $C0) <> $80 then           // malformed trail byte or out of range char
              Exit;
            if I >= SourceBytes then             // incomplete multibyte char
              Exit;
            WC := (WC shl 6) or (C and $3F);
          end;
          C := Byte(Source[I]);
          Inc(I);
          if (C and $C0) <> $80 then             // malformed trail byte
            Exit;

          Dest[Cnt] := WideChar((WC shl 6) or (C and $3F));
        end;
      end
      else
        Dest[Cnt] := WideChar(WC);
      Inc(Cnt);
    end;
    if Cnt >= MaxDestChars then Cnt := MaxDestChars - 1;
    Dest[Cnt] := #0;
  end
  else
  begin
    while (I < SourceBytes) do
    begin
      C := Byte(Source[I]);
      Inc(I);

      if (C and $80) <> 0 then                  // 最高位为 1，至少二字节
      begin
        if I >= SourceBytes then                // incomplete multibyte char
          Exit;

        C := C and $3F;                         // 留下第一个字节的低六位，前两位已经当成 11 了
        if (C and $20) <> 0 then                // 如果是 1110，则表示至少有仨字节
        begin
          if (C and $10) <> 0 then              // 如果是 11110，则表示共有四字节
          begin
            C := Byte(Source[I]);               // 读第四个中的第二个字节
            Inc(I);
            if (C and $C0) <> $80 then          // 该字节最高两位得是 10
              Exit;                             // malformed trail byte or out of range char
            if I >= SourceBytes then
              Exit;                             // incomplete multibyte char

            Inc(Cnt);                           // 四字节的 UTF8，应对应 UTF-16 中的两个 WideChar，这里额外加一
          end;

          C := Byte(Source[I]);                 // 读四个中的第三个字节，或三个中的第二个字节
          Inc(I);
          if (C and $C0) <> $80 then            // 该字节最高两位得是 10，否则退出
            Exit;
          if I >= SourceBytes then
            Exit;                               // incomplete multibyte char
        end;

        C := Byte(Source[I]);                   // 读四个中的第四个字节，或三个中的第三个字节，或二个中的第二个字节
        Inc(I);
        if (C and $C0) <> $80 then              // 该字节最高两位得是 10，否则退出
          Exit;                                 // malformed trail byte
      end;

      Inc(Cnt);
    end;
  end;
  Result := Cnt + 1;
end;

// 对 WideString 进行 UTF-8 编码得到 AnsiString，不做 Ansi 转换避免丢字符
function CnUtf8EncodeWideString(const S: TCnWideString): AnsiString;
var
  L: Integer;
  Temp: AnsiString;
begin
  Result := '';
  if S = '' then
    Exit;
  SetLength(Temp, Length(S) * 4); // 一个双字节字符最多 4 个 UTF-8 字符

  L := InternalUnicodeToUtf8(PAnsiChar(Temp), Length(Temp) + 1, PWideChar(S), Length(S));
  if L > 0 then
    SetLength(Temp, L - 1)
  else
    Temp := '';
  Result := Temp;
end;

// 对 AnsiString 的 UTF-8 解码得到 WideString，不做 Ansi 转换避免丢字符
function CnUtf8DecodeToWideString(const S: AnsiString): TCnWideString;
var
  L: Integer;
begin
  Result := '';
  if S = '' then
    Exit;
  SetLength(Result, Length(S));

  L := InternalUtf8ToUnicode(PWideChar(Result), Length(Result) + 1, PAnsiChar(S), Length(S));
  if L > 0 then
    SetLength(Result, L - 1)
  else
    Result := '';
end;

function GetUtf16HighByte(Rec: PCn2CharRec): Byte;
begin
{$IFDEF UTF16_BE}
  Result := Byte(Rec^.P1);
{$ELSE}
  Result := Byte(Rec^.P2); // UTF16-LE 的高低位会置换
{$ENDIF}
end;

function GetUtf16LowByte(Rec: PCn2CharRec): Byte;
begin
{$IFDEF UTF16_BE}
  Result := Byte(Rec^.P2);
{$ELSE}
  Result := Byte(Rec^.P1); // UTF16-LE 的高低位会置换
{$ENDIF}
end;

procedure SetUtf16HighByte(B: Byte; Rec: PCn2CharRec);
begin
{$IFDEF UTF16_BE}
  Rec^.P1 := AnsiChar(B);
{$ELSE}
  Rec^.P2 := AnsiChar(B); // UTF16-LE 的高低位会置换
{$ENDIF}
end;

procedure SetUtf16LowByte(B: Byte; Rec: PCn2CharRec);
begin
{$IFDEF UTF16_BE}
  Rec^.P2 := AnsiChar(B);
{$ELSE}
  Rec^.P1 := AnsiChar(B); // UTF16-LE 的高低位会置换
{$ENDIF}
end;

function GetCharLengthFromUtf8(Utf8Str: PAnsiChar): Integer;
var
  L: Integer;
begin
  Result := 0;
  while Utf8Str^ <> #0 do
  begin
    L := GetByteWidthFromUtf8(Utf8Str);
    Inc(Utf8Str, L);
    Inc(Result);
  end;
end;

function GetCharLengthFromUtf16(Utf16Str: PWideChar): Integer;
var
  L: Integer;
begin
  Result := 0;
  while Utf16Str^ <> #0 do
  begin
    L := GetByteWidthFromUtf16(Utf16Str);
    Utf16Str := PWideChar(TCnIntAddress(Utf16Str) + L);
    Inc(Result);
  end;
end;

function GetByteWidthFromUtf8(Utf8Str: PAnsiChar): Integer;
var
  B: Byte;
begin
  B := Byte(Utf8Str^);
  if B >= $FC then        // 6 个 1，1 个 0，先不考虑七或八 1 的情况
    Result := 6
  else if B >= $F8 then   // 5 个 1，1 个 0
    Result := 5
  else if B >= $F0 then   // 4 个 1，1 个 0
    Result := 4
  else if B >= $E0 then   // 3 个 1，1 个 0
    Result := 3
  else if B >= $B0 then   // 2 个 1，1 个 0
    Result := 2
  else                    // 其他
    Result := 1;
end;

function GetByteWidthFromUtf16(Utf16Str: PWideChar): Integer;
var
  P: PCn2CharRec;
  B1, B2: Byte;
begin
  Result := 2;

  P := PCn2CharRec(Utf16Str);
  B1 := GetUtf16HighByte(P);

  if (B1 >= CN_UTF16_4CHAR_PREFIX1_LOW) and (B1 < CN_UTF16_4CHAR_PREFIX1_HIGH) then
  begin
    // 如果两个单字节字符拼一块，其值在 $D800 到 $DBFF 之间，也就是该双字节的高位字节在 [$D8, $DC) 区间内
    Inc(P);
    B2 := GetUtf16HighByte(P);

    // 那么紧跟在后面的两个单字节字符应该在 $DC00 到 $DFFF 之间，
    if (B2 >= CN_UTF16_4CHAR_PREFIX2_LOW) and (B2 < CN_UTF16_4CHAR_PREFIX2_HIGH) then
      Result := 4;

    // 这四个字节组成一个四字节 Unicode 字符，但并非该值的编码值
  end;
end;

function GetCodePointFromUtf16Char(Utf16Str: PWideChar): TCnCodePoint;
var
  R: Word;
  C2: PCn2CharRec;
begin
  if GetByteWidthFromUtf16(Utf16Str) = 4 then // 四字节字符
    Result := GetCodePointFromUtf164Char(PAnsiChar(Utf16Str))
  else  // 普通双字节字符
  begin
    C2 := PCn2CharRec(Utf16Str);
    R := Byte(C2^.P1) shl 8 + Byte(C2^.P2);       // 双字节字符，值本身就是编码值

{$IFDEF UTF16_BE}
    Result := TCnCodePoint(R);
{$ELSE}
    Result := TCnCodePoint(UInt16ToBigEndian(R)); // UTF16-LE 要交换值
{$ENDIF}
  end;
end;

function GetCodePointFromUtf164Char(PtrTo4Char: Pointer): TCnCodePoint;
var
  TH, TL: Word;
  C2: PCn2CharRec;
begin
  C2 := PCn2CharRec(PtrTo4Char);

  // 第一个字节，去掉高位的 110110；第二个字节留着，共 2 + 8 = 10 位
  TH := (GetUtf16HighByte(C2) and CN_UTF16_4CHAR_HIGH_MASK) shl 8 + GetUtf16LowByte(C2);
  Inc(C2);

  // 第三个字节，去掉高位的 110111，第四个字节留着，共 2 + 8 = 10 位
  TL := (GetUtf16HighByte(C2) and CN_UTF16_4CHAR_HIGH_MASK) shl 8 + GetUtf16LowByte(C2);

  // 高 10 位拼低 10 位
  Result := TH shl 10 + TL + CN_UTF16_EXT_BASE;
  // 码点减去 $10000 后的值，前 10 位映射到 $D800 到 $DBFF 之间，后 10 位映射到 $DC00 到 $DFFF 之间
end;

function GetUtf16CharFromCodePoint(CP: TCnCodePoint; PtrToChars: Pointer): Integer;
var
  C2: PCn2CharRec;
  L, H: Byte;
  LW, HW: Word;
begin
  if CP = CN_INVALID_CODEPOINT then
  begin
    if PtrToChars <> nil then
    begin
      C2 := PCn2CharRec(PtrToChars);
      SetUtf16LowByte(0, C2);
      SetUtf16HighByte(0, C2);
    end;
    Result := 1;
    Exit;
  end;

  if CP >= CN_UTF16_EXT_BASE then
  begin
    if PtrToChars <> nil then
    begin
      CP := CP - CN_UTF16_EXT_BASE;
      // 拆出高 10 位放前两字节，拆出低 10 位放后两字节

      LW := CP and CN_UTF16_4CHAR_SPLIT_MASK;          // 低 10 位，放三、四字节
      HW := (CP shr 10) and CN_UTF16_4CHAR_SPLIT_MASK; // 高 10 位，放一、二字节

      L := HW and $FF;
      H := (HW shr 8) and CN_UTF16_4CHAR_HIGH_MASK;
      H := H or CN_UTF16_4CHAR_PREFIX1_LOW;              // 1101 1000
      C2 := PCn2CharRec(PtrToChars);

      SetUtf16LowByte(L, C2);
      SetUtf16HighByte(H, C2);

      L := LW and $FF;
      H := (LW shr 8) and CN_UTF16_4CHAR_HIGH_MASK;
      H := H or CN_UTF16_4CHAR_PREFIX1_HIGH;              // 1101 1100
      Inc(C2);

      SetUtf16LowByte(L, C2);
      SetUtf16HighByte(H, C2);
    end;
    Result := 2;
  end
  else
  begin
    if PtrToChars <> nil then
    begin
      C2 := PCn2CharRec(PtrToChars);
      SetUtf16LowByte(Byte(CP and $00FF), C2);
      SetUtf16HighByte(Byte(CP shr 8), C2);
    end;
    Result := 1;
  end;
end;

// 计算宽字符串的 UTF-8 长度，等于 Utf8Encode 后取 Length，但不实际转换
function CalcUtf8LengthFromWideString(Text: PWideChar): Integer;
begin
  Result := 0;
  if Text = nil then
    Exit;

  while Text^ <> #0 do
  begin
    Inc(Result, CalcUtf8LengthFromWideChar(Text^));
    Inc(Text);
  end;
end;

// 计算一个 WideChar 转换成 UTF-8 后的字符长度
function CalcUtf8LengthFromWideChar(AChar: WideChar): Integer;
var
  V: Cardinal;
begin
  V := Ord(AChar);
  if V <= $7F then
    Result := 1
  else if V <= $7FF then
    Result := 2
  else if V <= $FFFF then
    Result := 3
  else if V <= $10FFFF then
    Result := 4
  else
    Result := 0;
end;

// 计算 Unicode 宽字符串从 1 到 WideOffset 的子串的 UTF-8 长度，WideOffset 从 1 开始
function CalcUtf8LengthFromWideStringOffset(Text: PWideChar; WideOffset: Integer): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text <> nil) and (WideOffset > 0) then
  begin
    Idx := 0;
    while (Text^ <> #0) and (Idx < WideOffset) do // Idx 0 开始，WideOffset 1 开始，所以用 <
    begin
      Inc(Result, CalcUtf8LengthFromWideChar(Text^));
      Inc(Text);
      Inc(Idx);
    end;
  end;
end;

// 计算 Unicode 宽字符串转成 Ansi 后从 1 到 AnsiOffset 的子串的 UTF-8 长度，AnsiOffset 从 1 开始
function CalcUtf8LengthFromWideStringAnsiOffset(Text: PWideChar; AnsiOffset: Integer): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text <> nil) and (AnsiOffset > 0) then
  begin
    Idx := 0;
    while (Text^ <> #0) and (Idx < AnsiOffset) do // Idx 0 开始，AnsiOffset 1 开始，所以用 <
    begin
      Inc(Result, CalcUtf8LengthFromWideChar(Text^));
      Inc(Text);
      if Ord(Text^) > $FF then // 大于 $FF 的转成 Ansi 必然占两字节
        Inc(Idx, 2)
      else
        Inc(Idx);
    end;
  end;
end;

// 计算一个 UTF-8 前导字符所代表的字符长度
function CalcUtf8LengthFromUtf8HeadChar(AChar: AnsiChar): Integer;
var
  B: Byte;
begin
  B := Ord(AChar);
  if B and $80 = 0 then  // 0xxx xxxx
    Result := 1
  else if B and $E0 = $C0 then // 110x xxxx 10xxxxxx
    Result := 2
  else if B and $F0 = $E0 then // 1110 xxxx 10xxxxxx 10xxxxxx
    Result := 3
  else if B and $F8 = $F0 then // 1111 0xxx 10xxxxxx 10xxxxxx 10xxxxxx
    Result := 4
  else
    raise ECnWideStringException.Create(SCnErrorInvalidUtf8CharLength);
end;

// 计算 UTF-8 字符串转换成 WideSting 后指定 Wide 子串长度对应的 UTF-8 字符串长度，WideOffset 从 1 开始。
// 等于转 WideString 后 Copy(1, WideOffset) 再转回 UTF-8 再取 Length，但不用 UTF-8/WideString 互转，以避免额外的编码问题
function CalcUtf8StringLengthFromWideOffset(Utf8Text: PAnsiChar;
  WideOffset: Integer): Integer;
var
  Utf8Len, WideIdx: Integer;
begin
  Result := 0;
  if (Utf8Text = nil) or (WideOffset <= 0) then
    Exit;

  WideIdx := 0;
  while (Utf8Text^ <> #0) and (WideIdx < WideOffset) do
  begin
    Utf8Len := CalcUtf8LengthFromUtf8HeadChar(Utf8Text^);
    Inc(Result, Utf8Len);

    case Utf8Len of
      1:
        begin
          Inc(WideIdx);
          Inc(Utf8Text);
        end;
      2:
        begin
          Inc(WideIdx);
          Inc(Utf8Text);
          if Utf8Text^ = #0 then
            Exit;
          Inc(Utf8Text);
        end;
      3:
        begin
          Inc(WideIdx);
          Inc(Utf8Text);
          if Utf8Text^ = #0 then
            Exit;
          Inc(Utf8Text);
          if Utf8Text^ = #0 then
            Exit;
          Inc(Utf8Text);
        end;
      4: // UTF8-MB4
        begin
          Inc(WideIdx);
          Inc(Utf8Text);
          if Utf8Text^ = #0 then
            Exit;
          Inc(Utf8Text);
          if Utf8Text^ = #0 then
            Exit;
          Inc(Utf8Text);
          if Utf8Text^ = #0 then
            Exit;
          Inc(Utf8Text);
        end;
    else
      Exit;
    end;
  end;
end;

// 粗略判断一个 Unicode 宽字符是否占两个字符宽度，默认的简陋实现
function WideCharIsWideLength(const AWChar: WideChar): Boolean; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
const
  CN_UTF16_ANSI_WIDE_CHAR_SEP = $1100;
var
  C: Integer;
begin
  C := Ord(AWChar);
  Result := C > CN_UTF16_ANSI_WIDE_CHAR_SEP; // 姑且认为比 $1100 大的 Utf16 字符绘制宽度才占俩字节
end;

function CalcAnsiByteLengthFromWideString(Text: PWideChar): Integer;
begin
  Result := 0;
  if Text = nil then
    Exit;

  while Text^ <> #0 do
  begin
    if Ord(Text^) > $FF then
      Inc(Result, SizeOf(WideChar))
    else
      Inc(Result, SizeOf(AnsiChar));
    Inc(Text);
  end;
end;

// 计算 Unicode 宽字符串的 Ansi 长度，等于转 Ansi 后的 Length，但不用转 Ansi，以防止纯英文平台下丢字符
function CalcAnsiDisplayLengthFromWideString(Text: PWideChar;
  Calculator: TCnWideCharDisplayWideLengthCalculator): Integer;
begin
  Result := 0;
  if Text = nil then
    Exit;

  if not Assigned(Calculator) then
    Calculator := @WideCharIsWideLength;

  while Text^ <> #0 do
  begin
    if Calculator(Text^) then
      Inc(Result, SizeOf(WideChar))
    else
      Inc(Result, SizeOf(AnsiChar));
    Inc(Text);
  end;
end;

function CalcAnsiByteLengthFromWideStringOffset(Text: PWideChar; WideOffset: Integer): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text = nil) or (WideOffset <= 0) then
    Exit;

  Idx := 0;
  while (Text^ <> #0) and (Idx < WideOffset) do // Idx 0 开始，WideOffset 1 开始，所以用 <
  begin
    if Ord(Text^) > $FF then
      Inc(Result, SizeOf(WideChar))
    else
      Inc(Result, SizeOf(AnsiChar));
    Inc(Text);
    Inc(Idx);
  end;
end;

// 计算 Unicode 宽字符串从 1 到 WideOffset 的子串的 Ansi 长度，WideOffset 从 1 开始。
function CalcAnsiDisplayLengthFromWideStringOffset(Text: PWideChar; WideOffset: Integer;
  Calculator: TCnWideCharDisplayWideLengthCalculator): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text = nil) or (WideOffset <= 0) then
    Exit;

  Idx := 0;
  if not Assigned(Calculator) then
    Calculator := @WideCharIsWideLength;

  while (Text^ <> #0) and (Idx < WideOffset) do // Idx 0 开始，WideOffset 1 开始，所以用 <
  begin
    if Calculator(Text^) then
      Inc(Result, SizeOf(WideChar))
    else
      Inc(Result, SizeOf(AnsiChar));
    Inc(Text);
    Inc(Idx);
  end;
end;

function CalcWideStringByteLengthFromAnsiOffset(Text: PWideChar;
  AnsiOffset: Integer; AllowExceedEnd: Boolean): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text <> nil) and (AnsiOffset > 0) then
  begin
    Idx := 0;
    while (Text^ <> #0) and (Idx < AnsiOffset) do
    begin
      if Ord(Text^) > $FF then
        Inc(Idx, SizeOf(WideChar))
      else
        Inc(Idx, SizeOf(AnsiChar));
      Inc(Text);
      Inc(Result);
    end;

    if AllowExceedEnd and (Text^ = #0) and (Idx < AnsiOffset) then
      Inc(Result, AnsiOffset - Idx);
  end;
end;

function CalcWideStringDisplayLengthFromAnsiOffset(Text: PWideChar; AnsiOffset: Integer;
  AllowExceedEnd: Boolean; Calculator: TCnWideCharDisplayWideLengthCalculator): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text <> nil) and (AnsiOffset > 0) then
  begin
    Idx := 0;
    if not Assigned(Calculator) then
      Calculator := @WideCharIsWideLength;

    while (Text^ <> #0) and (Idx < AnsiOffset) do
    begin
      if Calculator(Text^) then
        Inc(Idx, SizeOf(WideChar))
      else
        Inc(Idx, SizeOf(AnsiChar));
      Inc(Text);
      Inc(Result);
    end;

    if AllowExceedEnd and (Text^ = #0) and (Idx < AnsiOffset) then
      Inc(Result, AnsiOffset - Idx);
  end;
end;

// 计算 Unicode 宽字符串转成显示相关的 Ansi 后从 1 到 AnsiOffset 的子串的 UTF-8 长度，AnsiDisplayOffset 从 1 开始
function CalcUtf8LengthFromWideStringAnsiDisplayOffset(Text: PWideChar;
  AnsiDisplayOffset: Integer; Calculator: TCnWideCharDisplayWideLengthCalculator): Integer;
var
  Idx: Integer;
begin
  Result := 0;
  if (Text <> nil) and (AnsiDisplayOffset > 0) then
  begin
    Idx := 0;
    if not Assigned(Calculator) then
      Calculator := @WideCharIsWideLength;

    while (Text^ <> #0) and (Idx < AnsiDisplayOffset) do // Idx 0 开始，AnsiDisplayOffset 1 开始，所以用 <
    begin
      Inc(Result, CalcUtf8LengthFromWideChar(Text^));
      Inc(Text);
      if Calculator(Text^) then
        Inc(Idx, SizeOf(WideChar))
      else
        Inc(Idx, SizeOf(AnsiChar));
    end;
  end;
end;

// 手动将宽字符串转换成 Ansi，把其中的宽字符都替换成两个 AlterChar，用于纯英文环境下的字符宽度计算
function ConvertUtf16ToAlterDisplayAnsi(WideText: PWideChar; AlterChar: AnsiChar;
  Calculator: TCnWideCharDisplayWideLengthCalculator): AnsiString;
var
  Len: Integer;
begin
  if WideText = nil then
  begin
    Result := '';
    Exit;
  end;

{$IFDEF UNICODE}
  Len := StrLen(WideText);
{$ELSE}
  Len := Length(WideString(WideText));
{$ENDIF}

  if Len = 0 then
  begin
    Result := '';
    Exit;
  end;

  SetLength(Result, Len * SizeOf(WideChar));

  if not Assigned(Calculator) then
    Calculator := @WideCharIsWideLength;

  Len := 0;
  while WideText^ <> #0 do
  begin
    if Calculator(WideText^) then
    begin
      Inc(Len);
      Result[Len] := AlterChar;
      Inc(Len);
      Result[Len] := AlterChar;
    end
    else
    begin
      Inc(Len);
      if Ord(WideText^) <= $FF then // Absolutely 'Single' Char
        Result[Len] := AnsiChar(WideText^)
      else                          // Extended 'Single' Char, Replace
        Result[Len] := AlterChar;
    end;
    Inc(WideText);
  end;
  SetLength(Result, Len);
end;

// 手动将 UTF-8 字符串转换成 Ansi，把其中的宽字符都替换成两个 AlterChar，用于纯英文环境下的字符宽度计算
function ConvertUtf8ToAlterDisplayAnsi(Utf8Text: PAnsiChar; AlterChar: AnsiChar;
  Calculator: TCnWideCharDisplayWideLengthCalculator): AnsiString;
var
  I, J, Len, ByteCount: Integer;
  C: AnsiChar;
  W: Word;
  B, B1, B2: Byte;
begin
  Result := '';
  if Utf8Text = nil then
    Exit;

  Len := StrLen(Utf8Text);
  if Len = 0 then
    Exit;

  SetLength(Result, Len); // 不会比原文长，先设较长
  I := 0;
  J := 1;

  if not Assigned(Calculator) then
    Calculator := @WideCharIsWideLength;

  while I < Len do
  begin
    C := Utf8Text[I];
    B := Ord(C);
    W := 0;

    // 根据 B 的值得出这个字符占多少位
    if B and $80 = 0 then  // 0xxx xxxx
      ByteCount := 1
    else if B and $E0 = $C0 then // 110x xxxx 10xxxxxx
      ByteCount := 2
    else if B and $F0 = $E0 then // 1110 xxxx 10xxxxxx 10xxxxxx
      ByteCount := 3
    else if B and $F8 = $F0 then // 1111 0xxx 10xxxxxx 10xxxxxx 10xxxxxx
      ByteCount := 4
    else
      raise ECnWideStringException.Create(SCnErrorInvalidModeLength);

    // 再计算出相应的宽字节字符
    case ByteCount of
      1:
      begin
        W := B and $7F;
      end;
      2:
      begin
        B1 := Ord(Utf8Text[I + 1]);
        W := ((B and $1F) shl 6) or (B1 and $3F);
      end;
      3:
      begin
        B1 := Ord(Utf8Text[I + 1]);
        B2 := Ord(Utf8Text[I + 2]);
        W := ((B and $0F) shl 12) or ((B1 and $3F) shl 6) or (B2 and $3F);
      end;
    end;

    if ByteCount = 4 then
    begin
      // 四字节 UTF8，铁定转为俩 WideChar，也就是四个字符
      // TODO: 但是显示宽度未必，很可能是生僻字那种正常俩字符
      Result[J] := AlterChar;
      Inc(J);
      Result[J] := AlterChar;
      Inc(J);
      Result[J] := AlterChar;
      Inc(J);
      Result[J] := AlterChar;
      Inc(J);
    end
    else if Calculator(WideChar(W)) then // 3 字节 UTF8，判断实际宽度
    begin
      Result[J] := AlterChar;
      Inc(J);
      Result[J] := AlterChar;
      Inc(J);
    end
    else
    begin
      if W <= 255 then
        Result[J] := AnsiChar(W)
      else
        Result[J] := AlterChar;
      Inc(J);
    end;

    Inc(I, ByteCount);
  end;

  SetLength(Result, J - 1); // Inc 的 J 是准备给下一个字符的，没了就减一
end;

function CnUtf8ToAnsi(const Text: AnsiString): AnsiString;
begin
{$IFDEF FPC}
  {$IFDEF LAZARUS}
  Result := ConvertEncoding(Text, EncodingUTF8, EncodingAnsi);
  {$ELSE}
  Result := Utf8ToAnsi(Text);
  {$ENDIF}
{$ELSE}
{$IFDEF UNICODE}
  Result := AnsiString(UTF8ToUnicodeString(PAnsiChar(Text)));
{$ELSE}
  {$IFDEF COMPILER6_UP}
  Result := Utf8ToAnsi(Text);
  {$ELSE}
  Result := AnsiString(CnUtf8DecodeToWideString(Text));
  {$ENDIF}
{$ENDIF}
{$ENDIF}
end;

function CnUtf8ToAnsi2(const Text: string): string;
begin
{$IFDEF FPC}
  {$IFDEF LAZARUS}
  Result := ConvertEncoding(Text, EncodingUTF8, EncodingAnsi);
  {$ELSE}
  Result := Utf8ToAnsi(Text);
  {$ENDIF}
{$ELSE}
{$IFDEF UNICODE}
  Result := UTF8ToUnicodeString(PAnsiChar(AnsiString(Text)));
{$ELSE}
  {$IFDEF COMPILER6_UP}
  Result := Utf8ToAnsi(Text);
  {$ELSE}
  Result := AnsiString(CnUtf8DecodeToWideString(Text));
  {$ENDIF}
{$ENDIF}
{$ENDIF}
end;

function CnAnsiToUtf8(const Text: AnsiString): AnsiString;
begin
{$IFDEF FPC}
  {$IFDEF LAZARUS}
  Result := ConvertEncoding(Text, EncodingAnsi, EncodingUTF8);
  {$ELSE}
  Result := AnsiToUtf8(Text);
  {$ENDIF}
{$ELSE}
{$IFDEF UNICODE}
  Result := AnsiString(Utf8Encode(Text)); // 返回值不可改为 UTF8String 类型，否则此处转换无效
{$ELSE}
  {$IFDEF COMPILER6_UP}
  Result := AnsiToUtf8(Text);
  {$ELSE}
  Result := CnUtf8EncodeWideString(WideString(Text));
  {$ENDIF}
{$ENDIF}
{$ENDIF}
end;

function CnAnsiToUtf82(const Text: string): string;
begin
{$IFDEF FPC}
  {$IFDEF LAZARUS}
  Result := ConvertEncoding(Text, EncodingAnsi, EncodingUTF8);
  {$ELSE}
  Result := AnsiToUtf8(Text);
  {$ENDIF}
{$ELSE}
{$IFDEF UNICODE}
  Result := string(Utf8Encode(Text));
{$ELSE}
  {$IFDEF COMPILER6_UP}
  Result := AnsiToUtf8(Text);
  {$ELSE}
  Result := CnUtf8EncodeWideString(WideString(Text));
  {$ENDIF}
{$ENDIF}
{$ENDIF}
end;

// ===================== TCnFileEncoding 相关实现 ==============================

function CnDetectFileEncoding(const Bytes: TBytes): TCnFileEncoding;
begin
  Result := cfeUnknown;
  if Length(Bytes) = 0 then Exit;

  // 检查 BOM
  if Length(Bytes) >= 3 then
  begin
    if (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    begin
      Result := cfeUtf8Bom;
      Exit;
    end;
  end;

  if Length(Bytes) >= 2 then
  begin
    if (Bytes[0] = $FF) and (Bytes[1] = $FE) then
    begin
      Result := cfeUtf16LE;
      Exit;
    end;
    if (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    begin
      Result := cfeUtf16BE;
      Exit;
    end;
  end;

  // 无 BOM，启发式检测 UTF-8
  if CnIsValidUtf8(Bytes) then
    Result := cfeUtf8
  else
    Result := cfeAnsi;
end;

function CnIsValidUtf8(const Bytes: TBytes): Boolean;
var
  I, Len, Remain: Integer;
  B: Byte;
begin
  Result := True;
  Len := Length(Bytes);
  I := 0;
  while I < Len do
  begin
    B := Bytes[I];
    if B and $80 = 0 then
      // 单字节: 0xxxxxxx
      Inc(I)
    else if B and $E0 = $C0 then
    begin
      // 双字节: 110xxxxx 10xxxxxx
      Inc(I);
      Remain := 1;
    end
    else if B and $F0 = $E0 then
    begin
      // 三字节: 1110xxxx 10xxxxxx 10xxxxxx
      Inc(I);
      Remain := 2;
    end
    else if B and $F8 = $F0 then
    begin
      // 四字节: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      Inc(I);
      Remain := 3;
    end
    else
    begin
      // 无效前缀
      Result := False;
      Exit;
    end;

    // 检查后续字节是否都是 10xxxxxx
    while (Remain > 0) and (I < Len) do
    begin
      if Bytes[I] and $C0 <> $80 then
      begin
        Result := False;
        Exit;
      end;
      Inc(I);
      Dec(Remain);
    end;

    // 字节不足
    if Remain > 0 then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function CnStripBomBytes(const Bytes: TBytes): TBytes;
var
  Offset: Integer;
begin
  Offset := 0;
  if Length(Bytes) >= 3 then
  begin
    if (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
      Offset := 3;
  end;
  if (Offset = 0) and (Length(Bytes) >= 2) then
  begin
    if ((Bytes[0] = $FF) and (Bytes[1] = $FE))
      or ((Bytes[0] = $FE) and (Bytes[1] = $FF)) then
      Offset := 2;
  end;

  if Offset > 0 then
  begin
    SetLength(Result, Length(Bytes) - Offset);
    if Length(Result) > 0 then
      Move(Bytes[Offset], Result[0], Length(Result));
  end
  else
    Result := Copy(Bytes);
end;

// ================= TBytes 与 string 之间的转换实现 ===========================

function CnUtf8BytesToString(const Bytes: TBytes): string;
var
  Utf8Str: AnsiString;
begin
  SetLength(Utf8Str, Length(Bytes));
  if Length(Bytes) > 0 then
    Move(Bytes[0], Utf8Str[1], Length(Bytes));
  Result := string(CnUtf8DecodeToWideString(Utf8Str));
end;

function CnStringToUtf8Bytes(const S: string): TBytes;
var
  Utf8Str: AnsiString;
begin
  Utf8Str := CnUtf8EncodeWideString(TCnWideString(S));
  SetLength(Result, Length(Utf8Str));
  if Length(Utf8Str) > 0 then
    Move(Utf8Str[1], Result[0], Length(Utf8Str));
end;

end.
