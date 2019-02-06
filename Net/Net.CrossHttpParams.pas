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

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.NetEncoding,
  System.IOUtils,
  System.RegularExpressions,
  System.SyncObjs,
  System.Diagnostics,
  System.DateUtils,
  Net.CrossHttpUtils;

type
  TNameValue = record
    Name, Value: string;
    constructor Create(const AName, AValue: string);
  end;

  /// <summary>
  ///   参数基础类
  /// </summary>
  TBaseParams = class(TEnumerable<TNameValue>)
  private
    FParams: TList<TNameValue>;

    function GetParamIndex(const AName: string): Integer;
    function GetParam(const AName: string): string;
    procedure SetParam(const AName, AValue: string);
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TNameValue;
    procedure SetItem(AIndex: Integer; const AValue: TNameValue);
  protected
    function DoGetEnumerator: TEnumerator<TNameValue>; override;
  public type
    TEnumerator = class(TEnumerator<TNameValue>)
    private
      FList: TList<TNameValue>;
      FIndex: Integer;
    protected
      function DoGetCurrent: TNameValue; override;
      function DoMoveNext: Boolean; override;
    public
      constructor Create(const AList: TList<TNameValue>);
    end;
  public
    constructor Create; overload; virtual;
    constructor Create(const AEncodedParams: string); overload; virtual;
    destructor Destroy; override;

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
    procedure Sort(const AComparison: TComparison<TNameValue> = nil);

    /// <summary>
    ///   从已编码的字符串中解码
    /// </summary>
    /// <param name="AEncodedParams">
    ///   已编码字符串
    /// </param>
    /// <param name="AClear">
    ///   是否清除现有数据
    /// </param>
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); virtual; abstract;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; virtual; abstract;

    /// <summary>
    ///   获取参数值
    /// </summary>
    function GetParamValue(const AName: string; out AValue: string): Boolean;

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
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

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
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; override;
  end;

  /// <summary>
  ///   带分隔符的参数
  /// </summary>
  TDelimitParams = class(TBaseParams)
  private
    FDelimiter: Char;
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
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; override;

    /// <summary>
    ///   分隔字符
    /// </summary>
    property Delimiter: Char read FDelimiter write FDelimiter;
  end;

  /// <summary>
  ///   客户端请求头中的Cookies
  /// </summary>
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
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   编码为字符串
    /// </summary>
    function Encode: string; override;
  end;

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
      AHttpOnly: Boolean = False; ASecure: Boolean = False);

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
  public
    constructor Create;
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
  THttpMultiPartFormData = class(TEnumerable<TFormField>)
  public type
    TDecodeState = (dsBoundary, dsDetect, dsPartHeader, dsPartData);
  private const
    DETECT_HEADER_BYTES: array [0..1] of Byte = (13, 10); // 回车换行
    DETECT_END_BYTES: array [0..3] of Byte = (45, 45, 13, 10); // --回车换行
    MAX_PART_HEADER: Integer = 64 * 1024;
  private
    FBoundary, FStoragePath: string;
    FBoundaryBytes, FLookbehind: TBytes;
    FBoundaryIndex, FDetectHeaderIndex, FDetectEndIndex, FPartDataBegin: Integer;
    FPrevIndex: Integer;
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
  protected
    function DoGetEnumerator: TEnumerator<TFormField>; override;
  public type
    TEnumerator = class(TEnumerator<TFormField>)
    private
      FList: TList<TFormField>;
      FIndex: Integer;
    protected
      function DoGetCurrent: TFormField; override;
      function DoMoveNext: Boolean; override;
    public
      constructor Create(const AList: TList<TFormField>);
    end;
  public
    constructor Create; virtual;
    destructor Destroy; override;

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

    /// <summary>
    /// Boundary特征字符串(只读)
    /// </summary>
    property Boundary: string read FBoundary;

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

  /// <summary>
  ///   Session成员接口
  /// </summary>
  ISession = interface
  ['{A3D525A1-C534-4CE6-969B-53C5B8CB77C3}']
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
    ///       值小于等于0时, Session生成后一直有效
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
  protected
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
    constructor Create(const ASessionID: string); virtual; abstract;

    procedure Touch; virtual;
    function Expired: Boolean; virtual;

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
    constructor Create(const ASessionID: string); override;
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
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    procedure RemoveSession(const ASessionID: string);

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
    function AddSession: ISession; overload; virtual;
    procedure AddSession(const ASessionID: string; ASession: ISession); overload; virtual; abstract;
    procedure RemoveSession(const ASessionID: string); virtual; abstract;

    property SessionClass: TSessionClass read GetSessionClass write SetSessionClass;
    property Count: Integer read GetCount;
    property Items[const AIndex: Integer]: ISession read GetItem;
    property Sessions[const ASessionID: string]: ISession read GetSession; default;
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
  end;

  TSessions = class(TSessionsBase)
  private
    FSessions: TDictionary<string, ISession>;
    FNewGUIDFunc: TFunc<string>;
    FLocker: TMultiReadExclusiveWriteSynchronizer;
    FSessionClass: TSessionClass;
    FExpire: Integer;
    FShutdown, FExpiredProcRunning: Boolean;
  protected
    function GetSessionClass: TSessionClass; override;
    function GetCount: Integer; override;
    function GetItem(const AIndex: Integer): ISession; override;
    function GetSession(const ASessionID: string): ISession; override;
    function GetExpiryTime: Integer; override;
    procedure SetSessionClass(const Value: TSessionClass); override;
    procedure SetExpiryTime(const Value: Integer); override;

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
    procedure RemoveSession(const ASessionID: string); override;

    property NewGUIDFunc: TFunc<string> read FNewGUIDFunc write FNewGUIDFunc;
  end;

implementation

uses
  Utils.Utils,
  Utils.DateTime;

{ TNameValue }

constructor TNameValue.Create(const AName,
  AValue: string);
begin
  Name := AName;
  Value := AValue;
end;

{ TBaseParams.TEnumerator }

constructor TBaseParams.TEnumerator.Create(const AList: TList<TNameValue>);
begin
  inherited Create;
  FList := AList;
  FIndex := -1;
end;

function TBaseParams.TEnumerator.DoGetCurrent: TNameValue;
begin
  Result := FList[FIndex];
end;

function TBaseParams.TEnumerator.DoMoveNext: Boolean;
begin
  if (FIndex >= FList.Count) then
    Exit(False);
  Inc(FIndex);
  Result := (FIndex < FList.Count);
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

procedure TBaseParams.Clear;
begin
  FParams.Clear;
end;

function TBaseParams.GetParamIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FParams.Count - 1 do
    if SameText(FParams[I].Name, AName) then Exit(I);
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

function TBaseParams.GetItem(AIndex: Integer): TNameValue;
begin
  Result := FParams.Items[AIndex];
end;

function TBaseParams.DoGetEnumerator: TEnumerator<TNameValue>;
begin
  Result := TEnumerator.Create(FParams);
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

procedure TBaseParams.Sort(const AComparison: TComparison<TNameValue>);
begin
  if Assigned(AComparison) then
    FParams.Sort(TComparer<TNameValue>.Construct(AComparison))
  else
    FParams.Sort(TComparer<TNameValue>.Construct(
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

procedure THttpUrlParams.Decode(const AEncodedParams: string; AClear: Boolean);
var
  p, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

  p := PChar(AEncodedParams);
  while (p^ <> #0) do
  begin
    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> '=') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    LName := TNetEncoding.URL.Decode(LName);
    // 跳过多余的'='
    while (p^ <> #0) and (p^ = '=') do
      Inc(p);

    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> '&') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    LValue := TNetEncoding.URL.Decode(LValue);
    // 跳过多余的'&'
    while (p^ <> #0) and (p^ = '&') do
      Inc(p);

    Add(LName, LValue);
  end;
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
      Result := Result + TNetEncoding.URL.Encode(FParams[I].Name)
    else
      Result := Result + FParams[I].Name;
    if FEncodeValue then
      Result := Result + '=' + TNetEncoding.URL.Encode(FParams[I].Value)
    else
      Result := Result + '=' + FParams[I].Value;
  end;
end;

{ THttpHeader }

procedure THttpHeader.Decode(const AEncodedParams: string; AClear: Boolean);
var
  p, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

  p := PChar(AEncodedParams);
  while (p^ <> #0) do
  begin
    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> ':') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    // 跳过多余的':'
    while (p^ <> #0) and ((p^ = ':') or (p^ = ' ')) do
      Inc(p);

    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> #13) do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    // 跳过多余的#13#10
    while (p^ <> #0) and ((p^ = #13) or (p^ = #10)) do
      Inc(p);

    Add(LName, LValue);
  end;
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

procedure TDelimitParams.Decode(const AEncodedParams: string; AClear: Boolean);
var
  p, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

  p := PChar(AEncodedParams);
  while (p^ <> #0) do
  begin
    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> '=') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    // 跳过多余的'='
    while (p^ <> #0) and (p^ = '=') do
      Inc(p);

    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> FDelimiter) do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    LValue := TNetEncoding.URL.Decode(LValue);
    // 跳过多余的';'
    while (p^ <> #0) and ((p^ = FDelimiter) or (p^ = ' ')) do
      Inc(p);

    Add(LName, LValue);
  end;
end;

function TDelimitParams.Encode: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FParams.Count - 1 do
  begin
    if (I > 0) then
      Result := Result + FDelimiter + ' ';
    Result := Result + FParams[I].Name + '=' + TNetEncoding.URL.Encode(FParams[I].Value);
  end;
end;

{ TRequestCookies }

procedure TRequestCookies.Decode(const AEncodedParams: string; AClear: Boolean);
var
  p, q: PChar;
  LName, LValue: string;
  LSize: Integer;
begin
  if AClear then
    FParams.Clear;

  p := PChar(AEncodedParams);
  while (p^ <> #0) do
  begin
    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> '=') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LName, LSize);
    Move(q^, Pointer(LName)^, LSize * SizeOf(Char));
    // 跳过多余的'='
    while (p^ <> #0) and (p^ = '=') do
      Inc(p);

    q := p;
    LSize := 0;
    while (p^ <> #0) and (p^ <> ';') do
    begin
      Inc(LSize);
      Inc(p);
    end;
    SetLength(LValue, LSize);
    Move(q^, Pointer(LValue)^, LSize * SizeOf(Char));
    LValue := TNetEncoding.URL.Decode(LValue);
    // 跳过多余的';'
    while (p^ <> #0) and ((p^ = ';') or (p^ = ' ')) do
      Inc(p);

    Add(LName, LValue);
  end;
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
    Result := Result + FParams[I].Name + '=' + TNetEncoding.URL.Encode(FParams[I].Value);
  end;
end;

{ TResponseCookie }

constructor TResponseCookie.Create(const AName, AValue: string;
  AMaxAge: Integer; const APath, ADomain: string; AHttpOnly, ASecure: Boolean);
begin
  Name := AName;
  Value := AValue;
  MaxAge := AMaxAge;
  Path := APath;
  Domain := ADomain;
  HttpOnly := AHttpOnly;
  Secure := ASecure;
end;

function TResponseCookie.Encode: string;
begin
  Result := Name + '=' + TNetEncoding.URL.Encode(Value);

  if (MaxAge > 0) then
  begin
    Result := Result + '; Max-Age=' + MaxAge.ToString;
    Result := Result + '; Expires=' + TCrossHttpUtils.RFC1123_DateToStr(Now.AddSeconds(MaxAge));
  end;
  if (Path <> '') then
    Result := Result + '; Path=' + Path;
  if (Domain <> '') then
    Result := Result + '; Domain=' + Domain;
  if HttpOnly then
    Result := Result + '; HttpOnly';
  if Secure then
    Result := Result + '; Secure';
end;

{ TFormField }

constructor TFormField.Create;
begin
end;

destructor TFormField.Destroy;
begin
  FreeValue;

  inherited;
end;

procedure TFormField.FreeValue;
begin
  if Assigned(FValue) then
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
  if (AEncoding = nil) then
    AEncoding := TEncoding.UTF8;

  Result := AEncoding.GetString(AsBytes);
end;

{ THttpMultiPartFormData.TEnumerator }

constructor THttpMultiPartFormData.TEnumerator.Create(
  const AList: TList<TFormField>);
begin
  inherited Create;
  FList := AList;
  FIndex := -1;
end;

function THttpMultiPartFormData.TEnumerator.DoGetCurrent: TFormField;
begin
  Result := FList[FIndex];
end;

function THttpMultiPartFormData.TEnumerator.DoMoveNext: Boolean;
begin
  if (FIndex >= FList.Count) then
    Exit(False);
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

procedure THttpMultiPartFormData.Clear;
var
  LField: TFormField;
begin
  for LField in FPartFields do
  begin
    if FAutoDeleteFiles and TFile.Exists(LField.FilePath) then
    begin
      LField.FreeValue;
      TFile.Delete(LField.FilePath);
    end;
  end;

  FPartFields.Clear;
end;

function THttpMultiPartFormData.DoGetEnumerator: TEnumerator<TFormField>;
begin
  Result := TEnumerator.Create(FPartFields);
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
    if SameText(FPartFields[I].Name, AName) then Exit(I);
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
  FBoundary := ABoundary;
  FBoundaryBytes := TEncoding.ANSI.GetBytes(#13#10'--' + FBoundary);
  FDecodeState := dsBoundary;
  FBoundaryIndex := 0;
  FCurrentPartHeader.Clear;
  SetLength(FLookbehind, Length(FBoundaryBytes) + 8);
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

      LMatch := TRegEx.Match(LContentDisposition, '\bname="(.*?)"(?=;|$)', [TRegExOption.roIgnoreCase]);
      if LMatch.Success then
        AFormField.FName := LMatch.Groups[1].Value;

      LMatch := TRegEx.Match(LContentDisposition, '\bfilename="(.*?)"(?=;|$)', [TRegExOption.roIgnoreCase]);
      if LMatch.Success then
      begin
        AFormField.FFileName := LMatch.Groups[1].Value;
        AFormField.FFilePath := TPath.Combine(FStoragePath,
          __NewFileID + TPath.GetExtension(AFormField.FFileName));
        if TFile.Exists(AFormField.FFilePath) then
          TFile.Delete(AFormField.FFilePath);
        AFormField.FValue := TFile.Open(AFormField.FFilePath, TFileMode.fmOpenOrCreate, TFileAccess.faReadWrite, TFileShare.fsRead);
      end else
        AFormField.FValue := TBytesStream.Create(nil);

      AFormField.FContentType := LFieldHeader['Content-Type'];
      AFormField.FContentTransferEncoding := LFieldHeader['Content-Transfer-Encoding'];
    finally
      FreeAndNil(LFieldHeader);
    end;
  end;
var
  C: Byte;
  I: Integer;
  P: PByteArray;
  LPartHeader: string;
begin
  if (FBoundaryBytes = nil) then Exit(0);

  P := ABuf;
  I := 0;
  while (I < ALen) do
  begin
    C := P[I];
    case FDecodeState of
      // 检测Boundary, 以确定第一块数据
      dsBoundary:
        begin
          if (C = FBoundaryBytes[2 + FBoundaryIndex]) then
            Inc(FBoundaryIndex)
          else
            FBoundaryIndex := 0;
          // --Boundary
          if (2 + FBoundaryIndex >= Length(FBoundaryBytes)) then
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
            LPartHeader := TEncoding.UTF8.GetString(FCurrentPartHeader.Bytes, 0, FCurrentPartHeader.Size - 4{#13#10#13#10});
            FCurrentPartHeader.Clear;
            FCurrentPartField := TFormField.Create;
            __InitFormFieldByHeader(FCurrentPartField, LPartHeader);
            FPartFields.Add(FCurrentPartField);

            FDecodeState := dsPartData;
            CR := 0;
            LF := 0;
            FPartDataBegin := -1;
            FBoundaryIndex := 0;
            FPrevIndex := 0;
          end;
        end;

      dsPartData:
        begin
          // 如果这是一个新的数据块, 需要保存数据块起始位置
          if (FPartDataBegin < 0) and (FPrevIndex = 0) then
            FPartDataBegin := I;

          // 检测Boundary
          if (C = FBoundaryBytes[FBoundaryIndex]) then
            Inc(FBoundaryIndex)
          else
          begin
            if (FBoundaryIndex > 0) then
            begin
              Dec(I);
              FBoundaryIndex := 0;
            end;

            if (FPartDataBegin < 0) then
              FPartDataBegin := I;
          end;

          // 上一个内存块结尾有部分有点像Boundary的数据, 进一步判断
          if (FPrevIndex > 0) then
          begin
            // 如果当前字节依然能跟Boundary匹配, 继续将其保存以作进一步分析
            if (FBoundaryIndex > 0) then
            begin
              FLookbehind[FPrevIndex] := C;
              Inc(FPrevIndex);
            end else
            // 当前字节与Boundary不匹配, 那么说明之前保存的有点像Boundary的数据
            // 并不是Boundary, 而是数据块中的数据, 将其存入Field中
            begin
              FCurrentPartField.FValue.Write(FLookbehind[0], FPrevIndex);
              FPrevIndex := 0;
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
            end else
            // 已解析到本内存块结尾, 但是发现了部分有点像Boundary的数据
            // 将其保存起来
            if (FPrevIndex = 0) and (FBoundaryIndex > 0) then
            begin
              FPrevIndex := FBoundaryIndex;
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
    if SameText(Items[I].Name, AName) then Exit(I);
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

function TSessionBase.Expired: Boolean;
begin
  Result := (Now.SecondsDiffer(LastAccessTime) >= ExpiryTime);
end;

procedure TSessionBase.Touch;
begin
  LastAccessTime := Now;
end;

{ TSession }

constructor TSession.Create(const ASessionID: string);
begin
  FValues := TDictionary<string, string>.Create;
  FSessionID := ASessionID;
  FCreateTime := Now;
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
  Result := GetSessionClass.Create(ASessionID);
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

{ TSessions }

constructor TSessions.Create(ANewGUIDFunc: TFunc<string>);
begin
  FNewGUIDFunc := ANewGUIDFunc;
  FSessions := TDictionary<string, ISession>.Create;
  FLocker := TMultiReadExclusiveWriteSynchronizer.Create;
  FSessionClass := TSession;
  CreateExpiredProcThread;
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
  FreeAndNil(FLocker);
  FreeAndNil(FSessions);

  inherited;
end;

procedure TSessions.AddSession(const ASessionID: string; ASession: ISession);
begin
  if (ASession.ExpiryTime <= 0) then
    ASession.ExpiryTime := ExpiryTime;
  FSessions.AddOrSetValue(ASessionID, ASession);
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
    ASession.LastAccessTime := Now;
end;

procedure TSessions.CreateExpiredProcThread;
begin
  TThread.CreateAnonymousThread(
    procedure
      procedure _ClearExpiredSessions;
      var
        LPair: TPair<string, ISession>;
      begin
        BeginWrite;
        try
          for LPair in FSessions do
          begin
            if FShutdown then Break;

            if LPair.Value.Expired then
              RemoveSession(LPair.Key);
          end;
        finally
          EndWrite;
        end;
      end;
    var
      LWatch: TStopwatch;
    begin
      FExpiredProcRunning := True;
      try
        LWatch := TStopwatch.StartNew;
        while not FShutdown do
        begin
          // 每 5 分钟清理一次超时 Session
          if (FExpire > 0) and (LWatch.Elapsed.TotalMinutes >= 5) then
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
      Result := FSessionClass.Create(LSessionID);
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

procedure TSessions.RemoveSession(const ASessionID: string);
begin
  FSessions.Remove(ASessionID);
end;

procedure TSessions.SetExpiryTime(const Value: Integer);
begin
  FExpire := Value;
end;

procedure TSessions.SetSessionClass(const Value: TSessionClass);
begin
  FSessionClass := Value;
end;

end.

