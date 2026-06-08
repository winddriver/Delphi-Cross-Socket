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

unit CnStrings;
{* |<PRE>
================================================================================
* 软件名称：CnPack 组件包
* 单元名称：CnStrings 实现单元，包括 AnsiStringList 以及一个快速子串搜索算法
*           基本支持 Win32/64 和 Posix
* 单元作者：CnPack 开发组 (master@cnpack.org)
* 开发平台：PWinXPPro + Delphi 5.01
* 兼容测试：PWin9X/2000/XP + Delphi 5/6/7/2005 + C++Build 5/6
* 备    注：AnsiStringList 移植自 Delphi 7 的 StringList
* 最后更新：2025.08.14
*               增加一个分隔符分隔的全匹配搜索实现函数
*           2022.10.25
*               增加 StringBuilder 的实现，支持 Ansi 和 Unicode 模式
*           2022.04.25
*               增加三个字符串替换函数，支持整字匹配
*           2017.01.09
*               增加移植自 Forrest Smith 的字符串模糊匹配算法，
*               并修正了最后一个匹配字符过于靠后的问题。
*           2015.06.01
*               增加快速搜索子串算法 FastPosition
*           2013.03.04
*               创建单元，实现功能
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  Classes, SysUtils, {$IFDEF MSWINDOWS} Windows, {$ENDIF} CnNative;

const
  SCN_BOM_UTF8: array[0..2] of Byte = ($EF, $BB, $BF);

  SCN_BOM_UTF16_LE: array[0..1] of Byte = ($FF, $FE);

  SCN_BOM_UTF16_BE: array[0..1] of Byte = ($FE, $FF);

type
  TCnMatchMode = (mmStart, mmAnywhere, mmFuzzy);
  {* 字符串匹配模式：开头匹配，中间匹配，全范围模糊匹配}

  TCnAnsiStrings = class;
  
  ICnStringsAdapter = interface
    ['{E32A5BD7-9A80-4DDE-83D7-2EE050BF476A}']
    procedure ReferenceStrings(S: TCnAnsiStrings);
    procedure ReleaseStrings;
  end;

  TCnAnsiStringsDefined = set of (sdDelimiter, sdQuoteChar, sdNameValueSeparator);

  TCnAnsiStrings = class(TPersistent)
  {* Ansi 版的 TStrings，适用于 Unicode 版编译器下提供 Ansi 版的 TStrings 功能}
  private
    FDefined: TCnAnsiStringsDefined;
    FDelimiter: AnsiChar;
    FQuoteChar: AnsiChar;
    FNameValueSeparator: AnsiChar;
    FUpdateCount: Integer;
    FAdapter: ICnStringsAdapter;
    FUseSingleLF: Boolean;
    function GetCommaText: AnsiString;
    function GetDelimitedText: AnsiString;
    function GetName(Index: Integer): AnsiString;
    function GetValue(const Name: AnsiString): AnsiString;
    procedure ReadData(Reader: TReader);
    procedure SetCommaText(const Value: AnsiString);
    procedure SetDelimitedText(const Value: AnsiString);
    procedure SetStringsAdapter(const Value: ICnStringsAdapter);
    procedure SetValue(const Name, Value: AnsiString);
    procedure WriteData(Writer: TWriter);
    function GetDelimiter: AnsiChar;
    procedure SetDelimiter(const Value: AnsiChar);
    function GetQuoteChar: AnsiChar;
    procedure SetQuoteChar(const Value: AnsiChar);
    function GetNameValueSeparator: AnsiChar;
    procedure SetNameValueSeparator(const Value: AnsiChar);
    function GetValueFromIndex(Index: Integer): AnsiString;
    procedure SetValueFromIndex(Index: Integer; const Value: AnsiString);
  protected
    procedure DefineProperties(Filer: TFiler); override;
    procedure Error(const Msg: AnsiString; Data: Integer); overload;
    procedure Error(Msg: PResStringRec; Data: Integer); overload;
    function ExtractName(const S: AnsiString): AnsiString;
    function Get(Index: Integer): AnsiString; virtual; abstract;
    function GetCapacity: Integer; virtual;
    function GetCount: Integer; virtual; abstract;
    function GetObject(Index: Integer): TObject; virtual;
    function GetTextStr: AnsiString; virtual;
    procedure Put(Index: Integer; const S: AnsiString); virtual;
    procedure PutObject(Index: Integer; AObject: TObject); virtual;
    procedure SetCapacity(NewCapacity: Integer); virtual;
    procedure SetTextStr(const Value: AnsiString); virtual;
    procedure SetUpdateState(Updating: Boolean); virtual;
    property UpdateCount: Integer read FUpdateCount;
    function CompareStrings(const S1, S2: AnsiString): Integer; virtual;
  public
    destructor Destroy; override;
    function Add(const S: AnsiString): Integer; virtual;
    function AddObject(const S: AnsiString; AObject: TObject): Integer; virtual;
    procedure Append(const S: AnsiString);
    procedure AddStrings(Strings: TCnAnsiStrings); virtual;
    procedure Assign(Source: TPersistent); override;
    procedure BeginUpdate;
    procedure Clear; virtual; abstract;
    procedure Delete(Index: Integer); virtual; abstract;
    procedure EndUpdate;
    function Equals(Strings: TCnAnsiStrings): Boolean; reintroduce;
    procedure Exchange(Index1, Index2: Integer); virtual;
    function GetText: PAnsiChar; virtual;
    function IndexOf(const S: AnsiString): Integer; virtual;
    function IndexOfName(const Name: AnsiString): Integer; virtual;
    function IndexOfObject(AObject: TObject): Integer; virtual;
    procedure Insert(Index: Integer; const S: AnsiString); virtual; abstract;
    procedure InsertObject(Index: Integer; const S: AnsiString;
      AObject: TObject); virtual;
    procedure LoadFromFile(const FileName: AnsiString); virtual;
    procedure LoadFromStream(Stream: TStream); virtual;
    procedure Move(CurIndex, NewIndex: Integer); virtual;
    procedure SaveToFile(const FileName: AnsiString); virtual;
    procedure SaveToStream(Stream: TStream); virtual;
    procedure SetText(Text: PAnsiChar); virtual;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property CommaText: AnsiString read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Delimiter: AnsiChar read GetDelimiter write SetDelimiter;
    property DelimitedText: AnsiString read GetDelimitedText write SetDelimitedText;
    property Names[Index: Integer]: AnsiString read GetName;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property QuoteChar: AnsiChar read GetQuoteChar write SetQuoteChar;
    property Values[const Name: AnsiString]: AnsiString read GetValue write SetValue;
    property ValueFromIndex[Index: Integer]: AnsiString read GetValueFromIndex write SetValueFromIndex;
    property NameValueSeparator: AnsiChar read GetNameValueSeparator write SetNameValueSeparator;
    property Strings[Index: Integer]: AnsiString read Get write Put; default;
    property Text: AnsiString read GetTextStr write SetTextStr;
    property StringsAdapter: ICnStringsAdapter read FAdapter write SetStringsAdapter;
    property UseSingleLF: Boolean read FUseSingleLF write FUseSingleLF;
    {* 增加的属性，控制 GetTextStr 时使用的换行是否是单个 #10 而不是常规的 #13#10}
  end;

  TCnAnsiStringList = class;

  PCnAnsiStringItem = ^TCnAnsiStringItem;
  TCnAnsiStringItem = record
    FString: AnsiString;
    FObject: TObject;
  end;

  PCnAnsiStringItemList = ^TCnAnsiStringItemList;
  TCnAnsiStringItemList = array[0..MaxListSize div 2] of TCnAnsiStringItem;
  TCnAnsiStringListSortCompare = function(List: TCnAnsiStringList; Index1, Index2: Integer): Integer;

  TCnAnsiStringList = class(TCnAnsiStrings)
  {* Ansi 版的 TStringList，适用于 Unicode 版编译器下提供 Ansi 版的 TStringList 功能}
  private
    FList: PCnAnsiStringItemList;
    FCount: Integer;
    FCapacity: Integer;
    FSorted: Boolean;
    FDuplicates: TDuplicates;
    FCaseSensitive: Boolean;
    FOnChange: TNotifyEvent;
    FOnChanging: TNotifyEvent;
    procedure ExchangeItems(Index1, Index2: Integer);
    procedure Grow;
    procedure QuickSort(L, R: Integer; SCompare: TCnAnsiStringListSortCompare);
    procedure SetSorted(Value: Boolean);
    procedure SetCaseSensitive(const Value: Boolean);
  protected
    procedure Changed; virtual;
    procedure Changing; virtual;
    function Get(Index: Integer): AnsiString; override;
    function GetCapacity: Integer; override;
    function GetCount: Integer; override;
    function GetObject(Index: Integer): TObject; override;
    procedure Put(Index: Integer; const S: AnsiString); override;
    procedure PutObject(Index: Integer; AObject: TObject); override;
    procedure SetCapacity(NewCapacity: Integer); override;
    procedure SetUpdateState(Updating: Boolean); override;
    function CompareStrings(const S1, S2: AnsiString): Integer; override;
    procedure InsertItem(Index: Integer; const S: AnsiString; AObject: TObject); virtual;
  public
    destructor Destroy; override;
    function Add(const S: AnsiString): Integer; override;
    function AddObject(const S: AnsiString; AObject: TObject): Integer; override;
    procedure Clear; override;
    procedure Delete(Index: Integer); override;
    procedure Exchange(Index1, Index2: Integer); override;
    function Find(const S: AnsiString; var Index: Integer): Boolean; virtual;
    function IndexOf(const S: AnsiString): Integer; override;
    procedure Insert(Index: Integer; const S: AnsiString); override;
    procedure InsertObject(Index: Integer; const S: AnsiString;
      AObject: TObject); override;
    procedure Sort; virtual;
    procedure CustomSort(Compare: TCnAnsiStringListSortCompare); virtual;
    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
    property Sorted: Boolean read FSorted write SetSorted;
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChanging: TNotifyEvent read FOnChanging write FOnChanging;
  end;

  PPCnAnsiHashItem = ^PCnAnsiHashItem;
  PCnAnsiHashItem = ^TCnAnsiHashItem;
  TCnAnsiHashItem = record
    Next: PCnAnsiHashItem;
    Key: AnsiString;
    Value: Integer;
  end;

  TCnAnsiStringHash = class
  private
    Buckets: array of PCnAnsiHashItem;
  protected
    function Find(const Key: AnsiString): PPCnAnsiHashItem;
    function HashOf(const Key: AnsiString): Cardinal; virtual;
  public
    constructor Create(Size: Cardinal = 256);
    destructor Destroy; override;
    procedure Add(const Key: AnsiString; Value: Integer);
    procedure Clear;
    procedure Remove(const Key: AnsiString);
    function Modify(const Key: AnsiString; Value: Integer): Boolean;
    function ValueOf(const Key: AnsiString): Integer;
  end;

  TCnHashedAnsiStringList = class(TCnAnsiStringList)
  {* Ansi 版的 THashedStringList，适用于 Unicode 版编译器下提供 Ansi 版的 THashedStringList 功能}
  private
    FValueHash: TCnAnsiStringHash;
    FNameHash: TCnAnsiStringHash;
    FValueHashValid: Boolean;
    FNameHashValid: Boolean;
    procedure UpdateValueHash;
    procedure UpdateNameHash;
  protected
    procedure Changed; override;
  public
    destructor Destroy; override;
    function IndexOf(const S: AnsiString): Integer; override;
    function IndexOfName(const Name: AnsiString): Integer; override;
  end;

  TCnStringBuilder = class
  {* 输出形式灵活的 StringBuilder，暂时只支持添加，不支持删除。
     非 Unicode 版本支持 string 和 WideString，Unicode 版本支持 AnsiString 和 string}
  private
    FModeIsFromOut: Boolean;
    FOutMode: Boolean;
    FAnsiMode: Boolean;      // 非 Unicode 版本默认 True，Unicode 版本默认 False，可创建时指定
    FCharLength: Integer;    // 以字符为单位的长度
    FMaxCharCapacity: Integer;
{$IFDEF UNICODE}
    FAnsiData: AnsiString;   // AnsiMode True 时使用
    FData: string;           // AnsiMode False 时使用
{$ELSE}
    FData: string;           // AnsiMode True 时使用
    FWideData: WideString;   // AnsiMode False 时使用
{$ENDIF}
    function GetCharCapacity: Integer;
    procedure SetCharCapacity(const Value: Integer);
    procedure SetCharLength(const Value: Integer);
  protected
    procedure ExpandCharCapacity;
    {* 根据 CharLength 的要求来扩展内部存储为 CharLength * 2，如 CharLength 太短则固定扩展 Capacity 的 0.5 倍}

    function AppendString(const Value: string): TCnStringBuilder;
    {* 将 string 添加到 FData，无论是否 Unicode 环境。由调用者根据 AnsiMode 控制。

       参数：
         const Value: string              - 待添加的字符串

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }
  public
    constructor Create; overload;
    {* 构造函数，内部实现默认 string}

    constructor Create(IsAnsi: Boolean); overload;
    {* 可指定内部是 Ansi 还是 Wide 的构造函数。

       参数：
         IsAnsi: Boolean                  - 指明内部是否使用 Ansi 模式

       返回值：（无）
    }

    destructor Destroy; override;
    {* 析构函数}

    procedure Clear;
    {* 清空内容}

{$IFDEF UNICODE}
    function AppendAnsi(const Value: AnsiString): TCnStringBuilder;
    {* 将 AnsiString 添加到 Unicode 环境下的 FAnsiData。由调用者根据 AnsiMode 控制。

       参数：
         const Value: AnsiString          - 待添加的单字节字符串

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

{$ELSE}
    function AppendWide(const Value: WideString): TCnStringBuilder;
    {* 将 WideString 添加到非 Unicode 环境中的 FWideData，由调用者根据 AnsiMode 控制。

       参数：
         const Value: WideString          - 待添加的宽字符串

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }
{$ENDIF}

    function Append(const Value: string): TCnStringBuilder; overload;
    {* 添加通用字符串，是所有其他参数类型 Append 的总入口，内部根据当前编译器以及 AnsiMode 决定用何种实现来拼接。

       参数：
         const Value: string              - 待添加的字符串

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Boolean): TCnStringBuilder; overload;
    {* 添加一布尔值。

       参数：
         Value: Boolean                   - 待添加的布尔值

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function AppendChar(Value: Char): TCnStringBuilder;
    {* 添加一字符。注意 Char 和单字符 String 是等同的，因而必须改名，不能和 Append 用 overload。

       参数：
         Value: Char                      - 待添加的字符

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function AppendAnsiChar(Value: AnsiChar): TCnStringBuilder;
    {* 添加一单字节字符。

       参数：
         Value: AnsiChar                  - 待添加的单字节字符

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function AppendWideChar(Value: WideChar): TCnStringBuilder;
    {* 添加一宽字符。

       参数：
         Value: WideChar                  - 待添加的宽字符

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }


    function AppendCurrency(Value: Currency): TCnStringBuilder;
    {* 添加一 Currency 值，注意 Currency 在低版本 Delphi 中和 Double 是等同的，
       因而必须改名，不能和 Append 用 overload。

       参数：
         Value: Currency                  - 待添加的 Currency 值

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }


    function Append(Value: Single): TCnStringBuilder; overload;
    {* 添加一单精度浮点数。

       参数：
         Value: Single                    - 待添加的单精度浮点数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Double): TCnStringBuilder; overload;
    {* 添加一双精度浮点数。

       参数：
         Value: Double                    - 待添加的双精度浮点数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: ShortInt): TCnStringBuilder; overload;
    {* 添加一 8 位有符号整数。

       参数：
         Value: ShortInt                  - 待添加的 8 位有符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: SmallInt): TCnStringBuilder; overload;
    {* 添加一 16 位有符号整数。

       参数：
         Value: SmallInt                  - 待添加的 16 位有符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Integer): TCnStringBuilder; overload;
    {* 添加一 32 位有符号整数。

       参数：
         Value: Integer                   - 待添加的 32 位有符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Int64): TCnStringBuilder; overload;
    {* 添加一 64 位有符号整数。

       参数：
         Value: Int64                     - 待添加的 64 位有符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Byte): TCnStringBuilder; overload;
    {* 添加一 8 位无符号整数。

       参数：
         Value: Byte                      - 待添加的 8 位无符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Word): TCnStringBuilder; overload;
    {* 添加一 16 位无符号整数。

       参数：
         Value: Word                      - 待添加的 16 位无符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Cardinal): TCnStringBuilder; overload;
    {* 添加一 32 位无符号整数。

       参数：
         Value: Cardinal                  - 待添加的 32 位无符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

{$IFDEF SUPPORT_UINT64}
    function Append(Value: UInt64): TCnStringBuilder; overload;
    {* 添加一 64 位无符号整数。

       参数：
         Value: UInt64                    - 待添加的 64 位无符号整数

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }
{$ENDIF}

    function Append(Value: TObject): TCnStringBuilder; overload;
    {* 添加一对象。

       参数：
         Value: TObject                   - 待添加的对象，内部使用其 ToString，无则使用对象十六进制地址

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: PAnsiChar): TCnStringBuilder; overload;
    {* 添加一单字节字符串。

       参数：
         Value: PAnsiChar                 - 待添加的单字节字符串地址

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(Value: Char; RepeatCount: Integer): TCnStringBuilder; overload;
    {* 添加一重复数量的相同字符。

       参数：
         Value: Char                      - 待添加的字符
         RepeatCount: Integer             - 字符数量

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(const Value: string; StartIndex: Integer; Count: Integer): TCnStringBuilder; overload;
    {* 添加一字符串的子串。

       参数：
         const Value: string              - 待添加的字符串
         StartIndex: Integer              - 起始位置
         Count: Integer                   - 字符数量

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function Append(const AFormat: string; const Args: array of const): TCnStringBuilder; overload;
    {* 添加一格式化字符串。

       参数：
         const AFormat: string            - 格式字符串
         const Args: array of const       - 格式参数列表

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function AppendLine: TCnStringBuilder; overload;
    {* 添加一空行。

       参数：
         （无）

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function AppendLine(const Value: string): TCnStringBuilder; overload;
    {* 添加一字符串并加上回车换行

       参数：
         const Value: string              - 待添加的字符串

       返回值：TCnStringBuilder           - 返回本对象供进一步添加调用
    }

    function ToString: string; {$IFDEF OBJECT_HAS_TOSTRING} override; {$ENDIF}
    {* 返回内容的 string 形式，无论是否 Unicode 环境，只要 AnsiMode 与编译器的 Unicode 支持一致。
       换句话说非 Unicode 环境中 AnsiMode 为 True 时才返回 AnsiString，
       Unicode 环境中 AnsiMode 为 False 时才返回 UnicodeString，其余情况返回空。

       参数：
         （无）

       返回值：string                     - 返回内容的字符串形式
    }

    function ToAnsiString: AnsiString;
    {* 强行返回内容的 AnsiString 形式，无论 AnsiMode 如何。
       可在 Unicode 环境中使用，如在非 Unicode 环境中使用，等同于 ToString。

       参数：
         （无）

       返回值：AnsiString                 - 返回内容的单字节字符串形式
    }

    function ToWideString: WideString;
    {* 强行返回内容的 WideString 形式，无论 AnsiMode 如何。
       可在非 Unicode 环境中使用，如在 Unicode 环境中使用，等同于 ToString。

       参数：
         （无）

       返回值：WideString                 - 返回内容的宽字符串形式
    }

    property CharCapacity: Integer read GetCharCapacity write SetCharCapacity;
    {* 以字符为单位的内部缓冲区的容量}
    property CharLength: Integer read FCharLength write SetCharLength;
    {* 以字符为单位的内部已经拼凑的内容长度}
    property MaxCharCapacity: Integer read FMaxCharCapacity;
    {* 以字符为单位的可设置的最大容量长度}
  end;

  TCnReplaceFlags = set of (crfReplaceAll, crfIgnoreCase, crfWholeWord);
  {* 字符串替换标记}

{$IFNDEF COMPILER7_UP}

function PosEx(const SubStr: string; const S: string; Offset: Cardinal = 1): Integer;
{* D5/6 BCB5/6 中无 StrUtils 单元的此函数，移植其 PosEx 函数放这里，使用请参考 PosEx 函数。

   参数：
     const SubStr: string                 - 待查找的子串
     const S: string                      - 原字符串
     Offset: Cardinal                     - 查找的起始偏移量

   返回值：Integer                        - 返回从起始偏移量起第一次出现子串的位置
}

{$ENDIF}

function FastPosition(const Str: PChar; const Pattern: PChar; FromIndex: Integer = 0): Integer;
{* 快速搜索子串，返回 Pattern 在 Str 中的第一次出现的索引号，无则返回 -1。

   参数：
     const Str: PChar                     - 待搜索的完整字符串
     const Pattern: PChar                 - 待匹配的子串
     FromIndex: Integer                   - 从何处开始搜索

   返回值：Integer                        - 返回匹配的第一次出现的索引号，无则返回 -1
}

function FuzzyMatchStr(const Pattern: string; const Str: string; MatchedIndexes: TList = nil;
  CaseSensitive: Boolean = False): Boolean;
{* 模糊匹配子串，MatchedIndexes 中返回 Str 中匹配的下标号。

   参数：
     const Pattern: string                - 待匹配的子串
     const Str: string                    - 待搜索的完整字符串
     MatchedIndexes: TList                - 返回字符串中各字符匹配的下标号
     CaseSensitive: Boolean               - 控制是否区分大小写

   返回值：Boolean                        - 返回是否有模糊匹配的内容
}

function FuzzyMatchStrWithScore(const Pattern: string; const Str: string; out Score: Integer;
  MatchedIndexes: TList = nil; CaseSensitive: Boolean = False): Boolean;
{* 模糊匹配子串，Score 返回匹配程度，MatchedIndexes 中返回 Str 中匹配的下标号，
   注意 Score 的比较只有子串以及大小写一致时才有意义。

   参数：
     const Pattern: string                - 待匹配的子串
     const Str: string                    - 待搜索的完整字符串
     out Score: Integer                   - 返回匹配程度评分
     MatchedIndexes: TList                - 返回字符串中各字符匹配的下标号
     CaseSensitive: Boolean               - 控制是否区分大小写

   返回值：Boolean                        - 返回是否有模糊匹配的内容
}

function AnyWhereSepMatchStr(const Pattern: string; const Str: string; SepContainer: TStringList;
  MatchedIndexes: TList = nil; CaseSensitive: Boolean = False; SepChar: Char = ' '): Boolean;
{* 分割子串后独立均匹配子串，也就是把 Pattern 按 SepChar 劈分成多个字符串后进行匹配，全都匹配才返回匹配。
   MatchedIndexes 中返回 Str 中匹配的下标号，SepContainer 是外界传入的 TStringList 以减少创建开销。

   参数：
     const Pattern: string                - 待匹配的子串
     const Str: string                    - 待搜索的完整字符串
     SepContainer: TStringList;           - 外界传入的 TStringList 以减少内部创建开销
     MatchedIndexes: TList                - 返回字符串中各字符匹配的下标号
     CaseSensitive: Boolean               - 控制是否区分大小写

   返回值：Boolean                        - 返回是否匹配成功
}

function CnStringReplace(const S: string; const OldPattern: string;
  const NewPattern: string; Flags: TCnReplaceFlags): string;
{* 支持整字匹配的字符串替换，在 Unicode 或非 Unicode 编译器下都有效。

   参数：
     const S: string                      - 待替换的字符串
     const OldPattern: string             - 待替换的字符串内容
     const NewPattern: string             - 替换的字符串新内容
     Flags: TCnReplaceFlags               - 替换标记，支持整字匹配

   返回值：string                         - 返回字符串替换结果
}

{$IFDEF UNICODE}

function CnStringReplaceA(const S: AnsiString; const OldPattern: AnsiString;
  const NewPattern: AnsiString; Flags: TCnReplaceFlags): AnsiString;
{* 支持整字匹配的 Ansi 字符串替换，在 Unicode 编译器下有效。

   参数：
     const S: AnsiString                  - 待替换的单字节字符串
     const OldPattern: AnsiString         - 待替换的单字节字符串内容
     const NewPattern: AnsiString         - 替换的单字节字符串新内容
     Flags: TCnReplaceFlags               - 替换标记，支持整字匹配

   返回值：AnsiString                     - 返回单字节字符串替换结果
}

{$ELSE}

function CnStringReplaceW(const S: WideString; const OldPattern: WideString;
  const NewPattern: WideString; Flags: TCnReplaceFlags): WideString;
{* 支持整字匹配的 Wide 字符串替换，在非 Unicode 编译器下有效。

   参数：
     const S: WideString                  - 待替换的宽字符串
     const OldPattern: WideString         - 待替换的宽字符串内容
     const NewPattern: WideString         - 替换的宽字符串新内容
     Flags: TCnReplaceFlags               - 替换标记，支持整字匹配

   返回值：WideString                     - 返回宽字符串替换结果
}

{$ENDIF}

function CnPosEx(const SubStr, S: string; CaseSensitive: Boolean; WholeWords:
  Boolean; StartCount: Integer = 1): Integer;
{* 增强的字符串查找函数，支持查找第几个，首个的 StartCount 为 1}

procedure CnSplitString(const Sub: string; const Str: string; Strings: TStrings);
{* 字符串劈分函数，不限于字符劈分}

function NativeStringToUIString(const Str: string): string;
{* Lazarus/FPC 的 Ansi 模式专用，因为 Lazarus/FPC 的 Ansi 模式下和界面有关的字符串是 Utf8 格式，
   而我们内部的普通字符串大多是 Ansi 或 Utf16，这里做一次封装转换。}

function UIStringToNativeString(const Str: string): string;
{* Lazarus/FPC 的 Ansi 模式专用，因为 Lazarus/FPC 的 Ansi 模式下和界面有关的字符串是 Utf8 格式，
   而我们内部的普通字符串大多是 Ansi 或 Utf16，这里做一次封装转换。}

implementation

uses
  CnWideStrings;

const
  SLineBreak = #13#10;
  SLineBreakLF = #10;
  STRING_BUILDER_DEFAULT_CAPACITY = 16;

resourcestring
  SDuplicateString = 'AnsiString list does not allow duplicates';
  SListIndexError = 'AnsiString List index out of bounds (%d)';
  SSortedListError = 'Operation not allowed on sorted AnsiString list';
  SListCapacityError = 'Error New Capacity or Length Value %d';

function NativeStringToUIString(const Str: string): string;
begin
{$IFDEF FPC}
  Result := CnAnsiToUtf82(Str);
{$ELSE}
  Result := Str;
{$ENDIF}
end;

function UIStringToNativeString(const Str: string): string;
begin
{$IFDEF FPC}
  Result := CnUtf8ToAnsi2(Str);
{$ELSE}
  Result := Str;
{$ENDIF}
end;

{$IFNDEF COMPILER7_UP}

function PosEx(const SubStr, S: string; Offset: Cardinal = 1): Integer;
var
  I,X: Integer;
  Len, LenSubStr: Integer;
begin
  if Offset = 1 then
    Result := Pos(SubStr, S)
  else
  begin
    I := Offset;
    LenSubStr := Length(SubStr);
    Len := Length(S) - LenSubStr + 1;
    while I <= Len do
    begin
      if S[I] = SubStr[1] then
      begin
        X := 1;
        while (X < LenSubStr) and (S[I + X] = SubStr[X + 1]) do
          Inc(X);
        if (X = LenSubStr) then
        begin
          Result := I;
          exit;
        end;
      end;
      Inc(I);
    end;
    Result := 0;
  end;
end;

{$ENDIF}

// 快速搜索子串，返回 Pattern 在 Str 中的第一次出现的索引号，无则返回 -1
function FastPosition(const Str, Pattern: PChar; FromIndex: Integer): Integer;
var
  C: Char;
  I, L, X, Y, PLen, SLen: Integer;
  BCS: array[0..255] of Integer;
begin
  Result := -1;
  if (Str = nil) or (Pattern = nil) then
    Exit;

  PLen := StrLen(Pattern);
  if PLen = 0 then
    Exit;
  SLen := StrLen(Str);

  // 如果是单字符搜索模式
  if PLen = 1 then
  begin
    for I := FromIndex to SLen - 1 do
    begin
      if Str[I] = Pattern[0] then
      begin
        Result := I;
        Exit;
      end;
    end;
    Exit;
  end;

  // 填充快速跃进表
  for I := Low(BCS) to High(BCS) do
    BCS[I] := PLen;

  for I := 0 to PLen - 2 do
  begin
    C := Pattern[I];
    L := Ord(C) and $FF;
    if PLen - I - 1 < BCS[L] then
      BCS[L] := PLen - I - 1;
  end;

  // 再进行搜索
  I := FromIndex + PLen - 1;
  while I < SLen do
  begin
    X := I;
    Y := PLen - 1;
    while True do
    begin
      if Pattern[Y] <> Str[X] then
      begin
        Inc(I, BCS[Ord(Str[X]) and $FF]);
        Break;
      end;

      if Y = 0 then
      begin
        Result := X;
        Exit;
      end;

      Dec(X);
      Dec(Y);
    end;
  end;
end;

{$WARNINGS OFF}

function LowChar(AChar: Char): Char; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  if AChar in ['A'..'Z'] then
    Result := Chr(Ord(AChar) + 32)
  else
    Result := AChar;
end;

// 模糊匹配子串
function FuzzyMatchStr(const Pattern: string; const Str: string;
  MatchedIndexes: TList; CaseSensitive: Boolean): Boolean;
var
  PIdx, SIdx: Integer;
begin
  Result := False;
  if (Pattern = '') or (Str = '') then
    Exit;

  PIdx := 1;
  SIdx := 1;
  if MatchedIndexes <> nil then
    MatchedIndexes.Clear;

  if CaseSensitive then
  begin
    while (PIdx <= Length(Pattern)) and (SIdx <= Length(Str)) do
    begin
      if Pattern[PIdx] = Str[SIdx] then
      begin
        Inc(PIdx);
        if MatchedIndexes <> nil then
          MatchedIndexes.Add(Pointer(SIdx));
      end;
      Inc(SIdx);
    end;
  end
  else
  begin
    while (PIdx <= Length(Pattern)) and (SIdx <= Length(Str)) do
    begin
      if LowChar(Pattern[PIdx]) = LowChar(Str[SIdx]) then
      begin
        Inc(PIdx);
        if MatchedIndexes <> nil then
          MatchedIndexes.Add(Pointer(SIdx));
      end;
      Inc(SIdx);
    end;
  end;
  Result := PIdx > Length(Pattern);
end;

// 模糊匹配子串，Score 返回匹配程度，注意 Score 的比较只有子串以及大小写一致时才有意义
function FuzzyMatchStrWithScore(const Pattern: string; const Str: string;
  out Score: Integer; MatchedIndexes: TList; CaseSensitive: Boolean): Boolean;
const
  ADJACENCY_BONUS = 4;               // 每多一个字符的紧邻匹配时加分
  SEPARATOR_BONUS = 10;              // 每多一个字符匹配发生在一个分隔符号后的加分
  CAMEL_BONUS = 5;                   // 前一个匹配是小写而本次是大写时加分
  LEADING_LETTER_PENALTY = -3;       // 第一个匹配的字母越靠母串后越扣分
  MAX_LEADING_LETTER_PENALTY = -9;   // 第一个匹配的字母哪怕最后，封顶只扣这么点分
  UNMATCHED_LETTER_PENALTY = -1;     // 不匹配的扣分
  START_BONUS = 6;
var
  PIdx, SIdx: Integer;
  PrevMatch, PrevLow, PrevSep: Boolean;
  BestLetterPtr: PChar;
  BestLetterScore, NewScore, Penalty: Integer;
  PatternLetter, StrLetter: Char; // 分别用来遍历子串和母串的字符
  ThisMatch, Rematch, Advanced, PatternRepeat: Boolean;
begin
  Score := 0;
  Result := False;
  if (Pattern = '') or (Str = '') then
    Exit;

  if MatchedIndexes <> nil then
    MatchedIndexes.Clear;

  PrevMatch := False;
  PrevLow := False;
  PrevSep := True;

  PIdx := 1;
  SIdx := 1;

  BestLetterPtr := nil;
  BestLetterScore := 0;

  while SIdx <= Length(Str) do // SIdx 是母串索引位置，1 开始
  begin
    if PIdx <= Length(Pattern) then
      PatternLetter := Pattern[PIdx]
    else
      PatternLetter := #0;
    StrLetter := Str[SIdx];

    if CaseSensitive then
    begin
      ThisMatch := (PatternLetter <> #0) and (PatternLetter = StrLetter);
      Rematch := (BestLetterPtr <> nil) and (BestLetterPtr^ = StrLetter);
      Advanced := ThisMatch and (BestLetterPtr <> nil);
      PatternRepeat := (BestLetterPtr <> nil) and (PatternLetter <> #0) and (BestLetterPtr^ = PatternLetter);
    end
    else
    begin
      ThisMatch := (PatternLetter <> #0) and (LowChar(PatternLetter) = LowChar(StrLetter));
      Rematch := (BestLetterPtr <> nil) and (LowChar(BestLetterPtr^) = LowChar(StrLetter));
      Advanced := ThisMatch and (BestLetterPtr <> nil);
      PatternRepeat := (BestLetterPtr <> nil) and (PatternLetter <> #0) and (LowChar(BestLetterPtr^) = LowChar(PatternLetter));
    end;

    if ThisMatch and (MatchedIndexes <> nil) then
    begin
      MatchedIndexes.Add(Pointer(SIdx));
      if SIdx <= START_BONUS then        // 提高靠母串前头单个匹配字符的分数
        Inc(Score, (START_BONUS - SIdx + 1) * 2);
    end;

    if Advanced or PatternRepeat then
    begin
      Inc(Score, BestLetterScore);
      BestLetterPtr := nil;
      BestLetterScore := 0;
    end;

    if ThisMatch or Rematch then
    begin
      NewScore := 0;
      if PIdx = 1 then
      begin
        Penalty := LEADING_LETTER_PENALTY * (SIdx - 1); // 最头上匹配不扣分
        if Penalty < MAX_LEADING_LETTER_PENALTY then
          Penalty := MAX_LEADING_LETTER_PENALTY;

        Inc(Score, Penalty);
      end;

      if PrevMatch then
        Inc(NewScore, ADJACENCY_BONUS);
      if PrevSep then
        Inc(NewScore, SEPARATOR_BONUS);
      if PrevLow and (strLetter in ['A'..'Z']) then
        Inc(NewScore, CAMEL_BONUS);

      if ThisMatch then
        Inc(PIdx);

      if NewScore >= BestLetterScore then
      begin
        if BestLetterPtr <> nil then
          Inc(Score, UNMATCHED_LETTER_PENALTY);
        BestLetterPtr := @(Str[SIdx]);
        BestLetterScore := NewScore;
      end;
      PrevMatch := True;
    end
    else
    begin
      Inc(Score, UNMATCHED_LETTER_PENALTY);
      PrevMatch := False;
    end;

    PrevLow := StrLetter in ['a'..'z'];
    PrevSep := strLetter in ['_', ' ', '/', '\', '.'];

    Inc(SIdx);
  end;

  if BestLetterPtr <> nil then
    Inc(Score, BestLetterScore);

  Result := PIdx > Length(Pattern);
end;

function MatchedIndexesCompare(Item1, Item2: Pointer): Integer;
var
  R1, R2: Integer;
begin
  R1 := Integer(Item1);
  R2 := Integer(Item2);
  Result := R1 - R2;
end;

function AnyWhereSepMatchStr(const Pattern: string; const Str: string; SepContainer: TStringList;
  MatchedIndexes: TList; CaseSensitive: Boolean; SepChar: Char): Boolean;
var
  IsNil: Boolean;
  D, I, J: Integer;
  ToFind: string;
  SepChars: TSysCharSet;
begin
  Result := False;

  if Pos(SepChar, Pattern) <= 0 then
  begin
    // 没有隔离字符，蜕变成 Pos
    if CaseSensitive then
      D := Pos(Pattern, Str)
    else
      D := Pos(UpperCase(Pattern), UpperCase(Str));

    if D > 0 then
    begin
      Result := True;
      if MatchedIndexes <> nil then
      begin
        MatchedIndexes.Clear;
        for I := 0 to Length(Pattern) - 1 do
          MatchedIndexes.Add(Pointer(D + I));
      end;
    end;
  end
  else
  begin
    IsNil := SepContainer = nil;
    if IsNil then
      SepContainer := TStringList.Create
    else
      SepContainer.Clear;

    try
      SepChars := [];
      Include(SepChars, AnsiChar(SepChar));
      if CaseSensitive then
      begin
        ExtractStrings(SepChars, [], PChar(Pattern), SepContainer);
        ToFind := Str;
      end
      else
      begin
        ExtractStrings(SepChars, [], PChar(UpperCase(Pattern)), SepContainer);
        ToFind := UpperCase(Str);
      end;

      if MatchedIndexes <> nil then
        MatchedIndexes.Clear;
      for I := 0 to SepContainer.Count - 1 do
      begin
        D := Pos(SepContainer[I], ToFind);
        if D <= 0 then
        begin
          if MatchedIndexes <> nil then
            MatchedIndexes.Clear;
          Exit;
        end
        else
        begin
          if MatchedIndexes <> nil then
          begin
            for J := 0 to Length(SepContainer[I]) - 1 do
              MatchedIndexes.Add(Pointer(D + J));
          end;
        end;
      end;

      if (MatchedIndexes <> nil) and (MatchedIndexes.Count > 1) then
        MatchedIndexes.Sort(MatchedIndexesCompare);
      Result := True;
    finally
      if IsNil then
        SepContainer.Free;
    end;
  end;
end;

{ TCnAnsiStrings }

destructor TCnAnsiStrings.Destroy;
begin
  StringsAdapter := nil;
  inherited Destroy;
end;

function TCnAnsiStrings.Add(const S: AnsiString): Integer;
begin
  Result := GetCount;
  Insert(Result, S);
end;

function TCnAnsiStrings.AddObject(const S: AnsiString; AObject: TObject): Integer;
begin
  Result := Add(S);
  PutObject(Result, AObject);
end;

procedure TCnAnsiStrings.Append(const S: AnsiString);
begin
  Add(S);
end;

procedure TCnAnsiStrings.AddStrings(Strings: TCnAnsiStrings);
var
  I: Integer;
begin
  BeginUpdate;
  try
    for I := 0 to Strings.Count - 1 do
      AddObject(Strings[I], Strings.Objects[I]);
  finally
    EndUpdate;
  end;
end;

procedure TCnAnsiStrings.Assign(Source: TPersistent);
begin
  if Source is TCnAnsiStrings then
  begin
    BeginUpdate;
    try
      Clear;
      FDefined := TCnAnsiStrings(Source).FDefined;
      FNameValueSeparator := TCnAnsiStrings(Source).FNameValueSeparator;
      FQuoteChar := TCnAnsiStrings(Source).FQuoteChar;
      FDelimiter := TCnAnsiStrings(Source).FDelimiter;
      AddStrings(TCnAnsiStrings(Source));
    finally
      EndUpdate;
    end;
    Exit;
  end;
  inherited Assign(Source);
end;

procedure TCnAnsiStrings.BeginUpdate;
begin
  if FUpdateCount = 0 then SetUpdateState(True);
  Inc(FUpdateCount);
end;

procedure TCnAnsiStrings.DefineProperties(Filer: TFiler);

  function DoWrite: Boolean;
  begin
    if Filer.Ancestor <> nil then
    begin
      Result := True;
      if Filer.Ancestor is TCnAnsiStrings then
        Result := not Equals(TCnAnsiStrings(Filer.Ancestor))
    end
    else Result := Count > 0;
  end;

begin
  Filer.DefineProperty('Strings', ReadData, WriteData, DoWrite);
end;

procedure TCnAnsiStrings.EndUpdate;
begin
  Dec(FUpdateCount);
  if FUpdateCount = 0 then SetUpdateState(False);
end;

function TCnAnsiStrings.Equals(Strings: TCnAnsiStrings): Boolean;
var
  I, Count: Integer;
begin
  Result := False;
  Count := GetCount;
  if Count <> Strings.GetCount then Exit;
  for I := 0 to Count - 1 do if Get(I) <> Strings.Get(I) then Exit;
  Result := True;
end;

procedure TCnAnsiStrings.Error(const Msg: AnsiString; Data: Integer);

{$IFDEF MSWINDOWS}
  function ReturnAddr: Pointer;
  asm
          MOV     EAX,[EBP+4]
  end;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  raise EStringListError.CreateFmt(string(Msg), [Data]) at ReturnAddr;
{$ELSE}
  raise EStringListError.CreateFmt(string(Msg), [Data]);
{$ENDIF}
end;

procedure TCnAnsiStrings.Error(Msg: PResStringRec; Data: Integer);
begin
  Error(AnsiString(LoadResString(Msg)), Data);
end;

procedure TCnAnsiStrings.Exchange(Index1, Index2: Integer);
var
  TempObject: TObject;
  TempString: AnsiString;
begin
  BeginUpdate;
  try
    TempString := Strings[Index1];
    TempObject := Objects[Index1];
    Strings[Index1] := Strings[Index2];
    Objects[Index1] := Objects[Index2];
    Strings[Index2] := TempString;
    Objects[Index2] := TempObject;
  finally
    EndUpdate;
  end;
end;

function TCnAnsiStrings.ExtractName(const S: AnsiString): AnsiString;
var
  P: Integer;
begin
  Result := S;
  P := AnsiPos(string(NameValueSeparator), string(S));
  if P <> 0 then
    SetLength(Result, P-1) else
    SetLength(Result, 0);
end;

function TCnAnsiStrings.GetCapacity: Integer;
begin  // descendents may optionally override/replace this default implementation
  Result := Count;
end;

function TCnAnsiStrings.GetCommaText: AnsiString;
var
  LOldDefined: TCnAnsiStringsDefined;
  LOldDelimiter: AnsiChar;
  LOldQuoteChar: AnsiChar;
begin
  LOldDefined := FDefined;
  LOldDelimiter := FDelimiter;
  LOldQuoteChar := FQuoteChar;
  Delimiter := ',';
  QuoteChar := '"';
  try
    Result := GetDelimitedText;
  finally
    FDelimiter := LOldDelimiter;
    FQuoteChar := LOldQuoteChar;
    FDefined := LOldDefined;
  end;
end;

function TCnAnsiStrings.GetDelimitedText: AnsiString;
var
  S: AnsiString;
  P: PAnsiChar;
  I, Count: Integer;
begin
  Count := GetCount;
  if (Count = 1) and (Get(0) = '') then
    Result := QuoteChar + QuoteChar
  else
  begin
    Result := '';
    for I := 0 to Count - 1 do
    begin
      S := Get(I);
      P := PAnsiChar(S);
      while not (P^ in [#0..' ', QuoteChar, Delimiter]) do
      {$IFDEF MSWINDOWS}
        P := CharNextA(P);
      {$ELSE}
        Inc(P);
      {$ENDIF}
      if (P^ <> #0) then S := AnsiString(AnsiQuotedStr(string(S), Char(QuoteChar)));
      Result := Result + S + Delimiter;
    end;
    System.Delete(Result, Length(Result), 1);
  end;
end;

function TCnAnsiStrings.GetName(Index: Integer): AnsiString;
begin
  Result := ExtractName(Get(Index));
end;

function TCnAnsiStrings.GetObject(Index: Integer): TObject;
begin
  Result := nil;
end;

function TCnAnsiStrings.GetText: PAnsiChar;
begin
  Result := StrNew(PAnsiChar(GetTextStr));
end;

function TCnAnsiStrings.GetTextStr: AnsiString;
var
  I, L, Size, Count: Integer;
  P: PAnsiChar;
  S, LB: AnsiString;
begin
  Count := GetCount;
  Size := 0;

  if FUseSingleLF then
    LB := SLineBreakLF
  else
    LB := SLineBreak;

  for I := 0 to Count - 1 do Inc(Size, Length(Get(I)) + Length(LB));
  SetString(Result, nil, Size);
  P := Pointer(Result);
  for I := 0 to Count - 1 do
  begin
    S := Get(I);
    L := Length(S);
    if L <> 0 then
    begin
      System.Move(Pointer(S)^, P^, L);
      Inc(P, L);
    end;
    L := Length(LB);
    if L <> 0 then
    begin
      System.Move(Pointer(LB)^, P^, L);
      Inc(P, L);
    end;
  end;
end;

function TCnAnsiStrings.GetValue(const Name: AnsiString): AnsiString;
var
  I: Integer;
begin
  I := IndexOfName(Name);
  if I >= 0 then
    Result := Copy(Get(I), Length(Name) + 2, MaxInt) else
    Result := '';
end;

function TCnAnsiStrings.IndexOf(const S: AnsiString): Integer;
begin
  for Result := 0 to GetCount - 1 do
    if CompareStrings(Get(Result), S) = 0 then Exit;
  Result := -1;
end;

function TCnAnsiStrings.IndexOfName(const Name: AnsiString): Integer;
var
  P: Integer;
  S: AnsiString;
begin
  for Result := 0 to GetCount - 1 do
  begin
    S := Get(Result);
    P := AnsiPos(string(NameValueSeparator), string(S));
    if (P <> 0) and (CompareStrings(Copy(S, 1, P - 1), Name) = 0) then Exit;
  end;
  Result := -1;
end;

function TCnAnsiStrings.IndexOfObject(AObject: TObject): Integer;
begin
  for Result := 0 to GetCount - 1 do
    if GetObject(Result) = AObject then Exit;
  Result := -1;
end;

procedure TCnAnsiStrings.InsertObject(Index: Integer; const S: AnsiString;
  AObject: TObject);
begin
  Insert(Index, S);
  PutObject(Index, AObject);
end;

procedure TCnAnsiStrings.LoadFromFile(const FileName: AnsiString);
var
  Stream: TStream;
begin
  Stream := TFileStream.Create(string(FileName), fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TCnAnsiStrings.LoadFromStream(Stream: TStream);
var
  Size: Integer;
  S: AnsiString;
begin
  BeginUpdate;
  try
    Size := Stream.Size - Stream.Position;
    SetString(S, nil, Size);
    Stream.Read(Pointer(S)^, Size);
    SetTextStr(S);
  finally
    EndUpdate;
  end;
end;

procedure TCnAnsiStrings.Move(CurIndex, NewIndex: Integer);
var
  TempObject: TObject;
  TempString: AnsiString;
begin
  if CurIndex <> NewIndex then
  begin
    BeginUpdate;
    try
      TempString := Get(CurIndex);
      TempObject := GetObject(CurIndex);
      Delete(CurIndex);
      InsertObject(NewIndex, TempString, TempObject);
    finally
      EndUpdate;
    end;
  end;
end;

procedure TCnAnsiStrings.Put(Index: Integer; const S: AnsiString);
var
  TempObject: TObject;
begin
  TempObject := GetObject(Index);
  Delete(Index);
  InsertObject(Index, S, TempObject);
end;

procedure TCnAnsiStrings.PutObject(Index: Integer; AObject: TObject);
begin
end;

procedure TCnAnsiStrings.ReadData(Reader: TReader);
begin
  Reader.ReadListBegin;
  BeginUpdate;
  try
    Clear;
    while not Reader.EndOfList do Add(AnsiString(Reader.ReadString));
  finally
    EndUpdate;
  end;
  Reader.ReadListEnd;
end;

procedure TCnAnsiStrings.SaveToFile(const FileName: AnsiString);
var
  Stream: TStream;
begin
  Stream := TFileStream.Create(string(FileName), fmCreate);
  try
    SaveToStream(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TCnAnsiStrings.SaveToStream(Stream: TStream);
var
  S: AnsiString;
begin
  S := GetTextStr;
  Stream.WriteBuffer(Pointer(S)^, Length(S));
end;

procedure TCnAnsiStrings.SetCapacity(NewCapacity: Integer);
begin
  // do nothing - descendents may optionally implement this method
end;

procedure TCnAnsiStrings.SetCommaText(const Value: AnsiString);
begin
  Delimiter := ',';
  QuoteChar := '"';
  SetDelimitedText(Value);
end;

procedure TCnAnsiStrings.SetStringsAdapter(const Value: ICnStringsAdapter);
begin
  if FAdapter <> nil then FAdapter.ReleaseStrings;
  FAdapter := Value;
  if FAdapter <> nil then FAdapter.ReferenceStrings(Self);
end;

procedure TCnAnsiStrings.SetText(Text: PAnsiChar);
begin
  SetTextStr(Text);
end;

procedure TCnAnsiStrings.SetTextStr(const Value: AnsiString);
var
  P, Start: PAnsiChar;
  S: AnsiString;
begin
  BeginUpdate;
  try
    Clear;
    P := Pointer(Value);
    if P <> nil then
      while P^ <> #0 do
      begin
        Start := P;
        while not (P^ in [#0, #10, #13]) do Inc(P);
        SetString(S, Start, P - Start);
        Add(S);
        if P^ = #13 then Inc(P);
        if P^ = #10 then Inc(P);
      end;
  finally
    EndUpdate;
  end;
end;

procedure TCnAnsiStrings.SetUpdateState(Updating: Boolean);
begin
end;

procedure TCnAnsiStrings.SetValue(const Name, Value: AnsiString);
var
  I: Integer;
begin
  I := IndexOfName(Name);
  if Value <> '' then
  begin
    if I < 0 then I := Add('');
    Put(I, Name + NameValueSeparator + Value);
  end else
  begin
    if I >= 0 then Delete(I);
  end;
end;

procedure TCnAnsiStrings.WriteData(Writer: TWriter);
var
  I: Integer;
begin
  Writer.WriteListBegin;
  for I := 0 to Count - 1 do Writer.WriteString(string(Get(I)));
  Writer.WriteListEnd;
end;

procedure TCnAnsiStrings.SetDelimitedText(const Value: AnsiString);
var
  P, P1: PAnsiChar;
  S: AnsiString;
begin
  BeginUpdate;
  try
    Clear;
    P := PAnsiChar(Value);
    while P^ in [#1..' '] do
    {$IFDEF MSWINDOWS}
      P := CharNextA(P);
    {$ELSE}
      Inc(P);
    {$ENDIF}
    while P^ <> #0 do
    begin
      if P^ = QuoteChar then
        S := AnsiExtractQuotedStr(P, QuoteChar)
      else
      begin
        P1 := P;
        while (P^ > ' ') and (P^ <> Delimiter) do
        {$IFDEF MSWINDOWS}
          P := CharNextA(P);
        {$ELSE}
          Inc(P);
        {$ENDIF}
        SetString(S, P1, P - P1);
      end;
      Add(S);
      while P^ in [#1..' '] do
      {$IFDEF MSWINDOWS}
        P := CharNextA(P);
      {$ELSE}
        Inc(P);
      {$ENDIF}
      if P^ = Delimiter then
      begin
        P1 := P;
        {$IFDEF MSWINDOWS}
        if CharNextA(P1)^ = #0 then
        {$ELSE}
        Inc(P1);
        if P1^ = #0 then
        {$ENDIF}
          Add('');
        repeat
          {$IFDEF MSWINDOWS}
          P := CharNextA(P);
          {$ELSE}
          Inc(P);
          {$ENDIF}
        until not (P^ in [#1..' ']);
      end;
    end;
  finally
    EndUpdate;
  end;
end;

function TCnAnsiStrings.GetDelimiter: AnsiChar;
begin
  if not (sdDelimiter in FDefined) then
    Delimiter := ',';
  Result := FDelimiter;
end;

function TCnAnsiStrings.GetQuoteChar: AnsiChar;
begin
  if not (sdQuoteChar in FDefined) then
    QuoteChar := '"';
  Result := FQuoteChar;
end;

procedure TCnAnsiStrings.SetDelimiter(const Value: AnsiChar);
begin
  if (FDelimiter <> Value) or not (sdDelimiter in FDefined) then
  begin
    Include(FDefined, sdDelimiter);
    FDelimiter := Value;
  end
end;

procedure TCnAnsiStrings.SetQuoteChar(const Value: AnsiChar);
begin
  if (FQuoteChar <> Value) or not (sdQuoteChar in FDefined) then
  begin
    Include(FDefined, sdQuoteChar);
    FQuoteChar := Value;
  end
end;

function TCnAnsiStrings.CompareStrings(const S1, S2: AnsiString): Integer;
begin
  Result := AnsiCompareText(string(S1), string(S2));
end;

function TCnAnsiStrings.GetNameValueSeparator: AnsiChar;
begin
  if not (sdNameValueSeparator in FDefined) then
    NameValueSeparator := '=';
  Result := FNameValueSeparator;
end;

procedure TCnAnsiStrings.SetNameValueSeparator(const Value: AnsiChar);
begin
  if (FNameValueSeparator <> Value) or not (sdNameValueSeparator in FDefined) then
  begin
    Include(FDefined, sdNameValueSeparator);
    FNameValueSeparator := Value;
  end
end;

function TCnAnsiStrings.GetValueFromIndex(Index: Integer): AnsiString;
begin
  if Index >= 0 then
    Result := Copy(Get(Index), Length(Names[Index]) + 2, MaxInt) else
    Result := '';
end;

procedure TCnAnsiStrings.SetValueFromIndex(Index: Integer; const Value: AnsiString);
begin
  if Value <> '' then
  begin
    if Index < 0 then Index := Add('');
    Put(Index, Names[Index] + NameValueSeparator + Value);
  end
  else
    if Index >= 0 then Delete(Index);
end;

{ TCnAnsiStringList }

destructor TCnAnsiStringList.Destroy;
begin
  FOnChange := nil;
  FOnChanging := nil;
  inherited Destroy;
  if FCount <> 0 then Finalize(FList^[0], FCount);
  FCount := 0;
  SetCapacity(0);
end;

function TCnAnsiStringList.Add(const S: AnsiString): Integer;
begin
  Result := AddObject(S, nil);
end;

function TCnAnsiStringList.AddObject(const S: AnsiString; AObject: TObject): Integer;
begin
  if not Sorted then
    Result := FCount
  else
    if Find(S, Result) then
      case Duplicates of
        dupIgnore: Exit;
        dupError: Error(@SDuplicateString, 0);
      end;
  InsertItem(Result, S, AObject);
end;

procedure TCnAnsiStringList.Changed;
begin
  if (FUpdateCount = 0) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TCnAnsiStringList.Changing;
begin
  if (FUpdateCount = 0) and Assigned(FOnChanging) then
    FOnChanging(Self);
end;

procedure TCnAnsiStringList.Clear;
begin
  if FCount <> 0 then
  begin
    Changing;
    Finalize(FList^[0], FCount);
    FCount := 0;
    SetCapacity(0);
    Changed;
  end;
end;

procedure TCnAnsiStringList.Delete(Index: Integer);
begin
  if (Index < 0) or (Index >= FCount) then Error(@SListIndexError, Index);
  Changing;
  Finalize(FList^[Index]);
  Dec(FCount);
  if Index < FCount then
    System.Move(FList^[Index + 1], FList^[Index],
      (FCount - Index) * SizeOf(TCnAnsiStringItem));
  Changed;
end;

procedure TCnAnsiStringList.Exchange(Index1, Index2: Integer);
begin
  if (Index1 < 0) or (Index1 >= FCount) then Error(@SListIndexError, Index1);
  if (Index2 < 0) or (Index2 >= FCount) then Error(@SListIndexError, Index2);
  Changing;
  ExchangeItems(Index1, Index2);
  Changed;
end;

procedure TCnAnsiStringList.ExchangeItems(Index1, Index2: Integer);
var
  Temp: TCnNativeInt;
  Item1, Item2: PStringItem;
begin
  Item1 := @FList^[Index1];
  Item2 := @FList^[Index2];
  Temp := TCnNativeInt(Item1^.FString);
  TCnNativeInt(Item1^.FString) := TCnNativeInt(Item2^.FString);
  TCnNativeInt(Item2^.FString) := Temp;
  Temp := TCnNativeInt(Item1^.FObject);
  TCnNativeInt(Item1^.FObject) := TCnNativeInt(Item2^.FObject);
  TCnNativeInt(Item2^.FObject) := Temp;
end;

function TCnAnsiStringList.Find(const S: AnsiString; var Index: Integer): Boolean;
var
  L, H, I, C: Integer;
begin
  Result := False;
  L := 0;
  H := FCount - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := CompareStrings(FList^[I].FString, S);
    if C < 0 then L := I + 1 else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Result := True;
        if Duplicates <> dupAccept then L := I;
      end;
    end;
  end;
  Index := L;
end;

function TCnAnsiStringList.Get(Index: Integer): AnsiString;
begin
  if (Index < 0) or (Index >= FCount) then Error(@SListIndexError, Index);
  Result := FList^[Index].FString;
end;

function TCnAnsiStringList.GetCapacity: Integer;
begin
  Result := FCapacity;
end;

function TCnAnsiStringList.GetCount: Integer;
begin
  Result := FCount;
end;

function TCnAnsiStringList.GetObject(Index: Integer): TObject;
begin
  if (Index < 0) or (Index >= FCount) then Error(@SListIndexError, Index);
  Result := FList^[Index].FObject;
end;

procedure TCnAnsiStringList.Grow;
var
  Delta: Integer;
begin
  if FCapacity > 64 then Delta := FCapacity div 4 else
    if FCapacity > 8 then Delta := 16 else
      Delta := 4;
  SetCapacity(FCapacity + Delta);
end;

function TCnAnsiStringList.IndexOf(const S: AnsiString): Integer;
begin
  if not Sorted then Result := inherited IndexOf(S) else
    if not Find(S, Result) then Result := -1;
end;

procedure TCnAnsiStringList.Insert(Index: Integer; const S: AnsiString);
begin
  InsertObject(Index, S, nil);
end;

procedure TCnAnsiStringList.InsertObject(Index: Integer; const S: AnsiString;
  AObject: TObject);
begin
  if Sorted then Error(@SSortedListError, 0);
  if (Index < 0) or (Index > FCount) then Error(@SListIndexError, Index);
  InsertItem(Index, S, AObject);
end;

procedure TCnAnsiStringList.InsertItem(Index: Integer; const S: AnsiString; AObject: TObject);
begin
  Changing;
  if FCount = FCapacity then Grow;
  if Index < FCount then
    System.Move(FList^[Index], FList^[Index + 1],
      (FCount - Index) * SizeOf(TCnAnsiStringItem));
  with FList^[Index] do
  begin
    Pointer(FString) := nil;
    FObject := AObject;
    FString := S;
  end;
  Inc(FCount);
  Changed;
end;

procedure TCnAnsiStringList.Put(Index: Integer; const S: AnsiString);
begin
  if Sorted then Error(@SSortedListError, 0);
  if (Index < 0) or (Index >= FCount) then Error(@SListIndexError, Index);
  Changing;
  FList^[Index].FString := S;
  Changed;
end;

procedure TCnAnsiStringList.PutObject(Index: Integer; AObject: TObject);
begin
  if (Index < 0) or (Index >= FCount) then Error(@SListIndexError, Index);
  Changing;
  FList^[Index].FObject := AObject;
  Changed;
end;

procedure TCnAnsiStringList.QuickSort(L, R: Integer; SCompare: TCnAnsiStringListSortCompare);
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
        ExchangeItems(I, J);
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

procedure TCnAnsiStringList.SetCapacity(NewCapacity: Integer);
begin
  ReallocMem(FList, NewCapacity * SizeOf(TCnAnsiStringItem));
  FCapacity := NewCapacity;
end;

procedure TCnAnsiStringList.SetSorted(Value: Boolean);
begin
  if FSorted <> Value then
  begin
    if Value then Sort;
    FSorted := Value;
  end;
end;

procedure TCnAnsiStringList.SetUpdateState(Updating: Boolean);
begin
  if Updating then Changing else Changed;
end;

function StringListCompareStrings(List: TCnAnsiStringList; Index1, Index2: Integer): Integer;
begin
  Result := List.CompareStrings(List.FList^[Index1].FString,
                                List.FList^[Index2].FString);
end;

procedure TCnAnsiStringList.Sort;
begin
  CustomSort(StringListCompareStrings);
end;

procedure TCnAnsiStringList.CustomSort(Compare: TCnAnsiStringListSortCompare);
begin
  if not Sorted and (FCount > 1) then
  begin
    Changing;
    QuickSort(0, FCount - 1, Compare);
    Changed;
  end;
end;

function TCnAnsiStringList.CompareStrings(const S1, S2: AnsiString): Integer;
begin
  if CaseSensitive then
    Result := AnsiCompareStr(string(S1), string(S2))
  else
    Result := AnsiCompareText(string(S1), string(S2));
end;

procedure TCnAnsiStringList.SetCaseSensitive(const Value: Boolean);
begin
  if Value <> FCaseSensitive then
  begin
    FCaseSensitive := Value;
    if Sorted then Sort;
  end;
end;

{ TCnAnsiStringHash }

procedure TCnAnsiStringHash.Add(const Key: AnsiString; Value: Integer);
var
  Hash: Integer;
  Bucket: PCnAnsiHashItem;
begin
  Hash := HashOf(Key) mod Cardinal(Length(Buckets));
  New(Bucket);
  Bucket^.Key := Key;
  Bucket^.Value := Value;
  Bucket^.Next := Buckets[Hash];
  Buckets[Hash] := Bucket;
end;

procedure TCnAnsiStringHash.Clear;
var
  I: Integer;
  P, N: PCnAnsiHashItem;
begin
  for I := 0 to Length(Buckets) - 1 do
  begin
    P := Buckets[I];
    while P <> nil do
    begin
      N := P^.Next;
      Dispose(P);
      P := N;
    end;
    Buckets[I] := nil;
  end;
end;

constructor TCnAnsiStringHash.Create(Size: Cardinal);
begin
  inherited Create;
  SetLength(Buckets, Size);
end;

destructor TCnAnsiStringHash.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TCnAnsiStringHash.Find(const Key: AnsiString): PPCnAnsiHashItem;
var
  Hash: Integer;
begin
  Hash := HashOf(Key) mod Cardinal(Length(Buckets));
  Result := @Buckets[Hash];
  while Result^ <> nil do
  begin
    if Result^.Key = Key then
      Exit
    else
      Result := @Result^.Next;
  end;
end;

function TCnAnsiStringHash.HashOf(const Key: AnsiString): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(Key) do
    Result := ((Result shl 2) or (Result shr (SizeOf(Result) * 8 - 2))) xor
      Ord(Key[I]);
end;

function TCnAnsiStringHash.Modify(const Key: AnsiString; Value: Integer): Boolean;
var
  P: PCnAnsiHashItem;
begin
  P := Find(Key)^;
  if P <> nil then
  begin
    Result := True;
    P^.Value := Value;
  end
  else
    Result := False;
end;

procedure TCnAnsiStringHash.Remove(const Key: AnsiString);
var
  P: PCnAnsiHashItem;
  Prev: PPCnAnsiHashItem;
begin
  Prev := Find(Key);
  P := Prev^;
  if P <> nil then
  begin
    Prev^ := P^.Next;
    Dispose(P);
  end;
end;

function TCnAnsiStringHash.ValueOf(const Key: AnsiString): Integer;
var
  P: PCnAnsiHashItem;
begin
  P := Find(Key)^;
  if P <> nil then
    Result := P^.Value
  else
    Result := -1;
end;

{ TCnHashedAnsiStringList }

procedure TCnHashedAnsiStringList.Changed;
begin
  inherited Changed;
  FValueHashValid := False;
  FNameHashValid := False;
end;

destructor TCnHashedAnsiStringList.Destroy;
begin
  FValueHash.Free;
  FNameHash.Free;
  inherited Destroy;
end;

function TCnHashedAnsiStringList.IndexOf(const S: AnsiString): Integer;
begin
  UpdateValueHash;
  if not CaseSensitive then
    Result :=  FValueHash.ValueOf(AnsiString(AnsiUpperCase(string(S))))
  else
    Result :=  FValueHash.ValueOf(S);
end;

function TCnHashedAnsiStringList.IndexOfName(const Name: AnsiString): Integer;
begin
  UpdateNameHash;
  if not CaseSensitive then
    Result := FNameHash.ValueOf(AnsiString(AnsiUpperCase(string(Name))))
  else
    Result := FNameHash.ValueOf(Name);
end;

procedure TCnHashedAnsiStringList.UpdateNameHash;
var
  I: Integer;
  P: Integer;
  Key: AnsiString;
begin
  if FNameHashValid then Exit;
  
  if FNameHash = nil then
    FNameHash := TCnAnsiStringHash.Create
  else
    FNameHash.Clear;
  for I := 0 to Count - 1 do
  begin
    Key := Get(I);
    P := AnsiPos('=', string(Key));
    if P <> 0 then
    begin
      if not CaseSensitive then
        Key := AnsiString(AnsiUpperCase(string(Copy(Key, 1, P - 1))))
      else
        Key := Copy(Key, 1, P - 1);
      FNameHash.Add(Key, I);
    end;
  end;
  FNameHashValid := True;
end;

procedure TCnHashedAnsiStringList.UpdateValueHash;
var
  I: Integer;
begin
  if FValueHashValid then Exit;
  
  if FValueHash = nil then
    FValueHash := TCnAnsiStringHash.Create
  else
    FValueHash.Clear;
  for I := 0 to Count - 1 do
    if not CaseSensitive then
      FValueHash.Add(AnsiString(AnsiUpperCase(string(Self[I]))), I)
    else
      FValueHash.Add(Self[I], I);
  FValueHashValid := True;
end;

// 判断一个字符是否整字匹配的分隔符
function IsSepChar(AChar: Char): Boolean;
begin
{$IFDEF UNICODE}
  Result := not CharInSet(AChar, ['0'..'9', 'A'..'Z', 'a'..'z', '_']);
{$ELSE}
  Result := not (AChar in ['0'..'9', 'A'..'Z', 'a'..'z', '_']);
{$ENDIF}
end;

function IsSepCharA(AChar: AnsiChar): Boolean;
begin
  Result := not (AChar in ['0'..'9', 'A'..'Z', 'a'..'z', '_']);
end;

function IsSepCharW(AChar: WideChar): Boolean;
begin
  Result := (Ord(AChar) < 127) and not (AnsiChar(AChar) in ['0'..'9', 'A'..'Z', 'a'..'z', '_']);
end;

function CnStringReplace(const S, OldPattern, NewPattern: string;
  Flags: TCnReplaceFlags): string;
var
  SearchStr, Patt, NewStr: string;
  Offset, TailOffset: Integer;
  IsWhole: Boolean;
begin
  if crfIgnoreCase in Flags then
  begin
{$IFDEF UNICODE}
    SearchStr := UpperCase(S);
    Patt := UpperCase(OldPattern);
{$ELSE}
    SearchStr := AnsiUpperCase(S);
    Patt := AnsiUpperCase(OldPattern);
{$ENDIF}
  end
  else
  begin
    SearchStr := S;
    Patt := OldPattern;
  end;

  NewStr := S;
  Result := '';

  while SearchStr <> '' do
  begin
{$IFDEF UNICODE}
    Offset := Pos(Patt, SearchStr);
{$ELSE}
    Offset := AnsiPos(Patt, SearchStr);
{$ENDIF}
    IsWhole := True;
    if Offset = 0 then
    begin
      Result := Result + NewStr;
      Break;
    end
    else if crfWholeWord in Flags then
    begin
      // 找到了子串且需要整字匹配，须进行整字判断，不符合则当
      // 有头且头非分隔符，或有尾且尾非分隔符，则非整字
      if (Offset > 1) and not IsSepChar(SearchStr[Offset - 1]) then
        IsWhole := False
      else
      begin
        TailOffset := Offset + Length(Patt); // 指向匹配后的一个字符
        if (TailOffset <= Length(SearchStr)) and not IsSepChar(SearchStr[TailOffset]) then
          IsWhole := False;
      end;

      // 得到了是否整字匹配的结论
    end;

    if not (crfWholeWord in Flags) or IsWhole then // 普通匹配或整字匹配了
    begin
      // 替换一次
      Result := Result + Copy(NewStr, 1, Offset - 1) + NewPattern;
      NewStr := Copy(NewStr, Offset + Length(OldPattern), MaxInt);
      if not (crfReplaceAll in Flags) then
      begin
        Result := Result + NewStr;
        Break;
      end;
    end
    else // 整字匹配的要求下，未整字匹配，不能替换
    begin
      Result := Result + Copy(NewStr, 1, Offset - 1) + OldPattern; // 注意必须用 OldePattern，不能替换
      NewStr := Copy(NewStr, Offset + Length(OldPattern), MaxInt);
    end;
    SearchStr := Copy(SearchStr, Offset + Length(Patt), MaxInt);
  end;
end;

{$IFDEF UNICODE}

function CnStringReplaceA(const S, OldPattern, NewPattern: AnsiString;
  Flags: TCnReplaceFlags): AnsiString;
var
  SearchStr, Patt, NewStr: AnsiString;
  Offset, TailOffset: Integer;
  IsWhole: Boolean;
begin
  if crfIgnoreCase in Flags then
  begin
    SearchStr := AnsiUpperCase(S);
    Patt := AnsiUpperCase(OldPattern);
  end
  else
  begin
    SearchStr := S;
    Patt := OldPattern;
  end;

  NewStr := S;
  Result := '';

  while SearchStr <> '' do
  begin
    Offset := AnsiPos(Patt, SearchStr);
    IsWhole := True;
    if Offset = 0 then
    begin
      Result := Result + NewStr;
      Break;
    end
    else if crfWholeWord in Flags then
    begin
      // 找到了子串且需要整字匹配，须进行整字判断，不符合则当
      // 有头且头非分隔符，或有尾且尾非分隔符，则非整字
      if (Offset > 1) and not IsSepCharA(SearchStr[Offset - 1]) then
        IsWhole := False
      else
      begin
        TailOffset := Offset + Length(Patt); // 指向匹配后的一个字符
        if (TailOffset <= Length(SearchStr)) and not IsSepCharA(SearchStr[TailOffset]) then
          IsWhole := False;
      end;

      // 得到了是否整字匹配的结论
    end;

    if not (crfWholeWord in Flags) or IsWhole then // 普通匹配或整字匹配了
    begin
      // 替换一次
      Result := Result + Copy(NewStr, 1, Offset - 1) + NewPattern;
      NewStr := Copy(NewStr, Offset + Length(OldPattern), MaxInt);
      if not (crfReplaceAll in Flags) then
      begin
        Result := Result + NewStr;
        Break;
      end;
    end
    else // 整字匹配的要求下，未整字匹配，不能替换
    begin
      Result := Result + Copy(NewStr, 1, Offset - 1) + OldPattern; // 注意必须用 OldePattern，不能替换
      NewStr := Copy(NewStr, Offset + Length(OldPattern), MaxInt);
    end;
    SearchStr := Copy(SearchStr, Offset + Length(Patt), MaxInt);
  end;
end;

{$ELSE}

function CnStringReplaceW(const S, OldPattern, NewPattern: WideString;
  Flags: TCnReplaceFlags): WideString;
var
  SearchStr, Patt, NewStr: WideString;
  Offset, TailOffset: Integer;
  IsWhole: Boolean;
begin
  if crfIgnoreCase in Flags then
  begin
    SearchStr := UpperCase(S);
    Patt := UpperCase(OldPattern);
  end
  else
  begin
    SearchStr := S;
    Patt := OldPattern;
  end;

  NewStr := S;
  Result := '';

  while SearchStr <> '' do
  begin
    Offset := Pos(Patt, SearchStr);
    IsWhole := True;
    if Offset = 0 then
    begin
      Result := Result + NewStr;
      Break;
    end
    else if crfWholeWord in Flags then
    begin
      // 找到了子串且需要整字匹配，须进行整字判断，不符合则当
      // 有头且头非分隔符，或有尾且尾非分隔符，则非整字
      if (Offset > 1) and not IsSepCharW(SearchStr[Offset - 1]) then
        IsWhole := False
      else
      begin
        TailOffset := Offset + Length(Patt); // 指向匹配后的一个字符
        if (TailOffset <= Length(SearchStr)) and not IsSepCharW(SearchStr[TailOffset]) then
          IsWhole := False;
      end;

      // 得到了是否整字匹配的结论
    end;

    if not (crfWholeWord in Flags) or IsWhole then // 普通匹配或整字匹配了
    begin
      // 替换一次
      Result := Result + Copy(NewStr, 1, Offset - 1) + NewPattern;
      NewStr := Copy(NewStr, Offset + Length(OldPattern), MaxInt);
      if not (crfReplaceAll in Flags) then
      begin
        Result := Result + NewStr;
        Break;
      end;
    end
    else // 整字匹配的要求下，未整字匹配，不能替换
    begin
      Result := Result + Copy(NewStr, 1, Offset - 1) + OldPattern; // 注意必须用 OldePattern，不能替换
      NewStr := Copy(NewStr, Offset + Length(OldPattern), MaxInt);
    end;
    SearchStr := Copy(SearchStr, Offset + Length(Patt), MaxInt);
  end;
end;

{$ENDIF}

function CnPosEx(const SubStr, S: string; CaseSensitive: Boolean; WholeWords:
  Boolean; StartCount: Integer): Integer;
var
  P: PChar;
  I, Count, Len, SubLen: Integer;
  StrUpper, SubUpper: string;
begin
  Result := 0;
  if (SubStr = '') or (S = '') or (StartCount < 1) then
    Exit;

  Len := Length(S);
  SubLen := Length(SubStr);
  if SubLen > Len then
    Exit;

  if not CaseSensitive then
  begin
    StrUpper := UpperCase(S);
    SubUpper := UpperCase(SubStr);
    P := PChar(StrUpper);
  end
  else
    P := PChar(S);

  Count := 0;
  for I := 1 to Len - SubLen + 1 do
  begin
    if (CaseSensitive and (P^ = SubStr[1]) and
      (CompareMem(P, PChar(SubStr), SubLen * SizeOf(Char))))
      or
      (not CaseSensitive and (P^ = SubUpper[1]) and
      (CompareMem(P, PChar(SubUpper), SubLen * SizeOf(Char)))) then
    begin
      if WholeWords then
      begin
        // 检查是否整词匹配
        if ((I = 1) or IsSepChar((P - 1)^)) and
           ((I + SubLen - 1 >= Len) or IsSepChar((P + SubLen)^)) then
        begin
          Inc(Count);
          if Count = StartCount then
          begin
            Result := I;
            Exit;
          end;
        end;
      end
      else
      begin
        Inc(Count);
        if Count = StartCount then
        begin
          Result := I;
          Exit;
        end;
      end;
    end;
    Inc(P);
  end;
end;

procedure CnSplitString(const Sub: string; const Str: string; Strings: TStrings);
var
  S: string;
  P, SubLen: Integer;
begin
  if Strings = nil then
    Exit;                     // 忽略空指针

  Strings.Clear;              // 清空原有内容

  // 处理分隔符为空的情况：将整个字符串作为一个条目
  if Sub = '' then
  begin
    Strings.Add(Str);
    Exit;
  end;

  // 处理源字符串为空的情况：添加一个空条目
  if Str = '' then
  begin
    Strings.Add('');
    Exit;
  end;

  SubLen := Length(Sub);
  S := Str;  // 创建源字符串的副本，后续操作会修改此副本

  while S <> '' do
  begin
    P := Pos(Sub, S);         // 在剩余字符串中查找分隔符

    if P = 0 then
    begin
      // 没有更多分隔符，将剩余部分作为最后一个条目
      Strings.Add(S);
      Break;
    end;

    // 取出从开头到分隔符前的内容（可能为空）
    Strings.Add(Copy(S, 1, P - 1));

    // 删除已处理的部分（包括刚找到的分隔符）
    Delete(S, 1, P + SubLen - 1);

    // 如果删除后字符串为空，且原字符串以分隔符结尾，则需要添加一个空条目
    if S = '' then
      Strings.Add('');
  end;
end;

{$WARNINGS ON}

{ TCnStringBuilder }

constructor TCnStringBuilder.Create;
begin
  inherited;
  if not FModeIsFromOut then // 外部未指定时自动设置模式
  begin
{$IFDEF UNICODE}
    FAnsiMode := False;
{$ELSE}
    FAnsiMode := True;
{$ENDIF}
  end
  else
    FAnsiMode := FOutMode;

  if FAnsiMode then
    FMaxCharCapacity := MaxInt
  else
    FMaxCharCapacity := MaxInt div 2;

  CharCapacity := STRING_BUILDER_DEFAULT_CAPACITY;
  FCharLength := 0;
end;

function TCnStringBuilder.Append(const Value: string): TCnStringBuilder;
begin
{$IFDEF UNICODE}
   if FAnsiMode then
     Result := AppendAnsi(AnsiString(Value))
   else
     Result := AppendString(Value);
{$ELSE}
   if FAnsiMode then
     Result := AppendString(Value)
   else
     Result := AppendWide(WideString(Value));
{$ENDIF}
end;

{$IFDEF UNICODE}

function TCnStringBuilder.AppendAnsi(const Value: AnsiString): TCnStringBuilder;
var
  Delta, OL: Integer;
begin
  Delta := Length(Value);
  if Delta <> 0 then
  begin
    OL := CharLength;
    CharLength := CharLength + Delta;
    if CharLength > CharCapacity then
      ExpandCharCapacity;
    Move(Pointer(Value)^, (PAnsiChar(Pointer(FAnsiData)) + OL)^, Delta * SizeOf(AnsiChar));
  end;
  Result := Self;
end;

{$ELSE}

function TCnStringBuilder.AppendWide(const Value: WideString): TCnStringBuilder;
var
  Delta, OL: Integer;
begin
  Delta := Length(Value);
  if Delta <> 0 then
  begin
    OL := CharLength;
    CharLength := CharLength + Delta;
    if CharLength > CharCapacity then
      ExpandCharCapacity;
    Move(Pointer(Value)^, (PWideChar(Pointer(FWideData)) + OL)^, Delta * SizeOf(WideChar));
  end;
  Result := Self;
end;

{$ENDIF}

constructor TCnStringBuilder.Create(IsAnsi: Boolean);
begin
  FModeIsFromOut := True;
  FOutMode := IsAnsi;     // 标记由外部指定 AnsiMode
  Create;
end;

destructor TCnStringBuilder.Destroy;
begin
  inherited;

end;

procedure TCnStringBuilder.ExpandCharCapacity;
var
  NC: Integer;
begin
  NC := (CharCapacity * 3) div 2;
  if CharLength > NC then
    NC := CharLength * 2;
  if NC > FMaxCharCapacity then
    NC := FMaxCharCapacity;
  if NC < 0 then
    NC := CharLength;

  CharCapacity := NC;
end;

function TCnStringBuilder.GetCharCapacity: Integer;
begin
{$IFDEF UNICODE}
   if FAnsiMode then
     Result := Length(FAnsiData)
   else
     Result := Length(FData);
{$ELSE}
   if FAnsiMode then
     Result := Length(FData)
   else
     Result := Length(FWideData);
{$ENDIF}
end;

procedure TCnStringBuilder.SetCharCapacity(const Value: Integer);
begin
  if (Value < FCharLength) or (Value > FMaxCharCapacity) then
    raise ERangeError.CreateResFmt(@SListCapacityError, [Value]);

{$IFDEF UNICODE}
   if FAnsiMode then  
     SetLength(FAnsiData, Value)   // FAnsiData
   else
     SetLength(FData, Value);      // FData
{$ELSE}
   if FAnsiMode then
     SetLength(FData, Value)       // FData
   else
     SetLength(FWideData, Value);  // FWideData
{$ENDIF}
end;

procedure TCnStringBuilder.SetCharLength(const Value: Integer);
var
  OL: Integer;
begin
  if (Value < 0) or (Value > FMaxCharCapacity) then
    raise ERangeError.CreateResFmt(@SListCapacityError, [Value]);

  OL := FCharLength;
  try
    FCharLength := Value;
    if FCharLength > CharCapacity then
      ExpandCharCapacity;
  except
    on E: EOutOfMemory do
    begin
      FCharLength := OL;
      raise;
    end;
  end;
end;

function TCnStringBuilder.AppendString(const Value: string): TCnStringBuilder;
var
  Delta, OL: Integer;
begin
  Delta := Length(Value);
  if Delta <> 0 then
  begin
    OL := CharLength;
    FCharLength := CharLength + Delta;
    if CharLength > CharCapacity then
      ExpandCharCapacity;

    Move(Pointer(Value)^, (PChar(Pointer(FData)) + OL)^, Delta * SizeOf(Char));
  end;
  Result := Self;
end;

function TCnStringBuilder.ToString: string;
begin
  if FCharLength = CharCapacity then
    Result := FData
  else
    Result := Copy(FData, 1, FCharLength);
end;

function TCnStringBuilder.ToAnsiString: AnsiString;
begin
{$IFDEF UNICODE}
  if FAnsiMode then // Unicode 环境下如果是 Ansi 模式，用 FAnsiData，无需转换
  begin
    if FCharLength = CharCapacity then
      Result := FAnsiData
    else
      Result := Copy(FAnsiData, 1, FCharLength);
  end
  else  // Unicode 环境下如果是非 Ansi 模式，用 FData，进行 AnsiString 转换
  begin
    if FCharLength = CharCapacity then
      Result := AnsiString(FData)
    else
      Result := AnsiString(Copy(FData, 1, FCharLength));
  end;
{$ELSE}
  Result := ToString; // 非 Unicode 环境下等于 ToString
{$ENDIF}
end;

function TCnStringBuilder.ToWideString: WideString;
begin
{$IFNDEF UNICODE}
  if FAnsiMode then // 非 Unicode 环境下如果是 Ansi 模式，用 FData，进行 WideString 转换
  begin
    if FCharLength = CharCapacity then
      Result := WideString(FData)
    else
      Result := WideString(Copy(FData, 1, FCharLength));
  end
  else // 非 Unicode 环境下如果是非 Ansi 模式，用 FWideData，无需转换
  begin
    if FCharLength = CharCapacity then
      Result := FWideData
    else
      Result := Copy(FWideData, 1, FCharLength);
  end;
{$ELSE}
  Result := ToString; // Unicode 环境下等于 ToString
{$ENDIF}
end;

function TCnStringBuilder.Append(Value: Integer): TCnStringBuilder;
begin
  Result := Append(IntToStr(Value));
end;

function TCnStringBuilder.Append(Value: SmallInt): TCnStringBuilder;
begin
  Result := Append(IntToStr(Value));
end;

function TCnStringBuilder.Append(Value: TObject): TCnStringBuilder;
begin
{$IFDEF OBJECT_HAS_TOSTRING}
  Result := Append(Value.ToString);
{$ELSE}
  Result := Append(IntToHex(TCnNativeInt(Value), 2));
{$ENDIF}
end;

function TCnStringBuilder.Append(Value: Int64): TCnStringBuilder;
begin
  Result := Append(IntToStr(Value));
end;

function TCnStringBuilder.Append(Value: Double): TCnStringBuilder;
begin
  Result := Append(FloatToStr(Value));
end;

function TCnStringBuilder.Append(Value: Byte): TCnStringBuilder;
begin
  Result := Append(IntToStr(Value));
end;

function TCnStringBuilder.Append(Value: Boolean): TCnStringBuilder;
begin
  if Value then
    Result := Append('True')
  else
    Result := Append('False');
end;

function TCnStringBuilder.AppendCurrency(Value: Currency): TCnStringBuilder;
begin
  Result := Append(CurrToStr(Value));
end;

function TCnStringBuilder.AppendChar(Value: Char): TCnStringBuilder;
var
  S: string;
begin
  SetLength(S, 1);
  Move(Value, S[1], SizeOf(Char));
  Result := Append(S);
end;

function TCnStringBuilder.Append(Value: ShortInt): TCnStringBuilder;
begin
  Result := Append(IntToStr(Value));
end;

function TCnStringBuilder.Append(Value: Char;
  RepeatCount: Integer): TCnStringBuilder;
begin
  Result := Append(StringOfChar(Value, RepeatCount));
end;

function TCnStringBuilder.Append(Value: PAnsiChar): TCnStringBuilder;
begin
  Result := Append(string(Value));
end;

function TCnStringBuilder.Append(const Value: string; StartIndex,
  Count: Integer): TCnStringBuilder;
begin
  Result := Append(Copy(Value, StartIndex, Count));
end;

function TCnStringBuilder.Append(Value: Cardinal): TCnStringBuilder;
begin
  Result := Append(UInt32ToStr(Value));
end;

{$IFDEF SUPPORT_UINT64}

function TCnStringBuilder.Append(Value: UInt64): TCnStringBuilder;
begin
  Result := Append(UInt64ToStr(Value));
end;

{$ENDIF}

function TCnStringBuilder.Append(Value: Single): TCnStringBuilder;
begin
  Result := Append(FloatToStr(Value));
end;

function TCnStringBuilder.Append(Value: Word): TCnStringBuilder;
begin
  Result := Append(IntToStr(Value));
end;

procedure TCnStringBuilder.Clear;
begin
  CharLength := 0;
  CharCapacity := STRING_BUILDER_DEFAULT_CAPACITY;
end;

function TCnStringBuilder.AppendLine: TCnStringBuilder;
begin
  Result := Append(SLineBreak);
end;

function TCnStringBuilder.AppendLine(const Value: string): TCnStringBuilder;
begin
  Result := Append(Value + SLineBreak);
end;

function TCnStringBuilder.Append(const AFormat: string;
  const Args: array of const): TCnStringBuilder;
begin
  Result := Append(Format(AFormat, Args));
end;

function TCnStringBuilder.AppendAnsiChar(Value: AnsiChar): TCnStringBuilder;
var
  S: AnsiString;
begin
  SetLength(S, 1);
  Move(Value, S[1], SizeOf(AnsiChar));
{$IFDEF UNICODE}
  Result := AppendAnsi(S);
{$ELSE}
  Result := Append(S); // Unicode 下 S 转为 string 可能会变问号
{$ENDIF}
end;

function TCnStringBuilder.AppendWideChar(Value: WideChar): TCnStringBuilder;
var
  S: WideString;
begin
  SetLength(S, 1);
  Move(Value, S[1], SizeOf(WideChar));
{$IFDEF UNICODE}
  Result := Append(S);
{$ELSE}
  Result := AppendWide(S);
{$ENDIF}
end;

end.
