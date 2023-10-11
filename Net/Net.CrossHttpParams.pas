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

  {$IFDEF DELPHI}
  System.Diagnostics,
  {$ELSE}
  DTF.Types,
  DTF.Diagnostics,
  DTF.Generics,
  {$ENDIF}

  Net.CrossHttpUtils,

  Utils.AnonymousThread,
  Utils.RegEx,
  Utils.IOUtils,
  Utils.DateTime,
  Utils.StrUtils,
  Utils.SyncObjs,
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
    ///   根据名称删除指定参数
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
    function Decode(const AEncodedParams: string; AClear: Boolean = True): Boolean; virtual; abstract;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; virtual; abstract;

    /// <summary>
    ///   获取参数值
    /// </summary>
    function GetParamValue(const AName: string; out AValue: string): Boolean;

    /// <summary>
    ///   是否存在参数
    /// </summary>
    function ExistsParam(const AName: string): Boolean;

    /// <summary>
    ///   按名称访问参数
    /// </summary>
    property Params[const AName: string]: string read GetParam write SetParam; default;

    /// <summary>
    ///   按序号访问参数
    /// </summary>
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
    FValueOwned: Boolean;
  public
    constructor Create; overload;
    destructor Destroy; override;

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
  private const
    DETECT_HEADER_BYTES: array [0..1] of Byte = (13, 10); // 回车换行
    DETECT_END_BYTES: array [0..3] of Byte = (45, 45, 13, 10); // --回车换行
    MAX_PART_HEADER: Integer = 64 * 1024;
  private
    FBoundary, FStoragePath: string;
    FFirstBoundaryBytes, FBoundaryBytes, FLookbehind: TBytes;
    FBoundaryIndex, FDetectHeaderIndex, FDetectEndIndex, FPartDataBegin: Integer;
    FPrevBoundaryIndex: Integer;
    FDecodeState: TDecodeState;
    CR, LF: Integer;
    FPartFields: TObjectList<TFormField>;
    FCurrentPartHeader: TBytesStream;
    FCurrentPartField: TFormField;
    FAutoDeleteFiles: Boolean;

    function GetItemIndex(const AName: string): Integer;
    function GetItem(AIndex: Integer): TFormField;
    function GetCount: Integer;
    function GetDataSize: Integer;
    function GetField(const AName: string): TFormField;
    procedure SetBoundary(const AValue: string);
  public
    constructor Create; virtual;
    destructor Destroy; override;

    /// <summary>
    ///   枚举器
    /// </summary>
    function GetEnumerator: TEnumerator; inline;

    /// <summary>
    /// 初始化Boundary(Decode之前调用)
    /// </summary>
    procedure InitWithBoundary(const ABoundary: string);

    /// <summary>
    ///   从内存中解码(必须先调用InitWithBoundary)
    /// </summary>
    /// <param name="ABuf">
    ///   待解码数据
    /// </param>
    /// <param name="ALen">
    ///   数据长度
    /// </param>
    function Decode(const ABuf: Pointer; ALen: Integer): Integer;

    /// <summary>
    /// 清除所有Items
    /// </summary>
    procedure Clear;

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
      const AStream: TStream; const AOwned: Boolean): TFormField; overload;

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

    /// <summary>
    /// 查找参数
    /// </summary>
    function FindField(const AFieldName: string; out AField: TFormField): Boolean;

    /// <summary>
    /// Boundary特征字符串
    /// </summary>
    property Boundary: string read FBoundary write SetBoundary;

    /// <summary>
    /// 上传文件保存的路径
    /// </summary>
    property StoragePath: string read FStoragePath write FStoragePath;

    /// <summary>
    /// 按序号访问参数
    /// </summary>
    property Items[AIndex: Integer]: TFormField read GetItem;

    /// <summary>
    ///   按名称访问参数
    /// </summary>
    property Fields[const AName: string]: TFormField read GetField;

    /// <summary>
    /// Items个数(只读)
    /// </summary>
    property Count: Integer read GetCount;

    /// <summary>
    /// 所有Items数据的总尺寸(字节数)
    /// </summary>
    property DataSize: Integer read GetDataSize;

    /// <summary>
    /// 对象释放时自动删除上传的文件
    /// </summary>
    property AutoDeleteFiles: Boolean read FAutoDeleteFiles write FAutoDeleteFiles;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   MultiPartFormData流
  /// </summary>
  /// <remarks>
  ///   动态从 MultiPartFormData 对象中读取数据, 而不是打包到内存中, 所以支持从磁盘加载超大文件
  /// </remarks>
  {$ENDREGION}
  THttpMultiPartFormStream = class(TStream)
  private type
    TFormFieldEx = record
      Header: TBytes;
      Field: TFormField;
      Offset: Int64;

      function HeaderSize: Integer;
      function DataSize: Int64;
      function TotalSize: Int64;
    end;

    TFormFieldExArray = TArray<TFormFieldEx>;
  private
    FMultiPartFormData: THttpMultiPartFormData;
    FFormFieldExArray: TFormFieldExArray;
    FMultiPartEnd: TBytes;
    FSize, FPosition, FEndPos: Int64;

    procedure _Init;
    function _GetFiledIndexByOffset(const AOffset: Int64): Integer;
  public
    constructor Create(const AMultiPartFormData: THttpMultiPartFormData);

    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
  end;

  TSessionsBase = class;
  ISessions = interface;

  /// <summary>
  ///   Session成员接口
  /// </summary>
  ISession = interface
  ['{A3D525A1-C534-4CE6-969B-53C5B8CB77C3}']
    function GetOwner: ISessions;

    function GetSessionID: string;
    function GetCreateTime: TDateTime;
    function GetLastAccessTime: TDateTime;
    function GetExpiryTime: Integer;
    function GetValue(const AName: string): string;
    procedure SetSessionID(const ASessionID: string);
    procedure SetCreateTime(const ACreateTime: TDateTime);
    procedure SetLastAccessTime(const ALastAccessTime: TDateTime);
    procedure SetExpiryTime(const Value: Integer);
    procedure SetValue(const AName, AValue: string);

    /// <summary>
    ///   更新最后访问时间
    /// </summary>
    procedure Touch;

    /// <summary>
    ///   是否已过期
    /// </summary>
    function Expired: Boolean;

    /// <summary>
    ///   父容器
    /// </summary>
    property Owner: ISessions read GetOwner;

    /// <summary>
    ///   Session ID
    /// </summary>
    property SessionID: string read GetSessionID write SetSessionID;

    /// <summary>
    ///   创建时间
    /// </summary>
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;

    /// <summary>
    ///   最后访问时间
    /// </summary>
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;

    /// <summary>
    ///   Session过期时间(秒)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       值大于0时, 当Session超过设定值秒数没有使用就会被释放;
    ///     </item>
    ///     <item>
    ///       值等于0时, 使用父容器的超时设置
    ///     </item>
    ///     <item>
    ///       值小于0时, Session生成后一直有效
    ///     </item>
    ///   </list>
    /// </remarks>
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;

    /// <summary>
    ///   Session是一个KEY-VALUE结构的数据, 该属性用于访问其中的成员值
    /// </summary>
    property Values[const AName: string]: string read GetValue write SetValue; default;
  end;

  TSessionBase = class abstract(TInterfacedObject, ISession)
  private
    FOwner: TSessionsBase;
  protected
    function GetOwner: ISessions;
    function GetSessionID: string; virtual; abstract;
    function GetCreateTime: TDateTime; virtual; abstract;
    function GetLastAccessTime: TDateTime; virtual; abstract;
    function GetExpiryTime: Integer; virtual; abstract;
    function GetValue(const AName: string): string; virtual; abstract;
    procedure SetSessionID(const ASessionID: string); virtual; abstract;
    procedure SetCreateTime(const ACreateTime: TDateTime); virtual; abstract;
    procedure SetLastAccessTime(const ALastAccessTime: TDateTime); virtual; abstract;
    procedure SetExpiryTime(const Value: Integer); virtual; abstract;
    procedure SetValue(const AName, AValue: string); virtual; abstract;
  public
    constructor Create(const AOwner: TSessionsBase; const ASessionID: string); virtual;

    procedure Touch; virtual;
    function Expired: Boolean; virtual;

    property Owner: ISessions read GetOwner;

    property SessionID: string read GetSessionID write SetSessionID;
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
    property Values[const AName: string]: string read GetValue write SetValue; default;
  end;

  TSession = class(TSessionBase)
  protected
    FSessionID: string;
    FCreateTime: TDateTime;
    FLastAccessTime: TDateTime;
    FExpire: Integer;
    FValues: TDictionary<string, string>;

    function GetSessionID: string; override;
    function GetCreateTime: TDateTime; override;
    function GetLastAccessTime: TDateTime; override;
    function GetExpiryTime: Integer; override;
    function GetValue(const AName: string): string; override;
    procedure SetSessionID(const ASessionID: string); override;
    procedure SetCreateTime(const ACreateTime: TDateTime); override;
    procedure SetLastAccessTime(const ALastAccessTime: TDateTime); override;
    procedure SetExpiryTime(const AValue: Integer); override;
    procedure SetValue(const AName, AValue: string); override;
  public
    constructor Create(const AOwner: TSessionsBase; const ASessionID: string); override;
    destructor Destroy; override;

    property SessionID: string read GetSessionID write SetSessionID;
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;
    property Values[const AName: string]: string read GetValue write SetValue; default;
  end;

  TSessionClass = class of TSessionBase;

  /// <summary>
  ///   Session管理接口
  /// </summary>
  ISessions = interface
  ['{5187CA76-4CC4-4986-B67B-BC3E76D6CD74}']
    function GetEnumerator: TEnumerator<ISession>;

    function GetSessionClass: TSessionClass;
    function GetCount: Integer;
    function GetItem(const AIndex: Integer): ISession;
    function GetSession(const ASessionID: string): ISession;
    function GetExpiryTime: Integer;
    procedure SetSessionClass(const Value: TSessionClass);
    procedure SetExpiryTime(const Value: Integer);

    /// <summary>
    ///   开始写(用于线程同步)
    /// </summary>
    procedure BeginWrite;

    /// <summary>
    ///   结束写(用于线程同步)
    /// </summary>
    procedure EndWrite;

    /// <summary>
    ///   开始读(用于线程同步)
    /// </summary>
    procedure BeginRead;

    /// <summary>
    ///   结束读(用于线程同步)
    /// </summary>
    procedure EndRead;

    /// <summary>
    ///   生成新Session ID
    /// </summary>
    function NewSessionID: string;

    /// <summary>
    ///   检查是否存在指定ID的Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <param name="ASession">
    ///   如果存在指定的Session， 则将实例保存到该参数中
    /// </param>
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; overload;

    /// <summary>
    ///   检查是否存在指定ID的Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    function ExistsSession(const ASessionID: string): Boolean; overload;

    /// <summary>
    ///   新增Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <returns>
    ///   Session实例
    /// </returns>
    function AddSession(const ASessionID: string): ISession; overload;

    /// <summary>
    ///   新增Session
    /// </summary>
    /// <returns>
    ///   Session实例
    /// </returns>
    function AddSession: ISession; overload;

    /// <summary>
    ///   新增Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <param name="ASession">
    ///   Session实例
    /// </param>
    procedure AddSession(const ASessionID: string; ASession: ISession); overload;

    /// <summary>
    ///   删除Session
    /// </summary>
    /// <param name="ASession">
    ///   Session对象
    /// </param>
    procedure RemoveSession(const ASession: ISession); overload;

    /// <summary>
    ///   删除Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    procedure RemoveSession(const ASessionID: string); overload;

    /// <summary>
    ///   批量删除Session
    /// </summary>
    /// <param name="ASessions">
    ///   Session对象数据
    /// </param>
    procedure RemoveSessions(const ASessions: TArray<ISession>);

    /// <summary>
    ///   清除所有Session
    /// </summary>
    procedure Clear;

    /// <summary>
    ///   Session类
    /// </summary>
    property SessionClass: TSessionClass read GetSessionClass write SetSessionClass;

    /// <summary>
    ///   Session个数
    /// </summary>
    property Count: Integer read GetCount;

    /// <summary>
    ///   获取指定序号的Session, 如果不存在则返回nil
    /// </summary>
    property Items[const AIndex: Integer]: ISession read GetItem;

    /// <summary>
    ///   获取指定ID的Session, 如果不存在则会新建一个
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    property Sessions[const ASessionID: string]: ISession read GetSession; default;

    /// <summary>
    ///   Session过期时间(秒)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       值大于0时, 当Session超过设定值秒数没有使用就会被释放;
    ///     </item>
    ///     <item>
    ///       值小于等于0时, Session生成后一直有效
    ///     </item>
    ///   </list>
    /// </remarks>
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
  end;

  TSessionsBase = class abstract(TInterfacedObject, ISessions)
  protected
    function GetSessionClass: TSessionClass; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetItem(const AIndex: Integer): ISession; virtual; abstract;
    function GetSession(const ASessionID: string): ISession; virtual; abstract;
    function GetExpiryTime: Integer; virtual; abstract;
    procedure SetSessionClass(const Value: TSessionClass); virtual; abstract;
    procedure SetExpiryTime(const Value: Integer); virtual; abstract;
  public
    function GetEnumerator: TEnumerator<ISession>; virtual; abstract;

    procedure BeginWrite; virtual; abstract;
    procedure EndWrite; virtual; abstract;

    procedure BeginRead; virtual; abstract;
    procedure EndRead; virtual; abstract;

    function NewSessionID: string; virtual; abstract;
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; overload; virtual; abstract;
    function ExistsSession(const ASessionID: string): Boolean; overload; virtual;
    function AddSession(const ASessionID: string): ISession; overload; virtual;
    function AddSession: ISession; overload;
    procedure AddSession(const ASessionID: string; ASession: ISession); overload; virtual; abstract;

    procedure RemoveSessions(const ASessions: TArray<ISession>); virtual; abstract;
    procedure RemoveSession(const ASession: ISession); overload; virtual;
    procedure RemoveSession(const ASessionID: string); overload; virtual;

    procedure Clear; virtual; abstract;

    property SessionClass: TSessionClass read GetSessionClass write SetSessionClass;
    property Count: Integer read GetCount;
    property Items[const AIndex: Integer]: ISession read GetItem;
    property Sessions[const ASessionID: string]: ISession read GetSession; default;
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
  end;

  TSessions = class(TSessionsBase)
  private
    FNewGUIDFunc: TFunc<string>;
    FLocker: IReadWriteLock;
    FSessionClass: TSessionClass;
    FExpire: Integer;
    FShutdown, FExpiredProcRunning: Boolean;

    procedure _ClearExpiredSessions;
  protected
    FSessions: TDictionary<string, ISession>;

    function GetSessionClass: TSessionClass; override;
    function GetCount: Integer; override;
    function GetItem(const AIndex: Integer): ISession; override;
    function GetSession(const ASessionID: string): ISession; override;
    function GetExpiryTime: Integer; override;
    procedure SetSessionClass(const Value: TSessionClass); override;
    procedure SetExpiryTime(const Value: Integer); override;

    procedure BeforeClearExpiredSessions; virtual;
    function OnCheckExpiredSession(const ASession: ISession): Boolean; virtual;
    procedure AfterClearExpiredSessions; virtual;
    procedure CreateExpiredProcThread;
  public
    constructor Create(ANewGUIDFunc: TFunc<string>); overload; virtual;
    constructor Create; overload; virtual;
    destructor Destroy; override;

    function GetEnumerator: TEnumerator<ISession>; override;

    procedure BeginWrite; override;
    procedure EndWrite; override;

    procedure BeginRead; override;
    procedure EndRead; override;

    function NewSessionID: string; override;
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; override;
    procedure AddSession(const ASessionID: string; ASession: ISession); override;

    procedure RemoveSessions(const ASessions: TArray<ISession>); override;

    procedure Clear; override;

    property NewGUIDFunc: TFunc<string> read FNewGUIDFunc write FNewGUIDFunc;
  end;

implementation

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

procedure TBaseParams.Remove(const AName: string);
var
  I: Integer;
begin
  I := GetParamIndex(AName);
  if (I >= 0) then
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
begin
  if Assigned(AComparison) then
    FParams.Sort(TNameValueComparer.Create(AComparison))
  else
    FParams.Sort(TNameValueComparer.Create(
      function(const Left, Right: TNameValue): Integer
      begin
        Result := CompareStr(Left.Name, Right.Name, TLocaleOptions.loInvariantLocale);
      end));
end;

{ THttpUrlParams }

constructor THttpUrlParams.Create;
begin
  inherited Create;

  FEncodeName := False;
  FEncodeValue := True;
end;

function THttpUrlParams.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
var
  p, pEnd, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

  p := PChar(AEncodedParams);
  pEnd := p + Length(AEncodedParams);
  while (p < pEnd) do
  begin
    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> '=') and (p^ <> '&') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    LName := TCrossHttpUtils.UrlDecode(LName);
    // 跳过多余的'='
    while (p < pEnd) and (p^ = '=') do
      Inc(p);

    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> '&') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    LValue := TCrossHttpUtils.UrlDecode(LValue);
    // 跳过多余的'&'
    while (p < pEnd) and (p^ = '&') do
      Inc(p);

    Add(LName, LValue);
  end;

  Result := (Self.Count > 0);
end;

function THttpUrlParams.Encode: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    if (I > 0) then
      Result := Result + '&';
    if FEncodeName then
      Result := Result + TCrossHttpUtils.UrlEncode(FParams[I].Name)
    else
      Result := Result + FParams[I].Name;
    if FEncodeValue then
      Result := Result + '=' + TCrossHttpUtils.UrlEncode(FParams[I].Value)
    else
      Result := Result + '=' + FParams[I].Value;
  end;
end;

{ THttpHeader }

function THttpHeader.Decode(const AEncodedParams: string; AClear: Boolean): Boolean;
var
  p, pEnd, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

  p := PChar(AEncodedParams);
  pEnd := p + Length(AEncodedParams);
  while (p < pEnd) do
  begin
    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> ':') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    // 跳过多余的':'
    while (p < pEnd) and ((p^ = ':') or (p^ = ' ')) do
      Inc(p);

    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> #13) do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    // 跳过多余的#13#10
    while (p < pEnd) and ((p^ = #13) or (p^ = #10)) do
      Inc(p);

    Add(LName, LValue);
  end;

  Result := (Self.Count > 0);
end;

function THttpHeader.Encode: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    Result := Result + FParams[I].Name;
    Result := Result + ': ' + FParams[I].Value + #13#10;
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
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

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
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
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
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    if FUrlEncode then
      LValue := TCrossHttpUtils.UrlDecode(LValue);
    // 跳过多余的';'
    while (p < pEnd) and ((p^ = FDelimiter) or (p^ = ' ')) do
      Inc(p);

    Add(LName, LValue);
  end;

  Result := (Self.Count > 0);
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
  p, pEnd, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

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
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    // 跳过多余的'='
    while (p < pEnd) and (p^ = '=') do
      Inc(p);

    q := p;
    LSize := 0;
    while (p < pEnd) and (p^ <> ';') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    LValue := TCrossHttpUtils.UrlDecode(LValue);
    // 跳过多余的';'
    while (p < pEnd) and ((p^ = ';') or (p^ = ' ')) do
      Inc(p);

    Add(LName, LValue);
  end;

  Result := (Self.Count > 0);
end;

function TRequestCookies.Encode: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    if (I > 0) then
      Result := Result + '; ';
    Result := Result + FParams[I].Name + '=' + TCrossHttpUtils.UrlEncode(FParams[I].Value);
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
  Self.Domain := ADomain;
  Self.HttpOnly := AHttpOnly;
  Self.Secure := ASecure;
end;

constructor TResponseCookie.Create(const ACookieData, ADomain: string);

  procedure SetExpires(const AValue: string);
  begin
    if (Self.MaxAge = 0) then
      Self.MaxAge := TCrossHttpUtils.RFC1123_StrToDate(AValue).SecondsDiffer(Now);
  end;

  procedure SetMaxAge(const AValue: string);
  var
    LMaxAge: Integer;
  begin
    if TryStrToInt(AValue, LMaxAge) then
      Self.MaxAge := LMaxAge;
  end;

  procedure SetPath(const AValue: string);
  begin
    if (AValue = '') or (AValue[High(AValue)] <> '/') then
      Self.Path := AValue + '/'
    else
      Self.Path := AValue;
  end;

  procedure SetDomain(const AValue: string);
  begin
    if (AValue <> '') then
      Self.Domain := AValue;
  end;

var
  LValues: TArray<string>;
  I: Integer;
  LPos: Integer;
  LName: string;
  LValue: string;
begin
  LValues := ACookieData.Split([Char(';')], Char('"'));
  if Length(LValues) = 0 then Exit;

  LPos := LValues[0].IndexOf(Char('='));
  if (LPos <= 0) then Exit;

  Self.Name := LValues[0].Substring(0, LPos).Trim;
  Self.Value := TCrossHttpUtils.UrlDecode(LValues[0].Substring(LPos + 1).Trim);
  Self.Path := '/';
  Self.Domain := ADomain;

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
  Result := Self.Name + '=' + TCrossHttpUtils.UrlEncode(Self.Value);

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
  LBytesStream: TBytesStream;
begin
  if (FValue = nil) or (FValue.Size <= 0) then Exit(nil);

  if (FValue is TBytesStream) then
  begin
    Result := TBytesStream(FValue).Bytes;
    SetLength(Result, FValue.Size);
  end else
  begin
    LBytesStream := TBytesStream.Create;
    try
      LBytesStream.CopyFrom(FValue, 0);
      Result := LBytesStream.Bytes;
      SetLength(Result, LBytesStream.Size);
    finally
      FreeAndNil(LBytesStream);
    end;
  end;
end;

function TFormField.AsString(AEncoding: TEncoding): string;
begin
//  if (AEncoding = nil) then
//    AEncoding := TEncoding.UTF8;
//
//  Result := AEncoding.GetString(AsBytes);

  Result := TUtils.GetString(AsBytes, AEncoding);
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
  FCurrentPartHeader := TBytesStream.Create(nil);
  FPartFields := TObjectList<TFormField>.Create(True);
end;

destructor THttpMultiPartFormData.Destroy;
begin
  Clear;
  FreeAndNil(FCurrentPartHeader);
  FreeAndNil(FPartFields);
  inherited;
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
    TFileUtils.OpenRead(AFileName),
    True);
  Result.FFilePath := AFileName;
end;

procedure THttpMultiPartFormData.Clear;
var
  LField: TFormField;
begin
  for LField in FPartFields do
  begin
    if FAutoDeleteFiles and FileExists(LField.FilePath) then
    begin
      LField.FreeValue;
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
  Clear;

  SetBoundary(ABoundary);

  FDecodeState := dsBoundary;
  FBoundaryIndex := 0;
  FPrevBoundaryIndex := 0;
  FCurrentPartHeader.Clear;
  SetLength(FLookbehind, Length(FBoundaryBytes) + 8);
end;

procedure THttpMultiPartFormData.SetBoundary(const AValue: string);
begin
  if (FBoundary <> AValue) then
  begin
    FBoundary := AValue;
    FBoundary := FBoundary.Trim(['"']);

    // 第一块数据是紧跟着 HTTP HEADER 的, 前面没有多余的 #13#10
    FFirstBoundaryBytes := TEncoding.ANSI.GetBytes('--' + FBoundary);

    // 第二块及以后的数据 Boundary 前面都会有 #13#10
    FBoundaryBytes := [13, 10] + FFirstBoundaryBytes;
  end;
end;

function THttpMultiPartFormData.Decode(const ABuf: Pointer; ALen: Integer): Integer;
  function __NewFileID: string;
  begin
    Result := TUtils.GetGUID.ToLower;
  end;

  procedure __InitFormFieldByHeader(AFormField: TFormField; const AHeader: string);
  var
    LFieldHeader: THttpHeader;
    LContentDisposition: string;
    LMatch: TMatch;
  begin
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
          AFormField.FFileName := LMatch.Groups[1].Value;
          AFormField.FFilePath := TPathUtils.Combine(FStoragePath,
            __NewFileID + TPathUtils.GetExtension(AFormField.FFileName));
        end else
        begin
          AFormField.FFileName := __NewFileID + '.bin';
          AFormField.FFilePath := TPathUtils.Combine(FStoragePath,
            AFormField.FFileName);
        end;

        AFormField.FValue := TFileUtils.OpenCreate(AFormField.FFilePath);
      end else
        AFormField.FValue := TBytesStream.Create(nil);

      AFormField.FValueOwned := True;
      AFormField.FContentTransferEncoding := LFieldHeader['Content-Transfer-Encoding'];
    finally
      FreeAndNil(LFieldHeader);
    end;
  end;
var
  C: Byte;
  I: Integer;
  P: PByte;
  LPartHeader: string;
begin
  if (FBoundaryBytes = nil) then Exit(0);

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
            CR := 0;
            LF := 0;
            FBoundaryIndex := 0;
            FDetectHeaderIndex := 0;
            FDetectEndIndex := 0;
          end;
        end;

      // 已通过Boundary检测, 继续检测以确定后面有数据还是已到结束
      dsDetect:
        begin
          if (C = DETECT_HEADER_BYTES[FDetectHeaderIndex]) then
            Inc(FDetectHeaderIndex)
          else
            FDetectHeaderIndex := 0;

          if (C = DETECT_END_BYTES[FDetectEndIndex]) then
            Inc(FDetectEndIndex)
          else
            FDetectEndIndex := 0;

          // 非法数据
          if (FDetectHeaderIndex = 0) and (FDetectEndIndex = 0) then Exit(I);

          // 检测到结束标志
          // --Boundary--#13#10
          if (FDetectEndIndex >= Length(DETECT_END_BYTES)) then
          begin
            FDecodeState := dsBoundary;
            CR := 0;
            LF := 0;
            FBoundaryIndex := 0;
            FDetectEndIndex := 0;
          end else
          // 后面还有数据
          // --Boundary#13#10
          if (FDetectHeaderIndex >= Length(DETECT_HEADER_BYTES)) then
          begin
            FCurrentPartHeader.Clear;
            FDecodeState := dsPartHeader;
            CR := 0;
            LF := 0;
            FBoundaryIndex := 0;
            FDetectHeaderIndex := 0;
          end;
        end;

      dsPartHeader:
        begin
          case C of
            13: Inc(CR);
            10: Inc(LF);
          else
            CR := 0;
            LF := 0;
          end;

          // 保存头部数据到缓存流中, 这里有隐患, 如果客户端构造恶意数据, 生成一个
          // 无比巨大的头数据, 就会造成缓存流占用过多内存, 甚至有可能内存溢出
          // 所以这里加入一个头部最大尺寸的限制(MAX_PART_HEADER)
          // ***可以进一步优化***:
          // 可以不使用临时缓存流, 而采用直接从ABuf中解析头数据, 不过当头数据被切
          // 割到两个ABuf中时处理比较麻烦
          FCurrentPartHeader.Write(C, 1);
          // 块头部过大, 视为非法数据
          if (FCurrentPartHeader.Size > MAX_PART_HEADER) then Exit(I);

          // 块头部结束
          // #13#10#13#10
          if (CR = 2) and (LF = 2) then
          begin
            // 块头部通常采用UTF8编码
            LPartHeader := TUtils.GetString(FCurrentPartHeader.Bytes, 0, FCurrentPartHeader.Size - 4{#13#10#13#10});
            FCurrentPartHeader.Clear;
            FCurrentPartField := TFormField.Create;
            __InitFormFieldByHeader(FCurrentPartField, LPartHeader);
            FPartFields.Add(FCurrentPartField);

            FDecodeState := dsPartData;
            CR := 0;
            LF := 0;
            FPartDataBegin := -1;
            FBoundaryIndex := 0;
            FPrevBoundaryIndex := 0;
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
              FPrevBoundaryIndex := 0;
              FPartDataBegin := I;
            end;

            if (FBoundaryIndex > 0) then
            begin
              // 之前检测到有一部分数据跟Boundary有点像, 但是到这个字节可以确定之前
              // 这部分数据并不是Boundary, 需要把这部分数据写入Field中
              FCurrentPartField.FValue.Write(P[FPartDataBegin], I - FPartDataBegin);
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
              FCurrentPartField.FValue.Write(P[FPartDataBegin], I - FPartDataBegin - FBoundaryIndex + 1);

            // 已解析出一个完整的数据块
            if (FBoundaryIndex >= Length(FBoundaryBytes)) then
            begin
              FCurrentPartField.FValue.Position := 0;
              FDecodeState := dsDetect;
              FBoundaryIndex := 0;
              FPrevBoundaryIndex := 0;
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

  Result := ALen;
end;

{ THttpMultiPartFormStream.TFormFieldEx }

function THttpMultiPartFormStream.TFormFieldEx.DataSize: Int64;
begin
  if (Field <> nil) and (Field.Value <> nil) then
    Result := Field.Value.Size
  else
    Result := 0;
end;

function THttpMultiPartFormStream.TFormFieldEx.HeaderSize: Integer;
begin
  Result := Length(Header);
end;

function THttpMultiPartFormStream.TFormFieldEx.TotalSize: Int64;
begin
  Result := HeaderSize + DataSize;
end;

{ THttpMultiPartFormStream }

constructor THttpMultiPartFormStream.Create(
  const AMultiPartFormData: THttpMultiPartFormData);
begin
  FMultiPartFormData := AMultiPartFormData;

  _Init;
end;

function THttpMultiPartFormStream.Read(var ABuffer; ACount: Longint): Longint;
var
  LReadCount, LPos, LHeaderPos, LDataPos, LCount, LHeaderCount, LDataCount, LEndPos, LEndCount: Int64;
  LFieldIndex: Integer;
  LFieldEx: TFormFieldEx;
  P: PByte;
begin
  Result := 0;
  if (FPosition < 0) or (FPosition >= FSize) or (ACount <= 0) then Exit;

  // 计算实际还能读取多少字节数据
  if (ACount + FPosition <= FSize) then
    LReadCount := ACount
  else
    LReadCount := FSize - FPosition;

  Result := LReadCount;

  P := @ABuffer;

  {$region '从 Field 中读取数据'}
  while (LReadCount > 0) do
  begin
    LFieldIndex := _GetFiledIndexByOffset(FPosition);
    if (LFieldIndex < 0) then Break;

    LFieldEx := FFormFieldExArray[LFieldIndex];

    // 计算要读取的数据位于这个 Field 的偏移
    LPos := FPosition - LFieldEx.Offset;

    // 计算需要从这个 Field 中读取多少字节
    LCount := Min(LFieldEx.TotalSize - LPos, LReadCount);

    // 计算分别需要从 Header 和 Data 中读取多少字节
    if (LPos < LFieldEx.HeaderSize) then
    begin
      LHeaderPos := LPos;
      LDataPos := 0;

      LHeaderCount := Min(LFieldEx.HeaderSize - LHeaderPos, LCount);
      LDataCount := LCount - LHeaderCount;
    end else
    begin
      LHeaderPos := -1;
      LDataPos := LPos - LFieldEx.HeaderSize;

      LHeaderCount := 0;
      LDataCount := LCount - LHeaderCount;
    end;

    // 读取 Header
    if (LHeaderCount > 0) then
    begin
      Move(LFieldEx.Header[LHeaderPos], P^, LHeaderCount);
      Inc(P, LHeaderCount);
      Dec(LReadCount, LHeaderCount);

      Seek(LHeaderCount, soCurrent);
    end;

    // 读取 Data
    if (LDataCount > 0) then
    begin
      LFieldEx.Field.Value.Position := LDataPos;
      LFieldEx.Field.Value.Read(P^, LDataCount);
      Inc(P, LDataCount);
      Dec(LReadCount, LDataCount);

      Seek(LDataCount, soCurrent);
    end;
  end;
  {$endregion}

  // 从尾巴读取数据
  if (LReadCount > 0) then
  begin
    LEndPos := FPosition - FEndPos;
    LEndCount := Min(Length(FMultiPartEnd) - LEndPos, LReadCount);

    if (LEndCount > 0) then
    begin
      Move(FMultiPartEnd[LEndPos], P^, LEndCount);
//      Inc(P, LEndCount);
//      Dec(LReadCount, LEndCount);

      Seek(LEndCount, soCurrent);
    end;
  end;
end;

function THttpMultiPartFormStream.Seek(const AOffset: Int64;
  AOrigin: TSeekOrigin): Int64;
begin
  case AOrigin of
    soBeginning: FPosition := AOffset;
    soCurrent: Inc(FPosition, AOffset);
    soEnd: FPosition := FSize + AOffset;
  end;

  if (FPosition < 0) then
    FPosition := -1;

  if (FPosition > FSize) then
    FPosition := FSize;

  Result := FPosition;
end;

function THttpMultiPartFormStream._GetFiledIndexByOffset(
  const AOffset: Int64): Integer;
var
  LOffset: Int64;
  I: Integer;
begin
  Result := -1;
  if (AOffset < 0) or (AOffset >= FSize) then Exit;

  LOffset := 0;

  for I := 0 to High(FFormFieldExArray) do
  begin
    Inc(LOffset, FFormFieldExArray[I].TotalSize);
    if (AOffset < LOffset) then Exit(I);
  end;
end;

procedure THttpMultiPartFormStream._Init;
var
  I: Integer;
  LFormFieldEx: TFormFieldEx;
  LContentType, LPartHeaderStr: string;
  LBoundary: TBytes;
  LOffset: Int64;
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
  // 检查 boundary, 如果没有则生成
  if (FMultiPartFormData.Boundary = '') then
  begin
    Randomize;
    FMultiPartFormData.Boundary := '--DCSFormBoundary'
      + IntToHex(Random(MaxInt), 8)
      + IntToHex(Random(MaxInt), 8);
  end;

  // 结尾数据
  FMultiPartEnd := FMultiPartFormData.FBoundaryBytes + [45, 45, 13, 10];

  LOffset := 0;
  FSize := 0;
  FPosition := 0;

  {$region '生成Field的头'}
  SetLength(FFormFieldExArray, FMultiPartFormData.Count);

  for I := 0 to FMultiPartFormData.Count - 1 do
  begin
    LFormFieldEx.Offset := LOffset;
    LFormFieldEx.Field := FMultiPartFormData.Items[I];

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

    LFormFieldEx.Header := LBoundary + [13, 10]
      + TEncoding.UTF8.GetBytes(LPartHeaderStr);

    Inc(FSize, LFormFieldEx.HeaderSize);
    Inc(FSize, LFormFieldEx.DataSize);
    Inc(LOffset, LFormFieldEx.TotalSize);

    FFormFieldExArray[I] := LFormFieldEx;
  end;
  {$endregion}

  FEndPos := LOffset;
  Inc(FSize, Length(FMultiPartEnd));
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

{ TSessionBase }

constructor TSessionBase.Create(const AOwner: TSessionsBase; const ASessionID: string);
var
  LNow: TDateTime;
begin
  LNow := Now;

  FOwner := AOwner;

  SetSessionID(ASessionID);
  SetCreateTime(LNow);
  SetLastAccessTime(LNow);
end;

function TSessionBase.Expired: Boolean;
begin
  Result := (ExpiryTime > 0) and (Now.SecondsDiffer(LastAccessTime) >= ExpiryTime);
end;

function TSessionBase.GetOwner: ISessions;
begin
  Result := FOwner;
end;

procedure TSessionBase.Touch;
begin
  LastAccessTime := Now;
end;

{ TSession }

constructor TSession.Create(const AOwner: TSessionsBase; const ASessionID: string);
begin
  FValues := TDictionary<string, string>.Create;

  inherited Create(AOwner, ASessionID);
end;

destructor TSession.Destroy;
begin
  FreeAndNil(FValues);
  inherited;
end;

function TSession.GetCreateTime: TDateTime;
begin
  Result := FCreateTime;
end;

function TSession.GetExpiryTime: Integer;
begin
  Result := FExpire;
end;

function TSession.GetLastAccessTime: TDateTime;
begin
  Result := FLastAccessTime;
end;

function TSession.GetSessionID: string;
begin
  Result := FSessionID;
end;

function TSession.GetValue(const AName: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := '';
  FLastAccessTime := Now;
end;

procedure TSession.SetCreateTime(const ACreateTime: TDateTime);
begin
  FCreateTime := ACreateTime;
end;

procedure TSession.SetExpiryTime(const AValue: Integer);
begin
  FExpire := AValue;
end;

procedure TSession.SetLastAccessTime(const ALastAccessTime: TDateTime);
begin
  FLastAccessTime := ALastAccessTime;
end;

procedure TSession.SetSessionID(const ASessionID: string);
begin
  FSessionID := ASessionID;
end;

procedure TSession.SetValue(const AName, AValue: string);
begin
  if (AValue <> '') then
    FValues.AddOrSetValue(AName, AValue)
  else
    FValues.Remove(AName);
  FLastAccessTime := Now;
end;

{ TSessionsBase }

function TSessionsBase.AddSession(const ASessionID: string): ISession;
begin
  Result := GetSessionClass.Create(Self, ASessionID);
  Result.ExpiryTime := ExpiryTime;
  AddSession(ASessionID, Result);
end;

function TSessionsBase.AddSession: ISession;
begin
  Result := AddSession(NewSessionID);
end;

function TSessionsBase.ExistsSession(const ASessionID: string): Boolean;
var
  LStuff: ISession;
begin
  Result := ExistsSession(ASessionID, LStuff);
end;

procedure TSessionsBase.RemoveSession(const ASessionID: string);
var
  LSession: ISession;
begin
  if ExistsSession(ASessionID, LSession) then
    RemoveSession(LSession);
end;

procedure TSessionsBase.RemoveSession(const ASession: ISession);
begin
  RemoveSessions([ASession]);
end;

{ TSessions }

constructor TSessions.Create(ANewGUIDFunc: TFunc<string>);
begin
  FNewGUIDFunc := ANewGUIDFunc;
  FSessions := TDictionary<string, ISession>.Create;
  FLocker := TReadWriteLock.Create;
  FSessionClass := TSession;
  CreateExpiredProcThread;
end;

procedure TSessions.Clear;
begin
  FSessions.Clear;
end;

constructor TSessions.Create;
begin
  Create(nil);
end;

destructor TSessions.Destroy;
begin
  FShutdown := True;
  while FExpiredProcRunning do Sleep(10);

  BeginWrite;
  FSessions.Clear;
  EndWrite;
  FreeAndNil(FSessions);

  inherited;
end;

procedure TSessions.AddSession(const ASessionID: string; ASession: ISession);
begin
  if (ASession.ExpiryTime = 0) then
    ASession.ExpiryTime := ExpiryTime;
  FSessions.AddOrSetValue(ASessionID, ASession);
end;

procedure TSessions.AfterClearExpiredSessions;
begin

end;

procedure TSessions.BeforeClearExpiredSessions;
begin

end;

procedure TSessions.BeginRead;
begin
  FLocker.BeginRead;
end;

procedure TSessions.BeginWrite;
begin
  FLocker.BeginWrite;
end;

procedure TSessions.EndRead;
begin
  FLocker.EndRead;
end;

procedure TSessions.EndWrite;
begin
  FLocker.EndWrite;
end;

function TSessions.ExistsSession(const ASessionID: string;
  var ASession: ISession): Boolean;
begin
  Result := FSessions.TryGetValue(ASessionID, ASession);
  if Result then
    ASession.Touch;
end;

procedure TSessions.CreateExpiredProcThread;
begin
  TAnonymousThread.Create(
    procedure
    var
      LWatch: TStopwatch;
    begin
      FExpiredProcRunning := True;
      try
        LWatch := TStopwatch.StartNew;
        while not FShutdown do
        begin
          // 每 1 分钟清理一次超时 Session
          if (FExpire > 0) and (LWatch.Elapsed.TotalMinutes >= 1) then
          begin
            _ClearExpiredSessions;
            LWatch.Reset;
            LWatch.Start;
          end;
          Sleep(10);
        end;
      finally
        FExpiredProcRunning := False;
      end;
    end).Start;
end;

function TSessions.NewSessionID: string;
begin
  if Assigned(FNewGUIDFunc) then
    Result := FNewGUIDFunc()
  else
    Result := TUtils.GetGUID.ToLower;
end;

function TSessions.OnCheckExpiredSession(const ASession: ISession): Boolean;
begin
  Result := ASession.Expired;
end;

function TSessions.GetCount: Integer;
begin
  Result := FSessions.Count;
end;

function TSessions.GetEnumerator: TEnumerator<ISession>;
begin
  Result := TDictionary<string, ISession>.TValueEnumerator.Create(FSessions);
end;

function TSessions.GetExpiryTime: Integer;
begin
  Result := FExpire;
end;

function TSessions.GetItem(const AIndex: Integer): ISession;
var
  LIndex: Integer;
  LPair: TPair<string, ISession>;
begin
  LIndex := 0;
  for LPair in FSessions do
  begin
    if (LIndex = AIndex) then Exit(LPair.Value);
    Inc(LIndex);
  end;
  Result := nil;
end;

function TSessions.GetSession(const ASessionID: string): ISession;
var
  LSessionID: string;
begin
  LSessionID := ASessionID;
  BeginWrite;
  try
    if (LSessionID = '') then
      LSessionID := NewSessionID;
    if not FSessions.TryGetValue(LSessionID, Result) then
    begin
      Result := FSessionClass.Create(Self, LSessionID);
      Result.ExpiryTime := ExpiryTime;
      AddSession(LSessionID, Result);
    end;
  finally
    EndWrite;
  end;

  Result.LastAccessTime := Now;
end;

function TSessions.GetSessionClass: TSessionClass;
begin
  Result := FSessionClass;
end;

procedure TSessions.RemoveSessions(const ASessions: TArray<ISession>);
var
  LSession: ISession;
begin
  for LSession in ASessions do
    FSessions.Remove(LSession.SessionID);
end;

procedure TSessions.SetExpiryTime(const Value: Integer);
begin
  FExpire := Value;
end;

procedure TSessions.SetSessionClass(const Value: TSessionClass);
begin
  FSessionClass := Value;
end;

procedure TSessions._ClearExpiredSessions;
var
  LPair: TPair<string, ISession>;
  LDelSessions: TArray<ISession>;
begin
  BeginWrite;
  try
    BeforeClearExpiredSessions;

    LDelSessions := nil;
    for LPair in FSessions do
    begin
      if FShutdown then Break;

      if OnCheckExpiredSession(LPair.Value) then
        LDelSessions := LDelSessions + [LPair.Value];
    end;
    RemoveSessions(LDelSessions);

    AfterClearExpiredSessions;
  finally
    EndWrite;
  end;
end;

end.

