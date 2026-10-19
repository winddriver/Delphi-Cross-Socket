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
  TNameValue = record
    Name, Value: string;
    constructor Create(const AName, AValue: string);
  end;

  INameValueComparer = IComparer<TNameValue>;
  TNameValueComparison = {$IFDEF DELPHI}TComparison<TNameValue>{$ELSE}TComparisonAnonymousFunc<TNameValue>{$ENDIF};
  TNameValueComparer = {$IFDEF DELPHI}TDelegatedComparer<TNameValue>{$ELSE}TDelegatedComparerAnonymousFunc<TNameValue>{$ENDIF};

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
      function GetCurrent: TNameValue; inline;
      function MoveNext: Boolean; inline;
      property Current: TNameValue read GetCurrent;
    end;
  private
    FParams: TList<TNameValue>;

    function GetParamIndex(const AName: string): Integer;
    function GetParam(const AName: string): string;
    procedure SetParam(const AName, AValue: string);
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TNameValue;
    procedure SetItem(AIndex: Integer; const AValue: TNameValue);
  public
    constructor Create; overload; virtual;
    constructor Create(const AEncodedParams: string); overload; virtual;
    destructor Destroy; override;

    /// <summary>
    ///   枚举器
    /// </summary>
    function GetEnumerator: TEnumerator; inline;

    /// <summary>
    ///   从源对象设置数据
    /// </summary>
    procedure Assign(const ASource: TBaseParams);

    /// <summary>
    ///   添加参数
    /// </summary>
    procedure Add(const AParamValue: TNameValue); overload;

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
    ///   是否允许重名参数
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
    procedure Sort(const AComparison: TNameValueComparison = nil);

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
    property Items[AIndex: Integer]: TNameValue read GetItem write SetItem;

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
  public
    // 在所有同名头中匹配完整的逗号分隔 token，不接受子串。
    function ContainsToken(const AName, AToken: string): Boolean;
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

  TFormField = class
  private
    FName: string;
    FValue: TStream;
    FFileName: string;
    FFilePath: string;
    FContentType: string;
    FContentTransferEncoding: string;
    FValueOwned, FIsTempFile: Boolean;
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
    property FilePath: string read FFilePath;

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

{ TNameValue }

constructor TNameValue.Create(const AName,
  AValue: string);
begin
  Name := AName;
  Value := AValue;
end;

{ TBaseParams.TEnumerator }

constructor TBaseParams.TEnumerator.Create(const AParams: TBaseParams);
begin
  FParams := AParams;
  FIndex := -1;
end;

function TBaseParams.TEnumerator.GetCurrent: TNameValue;
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
begin
  FParams := TList<TNameValue>.Create(TComparer<TNameValue>.Construct(
    function(const Left, Right: TNameValue): Integer
    begin
      Result := CompareText(Left.Name, Right.Name, TLocaleOptions.loUserLocale);
    end));
end;

constructor TBaseParams.Create(const AEncodedParams: string);
begin
  Create;
  Decode(AEncodedParams, True);
end;

destructor TBaseParams.Destroy;
begin
  FreeAndNil(FParams);
  inherited;
end;

procedure TBaseParams.Add(const AName, AValue: string; ADupAllowed: Boolean);
begin
  if ADupAllowed then
    FParams.Add(TNameValue.Create(AName, AValue))
  else
    SetParam(AName, AValue);
end;

procedure TBaseParams.Add(const AEncodedParams: string);
begin
  Decode(AEncodedParams, False);
end;

procedure TBaseParams.Assign(const ASource: TBaseParams);
var
  LParamItem: TNameValue;
begin
  Clear;

  if (ASource = nil) or (ASource.Count <= 0) then Exit;

  for LParamItem in ASource do
    Add(LParamItem);
end;

procedure TBaseParams.Add(const AParamValue: TNameValue);
begin
  FParams.Add(AParamValue);
end;

procedure TBaseParams.Clear;
begin
  FParams.Clear;
end;

function TBaseParams.GetParamIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FParams.Count - 1 do
    if TStrUtils.SameText(FParams[I].Name, AName) then Exit(I);
  Result := -1;
end;

function TBaseParams.GetParamValue(const AName: string;
  out AValue: string): Boolean;
var
  I: Integer;
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
  begin
    AValue := FParams[I].Value;
    Exit(True);
  end;

  AValue := '';
  Result := False;
end;

function TBaseParams.GetHeaderValues(const AName: string;
  out AValues: TArray<string>): Boolean;
var
  I, LCount: Integer;
begin
  SetLength(AValues, FParams.Count);
  LCount := 0;
  Result := False;
  for I := 0 to FParams.Count - 1 do
  begin
    if not TStrUtils.SameText(FParams[I].Name, AName) then Continue;
    AValues[LCount] := FParams[I].Value;
    Inc(LCount);
    Result := True;
  end;
  SetLength(AValues, LCount);
end;

function THttpHeader.ContainsToken(const AName, AToken: string): Boolean;
var
  LHeader: TNameValue;
  LToken, LValue: string;
begin
  if not _IsHttpToken(AToken) then Exit(False);
  for LHeader in Self do
    if TStrUtils.SameText(LHeader.Name, AName) then
      for LToken in LHeader.Value.Split([',']) do
      begin
        LValue := LToken.Trim;
        // HTTP token 只有 ASCII；不能让 Unicode 大小写折叠把其他字符当成协议名。
        if _IsHttpToken(LValue) and TStrUtils.SameText(LValue, AToken) then Exit(True);
      end;
  Result := False;
end;

procedure TBaseParams.Remove(const AName: string);
var
  I: Integer;
begin
  // 倒序删除，避免删除后索引移动导致漏项。
  for I := FParams.Count - 1 downto 0 do
    if TStrUtils.SameText(FParams[I].Name, AName) then
      FParams.Delete(I);
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

function TBaseParams.GetItem(AIndex: Integer): TNameValue;
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
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
    Exit(FParams[I].Value);
  Result := '';
end;

procedure TBaseParams.SetItem(AIndex: Integer; const AValue: TNameValue);
begin
  FParams[AIndex] := AValue;
end;

procedure TBaseParams.SetParam(const AName, AValue: string);
var
  I: Integer;
  LItem: TNameValue;
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
  begin
    LItem := FParams[I];
    LItem.Value := AValue;
    FParams[I] := LItem;
  end else
    FParams.Add(TNameValue.Create(AName, AValue));
end;

procedure TBaseParams.Sort(const AComparison: TNameValueComparison);
var
  LComparer: INameValueComparer;
begin
  if Assigned(AComparison) then
    LComparer := TNameValueComparer.Create(AComparison)
  else
    LComparer := TNameValueComparer.Create(
      function(const Left, Right: TNameValue): Integer
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
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    if (I > 0) then
      Result := Result + '&';

    if FEncodeName then
      LName := TCrossHttpUtils.UrlEncode(FParams[I].Name)
    else
      LName := FParams[I].Name;
    Result := Result + LName;

    if FEncodeValue then
      LValue := TCrossHttpUtils.UrlEncode(FParams[I].Value)
    else
      LValue := FParams[I].Value;
    if (LValue <> '') then
      Result := Result + '=' + LValue;
  end;
end;

{ THttpHeader }

function THttpHeader.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
const
  CR = #13;
  LF = #10;
var
  P, PEnd, LLineStart, LColonPos, LValueStart, LValueEnd: PChar;
  LCh: Char;
  LName, LValue: string;
  LLineValid, LInName: Boolean;
  LDecodedCount: Integer;
begin
  if AClear then
    FParams.Clear;

  LDecodedCount := 0;
  P := PChar(AEncodedParams);
  PEnd := P + Length(AEncodedParams);

  // 单趟状态机解析 (RFC 7230 §3): 每行字符仅访问 1 次, 同时完成
  //   1) CRLF 边界检测: bare-CR / bare-LF 立即拒绝 (Exit(False)),
  //      防御 \r\r\n\n 等走私序列及上下游切分不一致
  //   2) ':' 定位 (切 name / value)
  //   3) value 前后 OWS 跳过 + 尾随 OWS 自动 trim
  //   4) name 每字节 token 校验 + value 每字节 CTL 校验
  //  非法行整行跳过 (仅限 name/value 校验失败, 不含 bare-CR/LF),
  //  与 THttpHeader.Encode 过滤策略对称, 作为深度防御.
  while (P < PEnd) do
  begin
    LLineStart := P;
    LColonPos := nil;
    LValueStart := nil;
    LValueEnd := nil;
    LLineValid := True;
    LInName := True;

    // 内层: 逐字节扫描本行, 直到 CRLF 或 PEnd
    while (P < PEnd) do
    begin
      LCh := P^;

      if (LCh = CR) then
      begin
        if (P + 1 < PEnd) and ((P + 1)^ = LF) then
          Break; // 完整 CRLF: 退出内层, P 仍指向 CR
        // bare-CR: 立即拒绝, 防御 \r\r\n\n 等走私序列
        if AClear then FParams.Clear;
        Exit(False);
      end;

      if (LCh = LF) then
      begin
        // bare-LF: 立即拒绝
        if AClear then FParams.Clear;
        Exit(False);
      end;

      if LInName then
      begin
        if (LCh = ':') then
        begin
          LColonPos := P;
          LInName := False;
        end else
        if not TCrossHttpUtils.IsTokenChar(LCh) then
          // name 段非 token 字符 (含 OWS / CTL / 非 ASCII 等) → 非法
          LLineValid := False;
      end else
      begin
        // value 段: 前导 OWS 跳过, 记录首/末非 OWS 位置, 同时校验 CTL
        if (LCh <> ' ') and (LCh <> #9) then
        begin
          if (LValueStart = nil) then
            LValueStart := P;
          LValueEnd := P + 1; // exclusive: 最后非 OWS 字符之后位置
          if not TCrossHttpUtils.IsHeaderValueChar(LCh) then
            LLineValid := False;
        end;
      end;

      Inc(P);
    end;

    // 退出内层: P 指向 CR (CRLF 完整) 或 P >= PEnd (末尾无 CRLF).
    // 末尾无 CRLF 的残行也按相同规则尝试入库, 兼容 multipart part header
    // 等调用方剥掉块终止符 \r\n\r\n 后再喂入的字符串. 主路径 HTTP
    // request/response header 末尾必带空行 \r\n, 始终走 CRLF 完整分支,
    // 严格性不变.
    if (P < PEnd) then
      Inc(P, 2); // 跳过 CRLF; PEnd 路径 P 已等于 PEnd, 外层 while 自然退出

    if not LLineValid then Continue;

    // 空行: header 块结束标记, 跳过.
    //   CRLF 完整路径: LLineStart 指向被消费 CRLF 的位置 (即 P - 2)
    //   PEnd 路径    : LLineStart 等于 P (本行 0 字节)
    if (LLineStart = P) or (LLineStart = P - 2) then Continue;

    // 必须出现过 ':'
    if (LColonPos = nil) then Continue;

    // name 不能为空
    if (LColonPos = LLineStart) then Continue;

    SetString(LName, LLineStart, LColonPos - LLineStart);

    if (LValueStart = nil) then
      LValue := ''
    else
      SetString(LValue, LValueStart, LValueEnd - LValueStart);

    Add(LName, LValue, True);
    Inc(LDecodedCount);
  end;

  Result := (LDecodedCount > 0);
end;

function THttpHeader.Encode: string;
var
  I: Integer;
  LName, LValue: string;
begin
  // 防御 HTTP 响应拆分 (Response Splitting):
  //   Header name 必须是 RFC 7230 token, value 不允许 CR/LF/CTL.
  //   非法 entry 直接跳过 (业务方应在写入前自行 sanitize), 避免拼到 wire 上注入伪造响应.
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    LName := FParams[I].Name;
    LValue := FParams[I].Value;

    if not TCrossHttpUtils.IsValidHeaderName(LName) then Continue;
    if not TCrossHttpUtils.IsValidHeaderValue(LValue) then Continue;

    Result := Result + LName + ': ' + LValue + #13#10;
  end;
  Result := Result + #13#10;
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
  LParsedParams: TList<TNameValue>;
  LItem: TNameValue;
  LPos, LLen, LPairEnd, LEqualsPos, LDecodedCount: Integer;
  LPair: string;
  LName, LValue: string;
  LNormalizedValue: string;
begin
  LDecodedCount := 0;
  Result := False;
  // 先解析到临时列表，确保整行 Cookie 全部合法后再提交，避免失败时留下半解析数据。
  LParsedParams := TList<TNameValue>.Create;
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

      LParsedParams.Add(TNameValue.Create(LName, LNormalizedValue));
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
    if (I > 0) then
      Result := Result + '; ';
    LName := FParams[I].Name;
    LValue := FParams[I].Value;
    if not _IsHttpToken(LName) then
      raise Exception.CreateFmt('Invalid cookie name: %s', [LName]);
    if not _IsCookieOctets(LValue) then
      raise Exception.CreateFmt('Invalid cookie value: %s', [LName]);
    Result := Result + LName + '=' + LValue;
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
  if FValueOwned and Assigned(FValue) then
    FreeAndNil(FValue);
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
begin
  FreeValue;

  if (ASource = nil) then Exit;

  FName := ASource.FName;
  FValueOwned := ASource.FValueOwned;
  FIsTempFile := ASource.FIsTempFile;
  FFileName := ASource.FFileName;
  FFilePath := ASource.FFilePath;
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
  Clear;
  FCurrentPartHeader := nil;
  FCurrentPartField := nil;
  FreeAndNil(FPartFields);
  inherited;
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

procedure THttpMultiPartFormData.Clear;
var
  LField: TFormField;
begin
  for LField in FPartFields do
  begin
    if FAutoDeleteFiles and (LField.FilePath <> '')
      and FileExists(LField.FilePath) then
    begin
      LField.FreeValue;

      if LField.FIsTempFile then
        DeleteFile(LField.FilePath);
    end;
  end;

  FPartFields.Clear;
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

  function __InitFormFieldByHeader(AFormField: TFormField; const AHeader: string): Boolean;
  var
    LFieldHeader: THttpHeader;
    LContentDisposition: string;
    LMatch: TMatch;
  begin
    Result := False;

    LFieldHeader := THttpHeader.Create;
    try
      LFieldHeader.Decode(AHeader);
      LContentDisposition := LFieldHeader['Content-Disposition'];
      if (LContentDisposition = '') then Exit;

      AFormField.FContentType := LFieldHeader['Content-Type'];

      LMatch := TRegEx.Match(LContentDisposition, '\bname="(.*?)"(?=;|$)', [TRegExOption.roIgnoreCase]);
      if LMatch.Success then
        AFormField.FName := LMatch.Groups[1].Value;

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
        LMatch := TRegEx.Match(LContentDisposition, '\bfilename="(.*?)"(?=;|$)', [TRegExOption.roIgnoreCase]);
        // 带 filename 属性的头:
        //   Content-Disposition: form-data; name="content"; filename="test.json"
        //   Content-Type: application/json
        if LMatch.Success then
        begin
          AFormField.FFileName := TPathUtils.GetFileName(LMatch.Groups[1].Value);
          AFormField.FFilePath := TPathUtils.Combine(FStoragePath,
            __NewFileID + TPathUtils.GetExtension(AFormField.FFileName));
        end else
        begin
          AFormField.FFileName := __NewFileID + '.bin';
          AFormField.FFilePath := TPathUtils.Combine(FStoragePath,
            AFormField.FFileName);
        end;

        AFormField.FIsTempFile := True;
        AFormField.FValue := TFileUtils.OpenCreate(AFormField.FFilePath);
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
  LPartHeader: string;
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
                // 块头部通常采用UTF8编码
                LPartHeader := TUtils.GetString(@FCurrentPartHeader[0], FCurrentPartHeaderLen - 4{#13#10#13#10});
                FCurrentPartHeaderLen := 0;
                FCurrentPartField := TFormField.Create;
                if not __InitFormFieldByHeader(FCurrentPartField, LPartHeader) then
                begin
                  FreeAndNil(FCurrentPartField);
                  AConsumed := I + 1;
                  Exit(frFailed);
                end;
                FPartFields.Add(FCurrentPartField);

                FDecodeState := dsPartData;
                FPartDataBegin := -1;
                FBoundaryIndex := 0;
                FPrevBoundaryIndex := 0;
                FCurrentPartDataSize := 0;
              end else
              if (C = 13) then FLineEndState := lesLF1
              else FLineEndState := lesCR1;
          end;

          // 块头部过大, 视为非法数据
          if (FCurrentPartHeaderLen > MAX_PART_HEADER) then
          begin
            AConsumed := I + 1;
            Exit(frFailed);
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
              FCurrentPartField.FValue.Write(FLookbehind[0], FPrevBoundaryIndex);
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
              FCurrentPartField.FValue.Write(P[FPartDataBegin], I - FPartDataBegin);
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
                FCurrentPartField.FValue.Write(P[FPartDataBegin], LSize);
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
