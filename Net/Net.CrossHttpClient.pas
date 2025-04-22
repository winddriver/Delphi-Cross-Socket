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
  Utils.Punycode,
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

  TCrossHttpClientConnection = class;
  TCrossHttpClientRequest = class;
  TCrossHttpClientResponse = class;
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
    rsRespondTimeout,

    /// <summary>
    ///   响应包含Connection: close, 连接需要关闭
    /// </summary>
    rsClose);

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

  /// <summary>
  ///   HTTP客户端连接
  /// </summary>
  ICrossHttpClientConnection = interface(ICrossSslConnection)
  ['{42507AC7-28E0-4CBE-92F6-FFCA8E5E79D6}']
    function GetHost: string;
    function GetPort: Word;
    function GetProtocol: string;
    function GetRawHost: string;
    function GetRequestStatus: TRequestStatus;

    {$REGION 'Documentation'}
    /// <summary>
    ///   连接协议(http/https/ws/wss)
    /// </summary>
    {$ENDREGION}
    property Protocol: string read GetProtocol;

    {$REGION 'Documentation'}
    /// <summary>
    ///   主机地址(如果主机地址包含Unicode字符, 该地址会被转换为Punycode)
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
    ///   主机原始地址
    /// </summary>
    {$ENDREGION}
    property RawHost: string read GetRawHost;

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
    function GetLocalPort: Word;
    procedure SetLocalPort(const AValue: Word);

    {$REGION 'Documentation'}
    /// <summary>
    ///   发出请求
    /// </summary>
    /// <param name="ARequest">
    ///   请求对象
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const ARequest: ICrossHttpClientRequest); overload;

    /// <summary>
    ///   本地端口(一般不需要指定, 设置为0由系统随机分配, 默认为0; 一定要在首次调用请求之前设置)
    /// </summary>
    property LocalPort: Word read GetLocalPort write SetLocalPort;
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
    function GetReUseConnection: Boolean;
    function GetTimeout: Integer;
    function GetAutoUrlEncode: Boolean;
    function GetLocalPort: Word;

    procedure SetIdleout(const AValue: Integer);
    procedure SetIoThreads(const AValue: Integer);
    procedure SetMaxConnsPerServer(const AValue: Integer);
    procedure SetReUseConnection(const AValue: Boolean);
    procedure SetTimeout(const AValue: Integer);
    procedure SetAutoUrlEncode(const AValue: Boolean);
    procedure SetLocalPort(const AValue: Word);

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
    ///   是否重用连接
    /// </summary>
    property ReUseConnection: Boolean read GetReUseConnection write SetReUseConnection;

    /// <summary>
    ///   请求超时时间(秒, 从请求发送成功之后算起, 设置为0则不检查超时)
    /// </summary>
    property Timeout: Integer read GetTimeout write SetTimeout;

    /// <summary>
    ///   自动对url参数进行编码(默认为True)
    /// </summary>
    property AutoUrlEncode: Boolean read GetAutoUrlEncode write SetAutoUrlEncode;

    /// <summary>
    ///   本地端口(一般不需要指定, 设置为0由系统随机分配, 默认为0; 一定要在首次调用请求之前设置)
    /// </summary>
    property LocalPort: Word read GetLocalPort write SetLocalPort;
  end;

  TCrossHttpClientConnection = class(TCrossSslConnection, ICrossHttpClientConnection)
  private
    FProtocol, FRawHost, FHost: string;
    FPort: Word;
    FServerDock: TServerDock;
    FPending: Integer;
    FWatch: TSimpleWatch;
    FStatus: Integer; // TRequestStatus

    FCompressType: TCompressType;
    FAutoUrlEncode: Boolean;
    FCallback: TCrossHttpResponseProc;

    FRequestObj: TCrossHttpClientRequest;
    FRequest: ICrossHttpClientRequest;
    FResponseObj: TCrossHttpClientResponse;
    FResponse: ICrossHttpClientResponse;
    FHttpParser: TCrossHttpParser;
    FReqLock: ILock;

    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValue: string): Boolean;
    procedure _OnBodyBegin;
    procedure _OnBodyData(const ADataPtr: Pointer; const ADataSize: Integer);
    procedure _OnBodyEnd;
    procedure _OnParseBegin;
    procedure _OnParseSuccess;
    procedure _OnParseFailed(const ACode: Integer; const AError: string);

    procedure _BeginRequest; inline;
    procedure _EndRequest; inline;
    function _IsIdle: Boolean; inline;
    procedure _UpdateWatch;
    function _IsIdleout: Boolean;
    function _IsTimeout: Boolean;
    function _SetRequestStatus(const AStatus: TRequestStatus): TRequestStatus;

    procedure _ReqLock; inline;
    procedure _ReqUnlock; inline;
    function _CreateRequestHeader(const ABodySize: Int64; AChunked: Boolean): TBytes;
  protected
    procedure InternalClose; override;

    procedure TriggerResponseSuccess; virtual;
    procedure TriggerResponseFailed(const AStatusCode: Integer; const AStatusText: string = ''); virtual;
    procedure TriggerResponseTimeout; virtual;
  protected
    function GetHost: string;
    function GetPort: Word;
    function GetProtocol: string;
    function GetRawHost: string;
    function GetRequestStatus: TRequestStatus;

    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer); virtual;

    {$region '内部: 基础发送方法'}
    procedure _Send(const ASource: TCrossHttpChunkDataFunc;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    procedure _Send(const AHeaderSource, ABodySource: TCrossHttpChunkDataFunc;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    {$endregion}

    {$region '不压缩发送'}
    procedure SendNoCompress(const AChunkSource: TCrossHttpChunkDataFunc;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: Pointer; const ABodySize: NativeInt;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    {$endregion}

    {$region '压缩发送'}
    procedure SendZCompress(const AChunkSource: TCrossHttpChunkDataFunc;
      const ACompressType: TCompressType;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: Pointer;
      const ABodySize: NativeInt; const ACompressType: TCompressType;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    {$endregion}

    // 所有请求方法的核心
    procedure DoRequest(const ARequest: ICrossHttpClientRequest; const ACallback: TCrossHttpResponseProc);
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

    property Protocol: string read GetProtocol;
    property Host: string read GetHost;
    property Port: Word read GetPort;
    property RawHost: string read GetRawHost;
    property RequestStatus: TRequestStatus read GetRequestStatus;
  end;

  TCrossHttpClientRequest = class(TInterfacedObject, ICrossHttpClientRequest)
  private
    FConnection: ICrossHttpClientConnection;

    FUrl, FProtocol, FHost: string;
    FPort: Word;
    FRequestBodyFunc: TCrossHttpChunkDataFunc;
    FRequestBody: Pointer;
    FRequestBodySize: NativeInt;
    FResponseStream: TStream;
    FInitProc: TCrossHttpRequestInitProc;
    FCallback: TCrossHttpResponseProc;

    FHttpVersion: THttpVersion;
    FMethod: string;
    FPath: string;
    FHeader: THttpHeader;
    FCookies: TRequestCookies;

    procedure _ParseUrl;
  protected
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
  public
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

    destructor Destroy; override;

    property Connection: ICrossHttpClientConnection read GetConnection;
    property Header: THttpHeader read GetHeader;
    property Cookies: TRequestCookies read GetCookies;
  end;

  TCrossHttpClientResponse = class(TInterfacedObject, ICrossHttpClientResponse)
  private
    FConnection: ICrossHttpClientConnection;
    FConnectionObj: TCrossHttpClientConnection;

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

    procedure _SetResponseStream(const AValue: TStream);
  protected
    function ParseHeader(const ADataPtr: Pointer; const ADataSize: Integer): Boolean;

    procedure TriggerResponseDataBegin; virtual;
    procedure TriggerResponseData(const ABuf: Pointer; const ALen: Integer); virtual;
    procedure TriggerResponseDataEnd; virtual;
  protected
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetContent: TStream;
    function GetContentType: string;
    function GetStatusCode: Integer;
    function GetStatusText: string;
  public
    constructor Create(const AConnection: ICrossHttpClientConnection); overload;
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

  TRequestQueue = TList<ICrossHttpClientRequest>;
  TClientConnections = TList<ICrossHttpClientConnection>;

  TServerDock = class
  private
    FClientSocket: TCrossHttpClientSocket;
    FProtocol, FRawHost, FHost: string;
    FPort, FLocalPort: Word;
    FRequestQueue: TRequestQueue;
    FConnections: TClientConnections;
    FConnCount: Integer;
    FLock: ILock;

    procedure _Lock; inline;
    procedure _Unlock; inline;
  public
    constructor Create(const AClientSocket: TCrossHttpClientSocket;
      const AProtocol, AHost: string; const APort, ALocalPort: Word);
    destructor Destroy; override;

    procedure AddConnection(const AConnection: ICrossHttpClientConnection);
    procedure RemoveConnection(const AConnection: ICrossHttpClientConnection);
    function GetConnsCount: Integer;
    function GetIdleConnection: ICrossHttpClientConnection;

    procedure PushRequest(const ARequest: ICrossHttpClientRequest);
    function PopRequest(out ARequest: ICrossHttpClientRequest): Boolean;

    procedure ProcNext;

    // 所有请求方法的核心
    procedure DoRequest(const AHttpConn: ICrossHttpClientConnection;
      const ARequest: ICrossHttpClientRequest); overload;
    procedure DoRequest(const ARequest: ICrossHttpClientRequest); overload;
  end;

  TServerDockDict = TObjectDictionary<string, TServerDock>;

  TCrossHttpClientSocket = class(TCrossSslSocket, ICrossHttpClientSocket)
  private
    FHttpClient: TCrossHttpClient;
    FReUseConnection, FAutoUrlEncode: Boolean;
    FCompressType: TCompressType;
    FMaxConnsPerServer: Integer;
    FServerDockDict: TServerDockDict;
    FServerDockLock: ILock;
    FLocalPort: Word;

    procedure _LockServerDock; inline;
    procedure _UnlockServerDock; inline;

    function _MakeServerDockKey(const AProtocol, AHost: string; const APort: Word): string;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word;
      out AServerDock: TServerDock): Boolean; overload;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word): TServerDock; overload;
  protected
    function GetLocalPort: Word;
    procedure SetLocalPort(const AValue: Word);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
  public
    constructor Create(const AHttpClient: TCrossHttpClient;
      const AIoThreads, AMaxConnsPerServer: Integer;
      const ASsl, AReUseConnection, AAutoUrlEncode: Boolean;
      const ACompressType: TCompressType = ctNone); reintroduce; virtual;
    destructor Destroy; override;

    // 所有请求方法的核心
    procedure DoRequest(const ARequest: ICrossHttpClientRequest); overload;

    property LocalPort: Word read GetLocalPort write SetLocalPort;
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
    FReUseConnection, FAutoUrlEncode: Boolean;
    FLocalPort: Word;

    procedure _ProcTimeout;
  protected
    procedure _Lock; inline;
    procedure _Unlock; inline;

    function CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket; virtual;

    function GetIdleout: Integer;
    function GetIoThreads: Integer;
    function GetMaxConnsPerServer: Integer;
    function GetReUseConnection: Boolean;
    function GetTimeout: Integer;
    function GetAutoUrlEncode: Boolean;
    function GetLocalPort: Word;

    procedure SetIdleout(const AValue: Integer);
    procedure SetIoThreads(const AValue: Integer);
    procedure SetMaxConnsPerServer(const AValue: Integer);
    procedure SetReUseConnection(const AValue: Boolean);
    procedure SetTimeout(const AValue: Integer);
    procedure SetAutoUrlEncode(const AValue: Boolean);
    procedure SetLocalPort(const AValue: Word);
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

    property Idleout: Integer read GetIdleout write SetIdleout;
    property IoThreads: Integer read GetIoThreads write SetIoThreads;
    property MaxConnsPerServer: Integer read GetMaxConnsPerServer write SetMaxConnsPerServer;
    property ReUseConnection: Boolean read GetReUseConnection write SetReUseConnection;
    property Timeout: Integer read GetTimeout write SetTimeout;
    property AutoUrlEncode: Boolean read GetAutoUrlEncode write SetAutoUrlEncode;
    property LocalPort: Word read GetLocalPort write SetLocalPort;
  end;

const
  SND_BUF_SIZE = 32768;

implementation

{ TCrossHttpClientConnection }

constructor TCrossHttpClientConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
var
  LHttpClientSocket: TCrossHttpClientSocket;
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);

  FHttpParser := TCrossHttpParser.Create(pmClient);
  FHttpParser.OnHeaderData := _OnHeaderData;
  FHttpParser.OnGetHeaderValue := _OnGetHeaderValue;
  FHttpParser.OnBodyBegin := _OnBodyBegin;
  FHttpParser.OnBodyData := _OnBodyData;
  FHttpParser.OnBodyEnd := _OnBodyEnd;
  FHttpParser.OnParseBegin := _OnParseBegin;
  FHttpParser.OnParseSuccess := _OnParseSuccess;
  FHttpParser.OnParseFailed := _OnParseFailed;

  // 肯定是要发起请求才会新建连接
  // 所以直接将连接状态锁定
  // 避免被别的请求占用
  _BeginRequest;

  FWatch := TSimpleWatch.Create;
  FReqLock := TLock.Create;

  LHttpClientSocket := AOwner as TCrossHttpClientSocket;
  FCompressType := LHttpClientSocket.FCompressType;
  FAutoUrlEncode := LHttpClientSocket.FAutoUrlEncode;
end;

procedure TCrossHttpClientConnection.DoRequest(const ARequest: ICrossHttpClientRequest;
  const ACallback: TCrossHttpResponseProc);
var
  LConnection: ICrossHttpClientConnection;
  LRequestObj: TCrossHttpClientRequest;
  LChunkDataFunc: TCrossHttpChunkDataFunc;
  LRequestBody: Pointer;
  LRequestBodySize: NativeInt;
begin
  LConnection := Self;
  LRequestObj := ARequest as TCrossHttpClientRequest;
  LRequestObj.FConnection := LConnection;

  // 调用初始化函数
  if Assigned(LRequestObj.FInitProc) then
    LRequestObj.FInitProc(ARequest);

  // 压缩方式
  if (FCompressType <> ctNone) then
    LRequestObj.FHeader[HEADER_CONTENT_ENCODING] := ZLIB_CONTENT_ENCODING[FCompressType];

  _ReqLock;
  try
    // 保存请求对象
    FRequestObj := LRequestObj;
    FRequest := ARequest;

    // 设置响应回调
    if Assigned(ACallback) then
      FCallback := ACallback
    else
      FCallback := FRequestObj.FCallback;

    LChunkDataFunc := FRequestObj.FRequestBodyFunc;
    LRequestBody := FRequestObj.FRequestBody;
    LRequestBodySize := FRequestObj.FRequestBodySize;
  finally
    _ReqUnlock;
  end;

  // 发起请求
  if Assigned(LChunkDataFunc) then
  begin
    SendZCompress(
      LChunkDataFunc,
      FCompressType);
  end else
  begin
    SendZCompress(
      LRequestBody,
      LRequestBodySize,
      FCompressType);
  end;
end;

destructor TCrossHttpClientConnection.Destroy;
begin
  _Lock;
  try
    if Assigned(FCallback) then
      TriggerResponseFailed(400, 'Connection destroyed');
  finally
    _Unlock;
  end;

  inherited;
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

function TCrossHttpClientConnection.GetRawHost: string;
begin
  Result := FRawHost;
end;

function TCrossHttpClientConnection.GetRequestStatus: TRequestStatus;
begin
  Result := TRequestStatus(AtomicCmpExchange(FStatus, 0, 0));
end;

procedure TCrossHttpClientConnection.InternalClose;
begin
  inherited InternalClose;
  FreeAndNil(FHttpParser);
end;

procedure TCrossHttpClientConnection.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
begin
  _UpdateWatch;

//  _Log('ParseRecvData, %s, 0x%x, %d', [Self.DebugInfo, NativeUInt(ABuf), ALen]);
  if (FHttpParser <> nil) then
    FHttpParser.Decode(ABuf, ALen);
end;

procedure TCrossHttpClientConnection.SendNoCompress(
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback);
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
      LHeaderBytes := _CreateRequestHeader(0, LChunked);

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
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LHeaderBytes := nil;
      LChunkHeader := nil;

      if Assigned(ASendCb) then
        ASendCb(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpClientConnection.SendNoCompress(const ABody: Pointer;
  const ABodySize: NativeInt; const ASendCb: TCrossConnectionCallback);
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
      LHeaderBytes := _CreateRequestHeader(LBodySize, False);

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
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LHeaderBytes := nil;

      if Assigned(ASendCb) then
        ASendCb(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpClientConnection.SendZCompress(
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ACompressType: TCompressType; const ASendCb: TCrossConnectionCallback);
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
    SendNoCompress(AChunkSource, ASendCb);
    Exit;
  end;

  SetLength(LBuffer, SND_BUF_SIZE);

  FillChar(LZStream, SizeOf(TZStreamRec), 0);
  LZResult := Z_OK;
  LZFlush := Z_NO_FLUSH;

  if (deflateInit2(LZStream, Z_DEFAULT_COMPRESSION,
    Z_DEFLATED, ZLIB_WINDOW_BITS[ACompressType], 8, Z_DEFAULT_STRATEGY) <> Z_OK) then
  begin
    TriggerResponseFailed(400, 'deflateInit2 failed');

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
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LBuffer := nil;
      deflateEnd(LZStream);

      if Assigned(ASendCb) then
        ASendCb(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpClientConnection.SendZCompress(const ABody: Pointer;
  const ABodySize: NativeInt; const ACompressType: TCompressType;
  const ASendCb: TCrossConnectionCallback);
var
  P: PByte;
  LBodySize: NativeInt;
begin
  if (ACompressType = ctNone) then
  begin
    SendNoCompress(ABody, ABodySize, ASendCb);
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
    ASendCb);
end;

procedure TCrossHttpClientConnection.TriggerResponseFailed(
  const AStatusCode: Integer; const AStatusText: string);
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
begin
  _ReqLock;
  try
    LCallback := FCallback;
    FCallback := nil;

    _SetRequestStatus(rsRespondFailed);
    Close;
  finally
    FRequest := nil;
    FRequestObj := nil;
    FResponse := nil;
    FResponseObj := nil;

    _ReqUnlock;
    _EndRequest;
  end;

  if Assigned(LCallback) then
  try
    LResponse := TCrossHttpClientResponse.Create(AStatusCode, AStatusText);
    LCallback(LResponse);
  except
  end;
end;

procedure TCrossHttpClientConnection.TriggerResponseSuccess;
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
begin
  _ReqLock;
  try
    // 只有在等待响应状态的情况才应该触发完成响应回调
    // 因为有可能响应完成的数据在超时后才到来, 这时候请求状态已经被置为超时
    // 不应该再触发完成回调
    if (RequestStatus <> rsResponding) then Exit;

    LCallback := FCallback;
    FCallback := nil;
    LResponse := FResponse;

    if SameText(FResponseObj.FHeader[HEADER_CONNECTION], 'close') then
    begin
      _SetRequestStatus(rsClose);
      Close;
    end else
    begin
      _UpdateWatch;
      _SetRequestStatus(rsIdle);
    end;
  finally
    FRequest := nil;
    FRequestObj := nil;
    FResponse := nil;
    FResponseObj := nil;

    _ReqUnlock;
    _EndRequest;
  end;

  if Assigned(LCallback) then
  try
    LCallback(LResponse);
  except
  end;
end;

procedure TCrossHttpClientConnection.TriggerResponseTimeout;
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
begin
  _ReqLock;
  try
    LCallback := FCallback;
    FCallback := nil;

    _SetRequestStatus(rsRespondTimeout);
    Close;
  finally
    FRequest := nil;
    FRequestObj := nil;
    FResponse := nil;
    FResponseObj := nil;

    _ReqUnlock;
    _EndRequest;
  end;

  if Assigned(LCallback) then
  try
    // 408 = Request Time-out
    LResponse := TCrossHttpClientResponse.Create(408);
    LCallback(LResponse);
  except
  end;
end;

procedure TCrossHttpClientConnection._BeginRequest;
begin
  AtomicIncrement(FPending);
  _UpdateWatch;
end;

function TCrossHttpClientConnection._CreateRequestHeader(const ABodySize: Int64;
  AChunked: Boolean): TBytes;
var
  LHeaderStr, LCookieStr, LPathStr: string;
begin
  _ReqLock;
  try
    if (FRequestObj.FHeader[HEADER_CACHE_CONTROL] = '') then
      FRequestObj.FHeader[HEADER_CACHE_CONTROL] := 'no-cache';

    if (FRequestObj.FHeader[HEADER_PRAGMA] = '') then
      FRequestObj.FHeader[HEADER_PRAGMA] := 'no-cache';

    if (FRequestObj.FHeader[HEADER_CONNECTION] = '') then
      FRequestObj.FHeader[HEADER_CONNECTION] := 'keep-alive';

    // 设置数据格式
    if (FRequestObj.FHeader[HEADER_CONTENT_TYPE] = '')
      and (AChunked or (ABodySize > 0)) then
      FRequestObj.FHeader[HEADER_CONTENT_TYPE] := TMediaType.APPLICATION_OCTET_STREAM;

    // 设置主机信息
    if (FRequestObj.FHeader[HEADER_HOST] = '') then
    begin
      if (not Ssl and (FPort = HTTP_DEFAULT_PORT))
        or (Ssl and (FPort = HTTPS_DEFAULT_PORT)) then
        FRequestObj.FHeader[HEADER_HOST] := FHost
      else
        FRequestObj.FHeader[HEADER_HOST] := FHost + ':' + FPort.ToString;
    end;

    // 设置接受的数据传输方式
    if AChunked then
      FRequestObj.FHeader[HEADER_TRANSFER_ENCODING] := 'chunked'
    else if (ABodySize > 0) then
      FRequestObj.FHeader[HEADER_CONTENT_LENGTH] := ABodySize.ToString;

    // 设置接受的数据编码方式
    if (FRequestObj.FHeader[HEADER_ACCEPT_ENCODING] = '') then
      FRequestObj.FHeader[HEADER_ACCEPT_ENCODING] := 'gzip, deflate';

    // 设置 Cookies
    LCookieStr := FRequestObj.FCookies.Encode;
    if (LCookieStr <> '') then
      FRequestObj.FHeader[HEADER_COOKIE] := LCookieStr;

    if (FRequestObj.FHeader[HEADER_CROSS_HTTP_CLIENT] = '') then
      FRequestObj.FHeader[HEADER_CROSS_HTTP_CLIENT] := CROSS_HTTP_CLIENT_NAME;

    LPathStr := FRequestObj.FPath;
    if FAutoUrlEncode then
      LPathStr := TCrossHttpUtils.UrlEncode(FRequestObj.FPath, ['/', '?', '=', '&']);

    // 设置请求行
    LHeaderStr := FRequestObj.FMethod + ' '
      + LPathStr + ' '
      + HTTP_VER_STR[FRequestObj.FHttpVersion] + CRLF;

    LHeaderStr := LHeaderStr + FRequestObj.FHeader.Encode;
  finally
    _ReqUnlock;
  end;

  Result := TEncoding.ANSI.GetBytes(LHeaderStr);
end;

procedure TCrossHttpClientConnection._EndRequest;
begin
  AtomicDecrement(FPending);
end;

function TCrossHttpClientConnection._IsIdle: Boolean;
begin
  Result := (ConnectStatus = csConnected)
    and (GetRequestStatus in [rsIdle])
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

procedure TCrossHttpClientConnection._OnBodyBegin;
begin
  FResponseObj.TriggerResponseDataBegin;
end;

procedure TCrossHttpClientConnection._OnBodyData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  FResponseObj.TriggerResponseData(ADataPtr, ADataSize);
end;

procedure TCrossHttpClientConnection._OnBodyEnd;
begin
  FResponseObj.TriggerResponseDataEnd;
end;

function TCrossHttpClientConnection._OnGetHeaderValue(const AHeaderName: string;
  out AHeaderValue: string): Boolean;
begin
  Result := FResponseObj.FHeader.GetParamValue(AHeaderName, AHeaderValue);
end;

procedure TCrossHttpClientConnection._OnHeaderData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  FResponseObj.ParseHeader(ADataPtr, ADataSize);
end;

procedure TCrossHttpClientConnection._OnParseBegin;
begin
  _ReqLock;
  try
    FResponseObj := TCrossHttpClientResponse.Create(Self);
    FResponse := FResponseObj;

    FResponseObj._SetResponseStream(FRequestObj.FResponseStream);
  finally
    _ReqUnLock;
  end;
end;

procedure TCrossHttpClientConnection._OnParseFailed(const ACode: Integer;
  const AError: string);
begin
  TriggerResponseFailed(ACode, AError);
end;

procedure TCrossHttpClientConnection._OnParseSuccess;
begin
  TriggerResponseSuccess;
end;

procedure TCrossHttpClientConnection._ReqLock;
begin
  FReqLock.Enter;
end;

procedure TCrossHttpClientConnection._ReqUnlock;
begin
  FReqLock.Leave;
end;

procedure TCrossHttpClientConnection._Send(
  const ASource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback);
var
  LHttpConnection: ICrossHttpClientConnection;
  LSender: TCrossConnectionCallback;
begin
  LHttpConnection := Self;

  // 标记正在发送请求
  _SetRequestStatus(rsSending);

  // 更新计时器
  _UpdateWatch;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
    begin
      // 发送失败
      if not ASuccess then
      begin
        Close;
        TriggerResponseFailed(400, 'Send failed');
        LHttpConnection := nil;
        LSender := nil;

        if Assigned(ASendCb) then
          ASendCb(AConnection, ASuccess);

        Exit;
      end;

      // 更新计时器
      _UpdateWatch;

      LData := nil;
      LCount := 0;
      if not Assigned(ASource)
        or not ASource(@LData, @LCount)
        or (LData = nil)
        or (LCount <= 0) then
      begin
        // 标记正在等待响应
        _SetRequestStatus(rsResponding);
        LHttpConnection := nil;
        LSender := nil;

        if Assigned(ASendCb) then
          ASendCb(AConnection, ASuccess);

        Exit;
      end;

      LHttpConnection.SendBuf(LData^, LCount, LSender);
    end;

  LSender(LHttpConnection, True);
end;

procedure TCrossHttpClientConnection._Send(const AHeaderSource,
  ABodySource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback);
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
    ASendCb);
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

constructor TCrossHttpClientRequest.Create(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBodyFunc: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream; const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  FHeader := THttpHeader.Create;
  FCookies := TRequestCookies.Create;
  FHttpVersion := hvHttp11;

  FMethod := AMethod;
  FUrl := AUrl;
  if (AHttpHeaders <> nil) then
    FHeader.Assign(AHttpHeaders);
  FRequestBodyFunc := ARequestBodyFunc;
  FRequestBody := nil;
  FRequestBodySize := 0;
  FResponseStream := AResponseStream;
  FInitProc := AInitProc;
  FCallback := ACallback;

  _ParseUrl;
end;

constructor TCrossHttpClientRequest.Create(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  FHeader := THttpHeader.Create;
  FCookies := TRequestCookies.Create;
  FHttpVersion := hvHttp11;

  FMethod := AMethod;
  FUrl := AUrl;
  if (AHttpHeaders <> nil) then
    FHeader.Assign(AHttpHeaders);
  FRequestBodyFunc := nil;
  FRequestBody := ARequestBody;
  FRequestBodySize := ABodySize;
  FResponseStream := AResponseStream;
  FInitProc := AInitProc;
  FCallback := ACallback;

  _ParseUrl;
end;

destructor TCrossHttpClientRequest.Destroy;
begin
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);

  inherited;
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

procedure TCrossHttpClientRequest._ParseUrl;
begin
  if not TCrossHttpUtils.ExtractUrl(FUrl, FProtocol, FHost, FPort, FPath) then
  begin
    if Assigned(FCallback) then
      FCallback(TCrossHttpClientResponse.Create(400, 'Invalid URL'));

    Abort;
  end;
end;

{ TCrossHttpClientResponse }

constructor TCrossHttpClientResponse.Create(
  const AConnection: ICrossHttpClientConnection);
begin
  FConnection := AConnection;
  FConnectionObj := AConnection as TCrossHttpClientConnection;

  FHeader := THttpHeader.Create;
  FCookies := TResponseCookies.Create;
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
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);

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
      FCookies.Add(TResponseCookie.Create(LHeader.Value, FConnectionObj.FHost));
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
  if (FResponseBodyStream.Size > 0) then
    FResponseBodyStream.Size := 0;
end;

procedure TCrossHttpClientResponse.TriggerResponseDataEnd;
begin
  if (FResponseBodyStream <> nil) and (FResponseBodyStream.Size > 0) then
    FResponseBodyStream.Position := 0;
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

{ TCrossHttpClientSocket }

constructor TCrossHttpClientSocket.Create(const AHttpClient: TCrossHttpClient;
  const AIoThreads, AMaxConnsPerServer: Integer;
  const ASsl, AReUseConnection, AAutoUrlEncode: Boolean;
  const ACompressType: TCompressType);
begin
  FHttpClient := AHttpClient;
  FReUseConnection := AReUseConnection;
  FAutoUrlEncode := AAutoUrlEncode;
  FMaxConnsPerServer := AMaxConnsPerServer;
  FCompressType := ACompressType;

  inherited Create(AIoThreads, ASsl);

  FServerDockDict := TServerDockDict.Create([doOwnsValues]);
  FServerDockLock := TLock.Create;
end;

function TCrossHttpClientSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossHttpClientConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

destructor TCrossHttpClientSocket.Destroy;
begin
  FreeAndNil(FServerDockDict);
  inherited;
end;

procedure TCrossHttpClientSocket.DoRequest(const ARequest: ICrossHttpClientRequest);
var
  LRequestObj: TCrossHttpClientRequest;
  LServerDock: TServerDock;
begin
  LRequestObj := ARequest as TCrossHttpClientRequest;
  _LockServerDock;
  try
    LServerDock := _GetServerDock(
      LRequestObj.FProtocol,
      LRequestObj.FHost,
      LRequestObj.FPort);
  finally
    _UnlockServerDock;
  end;

  LServerDock.DoRequest(ARequest);
end;

function TCrossHttpClientSocket.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

procedure TCrossHttpClientSocket.LogicDisconnected(
  const AConnection: ICrossConnection);
var
  LServerDock: TServerDock;
  LConn: ICrossHttpClientConnection;
  LConnObj: TCrossHttpClientConnection;
begin
  LConn := AConnection as ICrossHttpClientConnection;
  LConnObj := LConn as TCrossHttpClientConnection;

  // 在等待响应的过程中连接被断开了
  // 需要触发回调函数
  if Assigned(LConnObj.FCallback) then
    LConnObj.TriggerResponseFailed(400, 'Connection lost');

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

  inherited LogicDisconnected(AConnection);
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

  inherited LogicReceived(AConnection, ABuf, ALen);
end;

procedure TCrossHttpClientSocket.SetLocalPort(const AValue: Word);
begin
  FLocalPort := AValue;
end;

function TCrossHttpClientSocket._GetServerDock(const AProtocol, AHost: string;
  const APort: Word): TServerDock;
var
  LKey: string;
begin
  LKey := _MakeServerDockKey(AProtocol, AHost, APort);
  if not FServerDockDict.TryGetValue(LKey, Result) then
  begin
    Result := TServerDock.Create(Self, AProtocol, AHost, APort, FLocalPort);
    FServerDockDict.Add(LKey, Result);
  end else
    Result.FLocalPort := FLocalPort;
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

  // 默认重用连接
  FReUseConnection := True;

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
      FHttpCli := TCrossHttpClientSocket.Create(Self, FIoThreads,
        FMaxConnsPerServer, False,
        FReUseConnection, FAutoUrlEncode,
        FCompressType);
      FHttpCliArr := FHttpCliArr + [FHttpCli];
    end;

    Result := FHttpCli;
  end else
  if TStrUtils.SameText(AProtocol, HTTPS) then
  begin
    if (FHttpsCli = nil) then
    begin
      FHttpsCli := TCrossHttpClientSocket.Create(Self, FIoThreads,
        FMaxConnsPerServer, True,
        FReUseConnection, FAutoUrlEncode,
        FCompressType);
      FHttpCliArr := FHttpCliArr + [FHttpsCli];
    end;

    Result := FHttpsCli;
  end else
    raise ECrossHttpClient.CreateFmt('Invalid protocol:%s', [AProtocol]);

  Result.LocalPort := FLocalPort;
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBody: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpCli: ICrossHttpClientSocket;
  LRequestObj: TCrossHttpClientRequest;
  LRequest: ICrossHttpClientRequest;
begin
  LRequestObj := TCrossHttpClientRequest.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    AResponseStream,
    AInitProc,
    ACallback);
  LRequest := LRequestObj;

  // 根据协议获取HttpCli对象
  _Lock;
  try
    LHttpCli := CreateHttpCli(LRequestObj.FProtocol);
  finally
    _Unlock;
  end;

  LHttpCli.DoRequest(LRequest);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpCli: ICrossHttpClientSocket;
  LRequestObj: TCrossHttpClientRequest;
  LRequest: ICrossHttpClientRequest;
begin
  LRequestObj := TCrossHttpClientRequest.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    ABodySize,
    AResponseStream,
    AInitProc,
    ACallback);
  LRequest := LRequestObj;

  // 根据协议获取HttpCli对象
  _Lock;
  try
    LHttpCli := CreateHttpCli(LRequestObj.FProtocol);
  finally
    _Unlock;
  end;

  LHttpCli.DoRequest(LRequest);
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
        LHttpConn := LConn as ICrossHttpClientConnection;
        LHttpConnObj := LHttpConn as TCrossHttpClientConnection;

        if not LConn.IsClosed then
        begin
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
      _Log('first idle conn [%u] idle watch: %d ms / start-time: %s', [
        LFirstIdleConn.UID,
        LFirstIdleConn.FWatch.ElapsedMilliseconds,
        FormatDateTime('hh":"nn":"ss.zzz', LFirstIdleConn.FWatch.LastTime)
      ]);
    end;
    {$ENDIF}

    for LHttpConn in LTimeoutArr do
    begin
      LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
      LHttpConnObj.TriggerResponseTimeout;
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

function TCrossHttpClient.GetAutoUrlEncode: Boolean;
begin
  Result := FAutoUrlEncode;
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

function TCrossHttpClient.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TCrossHttpClient.GetMaxConnsPerServer: Integer;
begin
  Result := FMaxConnsPerServer;
end;

function TCrossHttpClient.GetReUseConnection: Boolean;
begin
  Result := FReUseConnection;
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

procedure TCrossHttpClient.SetAutoUrlEncode(const AValue: Boolean);
begin
  FAutoUrlEncode := AValue;
end;

procedure TCrossHttpClient.SetIdleout(const AValue: Integer);
begin
  FIdleout := AValue;
end;

procedure TCrossHttpClient.SetIoThreads(const AValue: Integer);
begin
  FIoThreads := AValue;
end;

procedure TCrossHttpClient.SetLocalPort(const AValue: Word);
begin
  FLocalPort := AValue;
end;

procedure TCrossHttpClient.SetMaxConnsPerServer(const AValue: Integer);
begin
  FMaxConnsPerServer := AValue;
end;

procedure TCrossHttpClient.SetReUseConnection(const AValue: Boolean);
begin
  FReUseConnection := AValue;
end;

procedure TCrossHttpClient.SetTimeout(const AValue: Integer);
begin
  FTimeout := AValue;
end;

{ TServerDock }

procedure TServerDock.AddConnection(
  const AConnection: ICrossHttpClientConnection);
begin
  _Lock;
  try
    FConnections.Add(AConnection);
  finally
    _Unlock;
  end;
end;

constructor TServerDock.Create(const AClientSocket: TCrossHttpClientSocket;
  const AProtocol, AHost: string; const APort, ALocalPort: Word);
begin
  FClientSocket := AClientSocket;
  FProtocol := AProtocol;
  FRawHost := AHost;
  FHost := TPunycode.EncodeDomain(FRawHost);
  FPort := APort;
  FLocalPort := ALocalPort;

  FRequestQueue := TRequestQueue.Create;
  FConnections := TClientConnections.Create;

  FLock := TLock.Create;
end;

destructor TServerDock.Destroy;
begin
  FreeAndNil(FRequestQueue);
  FreeAndNil(FConnections);

  inherited;
end;

procedure TServerDock.DoRequest(const AHttpConn: ICrossHttpClientConnection;
  const ARequest: ICrossHttpClientRequest);
var
  LConnectionObj: TCrossHttpClientConnection;
  LRequest: ICrossHttpClientRequest;
  LRequestObj: TCrossHttpClientRequest;
begin
  LRequest := ARequest;
  LRequestObj := ARequest as TCrossHttpClientRequest;

  if (AHttpConn <> nil) then
  begin
    LConnectionObj := AHttpConn as TCrossHttpClientConnection;
    LConnectionObj.DoRequest(ARequest,
      procedure(const AResponse: ICrossHttpClientResponse)
      begin
        try
          if Assigned(LRequestObj.FCallback) then
            LRequestObj.FCallback(AResponse);
        finally
          LRequest := nil;
          ProcNext;
        end;
      end);
  end else
  begin
    try
      if Assigned(LRequestObj.FCallback) then
        LRequestObj.FCallback(TCrossHttpClientResponse.Create(400, 'Connect failed'));
    finally
      LRequest := nil;
      ProcNext;
    end;
  end;
end;

procedure TServerDock.DoRequest(const ARequest: ICrossHttpClientRequest);
var
  LRequest: ICrossHttpClientRequest;
  LHttpConn: ICrossHttpClientConnection;
  LServerDock: TServerDock;
begin
  LRequest := ARequest;
  LHttpConn := nil;

  // 优先使用空闲连接
  if FClientSocket.FReUseConnection then
    LHttpConn := GetIdleConnection;

  if (LHttpConn <> nil) then
  begin
    DoRequest(LHttpConn, LRequest);
    Exit;
  end;

  // 没有空闲连接并且连接数未超过限定
  // 建立新连接
  if (FClientSocket.FMaxConnsPerServer <= 0)
    or (AtomicCmpExchange(FConnCount, 0, 0) < FClientSocket.FMaxConnsPerServer) then
  begin
    LServerDock := Self;
    FClientSocket.Connect(FHost, FPort, FLocalPort,
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      var
        LHttpConn: ICrossHttpClientConnection;
        LHttpConnObj: TCrossHttpClientConnection;
      begin
        // 连接成功
        if ASuccess then
        begin
          //   _Log('NewConnection[%s], %s', [AConnection.DebugInfo, (LRequest as TCrossHttpClientRequest).FUrl]);
          // 连接成功之后才增加连接数
          // 这样的好处是, 并发请求能尽快处理,
          //   当要请求的服务器不可用时, 多个并发能快速连接失败, 否则并发请求越多后面的请求等待的时间就会越长
          //   导致请求越堆积越多
          // 坏处就是无法精确限制并发连接数
          AtomicIncrement(FConnCount);

          LHttpConn := AConnection as ICrossHttpClientConnection;
          LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
          LHttpConnObj.FProtocol := FProtocol;
          LHttpConnObj.FRawHost := FRawHost;
          LHttpConnObj.FHost := FHost;
          LHttpConnObj.FPort := FPort;
          LHttpConnObj.FServerDock := LServerDock;
          LServerDock.AddConnection(LHttpConn);
        end else
          LHttpConn := nil;

        DoRequest(LHttpConn, LRequest);
      end);

    Exit;
  end;

  // 没有空闲连接并且连接数已达限定值
  // 将请求放入队列
  PushRequest(LRequest);
end;

function TServerDock.GetConnsCount: Integer;
var
  LConn: ICrossConnection;
begin
  _Lock;
  try
    Result := 0;

    for LConn in FConnections do
    begin
      if not LConn.IsClosed then
        Inc(Result);
    end;
  finally
    _Unlock;
  end;
end;

function TServerDock.GetIdleConnection: ICrossHttpClientConnection;
var
  LConn: ICrossConnection;
  LHttpConnObj: TCrossHttpClientConnection;
begin
  _Lock;
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
    _Unlock;
  end;
end;

function TServerDock.PopRequest(out ARequest: ICrossHttpClientRequest): Boolean;
begin
  _Lock;
  try
    if (FRequestQueue.Count <= 0) then Exit(False);

    ARequest := FRequestQueue.Items[0];
    FRequestQueue.Delete(0);
    Result := True;
  finally
    _Unlock;
  end;
end;

procedure TServerDock.ProcNext;
var
  LRequest: ICrossHttpClientRequest;
begin
  if not PopRequest(LRequest) then Exit;

  DoRequest(LRequest);
end;

procedure TServerDock.PushRequest(const ARequest: ICrossHttpClientRequest);
begin
  _Lock;
  try
    FRequestQueue.Add(ARequest);
  finally
    _Unlock;
  end;
end;

procedure TServerDock.RemoveConnection(
  const AConnection: ICrossHttpClientConnection);
begin
  AtomicDecrement(FConnCount);

  _Lock;
  try
    FConnections.Remove(AConnection);
  finally
    _Unlock;
  end;
end;

procedure TServerDock._Lock;
begin
  FLock.Enter;
end;

procedure TServerDock._Unlock;
begin
  FLock.Leave;
end;

end.
