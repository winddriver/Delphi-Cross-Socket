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
  {$ENDIF}
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

    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValues: TArray<string>): Boolean;
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
    function _IsRequestTimeout: Boolean;
    function _IsConnectTimeout: Boolean;
    function _SetRequestStatus(const AStatus: TRequestStatus): TRequestStatus;

    procedure _ReqLock; inline;
    procedure _ReqUnlock; inline;
    function _CreateRequestHeader(const ABodySize: Int64; AChunked: Boolean): TBytes;
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
      const ASendCb: TCrossConnectionCallback = nil);
    procedure _HttpSend(const AHeaderSource, ABodySource: TCrossHttpChunkDataFunc;
      const ASendCb: TCrossConnectionCallback = nil);
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
    FUrlReady: Boolean;
    FQuery: THttpUrlParams;
    FRequestBodyFunc: TCrossHttpChunkDataFunc;
    FRequestBody: Pointer;
    FRequestBodySize: NativeInt;
    FResponseStream: TStream;
    FInitProc: TCrossHttpRequestInitProc;
    FCallback: TCrossHttpResponseProc;

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

    procedure _Lock; inline;
    procedure _Unlock; inline;
    function _TryBeginConnect: Boolean;
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

    procedure _LockServerDock; inline;
    procedure _UnlockServerDock; inline;

    function _MakeServerDockKey(const AProtocol, AHost: string; const APort: Word): string;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word;
      out AServerDock: IServerDock): Boolean; overload;
    function _GetServerDock(const AProtocol, AHost: string; const APort: Word): IServerDock; overload;
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

  TCrossHttpClient = class(TInterfacedObject, ICrossHttpClient)
  private
    class var FDefaultIOThreads: Integer;
    class var FDefault: ICrossHttpClient;

    class constructor Create;
    class function GetDefault: ICrossHttpClient; static;
  private
    FIoThreads, FMaxConnsPerServer, FMaxCompressRatio: Integer;
    FCompressType: TCompressType;
    FLock: ILock;
    FTimer: IEasyTimer;
    FHttpCli, FHttpsCli: ICrossHttpClientSocket;
    FHttpCliArr: TArray<ICrossHttpClientSocket>;
    FRequestTimeout, FIdleout, FConnectTimeout: Integer;
    FReUseConnection, FAutoUrlEncode: Boolean;
    FLocalPort: Word;
    FVerifyPeer: Boolean;
    FCertificate, FPrivateKey: TBytes;
    FPrivateKeyPassword: string;
    FCACertificates: TArray<TBytes>;

    procedure _ProcTimeout;
    procedure _UpdateCliOptions;
    procedure _ApplyTlsOptions(const ACli: ICrossHttpClientSocket);
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
  public
    constructor Create(const AIoThreads, AMaxConnsPerServer: Integer;
      const ACompressType: TCompressType = ctNone); overload;
    constructor Create(const AIoThreads: Integer = 4;
      const ACompressType: TCompressType = ctNone); overload;
    destructor Destroy; override;

    procedure Prepare(const AProtocols: array of string);

    procedure CancelAll; virtual;

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
    property MaxConnsPerServer: Integer read GetMaxConnsPerServer write SetMaxConnsPerServer;
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;
    property ReUseConnection: Boolean read GetReUseConnection write SetReUseConnection;
    property RequestTimeout: Integer read GetRequestTimeout write SetRequestTimeout;
    property ConnectTimeout: Integer read GetConnectTimeout write SetConnectTimeout;
    property AutoUrlEncode: Boolean read GetAutoUrlEncode write SetAutoUrlEncode;
    property LocalPort: Word read GetLocalPort write SetLocalPort;
    property VerifyPeer: Boolean read GetVerifyPeer write SetVerifyPeer;
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

  LHttpClientSocket := AOwner as TCrossHttpClientSocket;

  FHttpParser := TCrossHttpParser.Create(pmClient);
  // 透传压缩比限制 (zip bomb 防御); 直接读 socket 字段, 与其它配置 (CompressType / AutoUrlEncode) 取值方式一致
  FHttpParser.MaxCompressRatio := LHttpClientSocket.FMaxCompressRatio;
  FHttpParser.OnHeaderData := _OnHeaderData;
  FHttpParser.OnGetHeaderValue := _OnGetHeaderValue;
  FHttpParser.OnBodyBegin := _OnBodyBegin;
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
  finally
    _ReqUnlock;
  end;

  try
    // 调用初始化函数
    if Assigned(LRequestObj.FInitProc) then
      LRequestObj.FInitProc(ARequest);

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
        FCompressType);
    end else
    begin
      SendZCompress(
        LRequestBody,
        LRequestBodySize,
        FCompressType);
    end;
  except
    on E: Exception do
      TriggerResponseFailed(400, 'Internal: ' + E.Message);
  end;
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
begin
  _UpdateWatch;

//  _Log('ParseRecvData, %s, 0x%x, %d', [Self.DebugInfo, NativeUInt(ABuf), ALen]);
  if (FHttpParser <> nil) then
    FHttpParser.Decode(ABuf, ALen)
  else
    ALen := 0;
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
  LRequestEnded: Boolean;
begin
  LCallback := nil;
  LRequestEnded := False;
  _ReqLock;
  try
    // 只在请求进行中的状态才处理, 防止竞态下重复触发回调与 _EndRequest 多减计数
    if not (RequestStatus in [rsIdle, rsSending, rsResponding]) then Exit;

    LCallback := FCallback;
    FCallback := nil;
    LRequestEnded := True;

    _SetRequestStatus(rsRespondFailed);
  finally
    FRequest := nil;
    FRequestObj := nil;
    FResponse := nil;
    FResponseObj := nil;

    _ReqUnlock;
    if LRequestEnded then
      _EndRequest;
  end;

  Close;

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
  LRequestEnded, LIsSwitching: Boolean;
  LNeedClose: Boolean;
begin
  LCallback := nil;
  LResponse := nil;
  LRequestEnded := False;
  LNeedClose := False;
  _ReqLock;
  try
    // 只有在等待响应状态的情况才应该触发完成响应回调
    // 因为有可能响应完成的数据在超时后才到来, 这时候请求状态已经被置为超时
    // 不应该再触发完成回调
    if not (RequestStatus in [rsSending, rsResponding]) then Exit;

    LCallback := FCallback;
    FCallback := nil;
    LResponse := FResponse;
    LRequestEnded := True;

    // HTTP/1.1 101 Switching Protocols: 协议升级, 连接由上层协议(如 WebSocket)接管,
    // 不能 close, 也不能进入 idle 池被复用为 HTTP 请求.
    LIsSwitching := (FResponseObj <> nil)
      and (FResponseObj.FStatusCode = 101);

    if IsClosed
      or ((not LIsSwitching)
        and ((not (Owner as TCrossHttpClientSocket).FReUseConnection)
          or ((FResponseObj <> nil) and SameText(FResponseObj.FHeader[HEADER_CONNECTION], 'close')))) then
    begin
      _SetRequestStatus(rsClose);
      LNeedClose := True;
    end else if LIsSwitching then
    begin
      _SetRequestStatus(rsUpgraded);
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
    if LRequestEnded then
      _EndRequest;
  end;
  if LNeedClose then Close;
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
  LResponse: ICrossHttpClientResponse;
  LRequestEnded: Boolean;
begin
  LCallback := nil;
  LRequestEnded := False;
  _ReqLock;
  try
    // 只在请求进行中的状态才处理, 防止重复触发与 _EndRequest 多减计数
    if not (RequestStatus in [rsSending, rsResponding]) then Exit;

    LCallback := FCallback;
    FCallback := nil;
    LRequestEnded := True;

    _SetRequestStatus(rsRespondTimeout);
  finally
    FRequest := nil;
    FRequestObj := nil;
    FResponse := nil;
    FResponseObj := nil;

    _ReqUnlock;
    if LRequestEnded then
      _EndRequest;
  end;
  Close;
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
    begin
          // Owner 在 TCrossHttpClientSocket.CreateConnection 中固定为 TCrossHttpClientSocket
      if (Owner as TCrossHttpClientSocket).FReUseConnection then
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

    if FAutoUrlEncode then
    begin
      // 按 RFC 3986 分组件编码:
      //   path: pchar = unreserved / pct-encoded / sub-delims / ":" / "@", 段间 "/"
      //         APreserveEncoded=True 启用 Normalizer 语义, 识别已有 %xx 序列,
      //         避免二次编码 (RFC 3986 §2.4 "MUST NOT encode the same string more than once")
      //   query: 由 FQuery.Encode 处理, 内部 key/value 已被 SetUrl 阶段 Decode 到原始字节,
      //          重新编码时 key/value 均按严格 unreserved 集编码 (&/=/% 等都正确转义).
      LPathStr := TCrossHttpUtils.UrlEncode(FRequestObj.FPath, ['/', ':', '@'], True);
      if (FRequestObj.FQuery.Count > 0) then
        LPathStr := LPathStr + '?' + FRequestObj.FQuery.Encode;
    end else
      LPathStr := FRequestObj.FPathAndParams;

    // 设置请求行
    LHeaderStr := FRequestObj.FMethod + ' '
      + LPathStr + ' '
      + HTTP_VER_STR[FRequestObj.FHttpVersion] + CRLF;

    LHeaderStr := LHeaderStr + FRequestObj.FHeader.Encode;
  finally
    _ReqUnlock;
  end;

  Result := TEncoding.ASCII.GetBytes(LHeaderStr);
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

  // 仅判定已连接(csConnected)的空闲连接, csConnecting 状态交由 _IsConnectTimeout 处理
  Result := (ConnectStatus = csConnected)
    and (GetRequestStatus = rsIdle)
    and (FWatch.ElapsedMilliseconds div 1000 >= LIdleout);
end;

function TCrossHttpClientConnection._IsRequestTimeout: Boolean;
var
  LRequestTimeout: Integer;
begin
  LRequestTimeout := (Owner as TCrossHttpClientSocket).FHttpClient.FRequestTimeout;
  if (LRequestTimeout <= 0) then Exit(False);

  Result := (GetRequestStatus in [rsSending, rsResponding])
    and (FWatch.ElapsedMilliseconds div 1000 >= LRequestTimeout);
end;

function TCrossHttpClientConnection._IsConnectTimeout: Boolean;
var
  LConnectTimeout: Integer;
begin
  LConnectTimeout := (Owner as TCrossHttpClientSocket).FHttpClient.FConnectTimeout;
  if (LConnectTimeout <= 0) then Exit(False);

  // 处理 ConnectEx 投递成功但 SYN 永远收不到响应的退化场景
  Result := (ConnectStatus = csConnecting)
    and (FWatch.ElapsedMilliseconds div 1000 >= LConnectTimeout);
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
    FResponseObj.ParseHeader(ADataPtr, ADataSize);
    if (FRequestObj <> nil) and (FHttpParser <> nil) then
      FHttpParser.SetNoBody(SameText(FRequestObj.FMethod, THttpMethod.HEAD)
        or ((FResponseObj.FStatusCode >= 100) and (FResponseObj.FStatusCode < 200))
        or (FResponseObj.FStatusCode = 204)
        or (FResponseObj.FStatusCode = 304));
  end;
end;

procedure TCrossHttpClientConnection._OnParseBegin;
begin
  _ReqLock;
  try
    FResponseObj := TCrossHttpClientResponse.Create(Self);
    FResponse := FResponseObj;

    FResponseObj._SetResponseStream(FRequestObj.FResponseStream);
  finally
    _ReqUnlock;
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

procedure TCrossHttpClientConnection._SocketSend(
  const ASource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback);
var
  LHttpConnection: ICrossHttpClientConnection;
  LSender: TCrossConnectionCallback;
begin
  LHttpConnection := Self;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
    begin
      try
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
          _ReqLock;
          try
            if (RequestStatus = rsSending) then
              _SetRequestStatus(rsResponding);
          finally
            _ReqUnlock;
          end;
          LHttpConnection := nil;
          LSender := nil;

          if Assigned(ASendCb) then
            ASendCb(AConnection, ASuccess);

          Exit;
        end;

        LHttpConnection.SendBuf(LData^, LCount, LSender);
      except
        on E: Exception do
        begin
          LHttpConnection := nil;
          LSender := nil;
          if Assigned(ASendCb) then
            ASendCb(AConnection, False);
          TriggerResponseFailed(400, 'Send failed: ' + E.Message);
        end;
      end;
    end;

  LSender(LHttpConnection, True);
end;

procedure TCrossHttpClientConnection._HttpSend(const AHeaderSource,
  ABodySource: TCrossHttpChunkDataFunc;
  const ASendCb: TCrossConnectionCallback);
var
  LMethodIsHead, LHeaderDone: Boolean;
begin
  // 更新计时器
  _UpdateWatch;

  _ReqLock;
  try
    // 标记正在发送请求
    _SetRequestStatus(rsSending);

    LMethodIsHead := (FRequest <> nil) and (FRequest.Method = 'HEAD');
  finally
    _ReqUnlock;
  end;

  // HEAD 请求不应包含请求体 (RFC 7231 §4.3.2)
  if LMethodIsHead then
  begin
    _SocketSend(AHeaderSource, ASendCb);
    Exit;
  end;

  LHeaderDone := False;

  _SocketSend(
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

procedure TCrossHttpClientRequest._ExecCallback(
  const AResponse: ICrossHttpClientResponse);
var
  LCallback: TCrossHttpResponseProc;
begin
  if not Assigned(FCallback) then Exit;

  LCallback := FCallback;
  FCallback := nil;
  LCallback(AResponse);
end;

procedure TCrossHttpClientRequest._Init(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader;
  const ARequestBodyFunc: TCrossHttpChunkDataFunc; const ARequestBody: Pointer;
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
    _ExecCallback(TCrossHttpClientResponse.Create(400, 'Invalid URL:' + FUrl));
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
  LCookie: TResponseCookie;
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
  if (I < 0) then Exit(False);
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
    begin
      LCookie := TResponseCookie.Create(LHeader.Value, FConnectionObj.FHost);
      if (LCookie.Name <> '') then
        FCookies.Add(LCookie);
    end;
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

  inherited Create(AIoThreads, ASsl);

  FServerDockDict := TServerDockDict.Create;
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

  if Assigned(LConnObj.FCallback) and (LConnObj.FHttpParser <> nil) then
    LConnObj.FHttpParser.Finish;

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
  if (FTimer <> nil) then
  begin
    FTimer.Terminate;
    FTimer.WaitFor;
    FTimer := nil;
  end;

  if (FHttpCli <> nil) then
    FHttpCli.StopLoop;

  if (FHttpsCli <> nil) then
    FHttpsCli.StopLoop;

  if Length(FPrivateKey) > 0 then
    FillChar(FPrivateKey[0], Length(FPrivateKey), 0);
  FPrivateKeyPassword := '';

  inherited;
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
      FHttpsCli := LHttpsCli;
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
  if not LRequestObj.FUrlReady then Exit;

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
  if not LRequestObj.FUrlReady then Exit;

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
  procedure _Proc(const AHttpCli: ICrossHttpClientSocket);
  var
    LConns: TCrossConnections;
    LConn: ICrossConnection;
    LHttpConn: ICrossHttpClientConnection;
    LHttpConnObj: TCrossHttpClientConnection;
    LRequestTimeoutArr, LIdleoutArr, LConnectTimeoutArr: TArray<ICrossHttpClientConnection>;
    {$IFDEF DEBUG}
    LIdleCnt, LSendingCnt, LRespondingCnt, LRespondFailedCnt, LRespondTimeoutCnt: Integer;
    LFirstIdleConn: TCrossHttpClientConnection;
    {$ENDIF}
  begin
    LRequestTimeoutArr := [];
    LIdleoutArr := [];
    LConnectTimeoutArr := [];

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
          if LHttpConnObj._IsRequestTimeout then
            LRequestTimeoutArr := LRequestTimeoutArr + [LHttpConn]
          else if LHttpConnObj._IsConnectTimeout then
            LConnectTimeoutArr := LConnectTimeoutArr + [LHttpConn]
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
      'http-client, conn:%d, timeout:%d, connect-timeout:%d, idleout:%d' +
      ', idle:%d, sending:%d, responding:%d, respond-failed:%d, respond-timeout:%d', [
      LConns.Count, Length(LRequestTimeoutArr), Length(LConnectTimeoutArr), Length(LIdleoutArr),
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

    for LHttpConn in LRequestTimeoutArr do
    begin
      LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
      LHttpConnObj.TriggerResponseTimeout;
    end;

    // 连接建立超时: 直接关闭, 触发 LogicDisconnected → 上层连接失败回调
    for LHttpConn in LConnectTimeoutArr do
      LHttpConn.Close;

    for LHttpConn in LIdleoutArr do
      LHttpConn.Close;
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
      _Log('CancelAllRequests callback exception: %s', [E.Message]);
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

procedure TServerDock._DoRequestOn(const AHttpConn: ICrossHttpClientConnection;
  const ARequest: ICrossHttpClientRequest);
var
  LConnectionObj: TCrossHttpClientConnection;
  LRequest: ICrossHttpClientRequest;
  LRequestObj: TCrossHttpClientRequest;
begin
  // 调用方(空闲连接路径 与 Connect 成功分支)保证 AHttpConn <> nil;
  // 连接失败场景已在 DoRequest 闭包失败分支独立处理, 不再进入本方法
  LRequest := ARequest;
  LRequestObj := ARequest as TCrossHttpClientRequest;

  LConnectionObj := AHttpConn as TCrossHttpClientConnection;
  LConnectionObj.DoRequest(ARequest,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      try
        LRequestObj._ExecCallback(AResponse);
      finally
        LRequest := nil;
        ProcNext;
      end;
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
    LErrCode := AConnection.LastNetError;
    if (LErrCode <> 0) then
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
function TServerDock._TryBeginConnect: Boolean;
var
  LMaxConnsPerServer: Integer;
begin
  LMaxConnsPerServer := FClientSocket.FMaxConnsPerServer;
  _Lock;
  try
    Result := (LMaxConnsPerServer <= 0)
      or (FConnCount + FConnectingCount < LMaxConnsPerServer);
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

procedure TServerDock.DoRequest(const ARequest: ICrossHttpClientRequest);
var
  LSelf: IServerDock;
  LRequest: ICrossHttpClientRequest;
  LIdleHttpConn: ICrossHttpClientConnection;
  LRequestObj: TCrossHttpClientRequest;
  LClientSocket: TCrossHttpClientSocket;
  LProtocol, LRawHost, LHost: string;
  LPort, LLocalPort: Word;
begin
  LRequest := ARequest;
  LRequestObj := LRequest as TCrossHttpClientRequest;
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

    try
      LClientSocket.Connect(LHost, LPort, LLocalPort,
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
