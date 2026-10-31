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
  //ZLib,
  {$IFDEF DELPHI}
  ZLib,
  {$ELSE}
  DTF.StaticZLib,
  DTF.Generics,
  DTF.Types,
  {$ENDIF}
  Generics.Collections,

  Net.SocketAPI,
  Net.CrossProxy,
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
  IServerDock = interface;

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
    rsClose,

    /// <summary>
    ///   协议已升级 (HTTP/1.1 101 Switching Protocols), 连接由上层协议(如 WebSocket)接管,
    ///   不再参与 HTTP 请求队列复用、idleout 与 RequestTimeout 检查
    /// </summary>
    rsUpgraded);

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

  // 正文及初始化回调已不再被发送链使用；不表示对端业务完成。
  TCrossHttpRequestSendProc = reference to procedure(const ASuccess: Boolean);

  // 独立能力接口，保持原 ICrossHttpClient 的 IID 和方法布局。
  ICrossHttpClientSend = interface
  ['{4D0F7848-E9CB-45CB-9B78-259C80D2CD80}']
    // 构造请求失败时可同步抛出且无回调；接管后发送/响应各完成一次。
    // ResponseCb 可以先到；调用方必须将借用正文及其 owner 保留到 SendCb。
    procedure DoRequestWithSend(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody, AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ASendCb: TCrossHttpRequestSendProc;
      const AResponseCb: TCrossHttpResponseProc);
  end;

  ICrossHttpClientEntity = interface
  ['{987DDCB1-5310-44B4-9F29-3515D966F287}']
    function GetPreserveResponseEntity: Boolean;
    procedure SetPreserveResponseEntity(const AValue: Boolean);
    // 新连接快照；默认 False，仍使用原自动内容解码。
    property PreserveResponseEntity: Boolean read GetPreserveResponseEntity write SetPreserveResponseEntity;
  end;

  THttpResponseStorageOptions = record
    // 0 保留默认全内存行为；只作用于客户端自行创建的响应流。
    MemoryThreshold: Integer;
    TempPath: string;
  end;

  ICrossHttpClientResponseStorage = interface
  ['{19A64885-F763-4CC3-BB21-F1429018AEB4}']
    // 新连接快照；外部传入的 AResponseStream 继续由调用方管理。
    procedure SetResponseStorageOptions(const AValue: THttpResponseStorageOptions);
    function GetResponseStorageOptions: THttpResponseStorageOptions;
  end;

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
    function GetQuery: THttpUrlParams;
    function GetMethod: string;
    function GetPath: string;
    function GetPathAndParams: string;

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

    {$REGION 'Documentation'}
    /// <summary>
    ///   请求路径后形如?key1=value1&amp;key2=value2的参数
    /// </summary>
    {$ENDREGION}
    property Query: THttpUrlParams read GetQuery;

    {$REGION 'Documentation'}
    /// <summary>
    ///   请求方法
    ///   <list type="bullet">
    ///     <item>
    ///       GET
    ///     </item>
    ///     <item>
    ///       POST
    ///     </item>
    ///     <item>
    ///       PUT
    ///     </item>
    ///     <item>
    ///       DELETE
    ///     </item>
    ///     <item>
    ///       HEAD
    ///     </item>
    ///     <item>
    ///       OPTIONS
    ///     </item>
    ///     <item>
    ///       TRACE
    ///     </item>
    ///     <item>
    ///       CONNECT
    ///     </item>
    ///     <item>
    ///       PATCH
    ///     </item>
    ///     <item>
    ///       COPY
    ///     </item>
    ///     <item>
    ///       LINK
    ///     </item>
    ///     <item>
    ///       UNLINK
    ///     </item>
    ///     <item>
    ///       PURGE
    ///     </item>
    ///     <item>
    ///       LOCK
    ///     </item>
    ///     <item>
    ///       UNLOCK
    ///     </item>
    ///     <item>
    ///       PROPFIND
    ///     </item>
    ///   </list>
    /// </summary>
    {$ENDREGION}
    property Method: string read GetMethod;

    {$REGION 'Documentation'}
    /// <summary>
    ///   <para>
    ///     请求路径, 不包含参数部分
    ///   </para>
    ///   <para>
    ///     比如: /api/callapi1
    ///   </para>
    /// </summary>
    {$ENDREGION}
    property Path: string read GetPath;

    {$REGION 'Documentation'}
    /// <summary>
    ///   <para>
    ///     请求路径及参数
    ///   </para>
    ///   <para>
    ///     比如: /api/callapi1?aaa=111&bbb=222
    ///   </para>
    /// </summary>
    {$ENDREGION}
    property PathAndParams: string read GetPathAndParams;
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
  ['{8944949B-EC8D-406E-B471-F1BF6BEDA15B}']
    function GetLocalPort: Word;
    procedure SetLocalPort(const AValue: Word);
    procedure ConnectTarget(const APhysicalHost: string;
      const APhysicalPort, ALocalPort: Word; const ALogicalHost: string;
      const ALogicalPort: Word;
      const ACallback: TCrossConnectionCallback = nil);

    {$REGION 'Documentation'}
    /// <summary>
    ///   发出请求
    /// </summary>
    /// <param name="ARequest">
    ///   请求对象
    /// </param>
    {$ENDREGION}
    procedure DoRequest(const ARequest: ICrossHttpClientRequest); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   取消所有请求
    /// </summary>
    {$ENDREGION}
    procedure CancelAllRequests;

    {$REGION 'Documentation'}
    /// <summary>
    ///   同步选项配置
    /// </summary>
    /// <param name="AMaxConnsPerServer">
    ///   每个服务器最大连接数
    /// </param>
    /// <param name="AMaxCompressRatio">
    ///   gzip/deflate 解压最大压缩比 (仅影响后续新建连接的 parser)
    /// </param>
    /// <param name="AReUseConnection">
    ///   是否重用连接
    /// </param>
    /// <param name="AAutoUrlEncode">
    ///   是否自动URL编码
    /// </param>
    {$ENDREGION}
    procedure SyncOptions(const AMaxConnsPerServer, AMaxCompressRatio: Integer;
      const AReUseConnection, AAutoUrlEncode: Boolean);

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
  ['{A136B460-1A81-42D8-9724-EDB7E65EFB3C}']
    function GetIdleout: Integer;
    function GetIoThreads: Integer;
    function GetMaxConnsPerServer: Integer;
    function GetMaxCompressRatio: Integer;
    function GetReUseConnection: Boolean;
    function GetRequestTimeout: Integer;
    function GetConnectTimeout: Integer;
    function GetAutoUrlEncode: Boolean;
    function GetLocalPort: Word;
    function GetVerifyPeer: Boolean;
    function GetProxySettings: TCrossProxySettings;

    procedure SetIdleout(const AValue: Integer);
    procedure SetIoThreads(const AValue: Integer);
    procedure SetMaxConnsPerServer(const AValue: Integer);
    procedure SetMaxCompressRatio(const AValue: Integer);
    procedure SetReUseConnection(const AValue: Boolean);
    procedure SetRequestTimeout(const AValue: Integer);
    procedure SetConnectTimeout(const AValue: Integer);
    procedure SetAutoUrlEncode(const AValue: Boolean);
    procedure SetLocalPort(const AValue: Word);
    procedure SetVerifyPeer(const AValue: Boolean);
    procedure SetProxySettings(const AValue: TCrossProxySettings);

    /// <summary>
    ///   设置客户端证书
    /// </summary>
    /// <param name="ACertBuf">
    ///   证书内存指针
    /// </param>
    /// <param name="ACertBufSize">
    ///   证书内存大小
    /// </param>
    procedure SetCertificate(const ACertBuf: Pointer;
      const ACertBufSize: Integer); overload;
    /// <summary>
    ///   设置客户端证书
    /// </summary>
    /// <param name="ACertBytes">
    ///   证书字节数组
    /// </param>
    procedure SetCertificate(const ACertBytes: TBytes); overload;
    /// <summary>
    ///   设置客户端证书
    /// </summary>
    /// <param name="ACertStr">
    ///   证书字符串
    /// </param>
    procedure SetCertificate(const ACertStr: string); overload;
    /// <summary>
    ///   设置客户端证书文件
    /// </summary>
    /// <param name="ACertFile">
    ///   证书文件路径
    /// </param>
    procedure SetCertificateFile(const ACertFile: string);

    /// <summary>
    ///   设置客户端私钥
    /// </summary>
    /// <param name="APKeyBuf">
    ///   私钥内存指针
    /// </param>
    /// <param name="APKeyBufSize">
    ///   私钥内存大小
    /// </param>
    /// <param name="APassword">
    ///   私钥密码, 默认为空
    /// </param>
    procedure SetPrivateKey(const APKeyBuf: Pointer;
      const APKeyBufSize: Integer; const APassword: string = ''); overload;
    /// <summary>
    ///   设置客户端私钥
    /// </summary>
    /// <param name="APKeyBytes">
    ///   私钥字节数组
    /// </param>
    /// <param name="APassword">
    ///   私钥密码, 默认为空
    /// </param>
    procedure SetPrivateKey(const APKeyBytes: TBytes;
      const APassword: string = ''); overload;
    /// <summary>
    ///   设置客户端私钥
    /// </summary>
    /// <param name="APKeyStr">
    ///   私钥字符串
    /// </param>
    /// <param name="APassword">
    ///   私钥密码, 默认为空
    /// </param>
    procedure SetPrivateKey(const APKeyStr: string;
      const APassword: string = ''); overload;
    /// <summary>
    ///   设置客户端私钥文件
    /// </summary>
    /// <param name="APKeyFile">
    ///   私钥文件路径
    /// </param>
    /// <param name="APassword">
    ///   私钥密码, 默认为空
    /// </param>
    procedure SetPrivateKeyFile(const APKeyFile: string;
      const APassword: string = '');

    /// <summary>
    ///   从内存追加用于验证 HTTPS 服务端证书链的受信任 CA 证书
    /// </summary>
    /// <remarks>
    ///   此方法只配置服务端证书的信任锚，不会设置 mTLS 客户端身份。
    ///   mTLS 客户端证书和私钥应分别通过 SetCertificate 和 SetPrivateKey
    ///   设置。应先添加至少一个 CA，再设置 VerifyPeer=True，并且必须在
    ///   首个 HTTPS 连接创建前完成配置。可多次调用以累积 CA，也可一次
    ///   传入 PEM bundle；自签名服务端证书也可以作为信任锚直接添加。
    /// </remarks>
    /// <param name="ABuf">
    ///   CA 证书或 PEM bundle 内存指针
    /// </param>
    /// <param name="ASize">
    ///   CA 证书缓冲区大小
    /// </param>
    procedure AddCACertificate(const ABuf: Pointer;
      const ASize: Integer); overload;
    /// <summary>
    ///   从字节数组追加用于验证 HTTPS 服务端证书链的受信任 CA 证书
    /// </summary>
    /// <param name="ABytes">
    ///   CA 证书或 PEM bundle 字节数组
    /// </param>
    procedure AddCACertificate(const ABytes: TBytes); overload;
    /// <summary>
    ///   从字符串追加用于验证 HTTPS 服务端证书链的受信任 CA 证书
    /// </summary>
    /// <param name="AText">
    ///   CA 证书或 PEM bundle 字符串
    /// </param>
    procedure AddCACertificate(const AText: string); overload;
    /// <summary>
    ///   从文件追加用于验证 HTTPS 服务端证书链的受信任 CA 证书
    /// </summary>
    /// <param name="AFileName">
    ///   CA 证书或 PEM bundle 文件路径
    /// </param>
    procedure AddCACertificateFile(const AFileName: string);

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
    ///   gzip/deflate 解压时的最大压缩比 (DecodedSize / EncodedSize)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>&gt; 0, 解压输出与输入比超过该值则按 zip bomb 拒绝 (400)</item>
    ///     <item>= 0, 不做压缩比检查</item>
    ///   </list>
    ///   合法 gzip 通常 1.5-15:1, 极规整数据可达 100-500:1
    ///   经典 zip bomb 1000:1 起 (42.zip ~100000:1), 默认 1000:1 兜底拦截 bomb
    /// </remarks>
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;

    /// <summary>
    ///   是否重用连接
    /// </summary>
    property ReUseConnection: Boolean read GetReUseConnection write SetReUseConnection;

    /// <summary>
    ///   请求超时时间(秒, 从请求发送成功之后算起, 设置为0则不检查超时)
    /// </summary>
    property RequestTimeout: Integer read GetRequestTimeout write SetRequestTimeout;

    /// <summary>
    ///   连接建立超时时间(秒, 适用于 csConnecting 状态, 设置为<=0则不检查连接超时)
    /// </summary>
    /// <remarks>
    ///   独立于 RequestTimeout 与 Idleout: RequestTimeout 是请求发送/响应阶段超时, Idleout 是已连接空闲连接的回收;
    ///   ConnectTimeout 专门处理 ConnectEx 投递成功但 SYN 永远收不到响应的退化场景
    /// </remarks>
    property ConnectTimeout: Integer read GetConnectTimeout write SetConnectTimeout;

    /// <summary>
    ///   自动对url参数进行编码(默认为True)
    /// </summary>
    property AutoUrlEncode: Boolean read GetAutoUrlEncode write SetAutoUrlEncode;

    /// <summary>
    ///   本地端口(一般不需要指定, 设置为0由系统随机分配, 默认为0; 一定要在首次调用请求之前设置)
    /// </summary>
    property LocalPort: Word read GetLocalPort write SetLocalPort;

    /// <summary>
    ///   是否强制验证对端证书。服务端要求客户端证书，客户端同时验证服务端主机名。
    /// </summary>
    property VerifyPeer: Boolean read GetVerifyPeer write SetVerifyPeer;
    property ProxySettings: TCrossProxySettings read GetProxySettings write SetProxySettings;
  end;

  TCrossHttpClientConnection = class(TCrossSslConnection, ICrossHttpClientConnection)
  private
    FProtocol, FRawHost, FHost: string;
    FPort: Word;
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
    FHttpParser: ICrossHttpParser;
    FReqLock: ILock;
    FSendFinished, FResponseFinished: Boolean;
    FResponseReady, FResponseMustClose: Boolean;
    FReceiveDepth: Integer;
    FDeferredReceiveFailure: Boolean;
    FDeferredReceiveCode: Integer;
    FDeferredReceiveText: string;
    FFinishReceivePending: Boolean;
    FResponseStatus: TRequestStatus;
    FPreserveResponseEntity: Boolean;
    FResponseStorage: THttpResponseStorageOptions;

    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValues: TArray<string>): Boolean;
    procedure _OnBodyBegin;
    procedure _OnBodyPolicy(var APreserveEntity: Boolean);
    procedure _OnBodyData(const ADataPtr: Pointer; const ADataSize: Integer);
    procedure _OnBodyEnd;
    procedure _OnParseBegin;
    procedure _OnParseSuccess;
    procedure _OnParseFailed(const ACode: Integer; const AError: string);

    procedure _BeginRequest; inline;
    function _TryBeginRequest: Boolean;
    procedure _CloseIfTimeout(const AConnecting: Boolean);
    procedure _EndRequest; inline;
    function _IsIdle: Boolean; inline;
    procedure _UpdateWatch;
    function _IsIdleout: Boolean;
    function _IsRequestTimeout: Boolean;
    function _IsConnectTimeout: Boolean;
    function _SetRequestStatus(const AStatus: TRequestStatus): TRequestStatus;

    procedure _ReqLock; inline;
    procedure _ReqUnlock; inline;
    function _CreateRequestHeader(const ABodySize: Int64; AChunked: Boolean): TBytes;
    procedure _RequestSendDone(const ARequest: ICrossHttpClientRequest;
      const ASuccess: Boolean; const AAfterSend: TProc);
    procedure _LeaveReceive;
    procedure _FinishReceive;
  protected
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
    procedure _SocketSend(const ASource: TCrossHttpChunkDataFunc;
      const ASendCb: TCrossConnectionCallback = nil;
      const ASourceFinished: TFunc<Boolean> = nil);
    procedure _HttpSend(const AHeaderSource, ABodySource: TCrossHttpChunkDataFunc;
      const ASendCb: TCrossConnectionCallback = nil;
      const ABodyFinished: TFunc<Boolean> = nil);
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
    /// <remarks>
    ///   ABody 指向的内存必须在请求完成回调(ACallback)执行完成前一直有效。
    ///   调用方不应在 DoRequest 返回后立即释放 ABody 指向的数据。
    /// </remarks>
    procedure SendZCompress(const ABody: Pointer;
      const ABodySize: NativeInt; const ACompressType: TCompressType;
      const ASendCb: TCrossConnectionCallback = nil); overload;
    {$endregion}

    // 所有请求方法的核心
    procedure DoRequest(const ARequest: ICrossHttpClientRequest;
      const ACallback: TCrossHttpResponseProc; const AAfterSend: TProc = nil);
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
    FUrlReady: Boolean;
    FQuery: THttpUrlParams;
    FRequestBodyFunc: TCrossHttpChunkDataFunc;
    FRequestBody: Pointer;
    FRequestBodySize: NativeInt;
    FResponseStream: TStream;
    FInitProc: TCrossHttpRequestInitProc;
    FCallback: TCrossHttpResponseProc;
    FCompleted: Integer;
    FStateLock: ILock;
    FAdmission: IInterface;
    FAdmissionReleased: Integer;
    FSendState: Integer; // 0 尚未开始，1 发送链使用中，2 已不再使用。
    FSendCb: TCrossHttpRequestSendProc;
    FSeparateSend: Boolean;
    FDeferredResponse: ICrossHttpClientResponse;
    FDeferredCallback: TCrossHttpResponseProc;

    FHttpVersion: THttpVersion;
    FMethod: string;
    FPathAndParams, FPath: string;
    FHeader: THttpHeader;
    FCookies: TRequestCookies;

    procedure _ParseUrl;
    procedure _Init(
      const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBodyFunc: TCrossHttpChunkDataFunc;
      const ARequestBody: Pointer;
      const ABodySize: NativeInt;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc);
    procedure _ExecCallback(const AResponse: ICrossHttpClientResponse);
    procedure _ReleaseAdmission;
    procedure _CancelSendBeforeStart;
    procedure _NotifySend(const ASuccess: Boolean);
  protected
    function GetConnection: ICrossHttpClientConnection;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
    function GetMethod: string;
    function GetPath: string;
    function GetPathAndParams: string;
    function GetQuery: THttpUrlParams;
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
    property Method: string read GetMethod;
    property Path: string read GetPath;
    property PathAndParams: string read GetPathAndParams;
    property Query: THttpUrlParams read GetQuery;
  end;

  TCrossHttpClientResponse = class(TInterfacedObject, ICrossHttpClientResponse)
  private
    FConnection: ICrossHttpClientConnection;
    FConnectionObj: TCrossHttpClientConnection;

    FHttpVer: string;
    FStatusCode: Integer;
    FStatusText: string;
    FContentType: string;
    FContentLength: Int64;
    FTransferEncoding, FContentEncoding: string;
    FIsChunked: Boolean;
    FKeepAlive: Boolean;

    FHeader: THttpHeader;
    FCookies: TResponseCookies;

    FResponseBodyStream: TStream;
    FNeedFreeResponseBodyStream: Boolean;
    FStorageOptions: THttpResponseStorageOptions;

    procedure _SetResponseStream(const AValue: TStream);
  protected
    // ADataPtr 是 Parser 已收齐的响应头；ADataSize 为字节数，含状态行和最终空行，不含正文。
    // 输入仅在调用期间借用；各 Header 项复制自己的值数据。语法失败返回 False，
    // 由 _OnHeaderData 交给 Parser.Fail；字符转换异常保留外层 Parser 的处理路径。
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

    // 具体类提供已解析的协议版本，保持既有接口布局不变。
    property Version: string read FHttpVer;
    property Connection: ICrossHttpClientConnection read GetConnection;
    property Header: THttpHeader read GetHeader;
    property Cookies: TResponseCookies read GetCookies;
    property Content: TStream read GetContent;
    property ContentType: string read GetContentType;
    property StatusCode: Integer read GetStatusCode;
    property StatusText: string read GetStatusText;
  end;

  TRequestQueue = {$IFDEF FPC}TFpcQueue{$ELSE}TQueue{$ENDIF}<ICrossHttpClientRequest>;
  TClientConnections = TList<ICrossHttpClientConnection>;

  /// <summary>
  ///   ServerDock 对外接口: 通过引用计数保证持有方在锁外使用期间对象不被释放
  /// </summary>
  IServerDock = interface
    ['{6B532075-C9A6-42FE-B1C6-2F0BFD70EACF}']
    procedure AddConnection(const AConnection: ICrossHttpClientConnection);
    procedure RemoveConnection(const AConnection: ICrossHttpClientConnection);
    function  GetConnsCount: Integer;
    function  GetIdleConnection: ICrossHttpClientConnection;

    procedure PushRequest(const ARequest: ICrossHttpClientRequest);
    function  PopRequest(out ARequest: ICrossHttpClientRequest): Boolean;
    procedure CancelAllRequests(const AStatusCode: Integer; const AStatusText: string);

    procedure ProcNext;

    // 请求入口: 优先复用空闲连接, 否则异步建立新连接后发起
    procedure DoRequest(const ARequest: ICrossHttpClientRequest);
  end;

  TServerDock = class(TInterfacedObject, IServerDock)
  private
    FClientSocket: TCrossHttpClientSocket;
    FProtocol, FRawHost, FHost: string;
    FPort, FLocalPort: Word;
    FRequestQueue: TRequestQueue;
    FConnections: TClientConnections;
    FConnCount, FConnectingCount: Integer;
    FLock: ILock;
    FRequestLimit: Integer;
    FRequestCount: IInterface;

    procedure _Lock; inline;
    procedure _Unlock; inline;
    function _IsClosing: Boolean; inline;
    procedure _CancelRequest(const ARequest: TCrossHttpClientRequest);
    function _TryBeginConnect: Boolean;
    function _TryAdmitRequest(const ARequest: TCrossHttpClientRequest): Boolean;
    procedure _EndConnect;

    // 在指定连接上执行请求(仅内部使用: 空闲连接复用路径 与 Connect 成功回调路径)
    procedure _DoRequestOn(const AHttpConn: ICrossHttpClientConnection;
      const ARequest: ICrossHttpClientRequest);

    procedure _HandleConnectSuccess(const AConnection: ICrossConnection;
      const ARequest: ICrossHttpClientRequest; const ALSelf: IServerDock;
      const AProtocol, ARawHost, AHost: string; const APort: Word);
    procedure _HandleConnectFailure(const AConnection: ICrossConnection;
      const ARequestObj: TCrossHttpClientRequest; const ALSelf: IServerDock);
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
    procedure CancelAllRequests(const AStatusCode: Integer; const AStatusText: string);

    procedure ProcNext;

    // 所有请求方法的核心
    procedure DoRequest(const ARequest: ICrossHttpClientRequest);
  end;

  TServerDockDict = TDictionary<string, IServerDock>;

  TCrossHttpClientSocket = class(TCrossSslSocket, ICrossHttpClientSocket)
  private
    FHttpClient: TCrossHttpClient;
    FReUseConnection, FAutoUrlEncode: Boolean;
    FCompressType: TCompressType;
    FMaxConnsPerServer, FMaxCompressRatio: Integer;
    FServerDockDict: TServerDockDict;
    FServerDockLock: ILock;
    FLocalPort: Word;
    FProxySettings: TCrossProxySettings;

    procedure _LockServerDock; inline;
    procedure _UnlockServerDock; inline;

    function _MakeServerDockKey(const AProtocol, AHost: string; const APort: Word): string;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word;
      out AServerDock: IServerDock): Boolean; overload;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word): IServerDock; overload;
  protected
    function GetLocalPort: Word;
    procedure SetLocalPort(const AValue: Word);
    procedure ConnectTarget(const APhysicalHost: string;
      const APhysicalPort, ALocalPort: Word; const ALogicalHost: string;
      const ALogicalPort: Word;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    procedure SyncProxySettings(const AValue: TCrossProxySettings);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure PrepareConnection(const AConnection: ICrossConnection;
      const ALogicalHost: string; const ALogicalPort: Word); override;
    procedure TriggerConnecting(const AConnection: ICrossConnection); override;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
  public
    constructor Create(const AHttpClient: TCrossHttpClient;
      const AIoThreads, AMaxConnsPerServer, AMaxCompressRatio: Integer;
      const ASsl, AReUseConnection, AAutoUrlEncode: Boolean;
      const ACompressType: TCompressType = ctNone); reintroduce; virtual;
    destructor Destroy; override;

    procedure CancelAllRequests;
    procedure SyncOptions(const AMaxConnsPerServer, AMaxCompressRatio: Integer;
      const AReUseConnection, AAutoUrlEncode: Boolean);

    // 所有请求方法的核心
    procedure DoRequest(const ARequest: ICrossHttpClientRequest); overload;

    property LocalPort: Word read GetLocalPort write SetLocalPort;
  end;

  TCrossHttpClient = class(TInterfacedObject, ICrossHttpClient, ICrossHttpClientSend,
    ICrossHttpClientEntity, ICrossHttpClientResponseStorage)
  private
    class var FDefaultIOThreads: Integer;
    class var FDefault: ICrossHttpClient;

    class constructor Create;
    class function GetDefault: ICrossHttpClient; static;
  private
    FIoThreads, FMaxConnsPerServer, FMaxCompressRatio: Integer;
    FMaxPendingRequestsPerServer: Integer;
    FClosing: Integer;
    FCompressType: TCompressType;
    FLock: ILock;
    FTimer: IEasyTimer;
    FHttpCli, FHttpsCli: ICrossHttpClientSocket;
    FHttpCliArr: TArray<ICrossHttpClientSocket>;
    FRequestTimeout, FIdleout, FConnectTimeout: Integer;
    FReUseConnection, FAutoUrlEncode: Boolean;
    FPreserveResponseEntity: Boolean;
    FResponseStorage: THttpResponseStorageOptions;
    FLocalPort: Word;
    FVerifyPeer: Boolean;
    FProxySettings: TCrossProxySettings;
    FCertificate, FPrivateKey: TBytes;
    FPrivateKeyPassword: string;
    FCACertificates: TArray<TBytes>;

    procedure _ProcTimeout;
    procedure _UpdateCliOptions;
    procedure _ApplyTlsOptions(const ACli: ICrossHttpClientSocket);
    procedure _SubmitRequest(const ARequest: ICrossHttpClientRequest);
  protected
    procedure _Lock; inline;
    procedure _Unlock; inline;

    function CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket; virtual;

    function GetIdleout: Integer;
    function GetIoThreads: Integer;
    function GetMaxConnsPerServer: Integer;
    function GetMaxCompressRatio: Integer;
    function GetReUseConnection: Boolean;
    function GetRequestTimeout: Integer;
    function GetConnectTimeout: Integer;
    function GetAutoUrlEncode: Boolean;
    function GetLocalPort: Word;
    function GetVerifyPeer: Boolean;
    function GetProxySettings: TCrossProxySettings;
    function GetPreserveResponseEntity: Boolean;
    procedure SetPreserveResponseEntity(const AValue: Boolean);
    procedure SetResponseStorageOptions(const AValue: THttpResponseStorageOptions);
    function GetResponseStorageOptions: THttpResponseStorageOptions;

    procedure SetIdleout(const AValue: Integer);
    procedure SetIoThreads(const AValue: Integer);
    procedure SetMaxConnsPerServer(const AValue: Integer);
    procedure SetMaxCompressRatio(const AValue: Integer);
    procedure SetReUseConnection(const AValue: Boolean);
    procedure SetRequestTimeout(const AValue: Integer);
    procedure SetConnectTimeout(const AValue: Integer);
    procedure SetAutoUrlEncode(const AValue: Boolean);
    procedure SetLocalPort(const AValue: Word);
    procedure SetVerifyPeer(const AValue: Boolean);
    procedure SetProxySettings(const AValue: TCrossProxySettings); virtual;
  public
    constructor Create(const AIoThreads, AMaxConnsPerServer: Integer;
      const ACompressType: TCompressType = ctNone); overload;
    constructor Create(const AIoThreads: Integer = 4;
      const ACompressType: TCompressType = ctNone); overload;
    destructor Destroy; override;

    procedure Prepare(const AProtocols: array of string);

    procedure CancelAll; virtual;
    procedure DoRequestWithSend(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody, AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ASendCb: TCrossHttpRequestSendProc;
      const AResponseCb: TCrossHttpResponseProc);

    procedure SetCertificate(const ACertBuf: Pointer;
      const ACertBufSize: Integer); overload;
    procedure SetCertificate(const ACertBytes: TBytes); overload;
    procedure SetCertificate(const ACertStr: string); overload;
    procedure SetCertificateFile(const ACertFile: string);

    procedure SetPrivateKey(const APKeyBuf: Pointer;
      const APKeyBufSize: Integer; const APassword: string = ''); overload;
    procedure SetPrivateKey(const APKeyBytes: TBytes;
      const APassword: string = ''); overload;
    procedure SetPrivateKey(const APKeyStr: string;
      const APassword: string = ''); overload;
    procedure SetPrivateKeyFile(const APKeyFile: string;
      const APassword: string = '');

    procedure AddCACertificate(const ABuf: Pointer;
      const ASize: Integer); overload;
    procedure AddCACertificate(const ABytes: TBytes); overload;
    procedure AddCACertificate(const AText: string); overload;
    procedure AddCACertificateFile(const AFileName: string);

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
    // 首次请求前配置；每个新 server 池快照，已有池不追溯修改。<=0 不限。
    // 包括排队、连接建立中和活动请求，完成/取消后归还额度。
    property MaxPendingRequestsPerServer: Integer read FMaxPendingRequestsPerServer write FMaxPendingRequestsPerServer;
    property MaxConnsPerServer: Integer read GetMaxConnsPerServer write SetMaxConnsPerServer;
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;
    property ReUseConnection: Boolean read GetReUseConnection write SetReUseConnection;
    property RequestTimeout: Integer read GetRequestTimeout write SetRequestTimeout;
    property ConnectTimeout: Integer read GetConnectTimeout write SetConnectTimeout;
    property AutoUrlEncode: Boolean read GetAutoUrlEncode write SetAutoUrlEncode;
    property LocalPort: Word read GetLocalPort write SetLocalPort;
    property VerifyPeer: Boolean read GetVerifyPeer write SetVerifyPeer;
    property ProxySettings: TCrossProxySettings read GetProxySettings write SetProxySettings;
  end;

const
  SND_BUF_SIZE = 32768;

{$IFDEF CROSS_HTTP_TIMEOUT_TESTS}
type THttpTimeoutCollectedProc = reference to procedure;
procedure StopHttpTimeoutTimerForTest(const AClient: TCrossHttpClient);
procedure ProcHttpTimeoutForTest(const AClient: TCrossHttpClient;
  const AAfterCollect: THttpTimeoutCollectedProc);
{$ENDIF}

{$IFDEF CROSS_CAPACITY_TESTS}
type TClientAdmissionTestProc = reference to procedure(const AStage: string;
  const ARequest: ICrossHttpClientRequest);
procedure SetClientAdmissionTestHook(const AHook: TClientAdmissionTestProc);
{$ENDIF}

{$IFDEF CROSS_HTTP_SEND_TESTS}
type
  THttpSendTestWrite = reference to procedure(const AConnection: ICrossConnection;
    const ABuffer: Pointer; const ACount: Integer; const ACallback: TCrossConnectionCallback);
  THttpSendTestSubmit = reference to procedure(const AClient: TCrossHttpClient;
    const ARequest: ICrossHttpClientRequest);
  THttpSendTestTempStreamFactory = reference to function(const APath: string): TStream;
procedure SetHttpSendTestHooks(const AWrite: THttpSendTestWrite;
  const ASubmit: THttpSendTestSubmit);
procedure SetHttpSendTestTempStreamFactory(const AFactory: THttpSendTestTempStreamFactory);
function HttpSendTestPendingRequests(const AConnection: ICrossHttpClientConnection): Integer;
function NewHttpSendTestConnection(const AClient: TCrossHttpClient): ICrossHttpClientConnection;
procedure StartHttpSendTestRequest(const AConnection: ICrossHttpClientConnection;
  const ARequest: ICrossHttpClientRequest);
procedure RespondHttpSendTestRequest(const AConnection: ICrossHttpClientConnection;
  const AStatus: Integer; const AKeepAlive: Boolean = True);
procedure CancelHttpSendTestRequest(const AConnection: ICrossHttpClientConnection);
procedure CancelHttpSendTestQueued(const ARequest: ICrossHttpClientRequest);
function HttpSendTestIsIdle(const AConnection: ICrossHttpClientConnection): Boolean;
function HttpSendTestLiveConnections: Integer;
procedure ReceiveHttpSendTestResponse(const AConnection: ICrossHttpClientConnection; const AData: TBytes);
{$ENDIF}

implementation

{$IFDEF CROSS_HTTP_SEND_TESTS}
type
  THttpSendTestConnection = class(TCrossHttpClientConnection)
  public
    Counted: Boolean;
    destructor Destroy; override;
  end;
var
  GHttpSendTestWrite: THttpSendTestWrite;
  GHttpSendTestSubmit: THttpSendTestSubmit;
  GHttpSendTestTempStreamFactory: THttpSendTestTempStreamFactory;
  GHttpSendTestConnections: Integer;

destructor THttpSendTestConnection.Destroy;
begin
  try
    inherited;
  finally
    if Counted then AtomicDecrement(GHttpSendTestConnections);
  end;
end;

function HttpSendTestLiveConnections: Integer;
begin
  Result := AtomicCmpExchange(GHttpSendTestConnections, 0, 0);
end;

procedure SetHttpSendTestHooks(const AWrite: THttpSendTestWrite;
  const ASubmit: THttpSendTestSubmit);
begin
  GHttpSendTestWrite := AWrite;
  GHttpSendTestSubmit := ASubmit;
end;

procedure SetHttpSendTestTempStreamFactory(const AFactory: THttpSendTestTempStreamFactory);
begin
  GHttpSendTestTempStreamFactory := AFactory;
end;

function HttpSendTestPendingRequests(const AConnection: ICrossHttpClientConnection): Integer;
var
  LConnection: TCrossHttpClientConnection;
begin
  LConnection := AConnection as TCrossHttpClientConnection;
  LConnection._ReqLock;
  try
    Result := LConnection.FPending;
  finally
    LConnection._ReqUnlock;
  end;
end;

function NewHttpSendTestConnection(const AClient: TCrossHttpClient): ICrossHttpClientConnection;
var
  LSocket: ICrossHttpClientSocket;
  LConnection: THttpSendTestConnection;
begin
  LSocket := AClient.CreateHttpCli(HTTP);
  LConnection := THttpSendTestConnection.Create(LSocket as TCrossHttpClientSocket,
    INVALID_SOCKET, ctConnect, '127.0.0.1', nil);
  Result := LConnection;
  LConnection.Counted := True;
  AtomicIncrement(GHttpSendTestConnections);
  LConnection.ConnectStatus := csConnected;
  LConnection.FProtocol := HTTP;
  LConnection.FHost := '127.0.0.1';
  LConnection.FRawHost := '127.0.0.1';
  LConnection.FPort := 80;
end;

procedure StartHttpSendTestRequest(const AConnection: ICrossHttpClientConnection;
  const ARequest: ICrossHttpClientRequest);
var
  LConnection: TCrossHttpClientConnection;
begin
  LConnection := AConnection as TCrossHttpClientConnection;
  if LConnection._IsIdle then LConnection._TryBeginRequest;
  LConnection.DoRequest(ARequest,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      (ARequest as TCrossHttpClientRequest)._ExecCallback(AResponse);
    end);
end;

procedure RespondHttpSendTestRequest(const AConnection: ICrossHttpClientConnection;
  const AStatus: Integer; const AKeepAlive: Boolean);
var
  LConnection: TCrossHttpClientConnection;
begin
  LConnection := AConnection as TCrossHttpClientConnection;
  LConnection.FResponse := TCrossHttpClientResponse.Create(AStatus);
  LConnection.FResponseObj := LConnection.FResponse as TCrossHttpClientResponse;
  LConnection.FResponseObj.FKeepAlive := AKeepAlive;
  LConnection.TriggerResponseSuccess;
end;

procedure CancelHttpSendTestRequest(const AConnection: ICrossHttpClientConnection);
begin
  AConnection.Close;
  (AConnection as TCrossHttpClientConnection).TriggerResponseFailed(400, 'test canceled');
end;

procedure CancelHttpSendTestQueued(const ARequest: ICrossHttpClientRequest);
begin
  (ARequest as TCrossHttpClientRequest)._ExecCallback(
    TCrossHttpClientResponse.Create(400, 'test queued canceled'));
end;

function HttpSendTestIsIdle(const AConnection: ICrossHttpClientConnection): Boolean;
begin
  Result := (AConnection as TCrossHttpClientConnection)._IsIdle;
end;

procedure ReceiveHttpSendTestResponse(const AConnection: ICrossHttpClientConnection; const AData: TBytes);
var
  P: Pointer;
  N: Integer;
begin
  if Length(AData) = 0 then Exit;
  P := @AData[0];
  N := Length(AData);
  while N > 0 do (AConnection as TCrossHttpClientConnection).ParseRecvData(P, N);
end;
{$ENDIF}

{$IFDEF CROSS_CAPACITY_TESTS}
var GClientAdmissionTestHook: TClientAdmissionTestProc;
procedure SetClientAdmissionTestHook(const AHook: TClientAdmissionTestProc);
begin GClientAdmissionTestHook := AHook; end;
procedure _ClientAdmissionTest(const AStage: string; const ARequest: ICrossHttpClientRequest);
begin if Assigned(GClientAdmissionTestHook) then GClientAdmissionTestHook(AStage, ARequest); end;
{$ENDIF}

{$IFDEF CROSS_HTTP_TIMEOUT_TESTS}
var GHttpTimeoutAfterCollect: THttpTimeoutCollectedProc;
procedure StopHttpTimeoutTimerForTest(const AClient: TCrossHttpClient);
begin
  if AClient.FTimer <> nil then
  begin
    AClient.FTimer.Terminate;
    AClient.FTimer.WaitFor;
    AClient.FTimer := nil;
  end;
end;
procedure ProcHttpTimeoutForTest(const AClient: TCrossHttpClient;
  const AAfterCollect: THttpTimeoutCollectedProc);
begin
  GHttpTimeoutAfterCollect := AAfterCollect;
  try AClient._ProcTimeout; finally GHttpTimeoutAfterCollect := nil; end;
end;
{$ENDIF}

// 请求只持计数状态，不反向持有 server 池，避免队列与请求形成引用环。
type
  THttpRequestCount = class(TInterfacedObject)
  public
    Lock: ILock;
    Count: Integer;
    procedure ReleaseRequest;
  end;

procedure THttpRequestCount.ReleaseRequest;
begin
  Lock.Enter;
  try
    Dec(Count);
  finally
    Lock.Leave;
  end;
end;

{ TCrossHttpClientConnection }

constructor TCrossHttpClientConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
var
  LHttpClientSocket: TCrossHttpClientSocket;
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);

  LHttpClientSocket := AOwner as TCrossHttpClientSocket;

  FHttpParser := TCrossHttpParser.Create(pmClient);
  // 透传压缩比限制 (zip bomb 防御); 直接读 socket 字段, 与其它配置 (CompressType / AutoUrlEncode) 取值方式一致
  FHttpParser.MaxCompressRatio := LHttpClientSocket.FMaxCompressRatio;
  FHttpParser.OnHeaderData := _OnHeaderData;
  FHttpParser.OnGetHeaderValue := _OnGetHeaderValue;
  FHttpParser.OnBodyBegin := _OnBodyBegin;
  (FHttpParser as TCrossHttpParser).OnBodyPolicy := _OnBodyPolicy;
  FPreserveResponseEntity := LHttpClientSocket.FHttpClient.GetPreserveResponseEntity;
  FResponseStorage := LHttpClientSocket.FHttpClient.GetResponseStorageOptions;
  FHttpParser.OnBodyData := _OnBodyData;
  FHttpParser.OnBodyEnd := _OnBodyEnd;
  FHttpParser.OnParseBegin := _OnParseBegin;
  FHttpParser.OnParseSuccess := _OnParseSuccess;
  FHttpParser.OnParseFailed := _OnParseFailed;

  FWatch := TSimpleWatch.Create;
  FReqLock := TLock.Create;

  // 肯定是要发起请求才会新建连接
  // 所以直接将连接状态锁定
  // 避免被别的请求占用
  _BeginRequest;

  FCompressType := LHttpClientSocket.FCompressType;
  FAutoUrlEncode := LHttpClientSocket.FAutoUrlEncode;
end;

procedure TCrossHttpClientConnection.DoRequest(const ARequest: ICrossHttpClientRequest;
  const ACallback: TCrossHttpResponseProc; const AAfterSend: TProc);
var
  LConnection: ICrossHttpClientConnection;
  LRequestObj: TCrossHttpClientRequest;
  LRequest: ICrossHttpClientRequest;
  LSendCb: TCrossConnectionCallback;
  LChunkDataFunc: TCrossHttpChunkDataFunc;
  LRequestBody: Pointer;
  LRequestBodySize: NativeInt;
begin
  LConnection := Self;
  LRequest := ARequest;
  LRequestObj := ARequest as TCrossHttpClientRequest;
  // 排队取消与真正开始发送竞争同一个状态，取消后不能再读取正文。
  if AtomicCmpExchange(LRequestObj.FSendState, 1, 0) <> 0 then
  begin
    _EndRequest;
    Close;
    Exit;
  end;
  LRequestObj.FConnection := LConnection;

  _ReqLock;
  try
    // 保存请求对象
    FRequestObj := LRequestObj;
    FRequest := ARequest;
    FSendFinished := False;
    FResponseFinished := False;
    FResponseReady := False;
    FResponseMustClose := False;
    FResponseStatus := rsIdle;
    _SetRequestStatus(rsSending);

    // 设置响应回调
    if Assigned(ACallback) then
      FCallback := ACallback
    else
      FCallback := FRequestObj.FCallback;
  finally
    _ReqUnlock;
  end;

  LSendCb :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 独立持有请求。早响应可以移除响应回调，但不能销毁正在使用的头/正文。
      _RequestSendDone(LRequest, ASuccess, AAfterSend);
    end;
  try
    // 调用初始化函数
    if Assigned(LRequestObj.FInitProc) then
      LRequestObj.FInitProc(ARequest);
    if IsClosed then
    begin
      LSendCb(LConnection, False);
      TriggerResponseFailed(400, 'Connection closed before send');
      Exit;
    end;

    // HEAD 按无正文发送，跳过正文预读和压缩。
    if (LRequestObj.FMethod = THttpMethod.HEAD) then
    begin
      SendNoCompress(Pointer(nil), 0, LSendCb);
      Exit;
    end;

    // 压缩方式
    if (FCompressType <> ctNone) then
      LRequestObj.FHeader[HEADER_CONTENT_ENCODING] := ZLIB_CONTENT_ENCODING[FCompressType];

    LChunkDataFunc := LRequestObj.FRequestBodyFunc;
    LRequestBody := LRequestObj.FRequestBody;
    LRequestBodySize := LRequestObj.FRequestBodySize;

    // 发起请求
    if Assigned(LChunkDataFunc) then
    begin
      SendZCompress(
        LChunkDataFunc,
        FCompressType, LSendCb);
    end else
    begin
      SendZCompress(
        LRequestBody,
        LRequestBodySize,
        FCompressType, LSendCb);
    end;
  except
    on E: Exception do
    begin
      // 初始化、首块读取及构造发送源失败时还没有在途物理写。
      // 已同步完成后再抛出的异常由请求的一次性状态忽略。
      LSendCb(LConnection, False);
      TriggerResponseFailed(400, 'Internal: ' + E.Message);
    end;
  end;
end;

procedure TCrossHttpClientConnection._RequestSendDone(
  const ARequest: ICrossHttpClientRequest; const ASuccess: Boolean;
  const AAfterSend: TProc);
var
  LRequestObj: TCrossHttpClientRequest;
  LResponseFinished, LClose: Boolean;
begin
  LRequestObj := ARequest as TCrossHttpClientRequest;
  if AtomicCmpExchange(LRequestObj.FSendState, 2, 1) <> 1 then Exit;
  _ReqLock;
  try
    FSendFinished := True;
    LResponseFinished := FResponseFinished;
    LClose := LResponseFinished and (FResponseStatus = rsClose);
    if LResponseFinished then
    begin
      FRequest := nil;
      FRequestObj := nil;
      _SetRequestStatus(FResponseStatus);
      _EndRequest;
    end else if RequestStatus = rsSending then
      _SetRequestStatus(rsResponding);
  finally
    _ReqUnlock;
  end;
  if LClose then
  try Close; except on E: Exception do _Log('HTTP send-close exception: %s', [E.Message]); end;
  LRequestObj._NotifySend(ASuccess);
  // 早响应已经尝试过 ProcNext；直到本次发送退出才有可复用的连接。
  if LResponseFinished and Assigned(AAfterSend) then
  try AAfterSend; except on E: Exception do _Log('HTTP after-send exception: %s', [E.Message]); end;
end;

destructor TCrossHttpClientConnection.Destroy;
begin
  if Assigned(FCallback) then
    TriggerResponseFailed(400, 'Connection destroyed');

  FHttpParser := nil;

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

procedure TCrossHttpClientConnection.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
var
  LKeep: ICrossHttpClientConnection;
  LReject, LClose: Boolean;
begin
  LKeep := Self;
  _ReqLock;
  try
    // 检查与登记接收共用请求锁，超时先清理时不能再进入解析。
    LReject := IsClosed or (FRequest = nil) or (FRequestObj = nil)
      or FResponseFinished or FResponseReady or FDeferredReceiveFailure
      or not (RequestStatus in [rsSending, rsResponding]);
    LClose := LReject and not IsClosed;
    if LClose then
    begin
      FResponseMustClose := True;
      if (FResponseFinished or FResponseReady) and not FSendFinished
        and (FResponseStatus in [rsIdle, rsClose]) then
      begin
        // 已成功的早响应仍需保活在途发送，发送结束后按关闭意图收尾。
        FResponseStatus := rsClose;
        LClose := False;
      end else
      if RequestStatus = rsIdle then
        _SetRequestStatus(rsClose);
    end;
    if not LReject then Inc(FReceiveDepth);
  finally
    _ReqUnlock;
  end;
  if LReject then
  begin
    ABuf := PByte(ABuf) + ALen;
    ALen := 0;
    if LClose then Close;
    Exit;
  end;
  try
    _UpdateWatch;

//  _Log('ParseRecvData, %s, 0x%x, %d', [Self.DebugInfo, NativeUInt(ABuf), ALen]);
    if (FHttpParser <> nil) then
      FHttpParser.Decode(ABuf, ALen)
    else
      ALen := 0;
    _ReqLock;
    try
      // 普通最终响应的尾部必须在回调和回池之前处理，不能归给下一请求。
      if FResponseReady and (ALen > 0) then
      begin
        FResponseMustClose := True;
        ABuf := PByte(ABuf) + ALen;
        ALen := 0;
      end;
    finally
      _ReqUnlock;
    end;
  finally
    _LeaveReceive;
  end;
end;

procedure TCrossHttpClientConnection._LeaveReceive;
var
  LFailCode: Integer;
  LFailText: string;
  LFinish, LFail, LSuccess: Boolean;
begin
  LSuccess := False;
  LFailCode := 0;
  LFinish := False;
  LFail := False;
  _ReqLock;
  try
    Dec(FReceiveDepth);
    if FReceiveDepth = 0 then
    begin
      LFinish := FFinishReceivePending;
      FFinishReceivePending := False;
      if FDeferredReceiveFailure then
      begin
        LFail := True;
        LFailCode := FDeferredReceiveCode;
        LFailText := FDeferredReceiveText;
        FDeferredReceiveFailure := False;
        FDeferredReceiveText := '';
      end;
      // 写入异常、超时和解码内重入关闭优先；EOF 的 Finish 也从这里发布成功。
      LSuccess := FResponseReady and not LFail and not LFinish;
      // 成功标志保留到终态认领，关闭线程仍能识别已完整接收的响应。
      if LFail or LFinish then FResponseReady := False;
    end;
  finally
    _ReqUnlock;
  end;
  // 包括流.Write重入Close；离开解码/写入栈后才通知调用方释放响应流。
  if LFail then TriggerResponseFailed(LFailCode, LFailText)
  else
  if LFinish then _FinishReceive
  else
  if LSuccess then TriggerResponseSuccess;
end;

procedure TCrossHttpClientConnection._FinishReceive;
var
  LKeep: ICrossHttpClientConnection;
  LComplete: Boolean;
begin
  LKeep := Self;
  _ReqLock;
  try
    if FReceiveDepth > 0 then
    begin
      if FResponseReady then
        FResponseMustClose := True
      else
        FFinishReceivePending := True;
      Exit;
    end;
    // 完整响应已就绪时关闭只影响复用，不能对已重置的 Parser 再报连接丢失。
    LComplete := FResponseReady and not FDeferredReceiveFailure and not FResponseFinished;
    if LComplete then FResponseMustClose := True
    else Inc(FReceiveDepth);
  finally
    _ReqUnlock;
  end;
  if LComplete then
  begin
    TriggerResponseSuccess;
    Exit;
  end;
  try
    if FHttpParser <> nil then FHttpParser.Finish;
  finally
    _LeaveReceive;
  end;
  TriggerResponseFailed(400, 'Connection lost');
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

  _HttpSend(
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
              TEncoding.ASCII.GetBytes(IntToHex(LChunkSize, 0)),
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
    end,
    function: Boolean
    begin
      Result := not LChunked or (LChunkState = csDone);
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

  _HttpSend(
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
    end,
    function: Boolean
    begin
      Result := LBodySize = 0;
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
    if Assigned(ASendCb) then ASendCb(Self, False);
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

procedure ReleaseFailedHttpResponse(var AResponse: ICrossHttpClientResponse);
begin
  try
    AResponse := nil;
  except
    on E: Exception do
      try
        _Log('HTTP failed response cleanup exception: %s', [E.Message]);
      except
        // 原始失败仍需通知；日志或二次刷新异常不能覆盖终态。
      end;
  end;
end;

procedure TCrossHttpClientConnection.TriggerResponseFailed(
  const AStatusCode: Integer; const AStatusText: string);
var
  LCallback: TCrossHttpResponseProc;
  LResponse, LDiscardedResponse: ICrossHttpClientResponse;
  LRequestEnded, LHandled, LDeferred: Boolean;
begin
  LCallback := nil;
  LRequestEnded := False;
  LHandled := False;
  LDeferred := False;
  _ReqLock;
  try
    // 只在请求进行中的状态才处理, 防止竞态下重复触发回调与 _EndRequest 多减计数
    if FResponseFinished
      or not (RequestStatus in [rsIdle, rsSending, rsResponding]) then Exit;

    if FReceiveDepth > 0 then
    begin
      if not FDeferredReceiveFailure then
      begin
        FDeferredReceiveFailure := True;
        FDeferredReceiveCode := AStatusCode;
        FDeferredReceiveText := AStatusText;
      end;
      LDeferred := True;
    end else
    begin
      LHandled := True;
      LCallback := FCallback;
      FCallback := nil;
      FResponseFinished := True;
      FResponseReady := False;
      if AStatusCode = 408 then FResponseStatus := rsRespondTimeout
      else FResponseStatus := rsRespondFailed;
      LRequestEnded := FSendFinished;

      _SetRequestStatus(FResponseStatus);
    end;
  finally
    if LRequestEnded then
    begin
      FRequest := nil;
      FRequestObj := nil;
    end;
    if LHandled then
    begin
      LDiscardedResponse := FResponse;
      FResponse := nil;
      FResponseObj := nil;
    end;

    _ReqUnlock;
    if LRequestEnded then
      _EndRequest;
  end;

  ReleaseFailedHttpResponse(LDiscardedResponse);
  try Close; except on E: Exception do _Log('HTTP failure-close exception: %s', [E.Message]); end;
  if LDeferred then Exit;

  if Assigned(LCallback) then
  try
    LResponse := TCrossHttpClientResponse.Create(AStatusCode, AStatusText);
    LCallback(LResponse);
  except
    on E: Exception do
      _Log('TriggerResponseFailed callback exception: %s', [E.Message]);
  end;
end;

procedure TCrossHttpClientConnection.TriggerResponseSuccess;
var
  LCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
  LRequestEnded, LIsSwitching, LHandled: Boolean;
  LNeedClose: Boolean;
begin
  LCallback := nil;
  LResponse := nil;
  LRequestEnded := False;
  LHandled := False;
  LNeedClose := False;
  _ReqLock;
  try
    // 只有在等待响应状态的情况才应该触发完成响应回调
    // 因为有可能响应完成的数据在超时后才到来, 这时候请求状态已经被置为超时
    // 不应该再触发完成回调
    if FResponseFinished or FDeferredReceiveFailure
      or not (RequestStatus in [rsSending, rsResponding]) then Exit;

    LHandled := True;
    LCallback := FCallback;
    FCallback := nil;
    LResponse := FResponse;
    FResponseFinished := True;
    FResponseReady := False;
    LRequestEnded := FSendFinished;

    // HTTP/1.1 101 Switching Protocols: 协议升级, 连接由上层协议(如 WebSocket)接管,
    // 不能 close, 也不能进入 idle 池被复用为 HTTP 请求.
    LIsSwitching := (FResponseObj <> nil)
      and (FResponseObj.FStatusCode = 101);

    if IsClosed or FResponseMustClose
      or ((not LIsSwitching)
        and ((not (Owner as TCrossHttpClientSocket).FReUseConnection)
          or ((FRequestObj <> nil) and FRequestObj.FHeader.ContainsToken(HEADER_CONNECTION, 'close'))
          or ((FResponseObj <> nil) and not FResponseObj.FKeepAlive))) then
    begin
      FResponseStatus := rsClose;
      // 最终响应可能早于最后一个物理写的完成通知。此时主动 Close
      // 会取消已经到达对端的尾块，并把正常 HTTP 转发误报为发送失败。
      if FSendFinished then _SetRequestStatus(rsClose);
      LNeedClose := FSendFinished;
    end else if LIsSwitching then
    begin
      FResponseStatus := rsUpgraded;
      // 101 之后的字节已经属于升级协议。即使 GET 的物理写完成通知晚到，
      // 派生连接也必须能将同批首帧暂存，不能再次交给 HTTP parser。
      // FPending 仍保留到发送结束，公开响应回调仍遵循独立生命周期。
      _SetRequestStatus(rsUpgraded);
    end else
    begin
      _UpdateWatch;
      FResponseStatus := rsIdle;
      if FSendFinished then _SetRequestStatus(rsIdle);
    end;
  finally
    if LRequestEnded then
    begin
      FRequest := nil;
      FRequestObj := nil;
    end;
    if LHandled then
    begin
      FResponse := nil;
      FResponseObj := nil;
    end;

    _ReqUnlock;
    if LRequestEnded then
      _EndRequest;
  end;
  if LNeedClose then
  try Close; except on E: Exception do _Log('HTTP response-close exception: %s', [E.Message]); end;
  if Assigned(LCallback) then
  try
    LCallback(LResponse);
  except
    on E: Exception do
      _Log('TriggerResponseSuccess callback exception: %s', [E.Message]);
  end;
end;

procedure TCrossHttpClientConnection.TriggerResponseTimeout;
var
  LCallback: TCrossHttpResponseProc;
  LResponse, LDiscardedResponse: ICrossHttpClientResponse;
  LRequestEnded, LDeferred: Boolean;
begin
  LCallback := nil;
  LRequestEnded := False;
  LDeferred := False;
  _ReqLock;
  try
    // 只在请求进行中的状态才处理, 防止重复触发与 _EndRequest 多减计数
    // 候选收集后可能已有新正文或被后续请求复用，必须在同一请求锁内重验。
    if not _IsRequestTimeout then Exit;

    if FReceiveDepth > 0 then
    begin
      if not FDeferredReceiveFailure then
      begin
        FDeferredReceiveFailure := True;
        FDeferredReceiveCode := 408;
        FDeferredReceiveText := '';
      end;
      LDeferred := True;
    end else
    begin
      LCallback := FCallback;
      FCallback := nil;
      FResponseFinished := True;
      FResponseReady := False;
      FResponseStatus := rsRespondTimeout;
      LRequestEnded := FSendFinished;

      _SetRequestStatus(rsRespondTimeout);
      if LRequestEnded then
      begin
        FRequest := nil;
        FRequestObj := nil;
      end;
      LDiscardedResponse := FResponse;
      FResponse := nil;
      FResponseObj := nil;
    end;
  finally
    _ReqUnlock;
    if LRequestEnded then
      _EndRequest;
  end;
  ReleaseFailedHttpResponse(LDiscardedResponse);
  try Close; except on E: Exception do _Log('HTTP timeout-close exception: %s', [E.Message]); end;
  if LDeferred then Exit;
  if Assigned(LCallback) then
  try
    // 408 = Request Time-out
    LResponse := TCrossHttpClientResponse.Create(408);
    LCallback(LResponse);
  except
    on E: Exception do
      _Log('TriggerResponseTimeout callback exception: %s', [E.Message]);
  end;
end;

procedure TCrossHttpClientConnection._BeginRequest;
begin
  AtomicIncrement(FPending);
  _UpdateWatch;
end;

function TCrossHttpClientConnection._TryBeginRequest: Boolean;
begin
  _ReqLock;
  try
    Result := _IsIdle;
    if Result then _BeginRequest;
  finally
    _ReqUnlock;
  end;
end;

procedure TCrossHttpClientConnection._CloseIfTimeout(const AConnecting: Boolean);
var
  LClose: Boolean;
begin
  _ReqLock;
  try
    if AConnecting then LClose := _IsConnectTimeout else LClose := _IsIdleout;
    // 与池复用共享请求锁；认领关闭后不允许新请求再预占此连接。
    if LClose then _SetRequestStatus(rsClose);
  finally
    _ReqUnlock;
  end;
  if LClose then Close;
end;

function TCrossHttpClientConnection._CreateRequestHeader(const ABodySize: Int64;
  AChunked: Boolean): TBytes;
var
  LHeaderStr, LCookieStr, LPathStr, LProxyAuthorization: string;
  LHttpSocket: TCrossHttpClientSocket;
  LUseHttpForwardProxy: Boolean;
  LParam: TParamEntry;
  I: Integer;
begin
  _ReqLock;
  try
    LHttpSocket := Owner as TCrossHttpClientSocket;
    LUseHttpForwardProxy :=
      not Ssl and
      LHttpSocket.FProxySettings.IsEnabled and
      (LHttpSocket.FProxySettings.ProxyType = cptHttp) and
      not LHttpSocket.FProxySettings.ShouldBypass(FHost);

    if (FRequestObj.FHeader[HEADER_CACHE_CONTROL] = '') then
      FRequestObj.FHeader[HEADER_CACHE_CONTROL] := 'no-cache';

    if (FRequestObj.FHeader[HEADER_PRAGMA] = '') then
      FRequestObj.FHeader[HEADER_PRAGMA] := 'no-cache';

    if (FRequestObj.FHeader[HEADER_CONNECTION] = '') then
    begin
          // Owner 在 TCrossHttpClientSocket.CreateConnection 中固定为 TCrossHttpClientSocket
      if LHttpSocket.FReUseConnection then
        FRequestObj.FHeader[HEADER_CONNECTION] := 'keep-alive'
      else
        FRequestObj.FHeader[HEADER_CONNECTION] := 'close';
    end;

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

    // 设置数据传输方式
    if (FRequestObj.FMethod = THttpMethod.HEAD) then
    begin
      // HEAD 不发送请求正文，同时清除调用方设置的正文定界头。
      FRequestObj.FHeader.Remove(HEADER_CONTENT_LENGTH);
      FRequestObj.FHeader.Remove(HEADER_TRANSFER_ENCODING);
    end else
    if AChunked then
      FRequestObj.FHeader[HEADER_TRANSFER_ENCODING] := 'chunked'
    // RFC 9110 8.6: send Content-Length when the method gives the body a
    // meaning, even when the body is empty - http.sys answers 411 otherwise.
    else if (ABodySize > 0)
      or SameText(FRequestObj.FMethod, THttpMethod.POST)
      or SameText(FRequestObj.FMethod, THttpMethod.PUT)
      or SameText(FRequestObj.FMethod, THttpMethod.PATCH) then
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

    // 必须在 URL 编码之前拒绝坏代理项，否则编码器可能先替换它们，再产生看似合法的 %xx。
    TCrossHttpUtils.CheckUtf16(FRequestObj.FPathAndParams);
    if FAutoUrlEncode then
    begin
      TCrossHttpUtils.CheckUtf16(FRequestObj.FPath);
      // 初始化回调可独立修改 Query，它不一定与原 FPathAndParams 同步，所以也检查当前项。
      // 校验过程不修改Query；索引遍历省去空/非空集合都要创建的枚举器对象。
      for I := 0 to FRequestObj.FQuery.Count - 1 do
      begin
        LParam := FRequestObj.FQuery.Items[I];
        TCrossHttpUtils.CheckUtf16(LParam.Name);
        TCrossHttpUtils.CheckUtf16(LParam.Value);
      end;
    end;
    if FAutoUrlEncode then
    begin
      // 按 RFC 3986 分组件编码:
      //   path: pchar = unreserved / pct-encoded / sub-delims / ":" / "@", 段间 "/"
      //         APreserveEncoded=True 启用 Normalizer 语义, 识别已有 %xx 序列,
      //         避免二次编码 (RFC 3986 §2.4 "MUST NOT encode the same string more than once")
      //   query: 由 FQuery.Encode 处理，key/value 是 SetUrl 解码后或调用方写入的字符串，
      //          重新编码时 key/value 均按严格 unreserved 集编码 (&/=/% 等都正确转义).
      LPathStr := TCrossHttpUtils.UrlEncode(FRequestObj.FPath, ['/', ':', '@'], True);
      if (FRequestObj.FQuery.Count > 0) then
        LPathStr := LPathStr + '?' + FRequestObj.FQuery.Encode;
    end else
      LPathStr := FRequestObj.FPathAndParams;

    if LUseHttpForwardProxy then
    begin
      LPathStr := FRequestObj.FProtocol + '://' +
        FRequestObj.FHeader[HEADER_HOST] + LPathStr;
      LProxyAuthorization := LHttpSocket.FProxySettings.HttpProxyAuthorization;
      if (LProxyAuthorization <> '') and
        (FRequestObj.FHeader['Proxy-Authorization'] = '') then
        FRequestObj.FHeader['Proxy-Authorization'] := LProxyAuthorization;
    end;

    // 设置请求行
    LHeaderStr := FRequestObj.FMethod + ' '
      + LPathStr + ' '
      + HTTP_VER_STR[FRequestObj.FHttpVersion] + CRLF;

    LHeaderStr := LHeaderStr + FRequestObj.FHeader.Encode;
  finally
    _ReqUnlock;
  end;

  // 完整头统一验证 UTF-16 并编码；字段先 Encode，保持错误报告顺序。
  // URL/query 原始值在百分号编码前的检查仍保留，不能依赖最终文本发现被替换的代理项。
  // 首行和字段共同决定 ASCII 快路，输出始终为无 BOM UTF-8，异常仍由发送链结算失败。
  Result := TCrossHttpUtils.EncodeHeader(LHeaderStr);
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
  _ReqLock;
  try
    LIdleout := (Owner as TCrossHttpClientSocket).FHttpClient.FIdleout;
    if (LIdleout <= 0) then Exit(False);

    // 仅判定已连接(csConnected)的空闲连接, csConnecting 状态交由 _IsConnectTimeout 处理
    Result := _IsIdle
      and (FWatch.ElapsedMilliseconds div 1000 >= LIdleout);
  finally
    _ReqUnlock;
  end;
end;

function TCrossHttpClientConnection._IsRequestTimeout: Boolean;
var
  LRequestTimeout: Integer;
begin
  _ReqLock;
  try
    LRequestTimeout := (Owner as TCrossHttpClientSocket).FHttpClient.FRequestTimeout;
    if (LRequestTimeout <= 0) then Exit(False);

    Result := ((GetRequestStatus in [rsSending, rsResponding])
      or ((GetRequestStatus = rsUpgraded) and not FSendFinished))
      and (FWatch.ElapsedMilliseconds div 1000 >= LRequestTimeout);
  finally
    _ReqUnlock;
  end;
end;

function TCrossHttpClientConnection._IsConnectTimeout: Boolean;
var
  LConnectTimeout: Integer;
begin
  _ReqLock;
  try
    LConnectTimeout := (Owner as TCrossHttpClientSocket).FHttpClient.FConnectTimeout;
    if (LConnectTimeout <= 0) then Exit(False);

    // 处理 ConnectEx 投递成功但 SYN 永远收不到响应的退化场景
    Result := (ConnectStatus = csConnecting)
      and (FWatch.ElapsedMilliseconds div 1000 >= LConnectTimeout);
  finally
    _ReqUnlock;
  end;
end;

procedure TCrossHttpClientConnection._OnBodyPolicy(var APreserveEntity: Boolean);
begin
  APreserveEntity := FPreserveResponseEntity;
end;

procedure TCrossHttpClientConnection._OnBodyBegin;
begin
  if (FResponseObj <> nil) then
    FResponseObj.TriggerResponseDataBegin;
end;

procedure TCrossHttpClientConnection._OnBodyData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  if (FResponseObj <> nil) then
    FResponseObj.TriggerResponseData(ADataPtr, ADataSize);
end;

procedure TCrossHttpClientConnection._OnBodyEnd;
begin
  if (FResponseObj <> nil) then
    FResponseObj.TriggerResponseDataEnd;
end;

function TCrossHttpClientConnection._OnGetHeaderValue(const AHeaderName: string;
  out AHeaderValues: TArray<string>): Boolean;
begin
  if (FResponseObj <> nil) then
    Result := FResponseObj.FHeader.GetHeaderValues(AHeaderName, AHeaderValues)
  else
  begin
    SetLength(AHeaderValues, 0);
    Result := False;
  end;
end;

procedure TCrossHttpClientConnection._OnHeaderData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  if (FResponseObj <> nil) then
  begin
    if not FResponseObj.ParseHeader(ADataPtr, ADataSize) then
    begin
      // 头部解码失败由 Parser 进入统一失败终态，不能继续发布空状态或部分头部。
      (FHttpParser as TCrossHttpParser).Fail(400, 'Invalid response header.');
      Exit;
    end;
    if (FRequestObj <> nil) and (FHttpParser <> nil) then
      FHttpParser.SetNoBody(SameText(FRequestObj.FMethod, THttpMethod.HEAD)
        or ((FResponseObj.FStatusCode >= 100) and (FResponseObj.FStatusCode < 200))
        or (FResponseObj.FStatusCode = 204)
        or (FResponseObj.FStatusCode = 304));
  end;
end;

procedure TCrossHttpClientConnection._OnParseBegin;
var
  LHasRequest: Boolean;
begin
  _ReqLock;
  try
    LHasRequest := (FRequest <> nil) and (FRequestObj <> nil);
    if LHasRequest then
    begin
      FResponseObj := TCrossHttpClientResponse.Create(Self);
      FResponseObj.FStorageOptions := FResponseStorage;
      FResponse := FResponseObj;
      FResponseObj._SetResponseStream(FRequestObj.FResponseStream);
    end;
  finally
    _ReqUnlock;
  end;
  if not LHasRequest then
  begin
    // 入口之外的最后防线：无所属请求不能创建响应或继续当前解析。
    try
      (FHttpParser as TCrossHttpParser).Fail(400, 'Response without an active request');
    finally
      Close;
    end;
  end;
end;

procedure TCrossHttpClientConnection._OnParseFailed(const ACode: Integer;
  const AError: string);
begin
  TriggerResponseFailed(ACode, AError);
end;

procedure TCrossHttpClientConnection._OnParseSuccess;
begin
  _ReqLock;
  try
    if (FResponseObj <> nil)
      and (FResponseObj.FStatusCode >= 100) and (FResponseObj.FStatusCode < 200)
      and (FResponseObj.FStatusCode <> 101) then
    begin
      // 临时响应只结束当前头部，保留请求、回调和连接占用，继续等最终响应。
      FResponseObj := nil;
      FResponse := nil;
      Exit;
    end;
    if (FResponseObj <> nil) and (FResponseObj.FStatusCode <> 101) then
    begin
      // Decode 返回后才能知道本批尾部；保持占用直到接收收尾检查完成。
      FResponseReady := not FFinishReceivePending and not FDeferredReceiveFailure;
      Exit;
    end;
  finally
    _ReqUnlock;
  end;
  // 升级响应保留既有发布顺序，后续字节由 WebSocket 派生连接接管。
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

procedure TCrossHttpClientConnection._SocketSend(
  const ASource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback; const ASourceFinished: TFunc<Boolean>);
var
  LHttpConnection: ICrossHttpClientConnection;
  LSender, LFinish: TCrossConnectionCallback;
  LCompleted: Integer;
begin
  LHttpConnection := Self;
  LCompleted := 0;
  LFinish :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      LSender := nil;
      LHttpConnection := nil;
      try
        if not ASuccess then
        try
          TriggerResponseFailed(400, 'Send failed');
        except
          on E: Exception do _Log('HTTP send failure notification exception: %s', [E.Message]);
        end;
        if Assigned(ASendCb) then
        try
          ASendCb(AConnection, ASuccess);
        except
          on E: Exception do _Log('HTTP send callback exception: %s', [E.Message]);
        end;
      finally
        LFinish := nil;
      end;
    end;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LKeep: ICrossHttpClientConnection;
      LData: Pointer;
      LCount: NativeInt;
      LHasData: Boolean;
      LWriteDone: Integer;
      LWriteCallback: TCrossConnectionCallback;
    begin
      LKeep := LHttpConnection;
      if (LKeep = nil) or (AtomicCmpExchange(LCompleted, 0, 0) <> 0) then Exit;
      try
        // 只有最后一个物理写已经成功，且内部状态确认没有剩余字节时，
        // 才允许在对端紧接着关闭连接的情况下仍报告完整发送。
        // 此判定只读状态，不在 Close 后再次调用用户 Read 探测 EOF。
        if ASuccess and Assigned(ASourceFinished) and ASourceFinished() then
        begin
          LFinish(AConnection, True);
          Exit;
        end;
        if not ASuccess or LKeep.IsClosed then
        begin
          LFinish(AConnection, False);
          Exit;
        end;

        // 更新计时器
        _UpdateWatch;

        LData := nil;
        LCount := 0;
        LHasData := Assigned(ASource) and ASource(@LData, @LCount)
          and (LData <> nil) and (LCount > 0);
        // Close 可在阻塞 Read 期间发生；只有 Read 退出后才结算。
        if LKeep.IsClosed then
        begin
          LFinish(AConnection, False);
          Exit;
        end;
        if not LHasData then
        begin
          // 标记正在等待响应
          _ReqLock;
          try
            if (RequestStatus = rsSending) then
              _SetRequestStatus(rsResponding);
          finally
            _ReqUnlock;
          end;
          LFinish(AConnection, True);
          Exit;
        end;

        // 每个物理写独立防重；同步回调后抛异常不能再次完成同一次写。
        LWriteDone := 0;
        LWriteCallback :=
          procedure(const C: ICrossConnection; const OK: Boolean)
          begin
            if AtomicExchange(LWriteDone, 1) <> 0 then Exit;
            if Assigned(LSender) then LSender(C, OK);
          end;
        try
          {$IFDEF CROSS_HTTP_SEND_TESTS}
          if Assigned(GHttpSendTestWrite) then
            GHttpSendTestWrite(LKeep, LData, LCount, LWriteCallback)
          else
          {$ENDIF}
            LKeep.SendBuf(LData^, LCount, LWriteCallback);
        except
          on E: Exception do LWriteCallback(AConnection, False);
        end;
      except
        on E: Exception do
        begin
          if Assigned(LFinish) then LFinish(AConnection, False);
        end;
      end;
    end;

  LSender(LHttpConnection, True);
end;

procedure TCrossHttpClientConnection._HttpSend(const AHeaderSource,
  ABodySource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback; const ABodyFinished: TFunc<Boolean>);
var
  LMethodIsHead, LHeaderDone, LClosed: Boolean;
begin
  // 更新计时器
  _UpdateWatch;

  _ReqLock;
  try
    // 标记正在发送请求
    LClosed := IsClosed;
    if not LClosed and not FResponseFinished then _SetRequestStatus(rsSending);

    LMethodIsHead := (FRequest <> nil) and (FRequest.Method = 'HEAD');
  finally
    _ReqUnlock;
  end;
  if LClosed then
  begin
    if Assigned(ASendCb) then ASendCb(Self, False);
    Exit;
  end;

  // HEAD 请求不应包含请求体 (RFC 7231 §4.3.2)
  // [FIX-HEAD-LOOP-2] Client mirror of FIX-HEAD-LOOP-1 in
  // TCrossHttpResponse._Send. _SocketSend calls the header source again after
  // each completed SendBuf and the source never returns False, so passing
  // AHeaderSource on its own resent the REQUEST header until the connection
  // went away. Measured: the server parsed a 15747-byte read = 87 x the
  // 181-byte HEAD header.

  LHeaderDone := False;

  _SocketSend(
    function(const AData: PPointer; const ADataSize: PNativeInt): Boolean
    begin
      if not LHeaderDone then
      begin
        LHeaderDone := True;
        Result := Assigned(AHeaderSource) and AHeaderSource(AData, ADataSize);
      end else
      if LMethodIsHead then
        Result := False
      else
      begin
        Result := Assigned(ABodySource) and ABodySource(AData, ADataSize);
      end;
    end,
    ASendCb,
    function: Boolean
    begin
      Result := LHeaderDone and (LMethodIsHead or
        (Assigned(ABodyFinished) and ABodyFinished()));
    end);
end;

function TCrossHttpClientConnection._SetRequestStatus(
  const AStatus: TRequestStatus): TRequestStatus;
begin
  Result := TRequestStatus(AtomicExchange(FStatus, Integer(AStatus)));
end;

procedure TCrossHttpClientConnection._UpdateWatch;
begin
  _ReqLock;
  try
    FWatch.Reset;
  finally
    _ReqUnlock;
  end;
end;

{ TCrossHttpClientRequest }

constructor TCrossHttpClientRequest.Create(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBodyFunc: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream; const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  _Init(AMethod, AUrl, AHttpHeaders,
    ARequestBodyFunc, nil, 0,
    AResponseStream, AInitProc, ACallback);
end;

constructor TCrossHttpClientRequest.Create(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  _Init(AMethod, AUrl, AHttpHeaders,
    nil, ARequestBody, ABodySize,
    AResponseStream, AInitProc, ACallback);
end;

destructor TCrossHttpClientRequest.Destroy;
begin
  _CancelSendBeforeStart;
  _ReleaseAdmission;
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);
  FreeAndNil(FQuery);

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

function TCrossHttpClientRequest.GetMethod: string;
begin
  Result := FMethod;
end;

function TCrossHttpClientRequest.GetPath: string;
begin
  Result := FPath;
end;

function TCrossHttpClientRequest.GetPathAndParams: string;
begin
  Result := FPathAndParams;
end;

function TCrossHttpClientRequest.GetQuery: THttpUrlParams;
begin
  Result := FQuery;
end;

procedure TCrossHttpClientRequest._ReleaseAdmission;
var
  LAdmission: IInterface;
begin
  if FStateLock = nil then Exit;
  FStateLock.Enter;
  try
    if FAdmissionReleased <> 0 then Exit;
    FAdmissionReleased := 1;
    LAdmission := FAdmission;
    FAdmission := nil;
  finally
    FStateLock.Leave;
  end;
  if LAdmission <> nil then
    (LAdmission as THttpRequestCount).ReleaseRequest;
end;

procedure TCrossHttpClientRequest._NotifySend(const ASuccess: Boolean);
var
  LCallback: TCrossHttpRequestSendProc;
  LResponseCallback: TCrossHttpResponseProc;
  LResponse: ICrossHttpClientResponse;
  LInit: TCrossHttpRequestInitProc;
  LBody: TCrossHttpChunkDataFunc;
begin
  if FStateLock = nil then Exit;
  LCallback := FSendCb;
  FSendCb := nil;
  LInit := FInitProc;
  FInitProc := nil;
  LBody := FRequestBodyFunc;
  FRequestBodyFunc := nil;
  FRequestBody := nil;
  if AtomicCmpExchange(FCompleted, 0, 0) <> 0 then _ReleaseAdmission;
  if Assigned(LCallback) then
  try
    LCallback(ASuccess);
  except
    on E: Exception do _Log('HTTP request send callback exception: %s', [E.Message]);
  end;
  FStateLock.Enter;
  try
    LResponseCallback := FDeferredCallback;
    FDeferredCallback := nil;
    LResponse := FDeferredResponse;
    FDeferredResponse := nil;
  finally
    FStateLock.Leave;
  end;
  if Assigned(LResponseCallback) then
  try
    LResponseCallback(LResponse);
  except
    on E: Exception do _Log('HTTP deferred response callback exception: %s', [E.Message]);
  end;
end;

procedure TCrossHttpClientRequest._CancelSendBeforeStart;
begin
  if AtomicCmpExchange(FSendState, 2, 0) = 0 then _NotifySend(False);
end;

procedure TCrossHttpClientRequest._ExecCallback(
  const AResponse: ICrossHttpClientResponse);
var
  LCallback: TCrossHttpResponseProc;
begin
  if AtomicExchange(FCompleted, 1) <> 0 then Exit;
  LCallback := FCallback;
  FCallback := nil;
  _CancelSendBeforeStart;
  FStateLock.Enter;
  try
    // 旧入口没有发送回调，原调用方普遍在响应回调中释放正文。
    // 保留此用法：只有新能力入口允许应用响应通知早于发送结束。
    if not FSeparateSend and (AtomicCmpExchange(FSendState, 0, 0) <> 2) then
    begin
      FDeferredResponse := AResponse;
      FDeferredCallback := LCallback;
      LCallback := nil;
    end;
  finally
    FStateLock.Leave;
  end;
  // 早响应不归还仍被发送链占用的额度。
  if AtomicCmpExchange(FSendState, 0, 0) = 2 then _ReleaseAdmission;
  if Assigned(LCallback) then
  try
    LCallback(AResponse);
  except
    on E: Exception do _Log('HTTP request response callback exception: %s', [E.Message]);
  end;
end;

procedure TCrossHttpClientRequest._Init(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBodyFunc: TCrossHttpChunkDataFunc; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
begin
  FStateLock := TLock.Create;
  FHeader := THttpHeader.Create;
  FCookies := TRequestCookies.Create;
  FHttpVersion := hvHttp11;

  FMethod := AMethod;
  FUrl := AUrl;
  if (AHttpHeaders <> nil) then
    FHeader.Assign(AHttpHeaders);
  FRequestBodyFunc := ARequestBodyFunc;
  FRequestBody := ARequestBody;
  FRequestBodySize := ABodySize;
  FResponseStream := AResponseStream;
  FInitProc := AInitProc;
  FCallback := ACallback;

  _ParseUrl;
end;

procedure TCrossHttpClientRequest._ParseUrl;
var
  I: Integer;
  LParamsText: string;
begin
  FQuery := THttpUrlParams.Create;
  FUrlReady := TCrossHttpUtils.ExtractUrl(FUrl, FProtocol, FHost, FPort, FPathAndParams);
  if not FUrlReady then
  begin
    Exit;
  end;

  // 解析?key1=value1&key2=value2参数
  I := FPathAndParams.IndexOf('?');
  if (I >= 0) then
  begin
    FPath := FPathAndParams.Substring(0, I);
    LParamsText := FPathAndParams.Substring(I + 1);
    FQuery.Decode(LParamsText);
  end else
    FPath := FPathAndParams;
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
  try
    FreeAndNil(FHeader);
    FreeAndNil(FCookies);

    if FNeedFreeResponseBodyStream and (FResponseBodyStream <> nil) then
    try
      FreeAndNil(FResponseBodyStream);
    except
      on E: Exception do
        try
          // 正常发布响应前已Flush；失败/取消收尾的二次刷新不能中断
          // 引用计数对象自身及其连接引用的最终释放。
          _Log('HTTP response stream cleanup exception: %s', [E.Message]);
        except
        end;
    end;
  finally
    inherited;
  end;
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
  I, LLineEnd: Integer;
  P: PByte;
  LCookieValues: TArray<string>;
  LCookieValue: string;
  LCookie: TResponseCookie;
begin
  Result := False;
  if (ADataPtr = nil) or (ADataSize <= 0) then Exit;
  // 1. 直接扫描借用的原始缓冲区，先确定状态行边界，不能先转换整块头。
  // 下标从 0 开始且均为字节偏移；LLineEnd 指向行末 CR，不计入状态文本。
  P := ADataPtr;
  LLineEnd := 0;
  while (LLineEnd < ADataSize) and (P[LLineEnd] <> 13) do
  begin
    if not TCrossHttpUtils.IsHeaderValueChar(Char(P[LLineEnd])) then Exit;
    Inc(LLineEnd);
  end;
  if (LLineEnd + 1 >= ADataSize) or (P[LLineEnd + 1] <> 10) then Exit;
  // 2. 当前支持的状态行布局为 HTTP/1.x SP 三位状态码 SP 原因文本。
  // 8/12 是两个 SP 的字节偏移；长度至少 13，最后一个 SP 后的原因文本可以为空。
  // 版本和状态码是 ASCII 控制内容，先验证原字节，避免文本转换改变其意义。
  if (LLineEnd < 13) or (P[8] <> 32) or (P[12] <> 32) then Exit;
  for I := 0 to 7 do
    if P[I] > 127 then Exit;
  FHttpVer := TUtils.GetString(P, 8);
  if (FHttpVer <> 'HTTP/1.0') and (FHttpVer <> 'HTTP/1.1') then Exit;
  if (P[9] < Ord('1')) or (P[9] > Ord('9'))
    or (P[10] < Ord('0')) or (P[10] > Ord('9'))
    or (P[11] < Ord('0')) or (P[11] > Ord('9')) then Exit;
  FStatusCode := (P[9] - Ord('0')) * 100 + (P[10] - Ord('0')) * 10 + P[11] - Ord('0');
  // 3. 原因文本可含非 ASCII，单独转换这个已确定的区间，不用其结果寻找状态行边界。
  FStatusText := TUtils.GetString(P + 13, LLineEnd - 13);
  // 4. 剩余区间仍为原始字节，交给 Header.Decode 校验、保存 raw 并转换各值。
  // 必须检查返回值，不能使用半份头继续推断正文长度或进入 WebSocket 升级。
  if not FHeader.Decode(P + LLineEnd + 2, ADataSize - LLineEnd - 2) then Exit;
  FKeepAlive := not FHeader.ContainsToken(HEADER_CONNECTION, 'close')
    and ((FHttpVer = 'HTTP/1.1') or FHeader.ContainsToken(HEADER_CONNECTION, 'keep-alive'));

  // 5. 从完整字段集合派生响应属性。逐项读取 Set-Cookie，保留重复字段，不能合并为一个值。
  // 只收集匹配项的Value，避免为每个普通字段复制Name/Value/raw整条记录。
  // GetHeaderValues保留顺序和重复项；没有Set-Cookie时不申请值数组。
  if FHeader.GetHeaderValues(HEADER_SETCOOKIE, LCookieValues) then
    for LCookieValue in LCookieValues do
    begin
      LCookie := TResponseCookie.Create(LCookieValue, FConnectionObj.FHost);
      if (LCookie.Name <> '') then
        FCookies.Add(LCookie);
    end;

  FContentType := FHeader[HEADER_CONTENT_TYPE];
  // 此处只是响应属性；CL/TE 的合法性、重复值和正文定界由外层 Parser 统一检查。
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

  // 调用方在本方法成功后先设置 HEAD/1xx/204/304 的无正文标记，Parser 再处理定界。
  Result := True;
end;

procedure TCrossHttpClientResponse.TriggerResponseData(const ABuf: Pointer;
  const ALen: Integer);
var
  LTemporary, LOld: TStream;
begin
  if (FResponseBodyStream = nil)
    or (ABuf = nil) or (ALen <= 0) then Exit;

  if FNeedFreeResponseBodyStream and (FStorageOptions.MemoryThreshold > 0)
    and (FResponseBodyStream is TMemoryStream)
    and (Int64(ALen) > FStorageOptions.MemoryThreshold - FResponseBodyStream.Size) then
  begin
    {$IFDEF CROSS_HTTP_SEND_TESTS}
    if Assigned(GHttpSendTestTempStreamFactory) then
      LTemporary := GHttpSendTestTempStreamFactory(FStorageOptions.TempPath)
    else
    {$ENDIF}
      LTemporary := TFileUtils.CreateTempFile(FStorageOptions.TempPath);
    try
      FResponseBodyStream.Position := 0;
      LTemporary.CopyFrom(FResponseBodyStream, FResponseBodyStream.Size);
      LOld := FResponseBodyStream;
      FResponseBodyStream := LTemporary;
      LTemporary := nil;
      LOld.Free;
    finally
      LTemporary.Free;
    end;
  end;
  // 忽略短写会在HTTP头仍表示完整成功时留下截断正文。
  FResponseBodyStream.WriteBuffer(ABuf^, ALen);
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
  if FResponseBodyStream is TFastFileStream then
    TFastFileStream(FResponseBodyStream).FlushBuffer;
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
  const AIoThreads, AMaxConnsPerServer, AMaxCompressRatio: Integer;
  const ASsl, AReUseConnection, AAutoUrlEncode: Boolean;
  const ACompressType: TCompressType);
begin
  FHttpClient := AHttpClient;
  FReUseConnection := AReUseConnection;
  FAutoUrlEncode := AAutoUrlEncode;
  FMaxConnsPerServer := AMaxConnsPerServer;
  FMaxCompressRatio := AMaxCompressRatio;
  FCompressType := ACompressType;
  FProxySettings := AHttpClient.FProxySettings;

  inherited Create(AIoThreads, ASsl);

  FServerDockDict := TServerDockDict.Create;
  FServerDockLock := TLock.Create;
end;

procedure TCrossHttpClientSocket.TriggerConnecting(const AConnection: ICrossConnection);
begin
  inherited;
  {$IFDEF CROSS_CAPACITY_TESTS}_ClientAdmissionTest('registered', nil);{$ENDIF}
  // 登记晚于析构的 CloseAll 快照时，也必须立即回收该连接。
  if AtomicCmpExchange(FHttpClient.FClosing, 0, 0) <> 0 then AConnection.Close;
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

procedure TCrossHttpClientSocket.PrepareConnection(
  const AConnection: ICrossConnection; const ALogicalHost: string;
  const ALogicalPort: Word);
begin
  inherited PrepareConnection(AConnection, ALogicalHost, ALogicalPort);
  if not Ssl and FProxySettings.IsEnabled and
    (FProxySettings.ProxyType = cptHttp) and
    not FProxySettings.ShouldBypass(ALogicalHost) then
    (AConnection as TCrossConnectionBase).ConfigureProxy(
      TCrossProxySettings.Direct, ALogicalHost, ALogicalPort)
  else
    (AConnection as TCrossConnectionBase).ConfigureProxy(
      FProxySettings, ALogicalHost, ALogicalPort);
end;

destructor TCrossHttpClientSocket.Destroy;
begin
  FreeAndNil(FServerDockDict);
  inherited;
end;

procedure TCrossHttpClientSocket.CancelAllRequests;
var
  LServerDockArr: TArray<IServerDock>;
  LServerDock: IServerDock;
begin
  _LockServerDock;
  try
    LServerDockArr := FServerDockDict.Values.ToArray;
  finally
    _UnlockServerDock;
  end;

  for LServerDock in LServerDockArr do
    LServerDock.CancelAllRequests(400, 'Request canceled');
end;

procedure TCrossHttpClientSocket.DoRequest(const ARequest: ICrossHttpClientRequest);
var
  LRequestObj: TCrossHttpClientRequest;
  LServerDock: IServerDock;
begin
  LRequestObj := ARequest as TCrossHttpClientRequest;
  if not LRequestObj.FUrlReady then Exit;

  _LockServerDock;
  try
    LServerDock := _GetServerDock(
      LRequestObj.FProtocol,
      LRequestObj.FHost,
      LRequestObj.FPort);
  finally
    _UnlockServerDock;
  end;

  // 锁外调用安全: LServerDock 持有接口引用, 引用计数保证对象存活
  LServerDock.DoRequest(ARequest);
end;

function TCrossHttpClientSocket.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

procedure TCrossHttpClientSocket.LogicDisconnected(
  const AConnection: ICrossConnection);
var
  LServerDock: IServerDock;
  LConn: ICrossHttpClientConnection;
  LConnObj: TCrossHttpClientConnection;
begin
  LConn := AConnection as ICrossHttpClientConnection;
  LConnObj := LConn as TCrossHttpClientConnection;

  // Finish与正在执行的Decode/正文Write串行化，包括Write内重入Close。
  // 关闭定界响应仍可由正常EOF完成；长度不足或写入失败不能发布成功。
  LConnObj._FinishReceive;

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

procedure TCrossHttpClientSocket.SyncOptions(const AMaxConnsPerServer,
  AMaxCompressRatio: Integer; const AReUseConnection, AAutoUrlEncode: Boolean);
begin
  FMaxConnsPerServer := AMaxConnsPerServer;
  FMaxCompressRatio := AMaxCompressRatio;
  FReUseConnection := AReUseConnection;
  FAutoUrlEncode := AAutoUrlEncode;
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

procedure TCrossHttpClientSocket.ConnectTarget(
  const APhysicalHost: string; const APhysicalPort, ALocalPort: Word;
  const ALogicalHost: string; const ALogicalPort: Word;
  const ACallback: TCrossConnectionCallback);
begin
  inherited ConnectTarget(APhysicalHost, APhysicalPort, ALocalPort,
    ALogicalHost, ALogicalPort, ACallback);
end;

procedure TCrossHttpClientSocket.SyncProxySettings(
  const AValue: TCrossProxySettings);
begin
  FProxySettings := AValue;
  CloseAll;
end;

function TCrossHttpClientSocket._GetServerDock(const AProtocol, AHost: string;
  const APort: Word): IServerDock;
var
  LKey: string;
begin
  LKey := _MakeServerDockKey(AProtocol, AHost, APort);
  if not FServerDockDict.TryGetValue(LKey, Result) then
  begin
    Result := TServerDock.Create(Self, AProtocol, AHost, APort, FLocalPort);
    FServerDockDict.Add(LKey, Result);
  end else
    // 字典持有的永远是 TServerDock 实例, 转回具体类型以访问内部字段
    (Result as TObject as TServerDock).FLocalPort := FLocalPort;
end;

function TCrossHttpClientSocket._GetServerDock(const AProtocol, AHost: string;
  const APort: Word; out AServerDock: IServerDock): Boolean;
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
  // 连接池按代理配置隔离，避免跨代理复用连接。
  Result := AProtocol + '://' + AHost + ':' + APort.ToString + '|' +
    FProxySettings.CacheKey;
end;

procedure TCrossHttpClientSocket._UnlockServerDock;
begin
  FServerDockLock.Leave;
end;

{ TCrossHttpClient }

procedure TCrossHttpClient.SetResponseStorageOptions(
  const AValue: THttpResponseStorageOptions);
begin
  if AValue.MemoryThreshold < 0 then
    raise ECrossHttpClient.Create('响应内存阈值不能为负数');
  _Lock;
  try FResponseStorage := AValue; finally _Unlock; end;
end;

function TCrossHttpClient.GetResponseStorageOptions: THttpResponseStorageOptions;
begin
  _Lock;
  try Result := FResponseStorage; finally _Unlock; end;
end;

function TCrossHttpClient.GetPreserveResponseEntity: Boolean;
begin
  _Lock;
  try Result := FPreserveResponseEntity; finally _Unlock; end;
end;

procedure TCrossHttpClient.SetPreserveResponseEntity(const AValue: Boolean);
begin
  _Lock;
  try FPreserveResponseEntity := AValue; finally _Unlock; end;
end;

procedure TCrossHttpClient.CancelAll;
var
  LHttpCli: ICrossHttpClientSocket;
begin
  for LHttpCli in FHttpCliArr do
  begin
    LHttpCli.CancelAllRequests;
    LHttpCli.CloseAll;
  end;
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
  FRequestTimeout := 120;

  // 空闲超时默认设置为10秒
  FIdleout := 10;

  // 连接建立超时默认 30 秒(Windows 默认 SYN 超时约 21 秒, 留 9 秒余量)
  FConnectTimeout := 30;

  // 默认重用连接
  FReUseConnection := True;

  // 默认UrlEncode
  FAutoUrlEncode := True;

  FIoThreads := AIoThreads;
  FMaxConnsPerServer := AMaxConnsPerServer;
  FMaxCompressRatio := DEFAULT_MAX_COMPRESS_RATIO;
  FCompressType := ACompressType;
  FProxySettings := TCrossProxySettings.Direct;
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
var
  LHttpCli: ICrossHttpClientSocket;
begin
  AtomicExchange(FClosing, 1);
  try
    if FTimer <> nil then
    begin
      FTimer.Terminate;
      FTimer.WaitFor;
      FTimer := nil;
    end;
  finally
    // 析构中的取消回调可以重入；入口只拒绝，不复活 Self 或再接纳请求。
    for LHttpCli in FHttpCliArr do
    begin
      try
        LHttpCli.CancelAllRequests;
        {$IFDEF CROSS_CAPACITY_TESTS}_ClientAdmissionTest('after-cancel', nil);{$ENDIF}
      except
        on E: Exception do _LogException('HTTP client destroy cancel failed', E);
      end;
      try
        LHttpCli.CloseAll;
      except
        on E: Exception do _LogException('HTTP client destroy close failed', E);
      end;
      try
        LHttpCli.StopLoop;
      except
        on E: Exception do _LogException('HTTP client destroy stop failed', E);
      end;
    end;
    if Length(FPrivateKey) > 0 then
      FillChar(FPrivateKey[0], Length(FPrivateKey), 0);
    FPrivateKeyPassword := '';
    inherited;
  end;
end;

class constructor TCrossHttpClient.Create;
begin
  FDefaultIOThreads := 4;
end;

function TCrossHttpClient.CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket;
var
  LHttpsCli: ICrossHttpClientSocket;
begin
  // 注意：调用方应该已经持有锁，这里的断言用于调试验证
  // 如果外部没有加锁，此方法内部不再重复加锁，以避免死锁
  if TStrUtils.SameText(AProtocol, HTTP) then
  begin
    if (FHttpCli = nil) then
    begin
      FHttpCli := TCrossHttpClientSocket.Create(Self, FIoThreads,
        FMaxConnsPerServer, FMaxCompressRatio, False,
        FReUseConnection, FAutoUrlEncode,
        FCompressType);
      (FHttpCli as TObject as TCrossHttpClientSocket).SyncProxySettings(FProxySettings);
      FHttpCliArr := FHttpCliArr + [FHttpCli];
    end;

    Result := FHttpCli;
  end else
  if TStrUtils.SameText(AProtocol, HTTPS) then
  begin
    if (FHttpsCli = nil) then
    begin
      LHttpsCli := TCrossHttpClientSocket.Create(Self, FIoThreads,
        FMaxConnsPerServer, FMaxCompressRatio, True,
        FReUseConnection, FAutoUrlEncode,
        FCompressType);
      _ApplyTlsOptions(LHttpsCli);
      (LHttpsCli as TObject as TCrossHttpClientSocket).SyncProxySettings(FProxySettings);
      FHttpsCli := LHttpsCli;
      FHttpCliArr := FHttpCliArr + [FHttpsCli];
    end;

    Result := FHttpsCli;
  end else
    raise ECrossHttpClient.CreateFmt('Invalid protocol:%s', [AProtocol]);

  Result.LocalPort := FLocalPort;
end;

procedure TCrossHttpClient._SubmitRequest(const ARequest: ICrossHttpClientRequest);
var
  LHttpCli: ICrossHttpClientSocket;
  LRequestObj: TCrossHttpClientRequest;
begin
  LRequestObj := ARequest as TCrossHttpClientRequest;
  // 此入口接管完成通知；接管后的异常不再向调用方伪装成未接纳。
  try
    if AtomicCmpExchange(FClosing, 0, 0) <> 0 then
    begin
      LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, 'Request canceled'));
      Exit;
    end;
    if not LRequestObj.FUrlReady then
    begin
      LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, 'Invalid URL:' + LRequestObj.FUrl));
      Exit;
    end;
    {$IFDEF CROSS_HTTP_SEND_TESTS}
    if Assigned(GHttpSendTestSubmit) then
    begin
      GHttpSendTestSubmit(Self, ARequest);
      Exit;
    end;
    {$ENDIF}
    _Lock;
    try
      LHttpCli := CreateHttpCli(LRequestObj.FProtocol);
    finally
      _Unlock;
    end;
    LHttpCli.DoRequest(ARequest);
  except
    on E: Exception do
      LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, 'Request failed: ' + E.Message));
  end;
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBody: TCrossHttpChunkDataFunc;
  const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LRequest: ICrossHttpClientRequest;
begin
  LRequest := TCrossHttpClientRequest.Create(AMethod, AUrl, AHttpHeaders,
    ARequestBody, AResponseStream, AInitProc, ACallback);
  _SubmitRequest(LRequest);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LRequest: ICrossHttpClientRequest;
begin
  LRequest := TCrossHttpClientRequest.Create(
    AMethod,
    AUrl,
    AHttpHeaders,
    ARequestBody,
    ABodySize,
    AResponseStream,
    AInitProc,
    ACallback);
  _SubmitRequest(LRequest);
end;

procedure TCrossHttpClient.DoRequestWithSend(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody, AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ASendCb: TCrossHttpRequestSendProc;
  const AResponseCb: TCrossHttpResponseProc);
var
  LRemaining: Int64;
  LBuffer: TBytes;
  LRequest: ICrossHttpClientRequest;
  LRequestObj: TCrossHttpClientRequest;
begin
  // Size/定位/对象构造异常发生在接管之前，此时不触发任何完成回调。
  LRemaining := 0;
  if ARequestBody <> nil then
  begin
    LRemaining := ARequestBody.Size;
    if LRemaining < 0 then raise ECrossHttpClient.Create('请求正文长度不能为负数');
    ARequestBody.Position := 0;
    SetLength(LBuffer, SND_BUF_SIZE);
  end;
  LRequestObj := TCrossHttpClientRequest.Create(AMethod, AUrl, AHttpHeaders,
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    var
      LRead, LWant: Integer;
    begin
      if LRemaining = 0 then Exit(False);
      LWant := Min(LRemaining, SND_BUF_SIZE);
      LRead := ARequestBody.Read(LBuffer[0], LWant);
      if (LRead <= 0) or (LRead > LWant) then
        raise EReadError.Create('请求正文未达到声明长度');
      Dec(LRemaining, LRead);
      AData^ := @LBuffer[0];
      ACount^ := LRead;
      Result := True;
    end, AResponseStream, AInitProc, AResponseCb);
  LRequest := LRequestObj;
  LRequestObj.FSeparateSend := True;
  LRequestObj.FSendCb := ASendCb;
  _SubmitRequest(LRequest);
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

procedure TCrossHttpClient._ApplyTlsOptions(
  const ACli: ICrossHttpClientSocket);
var
  LCACertificate: TBytes;
begin
  if Length(FCertificate) > 0 then
    ACli.SetCertificate(FCertificate);
  if Length(FPrivateKey) > 0 then
    ACli.SetPrivateKey(FPrivateKey, FPrivateKeyPassword);
  for LCACertificate in FCACertificates do
    ACli.AddCACertificate(LCACertificate);
  ACli.VerifyPeer := FVerifyPeer;
end;

procedure TCrossHttpClient.AddCACertificate(const ABuf: Pointer;
  const ASize: Integer);
var
  LBytes: TBytes;
begin
  if (ABuf = nil) or (ASize <= 0) then
    raise ECrossHttpClient.Create('CA certificate data is empty.');

  SetLength(LBytes, ASize);
  Move(ABuf^, LBytes[0], ASize);

  _Lock;
  try
    if FHttpsCli <> nil then
      FHttpsCli.AddCACertificate(LBytes);
    FCACertificates := FCACertificates + [LBytes];
  finally
    _Unlock;
  end;
end;

procedure TCrossHttpClient.AddCACertificate(const ABytes: TBytes);
begin
  AddCACertificate(Pointer(ABytes), Length(ABytes));
end;

procedure TCrossHttpClient.AddCACertificate(const AText: string);
begin
  AddCACertificate(TEncoding.ANSI.GetBytes(AText));
end;

procedure TCrossHttpClient.AddCACertificateFile(const AFileName: string);
begin
  AddCACertificate(TFileUtils.ReadAllBytes(AFileName));
end;

procedure TCrossHttpClient.SetCertificate(const ACertBuf: Pointer;
  const ACertBufSize: Integer);
var
  LBytes: TBytes;
begin
  if (ACertBuf = nil) or (ACertBufSize <= 0) then
    raise ECrossHttpClient.Create('Certificate data is empty.');

  SetLength(LBytes, ACertBufSize);
  Move(ACertBuf^, LBytes[0], ACertBufSize);

  _Lock;
  try
    if FHttpsCli <> nil then
      FHttpsCli.SetCertificate(LBytes);
    FCertificate := LBytes;
  finally
    _Unlock;
  end;
end;

procedure TCrossHttpClient.SetCertificate(const ACertBytes: TBytes);
begin
  SetCertificate(Pointer(ACertBytes), Length(ACertBytes));
end;

procedure TCrossHttpClient.SetCertificate(const ACertStr: string);
begin
  SetCertificate(TEncoding.ANSI.GetBytes(ACertStr));
end;

procedure TCrossHttpClient.SetCertificateFile(const ACertFile: string);
begin
  SetCertificate(TFileUtils.ReadAllBytes(ACertFile));
end;

procedure TCrossHttpClient.SetPrivateKey(const APKeyBuf: Pointer;
  const APKeyBufSize: Integer; const APassword: string);
var
  LBytes: TBytes;
begin
  if (APKeyBuf = nil) or (APKeyBufSize <= 0) then
    raise ECrossHttpClient.Create('Private key data is empty.');

  SetLength(LBytes, APKeyBufSize);
  Move(APKeyBuf^, LBytes[0], APKeyBufSize);

  _Lock;
  try
    if FHttpsCli <> nil then
      FHttpsCli.SetPrivateKey(LBytes, APassword);
    if Length(FPrivateKey) > 0 then
      FillChar(FPrivateKey[0], Length(FPrivateKey), 0);
    FPrivateKey := LBytes;
    FPrivateKeyPassword := APassword;
  finally
    _Unlock;
  end;
end;

procedure TCrossHttpClient.SetPrivateKey(const APKeyBytes: TBytes;
  const APassword: string);
begin
  SetPrivateKey(Pointer(APKeyBytes), Length(APKeyBytes), APassword);
end;

procedure TCrossHttpClient.SetPrivateKey(const APKeyStr,
  APassword: string);
var
  LBytes: TBytes;
begin
  LBytes := TEncoding.ANSI.GetBytes(APKeyStr);
  try
    SetPrivateKey(LBytes, APassword);
  finally
    if Length(LBytes) > 0 then
      FillChar(LBytes[0], Length(LBytes), 0);
  end;
end;

procedure TCrossHttpClient.SetPrivateKeyFile(const APKeyFile,
  APassword: string);
var
  LBytes: TBytes;
begin
  LBytes := TFileUtils.ReadAllBytes(APKeyFile);
  try
    SetPrivateKey(LBytes, APassword);
  finally
    if Length(LBytes) > 0 then
      FillChar(LBytes[0], Length(LBytes), 0);
  end;
end;

procedure TCrossHttpClient._Lock;
begin
  FLock.Enter;
end;

procedure TCrossHttpClient._ProcTimeout;
type
  TTimeoutKind = (tkNone, tkRequest, tkConnect, tkIdle);

  function _GetTimeoutKind(const AConnection: TCrossHttpClientConnection): TTimeoutKind;
  var
    LClient: TCrossHttpClient;
    LTimeout: Integer;
  begin
    Result := tkNone;
    // 收集只判断候选：一次持锁取代三个判定各自加锁；实际动作仍用原函数重验。
    AConnection._ReqLock;
    try
      LClient := (AConnection.Owner as TCrossHttpClientSocket).FHttpClient;
      // 与_IsRequestTimeout保持相同条件、优先级和秒级比较，未发完的升级请求也参与。
      LTimeout := LClient.FRequestTimeout;
      if LTimeout > 0 then
      begin
        if ((AConnection.GetRequestStatus in [rsSending, rsResponding])
          or ((AConnection.GetRequestStatus = rsUpgraded) and not AConnection.FSendFinished))
          and (AConnection.FWatch.ElapsedMilliseconds div 1000 >= LTimeout) then
          Exit(tkRequest);
      end;

      LTimeout := LClient.FConnectTimeout;
      if LTimeout > 0 then
      begin
        if (AConnection.ConnectStatus = csConnecting)
          and (AConnection.FWatch.ElapsedMilliseconds div 1000 >= LTimeout) then
          Exit(tkConnect);
      end;

      LTimeout := LClient.FIdleout;
      if LTimeout > 0 then
      begin
        if AConnection._IsIdle
          and (AConnection.FWatch.ElapsedMilliseconds div 1000 >= LTimeout) then
          Exit(tkIdle);
      end;
    finally
      AConnection._ReqUnlock;
    end;
  end;

  procedure _Proc(const AHttpCli: ICrossHttpClientSocket);
  var
    LConns: TCrossConnections;
    LConn: ICrossConnection;
    LHttpConn: ICrossHttpClientConnection;
    LHttpConnObj: TCrossHttpClientConnection;
    LRequestTimeoutArr, LIdleoutArr, LConnectTimeoutArr: TArray<ICrossHttpClientConnection>;
    LRequestCount, LIdleCount, LConnectCount, I: NativeInt;
    {$IFDEF DEBUG}
    LIdleCnt, LSendingCnt, LRespondingCnt, LRespondFailedCnt, LRespondTimeoutCnt: Integer;
    LFirstIdleConn: ICrossHttpClientConnection;
    LConnectionCount: Integer;
    LWatchElapsed: Int64;
    LWatchTime: TDateTime;
    {$ENDIF}
  begin
    LRequestTimeoutArr := [];
    LIdleoutArr := [];
    LConnectTimeoutArr := [];
    LRequestCount := 0;
    LIdleCount := 0;
    LConnectCount := 0;

    LConns := AHttpCli.LockConnections;
    try
      {$IFDEF DEBUG}
      LIdleCnt := 0;
      LSendingCnt := 0;
      LRespondingCnt := 0;
      LRespondFailedCnt := 0;
      LRespondTimeoutCnt := 0;
      LFirstIdleConn := nil;
      LConnectionCount := LConns.Count;
      {$ENDIF}

      for LConn in LConns.Values do
      begin
        LHttpConn := LConn as ICrossHttpClientConnection;
        LHttpConnObj := LHttpConn as TCrossHttpClientConnection;

        if not LConn.IsClosed then
        begin
          case _GetTimeoutKind(LHttpConnObj) of
            tkRequest:
              begin
                if LRequestCount = 0 then SetLength(LRequestTimeoutArr, LConns.Count);
                LRequestTimeoutArr[LRequestCount] := LHttpConn;
                Inc(LRequestCount);
              end;
            tkConnect:
              begin
                if LConnectCount = 0 then SetLength(LConnectTimeoutArr, LConns.Count);
                LConnectTimeoutArr[LConnectCount] := LHttpConn;
                Inc(LConnectCount);
              end;
            tkIdle:
              begin
                if LIdleCount = 0 then SetLength(LIdleoutArr, LConns.Count);
                LIdleoutArr[LIdleCount] := LHttpConn;
                Inc(LIdleCount);
              end;
          end;

          {$IFDEF DEBUG}
          case LHttpConn.RequestStatus of
            rsIdle:
              begin
                Inc(LIdleCnt);
                if (LFirstIdleConn = nil) then
                  LFirstIdleConn := LHttpConn;
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
      'http-client, conn:%d, timeout:%d, connect-timeout:%d, idleout:%d' +
      ', idle:%d, sending:%d, responding:%d, respond-failed:%d, respond-timeout:%d', [
      LConnectionCount, LRequestCount, LConnectCount, LIdleCount,
      LIdleCnt, LSendingCnt, LRespondingCnt, LRespondFailedCnt, LRespondTimeoutCnt
    ]);

    if (LFirstIdleConn <> nil) then
    begin
      LHttpConnObj := LFirstIdleConn as TCrossHttpClientConnection;
      LHttpConnObj._ReqLock;
      try
        LWatchElapsed := LHttpConnObj.FWatch.ElapsedMilliseconds;
        LWatchTime := LHttpConnObj.FWatch.LastTime;
      finally
        LHttpConnObj._ReqUnlock;
      end;
      _Log('first idle conn [%u] idle watch: %d ms / start-time: %s', [
        LFirstIdleConn.UID, LWatchElapsed,
        FormatDateTime('hh":"nn":"ss.zzz', LWatchTime)
      ]);
    end;
    {$ENDIF}

    {$IFDEF CROSS_HTTP_TIMEOUT_TESTS}
    if (LRequestCount + LConnectCount + LIdleCount > 0)
      and Assigned(GHttpTimeoutAfterCollect) then GHttpTimeoutAfterCollect;
    {$ENDIF}

    for I := 0 to LRequestCount - 1 do
    begin
      LHttpConnObj := LRequestTimeoutArr[I] as TCrossHttpClientConnection;
      LHttpConnObj.TriggerResponseTimeout;
    end;

    // 连接建立超时: 直接关闭, 触发 LogicDisconnected → 上层连接失败回调
    for I := 0 to LConnectCount - 1 do
      (LConnectTimeoutArr[I] as TCrossHttpClientConnection)._CloseIfTimeout(True);

    for I := 0 to LIdleCount - 1 do
      (LIdleoutArr[I] as TCrossHttpClientConnection)._CloseIfTimeout(False);
  end;
var
  LHttpCliArr: TArray<ICrossHttpClientSocket>;
  LHttpCli: ICrossHttpClientSocket;
begin
  _Lock;
  try
    LHttpCliArr := Copy(FHttpCliArr);
  finally
    _Unlock;
  end;

  for LHttpCli in LHttpCliArr do
    _Proc(LHttpCli);
end;

procedure TCrossHttpClient._Unlock;
begin
  FLock.Leave;
end;

procedure TCrossHttpClient._UpdateCliOptions;
var
  LHttpCli: ICrossHttpClientSocket;
begin
  for LHttpCli in FHttpCliArr do
    LHttpCli.SyncOptions(
      FMaxConnsPerServer, FMaxCompressRatio,
      FReUseConnection, FAutoUrlEncode);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: TFormUrlEncoded;
  const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  LIsGetReq: Boolean;
  LUrl, LReqStr: string;
  LReqBytes: TBytes;
begin
  LIsGetReq := TStrUtils.SameText(AMethod, THttpMethod.GET);
  LUrl := AUrl;
  if (ARequestBody <> nil) then
    LReqStr := ARequestBody.Encode
  else
    LReqStr := '';
  LReqBytes := nil;

  if LIsGetReq then
  begin
    if (LReqStr <> '') then
      LUrl := LUrl + '?' + LReqStr;
  end else
  begin
    LReqBytes := TEncoding.UTF8.GetBytes(LReqStr)
  end;

  DoRequest(AMethod, LUrl, AHttpHeaders,
    LReqBytes,
    AResponseStream,
    procedure(const ARequest: ICrossHttpClientRequest)
    begin
      if Assigned(AInitProc) then
        AInitProc(ARequest);

      if not LIsGetReq and (ARequest.Header[HEADER_CONTENT_TYPE] = '') then
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

function TCrossHttpClient.GetVerifyPeer: Boolean;
begin
  _Lock;
  try
    Result := FVerifyPeer;
  finally
    _Unlock;
  end;
end;

function TCrossHttpClient.GetProxySettings: TCrossProxySettings;
begin
  _Lock;
  try
    Result := FProxySettings;
  finally
    _Unlock;
  end;
end;

function TCrossHttpClient.GetMaxConnsPerServer: Integer;
begin
  Result := FMaxConnsPerServer;
end;

function TCrossHttpClient.GetMaxCompressRatio: Integer;
begin
  Result := FMaxCompressRatio;
end;

function TCrossHttpClient.GetReUseConnection: Boolean;
begin
  Result := FReUseConnection;
end;

function TCrossHttpClient.GetRequestTimeout: Integer;
begin
  Result := FRequestTimeout;
end;

function TCrossHttpClient.GetConnectTimeout: Integer;
begin
  Result := FConnectTimeout;
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
  _UpdateCliOptions;
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

procedure TCrossHttpClient.SetVerifyPeer(const AValue: Boolean);
begin
  _Lock;
  try
    if AValue and (Length(FCACertificates) = 0) then
      raise ECrossHttpClient.Create(
        'At least one CA certificate is required before enabling peer verification.');
    if FHttpsCli <> nil then
      FHttpsCli.VerifyPeer := AValue;
    FVerifyPeer := AValue;
  finally
    _Unlock;
  end;
end;

procedure TCrossHttpClient.SetProxySettings(
  const AValue: TCrossProxySettings);
var
  LHttpCli: ICrossHttpClientSocket;
  LHttpCliArr: TArray<ICrossHttpClientSocket>;
begin
  _Lock;
  try
    FProxySettings := AValue;
    LHttpCliArr := Copy(FHttpCliArr);
  finally
    _Unlock;
  end;

  for LHttpCli in LHttpCliArr do
    (LHttpCli as TObject as TCrossHttpClientSocket).SyncProxySettings(AValue);
end;

procedure TCrossHttpClient.SetMaxCompressRatio(const AValue: Integer);
begin
  // 同步到所有已创建的 socket; 已建立的 connection 上 parser 已用旧值, 仅影响后续新建连接.
  FMaxCompressRatio := AValue;
  _UpdateCliOptions;
end;

procedure TCrossHttpClient.SetMaxConnsPerServer(const AValue: Integer);
begin
  FMaxConnsPerServer := AValue;
  _UpdateCliOptions;
end;

procedure TCrossHttpClient.SetReUseConnection(const AValue: Boolean);
begin
  FReUseConnection := AValue;
  _UpdateCliOptions;
end;

procedure TCrossHttpClient.SetRequestTimeout(const AValue: Integer);
begin
  FRequestTimeout := AValue;
end;

procedure TCrossHttpClient.SetConnectTimeout(const AValue: Integer);
begin
  FConnectTimeout := AValue;
end;

{ TServerDock }

procedure TServerDock.AddConnection(
  const AConnection: ICrossHttpClientConnection);
begin
  // 连接计数与连接列表的管理统一归于此方法,
  // 调用方不再需要单独维护 FConnCount (与 RemoveConnection 对称)
  _Lock;
  try
    Inc(FConnCount);
    FConnections.Add(AConnection);
  finally
    _Unlock;
  end;
end;

procedure TServerDock.CancelAllRequests(const AStatusCode: Integer;
  const AStatusText: string);
var
  LRequestArr: TArray<ICrossHttpClientRequest>;
  LRequest: ICrossHttpClientRequest;
begin
  _Lock;
  try
    LRequestArr := FRequestQueue.ToArray;
    FRequestQueue.Clear;
  finally
    _Unlock;
  end;

  for LRequest in LRequestArr do
  try
    (LRequest as TCrossHttpClientRequest)._ExecCallback(
      TCrossHttpClientResponse.Create(AStatusCode, AStatusText));
  except
    on E: Exception do
      _LogException('CancelAllRequests callback failed', E);
  end;
end;

constructor TServerDock.Create(const AClientSocket: TCrossHttpClientSocket;
  const AProtocol, AHost: string; const APort, ALocalPort: Word);
var
  LCount: THttpRequestCount;
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
  if FClientSocket <> nil then
    FRequestLimit := FClientSocket.FHttpClient.FMaxPendingRequestsPerServer;
  if FRequestLimit > 0 then
  begin
    LCount := THttpRequestCount.Create;
    LCount.Lock := FLock;
    FRequestCount := LCount;
  end;
end;

destructor TServerDock.Destroy;
begin
  FreeAndNil(FRequestQueue);
  FreeAndNil(FConnections);

  inherited;
end;

procedure TServerDock._DoRequestOn(const AHttpConn: ICrossHttpClientConnection;
  const ARequest: ICrossHttpClientRequest);
var
  LConnectionObj: TCrossHttpClientConnection;
  LRequest: ICrossHttpClientRequest;
  LRequestObj: TCrossHttpClientRequest;
  LSelf: IServerDock;
begin
  // 调用方(空闲连接路径 与 Connect 成功分支)保证 AHttpConn <> nil;
  // 连接失败场景已在 DoRequest 闭包失败分支独立处理, 不再进入本方法
  LRequest := ARequest;
  LSelf := Self;
  LRequestObj := ARequest as TCrossHttpClientRequest;
  if _IsClosing then
  begin
    try AHttpConn.Close; finally _CancelRequest(LRequestObj); end;
    Exit;
  end;

  LConnectionObj := AHttpConn as TCrossHttpClientConnection;
  LConnectionObj.DoRequest(ARequest,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      try
        LRequestObj._ExecCallback(AResponse);
      finally
        LRequest := nil;
        LSelf.ProcNext;
      end;
    end,
    procedure
    begin
      LSelf.ProcNext;
    end);
end;


procedure TServerDock._HandleConnectSuccess(
  const AConnection: ICrossConnection;
  const ARequest: ICrossHttpClientRequest; const ALSelf: IServerDock;
  const AProtocol, ARawHost, AHost: string; const APort: Word);
var
  LNewHttpConn: ICrossHttpClientConnection;
  LNewHttpConnObj: TCrossHttpClientConnection;
begin
  if _IsClosing then
  begin
    try AConnection.Close;
    finally _CancelRequest(ARequest as TCrossHttpClientRequest); end;
    Exit;
  end;
  LNewHttpConn := AConnection as ICrossHttpClientConnection;
  LNewHttpConnObj := LNewHttpConn as TCrossHttpClientConnection;
  LNewHttpConnObj.FProtocol := AProtocol;
  LNewHttpConnObj.FRawHost := ARawHost;
  LNewHttpConnObj.FHost := AHost;
  LNewHttpConnObj.FPort := APort;

  ALSelf.AddConnection(LNewHttpConn);
  _DoRequestOn(LNewHttpConn, ARequest);
end;

procedure TServerDock._HandleConnectFailure(
  const AConnection: ICrossConnection;
  const ARequestObj: TCrossHttpClientRequest; const ALSelf: IServerDock);
var
  LErrMsg: string;
  LErrCode: Integer;
begin
  LErrMsg := 'Connect failed';
  if (AConnection <> nil) then
  begin
    // 代理握手错误优先于底层 socket 错误, 这样 407/认证失败不会被吞掉。
    if AConnection.ProxyError <> '' then
      LErrMsg := 'Connect failed: ' + AConnection.ProxyError;
    LErrCode := AConnection.LastNetError;
    if (LErrCode <> 0) and (Pos('Connect failed:', LErrMsg) = 0) then
      LErrMsg := TStrUtils.Format('Connect failed (code=%d)', [LErrCode]);
  end;
  try
    ARequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, LErrMsg));
  except
    on E: Exception do
      _Log('Connect failed callback exception: %s', [E.Message]);
  end;
  ALSelf.ProcNext;
end;
function TServerDock._IsClosing: Boolean;
begin
  Result := (FClientSocket <> nil)
    and (AtomicCmpExchange(FClientSocket.FHttpClient.FClosing, 0, 0) <> 0);
end;

procedure TServerDock._CancelRequest(const ARequest: TCrossHttpClientRequest);
begin
  try
    ARequest._ExecCallback(TCrossHttpClientResponse.Create(400, 'Request canceled'));
  except
    on E: Exception do _LogException('HTTP client canceled callback failed', E);
  end;
end;

function TServerDock._TryBeginConnect: Boolean;
var
  LMaxConnsPerServer: Integer;
begin
  LMaxConnsPerServer := FClientSocket.FMaxConnsPerServer;
  _Lock;
  try
    Result := not _IsClosing and ((LMaxConnsPerServer <= 0)
      or (FConnCount + FConnectingCount < LMaxConnsPerServer));
    if Result then
      Inc(FConnectingCount);
  finally
    _Unlock;
  end;
end;

procedure TServerDock._EndConnect;
begin
  _Lock;
  try
    Dec(FConnectingCount);
  finally
    _Unlock;
  end;
end;

function TServerDock._TryAdmitRequest(const ARequest: TCrossHttpClientRequest): Boolean;
var
  LCount: THttpRequestCount;
begin
  if AtomicCmpExchange(ARequest.FCompleted, 0, 0) <> 0 then Exit(False);
  // 默认无限制不创建计数对象，也不为每个请求保存额外引用。
  if FRequestCount = nil then Exit(True);
  _Lock;
  ARequest.FStateLock.Enter;
  try
    if AtomicCmpExchange(ARequest.FCompleted, 0, 0) <> 0 then Exit(False);
    // 已出队但尚未完成的请求仍占原额度，重试不能重复计费。
    if ARequest.FAdmission <> nil then Exit(True);
    LCount := FRequestCount as THttpRequestCount;
    if LCount.Count >= FRequestLimit then Exit(False);
    Inc(LCount.Count);
    ARequest.FAdmission := FRequestCount;
    Result := True;
  finally
    ARequest.FStateLock.Leave;
    _Unlock;
  end;
end;

procedure TServerDock.DoRequest(const ARequest: ICrossHttpClientRequest);
var
  LSelf: IServerDock;
  LRequest: ICrossHttpClientRequest;
  LIdleHttpConn: ICrossHttpClientConnection;
  LRequestObj: TCrossHttpClientRequest;
  LClientSocket: TCrossHttpClientSocket;
  LProtocol, LRawHost, LHost: string;
  LPort, LLocalPort, LPhysicalPort: Word;
  LPhysicalHost: string;
begin
  LRequest := ARequest;
  LRequestObj := LRequest as TCrossHttpClientRequest;
  if _IsClosing then
  begin
    _CancelRequest(LRequestObj);
    Exit;
  end;
  if not _TryAdmitRequest(LRequestObj) then
  begin
    try
      LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(503, 'Client request limit exceeded'));
    except
      on E: Exception do _LogException('HTTP client rejected callback failed', E);
    end;
    Exit;
  end;
  LIdleHttpConn := nil;

  // 优先使用空闲连接
  if FClientSocket.FReUseConnection then
    LIdleHttpConn := GetIdleConnection;

  // 有空闲连接, 使用空闲连接处理请求
  if (LIdleHttpConn <> nil) then
  begin
    // 异常兜底: _DoRequestOn 内部若抛异常(URL 异常/OOM/底层异常等),
    // 仍保证用户回调被触发一次且请求队列必定推进, 避免在途请求悬挂
    try
      _DoRequestOn(LIdleHttpConn, LRequest);
    except
      on E: Exception do
      begin
        try
          LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, 'Internal: ' + E.Message));
        except
          // 用户回调内的异常不向外传播, 确保 ProcNext 能被执行
        end;
        ProcNext;
      end;
    end;
    Exit;
  end;

  // 没有空闲连接并且连接数未超过限定
  // 建立新连接
  if _TryBeginConnect then
  begin
    // 显式升级 Self 为 IServerDock 接口引用, 由闭包捕获
    // → 引用计数保证 TServerDock 对象在异步回调触发时仍存活, 回调可直接调用成员方法
    //   即使此期间 FServerDockDict 已被销毁也不影响本次请求完成
    LSelf := Self;

    LClientSocket := FClientSocket;
    LProtocol := FProtocol;
    LRawHost := FRawHost;
    LHost := FHost;
    LPort := FPort;
    LLocalPort := FLocalPort;
    LPhysicalHost := LHost;
    LPhysicalPort := LPort;
    if LClientSocket.FProxySettings.IsEnabled and
      not LClientSocket.FProxySettings.ShouldBypass(LHost) then
    begin
      LPhysicalHost := LClientSocket.FProxySettings.Host;
      LPhysicalPort := LClientSocket.FProxySettings.Port;
    end;

    try
      LClientSocket.ConnectTarget(LPhysicalHost, LPhysicalPort, LLocalPort,
        LHost, LPort,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        try
          _EndConnect;
          try
            if ASuccess then
              _HandleConnectSuccess(AConnection, LRequest, LSelf, LProtocol, LRawHost, LHost, LPort)
            else
              _HandleConnectFailure(AConnection, LRequestObj, LSelf);
          except
            on E: Exception do
            begin
              try LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, 'Internal: ' + E.Message)); except end;
              LSelf.ProcNext;
            end;
          end;
        finally
          LSelf := nil;
          LRequest := nil;
        end;
      end);
    except
      on E: Exception do
      begin
        _EndConnect;
        LSelf := nil;
        LRequestObj._ExecCallback(TCrossHttpClientResponse.Create(400, 'Connect failed: ' + E.Message));
        ProcNext;
      end;
    end;

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
  I: Integer;
  LConn: ICrossConnection;
  LHttpConnObj: TCrossHttpClientConnection;
begin
  _Lock;
  try
    // 同一dock锁保护列表与连接认领；索引遍历省去每次查找的枚举器对象。
    for I := 0 to FConnections.Count - 1 do
    begin
      LConn := FConnections[I];
      LHttpConnObj := LConn as TCrossHttpClientConnection;
      if LHttpConnObj._TryBeginRequest then
      begin
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

    ARequest := FRequestQueue.Dequeue;
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
  {$IFDEF CROSS_CAPACITY_TESTS}_ClientAdmissionTest('after-pop', LRequest);{$ENDIF}

  DoRequest(LRequest);
end;

procedure TServerDock.PushRequest(const ARequest: ICrossHttpClientRequest);
var
  LCancel: Boolean;
begin
  {$IFDEF CROSS_CAPACITY_TESTS}_ClientAdmissionTest('before-push', ARequest);{$ENDIF}
  _Lock;
  try
    LCancel := _IsClosing;
    if not LCancel then FRequestQueue.Enqueue(ARequest);
  finally
    _Unlock;
  end;
  if LCancel then _CancelRequest(ARequest as TCrossHttpClientRequest);
end;

procedure TServerDock.RemoveConnection(
  const AConnection: ICrossHttpClientConnection);
var
  LNeedProcNext: Boolean;
begin
  _Lock;
  try
    Dec(FConnCount);
    FConnections.Remove(AConnection);

    // 连接被移除后, 只要队列里还有积压请求就推进 (防御性加固).
    // 原逻辑用 (GetRequestStatus = rsIdle) 判断, 但连接已在被移除, 此判断意义不明,
    // 且漏掉 rsClose / rsRespondFailed / rsRespondTimeout 等状态. 在异步 IO 路径下
    // (LogicDisconnected 跨线程触发) 可能造成排队请求得不到处理.
    LNeedProcNext := (FRequestQueue.Count > 0);
  finally
    _Unlock;
  end;

  if LNeedProcNext then
    ProcNext;
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
