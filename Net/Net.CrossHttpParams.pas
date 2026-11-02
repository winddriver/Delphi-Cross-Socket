{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpParams;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,
  Generics.Defaults,
  DateUtils,
  Math,

  {$IFDEF FPC}
  DTF.Types,
  DTF.Generics,
  {$ENDIF}

  Net.CrossHttpUtils,
  Net.CrossHttpSessions,

  Utils.RegEx,
  Utils.IOUtils,
  Utils.DateTime,
  Utils.StrUtils,
  Utils.ArrayUtils,
  Utils.Utils;

type
  TParamEntry = record
    // 业务使用的名称和值；Value 可以直接来自字符串，也可以由原始字节转换。
    Name, Value: string;
    // 仅字节来源保存原值。Header.Decode 会先去掉值两侧的 SP/HTAB，
    // 字节构造器本身不裁剪；完整行和原始空白见请求的 RawRequestHeader。
    // 记录复制、Items、枚举和 Assign 均共享数组；修改前应自行 Copy。
    RawValue: TBytes;
    // True 也可以对应空 RawValue，表示“收到过空值”；False 表示没有字节来源。
    HasRawValue: Boolean;
    /// <summary>保存名称和值字符串，不生成原始字节，也不校验具体协议语法。</summary>
    constructor Create(const AName, AValue: string); overload;
    /// <summary>复制字段值字节，并通过 TUtils.GetString 生成 Value。</summary>
    /// <param name="AName">已取得的参数名；本构造器不解析名称或冒号。</param>
    /// <param name="ARawValue">值缓冲区，只在调用期间借用，不保留输入指针。</param>
    /// <param name="ARawSize">字节数，不包含隐含的结尾零字符；零长度不读取指针。</param>
    /// <remarks>
    ///   负长度或 nil/正长度抛 EArgumentException。GetString 的 BOM 检测、
    ///   编码回退及转换异常保持原样；这不是新增的严格 UTF-8 解码器。
    /// </remarks>
    constructor Create(const AName: string; const ARawValue: Pointer;
      const ARawSize: Integer); overload;
  end;

  IParamEntryComparer = IComparer<TParamEntry>;
  TParamEntryComparison = {$IFDEF DELPHI}TComparison<TParamEntry>{$ELSE}TComparisonAnonymousFunc<TParamEntry>{$ENDIF};
  TParamEntryComparer = {$IFDEF DELPHI}TDelegatedComparer<TParamEntry>{$ELSE}TDelegatedComparerAnonymousFunc<TParamEntry>{$ENDIF};

  /// <summary>
  ///   参数基础类
  /// </summary>
  TBaseParams = class
  private type
    TEnumerator = class
    private
      FIndex: Integer;
      FParams: TBaseParams;
    public
      constructor Create(const AParams: TBaseParams);
      function GetCurrent: TParamEntry; inline;
      function MoveNext: Boolean; inline;
      property Current: TParamEntry read GetCurrent;
    end;
  private
    FParams: TList<TParamEntry>;

    function GetParamIndex(const AName: string): Integer;
    function GetParam(const AName: string): string;
    procedure SetParam(const AName, AValue: string);
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TParamEntry;
    procedure SetItem(AIndex: Integer; const AValue: TParamEntry);
  public
    constructor Create; overload; virtual;
    constructor Create(const AEncodedParams: string); overload; virtual;
    destructor Destroy; override;

    /// <summary>
    ///   枚举器
    /// </summary>
    function GetEnumerator: TEnumerator; inline;

    /// <summary>
    ///   复制完整记录，RawValue 按动态数组的引用语义共享；Self 不操作，nil 清空。
    /// </summary>
    procedure Assign(const ASource: TBaseParams);

    /// <summary>
    ///   追加完整记录，允许重名，不重新解码或修正四个字段；调用方维护其一致性。
    /// </summary>
    procedure Add(const AParamValue: TParamEntry); overload;

    /// <summary>
    ///   添加参数
    /// </summary>
    /// <param name="AName">
    ///   参数名
    /// </param>
    /// <param name="AValue">
    ///   参数值
    /// </param>
    /// <param name="ADupAllowed">
    ///   True 追加；False 更新第一条同名项，不存在时追加。
    ///   此字符串入口使目标项没有原始字节来源，不影响其他重复项。
    /// </param>
    procedure Add(const AName, AValue: string; ADupAllowed: Boolean = False); overload;

    /// <summary>
    ///   添加已编码参数
    /// </summary>
    /// <param name="AEncodedParams">
    ///   已编码参数字符串
    /// </param>
    procedure Add(const AEncodedParams: string); overload;

    /// <summary>
    ///   根据名称删除所有同名参数，不区分大小写
    /// </summary>
    /// <param name="AName">
    ///   参数名称
    /// </param>
    procedure Remove(const AName: string); overload;

    /// <summary>
    ///   根据序号删除指定参数
    /// </summary>
    /// <param name="AIndex">
    ///   参数序号
    /// </param>
    procedure Remove(AIndex: Integer); overload;

    /// <summary>
    ///   清除所有参数
    /// </summary>
    procedure Clear;

    /// <summary>
    ///   对参数排序
    /// </summary>
    /// <param name="AComparison">
    ///   自定义比较函数，为nil时按参数名排序
    /// </param>
    procedure Sort(const AComparison: TParamEntryComparison = nil);

    /// <summary>
    ///   从已编码的字符串中解码
    /// </summary>
    /// <param name="AEncodedParams">
    ///   已编码字符串
    /// </param>
    /// <param name="AClear">
    ///   是否清除现有数据
    /// </param>
    /// <returns>
    ///   解码是否成功
    /// </returns>
    function Decode(const AEncodedParams: string; AClear: Boolean = True): Boolean; virtual; abstract;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    /// <returns>
    ///   编码后的字符串
    /// </returns>
    function Encode: string; virtual; abstract;

    /// <summary>
    ///   获取参数值
    /// </summary>
    /// <param name="AName">
    ///   参数名称
    /// </param>
    /// <param name="AValue">
    ///   返回的参数值
    /// </param>
    /// <returns>
    ///   如果找到参数返回True，否则返回False
    /// </returns>
    function GetParamValue(const AName: string; out AValue: string): Boolean;

    /// <summary>
    ///   获取指定名称的所有参数值
    /// </summary>
    /// <param name="AName">
    ///   参数名称
    /// </param>
    /// <param name="AValues">
    ///   返回的参数值数组
    /// </param>
    /// <returns>
    ///   如果找到参数返回True，否则返回False
    /// </returns>
    /// <remarks>
    ///   按原顺序返回各项的 Value 文本，不合并重复字段；原始字节通过 Items/枚举中的
    ///   RawValue、HasRawValue 查看，此方法不会重新解码或回放 raw。
    /// </remarks>
    function GetHeaderValues(const AName: string; out AValues: TArray<string>): Boolean;

    /// <summary>
    ///   是否存在参数
    /// </summary>
    /// <param name="AName">
    ///   参数名称
    /// </param>
    /// <returns>
    ///   如果存在参数返回True，否则返回False
    /// </returns>
    function ExistsParam(const AName: string): Boolean;

    /// <summary>
    ///   按名称访问参数
    /// </summary>
    /// <param name="AName">
    ///   参数名称
    /// </param>
    /// <value>
    ///   参数值，如果不存在返回空字符串
    /// </value>
    property Params[const AName: string]: string read GetParam write SetParam; default;

    /// <summary>
    ///   按序号访问参数
    /// </summary>
    /// <param name="AIndex">
    ///   参数序号
    /// </param>
    /// <value>
    ///   参数名值对
    /// </value>
    /// <remarks>
    ///   读写的是完整记录，RawValue 引用共享。直接修改 Value 再回写时，
    ///   调用方须同步维护来源状态；按名称写字符串则由集合自动清除该项来源。
    /// </remarks>
    property Items[AIndex: Integer]: TParamEntry read GetItem write SetItem;

    /// <summary>
    ///   参数个数
    /// </summary>
    property Count: Integer read GetCount;
  end;

  /// <summary>
  ///   Url参数类
  /// </summary>
  THttpUrlParams = class(TBaseParams)
  private
    FEncodeName: Boolean;
    FEncodeValue: Boolean;
  public
    constructor Create; override;

    /// <summary>
    ///   从已编码的字符串中解码
    /// </summary>
    /// <param name="AEncodedParams">
    ///   已编码字符串
    /// </param>
    /// <param name="AClear">
    ///   是否清除现有数据
    /// </param>
    function Decode(const AEncodedParams: string; AClear: Boolean = True): Boolean; override;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; override;

    /// <summary>
    ///   是否对名称做编码
    /// </summary>
    property EncodeName: Boolean read FEncodeName write FEncodeName;

    /// <summary>
    ///   是否对名称做编码
    /// </summary>
    property EncodeValue: Boolean read FEncodeValue write FEncodeValue;
  end;

  /// <summary>
  ///   HTTP头类
  /// </summary>
  THttpHeader = class(TBaseParams)
  private
    // 共用结构扫描器，ASize 的单位由 ABytes 决定：
    // True：AData 按 PByte 读取，ASize 为字节数，并复制保存字段原始值；
    // False：AData 按 PChar 读取，ASize 为 UTF-16 码元数，不生成 RawValue。
    // 输入仅同步借用；所有下标沿用上述单位，不能把字符长度乘 SizeOf(Char)。
    function _Decode(const AData: Pointer; const ASize: Integer;
      const AClear, ABytes: Boolean): Boolean;
  public
    /// <summary>解析完整字段集合，不含请求行/状态行和正文；不负责增量组包。</summary>
    /// <param name="AData">只读输入缓冲区，在本次调用期间必须有效，不保存其指针。</param>
    /// <param name="ASize">准确的字节数；不要求结尾零字符，零长度空集合有效。</param>
    /// <param name="AClear">
    ///   True 先清空；False 追加。语法失败或转换异常时撤销本次新增项：
    ///   清空模式最终为空，追加模式保留原有记录和原始值。
    /// </param>
    /// <returns>结构有效返回 True，语法错误返回 False。</returns>
    /// <remarks>
    ///   可省略最后一行 CRLF 或最后的结束空行；字段间必须为 CRLF，
    ///   结束空行后不允许额外数据。字段值保存裁剪最外侧 SP/HTAB 后的字节。
    ///   负长度或 nil/正长度在改变集合前抛 EArgumentException；GetString 异常向上传播。
    /// </remarks>
    function Decode(const AData: Pointer; const ASize: Integer;
      AClear: Boolean = True): Boolean; reintroduce; overload;
    // 在所有同名头中匹配完整的逗号分隔 token，不接受子串。
    function ContainsToken(const AName, AToken: string): Boolean;
    /// <summary>
    ///   解析已有 Unicode 字符串；结构和回滚规则同字节入口，不生成原始字节。
    /// </summary>
    /// <param name="AEncodedParams">
    ///   完整字段集合。Length 按 UTF-16 码元计数，不是 UTF-8 字节数。
    /// </param>
    /// <param name="AClear">True 清空后解析，False 追加；失败时回滚本次新增项。</param>
    /// <remarks>
    ///   已有文本不再经 GetString 转换。网络原始控制字节的校验只在字节入口执行。
    ///   Header 的 Create(string)/Add(string) 包装此入口，并将 False 转为 EConvertError。
    /// </remarks>
    function Decode(const AEncodedParams: string; AClear: Boolean = True): Boolean; overload; override;

    /// <summary>
    ///   用当前 Value 生成含最终空行的 Unicode 头部文本，不回放 RawValue。
    /// </summary>
    /// <remarks>
    ///   非法字段或无效 UTF-16 抛 EConvertError，不静默跳过字段，不修改集合。
    ///   此处不发送数据；调用方拼好首行等内容后再将完整头部编码为无 BOM UTF-8。
    /// </remarks>
    function Encode: string; override;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   x-www-form-urlencoded 格式参数
  /// </summary>
  {$ENDREGION}
  TFormUrlEncoded = class(THttpUrlParams);

  /// <summary>
  ///   带分隔符的参数
  /// </summary>
  TDelimitParams = class(TBaseParams)
  private
    FDelimiter: Char;
    FUrlEncode: Boolean;
  public
    constructor Create(const ADelimiter: Char; const AUrlEncode: Boolean = False); reintroduce; overload; virtual;
    constructor Create(const AEncodedParams: string; const ADelimiter: Char; const AUrlEncode: Boolean = False); reintroduce; overload; virtual;

    /// <summary>
    ///   从已编码的字符串中解码
    /// </summary>
    /// <param name="AEncodedParams">
    ///   已编码字符串
    /// </param>
    /// <param name="AClear">
    ///   是否清除现有数据
    /// </param>
    function Decode(const AEncodedParams: string; AClear: Boolean = True): Boolean; override;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; override;

    /// <summary>
    ///   分隔字符
    /// </summary>
    property Delimiter: Char read FDelimiter write FDelimiter;

    /// <summary>
    ///   是否进行URL编解码
    /// </summary>
    property UrlEncode: Boolean read FUrlEncode write FUrlEncode;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   客户端请求头中的Cookies
  /// </summary>
  /// <remarks>
  ///   <para>
  ///     格式如下
  ///   </para>
  ///   <para>
  ///     Cookie: name1=value1; name2=value2; ...
  ///   </para>
  /// </remarks>
  {$ENDREGION}
  TRequestCookies = class(TBaseParams)
  public
    /// <summary>
    ///   从已编码的字符串中解码
    /// </summary>
    /// <param name="AEncodedParams">
    ///   已编码字符串
    /// </param>
    /// <param name="AClear">
    ///   是否清除现有数据
    /// </param>
    function Decode(const AEncodedParams: string; AClear: Boolean = True): Boolean; override;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; override;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   响应头中的Cookie
  /// </summary>
  /// <remarks>
  ///   <para>
  ///     格式如下
  ///   </para>
  ///   <para>
  ///     Set-Cookie: name=value; [expires=date;] [path=path;]
  ///     [domain=domain;] [secure;] [HttpOnly;] <br />
  ///   </para>
  /// </remarks>
  {$ENDREGION}
  TResponseCookie = record
    /// <summary>
    ///   Cookie名称
    /// </summary>
    Name: string;

    /// <summary>
    ///   Cookie数据
    /// </summary>
    Value: string;

    /// <summary>
    ///   Cookie有效期秒数, 如果设置为0则浏览器关闭后该Cookie即失效
    /// </summary>
    MaxAge: Integer;

    /// <summary>
    ///   域名作用域
    /// </summary>
    /// <remarks>
    ///   定义Cookie的生效作用域, 只有当域名和路径同时满足的时候, 浏览器才会将Cookie发送给Server.
    ///   如果没有设置Domain和Path的话, 他们会被默认为当前请求页面对应值
    /// </remarks>
    Domain: string;

    /// <summary>
    ///   路径作用域
    /// </summary>
    /// <remarks>
    ///   定义Cookie的生效作用域, 只有当域名和路径同时满足的时候, 浏览器才会将Cookie发送给Server.
    ///   如果没有设置Domain和Path的话, 他们会被默认为当前请求页面对应值
    /// </remarks>
    Path: string;

    /// <summary>
    ///   是否启用 HttpOnly
    /// </summary>
    /// <remarks>
    ///   HttpOnly字段告诉浏览器, 只有在HTTP协议下使用, 对浏览器的脚本不可见, 所以跨站脚本攻击时也不会被窃取
    /// </remarks>
    HttpOnly: Boolean;

    /// <summary>
    ///   是否启用Secure
    /// </summary>
    /// <remarks>
    ///   Secure字段告诉浏览器在https通道时, 对Cookie进行安全加密, 这样即时有黑客监听也无法获取cookie内容
    /// </remarks>
    Secure: Boolean;

    constructor Create(const AName, AValue: string; AMaxAge: Integer;
      const APath: string = ''; const ADomain: string = '';
      AHttpOnly: Boolean = False; ASecure: Boolean = False); overload;

    constructor Create(const ACookieData: string; const ADomain: string = ''); overload;

    function Encode: string;
  end;

  /// <summary>
  ///   Cookie类
  /// </summary>
  TResponseCookies = class(TList<TResponseCookie>)
  private
    function GetCookieIndex(const AName: string): Integer;
    function GetCookie(const AName: string): TResponseCookie;
    procedure SetCookie(const AName: string; const Value: TResponseCookie);
  public
    procedure AddOrSet(const AName, AValue: string; AMaxAge: Integer;
      const APath: string = ''; const ADomain: string = '';
      AHttpOnly: Boolean = False; ASecure: Boolean = False);
    procedure Remove(const AName: string);

    property Cookies[const AName: string]: TResponseCookie read GetCookie write SetCookie;
  end;

  // 可延迟落盘的文件流；FilePath 只反映当前存储，读取不得触发 IO。
  TFormFileStream = class(TStream)
  protected
    function GetFilePath: string; virtual; abstract;
  public
    function EnsureFilePath: string; virtual; abstract;
    property FilePath: string read GetFilePath;
  end;

  TFormField = class
  private
    FName: string;
    FValue: TStream;
    FFileName: string;
    FFilePath: string;
    FContentType: string;
    FContentTransferEncoding: string;
    FValueOwned, FIsTempFile: Boolean;
    function GetFilePath: string;
    function GetIsFile: Boolean;
  public
    constructor Create; overload;
    destructor Destroy; override;

    /// <summary>
    ///   从源对象设置数据
    /// </summary>
    procedure Assign(const ASource: TFormField);

    /// <summary>
    ///   将数据转为字节
    /// </summary>
    function AsBytes: TBytes;

    /// <summary>
    ///   将数据转为字符串
    /// </summary>
    /// <param name="AEncoding">
    ///   字符串编码
    /// </param>
    function AsString(AEncoding: TEncoding = nil): string;

    /// <summary>
    ///   释放流数据
    /// </summary>
    procedure FreeValue;
    // 显式需要文件路径时才落盘；普通文件和旧的无路径发送流保持原有行为。
    function EnsureFilePath: string;

    /// <summary>
    ///   名称
    /// </summary>
    property Name: string read FName;

    /// <summary>
    ///   原始流数据
    /// </summary>
    property Value: TStream read FValue;

    /// <summary>
    ///   文件名（只有文件才有该属性）
    /// </summary>
    property FileName: string read FFileName;

    /// <summary>
    ///   文件保存路径（只有文件才有该属性）
    /// </summary>
    property FilePath: string read GetFilePath;
    // 接收文件可暂存在内存，不能再仅用路径是否为空区分它和文本字段。
    property IsFile: Boolean read GetIsFile;

    /// <summary>
    ///   内容类型（只有文件才有该属性）
    /// </summary>
    property ContentType: string read FContentType;
    property ContentTransferEncoding: string read FContentTransferEncoding;
  end;

  /// <summary>
  ///   FormData解码结果
  /// </summary>
  TFormDataDecodeResult = (frContinue, frComplete, frFailed);

  /// <summary>
  ///   MultiPartFormData类
  /// </summary>
  THttpMultiPartFormData = class
  private type
    TEnumerator = class
    private
      FList: TList<TFormField>;
      FIndex: Integer;
    public
      constructor Create(const AList: TList<TFormField>);
      function GetCurrent: TFormField; inline;
      function MoveNext: Boolean; inline;
      property Current: TFormField read GetCurrent;
    end;
  public type
    TDecodeState = (dsBoundary, dsDetect, dsPartHeader, dsPartData);

    /// <summary>
    ///   头部结束标记检测状态机, 严格匹配 #13#10#13#10 序列
    /// </summary>
    TLineEndState = (lesCR1, lesLF1, lesCR2, lesLF2);

    /// <summary>
    ///   dsDetect 状态: Boundary 标记之后判断是 Header 数据还是结束标记
    /// </summary>
    TPostBoundaryState = (pbsDetect, pbsHeader1, pbsEnd1, pbsEnd2, pbsEnd3);
  private const
    MAX_PART_HEADER: Integer = 64 * 1024;
  private
    FBoundary, FStoragePath: string;
    FFirstBoundaryBytes, FBoundaryBytes, FLookbehind: TBytes;
    FBoundaryIndex, FPartDataBegin: Integer;
    FPostBoundaryState: TPostBoundaryState;
    FPrevBoundaryIndex: Integer;
    FDecodeState: TDecodeState;
    FLineEndState: TLineEndState;
    FPartFields: TObjectList<TFormField>;
    FCurrentPartHeader: TBytes;
    FCurrentPartHeaderLen: Integer;
    FCurrentPartField: TFormField;
    FAutoDeleteFiles: Boolean;
    FMaxPartDataSize: Integer;
    FCurrentPartDataSize: Int64;

    function GetItemIndex(const AName: string): Integer;
    function GetItem(AIndex: Integer): TFormField;
    function GetCount: Integer;
    function GetDataSize: Integer;
    function GetField(const AName: string): TFormField;
    procedure SetBoundary(const AValue: string);
  protected
    // 默认仍直接创建文件；私有协议可仅为特定字段覆盖存储方式。
    function CreateFileStream(const AField: TFormField): TStream; virtual;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    {$REGION 'Documentation'}
    /// <summary>
    ///   枚举器
    /// </summary>
    {$ENDREGION}
    function GetEnumerator: TEnumerator; inline;

    {$REGION 'Documentation'}
    /// <summary>
    ///   从源对象设置数据
    /// </summary>
    {$ENDREGION}
    procedure Assign(const ASource: THttpMultiPartFormData);

    {$REGION 'Documentation'}
    /// <summary>
    /// 初始化Boundary(Decode之前调用)
    /// </summary>
    {$ENDREGION}
    procedure InitWithBoundary(const ABoundary: string);
    // Decode 仍为 frContinue 时，仅在外层已确定 EOF 后判断无尾部 CRLF 的结束行。
    function EndsAtClosingBoundary: Boolean;

    {$REGION 'Documentation'}
    /// <summary>
    ///   从内存中解码(必须先调用InitWithBoundary)
    /// </summary>
    /// <param name="ABuf">
    ///   待解码数据
    /// </param>
    /// <param name="ALen">
    ///   数据长度
    /// </param>
    /// <remarks>
    ///   已知限制: 仅支持 multipart/form-data; 不支持 RFC 2046 preamble/epilogue 文本;
    ///   不支持 multipart/mixed 嵌套; Content-Transfer-Encoding 仅存储不解码.
    /// </remarks>
    {$ENDREGION}
    function Decode(const ABuf: Pointer; ALen: Integer): TFormDataDecodeResult; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   从内存中解码并返回实际消费的字节数(必须先调用InitWithBoundary)
    /// </summary>
    /// <param name="ABuf">
    ///   待解码数据
    /// </param>
    /// <param name="ALen">
    ///   数据长度
    /// </param>
    /// <param name="AConsumed">
    ///   出参: 实际消费的字节数. frComplete 时可能小于 ALen, 调用方需要用剩余字节继续后续解析.
    /// </param>
    {$ENDREGION}
    function Decode(const ABuf: Pointer; ALen: Integer; out AConsumed: Integer): TFormDataDecodeResult; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   从数据流解码(必须先调用InitWithBoundary)
    /// </summary>
    /// <param name="AStream">
    ///   待解码数据流
    /// </param>
    {$ENDREGION}
    function Decode(const AStream: TStream): TFormDataDecodeResult; overload;

    // 长度协议已验证完整字段后直接装配，不再经过 multipart boundary 解析。
    // 成功后接管 AValue；抛错时流仍归调用方。接收文件由 AutoDeleteFiles 管理。
    function AddDecodedField(const AName, AFileName, AContentType,
      AContentTransferEncoding: string; const AValue: TStream;
      const AIsFile: Boolean): TFormField;

    {$REGION 'Documentation'}
    /// <summary>
    /// 清除所有Items
    /// </summary>
    {$ENDREGION}
    procedure Clear;

    {$REGION 'Documentation'}
    /// <summary>
    ///   添加字段
    /// </summary>
    /// <param name="AField">
    ///   字段对象
    /// </param>
    {$ENDREGION}
    function AddField(const AField: TFormField): TFormField; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   添加字段
    /// </summary>
    /// <param name="AFieldName">
    ///   字段名
    /// </param>
    /// <param name="AValue">
    ///   字段值
    /// </param>
    {$ENDREGION}
    function AddField(const AFieldName: string; const AValue: TBytes): TFormField; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   添加字段
    /// </summary>
    /// <param name="AFieldName">
    ///   字段名
    /// </param>
    /// <param name="AValue">
    ///   字段值
    /// </param>
    {$ENDREGION}
    function AddField(const AFieldName, AValue: string): TFormField; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   添加文件字段
    /// </summary>
    /// <param name="AFieldName">
    ///   字段名
    /// </param>
    /// <param name="AFileName">
    ///   文件名
    /// </param>
    /// <param name="AStream">
    ///   文件流
    /// </param>
    /// <param name="AOwned">
    ///   是否自动释放
    /// </param>
    {$ENDREGION}
    function AddFile(const AFieldName, AFileName: string;
      const AStream: TStream; const AOwned: Boolean = False): TFormField; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   添加文件字段
    /// </summary>
    /// <param name="AFieldName">
    ///   字段名
    /// </param>
    /// <param name="AFileName">
    ///   文件名
    /// </param>
    {$ENDREGION}
    function AddFile(const AFieldName, AFileName: string): TFormField; overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   根据名称删除指定字段
    /// </summary>
    /// <param name="AFieldName">
    ///   字段名
    /// </param>
    {$ENDREGION}
    procedure Remove(const AFieldName: string); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   根据序号删除指定字段
    /// </summary>
    /// <param name="AIndex">
    ///   字段序号
    /// </param>
    {$ENDREGION}
    procedure Remove(AIndex: Integer); overload;

    {$REGION 'Documentation'}
    /// <summary>
    /// 查找参数
    /// </summary>
    {$ENDREGION}
    function FindField(const AFieldName: string; out AField: TFormField): Boolean;

    function AsBytes(const AFieldName: string; out AValue: TBytes): Boolean; overload;
    function AsBytes(const AFieldName: string): TBytes; overload;

    function AsStream(const AFieldName: string; out AValue: TStream): Boolean; overload;
    function AsStream(const AFieldName: string): TStream; overload;

    function AsString(const AFieldName: string; const AEncoding: TEncoding; out AValue: string): Boolean; overload;
    function AsString(const AFieldName: string; out AValue: string): Boolean; overload;
    function AsString(const AFieldName: string; const AEncoding: TEncoding = nil): string; overload;

    {$REGION 'Documentation'}
    /// <summary>
    /// Boundary特征字符串
    /// </summary>
    {$ENDREGION}
    property Boundary: string read FBoundary write SetBoundary;

    {$REGION 'Documentation'}
    /// <summary>
    /// 上传文件保存的路径
    /// </summary>
    {$ENDREGION}
    property StoragePath: string read FStoragePath write FStoragePath;

    {$REGION 'Documentation'}
    /// <summary>
    /// 按序号访问参数
    /// </summary>
    {$ENDREGION}
    property Items[AIndex: Integer]: TFormField read GetItem;

    {$REGION 'Documentation'}
    /// <summary>
    ///   按名称访问参数
    /// </summary>
    {$ENDREGION}
    property Fields[const AName: string]: TFormField read GetField;

    {$REGION 'Documentation'}
    /// <summary>
    /// Items个数(只读)
    /// </summary>
    {$ENDREGION}
    property Count: Integer read GetCount;

    {$REGION 'Documentation'}
    /// <summary>
    /// 所有Items数据的总尺寸(字节数)
    /// </summary>
    {$ENDREGION}
    property DataSize: Integer read GetDataSize;

    {$REGION 'Documentation'}
    /// <summary>
    /// 对象释放时自动删除上传的文件
    /// </summary>
    {$ENDREGION}
    property AutoDeleteFiles: Boolean read FAutoDeleteFiles write FAutoDeleteFiles;

    {$REGION 'Documentation'}
    /// <summary>
    /// 单个 Part Body 最大字节数, 0 表示不限制. 超过限制时 Decode 返回 frFailed.
    /// </summary>
    {$ENDREGION}
    property MaxPartDataSize: Integer read FMaxPartDataSize write FMaxPartDataSize;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   MultiPartFormData流
  /// </summary>
  /// <remarks>
  ///   动态从 MultiPartFormData 对象中读取数据, 而不是打包到内存中, 所以支持从磁盘加载超大文件
  ///   视图存活期间不得修改字段集合、字段信息、底层流对象及所有权。
  ///   字段流大小改变时，在访问该字段时抛出 EReadError；不支持并发修改底层流。
  /// </remarks>
  {$ENDREGION}
  THttpMultiPartFormStream = class(TStream)
  private type
    TFormFieldEx = record
      Header: TBytes;
      Field: TFormField;
      Stream: TStream;
      Offset, EndOffset, DataSize: Int64;

      function HeaderSize: Integer;
    end;

    PFormFieldEx = ^TFormFieldEx;
    TFormFieldExArray = TArray<TFormFieldEx>;
  private
    FMultiPartFormData: THttpMultiPartFormData;
    FOwned: Boolean;
    FFormFieldExArray: TFormFieldExArray;
    FMultiPartEnd: TBytes;
    FSize, FPosition, FEndPos: Int64;
    FFieldIndex: Integer;

    procedure _Init;
    procedure _CheckField(const AIndex: Integer);
    function _GetFieldIndexByOffset(const AOffset: Int64): Integer;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(const AMultiPartFormData: THttpMultiPartFormData;
      const AOwned: Boolean = False); reintroduce;
    destructor Destroy; override;

    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;

    property MultiPartFormData: THttpMultiPartFormData read FMultiPartFormData;
  end;

  // 保留旧单元中的类型名；会话实现集中在独立单元。
  ISession = Net.CrossHttpSessions.ISession;
  ISessions = Net.CrossHttpSessions.ISessions;
  TSessionBase = Net.CrossHttpSessions.TSessionBase;
  TSession = Net.CrossHttpSessions.TSession;
  TSessionClass = Net.CrossHttpSessions.TSessionClass;
  TSessionsBase = Net.CrossHttpSessions.TSessionsBase;
  TSessions = Net.CrossHttpSessions.TSessions;
  {$IFDEF CROSS_SESSION_TESTS}
  TSessionTestHook = Net.CrossHttpSessions.TSessionTestHook;
  TSessionTestOptions = Net.CrossHttpSessions.TSessionTestOptions;
  {$ENDIF}

{$IFDEF CROSS_SESSION_TESTS}
procedure SetSessionTestOptions(const AOptions: TSessionTestOptions);
procedure ClearExpiredSessionsForTest(const ASessions: TSessions);
{$ENDIF}

implementation

type
  PParamEntry = ^TParamEntry;

  {$IFDEF FPC}
  // 仅 Header 使用，避免含 raw 的记录在 FPC Clear 中先搬到临时删除数组。
  TParamList = TList<TParamEntry>;
  THeaderParamList = class(TParamList)
  protected
    procedure SetCapacity(AValue: SizeInt); override;
  public
    procedure ClearHeader;
  end;
  TParamListClass = class of TParamList;
  {$ENDIF}

{$IFDEF FPC}
procedure THeaderParamList.SetCapacity(AValue: SizeInt);
begin
  if AValue = 0 then
  begin
    // 使用 RTL 留给后代的字段；释放所有托管引用及容量，不跨请求保留数组。
    // TList.Destroy 也经由此虚方法释放容量。
    FLength := 0;
    FItems := nil;
  end else
    inherited SetCapacity(AValue);
end;

procedure THeaderParamList.ClearHeader;
begin
  SetCapacity(0);
end;
{$ENDIF}

// 只借用公开后备数组的元素地址，不依赖 TList 私有布局，也不建立整记录副本。
// Delphi 用 PList 避免 GetList 返回托管数组临时引用；FPC 的 List 直接读取数组字段。
// 空数组可返回 nil；调用方仅在 Count 范围内读取，不跨突变/扩容保存元素指针。
function _ParamData(const AParams: TList<TParamEntry>): PParamEntry; inline;
begin
  {$IFDEF DELPHI}
    {$IF CompilerVersion >= 35.0}
    // D11+ 使用公开 PList，避免 List getter 返回托管数组造成临时引用。
    Result := PParamEntry(AParams.PList^);
    {$ELSE}
    // 旧 Delphi 保留已有 List 入口；其运行性能未纳入本轮验证。
    Result := PParamEntry(AParams.List);
    {$IFEND}
  {$ELSE}
  // FPC 的公开 List 直接读取后备数组，不需要 Delphi 的 PList 适配。
  Result := PParamEntry(AParams.List);
  {$ENDIF}
end;

// 只读取容量，不产生后备数组的托管临时引用；不改变扩容策略或持有元素地址。
// 与 _ParamData 一样只借用 RTL 公开入口，旧 Delphi/FPC 保留原 Capacity 实现。
function _ParamCapacity(const AParams: TList<TParamEntry>): NativeInt; inline;
begin
  {$IFDEF DELPHI}
    {$IF CompilerVersion >= 35.0}
    Result := Length(AParams.PList^);
    {$ELSE}
    Result := AParams.Capacity;
    {$IFEND}
  {$ELSE}
  Result := AParams.Capacity;
  {$ENDIF}
end;


{$IFDEF CROSS_SESSION_TESTS}
procedure SetSessionTestOptions(const AOptions: TSessionTestOptions);
begin
  Net.CrossHttpSessions.SetSessionTestOptions(AOptions);
end;

procedure ClearExpiredSessionsForTest(const ASessions: TSessions);
begin
  Net.CrossHttpSessions.ClearExpiredSessionsForTest(ASessions);
end;
{$ENDIF}

function _IsHttpToken(const AValue: string): Boolean;
var
  I: Integer;
begin
  if (AValue = '') then Exit(False);

  for I := 1 to Length(AValue) do
  begin
    case AValue[I] of
      'A'..'Z', 'a'..'z', '0'..'9',
      '!', '#', '$', '%', '&', '''', '*', '+', '-', '.', '^', '_', '`', '|', '~': ;
    else
      Exit(False);
    end;
  end;

  Result := True;
end;

function _IsCookieOctets(const AValue: string): Boolean;
var
  I, LCode: Integer;
begin
  for I := 1 to Length(AValue) do
  begin
    LCode := Ord(AValue[I]);
    case LCode of
      $21,           // '!'
      $23..$2B,      // '#' to '+'
      $2D..$3A,      // '-' to ':'
      $3C..$5B,      // '<' to '['
      $5D..$7E: ;    // ']' to '~'
    else
      Exit(False);
    end;
  end;

  Result := True;
end;

function _IsCookieAvValue(const AValue: string): Boolean;
var
  I, LCode: Integer;
begin
  for I := 1 to Length(AValue) do
  begin
    LCode := Ord(AValue[I]);
    if (LCode < $20) or (LCode >= $7F) or (AValue[I] = ';') then
      Exit(False);
  end;

  Result := True;
end;

function _TryNormalizeCookieValue(const AValue: string;
  out ANormalizedValue: string; const ACheckCookieOctets: Boolean): Boolean;
begin
  ANormalizedValue := AValue;
  if (Length(ANormalizedValue) >= 2) then
    if (ANormalizedValue[1] = '"')
      and (ANormalizedValue[High(ANormalizedValue)] = '"') then
      ANormalizedValue := Copy(ANormalizedValue, 2, Length(ANormalizedValue) - 2);

  if ACheckCookieOctets then
    Result := _IsCookieOctets(ANormalizedValue)
  else
    Result := True;
end;

function _NormalizeCookieDomain(const AValue: string): string;
begin
  if not _IsCookieAvValue(AValue) then Exit('');

  Result := AValue.Trim.ToLower;
  if (Result <> '') then
    if (Result[1] = '.') then
      Delete(Result, 1, 1);
end;

function _TryParseCookieMaxAge(const AValue: string; out AMaxAge: Integer): Boolean;
var
  I: Integer;
begin
  AMaxAge := 0;
  Result := False;
  if (AValue = '') then Exit;

  if (AValue[1] = '-') then
  begin
    if (Length(AValue) = 1) then Exit;
    for I := 2 to Length(AValue) do
      if not CharInSet(AValue[I], ['0'..'9']) then Exit;
  end else
  begin
    for I := 1 to Length(AValue) do
      if not CharInSet(AValue[I], ['0'..'9']) then Exit;
  end;

  Result := TryStrToInt(AValue, AMaxAge);
end;

{ TParamEntry }

constructor TParamEntry.Create(const AName,
  AValue: string);
begin
  Name := AName;
  Value := AValue;
  RawValue := nil;
  HasRawValue := False;
end;

// AEntry 是调用方拥有的记录；AName 和原字节仅在本次调用期间借用。
// 先复制 raw 并完成 GetString，再提交各托管字段，参数/分配/转换异常不改动旧记录。
// 过程使用 var 显式写入槽位，避免依赖不同编译器的实例 record constructor 调用语义。
procedure _InitRawParamEntry(var AEntry: TParamEntry; const AName: string;
  const ARawValue: Pointer; const ARawSize: Integer); inline;
var
  LRawValue: TBytes;
  LValue: string;
begin
  if (ARawSize < 0) or ((ARawValue = nil) and (ARawSize > 0)) then
    raise EArgumentException.Create('Invalid header value buffer');
  // 输入可在调用返回后被释放/覆盖；解码与保存使用同一份自有 raw，空值也保留来源。
  SetLength(LRawValue, ARawSize);
  if ARawSize > 0 then
    Move(ARawValue^, LRawValue[0], ARawSize);
  LValue := TUtils.GetString(PByte(LRawValue), ARawSize);
  AEntry.Name := AName;
  AEntry.Value := LValue;
  AEntry.RawValue := LRawValue;
  AEntry.HasRawValue := True;
end;

constructor TParamEntry.Create(const AName: string; const ARawValue: Pointer;
  const ARawSize: Integer);
begin
  _InitRawParamEntry(Self, AName, ARawValue, ARawSize);
end;

{ TBaseParams.TEnumerator }

constructor TBaseParams.TEnumerator.Create(const AParams: TBaseParams);
begin
  FParams := AParams;
  FIndex := -1;
end;

function TBaseParams.TEnumerator.GetCurrent: TParamEntry;
begin
  Result := FParams.Items[FIndex];
end;

function TBaseParams.TEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := (FIndex < FParams.Count);
end;

{ TBaseParams }

constructor TBaseParams.Create;
{$IFDEF FPC}
var
  LParamsClass: TParamListClass;
{$ENDIF}
begin
  {$IFDEF FPC}
  LParamsClass := TParamList;
  if Self is THttpHeader then
    LParamsClass := THeaderParamList;
  FParams := LParamsClass.Create(TComparer<TParamEntry>.Construct(
  {$ELSE}
  FParams := TList<TParamEntry>.Create(TComparer<TParamEntry>.Construct(
  {$ENDIF}
    function(const Left, Right: TParamEntry): Integer
    begin
      Result := CompareText(Left.Name, Right.Name, TLocaleOptions.loUserLocale);
    end));
end;

constructor TBaseParams.Create(const AEncodedParams: string);
begin
  Create;
  // 构造器没有 Boolean 返回值；仅 Header 将严格解析失败转为异常，
  // 不改变 URL 参数、Cookie 等其他子类的既有构造行为。
  if not Decode(AEncodedParams, True) and (Self is THttpHeader) then
    raise EConvertError.Create('Invalid HTTP header');
end;

destructor TBaseParams.Destroy;
begin
  FreeAndNil(FParams);
  inherited;
end;

// 扩容前先构造完整记录，保住传入的字符串引用，再由 RTL 按原策略扩容。
// 不内联，避免容量内追加也初始化、复制、终结整条临时 TParamEntry。
procedure _AddParamItem(const AParams: TList<TParamEntry>; const AName, AValue: string);
begin
  AParams.Add(TParamEntry.Create(AName, AValue));
end;

procedure TBaseParams.Add(const AName, AValue: string; ADupAllowed: Boolean);
var
  I, LCapacity: NativeInt;
  P: PParamEntry;
begin
  if not ADupAllowed then
  begin
    SetParam(AName, AValue);
    Exit;
  end;
  I := FParams.Count;
  LCapacity := _ParamCapacity(FParams);
  if I >= LCapacity then
  begin
    _AddParamItem(FParams, AName, AValue);
    Exit;
  end;
  // 已有容量的新槽由 RTL 清零；此处不扩容，字符串参数的现有别名仍有效。
  // 只建立最终字段引用，不制造 raw 来源，也不产生整记录中转。
  FParams.Count := I + 1;
  P := _ParamData(FParams);
  Inc(P, I);
  P^.Name := AName;
  P^.Value := AValue;
  P^.HasRawValue := False;
end;

procedure TBaseParams.Add(const AEncodedParams: string);
begin
  // Header.Decode 先完成追加回滚，再在此抛错；经基类引用调用也遵守此合同。
  if not Decode(AEncodedParams, False) and (Self is THttpHeader) then
    raise EConvertError.Create('Invalid HTTP header');
end;

procedure TBaseParams.Assign(const ASource: TBaseParams);
var
  I: Integer;
  P: PParamEntry;
begin
  // 必须在 Clear 前判断自赋值，否则也会清空作为来源的同一对象。
  if ASource = Self then Exit;
  Clear;

  if (ASource = nil) or (ASource.Count <= 0) then Exit;

  // 来源和目标列表独立；循环只修改目标，借用来源记录不会被目标扩容失效。
  // Add仍复制完整记录并管理引用，保留raw共享及原增长策略，省去枚举器和记录中转。
  P := _ParamData(ASource.FParams);
  for I := 0 to ASource.Count - 1 do
  begin
    Add(P^);
    Inc(P);
  end;
end;

procedure TBaseParams.Add(const AParamValue: TParamEntry);
begin
  FParams.Add(AParamValue);
end;

procedure TBaseParams.Clear;
begin
  {$IFDEF FPC}
  if FParams is THeaderParamList then
    THeaderParamList(FParams).ClearHeader
  else
  {$ENDIF}
    FParams.Clear;
end;

function TBaseParams.GetParamIndex(const AName: string): Integer;
var
  I: Integer;
  P: PParamEntry;
begin
  // 这里只需 Name；直接借用元素，避免 Items 为每次比较复制包含 raw 的整条记录。
  P := _ParamData(FParams);
  for I := 0 to FParams.Count - 1 do
  begin
    if TStrUtils.SameText(P^.Name, AName) then Exit(I);
    Inc(P);
  end;
  Result := -1;
end;

function TBaseParams.GetParamValue(const AName: string;
  out AValue: string): Boolean;
var
  I: Integer;
  P: PParamEntry;
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
  begin
    P := _ParamData(FParams);
    Inc(P, I);
    AValue := P^.Value;
    Exit(True);
  end;

  AValue := '';
  Result := False;
end;

function TBaseParams.GetHeaderValues(const AName: string;
  out AValues: TArray<string>): Boolean;
var
  I, LCount: Integer;
  P: PParamEntry;
begin
  AValues := nil;
  LCount := 0;
  Result := False;
  P := _ParamData(FParams);
  for I := 0 to FParams.Count - 1 do
  begin
    if TStrUtils.SameText(P^.Name, AName) then
    begin
      // 找到首项后才预留剩余字段的容量；缺失字段查询不申请临时数组。
      if LCount = 0 then SetLength(AValues, FParams.Count - I);
      AValues[LCount] := P^.Value;
      Inc(LCount);
      Result := True;
    end;
    Inc(P);
  end;
  // 长度相同时不再调用SetLength，避免不必要的重分配请求；需要缩容时仍照常处理。
  if Length(AValues) <> LCount then SetLength(AValues, LCount);
end;

function THttpHeader.ContainsToken(const AName, AToken: string): Boolean;
var
  I, J, LStart, LEnd, LNext, LLength, LTokenLength: Integer;
  LValue: string;
  C, T: Char;
  LMatched: Boolean;
  P: PParamEntry;
begin
  if not _IsHttpToken(AToken) then Exit(False);
  LTokenLength := Length(AToken);
  P := _ParamData(FParams);
  for I := 0 to FParams.Count - 1 do
  begin
    if TStrUtils.SameText(P^.Name, AName) then
    begin
      LValue := P^.Value;
      LLength := Length(LValue);
      LStart := 1;
      while LStart <= LLength do
      begin
        LEnd := LStart;
        while (LEnd <= LLength) and (LValue[LEnd] <> ',') do Inc(LEnd);
        LNext := LEnd + 1;
        Dec(LEnd);
        // 与原 Trim 一致，只去除两端不大于空格的字符，不创建子串。
        while (LStart <= LEnd) and (LValue[LStart] <= ' ') do Inc(LStart);
        while (LEnd >= LStart) and (LValue[LEnd] <= ' ') do Dec(LEnd);
        if LEnd - LStart + 1 = LTokenLength then
        begin
          LMatched := True;
          for J := 1 to LTokenLength do
          begin
            C := LValue[LStart + J - 1];
            T := AToken[J];
            // AToken 已验证；仅折叠 ASCII 大小写，匹配成功也就验证了输入 token。
            if (C >= 'A') and (C <= 'Z') then C := Char(Ord(C) + 32);
            if (T >= 'A') and (T <= 'Z') then T := Char(Ord(T) + 32);
            if C <> T then
            begin
              LMatched := False;
              Break;
            end;
          end;
          if LMatched then Exit(True);
        end;
        LStart := LNext;
      end;
    end;
    Inc(P);
  end;
  Result := False;
end;

procedure TBaseParams.Remove(const AName: string);
var
  I: Integer;
  P: PParamEntry;
begin
  // 只读名称，不为比较复制Value/raw；倒序保持重复项删除规则。
  for I := FParams.Count - 1 downto 0 do
  begin
    // 删除后元素/后备数组可能改变，每轮重新取地址，不跨删除保存旧指针。
    P := _ParamData(FParams);
    Inc(P, I);
    if TStrUtils.SameText(P^.Name, AName) then
      // 通过既有非inline重载隔离Delete的托管记录临时，未命中时无需初始化/终结它。
      Remove(I);
  end;
end;

procedure TBaseParams.Remove(AIndex: Integer);
begin
  FParams.Delete(AIndex);
end;

function TBaseParams.GetCount: Integer;
begin
  Result := FParams.Count;
end;

function TBaseParams.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(Self);
end;

function TBaseParams.GetItem(AIndex: Integer): TParamEntry;
begin
  Result := FParams.Items[AIndex];
end;

function TBaseParams.ExistsParam(const AName: string): Boolean;
begin
  Result := (GetParamIndex(AName) >= 0);
end;

function TBaseParams.GetParam(const AName: string): string;
var
  I: Integer;
  P: PParamEntry;
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
  begin
    P := _ParamData(FParams);
    Inc(P, I);
    Exit(P^.Value);
  end;
  Result := '';
end;

procedure TBaseParams.SetItem(AIndex: Integer; const AValue: TParamEntry);
begin
  // 完整 record 回写由调用方维护 Value/raw 的一致性，不套用字符串 setter 的失效规则。
  FParams[AIndex] := AValue;
end;

procedure TBaseParams.SetParam(const AName, AValue: string);
var
  I: Integer;
  P: PParamEntry;
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
  begin
    P := _ParamData(FParams);
    Inc(P, I);
    // 只更新首项；先赋值以保留自赋值/共享字符串，再使该项raw来源失效。
    // 不修改Name和raw数组内容，外部记录快照仍持有原值；无需整记录复制回写。
    P^.Value := AValue;
    P^.RawValue := nil;
    P^.HasRawValue := False;
  end else
    Add(AName, AValue, True);
end;

procedure TBaseParams.Sort(const AComparison: TParamEntryComparison);
var
  LComparer: IParamEntryComparer;
begin
  if Assigned(AComparison) then
    LComparer := TParamEntryComparer.Create(AComparison)
  else
    LComparer := TParamEntryComparer.Create(
      function(const Left, Right: TParamEntry): Integer
      begin
        Result := CompareStr(Left.Name, Right.Name, TLocaleOptions.loInvariantLocale);
      end);

  FParams.Sort(LComparer);
end;

{ THttpUrlParams }

constructor THttpUrlParams.Create;
begin
  inherited Create;

  // RFC 3986 / WHATWG application/x-www-form-urlencoded:
  // key 与 value 内含的 reserved/非 unreserved 字符都必须 percent-encode,
  // 否则 key 中的 '&'/'='/'#' 等会被服务端误解析 (参数注入风险).
  // 与 Go url.Values.Encode / Python urlencode / Java URLEncoder 等主流库默认行为一致.
  FEncodeName := True;
  FEncodeValue := True;
end;

function THttpUrlParams.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
var
  p, pEnd, q: PChar;
  LName, LValue: string;
  LSize, LDecodedCount: Integer;
begin
  if AClear then
    FParams.Clear;

  LDecodedCount := 0;
  p := PChar(AEncodedParams);
  pEnd := p + Length(AEncodedParams);
  while (p < pEnd) do
  begin
    // WHATWG application/x-www-form-urlencoded parser: 按 '&' 拆分并忽略空片段.
    while (p < pEnd) and (p^ = '&') do
      Inc(p);
    if (p >= pEnd) then Break;

    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> '=') and (p^ <> '&') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetString(LName, q, LSize);
    LName := TCrossHttpUtils.UrlDecode(LName);

    if (p < pEnd) and (p^ = '=') then
    begin
      Inc(p);

      q := p;
      LSize := 0;
      while (p < pEnd) and (p^ <> '&') do
      begin
        Inc(LSize);
        Inc(p);
      end;
      SetString(LValue, q, LSize);
      LValue := TCrossHttpUtils.UrlDecode(LValue);
    end else
    begin
      LValue := '';
    end;

    Add(LName, LValue, True);
    Inc(LDecodedCount);
  end;

  Result := (LDecodedCount > 0);
end;

function THttpUrlParams.Encode: string;
var
  I: Integer;
  LName, LValue: string;
  P: PParamEntry;
begin
  Result := '';
  // 编码期间列表不变；只借用本项字段，避免Items为Name和Value各复制整条记录。
  P := _ParamData(FParams);
  for I := 0 to FParams.Count - 1 do
  begin
    if FEncodeName then
      LName := TCrossHttpUtils.UrlEncode(P^.Name)
    else
      LName := P^.Name;

    if FEncodeValue then
      LValue := TCrossHttpUtils.UrlEncode(P^.Value)
    else
      LValue := P^.Value;
    // 名称和值准备好后只追加一次，避免依次追加分隔符、名称和值而重复复制前缀。
    // 按编码后的值判断是否输出等号，保留空值、重复项和首项的原格式。
    if I = 0 then
    begin
      if LValue <> '' then Result := LName + '=' + LValue else Result := LName;
    end else
    begin
      if LValue <> '' then
        Result := Result + '&' + LName + '=' + LValue
      else
        Result := Result + '&' + LName;
    end;
    Inc(P);
  end;
end;

{ THttpHeader }

function THttpHeader.Decode(const AData: Pointer; const ASize: Integer;
  AClear: Boolean): Boolean;
begin
  Result := _Decode(AData, ASize, AClear, True);
end;

function THttpHeader.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
begin
  // PChar 指向字符串的 UTF-16 内容；False 让扫描器按 Char 而非 Byte 寻址。
  // Length 是码元数，无需乘 SizeOf(Char)；同步借用输入，解析结果另行复制。
  Result := _Decode(PChar(AEncodedParams), Length(AEncodedParams), AClear, False);
end;

type
  TControlHeaderKind = (chkText, chkAscii, chkQuotedText);

// 名称已通过 ASCII token 校验；与固定小写协议名比较，不调用区域相关的 Unicode 比较。
function _SameAsciiHeaderName(const AName, ALowerName: string): Boolean; inline;
var
  I: Integer;
begin
  if Length(AName) <> Length(ALowerName) then Exit(False);
  for I := 1 to Length(AName) do
    if (Ord(AName[I]) or $20) <> Ord(ALowerName[I]) then Exit(False);
  Result := True;
end;

// 一次分类同时决定是否需要原始控制字节校验，以及是否允许引号中的 obs-text。
// 这里只识别名称；具体数字、Base64、传输编码等语义仍由相应协议层校验。
function _GetControlHeaderKind(const AName: string): TControlHeaderKind;
begin
  Result := chkAscii;
  case Length(AName) of
    6: if _SameAsciiHeaderName(AName, 'expect') then Exit(chkQuotedText);
    7: if _SameAsciiHeaderName(AName, 'upgrade') then Exit;
    10: if _SameAsciiHeaderName(AName, 'connection') then Exit;
    14: if _SameAsciiHeaderName(AName, 'content-length') then Exit;
    15: if _SameAsciiHeaderName(AName, 'accept-encoding') then Exit;
    16: if _SameAsciiHeaderName(AName, 'content-encoding') then Exit;
    17:
      begin
        if _SameAsciiHeaderName(AName, 'transfer-encoding') then Exit(chkQuotedText);
        if _SameAsciiHeaderName(AName, 'sec-websocket-key') then Exit;
      end;
    20: if _SameAsciiHeaderName(AName, 'sec-websocket-accept') then Exit;
    21: if _SameAsciiHeaderName(AName, 'sec-websocket-version') then Exit;
    22: if _SameAsciiHeaderName(AName, 'sec-websocket-protocol') then Exit;
    24: if _SameAsciiHeaderName(AName, 'sec-websocket-extensions') then Exit;
  end;
  Result := chkText;
end;

// AData/ASize 是裁剪外侧 OWS 后的值及字节数；外层已拒绝 CR/LF/NUL/DEL 等非法字节。
// AAllowQuotedText 仅为 Expect/Transfer-Encoding 开启，允许引号参数中的 obs-text。
// 此筛查早于字符转换，不替代对应协议层的完整字段语义校验。
function _IsValidControlBytes(const AData: PByte; const ASize: Integer;
  const AAllowQuotedText: Boolean): Boolean;
var
  I: Integer;
  LQuoted, LEscaped: Boolean;
  C: Byte;
begin
  LQuoted := False;
  LEscaped := False;
  for I := 0 to ASize - 1 do
  begin
    C := AData[I];
    // Expect / Transfer-Encoding 的 quoted-string 允许 obs-text；引号和
    // 转义边界仍按字节判断。具体 token/编码语法由现有协议层继续校验。
    if (C > 127) and not LQuoted then Exit(False);
    if not AAllowQuotedText then Continue;
    // 反斜杠只在引号内转义紧随的一个字节；被转义的引号不能结束参数。
    if LEscaped then
      LEscaped := False
    else if LQuoted and (C = Ord('\')) then
      LEscaped := True
    else if C = Ord('"') then
      LQuoted := not LQuoted;
  end;
  // 未闭合引号（包括引号内悬空反斜杠）不能视为完整参数。
  Result := not LQuoted;
end;

// AStart/AEnd 是当前行起点与完整输入的右边界；AEnd 不可解引用。
// ALineEnd 返回 CR 或输入末端；AColon=nil 表示未找到冒号。这里只识别结构/字符，
// 空行、名称非空及字段构造仍由共用 Decode 处理，不在扫描器内做文本解码。
function _ScanByteHeaderLine(const AStart, AEnd: PByte;
  out ALineEnd, AColon: PByte): Boolean;
const
  // 与 IsTokenChar 在 0..255 的集合相同：字母、数字及 RFC token 标点。
  TOKEN_BYTES: set of Byte = [33, 35..39, 42..43, 45..46, 48..57,
    65..90, 94..96, 97..122, 124, 126];
  LOW_BITS: UInt64 = $7F7F7F7F7F7F7F7F;
  // 分成两个 32 位正值，避免 FPC 在 R+ 下先把高位十六进制常量折为负 Int64。
  HIGH_BITS: UInt64 = (UInt64($80808080) shl 32) or UInt64($80808080);
  SPACE_BIAS: UInt64 = $6060606060606060;
type
  // 沿用 Utils._IsUTF8 的 packed 读取模式，不要求调用方按 8 字节对齐。
  THeaderByteBlock = packed record
    Value: UInt64;
  end;
  PHeaderByteBlock = ^THeaderByteBlock;
var
  P: PByte;
  C: Byte;
  W, X: UInt64;
begin
  Result := False;
  AColon := nil;
  P := AStart;
  while P < AEnd do
  begin
    C := P^;
    if C = 13 then Break;
    if C = Ord(':') then
    begin
      AColon := P;
      Inc(P);
      Break;
    end;
    if not (C in TOKEN_BYTES) then Exit;
    Inc(P);
  end;
  if AColon <> nil then
  begin
    // 明确证明 8 字节都在输入内才读取；遇到特殊块后只走原标量余下部分。
    while AEnd - P >= SizeOf(THeaderByteBlock) do
    begin
      W := PHeaderByteBlock(P)^.Value;
      // 每字节 ((b and $7F) + $60) or b 的高位为 1，当且仅当 b >= 32。
      // 加数逐字节最大 $DF，无跨字节进位，也不可能发生 UInt64 溢出。
      if ((((W and LOW_BITS) + SPACE_BIAS) or W) and HIGH_BITS) <> HIGH_BITS then Break;
      X := W xor LOW_BITS;
      // x = b xor $7F；((x and $7F) + $7F) or x 的高位为 0，当且仅当 b = DEL。
      // 逐字节和最大 $FE，同样不依赖关闭溢出检查；两个掩码与端序无关。
      if ((((X and LOW_BITS) + LOW_BITS) or X) and HIGH_BITS) <> HIGH_BITS then Break;
      Inc(P, SizeOf(THeaderByteBlock));
    end;
    while P < AEnd do
    begin
      C := P^;
      if C = 13 then Break;
      // HTAB 仍合法，CR/CRLF 及其它 CTL 的判定保持原标量规则。
      if not TCrossHttpUtils.IsHeaderValueChar(Char(C)) then Exit;
      Inc(P);
    end;
  end;
  ALineEnd := P;
  if P < AEnd then
  begin
    // 此时 P 停在 CR；先验证下一字节存在，再读取，兼容完整布尔求值。
    Inc(P);
    if P = AEnd then Exit;
    if P^ <> 10 then Exit;
  end;
  Result := True;
end;

// 字符入口使用同样结构规则，但指针步长为 UTF-16 码元，不扩宽或重新解码文本。
function _ScanCharHeaderLine(const AStart, AEnd: PChar;
  out ALineEnd, AColon: PChar): Boolean;
var
  P: PChar;
  C: Char;
begin
  Result := False;
  AColon := nil;
  P := AStart;
  while P < AEnd do
  begin
    C := P^;
    if C = #13 then Break;
    if C = ':' then
    begin
      AColon := P;
      Inc(P);
      Break;
    end;
    if not TCrossHttpUtils.IsTokenChar(C) then Exit;
    Inc(P);
  end;
  if AColon <> nil then
    while P < AEnd do
    begin
      C := P^;
      if C = #13 then Break;
      if not TCrossHttpUtils.IsHeaderValueChar(C) then Exit;
      Inc(P);
    end;
  ALineEnd := P;
  if P < AEnd then
  begin
    Inc(P);
    if P = AEnd then Exit;
    if P^ <> #10 then Exit;
  end;
  Result := True;
end;

// 仅失败时进入，不标 inline：Delete 在 FPC 会产生托管记录临时量。
// 将该临时量限制在失败路径，正常解析不用初始化/终结整条 TParamEntry。
procedure _RollbackHeader(const AParams: TList<TParamEntry>; const ACount: Integer);
begin
  while AParams.Count > ACount do AParams.Delete(AParams.Count - 1);
end;

function THttpHeader._Decode(const AData: Pointer; const ASize: Integer;
  const AClear, ABytes: Boolean): Boolean;
var
  // 下标从 0 开始，End 均为不包含的右边界；单位随 ABytes 选择字节或 UTF-16 码元。
  I, J, LStart, LEnd, LColon, LValueStart, LValueEnd, LOldCount: Integer;
  C: Char;
  LName: string;
  LControlKind: TControlHeaderKind;
  LNamePtr: PChar;
  LItem: PParamEntry;
  LItemIndex: Integer;
  LByteLineEnd, LByteColon: PByte;
  LCharLineEnd, LCharColon: PChar;


begin
  // 参数错误不能改变已有内容；语法失败只回滚本次追加的字段。
  if (ASize < 0) or ((AData = nil) and (ASize > 0)) then
    raise EArgumentException.Create('Invalid header buffer');
  if AClear then
    {$IFDEF FPC}
    THeaderParamList(FParams).ClearHeader;
    {$ELSE}
    FParams.Clear;
    {$ENDIF}
  LOldCount := FParams.Count;
  // 完整成功前保持 False，所有提前 Exit 和转换异常都由 finally 统一回滚。
  Result := False;
  try
    I := 0;
    while I < ASize do
    begin
      LStart := I;
      LColon := -1;
      // 每行只选择一次字节/码元扫描器；名称和值各自扫描，字符循环不再反复判断模式。
      // 首个冒号确定值起点；原有 CRLF、非法字符及末行无 CRLF 的规则保持。
      if ABytes then
      begin
        if not _ScanByteHeaderLine(PByte(AData) + I, PByte(AData) + ASize,
          LByteLineEnd, LByteColon) then Exit;
        LEnd := LByteLineEnd - PByte(AData);
        if LByteColon <> nil then LColon := LByteColon - PByte(AData);
      end else
      begin
        if not _ScanCharHeaderLine(PChar(AData) + I, PChar(AData) + ASize,
          LCharLineEnd, LCharColon) then Exit;
        // 显式换回码元下标，避免把 Char 指针的地址差误用成字节长度。
        LEnd := (NativeUInt(LCharLineEnd) - NativeUInt(AData)) div SizeOf(Char);
        if LCharColon <> nil then
          LColon := (NativeUInt(LCharColon) - NativeUInt(AData)) div SizeOf(Char);
      end;
      I := LEnd;
      if I < ASize then Inc(I, 2);
      if LEnd = LStart then
      begin
        // 终止空行后不能再有字段或正文；非法尾随仍由 finally 回滚。
        if I <> ASize then Exit;
        // 成功通过循环尾正常离开 try，避免 FPC 为正常请求调用局部异常栈展开。
        Break;
      end;
      if LColon <= LStart then Exit;
      // 只裁剪值最外侧的 ASCII OWS，保留引号内、内部和 Unicode 空白。
      LValueStart := LColon + 1;
      LValueEnd := LEnd;
      // 显式先检查区间再读取，完整布尔求值下也不会触及长度以外的 OWS。
      if ABytes then
      begin
        while LValueStart < LValueEnd do
        begin
          C := Char(PByte(AData)[LValueStart]);
          if (C <> ' ') and (C <> #9) then Break;
          Inc(LValueStart);
        end;
        while LValueEnd > LValueStart do
        begin
          C := Char(PByte(AData)[LValueEnd - 1]);
          if (C <> ' ') and (C <> #9) then Break;
          Dec(LValueEnd);
        end;
      end else
      begin
        while LValueStart < LValueEnd do
        begin
          C := PChar(AData)[LValueStart];
          if (C <> ' ') and (C <> #9) then Break;
          Inc(LValueStart);
        end;
        while LValueEnd > LValueStart do
        begin
          C := PChar(AData)[LValueEnd - 1];
          if (C <> ' ') and (C <> #9) then Break;
          Dec(LValueEnd);
        end;
      end;
      // name 已通过 ASCII token 校验，直接扩宽，避免任何字符集推断。
      if ABytes then
      begin
        // SetLength 后一次取得自有可写指针，避免逐码元触发托管字符串唯一性检查。
        SetLength(LName, LColon - LStart);
        LNamePtr := PChar(LName);
        for J := LStart to LColon - 1 do
        begin
          LNamePtr^ := Char(PByte(AData)[J]);
          Inc(LNamePtr);
        end;
      end;
      if ABytes then
      begin
        // 每个重复项都校验原始区间，避免 GetString 剥 BOM 后把非法 CL/TE 或握手值
        // 变为合法文本。随后复制该区间，同时建立 Value/raw。
        LControlKind := _GetControlHeaderKind(LName);
        if (LControlKind <> chkText) and not _IsValidControlBytes(
          PByte(AData) + LValueStart, LValueEnd - LValueStart,
          LControlKind = chkQuotedText) then Exit;
        // Add 可能扩容，必须之后重新取得槽位；失败时零记录由外层 finally 一并回滚。
        LItemIndex := FParams.Count;
        // 已有容量中的空槽由 RTL 保证为零；满容量仍用 Add，保持原先的扩容方式。
        if LItemIndex < _ParamCapacity(FParams) then
          FParams.Count := LItemIndex + 1
        else
          LItemIndex := FParams.Add(Default(TParamEntry));
        LItem := _ParamData(FParams);
        Inc(LItem, LItemIndex);
        // 新槽位由外层 finally 负责失败回滚；直接建立自有 raw，省去临时数组的引用搬运。
        // 公开构造器仍使用强提交 helper，此处转换抛错时会删除本次新增的部分记录。
        SetLength(LItem^.RawValue, LValueEnd - LValueStart);
        if LValueEnd > LValueStart then
          Move(PByte(AData)[LValueStart], LItem^.RawValue[0], LValueEnd - LValueStart);
        LItem^.Value := TUtils.GetString(PByte(LItem^.RawValue), LValueEnd - LValueStart);
        LItem^.Name := LName;
        LItem^.HasRawValue := True;
      end
      else
      begin
        LItemIndex := FParams.Count;
        // 已有容量中的空槽由 RTL 保证为零；满容量仍用 Add，保持原先的扩容方式。
        if LItemIndex < _ParamCapacity(FParams) then
          FParams.Count := LItemIndex + 1
        else
          LItemIndex := FParams.Add(Default(TParamEntry));
        LItem := _ParamData(FParams);
        Inc(LItem, LItemIndex);
        // PChar 加法及长度均按 UTF-16 码元计；直接复制到最终槽，避免 Name/Value 中转。
        // 新槽保证全零，文本入口不制造 raw 来源；任一步复制抛错仍由 finally 回滚整槽。
        SetString(LItem^.Name, PChar(AData) + LStart, LColon - LStart);
        SetString(LItem^.Value, PChar(AData) + LValueStart, LValueEnd - LValueStart);
      end;
    end;
    Result := True;
  finally
    // 删除本次追加的整条记录，文本与 raw 一起释放；旧项及共享数组不被原地改写。
    if not Result then
      _RollbackHeader(FParams, LOldCount);
  end;
end;

// AValue 是当前字段值；只借用显式长度范围，不寻找结束零字符。
// AValidUtf16 累计整块字段的代理合法性，只会由 True 变 False。非法 HTTP 字符立即
// 抛错；坏代理延迟至 Encode 完成所有字段检查后报告，保持原先字段错误优先的顺序。
procedure _CheckHeaderValue(const AValue: string; var AValidUtf16: Boolean);
var
  P, LEnd: PChar;
  C: Word;
begin
  P := PChar(AValue);
  LEnd := P + Length(AValue);
  while P < LEnd do
  begin
    C := Ord(P^);
    Inc(P);
    if ((C < 32) and (C <> 9)) or (C = 127) then
      raise EConvertError.Create('Invalid HTTP header field');
    if (C and $F800) <> $D800 then Continue;
    if C <= $DBFF then
    begin
      // 先验证余量再读下一码元，完整布尔求值及恰好结尾的高代理也不会越界。
      if P < LEnd then
        if (Ord(P^) and $FC00) = $DC00 then
        begin
          Inc(P);
          Continue;
        end;
    end;
    // 非低代理的下一码元尚未消费，下轮仍会检查它是否是非法 CTL/DEL。
    AValidUtf16 := False;
  end;
end;

function THttpHeader.Encode: string;
const
  {$IF DEFINED(DELPHI) AND DEFINED(CPU64)}
  // Delphi 的 UnicodeString SetLength 在64位下仍以 Integer 接收字符数。
  MAX_HEADER_LENGTH = High(Integer);
  {$ELSE}
  // 保证码元数转换为 Move 的字节数时不发生 NativeInt 溢出。
  MAX_HEADER_LENGTH = High(NativeInt) div SizeOf(Char);
  {$ENDIF}
var
  I, LLength, LNameLength, LValueLength: NativeInt;
  LValidUtf16: Boolean;
  P: PParamEntry;
  LDest: PChar;
begin
  // 保留原入口的清空语义，不借用调用方隐藏结果槽中的旧输出缓冲。
  Result := '';
  // 空集合只有结束空行，保持原来的常量字符串结果，无需分配可写缓冲区。
  if FParams.Count = 0 then Exit(#13#10);
  LLength := 2;
  LValidUtf16 := True;
  P := _ParamData(FParams);
  for I := 0 to FParams.Count - 1 do
  begin
    // 保持逐项 Name→Value 的检查顺序，坏代理延迟到所有字段合法性检查之后报告。
    if not TCrossHttpUtils.IsValidHeaderName(P^.Name) then
      raise EConvertError.Create('Invalid HTTP header field');
    _CheckHeaderValue(P^.Value, LValidUtf16);
    LNameLength := Length(P^.Name);
    LValueLength := Length(P^.Value);
    // 每行另需 ": " 和 CRLF 共4个码元；先减法判界，再累加，兼容溢出检查开启。
    if (LLength > MAX_HEADER_LENGTH - 4)
      or (LNameLength > MAX_HEADER_LENGTH - LLength - 4) then
      raise EOutOfMemory.Create('HTTP header is too large');
    Inc(LLength, LNameLength + 4);
    if LValueLength > MAX_HEADER_LENGTH - LLength then
      raise EOutOfMemory.Create('HTTP header is too large');
    Inc(LLength, LValueLength);
    Inc(P);
  end;
  if not LValidUtf16 then
    raise EConvertError.Create('Invalid UTF-16 in HTTP header');

  // 一次申请最终长度。下面只复制已校验的字段，不再逐行扩容或重复复制前缀。
  // SetLength先成功再取得写指针；没有集合突变/回调，且输出不与任何字段字符串共享。
  SetLength(Result, LLength);
  LDest := PChar(Result);
  P := _ParamData(FParams);
  for I := 0 to FParams.Count - 1 do
  begin
    LNameLength := Length(P^.Name);
    LValueLength := Length(P^.Value);
    Move(PChar(P^.Name)^, LDest^, LNameLength * SizeOf(Char));
    Inc(LDest, LNameLength);
    LDest^ := ':'; Inc(LDest);
    LDest^ := ' '; Inc(LDest);
    // 空值不读取源指针；发送始终使用当前 Value，原始字节仅供查看。
    if LValueLength > 0 then
    begin
      Move(PChar(P^.Value)^, LDest^, LValueLength * SizeOf(Char));
      Inc(LDest, LValueLength);
    end;
    LDest^ := #13; Inc(LDest);
    LDest^ := #10; Inc(LDest);
    Inc(P);
  end;
  LDest^ := #13; Inc(LDest);
  LDest^ := #10;
end;

{ TDelimitParams }

constructor TDelimitParams.Create(const ADelimiter: Char; const AUrlEncode: Boolean);
begin
  FDelimiter := ADelimiter;
  FUrlEncode := AUrlEncode;

  inherited Create;
end;

constructor TDelimitParams.Create(const AEncodedParams: string;
  const ADelimiter: Char; const AUrlEncode: Boolean);
begin
  FDelimiter := ADelimiter;
  FUrlEncode := AUrlEncode;

  inherited Create(AEncodedParams);
end;

function TDelimitParams.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
var
  p, pEnd, q: PChar;
  LName, LValue: string;
  LSize, LDecodedCount: Integer;
begin
  if AClear then
    FParams.Clear;

  LDecodedCount := 0;
  p := PChar(AEncodedParams);
  pEnd := p + Length(AEncodedParams);
  while (p < pEnd) do
  begin
    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> '=') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetString(LName, q, LSize);
    // 跳过多余的'='
    while (p < pEnd) and (p^ = '=') do
      Inc(p);

    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> FDelimiter) do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetString(LValue, q, LSize);
    if FUrlEncode then
      LValue := TCrossHttpUtils.UrlDecode(LValue);
    // 跳过多余的';'
    while (p < pEnd) and ((p^ = FDelimiter) or (p^ = ' ')) do
      Inc(p);

    Add(LName, LValue);
    Inc(LDecodedCount);
  end;

  Result := (LDecodedCount > 0);
end;

function TDelimitParams.Encode: string;
var
  I: Integer;
  LValue: string;
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    if (I > 0) then
      Result := Result + FDelimiter + ' ';
    LValue := FParams[I].Value;
    if FUrlEncode then
      LValue := TCrossHttpUtils.UrlEncode(LValue);
    Result := Result + FParams[I].Name + '=' + LValue;
  end;
end;

{ TRequestCookies }

function TRequestCookies.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
var
  LParsedParams: TList<TParamEntry>;
  LItem: TParamEntry;
  LPos, LLen, LPairEnd, LEqualsPos, LDecodedCount: Integer;
  LPair: string;
  LName, LValue: string;
  LNormalizedValue: string;
begin
  LDecodedCount := 0;
  Result := False;
  // 先解析到临时列表，确保整行 Cookie 全部合法后再提交，避免失败时留下半解析数据。
  LParsedParams := TList<TParamEntry>.Create;
  try
    LLen := Length(AEncodedParams);
    LPos := 1;
    while (LPos <= LLen) do
    begin
      // 跳过空白字符(空格和制表符)
      while (LPos <= LLen) and CharInSet(AEncodedParams[LPos], [' ', #9]) do
        Inc(LPos);
      if (LPos > LLen) then Break;

      LPairEnd := LPos;
      // 查找分号分隔符, 确定当前 cookie-pair 的结束位置
      while (LPairEnd <= LLen) and (AEncodedParams[LPairEnd] <> ';') do
        Inc(LPairEnd);

      // 提取当前 cookie-pair 字符串
      LPair := Copy(AEncodedParams, LPos, LPairEnd - LPos);
      // 查找等号位置, 用于分割 name 和 value
      LEqualsPos := Pos('=', LPair);
      // 如果没有等号或等号在第一个位置(name 为空), 则认为格式非法
      if (LEqualsPos <= 1) then
      begin
        if AClear then FParams.Clear;
        Exit;
      end;

      // 提取 name 部分（等号之前的内容）
      LName := Copy(LPair, 1, LEqualsPos - 1);
      // 提取 value 部分（等号之后的所有内容）
      LValue := Copy(LPair, LEqualsPos + 1, MaxInt);
      // 请求 Cookie 接收端保持宽松：部分浏览器或第三方系统会发送包含
      // 逗号等非标准字符的值，不应因此拒绝整个 HTTP 请求。
      if not _IsHttpToken(LName)
        or not _TryNormalizeCookieValue(LValue, LNormalizedValue, False) then
      begin
        if AClear then FParams.Clear;
        Exit;
      end;

      LParsedParams.Add(TParamEntry.Create(LName, LNormalizedValue));
      LPos := LPairEnd + 1;
      Inc(LDecodedCount);
    end;

    // 所有 cookie-pair 均校验通过后，才按 AClear 语义提交到 FParams。
    if AClear then
      FParams.Clear;
    for LItem in LParsedParams do
      Add(LItem.Name, LItem.Value);
    Result := (LDecodedCount > 0);
  finally
    FreeAndNil(LParsedParams);
  end;
end;

function TRequestCookies.Encode: string;
var
  I: Integer;
  LName, LValue: string;
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    LName := FParams[I].Name;
    LValue := FParams[I].Value;
    if not _IsHttpToken(LName) then
      raise Exception.CreateFmt('Invalid cookie name: %s', [LName]);
    if not _IsCookieOctets(LValue) then
      raise Exception.CreateFmt('Invalid cookie value: %s', [LName]);
    // 校验通过后一次追加完整项，避免先追加分隔符而重复扩容或复制前缀。
    // 空值仍输出等号；按索引区分首项，保持顺序和重复名称。
    if I = 0 then
      Result := LName + '=' + LValue
    else
      Result := Result + '; ' + LName + '=' + LValue;
  end;
end;

{ TResponseCookie }

constructor TResponseCookie.Create(const AName, AValue: string;
  AMaxAge: Integer; const APath, ADomain: string; AHttpOnly, ASecure: Boolean);
begin
  Self.Name := AName;
  Self.Value := AValue;
  Self.MaxAge := AMaxAge;
  Self.Path := APath;
  Self.Domain := _NormalizeCookieDomain(ADomain);
  Self.HttpOnly := AHttpOnly;
  Self.Secure := ASecure;
end;

constructor TResponseCookie.Create(const ACookieData, ADomain: string);

  procedure SetExpires(const AValue: string);
  var
    LMaxAge: Integer;
  begin
    if (Self.MaxAge = 0) then
    begin
      LMaxAge := TCrossHttpUtils.RFC1123_StrToDate(AValue).SecondsDiffer(Now);
      if (LMaxAge > 0) then
        Self.MaxAge := LMaxAge;
    end;
  end;

  procedure SetMaxAge(const AValue: string);
  var
    LMaxAge: Integer;
  begin
    if _TryParseCookieMaxAge(AValue, LMaxAge) then
      Self.MaxAge := LMaxAge;
  end;

  procedure SetPath(const AValue: string);
  begin
    if (AValue <> '') and (AValue[1] = '/') and _IsCookieAvValue(AValue) then
      Self.Path := AValue;
  end;

  procedure SetDomain(const AValue: string);
  var
    LDomain: string;
  begin
    LDomain := _NormalizeCookieDomain(AValue);
    if (LDomain <> '') then
      Self.Domain := LDomain;
  end;

var
  LValues: TArray<string>;
  I: Integer;
  LPos: Integer;
  LName: string;
  LValue: string;
begin
  Self.Name := '';
  Self.Value := '';
  Self.MaxAge := 0;
  Self.Path := '/';
  Self.Domain := _NormalizeCookieDomain(ADomain);
  Self.HttpOnly := False;
  Self.Secure := False;

  LValues := ACookieData.Split([Char(';')], Char('"'));
  if Length(LValues) = 0 then Exit;

  LPos := LValues[0].IndexOf(Char('='));
  if (LPos <= 0) then Exit;

  Self.Name := LValues[0].Substring(0, LPos).Trim;
  if not _IsHttpToken(Self.Name)
    or not _TryNormalizeCookieValue(LValues[0].Substring(LPos + 1).Trim,
      Self.Value, True) then
  begin
    Self.Name := '';
    Self.Value := '';
    Exit;
  end;

  for I := 1 to High(LValues) do
  begin
    LPos := LValues[I].IndexOf(Char('='));
    if LPos > 0 then
    begin
      LName := LValues[I].Substring(0, LPos).Trim;
      LValue := LValues[I].Substring(LPos + 1).Trim;
      if (LValue.Length > 1) and (LValue.Chars[0] = '"') and (LValue[High(LValue)] = '"') then
        LValue := LValue.Substring(1, LValue.Length - 2);
    end
    else
    begin
      LName := LValues[I].Trim;
      LValue := '';
    end;

    if TStrUtils.SameText(LName, 'Max-Age') then
      SetMaxAge(LValue)
    else if TStrUtils.SameText(LName, 'Expires') then
      SetExpires(LValue)
    else if TStrUtils.SameText(LName, 'Path') then
      SetPath(LValue)
    else if TStrUtils.SameText(LName, 'Domain') then
      SetDomain(LValue)
    else if TStrUtils.SameText(LName, 'HttpOnly') then
      Self.HttpOnly := True
    else if TStrUtils.SameText(LName, 'Secure') then
      Self.Secure := True;
  end;
end;

function TResponseCookie.Encode: string;
begin
  if not _IsHttpToken(Self.Name) then
    raise Exception.CreateFmt('Invalid cookie name: %s', [Self.Name]);
  if not _IsCookieOctets(Self.Value) then
    raise Exception.CreateFmt('Invalid cookie value: %s', [Self.Value]);
  if not _IsCookieAvValue(Self.Path) then
    raise Exception.CreateFmt('Invalid cookie path: %s', [Self.Name]);
  if (Self.Path <> '') and (Self.Path[1] <> '/') then
    raise Exception.CreateFmt('Invalid cookie path: %s', [Self.Name]);
  if not _IsCookieAvValue(Self.Domain) then
    raise Exception.CreateFmt('Invalid cookie domain: %s', [Self.Name]);

  Result := Self.Name + '=' + Self.Value;

  if (Self.MaxAge > 0) then
    Result := Result + '; Max-Age=' + Self.MaxAge.ToString;
  if (Self.Path <> '') then
    Result := Result + '; Path=' + Self.Path;
  if (Self.Domain <> '') then
    Result := Result + '; Domain=' + Self.Domain;
  if Self.HttpOnly then
    Result := Result + '; HttpOnly';
  if Self.Secure then
    Result := Result + '; Secure';
end;

{ TFormField }

constructor TFormField.Create;
begin
  FValueOwned := True;
end;

destructor TFormField.Destroy;
begin
  FreeValue;

  inherited;
end;

procedure TFormField.FreeValue;
begin
  // 借用流在发送结束后可能已由调用方释放，清理字段不能再检查其VMT或路径。
  if not FValueOwned then Exit;
  // 释放前记录已经存在的真实路径，不能在析构时强制把内存内容落盘。
  if FValue is TFormFileStream then
    FFilePath := TFormFileStream(FValue).FilePath;
  if Assigned(FValue) then
    FreeAndNil(FValue);
end;

function TFormField.GetFilePath: string;
begin
  if FValue is TFormFileStream then
    Result := TFormFileStream(FValue).FilePath
  else
    Result := FFilePath;
end;

function TFormField.GetIsFile: Boolean;
begin
  // 保持旧发送端无路径流的分类；新增内存文件只来自接收端临时文件分支。
  Result := FIsTempFile or (FFilePath <> '');
end;

function TFormField.EnsureFilePath: string;
begin
  if FValue is TFormFileStream then
    FFilePath := TFormFileStream(FValue).EnsureFilePath
  else
  if FValue is TFastFileStream then
    TFastFileStream(FValue).FlushBuffer;
  Result := FFilePath;
end;

function TFormField.AsBytes: TBytes;
var
  LBufSize: Integer;
begin
  if (FValue = nil) or (FValue.Size <= 0) then Exit(nil);

  if (FValue is TBytesStream) then
  begin
    Result := TBytesStream(FValue).Bytes;
    SetLength(Result, FValue.Size);
  end else
  begin
    FValue.Position := 0;
    LBufSize := FValue.Size;
    SetLength(Result, LBufSize);
    FValue.ReadBuffer(Result, LBufSize);
  end;
end;

procedure TFormField.Assign(const ASource: TFormField);
var
  LSourcePath: string;
begin
  if ASource = Self then Exit;
  // 文件字段复制沿用按路径重新打开的语义；延迟文件必须先显式物化，
  // 不能复制尚未创建的预定路径。物化失败时保留目标原内容。
  LSourcePath := '';
  if ASource <> nil then
    LSourcePath := ASource.EnsureFilePath;
  FreeValue;

  if (ASource = nil) then Exit;

  FName := ASource.FName;
  FValueOwned := ASource.FValueOwned;
  FIsTempFile := ASource.FIsTempFile;
  FFileName := ASource.FFileName;
  FFilePath := LSourcePath;
  FContentType := ASource.FContentType;
  FContentTransferEncoding := ASource.FContentTransferEncoding;

  if ASource.FValueOwned then
  begin
    if (FFilePath <> '') then
      FValue := TFileUtils.OpenRead(FFilePath, fmShareDenyNone)
    else
    begin
      FValue := TBytesStream.Create;
      FValue.CopyFrom(ASource.FValue, 0);
    end;
  end else
  begin
    FValue := ASource.FValue;
  end;
end;

function TFormField.AsString(AEncoding: TEncoding): string;
begin
  Result := TUtils.GetString(FValue, AEncoding);
end;

{ THttpMultiPartFormData.TEnumerator }

constructor THttpMultiPartFormData.TEnumerator.Create(
  const AList: TList<TFormField>);
begin
  inherited Create;
  FList := AList;
  FIndex := -1;
end;

function THttpMultiPartFormData.TEnumerator.GetCurrent: TFormField;
begin
  Result := FList[FIndex];
end;

function THttpMultiPartFormData.TEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := (FIndex < FList.Count);
end;

{ THttpMultiPartFormData }

constructor THttpMultiPartFormData.Create;
begin
  FDecodeState := dsBoundary;
  SetLength(FCurrentPartHeader, MAX_PART_HEADER);
  FCurrentPartHeaderLen := 0;
  FPartFields := TObjectList<TFormField>.Create(True);
  FAutoDeleteFiles := True;
  FMaxPartDataSize := 0;
  FCurrentPartDataSize := 0;
end;

function THttpMultiPartFormData.CreateFileStream(const AField: TFormField): TStream;
begin
  Result := TFileUtils.OpenCreate(AField.FilePath);
end;

function THttpMultiPartFormData.Decode(
  const AStream: TStream): TFormDataDecodeResult;
const
  BUF_SIZE = 1024 * 32;
var
  LBuffer: array [0..BUF_SIZE - 1] of Byte;
  N: Integer;
begin
  while True do
  begin
    N := AStream.Read(LBuffer[0], BUF_SIZE);
    Result := Decode(@LBuffer[0], N);

    if (Result in [frComplete, frFailed])
      or (N < BUF_SIZE) then Exit;
  end;
end;

destructor THttpMultiPartFormData.Destroy;
begin
  try
    Clear;
  finally
    FCurrentPartHeader := nil;
    FCurrentPartField := nil;
    try
      FreeAndNil(FPartFields);
    finally
      inherited;
    end;
  end;
end;

function THttpMultiPartFormData.AddField(const AField: TFormField): TFormField;
begin
  FPartFields.Add(AField);
  Result := AField;
end;

function THttpMultiPartFormData.AddField(const AFieldName: string;
  const AValue: TBytes): TFormField;
begin
  Result := TFormField.Create;
  Result.FName := AFieldName;
  Result.FValueOwned := True;
  Result.FValue := TBytesStream.Create(AValue);
  Result.FContentType := TMediaType.APPLICATION_OCTET_STREAM;

  FPartFields.Add(Result);
end;

function THttpMultiPartFormData.AddField(const AFieldName, AValue: string): TFormField;
begin
  Result := TFormField.Create;
  Result.FName := AFieldName;
  Result.FValueOwned := True;
  Result.FValue := TBytesStream.Create(TEncoding.UTF8.GetBytes(AValue));

  FPartFields.Add(Result);
end;

function THttpMultiPartFormData.AddFile(const AFieldName, AFileName: string;
  const AStream: TStream; const AOwned: Boolean): TFormField;
begin
  Result := TFormField.Create;
  Result.FName := AFieldName;
  Result.FFileName := AFileName;
  Result.FValueOwned := AOwned;
  Result.FValue := AStream;
  Result.FContentType := TCrossHttpUtils.GetFileMIMEType(AFileName);

  FPartFields.Add(Result);
end;

function THttpMultiPartFormData.AddFile(const AFieldName, AFileName: string): TFormField;
begin
  Result := AddFile(AFieldName,
    ExtractFileName(AFileName),
    TFileUtils.OpenRead(AFileName, fmShareDenyNone),
    True);
  Result.FFilePath := AFileName;
end;

procedure THttpMultiPartFormData.Assign(const ASource: THttpMultiPartFormData);
var
  LSrcField, LNewField: TFormField;
begin
  Clear;

  Boundary := ASource.Boundary;

  for LSrcField in ASource do
  begin
    LNewField := TFormField.Create;
    LNewField.Assign(LSrcField);

    AddField(LNewField);
  end;
end;

function THttpMultiPartFormData.AsBytes(const AFieldName: string;
  out AValue: TBytes): Boolean;
var
  LField: TFormField;
begin
  Result := FindField(AFieldName, LField);
  if Result then
    AValue := LField.AsBytes
  else
    AValue := nil;
end;

function THttpMultiPartFormData.AsBytes(const AFieldName: string): TBytes;
begin
  AsBytes(AFieldName, Result);
end;

function THttpMultiPartFormData.AsStream(const AFieldName: string;
  out AValue: TStream): Boolean;
var
  LField: TFormField;
begin
  Result := FindField(AFieldName, LField);
  if Result then
  begin
    AValue := LField.Value;
    if (AValue.Size > 0) then
    AValue.Position := 0;
  end else
    AValue := nil;
end;

function THttpMultiPartFormData.AsStream(const AFieldName: string): TStream;
begin
  AsStream(AFieldName, Result);
end;

function THttpMultiPartFormData.AsString(const AFieldName: string;
  const AEncoding: TEncoding; out AValue: string): Boolean;
var
  LField: TFormField;
begin
  Result := FindField(AFieldName, LField);
  if Result then
    AValue := LField.AsString(AEncoding)
  else
    AValue := '';
end;

function THttpMultiPartFormData.AsString(const AFieldName: string;
  out AValue: string): Boolean;
begin
  Result := AsString(AFieldName, nil, AValue);
end;

function THttpMultiPartFormData.AsString(const AFieldName: string;
  const AEncoding: TEncoding): string;
begin
  AsString(AFieldName, AEncoding, Result);
end;

function THttpMultiPartFormData.AddDecodedField(const AName, AFileName,
  AContentType, AContentTransferEncoding: string; const AValue: TStream;
  const AIsFile: Boolean): TFormField;
begin
  Result := TFormField.Create;
  try
    Result.FValueOwned := False;
    Result.FName := AName;
    Result.FFileName := AFileName;
    Result.FContentType := AContentType;
    Result.FContentTransferEncoding := AContentTransferEncoding;
    Result.FValue := AValue;
    Result.FIsTempFile := AIsFile;
    FPartFields.Add(Result);
    Result.FValueOwned := True;
  except
    Result.Free;
    raise;
  end;
end;

procedure THttpMultiPartFormData.Clear;
var
  LField: TFormField;
  LFilePath: string;
  LFirstException: TObject;

  procedure SaveFirstException;
  begin
    if LFirstException = nil then
      LFirstException := TObject(AcquireExceptionObject);
  end;

begin
  if FPartFields = nil then Exit;
  LFirstException := nil;
  FCurrentPartField := nil;
  // 一次反转后从末尾提取，保持原字段清理顺序，避免反复移动剩余元素。
  FPartFields.Reverse;
  while FPartFields.Count > 0 do
  begin
    {$IFDEF FPC}
    LField := FPartFields.ExtractIndex(FPartFields.Count - 1);
    {$ELSE}
    LField := FPartFields.ExtractAt(FPartFields.Count - 1);
    {$ENDIF}
    if LField = nil then Continue;
    LFilePath := '';
    try
      if FAutoDeleteFiles and LField.FIsTempFile then
        LFilePath := LField.FilePath;
    except
      SaveFirstException;
    end;
    // 先脱离拥有列表。关闭流失败也不能使该字段留在列表中被再次释放。
    try
      LField.Free;
    except
      SaveFirstException;
    end;
    try
      // 保持原有的尽力删除语义，例如其它合法读句柄可能暂时阻止 Windows 删除。
      if (LFilePath <> '') and FileExists(LFilePath) then
        DeleteFile(LFilePath);
    except
      SaveFirstException;
    end;
  end;
  if LFirstException <> nil then
    raise LFirstException;
end;

function THttpMultiPartFormData.FindField(const AFieldName: string;
  out AField: TFormField): Boolean;
var
  I: Integer;
begin
  I := GetItemIndex(AFieldName);
  if (I >= 0) then
  begin
    AField := FPartFields[I];
    Exit(True);
  end;

  AField := nil;
  Result := False;
end;

function THttpMultiPartFormData.GetItem(AIndex: Integer): TFormField;
begin
  Result := FPartFields.Items[AIndex];
end;

function THttpMultiPartFormData.GetItemIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FPartFields.Count - 1 do
    if TStrUtils.SameText(FPartFields[I].Name, AName) then Exit(I);
  Result := -1;
end;

function THttpMultiPartFormData.GetCount: Integer;
begin
  Result := FPartFields.Count;
end;

function THttpMultiPartFormData.GetDataSize: Integer;
var
  LPartField: TFormField;
begin
  Result := 0;
  for LPartField in FPartFields do
    Inc(Result, LPartField.FValue.Size);
end;

function THttpMultiPartFormData.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(FPartFields);
end;

function THttpMultiPartFormData.GetField(const AName: string): TFormField;
var
  I: Integer;
begin
  I := GetItemIndex(AName);
  if (I >= 0) then
    Exit(FPartFields[I]);
  Result := nil;
end;

function THttpMultiPartFormData.EndsAtClosingBoundary: Boolean;
begin
  Result := (FDecodeState = dsDetect) and (FPostBoundaryState = pbsEnd2);
end;

procedure THttpMultiPartFormData.InitWithBoundary(const ABoundary: string);
begin
  // Decode 返回 frFailed 后, 调用方应调用 InitWithBoundary 重用实例;
  // Clear 会根据 AutoDeleteFiles 清理半解析的临时文件.
  Clear;

  SetBoundary(ABoundary);

  FDecodeState := dsBoundary;
  FBoundaryIndex := 0;
  FPrevBoundaryIndex := 0;
  FCurrentPartDataSize := 0;
  FCurrentPartHeaderLen := 0;
  FCurrentPartField := nil;
  SetLength(FLookbehind, Length(FBoundaryBytes) + 8);
end;

procedure THttpMultiPartFormData.Remove(AIndex: Integer);
begin
  FPartFields.Delete(AIndex);
end;

procedure THttpMultiPartFormData.Remove(const AFieldName: string);
var
  I: Integer;
begin
  I := GetItemIndex(AFieldName);
  if (I >= 0) then
    FPartFields.Delete(I);
end;

procedure THttpMultiPartFormData.SetBoundary(const AValue: string);
begin
  if (FBoundary <> AValue) then
  begin
    FBoundary := AValue;
    FBoundary := FBoundary.Trim(['"']);

    // 第一块数据是紧跟着 HTTP HEADER 的, 前面没有多余的 #13#10
    FFirstBoundaryBytes := TEncoding.ASCII.GetBytes('--' + FBoundary);

    // 第二块及以后的数据 Boundary 前面都会有 #13#10
    FBoundaryBytes := TArrayUtils<Byte>.Concat([13, 10], FFirstBoundaryBytes);
  end;
end;

function THttpMultiPartFormData.Decode(const ABuf: Pointer; ALen: Integer; out AConsumed: Integer): TFormDataDecodeResult;
  function __NewFileID: string;
  begin
    Result := TUtils.GetGUID.ToLower;
  end;

  // AHeader 是已收齐的 part 头（含结束空行），AHeaderSize 为字节数，不含 boundary/正文。
  // AFormField 尚由调用者持有；False 时调用者释放它，不把不完整字段加入表单。
  function __InitFormFieldByHeader(AFormField: TFormField;
    const AHeader: Pointer; const AHeaderSize: Integer): Boolean;
  var
    LFieldHeader: THttpHeader;
    LContentDisposition: string;
    LRegEx: IRegEx;
  begin
    Result := False;

    LFieldHeader := THttpHeader.Create;
    try
      // 在原始字节上识别字段边界，再让各值独立转换；不能先解码整个 part 头。
      if not LFieldHeader.Decode(AHeader, AHeaderSize) then Exit;
      LContentDisposition := LFieldHeader['Content-Disposition'];
      if (LContentDisposition = '') then Exit;

      AFormField.FContentType := LFieldHeader['Content-Type'];

      // 这里只读取第一个捕获值，无需为所有组构造TMatch包装；匹配规则和起点保持。
      LRegEx := TRegEx.Create('\bname="(.*?)"(?=;|$)');
      LRegEx.Subject := LContentDisposition;
      LRegEx.StartPos := 1;
      LRegEx.Options := [TRegExOption.roIgnoreCase];
      if LRegEx.Match then
        AFormField.FName := LRegEx.Groups[1];

      // 使用 Content-Type 来判断是否需要按文件保存更为准确
      // 前端通过流的方式提交, 可能不会传递 filename 属性,
      // 这种情况收到的 AHeader 是这样的:
      //   Content-Disposition: form-data; name="test_content"
      //   Content-Type: application/octet-stream
      // 这种数据也可以当成文件来储存, 随机给它分配一个文件名即可
      // 而普通的文本数据是不会有 Content-Type 的：
      //   Content-Disposition: form-data; name="test_text"
      if (AFormField.FContentType <> '') then
      begin
        // filename仍独立查找，不合并两条正则，以免改变重复属性/异常引号的既有结果。
        LRegEx := TRegEx.Create('\bfilename="(.*?)"(?=;|$)');
        LRegEx.Subject := LContentDisposition;
        LRegEx.StartPos := 1;
        LRegEx.Options := [TRegExOption.roIgnoreCase];
        // 带 filename 属性的头:
        //   Content-Disposition: form-data; name="content"; filename="test.json"
        //   Content-Type: application/json
        if LRegEx.Match then
        begin
          AFormField.FFileName := TPathUtils.GetFileName(LRegEx.Groups[1]);
          AFormField.FFilePath := TPathUtils.Combine(FStoragePath,
            __NewFileID + TPathUtils.GetExtension(AFormField.FFileName));
        end else
        begin
          AFormField.FFileName := __NewFileID + '.bin';
          AFormField.FFilePath := TPathUtils.Combine(FStoragePath,
            AFormField.FFileName);
        end;

        AFormField.FIsTempFile := True;
        AFormField.FValue := CreateFileStream(AFormField);
        if AFormField.FValue = nil then
          raise EStreamError.Create('文件字段未创建存储流');
      end else
        AFormField.FValue := TBytesStream.Create(nil);

      AFormField.FValueOwned := True;
      // 注意: Content-Transfer-Encoding (base64/quoted-printable) 仅存储不解码,
      // dsPartData 阶段总是按原始字节写入, 如需支持非二进制传输编码需在此增加解码层.
      AFormField.FContentTransferEncoding := LFieldHeader['Content-Transfer-Encoding'];
    finally
      FreeAndNil(LFieldHeader);
    end;

    Result := True;
  end;
var
  C: Byte;
  I, LSize: Integer;
  P: PByte;
  LNewField: TFormField;
  LFailedFilePath: string;
begin
  AConsumed := 0;
  if (FBoundaryBytes = nil) then Exit(frFailed);

  (*
   ***************************************
   ***** multipart/form-data数据格式 *****
   ***************************************

  # 请求头, 这个是必须的, 需要指定Content-Type为multipart/form-data, 指定唯一边界值
  Content-Type: multipart/form-data; boundary=${Boundary}

  # 请求体
  --${Boundary}
  Content-Disposition: form-data; name="name of file"
  Content-Type: application/octet-stream

  bytes of file
  --${Boundary}
  Content-Disposition: form-data; name="name of pdf"; filename="pdf-file.pdf"
  Content-Type: application/octet-stream

  bytes of pdf file
  --${Boundary}
  Content-Disposition: form-data; name="key"
  Content-Type: text/plain;charset=UTF-8

  text encoded in UTF-8
  --${Boundary}--
  *)

  P := ABuf;
  I := 0;
  while (I < ALen) do
  begin
    C := P[I];
    case FDecodeState of
      // 检测Boundary, 以确定第一块数据
      dsBoundary:
        begin
          // 第一块数据是紧跟着 HTTP HEADER 的, 前面没有多余的 #13#10
          // 所以这里检测时要跳过 2 个字节
          if (C = FFirstBoundaryBytes[FBoundaryIndex]) then
            Inc(FBoundaryIndex)
          else
            FBoundaryIndex := 0;
          // --Boundary
          if (FBoundaryIndex >= Length(FFirstBoundaryBytes)) then
          begin
            FDecodeState := dsDetect;
            FLineEndState := lesCR1;
            FBoundaryIndex := 0;
            FPostBoundaryState := pbsDetect;
          end;
        end;

      // 已通过Boundary检测, 继续检测以确定后面有数据还是已到结束
      dsDetect:
        begin
          // 严格匹配 #13#10 (Header) 或 --#13#10 (End), 拒绝其他任何字节
          case FPostBoundaryState of
            pbsDetect:
              if (C = 45) then          // '-'
                FPostBoundaryState := pbsEnd1
              else if (C = 13) then     // '\r'
                FPostBoundaryState := pbsHeader1
              else if (C = 32) or (C = 9) then  // RFC 2046 LWSP
                { stay in pbsDetect }
              else
              begin
                AConsumed := I + 1;
                Exit(frFailed);
              end;
            pbsEnd1:
              if (C = 45) then          // '-'
                FPostBoundaryState := pbsEnd2
              else
              begin
                AConsumed := I + 1;
                Exit(frFailed);
              end;
            pbsEnd2:
              if (C = 13) then          // '\r'
                FPostBoundaryState := pbsEnd3
              else if (C = 32) or (C = 9) then
                { 结束分隔行允许尾随 SP/HTAB }
              else
              begin
                AConsumed := I + 1;
                Exit(frFailed);
              end;
            pbsEnd3:
              if (C = 10) then          // '\n' → --Boundary--#13#10
              begin
                FDecodeState := dsBoundary;
                FLineEndState := lesCR1;
                FBoundaryIndex := 0;
                FPostBoundaryState := pbsDetect;
                AConsumed := I + 1;
                Exit(frComplete);
              end else
              begin
                AConsumed := I + 1;
                Exit(frFailed);
              end;
            pbsHeader1:
              if (C = 10) then          // '\n' → --Boundary#13#10
              begin
                FCurrentPartHeaderLen := 0;
                FDecodeState := dsPartHeader;
                FLineEndState := lesCR1;
                FBoundaryIndex := 0;
                FPostBoundaryState := pbsDetect;
              end else
              begin
                AConsumed := I + 1;
                Exit(frFailed);
              end;
          end;
        end;

      dsPartHeader:
        begin
          // 在写入前检查实际容量，允许结束符恰好落在最后一个有效字节。
          if FCurrentPartHeaderLen >= Length(FCurrentPartHeader) then
          begin
            AConsumed := I;
            Exit(frFailed);
          end;
          FCurrentPartHeader[FCurrentPartHeaderLen] := C;
          Inc(FCurrentPartHeaderLen);

          // 状态机严格匹配 #13#10#13#10 序列
          case FLineEndState of
            lesCR1: if (C = 13) then FLineEndState := lesLF1;
            lesLF1:
              if (C = 10) then FLineEndState := lesCR2
              else if (C <> 13) then FLineEndState := lesCR1;
            lesCR2:
              if (C = 13) then FLineEndState := lesLF2
              else FLineEndState := lesCR1;
            lesLF2:
              if (C = 10) then
              begin
                FLineEndState := lesCR1;
                // 块头部结束 #13#10#13#10
                LNewField := TFormField.Create;
                try
                  if not __InitFormFieldByHeader(LNewField, @FCurrentPartHeader[0],
                    FCurrentPartHeaderLen) then
                  begin
                    AConsumed := I + 1;
                    Exit(frFailed);
                  end;
                  // 辅助方法同步读取且复制所需值后才重置长度，缓冲区可供下一 part 复用。
                  FCurrentPartHeaderLen := 0;
                  FPartFields.Add(LNewField);
                  FCurrentPartField := LNewField;
                  LNewField := nil;
                finally
                  if LNewField <> nil then
                  begin
                    // 初始化或加入拥有列表失败时，不能留下未被接管的流和临时文件。
                    LFailedFilePath := '';
                    try
                      if LNewField.FIsTempFile then
                        LFailedFilePath := LNewField.FilePath;
                    finally
                      LNewField.Free;
                    end;
                    if LFailedFilePath <> '' then
                      DeleteFile(LFailedFilePath);
                  end;
                end;

                FDecodeState := dsPartData;
                FPartDataBegin := -1;
                FBoundaryIndex := 0;
                FPrevBoundaryIndex := 0;
                FCurrentPartDataSize := 0;
              end else
              if (C = 13) then FLineEndState := lesLF1
              else FLineEndState := lesCR1;
          end;

        end;

      dsPartData:
        begin
          // 如果这是一个新的数据块, 需要保存数据块起始位置
          if (FPartDataBegin < 0) then
            FPartDataBegin := I;

          // 检测Boundary
          if (C = FBoundaryBytes[FBoundaryIndex]) then
          begin
            Inc(FBoundaryIndex);

            if (FPrevBoundaryIndex > 0) then
            begin
              FLookbehind[FPrevBoundaryIndex] := C;
              Inc(FPrevBoundaryIndex);
            end;
          end else
          begin
            // 上一个内存块结尾有部分有点像Boundary的数据,
            // 进一步判断之后确定不是Boundary, 需要把这部分数据写入Field中
            if (FPrevBoundaryIndex > 0) then
            begin
              FCurrentPartField.FValue.WriteBuffer(FLookbehind[0], FPrevBoundaryIndex);
              Inc(FCurrentPartDataSize, FPrevBoundaryIndex);
              // 检查单 Part Body 大小是否超限 (与块结尾检查对称)
              if (FMaxPartDataSize > 0) and (FCurrentPartDataSize > FMaxPartDataSize) then
              begin
                AConsumed := I + 1;
                Exit(frFailed);
              end;
              FPrevBoundaryIndex := 0;
              FPartDataBegin := I;
            end;

            if (FBoundaryIndex > 0) then
            begin
              // 之前检测到有一部分数据跟Boundary有点像, 但是到这个字节可以确定之前
              // 这部分数据并不是Boundary, 需要把这部分数据写入Field中
              FCurrentPartField.FValue.WriteBuffer(P[FPartDataBegin], I - FPartDataBegin);
              Inc(FCurrentPartDataSize, I - FPartDataBegin);
              FPartDataBegin := I;

              FBoundaryIndex := 0;

              // 再次检测Boundary
              if (C = FBoundaryBytes[FBoundaryIndex]) then
                Inc(FBoundaryIndex);
            end;
          end;

          // 如果已到内存块结束或者已经解析出一个完整的数据块
          if (I >= ALen - 1) or (FBoundaryIndex >= Length(FBoundaryBytes)) then
          begin
            // 将内存块数据存入Field中
            if (FPartDataBegin >= 0) then
            begin
              LSize := I - FPartDataBegin - FBoundaryIndex + 1;
              if (LSize > 0) then
              begin
                FCurrentPartField.FValue.WriteBuffer(P[FPartDataBegin], LSize);
                Inc(FCurrentPartDataSize, LSize);
              end;
            end;

            // 检查单 Part Body 大小是否超限 (必须在状态切换前检查)
            if (FMaxPartDataSize > 0) and (FCurrentPartDataSize > FMaxPartDataSize) then
            begin
              AConsumed := I + 1;
              Exit(frFailed);
            end;

            // 已解析出一个完整的数据块
            if (FBoundaryIndex >= Length(FBoundaryBytes)) then
            begin
              FCurrentPartField.FValue.Position := 0;
              FDecodeState := dsDetect;
              FBoundaryIndex := 0;
              FPrevBoundaryIndex := 0;
              FCurrentPartDataSize := 0;
            end else
            // 已解析到本内存块结尾, 但是发现了部分有点像Boundary的数据
            // 将其保存起来
            if (FPrevBoundaryIndex = 0) and (FBoundaryIndex > 0) then
            begin
              FPrevBoundaryIndex := FBoundaryIndex;
              Move(P[I - FBoundaryIndex + 1], FLookbehind[0], FBoundaryIndex);
            end;

            // 数据块起始位置需要在之后决定
            FPartDataBegin := -1;
          end;
        end;
    end;

    Inc(I);
  end;

  AConsumed := ALen;
  Result := frContinue;
end;

function THttpMultiPartFormData.Decode(const ABuf: Pointer; ALen: Integer): TFormDataDecodeResult;
var
  LDummy: Integer;
begin
  // 兼容旧调用方: 丢弃 consumed; 仅在调用方明确知道 multipart 数据帧严格对齐时使用.
  Result := Decode(ABuf, ALen, LDummy);
end;

{ THttpMultiPartFormStream.TFormFieldEx }

function THttpMultiPartFormStream.TFormFieldEx.HeaderSize: Integer;
begin
  Result := Length(Header);
end;

{ THttpMultiPartFormStream }

constructor THttpMultiPartFormStream.Create(
  const AMultiPartFormData: THttpMultiPartFormData; const AOwned: Boolean);
begin
  FMultiPartFormData := AMultiPartFormData;
  FOwned := AOwned;

  _Init;
end;

destructor THttpMultiPartFormStream.Destroy;
begin
  if FOwned and (FMultiPartFormData <> nil) then
    FreeAndNil(FMultiPartFormData);

  inherited;
end;

function THttpMultiPartFormStream.GetSize: Int64;
begin
  Result := FSize;
end;

procedure THttpMultiPartFormStream._CheckField(const AIndex: Integer);
var
  LField: TFormField;
  LSize: Int64;
begin
  if FMultiPartFormData.Count <> Length(FFormFieldExArray) then
    raise EReadError.Create('Multipart 字段集合已改变');
  LField := FMultiPartFormData.Items[AIndex];
  if LField <> FFormFieldExArray[AIndex].Field then
    raise EReadError.Create('Multipart 字段已改变');
  if LField.Value <> FFormFieldExArray[AIndex].Stream then
    raise EReadError.Create('Multipart 字段流已改变');
  LSize := 0;
  if LField.Value <> nil then LSize := LField.Value.Size;
  if LSize <> FFormFieldExArray[AIndex].DataSize then
    raise EReadError.Create('Multipart 字段流大小已改变');
end;

function THttpMultiPartFormStream.Read(var ABuffer; ACount: Longint): Longint;
var
  LRemaining, LCount, LActual: Integer;
  LOffset, LDataOffset: Int64;
  LField: PFormFieldEx;
  P: PByte;
begin
  Result := 0;
  if (FPosition < 0) or (FPosition >= FSize) or (ACount <= 0) then Exit;

  // 用剩余长度做减法，避免接近 Int64 上限时 ACount + FPosition 溢出。
  LRemaining := Min(Int64(ACount), FSize - FPosition);
  P := @ABuffer;
  while LRemaining > 0 do
  begin
    if FPosition >= FEndPos then
    begin
      LOffset := FPosition - FEndPos;
      LCount := Min(Int64(LRemaining), Length(FMultiPartEnd) - LOffset);
      Move(FMultiPartEnd[Integer(LOffset)], P^, LCount);
      Inc(FPosition, LCount);
      Inc(Result, LCount);
      Break;
    end;

    if FFieldIndex < 0 then FFieldIndex := _GetFieldIndexByOffset(FPosition);
    _CheckField(FFieldIndex);
    LField := @FFormFieldExArray[FFieldIndex];
    LOffset := FPosition - LField.Offset;
    if LOffset < LField.HeaderSize then
    begin
      LCount := Min(Int64(LRemaining), LField.HeaderSize - LOffset);
      Move(LField.Header[Integer(LOffset)], P^, LCount);
      Inc(P, LCount);
      Inc(FPosition, LCount);
      Inc(Result, LCount);
      Dec(LRemaining, LCount);
    end;

    if (LRemaining > 0) and (FPosition < LField.EndOffset) then
    begin
      LDataOffset := FPosition - LField.Offset - LField.HeaderSize;
      if LField.Stream.Seek(LDataOffset, soBeginning) <> LDataOffset then
        raise EReadError.Create('Multipart 字段流无法定位');
      LCount := Min(Int64(LRemaining), LField.DataSize - LDataOffset);
      while LCount > 0 do
      begin
        LActual := LField.Stream.Read(P^, LCount);
        if (LActual <= 0) or (LActual > LCount) then
          raise EReadError.Create('Multipart 字段流未返回预期数据');
        // 合法短读继续补齐；只推进实际已填充的字节，不调用外部 Seek 重查字段。
        Inc(P, LActual);
        Inc(FPosition, LActual);
        Inc(Result, LActual);
        Dec(LRemaining, LActual);
        Dec(LCount, LActual);
      end;
    end;

    if FPosition = LField.EndOffset then
    begin
      Inc(FFieldIndex);
      if FFieldIndex = Length(FFormFieldExArray) then FFieldIndex := -1;
    end;
  end;
end;

function THttpMultiPartFormStream.Seek(const AOffset: Int64;
  AOrigin: TSeekOrigin): Int64;
var
  LBase: Int64;
begin
  case AOrigin of
    soBeginning: LBase := 0;
    soCurrent: LBase := FPosition;
    soEnd: LBase := FSize;
  else
    Exit(FPosition);
  end;
  if AOffset > 0 then
  begin
    if LBase > High(Int64) - AOffset then FPosition := FSize
    else FPosition := LBase + AOffset;
  end
  else if AOffset < 0 then
  begin
    if LBase < Low(Int64) - AOffset then FPosition := -1
    else FPosition := LBase + AOffset;
  end
  else FPosition := LBase;

  if FPosition < 0 then FPosition := -1;
  if FPosition > FSize then FPosition := FSize;
  FFieldIndex := _GetFieldIndexByOffset(FPosition);
  Result := FPosition;
end;

function THttpMultiPartFormStream._GetFieldIndexByOffset(
  const AOffset: Int64): Integer;
var
  LLow, LHigh, LMiddle: Integer;
begin
  Result := -1;
  if (AOffset < 0) or (AOffset >= FEndPos) then Exit;
  LLow := 0;
  LHigh := High(FFormFieldExArray);
  while LLow <= LHigh do
  begin
    LMiddle := LLow + (LHigh - LLow) div 2;
    if AOffset < FFormFieldExArray[LMiddle].Offset then
      LHigh := LMiddle - 1
    else if AOffset >= FFormFieldExArray[LMiddle].EndOffset then
      LLow := LMiddle + 1
    else
      Exit(LMiddle);
  end;
end;

procedure THttpMultiPartFormStream._Init;
var
  I: Integer;
  LFormFieldEx: TFormFieldEx;
  LContentType, LPartHeaderStr: string;
  LPartHeaderBytes, LBoundary: TBytes;
  LOffset, LPartSize: Int64;
begin
  {
  --boundary_value
  Content-Disposition: form-data; name="text_field"

  This is a simple text field.

  --boundary_value
  Content-Disposition: form-data; name="binary_data"
  Content-Type: application/octet-stream

  [Binary data goes here]

  --boundary_value
  Content-Disposition: form-data; name="file_field"; filename="example.txt"
  Content-Type: text/plain

  Contents of the example.txt file.

  --boundary_value
  Content-Disposition: form-data; name="image"; filename="image.jpg"
  Content-Type: image/jpeg

  [Binary image data]

  --boundary_value--
  }
  if FMultiPartFormData = nil then
    raise EStreamError.Create('Multipart 数据不能为空');

  // 检查 boundary, 如果没有则生成
  if (FMultiPartFormData.Boundary = '') then
  begin
    Randomize;
    FMultiPartFormData.Boundary := '--DCSFormBoundary'
      + IntToHex(Random(MaxInt), 8)
      + IntToHex(Random(MaxInt), 8);
  end;

  // 结尾数据
  FMultiPartEnd := TArrayUtils<Byte>.Concat(FMultiPartFormData.FBoundaryBytes, [45, 45, 13, 10]);

  LOffset := 0;
  FSize := 0;
  FPosition := 0;
  FFieldIndex := -1;

  {$region '生成Field的头'}
  SetLength(FFormFieldExArray, FMultiPartFormData.Count);
  if Length(FFormFieldExArray) > 0 then FFieldIndex := 0;

  for I := 0 to FMultiPartFormData.Count - 1 do
  begin
    LFormFieldEx.Offset := LOffset;
    LFormFieldEx.Field := FMultiPartFormData.Items[I];
    if LFormFieldEx.Field = nil then
      raise EStreamError.Create('Multipart 字段不能为空');
    LFormFieldEx.Stream := LFormFieldEx.Field.Value;
    LFormFieldEx.DataSize := 0;
    if LFormFieldEx.Stream <> nil then
      LFormFieldEx.DataSize := LFormFieldEx.Stream.Size;
    if LFormFieldEx.DataSize < 0 then
      raise EStreamError.Create('Multipart 字段流大小不能为负数');

    if (I = 0) then
      LBoundary := FMultiPartFormData.FFirstBoundaryBytes
    else
      LBoundary := FMultiPartFormData.FBoundaryBytes;

    // 'Content-Disposition: form-data; name="%s"; filename="%s"'#13#10 +
    // 'Content-Type: %s'#13#10#13#10

    LContentType := LFormFieldEx.Field.ContentType;

    LPartHeaderStr := Format(
      'Content-Disposition: form-data; name="%s"', [
        LFormFieldEx.Field.Name
      ]);
    if (LFormFieldEx.Field.FileName <> '') then
    begin
      LPartHeaderStr := LPartHeaderStr
        + Format('; filename="%s"', [LFormFieldEx.Field.FileName]);

      if (LContentType = '') then
        LContentType := TCrossHttpUtils.GetFileMIMEType(LFormFieldEx.Field.FileName);
    end;
    LPartHeaderStr := LPartHeaderStr + #13#10;

    if (LContentType <> '') then
    begin
      LPartHeaderStr := LPartHeaderStr
        + Format('Content-Type: %s', [LContentType])
        + #13#10;
    end;
    LPartHeaderStr := LPartHeaderStr + #13#10;

    LPartHeaderBytes := TEncoding.UTF8.GetBytes(LPartHeaderStr);

    LFormFieldEx.Header := TArrayUtils<Byte>.Concat([
      LBoundary, [13, 10], LPartHeaderBytes]);

    if LFormFieldEx.DataSize > High(Int64) - LFormFieldEx.HeaderSize then
      raise EStreamError.Create('Multipart 字段长度溢出');
    LPartSize := LFormFieldEx.HeaderSize + LFormFieldEx.DataSize;
    if LOffset > High(Int64) - LPartSize then
      raise EStreamError.Create('Multipart 总长度溢出');
    Inc(LOffset, LPartSize);
    LFormFieldEx.EndOffset := LOffset;

    FFormFieldExArray[I] := LFormFieldEx;
  end;
  {$endregion}

  FEndPos := LOffset;
  if LOffset > High(Int64) - Length(FMultiPartEnd) then
    raise EStreamError.Create('Multipart 结尾长度溢出');
  FSize := LOffset + Length(FMultiPartEnd);
end;

{ TResponseCookies }

procedure TResponseCookies.AddOrSet(const AName, AValue: string;
  AMaxAge: Integer; const APath, ADomain: string; AHttpOnly, ASecure: Boolean);
begin
  SetCookie(AName, TResponseCookie.Create(AName, AValue, AMaxAge, APath, ADomain, AHttpOnly, ASecure));
end;

function TResponseCookies.GetCookieIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if TStrUtils.SameText(Items[I].Name, AName) then Exit(I);
  Result := -1;
end;

procedure TResponseCookies.Remove(const AName: string);
var
  I: Integer;
begin
  I := GetCookieIndex(AName);
  if (I >= 0) then
    inherited Delete(I);
end;

function TResponseCookies.GetCookie(const AName: string): TResponseCookie;
var
  I: Integer;
begin
  I := GetCookieIndex(AName);
  if (I >= 0) then
    Result := Items[I]
  else
  begin
    Result := TResponseCookie.Create(AName, '', 0);
    Add(Result);
  end;
end;

procedure TResponseCookies.SetCookie(const AName: string;
  const Value: TResponseCookie);
var
  I: Integer;
begin
  I := GetCookieIndex(AName);
  if (I >= 0) then
    Items[I] := Value
  else
    Add(Value);
end;

end.
