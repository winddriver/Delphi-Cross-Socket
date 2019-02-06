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
  ///   ����������
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
    ///   ��Ӳ���
    /// </summary>
    /// <param name="AName">
    ///   ������
    /// </param>
    /// <param name="AValue">
    ///   ����ֵ
    /// </param>
    /// <param name="ADupAllowed">
    ///   �Ƿ�������������
    /// </param>
    procedure Add(const AName, AValue: string; ADupAllowed: Boolean = False); overload;

    /// <summary>
    ///   ����ѱ������
    /// </summary>
    /// <param name="AEncodedParams">
    ///   �ѱ�������ַ���
    /// </param>
    procedure Add(const AEncodedParams: string); overload;

    /// <summary>
    ///   ��������ɾ��ָ������
    /// </summary>
    /// <param name="AName">
    ///   ��������
    /// </param>
    procedure Remove(const AName: string); overload;

    /// <summary>
    ///   �������ɾ��ָ������
    /// </summary>
    /// <param name="AIndex">
    ///   �������
    /// </param>
    procedure Remove(AIndex: Integer); overload;

    /// <summary>
    ///   ������в���
    /// </summary>
    procedure Clear;

    /// <summary>
    ///   �Բ�������
    /// </summary>
    procedure Sort(const AComparison: TComparison<TNameValue> = nil);

    /// <summary>
    ///   ���ѱ�����ַ����н���
    /// </summary>
    /// <param name="AEncodedParams">
    ///   �ѱ����ַ���
    /// </param>
    /// <param name="AClear">
    ///   �Ƿ������������
    /// </param>
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); virtual; abstract;

    /// <summary>
    ///   ����Ϊ�ַ���
    /// </summary>
    function Encode: string; virtual; abstract;

    /// <summary>
    ///   ��ȡ����ֵ
    /// </summary>
    function GetParamValue(const AName: string; out AValue: string): Boolean;

    /// <summary>
    ///   �����Ʒ��ʲ���
    /// </summary>
    property Params[const AName: string]: string read GetParam write SetParam; default;

    /// <summary>
    ///   ����ŷ��ʲ���
    /// </summary>
    property Items[AIndex: Integer]: TNameValue read GetItem write SetItem;

    /// <summary>
    ///   ��������
    /// </summary>
    property Count: Integer read GetCount;
  end;

  /// <summary>
  ///   Url������
  /// </summary>
  THttpUrlParams = class(TBaseParams)
  private
    FEncodeName: Boolean;
    FEncodeValue: Boolean;
  public
    constructor Create; override;

    /// <summary>
    ///   ���ѱ�����ַ����н���
    /// </summary>
    /// <param name="AEncodedParams">
    ///   �ѱ����ַ���
    /// </param>
    /// <param name="AClear">
    ///   �Ƿ������������
    /// </param>
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   ����Ϊ�ַ���
    /// </summary>
    function Encode: string; override;

    /// <summary>
    ///   �Ƿ������������
    /// </summary>
    property EncodeName: Boolean read FEncodeName write FEncodeName;

    /// <summary>
    ///   �Ƿ������������
    /// </summary>
    property EncodeValue: Boolean read FEncodeValue write FEncodeValue;
  end;

  /// <summary>
  ///   HTTPͷ��
  /// </summary>
  THttpHeader = class(TBaseParams)
  public
    /// <summary>
    ///   ���ѱ�����ַ����н���
    /// </summary>
    /// <param name="AEncodedParams">
    ///   �ѱ����ַ���
    /// </param>
    /// <param name="AClear">
    ///   �Ƿ������������
    /// </param>
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   ����Ϊ�ַ���
    /// </summary>
    function Encode: string; override;
  end;

  /// <summary>
  ///   ���ָ����Ĳ���
  /// </summary>
  TDelimitParams = class(TBaseParams)
  private
    FDelimiter: Char;
  public
    /// <summary>
    ///   ���ѱ�����ַ����н���
    /// </summary>
    /// <param name="AEncodedParams">
    ///   �ѱ����ַ���
    /// </param>
    /// <param name="AClear">
    ///   �Ƿ������������
    /// </param>
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   ����Ϊ�ַ���
    /// </summary>
    function Encode: string; override;

    /// <summary>
    ///   �ָ��ַ�
    /// </summary>
    property Delimiter: Char read FDelimiter write FDelimiter;
  end;

  /// <summary>
  ///   �ͻ�������ͷ�е�Cookies
  /// </summary>
  TRequestCookies = class(TBaseParams)
  public
    /// <summary>
    ///   ���ѱ�����ַ����н���
    /// </summary>
    /// <param name="AEncodedParams">
    ///   �ѱ����ַ���
    /// </param>
    /// <param name="AClear">
    ///   �Ƿ������������
    /// </param>
    procedure Decode(const AEncodedParams: string; AClear: Boolean = True); override;

    /// <summary>
    ///   ����Ϊ�ַ���
    /// </summary>
    function Encode: string; override;
  end;

  TResponseCookie = record
    /// <summary>
    ///   Cookie����
    /// </summary>
    Name: string;

    /// <summary>
    ///   Cookie����
    /// </summary>
    Value: string;

    /// <summary>
    ///   Cookie��Ч������, �������Ϊ0��������رպ��Cookie��ʧЧ
    /// </summary>
    MaxAge: Integer;

    /// <summary>
    ///   ����������
    /// </summary>
    /// <remarks>
    ///   ����Cookie����Ч������, ֻ�е�������·��ͬʱ�����ʱ��, ������ŻὫCookie���͸�Server.
    ///   ���û������Domain��Path�Ļ�, ���ǻᱻĬ��Ϊ��ǰ����ҳ���Ӧֵ
    /// </remarks>
    Domain: string;

    /// <summary>
    ///   ·��������
    /// </summary>
    /// <remarks>
    ///   ����Cookie����Ч������, ֻ�е�������·��ͬʱ�����ʱ��, ������ŻὫCookie���͸�Server.
    ///   ���û������Domain��Path�Ļ�, ���ǻᱻĬ��Ϊ��ǰ����ҳ���Ӧֵ
    /// </remarks>
    Path: string;

    /// <summary>
    ///   �Ƿ����� HttpOnly
    /// </summary>
    /// <remarks>
    ///   HttpOnly�ֶθ��������, ֻ����HTTPЭ����ʹ��, ��������Ľű����ɼ�, ���Կ�վ�ű�����ʱҲ���ᱻ��ȡ
    /// </remarks>
    HttpOnly: Boolean;

    /// <summary>
    ///   �Ƿ�����Secure
    /// </summary>
    /// <remarks>
    ///   Secure�ֶθ����������httpsͨ��ʱ, ��Cookie���а�ȫ����, ������ʱ�кڿͼ���Ҳ�޷���ȡcookie����
    /// </remarks>
    Secure: Boolean;

    constructor Create(const AName, AValue: string; AMaxAge: Integer;
      const APath: string = ''; const ADomain: string = '';
      AHttpOnly: Boolean = False; ASecure: Boolean = False);

    function Encode: string;
  end;

  /// <summary>
  ///   Cookie��
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
    ///   ������תΪ�ֽ�
    /// </summary>
    function AsBytes: TBytes;

    /// <summary>
    ///   ������תΪ�ַ���
    /// </summary>
    /// <param name="AEncoding">
    ///   �ַ�������
    /// </param>
    function AsString(AEncoding: TEncoding = nil): string;

    /// <summary>
    ///   �ͷ�������
    /// </summary>
    procedure FreeValue;

    /// <summary>
    ///   ����
    /// </summary>
    property Name: string read FName;

    /// <summary>
    ///   ԭʼ������
    /// </summary>
    property Value: TStream read FValue;

    /// <summary>
    ///   �ļ�����ֻ���ļ����и����ԣ�
    /// </summary>
    property FileName: string read FFileName;

    /// <summary>
    ///   �ļ�����·����ֻ���ļ����и����ԣ�
    /// </summary>
    property FilePath: string read FFilePath;

    /// <summary>
    ///   �������ͣ�ֻ���ļ����и����ԣ�
    /// </summary>
    property ContentType: string read FContentType;
    property ContentTransferEncoding: string read FContentTransferEncoding;
  end;

  /// <summary>
  ///   MultiPartFormData��
  /// </summary>
  THttpMultiPartFormData = class(TEnumerable<TFormField>)
  public type
    TDecodeState = (dsBoundary, dsDetect, dsPartHeader, dsPartData);
  private const
    DETECT_HEADER_BYTES: array [0..1] of Byte = (13, 10); // �س�����
    DETECT_END_BYTES: array [0..3] of Byte = (45, 45, 13, 10); // --�س�����
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
    /// ��ʼ��Boundary(Decode֮ǰ����)
    /// </summary>
    procedure InitWithBoundary(const ABoundary: string);

    /// <summary>
    ///   ���ڴ��н���(�����ȵ���InitWithBoundary)
    /// </summary>
    /// <param name="ABuf">
    ///   ����������
    /// </param>
    /// <param name="ALen">
    ///   ���ݳ���
    /// </param>
    function Decode(const ABuf: Pointer; ALen: Integer): Integer;

    /// <summary>
    /// �������Items
    /// </summary>
    procedure Clear;

    /// <summary>
    /// Boundary�����ַ���(ֻ��)
    /// </summary>
    property Boundary: string read FBoundary;

    /// <summary>
    /// �ϴ��ļ������·��
    /// </summary>
    property StoragePath: string read FStoragePath write FStoragePath;

    /// <summary>
    /// ����ŷ��ʲ���
    /// </summary>
    property Items[AIndex: Integer]: TFormField read GetItem;

    /// <summary>
    ///   �����Ʒ��ʲ���
    /// </summary>
    property Fields[const AName: string]: TFormField read GetField;

    /// <summary>
    /// Items����(ֻ��)
    /// </summary>
    property Count: Integer read GetCount;

    /// <summary>
    /// ����Items���ݵ��ܳߴ�(�ֽ���)
    /// </summary>
    property DataSize: Integer read GetDataSize;

    /// <summary>
    /// �����ͷ�ʱ�Զ�ɾ���ϴ����ļ�
    /// </summary>
    property AutoDeleteFiles: Boolean read FAutoDeleteFiles write FAutoDeleteFiles;
  end;

  /// <summary>
  ///   Session��Ա�ӿ�
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
    ///   ����������ʱ��
    /// </summary>
    procedure Touch;

    /// <summary>
    ///   �Ƿ��ѹ���
    /// </summary>
    function Expired: Boolean;

    /// <summary>
    ///   Session ID
    /// </summary>
    property SessionID: string read GetSessionID write SetSessionID;

    /// <summary>
    ///   ����ʱ��
    /// </summary>
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;

    /// <summary>
    ///   ������ʱ��
    /// </summary>
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;

    /// <summary>
    ///   Session����ʱ��(��)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       ֵ����0ʱ, ��Session�����趨ֵ����û��ʹ�þͻᱻ�ͷ�;
    ///     </item>
    ///     <item>
    ///       ֵС�ڵ���0ʱ, Session���ɺ�һֱ��Ч
    ///     </item>
    ///   </list>
    /// </remarks>
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;

    /// <summary>
    ///   Session��һ��KEY-VALUE�ṹ������, ���������ڷ������еĳ�Աֵ
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
  ///   Session����ӿ�
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
    ///   ��ʼд(�����߳�ͬ��)
    /// </summary>
    procedure BeginWrite;

    /// <summary>
    ///   ����д(�����߳�ͬ��)
    /// </summary>
    procedure EndWrite;

    /// <summary>
    ///   ��ʼ��(�����߳�ͬ��)
    /// </summary>
    procedure BeginRead;

    /// <summary>
    ///   ������(�����߳�ͬ��)
    /// </summary>
    procedure EndRead;

    /// <summary>
    ///   ������Session ID
    /// </summary>
    function NewSessionID: string;

    /// <summary>
    ///   ����Ƿ����ָ��ID��Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <param name="ASession">
    ///   �������ָ����Session�� ��ʵ�����浽�ò�����
    /// </param>
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; overload;

    /// <summary>
    ///   ����Ƿ����ָ��ID��Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    function ExistsSession(const ASessionID: string): Boolean; overload;

    /// <summary>
    ///   ����Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <returns>
    ///   Sessionʵ��
    /// </returns>
    function AddSession(const ASessionID: string): ISession; overload;

    /// <summary>
    ///   ����Session
    /// </summary>
    /// <returns>
    ///   Sessionʵ��
    /// </returns>
    function AddSession: ISession; overload;

    /// <summary>
    ///   ����Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <param name="ASession">
    ///   Sessionʵ��
    /// </param>
    procedure AddSession(const ASessionID: string; ASession: ISession); overload;

    /// <summary>
    ///   ɾ��Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    procedure RemoveSession(const ASessionID: string);

    /// <summary>
    ///   Session��
    /// </summary>
    property SessionClass: TSessionClass read GetSessionClass write SetSessionClass;

    /// <summary>
    ///   Session����
    /// </summary>
    property Count: Integer read GetCount;

    /// <summary>
    ///   ��ȡָ����ŵ�Session, ����������򷵻�nil
    /// </summary>
    property Items[const AIndex: Integer]: ISession read GetItem;

    /// <summary>
    ///   ��ȡָ��ID��Session, �������������½�һ��
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    property Sessions[const ASessionID: string]: ISession read GetSession; default;

    /// <summary>
    ///   Session����ʱ��(��)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       ֵ����0ʱ, ��Session�����趨ֵ����û��ʹ�þͻᱻ�ͷ�;
    ///     </item>
    ///     <item>
    ///       ֵС�ڵ���0ʱ, Session���ɺ�һֱ��Ч
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
    // ���������'='
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
    // ���������'&'
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
    // ���������':'
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
    // ���������#13#10
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
    // ���������'='
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
    // ���������';'
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
    // ���������'='
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
    // ���������';'
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
      // ���Boundary, ��ȷ����һ������
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

      // ��ͨ��Boundary���, ���������ȷ�����������ݻ����ѵ�����
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

          // �Ƿ�����
          if (FDetectHeaderIndex = 0) and (FDetectEndIndex = 0) then Exit(I);

          // ��⵽������־
          // --Boundary--#13#10
          if (FDetectEndIndex >= Length(DETECT_END_BYTES)) then
          begin
            FDecodeState := dsBoundary;
            CR := 0;
            LF := 0;
            FBoundaryIndex := 0;
            FDetectEndIndex := 0;
          end else
          // ���滹������
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

          // ����ͷ�����ݵ���������, ����������, ����ͻ��˹����������, ����һ��
          // �ޱȾ޴��ͷ����, �ͻ���ɻ�����ռ�ù����ڴ�, �����п����ڴ����
          // �����������һ��ͷ�����ߴ������(MAX_PART_HEADER)
          // ***���Խ�һ���Ż�***:
          // ���Բ�ʹ����ʱ������, ������ֱ�Ӵ�ABuf�н���ͷ����, ������ͷ���ݱ���
          // �����ABuf��ʱ����Ƚ��鷳
          FCurrentPartHeader.Write(C, 1);
          // ��ͷ������, ��Ϊ�Ƿ�����
          if (FCurrentPartHeader.Size > MAX_PART_HEADER) then Exit(I);

          // ��ͷ������
          // #13#10#13#10
          if (CR = 2) and (LF = 2) then
          begin
            // ��ͷ��ͨ������UTF8����
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
          // �������һ���µ����ݿ�, ��Ҫ�������ݿ���ʼλ��
          if (FPartDataBegin < 0) and (FPrevIndex = 0) then
            FPartDataBegin := I;

          // ���Boundary
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

          // ��һ���ڴ���β�в����е���Boundary������, ��һ���ж�
          if (FPrevIndex > 0) then
          begin
            // �����ǰ�ֽ���Ȼ�ܸ�Boundaryƥ��, �������䱣��������һ������
            if (FBoundaryIndex > 0) then
            begin
              FLookbehind[FPrevIndex] := C;
              Inc(FPrevIndex);
            end else
            // ��ǰ�ֽ���Boundary��ƥ��, ��ô˵��֮ǰ������е���Boundary������
            // ������Boundary, �������ݿ��е�����, �������Field��
            begin
              FCurrentPartField.FValue.Write(FLookbehind[0], FPrevIndex);
              FPrevIndex := 0;
            end;
          end;

          // ����ѵ��ڴ����������Ѿ�������һ�����������ݿ�
          if (I >= ALen - 1) or (FBoundaryIndex >= Length(FBoundaryBytes)) then
          begin
            // ���ڴ�����ݴ���Field��
            if (FPartDataBegin >= 0) then
              FCurrentPartField.FValue.Write(P[FPartDataBegin], I - FPartDataBegin - FBoundaryIndex + 1);

            // �ѽ�����һ�����������ݿ�
            if (FBoundaryIndex >= Length(FBoundaryBytes)) then
            begin
              FCurrentPartField.FValue.Position := 0;
              FDecodeState := dsDetect;
              FBoundaryIndex := 0;
            end else
            // �ѽ��������ڴ���β, ���Ƿ����˲����е���Boundary������
            // ���䱣������
            if (FPrevIndex = 0) and (FBoundaryIndex > 0) then
            begin
              FPrevIndex := FBoundaryIndex;
              Move(P[I - FBoundaryIndex + 1], FLookbehind[0], FBoundaryIndex);
            end;

            // ���ݿ���ʼλ����Ҫ��֮�����
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
          // ÿ 5 ��������һ�γ�ʱ Session
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

