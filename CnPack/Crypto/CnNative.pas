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

unit CnNative;
{* |<PRE>
================================================================================
* 软件名称：CnPack 组件包
* 单元名称：32 位和 64 位及跨平台的一些统一声明以及一大批基础函数的实现单元
* 单元作者：CnPack 开发组 (master@cnpack.org)
* 备    注：本单元包括一批 32 位和 64 位及跨平台的一些统一声明与实现。
*           Delphi XE 2 支持 32 和 64 以来，开放出的 NativeInt 和 NativeUInt 随
*           当前是 32 位还是 64 而动态变化，影响到的是 Pointer、Reference等东西。
*           考虑到兼容性，固定长度的 32 位 Cardinal/Integer 等和 Pointer 这些就
*           不能再通用了，即使 32 位下也被编译器禁止。因此本单元声明了几个类型，
*           供同时在低版本和高版本的 Delphi 中使用。
*
*           本单元也包括在不支持 UInt64 的编译器 Delphi 5/6/7 下用 Int64 模拟 UInt64
*           的各类运算，加减天然支持，但乘除需要模拟 div 与 mod。
*           地址运算 Integer(APtr) 在 64 位下尤其是 MacOS 上容易出现截断，需要用 NativeInt。
*
*           另外实现了大小端相关、字节数组转换、固定耗时等方面的大量底层函数与工具类。
*
* 开发平台：PWin2000 + Delphi 5.0
* 兼容测试：PWin9X/2000/XP + Delphi 5/6/7 XE 2
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2023.08.14 V2.4
*               补上几个时间固定的函数并改名
*           2022.11.11 V2.3
*               补上几个无符号整数的字节顺序调换函数
*           2022.07.23 V2.2
*               增加几个内存位运算函数与二进制转换字符串函数，并改名为 CnNative
*           2022.06.08 V2.1
*               增加四个时间固定的交换函数以及内存倒排函数
*           2022.03.14 V2.0
*               增加几个十六进制转换函数
*           2022.02.17 V1.9
*               增加 FPC 的编译支持
*           2022.02.09 V1.8
*               加入运行期的大小端判断函数
*           2021.09.05 V1.7
*               加入 Int64/UInt64 的整数次幂与根的运算函数
*           2020.10.28 V1.6
*               加入 UInt64 溢出相关的判断与运算函数
*           2020.09.06 V1.5
*               加入求 UInt64 整数平方根的函数
*           2020.07.01 V1.5
*               加入判断 32 位与 64 位有无符号整数相加是否溢出的函数
*           2020.06.20 V1.4
*               加入 32 位与 64 位获取最高与最低的 1 位位置的函数
*           2020.01.01 V1.3
*               加入 32 位无符号整型的 mul 运算，在不支持 UInt64 的系统上以 Int64 代替以避免溢出
*           2018.06.05 V1.2
*               加入 64 位整型的 div/mod 运算，在不支持 UInt64 的系统上以 Int64 代替 
*           2016.09.27 V1.1
*               加入 64 位整型的一些定义
*           2011.07.06 V1.0
*               创建单元，实现功能
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  Classes, SysUtils, SysConst, Math {$IFDEF COMPILER5}, Windows {$ENDIF};
                                    // D5 下需要引用 Windows 中的 PByte 等
type
  ECnNativeException = class(Exception);
  {* Native 相关异常}

{$IFDEF COMPILER5}
  PByte = Windows.PByte;
  {* D5 下 PByte 定义在 Windows 中，其他版本定义在 System 中，
    这里统一一下供外界使用 PByte 时无需 uses Windows，以有利于跨平台，以下同}
  PWord     = Windows.PWord;
  {* D5 下 PWord 定义在 Windows 中}
  PShortInt = Windows.PShortInt;
  {* D5 下 PShortInt 定义在 Windows 中}
  PSmallInt = Windows.PSmallInt;
  {* D5 下 PSmallInt 定义在 Windows 中}
  PInteger  = Windows.PInteger;
  {* D5 下 PInteger 定义在 Windows 中}
  PSingle   = Windows.PSingle;
  {* D5 下 PSingle 定义在 Windows 中}
  PDouble   = Windows.PDouble;
  {* D5 下 PDouble 定义在 Windows 中}

  PCardinal = ^Cardinal;
  {* D5 下 System 单元中未定义 Cardinal 指针类型，定义上}
  PBoolean = ^Boolean;
  {* D5 下 System 单元中未定义 Boolean 指针类型，定义上}
{$ENDIF}

{$IFDEF BCB5OR6}
  PInt64 = ^Int64;
  {* C++Builder 5/6 的 sysmac.h 里没有 PInt64 的定义（有的 PUINT64 大小写不同，不算）}
{$ENDIF}

{$IFDEF SUPPORT_32_AND_64}
  TCnNativeInt     = NativeInt;
  {* 统一定义 32 位和 64 位下通用的有符号整数类型}
  TCnNativeUInt    = NativeUInt;
  {* 统一定义 32 位和 64 位下通用的无符号整数类型}
  TCnNativePointer = NativeInt;
  {* 统一定义 32 位和 64 位下通用的指针类型}
  TCnNativeIntPtr  = PNativeInt;
  {* 统一定义 32 位和 64 位下通用的指向有符号整数的指针类型}
  TCnNativeUIntPtr = PNativeUInt;
  {* 统一定义 32 位和 64 位下通用的指向无符号整数的指针类型}
{$ELSE}
  TCnNativeInt     = Integer;
  {* 统一定义 32 位和 64 位下通用的有符号整数类型}
  TCnNativeUInt    = Cardinal;
  {* 统一定义 32 位和 64 位下通用的无符号整数类型}
  TCnNativePointer = Integer;
  {* 统一定义 32 位和 64 位下通用的指针类型}
  TCnNativeIntPtr  = PInteger;
  {* 统一定义 32 位和 64 位下通用的指向有符号整数的指针类型}
  TCnNativeUIntPtr = PCardinal;
  {* 统一定义 32 位和 64 位下通用的指向无符号整数的指针类型}
{$ENDIF}
  PCnNativeInt = ^TCnNativeInt;
  {* 指向统一定义 32 位和 64 位下通用的有符号整数类型的指针}
  PCnNativeUInt = ^TCnNativeUInt;
  {* 指向统一定义 32 位和 64 位下通用的无符号整数类型的指针}
{$IFDEF FPC}
  TCnHashCode      = PtrInt;
  {* 统一定义 Delphi 和 FPC 下的 HashCode 类型}
{$ELSE}
  TCnHashCode      = Integer;
  {* 统一定义 Delphi 和 FPC 下的 HashCode 类型}
{$ENDIF}

  // 供进行地址加减运算的类型，考虑了 FPC 和 Delphi 下对符号的要求
{$IFDEF FPC}
  TCnIntAddress    = NativeUInt;
  {* 统一定义 Delphi 和 FPC 下的供进行地址加减运算的类型}
{$ELSE}
  {$IFDEF SUPPORT_32_AND_64}
  TCnIntAddress    = NativeInt;
  {* 统一定义 Delphi 和 FPC 下的供进行地址加减运算的类型}
  {$ELSE}
  TCnIntAddress    = Integer;
  {* 统一定义 Delphi 和 FPC 下的供进行地址加减运算的类型}
  {$ENDIF}
{$ENDIF}

{$IFDEF CPU64BITS}
  TCnUInt64        = NativeUInt;
  {* 统一定义 64 位无符号整数类型}
  TCnInt64         = NativeInt;
  {* 统一定义 64 位有符号整数类型}
{$ELSE}
  {$IFDEF SUPPORT_UINT64}
  TCnUInt64        = UInt64;
  {* 统一定义 64 位无符号整数类型}
  {$ELSE}
  TCnUInt64 = packed record
  {* 在不支持 UInt64 的 32 位环境下，定义 64 位无符号整数结构}
    case Boolean of
      True:  (Value: Int64);
      False: (Lo32, Hi32: Cardinal);
  end;
  {$ENDIF}
  TCnInt64         = Int64;
  {* 统一定义 64 位有无符号整数类型}
{$ENDIF}

// TUInt64 用于 cnvcl 库中不支持 UInt64 的运算如 div mod 等
{$IFDEF SUPPORT_UINT64}
  TUInt64          = UInt64;
  {* 统一定义 64 位无符号整数类型}
  {$IFNDEF SUPPORT_PUINT64}
  PUInt64          = ^UInt64;
  {* 统一定义指向 64 位无符号整数的指针类型}
  {$ENDIF}
{$ELSE}
  TUInt64          = Int64;
  {* 统一定义 64 位无符号整数类型，用于 cnvcl 库中不支持 UInt64 的运算}
  PUInt64          = ^TUInt64;
  {* 统一定义指向 64 位无符号整数的指针类型，用于 cnvcl 库中不支持 UInt64 的运算}
{$ENDIF}

{$IFNDEF SUPPORT_INT64ARRAY}
  Int64Array  = array[0..$0FFFFFFE] of Int64;
  {* 如果系统没有定义 Int64Array 则定义上 64 位有符号数组}
  PInt64Array = ^Int64Array;
  {* 如果系统没有定义 PInt64Array 则定义上 64 位有符号数组指针}
{$ENDIF}

  TUInt64Array = array of TUInt64;
  {* 统一定义 64 位无符号整数动态数组，注意这个动态数组声明似乎容易和静态数组声明有冲突}
  ExtendedArray = array[0..65537] of Extended;
  {* 扩展精度浮点数数组}
  PExtendedArray = ^ExtendedArray;
  {* 扩展精度浮点数数组指针}

  PCnWord16Array = ^TCnWord16Array;
  {* 16 位无符号整数数组指针}
  TCnWord16Array = array [0..0] of Word;
  {* 16 位无符号整数数组}

{$IFDEF POSIX64}
  TCnLongWord32 = Cardinal;
  {* 统一定义 32 位无符号 LongWord，因为 Linux64/MacOS64 或 POSIX64 下面 LongWord 竟然是 64 位无符号数}
{$ELSE}
  TCnLongWord32 = LongWord;
  {* 统一定义 32 位无符号 LongWord}
{$ENDIF}
  PCnLongWord32 = ^TCnLongWord32;
  {* 统一定义指向 32 位无符号 LongWord 的指针}

  TCnLongWord32Array = array [0..MaxInt div SizeOf(Integer) - 1] of TCnLongWord32;
  {* 统一定义 32 位无符号 LongWord 数组}

  PCnLongWord32Array = ^TCnLongWord32Array;
  {* 统一定义 32 位无符号 LongWord 数组指针}

{$IFNDEF TBYTES_DEFINED}
  TBytes = array of Byte;
  {* 无符号字节动态数组，未定义时定义上}
{$ENDIF}

  TShortInts = array of ShortInt;
  {* 有符号字节动态数组}

  TSmallInts = array of SmallInt;
  {* 有符号双字节动态数组}

  TWords = array of Word;
  {* 无符号双字节动态数组}

  TIntegers = array of Integer;
  {* 有符号四字节动态数组}

  TCardinals = array of Cardinal;
  {* 无符号四字节动态数组}

  TBooleans = array of Boolean;
  {* 布尔动态数组}

  PCnByte = ^Byte;
  {* 指向 8 位无符号数的指针类型}
  PCnWord = ^Word;
  {* 指向 16 位无符号数的指针类型}

  TCnBitOperation = (boAnd, boOr, boXor, boNot);
  {* 位操作类型}

  // 供我们使用的静态有符号无符号数组类型
  PCnInt8Array = ^TCnInt8Array;
  {* 静态 8 位有符号整数数组指针}
  TCnInt8Array = array[0..(MaxInt div SizeOf(ShortInt) - 1)] of ShortInt;
  {* 静态 8 位有符号整数数组}

  PCnUInt8Array = ^TCnUInt8Array;
  {* 静态 8 位无符号整数数组指针}
  TCnUInt8Array = array[0..(MaxInt div SizeOf(Byte) - 1)] of Byte;
  {* 静态 8 位无符号整数数组}

  PCnInt16Array = ^TCnInt16Array;
  {* 静态 16 位有符号整数数组指针}
  TCnInt16Array = array[0..(MaxInt div SizeOf(SmallInt) - 1)] of SmallInt;
  {* 静态 16 位有符号整数数组}

  PCnUInt16Array = ^TCnUInt16Array;
  {* 静态 16 位无符号整数数组指针}
  TCnUInt16Array = array[0..(MaxInt div SizeOf(Word) - 1)] of Word;
  {* 静态 16 位无符号整数数组}

  PCnInt32Array = ^TCnInt32Array;
  {* 静态 32 位有符号整数数组指针}
  TCnInt32Array = array[0..(MaxInt div SizeOf(Integer) - 1)] of Integer;
  {* 静态 32 位有符号整数数组}

  PCnUInt32Array = ^TCnUInt32Array;
  {* 静态 32 位无符号整数数组指针}
  TCnUInt32Array = array[0..(MaxInt div SizeOf(Cardinal) - 1)] of Cardinal;
  {* 静态 32 位无符号整数数组}

  PCnInt64Array = ^TCnInt64Array;
  {* 静态 64 位有符号整数数组指针}
  TCnInt64Array = array[0..(MaxInt div SizeOf(Int64) - 1)] of Int64;
  {* 静态 64 位有符号整数数组}

  PCnUInt64Array = ^TCnUInt64Array;
  {* 静态 64 位无符号整数数组指针}
  TCnUInt64Array = array[0..(MaxInt div SizeOf(TUInt64) - 1)] of TUInt64;
  {* 静态 64 位无符号整数数组}

type
  TCnMemSortCompareProc = function (P1, P2: Pointer; ElementByteSize: Integer): Integer;
  {* 内存固定块尺寸的数组排序比较函数原型}

const
  CN_MAX_SQRT_INT64: Cardinal               = 3037000499;
  {* 64 位有符号数范围内最大的平方根}
  CN_MAX_INT8: ShortInt                     = $7F;
  {* 最大的 8 位有符号数}
  CN_MIN_INT8: ShortInt                     = -128;
  {* 最小的 8 位有符号数}
  CN_MAX_INT16: SmallInt                    = $7FFF;
  {* 最大的 16 位有符号数}
  CN_MIN_INT16: SmallInt                    = -32768;
  {* 最小的 16 位有符号数}
  CN_MAX_INT32: Integer                     = $7FFFFFFF;
  {* 最大的 32 位有符号数}
{$WARNINGS OFF}
  CN_MIN_INT32: Integer                     = $80000000;
  {* 最小的 32 位有符号数 -2147483648}
  // 会出编译警告，但写 -2147483648 会出错
{$WARNINGS ON}
  CN_MIN_INT32_IN_INT64: Int64              = $0000000080000000;
  {* 64 位有符号数范围内最小的 32 位有符号数 -2147483648}
  CN_MAX_INT64: Int64                       = $7FFFFFFFFFFFFFFF;
  {* 最大的 64 位有符号数}
  CN_MIN_INT64: Int64                       = $8000000000000000;
  {* 最小的 64 位有符号数}
  CN_MAX_UINT8: Byte                        = $FF;
  {* 最大的 8 位无符号数}
  CN_MAX_UINT16: Word                       = $FFFF;
  {* 最大的 16 位无符号数}
  CN_MAX_UINT32: Cardinal                   = $FFFFFFFF;
  {* 最大的 32 位无符号数}
  CN_MAX_TUINT64: TUInt64                   = $FFFFFFFFFFFFFFFF;
  {* 最大的 64 位无符号数}
  CN_MAX_SIGNED_INT64_IN_TUINT64: TUInt64   = $7FFFFFFFFFFFFFFF;
  {* 64 位无符号数范围内最大的 64 位有符号数}

{*
  对于 D567 等不支持 UInt64 的编译器，虽然可以用 Int64 代替 UInt64 进行加减、存储
  但乘除运算则无法直接完成，这里封装了两个调用 System 库中的 _lludiv 与 _llumod
  函数，实现以 Int64 表示的 UInt64 数据的 div 与 mod 功能。
}
function UInt64Mod(A: TUInt64; B: TUInt64): TUInt64;
{* 两个 64 位无符号整数求余。

   参数：
     A: TUInt64                           - 被除数
     B: TUInt64                           - 除数

   返回值：TUInt64                        - 余数
}

function UInt64Div(A: TUInt64; B: TUInt64): TUInt64;
{* 两个 64 位无符号整数整除。

   参数：
     A: TUInt64                           - 被除数
     B: TUInt64                           - 除数

   返回值：TUInt64                        - 整商
}

function UInt64Mul(A: Cardinal; B: Cardinal): TUInt64;
{* 两个 32 位无符号整数不溢出的相乘。在不支持 UInt64 的平台上，结果以 UInt64 的形式放在 Int64 里，
   如果结果直接使用 Int64 计算则有可能溢出。

   参数：
     A: Cardinal                          - 乘数一
     B: Cardinal                          - 乘数二

   返回值：TUInt64                        - 积
}

procedure UInt64AddUInt64(A: TUInt64; B: TUInt64; var ResLo: TUInt64; var ResHi: TUInt64);
{* 两个 64 位无符号整数相加，处理溢出的情况，结果放 ResLo 与 ResHi 中。
   注：内部实现按算法来看较为复杂，实际上如果溢出，ResHi 必然是 1，直接判断溢出并将其设 1 即可

   参数：
     A: TUInt64                           - 乘数一
     B: TUInt64                           - 乘数二
     var ResLo: TUInt64                   - 和低位
     var ResHi: TUInt64                   - 和高位

   返回值：（无）
}

procedure UInt64MulUInt64(A: TUInt64; B: TUInt64; var ResLo: TUInt64; var ResHi: TUInt64);
{* 两个64 位无符号整数相乘，结果放 ResLo 与 ResHi 中。Win 64 位下用汇编实现，提速约一倍以上。

   参数：
     A: TUInt64                           - 乘数一
     B: TUInt64                           - 乘数二
     var ResLo: TUInt64                   - 积低位
     var ResHi: TUInt64                   - 积高位

   返回值：（无）
}

function UInt64ToHex(N: TUInt64; RemoveZeroPrefix: Boolean = False): string;
{* 将 64 位无符号整数转换为十六进制字符串。

   参数：
     N: TUInt64                           - 待转换的值
     RemoveZeroPrefix: Boolean            - 是否去除转换结果高位的 0，默认不去除

   返回值：string                         - 返回十六进制字符串
}

function UInt64ToStr(N: TUInt64): string;
{* 将 64 位无符号整数转换为十进制字符串。

   参数：
     N: TUInt64                           - 待转换的值

   返回值：string                         - 返回十进制字符串
}

function StrToUInt64(const S: string): TUInt64;
{* 将字符串转换为 64 位无符号整数。

   参数：
     const S: string                      - 待转换的字符串

   返回值：TUInt64                        - 返回转换结果
}

function UInt64Compare(A: TUInt64; B: TUInt64): Integer;
{* 比较两个 64 位无符号整数值，分别根据比较的结果是大于、等于还是小于来返回 1、0、-1。

   参数：
     A: TUInt64                           - 待比较的数一
     B: TUInt64                           - 待比较的数二

   返回值：Integer                        - 返回比较结果
}

function UInt64Sqrt(N: TUInt64): TUInt64;
{* 求 64 位无符号整数的平方根的整数部分。

   参数：
     N: TUInt64                           - 待求平方根的数

   返回值：TUInt64                        - 返回平方根的整数部分
}

function UInt32IsNegative(N: Cardinal): Boolean;
{* 判断 32 位无符号整数被当成 32 位有符号整数时是否小于 0。

   参数：
     N: Cardinal                          - 待判断的值

   返回值：Boolean                        - 返回是否小于 0
}

function UInt64IsNegative(N: TUInt64): Boolean;
{* 判断 64 位无符号整数被当成 64 位有符号整数时是否小于 0。

   参数：
     N: TUInt64                           - 待判断的值

   返回值：Boolean                        - 返回是否小于 0
}

procedure UInt64SetBit(var B: TUInt64; Index: Integer);
{* 给 64 位整数的某一位置 1，位 Index 从 0 开始到 63。

   参数：
     var B: TUInt64                       - 待置位的值
     Index: Integer                       - 待置 1 的位序号

   返回值：（无）
}

procedure UInt64ClearBit(var B: TUInt64; Index: Integer);
{* 给 64 位整数的某一位置 0，位 Index 从 0 开始到 63。

   参数：
     var B: TUInt64                       - 待置位的值
     Index: Integer                       - 待置 0 的位序号

   返回值：（无）
}

function GetUInt64BitSet(B: TUInt64; Index: Integer): Boolean;
{* 返回 64 位整数的某一位是否是 1，位 Index 从 0 开始到 63。

   参数：
     B: TUInt64                           - 待判断的值
     Index: Integer                       - 待判断的位序号

   返回值：Boolean                        - 返回该位是否是 1
}

function GetUInt64HighBits(B: TUInt64): Integer;
{* 返回 64 位整数的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1。

   参数：
     B: TUInt64                           - 待判断的值

   返回值：Integer                        - 返回 1 的最高位序号
}

function GetUInt32HighBits(B: Cardinal): Integer;
{* 返回 32 位整数的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1。

   参数：
     B: Cardinal                          - 待判断的值

   返回值：Integer                        - 返回 1 的最高位序号
}

function GetUInt16HighBits(B: Word): Integer;
{* 返回 16 位整数的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1。

   参数：
     B: Word                              - 待判断的值

   返回值：Integer                        - 返回 1 的最高位序号
}

function GetUInt8HighBits(B: Byte): Integer;
{* 返回 8 位整数的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1。

   参数：
     B: Byte                              - 待判断的值

   返回值：Integer                        - 返回 1 的最高位序号
}

function GetUInt64BitLength(B: TUInt64): Integer;
{* 返回 64 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0。

   参数：
     B: TUInt64                           - 待判断的值

   返回值：Integer                        - 返回有效位长度
}

function GetUInt32BitLength(B: Cardinal): Integer;
{* 返回 32 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0。

   参数：
     B: Cardinal                          - 待判断的值

   返回值：Integer                        - 返回有效位长度
}

function GetUInt16BitLength(B: Word): Integer;
{* 返回 16 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0。

   参数：
     B: Word                              - 待判断的值

   返回值：Integer                        - 返回有效位长度
}

function GetUInt8BitLength(B: Byte): Integer;
{* 返回 8 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0。

   参数：
     B: Byte                              - 待判断的值

   返回值：Integer                        - 返回有效位长度
}

function GetUInt64LowBits(B: TUInt64): Integer;
{* 返回 64 位整数的是 1 的最低二进制位是第几位，最低位是 0，基本等同于末尾几个 0。如果没有 1，返回 -1。

   参数：
     B: TUInt64                           - 待判断的值

   返回值：Integer                        - 返回 1 的最低位序号
}

function GetUInt32LowBits(B: Cardinal): Integer;
{* 返回 32 位整数的是 1 的最低二进制位是第几位，最低位是 0，基本等同于末尾几个 0。如果没有 1，返回 -1。

   参数：
     B: Cardinal                          - 待判断的值

   返回值：Integer                        - 返回 1 的最低位序号
}

function GetUInt16LowBits(B: Word): Integer;
{* 返回 16 位整数的是 1 的最低二进制位是第几位，最低位是 0，基本等同于末尾几个 0。如果没有 1，返回 -1。

   参数：
     B: Word                              - 待判断的值

   返回值：Integer                        - 返回 1 的最低位序号
}

function GetUInt8LowBits(B: Byte): Integer;
{* 返回 8 位整数的是 1 的最低二进制位是第几位，最低位是 0，基本等同于末尾几个 0。如果没有 1，返回 -1。

   参数：
     B: Byte                              - 待判断的值

   返回值：Integer                        - 返回 1 的最低位序号
}

function Int64Mod(M: Int64; N: Int64): Int64;
{* 封装的 Int64 Mod，M 碰到负值时取反求模再模减，但 N 仍要求正数否则结果不靠谱。

   参数：
     M: Int64                             - 被除数
     N: Int64                             - 除数

   返回值：Int64                          - 余数
}

function Int64CenterMod(A: Int64; N: Int64): Int64;
{* 将 A 先 mod N 后，中心化到开闭区间 (-(N - 1)/2 的下界（更负）, (N - 1)/ 2 的下界（正数更靠近 0）]，
   要求 N 是正数。注意，中心化并不是将 A mod N 的正值整体左移，而是超出一半的直接减 N。
   这个一半的精确定义是，比 N/2 的整数部分大的，直接减 N，无论 N 是奇数还是偶数。
   关于边界：一句话概括是奇数对称偶往上靠。
   比如 N 是 7 则 [-3, 3]，比 3 大的都减 7，注意 3 不减。
   N 是 6 则 [-2, 3]，比 3 大的都减 6，注意 3 也不减。
   N 为奇数时，(N - 1)是偶数，除以二是整数。数量加上 0 一共 N 个，0 到 N - 1，映射到 [-(N - 1)/2, (N - 1)/2]
   N 为偶数时，N/2 是偶数，左边界 -N/2 + 1，右边界 N/2，0 到 N - 1，映射到 [-N/2 + 1, N/2]

   参数：
     A: Int64                             - 待中心化的值
     N: Int64                             - 模数

   返回值：Int64                          - 返回中心化结果
}

function IsUInt32PowerOf2(N: Cardinal): Boolean;
{* 判断一 32 位无符号整数是否 2 的整数次幂。

   参数：
     N: Cardinal                          - 待判断的值

   返回值：Boolean                        - 返回是否是 2 的整数次幂
}

function IsUInt64PowerOf2(N: TUInt64): Boolean;
{* 判断一 64 位无符号整数是否 2 的整数次幂。

   参数：
     N: TUInt64                           - 待判断的值

   返回值：Boolean                        - 返回是否是 2 的整数次幂
}

function GetUInt32PowerOf2GreaterEqual(N: Cardinal): Cardinal;
{* 得到一比指定 32 位无符号整数大或等的 2 的整数次幂，如溢出则返回 0

   参数：
     N: Cardinal                          - 待计算的值

   返回值：Cardinal                       - 返回符合条件的 2 的整数次幂或 0
}

function GetUInt64PowerOf2GreaterEqual(N: TUInt64): TUInt64;
{* 得到一比指定 64 位无符号整数大或等的 2 的整数次幂，如溢出则返回 0

   参数：
     N: TUInt64                           - 待计算的值

   返回值：TUInt64                        - 返回符合条件的 2 的整数次幂或 0
}

function IsInt32AddOverflow(A: Integer; B: Integer): Boolean;
{* 判断两个 32 位有符号整数相加是否溢出 32 位有符号整数上限。

   参数：
     A: Integer                           - 加数一
     B: Integer                           - 加数二

   返回值：Boolean                        - 返回相加是否会溢出
}

function IsUInt32AddOverflow(A: Cardinal; B: Cardinal): Boolean;
{* 判断两个 32 位无符号整数相加是否溢出 32 位无符号整数上限。

   参数：
     A: Cardinal                          - 加数一
     B: Cardinal                          - 加数二

   返回值：Boolean                        - 返回相加是否会溢出
}

function IsInt64AddOverflow(A: Int64; B: Int64): Boolean;
{* 判断两个 64 位有符号整数相加是否溢出 64 位有符号整数上限。

   参数：
     A: Int64                             - 加数一
     B: Int64                             - 加数二

   返回值：Boolean                        - 返回相加是否会溢出
}

function IsUInt64AddOverflow(A: TUInt64; B: TUInt64): Boolean;
{* 判断两个 64 位无符号整数相加是否溢出 64 位无符号整数上限。

   参数：
     A: TUInt64                           - 加数一
     B: TUInt64                           - 加数二

   返回值：Boolean                        - 返回相加是否会溢出
}

function IsUInt64SubOverflowInt32(A: TUInt64; B: TUInt64): Boolean;
{* 判断一个 64 位无符号整数减去另一个 64 位无符号整数的结果是否超出 32 位有符号整数范围，
   可用于 64 位汇编中的 JMP 跳转类型判断。

   参数：
     A: TUInt64                           - 被减数
     B: TUInt64                           - 减数

   返回值：Boolean                        - 返回是否超出 32 位有符号整数范围
}

procedure UInt64Add(var R: TUInt64; A: TUInt64; B: TUInt64; out Carry: Integer);
{* 两个 64 位无符号整数相加，A + B => R，如果有溢出，则溢出的 1 置进位标记里，否则进位标记清零。

   参数：
     var R: TUInt64                       - 和
     A: TUInt64                           - 加数一
     B: TUInt64                           - 加数二
     out Carry: Integer                   - 进位标记

   返回值：（无）
}

procedure UInt64Sub(var R: TUInt64; A: TUInt64; B: TUInt64; out Carry: Integer);
{* 两个 64 位无符号整数相减，A - B => R，如果不够减有借位，则借的 1 置借位标记里，否则借位标记清零。

   参数：
     var R: TUInt64                       - 差
     A: TUInt64                           - 被减数
     B: TUInt64                           - 减数
     out Carry: Integer                   - 借位标记

   返回值：（无）
}

function IsInt32MulOverflow(A: Integer; B: Integer): Boolean;
{* 判断两个 32 位有符号整数相乘是否溢出 32 位有符号整数上限。

   参数：
     A: Integer                           - 乘数一
     B: Integer                           - 乘数二

   返回值：Boolean                        - 返回是否溢出
}

function IsUInt32MulOverflow(A: Cardinal; B: Cardinal): Boolean;
{* 判断两个 32 位无符号整数相乘是否溢出 32 位无符号整数上限

   参数：
     A: Cardinal                          - 乘数一
     B: Cardinal                          - 乘数二

   返回值：Boolean                        - 返回是否溢出
}

function IsUInt32MulOverflowInt64(A: Cardinal; B: Cardinal; out R: TUInt64): Boolean;
{* 判断两个 32 位无符号整数相乘是否溢出 64 位有符号整数上限，如未溢出也即返回 False 时，R 中直接返回结果。
   如溢出也即返回 True，外界需要重新调用 UInt64Mul 才能实施相乘。

   参数：
     A: Cardinal                          - 乘数一
     B: Cardinal                          - 乘数二
     out R: TUInt64                       - 未溢出时返回积

   返回值：Boolean                        - 返回是否溢出
}

function IsInt64MulOverflow(A: Int64; B: Int64): Boolean;
{* 判断两个 64 位有符号整数相乘是否溢出 64 位有符号整数上限。

   参数：
     A: Int64                             - 乘数一
     B: Int64                             - 乘数二

   返回值：Boolean                        - 返回是否溢出
}

function PointerToInteger(P: Pointer): Integer;
{* 指针类型转换成整型，支持 32/64 位。注意 64 位下可能会丢超出 32 位的内容。

   参数：
     P: Pointer                           - 待转换的指针

   返回值：Integer                        - 返回转换的整数
}

function IntegerToPointer(I: Integer): Pointer;
{* 整型转换成指针类型，支持 32/64 位。

   参数：
     I: Integer                           - 待转换的整型

   返回值：Pointer                        - 返回转换的指针
}

function Int64NonNegativeAddMod(A: Int64; B: Int64; N: Int64): Int64;
{* 求 64 位有符号整数范围内俩加数的和求余，处理溢出的情况，要求 N 大于 0。

   参数：
     A: Int64                             - 加数一
     B: Int64                             - 加数一
     N: Int64                             - 模数

   返回值：Int64                          - 返回相加求余的结果
}

function UInt64NonNegativeAddMod(A: TUInt64; B: TUInt64; N: TUInt64): TUInt64;
{* 求 64 位无符号整数范围内俩加数的和求余，处理溢出的情况，要求 N 大于 0。

   参数：
     A: TUInt64                           - 加数一
     B: TUInt64                           - 加数二
     N: TUInt64                           - 模数

   返回值：TUInt64                        - 返回相加求余的结果
}

function Int64NonNegativeMulMod(A: Int64; B: Int64; N: Int64): Int64;
{* 64 位有符号整数范围内的相乘求余，不能直接计算，容易溢出。要求 N 大于 0。

   参数：
     A: Int64                             - 乘数一
     B: Int64                             - 乘数二
     N: Int64                             - 模数

   返回值：Int64                          - 返回相乘求余的结果
}

function UInt64NonNegativeMulMod(A: TUInt64; B: TUInt64; N: TUInt64): TUInt64;
{* 64 位无符号整数范围内的相乘求余，不能直接计算，容易溢出。

   参数：
     A: TUInt64                           - 乘数一
     B: TUInt64                           - 乘数二
     N: TUInt64                           - 模数

   返回值：TUInt64                        - 返回相乘求余的结果
}

function Int64NonNegativeMod(N: Int64; P: Int64): Int64;
{* 封装的 64 位有符号整数的非负求余函数，也就是余数为负时，加个除数变正，调用者需保证 P 大于 0。

   参数：
     N: Int64                             - 被除数
     P: Int64                             - 除数

   返回值：Int64                          - 返回非负求余的结果
}

function Int64NonNegativPower(N: Int64; Exp: Integer): Int64;
{* 求 64 位有符号整数的非负整数指数幂，不考虑溢出的情况。

   参数：
     N: Int64                             - 底数
     Exp: Integer                         - 指数，要求正数或 0

   返回值：Int64                          - 返回幂的结果
}

function Int64NonNegativeRoot(N: Int64; Exp: Integer): Int64;
{* 求 64 位有符号整数的非负整数次方根的整数部分，不考虑溢出的情况。

   参数：
     N: Int64                             - 底数
     Exp: Integer                         - 方根次数

   返回值：Int64                          - 返回开方的整数部分结果
}

function UInt64NonNegativPower(N: TUInt64; Exp: Integer): TUInt64;
{* 求 64 位无符号整数的非负整数指数幂，不考虑溢出的情况。

   参数：
     N: TUInt64                           - 底数
     Exp: Integer                         - 指数，要求正数或 0

   返回值：TUInt64                        - 返回幂的结果
}

function UInt64NonNegativeRoot(N: TUInt64; Exp: Integer): TUInt64;
{* 求 64 位无符号整数的非负整数次方根的整数部分，不考虑溢出的情况。

   参数：
     N: TUInt64                           - 底数
     Exp: Integer                         - 方根次数

   返回值：TUInt64                        - 返回开方的整数部分结果
}

function CurrentByteOrderIsBigEndian: Boolean;
{* 返回当前运行期环境是否是大端，也就是是否将整数中的高序字节存储在较低的起始地址。
   符合从左到右的阅读习惯，如部分指定的 ARM 和 MIPS。

   参数：
     （无）

   返回值：Boolean                        - 返回当前运行期环境是否是大端
}

function CurrentByteOrderIsLittleEndian: Boolean;
{* 返回当前运行期环境是否是小端，也就是是否将整数中的高序字节存储在较高的起始地址，如 x86 与部分默认 ARM。

   参数：
     （无）

   返回值：Boolean                        - 返回当前运行期环境是否是小端
}

function Int64ToBigEndian(Value: Int64): Int64;
{* 确保 64 位有符号整数值为大端，在小端环境中会进行转换。

   参数：
     Value: Int64                         - 待转换的 64 位有符号整数

   返回值：Int64                          - 返回大端值
}

function Int32ToBigEndian(Value: Integer): Integer;
{* 确保 32 位有符号整数值为大端，在小端环境中会进行转换。

   参数：
     Value: Integer                       - 待转换的 32 位有符号整数

   返回值：Integer                        - 返回大端值
}

function Int16ToBigEndian(Value: SmallInt): SmallInt;
{* 确保 16 位有符号整数值为大端，在小端环境中会进行转换。

   参数：
     Value: SmallInt                      - 待转换的 16 位有符号整数

   返回值：SmallInt                       - 返回大端值
}

function Int64ToLittleEndian(Value: Int64): Int64;
{* 确保 64 位有符号整数值为小端，在大端环境中会进行转换。

   参数：
     Value: Int64                         - 待转换的 64 位有符号整数

   返回值：Int64                          - 返回大端值
}

function Int32ToLittleEndian(Value: Integer): Integer;
{* 确保 32 位有符号整数值为小端，在大端环境中会进行转换。

   参数：
     Value: Integer                       - 待转换的 32 位有符号整数

   返回值：Integer                        - 返回小端值
}

function Int16ToLittleEndian(Value: SmallInt): SmallInt;
{* 确保 16 位有符号整数值为小端，在大端环境中会进行转换。

   参数：
     Value: SmallInt                      - 待转换的 16 位有符号整数

   返回值：SmallInt                       - 返回小端值
}

function UInt64ToBigEndian(Value: TUInt64): TUInt64;
{* 确保 64 位无符号整数值为大端，在小端环境中会进行转换。

   参数：
     Value: TUInt64                       - 待转换的 64 位无符号整数

   返回值：TUInt64                        - 返回大端值
}

function UInt32ToBigEndian(Value: Cardinal): Cardinal;
{* 确保 32 位无符号整数值为大端，在小端环境中会进行转换。

   参数：
     Value: Cardinal                      - 待转换的 32 位无符号整数

   返回值：Cardinal                       - 返回大端值
}

function UInt16ToBigEndian(Value: Word): Word;
{* 确保 16 位无符号整数值为大端，在小端环境中会进行转换。

   参数：
     Value: Word                          - 待转换的 16 位无符号整数

   返回值：Word                           - 返回大端值
}

function UInt64ToLittleEndian(Value: TUInt64): TUInt64;
{* 确保 64 位无符号整数值为小端，在大端环境中会进行转换。

   参数：
     Value: TUInt64                       - 待转换的 64 位无符号整数

   返回值：TUInt64                        - 返回大端值
}

function UInt32ToLittleEndian(Value: Cardinal): Cardinal;
{* 确保 32 位无符号整数值为小端，在大端环境中会进行转换。

   参数：
     Value: Cardinal                      - 待转换的 32 位无符号整数

   返回值：Cardinal                       - 返回小端值
}

function UInt16ToLittleEndian(Value: Word): Word;
{* 确保 16 位无符号整数值为小端，在大端环境中会进行转换。

   参数：
     Value: Word                          - 待转换的 16 位无符号整数

   返回值：Word                           - 返回小端值
}

function Int64HostToNetwork(Value: Int64): Int64;
{* 将 64 位有符号整数值从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。

   参数：
     Value: Int64                         - 待转换的 64 位有符号整数

   返回值：Int64                          - 返回网络字节顺序值
}

function Int32HostToNetwork(Value: Integer): Integer;
{* 将 32 位有符号整数值从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。

   参数：
     Value: Integer                       - 待转换的 32 位有符号整数

   返回值：Integer                        - 返回网络字节顺序值
}

function Int16HostToNetwork(Value: SmallInt): SmallInt;
{* 将 16 位有符号整数值从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。

   参数：
     Value: SmallInt                      - 待转换的 16 位有符号整数

   返回值：SmallInt                       - 返回网络字节顺序值
}

function Int64NetworkToHost(Value: Int64): Int64;
{* 将 64 位有符号整数值从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。

   参数：
     Value: Int64                         - 待转换的 64 位有符号整数

   返回值：Int64                          - 返回主机字节顺序值
}

function Int32NetworkToHost(Value: Integer): Integer;
{* 将 32 位有符号整数值从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。

   参数：
     Value: Integer                       - 待转换的 32 位有符号整数

   返回值：Integer                        - 返回主机字节顺序值
}

function Int16NetworkToHost(Value: SmallInt): SmallInt;
{* 将 16 位有符号整数值从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。

   参数：
     Value: SmallInt                      - 待转换的 16 位有符号整数

   返回值：SmallInt                       - 返回主机字节顺序值
}

function UInt64HostToNetwork(Value: TUInt64): TUInt64;
{* 将 64 位无符号整数值从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。

   参数：
     Value: TUInt64                       - 待转换的 64 位无符号整数

   返回值：TUInt64                        - 返回网络字节顺序值
}

function UInt32HostToNetwork(Value: Cardinal): Cardinal;
{* 将 32 位无符号整数值从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。

   参数：
     Value: Cardinal                      - 待转换的 32 位无符号整数

   返回值：Cardinal                       - 返回网络字节顺序值
}

function UInt16HostToNetwork(Value: Word): Word;
{* 将 16 位无符号整数值从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。

   参数：
     Value: Word                          - 待转换的 16 位无符号整数

   返回值：Word                           - 返回网络字节顺序值
}

function UInt64NetworkToHost(Value: TUInt64): TUInt64;
{* 将 64 位无符号整数值从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。

   参数：
     Value: TUInt64                       - 待转换的 64 位无符号整数

   返回值：TUInt64                        - 返回主机字节顺序值
}

function UInt32NetworkToHost(Value: Cardinal): Cardinal;
{* 将 32 位无符号整数值从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。

   参数：
     Value: Cardinal                      - 待转换的 32 位无符号整数

   返回值：Cardinal                       - 返回主机字节顺序值
}

function UInt16NetworkToHost(Value: Word): Word;
{* 将 16 位无符号整数值从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。

   参数：
     Value: Word                          - 待转换的 16 位无符号整数

   返回值：Word                           - 返回主机字节顺序值
}

procedure MemoryNetworkToHost(Mem: Pointer; MemByteLen: Integer);
{* 将一片内存区域从网络字节顺序转换为主机字节顺序，在小端环境中会进行转换。
   该方法应用场合较少，大多数情况下二、四、八字节转换已经足够。

   参数：
     Mem: Pointer                         - 待转换的数据块地址
     MemByteLen: Integer                  - 待转换的数据块字节长度

   返回值：（无）
}

procedure MemoryHostToNetwork(Mem: Pointer; MemByteLen: Integer);
{* 将一片内存区域从主机字节顺序转换为网络字节顺序，在小端环境中会进行转换。
   该方法应用场合较少，大多数情况下二、四、八字节转换已经足够。

   参数：
     Mem: Pointer                         - 待转换的数据块地址
     MemByteLen: Integer                  - 待转换的数据块字节长度

   返回值：（无）
}

procedure ReverseMemory(Mem: Pointer; MemByteLen: Integer);
{* 按字节顺序倒置一块内存块，字节内部不变。

   参数：
     Mem: Pointer                         - 待倒置的数据块地址
     MemByteLen: Integer                  - 待倒置的数据块字节长度

   返回值：（无）
}

function ReverseBitsInInt8(V: Byte): Byte;
{* 倒置一字节内部的位的内容。

   参数：
     V: Byte                              - 待倒置的一字节

   返回值：Byte                           - 返回倒置值
}

function ReverseBitsInInt16(V: Word): Word;
{* 倒置二字节及其内部位的内容。

   参数：
     V: Word                              - 待倒置的二字节

   返回值：Word                           - 返回倒置值
}

function ReverseBitsInInt32(V: Cardinal): Cardinal;
{* 倒置四字节及其内部位的内容。

   参数：
     V: Cardinal                          - 待倒置的四字节

   返回值：Cardinal                       - 返回倒置值
}

function ReverseBitsInInt64(V: Int64): Int64;
{* 倒置八字节及其内部位的内容。

   参数：
     V: Int64                             - 待倒置的八字节

   返回值：Int64                          - 返回倒置值
}

procedure ReverseMemoryWithBits(Mem: Pointer; MemByteLen: Integer);
{* 按字节顺序倒置一块内存块，并且每个字节也倒过来。

   参数：
     Mem: Pointer                         - 待倒置的数据块地址
     MemByteLen: Integer                  - 待倒置的数据块字节长度

   返回值：（无）
}

procedure MemoryAnd(AMem: Pointer; BMem: Pointer; MemByteLen: Integer; ResMem: Pointer);
{* 两块长度相同的内存 AMem 和 BMem 按位与，结果放 ResMem 中，三者可相同。

   参数：
     AMem: Pointer                        - 待处理的数据块地址一
     BMem: Pointer                        - 待处理的数据块地址二
     MemByteLen: Integer                  - 待处理的数据块字节长度
     ResMem: Pointer                      - 结果数据块地址

   返回值：（无）
}

procedure MemoryOr(AMem: Pointer; BMem: Pointer; MemByteLen: Integer; ResMem: Pointer);
{* 两块长度相同的内存 AMem 和 BMem 按位或，结果放 ResMem 中，三者可相同。

   参数：
     AMem: Pointer                        - 待处理的数据块地址一
     BMem: Pointer                        - 待处理的数据块地址二
     MemByteLen: Integer                  - 待处理的数据块字节长度
     ResMem: Pointer                      - 结果数据块地址

   返回值：（无）
}

procedure MemoryXor(AMem: Pointer; BMem: Pointer; MemByteLen: Integer; ResMem: Pointer);
{* 两块长度相同的内存 AMem 和 BMem 按位异或，结果放 ResMem 中，三者可相同。

   参数：
     AMem: Pointer                        - 待处理的数据块地址一
     BMem: Pointer                        - 待处理的数据块地址二
     MemByteLen: Integer                  - 待处理的数据块字节长度
     ResMem: Pointer                      - 结果数据块地址

   返回值：（无）
}

procedure MemoryNot(Mem: Pointer; MemByteLen: Integer; ResMem: Pointer);
{* 一块内存 AMem 取反，结果放 ResMem 中，两者可相同。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     MemByteLen: Integer                  - 待处理的数据块字节长度
     ResMem: Pointer                      - 结果数据块地址

   返回值：（无）
}

procedure MemoryShiftLeft(AMem: Pointer; BMem: Pointer; MemByteLen: Integer; BitCount: Integer);
{* AMem 整块内存左移 BitCount 位至 BMem，往内存地址低位移，空位补 0，两者可相等。

   参数：
     AMem: Pointer                        - 待处理的数据块地址一
     BMem: Pointer                        - 待处理的数据块地址二
     MemByteLen: Integer                  - 待处理的数据块字节长度
     BitCount: Integer                    - 左移的位数

   返回值：（无）
}

procedure MemoryShiftRight(AMem: Pointer; BMem: Pointer; MemByteLen: Integer; BitCount: Integer);
{* AMem 整块内存右移 BitCount 位至 BMem，往内存地址高位移，空位补 0，两者可相等。

   参数：
     AMem: Pointer                        - 待处理的数据块地址一
     BMem: Pointer                        - 待处理的数据块地址二
     MemByteLen: Integer                  - 待处理的数据块字节长度
     BitCount: Integer                    - 右移的位数

   返回值：（无）
}

function MemoryIsBitSet(Mem: Pointer; N: Integer): Boolean;
{* 返回内存块某 Bit 位是否置 1，内存地址低位是 0，字节内还是右边为 0。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     N: Integer                           - 位索引号

   返回值：Boolean                        - 返回是否是 1
}

procedure MemorySetBit(Mem: Pointer; N: Integer);
{* 给内存块某 Bit 位置 1，内存地址低位是 0，字节内还是右边为 0。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     N: Integer                           - 位索引号

   返回值：（无）
}

procedure MemoryClearBit(Mem: Pointer; N: Integer);
{* 给内存块某 Bit 位置 0，内存地址低位是 0，字节内还是右边为 0。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     N: Integer                           - 位索引号

   返回值：（无）
}

function MemoryGetHighBits(Mem: Pointer; MemByteLen: Integer): Integer;
{* 返回内存块中是 1 的最高二进制位是第几位，“高”指低地址方向。如果没有 1，返回 -1。
   内存块从地址低到高编为 8 * MemByteLen - 1 到 0 这么多位，末字节的最低位是 0 位。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     MemByteLen: Integer                  - 待处理的数据块字节长度

   返回值：Integer                        - 返回 1 的最高位序号
}

function MemoryGetLowBits(Mem: Pointer; MemByteLen: Integer): Integer;
{* 返回内存块中是 1 的最低二进制位是第几位，“低”指高地址方向。如果没有 1，返回 -1。
   内存块从地址低到高编为 8 * MemByteLen - 1 到 0 这么多位，末字节的最低位是 0 位。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     MemByteLen: Integer                  - 待处理的数据块字节长度

   返回值：Integer                        - 返回 1 的最低位序号
}

function MemoryToBinStr(Mem: Pointer; MemByteLen: Integer; Sep: Boolean = False): string;
{* 将一块内存内容从低到高字节顺序输出为二进制字符串，Sep 表示字节之间是否空格分隔。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     MemByteLen: Integer                  - 待处理的数据块字节长度
     Sep: Boolean                         - 字节之间是否用空格分隔

   返回值：string                         - 返回二进制字符串
}

procedure MemorySwap(AMem: Pointer; BMem: Pointer; MemByteLen: Integer);
{* 交换两块相同长度的内存块的内容，如两者是相同的内存块则什么都不做

   参数：
     AMem: Pointer                        - 待处理的数据块地址一
     BMem: Pointer                        - 待处理的数据块地址二
     MemByteLen: Integer                  - 待处理的数据块字节长度

   返回值：（无）
}

function MemoryCompare(AMem: Pointer; BMem: Pointer; MemByteLen: Integer): Integer;
{* 以无符号整数的方式比较两块内存，返回 1、0、-1，如两者是相同的内存块则直接返回 0

   参数：
     AMem: Pointer                        - 待比较的数据块地址一
     BMem: Pointer                        - 待比较的数据块地址二
     MemByteLen: Integer                  - 待比较的数据块字节长度

   返回值：Integer                        - 返回比较的结果
}

procedure MemoryQuickSort(Mem: Pointer; ElementByteSize: Integer;
  ElementCount: Integer; CompareProc: TCnMemSortCompareProc = nil);
{* 针对固定大小的元素的数组进行排序。

   参数：
     Mem: Pointer                         - 待处理的数据块地址
     ElementByteSize: Integer             - 排序的元素字节长度
     ElementCount: Integer                - 数据块中元素的个数
     CompareProc: TCnMemSortCompareProc   - 用来进行元素比较的回调函数

   返回值：（无）
}

function UInt8ToBinStr(V: Byte): string;
{* 将一 8 位无符号整数转换为二进制字符串。

   参数：
     V: Byte                              - 待转换的 8 位无符号整数

   返回值：string                         - 返回二进制字符串
}

function UInt16ToBinStr(V: Word): string;
{* 将一 16 位无符号整数转换为二进制字符串。

   参数：
     V: Word                              - 待转换的 16 位无符号整数

   返回值：string                         - 返回二进制字符串
}

function UInt32ToBinStr(V: Cardinal): string;
{* 将一 32 位无符号整数转换为二进制字符串。

   参数：
     V: Cardinal                          - 待转换的 32 位无符号整数

   返回值：string                         - 返回二进制字符串
}

function UInt32ToStr(V: Cardinal): string;
{* 将一 32 位无符号整数转换为十进制字符串。

   参数：
     V: Cardinal                          - 待转换的 32 位无符号整数

   返回值：string                         - 返回十进制字符串
}

function UInt64ToBinStr(V: TUInt64): string;
{* 将一 64 位无符号整数转换为二进制字符串。

   参数：
     V: TUInt64                           - 待转换的 64 位无符号整数

   返回值：string                         - 返回二进制字符串
}

function StrToUInt(const S: string): Cardinal;
{* 将字符串转换为 32 位无符号整数。

   参数：
     const S: string                      - 待转换的字符串

   返回值：Cardinal                       - 返回转换结果
}

function HexToInt(const Hex: string): Integer; overload;
{* 将一十六进制字符串转换为整型，适合较短尤其是 2 字符的字符串。

   参数：
     const Hex: string                    - 待转换的十六进制字符串

   返回值：Integer                        - 返回整数
}

function HexToInt(Hex: PChar; CharLen: Integer): Integer; overload;
{* 将一十六进制字符串指针所指的内容转换为整型，适合较短尤其是 2 字符的字符串。

   参数：
     Hex: PChar                           - 待转换的十六进制字符串地址
     CharLen: Integer                     - 字符长度

   返回值：Integer                        - 返回整数
}

function IsHexString(const Hex: string): Boolean;
{* 判断一字符串是否合法的十六进制字符串，不区分大小写。

   参数：
     const Hex: string                    - 待判断的十六进制字符串

   返回值：Boolean                        - 返回是否是合法的十六进制字符串
}

function DataToHex(InData: Pointer; ByteLength: Integer; UseUpperCase: Boolean = True): string;
{* 内存块转换为十六进制字符串，内存低位的内容出现在字符串左方，相当于网络字节顺序。
   UseUpperCase 控制输出内容的大小写

   参数：
     InData: Pointer                      - 待转换的数据块地址
     ByteLength: Integer                  - 待转换的数据块字节长度
     UseUpperCase: Boolean                - 十六进制字符串内部是否大写

   返回值：string                         - 返回十六进制字符串
}

function HexToData(const Hex: string; OutData: Pointer = nil): Integer;
{* 十六进制字符串转换为内存块，字符串左方的内容出现在内存低位，相当于网络字节顺序，
   十六进制字符串长度为奇或转换失败时抛出异常。返回转换成功的字节数。
   注意 OutData 应该指向足够容纳转换内容的区域，字节长度至少为 Length(Hex) div 2
   如果传 nil，则只返回所需的字节长度，不进行正式转换。

   参数：
     const Hex: string                    - 待转换的十六进制字符串
     OutData: Pointer                     - 输出区域，字节长度应至少为 Length(Hex) div 2

   返回值：Integer                        - 返回转换的字节长度
}

function StringToHex(const Data: string; UseUpperCase: Boolean = True): string;
{* 字符串转换为十六进制字符串，UseUpperCase 控制输出内容的大小写。

   参数：
     const Data: string                   - 待转换的字符串
     UseUpperCase: Boolean                - 十六进制字符串内部是否大写

   返回值：string                         - 返回转换的十六进制字符串
}

function HexToString(const Hex: string): string;
{* 十六进制字符串转换为字符串，十六进制字符串长度为奇或转换失败时抛出异常。

   参数：
     const Hex: string                    - 待转换的十六进制字符串

   返回值：string                         - 返回转换的字符串
}

function HexToAnsiStr(const Hex: AnsiString): AnsiString;
{* 十六进制字符串转换为字符串，十六进制字符串长度为奇或转换失败时抛出异常。

   参数：
     const Hex: AnsiString                - 待转换的十六进制字符串

   返回值：AnsiString                     - 返回转换的字符串
}

function AnsiStrToHex(const Data: AnsiString; UseUpperCase: Boolean = True): AnsiString;
{* AnsiString 转换为十六进制字符串，UseUpperCase 控制输出内容的大小写。

   参数：
     const Data: AnsiString               - 待转换的字符串
     UseUpperCase: Boolean                - 十六进制字符串内部是否大写

   返回值：AnsiString                     - 返回十六进制字符串
}

function BytesToHex(const Data: TBytes; UseUpperCase: Boolean = True): string;
{* 字节数组转换为十六进制字符串，下标低位的内容出现在字符串左方，相当于网络字节顺序，
   UseUpperCase 控制输出内容的大小写。

   参数：
     const Data: TBytes                   - 待转换的字节数组
     UseUpperCase: Boolean                - 十六进制字符串内部是否大写

   返回值：string                         - 返回十六进制字符串
}

function HexToBytes(const Hex: string): TBytes;
{* 十六进制字符串转换为字节数组，字符串左边的内容出现在下标低位，相当于网络字节顺序，
   字符串长度为奇或转换失败时抛出异常。

   参数：
     const Hex: string                    - 待转换的十六进制字符串

   返回值：TBytes                         - 返回新建的字节数组
}

function StreamToHex(Stream: TStream; UseUpperCase: Boolean = True): string;
{* 将流中的全部内容从头转换为十六进制字符串。

   参数：
     Stream: TStream                      - 待读入的流
     UseUpperCase: Boolean                - 十六进制字符串内部是否大写

   返回值：string                         - 返回十六进制字符串
}

function HexToStream(const Hex: string; Stream: TStream): Integer;
{* 将十六进制字符串内容转换后写入流中，返回写入的字节数。

   参数：
     const Hex: string                    - 待转换的十六进制字符串
     Stream: TStream                      - 写入的流

   返回值：Integer                        - 返回写入的字节数
}

function WriteBytesToStream(const Data: TBytes; Stream: TStream): Integer;
{* 将字节数组写入流中，返回写入的字节数。

   参数：
     const Data: TBytes                   - 待写入的字节数组
     Stream: TStream                      - 写入的流

   返回值：Integer                        - 返回写入的字节数
}

procedure ReverseBytes(Data: TBytes);
{* 按字节顺序倒置一字节数组的内容。

   参数：
     Data: TBytes                         - 待倒置的字节数组

   返回值：（无）
}

function CloneBytes(const Data: TBytes): TBytes;
{* 复制一个新的字节数组

   参数：
     const Data: TBytes                   - 待复制的字节数组

   返回值：TBytes                         - 返回新建的字节数组
}

function StreamToBytes(Stream: TStream): TBytes;
{* 从流从头读入全部内容至字节数组，返回新建的字节数组。

   参数：
     Stream: TStream                      - 待读入的流

   返回值：TBytes                         - 返回新建的字节数组
}

function BytesToStream(const Data: TBytes; OutStream: TStream): Integer;
{* 将字节数组整个写入流，原始流内容清除。返回写入字节数。

   参数：
     const Data: TBytes                   - 待写入的字节数组
     OutStream: TStream                   - 写入的流

   返回值：Integer                        - 返回写入字节数
}

function AnsiToBytes(const Str: AnsiString): TBytes;
{* 将 AnsiString 的内容直接转换为字节数组，不处理编码。

   参数：
     const Str: AnsiString                - 待转换的字符串

   返回值：TBytes                         - 返回转换的字节数组
}

function BytesToAnsi(const Data: TBytes): AnsiString;
{* 将字节数组的内容直接转换为 AnsiString，不处理编码。

   参数：
     const Data: TBytes                   - 待转换的字节数组

   返回值：AnsiString                     - 返回转换的字符串
}

function BytesToString(const Data: TBytes): string;
{* 将字节数组的内容转换为 string，内部逐个 Byte 赋值为 Char，不处理编码。

   参数：
     const Data: TBytes                   - 待转换的字节数组

   返回值：string                         - 返回转换的字符串
}

function MemoryToString(Mem: Pointer; MemByteLen: Integer): string;
{* 将内存块的内容转换为 string，内部逐个字节赋值，不处理编码。

   参数：
     Mem: Pointer                         - 待转换的数据块地址
     MemByteLen: Integer                  - 待转换的数据块字节长度

   返回值：string                         - 返回转换的字符串
}

function BitsToString(Bits: TBits): string;
{* 将位串对象转换为包含 0 和 1 的字符串。

   参数：
     Bits: TBits                          - 待转换的位串对象

   返回值：string                         - 返回转换的字符串
}

function ConcatBytes(const A: TBytes; const B: TBytes): TBytes; overload;
{* 将 A B 两个字节数组顺序拼好返回一个新字节数组，A B 自身保持不变。

   参数：
     const A: TBytes                      - 待拼接的字节数组一
     const B: TBytes                      - 待拼接的字节数组二

   返回值：TBytes                         - 返回拼接的新字节数组
}

function ConcatBytes(const A: TBytes; const B: TBytes; const C: TBytes): TBytes; overload;
{* 将 A B C 三个字节数组顺序拼好返回一个新字节数组，A B C 自身保持不变。

   参数：
     const A: TBytes                      - 待拼接的字节数组一
     const B: TBytes                      - 待拼接的字节数组二
     const C: TBytes                      - 待拼接的字节数组三

   返回值：TBytes                         - 返回拼接的新字节数组
}

function ConcatBytes(const A: TBytes; const B: TBytes; const C: TBytes; const D: TBytes): TBytes; overload;
{* 将 A B C D 四个字节数组顺序拼好返回一个新字节数组，A B C D 自身保持不变。

   参数：
     const A: TBytes                      - 待拼接的字节数组一
     const B: TBytes                      - 待拼接的字节数组二
     const C: TBytes                      - 待拼接的字节数组三
     const D: TBytes                      - 待拼接的字节数组四

   返回值：TBytes                         - 返回拼接的新字节数组
}

function NewZeroBytes(ByteLen: Integer): TBytes;
{* 返回 ByteLen 字节长度的新字节数组。

   参数：
     ByteLen: Integer                     - 字节数组所需的字节长度

   返回值：TBytes                         - 返回全零的新字节数组
}

function ConcatBytesMemory(const A: TBytes; Data: Pointer; DataByteLen: Integer): TBytes;
{* 将一个字节数组与一片内存区域拼好返回一个新数组，原有字节数组与内存区域均不变。

   参数：
     const A: TBytes                      - 待拼接的字节数组
     Data: Pointer                        - 待拼接的数据块地址
     DataByteLen: Integer                 - 待拼接的数据块字节长度

   返回值：TBytes                         - 返回拼接的新字节数组
}

function NewBytesFromMemory(Data: Pointer; DataByteLen: Integer): TBytes;
{* 新建一字节数组，并从一片内存区域复制内容过来。

   参数：
     Data: Pointer                        - 待处理的数据块地址
     DataByteLen: Integer                 - 待处理的数据块字节长度

   返回值：TBytes                         - 返回新建的字节数组
}

procedure PutBytesToMemory(const Data: TBytes; Mem: Pointer; MaxByteSize: Integer = 0);
{* 将一字节数组的内容写入指定内存区域，允许设置写入的最大数量。

   参数：
     const Data: TBytes                   - 待处理的字节数组
     Mem: Pointer                         - 待写入的数据块地址
     MaxByteSize: Integer                 - 控制写入的最大字节数，0 表示不控制

   返回值：（无）
}

function CompareBytes(const A: TBytes; const B: TBytes): Boolean; overload;
{* 比较两个字节数组内容是否相同。

   参数：
     const A: TBytes                      - 待比较的字节数组一
     const B: TBytes                      - 待比较的字节数组二

   返回值：Boolean                        - 返回比较结果是否相同
}

function CompareBytes(const A: TBytes; const B: TBytes; MaxLength: Integer): Boolean; overload;
{* 比较两个字节数组的最多前 MaxLength 个字节的内容是否相同。

   参数：
     const A: TBytes                      - 待比较的字节数组一
     const B: TBytes                      - 待比较的字节数组二
     MaxLength: Integer                   - 比较的字节数上限

   返回值：Boolean                        - 返回比较结果是否相同
}

function CompareBytesWithDiffIndex(const A, B: TBytes; out DiffIndex: Integer): Boolean;
{* 比较两个字节数组的内容是否相同。
   长度相等且内容不同时，DiffIndex 返回第一个不相等的字节索引，其他情况返回 -1。

   参数：
     const A: TBytes                      - 待比较的字节数组一
     const B: TBytes                      - 待比较的字节数组二
     out DiffIndex: Integer               - 返回第一个不相等的字节索引

   返回值：Boolean                        - 返回比较结果是否相同
}

function MoveMost(const Source; var Dest; ByteLen: Integer; MostLen: Integer): Integer;
{* 从 Source 移动 ByteLen 且不超过 MostLen 个字节到 Dest 中，返回实际移动的字节数。
   如 ByteLen 小于 MostLen，则 Dest 填充 0，要求 Dest 容纳至少 MostLen。

   参数：
     const Source                         - 待移动的源位置。不传地址，传变量本身
     var Dest                             - 待移动的目标位置。不传地址，传变量本身，且要求能容纳至少 MostLen 字节
     ByteLen: Integer                     - 待移动的字节数
     MostLen: Integer                     - 能移动的字节数上限

   返回值：Integer                        - 返回实际移动的字节数
}

// =============================== 算术右移 ===================================

function SarInt8(V: ShortInt; ShiftCount: Integer): ShortInt;
{* 将一 8 位有符号整数进行算术右移，也就是用符号位填充空位的右移。

   参数：
     V: ShortInt                          - 待算术右移的 8 位有符号整数
     ShiftCount: Integer                  - 算术右移的位数

   返回值：ShortInt                       - 返回移位后的值
}

function SarInt16(V: SmallInt; ShiftCount: Integer): SmallInt;
{* 将一 16 位有符号整数进行算术右移，也就是用符号位填充空位的右移。

   参数：
     V: SmallInt                          - 待算术右移的 16 位有符号整数
     ShiftCount: Integer                  - 算术右移的位数

   返回值：SmallInt                       - 返回移位后的值
}

function SarInt32(V: Integer; ShiftCount: Integer): Integer;
{* 将一 32 位有符号整数进行算术右移，也就是用符号位填充空位的右移。

   参数：
     V: Integer                           - 待算术右移的 32 位有符号整数
     ShiftCount: Integer                  - 算术右移的位数

   返回值：Integer                        - 返回移位后的值
}

function SarInt64(V: Int64; ShiftCount: Integer): Int64;
{* 将一 64 位有符号整数进行算术右移，也就是用符号位填充空位的右移。

   参数：
     V: Int64                             - 待算术右移的 64 位有符号整数
     ShiftCount: Integer                  - 算术右移的位数

   返回值：Int64                          - 返回移位后的值
}

// ================ 以下是执行时间固定的无 if 判断的部分逻辑函数 ===============

procedure ConstTimeConditionalSwap8(CanSwap: Boolean; var A: Byte; var B: Byte);
{* 针对两个 8 位整型变量的执行时间固定的条件交换，CanSwap 为 True 时才实施 A B 交换。

   参数：
     CanSwap: Boolean                     - 控制是否交换
     var A: Byte                          - 待交换的 8 位整型变量一
     var B: Byte                          - 待交换的 8 位整型变量二

   返回值：（无）
}

procedure ConstTimeConditionalSwap16(CanSwap: Boolean; var A: Word; var B: Word);
{* 针对两个 16 位整型变量的执行时间固定的条件交换，CanSwap 为 True 时才实施 A B 交换。

   参数：
     CanSwap: Boolean                     - 控制是否交换
     var A: Word                          - 待交换的 16 位整型变量一
     var B: Word                          - 待交换的 16 位整型变量二

   返回值：（无）
}

procedure ConstTimeConditionalSwap32(CanSwap: Boolean; var A: Cardinal; var B: Cardinal);
{* 针对两个 32 位整型变量的执行时间固定的条件交换，CanSwap 为 True 时才实施 A B 交换。

   参数：
     CanSwap: Boolean                     - 控制是否交换
     var A: Cardinal                      - 待交换的 32 位整型变量一
     var B: Cardinal                      - 待交换的 32 位整型变量二

   返回值：（无）
}

procedure ConstTimeConditionalSwap64(CanSwap: Boolean; var A: TUInt64; var B: TUInt64);
{* 针对两个 64 位整型变量的执行时间固定的条件交换，CanSwap 为 True 时才实施 A B 交换。

   参数：
     CanSwap: Boolean                     - 控制是否交换
     var A: TUInt64                       - 待交换的 64 位整型变量一
     var B: TUInt64                       - 待交换的 64 位整型变量二

   返回值：（无）
}

function ConstTimeEqual8(A: Byte; B: Byte): Boolean;
{* 针对俩单字节的执行时间固定的比较，避免 CPU 指令跳转预测导致的执行时间差异，内容相同时返回 True。

   参数：
     A: Byte                              - 待比较的 8 位整型变量一
     B: Byte                              - 待比较的 8 位整型变量二

   返回值：Boolean                        - 返回是否相等
}

function ConstTimeEqual16(A: Word; B: Word): Boolean;
{* 针对俩双字节的执行时间固定的比较，避免 CPU 指令跳转预测导致的执行时间差异，内容相同时返回 True。

   参数：
     A: Word                              - 待比较的 16 位整型变量一
     B: Word                              - 待比较的 16 位整型变量二

   返回值：Boolean                        - 返回是否相等
}

function ConstTimeEqual32(A: Cardinal; B: Cardinal): Boolean;
{* 针对俩四字节的执行时间固定的比较，避免 CPU 指令跳转预测导致的执行时间差异，内容相同时返回 True。

   参数：
     A: Cardinal                          - 待比较的 32 位整型变量一
     B: Cardinal                          - 待比较的 32 位整型变量二

   返回值：Boolean                        - 返回是否相等
}

function ConstTimeEqual64(A: TUInt64; B: TUInt64): Boolean;
{* 针对俩八字节的执行时间固定的比较，避免 CPU 指令跳转预测导致的执行时间差异，内容相同时返回 True。

   参数：
     A: TUInt64                           - 待比较的 64 位整型变量一
     B: TUInt64                           - 待比较的 64 位整型变量二

   返回值：Boolean                        - 返回是否相等
}

function ConstTimeCompareMem(P1, P2: Pointer; ByteLength: Integer): Boolean;
{* 针对俩相同长度的内存块的执行时间固定的比较，内容相同时返回 True。

   参数：
     P1: Pointer                          - 待比较的第一个内存块地址
     P2: Pointer                          - 待比较的第二个内存块地址
     ByteLength: Integer                  - 待比较的字节长度

   返回值：Boolean                        - 返回是否相等
}

function ConstTimeCompareBytes(const A, B: TBytes): Boolean;
{* 执行长度相同时两个字节数组的恒定时间的比较，如长度不同直接返回 False，长度与内容均相同则返回 True。

   参数：
     const A: TBytes                      - 待比较的字节数组一
     const B: TBytes                      - 待比较的字节数组二

   返回值：Boolean                        - 是否相同
}

function ConstTimeExpandBoolean8(V: Boolean): Byte;
{* 根据 V 的值返回 8 位整数全 1 或全 0。

   参数：
     V: Boolean                           - 是否返回全 1

   返回值：Byte                           - 返回 $FF 或 0
}

function ConstTimeExpandBoolean16(V: Boolean): Word;
{* 根据 V 的值返回 16 位整数全 1 或全 0。

   参数：
     V: Boolean                           - 是否返回全 1

   返回值：Word                           - 返回 $FFFF 或 0
}

function ConstTimeExpandBoolean32(V: Boolean): Cardinal;
{* 根据 V 的值返回 32 位整数全 1 或全 0。

   参数：
     V: Boolean                           - 是否返回全 1

   返回值：Cardinal                       - 返回 $FFFFFFFF 或 0
}

function ConstTimeExpandBoolean64(V: Boolean): TUInt64;
{* 根据 V 的值返回 64 位整数全 1 或全 0。

   参数：
     V: Boolean                           - 是否返回全 1

   返回值：TUInt64                        - 返回 $FFFFFFFFFFFFFFFF 或 0
}

function ConstTimeConditionalSelect8(Condition: Boolean; A: Byte; B: Byte): Byte;
{* 针对两个字节变量执行时间固定的判断选择，Condtion 为 True 时返回 A，否则返回 B。

   参数：
     Condition: Boolean                   - 是否选择 A 也就是参数一
     A: Byte                              - 待选择的 8 位整数一
     B: Byte                              - 待选择的 8 位整数二

   返回值：Byte                           - 返回选择的 8 位整数
}

function ConstTimeConditionalSelect16(Condition: Boolean; A: Word; B: Word): Word;
{* 针对两个双字节变量执行时间固定的判断选择，Condtion 为 True 时返回 A，否则返回 B。

   参数：
     Condition: Boolean                   - 是否选择 A 也就是参数一
     A: Word                              - 待选择的 16 位整数一
     B: Word                              - 待选择的 16 位整数二

   返回值：Word                           - 返回选择的 16 位整数
}

function ConstTimeConditionalSelect32(Condition: Boolean; A: Cardinal; B: Cardinal): Cardinal;
{* 针对两个四字节变量执行时间固定的判断选择，Condtion 为 True 时返回 A，否则返回 B

   参数：
     Condition: Boolean                   - 是否选择 A 也就是参数一
     A: Cardinal                          - 待选择的 32 位整数一
     B: Cardinal                          - 待选择的 32 位整数二

   返回值：Cardinal                       - 返回选择的 32 位整数
}

function ConstTimeConditionalSelect64(Condition: Boolean; A: TUInt64; B: TUInt64): TUInt64;
{* 针对两个八字节变量执行时间固定的判断选择，Condtion 为 True 时返回 A，否则返回 B

   参数：
     Condition: Boolean                   - 是否选择 A 也就是参数一
     A: TUInt64                           - 待选择的 64 位整数一
     B: TUInt64                           - 待选择的 64 位整数二

   返回值：TUInt64                        - 返回选择的 64 位整数
}

// ================ 以上是执行时间固定的无 if 判断的部分逻辑函数 ===============

{$IFDEF MSWINDOWS}

// 这四个函数因为用了 Intel 汇编，因而只支持 32 位和 64 位的 Intel CPU，照理应该用条件：CPUX86 或 CPUX64

procedure Int64DivInt32Mod(A: Int64; B: Integer;
  var DivRes: Integer; var ModRes: Integer);
{* 64 位有符号整数除以 32 位有符号整数，商放 DivRes，余数放 ModRes。
   调用者须自行保证商在 32 位范围内，否则会抛溢出异常。

   参数：
     A: Int64                             - 被除数
     B: Integer                           - 除数
     var DivRes: Integer                  - 商
     var ModRes: Integer                  - 余数

   返回值：（无）
}

procedure UInt64DivUInt32Mod(A: TUInt64; B: Cardinal;
  var DivRes: Cardinal; var ModRes: Cardinal);
{* 64 位无符号整数除以 32 位无符号整数，商放 DivRes，余数放 ModRes
   调用者须自行保证商在 32 位范围内，否则会抛溢出异常。

   参数：
     A: TUInt64                           - 被除数
     B: Cardinal                          - 除数
     var DivRes: Cardinal                 - 商
     var ModRes: Cardinal                 - 余数

   返回值：（无）
}

procedure Int128DivInt64Mod(ALo: Int64; AHi: Int64; B: Int64;
  var DivRes: Int64; var ModRes: Int64);
{* 128 位有符号整数除以 64 位有符号整数，商放 DivRes，余数放 ModRes。
   调用者须自行保证商在 64 位范围内，否则会抛溢出异常。

   参数：
     ALo: Int64                           - 被除数低 64 位
     AHi: Int64                           - 被除数高 64 位
     B: Int64                             - 除数
     var DivRes: Int64                    - 商
     var ModRes: Int64                    - 余数

   返回值：（无）
}

procedure UInt128DivUInt64Mod(ALo: TUInt64; AHi: TUInt64; B: TUInt64;
  var DivRes: TUInt64; var ModRes: TUInt64);
{* 128 位无符号整数除以 64 位无符号整数，商放 DivRes，余数放 ModRes。
   调用者须自行保证商在 64 位范围内，否则会抛溢出异常。

   参数：
     ALo: TUInt64                         - 被除数低 64 位
     AHi: TUInt64                         - 被除数高 64 位
     B: TUInt64                           - 除数
     var DivRes: TUInt64                  - 商
     var ModRes: TUInt64                  - 余数

   返回值：（无）
}

{$ENDIF}

function IsUInt128BitSet(Lo: TUInt64; Hi: TUInt64; N: Integer): Boolean;
{* 针对两个 Int64 拼成的 128 位数字，返回第 N 位是否为 1，N 从 0 到 127。

   参数：
     Lo: TUInt64                          - 待判断的整数的低 64 位
     Hi: TUInt64                          - 待判断的整数的高 64 位
     N: Integer                           - 待判断的位索引号

   返回值：Boolean                        - 返回是否为 1
}

procedure SetUInt128Bit(var Lo: TUInt64; var Hi: TUInt64; N: Integer);
{* 针对两个 Int64 拼成的 128 位数字，设置第 N 位为 1，N 从 0 到 127。

   参数：
     var Lo: TUInt64                      - 待设置的整数的低 64 位
     var Hi: TUInt64                      - 待设置的整数的高 64 位
     N: Integer                           - 待设置的位索引号

   返回值：（无）
}

procedure ClearUInt128Bit(var Lo: TUInt64; var Hi: TUInt64; N: Integer);
{* 针对两个 Int64 拼成的 128 位数字，清掉第 N 位，N 从 0 到 127。

   参数：
     var Lo: TUInt64                      - 待设置的整数的低 64 位
     var Hi: TUInt64                      - 待设置的整数的高 64 位
     N: Integer                           - 待设置的位索引号

   返回值：（无）
}

function UnsignedAddWithLimitRadix(A: Cardinal; B: Cardinal; C: Cardinal;
  var R: Cardinal; L: Cardinal; H: Cardinal): Cardinal;
{* 计算非正常进制的无符号加法，A + B + C，结果放 R 中，返回进位值。
   结果确保在 L 和 H 的闭区间内，用户须确保 H 大于 L，不考虑溢出的情形。
   该函数多用于字符分区间计算与映射，其中 C 一般是进位。

   参数：
     A: Cardinal                          - 加数一
     B: Cardinal                          - 加数二
     C: Cardinal                          - 加数三，一般是进位
     var R: Cardinal                      - 和
     L: Cardinal                          - 和的区间下限
     H: Cardinal                          - 和的区间上限

   返回值：Cardinal                       - 返回是否有进位
}

// =========================== 循环移位函数 ====================================

// 注意这批函数的 N 应在 (0, A 最大位数) 开区间内，如 N 为 0 或 A 最大位数时返回值应仍为 A
// N 超界时会求余（编译器行为，和仓颉等不同），如对 32 位 A，N 为 33 时返回值等于 N 为 1 时的返回值

function RotateLeft16(A: Word; N: Integer): Word; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 针对 16 位整数进行循环左移 N 位。

   参数：
     A: Word                              - 待循环左移的 16 位整数
     N: Integer                           - 循环左移的位数

   返回值：Word                           - 返回移位后的值
}

function RotateRight16(A: Word; N: Integer): Word; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 针对 16 位整数进行循环右移 N 位。

   参数：
     A: Word                              - 待循环右移的 16 位整数
     N: Integer                           - 循环右移的位数

   返回值：Word                           - 返回移位后的值
}

function RotateLeft32(A: Cardinal; N: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 针对 32 位整数进行循环左移 N 位。

   参数：
     A: Cardinal                          - 待循环左移的 32 位整数
     N: Integer                           - 循环左移的位数

   返回值：Cardinal                       - 返回移位后的值
}

function RotateRight32(A: Cardinal; N: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 针对 32 位整数进行循环右移 N 位。

   参数：
     A: Cardinal                          - 待循环右移的 32 位整数
     N: Integer                           - 循环右移的位数

   返回值：Cardinal                       - 返回移位后的值
}

function RotateLeft64(A: TUInt64; N: Integer): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 针对 64 位整数进行循环左移 N 位。

   参数：
     A: TUInt64                           - 待循环左移的 64 位整数
     N: Integer                           - 循环左移的位数

   返回值：TUInt64                        - 返回移位后的值
}

function RotateRight64(A: TUInt64; N: Integer): TUInt64; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
{* 针对 64 位整数进行循环右移 N 位。

   参数：
     A: TUInt64                           - 待循环右移的 64 位整数
     N: Integer                           - 循环右移的位数

   返回值：TUInt64                        - 返回移位后的值
}

{$IFDEF COMPILER5}

function BoolToStr(Value: Boolean; UseBoolStrs: Boolean = False): string;
{* 布尔变量转换为字符串。Delphi 5 下没有该 BoolToStr 函数，补上。

   参数：
     Value: Boolean                       - 待转换的布尔值
     UseBoolStrs: Boolean                 - 是否返回英文单词

   返回值：string                         - UseBoolStrs 为 False 时返回 -1 或 0，否则返回 True 或 False
}

{$ENDIF}

implementation

resourcestring
  SCnErrorNotAHexPChar = 'Error: NOT a Hex Char: #%d';
  SCnErrorLengthNotHex = 'Error Length %d: NOT a Hex String';
  SCnErrorLengthNotHexAnsi = 'Error Length %d: NOT a Hex AnsiString';

var
  FByteOrderIsBigEndian: Boolean = False;

function CurrentByteOrderIsBigEndian: Boolean;
type
  TByteOrder = packed record
    case Boolean of
      False: (C: array[0..1] of Byte);
      True: (W: Word);
  end;
var
  T: TByteOrder;
begin
  T.W := $00CC;
  Result := T.C[1] = $CC;
end;

function CurrentByteOrderIsLittleEndian: Boolean;
begin
  Result := not CurrentByteOrderIsBigEndian;
end;

function ReverseInt64(Value: Int64): Int64;
var
  Lo, Hi: Cardinal;
  Rec: Int64Rec;
begin
  Lo := Int64Rec(Value).Lo;
  Hi := Int64Rec(Value).Hi;
  Lo := ((Lo and $000000FF) shl 24) or ((Lo and $0000FF00) shl 8)
    or ((Lo and $00FF0000) shr 8) or ((Lo and $FF000000) shr 24);
  Hi := ((Hi and $000000FF) shl 24) or ((Hi and $0000FF00) shl 8)
    or ((Hi and $00FF0000) shr 8) or ((Hi and $FF000000) shr 24);
  Rec.Lo := Hi;
  Rec.Hi := Lo;
  Result := Int64(Rec);
end;

function ReverseUInt64(Value: TUInt64): TUInt64;
var
  Lo, Hi: Cardinal;
  Rec: Int64Rec;
begin
  Lo := Int64Rec(Value).Lo;
  Hi := Int64Rec(Value).Hi;
  Lo := ((Lo and $000000FF) shl 24) or ((Lo and $0000FF00) shl 8)
    or ((Lo and $00FF0000) shr 8) or ((Lo and $FF000000) shr 24);
  Hi := ((Hi and $000000FF) shl 24) or ((Hi and $0000FF00) shl 8)
    or ((Hi and $00FF0000) shr 8) or ((Hi and $FF000000) shr 24);
  Rec.Lo := Hi;
  Rec.Hi := Lo;
  Result := TUInt64(Rec);
end;

function Int64ToBigEndian(Value: Int64): Int64;
begin
  if FByteOrderIsBigEndian then
    Result := Value
  else
    Result := ReverseInt64(Value);
end;

function Int32ToBigEndian(Value: Integer): Integer;
begin
  if FByteOrderIsBigEndian then
    Result := Value
  else
    Result := Integer((Value and $000000FF) shl 24) or Integer((Value and $0000FF00) shl 8)
      or Integer((Value and $00FF0000) shr 8) or Integer((Value and $FF000000) shr 24);
end;

function Int16ToBigEndian(Value: SmallInt): SmallInt;
begin
  if FByteOrderIsBigEndian then
    Result := Value
  else
    Result := SmallInt((Value and $00FF) shl 8) or SmallInt((Value and $FF00) shr 8);
end;

function Int64ToLittleEndian(Value: Int64): Int64;
begin
  if not FByteOrderIsBigEndian then
    Result := Value
  else
    Result := ReverseInt64(Value);
end;

function Int32ToLittleEndian(Value: Integer): Integer;
begin
  if not FByteOrderIsBigEndian then
    Result := Value
  else
    Result := Integer((Value and $000000FF) shl 24) or Integer((Value and $0000FF00) shl 8)
      or Integer((Value and $00FF0000) shr 8) or Integer((Value and $FF000000) shr 24);
end;

function Int16ToLittleEndian(Value: SmallInt): SmallInt;
begin
  if not FByteOrderIsBigEndian then
    Result := Value
  else
    Result := SmallInt((Value and $00FF) shl 8) or SmallInt((Value and $FF00) shr 8);
end;

function UInt64ToBigEndian(Value: TUInt64): TUInt64;
begin
  if FByteOrderIsBigEndian then
    Result := Value
  else
    Result := ReverseUInt64(Value);
end;

function UInt32ToBigEndian(Value: Cardinal): Cardinal;
begin
  if FByteOrderIsBigEndian then
    Result := Value
  else
    Result := Cardinal((Value and $000000FF) shl 24) or Cardinal((Value and $0000FF00) shl 8)
      or Cardinal((Value and $00FF0000) shr 8) or Cardinal((Value and $FF000000) shr 24);
end;

function UInt16ToBigEndian(Value: Word): Word;
begin
  if FByteOrderIsBigEndian then
    Result := Value
  else
    Result := Word((Value and $00FF) shl 8) or Word((Value and $FF00) shr 8);
end;

function UInt64ToLittleEndian(Value: TUInt64): TUInt64;
begin
  if not FByteOrderIsBigEndian then
    Result := Value
  else
    Result := ReverseUInt64(Value);
end;

function UInt32ToLittleEndian(Value: Cardinal): Cardinal;
begin
  if not FByteOrderIsBigEndian then
    Result := Value
  else
    Result := Cardinal((Value and $000000FF) shl 24) or Cardinal((Value and $0000FF00) shl 8)
      or Cardinal((Value and $00FF0000) shr 8) or Cardinal((Value and $FF000000) shr 24);
end;

function UInt16ToLittleEndian(Value: Word): Word;
begin
  if not FByteOrderIsBigEndian then
    Result := Value
  else
    Result := Word((Value and $00FF) shl 8) or Word((Value and $FF00) shr 8);
end;

function Int64HostToNetwork(Value: Int64): Int64;
begin
  if not FByteOrderIsBigEndian then
    Result := ReverseInt64(Value)
  else
    Result := Value;
end;

function Int32HostToNetwork(Value: Integer): Integer;
begin
  if not FByteOrderIsBigEndian then
    Result := Integer((Value and $000000FF) shl 24) or Integer((Value and $0000FF00) shl 8)
      or Integer((Value and $00FF0000) shr 8) or Integer((Value and $FF000000) shr 24)
  else
    Result := Value;
end;

function Int16HostToNetwork(Value: SmallInt): SmallInt;
begin
  if not FByteOrderIsBigEndian then
    Result := SmallInt((Value and $00FF) shl 8) or SmallInt((Value and $FF00) shr 8)
  else
    Result := Value;
end;

function Int64NetworkToHost(Value: Int64): Int64;
begin
  if not FByteOrderIsBigEndian then
    REsult := ReverseInt64(Value)
  else
    Result := Value;
end;

function Int32NetworkToHost(Value: Integer): Integer;
begin
  if not FByteOrderIsBigEndian then
    Result := Integer((Value and $000000FF) shl 24) or Integer((Value and $0000FF00) shl 8)
      or Integer((Value and $00FF0000) shr 8) or Integer((Value and $FF000000) shr 24)
  else
    Result := Value;
end;

function Int16NetworkToHost(Value: SmallInt): SmallInt;
begin
  if not FByteOrderIsBigEndian then
    Result := SmallInt((Value and $00FF) shl 8) or SmallInt((Value and $FF00) shr 8)
  else
    Result := Value;
end;

function UInt64HostToNetwork(Value: TUInt64): TUInt64;
begin
  if CurrentByteOrderIsBigEndian then
    Result := Value
  else
    Result := ReverseUInt64(Value);
end;

function UInt32HostToNetwork(Value: Cardinal): Cardinal;
begin
  if not FByteOrderIsBigEndian then
    Result := Cardinal((Value and $000000FF) shl 24) or Cardinal((Value and $0000FF00) shl 8)
      or Cardinal((Value and $00FF0000) shr 8) or Cardinal((Value and $FF000000) shr 24)
  else
    Result := Value;
end;

function UInt16HostToNetwork(Value: Word): Word;
begin
  if not FByteOrderIsBigEndian then
    Result := ((Value and $00FF) shl 8) or ((Value and $FF00) shr 8)
  else
    Result := Value;
end;

function UInt64NetworkToHost(Value: TUInt64): TUInt64;
begin
  if CurrentByteOrderIsBigEndian then
    Result := Value
  else
    Result := ReverseUInt64(Value);
end;

function UInt32NetworkToHost(Value: Cardinal): Cardinal;
begin
  if not FByteOrderIsBigEndian then
    Result := Cardinal((Value and $000000FF) shl 24) or Cardinal((Value and $0000FF00) shl 8)
      or Cardinal((Value and $00FF0000) shr 8) or Cardinal((Value and $FF000000) shr 24)
  else
    Result := Value;
end;

function UInt16NetworkToHost(Value: Word): Word;
begin
  if not FByteOrderIsBigEndian then
    Result := ((Value and $00FF) shl 8) or ((Value and $FF00) shr 8)
  else
    Result := Value;
end;

function ReverseBitsInInt8(V: Byte): Byte;
begin
  // 0 和 1 交换、2 和 3 交换、4 和 5 交换、6 和 7 交换
  V := ((V and $AA) shr 1) or ((V and $55) shl 1);
  // 01 和 23 交换、45 和 67 交换
  V := ((V and $CC) shr 2) or ((V and $33) shl 2);
  // 0123 和 4567 交换
  V := (V shr 4) or (V shl 4);
  Result := V;
end;

function ReverseBitsInInt16(V: Word): Word;
begin
  Result := (ReverseBitsInInt8(V and $00FF) shl 8)
    or ReverseBitsInInt8((V and $FF00) shr 8);
end;

function ReverseBitsInInt32(V: Cardinal): Cardinal;
begin
  Result := (ReverseBitsInInt16(V and $0000FFFF) shl 16)
    or ReverseBitsInInt16((V and $FFFF0000) shr 16);
end;

function ReverseBitsInInt64(V: Int64): Int64;
begin
  Result := (Int64(ReverseBitsInInt32(V and $00000000FFFFFFFF)) shl 32)
    or ReverseBitsInInt32((V and $FFFFFFFF00000000) shr 32);
end;

procedure ReverseMemory(Mem: Pointer; MemByteLen: Integer);
var
  I, L: Integer;
  P: PByteArray;
  T: Byte;
begin
  if (Mem = nil) or (MemByteLen < 2) then
    Exit;

  L := MemByteLen div 2;
  P := PByteArray(Mem);
  for I := 0 to L - 1 do
  begin
    // 交换第 I 和第 MemLen - I - 1
    T := P^[I];
    P^[I] := P^[MemByteLen - I - 1];
    P^[MemByteLen - I - 1] := T;
  end;
end;

procedure ReverseMemoryWithBits(Mem: Pointer; MemByteLen: Integer);
var
  I: Integer;
  P: PByteArray;
begin
  if (Mem = nil) or (MemByteLen <= 0) then
    Exit;

  ReverseMemory(Mem, MemByteLen);
  P := PByteArray(Mem);

  for I := 0 to MemByteLen - 1 do
    P^[I] := ReverseBitsInInt8(P^[I]);
end;

procedure MemoryNetworkToHost(Mem: Pointer; MemByteLen: Integer);
begin
  if not FByteOrderIsBigEndian then
    ReverseMemory(Mem, MemByteLen);
end;

procedure MemoryHostToNetwork(Mem: Pointer; MemByteLen: Integer);
begin
  if not FByteOrderIsBigEndian then
    ReverseMemory(Mem, MemByteLen);
end;

// N 字节长度的内存块的位操作
procedure MemoryBitOperation(AMem, BMem, RMem: Pointer; N: Integer; Op: TCnBitOperation);
var
  A, B, R: PCnLongWord32Array;
  BA, BB, BR: PByteArray;
begin
  if N <= 0 then
    Exit;

  if (AMem = nil) or ((BMem = nil) and (Op <> boNot)) or (RMem = nil) then
    Exit;

  A := PCnLongWord32Array(AMem);
  B := PCnLongWord32Array(BMem);
  R := PCnLongWord32Array(RMem);

  while (N and (not 3)) <> 0 do
  begin
    case Op of
      boAnd:
        R^[0] := A^[0] and B^[0];
      boOr:
        R^[0] := A^[0] or B^[0];
      boXor:
        R^[0] := A^[0] xor B^[0];
      boNot: // 求反时忽略 B
        R^[0] := not A^[0];
    end;

    A := PCnLongWord32Array(TCnIntAddress(A) + SizeOf(Cardinal));
    B := PCnLongWord32Array(TCnIntAddress(B) + SizeOf(Cardinal));
    R := PCnLongWord32Array(TCnIntAddress(R) + SizeOf(Cardinal));

    Dec(N, SizeOf(Cardinal));
  end;

  if N > 0 then
  begin
    BA := PByteArray(A);
    BB := PByteArray(B);
    BR := PByteArray(R);

    while N <> 0 do
    begin
      case Op of
        boAnd:
          BR^[0] := BA^[0] and BB^[0];
        boOr:
          BR^[0] := BA^[0] or BB^[0];
        boXor:
          BR^[0] := BA^[0] xor BB^[0];
        boNot:
          BR^[0] := not BA^[0];
      end;

      BA := PByteArray(TCnIntAddress(BA) + SizeOf(Byte));
      BB := PByteArray(TCnIntAddress(BB) + SizeOf(Byte));
      BR := PByteArray(TCnIntAddress(BR) + SizeOf(Byte));
      Dec(N);
    end;
  end;
end;

procedure MemoryAnd(AMem, BMem: Pointer; MemByteLen: Integer; ResMem: Pointer);
begin
  MemoryBitOperation(AMem, BMem, ResMem, MemByteLen, boAnd);
end;

procedure MemoryOr(AMem, BMem: Pointer; MemByteLen: Integer; ResMem: Pointer);
begin
  MemoryBitOperation(AMem, BMem, ResMem, MemByteLen, boOr);
end;

procedure MemoryXor(AMem, BMem: Pointer; MemByteLen: Integer; ResMem: Pointer);
begin
  MemoryBitOperation(AMem, BMem, ResMem, MemByteLen, boXor);
end;

procedure MemoryNot(Mem: Pointer; MemByteLen: Integer; ResMem: Pointer);
begin
  MemoryBitOperation(Mem, nil, ResMem, MemByteLen, boNot);
end;

procedure MemoryShiftLeft(AMem, BMem: Pointer; MemByteLen: Integer; BitCount: Integer);
var
  I, L, N, LB, RB: Integer;
  PF, PT: PByteArray;
begin
  if (AMem = nil) or (MemByteLen <= 0) or (BitCount = 0) then
    Exit;

  if BitCount < 0 then
  begin
    MemoryShiftRight(AMem, BMem, MemByteLen, -BitCount);
    Exit;
  end;

  if BMem = nil then
    BMem := AMem;

  if (MemByteLen * 8) <= BitCount then // 移太多不够，全 0
  begin
    FillChar(BMem^, MemByteLen, 0);
    Exit;
  end;

  N := BitCount div 8;  // 移位超过的整字节数
  RB := BitCount mod 8; // 去除整字节后剩下的位数
  LB := 8 - RB;         // 上面剩下的位数在一字节内再剩下的位数

  PF := PByteArray(AMem);
  PT := PByteArray(BMem);

  if RB = 0 then // 整块，好办，要移位的字节数是 MemLen - NW
  begin
    Move(PF^[N], PT^[0], MemByteLen - N);
    FillChar(PT^[MemByteLen - N], N, 0);
  end
  else
  begin
    // 起点是 PF^[N] 和 PT^[0]，长度 MemLen - N 个字节，但相邻字节间有交叉
    L := MemByteLen - N;
    PF := PByteArray(TCnIntAddress(PF) + N);

    for I := 1 to L do // 从低位往低移动，先处理低的
    begin
      PT^[0] := Byte(PF^[0] shl RB);
      if I < L then    // 最高一个字节 PF^[1] 会超界
        PT^[0] := (PF^[1] shr LB) or PT^[0];

      PF := PByteArray(TCnIntAddress(PF) + 1);
      PT := PByteArray(TCnIntAddress(PT) + 1);
    end;

    // 剩下的要填 0
    if N > 0 then
      FillChar(PT^[0], N, 0);
  end;
end;

procedure MemoryShiftRight(AMem, BMem: Pointer; MemByteLen: Integer; BitCount: Integer);
var
  I, L, N, LB, RB: Integer;
  PF, PT: PByteArray;
begin
  if (AMem = nil) or (MemByteLen <= 0) or (BitCount = 0) then
    Exit;

  if BitCount < 0 then
  begin
    MemoryShiftLeft(AMem, BMem, MemByteLen, -BitCount);
    Exit;
  end;

  if BMem = nil then
    BMem := AMem;

  if (MemByteLen * 8) <= BitCount then // 移太多不够，全 0
  begin
    FillChar(BMem^, MemByteLen, 0);
    Exit;
  end;

  N := BitCount div 8;  // 移位超过的整字节数
  RB := BitCount mod 8; // 去除整字节后剩下的位数
  LB := 8 - RB;         // 上面剩下的位数在一字节内再剩下的位数

  if RB = 0 then // 整块，好办，要移位的字节数是 MemLen - N
  begin
    PF := PByteArray(AMem);
    PT := PByteArray(BMem);

    Move(PF^[0], PT^[N], MemByteLen - N);
    FillChar(PT^[0], N, 0);
  end
  else
  begin
    // 起点是 PF^[0] 和 PT^[N]，长度 MemLen - N 个字节，但得从高处开始，且相邻字节间有交叉
    L := MemByteLen - N;

    PF := PByteArray(TCnIntAddress(AMem) + L - 1);
    PT := PByteArray(TCnIntAddress(BMem) + MemByteLen - 1);

    for I := L downto 1 do // 从高位往高位移动，先处理后面的
    begin
      PT^[0] := Byte(PF^[0] shr RB);
      if I > 1 then        // 最低一个字节 PF^[-1] 会超界
      begin
        PF := PByteArray(TCnIntAddress(PF) - 1);
        PT^[0] := Byte((PF^[0] shl LB) or PT^[0]);
      end
      else
        PF := PByteArray(TCnIntAddress(PF) - 1);

      PT := PByteArray(TCnIntAddress(PT) - 1);
    end;

    // 剩下的最前面的要填 0
    if N > 0 then
      FillChar(BMem^, N, 0);
  end;
end;

function MemoryIsBitSet(Mem: Pointer; N: Integer): Boolean;
var
  P: PByte;
  A, B: Integer;
  V: Byte;
begin
  if (Mem = nil) or (N < 0) then
    raise ERangeError.Create(SRangeError);

  A := N div 8;
  B := N mod 8;
  P := PByte(TCnIntAddress(Mem) + A);

  V := Byte(1 shl B);
  Result := (P^ and V) <> 0;
end;

procedure MemorySetBit(Mem: Pointer; N: Integer);
var
  P: PByte;
  A, B: Integer;
  V: Byte;
begin
  if (Mem = nil) or (N < 0) then
    raise ERangeError.Create(SRangeError);

  A := N div 8;
  B := N mod 8;
  P := PByte(TCnIntAddress(Mem) + A);

  V := Byte(1 shl B);
  P^ := P^ or V;
end;

procedure MemoryClearBit(Mem: Pointer; N: Integer);
var
  P: PByte;
  A, B: Integer;
  V: Byte;
begin
  if (Mem = nil) or (N < 0) then
    raise ERangeError.Create(SRangeError);

  A := N div 8;
  B := N mod 8;
  P := PByte(TCnIntAddress(Mem) + A);

  V := not Byte(1 shl B);
  P^ := P^ and V;
end;

function MemoryGetHighBits(Mem: Pointer; MemByteLen: Integer): Integer;
var
  I, R, ZO: Integer;
  P: PByteArray;
begin
  Result := -1;
  if (Mem = nil) or (MemByteLen <= 0) then
    Exit;

  P := PByteArray(Mem);
  ZO := 0;
  for I := 0 to MemByteLen - 1 do // 从低地址往高地址找
  begin
    R := GetUInt8HighBits(P^[I]);
    if R = -1 then // 该字节全 0
    begin
      ZO := ZO + 8;
    end
    else // 该字节有 1，中止
    begin
      ZO := ZO + 8 - R + 1;
      Break;
    end;
  end;

  if ZO = MemByteLen * 8 then // 全零，没 1
    Result := -1
  else
    Result := MemByteLen * 8 - ZO; // 有 1，总位数减去 0 的个数
end;

function MemoryGetLowBits(Mem: Pointer; MemByteLen: Integer): Integer;
var
  I, R, ZC: Integer;
  P: PByteArray;
begin
  Result := -1;
  if (Mem = nil) or (MemByteLen <= 0) then
    Exit;

  P := PByteArray(Mem);
  ZC := 0;
  for I := MemByteLen - 1 downto 0 do // 从高地址往低地址找
  begin
    R := GetUInt8LowBits(P^[I]);
    if R = -1 then // 该字节全 0
    begin
      ZC := ZC + 8;
    end
    else // 该字节有 1，中止
    begin
      ZC := ZC + R;
      Break;
    end;
  end;

  if ZC = MemByteLen * 8 then // 全零，没 1
    Result := -1
  else
    Result := MemByteLen * 8 - ZC; // 有 1，总位数减去 0 的个数
end;

function MemoryToBinStr(Mem: Pointer; MemByteLen: Integer; Sep: Boolean): string;
var
  J, L: Integer;
  P: PByteArray;
  B: PChar;

  procedure FillAByteToBuf(V: Byte; Buf: PChar);
  const
    M = $80;
  var
    I: Integer;
  begin
    for I := 0 to 7 do
    begin
      if (V and M) <> 0 then
        Buf[I] := '1'
      else
        Buf[I] := '0';
      V := V shl 1;
    end;
  end;

begin
  Result := '';
  if (Mem = nil) or (MemByteLen <= 0) then
    Exit;

  L := MemByteLen * 8;
  if Sep then
    L := L + MemByteLen - 1; // 中间用空格分隔

  SetLength(Result, L);
  B := PChar(@Result[1]);
  P := PByteArray(Mem);

  for J := 0 to MemByteLen - 1 do
  begin
    FillAByteToBuf(P^[J], B);
    if Sep then
    begin
      B[8] := ' ';
      Inc(B, 9);
    end
    else
      Inc(B, 8);
  end;
end;

procedure MemorySwap(AMem, BMem: Pointer; MemByteLen: Integer);
var
  A, B: PCnLongWord32Array;
  BA, BB: PByteArray;
  TC: Cardinal;
  TB: Byte;
begin
  if (AMem = nil) or (BMem = nil) or (MemByteLen <= 0) then
    Exit;

  A := PCnLongWord32Array(AMem);
  B := PCnLongWord32Array(BMem);

  if A = B then
    Exit;

  while (MemByteLen and (not 3)) <> 0 do
  begin
    TC := A^[0];
    A^[0] := B^[0];
    B^[0] := TC;

    A := PCnLongWord32Array(TCnIntAddress(A) + SizeOf(Cardinal));
    B := PCnLongWord32Array(TCnIntAddress(B) + SizeOf(Cardinal));

    Dec(MemByteLen, SizeOf(Cardinal));
  end;

  if MemByteLen > 0 then
  begin
    BA := PByteArray(A);
    BB := PByteArray(B);

    while MemByteLen <> 0 do
    begin
      TB := BA^[0];
      BA^[0] := BB^[0];
      BB^[0] :=TB;

      BA := PByteArray(TCnIntAddress(BA) + SizeOf(Byte));
      BB := PByteArray(TCnIntAddress(BB) + SizeOf(Byte));

      Dec(MemByteLen);
    end;
  end;
end;

function MemoryCompare(AMem, BMem: Pointer; MemByteLen: Integer): Integer;
var
  A, B: PCnLongWord32Array;
  BA, BB: PByteArray;
begin
  Result := 0;
  if ((AMem = nil) and (BMem = nil)) or (AMem = BMem) then // 同一块
    Exit;

  if MemByteLen <= 0 then
    Exit;

  if AMem = nil then
  begin
    Result := -1;
    Exit;
  end;
  if BMem = nil then
  begin
    Result := 1;
    Exit;
  end;

  A := PCnLongWord32Array(AMem);
  B := PCnLongWord32Array(BMem);

  while (MemByteLen and (not 3)) <> 0 do
  begin
    if A^[0] > B^[0] then
    begin
      Result := 1;
      Exit;
    end
    else if A^[0] < B^[0] then
    begin
      Result := -1;
      Exit;
    end;

    A := PCnLongWord32Array(TCnIntAddress(A) + SizeOf(Cardinal));
    B := PCnLongWord32Array(TCnIntAddress(B) + SizeOf(Cardinal));

    Dec(MemByteLen, SizeOf(Cardinal));
  end;

  if MemByteLen > 0 then
  begin
    BA := PByteArray(A);
    BB := PByteArray(B);

    while MemByteLen <> 0 do
    begin
      if BA^[0] > BB^[0] then
      begin
        Result := 1;
        Exit;
      end
      else if BA^[0] < BB^[0] then
      begin
        Result := -1;
        Exit;
      end;

      BA := PByteArray(TCnIntAddress(BA) + SizeOf(Byte));
      BB := PByteArray(TCnIntAddress(BB) + SizeOf(Byte));

      Dec(MemByteLen);
    end;
  end;
end;

function UInt8ToBinStr(V: Byte): string;
const
  M = $80;
var
  I: Integer;
begin
  SetLength(Result, 8 * SizeOf(V));
  for I := 1 to 8 * SizeOf(V) do
  begin
    if (V and M) <> 0 then
      Result[I] := '1'
    else
      Result[I] := '0';
    V := V shl 1;
  end;
end;

function UInt16ToBinStr(V: Word): string;
const
  M = $8000;
var
  I: Integer;
begin
  SetLength(Result, 8 * SizeOf(V));
  for I := 1 to 8 * SizeOf(V) do
  begin
    if (V and M) <> 0 then
      Result[I] := '1'
    else
      Result[I] := '0';
    V := V shl 1;
  end;
end;

function UInt32ToBinStr(V: Cardinal): string;
const
  M = $80000000;
var
  I: Integer;
begin
  SetLength(Result, 8 * SizeOf(V));
  for I := 1 to 8 * SizeOf(V) do
  begin
    if (V and M) <> 0 then
      Result[I] := '1'
    else
      Result[I] := '0';
    V := V shl 1;
  end;
end;

function UInt32ToStr(V: Cardinal): string;
begin
  Result := Format('%u', [V]);
end;

function UInt64ToBinStr(V: TUInt64): string;
const
  M = $8000000000000000;
var
  I: Integer;
begin
  SetLength(Result, 8 * SizeOf(V));

  for I := 1 to 8 * SizeOf(V) do
  begin
    if (V and M) <> 0 then
      Result[I] := '1'
    else
      Result[I] := '0';
    V := V shl 1;
  end;
end;

const
  HiDigits: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7',
                                  '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
const
  LoDigits: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7',
                                  '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');

const
  AnsiHiDigits: array[0..15] of AnsiChar = ('0', '1', '2', '3', '4', '5', '6', '7',
                                  '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
const
  AnsiLoDigits: array[0..15] of AnsiChar = ('0', '1', '2', '3', '4', '5', '6', '7',
                                  '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');

function HexToInt(Hex: PChar; CharLen: Integer): Integer;
var
  I, Res: Integer;
  C: Char;
begin
  Res := 0;
  for I := 0 to CharLen - 1 do
  begin
    C := Hex[I];
    if (C >= '0') and (C <= '9') then
      Res := Res * 16 + Ord(C) - Ord('0')
    else if (C >= 'A') and (C <= 'F') then
      Res := Res * 16 + Ord(C) - Ord('A') + 10
    else if (C >= 'a') and (C <= 'f') then
      Res := Res * 16 + Ord(C) - Ord('a') + 10
    else
      raise ECnNativeException.CreateFmt(SCnErrorNotAHexPChar, [Ord(C)]);
  end;
  Result := Res;
end;

function HexToInt(const Hex: string): Integer;
begin
  Result := HexToInt(PChar(Hex), Length(Hex));
end;

{$WARNINGS OFF}

function IsHexString(const Hex: string): Boolean;
var
  I, L: Integer;
begin
  Result := False;
  L := Length(Hex);
  if (L <= 0) or ((L and 1) <> 0) then // 空或非偶长度都不是
    Exit;

  for I := 1 to L do
  begin
    // 注意此处 Unicode 下虽然有 Warning，但并不是将 Hex[I] 这个 WideChar 直接截断至 AnsiChar
    // 后再进行判断（那样会导致“晦晦”这种 $66$66$66$66 的字符串出现误判），而是
    // 直接通过 WideChar 的值（在 ax 中因而是双字节的）加减来判断，不会出现误判
    if not (Hex[I] in ['0'..'9', 'A'..'F', 'a'..'f']) then
      Exit;
  end;
  Result := True;
end;

{$WARNINGS ON}

function DataToHex(InData: Pointer; ByteLength: Integer; UseUpperCase: Boolean = True): string;
var
  I: Integer;
  B: Byte;
begin
  Result := '';
  if ByteLength <= 0 then
    Exit;

  SetLength(Result, ByteLength * 2);
  if UseUpperCase then
  begin
    for I := 0 to ByteLength - 1 do
    begin
      B := PByte(TCnIntAddress(InData) + I * SizeOf(Byte))^;
      Result[I * 2 + 1] := HiDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := HiDigits[B and $0F];
    end;
  end
  else
  begin
    for I := 0 to ByteLength - 1 do
    begin
      B := PByte(TCnIntAddress(InData) + I * SizeOf(Byte))^;
      Result[I * 2 + 1] := LoDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := LoDigits[B and $0F];
    end;
  end;
end;

function HexToData(const Hex: string; OutData: Pointer): Integer;
var
  I, L: Integer;
  H: PChar;
begin
  L := Length(Hex);
  if (L mod 2) <> 0 then
    raise ECnNativeException.CreateFmt(SCnErrorLengthNotHex, [L]);

  if OutData = nil then
  begin
    Result := L div 2;
    Exit;
  end;

  Result := 0;
  H := PChar(Hex);
  for I := 1 to L div 2 do
  begin
    PByte(TCnIntAddress(OutData) + I - 1)^ := Byte(HexToInt(@H[(I - 1) * 2], 2));
    Inc(Result);
  end;
end;

function StringToHex(const Data: string; UseUpperCase: Boolean): string;
var
  I, L: Integer;
  B: Byte;
  Buffer: PChar;
begin
  Result := '';
  L := Length(Data);
  if L = 0 then
    Exit;

  SetLength(Result, L * 2);
  Buffer := @Data[1];

  if UseUpperCase then
  begin
    for I := 0 to L - 1 do
    begin
      B := PByte(TCnIntAddress(Buffer) + I * SizeOf(Char))^;
      Result[I * 2 + 1] := HiDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := HiDigits[B and $0F];
    end;
  end
  else
  begin
    for I := 0 to L - 1 do
    begin
      B := PByte(TCnIntAddress(Buffer) + I * SizeOf(Char))^;
      Result[I * 2 + 1] := LoDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := LoDigits[B and $0F];
    end;
  end;
end;

function HexToString(const Hex: string): string;
var
  I, L: Integer;
  H: PChar;
begin
  L := Length(Hex);
  if (L mod 2) <> 0 then
    raise ECnNativeException.CreateFmt(SCnErrorLengthNotHex, [L]);

  SetLength(Result, L div 2);
  H := PChar(Hex);
  for I := 1 to L div 2 do
    Result[I] := Chr(HexToInt(@H[(I - 1) * 2], 2));
end;

function HexToAnsiStr(const Hex: AnsiString): AnsiString;
var
  I, L: Integer;
  S: string;
begin
  L := Length(Hex);
  if (L mod 2) <> 0 then
    raise ECnNativeException.CreateFmt(SCnErrorLengthNotHexAnsi, [L]);

  SetLength(Result, L div 2);
  for I := 1 to L div 2 do
  begin
    S := string(Copy(Hex, I * 2 - 1, 2));
    Result[I] := AnsiChar(Chr(HexToInt(S)));
  end;
end;

function AnsiStrToHex(const Data: AnsiString; UseUpperCase: Boolean): AnsiString;
var
  I, L: Integer;
  B: Byte;
  Buffer: PAnsiChar;
begin
  Result := '';
  L := Length(Data);
  if L = 0 then
    Exit;

  SetLength(Result, L * 2);
  Buffer := @Data[1];

  if UseUpperCase then
  begin
    for I := 0 to L - 1 do
    begin
      B := PByte(TCnIntAddress(Buffer) + I)^;
      Result[I * 2 + 1] := AnsiHiDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := AnsiHiDigits[B and $0F];
    end;
  end
  else
  begin
    for I := 0 to L - 1 do
    begin
      B := PByte(TCnIntAddress(Buffer) + I)^;
      Result[I * 2 + 1] := AnsiLoDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := AnsiLoDigits[B and $0F];
    end;
  end;
end;

function BytesToHex(const Data: TBytes; UseUpperCase: Boolean): string;
var
  I, L: Integer;
  B: Byte;
  Buffer: PAnsiChar;
begin
  Result := '';
  L := Length(Data);
  if L = 0 then
    Exit;

  SetLength(Result, L * 2);
  Buffer := @Data[0];

  if UseUpperCase then
  begin
    for I := 0 to L - 1 do
    begin
      B := PByte(TCnIntAddress(Buffer) + I)^;
      Result[I * 2 + 1] := HiDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := HiDigits[B and $0F];
    end;
  end
  else
  begin
    for I := 0 to L - 1 do
    begin
      B := PByte(TCnIntAddress(Buffer) + I)^;
      Result[I * 2 + 1] := LoDigits[(B shr 4) and $0F];
      Result[I * 2 + 2] := LoDigits[B and $0F];
    end;
  end;
end;

function HexToBytes(const Hex: string): TBytes;
var
  I, L: Integer;
  H: PChar;
begin
  L := Length(Hex);
  if (L mod 2) <> 0 then
    raise ECnNativeException.CreateFmt(SCnErrorLengthNotHex, [L]);

  SetLength(Result, L div 2);
  H := PChar(Hex);

  for I := 1 to L div 2 do
    Result[I - 1] := Byte(HexToInt(@H[(I - 1) * 2], 2));
end;

function StreamToHex(Stream: TStream; UseUpperCase: Boolean): string;
var
  B: Byte;
  I: Integer;
begin
  Result := '';
  if Stream.Size > 0 then
  begin
    Stream.Position := 0;
    SetLength(Result, Stream.Size * 2);
    I := 1;
    if UseUpperCase then
    begin
      while Stream.Read(B, 1) = 1 do
      begin
        Result[I] := HiDigits[(B shr 4) and $0F];
        Inc(I);
        Result[I] := HiDigits[B and $0F];
        Inc(I);
      end;
    end
    else
    begin
      while Stream.Read(B, 1) = 1 do
      begin
        Result[I] := LoDigits[(B shr 4) and $0F];
        Inc(I);
        Result[I] := LoDigits[B and $0F];
        Inc(I);
      end;
    end;
  end;
end;

function HexToStream(const Hex: string; Stream: TStream): Integer;
var
  I, L: Integer;
  H: PChar;
  B: Byte;
begin
  Result := 0;
  L := Length(Hex);
  if (L mod 2) <> 0 then
    raise ECnNativeException.CreateFmt(SCnErrorLengthNotHex, [L]);

  H := PChar(Hex);
  for I := 1 to L div 2 do
  begin
    B := Byte(HexToInt(@H[(I - 1) * 2], 2));
    Inc(Result, Stream.Write(B, 1));
  end;
end;

function WriteBytesToStream(const Data: TBytes; Stream: TStream): Integer;
begin
  if Length(Data) > 0 then
    Result := Stream.Write(Data[0], Length(Data))
  else
    Result := 0;
end;

procedure ReverseBytes(Data: TBytes);
var
  I, L, M: Integer;
  T: Byte;
begin
  if (Data = nil) or (Length(Data) <= 1) then
    Exit;
  L := Length(Data);
  M := L div 2;
  for I := 0 to M - 1 do
  begin
    // 交换 I 和 L - I - 1
    T := Data[I];
    Data[I] := Data[L - I - 1];
    Data[L - I - 1] := T;
  end;
end;

function CloneBytes(const Data: TBytes): TBytes;
begin
  if Length(Data) = 0 then
    Result := nil
  else
  begin
    SetLength(Result, Length(Data));
    Move(Data[0], Result[0], Length(Data));
  end;
end;

function StreamToBytes(Stream: TStream): TBytes;
begin
  Result := nil;
  if (Stream <> nil) and (Stream.Size > 0) then
  begin
    SetLength(Result, Stream.Size);
    Stream.Position := 0;
    Stream.Read(Result[0], Stream.Size);
  end;
end;

function BytesToStream(const Data: TBytes; OutStream: TStream): Integer;
begin
  Result := 0;
  if (Data <> nil) and (Length(Data) > 0) and (OutStream <> nil) then
  begin
    OutStream.Size := 0;
    Result := OutStream.Write(Data[0], Length(Data));
  end;
end;

function AnsiToBytes(const Str: AnsiString): TBytes;
begin
  SetLength(Result, Length(Str));
  if Length(Str) > 0 then
    Move(Str[1], Result[0], Length(Str));
end;

function BytesToAnsi(const Data: TBytes): AnsiString;
begin
  SetLength(Result, Length(Data));
  if Length(Data) > 0 then
    Move(Data[0], Result[1], Length(Data));
end;

function BytesToString(const Data: TBytes): string;
var
  I: Integer;
begin
  SetLength(Result, Length(Data));
  for I := 1 to Length(Data) do
    Result[I] := Chr(Data[I - 1]);
end;

function MemoryToString(Mem: Pointer; MemByteLen: Integer): string;
var
  P: PByteArray;
  I: Integer;
begin
  if (Mem = nil) or (MemByteLen <= 0) then
  begin
    Result := '';
    Exit;
  end;

  P := PByteArray(Mem);
  SetLength(Result, MemByteLen);
  for I := 1 to MemByteLen do
    Result[I] := Chr(P^[I - 1]);
end;

function BitsToString(Bits: TBits): string;
var
  I: Integer;
begin
  if (Bits = nil) or (Bits.Size = 0) then
    Result := ''
  else
  begin
    SetLength(Result, Bits.Size);
    for I := 0 to Bits.Size - 1 do
    begin
      if Bits.Bits[I] then
        Result[I + 1] := '1'
      else
        Result[I + 1] := '0';
    end;
  end;
end;

function ConcatBytes(const A, B: TBytes): TBytes;
begin
  // 哪怕是 XE7 后也不能直接相加，因为 A 或 B 为空时会返回另一字节数组而不是新数组
  if (A = nil) or (Length(A) = 0) then
  begin
    SetLength(Result, Length(B));
    if Length(B) > 0 then
      Move(B[0], Result[0], Length(B));
  end
  else if (B = nil) or (Length(B) = 0) then
  begin
    SetLength(Result, Length(A));
    if Length(A) > 0 then
      Move(A[0], Result[0], Length(A));
  end
  else
  begin
    SetLength(Result, Length(A) + Length(B));
    Move(A[0], Result[0], Length(A));
    Move(B[0], Result[Length(A)], Length(B));
  end;
end;

function ConcatBytes(const A: TBytes; const B: TBytes; const C: TBytes): TBytes;
var
  L1, L2, L3: Integer;
begin
  Result := nil;
  L1 := Length(A);
  L2 := Length(B);
  L3 := Length(C);

  if (L1 = 0) and (L2 = 0) and (L3 = 0) then
    Exit;

  SetLength(Result, L1 + L2 + L3);
  if L1 > 0 then
    Move(A[0], Result[0], L1);
  if L2 > 0 then
    Move(B[0], Result[L1], L2);
  if L3 > 0 then
    Move(C[0], Result[L1 + L2], L3);
end;

function ConcatBytes(const A: TBytes; const B: TBytes; const C: TBytes; const D: TBytes): TBytes;
var
  L1, L2, L3, L4: Integer;
begin
  Result := nil;
  L1 := Length(A);
  L2 := Length(B);
  L3 := Length(C);
  L4 := Length(D);

  if (L1 = 0) and (L2 = 0) and (L3 = 0) and (L4 = 0) then
    Exit;

  SetLength(Result, L1 + L2 + L3 + L4);
  if L1 > 0 then
    Move(A[0], Result[0], L1);
  if L2 > 0 then
    Move(B[0], Result[L1], L2);
  if L3 > 0 then
    Move(C[0], Result[L1 + L2], L3);
  if L4 > 0 then
    Move(D[0], Result[L1 + L2 + L3], L4);
end;

function NewZeroBytes(ByteLen: Integer): TBytes;
begin
  if ByteLen > 0 then
  begin
    SetLength(Result, ByteLen);
    FillChar(Result[0], ByteLen, 0);
  end
  else
    Result := nil;
end;

function ConcatBytesMemory(const A: TBytes; Data: Pointer; DataByteLen: Integer): TBytes;
var
  L: Integer;
begin
  L := Length(A) + DataByteLen;
  if L > 0 then
  begin
    SetLength(Result, L);
    if Length(A) > 0 then
      Move(A[0], Result[0], Length(A));
    if (Data <> nil) and (DataByteLen > 0) then
      Move(Data^, Result[Length(A)], DataByteLen);
  end
  else
    Result := nil;
end;

function NewBytesFromMemory(Data: Pointer; DataByteLen: Integer): TBytes;
begin
  if (Data = nil) or (DataByteLen <= 0) then
    Result := nil
  else
  begin
    SetLength(Result, DataByteLen);
    Move(Data^, Result[0], DataByteLen);
  end;
end;

procedure PutBytesToMemory(const Data: TBytes; Mem: Pointer; MaxByteSize: Integer);
var
  L: Integer;
begin
  L := Length(Data);
  if (L > 0) and (Mem <> nil) then
  begin
    if (MaxByteSize > 0) and (L > MaxByteSize) then
      L := MaxByteSize;

    Move(Data[0], Mem^, L);
  end;
end;

function CompareBytes(const A, B: TBytes): Boolean;
var
  L: Integer;
begin
  Result := False;

  L := Length(A);
  if Length(B) <> L then // 长度不等则退出
    Exit;

  if L = 0 then          // 长度相等
    Result := True       // 如都是 0 视作相等
  else
    Result := CompareMem(@A[0], @B[0], L);
end;

function CompareBytes(const A, B: TBytes; MaxLength: Integer): Boolean;
var
  LA, LB: Integer;
begin
  Result := False;

  LA := Length(A);
  LB := Length(B);

  if LA > MaxLength then
    LA := MaxLength;
  if LB > MaxLength then
    LB := MaxLength;

  if LA <> LB then
    Exit;

  if LA = 0 then
    Result := True
  else
    Result := CompareMem(@A[0], @B[0], LA);
end;

function CompareBytesWithDiffIndex(const A, B: TBytes; out DiffIndex: Integer): Boolean;
var
  I: Integer;
  L1, L2: Integer;
begin
  L1 := Length(A);
  L2 := Length(B);
  DiffIndex := -1;
  Result := True;

  if L1 <> L2 then
  begin
    Result := False;
    Exit;
  end;

  if (L1 = 0) and (L2 = 0) then
    Exit;

  for I := 0 to L1 - 1 do
  begin
    if A[I] <> B[I] then
    begin
      Result := False;
      DiffIndex := I;
      Exit;
    end;
  end;
end;

function MoveMost(const Source; var Dest; ByteLen, MostLen: Integer): Integer;
begin
  if (MostLen <= 0) or (ByteLen <= 0) then
  begin
    Result := 0;
    Exit;
  end;

  if ByteLen > MostLen then
    ByteLen := MostLen
  else if ByteLen < MostLen then
  begin
    FillChar(Dest, MostLen, 0);

    // TODO: 要变为 FillChar(Dest + ByteLen, MostLen - ByteLen, 0); 以只填充不满的部分
  end;

  Move(Source, Dest, ByteLen);
  Result := ByteLen;
end;

// =============================== 算术右移 ===================================

function SarInt8(V: ShortInt; ShiftCount: Integer): ShortInt;
begin
  Result := V shr ShiftCount;
  if (V and $80) <> 0 then
    Result := Result or ($FF shl (8 - ShiftCount));
end;

function SarInt16(V: SmallInt; ShiftCount: Integer): SmallInt;
begin
  Result := V shr ShiftCount;
  if (V and $8000) <> 0 then
    Result := Result or ($FFFF shl (16 - ShiftCount));
end;

function SarInt32(V: Integer; ShiftCount: Integer): Integer;
begin
  Result := V shr ShiftCount;
  if (V and $80000000) <> 0 then
    Result := Result or Integer($FFFFFFFF shl (32 - ShiftCount));
end;

function SarInt64(V: Int64; ShiftCount: Integer): Int64;
begin
  Result := V shr ShiftCount;
  if (V and $8000000000000000) <> 0 then
    Result := Result or ($FFFFFFFFFFFFFFFF shl (64 - ShiftCount));
end;

procedure ConstTimeConditionalSwap8(CanSwap: Boolean; var A, B: Byte);
var
  T, V: Byte;
begin
  T := ConstTimeExpandBoolean8(CanSwap);
  V := (A xor B) and T;
  A := A xor V;
  B := B xor V;
end;

procedure ConstTimeConditionalSwap16(CanSwap: Boolean; var A, B: Word);
var
  T, V: Word;
begin
  T := ConstTimeExpandBoolean16(CanSwap);
  V := (A xor B) and T;
  A := A xor V;
  B := B xor V;
end;

procedure ConstTimeConditionalSwap32(CanSwap: Boolean; var A, B: Cardinal);
var
  T, V: Cardinal;
begin
  T := ConstTimeExpandBoolean32(CanSwap);
  V := (A xor B) and T;
  A := A xor V;
  B := B xor V;
end;

procedure ConstTimeConditionalSwap64(CanSwap: Boolean; var A, B: TUInt64);
var
  T, V: TUInt64;
begin
  T := ConstTimeExpandBoolean64(CanSwap);
  V := (A xor B) and T;
  A := A xor V;
  B := B xor V;
end;

function ConstTimeEqual8(A, B: Byte): Boolean;
var
  R: Byte;
begin
  R := not (A xor B);     // 异或后求反
  R := R and (R shr 4);   // 以下一半一半地与
  R := R and (R shr 2);   // 如果有一位出现 0
  R := R and (R shr 1);   // 最后结果就是 0
  Result := Boolean(R);   // 只有全 1 才是 1
end;

function ConstTimeEqual16(A, B: Word): Boolean;
begin
  Result := ConstTimeEqual8(Byte(A shr 8), Byte(B shr 8))
    and ConstTimeEqual8(Byte(A and $FF), Byte(B and $FF));
end;

function ConstTimeEqual32(A, B: Cardinal): Boolean;
begin
  Result := ConstTimeEqual16(Word(A shr 16), Word(B shr 16))
    and ConstTimeEqual16(Word(A and $FFFF), Word(B and $FFFF));
end;

function ConstTimeEqual64(A, B: TUInt64): Boolean;
begin
  Result := ConstTimeEqual32(Cardinal(A shr 32), Cardinal(B shr 32))
    and ConstTimeEqual32(Cardinal(A and $FFFFFFFF), Cardinal(B and $FFFFFFFF));
end;

function ConstTimeCompareMem(P1, P2: Pointer; ByteLength: Integer): Boolean;
var
  B1, B2: PByte;
  I: Integer;
  Diff: Byte;
begin
  Diff := 0;
  B1 := PByte(P1);
  B2 := PByte(P2);

  for I := 0 to ByteLength - 1 do
  begin
    Diff := Diff or (B1^ xor B2^);
    Inc(B1);
    Inc(B2);
  end;

  Result := Diff = 0;
end;

function ConstTimeCompareBytes(const A, B: TBytes): Boolean;
begin
  if Length(A) <> Length(B) then
    Result := False
  else
    Result := ConstTimeCompareMem(@A[0], @B[0], Length(A));
end;

function ConstTimeExpandBoolean8(V: Boolean): Byte;
begin
  Result := Byte(V);
  Result := not Result;                  // 如果 V 是 True，非 0，则此步 R 非纯 $FF，R 里头有 0
  Result := Result and (Result shr 4);   // 以下一半一半地与
  Result := Result and (Result shr 2);   // 如果有一位出现 0
  Result := Result and (Result shr 1);   // 最后结果就是 00000000，否则 00000001
  Result := Result or (Result shl 1);    // True 得到 00000000，False 得到 00000001，再往高位两倍两倍地扩
  Result := Result or (Result shl 2);
  Result := Result or (Result shl 4);    // 最终全 0 或 全 1
  Result := not Result;                  // 反成全 1 或全 0
end;

function ConstTimeExpandBoolean16(V: Boolean): Word;
var
  R: Byte;
begin
  R := ConstTimeExpandBoolean8(V);
  Result := R;
  Result := (Result shl 8) or R;         // 单字节全 1 或全 0 扩成双字节
end;

function ConstTimeExpandBoolean32(V: Boolean): Cardinal;
var
  R: Word;
begin
  R := ConstTimeExpandBoolean16(V);
  Result := R;
  Result := (Result shl 16) or R;        // 双字节全 1 或全 0 扩成四字节
end;

function ConstTimeExpandBoolean64(V: Boolean): TUInt64;
var
  R: Cardinal;
begin
  R := ConstTimeExpandBoolean32(V);
  Result := R;
  Result := (Result shl 32) or R;        // 四字节全 1 或全 0 扩成八字节
end;

function ConstTimeConditionalSelect8(Condition: Boolean; A, B: Byte): Byte;
begin
  ConstTimeConditionalSwap8(Condition, A, B);
  Result := B;
end;

function ConstTimeConditionalSelect16(Condition: Boolean; A, B: Word): Word;
begin
  ConstTimeConditionalSwap16(Condition, A, B);
  Result := B;
end;

function ConstTimeConditionalSelect32(Condition: Boolean; A, B: Cardinal): Cardinal;
begin
  ConstTimeConditionalSwap32(Condition, A, B);
  Result := B;
end;

function ConstTimeConditionalSelect64(Condition: Boolean; A, B: TUInt64): TUInt64;
begin
  ConstTimeConditionalSwap64(Condition, A, B);
  Result := B;
end;

{$IFDEF MSWINDOWS}

{$IFDEF CPUX64}

// 64 位汇编用 IDIV 和 IDIV 指令实现，其中 A 在 RCX 里，B 在 EDX/RDX 里，DivRes 地址在 R8 里，ModRes 地址在 R9 里
procedure Int64DivInt32Mod(A: Int64; B: Integer; var DivRes, ModRes: Integer); assembler;
asm
        PUSH    RCX                           // RCX 是 A
        MOV     RCX, RDX                      // 除数 B 放入 RCX
        POP     RAX                           // 被除数 A 放入 RAX
        XOR     RDX, RDX                      // 被除数高 64 位清零
        IDIV    RCX
        MOV     [R8], EAX                     // 商放入 R8 所指的 DivRes
        MOV     [R9], EDX                     // 余数放入 R9 所指的 ModRes
end;

procedure UInt64DivUInt32Mod(A: TUInt64; B: Cardinal; var DivRes, ModRes: Cardinal); assembler;
asm
        PUSH    RCX                           // RCX 是 A
        MOV     RCX, RDX                      // 除数 B 放入 RCX
        POP     RAX                           // 被除数 A 放入 RAX
        XOR     RDX, RDX                      // 被除数高 64 位清零
        DIV     RCX
        MOV     [R8], EAX                     // 商放入 R8 所指的 DivRes
        MOV     [R9], EDX                     // 余数放入 R9 所指的 ModRes
end;

// 64 位汇编用 IDIV 和 IDIV 指令实现，ALo 在 RCX，AHi 在 RDX，B 在 R8，DivRes 的地址在 R9，
procedure Int128DivInt64Mod(ALo, AHi: Int64; B: Int64; var DivRes, ModRes: Int64); assembler;
asm
        MOV     RAX, RCX                      // ALo 放入 RAX，AHi 已经在 RDX 了
        MOV     RCX, R8                       // B 放入 RCX
        IDIV    RCX
        MOV     [R9], RAX                     // 商放入 R9 所指的 DivRes
        MOV     RAX, [RBP + $30]              // ModRes 地址放入 RAX
        MOV     [RAX], RDX                    // 余数放入 RAX 所指的 ModRes
end;

procedure UInt128DivUInt64Mod(ALo, AHi: UInt64; B: UInt64; var DivRes, ModRes: UInt64); assembler;
asm
        MOV     RAX, RCX                      // ALo 放入 RAX，AHi 已经在 RDX 了
        MOV     RCX, R8                       // B 放入 RCX
        DIV     RCX
        MOV     [R9], RAX                     // 商放入 R9 所指的 DivRes
        MOV     RAX, [RBP + $30]              // ModRes 地址放入 RAX
        MOV     [RAX], RDX                    // 余数放入 RAX 所指的 ModRes
end;

{$ELSE}

// 32 位汇编用 IDIV 和 IDIV 指令实现，其中 A 在堆栈上，B 在 EAX，DivRes 地址在 EDX，ModRes 地址在 ECX
procedure Int64DivInt32Mod(A: Int64; B: Integer; var DivRes, ModRes: Integer); assembler;
asm
        PUSH    ECX                           // ECX 是 ModRes 地址，先保存
        MOV     ECX, B                        // B 在 EAX 中，搬移到 ECX 中
        PUSH    EDX                           // DivRes 的地址在 EDX 中，也保存
        MOV     EAX, [EBP + $8]               // A Lo
        MOV     EDX, [EBP + $C]               // A Hi
        IDIV    ECX
        POP     ECX                           // 弹出 ECX，拿到 DivRes 地址
        MOV     [ECX], EAX
        POP     ECX                           // 弹出 ECX，拿到 ModRes 地址
        MOV     [ECX], EDX
end;

procedure UInt64DivUInt32Mod(A: TUInt64; B: Cardinal; var DivRes, ModRes: Cardinal); assembler;
asm
        PUSH    ECX                           // ECX 是 ModRes 地址，先保存
        MOV     ECX, B                        // B 在 EAX 中，搬移到 ECX 中
        PUSH    EDX                           // DivRes 的地址在 EDX 中，也保存
        MOV     EAX, [EBP + $8]               // A Lo
        MOV     EDX, [EBP + $C]               // A Hi
        DIV     ECX
        POP     ECX                           // 弹出 ECX，拿到 DivRes 地址
        MOV     [ECX], EAX
        POP     ECX                           // 弹出 ECX，拿到 ModRes 地址
        MOV     [ECX], EDX
end;

// 32 位下的实现
procedure Int128DivInt64Mod(ALo, AHi: Int64; B: Int64; var DivRes, ModRes: Int64);
var
  C: Integer;
begin
  if B = 0 then
    raise EDivByZero.Create(SDivByZero);

  if (AHi = 0) or (AHi = $FFFFFFFFFFFFFFFF) then // 高 64 位为 0 的正值或负值
  begin
    DivRes := ALo div B;
    ModRes := ALo mod B;
  end
  else
  begin
    if B < 0 then // 除数是负数
    begin
      Int128DivInt64Mod(ALo, AHi, -B, DivRes, ModRes);
      DivRes := -DivRes;
      Exit;
    end;

    if AHi < 0 then // 被除数是负数
    begin
      // AHi, ALo 求反加 1，以得到正值
      AHi := not AHi;
      ALo := not ALo;
{$IFDEF SUPPORT_UINT64}
      UInt64Add(UInt64(ALo), UInt64(ALo), 1, C);
{$ELSE}
      UInt64Add(ALo, ALo, 1, C);
{$ENDIF}
      if C > 0 then
        AHi := AHi + C;

      // 被除数转正了
      Int128DivInt64Mod(ALo, AHi, B, DivRes, ModRes);

      // 结果再调整
      if ModRes = 0 then
        DivRes := -DivRes
      else
      begin
        DivRes := -DivRes - 1;
        ModRes := B - ModRes;
      end;
      Exit;
    end;

    // 全正后，按无符号来除
{$IFDEF SUPPORT_UINT64}
    UInt128DivUInt64Mod(TUInt64(ALo), TUInt64(AHi), TUInt64(B), TUInt64(DivRes), TUInt64(ModRes));
{$ELSE}
    UInt128DivUInt64Mod(ALo, AHi, B, DivRes, ModRes);
{$ENDIF}
  end;
end;

procedure UInt128DivUInt64Mod(ALo, AHi: TUInt64; B: TUInt64; var DivRes, ModRes: TUInt64);
var
  I, Cnt: Integer;
  Q, R: TUInt64;
begin
  if B = 0 then
    raise EDivByZero.Create(SDivByZero);

  if AHi = 0 then
  begin
    DivRes := UInt64Div(ALo, B);
    ModRes := UInt64Mod(ALo, B);
  end
  else
  begin
    // 有高位有低位咋办？先判断是否会溢出，如果 AHi >= B，则表示商要超 64 位，溢出
    if UInt64Compare(AHi, B) >= 0 then
      raise EIntOverflow.Create(SIntOverflow);

    Q := 0;
    R := 0;
    Cnt := GetUInt64LowBits(AHi) + 64;
    for I := Cnt downto 0 do
    begin
      R := R shl 1;
      if IsUInt128BitSet(ALo, AHi, I) then  // 被除数的第 I 位是否是 0
        R := R or 1
      else
        R := R and TUInt64(not 1);

      if UInt64Compare(R, B) >= 0 then
      begin
        R := R - B;
        Q := Q or (TUInt64(1) shl I);
      end;
    end;
    DivRes := Q;
    ModRes := R;
  end;
end;

{$ENDIF}

{$ENDIF}

{$IFDEF SUPPORT_UINT64}

// 只要支持 64 位无符号整数，无论 32/64 位 Intel 还是 ARM，无论 Delphi 还是 FPC，无论什么操作系统都能如此

function UInt64Mod(A, B: TUInt64): TUInt64;
begin
  Result := A mod B;
end;

function UInt64Div(A, B: TUInt64): TUInt64;
begin
  Result := A div B;
end;

{$ELSE}
{
  不支持 UInt64 的低版本 Delphi 下用 Int64 求 A mod/div B

  调用的入栈顺序是 A 的高位，A 的低位，B 的高位，B 的低位。挨个 push 完毕并进入函数后，
  ESP 是返回地址，ESP+4 是 B 的低位，ESP + 8 是 B 的高位，ESP + C 是 A 的低位，ESP + 10 是 A 的高位
  进入后 push esp 让 ESP 减了 4，然后 mov ebp esp，之后用 EBP 来寻址，全要多加 4

  而 System.@_llumod 要求在刚进入时，EAX <- A 的低位，EDX <- A 的高位，（System 源码注释中 EAX/EDX 写反了）
  [ESP + 8]（也就是 EBP + C）<- B 的高位，[ESP + 4] （也就是 EBP + 8）<- B 的低位

  所以 CALL 前加了四句搬移代码。UInt64 Div 的也类似
}
function UInt64Mod(A, B: TUInt64): TUInt64;
asm
        // PUSH ESP 让 ESP 减了 4，要补上
        MOV     EAX, [EBP + $10]              // A Lo
        MOV     EDX, [EBP + $14]              // A Hi
        PUSH    DWORD PTR[EBP + $C]           // B Hi
        PUSH    DWORD PTR[EBP + $8]           // B Lo
        CALL    System.@_llumod;
end;

function UInt64Div(A, B: TUInt64): TUInt64;
asm
        // PUSH ESP 让 ESP 减了 4，要补上
        MOV     EAX, [EBP + $10]              // A Lo
        MOV     EDX, [EBP + $14]              // A Hi
        PUSH    DWORD PTR[EBP + $C]           // B Hi
        PUSH    DWORD PTR[EBP + $8]           // B Lo
        CALL    System.@_lludiv;
end;

{$ENDIF}

{$IFDEF SUPPORT_UINT64}

// 只要支持 64 位无符号整数，无论 32/64 位 Intel 还是 ARM，无论 Delphi 还是 FPC，无论什么操作系统都能如此

function UInt64Mul(A, B: Cardinal): TUInt64;
begin
  Result := TUInt64(A) * B;
end;

{$ELSE} // 只有低版本 Delphi 会进这里，Win32 x86

{
  无符号 32 位整数相乘，如果结果直接使用 Int64 会溢出，模拟 64 位无符号运算

  调用寄存器约定是 A -> EAX，B -> EDX，不使用堆栈
  而 System.@_llmul 要求在刚进入时，EAX <- A 的低位，EDX <- A 的高位 0，
  [ESP + 8]（也就是 EBP + C）<- B 的高位 0，[ESP + 4] （也就是 EBP + 8）<- B 的低位
}
function UInt64Mul(A, B: Cardinal): TUInt64;
asm
        PUSH    0               // PUSH B 高位 0
        PUSH    EDX             // PUSH B 低位
                                // EAX A 低位，已经是了
        XOR     EDX, EDX        // EDX A 高位 0
        CALL    System.@_llmul; // 返回 EAX 低 32 位、EDX 高 32 位
end;

{$ENDIF}

// 两个无符号 64 位整数相加，处理溢出的情况，结果放 ResLo 与 ResHi 中
procedure UInt64AddUInt64(A, B: TUInt64; var ResLo, ResHi: TUInt64);
var
  X, Y, Z, T, R0L, R0H, R1L, R1H: Cardinal;
  R0, R1, R01, R12: TUInt64;
begin
  // 基本思想：2^32 是系数 M，拆成 (xM+y) + (zM+t) = (x+z) M + (y+t)
  // y+t 是 R0 占 0、1，x+z 是 R1 占 1、2，把 R0, R1 再拆开相加成 R01, R12
  if IsUInt64AddOverflow(A, B) then
  begin
    X := Int64Rec(A).Hi;
    Y := Int64Rec(A).Lo;
    Z := Int64Rec(B).Hi;
    T := Int64Rec(B).Lo;

    R0 := TUInt64(Y) + TUInt64(T);
    R1 := TUInt64(X) + TUInt64(Z);

    R0L := Int64Rec(R0).Lo;
    R0H := Int64Rec(R0).Hi;
    R1L := Int64Rec(R1).Lo;
    R1H := Int64Rec(R1).Hi;

    R01 := TUInt64(R0H) + TUInt64(R1L);
    R12 := TUInt64(R1H) + TUInt64(Int64Rec(R01).Hi);

    Int64Rec(ResLo).Lo := R0L;
    Int64Rec(ResLo).Hi := Int64Rec(R01).Lo;
    Int64Rec(ResHi).Lo := Int64Rec(R12).Lo;
    Int64Rec(ResHi).Hi := Int64Rec(R12).Hi;
  end
  else
  begin
    ResLo := A + B;
    ResHi := 0;
  end;
end;

{$IFDEF WIN64}  // 注意 Linux 64 下不支持 ASM，只能 WIN64

// 64 位下两个无符号 64 位整数相乘，结果放 ResLo 与 ResHi 中，直接用汇编实现，比下面快了一倍以上
procedure UInt64MulUInt64(A, B: UInt64; var ResLo, ResHi: UInt64); assembler;
asm
  PUSH RAX
  MOV RAX, RCX
  MUL RDX         // 得用无符号，不能用有符号的 IMUL
  MOV [R8], RAX
  MOV [R9], RDX
  POP RAX
end;

{$ELSE}

// 两个无符号 64 位整数相乘，结果放 ResLo 与 ResHi 中
procedure UInt64MulUInt64(A, B: TUInt64; var ResLo, ResHi: TUInt64);
var
  X, Y, Z, T: Cardinal;
  YT, XT, ZY, ZX: TUInt64;
  P, R1Lo, R1Hi, R2Lo, R2Hi: TUInt64;
begin
  // 基本思想：2^32 是系数 M，拆成 (xM+y)*(zM+t) = xzM^2 + (xt+yz)M + yt
  // 各项系数都是 UInt64，xz 占 2、3、4，xt+yz 占 1、2、3，yt 占 0、1，然后累加
  X := Int64Rec(A).Hi;
  Y := Int64Rec(A).Lo;
  Z := Int64Rec(B).Hi;
  T := Int64Rec(B).Lo;

  YT := UInt64Mul(Y, T);
  XT := UInt64Mul(X, T);
  ZY := UInt64Mul(Y, Z);
  ZX := UInt64Mul(X, Z);

  Int64Rec(ResLo).Lo := Int64Rec(YT).Lo;

  P := Int64Rec(YT).Hi;
  UInt64AddUInt64(P, XT, R1Lo, R1Hi);
  UInt64AddUInt64(ZY, R1Lo, R2Lo, R2Hi);

  Int64Rec(ResLo).Hi := Int64Rec(R2Lo).Lo;

  P := TUInt64(Int64Rec(R2Lo).Hi) + TUInt64(Int64Rec(ZX).Lo);

  Int64Rec(ResHi).Lo := Int64Rec(P).Lo;
  Int64Rec(ResHi).Hi := Int64Rec(R1Hi).Lo + Int64Rec(R2Hi).Lo + Int64Rec(ZX).Hi + Int64Rec(P).Hi;
end;

{$ENDIF}

{$HINTS OFF}

function _ValUInt64(const S: string; var Code: Integer): TUInt64;
const
  FirstIndex = 1;
var
  I: Integer;
  Dig: Integer;
  Sign: Boolean;
  Empty: Boolean;
begin
  I := FirstIndex;
  Dig := 0; 
  Result := 0;

  if S = '' then
  begin
    Code := 1;
    Exit;
  end;

  while S[I] = Char(' ') do
    Inc(I);
  Sign := False;

  if S[I] =  Char('-') then
  begin
    Sign := True;
    Code := 1; // 不支持负数
    Inc(I);
  end
  else if S[I] =  Char('+') then
    Inc(I);
  Empty := True;

  if (S[I] =  Char('$')) or (UpCase(S[I]) =  Char('X'))
    or ((S[I] =  Char('0')) and (I < Length(S)) and (UpCase(S[I + 1]) =  Char('X'))) then
  begin
    if S[I] =  Char('0') then
      Inc(I);
    Inc(I);
    while True do
    begin
      if I > Length(S) then
        Break;
      case Char(S[I]) of
        Char('0').. Char('9'): Dig := Ord(S[I]) - Ord('0');
        Char('A').. Char('F'): Dig := Ord(S[I]) - (Ord('A') - 10);
        Char('a').. Char('f'): Dig := Ord(S[I]) - (Ord('a') - 10);
      else
        Break;
      end;

      if Result > (CN_MAX_TUINT64 shr 4) then
        Break;
      if Sign and (Dig <> 0) then
        Break;

      Result := Result shl 4 + TUInt64(Dig);
      Inc(I);
      Empty := False;
    end;
  end
  else
  begin
    while True do
    begin
      if I > Length(S) then
        Break;
      case Char(S[I]) of
        Char('0').. Char('9'): Dig := Ord(S[I]) - Ord('0');
      else
        Break;
      end;

      if Result > UInt64Div(CN_MAX_TUINT64, 10) then
        Break;
      if Sign and (Dig <> 0) then
        Break;

      Result := Result * 10 + TUInt64(Dig);
      Inc(I);
      Empty := False;
    end;
  end;

  if ((I <= Length(S)) and (S[I] <> Char(#0))) or Empty then
    Code := I + 1 - FirstIndex
  else
    Code := 0;
end;

function _ValUInt32(const S: string; var Code: Integer): Cardinal;
const
  FirstIndex = 1;
var
  I: Integer;
  Dig: Integer;
  Sign: Boolean;
  Empty: Boolean;
begin
  I := FirstIndex;
  Dig := 0; 
  Result := 0;

  if S = '' then
  begin
    Code := 1;
    Exit;
  end;

  while S[I] = Char(' ') do
    Inc(I);
  Sign := False;

  if S[I] =  Char('-') then
  begin
    Sign := True;
    Code := 1; // 不支持负数
    Inc(I);
  end
  else if S[I] =  Char('+') then
    Inc(I);
  Empty := True;

  if (S[I] =  Char('$')) or (UpCase(S[I]) =  Char('X'))
    or ((S[I] =  Char('0')) and (I < Length(S)) and (UpCase(S[I + 1]) =  Char('X'))) then
  begin
    if S[I] =  Char('0') then
      Inc(I);
    Inc(I);
    while True do
    begin
      if I > Length(S) then
        Break;
      case Char(S[I]) of
        Char('0').. Char('9'): Dig := Ord(S[I]) - Ord('0');
        Char('A').. Char('F'): Dig := Ord(S[I]) - (Ord('A') - 10);
        Char('a').. Char('f'): Dig := Ord(S[I]) - (Ord('a') - 10);
      else
        Break;
      end;

      if Result > (CN_MAX_UINT32 shr 4) then
        Break;
      if Sign and (Dig <> 0) then
        Break;

      Result := Result shl 4 + Cardinal(Dig);
      Inc(I);
      Empty := False;
    end;
  end
  else
  begin
    while True do
    begin
      if I > Length(S) then
        Break;
      case Char(S[I]) of
        Char('0').. Char('9'): Dig := Ord(S[I]) - Ord('0');
      else
        Break;
      end;

      if Result > (CN_MAX_UINT32 div 10) then
        Break;
      if Sign and (Dig <> 0) then
        Break;

      Result := Result * 10 + Cardinal(Dig);
      Inc(I);
      Empty := False;
    end;
  end;

  if ((I <= Length(S)) and (S[I] <> Char(#0))) or Empty then
    Code := I + 1 - FirstIndex
  else
    Code := 0;
end;

{$HINTS ON}

function UInt64ToHex(N: TUInt64; RemoveZeroPrefix: Boolean): string;
const
  Digits: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7',
                                  '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');

  function HC(B: Byte): string;
  begin
    Result := string(Digits[(B shr 4) and $0F] + Digits[B and $0F]);
  end;

begin
  Result :=
      HC(Byte((N and $FF00000000000000) shr 56))
    + HC(Byte((N and $00FF000000000000) shr 48))
    + HC(Byte((N and $0000FF0000000000) shr 40))
    + HC(Byte((N and $000000FF00000000) shr 32))
    + HC(Byte((N and $00000000FF000000) shr 24))
    + HC(Byte((N and $0000000000FF0000) shr 16))
    + HC(Byte((N and $000000000000FF00) shr 8))
    + HC(Byte((N and $00000000000000FF)));

  if RemoveZeroPrefix then
  begin
    while (Length(Result) > 1) and (Result[1] = '0') do
      Delete(Result, 1, 1);
  end;
end;

function UInt64ToStr(N: TUInt64): string;
begin
  Result := Format('%u', [N]);
end;

function StrToUInt64(const S: string): TUInt64;
{$IFNDEF DELPHIXE6_UP}
var
  E: Integer;
{$ENDIF}
begin
{$IFDEF DELPHIXE6_UP}
  Result := SysUtils.StrToUInt64(S);  // StrToUInt64 only exists under XE6 or above
{$ELSE}
  Result := _ValUInt64(S, E);
  if E <> 0 then raise EConvertError.CreateResFmt(@SInvalidInteger, [S]);
{$ENDIF}
end;

function StrToUInt(const S: string): Cardinal;
{$IFNDEF DELPHI102_TOKYO_UP}
var
  E: Integer;
{$ENDIF}
begin
{$IFDEF DELPHI102_TOKYO_UP}
  Result := SysUtils.StrToUInt(S);  // StrToUInt only exists under D102T or above
{$ELSE}
  Result := _ValUInt32(S, E);
  if E <> 0 then raise EConvertError.CreateResFmt(@SInvalidInteger, [S]);
{$ENDIF}
end;

function UInt64Compare(A, B: TUInt64): Integer;
{$IFNDEF SUPPORT_UINT64}
var
  HiA, HiB, LoA, LoB: Cardinal;
{$ENDIF}
begin
{$IFDEF SUPPORT_UINT64}
  if A > B then
    Result := 1
  else if A < B then
    Result := -1
  else
    Result := 0;
{$ELSE}
  HiA := (A and $FFFFFFFF00000000) shr 32;
  HiB := (B and $FFFFFFFF00000000) shr 32;
  if HiA > HiB then
    Result := 1
  else if HiA < HiB then
    Result := -1
  else
  begin
    LoA := Cardinal(A and $00000000FFFFFFFF);
    LoB := Cardinal(B and $00000000FFFFFFFF);
    if LoA > LoB then
      Result := 1
    else if LoA < LoB then
      Result := -1
    else
      Result := 0;
  end;
{$ENDIF}
end;

function UInt64Sqrt(N: TUInt64): TUInt64;
var
  Rem, Root: TUInt64;
  I: Integer;
begin
  Result := 0;
  if N = 0 then
    Exit;

  if UInt64Compare(N, 4) < 0 then
  begin
    Result := 1;
    Exit;
  end;

  Rem := 0;
  Root := 0;

  for I := 0 to 31 do
  begin
    Root := Root shl 1;
    Inc(Root);

    Rem := Rem shl 2;
    Rem := Rem or (N shr 62);
    N := N shl 2;

    if UInt64Compare(Root, Rem) <= 0 then
    begin
      Rem := Rem - Root;
      Inc(Root);
    end
    else
      Dec(Root);
  end;
  Result := Root shr 1;
end;

function UInt32IsNegative(N: Cardinal): Boolean;
begin
  Result := (N and (1 shl 31)) <> 0;
end;

function UInt64IsNegative(N: TUInt64): Boolean;
begin
{$IFDEF SUPPORT_UINT64}
  Result := (N and (UInt64(1) shl 63)) <> 0;
{$ELSE}
  Result := N < 0;
{$ENDIF}
end;

// 给 UInt64 的某一位置 1，位 Index 从 0 开始
procedure UInt64SetBit(var B: TUInt64; Index: Integer);
begin
  B := B or (TUInt64(1) shl Index);
end;

// 给 UInt64 的某一位置 0，位 Index 从 0 开始
procedure UInt64ClearBit(var B: TUInt64; Index: Integer);
begin
  B := B and not (TUInt64(1) shl Index);
end;

// 返回 UInt64 的第几位是否是 1，0 开始
function GetUInt64BitSet(B: TUInt64; Index: Integer): Boolean;
begin
  B := B and (TUInt64(1) shl Index);
  Result := B <> 0;
end;

// 返回 UInt64 的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1
function GetUInt64HighBits(B: TUInt64): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 63 downto 0 do
  begin
    if (B and (TUInt64(1) shl I)) <> 0 then // 这里必须加 TUInt64 强制转换，否则会得出 8 的最高二进制位为 35 的错误结果
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 Cardinal 的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1
function GetUInt32HighBits(B: Cardinal): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 31 downto 0 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 Word 的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1
function GetUInt16HighBits(B: Word): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 15 downto 0 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 Byte 的是 1 的最高二进制位是第几位，最低位是 0，如果没有 1，返回 -1
function GetUInt8HighBits(B: Byte): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 7 downto 0 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 64 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0
function GetUInt64BitLength(B: TUInt64): Integer;
begin
  Result := 1 + GetUInt64HighBits(B);
end;

// 返回 32 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0
function GetUInt32BitLength(B: Cardinal): Integer;
begin
  Result := 1 + GetUInt32HighBits(B);
end;

// 返回 16 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0
function GetUInt16BitLength(B: Word): Integer;
begin
  Result := 1 + GetUInt16HighBits(B);
end;

// 返回 8 位整数去掉高位 0 后剩下的位长度，如果没有 1，返回 0
function GetUInt8BitLength(B: Byte): Integer;
begin
  Result := 1 + GetUInt8HighBits(B);
end;

// 返回 UInt64 的是 1 的最低二进制位是第几位，最低位是 0，如果没有 1，返回 -1
function GetUInt64LowBits(B: TUInt64): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 0 to 63 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 Cardinal 的是 1 的最低二进制位是第几位，最低位是 0，如果没有 1，返回 -1
function GetUInt32LowBits(B: Cardinal): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 0 to 31 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 Word 的是 1 的最低二进制位是第几位，最低位是 0，基本等同于末尾几个 0。如果没有 1，返回 -1
function GetUInt16LowBits(B: Word): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 0 to 15 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 返回 Byte 的是 1 的最低二进制位是第几位，最低位是 0，基本等同于末尾几个 0。如果没有 1，返回 -1
function GetUInt8LowBits(B: Byte): Integer;
var
  I: Integer;
begin
  Result := -1;
  if B = 0 then
    Exit;

  for I := 0 to 7 do
  begin
    if (B and (1 shl I)) <> 0 then
    begin
      Result := I;
      Break;
    end;
  end;
end;

// 封装的 Int64 Mod，碰到负值时取反求模再模减
function Int64Mod(M, N: Int64): Int64;
begin
  if M > 0 then
    Result := M mod N
  else
    Result := N - ((-M) mod N);
end;

function Int64CenterMod(A: Int64; N: Int64): Int64;
begin
  Result := Int64NonNegativeMod(A, N);
  if Result > N div 2 then // 高半部分直接减 N
    Result := Result - N;
end;

// 判断一 32 位无符号整数是否 2 的整数次幂
function IsUInt32PowerOf2(N: Cardinal): Boolean;
begin
  Result := (N and (N - 1)) = 0;
end;

// 判断一 64 位无符号整数是否 2 的整数次幂
function IsUInt64PowerOf2(N: TUInt64): Boolean;
begin
  Result := (N and (N - 1)) = 0;
end;

// 得到一比指定 32 位无符号整数数大或等的 2 的整数次幂，如溢出则返回 0
function GetUInt32PowerOf2GreaterEqual(N: Cardinal): Cardinal;
begin
  Result := N - 1;
  Result := Result or (Result shr 1);
  Result := Result or (Result shr 2);
  Result := Result or (Result shr 4);
  Result := Result or (Result shr 8);
  Result := Result or (Result shr 16);
  Inc(Result);
end;

// 得到一比指定 64 位无符号整数数大的 2 的整数次幂，如溢出则返回 0
function GetUInt64PowerOf2GreaterEqual(N: TUInt64): TUInt64;
begin
  Result := N - 1;
  Result := Result or (Result shr 1);
  Result := Result or (Result shr 2);
  Result := Result or (Result shr 4);
  Result := Result or (Result shr 8);
  Result := Result or (Result shr 16);
  Result := Result or (Result shr 32);
  Inc(Result);
end;

// 判断两个 32 位有符号整数相加是否溢出 32 位有符号整数上限
function IsInt32AddOverflow(A, B: Integer): Boolean;
var
  C: Integer;
begin
  C := A + B;
  Result := ((A > 0) and (B > 0) and (C < 0)) or   // 同符号且结果换号了说明出现了溢出
    ((A < 0) and (B < 0) and (C > 0));
end;

// 判断两个 32 位无符号整数相加是否溢出 32 位无符号整数上限
function IsUInt32AddOverflow(A, B: Cardinal): Boolean;
begin
  Result := (A + B) < A; // 无符号相加，结果只要小于任一个数就说明溢出了
end;

// 判断两个 64 位有符号整数相加是否溢出 64 位有符号整数上限
function IsInt64AddOverflow(A, B: Int64): Boolean;
var
  C: Int64;
begin
  C := A + B;
  Result := ((A > 0) and (B > 0) and (C < 0)) or   // 同符号且结果换号了说明出现了溢出
    ((A < 0) and (B < 0) and (C > 0));
end;

// 判断两个 64 位无符号整数相加是否溢出 64 位无符号整数上限
function IsUInt64AddOverflow(A, B: TUInt64): Boolean;
begin
  Result := UInt64Compare(A + B, A) < 0; // 无符号相加，结果只要小于任一个数就说明溢出了
end;

function IsUInt64SubOverflowInt32(A: TUInt64; B: TUInt64): Boolean;
var
  GT: Boolean;
  R: TUInt64;
begin
  GT := UInt64Compare(A, B) >= 0; // GT 表示 A >= B
  if GT then
  begin
    R := A - B;
    // 判断 64 位无符号范围内 R 是否超过 MaxInt32
    Result := UInt64Compare(R, TUInt64(CN_MAX_INT32)) > 0;
  end
  else
  begin
    R := B - A;
    // 判断 64 位有符号范围内 -R 是否小于 MinInt32，也就是判断 64 位无符号 R 是否超过 MinInt32 的无符号形式
    Result := UInt64Compare(R, CN_MIN_INT32_IN_INT64) > 0;
  end;
end;

// 两个 64 位无符号整数相加，A + B => R，如果有溢出，则溢出的 1 搁进位标记里，否则清零
procedure UInt64Add(var R: TUInt64; A, B: TUInt64; out Carry: Integer);
begin
  R := A + B;
  if UInt64Compare(R, A) < 0 then // 无符号相加，结果只要小于任一个数就说明溢出了
    Carry := 1
  else
    Carry := 0;
end;

// 两个 64 位无符号整数相减，A - B => R，如果不够减有借位，则借的 1 搁借位标记里，否则清零
procedure UInt64Sub(var R: TUInt64; A, B: TUInt64; out Carry: Integer);
begin
  R := A - B;
  if UInt64Compare(R, A) > 0 then // 无符号相减，结果只要大于被减数就说明借位了
    Carry := 1
  else
    Carry := 0;
end;

// 判断两个 32 位有符号整数相乘是否溢出 32 位有符号整数上限
function IsInt32MulOverflow(A, B: Integer): Boolean;
var
  T: Integer;
begin
  T := A * B;
  Result := (B <> 0) and ((T div B) <> A);
end;

// 判断两个 32 位无符号整数相乘是否溢出 32 位无符号整数上限
function IsUInt32MulOverflow(A, B: Cardinal): Boolean;
var
  T: TUInt64;
begin
  T := TUInt64(A) * TUInt64(B);
  Result := (T = Cardinal(T));
end;

// 判断两个 32 位无符号整数相乘是否溢出 64 位有符号整数，如未溢出也即返回 False 时，R 中直接返回结果
function IsUInt32MulOverflowInt64(A, B: Cardinal; out R: TUInt64): Boolean;
var
  T: Int64;
begin
  T := Int64(A) * Int64(B);
  Result := T < 0; // 如果出现 Int64 负值则说明溢出
  if not Result then
    R := TUInt64(T);
end;

// 判断两个 64 位有符号整数相乘是否溢出 64 位有符号整数上限
function IsInt64MulOverflow(A, B: Int64): Boolean;
var
  T: Int64;
begin
  T := A * B;
  Result := (B <> 0) and ((T div B) <> A);
end;

// 指针类型转换成整型，支持 32/64 位
function PointerToInteger(P: Pointer): Integer;
begin
{$IFDEF CPU64BITS}
  // 先这么写，利用 Pointer 的低 32 位存 Integer
  Result := Integer(P);
{$ELSE}
  Result := Integer(P);
{$ENDIF}
end;

// 整型转换成指针类型，支持 32/64 位
function IntegerToPointer(I: Integer): Pointer;
begin
{$IFDEF CPU64BITS}
  // 先这么写，利用 Pointer 的低 32 位存 Integer
  Result := Pointer(I);
{$ELSE}
  Result := Pointer(I);
{$ENDIF}
end;

// 求 Int64 范围内俩加数的和求余，处理溢出的情况，要求 N 大于 0
function Int64NonNegativeAddMod(A, B, N: Int64): Int64;
begin
  if IsInt64AddOverflow(A, B) then // 如果加起来溢出 Int64
  begin
    if A > 0 then
    begin
      // A 和 B 都大于 0，采用 UInt64 相加取模（和未溢出 UInt64 上限），注意 N 未溢出 Int64 因此取模结果小于 Int64 上限，不会变成负值
      Result := UInt64NonNegativeAddMod(A, B, N);
    end
    else
    begin
      // A 和 B 都小于 0，取反后采用 UInt64 相加取模（反后的和未溢出 UInt64 上限），模再被除数减一下
{$IFDEF SUPPORT_UINT64}
      Result := UInt64(N) - UInt64NonNegativeAddMod(-A, -B, N);
{$ELSE}
      Result := N - UInt64NonNegativeAddMod(-A, -B, N);
{$ENDIF}
    end;
  end
  else // 不溢出，直接加起来求余
    Result := Int64NonNegativeMod(A + B, N);
end;

// 求 UInt64 范围内俩加数的和求余，处理溢出的情况，要求 N 大于 0
function UInt64NonNegativeAddMod(A, B, N: TUInt64): TUInt64;
var
  C, D: TUInt64;
begin
  if IsUInt64AddOverflow(A, B) then // 如果加起来溢出
  begin
    C := UInt64Mod(A, N);  // 就各自求模
    D := UInt64Mod(B, N);
    if IsUInt64AddOverflow(C, D) then
    begin
      // 如果还是溢出，说明模比两个加数都大，各自求模没用。
      // 至少有一个加数大于等于 2^63，N 至少是 2^63 + 1
      // 和 = 溢出结果 + 2^64
      // 和 mod N = 溢出结果 mod N + (2^64 - 1) mod N) + 1
      // 这里 N 至少是 2^63 + 1，溢出结果最多是 2^64 - 2，所以前两项相加不会溢出，可以直接相加后减一再求模
      Result := UInt64Mod(UInt64Mod(A + B, N) + UInt64Mod(CN_MAX_TUINT64, N) + 1, N);
    end
    else
      Result := UInt64Mod(C + D, N);
  end
  else
  begin
    Result := UInt64Mod(A + B, N);
  end;
end;

function Int64NonNegativeMulMod(A, B, N: Int64): Int64;
var
  Neg: Boolean;
begin
  if N <= 0 then
    raise EDivByZero.Create(SDivByZero);

  // 范围小就直接算
  if not IsInt64MulOverflow(A, B) then
  begin
    Result := A * B mod N;
    if Result < 0 then
      Result := Result + N;
    Exit;
  end;

  // 调整符号到正
  Result := 0;
  if (A = 0) or (B = 0) then
    Exit;

  Neg := False;
  if (A < 0) and (B > 0) then
  begin
    A := -A;
    Neg := True;
  end
  else if (A > 0) and (B < 0) then
  begin
    B := -B;
    Neg := True;
  end
  else if (A < 0) and (B < 0) then
  begin
    A := -A;
    B := -B;
  end;

  // 移位循环算
  while B <> 0 do
  begin
    if (B and 1) <> 0 then
      Result := ((Result mod N) + (A mod N)) mod N;

    A := A shl 1;
    if A >= N then
      A := A mod N;

    B := B shr 1;
  end;

  if Neg then
    Result := N - Result;
end;

function UInt64NonNegativeMulMod(A, B, N: TUInt64): TUInt64;
begin
  Result := 0;
  if (UInt64Compare(A, CN_MAX_UINT32) <= 0) and (UInt64Compare(B, CN_MAX_UINT32) <= 0) then
  begin
    Result := UInt64Mod(A * B, N); // 足够小的话直接乘后求模
  end
  else
  begin
    while B <> 0 do
    begin
      if (B and 1) <> 0 then
        Result := UInt64NonNegativeAddMod(Result, A, N);

      A := UInt64NonNegativeAddMod(A, A, N);
      // 不能用传统算法里的 A := A shl 1，大于 N 后再 mod N，因为会溢出

      B := B shr 1;
    end;
  end;
end;

// 封装的非负求余函数，也就是余数为负时，加个除数变正，调用者需保证 P 大于 0
function Int64NonNegativeMod(N: Int64; P: Int64): Int64;
begin
  if P <= 0 then
    raise EDivByZero.Create(SDivByZero);

  Result := N mod P;
  if Result < 0 then
    Inc(Result, P);
end;

// Int64 的非负整数指数幂
function Int64NonNegativPower(N: Int64; Exp: Integer): Int64;
var
  T: Int64;
begin
  if Exp < 0 then
    raise ERangeError.Create(SRangeError)
  else if Exp = 0 then
  begin
    if N <> 0 then
      Result := 1
    else
      raise EDivByZero.Create(SDivByZero);
  end
  else if Exp = 1 then
    Result := N
  else
  begin
    Result := 1;
    T := N;

    while Exp > 0 do
    begin
      if (Exp and 1) <> 0 then
        Result := Result * T;

      Exp := Exp shr 1;
      T := T * T;
    end;
  end;
end;

function Int64NonNegativeRoot(N: Int64; Exp: Integer): Int64;
var
  I: Integer;
  X: Int64;
  X0, X1: Extended;
begin
  if (Exp < 0) or (N < 0) then
    raise ERangeError.Create(SRangeError)
  else if Exp = 0 then
    raise EDivByZero.Create(SDivByZero)
  else if (N = 0) or (N = 1) then
    Result := N
  else if Exp = 2 then
    Result := UInt64Sqrt(N)
  else
  begin
    // 牛顿迭代法求根
    I := GetUInt64HighBits(N) + 1; // 得到大约 Log2 N 的值
    I := (I div Exp) + 1;
    X := 1 shl I;                  // 得到一个较大的 X0 值作为起始值

    X0 := X;
    X1 := X0 - (Power(X0, Exp) - N) / (Exp * Power(X0, Exp - 1));

    while True do
    begin
      if (Trunc(X0) = Trunc(X1)) and (Abs(X0 - X1) < 0.001) then
      begin
        Result := Trunc(X1); // Trunc 只支持 Int64，超界了会出错
        Exit;
      end;

      X0 := X1;
      X1 := X0 - (Power(X0, Exp) - N) / (Exp * Power(X0, Exp - 1));
    end;
  end;
end;

function UInt64NonNegativPower(N: TUInt64; Exp: Integer): TUInt64;
var
  T, RL, RH: TUInt64;
begin
  if Exp < 0 then
    raise ERangeError.Create(SRangeError)
  else if Exp = 0 then
  begin
    if N <> 0 then
      Result := 1
    else
      raise EDivByZero.Create(SDivByZero);
  end
  else if Exp = 1 then
    Result := N
  else
  begin
    Result := 1;
    T := N;

    while Exp > 0 do
    begin
      if (Exp and 1) <> 0 then
      begin
        UInt64MulUInt64(Result, T, RL, RH);
        Result := RL;
      end;

      Exp := Exp shr 1;
      UInt64MulUInt64(T, T, RL, RH);
      T := RL;
    end;
  end;
end;

function UInt64NonNegativeRoot(N: TUInt64; Exp: Integer): TUInt64;
var
  Bits: Integer;
  L, H, M, B, P: TUInt64;
  Cmp: Integer;
  Overflow: Boolean;
  E: Integer;
begin
  if Exp < 0 then
    raise ERangeError.Create(SRangeError)
  else if Exp = 0 then
    raise EDivByZero.Create(SDivByZero)
  else if (N = 0) or (N = 1) then
    Result := N
  else if Exp = 1 then
    Result := N
  else if Exp = 2 then
    Result := UInt64Sqrt(N)
  else
  begin
    // 整数二分查找 根值区间；
    // 用 整数快速幂 + 溢出前判断 比较 M^Exp 与 N ；
    // 最终返回 floor(N^(1/Exp))

    Bits := GetUInt64HighBits(N) + 1; // 得到大约 Log2 N 的值
    H := TUInt64(1) shl ((Bits + Exp - 1) div Exp);
    if H = 0 then
      H := N
    else if H > N then
      H := N;
    L := 1;
    Cmp := -1;

    while L <= H do
    begin
      M := L + ((H - L) shr 1);
      B := M;
      P := 1;
      E := Exp;
      Overflow := False;
      while E > 0 do
      begin
        if (E and 1) <> 0 then
        begin
          if (B <> 0) and (P > N div B) then
          begin
            Overflow := True;
            Break;
          end;
          P := P * B;
        end;
        E := E shr 1;
        if E > 0 then
        begin
          if (B <> 0) and (B > N div B) then
          begin
            Overflow := True;
            Break;
          end;
          B := B * B;
        end;
      end;

      if Overflow then
        Cmp := 1
      else if P > N then
        Cmp := 1
      else if P < N then
        Cmp := -1
      else
        Cmp := 0;

      if Cmp = 0 then
      begin
        Result := M;
        Exit;
      end
      else if Cmp < 0 then
        L := M + 1
      else
      begin
        if M = 0 then
          Break;
        H := M - 1;
      end;
    end;

    if Cmp > 0 then
      Result := H
    else
      Result := L - 1;
  end;
end;

function IsUInt128BitSet(Lo, Hi: TUInt64; N: Integer): Boolean;
begin
  if N < 64 then
    Result := (Lo and (TUInt64(1) shl N)) <> 0
  else
  begin
    Dec(N, 64);
    Result := (Hi and (TUInt64(1) shl N)) <> 0;
  end;
end;

procedure SetUInt128Bit(var Lo, Hi: TUInt64; N: Integer);
begin
  if N < 64 then
    Lo := Lo or (TUInt64(1) shl N)
  else
  begin
    Dec(N, 64);
    Hi := Hi or (TUInt64(1) shl N);
  end;
end;

procedure ClearUInt128Bit(var Lo, Hi: TUInt64; N: Integer);
begin
  if N < 64 then
    Lo := Lo and not (TUInt64(1) shl N)
  else
  begin
    Dec(N, 64);
    Hi := Hi and not (TUInt64(1) shl N);
  end;
end;

function UnsignedAddWithLimitRadix(A, B, C: Cardinal; var R: Cardinal;
  L, H: Cardinal): Cardinal;
begin
  R := A + B + C;
  if R > H then         // 有进位
  begin
    A := H - L + 1;     // 得到进制
    B := R - L;         // 得到超出 L 的值

    Result := B div A;  // 超过进制的第几倍就进几
    R := L + (B mod A); // 去掉进制后的余数，加上下限
  end
  else
    Result := 0;
end;

procedure InternalQuickSort(Mem: Pointer; L, R: Integer; ElementByteSize: Integer;
  CompareProc: TCnMemSortCompareProc);
var
  I, J, P: Integer;
begin
  repeat
    I := L;
    J := R;
    P := (L + R) shr 1;
    repeat
      while CompareProc(Pointer(TCnIntAddress(Mem) + I * ElementByteSize),
        Pointer(TCnIntAddress(Mem) + P * ElementByteSize), ElementByteSize) < 0 do
        Inc(I);
      while CompareProc(Pointer(TCnIntAddress(Mem) + J * ElementByteSize),
        Pointer(TCnIntAddress(Mem) + P * ElementByteSize), ElementByteSize) > 0 do
        Dec(J);

      if I <= J then
      begin
        MemorySwap(Pointer(TCnIntAddress(Mem) + I * ElementByteSize),
          Pointer(TCnIntAddress(Mem) + J * ElementByteSize), ElementByteSize);

        if P = I then
          P := J
        else if P = J then
          P := I;
        Inc(I);
        Dec(J);
      end;
    until I > J;

    if L < J then
      InternalQuickSort(Mem, L, J, ElementByteSize, CompareProc);
    L := I;
  until I >= R;
end;

function DefaultCompareProc(P1, P2: Pointer; ElementByteSize: Integer): Integer;
begin
  Result := MemoryCompare(P1, P2, ElementByteSize);
end;

procedure MemoryQuickSort(Mem: Pointer; ElementByteSize: Integer;
  ElementCount: Integer; CompareProc: TCnMemSortCompareProc);
begin
  if (Mem <> nil) and (ElementCount > 0) and (ElementCount > 0) then
  begin
    if Assigned(CompareProc) then
      InternalQuickSort(Mem, 0, ElementCount - 1, ElementByteSize, CompareProc)
    else
      InternalQuickSort(Mem, 0, ElementCount - 1, ElementByteSize, DefaultCompareProc);
  end;
end;

{$IFDEF COMPILER5}

function BoolToStr(Value: Boolean; UseBoolStrs: Boolean): string;
begin
  if UseBoolStrs then
  begin
    if Value then
      Result := 'True'
    else
      Result := 'False';
  end
  else
  begin
    if Value then
      Result := '-1'
    else
      Result := '0';
  end;
end;

{$ENDIF}

// =========================== 循环移位函数 ====================================

function RotateLeft16(A: Word; N: Integer): Word;
begin
  Result := (A shl N) or (A shr (16 - N));
end;

function RotateRight16(A: Word; N: Integer): Word;
begin
  Result := (A shr N) or (A shl (16 - N));
end;

function RotateLeft32(A: Cardinal; N: Integer): Cardinal;
begin
  Result := (A shl N) or (A shr (32 - N));
end;

function RotateRight32(A: Cardinal; N: Integer): Cardinal;
begin
  Result := (A shr N) or (A shl (32 - N));
end;

function RotateLeft64(A: TUInt64; N: Integer): TUInt64;
begin
  Result := (A shl N) or (A shr (64 - N));
end;
function RotateRight64(A: TUInt64; N: Integer): TUInt64;
begin
  Result := (A shr N) or (A shl (64 - N));
end;

initialization
  FByteOrderIsBigEndian := CurrentByteOrderIsBigEndian;

end.
