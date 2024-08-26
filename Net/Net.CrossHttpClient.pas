{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpClient;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils,
  Math,
  ZLib,
  Generics.Collections,

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket,
  Net.CrossHttpParams,
  Net.CrossHttpUtils,
  Net.CrossHttpParser,

  Utils.StrUtils,
  Utils.IOUtils,
  Utils.SyncObjs,
  Utils.EasyTimer,
  Utils.ArrayUtils,
  Utils.SimpleWatch,
  Utils.Rtti,
  Utils.Utils;

const
  CROSS_HTTP_CLIENT_NAME = 'CrossHttpClient/1.0';
  CRLF = #13#10;

type
  ECrossHttpClient = class(Exception);

  ICrossHttpClientConnection = interface;
  ICrossHttpClientRequest = interface;
  ICrossHttpClientResponse = interface;
  ICrossHttpClient = interface;
  TCrossHttpClient = class;
  TCrossHttpClientSocket = class;
  TServerDock = class;

  {$REGION 'Documentation'}
  /// <summary>
  ///   请求状态
  /// </summary>
  {$ENDREGION}
  TRequestStatus = (
    /// <summary>
    ///   空闲
    /// </summary>
    rsIdle,

    /// <summary>
    ///   正在发送请求
    /// </summary>
    rsSending,

    /// <summary>
    ///   正在等待响应(请求发送成功)
    /// </summary>
    rsResponding,

    /// <summary>
    ///   响应失败(连接断开/数据异常)
    /// </summary>
    rsRespondFailed,

    /// <summary>
    ///   响应超时
    /// </summary>
    rsRespondTimeout);

  {$REGION 'Documentation'}
  /// <summary>
  ///   异步获取 HTTP 连接回调函数
  /// </summary>
  {$ENDREGION}
  TCrossHttpGetConnectionProc = reference to procedure(const AHttpConnection: ICrossHttpClientConnection);

  {$REGION 'Documentation'}
  /// <summary>
  ///   提供块数据的匿名函数(返回 False 表示没有数据了)
  /// </summary>
  {$ENDREGION}
  TCrossHttpChunkDataFunc = reference to function(const AData: PPointer; const ADataSize: PNativeInt): Boolean;

  {$REGION 'Documentation'}
  /// <summary>
  ///   请求初始化函数
  /// </summary>
  {$ENDREGION}
  TCrossHttpRequestInitProc = reference to procedure(const ARequest: ICrossHttpClientRequest);

  {$REGION 'Documentation'}
  /// <summary>
  ///   请求回调函数
  /// </summary>
  /// <remarks>
  ///   <para>
  ///     如果 AResponse 返回 nil 则说明连接失败了
  ///   </para>
  ///   <para>
  ///     否则肯定是连接成功了，然后需要根据 StatusCode 来判断响应是否成功
  ///   </para>
  /// </remarks>
  {$ENDREGION}
  TCrossHttpResponseProc = reference to procedure(const AResponse: ICrossHttpClientResponse);

  PRequestPack = ^TRequestPack;
  TRequestPack = record
  private
    procedure _ParseUrl;
  public
    Url, Protocol, Host: string;
    Port: Word;
    Method, Path: string;
    HttpHeaders: THttpHeader;
    RequestBodyFunc: TCrossHttpChunkDataFunc;
    RequestBody: Pointer;
    RequestBodySize: NativeInt;
    ResponseStream: TStream;
    InitProc: TCrossHttpRequestInitProc;
    Callback: TCrossHttpResponseProc;

    constructor Create(
      const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBodyFunc: TCrossHttpChunkDataFunc;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    constructor Create(
      const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: Pointer;
      const ABodySize: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;
  end;

  /// <summary>
  ///   HTTP客户端连接
  /// </summary>
  ICrossHttpClientConnection = interface(ICrossSslConnection)
  ['{42507AC7-28E0-4CBE-92F6-FFCA8E5E79D6}']
    function GetHost: string;
    function GetPort: Word;
    function GetProtocol: string;
    function GetRequestStatus: TRequestStatus;

    {$REGION 'Documentation'}
    /// <summary>
    ///   连接协议(http/https/ws/wss)
    /// </summary>
    {$ENDREGION}
    property Protocol: string read GetProtocol;

    {$REGION 'Documentation'}
    /// <summary>
    ///   主机地址
    /// </summary>
    {$ENDREGION}
    property Host: string read GetHost;

    {$REGION 'Documentation'}
    /// <summary>
    ///   主机端口
    /// </summary>
    {$ENDREGION}
    property Port: Word read GetPort;

    {$REGION 'Documentation'}
    /// <summary>
    ///   HTTP请求当前状态
    /// </summary>
    {$ENDREGION}
    property RequestStatus: TRequestStatus read GetRequestStatus;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   HTTP客户端请求
  /// </summary>
  {$ENDREGION}
  ICrossHttpClientRequest = interface
  ['{659CAE9A-C79C-4D6C-A696-8BC0A032F40A}']
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;

    {$REGION 'Documentation'}
    /// <summary>
    ///   HTTP 连接
    /// </summary>
    {$ENDREGION}
    property Connection: ICrossHttpClientConnection read GetConnection;

    {$REGION 'Documentation'}
    /// <summary>
    ///   请求头
    /// </summary>
    {$ENDREGION}
    property Header: THttpHeader read GetHeader;

    {$REGION 'Documentation'}
    /// <summary>
    ///   Cookies
    /// </summary>
    {$ENDREGION}
    property Cookies: TRequestCookies read GetCookies;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   HTTP客户端响应
  /// </summary>
  {$ENDREGION}
  ICrossHttpClientResponse = interface
  ['{C9544896-C951-42A1-9E8E-5DBCB3A492AA}']
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetContent: TStream;
    function GetContentType: string;
    function GetStatusCode: Integer;
    function GetStatusText: string;

    {$REGION 'Documentation'}
    /// <summary>
    ///   HTTP 连接
    /// </summary>
    {$ENDREGION}
    property Connection: ICrossHttpClientConnection read GetConnection;

    {$REGION 'Documentation'}
    /// <summary>
    ///   响应头
    /// </summary>
    {$ENDREGION}
    property Header: THttpHeader read GetHeader;

    {$REGION 'Documentation'}
    /// <summary>
    ///   Cookies
    /// </summary>
    {$ENDREGION}
    property Cookies: TResponseCookies read GetCookies;

    {$REGION 'Documentation'}
    /// <summary>
    ///   响应内容
    /// </summary>
    {$ENDREGION}
    property Content: TStream read GetContent;

    {$REGION 'Documentation'}
    /// <summary>
    ///   响应内容类型
    /// </summary>
    {$ENDREGION}
    property ContentType: string read GetContentType;

    {$REGION 'Documentation'}
    /// <summary>
    ///   状态码
    /// </summary>
    {$ENDREGION}
    property StatusCode: Integer read GetStatusCode;

    {$REGION 'Documentation'}
    /// <summary>
    ///   状态说明
    /// </summary>
    {$ENDREGION}
    property StatusText: string read GetStatusText;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   HTTP客户端SOCKET
  /// </summary>
  {$ENDREGION}
  ICrossHttpClientSocket = interface(ICrossSslSocket)
  ['{F689E29A-0489-4F1E-A0B8-64DA80B0862E}']
    procedure DoRequest(const ARequestPack: TRequestPack); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(所有请求的基础方法, 由匿名函数提供数据块)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestData">
    ///   请求体数据生成函数
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TCrossHttpChunkDataFunc;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: Pointer;
      const ABodySize: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   HTTP客户端
  /// </summary>
  {$ENDREGION}
  ICrossHttpClient = interface
  ['{99CC5305-02FE-48DA-9D62-3AE1A5FA86D1}']
    function GetIdleout: Integer;
    function GetIoThreads: Integer;
    function GetMaxConnsPerServer: Integer;
    function GetTimeout: Integer;

    procedure SetIdleout(const AValue: Integer);
    procedure SetIoThreads(const AValue: Integer);
    procedure SetMaxConnsPerServer(const AValue: Integer);
    procedure SetTimeout(const AValue: Integer);

    {$REGION 'Documentation'}
    /// <summary>
    ///   预创建请求对象
    /// </summary>
    {$ENDREGION}
    procedure Prepare(const AProtocols: array of string);

    {$REGION 'Documentation'}
    /// <summary>
    ///   取消所有请求(关闭所有连接)
    /// </summary>
    {$ENDREGION}
    procedure CancelAll;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(由匿名函数提供数据块)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestData">
    ///   请求体数据生成函数
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TCrossHttpChunkDataFunc;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(指定数据指针)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体
    /// </param>
    /// <param name="ABodySize">
    ///   数据大小
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: Pointer; const ABodySize: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(字节数组加偏移)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体
    /// </param>
    /// <param name="AOffset">
    ///   数据偏移
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TBytes; const AOffset, ACount: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(字节数组)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TBytes;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(数据流加偏移)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="AOffset">
    ///   数据偏移
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TStream; const AOffset, ACount: Int64;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   裸数据请求(数据流)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TStream;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   application/x-www-form-urlencoded 请求
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TFormUrlEncoded;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   multipart/form-data 请求
    /// </summary>
    /// <param name="AMethod">
    ///   请求方法
    /// </param>
    /// <param name="AUrl">
    ///   请求地址
    /// </param>
    /// <param name="AHttpHeaders">
    ///   请求头(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="ARequestBody">
    ///   请求体(由于请求是异步的, 所以请在回调中再回收资源, 避免请求过程中出现异常)
    /// </param>
    /// <param name="AResponseStream">
    ///   保存响应体的流对象(可以传nil, 由程序自动创建)
    /// </param>
    /// <param name="AInitProc">
    ///   初始化函数
    /// </param>
    /// <param name="ACallback">
    ///   请求回调
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: THttpMultiPartFormData;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    /// <summary>
    ///   连接空闲时间(秒, 空闲超过该时间连接将自动关闭, 设置为<=0则不检查空闲, 连接一直保留)
    /// </summary>
    property Idleout: Integer read GetIdleout write SetIdleout;

    /// <summary>
    ///   工作线程数
    /// </summary>
    property IoThreads: Integer read GetIoThreads write SetIoThreads;

    /// <summary>
    ///   每个主机最多使用连接数限制(如果设置为<=0的值则不做限制)
    /// </summary>
    property MaxConnsPerServer: Integer read GetMaxConnsPerServer write SetMaxConnsPerServer;

    /// <summary>
    ///   请求超时时间(秒, 从请求发送成功之后算起, 设置为0则不检查超时)
    /// </summary>
    property Timeout: Integer read GetTimeout write SetTimeout;
  end;

  TCrossHttpClientConnection = class(TCrossSslConnection, ICrossHttpClientConnection)
  private
    FProtocol, FHost: string;
    FPort: Word;
    FServerDock: TServerDock;
    FPending: Integer;
    FWatch: TSimpleWatch;
    FStatus: Integer; // TRequestStatus

    FRequest: ICrossHttpClientRequest;
    FResponse: ICrossHttpClientResponse;

    procedure _BeginRequest; inline;
    procedure _EndRequest; inline;
    function _IsIdle: Boolean; inline;
    procedure _UpdateWatch;
    function _IsIdleout: Boolean;
    function _IsTimeout: Boolean;
    function _SetRequestStatus(const AStatus: TRequestStatus): TRequestStatus;
  protected
    function GetHost: string;
    function GetPort: Word;
    function GetProtocol: string;
    function GetRequestStatus: TRequestStatus;

    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer); virtual;

    // 所有请求方法的核心
    procedure DoRequest(const ARequestPack: TRequestPack; const ACallback: TCrossHttpResponseProc); overload;
    procedure DoRequest(const ARequestPack: TRequestPack); overload;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback); override;

    property Protocol: string read GetProtocol;
    property Host: string read GetHost;
    property Port: Word read GetPort;
    property RequestStatus: TRequestStatus read GetRequestStatus;
  end;

  TCrossHttpClientRequest = class(TInterfacedObject, ICrossHttpClientRequest)
  private
    FConnection: TCrossHttpClientConnection;
    FCompressType: TCompressType;

    FHttpVersion: THttpVersion;
    FMethod: string;
    FPath: string;
    FHeader: THttpHeader;
    FCookies: TRequestCookies;

    function _CreateHeader(const ABodySize: Int64; AChunked: Boolean): TBytes;
  protected
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
  protected
    {$region '内部: 基础发送方法'}
    procedure _Send(const ASource: TCrossHttpChunkDataFunc;
      const ACallback: TCrossHttpResponseProc = nil); overload;
    procedure _Send(const AHeaderSource, ABodySource: TCrossHttpChunkDataFunc;
      const ACallback: TCrossHttpResponseProc = nil); overload;
    {$endregion}

    {$region '不压缩发送'}
    procedure SendNoCompress(const AChunkSource: TCrossHttpChunkDataFunc;
      const ACallback: TCrossHttpResponseProc = nil); overload;
    procedure SendNoCompress(const ABody: Pointer; const ABodySize: NativeInt;
      const ACallback: TCrossHttpResponseProc = nil); overload;
    {$endregion}

    {$region '压缩发送'}
    procedure SendZCompress(const AChunkSource: TCrossHttpChunkDataFunc;
      const ACompressType: TCompressType;
      const ACallback: TCrossHttpResponseProc = nil); overload;
    procedure SendZCompress(const ABody: Pointer;
      const ABodySize: NativeInt; const ACompressType: TCompressType;
      const ACallback: TCrossHttpResponseProc = nil); overload;
    {$endregion}

    {$region '裸数据请求方法(body部分需要提前按协议要求打包好)'}
    procedure DoRequest(const AMethod, APath: string;
      const AChunkSource: TCrossHttpChunkDataFunc;
      const ACallback: TCrossHttpResponseProc); overload;
    procedure DoRequest(const AMethod, APath: string;
      const ABody: Pointer; const ABodySize: NativeInt;
      const ACallback: TCrossHttpResponseProc); overload;
    {$endregion}
  public
    constructor Create(const AConnection: TCrossHttpClientConnection);
    destructor Destroy; override;

    property Connection: ICrossHttpClientConnection read GetConnection;
    property Header: THttpHeader read GetHeader;
    property Cookies: TRequestCookies read GetCookies;
  end;

  TCrossHttpClientResponse = class(TInterfacedObject, ICrossHttpClientResponse)
  private
    FConnection: TCrossHttpClientConnection;
    FCallback: TCrossHttpResponseProc;
    FLock: ILock;

    FRawResponseHeader: string;
    FHttpVer: string;
    FStatusCode: Integer;
    FStatusText: string;
    FContentType: string;
    FContentLength: Int64;
    FTransferEncoding, FContentEncoding: string;
    FIsChunked: Boolean;

    FHeader: THttpHeader;
    FCookies: TResponseCookies;

    FResponseBodyStream: TStream;
    FNeedFreeResponseBodyStream: Boolean;

    FHttpParser: TCrossHttpParser;

    procedure _SetResponseStream(const AValue: TStream);
    procedure _Lock; inline;
    procedure _Unlock; inline;

    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValue: string): Boolean;
    procedure _OnBodyBegin;
    procedure _OnBodyData(const ADataPtr: Pointer; const ADataSize: Integer);
    procedure _OnBodyEnd;
    procedure _OnParseSuccess;
    procedure _OnParseFailed(const ACode: Integer; const AError: string);
  protected
    function ParseHeader(const ADataPtr: Pointer; const ADataSize: Integer): Boolean;
    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer);

    procedure TriggerResponseDataBegin; virtual;
    procedure TriggerResponseData(const ABuf: Pointer; const ALen: Integer); virtual;
    procedure TriggerResponseDataEnd; virtual;

    procedure TriggerResponseSuccess; virtual;
    procedure TriggerResponseFailed(const AStatusCode: Integer; const AStatusText: string = ''); virtual;
    procedure TriggerResponseTimeout; virtual;
  protected
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetContent: TStream;
    function GetContentType: string;
    function GetStatusCode: Integer;
    function GetStatusText: string;
  public
    constructor Create(const AConnection: TCrossHttpClientConnection); overload;
    destructor Destroy; override;

    class function Create(const AStatusCode: Integer; const AStatusText: string = ''): ICrossHttpClientResponse; overload; static;
    procedure _SetStatus(const AStatusCode: Integer; const AStatusText: string = '');

    property Connection: ICrossHttpClientConnection read GetConnection;
    property Header: THttpHeader read GetHeader;
    property Cookies: TResponseCookies read GetCookies;
    property Content: TStream read GetContent;
    property ContentType: string read GetContentType;
    property StatusCode: Integer read GetStatusCode;
    property StatusText: string read GetStatusText;
  end;

  TRequestQueue = TList<TRequestPack>;
  TClientConnections = TList<ICrossHttpClientConnection>;

  TServerDock = class
  private
    FClientSocket: TCrossHttpClientSocket;
    FProtocol, FHost: string;
    FPort: Word;
    FRequestQueue: TRequestQueue;
    FConnections: TClientConnections;
    FConnCount: Integer;
    FQueueLock, FConnsLock: ILock;

    procedure _LockQueue; inline;
    procedure _UnlockQueue; inline;

    procedure _LockConns; inline;
    procedure _UnlockConns; inline;
  public
    constructor Create(const AClientSocket: TCrossHttpClientSocket;
      const AProtocol, AHost: string; const APort: Word);
    destructor Destroy; override;

    procedure AddConnection(const AConnection: ICrossHttpClientConnection);
    procedure RemoveConnection(const AConnection: ICrossHttpClientConnection);
    function GetConnsCount: Integer;
    function GetIdleConnection: ICrossHttpClientConnection;

    procedure PushRequest(const ARequestPack: TRequestPack);
    function PopRequest(out ARequestPack: TRequestPack): Boolean;

    procedure ProcNext;

    // 所有请求方法的核心
    procedure DoRequest(const ARequestPack: TRequestPack); overload;
  end;

  TServerDockDict = TObjectDictionary<string, TServerDock>;

  TCrossHttpClientSocket = class(TCrossSslSocket, ICrossHttpClientSocket)
  private
    FHttpClient: TCrossHttpClient;
    FReUseConnection: Boolean;
    FCompressType: TCompressType;
    FServerDockDict: TServerDockDict;
    FServerDockLock: ILock;

    procedure _LockServerDock; inline;
    procedure _UnlockServerDock; inline;

    function _MakeServerDockKey(const AProtocol, AHost: string; const APort: Word): string;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word;
      out AServerDock: TServerDock): Boolean; overload;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word): TServerDock; overload;
  protected
    FMaxConnsPerServer: Integer;

    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
  public
    constructor Create(const AHttpClient: TCrossHttpClient;
      const AIoThreads, AMaxConnsPerServer: Integer; const ASsl, AReUseConnection: Boolean;
      const ACompressType: TCompressType = ctNone); reintroduce; virtual;
    destructor Destroy; override;

    // 所有请求方法的核心
    procedure DoRequest(const ARequestPack: TRequestPack); overload;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TCrossHttpChunkDataFunc;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload; virtual;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: Pointer;
      const ABodySize: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload; virtual;
  end;

  TCrossHttpClient = class(TInterfacedObject, ICrossHttpClient)
  private
    class var FDefaultIOThreads: Integer;
    class var FDefault: ICrossHttpClient;

    class constructor Create;
    class function GetDefault: ICrossHttpClient; static;
  private
    FIoThreads, FMaxConnsPerServer: Integer;
    FCompressType: TCompressType;
    FLock: ILock;
    FTimer: IEasyTimer;
    FHttpCli, FHttpsCli: ICrossHttpClientSocket;
    FHttpCliArr: TArray<ICrossHttpClientSocket>;
    FTimeout, FIdleout: Integer;

    procedure _ProcTimeout;
  protected
    procedure _Lock; inline;
    procedure _Unlock; inline;

    function CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket; virtual;

    function GetIdleout: Integer;
    function GetIoThreads: Integer;
    function GetMaxConnsPerServer: Integer;
    function GetTimeout: Integer;

    procedure SetIdleout(const AValue: Integer);
    procedure SetIoThreads(const AValue: Integer);
    procedure SetMaxConnsPerServer(const AValue: Integer);
    procedure SetTimeout(const AValue: Integer);
  public
    constructor Create(const AIoThreads, AMaxConnsPerServer: Integer;
      const ACompressType: TCompressType = ctNone); overload;
    constructor Create(const AIoThreads: Integer = 4;
      const ACompressType: TCompressType = ctNone); overload;
    destructor Destroy; override;

    procedure Prepare(const AProtocols: array of string);

    procedure CancelAll; virtual;

    {$region '裸数据请求'}
    // 所有请求方法的核心
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TCrossHttpChunkDataFunc;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload; virtual;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: Pointer; const ABodySize: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TBytes; const AOffset, ACount: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TBytes;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TStream; const AOffset, ACount: Int64;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TStream;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;
    {$endregion}

    // application/x-www-form-urlencoded 请求
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TFormUrlEncoded;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    // multipart/form-data 数据请求
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: THttpMultiPartFormData;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

    class property DefaultIOThreads: Integer read FDefaultIOThreads write FDefaultIOThreads;
    class property &Default: ICrossHttpClient read GetDefault;
  end;

const
  SND_BUF_SIZE = 32768;

implementation

{ TCrossHttpClientConnection }

constructor TCrossHttpClientConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AConnectCb);

  // 肯定是要发起请求才会新建连接
  // 所以直接将连接状态锁定
  // 避免被别的请求占用
  _BeginRequest;

  FWatch := TSimpleWatch.Create;
end;

procedure TCrossHttpClientConnection.DoRequest(const ARequestPack: TRequestPack;
  const ACallback: TCrossHttpResponseProc);
var
  LRequestObj: TCrossHttpClientRequest;
  LResponseObj: TCrossHttpClientResponse;
begin
  // 新建请求对象
  LRequestObj := TCrossHttpClientRequest.Create(Self);
  LRequestObj.FCompressType := (Owner as TCrossHttpClientSocket).FCompressType;

  // 新建响应对象
  LResponseObj := TCrossHttpClientResponse.Create(Self);

  // 将请求和响应对象放到连接中
  FRequest := LRequestObj;
  FResponse := LResponseObj;

  // 设置请求头
  if (ARequestPack.HttpHeaders <> nil) then
    LRequestObj.Header.Assign(ARequestPack.HttpHeaders);

  // 设置响应数据流
  LResponseObj._SetResponseStream(ARequestPack.ResponseStream);

  // 调用初始化函数
  if Assigned(ARequestPack.InitProc) then
    ARequestPack.InitProc(FRequest);

  // 发起请求
  if Assigned(ARequestPack.RequestBodyFunc) then
    LRequestObj.DoRequest(
      ARequestPack.Method,
      ARequestPack.Path,
      ARequestPack.RequestBodyFunc,
      ACallback)
  else
    LRequestObj.DoRequest(
      ARequestPack.Method,
      ARequestPack.Path,
      ARequestPack.RequestBody,
      ARequestPack.RequestBodySize,
      ACallback);
end;

procedure TCrossHttpClientConnection.DoRequest(
  const ARequestPack: TRequestPack);
begin
  DoRequest(ARequestPack, ARequestPack.Callback);
end;

function TCrossHttpClientConnection.GetHost: string;
begin
  Result := FHost;
end;

function TCrossHttpClientConnection.GetPort: Word;
begin
  Result := FPort;
end;

function TCrossHttpClientConnection.GetProtocol: string;
begin
  Result := FProtocol;
end;

function TCrossHttpClientConnection.GetRequestStatus: TRequestStatus;
begin
  Result := TRequestStatus(AtomicCmpExchange(FStatus, 0, 0));
end;

procedure TCrossHttpClientConnection.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
var
  LResponseObj: TCrossHttpClientResponse;
begin
  _UpdateWatch;

  LResponseObj := FResponse as TCrossHttpClientResponse;
  LResponseObj.ParseRecvData(ABuf, ALen);
end;

procedure TCrossHttpClientConnection._BeginRequest;
begin
  AtomicIncrement(FPending);
  _UpdateWatch;
end;

procedure TCrossHttpClientConnection._EndRequest;
begin
  AtomicDecrement(FPending);
end;

function TCrossHttpClientConnection._IsIdle: Boolean;
begin
  Result := (GetRequestStatus in [rsIdle])
    and (AtomicCmpExchange(FPending, 0, 0) = 0);
end;

function TCrossHttpClientConnection._IsIdleout: Boolean;
var
  LIdleout: Integer;
begin
  LIdleout := (Owner as TCrossHttpClientSocket).FHttpClient.FIdleout;
  if (LIdleout <= 0) then Exit(False);

  Result := (GetRequestStatus = rsIdle)
    and (FWatch.ElapsedMilliseconds div 1000 >= LIdleout);
end;

function TCrossHttpClientConnection._IsTimeout: Boolean;
var
  LTimeout: Integer;
begin
  LTimeout := (Owner as TCrossHttpClientSocket).FHttpClient.FTimeout;
  if (LTimeout <= 0) then Exit(False);

  Result := (GetRequestStatus in [rsSending, rsResponding])
    and (FWatch.ElapsedMilliseconds div 1000 >= LTimeout);
end;

function TCrossHttpClientConnection._SetRequestStatus(
  const AStatus: TRequestStatus): TRequestStatus;
begin
  Result := TRequestStatus(AtomicExchange(FStatus, Integer(AStatus)));
end;

procedure TCrossHttpClientConnection._UpdateWatch;
begin
  FWatch.Reset;
end;

{ TCrossHttpClientRequest }

constructor TCrossHttpClientRequest.Create(
  const AConnection: TCrossHttpClientConnection);
begin
  FConnection := AConnection;
  FHeader := THttpHeader.Create;
  FCookies := TRequestCookies.Create;

  FHttpVersion := hvHttp11;
end;

destructor TCrossHttpClientRequest.Destroy;
begin
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);

  inherited;
end;

procedure TCrossHttpClientRequest.DoRequest(const AMethod, APath: string;
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossHttpResponseProc);
begin
  FMethod := AMethod;
  FPath := APath;

  SendZCompress(AChunkSource, FCompressType, ACallback);
end;

procedure TCrossHttpClientRequest.DoRequest(const AMethod, APath: string;
  const ABody: Pointer; const ABodySize: NativeInt;
  const ACallback: TCrossHttpResponseProc);
begin
  FMethod := AMethod;
  FPath := APath;

  SendZCompress(ABody, ABodySize, FCompressType, ACallback);
end;

function TCrossHttpClientRequest.GetConnection: ICrossHttpClientConnection;
begin
  Result := FConnection;
end;

function TCrossHttpClientRequest.GetCookies: TRequestCookies;
begin
  Result := FCookies;
end;

function TCrossHttpClientRequest.GetHeader: THttpHeader;
begin
  Result := FHeader;
end;

procedure TCrossHttpClientRequest.SendNoCompress(
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossHttpResponseProc);
{
HTTP头\r\n\r\n
块尺寸\r\n
块内容
\r\n块尺寸\r\n
块内容
\r\n0\r\n\r\n
}
type
  TChunkState = (csHead, csBody, csDone);
const
  CHUNK_END: array [0..6] of Byte = (13, 10, 48, 13, 10, 13, 10); // \r\n0\r\n\r\n
var
  LHeaderBytes, LChunkHeader: TBytes;
  LChunked, LIsFirstChunk: Boolean;
  LChunkState: TChunkState;
  LChunkData: Pointer;
  LChunkSize: NativeInt;
begin
  // 先取出第一个数据块
  // 如果有数据才需要使用 chunked 方式发送数据
  if Assigned(AChunkSource) then
  begin
    LChunked := AChunkSource(@LChunkData, @LChunkSize)
      and (LChunkData <> nil)
      and (LChunkSize > 0);
  end else
    LChunked := False;

  LIsFirstChunk := True;
  LChunkState := csHead;

  _Send(
    // HEADER
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      LHeaderBytes := _CreateHeader(0, LChunked);

      AData^ := @LHeaderBytes[0];
      ADataSize^ := Length(LHeaderBytes);

      Result := (ADataSize^ > 0);
    end,
    // BODY
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      if not LChunked then Exit(False);

      case LChunkState of
        csHead:
          begin
            if LIsFirstChunk then
            begin
              LIsFirstChunk := False;
              LChunkHeader := [];
            end else
            begin
              LChunkData := nil;
              LChunkSize := 0;
              if not Assigned(AChunkSource)
                or not AChunkSource(@LChunkData, @LChunkSize)
                or (LChunkData = nil)
                or (LChunkSize <= 0) then
              begin
                LChunkState := csDone;

                AData^ := @CHUNK_END[0];
                ADataSize^ := Length(CHUNK_END);

                Result := (ADataSize^ > 0);

                Exit;
              end;

              LChunkHeader := [13, 10];
            end;

            // FPC编译器在Linux下有BUG(FPC 3.3.1)
            // 无法将函数返回的字节数组直接与其它字节数组使用加号拼接
            // 实际上使用加号拼接字节数组还有其它各种异常
            // 所以改用我的TArrayUtils.Concat进行拼接
            LChunkHeader := TArrayUtils<Byte>.Concat([
              LChunkHeader,
              TEncoding.ANSI.GetBytes(IntToHex(LChunkSize, 0)),
              [13, 10]
            ]);

            LChunkState := csBody;

            AData^ := @LChunkHeader[0];
            ADataSize^ := Length(LChunkHeader);

            Result := (ADataSize^ > 0);
          end;

        csBody:
          begin
            LChunkState := csHead;

            AData^ := LChunkData;
            ADataSize^ := LChunkSize;

            Result := (ADataSize^ > 0);
          end;

        csDone:
          begin
            Result := False;
          end;
      else
        Result := False;
      end;
    end,
    // CALLBACK
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      LHeaderBytes := nil;
      LChunkHeader := nil;

      if Assigned(ACallback) then
        ACallback(AResponse);
    end);
end;

procedure TCrossHttpClientRequest.SendNoCompress(const ABody: Pointer;
  const ABodySize: NativeInt; const ACallback: TCrossHttpResponseProc);
var
  P: PByte;
  LBodySize: NativeInt;
  LHeaderBytes: TBytes;
begin
  P := ABody;
  LBodySize := ABodySize;

  _Send(
    // HEADER
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      LHeaderBytes := _CreateHeader(LBodySize, False);

      AData^ := @LHeaderBytes[0];
      ADataSize^ := Length(LHeaderBytes);

      Result := (ADataSize^ > 0);
    end,
    // BODY
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      AData^ := P;
      ADataSize^ := Min(LBodySize, SND_BUF_SIZE);
      Result := (ADataSize^ > 0);

      if (LBodySize > SND_BUF_SIZE) then
      begin
        Inc(P, SND_BUF_SIZE);
        Dec(LBodySize, SND_BUF_SIZE);
      end else
      begin
        LBodySize := 0;
        P := nil;
      end;
    end,
    // CALLBACK
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      LHeaderBytes := nil;

      if Assigned(ACallback) then
        ACallback(AResponse);
    end);
end;

procedure TCrossHttpClientRequest.SendZCompress(
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ACompressType: TCompressType;
  const ACallback: TCrossHttpResponseProc);
{
  本方法实现了一边压缩一边发送数据, 所以可以支持无限大的分块数据的压缩发送,
  而不用占用太多的内存和CPU

  zlib参考手册: http://www.zlib.net/zlib_how.html
}
var
  LZStream: TZStreamRec;
  LZFlush: Integer;
  LZResult: Integer;
  LOutSize: Integer;
  LBuffer: TBytes;
begin
  if (ACompressType = ctNone) then
  begin
    SendNoCompress(AChunkSource, ACallback);
    Exit;
  end;

  // 压缩方式
  FHeader[HEADER_CONTENT_ENCODING] := ZLIB_CONTENT_ENCODING[ACompressType];

  SetLength(LBuffer, SND_BUF_SIZE);

  FillChar(LZStream, SizeOf(TZStreamRec), 0);
  LZResult := Z_OK;
  LZFlush := Z_NO_FLUSH;

  if (deflateInit2(LZStream, Z_DEFAULT_COMPRESSION,
    Z_DEFLATED, ZLIB_WINDOW_BITS[ACompressType], 8, Z_DEFAULT_STRATEGY) <> Z_OK) then
  begin
    (FConnection.FResponse as TCrossHttpClientResponse).TriggerResponseFailed(400, 'deflateInit2 failed');

    Exit;
  end;

  SendNoCompress(
    // CHUNK
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    var
      LChunkData: Pointer;
      LChunkSize: NativeInt;
    begin
      repeat
        // 当 deflate(LZStream, Z_FINISH) 被调用后
        // 返回 Z_STREAM_END 表示所有数据处理完毕
        if (LZResult = Z_STREAM_END) then
        begin
          AData^ := nil;
          ADataSize^ := 0;
          Exit(False);
        end;

        // 输入缓冲区已经处理完毕
        // 需要填入新数据
        if (LZStream.avail_in = 0) then
        begin
          LChunkData := nil;
          LChunkSize := 0;
          if not Assigned(AChunkSource)
            or not AChunkSource(@LChunkData, @LChunkSize)
            or (LChunkData = nil)
            or (LChunkSize <= 0) then
            LZFlush := Z_FINISH // 如果没有后续数据了, 准备结束压缩
          else
            LZFlush := Z_NO_FLUSH;

          // 压缩数据输入缓冲区
          LZStream.avail_in := LChunkSize;
          LZStream.next_in := LChunkData;
        end;

        // 压缩数据输出缓冲区
        LZStream.avail_out := SND_BUF_SIZE;
        LZStream.next_out := @LBuffer[0];

        // 进行压缩处理
        // 输入缓冲区数据可以大于输出缓冲区
        // 这种情况可以多次调用 deflate 分批压缩,
        // 直到 avail_in=0  表示当前输入缓冲区数据已压缩完毕
        LZResult := deflate(LZStream, LZFlush);

        // 压缩出错之后直接结束
        // 这里也可能会返回 Z_STREAM_END(1)
        // 返回 Z_STREAM_END(1) 这一次还是有数据的
        // 所以要到下次 CHUNK 函数被调用的时候再结束
        if (LZResult < 0) then
        begin
          AData^ := nil;
          ADataSize^ := 0;
          Exit(False);
        end;

        // 已压缩完成的数据大小
        LOutSize := SND_BUF_SIZE - LZStream.avail_out;
      until (LOutSize > 0);

      // 已压缩的数据
      AData^ := @LBuffer[0];
      ADataSize^ := LOutSize;

      Result := (ADataSize^ > 0);
    end,
    // CALLBACK
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      LBuffer := nil;
      deflateEnd(LZStream);

      if Assigned(ACallback) then
        ACallback(AResponse);
    end);
end;

procedure TCrossHttpClientRequest.SendZCompress(const ABody: Pointer;
  const ABodySize: NativeInt; const ACompressType: TCompressType;
  const ACallback: TCrossHttpResponseProc);
var
  P: PByte;
  LBodySize: NativeInt;
begin
  if (ACompressType = ctNone) then
  begin
    SendNoCompress(ABody, ABodySize, ACallback);
    Exit;
  end;

  P := ABody;
  LBodySize := ABodySize;

  SendZCompress(
    // CHUNK
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      AData^ := P;
      ADataSize^ := Min(LBodySize, SND_BUF_SIZE);
      Result := (ADataSize^ > 0);

      if (LBodySize > SND_BUF_SIZE) then
      begin
        Inc(P, SND_BUF_SIZE);
        Dec(LBodySize, SND_BUF_SIZE);
      end else
      begin
        LBodySize := 0;
        P := nil;
      end;
    end,
    ACompressType,
    ACallback);
end;

function TCrossHttpClientRequest._CreateHeader(const ABodySize: Int64;
  AChunked: Boolean): TBytes;
var
  LHeaderStr, LCookieStr: string;
begin
  if (FHeader[HEADER_CACHE_CONTROL] = '') then
    FHeader[HEADER_CACHE_CONTROL] := 'no-cache';

  if (FHeader[HEADER_PRAGMA] = '') then
    FHeader[HEADER_PRAGMA] := 'no-cache';

  if (FHeader[HEADER_CONNECTION] = '') then
    FHeader[HEADER_CONNECTION] := 'keep-alive';

  // 设置数据格式
  if (FHeader[HEADER_CONTENT_TYPE] = '')
    and (AChunked or (ABodySize > 0)) then
    FHeader[HEADER_CONTENT_TYPE] := TMediaType.APPLICATION_OCTET_STREAM;

  // 设置主机信息
  if (FHeader[HEADER_HOST] = '') then
  begin
    if (not FConnection.Ssl and (FConnection.FPort = HTTP_DEFAULT_PORT))
      or (FConnection.Ssl and (FConnection.FPort = HTTPS_DEFAULT_PORT)) then
      FHeader[HEADER_HOST] := FConnection.FHost
    else
      FHeader[HEADER_HOST] := FConnection.FHost + ':' + FConnection.FPort.ToString;
  end;

  // 设置接受的数据传输方式
  if AChunked then
    FHeader[HEADER_TRANSFER_ENCODING] := 'chunked'
  else if (ABodySize > 0) then
    FHeader[HEADER_CONTENT_LENGTH] := ABodySize.ToString;

  // 设置接受的数据编码方式
  if (FHeader[HEADER_ACCEPT_ENCODING] = '') then
    FHeader[HEADER_ACCEPT_ENCODING] := 'gzip, deflate';

  // 设置 Cookies
  LCookieStr := FCookies.Encode;
  if (LCookieStr <> '') then
    FHeader[HEADER_COOKIE] := LCookieStr;

  if (FHeader[HEADER_CROSS_HTTP_CLIENT] = '') then
    FHeader[HEADER_CROSS_HTTP_CLIENT] := CROSS_HTTP_CLIENT_NAME;

  // 设置请求行
  LHeaderStr := FMethod + ' '
    + TCrossHttpUtils.UrlEncode(FPath, ['/', '?', '=', '&']) + ' '
    + HTTP_VER_STR[FHttpVersion] + CRLF;

  LHeaderStr := LHeaderStr + FHeader.Encode;

  Result := TEncoding.ANSI.GetBytes(LHeaderStr);
end;

procedure TCrossHttpClientRequest._Send(const ASource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpConnection: ICrossHttpClientConnection;
  LResponse: ICrossHttpClientResponse;
  LResponseObj: TCrossHttpClientResponse;
  LSender: TCrossConnectionCallback;
begin
  LHttpConnection := FConnection;
  LResponse := FConnection.FResponse;
  LResponseObj := LResponse as TCrossHttpClientResponse;
  LResponseObj.FCallback := ACallback;

  // 标记正在发送请求
  FConnection._SetRequestStatus(rsSending);

  // 更新计时器
  FConnection._UpdateWatch;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
    begin
      // 发送失败
      if not ASuccess then
      begin
        LHttpConnection.Close;
        LResponseObj.TriggerResponseFailed(400, 'Send failed');
        LHttpConnection := nil;
        LResponse := nil;
        LSender := nil;

        Exit;
      end;

      // 更新计时器
      FConnection._UpdateWatch;

      LData := nil;
      LCount := 0;
      if not Assigned(ASource)
        or not ASource(@LData, @LCount)
        or (LData = nil)
        or (LCount <= 0) then
      begin
        // 标记正在等待响应
        FConnection._SetRequestStatus(rsResponding);
        LHttpConnection := nil;
        LResponse := nil;
        LSender := nil;

        Exit;
      end;

      LHttpConnection.SendBuf(LData^, LCount, LSender);
    end;

  LSender(LHttpConnection, True);
end;

procedure TCrossHttpClientRequest._Send(const AHeaderSource,
  ABodySource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossHttpResponseProc);
var
  LHeaderDone: Boolean;
begin
  LHeaderDone := False;

  _Send(
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      if not LHeaderDone then
      begin
        LHeaderDone := True;
        Result := Assigned(AHeaderSource) and AHeaderSource(AData, ADataSize);
      end else
      begin
        Result := Assigned(ABodySource) and ABodySource(AData, ADataSize);
      end;
    end,
    ACallback);
end;

{ TCrossHttpClientResponse }

constructor TCrossHttpClientResponse.Create(
  const AConnection: TCrossHttpClientConnection);
begin
  FConnection := AConnection;

  FHeader := THttpHeader.Create;
  FCookies := TResponseCookies.Create;
  FLock := TLock.Create;

  FHttpParser := TCrossHttpParser.Create;
  FHttpParser.OnHeaderData := _OnHeaderData;
  FHttpParser.OnGetHeaderValue := _OnGetHeaderValue;
  FHttpParser.OnBodyBegin := _OnBodyBegin;
  FHttpParser.OnBodyData := _OnBodyData;
  FHttpParser.OnBodyEnd := _OnBodyEnd;
  FHttpParser.OnParseSuccess := _OnParseSuccess;
  FHttpParser.OnParseFailed := _OnParseFailed;
end;

class function TCrossHttpClientResponse.Create(const AStatusCode: Integer;
  const AStatusText: string): ICrossHttpClientResponse;
var
  LResponseObj: TCrossHttpClientResponse;
begin
  LResponseObj := TCrossHttpClientResponse.Create(nil);
  LResponseObj._SetStatus(AStatusCode, AStatusText);
  Result := LResponseObj;
end;

destructor TCrossHttpClientResponse.Destroy;
begin
  if Assigned(FCallback) then
    TriggerResponseFailed(400, 'Connection lost');

  FreeAndNil(FHeader);
  FreeAndNil(FCookies);
  FreeAndNil(FHttpParser);

  if FNeedFreeResponseBodyStream and (FResponseBodyStream <> nil) then
    FreeAndNil(FResponseBodyStream);

  inherited;
end;

function TCrossHttpClientResponse.GetCookies: TResponseCookies;
begin
  Result := FCookies;
end;

function TCrossHttpClientResponse.GetHeader: THttpHeader;
begin
  Result := FHeader;
end;

function TCrossHttpClientResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function TCrossHttpClientResponse.GetStatusText: string;
begin
  Result := FStatusText;
end;

function TCrossHttpClientResponse.GetConnection: ICrossHttpClientConnection;
begin
  Result := FConnection;
end;

function TCrossHttpClientResponse.GetContent: TStream;
begin
  Result := FResponseBodyStream;
end;

function TCrossHttpClientResponse.GetContentType: string;
begin
  Result := FContentType;
end;

function TCrossHttpClientResponse.ParseHeader(const ADataPtr: Pointer;
  const ADataSize: Integer): Boolean;
var
  LResponseFirstLine, LResponseHeader: string;
  I, J: Integer;
  LHeader: TNameValue;
begin
  {
  HTTP/1.1 200 OK
  Content-Type: application/json;charset=utf-8
  Content-Encoding: gzip
  Connection: keep-alive
  Transfer-Encoding: chunked
  }
  {
  HTTP/1.1 200 OK
  Content-Type: text/plain
  Accept-Ranges: bytes
  Content-Encoding: gzip
  Connection: keep-alive
  Transfer-Encoding: chunked
  }
  SetString(FRawResponseHeader, MarshaledAString(ADataPtr), ADataSize);
  I := FRawResponseHeader.IndexOf(#13#10);
  // 第一行是响应状态
  // HTTP/1.1 200 OK
  LResponseFirstLine := FRawResponseHeader.Substring(0, I);
  // 第二行起是请求头
  LResponseHeader := FRawResponseHeader.Substring(I + 2);
  // 解析请求头
  FHeader.Decode(LResponseHeader);

  // HTTP版本(HTTP/1.0 HTTP/1.1)
  I := LResponseFirstLine.IndexOf(' ');
  FHttpVer := LResponseFirstLine.Substring(0, I).ToUpper;

  // 响应状态码(200 400 404)
  J := LResponseFirstLine.IndexOf(' ', I + 1);
  FStatusCode := StrToIntDef(LResponseFirstLine.Substring(I + 1, J - I - 1), 0);

  // 响应状态文本(OK)
  FStatusText := LResponseFirstLine.SubString(J + 1);

  // 解析 Set-Cookie
  for LHeader in FHeader do
  begin
    if TStrUtils.SameText(LHeader.Name, HEADER_SETCOOKIE) then
      FCookies.Add(TResponseCookie.Create(LHeader.Value, FConnection.FHost));
  end;

  FContentType := FHeader[HEADER_CONTENT_TYPE];
  FContentLength := StrToInt64Def(FHeader[HEADER_CONTENT_LENGTH], -1);

  // 数据的编码方式
  // 只有一种编码方式: chunked
  // 如果 Transfer-Encoding 不存在于 Header 中, 则数据是连续的, 不采用分块编码
  // 理论上 Transfer-Encoding 和 Content-Length 只应该存在其中一个
  FTransferEncoding := FHeader[HEADER_TRANSFER_ENCODING];

  FIsChunked := TStrUtils.SameText(FTransferEncoding, 'chunked');

  // 数据的压缩方式
  // 可能的值为: gzip deflate br 其中之一
  // br: Brotli压缩算法, Brotli通常比gzip和deflate更高效
  FContentEncoding := FHeader[HEADER_CONTENT_ENCODING];

  Result := True;
end;

procedure TCrossHttpClientResponse.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
begin
  FHttpParser.Decode(ABuf, ALen);
end;

procedure TCrossHttpClientResponse.TriggerResponseData(const ABuf: Pointer;
  const ALen: Integer);
begin
  if (FResponseBodyStream = nil)
    or (ABuf = nil) or (ALen <= 0) then Exit;

  FResponseBodyStream.Write(ABuf^, ALen);
end;

procedure TCrossHttpClientResponse.TriggerResponseDataBegin;
begin
  if (FResponseBodyStream = nil) then
  begin
    FResponseBodyStream := TBytesStream.Create;
    FNeedFreeResponseBodyStream := True;
  end;
  FResponseBodyStream.Size := 0;
end;

procedure TCrossHttpClientResponse.TriggerResponseDataEnd;
begin
  if (FResponseBodyStream <> nil) and (FResponseBodyStream.Size > 0) then
    FResponseBodyStream.Position := 0;
end;

procedure TCrossHttpClientResponse.TriggerResponseFailed(const AStatusCode: Integer; const AStatusText: string);
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
begin
  _Lock;
  try
    LCallback := FCallback;
    FCallback := nil;

    // 只有还没收到响应码的情况(FStatusCode=0), 才允许修改
    if (FStatusCode = 0) then
      _SetStatus(AStatusCode, AStatusText);

    FConnection._SetRequestStatus(rsRespondFailed);
    FConnection.Close;
  finally
    _Unlock;
    FConnection._EndRequest;
  end;

  if Assigned(LCallback) then
  try
    LResponse := Self;
    LCallback(LResponse);
  except
  end;
end;

procedure TCrossHttpClientResponse.TriggerResponseSuccess;
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
begin
  _Lock;
  try
    // 只有在等待响应状态的情况才应该触发完成响应回调
    // 因为有可能响应完成的数据在超时后才到来, 这时候请求状态已经被置为超时
    // 不应该再触发完成回调
    if (FConnection.RequestStatus <> rsResponding) then Exit;

    LCallback := FCallback;
    FCallback := nil;

    FConnection._UpdateWatch;
    FConnection._SetRequestStatus(rsIdle);
  finally
    _Unlock;
    FConnection._EndRequest;
  end;

  if Assigned(LCallback) then
  try
    LResponse := Self;
    LCallback(LResponse);
  except
  end;
end;

procedure TCrossHttpClientResponse.TriggerResponseTimeout;
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
begin
  _Lock;
  try
    LCallback := FCallback;
    FCallback := nil;

    // 既然都判定超时了, 那不管收到了什么数据都直接丢弃
    if (FResponseBodyStream <> nil) and (FResponseBodyStream.Size > 0) then
      FResponseBodyStream.Size := 0;

    // 408 = Request Time-out
    _SetStatus(408);

    FConnection._SetRequestStatus(rsRespondTimeout);
    FConnection.Close;
  finally
    _Unlock;
    FConnection._EndRequest;
  end;

  if Assigned(LCallback) then
  try
    LResponse := Self;
    LCallback(LResponse);
  except
  end;
end;

procedure TCrossHttpClientResponse._Lock;
begin
  FLock.Enter;
end;

procedure TCrossHttpClientResponse._OnBodyBegin;
begin
  TriggerResponseDataBegin;
end;

procedure TCrossHttpClientResponse._OnBodyData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  TriggerResponseData(ADataPtr, ADataSize);
end;

procedure TCrossHttpClientResponse._OnBodyEnd;
begin
  TriggerResponseDataEnd;
end;

function TCrossHttpClientResponse._OnGetHeaderValue(const AHeaderName: string;
  out AHeaderValue: string): Boolean;
begin
  Result := FHeader.GetParamValue(AHeaderName, AHeaderValue);
end;

procedure TCrossHttpClientResponse._OnHeaderData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  ParseHeader(ADataPtr, ADataSize);
end;

procedure TCrossHttpClientResponse._OnParseFailed(const ACode: Integer;
  const AError: string);
begin
  TriggerResponseFailed(ACode, AError);
end;

procedure TCrossHttpClientResponse._OnParseSuccess;
begin
  TriggerResponseSuccess;
end;

procedure TCrossHttpClientResponse._SetResponseStream(const AValue: TStream);
begin
  if (FResponseBodyStream = AValue) then Exit;

  if FNeedFreeResponseBodyStream and (FResponseBodyStream <> nil) then
    FreeAndNil(FResponseBodyStream);

  FResponseBodyStream := AValue;
  FNeedFreeResponseBodyStream := False;
end;

procedure TCrossHttpClientResponse._SetStatus(const AStatusCode: Integer;
  const AStatusText: string);
begin
  FStatusCode := AStatusCode;
  if (AStatusText <> '') then
    FStatusText := AStatusText
  else
    FStatusText := TCrossHttpUtils.GetHttpStatusText(AStatusCode);
end;

procedure TCrossHttpClientResponse._Unlock;
begin
  FLock.Leave;
end;

{ TCrossHttpClientSocket }

constructor TCrossHttpClientSocket.Create(const AHttpClient: TCrossHttpClient;
  const AIoThreads, AMaxConnsPerServer: Integer; const ASsl, AReUseConnection: Boolean;
  const ACompressType: TCompressType);
begin
  FHttpClient := AHttpClient;
  FReUseConnection := AReUseConnection;
  FMaxConnsPerServer := AMaxConnsPerServer;
  FCompressType := ACompressType;

  inherited Create(AIoThreads, ASsl);

  FServerDockDict := TServerDockDict.Create([doOwnsValues]);
  FServerDockLock := TLock.Create;
end;

function TCrossHttpClientSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossHttpClientConnection.Create(AOwner, AClientSocket, AConnectType, AConnectCb);
end;

destructor TCrossHttpClientSocket.Destroy;
begin
  FreeAndNil(FServerDockDict);
  inherited;
end;

procedure TCrossHttpClientSocket.DoRequest(const ARequestPack: TRequestPack);
var
  LServerDock: TServerDock;
begin
  _LockServerDock;
  try
    LServerDock := _GetServerDock(ARequestPack.Protocol, ARequestPack.Host, ARequestPack.Port);

    LServerDock.DoRequest(ARequestPack);
  finally
    _UnlockServerDock;
  end;
end;

procedure TCrossHttpClientSocket.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream; const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LRequestPack: TRequestPack;
begin
  LRequestPack := TRequestPack.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    AResponseStream,
    AInitProc,
    ACallback);
  DoRequest(LRequestPack);
end;

procedure TCrossHttpClientSocket.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LRequestPack: TRequestPack;
begin
  LRequestPack := TRequestPack.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    ABodySize,
    AResponseStream,
    AInitProc,
    ACallback);
  DoRequest(LRequestPack);
end;

procedure TCrossHttpClientSocket.LogicDisconnected(
  const AConnection: ICrossConnection);
var
  LServerDock: TServerDock;
  LConn: ICrossHttpClientConnection;
  LConnObj: TCrossHttpClientConnection;
  LResponseObj: TCrossHttpClientResponse;
begin
  LConn := AConnection as ICrossHttpClientConnection;
  LConnObj := LConn as TCrossHttpClientConnection;

  // 在等待响应的过程中连接被断开了
  // 需要触发回调函数
  if (LConnObj.FResponse <> nil) then
  begin
    LResponseObj := LConnObj.FResponse as TCrossHttpClientResponse;
    if Assigned(LResponseObj.FCallback) then
      LResponseObj.TriggerResponseFailed(400, 'Connection lost');
  end;

  _LockServerDock;
  try
    if _GetServerDock(
      LConnObj.Protocol,
      LConnObj.Host,
      LConnObj.Port,
      LServerDock) then
      LServerDock.RemoveConnection(LConn);
  finally
    _UnlockServerDock;
  end;
end;

procedure TCrossHttpClientSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnObj: TCrossHttpClientConnection;
  LBuf: Pointer;
  LLen: Integer;
begin
  LConnObj := AConnection as TCrossHttpClientConnection;
  LBuf := ABuf;
  LLen := ALen;

  while (LLen > 0) do
    LConnObj.ParseRecvData(LBuf, LLen);
end;

function TCrossHttpClientSocket._GetServerDock(const AProtocol, AHost: string;
  const APort: Word): TServerDock;
var
  LKey: string;
begin
  LKey := _MakeServerDockKey(AProtocol, AHost, APort);
  if not FServerDockDict.TryGetValue(LKey, Result) then
  begin
    Result := TServerDock.Create(Self, AProtocol, AHost, APort);
    FServerDockDict.Add(LKey, Result);
  end;
end;

function TCrossHttpClientSocket._GetServerDock(const AProtocol, AHost: string;
  const APort: Word; out AServerDock: TServerDock): Boolean;
var
  LKey: string;
begin
  LKey := _MakeServerDockKey(AProtocol, AHost, APort);
  Result := FServerDockDict.TryGetValue(LKey, AServerDock);
end;

procedure TCrossHttpClientSocket._LockServerDock;
begin
  FServerDockLock.Enter;
end;

function TCrossHttpClientSocket._MakeServerDockKey(const AProtocol,
  AHost: string; const APort: Word): string;
begin
  Result := TStrUtils.Format('%s://%s:%d', [
    AProtocol, AHost, APort
  ]);
end;

procedure TCrossHttpClientSocket._UnlockServerDock;
begin
  FServerDockLock.Leave;
end;

{ TCrossHttpClient }

procedure TCrossHttpClient.CancelAll;
var
  LHttpCli: ICrossHttpClientSocket;
begin
  for LHttpCli in FHttpCliArr do
    LHttpCli.CloseAll;
end;

constructor TCrossHttpClient.Create(const AIoThreads,
  AMaxConnsPerServer: Integer; const ACompressType: TCompressType);
begin
  // 暂时超时时间设置为2分钟
  // 实际连接每收到一个数据包, 都会更新计时器
  // 所以不用担心2分钟无法完成大数据的收取
  // 一个正常的响应, 如果数据很大会被拆分成很多小的数据包发回
  // 每个小的数据包不太可能2分钟还传不完, 如果真出现2分钟传不完一个小数据包的情况
  // 那是真应该判定超时了, 因为这个网络环境确实太恶劣了, 基本也无法完成正常的网络交互
  FTimeout := 120;

  // 空闲超时默认设置为10秒
  FIdleout := 10;

  FIoThreads := AIoThreads;
  FMaxConnsPerServer := AMaxConnsPerServer;
  FCompressType := ACompressType;
  FLock := TLock.Create;
  FHttpCliArr := [];

  FTimer := TEasyTimer.Create('TCrossHttpClient.Timeout',
    procedure
    begin
      _ProcTimeout;
    end,
    5000);
end;

constructor TCrossHttpClient.Create(const AIoThreads: Integer;
  const ACompressType: TCompressType);
begin
  Create(AIoThreads, 2, ACompressType);
end;

destructor TCrossHttpClient.Destroy;
begin
  if (FHttpCli <> nil) then
    FHttpCli.StopLoop;

  if (FHttpsCli <> nil) then
    FHttpsCli.StopLoop;

  inherited;
end;

class constructor TCrossHttpClient.Create;
begin
  FDefaultIOThreads := 4;
end;

function TCrossHttpClient.CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket;
begin
  if TStrUtils.SameText(AProtocol, HTTP) then
  begin
    if (FHttpCli = nil) then
    begin
      FHttpCli := TCrossHttpClientSocket.Create(Self, FIoThreads, FMaxConnsPerServer, False, True, FCompressType);
      FHttpCliArr := FHttpCliArr + [FHttpCli];
    end;

    Result := FHttpCli;
  end else
  if TStrUtils.SameText(AProtocol, HTTPS) then
  begin
    if (FHttpsCli = nil) then
    begin
      FHttpsCli := TCrossHttpClientSocket.Create(Self, FIoThreads, FMaxConnsPerServer, True, True, FCompressType);
      FHttpCliArr := FHttpCliArr + [FHttpsCli];
    end;

    Result := FHttpsCli;
  end else
    raise ECrossHttpClient.CreateFmt('Invalid protocol:%s', [AProtocol]);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBody: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpCli: ICrossHttpClientSocket;
  LRequestPack: TRequestPack;
begin
  LRequestPack := TRequestPack.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    AResponseStream,
    AInitProc,
    ACallback);

  // 根据协议获取HttpCli对象
  _Lock;
  try
    LHttpCli := CreateHttpCli(LRequestPack.Protocol);
  finally
    _Unlock;
  end;

  LHttpCli.DoRequest(LRequestPack);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpCli: ICrossHttpClientSocket;
  LRequestPack: TRequestPack;
begin
  LRequestPack := TRequestPack.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    ABodySize,
    AResponseStream,
    AInitProc,
    ACallback);

  // 根据协议获取HttpCli对象
  _Lock;
  try
    LHttpCli := CreateHttpCli(LRequestPack.Protocol);
  finally
    _Unlock;
  end;

  LHttpCli.DoRequest(LRequestPack);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: TBytes; const AOffset,
  ACount: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LBody: TBytes;
  LOffset, LCount: NativeInt;
begin
  // 增加其引用计数
  LBody := ARequestBody;

  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(Length(LBody), LOffset, LCount);

  DoRequest(AMethod, AUrl, AHttpHeaders,
    Pointer(PByte(LBody) + LOffset), LCount,
    AResponseStream,
    AInitProc,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      // 减少引用计数
      LBody := nil;

      if Assigned(ACallback) then
        ACallback(AResponse);
    end);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: TBytes;
  const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  DoRequest(AMethod, AUrl, AHttpHeaders,
    ARequestBody, 0, Length(ARequestBody),
    AResponseStream,
    AInitProc,
    ACallback);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: TStream; const AOffset,
  ACount: Int64; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LOffset, LCount: Int64;
  LBody: TStream;
  LBuffer: TBytes;
begin
  if (ARequestBody <> nil) then
  begin
    LOffset := AOffset;
    LCount := ACount;
    TCrossHttpUtils.AdjustOffsetCount(ARequestBody.Size, LOffset, LCount);

    if (ARequestBody is TCustomMemoryStream) then
    begin
      DoRequest(AMethod, AUrl, AHttpHeaders,
        (PByte(TCustomMemoryStream(ARequestBody).Memory) + LOffset), LCount,
        AResponseStream,
        AInitProc,
        ACallback);

      Exit;
    end;

    LBody := ARequestBody;
    LBody.Position := LOffset;

    SetLength(LBuffer, SND_BUF_SIZE);
  end else
    LCount := 0;

  DoRequest(AMethod, AUrl, AHttpHeaders,
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      if (LCount <= 0) then
      begin
        LBuffer := nil;
        Exit(False);
      end;

      AData^ := @LBuffer[0];
      ACount^ := LBody.Read(LBuffer[0], Min(LCount, SND_BUF_SIZE));

      Result := (ACount^ > 0);

      if Result then
        Dec(LCount, ACount^);
    end,
    AResponseStream,
    AInitProc,
    ACallback);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody,
  AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  DoRequest(AMethod, AUrl, AHttpHeaders,
    ARequestBody, 0, 0,
    AResponseStream,
    AInitProc,
    ACallback);
end;

procedure TCrossHttpClient._Lock;
begin
  FLock.Enter;
end;

procedure TCrossHttpClient._ProcTimeout;
  procedure _Proc(const AHttpCli: ICrossHttpClientSocket);
  var
    LConns: TCrossConnections;
    LConn: ICrossConnection;
    LHttpConn: ICrossHttpClientConnection;
    LHttpConnObj: TCrossHttpClientConnection;
    LTimeoutArr, LIdleoutArr: TArray<ICrossHttpClientConnection>;
    {$IFDEF DEBUG}
    LIdleCnt, LSendingCnt, LRespondingCnt, LRespondFailedCnt, LRespondTimeoutCnt: Integer;
    LFirstIdleConn: TCrossHttpClientConnection;
    {$ENDIF}
  begin
    LTimeoutArr := [];
    LIdleoutArr := [];

    LConns := AHttpCli.LockConnections;
    try
      {$IFDEF DEBUG}
      LIdleCnt := 0;
      LSendingCnt := 0;
      LRespondingCnt := 0;
      LRespondFailedCnt := 0;
      LRespondTimeoutCnt := 0;
      LFirstIdleConn := nil;
      {$ENDIF}

      for LConn in LConns.Values do
      begin
        if not LConn.IsClosed then
        begin
          LHttpConn := LConn as ICrossHttpClientConnection;
          LHttpConnObj := LHttpConn as TCrossHttpClientConnection;

          if LHttpConnObj._IsTimeout then
            LTimeoutArr := LTimeoutArr + [LHttpConn]
          else if LHttpConnObj._IsIdleout then
            LIdleoutArr := LIdleoutArr + [LHttpConn];

          {$IFDEF DEBUG}
          case LHttpConn.RequestStatus of
            rsIdle:
              begin
                Inc(LIdleCnt);
                if (LFirstIdleConn = nil) then
                  LFirstIdleConn := LHttpConnObj;
              end;

            rsSending: Inc(LSendingCnt);
            rsResponding: Inc(LRespondingCnt);
            rsRespondFailed: Inc(LRespondFailedCnt);
            rsRespondTimeout: Inc(LRespondTimeoutCnt);
          end;
          {$ENDIF}
        end;
      end;
    finally
      AHttpCli.UnlockConnections;
    end;

    {$IFDEF DEBUG}
    _Log(
      'http-client, conn:%d, timeout:%d, idleout:%d' +
      ', idle:%d, sending:%d, responding:%d, respond-failed:%d, respond-timeout:%d', [
      LConns.Count, Length(LTimeoutArr), Length(LIdleoutArr),
      LIdleCnt, LSendingCnt, LRespondingCnt, LRespondFailedCnt, LRespondTimeoutCnt
    ]);

    if (LFirstIdleConn <> nil) then
    begin
      _Log('first idle conn [%d] idle watch: %d ms / start-time: %s', [
        LFirstIdleConn.UID,
        LFirstIdleConn.FWatch.ElapsedMilliseconds,
        FormatDateTime('hh":"nn":"ss.zzz', LFirstIdleConn.FWatch.LastTime)
      ]);
    end;
    {$ENDIF}

    for LHttpConn in LTimeoutArr do
    begin
      LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
      (LHttpConnObj.FResponse as TCrossHttpClientResponse).TriggerResponseTimeout;
    end;

    for LHttpConn in LIdleoutArr do
      LHttpConn.Close;
  end;
var
  LHttpCli: ICrossHttpClientSocket;
begin
  for LHttpCli in FHttpCliArr do
    _Proc(LHttpCli);
end;

procedure TCrossHttpClient._Unlock;
begin
  FLock.Leave;
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: TFormUrlEncoded;
  const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LReqBytes: TBytes;
begin
  if (ARequestBody <> nil) then
    LReqBytes := TEncoding.ANSI.GetBytes(ARequestBody.Encode)
  else
    LReqBytes := nil;
  DoRequest(AMethod, AUrl, AHttpHeaders,
    LReqBytes,
    AResponseStream,
    procedure(const ARequest: ICrossHttpClientRequest)
    begin
      if Assigned(AInitProc) then
        AInitProc(ARequest);

      ARequest.Header[HEADER_CONTENT_TYPE] := TMediaType.APPLICATION_FORM_URLENCODED_TYPE;
    end,
    ACallback);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: THttpMultiPartFormData;
  const AResponseStream: TStream; const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpMultiPartFormData: TStream;
begin
  if (ARequestBody <> nil) then
    LHttpMultiPartFormData := THttpMultiPartFormStream.Create(ARequestBody)
  else
    LHttpMultiPartFormData := nil;

  DoRequest(AMethod, AUrl, AHttpHeaders,
    LHttpMultiPartFormData,
    AResponseStream,
    procedure(const ARequest: ICrossHttpClientRequest)
    begin
      if Assigned(AInitProc) then
        AInitProc(ARequest);

      if (ARequestBody <> nil) then
        ARequest.Header[HEADER_CONTENT_TYPE] := TMediaType.MULTIPART_FORM_DATA + '; boundary=' + ARequestBody.Boundary;
    end,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      if (LHttpMultiPartFormData <> nil) then
        FreeAndNil(LHttpMultiPartFormData);

      if Assigned(ACallback) then
        ACallback(AResponse);
    end);
end;

class function TCrossHttpClient.GetDefault: ICrossHttpClient;
var
  LDefault: ICrossHttpClient;
begin
  if (FDefault = nil) then
  begin
    LDefault := TCrossHttpClient.Create(FDefaultIOThreads);
    if AtomicCmpExchange(Pointer(FDefault), Pointer(LDefault), nil) <> nil then
      LDefault := nil
    else
      FDefault._AddRef;
  end;
  Result := FDefault;
end;

function TCrossHttpClient.GetIdleout: Integer;
begin
  Result := FIdleout;
end;

function TCrossHttpClient.GetIoThreads: Integer;
begin
  Result := FIoThreads;
end;

function TCrossHttpClient.GetMaxConnsPerServer: Integer;
begin
  Result := FMaxConnsPerServer;
end;

function TCrossHttpClient.GetTimeout: Integer;
begin
  Result := FTimeout;
end;

procedure TCrossHttpClient.Prepare(const AProtocols: array of string);
var
  LProtocol: string;
begin
  _Lock;
  try
    for LProtocol in AProtocols do
      CreateHttpCli(LProtocol);
  finally
    _Unlock;
  end;
end;

procedure TCrossHttpClient.SetIdleout(const AValue: Integer);
begin
  FIdleout := AValue;
end;

procedure TCrossHttpClient.SetIoThreads(const AValue: Integer);
begin
  FIoThreads := AValue;
end;

procedure TCrossHttpClient.SetMaxConnsPerServer(const AValue: Integer);
begin
  FMaxConnsPerServer := AValue;
end;

procedure TCrossHttpClient.SetTimeout(const AValue: Integer);
begin
  FTimeout := AValue;
end;

{ TRequestPack }

constructor TRequestPack.Create(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBodyFunc: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream; const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  Method := AMethod;
  Url := AUrl;
  HttpHeaders := AHttpHeaders;
  RequestBodyFunc := ARequestBodyFunc;
  RequestBody := nil;
  RequestBodySize := 0;
  ResponseStream := AResponseStream;
  InitProc := AInitProc;
  Callback := ACallback;

  _ParseUrl;
end;

constructor TRequestPack.Create(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  Method := AMethod;
  Url := AUrl;
  HttpHeaders := AHttpHeaders;
  RequestBodyFunc := nil;
  RequestBody := ARequestBody;
  RequestBodySize := ABodySize;
  ResponseStream := AResponseStream;
  InitProc := AInitProc;
  Callback := ACallback;

  _ParseUrl;
end;

procedure TRequestPack._ParseUrl;
begin
  if not TCrossHttpUtils.ExtractUrl(Url, Protocol, Host, Port, Path) then
  begin
    if Assigned(Callback) then
      Callback(TCrossHttpClientResponse.Create(400, 'Invalid URL'));

    Abort;
  end;
end;

{ TServerDock }

procedure TServerDock.AddConnection(
  const AConnection: ICrossHttpClientConnection);
begin
  _LockConns;
  try
    FConnections.Add(AConnection);
  finally
    _UnlockConns;
  end;
end;

constructor TServerDock.Create(const AClientSocket: TCrossHttpClientSocket;
  const AProtocol, AHost: string; const APort: Word);
begin
  FClientSocket := AClientSocket;
  FProtocol := AProtocol;
  FHost := AHost;
  FPort := APort;

  FRequestQueue := TRequestQueue.Create;
  FConnections := TClientConnections.Create;

  FQueueLock := TLock.Create;
  FConnsLock := TLock.Create;
end;

destructor TServerDock.Destroy;
begin
  FreeAndNil(FRequestQueue);
  FreeAndNil(FConnections);

  inherited;
end;

procedure TServerDock.DoRequest(const ARequestPack: TRequestPack);
var
  LHttpConn: ICrossHttpClientConnection;
  LHttpConnObj: TCrossHttpClientConnection;
  LNewCallback: TCrossHttpResponseProc;
  LServerDock: TServerDock;
begin
  LNewCallback :=
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      if Assigned(ARequestPack.Callback) then
        ARequestPack.Callback(AResponse);

      ProcNext;
    end;

  LHttpConn := nil;

  // 优先使用空闲连接
  if FClientSocket.FReUseConnection then
    LHttpConn := GetIdleConnection;

  if (LHttpConn <> nil) then
  begin
    LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
    LHttpConnObj.DoRequest(ARequestPack, LNewCallback);

    LNewCallback := nil;

    Exit;
  end;

  _LockQueue;
  try
    // 没有空闲连接并且连接数未超过限定
    // 建立新连接
    if (FClientSocket.FMaxConnsPerServer <= 0)
      or (AtomicCmpExchange(FConnCount, 0, 0) < FClientSocket.FMaxConnsPerServer) then
    begin
      AtomicIncrement(FConnCount);
      LServerDock := Self;
      FClientSocket.Connect(FHost, FPort,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          if ASuccess then
          begin
            LHttpConn := AConnection as ICrossHttpClientConnection;
            LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
            LHttpConnObj.FProtocol := FProtocol;
            LHttpConnObj.FHost := FHost;
            LHttpConnObj.FPort := FPort;
            LHttpConnObj.FServerDock := LServerDock;
            LServerDock.AddConnection(LHttpConn);

            // 连接成功
            LHttpConnObj.DoRequest(ARequestPack, LNewCallback);
          end else
          begin
            AtomicDecrement(FConnCount);
            if Assigned(LNewCallback) then
              LNewCallback(TCrossHttpClientResponse.Create(400, 'Connect failed'));
          end;

          LNewCallback := nil;
        end);

      Exit;
    end;

    // 没有空闲连接并且连接数已达限定值
    // 将请求放入队列
    PushRequest(ARequestPack);
    LNewCallback := nil;
  finally
    _UnlockQueue;
  end;
end;

function TServerDock.GetConnsCount: Integer;
var
  LConn: ICrossConnection;
begin
  _LockConns;
  try
    Result := 0;

    for LConn in FConnections do
    begin
      if not LConn.IsClosed then
        Inc(Result);
    end;
  finally
    _UnlockConns;
  end;
end;

function TServerDock.GetIdleConnection: ICrossHttpClientConnection;
var
  LConn: ICrossConnection;
  LHttpConnObj: TCrossHttpClientConnection;
begin
  _LockConns;
  try
    for LConn in FConnections do
    begin
      LHttpConnObj := LConn as TCrossHttpClientConnection;
      if LHttpConnObj._IsIdle then
      begin
        LHttpConnObj._BeginRequest;
        Exit(LConn as ICrossHttpClientConnection);
      end;
    end;

    Result := nil;
  finally
    _UnlockConns;
  end;
end;

function TServerDock.PopRequest(out ARequestPack: TRequestPack): Boolean;
begin
  _LockQueue;
  try
    if (FRequestQueue.Count <= 0) then Exit(False);

    ARequestPack := FRequestQueue.Items[0];
    FRequestQueue.Delete(0);
    Result := True;
  finally
    _UnlockQueue;
  end;
end;

procedure TServerDock.ProcNext;
var
  LRequestPack: TRequestPack;
begin
  if not PopRequest(LRequestPack) then Exit;

  DoRequest(LRequestPack);
end;

procedure TServerDock.PushRequest(const ARequestPack: TRequestPack);
begin
  _LockQueue;
  try
    FRequestQueue.Add(ARequestPack);
  finally
    _UnlockQueue;
  end;
end;

procedure TServerDock.RemoveConnection(
  const AConnection: ICrossHttpClientConnection);
begin
  AtomicDecrement(FConnCount);

  _LockConns;
  try
    FConnections.Remove(AConnection);
  finally
    _UnlockConns;
  end;
end;

procedure TServerDock._LockConns;
begin
  FConnsLock.Enter;
end;

procedure TServerDock._LockQueue;
begin
  FQueueLock.Enter;
end;

procedure TServerDock._UnlockConns;
begin
  FConnsLock.Leave;
end;

procedure TServerDock._UnlockQueue;
begin
  FQueueLock.Leave;
end;

end.
