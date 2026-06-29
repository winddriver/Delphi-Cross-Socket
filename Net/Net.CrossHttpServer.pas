{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpServer;

{$I zLib.inc}

{
  Linux下需要安装zlib1g-dev开发包
  sudo apt-get install zlib1g-dev
}

interface

uses
  Classes,
  SysUtils,
  Math,
  Generics.Collections,
  //ZLib,
  {$IFDEF DELPHI}
  ZLib,
  {$ELSE}
  DTF.StaticZLib,
  {$ENDIF}

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossServer,
  Net.CrossHttpParams,
  Net.CrossHttpUtils,
  Net.CrossHttpParser,

  Utils.StrUtils,
  Utils.IOUtils,
  Utils.Hash,
  Utils.RegEx,
  Utils.SyncObjs,
  Utils.ArrayUtils,
  Utils.DateTime;

const
  CROSS_HTTP_SERVER_NAME = 'CrossHttpServer/3.0';
  MIN_COMPRESS_SIZE = 512;
  WILDCARD_CHAR = '*';
  REGEX_CHARS: array of Char = [':', '*', '?', '(', ')', '[', '{', '|', '+', '.'];

type
  ECrossHttpException = class(Exception)
  private
    FStatusCode: Integer;
  public
    constructor Create(const AMessage: string; AStatusCode: Integer = 400); reintroduce; virtual;
    constructor CreateFmt(const AMessage: string; const AArgs: array of const; AStatusCode: Integer = 400); reintroduce; virtual;
    property StatusCode: Integer read FStatusCode write FStatusCode;
  end;

  ICrossHttpServer = interface;
  ICrossHttpRequest = interface;
  ICrossHttpResponse = interface;
  IHttpResponseQueueItem = interface;

  TCrossHttpServer = class;
  TCrossHttpRequest = class;
  TCrossHttpResponse = class;
  THttpResponseQueueItem = class;

  /// <summary>
  ///   HTTP连接接口
  /// </summary>
  ICrossHttpConnection = interface(ICrossServerConnection)
  ['{72E9AC44-958C-4C6F-8769-02EA5EC3E9A8}']
    function GetRequest: ICrossHttpRequest;
    function GetResponse: ICrossHttpResponse;
    function GetServer: ICrossHttpServer;
    function GetPending: Integer;

    /// <summary>
    ///   请求对象
    /// </summary>
    property Request: ICrossHttpRequest read GetRequest;

    /// <summary>
    ///   响应对象
    /// </summary>
    property Response: ICrossHttpResponse read GetResponse;

    /// <summary>
    ///   Server对象
    /// </summary>
    property Server: ICrossHttpServer read GetServer;

    /// <summary>
    ///   当前连接上"已开始解析但尚未完成响应"的请求数量
    ///   (含正在处理中的与已入队等待发送的)
    /// </summary>
    property Pending: Integer read GetPending;
  end;

  /// <summary>
  ///   请求体类型
  /// </summary>
  TBodyType = (btNone, btUrlEncoded, btMultiPart, btBinary);

  /// <summary>
  ///   HTTP请求接口
  /// </summary>
  ICrossHttpRequest = interface
  ['{B26B7E7B-6B24-4D86-AB58-EBC20722CFDD}']
    function GetConnection: ICrossHttpConnection;
    function GetRawRequestText: string;
    function GetRawPathAndQuery: string;
    function GetMethod: string;
    function GetPath: string;
    function GetPathAndQuery: string;
    function GetVersion: string;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
    function GetSession: ISession;
    function GetParams: THttpUrlParams;
    function GetQuery: THttpUrlParams;
    function GetQueryText: string;
    function GetBody: TObject;
    function GetRawBody: TStream;
    function GetBodyType: TBodyType;
    function GetKeepAlive: Boolean;
    function GetAccept: string;
    function GetAcceptEncoding: string;
    function GetAcceptLanguage: string;
    function GetReferer: string;
    function GetUserAgent: string;
    function GetIfModifiedSince: TDateTime;
    function GetIfNoneMatch: string;
    function GetRange: string;
    function GetIfRange: string;
    function GetAuthorization: string;
    function GetXForwardedFor: string;
    function GetContentLength: Int64;
    function GetHostName: string;
    function GetHostPort: Word;
    function GetContentType: string;
    function GetContentEncoding: string;
    function GetRequestBoundary: string;
    function GetRequestCmdLine: string;
    function GetRequestConnection: string;
    function GetTransferEncoding: string;
    function GetIsChunked: Boolean;
    function GetIsMultiPartFormData: Boolean;
    function GetIsUrlEncodedFormData: Boolean;
    function GetPostDataSize: Int64;

    /// <summary>
    ///   HTTP连接对象
    /// </summary>
    property Connection: ICrossHttpConnection read GetConnection;

    /// <summary>
    ///   原始请求数据
    /// </summary>
    property RawRequestText: string read GetRawRequestText;

    /// <summary>
    ///   原始请求路径及参数
    /// </summary>
    property RawPathAndParams: string read GetRawPathAndQuery;

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
    property Method: string read GetMethod;

    /// <summary>
    ///   <para>
    ///     请求路径, 不包含参数部分
    ///   </para>
    ///   <para>
    ///     比如: /api/callapi1
    ///   </para>
    /// </summary>
    property Path: string read GetPath;

    /// <summary>
    ///   <para>
    ///     请求路径及参数
    ///   </para>
    ///   <para>
    ///     比如: /api/callapi1?aaa=111&bbb=222
    ///   </para>
    /// </summary>
    property PathAndQuery: string read GetPathAndQuery;

    /// <summary>
    ///   请求版本:
    ///   <list type="bullet">
    ///     <item>
    ///       HTTP/1.0
    ///     </item>
    ///     <item>
    ///       HTTP/1.1
    ///     </item>
    ///   </list>
    /// </summary>
    property Version: string read GetVersion;

    /// <summary>
    ///   HTTP请求头
    /// </summary>
    property Header: THttpHeader read GetHeader;

    /// <summary>
    ///   客户端传递过来的Cookies
    /// </summary>
    property Cookies: TRequestCookies read GetCookies;

    /// <summary>
    ///   Session对象
    /// </summary>
    /// <remarks>
    ///   <para>
    ///     只有在Server开启了Session支持的情况, 该属性才有效, 否则该属性为nil
    ///   </para>
    ///   <para>
    ///     要开启Server的Session支持, 只需要设置Server.SessionIDCookieName不为空即可
    ///   </para>
    /// </remarks>
    property Session: ISession read GetSession;

    /// <summary>
    ///   <para>
    ///     请求路径中定义的参数
    ///   </para>
    ///   <para>
    ///     比如定义了一个Get('/echo/:text', cb) 然后有一个请求为 /echo/hello, 那么 Params
    ///     中就会有一个名为 'text', 值为 'hello' 的参数
    ///   </para>
    /// </summary>
    property Params: THttpUrlParams read GetParams;

    /// <summary>
    ///   请求路径后形如?key1=value1&amp;key2=value2的参数
    /// </summary>
    property Query: THttpUrlParams read GetQuery;

    /// <summary>
    ///   <para>
    ///     请求路径中定义的参数
    ///   </para>
    /// </summary>
    property QueryText: string read GetQueryText;

    /// <summary>
    ///   解析后的Body数据, 通过检查BodyType可以知道数据类型:
    ///   <list type="bullet">
    ///     <item>
    ///       btNone(nil)
    ///     </item>
    ///     <item>
    ///       btUrlEncoded(TFormUrlEncoded)
    ///     </item>
    ///     <item>
    ///       btMultiPart(THttpMultiPartFormData)
    ///     </item>
    ///     <item>
    ///       btBinary(TMemoryStream)
    ///     </item>
    ///   </list>
    /// </summary>
    property Body: TObject read GetBody;

    /// <summary>
    ///   原始Body数据流, 仅对btUrlEncoded和btBinary缓存; multipart/form-data返回nil
    /// </summary>
    /// <remarks>
    ///   调用方只读使用, 不负责释放
    /// </remarks>
    property RawBody: TStream read GetRawBody;

    /// <summary>
    ///   Body的类型,
    ///   <list type="bullet">
    ///     <item>
    ///       btNone(nil)
    ///     </item>
    ///     <item>
    ///       btUrlEncoded(TFormUrlEncoded)
    ///     </item>
    ///     <item>
    ///       btMultiPart(THttpMultiPartFormData)
    ///     </item>
    ///     <item>
    ///       btBinary(TMemoryStream)
    ///     </item>
    ///   </list>
    /// </summary>
    property BodyType: TBodyType read GetBodyType;

    /// <summary>
    ///   KeepAliv标志
    /// </summary>
    property KeepAlive: Boolean read GetKeepAlive;

    /// <summary>
    ///   客户端能接收的数据种类
    /// </summary>
    /// <remarks>
    ///   image/webp,image/*,*/*;q=0.8
    /// </remarks>
    property Accept: string read GetAccept;

    /// <summary>
    ///   客户端能接收的编码
    /// </summary>
    /// <remarks>
    ///   gzip, deflate, sdch
    /// </remarks>
    property AcceptEncoding: string read GetAcceptEncoding;

    /// <summary>
    ///   客户端能接收的语言
    /// </summary>
    /// <remarks>
    ///   zh-CN,zh;q=0.8
    /// </remarks>
    property AcceptLanguage: string read GetAcceptLanguage;

    /// <summary>
    ///   参考地址, 描述该请求由哪个页面发出
    /// </summary>
    property Referer: string read GetReferer;

    /// <summary>
    ///   用户代理
    /// </summary>
    /// <example>
    ///   Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like
    ///   Gecko) Chrome/50.0.2661.102 Safari/537.36
    /// </example>
    property UserAgent: string read GetUserAgent;

    /// <summary>
    ///   请求内容在浏览器端的缓存时间
    /// </summary>
    property IfModifiedSince: TDateTime read GetIfModifiedSince;

    /// <summary>
    ///   请求内容在浏览器端的标记
    /// </summary>
    property IfNoneMatch: string read GetIfNoneMatch;

    /// <summary>
    ///   请求分块传输
    /// </summary>
    property Range: string read GetRange;

    /// <summary>
    ///   请求分块传输时传往服务器的标记, 用于服务器比较数据是否已发生变化
    /// </summary>
    property IfRange: string read GetIfRange;

    /// <summary>
    ///   简单认证信息
    /// </summary>
    property Authorization: string read GetAuthorization;

    /// <summary>
    ///   通过HTTP代理或负载均衡方式连接到Web服务器的客户端最原始的IP地址的HTTP请求头字段
    /// </summary>
    property XForwardedFor: string read GetXForwardedFor;

    /// <summary>
    ///   请求数据长度
    /// </summary>
    property ContentLength: Int64 read GetContentLength;

    /// <summary>
    ///   请求的主机名(域名、IP)
    /// </summary>
    property HostName: string read GetHostName;

    /// <summary>
    ///   请求的主机端口
    /// </summary>
    property HostPort: Word read GetHostPort;

    /// <summary>
    ///   内容类型
    /// </summary>
    property ContentType: string read GetContentType;

    /// <summary>
    ///   请求命令行(也就是HTTP请求的第一行)
    /// </summary>
    property RequestCmdLine: string read GetRequestCmdLine;

    /// <summary>
    ///   请求分界符
    /// </summary>
    property RequestBoundary: string read GetRequestBoundary;

    /// <summary>
    ///   传输编码
    /// </summary>
    property TransferEncoding: string read GetTransferEncoding;

    /// <summary>
    ///   内容编码
    /// </summary>
    property ContentEncoding: string read GetContentEncoding;

    /// <summary>
    ///   连接方式
    /// </summary>
    property RequestConnection: string read GetRequestConnection;

    /// <summary>
    ///   请求数据是否使用块编码
    /// </summary>
    property IsChunked: Boolean read GetIsChunked;

    /// <summary>
    ///   请求数据是使用 multipart/form-data 方式提交的
    /// </summary>
    property IsMultiPartFormData: Boolean read GetIsMultiPartFormData;

    /// <summary>
    ///   请求数据是使用 application/x-www-form-urlencoded 方式提交的
    /// </summary>
    property IsUrlEncodedFormData: Boolean read GetIsUrlEncodedFormData;

    /// <summary>
    ///   请求数据大小
    /// </summary>
    property PostDataSize: Int64 read GetPostDataSize;
  end;

  /// <summary>
  ///   提供块数据的匿名函数
  /// </summary>
  TCrossHttpChunkDataFunc = reference to function(const AData: PPointer; const ACount: PNativeInt): Boolean;

  /// <summary>
  ///   HTTP响应队列项接口
  ///   用于按请求解析顺序串行化每个连接上的响应发送, 避免 pipelining 响应交错
  /// </summary>
  IHttpResponseQueueItem = interface
  ['{B03F35B7-6984-41A8-9AA0-6B3D48F18F91}']
    function GetRequest: ICrossHttpRequest;
    function GetResponse: ICrossHttpResponse;
    function GetSource: TCrossHttpChunkDataFunc;
    function GetCallback: TCrossConnectionCallback;
    function GetReady: Boolean;
    function GetSending: Boolean;
    function GetCompleted: Boolean;
    function GetKeepAlive: Boolean;
    function GetStatusCode: Integer;

    procedure SetRequest(const AValue: ICrossHttpRequest);
    procedure SetResponse(const AValue: ICrossHttpResponse);
    procedure SetSource(const AValue: TCrossHttpChunkDataFunc);
    procedure SetCallback(const AValue: TCrossConnectionCallback);
    procedure SetReady(const AValue: Boolean);
    procedure SetSending(const AValue: Boolean);
    procedure SetCompleted(const AValue: Boolean);
    procedure SetKeepAlive(const AValue: Boolean);
    procedure SetStatusCode(const AValue: Integer);

    property Request: ICrossHttpRequest read GetRequest write SetRequest;
    property Response: ICrossHttpResponse read GetResponse write SetResponse;
    property Source: TCrossHttpChunkDataFunc read GetSource write SetSource;
    property Callback: TCrossConnectionCallback read GetCallback write SetCallback;
    property Ready: Boolean read GetReady write SetReady;
    property Sending: Boolean read GetSending write SetSending;
    property Completed: Boolean read GetCompleted write SetCompleted;
    property KeepAlive: Boolean read GetKeepAlive write SetKeepAlive;
    property StatusCode: Integer read GetStatusCode write SetStatusCode;
  end;

  /// <summary>
  ///   HTTP响应队列项实现类
  /// </summary>
  THttpResponseQueueItem = class(TInterfacedObject, IHttpResponseQueueItem)
  private
    FRequest: ICrossHttpRequest;
    FResponse: ICrossHttpResponse;
    FSource: TCrossHttpChunkDataFunc;
    FCallback: TCrossConnectionCallback;
    FReady: Boolean;
    FSending: Boolean;
    FCompleted: Boolean;
    FKeepAlive: Boolean;
    FStatusCode: Integer;
  protected
    function GetRequest: ICrossHttpRequest;
    function GetResponse: ICrossHttpResponse;
    function GetSource: TCrossHttpChunkDataFunc;
    function GetCallback: TCrossConnectionCallback;
    function GetReady: Boolean;
    function GetSending: Boolean;
    function GetCompleted: Boolean;
    function GetKeepAlive: Boolean;
    function GetStatusCode: Integer;

    procedure SetRequest(const AValue: ICrossHttpRequest);
    procedure SetResponse(const AValue: ICrossHttpResponse);
    procedure SetSource(const AValue: TCrossHttpChunkDataFunc);
    procedure SetCallback(const AValue: TCrossConnectionCallback);
    procedure SetReady(const AValue: Boolean);
    procedure SetSending(const AValue: Boolean);
    procedure SetCompleted(const AValue: Boolean);
    procedure SetKeepAlive(const AValue: Boolean);
    procedure SetStatusCode(const AValue: Integer);
  end;

  /// <summary>
  ///   HTTP应答接口
  /// </summary>
  ICrossHttpResponse = interface
  ['{5E15C20F-E221-4B10-90FC-222173A6F3E8}']
    function GetConnection: ICrossHttpConnection;
    function GetRequest: ICrossHttpRequest;
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetContentType: string;
    function GetLocation: string;
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetSent: Boolean;

    procedure SetContentType(const Value: string);
    procedure SetLocation(const Value: string);
    procedure SetStatusCode(Value: Integer);
    procedure SetStatusText(const Value: string);

    /// <summary>
    ///   重置数据
    /// </summary>
    procedure Reset;

    /// <summary>
    ///   压缩发送块数据
    /// </summary>
    /// <param name="AChunkSource">
    ///   产生块数据的匿名函数
    ///   <code lang="Delphi">// AData: 数据指针
    /// // ACount: 数据大小
    /// // Result: 如果返回True, 则发送数据; 如果返回False, 则忽略AData和ACount并结束发送
    /// function(const AData: PPointer; const ACount: PNativeInt): Boolean
    /// begin
    /// end</code>
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   本方法实现了一边压缩一边发送数据, 所以可以支持无限大的分块数据的压缩发送, 而不用占用太多的内存和CPU<br />
    ///   zlib参考手册: <see href="http://www.zlib.net/zlib_how.html" /><br />
    /// </remarks>
    procedure SendZCompress(const AChunkSource: TCrossHttpChunkDataFunc; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   压缩发送无类型数据
    /// </summary>
    /// <param name="ABody">
    ///   无类型数据
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendZCompress(const ABody; const ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   压缩发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendZCompress(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   压缩发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendZCompress(const ABody: TBytes; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   压缩发送流数据
    /// </summary>
    /// <param name="ABody">
    ///   流数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure SendZCompress(const ABody: TStream; const AOffset, ACount: Int64; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   压缩发送流数据
    /// </summary>
    /// <param name="ABody">
    ///   流数据
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure SendZCompress(const ABody: TStream; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   压缩发送字符串数据
    /// </summary>
    /// <param name="ABody">
    ///   字符串数据
    /// </param>
    /// <param name="ACompressType">
    ///   压缩方式
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendZCompress(const ABody: string; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送块数据
    /// </summary>
    /// <param name="AChunkSource">
    ///   产生块数据的匿名函数
    ///   <code lang="Delphi">// AData: 数据指针
    /// // ACount: 数据大小
    /// // Result: 如果返回True, 则发送数据; 如果返回False, 则忽略AData和ACount并结束发送
    /// function(const AData: PPointer; const ACount: PNativeInt): Boolean
    /// begin
    /// end</code>
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   使用该方法可以一边生成数据一边发送, 无需等待数据全部准备完成
    /// </remarks>
    procedure SendNoCompress(const AChunkSource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送无类型数据
    /// </summary>
    /// <param name="ABody">
    ///   无类型数据
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendNoCompress(const ABody; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendNoCompress(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendNoCompress(const ABody: TBytes; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送流数据
    /// </summary>
    /// <param name="ABody">
    ///   流数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure SendNoCompress(const ABody: TStream; const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送流数据
    /// </summary>
    /// <param name="ABody">
    ///   流数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure SendNoCompress(const ABody: TStream; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   不压缩发送字符串数据
    /// </summary>
    /// <param name="ABody">
    ///   字符串数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendNoCompress(const ABody: string; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送无类型数据
    /// </summary>
    /// <param name="ABody">
    ///   无类型数据
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Send(const ABody; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Send(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Send(const ABody: TBytes; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送流数据
    /// </summary>
    /// <param name="ABody">
    ///   流数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure Send(const ABody: TStream; const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送流数据
    /// </summary>
    /// <param name="ABody">
    ///   流数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure Send(const ABody: TStream; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字符串数据
    /// </summary>
    /// <param name="ABody">
    ///   字符串数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Send(const ABody: string; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送Json字符串数据
    /// </summary>
    /// <param name="AJson">
    ///   Json字符串数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Json(const AJson: string; const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   发送文件内容
    /// </summary>
    /// <param name="AFileName">
    ///   文件名
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure SendFile(const AFileName: string; const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   将文件以下载形式发送
    /// </summary>
    /// <param name="AFileName">
    ///   文件名
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Download(const AFileName: string; const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   发送状态码
    /// </summary>
    /// <param name="AStatusCode">
    ///   状态码
    /// </param>
    /// <param name="ADescription">
    ///   描述信息(body)
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   描述信息即是body数据, 如果设置为空, 则body也为空
    /// </remarks>
    procedure SendStatus(const AStatusCode: Integer; const ADescription: string;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送状态码
    /// </summary>
    /// <param name="AStatusCode">
    ///   状态码
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   该方法根据状态码生成默认的body数据
    /// </remarks>
    procedure SendStatus(const AStatusCode: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送重定向Url命令
    /// </summary>
    /// <param name="AUrl">
    ///   新的Url
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure Redirect(const AUrl: string; const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   设置Content-Disposition, 令客户端将收到的数据作为文件下载处理
    /// </summary>
    /// <param name="AFileName">
    ///   文件名
    /// </param>
    procedure Attachment(const AFileName: string);

    /// <summary>
    ///   HTTP连接对象
    /// </summary>
    property Connection: ICrossHttpConnection read GetConnection;

    /// <summary>
    ///   请求对象
    /// </summary>
    property Request: ICrossHttpRequest read GetRequest;

    /// <summary>
    ///   状态码
    /// </summary>
    property StatusCode: Integer read GetStatusCode write SetStatusCode;

    /// <summary>
    ///   状态文本
    /// </summary>
    property StatusText: string read GetStatusText write SetStatusText;

    /// <summary>
    ///   内容类型
    /// </summary>
    property ContentType: string read GetContentType write SetContentType;

    /// <summary>
    ///   重定向Url
    /// </summary>
    property Location: string read GetLocation write SetLocation;

    /// <summary>
    ///   HTTP响应头
    /// </summary>
    property Header: THttpHeader read GetHeader;

    /// <summary>
    ///   设置Cookies
    /// </summary>
    property Cookies: TResponseCookies read GetCookies;

    /// <summary>
    ///   是否已经发送数据
    /// </summary>
    property Sent: Boolean read GetSent;
  end;

  TCrossHttpRouterProc = reference to procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean);
  TCrossHttpRouterMethod = procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean) of object;

  TCrossHttpConnEvent = procedure(const Sender: TObject; const AConnection: ICrossHttpConnection) of object;
  TCrossHttpRequestExceptionEvent = procedure(const Sender: TObject; const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; const AException: Exception) of object;

  TCrossHttpRequestEvent = procedure(const Sender: TObject;
    const AConnection: ICrossHttpConnection;
    const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
    var AHandled: Boolean) of object;

  // Begin/End 事件签名带上 ARequest/AResponse, 让事件 handler 能拿到本次事件
  // 对应的请求/响应对象, 不再依赖连接级 FRequest/FResponse 兼容视图
  // (该兼容视图在 pipelining 下语义模糊, 已不再由 _FinishQueueItem 维护)
  TCrossHttpRequestBeginEvent = procedure(const Sender: TObject;
    const AConnection: ICrossHttpConnection;
    const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse) of object;
  TCrossHttpRequestEndEvent = procedure(const Sender: TObject;
    const AConnection: ICrossHttpConnection;
    const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
    const ASuccess: Boolean) of object;

  /// <summary>
  ///   <para>
  ///     跨平台HTTP服务器接口
  ///   </para>
  ///   <para>
  ///     路由定义方式:
  ///   </para>
  ///   <para>
  ///     Route(AMehod, APath, ARouter)
  ///   </para>
  ///   <para>
  ///     Get(APath, ARouter)
  ///   </para>
  ///   <para>
  ///     Put(APath, ARouter)
  ///   </para>
  ///   <para>
  ///     Post(APath, ARouter)
  ///   </para>
  ///   <para>
  ///     Delete(APath, ARouter)
  ///   </para>
  ///   <para>
  ///     All(APath, ARouter)
  ///   </para>
  ///   <para>
  ///     其中AMehod和APath都支持正则表达式, ARouter可以是一个对象方法也可以是匿名函数
  ///   </para>
  /// </summary>
  /// <remarks>
  ///   <para>
  ///     这里偷了下懒, 没将HTTP和HTTPS分开实现两个不同的接口, 需要通过编译开关选择使用HTTP还是HTTP
  ///   </para>
  ///   <para>
  ///     通过接口引用计数保证连接的有效性，所以可以在路由函数中调用线程池来处理业务逻辑，而不用担心处理过程中连接对象被释放
  ///   </para>
  ///   <para>
  ///     每个请求的响应流程大致为：
  ///   </para>
  ///   <list type="number">
  ///     <item>
  ///       执行匹配的中间件;
  ///     </item>
  ///     <item>
  ///       执行匹配的路由
  ///     </item>
  ///   </list>
  /// </remarks>
  /// <example>
  ///   <code lang="Delphi">// 在线程池中处理业务逻辑
  /// FCrossHttpServer.Route('GET', '/runtask/:name',
  ///   procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
  ///   begin
  ///     System.Threading.TTask.Run(
  ///       procedure
  ///       begin
  ///         CallTask(ARequest.Params['name']);
  ///       end);
  ///   end);
  /// // 正则表达式
  /// FCrossHttpServer.Route('GET', '/query/:count(\d+)',
  ///   procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
  ///   begin
  ///     System.Threading.TTask.Run(
  ///       procedure
  ///       begin
  ///         CallQuery(ARequest.Params['count'].ToInteger);
  ///       end);
  ///   end);</code>
  /// </example>
  ICrossHttpServer = interface(ICrossServer)
  ['{224D16AA-317C-435E-9C2E-92868E578DB3}']
    function GetStoragePath: string;
    function GetAutoDeleteFiles: Boolean;
    function GetMaxHeaderSize: Int64;
    function GetMaxPostDataSize: Int64;
    function GetMaxCompressRatio: Integer;
    function GetCompressible: Boolean;
    function GetMinCompressSize: Int64;
    function GetSessions: ISessions;
    function GetSessionIDCookieName: string;
    function GetOnRequestBegin: TCrossHttpRequestBeginEvent;
    function GetOnRequest: TCrossHttpRequestEvent;
    function GetOnRequestEnd: TCrossHttpRequestEndEvent;
    function GetOnRequestException: TCrossHttpRequestExceptionEvent;

    procedure SetStoragePath(const Value: string);
    procedure SetAutoDeleteFiles(const Value: Boolean);
    procedure SetMaxHeaderSize(const Value: Int64);
    procedure SetMaxPostDataSize(const Value: Int64);
    procedure SetMaxCompressRatio(const Value: Integer);
    procedure SetCompressible(const Value: Boolean);
    procedure SetMinCompressSize(const Value: Int64);
    procedure SetSessions(const Value: ISessions);
    procedure SetSessionIDCookieName(const Value: string);
    procedure SetOnRequestBegin(const Value: TCrossHttpRequestBeginEvent);
    procedure SetOnRequest(const Value: TCrossHttpRequestEvent);
    procedure SetOnRequestEnd(const Value: TCrossHttpRequestEndEvent);
    procedure SetOnRequestException(const Value: TCrossHttpRequestExceptionEvent);

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareProc">
    ///   中间件处理匿名函数, 执行完处理函数之后, 如果AHandled=False则会继续执行后续匹配的中间件及路由,
    ///   否则后续匹配的中间件及路由不会被执行
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       中间件严格按照注册时的顺序被调用
    ///     </item>
    ///     <item>
    ///       中间件先于路由执行
    ///     </item>
    ///   </list>
    /// </remarks>
    function Use(const AMethod, APath: string;
      const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareMethod">
    ///   中间件处理匿名方法, 执行完处理方法之后, 如果AHandled=False则会继续执行后续匹配的中间件及路由,
    ///   否则后续匹配的中间件及路由不会被执行
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       中间件严格按照注册时的顺序被调用
    ///     </item>
    ///     <item>
    ///       中间件先于路由执行
    ///     </item>
    ///   </list>
    /// </remarks>
    function Use(const AMethod, APath: string;
      const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareProc">
    ///   中间件处理匿名函数, 执行完处理函数之后, 如果AHandled=False则会继续执行后续匹配的中间件及路由,
    ///   否则后续匹配的中间件及路由不会被执行
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       中间件严格按照注册时的顺序被调用
    ///     </item>
    ///     <item>
    ///       中间件先于路由执行
    ///     </item>
    ///   </list>
    /// </remarks>
    function Use(const APath: string;
      const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareMethod">
    ///   中间件处理匿名方法, 执行完处理方法之后, 如果AHandled=False则会继续执行后续匹配的中间件及路由,
    ///   否则后续匹配的中间件及路由不会被执行
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       中间件严格按照注册时的顺序被调用
    ///     </item>
    ///     <item>
    ///       中间件先于路由执行
    ///     </item>
    ///   </list>
    /// </remarks>
    function Use(const APath: string;
      const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="AMiddlewareProc">
    ///   中间件处理匿名函数, 执行完处理函数之后还会继续执行后续匹配的中间件及路由
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       中间件严格按照注册时的顺序被调用
    ///     </item>
    ///     <item>
    ///       中间件先于路由执行
    ///     </item>
    ///   </list>
    /// </remarks>
    function Use(const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="AMiddlewareMethod">
    ///   中间件处理方法, 执行完处理方法之后还会继续执行后续匹配的中间件及路由
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       中间件严格按照注册时的顺序被调用
    ///     </item>
    ///     <item>
    ///       中间件先于路由执行
    ///     </item>
    ///   </list>
    /// </remarks>
    function Use(const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册路由(请求处理函数)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式, GET/POST/PUT/DELETE等, 支持正则表达式, * 表示处理全部请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterProc">
    ///   路由处理匿名函数
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Route(const AMethod, APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册路由(请求处理函数)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式, GET/POST/PUT/DELETE等, 支持正则表达式, * 表示处理全部请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由处理方法
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Route(const AMethod, APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册GET路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterProc">
    ///   路由处理匿名函数
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Get(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册GET路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由处理方法
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Get(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册PUT路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterProc">
    ///   路由处理匿名函数
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Put(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册PUT路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由处理方法
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Put(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册POST路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterProc">
    ///   路由处理匿名函数
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Post(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册POST路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由处理方法
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Post(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册DELETE路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterProc">
    ///   路由处理匿名函数
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Delete(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册DELETE路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由处理方法
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function Delete(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册全部请求方式路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterProc">
    ///   路由处理匿名函数
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function All(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册全部请求方式路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由处理方法
    /// </param>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       路由严格按照注册时的顺序被调用, 所以如果在注册了AMethod=*,
    ///       APath=*的路由之后，再注册的其它路由将不会被调用. 所以强烈建议把 "* 路由" 放到最后注册.
    ///     </item>
    ///     <item>
    ///       路由中的正则表达式用法与node.js express相同
    ///     </item>
    ///   </list>
    /// </remarks>
    function All(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册静态文件路由
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="ALocalStaticDir">
    ///   静态文件目录, 该目录及子目录下的文件都将作为静态文件返回
    /// </param>
    function &Static(const APath, ALocalStaticDir: string): ICrossHttpServer;

    /// <summary>
    ///   注册文件列表路由
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="ALocalDir">
    ///   本地文件目录
    /// </param>
    function Dir(const APath, ALocalDir: string): ICrossHttpServer;

    /// <summary>
    ///   注册含有默认首页文件的静态文件路由
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="ALocalDir">
    ///   含有默认首页文件的本地目录
    /// </param>
    /// <param name="ADefIndexFiles">
    ///   默认的首页文件,按顺序选择,先找到哪个就使用哪个
    /// </param>
    function Index(const APath, ALocalDir: string; const ADefIndexFiles: TArray<string>): ICrossHttpServer;

    /// <summary>
    ///   删除指定路由
    /// </summary>
    function RemoveRouter(const AMethod, APath: string): ICrossHttpServer;

    /// <summary>
    ///   清除所有路由
    /// </summary>
    function ClearRouters: ICrossHttpServer;

    /// <summary>
    ///   删除指定中间件
    /// </summary>
    function RemoveMiddleware(const AMethod, APath: string): ICrossHttpServer;

    /// <summary>
    ///   清除所有中间件
    /// </summary>
    function ClearMiddlewares: ICrossHttpServer;

    /// <summary>
    ///   上传文件保存路径
    /// </summary>
    /// <remarks>
    ///   用于保存multipart/form-data上传的文件
    /// </remarks>
    property StoragePath: string read GetStoragePath write SetStoragePath;

    /// <summary>
    /// 对象释放时自动删除上传的文件
    /// </summary>
    property AutoDeleteFiles: Boolean read GetAutoDeleteFiles write SetAutoDeleteFiles;

    /// <summary>
    ///   最大允许HEADER的数据尺寸
    ///   <list type="bullet">
    ///     <item>
    ///       &gt; 0, 限制HEADER尺寸
    ///     </item>
    ///     <item>
    ///       &lt;= 0, 不限制
    ///     </item>
    ///   </list>
    /// </summary>
    property MaxHeaderSize: Int64 read GetMaxHeaderSize write SetMaxHeaderSize;

    /// <summary>
    ///   最大允许POST的数据尺寸
    ///   <list type="bullet">
    ///     <item>
    ///       &gt; 0, 限制上传数据尺寸
    ///     </item>
    ///     <item>
    ///       &lt;= 0, 不限制
    ///     </item>
    ///   </list>
    /// </summary>
    property MaxPostDataSize: Int64 read GetMaxPostDataSize write SetMaxPostDataSize;

    /// <summary>
    ///   gzip/deflate 解压时的最大压缩比 (DecodedSize / EncodedSize)
    ///   <list type="bullet">
    ///     <item>
    ///       &gt; 0, 解压输出与输入比超过该值则按 zip bomb 拒绝 (400)
    ///     </item>
    ///     <item>
    ///       = 0, 不做压缩比检查 (仅靠 MaxPostDataSize 拦截)
    ///     </item>
    ///   </list>
    /// </summary>
    /// <remarks>
    ///   合法 gzip 通常 1.5-15:1, 极规整数据 (StringOfChar, 大块重复字节) 可达 100-500:1
    ///   经典 zip bomb 1000:1 起 (42.zip ~100000:1), 默认 1000:1 兜底拦截 bomb
    /// </remarks>
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;

    /// <summary>
    ///   是否开启压缩
    /// </summary>
    /// <remarks>
    ///   开启压缩后, 发往客户端的数据将会进行压缩处理
    /// </remarks>
    property Compressible: Boolean read GetCompressible write SetCompressible;

    /// <summary>
    ///   最小允许压缩的数据尺寸
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       如果设置值大于0, 则只有Body数据尺寸大于等于该值才会进行压缩
    ///     </item>
    ///     <item>
    ///       如果设置值小于等于0, 则无视Body数据尺寸, 始终进行压缩
    ///     </item>
    ///     <item>
    ///       由于数据是分块压缩发送, 所以数据无论多大都不会占用更多的资源, 也就不需要限制最大压缩尺寸了
    ///     </item>
    ///     <item>
    ///       目前支持的压缩方式: gzip, deflate
    ///     </item>
    ///   </list>
    /// </remarks>
    property MinCompressSize: Int64 read GetMinCompressSize write SetMinCompressSize;

    /// <summary>
    ///   Sessions接口对象
    /// </summary>
    /// <remarks>
    ///   通过它管理所有Session, 如果不设置则Session功能将不会被启用
    /// </remarks>
    property Sessions: ISessions read GetSessions write SetSessions;

    /// <summary>
    ///   <para>
    ///     SessionID在Cookie中存储的名称
    ///   </para>
    /// </summary>
    /// <remarks>
    ///   如果设置为空, 则Session功能将不会被启用
    /// </remarks>
    property SessionIDCookieName: string read GetSessionIDCookieName write SetSessionIDCookieName;

    property OnRequestBegin: TCrossHttpRequestBeginEvent read GetOnRequestBegin write SetOnRequestBegin;
    property OnRequest: TCrossHttpRequestEvent read GetOnRequest write SetOnRequest;
    property OnRequestEnd: TCrossHttpRequestEndEvent read GetOnRequestEnd write SetOnRequestEnd;
    property OnRequestException: TCrossHttpRequestExceptionEvent read GetOnRequestException write SetOnRequestException;
  end;

  TCrossHttpConnection = class(TCrossServerConnection, ICrossHttpConnection)
  private
    FServer: TCrossHttpServer;
    FRequestObj: TCrossHttpRequest;
    FRequest: ICrossHttpRequest;
    FResponseObj: TCrossHttpResponse;
    FResponse: ICrossHttpResponse;
    FHttpParser: ICrossHttpParser;
    FPending: Integer;

    // pipelining 响应队列, 按请求解析顺序串行化响应发送
    FResponseQueue: TList<IHttpResponseQueueItem>;
    FResponseQueueLock: ILock;
    FSendingResponse: Boolean;

    {$region 'HttpParser事件'}
    // 以下事件都在 FHttpParser.Decode 中被触发
    // 而 FHttpParser.Decode 在 ParseRecvData 中被调用
    // ParseRecvData 在 FServer.LogicReceived 中被调用
    // FServer.LogicReceived 被 TCrossConnectionBase._LockRecv 保护
    // 所以无需担心以下事件的多线程安全问题
    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValues: TArray<string>): Boolean;
    procedure _OnBodyBegin;
    procedure _OnBodyData(const ADataPtr: Pointer; const ADataSize: Integer);
    procedure _OnBodyEnd;
    procedure _OnParseBegin;
    procedure _OnParseSuccess;
    procedure _OnParseFailed(const ACode: Integer; const AError: string);
    {$endregion}

    // 响应队列内部方法
    procedure _QueueResponseReady(const AItem: IHttpResponseQueueItem;
      const ASource: TCrossHttpChunkDataFunc;
      const ACallback: TCrossConnectionCallback);
    procedure _SendQueueItem(const AItem: IHttpResponseQueueItem);
    procedure _FinishQueueItem(const AItem: IHttpResponseQueueItem; const ASuccess: Boolean);

    // 调用前必须已持有 FResponseQueueLock; 若可发送则取出队首 ready item
    // 并设置 FSendingResponse / item.Sending, 否则返回 nil
    function _TryDequeueReadyLocked: IHttpResponseQueueItem;

    // 调用前必须已持有 FResponseQueueLock; 清空队列, 同时主动断开每个 item
    // 内对 request/response/source/callback 的接口引用, 避免与 response.FQueueItem
    // 等形成的循环引用导致 item 永不释放
    procedure _ClearResponseQueueLocked;
  protected
    function GetRequest: ICrossHttpRequest;
    function GetResponse: ICrossHttpResponse;
    function GetServer: ICrossHttpServer;
    function GetPending: Integer;

    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer); virtual;

    procedure ReleaseRequest; virtual;
    procedure ReleaseResponse; virtual;

    // socket 关闭时主动打破 connection 与 request/response 之间的循环引用,
    // 并清空响应队列, 避免连接关闭后 connection 因循环引用永不释放导致内存泄漏
    procedure InternalClose; override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

    property Request: ICrossHttpRequest read GetRequest;
    property Response: ICrossHttpResponse read GetResponse;
    property Server: ICrossHttpServer read GetServer;
    property Pending: Integer read GetPending;
  end;

  TCrossHttpRequest = class(TInterfacedObject, ICrossHttpRequest)
  private
    FRawRequestText: string;
    FMethod, FPath, FQueryText, FPathAndQuery, FVersion: string;
    FRawPath, FRawQueryText, FRawPathAndQuery: string;
    FHttpVerNum: Integer;
    FKeepAlive: Boolean;
    FAccept: string;
    FReferer: string;
    FAcceptLanguage: string;
    FAcceptEncoding: string;
    FUserAgent: string;
    FIfModifiedSince: TDateTime;
    FIfNoneMatch: string;
    FRange: string;
    FIfRange: string;
    FAuthorization: string;
    FXForwardedFor: string;
    FContentLength: Int64;
    FHostName: string;
    FHostPort: Word;

    FPostDataSize: Int64;

    FRequestCmdLine: string;
    FContentType: string;
    FRequestBoundary: string;
    FTransferEncoding: string;
    FContentEncoding: string;
    FRequestCookies: string;
    FRequestHost: string;
    FRequestConnection: string;

    FConnectionObj: TCrossHttpConnection;
    FConnection: ICrossHttpConnection;
    FServer: TCrossHttpServer;
    FHeader: THttpHeader;
    FCookies: TRequestCookies;
    FSession: ISession;
    FParams: THttpUrlParams;
    FQuery: THttpUrlParams;
    FBody: TObject;
    FRawBody: TMemoryStream;
    FBodyType: TBodyType;
    FIsChunked: Boolean;
  private
    function CalcIsChunked: Boolean; inline;
  protected
    function GetConnection: ICrossHttpConnection;
    function GetRawRequestText: string;
    function GetRawPathAndQuery: string;
    function GetMethod: string;
    function GetPath: string;
    function GetPathAndQuery: string;
    function GetVersion: string;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
    function GetSession: ISession;
    function GetParams: THttpUrlParams;
    function GetQueryText: string;
    function GetQuery: THttpUrlParams;
    function GetBody: TObject;
    function GetRawBody: TStream;
    function GetBodyType: TBodyType;
    function GetKeepAlive: Boolean;
    function GetAccept: string;
    function GetAcceptEncoding: string;
    function GetAcceptLanguage: string;
    function GetReferer: string;
    function GetUserAgent: string;
    function GetIfModifiedSince: TDateTime;
    function GetIfNoneMatch: string;
    function GetRange: string;
    function GetIfRange: string;
    function GetAuthorization: string;
    function GetXForwardedFor: string;
    function GetContentLength: Int64;
    function GetHostName: string;
    function GetHostPort: Word;
    function GetContentType: string;
    function GetContentEncoding: string;
    function GetRequestBoundary: string;
    function GetRequestCmdLine: string;
    function GetRequestConnection: string;
    function GetTransferEncoding: string;
    function GetIsChunked: Boolean;
    function GetIsMultiPartFormData: Boolean;
    function GetIsUrlEncodedFormData: Boolean;
    function GetPostDataSize: Int64;

    function ParseHeader(const ADataPtr: Pointer; const ADataSize: Integer): Boolean;
  public
    constructor Create(const AConnection: TCrossHttpConnection);
    destructor Destroy; override;

    property Connection: ICrossHttpConnection read GetConnection;
    property RawRequestText: string read GetRawRequestText;
    property RawPathAndParams: string read GetRawPathAndQuery;
    property Method: string read GetMethod;
    property Path: string read GetPath;
    property PathAndQuery: string read GetPathAndQuery;
    property Version: string read GetVersion;
    property Header: THttpHeader read GetHeader;
    property Cookies: TRequestCookies read GetCookies;
    property Session: ISession read GetSession;
    property Params: THttpUrlParams read GetParams;
    property Query: THttpUrlParams read GetQuery;
    property QueryText: string read GetQueryText;
    property Body: TObject read GetBody;
    property RawBody: TStream read GetRawBody;
    property BodyType: TBodyType read GetBodyType;
    property KeepAlive: Boolean read GetKeepAlive;
    property Accept: string read GetAccept;
    property AcceptEncoding: string read GetAcceptEncoding;
    property AcceptLanguage: string read GetAcceptLanguage;
    property Referer: string read GetReferer;
    property UserAgent: string read GetUserAgent;
    property IfModifiedSince: TDateTime read GetIfModifiedSince;
    property IfNoneMatch: string read GetIfNoneMatch;
    property Range: string read GetRange;
    property IfRange: string read GetIfRange;
    property Authorization: string read GetAuthorization;
    property XForwardedFor: string read GetXForwardedFor;
    property ContentLength: Int64 read GetContentLength;
    property HostName: string read GetHostName;
    property HostPort: Word read GetHostPort;
    property ContentType: string read GetContentType;

    property RequestCmdLine: string read GetRequestCmdLine;

    property RequestBoundary: string read GetRequestBoundary;
    property TransferEncoding: string read GetTransferEncoding;
    property ContentEncoding: string read GetContentEncoding;
    property RequestConnection: string read GetRequestConnection;
    property IsChunked: Boolean read GetIsChunked;
    property IsMultiPartFormData: Boolean read GetIsMultiPartFormData;
    property IsUrlEncodedFormData: Boolean read GetIsUrlEncodedFormData;
    property PostDataSize: Int64 read GetPostDataSize;
  end;

  TCrossHttpResponse = class(TInterfacedObject, ICrossHttpResponse)
  public const
    SND_BUF_SIZE = TCrossConnection.SND_BUF_SIZE;
  private
    FConnectionObj: TCrossHttpConnection;
    FConnection: ICrossHttpConnection;
    FRequest: ICrossHttpRequest;
    FStatusCode: Integer;
    FStatusText: string;
    FHeader: THttpHeader;
    FCookies: TResponseCookies;
    FSendStatus: Integer;
    FQueueItem: IHttpResponseQueueItem;

    procedure Reset;
    function _CreateHeader(const ABodySize: Int64; AChunked: Boolean): TBytes;

    {$region '内部: 基础发送方法'}
    procedure _Send(const ASource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure _Send(const AHeaderSource, ABodySource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;
    {$endregion}

    function _CheckCompress(const ABodySize: Int64; out ACompressType: TCompressType): Boolean;

    // TCustomMemoryStream 优化: 直接获取内存指针, 避免逐块读流
    function _GetMemoryStreamPointer(const AStream: TStream;
      const AOffset, ACount: Int64; out P: PByte; out LSize: Int64): Boolean; inline;

    {$region '压缩发送'}
    procedure SendZCompress(const AChunkSource: TCrossHttpChunkDataFunc; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: Pointer; const ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody; const ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendZCompress(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: TBytes; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendZCompress(const ABody: TStream; const AOffset, ACount: Int64; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: TStream; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendZCompress(const ABody: string; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    {$endregion}

    {$region '不压缩发送'}
    procedure SendNoCompress(const AChunkSource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: Pointer; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendNoCompress(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: TBytes; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendNoCompress(const ABody: TStream; const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: TStream; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendNoCompress(const ABody: string; const ACallback: TCrossConnectionCallback = nil); overload;
    {$endregion}

    {$region '常规方法'}
    procedure Send(const ABody: Pointer; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure Send(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody: TBytes; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure Send(const ABody: TStream; const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody: TStream; const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure Send(const ABody: string; const ACallback: TCrossConnectionCallback = nil); overload;

    procedure Json(const AJson: string; const ACallback: TCrossConnectionCallback = nil);

    procedure SendFile(const AFileName: string; const ACallback: TCrossConnectionCallback = nil);
    procedure Download(const AFileName: string; const ACallback: TCrossConnectionCallback = nil);
    procedure SendStatus(const AStatusCode: Integer; const ADescription: string;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendStatus(const AStatusCode: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Redirect(const AUrl: string; const ACallback: TCrossConnectionCallback = nil);
    procedure Attachment(const AFileName: string);
    {$endregion}
  protected
    function GetConnection: ICrossHttpConnection;
    function GetRequest: ICrossHttpRequest;
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetContentType: string;
    function GetLocation: string;
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetSent: Boolean;

    procedure SetContentType(const Value: string);
    procedure SetLocation(const Value: string);
    procedure SetStatusCode(Value: Integer);
    procedure SetStatusText(const Value: string);
  public
    constructor Create(const AConnection: TCrossHttpConnection;
      const ARequest: ICrossHttpRequest;
      const AQueueItem: IHttpResponseQueueItem);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   路由参数定义
  /// </summary>
  TRouteParam = record
    Name: string;     // 参数名
    Pattern: string;  // 正则模式
  end;

  /// <summary>
  ///   路由类型
  /// </summary>
  TRouteType = (
    /// <summary>
    ///   静态路由
    /// </summary>
    rtStatic,

    /// <summary>
    ///   正则路由
    ///   例如: /users/:id, /users/:id/echo, /users/:id(\d+)
    /// </summary>
    rtRegex,

    /// <summary>
    ///   通配符路由
    ///   例如: /files/*, 其中*就是通配符节点, 通配符节点只能出现在路径最后一段
    /// </summary>
    rtWildcard
  );

  /// <summary>
  ///   路由接口
  /// </summary>
  IRouter = interface
  ['{5A7E2B1C-8D3F-4E69-A0C5-2F1B8E6D4A93}']
    function GetRouteType: TRouteType;
    function GetMethodPattern: string;
    function GetRegEx: IRegEx;

    procedure AddRouterProc(const ARouterProc: TCrossHttpRouterProc); overload;
    procedure AddRouterProc(const ARouterMethod: TCrossHttpRouterMethod); overload;

    procedure Execute(const ARequest: ICrossHttpRequest;
      const AResponse: ICrossHttpResponse; var AHandled: Boolean);

    property RouteType: TRouteType read GetRouteType;
    property MethodPattern: string read GetMethodPattern;
    property RegEx: IRegEx read GetRegEx;
  end;

  /// <summary>
  ///   路由
  /// </summary>
  TRouter = class(TInterfacedObject, IRouter)
  private
    // 路由类型
    FRouteType: TRouteType;
    // 方法模式(如 "GET", "GET|POST", "*" 等)
    FMethodPattern: string;
    FLock: IReadWriteLock;

    // 路由处理函数
    FRouterProcList: TList<TCrossHttpRouterProc>;
    FRouterMethodList: TList<TCrossHttpRouterMethod>;

    function GetRouteType: TRouteType;
    function GetMethodPattern: string;
    function GetRegEx: IRegEx;
  public
    constructor Create(const AMethodPattern: string);
    destructor Destroy; override;

    procedure AddRouterProc(const ARouterProc: TCrossHttpRouterProc); overload;
    procedure AddRouterProc(const ARouterMethod: TCrossHttpRouterMethod); overload;

    procedure Execute(const ARequest: ICrossHttpRequest;
      const AResponse: ICrossHttpResponse; var AHandled: Boolean);
  end;

  /// <summary>
  ///   路由段
  /// </summary>
  TRouteSegment = class
  private
    FOriginal: string;              // 原始段
    FPattern: string;               // 完整模式
    FParams: TArray<TRouteParam>;   // 参数定义数组
    FRouteType: TRouteType;         // 路由类型
  public
    constructor Create(const AOriginal, APattern: string;
      const AParams: TArray<TRouteParam>; ARouteType: TRouteType);

    // 正则匹配
    // 只有正则匹配的路由才需要处理参数
    function RegexMatch(const ASegment: string; const ARequest: ICrossHttpRequest): Boolean;

    property Original: string read FOriginal;
    property Pattern: string read FPattern;
    property Params: TArray<TRouteParam> read FParams;
    property RouteType: TRouteType read FRouteType;
  end;

  /// <summary>
  ///   路由节点
  /// </summary>
  TRouteNode = class
  private
    FRouteType: TRouteType;  // 路由类型
    FSegment: TRouteSegment; // 路由段

    FStaticChildren: TObjectDictionary<string, TRouteNode>; // 静态子节点
    FRegexChildren: TObjectList<TRouteNode>;                // 正则子节点
    FWildcardChild: TRouteNode;                             // 通配符子节点

    FStaticRouteMethodItems: TDictionary<string, IRouter>; // 静态方法路由项列表
    FRegexRouteMethodItems: TList<IRouter>;                // 正则方法路由项列表
    FWildcardRouteMethodItem: IRouter;                           // 通配符路由项

    function GetChildNode(const ASegment: string; const ARouteType: TRouteType; out ARouteNode: TRouteNode): Boolean;
    function CreateChildNode(const ASegment: TRouteSegment): TRouteNode;
  public
    constructor Create(ARouteType: TRouteType; const ASegment: TRouteSegment);
    destructor Destroy; override;

    // 注意: 添加和删除是使用的模式字符串(比如 GET POST GET|POST)
    procedure AddRouter(const AMethodPattern: string; const ARouter: IRouter);
    function GetRouter(const AMethodPattern: string; out ARouter: IRouter): Boolean;
    function RemoveRouter(const AMethodPattern: string): Boolean;

    // 注意: 查找使用的是确定的请求方法(比如 GET POST)
    function MatchRouter(const AMethod: string; out ARouter: IRouter): Boolean;
    function IsEmpty: Boolean;

    property RouteType: TRouteType read FRouteType;
    property Segment: TRouteSegment read FSegment;
    property StaticChildren: TObjectDictionary<string, TRouteNode> read FStaticChildren;
    property RegexChildren: TObjectList<TRouteNode> read FRegexChildren;
    property WildcardChild: TRouteNode read FWildcardChild;
  end;

  /// <summary>
  ///   路由树
  /// </summary>
  TCrossHttpRouterTree = class
  private
    FRoot: TRouteNode;
    FLock: IReadWriteLock;

    function CreateSegment(const ASegment: string; const ARouteType: TRouteType): TRouteSegment;

    // 注意: 添加和删除是使用的模式字符串(比如 GET POST GET|POST, /user/:id)
    procedure AddRouterToNode(ANode: TRouteNode; const APathPatternSegments: TArray<string>;
      AIndex: Integer; const AMethodPattern: string; const ARouter: IRouter);
    function GetRouterFromNode(ANode: TRouteNode; const APathPatternSegments: TArray<string>;
      AIndex: Integer; const AMethodPattern: string; out ARouter: IRouter): Boolean;
    function RemoveRouterFromNode(ANode: TRouteNode; const APathPatternSegments: TArray<string>;
      AIndex: Integer; const AMethodPattern: string): Boolean;

    function GetWildcardValue(const APathSegments: TArray<string>;
      AIndex: Integer; const AQueryText: string): string;
    // 注意: 查找使用的是确定的请求方法和路径(比如 GET POST, /user/123)
    function MatchRouterInNode(ANode: TRouteNode; const APathSegments: TArray<string>;
      AIndex: Integer; const AMethod: string; const ARequest: ICrossHttpRequest;
      out ARouter: IRouter): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // 将请求路径分段
    class function ParsePath(const APath: string): TArray<string>; static;

    // 注意: 添加和删除是使用的模式字符串(比如 GET POST GET|POST, /user/:id)
    procedure AddRouter(const AMethodPattern, APathPattern: string; const ARouter: IRouter); overload;
    function GetRouter(const AMethodPattern, APathPattern: string; out ARouter: IRouter): Boolean; overload;
    function GetRouter(const AMethodPattern, APathPattern: string): IRouter; overload;

    procedure AddRouter(const AMethodPattern, APathPattern: string; const ARouterProc: TCrossHttpRouterProc); overload;
    procedure AddRouter(const AMethodPattern, APathPattern: string; const ARouterMethod: TCrossHttpRouterMethod); overload;

    procedure RemoveRouter(const AMethodPattern, APathPattern: string);

    // 注意: 查找与请求匹配的路由
    function MatchRouter(const APathSegments: TArray<string>; const ARequest: ICrossHttpRequest; out ARouter: IRouter): Boolean; overload;
    function MatchRouter(const ARequest: ICrossHttpRequest; out ARouter: IRouter): Boolean; overload;
    procedure Clear;
  end;

  TCrossHttpServer = class(TCrossServer, ICrossHttpServer)
  private const
    SESSIONID_COOKIE_NAME = 'cross_sessionid';
  private
    FStoragePath: string;
    FAutoDeleteFiles: Boolean;
    FMaxPostDataSize: Int64;
    FMaxHeaderSize: Int64;
    FMaxCompressRatio: Integer;
    FMinCompressSize: Int64;
    FSessionIDCookieName: string;

    FRouters: TCrossHttpRouterTree;
    FMiddlewares: TCrossHttpRouterTree;

    FSessions: ISessions;
    FOnRequestBegin: TCrossHttpRequestBeginEvent;
    FOnRequestEnd: TCrossHttpRequestEndEvent;
    FOnRequest: TCrossHttpRequestEvent;
    FOnRequestException: TCrossHttpRequestExceptionEvent;
    FCompressible: Boolean;
  protected
    function GetStoragePath: string;
    function GetAutoDeleteFiles: Boolean;
    function GetMaxHeaderSize: Int64;
    function GetMaxPostDataSize: Int64;
    function GetMaxCompressRatio: Integer;
    function GetCompressible: Boolean;
    function GetMinCompressSize: Int64;
    function GetSessions: ISessions;
    function GetSessionIDCookieName: string;
    function GetOnRequest: TCrossHttpRequestEvent;
    function GetOnRequestEnd: TCrossHttpRequestEndEvent;
    function GetOnRequestBegin: TCrossHttpRequestBeginEvent;
    function GetOnRequestException: TCrossHttpRequestExceptionEvent;

    procedure SetStoragePath(const Value: string);
    procedure SetAutoDeleteFiles(const Value: Boolean);
    procedure SetMaxHeaderSize(const Value: Int64);
    procedure SetMaxPostDataSize(const Value: Int64);
    procedure SetMaxCompressRatio(const Value: Integer);
    procedure SetCompressible(const Value: Boolean);
    procedure SetMinCompressSize(const Value: Int64);
    procedure SetSessions(const Value: ISessions);
    procedure SetSessionIDCookieName(const Value: string);
    procedure SetOnRequest(const Value: TCrossHttpRequestEvent);
    procedure SetOnRequestBegin(const Value: TCrossHttpRequestBeginEvent);
    procedure SetOnRequestEnd(const Value: TCrossHttpRequestEndEvent);
    procedure SetOnRequestException(const Value: TCrossHttpRequestExceptionEvent);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;

    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;
  protected
    // 处理请求前
    // 显式传入 ARequest/AResponse, 避免在 pipelining 场景下从 connection 字段读取产生 race
    procedure DoOnRequestBegin(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse); virtual;

    // 处理请求
    procedure DoOnRequest(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse); virtual;

    // 处理请求后
    procedure DoOnRequestEnd(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
      const ASuccess: Boolean); virtual;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    function Use(const AMethod, APath: string;
      const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Use(const AMethod, APath: string;
      const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Use(const APath: string;
      const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Use(const APath: string;
      const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Use(const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Use(const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Route(const AMethod, APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Route(const AMethod, APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Get(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Get(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Put(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Put(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Post(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Post(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Delete(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Delete(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function All(const APath: string; const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function All(const APath: string; const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function &Static(const APath, ALocalStaticDir: string): ICrossHttpServer;
    function Dir(const APath, ALocalDir: string): ICrossHttpServer;
    function Index(const APath, ALocalDir: string; const ADefIndexFiles: TArray<string>): ICrossHttpServer;

    function RemoveRouter(const AMethod, APath: string): ICrossHttpServer;
    function ClearRouters: ICrossHttpServer;

    function RemoveMiddleware(const AMethod, APath: string): ICrossHttpServer;
    function ClearMiddlewares: ICrossHttpServer;

    property StoragePath: string read GetStoragePath write SetStoragePath;
    property AutoDeleteFiles: Boolean read GetAutoDeleteFiles write SetAutoDeleteFiles;
    property MaxHeaderSize: Int64 read GetMaxHeaderSize write SetMaxHeaderSize;
    property MaxPostDataSize: Int64 read GetMaxPostDataSize write SetMaxPostDataSize;
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;
    property Compressible: Boolean read GetCompressible write SetCompressible;
    property MinCompressSize: Int64 read GetMinCompressSize write SetMinCompressSize;
    property Sessions: ISessions read GetSessions write SetSessions;
    property SessionIDCookieName: string read GetSessionIDCookieName write SetSessionIDCookieName;

    property OnRequestBegin: TCrossHttpRequestBeginEvent read GetOnRequestBegin write SetOnRequestBegin;
    property OnRequest: TCrossHttpRequestEvent read GetOnRequest write SetOnRequest;
    property OnRequestEnd: TCrossHttpRequestEndEvent read GetOnRequestEnd write SetOnRequestEnd;
    property OnRequestException: TCrossHttpRequestExceptionEvent read GetOnRequestException write SetOnRequestException;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  Utils.Utils,
  Net.CrossHttpRouter;

const
  // HTTP/1.1 100 Continue 临时响应，用于 Expect: 100-continue 流程
  CResponse100Continue: AnsiString = 'HTTP/1.1 100 Continue'#13#10#13#10;


{ ECrossHttpException }

constructor ECrossHttpException.Create(const AMessage: string;
  AStatusCode: Integer);
begin
  inherited Create(AMessage);
  FStatusCode := AStatusCode;
end;

constructor ECrossHttpException.CreateFmt(const AMessage: string;
  const AArgs: array of const; AStatusCode: Integer);
begin
  inherited CreateFmt(AMessage, AArgs);
  FStatusCode := AStatusCode;
end;

{ THttpResponseQueueItem }

function THttpResponseQueueItem.GetRequest: ICrossHttpRequest;
begin
  Result := FRequest;
end;

function THttpResponseQueueItem.GetResponse: ICrossHttpResponse;
begin
  Result := FResponse;
end;

function THttpResponseQueueItem.GetSource: TCrossHttpChunkDataFunc;
begin
  Result := FSource;
end;

function THttpResponseQueueItem.GetCallback: TCrossConnectionCallback;
begin
  Result := FCallback;
end;

function THttpResponseQueueItem.GetReady: Boolean;
begin
  Result := FReady;
end;

function THttpResponseQueueItem.GetSending: Boolean;
begin
  Result := FSending;
end;

function THttpResponseQueueItem.GetCompleted: Boolean;
begin
  Result := FCompleted;
end;

function THttpResponseQueueItem.GetKeepAlive: Boolean;
begin
  Result := FKeepAlive;
end;

function THttpResponseQueueItem.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

procedure THttpResponseQueueItem.SetRequest(const AValue: ICrossHttpRequest);
begin
  FRequest := AValue;
end;

procedure THttpResponseQueueItem.SetResponse(const AValue: ICrossHttpResponse);
begin
  FResponse := AValue;
end;

procedure THttpResponseQueueItem.SetSource(const AValue: TCrossHttpChunkDataFunc);
begin
  FSource := AValue;
end;

procedure THttpResponseQueueItem.SetCallback(const AValue: TCrossConnectionCallback);
begin
  FCallback := AValue;
end;

procedure THttpResponseQueueItem.SetReady(const AValue: Boolean);
begin
  FReady := AValue;
end;

procedure THttpResponseQueueItem.SetSending(const AValue: Boolean);
begin
  FSending := AValue;
end;

procedure THttpResponseQueueItem.SetCompleted(const AValue: Boolean);
begin
  FCompleted := AValue;
end;

procedure THttpResponseQueueItem.SetKeepAlive(const AValue: Boolean);
begin
  FKeepAlive := AValue;
end;

procedure THttpResponseQueueItem.SetStatusCode(const AValue: Integer);
begin
  FStatusCode := AValue;
end;

{ TCrossHttpConnection }

constructor TCrossHttpConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);

  FServer := AOwner as TCrossHttpServer;

  FResponseQueue := TList<IHttpResponseQueueItem>.Create;
  FResponseQueueLock := TLock.Create;

  FHttpParser := TCrossHttpParser.Create(pmServer);
  FHttpParser.MaxHeaderSize := FServer.MaxHeaderSize;
  FHttpParser.MaxBodyDataSize := FServer.MaxPostDataSize;
  FHttpParser.MaxCompressRatio := FServer.MaxCompressRatio;
  FHttpParser.OnHeaderData := _OnHeaderData;
  FHttpParser.OnGetHeaderValue := _OnGetHeaderValue;
  FHttpParser.OnBodyBegin := _OnBodyBegin;
  FHttpParser.OnBodyData := _OnBodyData;
  FHttpParser.OnBodyEnd := _OnBodyEnd;
  FHttpParser.OnParseBegin := _OnParseBegin;
  FHttpParser.OnParseSuccess := _OnParseSuccess;
  FHttpParser.OnParseFailed := _OnParseFailed;
end;

destructor TCrossHttpConnection.Destroy;
begin
  if (FRequest <> nil) then
    (FRequest as TCrossHttpRequest).FConnection := nil;

  if (FResponse <> nil) then
    (FResponse as TCrossHttpResponse).FConnection := nil;

  ReleaseRequest;
  ReleaseResponse;

  // 队列清理由 InternalClose 负责 (包括 _ClearResponseQueueLocked 触发 callbacks),
  // 此处仅做 defensive 的 FreeAndNil, 避免重复清理
  FreeAndNil(FResponseQueue);
  FResponseQueueLock := nil;

  FHttpParser := nil;

  inherited;
end;

function TCrossHttpConnection.GetRequest: ICrossHttpRequest;
begin
  Result := FRequest;
end;

function TCrossHttpConnection.GetResponse: ICrossHttpResponse;
begin
  Result := FResponse;
end;

function TCrossHttpConnection.GetServer: ICrossHttpServer;
begin
  Result := Owner as ICrossHttpServer;
end;

function TCrossHttpConnection.GetPending: Integer;
begin
  // 读取在多 IO 线程间发生, 与 _OnParseBegin 的 AtomicIncrement /
  // _FinishQueueItem 的 AtomicDecrement 保持原子语义
  Result := AtomicCmpExchange(FPending, 0, 0);
end;

procedure TCrossHttpConnection.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
begin
  if (FHttpParser <> nil) then
    FHttpParser.Decode(ABuf, ALen)
  else
    ALen := 0;
end;

procedure TCrossHttpConnection.ReleaseRequest;
begin
  FRequestObj := nil;
  FRequest := nil;
end;

procedure TCrossHttpConnection.ReleaseResponse;
begin
  FResponseObj := nil;
  FResponse := nil;
end;

procedure TCrossHttpConnection.InternalClose;
begin
  // 必须在 socket 关闭时主动断开连接级 FRequest/FResponse 与 request.FConnection /
  // response.FConnection 之间的循环引用. 否则 connection.FRequest 持有 request, 而
  // request.FConnection 又持有 connection, refcount 永不归零, 不仅 connection 不会
  // 销毁, 队列内 item / request body / response header 等也全部泄漏.
  if (FRequest <> nil) then
    (FRequest as TCrossHttpRequest).FConnection := nil;
  if (FResponse <> nil) then
    (FResponse as TCrossHttpResponse).FConnection := nil;
  ReleaseRequest;
  ReleaseResponse;

  // 清空响应队列中剩余 items: 它们持有的 request/response/source/callback 接口字段
  // 与 response.FQueueItem 形成循环引用. 必须先逐个清空 item 内的接口字段,
  // 再 Clear 队列, 否则 items 引用计数减 1 之后仍因循环引用而不会归零, 导致泄漏
  if (FResponseQueueLock <> nil) and (FResponseQueue <> nil) then
  begin
    FResponseQueueLock.Enter;
    try
      FSendingResponse := False;
      _ClearResponseQueueLocked;
    finally
      FResponseQueueLock.Leave;
    end;
  end;

  inherited InternalClose;
end;

function TCrossHttpConnection._TryDequeueReadyLocked: IHttpResponseQueueItem;
begin
  Result := nil;

  if FSendingResponse then Exit;
  if (FResponseQueue = nil) or (FResponseQueue.Count = 0) then Exit;
  if not FResponseQueue[0].Ready then Exit;

  // 从队列中移除队首, 由调用方的局部接口引用保活后续发送过程
  Result := FResponseQueue[0];
  FResponseQueue.Delete(0);
  FSendingResponse := True;
  Result.Sending := True;
end;

// _ClearResponseQueueLocked:
//   调用前必须持有 FResponseQueueLock.
//   按队列注册顺序 (FIFO) 收集所有 callback, 清空队列并逐个清空 item 内部接口引用,
//   锁外按收集顺序触发 callback(False) 通知业务方发送失败.
//   注意: callback 中不应操作连接状态 (如 Disconnect), 因为此时连接正在关闭流程中.
procedure TCrossHttpConnection._ClearResponseQueueLocked;
var
  I: Integer;
  LItem: IHttpResponseQueueItem;
  LCallbacks: TArray<TCrossConnectionCallback>;
begin
  if (FResponseQueue = nil) then Exit;

  // 收集所有待通知 callback (在本方法尾部、队列清空后触发),
  // 避免静默丢弃导致业务方 hang 等通知.
  SetLength(LCallbacks, FResponseQueue.Count);
  for I := 0 to FResponseQueue.Count - 1 do
  begin
    LItem := FResponseQueue[I];
    if (LItem <> nil) then
    begin
      LCallbacks[I] := LItem.Callback;
      LItem.Request := nil;
      LItem.Response := nil;
      LItem.Source := nil;
      LItem.Callback := nil;
    end;
  end;

  FResponseQueue.Clear;

  // 触发所有被丢弃的 callback (通知失败)
  for I := 0 to High(LCallbacks) do
    if Assigned(LCallbacks[I]) then
      LCallbacks[I](Self, False);
end;

procedure TCrossHttpConnection._QueueResponseReady(
  const AItem: IHttpResponseQueueItem;
  const ASource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossConnectionCallback);
var
  LAlreadyReadyOrCompleted: Boolean;
  LItemToSend: IHttpResponseQueueItem;
begin
  if (AItem = nil) then
  begin
    if Assigned(ACallback) then
      ACallback(Self, False);
    Exit;
  end;

  LAlreadyReadyOrCompleted := False;
  LItemToSend := nil;

  // 单次锁块完成 "标记 ready" 与 "尝试 take 队首" 两件事
  // 减少 happy path 上的锁/解锁次数, 降低高并发竞争开销
  FResponseQueueLock.Enter;
  try
    if AItem.Ready or AItem.Completed then
    begin
      // 同一个 item 不允许重复 ready, 不修改原有 Source/Callback
      LAlreadyReadyOrCompleted := True;
    end else
    begin
      AItem.Source := ASource;
      AItem.Callback := ACallback;
      AItem.KeepAlive := AItem.Request.KeepAlive;
      AItem.StatusCode := AItem.Response.StatusCode;
      AItem.Ready := True;

      // 没有正在发送时, 立即尝试取队首 ready item
      LItemToSend := _TryDequeueReadyLocked;
    end;
  finally
    FResponseQueueLock.Leave;
  end;

  if LAlreadyReadyOrCompleted then
  begin
    // 安全降级: 对重复传入的 callback 触发失败, 避免调用方静默挂起
    if Assigned(ACallback) then
      ACallback(Self, False);
    Exit;
  end;

  if (LItemToSend <> nil) then
    _SendQueueItem(LItemToSend);
end;

procedure TCrossHttpConnection._SendQueueItem(const AItem: IHttpResponseQueueItem);
var
  LConnection: ICrossHttpConnection;
  LSender: TCrossConnectionCallback;
begin
  LConnection := Self;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
      LSource: TCrossHttpChunkDataFunc;
    begin
      if not ASuccess then
      begin
        _FinishQueueItem(AItem, False);
        LConnection := nil;
        LSender := nil;
        Exit;
      end;

      LSource := AItem.Source;
      LData := nil;
      LCount := 0;
      if not Assigned(LSource)
        or not LSource(@LData, @LCount)
        or (LData = nil)
        or (LCount <= 0) then
      begin
        // StatusCode>=500 表示压缩/发送过程中发生了不可恢复的错误
        _FinishQueueItem(AItem, AItem.StatusCode < 500);
        LConnection := nil;
        LSender := nil;
        Exit;
      end;

      AConnection.SendBuf(LData^, LCount, LSender);
    end;

  LSender(LConnection, True);
end;

procedure TCrossHttpConnection._FinishQueueItem(
  const AItem: IHttpResponseQueueItem; const ASuccess: Boolean);
var
  LRequest: ICrossHttpRequest;
  LResponse: ICrossHttpResponse;
  LCallback: TCrossConnectionCallback;
  LNeedDisconnect, LDoEnd: Boolean;
  LItemNext: IHttpResponseQueueItem;
begin
  LDoEnd := False;
  LNeedDisconnect := False;
  LRequest := nil;
  LResponse := nil;
  LCallback := nil;
  LItemNext := nil;

  // 单次锁块完成 "标记 completed + 释放 sending 标志 + 尝试 take 下一个 ready item"
  // 三件事, 锁外再触发下一个 item 的发送, 避免两次进出锁的开销
  FResponseQueueLock.Enter;
  try
    // 先复位 FSendingResponse, 确保无论 AItem 是否已经 Completed 都不会挂起后续响应
    FSendingResponse := False;
    if not AItem.Completed then
    begin
      LRequest := AItem.Request;
      LResponse := AItem.Response;
      LCallback := AItem.Callback;
      LNeedDisconnect := ASuccess and ((not AItem.KeepAlive) or (AItem.StatusCode >= 500));

      AItem.Completed := True;
      LDoEnd := True;

      // 关键: 立即清空 item 对外部对象的接口引用, 打破循环引用导致的内存泄漏:
      //   response.FQueueItem -> item.FResponse -> response  (双向接口循环)
      //   item.FSource -> 匿名方法 (captured Self=response) -> response  (隐式循环)
      // 不在此处释放, 这些引用要等到 connection 释放才能解开, 而 connection
      // 又被 request.FConnection / response.FConnection 持有, 形成多重循环
      AItem.Request := nil;
      AItem.Response := nil;
      AItem.Source := nil;
      AItem.Callback := nil;

      // 仅在 happy path 下提前 take 下一个 item; 失败/disconnect 路径不取,
      // 让 connection 关闭流程清理剩余 queue
      if ASuccess and (not LNeedDisconnect) then
        LItemNext := _TryDequeueReadyLocked;
    end;
  finally
    FResponseQueueLock.Leave;
  end;

  if LDoEnd then
  begin
    // 不写 FRequest/FResponse 连接级字段, 这两个字段仅由 _OnParseBegin
    // 在 _LockRecv 内独占写入. 当前完成 item 的 request/response 通过
    // LRequest/LResponse 显式传给 DoOnRequestEnd, 进而传给 OnRequestEnd 事件,
    // 事件 handler 可直接从参数拿到精确对应的请求/响应, 不需要读连接字段
    AtomicDecrement(FPending);

    // 用户 callback 可能抛异常, 必须用 try/finally 保证 DoOnRequestEnd 触发
    try
      if Assigned(LCallback) then
        LCallback(Self, ASuccess);
    finally
      FServer.DoOnRequestEnd(Self, LRequest, LResponse, ASuccess);
    end;
  end;

  if (not ASuccess) or LNeedDisconnect then
    Disconnect
  else if (LItemNext <> nil) then
    _SendQueueItem(LItemNext);
end;

procedure TCrossHttpConnection._OnBodyBegin;
var
  LMultiPart: THttpMultiPartFormData;
begin
  {$region '创建Body'}
  case FRequestObj.GetBodyType of
    btMultiPart:
      begin
        if (FServer.FStoragePath <> '') and not DirectoryExists(FServer.FStoragePath) then
          ForceDirectories(FServer.FStoragePath);

        LMultiPart := THttpMultiPartFormData.Create;
        LMultiPart.StoragePath := FServer.FStoragePath;
        LMultiPart.AutoDeleteFiles := FServer.FAutoDeleteFiles;
        LMultiPart.InitWithBoundary(FRequestObj.RequestBoundary);
        if (FRequestObj.FBody = FRequestObj.FRawBody) then
          FRequestObj.FBody := nil
        else
          FreeAndNil(FRequestObj.FBody);
        FreeAndNil(FRequestObj.FRawBody);
        FRequestObj.FBody := LMultiPart;
      end;

    btUrlEncoded, btBinary:
      begin
        // 二次校验: Parser 层可能未限制时由 Server 层兜底
        if (FServer.FMaxPostDataSize > 0) and (FRequestObj.FContentLength > FServer.FMaxPostDataSize) then
        begin
          _OnParseFailed(413, 'Request body too large.');
          Exit;  // FBody 保持 nil, _OnBodyData/_OnBodyEnd 有 nil guard 安全跳过
        end;
        if (FRequestObj.FBody = FRequestObj.FRawBody) then
          FRequestObj.FBody := nil
        else
          FreeAndNil(FRequestObj.FBody);
        FreeAndNil(FRequestObj.FRawBody);
        FRequestObj.FRawBody := TMemoryStream.Create;
        FRequestObj.FBody := FRequestObj.FRawBody;
      end;
  end;
  {$endregion}
end;

procedure TCrossHttpConnection._OnBodyData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  if (FRequestObj.FBody = nil) then Exit;

  Inc(FRequestObj.FPostDataSize, ADataSize);

  case FRequestObj.GetBodyType of
    btMultiPart:
      (FRequestObj.FBody as THttpMultiPartFormData).Decode(ADataPtr, ADataSize);

    btUrlEncoded, btBinary:
      if (FRequestObj.FRawBody <> nil) then
        FRequestObj.FRawBody.Write(ADataPtr^, ADataSize);
  end;
end;

procedure TCrossHttpConnection._OnBodyEnd;
var
  LUrlEncodedStr: string;
  LUrlEncodedBody: TFormUrlEncoded;
begin
  if (FRequestObj.FBody = nil) then Exit;

  case FRequestObj.GetBodyType of
    btUrlEncoded:
      begin
        if (FRequestObj.FRawBody = nil) then Exit;

        SetString(LUrlEncodedStr,
          MarshaledAString(FRequestObj.FRawBody.Memory),
          FRequestObj.FRawBody.Size);
        LUrlEncodedBody := TFormUrlEncoded.Create;
        if LUrlEncodedBody.Decode(LUrlEncodedStr) then
        begin
          if (FRequestObj.FBody = FRequestObj.FRawBody) then
            FRequestObj.FBody := nil
          else
            FreeAndNil(FRequestObj.FBody);
          FRequestObj.FBody := LUrlEncodedBody;
          FRequestObj.FRawBody.Position := 0;
        end else
        begin
          FreeAndNil(LUrlEncodedBody);
          // 如果按 UrlEncoded 方式解码失败, 则保留原始数据
          // 并将类型改为 btBinary
          FRequestObj.FBodyType := btBinary;
          FRequestObj.FBody := FRequestObj.FRawBody;
          FRequestObj.FRawBody.Position := 0;
        end;
      end;

    btBinary:
      if (FRequestObj.FRawBody <> nil) then
        FRequestObj.FRawBody.Position := 0;
  end;
end;

function TCrossHttpConnection._OnGetHeaderValue(const AHeaderName: string;
  out AHeaderValues: TArray<string>): Boolean;
begin
  Result := FRequest.Header.GetHeaderValues(AHeaderName, AHeaderValues);
end;

procedure TCrossHttpConnection._OnHeaderData(const ADataPtr: Pointer;
  const ADataSize: Integer);
var
  LParsed: Boolean;
  LExpect: string;
begin
  // ParseHeader 内部已用 try/except 将各类解析异常转为 Result := False,
  // 这里仍再加一层护栏, 防止以后修改 ParseHeader 时遗漏局部 try/except
  // 导致恶意/畸形请求的异常上抛到 LogicReceived 环外. 统一归一为 400 响应.
  try
    LParsed := (FRequest as TCrossHttpRequest).ParseHeader(ADataPtr, ADataSize);
  except
    LParsed := False;
  end;

  if not LParsed then
  begin
    _OnParseFailed(400, 'Invalid request header.');
    Abort;
  end;

  // RFC 7231 §5.1.1: Expect: 100-continue 支持
  //
  // 协议流程:
  //   客户端发送 header (含 Expect: 100-continue) →
  //   服务器在此处发送 100 Continue (临时响应, 不走响应队列) →
  //   Parser 继续接收 body (_OnBodyBegin → _OnBodyData → _OnBodyEnd) →
  //   _OnParseSuccess → DoOnRequest 正常处理路由/中间件 →
  //   最终发送正式响应 (200/404/500 等)
  //
  // 注意:
  //   100 Continue 只是一个协议层 "请继续" 信号, 不代表服务器接受该请求.
  //   当前实现不在此阶段做认证/校验, 意味着即使后续 DoOnRequest 返回 401,
  //   客户端也已发送完整 body. 对于大多数客户端, 不带 Expect 头时的行为
  //   也是如此 (body 总会随 header 一起发送), 所以无实际功能损失.
  // SendBuf 是非阻塞操作, 在 _LockRecv 内调用安全.
  LExpect := FRequest.Header[HEADER_EXPECT];
  if TStrUtils.SameText(LExpect.Trim, '100-continue') then
    Self.SendBuf(@CResponse100Continue[1], Length(CResponse100Continue), nil);
end;

procedure TCrossHttpConnection._OnParseBegin;
var
  LItem: IHttpResponseQueueItem;
begin
  // 本函数以及其它 HttpParser 回调均由 FHttpParser.Decode -> ParseRecvData ->
  // FServer.LogicReceived -> TCrossSocketBase.TriggerReceived 同步触发,
  // 调用链起点已由 TriggerReceived 加上 TCrossConnectionBase._LockRecv,
  // 所以这里不需要也不应该重复加锁

  // 为本次请求创建独立的 queue item, 队列顺序由解析顺序决定
  LItem := THttpResponseQueueItem.Create;

  FRequestObj := TCrossHttpRequest.Create(Self);
  FRequest := FRequestObj;

  // 创建响应对象, 显式绑定到 request 和 queue item, 确保异步发送时
  // 不依赖连接级 FRequest/FResponse 字段
  FResponseObj := TCrossHttpResponse.Create(Self, FRequest, LItem);
  FResponse := FResponseObj;

  LItem.Request := FRequest;
  LItem.Response := FResponse;

  FResponseQueueLock.Enter;
  try
    FResponseQueue.Add(LItem);
  finally
    FResponseQueueLock.Leave;
  end;

  AtomicIncrement(FPending);
end;

procedure TCrossHttpConnection._OnParseFailed(const ACode: Integer;
  const AError: string);
begin
  if (FResponse <> nil) then
    FResponse.SendStatus(ACode, AError)
  else
    Close;
end;

procedure TCrossHttpConnection._OnParseSuccess;
var
  LConnection: ICrossHttpConnection;
  LRequest: ICrossHttpRequest;
  LResponse: ICrossHttpResponse;
begin
  LConnection := Self;
  // 这里是 _LockRecv 保护下的同步调用, FRequest/FResponse 此刻仍是
  // _OnParseBegin 刚写入的当前 parse item 的 request/response.
  // 显式捕获为局部接口引用的真正意义在于: 一旦后续业务释放锁
  // (如未来调整架构则业务可能在锁外运行) 或 _OnParseBegin 重新写入
  // 连接级字段, 本局部变量仍以接口引用计数保证当前请求/响应对象存活,
  // 不会读到错位对象。对象生命周期本质上由接口引用计数保证, 与锁无关
  LRequest := FRequest;
  LResponse := FResponse;
  FServer.DoOnRequestBegin(LConnection, LRequest, LResponse);
  FServer.DoOnRequest(LConnection, LRequest, LResponse);
end;

function IsRegEx(const APattern: string): Boolean; inline;
begin
  Result := (APattern.IndexOfAny(REGEX_CHARS) >= 0);
end;

function IsWildcard(const APattern: string): Boolean; inline;
begin
  Result := (APattern = WILDCARD_CHAR);
end;

function GetPatternType(const APattern: string): TRouteType; inline;
begin
  // 通配符
  if IsWildcard(APattern) then
    Result := rtWildcard
  // 正则
  else if IsRegEx(APattern) then
    Result := rtRegex
  // 静态
  else
    Result := rtStatic;
end;

function CreateRouterRegEx(const APattern: string): IRegEx;
var
  LPattern: string;
begin
  LPattern := APattern;
  if (LPattern = '*') then
    LPattern := '.*';

  // 添加正则表达式的开始和结束锚点
  if not LPattern.StartsWith('^') then
    LPattern := '^' + LPattern;
  if not LPattern.EndsWith('$') then
    LPattern := LPattern + '$';

  Result := TRegEx.Create(LPattern);
  Result.Options := [roIgnoreCase];
end;

{ TRouter }

procedure TRouter.AddRouterProc(const ARouterProc: TCrossHttpRouterProc);
begin
  FLock.BeginWrite;
  try
    FRouterProcList.Add(ARouterProc);
  finally
    FLock.EndWrite;
  end;
end;

procedure TRouter.AddRouterProc(const ARouterMethod: TCrossHttpRouterMethod);
begin
  FLock.BeginWrite;
  try
    FRouterMethodList.Add(ARouterMethod);
  finally
    FLock.EndWrite;
  end;
end;

constructor TRouter.Create(const AMethodPattern: string);
begin
  FMethodPattern := AMethodPattern;
  FRouteType := GetPatternType(AMethodPattern);

  FRouterProcList := TList<TCrossHttpRouterProc>.Create;
  FRouterMethodList := TList<TCrossHttpRouterMethod>.Create;
  FLock := TReadWriteLock.Create;
end;

destructor TRouter.Destroy;
begin
  FreeAndNil(FRouterProcList);
  FreeAndNil(FRouterMethodList);

  inherited;
end;

function TRouter.GetRouteType: TRouteType;
begin
  Result := FRouteType;
end;

function TRouter.GetMethodPattern: string;
begin
  Result := FMethodPattern;
end;

function TRouter.GetRegEx: IRegEx;
begin
  Result := nil;
  if (FRouteType = rtRegex) then
    Result := CreateRouterRegEx(FMethodPattern);
end;

procedure TRouter.Execute(const ARequest: ICrossHttpRequest;
  const AResponse: ICrossHttpResponse; var AHandled: Boolean);
var
  LRouterProcArr: TArray<TCrossHttpRouterProc>;
  LRouterMethodArr: TArray<TCrossHttpRouterMethod>;
  LRouterProc: TCrossHttpRouterProc;
  LRouterMethod: TCrossHttpRouterMethod;
begin
  FLock.BeginRead;
  try
    LRouterProcArr := FRouterProcList.ToArray;
    LRouterMethodArr := FRouterMethodList.ToArray;
  finally
    FLock.EndRead;
  end;

  for LRouterProc in LRouterProcArr do
  begin
    if Assigned(LRouterProc) then
    begin
      LRouterProc(ARequest, AResponse, AHandled);
      if AHandled or AResponse.Sent then Exit;
    end;
  end;

  for LRouterMethod in LRouterMethodArr do
  begin
    if Assigned(LRouterMethod) then
    begin
      LRouterMethod(ARequest, AResponse, AHandled);
      if AHandled or AResponse.Sent then Exit;
    end;
  end;
end;

{ TRouteSegment }

constructor TRouteSegment.Create(const AOriginal, APattern: string;
  const AParams: TArray<TRouteParam>; ARouteType: TRouteType);
begin
  inherited Create;
  FOriginal := AOriginal;
  FPattern := APattern;
  FParams := AParams;
  FRouteType := ARouteType;
end;

function TRouteSegment.RegexMatch(const ASegment: string; const ARequest: ICrossHttpRequest): Boolean;
var
  I: Integer;
  LRegEx: IRegEx;
begin
  Result := False;

  case FRouteType of
    rtRegex:
      begin
        LRegEx := CreateRouterRegEx(FPattern);
        if LRegEx <> nil then
        begin
          LRegEx.Subject := ASegment;
          Result := LRegEx.Match;
          if Result and Assigned(ARequest) then
          begin
            // 提取所有参数值
            for I := 0 to High(FParams) do
              ARequest.Params[FParams[I].Name] := LRegEx.Groups[I + 1];
          end;
        end;
      end;
  end;
end;

{ TRouteNode }

constructor TRouteNode.Create(ARouteType: TRouteType; const ASegment: TRouteSegment);
begin
  inherited Create;

  FRouteType := ARouteType;
  FSegment := ASegment;
  FStaticChildren := TObjectDictionary<string, TRouteNode>.Create([doOwnsValues]);
  FRegexChildren := TObjectList<TRouteNode>.Create(True);

  FStaticRouteMethodItems := TDictionary<string, IRouter>.Create;
  FRegexRouteMethodItems := TList<IRouter>.Create;
end;

destructor TRouteNode.Destroy;
begin
  FreeAndNil(FSegment);
  FreeAndNil(FStaticChildren);
  FreeAndNil(FRegexChildren);
  FreeAndNil(FWildcardChild);

  FreeAndNil(FStaticRouteMethodItems);
  FreeAndNil(FRegexRouteMethodItems);
  FWildcardRouteMethodItem := nil;

  inherited;
end;

function TRouteNode.CreateChildNode(const ASegment: TRouteSegment): TRouteNode;
begin
  case ASegment.RouteType of
    rtStatic:
      begin
        Result := TRouteNode.Create(rtStatic, ASegment);
        FStaticChildren.Add(ASegment.Original.ToLower, Result);
      end;

    rtRegex:
      begin
        Result := TRouteNode.Create(rtRegex, ASegment);
        FRegexChildren.Add(Result);
      end;

    rtWildcard:
      begin
        if FWildcardChild = nil then
          FWildcardChild := TRouteNode.Create(rtWildcard, ASegment);
        Result := FWildcardChild;
      end;
  else
    Result := nil;
  end;
end;

procedure TRouteNode.AddRouter(const AMethodPattern: string; const ARouter: IRouter);
begin
  case ARouter.RouteType of
    rtStatic:
      FStaticRouteMethodItems.AddOrSetValue(AMethodPattern.ToLower, ARouter);

    rtRegex:
      FRegexRouteMethodItems.Add(ARouter);

    rtWildcard:
      FWildcardRouteMethodItem := ARouter;
  end;
end;

function TRouteNode.GetChildNode(const ASegment: string;
  const ARouteType: TRouteType; out ARouteNode: TRouteNode): Boolean;
var
  LChild: TRouteNode;
begin
  case ARouteType of
    rtStatic:
      begin
        Result := FStaticChildren.TryGetValue(ASegment.ToLower, ARouteNode)
      end;

    rtRegex:
      begin
        for LChild in FRegexChildren do
        begin
          if (LChild.Segment.Original = ASegment) then
          begin
            ARouteNode := LChild;
            Exit(True);
          end;
        end;

        Result := False;
      end;

    rtWildcard:
      begin
        ARouteNode := FWildcardChild;
        Result := (ARouteNode <> nil);
      end;
  else
    ARouteNode := nil;
    Result := False;
  end;
end;

function TRouteNode.GetRouter(const AMethodPattern: string;
  out ARouter: IRouter): Boolean;
var
  I: Integer;
  LRouter: IRouter;
begin
  Result := False;

  // 先尝试从静态方法路由中查找
  if FStaticRouteMethodItems.TryGetValue(AMethodPattern.ToLower, ARouter) then
    Exit(True);

  // 从正则方法路由中查找
  for I := 0 to FRegexRouteMethodItems.Count - 1 do
  begin
    LRouter := FRegexRouteMethodItems[I];
    if SameText(LRouter.MethodPattern, AMethodPattern) then
    begin
      ARouter := LRouter;
      Exit(True);
    end;
  end;

  // 从通配符方法路由中查找
  if (FWildcardRouteMethodItem <> nil) and IsWildcard(AMethodPattern) then
  begin
    ARouter := FWildcardRouteMethodItem;
    Exit(True);
  end;
end;

function TRouteNode.MatchRouter(const AMethod: string;
  out ARouter: IRouter): Boolean;
var
  LRouter: IRouter;
  LRegEx: IRegEx;
begin
  Result := False;

  // 优先从静态方法路由中查找
  if FStaticRouteMethodItems.TryGetValue(AMethod.ToLower, LRouter) then
  begin
    ARouter := LRouter;
    Exit(True);
  end;

  // 遍历所有正则方法路由项, 找到第一个匹配的
  for LRouter in FRegexRouteMethodItems do
  begin
    // 正则表达式方法使用局部匹配器, 避免并发请求共享匹配状态
    LRegEx := LRouter.RegEx;
    if (LRegEx <> nil) then
    begin
      LRegEx.Subject := AMethod;
      if LRegEx.Match then
      begin
        ARouter := LRouter;
        Exit(True);
      end;
    end;
  end;

  // 通配符
  if (FWildcardRouteMethodItem <> nil) then
  begin
    ARouter := FWildcardRouteMethodItem;
    Exit(True);
  end;
end;

function TRouteNode.RemoveRouter(const AMethodPattern: string): Boolean;
var
  LLowerMethod: string;
  I: Integer;
  LRouter: IRouter;
begin
  Result := False;

  // 先尝试从静态方法路由中删除
  LLowerMethod := AMethodPattern.ToLower;
  if FStaticRouteMethodItems.ContainsKey(LLowerMethod) then
  begin
    FStaticRouteMethodItems.Remove(LLowerMethod);
    Exit(True);
  end;

  // 从通配符方法路由删除
  if (FWildcardRouteMethodItem <> nil) and IsWildcard(AMethodPattern) then
  begin
    FWildcardRouteMethodItem := nil;
    Exit(True);
  end;

  // 遍历正则方法路由项, 删除匹配的路由
  for I := FRegexRouteMethodItems.Count - 1 downto 0 do
  begin
    LRouter := FRegexRouteMethodItems[I];
    if SameText(LRouter.MethodPattern, AMethodPattern) then
    begin
      FRegexRouteMethodItems.Delete(I);
      Exit(True);
    end;
  end;
end;

function TRouteNode.IsEmpty: Boolean;
begin
  // 节点为空的条件: 没有子节点且没有路由处理函数
  Result := (FStaticChildren.Count = 0) and
            (FRegexChildren.Count = 0) and
            (FWildcardChild = nil) and
            (FStaticRouteMethodItems.Count = 0) and
            (FRegexRouteMethodItems.Count = 0) and
            (FWildcardRouteMethodItem = nil);
end;

{ TCrossHttpRouterTree }

constructor TCrossHttpRouterTree.Create;
begin
  inherited Create;

  FRoot := TRouteNode.Create(rtStatic, TRouteSegment.Create('', '', [], rtStatic));
  FLock := TReadWriteLock.Create;
end;

destructor TCrossHttpRouterTree.Destroy;
begin
  FreeAndNil(FRoot);

  inherited;
end;

function TCrossHttpRouterTree.CreateSegment(const ASegment: string;
  const ARouteType: TRouteType): TRouteSegment;
var
  LPattern: string;
  LParams: TArray<TRouteParam>;
begin
  LPattern := ASegment;
  LParams := [];

  // 正则段需要处理参数
  if (ARouteType = rtRegex) then
  begin
    LPattern := ASegment;
    LParams := [];
    // 使用正则表达式匹配所有参数模式
    // 匹配 :param 和 :param(pattern) 格式
    // 可以在参数后面增加正则限定参数 :number(\d+), :word(\w+)
    LPattern := TRegEx.Replace(LPattern, ':(\w+)(?:\((.*?)\))?',
      function(const AMatch: TMatch): string
      var
        LParamName, LParamPattern: string;
        LParam: TRouteParam;
      begin
        if not AMatch.Success then Exit('');

        if (AMatch.Groups.Count > 1) then
          LParamName := AMatch.Groups[1].Value
        else
          LParamName := '';
        if (AMatch.Groups.Count > 2) then
          LParamPattern := AMatch.Groups[2].Value
        else
          LParamPattern := '';

        if (LParamPattern = '') or (LParamPattern = '*') then
          LParamPattern := '.*';

        Result := '(' + LParamPattern + ')';

        LParam.Name := LParamName;
        LParam.Pattern := LParamPattern;
        LParams := LParams + [LParam];
      end);
  end;

  Result := TRouteSegment.Create(ASegment, LPattern, LParams, ARouteType);
end;

class function TCrossHttpRouterTree.ParsePath(const APath: string): TArray<string>;
begin
  // 请求的是根路径, 无需拆分
  if (APath = '/') or (APath = '') then
  begin
    Result := [''];
    Exit;
  end;

  // 把请求路径按/拆分成多段
  Result := APath.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  if (Result = nil) then
    Result := [''];
end;

procedure TCrossHttpRouterTree.AddRouter(const AMethodPattern, APathPattern: string;
  const ARouter: IRouter);
var
  LPathSegments: TArray<string>;
begin
  FLock.BeginWrite;
  try
    LPathSegments := ParsePath(APathPattern);
    AddRouterToNode(FRoot, LPathSegments, 0, AMethodPattern, ARouter);
  finally
    FLock.EndWrite;
  end;
end;

procedure TCrossHttpRouterTree.AddRouter(const AMethodPattern,
  APathPattern: string; const ARouterProc: TCrossHttpRouterProc);
var
  LRouter: IRouter;
begin
  LRouter := GetRouter(AMethodPattern, APathPattern);
  LRouter.AddRouterProc(ARouterProc);
end;

procedure TCrossHttpRouterTree.AddRouter(const AMethodPattern,
  APathPattern: string; const ARouterMethod: TCrossHttpRouterMethod);
var
  LRouter: IRouter;
begin
  LRouter := GetRouter(AMethodPattern, APathPattern);
  LRouter.AddRouterProc(ARouterMethod);
end;

procedure TCrossHttpRouterTree.AddRouterToNode(ANode: TRouteNode;
  const APathPatternSegments: TArray<string>; AIndex: Integer; const AMethodPattern: string;
  const ARouter: IRouter);
var
  LSegmentPattern: string;
  LRouteType: TRouteType;
  LRouteSegment: TRouteSegment;
  LChild: TRouteNode;
begin
  if (AIndex > High(APathPatternSegments)) then
  begin
    // 到达路径末尾, 添加路由
    ANode.AddRouter(AMethodPattern, ARouter);
    Exit;
  end;

  LSegmentPattern := APathPatternSegments[AIndex];
  LRouteType := GetPatternType(LSegmentPattern);

  if not ANode.GetChildNode(LSegmentPattern, LRouteType, LChild) then
  begin
    LRouteSegment := CreateSegment(LSegmentPattern, LRouteType);
    LChild := ANode.CreateChildNode(LRouteSegment);
  end;

  AddRouterToNode(LChild, APathPatternSegments, AIndex + 1, AMethodPattern, ARouter);
end;

function TCrossHttpRouterTree.GetRouter(const AMethodPattern,
  APathPattern: string; out ARouter: IRouter): Boolean;
var
  LPathSegments: TArray<string>;
begin
  FLock.BeginRead;
  try
    LPathSegments := ParsePath(APathPattern);
    Result := GetRouterFromNode(FRoot, LPathSegments, 0, AMethodPattern, ARouter);
  finally
    FLock.EndRead;
  end;
end;

function TCrossHttpRouterTree.GetRouter(const AMethodPattern,
  APathPattern: string): IRouter;
var
  LPathSegments: TArray<string>;
begin
  FLock.BeginWrite;
  try
    LPathSegments := ParsePath(APathPattern);
    if not GetRouterFromNode(FRoot, LPathSegments, 0, AMethodPattern, Result) then
    begin
      Result := TRouter.Create(AMethodPattern);
      AddRouterToNode(FRoot, LPathSegments, 0, AMethodPattern, Result);
    end;
  finally
    FLock.EndWrite;
  end;
end;

function TCrossHttpRouterTree.GetRouterFromNode(ANode: TRouteNode;
  const APathPatternSegments: TArray<string>; AIndex: Integer;
  const AMethodPattern: string; out ARouter: IRouter): Boolean;
var
  LSegmentPattern: string;
  LRouteType: TRouteType;
  LChild: TRouteNode;
  LFound: Boolean;
begin
  Result := False;

  if (AIndex > High(APathPatternSegments)) then
  begin
    // 到达路径末尾, 查找该节点的路由
    Result := ANode.GetRouter(AMethodPattern, ARouter);
    Exit;
  end;

  LSegmentPattern := APathPatternSegments[AIndex];
  LRouteType := GetPatternType(LSegmentPattern);

  case LRouteType of
    rtStatic:
      // 从静态子节点中查找路由
      if ANode.StaticChildren.TryGetValue(LSegmentPattern.ToLower, LChild) then
      begin
        LFound := GetRouterFromNode(LChild, APathPatternSegments, AIndex + 1, AMethodPattern, ARouter);
        Result := Result or LFound;
      end;

    rtRegex:
      // 从正则子节点中查找路由
      for LChild in ANode.RegexChildren do
      begin
        if SameText(LChild.Segment.Original, LSegmentPattern) then
        begin
          LFound := GetRouterFromNode(LChild, APathPatternSegments, AIndex + 1, AMethodPattern, ARouter);
          Result := Result or LFound;
          if Result then Break;
        end;
      end;

    rtWildcard:
      // 从通配符子节点查找路由
      if (ANode.WildcardChild <> nil) then
      begin
        LFound := ANode.WildcardChild.GetRouter(AMethodPattern, ARouter);
        Result := Result or LFound;
      end;
  end;
end;

function TCrossHttpRouterTree.GetWildcardValue(
  const APathSegments: TArray<string>; AIndex: Integer;
  const AQueryText: string): string;
begin
  Result := string.Join('/', APathSegments, AIndex, Length(APathSegments) - AIndex);
  if (AQueryText <> '') then
    Result := Result + '?' + AQueryText;
end;

function TCrossHttpRouterTree.MatchRouterInNode(ANode: TRouteNode;
  const APathSegments: TArray<string>; AIndex: Integer; const AMethod: string;
  const ARequest: ICrossHttpRequest; out ARouter: IRouter): Boolean;
var
  LSegment, LWildcardValue: string;
  LChild: TRouteNode;
begin
  Result := False;

  if (AIndex > High(APathSegments)) then
  begin
    // 到达路径末尾, 查找匹配方法的路由
    Result := ANode.MatchRouter(AMethod, ARouter);

    // 尝试从通配符子节点查找路由
    if not Result and (ANode.WildcardChild <> nil) then
    begin
      Result := ANode.WildcardChild.MatchRouter(AMethod, ARouter);
      if Result then
      begin
        LWildcardValue := GetWildcardValue(APathSegments, AIndex, ARequest.QueryText);
        if Assigned(ARequest) then
          ARequest.Params[WILDCARD_CHAR] := LWildcardValue;
      end;
    end;

    Exit;
  end;

  LSegment := APathSegments[AIndex];

  // 1. 首先尝试精确匹配静态节点
  if ANode.StaticChildren.TryGetValue(LSegment.ToLower, LChild) then
  begin
    Result := MatchRouterInNode(LChild, APathSegments, AIndex + 1, AMethod,
      ARequest, ARouter);
    if Result then Exit;
  end;

  // 2. 尝试正则节点(支持多参数)
  for LChild in ANode.RegexChildren do
  begin
    if LChild.Segment.RegexMatch(LSegment, ARequest) then
    begin
      // 普通正则节点, 继续递归匹配
      Result := MatchRouterInNode(LChild, APathSegments, AIndex + 1, AMethod,
        ARequest, ARouter);
      if Result then Exit;
    end;
  end;

  // 3. 最后尝试通配符子节点(优先级最低)
  if (ANode.WildcardChild <> nil) then
  begin
    Result := ANode.WildcardChild.MatchRouter(AMethod, ARouter);
    if Result then
    begin
      LWildcardValue := GetWildcardValue(APathSegments, AIndex, ARequest.QueryText);
      if Assigned(ARequest) then
        ARequest.Params[WILDCARD_CHAR] := LWildcardValue;

      Exit;
    end;
  end;
end;

function TCrossHttpRouterTree.MatchRouter(const APathSegments: TArray<string>;
  const ARequest: ICrossHttpRequest; out ARouter: IRouter): Boolean;
begin
  FLock.BeginRead;
  try
    if FRoot.IsEmpty then
    begin
      ARouter := nil;
      Exit(False);
    end;

    Result := MatchRouterInNode(FRoot, APathSegments, 0, ARequest.Method, ARequest, ARouter);
  finally
    FLock.EndRead;
  end;
end;

function TCrossHttpRouterTree.MatchRouter(const ARequest: ICrossHttpRequest;
  out ARouter: IRouter): Boolean;
var
  LPathSegments: TArray<string>;
begin
  LPathSegments := ParsePath(ARequest.Path);
  Result := MatchRouter(LPathSegments, ARequest, ARouter);
end;

function TCrossHttpRouterTree.RemoveRouterFromNode(ANode: TRouteNode;
  const APathPatternSegments: TArray<string>; AIndex: Integer; const AMethodPattern: string): Boolean;
var
  LSegmentPattern, LLowerSegment: string;
  LRouteType: TRouteType;
  LChild: TRouteNode;
  LRemoved: Boolean;
  I: Integer;
begin
  Result := False;

  if (AIndex > High(APathPatternSegments)) then
  begin
    // 到达路径末尾, 删除该节点的路由
    Result := ANode.RemoveRouter(AMethodPattern);
    Exit;
  end;

  LSegmentPattern := APathPatternSegments[AIndex];
  LRouteType := GetPatternType(LSegmentPattern);
  LLowerSegment := LSegmentPattern.ToLower;

  case LRouteType of
    rtStatic:
      // 从静态子节点中删除路由
      if ANode.StaticChildren.TryGetValue(LLowerSegment, LChild) then
      begin
        LRemoved := RemoveRouterFromNode(LChild, APathPatternSegments, AIndex + 1, AMethodPattern);

        // 如果子节点变空, 删除它
        if LRemoved and LChild.IsEmpty then
          ANode.StaticChildren.Remove(LLowerSegment);

        Result := Result or LRemoved;
      end;

    rtRegex:
      // 从正则子节点中删除路由（逆序遍历，避免在迭代中修改集合）
      for I := ANode.RegexChildren.Count - 1 downto 0 do
      begin
        LChild := ANode.RegexChildren[I];
        if SameText(LChild.Segment.Original, LSegmentPattern) then
        begin
          LRemoved := RemoveRouterFromNode(LChild, APathPatternSegments, AIndex + 1, AMethodPattern);

          // 如果子节点变空, 删除它
          if LRemoved and LChild.IsEmpty then
            ANode.RegexChildren.Delete(I);

          Result := Result or LRemoved;
          if Result then Break;
        end;
      end;

    rtWildcard:
      // 从通配符子节点删除路由
      if (ANode.WildcardChild <> nil) then
      begin
        LRemoved := ANode.WildcardChild.RemoveRouter(AMethodPattern);

        // 如果子节点变空, 删除它
        if LRemoved and ANode.WildcardChild.IsEmpty then
          FreeAndNil(ANode.FWildcardChild);

        Result := Result or LRemoved;
      end;
  end;
end;

procedure TCrossHttpRouterTree.RemoveRouter(const AMethodPattern, APathPattern: string);
var
  LPathSegments: TArray<string>;
begin
  FLock.BeginWrite;
  try
    LPathSegments := ParsePath(APathPattern);
    RemoveRouterFromNode(FRoot, LPathSegments, 0, AMethodPattern);
  finally
    FLock.EndWrite;
  end;
end;

procedure TCrossHttpRouterTree.Clear;
begin
  FLock.BeginWrite;
  try
    FreeAndNil(FRoot);
    FRoot := TRouteNode.Create(rtStatic, TRouteSegment.Create('', '', [], rtStatic));
  finally
    FLock.EndWrite;
  end;
end;

{ TCrossHttpServer }

function TCrossHttpServer.All(const APath: string;
  const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('*', APath, ARouterProc);
end;

function TCrossHttpServer.All(const APath: string;
  const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('*', APath, ARouterMethod);
end;

constructor TCrossHttpServer.Create(const AIoThreads: Integer; const ASsl: Boolean);
begin
  inherited Create(AIoThreads, ASsl);

  FRouters := TCrossHttpRouterTree.Create;
  FMiddlewares := TCrossHttpRouterTree.Create;

  Port := 80;
  Addr := '';

  FCompressible := True;
  FMinCompressSize := MIN_COMPRESS_SIZE;
  FMaxCompressRatio := DEFAULT_MAX_COMPRESS_RATIO;
  FStoragePath := TCrossHttpUtils.CombinePath(TUtils.AppPath, 'temp', PathDelim) + PathDelim;
  FSessionIDCookieName := SESSIONID_COOKIE_NAME;
end;

function TCrossHttpServer.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossHttpConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

destructor TCrossHttpServer.Destroy;
begin
  Stop;

  FreeAndNil(FRouters);
  FreeAndNil(FMiddlewares);

  inherited Destroy;
end;

function TCrossHttpServer.Dir(const APath, ALocalDir: string): ICrossHttpServer;
var
  LReqPath: string;
begin
  LReqPath := APath;
  if not LReqPath.EndsWith('/') then
    LReqPath := LReqPath + '/';
  LReqPath := LReqPath + '*';
  Result := Get(LReqPath, TNetCrossRouter.Dir(APath, ALocalDir, '*'));
end;

function TCrossHttpServer.Delete(const APath: string;
  const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('DELETE', APath, ARouterProc);
end;

function TCrossHttpServer.Delete(const APath: string;
  const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('DELETE', APath, ARouterMethod);
end;

procedure TCrossHttpServer.DoOnRequestBegin(
  const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse);
begin
  if Assigned(FOnRequestBegin) then
    FOnRequestBegin(Self, AConnection, ARequest, AResponse);
end;

procedure TCrossHttpServer.DoOnRequestEnd(
  const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
  const ASuccess: Boolean);
begin
  if Assigned(FOnRequestEnd) then
    FOnRequestEnd(Self, AConnection, ARequest, AResponse, ASuccess);
end;

procedure TCrossHttpServer.DoOnRequest(const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse);
var
  LRequest: ICrossHttpRequest;
  LResponse: ICrossHttpResponse;
  LSessionID: string;
  LPathSegments: TArray<string>;
  LHandled: Boolean;
  LRouter: IRouter;
begin
  // 显式接收来自 _OnParseSuccess 的 request/response, 不再读取连接字段,
  // 避免与 _FinishQueueItem 等异步线程构成 race
  LRequest := ARequest;
  LResponse := AResponse;
  LHandled := False;

  try
    {$region 'Session'}
    if (FSessions <> nil) and (FSessionIDCookieName <> '') then
    begin
      LSessionID := LRequest.Cookies[FSessionIDCookieName];
      (LRequest as TCrossHttpRequest).FSession := FSessions.Sessions[LSessionID];
      if (LRequest.Session <> nil) and (LRequest.Session.SessionID <> LSessionID) then
      begin
        LSessionID := LRequest.Session.SessionID;
        LResponse.Cookies.AddOrSet(FSessionIDCookieName, LSessionID, 0);
      end;
    end;
    {$endregion}

    // 提前拆分请求路径, 可以减少一次 ParsePath 调用
    LPathSegments := TCrossHttpRouterTree.ParsePath(LRequest.Path);

    {$region '中间件'}
    // 执行匹配的中间件
    if FMiddlewares.MatchRouter(LPathSegments, LRequest, LRouter) then
    begin
      // 中间件通常用于请求的预处理
      // 所以默认将 LHandled 置为 False, 以保证后续路由能被执行
      // 除非用户在中间件中明确指定了 LHandled := True, 表明该请求无需后续路由响应了
      LHandled := False;
      LRouter.Execute(LRequest, LResponse, LHandled);

      // 如果已经发送了数据, 则后续的事件和路由响应都不需要执行了
      if LHandled or LResponse.Sent then Exit;
    end;
    {$endregion}

    {$region '路由'}
    // 执行匹配的路由
    if FRouters.MatchRouter(LPathSegments, LRequest, LRouter) then
    begin
      // 路由用于响应请求
      // 所以默认将 LHandled 置为 True, 以保证不会有多个匹配的路由被执行
      // 除非用户在路由中明确指定了 LHandled := False, 表明该路由并没有
      // 完成请求响应, 还需要后续路由继续进行响应
      LHandled := True;
      LRouter.Execute(LRequest, LResponse, LHandled);

      // 如果已经发送了数据, 则后续的事件和路由响应都不需要执行了
      if LHandled or LResponse.Sent then Exit;
    end;
    {$endregion}

    {$region '响应请求事件'}
    if Assigned(FOnRequest)
      and not (LHandled or LResponse.Sent) then
    begin
      FOnRequest(Self, AConnection, LRequest, LResponse, LHandled);

      // 如果已经发送了数据, 则后续的事件和路由响应都不需要执行了
      if LHandled or LResponse.Sent then Exit;
    end;
    {$endregion}

    // 如果该请求没有被任何中间件、事件、路由响应, 返回 404
    if not (LHandled or LResponse.Sent) then
      LResponse.SendStatus(404);
  except
    on e: Exception do
    begin
      if Assigned(FOnRequestException) then
        FOnRequestException(Self, LRequest, LResponse, e)
      else if LResponse.Sent then
        AConnection.Disconnect
      else if (e is ECrossHttpException) then
        LResponse.SendStatus(ECrossHttpException(e).StatusCode, ECrossHttpException(e).Message)
      else
        LResponse.SendStatus(500, e.Message);
    end;
  end;
end;

function TCrossHttpServer.Get(const APath: string;
  const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('GET', APath, ARouterProc);
end;

function TCrossHttpServer.Get(const APath: string;
  const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('GET', APath, ARouterMethod);
end;

function TCrossHttpServer.GetOnRequestEnd: TCrossHttpRequestEndEvent;
begin
  Result := FOnRequestEnd;
end;

function TCrossHttpServer.GetAutoDeleteFiles: Boolean;
begin
  Result := FAutoDeleteFiles;
end;

function TCrossHttpServer.GetOnRequestBegin: TCrossHttpRequestBeginEvent;
begin
  Result := FOnRequestBegin;
end;

function TCrossHttpServer.GetCompressible: Boolean;
begin
  Result := FCompressible;
end;

function TCrossHttpServer.GetMaxHeaderSize: Int64;
begin
  Result := FMaxHeaderSize;
end;

function TCrossHttpServer.GetMaxPostDataSize: Int64;
begin
  Result := FMaxPostDataSize;
end;

function TCrossHttpServer.GetMaxCompressRatio: Integer;
begin
  Result := FMaxCompressRatio;
end;

function TCrossHttpServer.GetMinCompressSize: Int64;
begin
  Result := FMinCompressSize;
end;

function TCrossHttpServer.GetOnRequest: TCrossHttpRequestEvent;
begin
  Result := FOnRequest;
end;

function TCrossHttpServer.GetOnRequestException: TCrossHttpRequestExceptionEvent;
begin
  Result := FOnRequestException;
end;

function TCrossHttpServer.GetSessionIDCookieName: string;
begin
  Result := FSessionIDCookieName;
end;

function TCrossHttpServer.GetSessions: ISessions;
begin
  Result := FSessions;
end;

function TCrossHttpServer.GetStoragePath: string;
begin
  Result := FStoragePath;
end;

procedure TCrossHttpServer.SetOnRequestEnd(const Value: TCrossHttpRequestEndEvent);
begin
  FOnRequestEnd := Value;
end;

procedure TCrossHttpServer.SetAutoDeleteFiles(const Value: Boolean);
begin
  FAutoDeleteFiles := Value;
end;

procedure TCrossHttpServer.SetOnRequestBegin(const Value: TCrossHttpRequestBeginEvent);
begin
  FOnRequestBegin := Value;
end;

procedure TCrossHttpServer.SetCompressible(const Value: Boolean);
begin
  FCompressible := Value;
end;

procedure TCrossHttpServer.SetMaxHeaderSize(const Value: Int64);
begin
  FMaxHeaderSize := Value;
end;

procedure TCrossHttpServer.SetMaxPostDataSize(const Value: Int64);
begin
  FMaxPostDataSize := Value;
end;

procedure TCrossHttpServer.SetMaxCompressRatio(const Value: Integer);
begin
  FMaxCompressRatio := Value;
end;

procedure TCrossHttpServer.SetMinCompressSize(const Value: Int64);
begin
  FMinCompressSize := Value;
end;

procedure TCrossHttpServer.SetOnRequest(const Value: TCrossHttpRequestEvent);
begin
  FOnRequest := Value;
end;

procedure TCrossHttpServer.SetOnRequestException(
  const Value: TCrossHttpRequestExceptionEvent);
begin
  FOnRequestException := Value;
end;

procedure TCrossHttpServer.SetSessionIDCookieName(const Value: string);
begin
  FSessionIDCookieName := Value;
end;

procedure TCrossHttpServer.SetSessions(const Value: ISessions);
begin
  FSessions := Value;
end;

procedure TCrossHttpServer.SetStoragePath(const Value: string);
begin
  FStoragePath := Value;
end;

function TCrossHttpServer.Static(const APath,
  ALocalStaticDir: string): ICrossHttpServer;
var
  LReqPath: string;
begin
  LReqPath := APath;
  if not LReqPath.EndsWith('/') then
    LReqPath := LReqPath + '/';
  LReqPath := LReqPath + '*';
  Result := Get(LReqPath, TNetCrossRouter.Static(ALocalStaticDir, '*'));
end;

function TCrossHttpServer.Index(const APath, ALocalDir: string;
  const ADefIndexFiles: TArray<string>): ICrossHttpServer;
var
  LReqPath: string;
begin
  LReqPath := APath;
  if not LReqPath.EndsWith('/') then
    LReqPath := LReqPath + '/';
  LReqPath := LReqPath + '*';
  Result := Get(LReqPath, TNetCrossRouter.Index(ALocalDir, '*', ADefIndexFiles));
end;

function TCrossHttpServer.Post(const APath: string;
  const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('POST', APath, ARouterProc);
end;

function TCrossHttpServer.Post(const APath: string;
  const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('POST', APath, ARouterMethod);
end;

function TCrossHttpServer.Put(const APath: string;
  const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('PUT', APath, ARouterMethod);
end;

function TCrossHttpServer.Put(const APath: string;
  const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('PUT', APath, ARouterProc);
end;

function TCrossHttpServer.Route(const AMethod, APath: string;
  const ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  FRouters.AddRouter(AMethod, APath, ARouterProc);
  Result := Self;
end;

function TCrossHttpServer.Route(const AMethod, APath: string;
  const ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  FRouters.AddRouter(AMethod, APath, ARouterMethod);
  Result := Self;
end;

function TCrossHttpServer.RemoveMiddleware(const AMethod,
  APath: string): ICrossHttpServer;
begin
  FMiddlewares.RemoveRouter(AMethod, APath);
  Result := Self;
end;

function TCrossHttpServer.RemoveRouter(const AMethod, APath: string): ICrossHttpServer;
begin
  FRouters.RemoveRouter(AMethod, APath);
  Result := Self;
end;

function TCrossHttpServer.ClearMiddlewares: ICrossHttpServer;
begin
  FMiddlewares.Clear;
  Result := Self;
end;

function TCrossHttpServer.ClearRouters: ICrossHttpServer;
begin
  FRouters.Clear;
  Result := Self;
end;

procedure TCrossHttpServer.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnObj: TCrossHttpConnection;
  LBuf: Pointer;
  LLen: Integer;
begin
  LConnObj := AConnection as TCrossHttpConnection;
  LBuf := ABuf;
  LLen := ALen;

  while (LLen > 0) do
    LConnObj.ParseRecvData(LBuf, LLen);

  inherited LogicReceived(AConnection, ABuf, ALen);
end;

function TCrossHttpServer.Use(
  const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Use('*', '*', AMiddlewareMethod);
end;

function TCrossHttpServer.Use(
  const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Use('*', '*', AMiddlewareProc);
end;

function TCrossHttpServer.Use(const AMethod, APath: string;
  const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  FMiddlewares.AddRouter(AMethod, APath, AMiddlewareMethod);
  Result := Self;
end;

function TCrossHttpServer.Use(const AMethod, APath: string;
  const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  FMiddlewares.AddRouter(AMethod, APath, AMiddlewareProc);
  Result := Self;
end;

function TCrossHttpServer.Use(const APath: string;
  const AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Use('*', APath, AMiddlewareMethod);
end;

function TCrossHttpServer.Use(const APath: string;
  const AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Use('*', APath, AMiddlewareProc);
end;

{ TCrossHttpRequest }

constructor TCrossHttpRequest.Create(const AConnection: TCrossHttpConnection);
begin
  FConnectionObj := AConnection;
  FConnection := AConnection;
  FServer := FConnection.Owner as TCrossHttpServer;

  FHeader := THttpHeader.Create;
  FCookies := TRequestCookies.Create;
  FParams := THttpUrlParams.Create;
  FQuery := THttpUrlParams.Create;
end;

destructor TCrossHttpRequest.Destroy;
begin
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);
  FreeAndNil(FParams);
  FreeAndNil(FQuery);
  if (FBody = FRawBody) then
    FBody := nil
  else
    FreeAndNil(FBody);
  FreeAndNil(FRawBody);

  inherited;
end;

function TCrossHttpRequest.GetAccept: string;
begin
  Result := FAccept;
end;

function TCrossHttpRequest.GetAcceptEncoding: string;
begin
  Result := FAcceptEncoding;
end;

function TCrossHttpRequest.GetAcceptLanguage: string;
begin
  Result := FAcceptLanguage;
end;

function TCrossHttpRequest.GetAuthorization: string;
begin
  Result := FAuthorization;
end;

function TCrossHttpRequest.GetBody: TObject;
begin
  Result := FBody;
end;

function TCrossHttpRequest.GetRawBody: TStream;
begin
  Result := FRawBody;
end;

function TCrossHttpRequest.GetBodyType: TBodyType;
begin
  Result := FBodyType;
end;

function TCrossHttpRequest.GetConnection: ICrossHttpConnection;
begin
  Result := FConnection;
end;

function TCrossHttpRequest.GetContentEncoding: string;
begin
  Result := FContentEncoding;
end;

function TCrossHttpRequest.GetContentLength: Int64;
begin
  Result := FContentLength;
end;

function TCrossHttpRequest.GetContentType: string;
begin
  Result := FContentType;
end;

function TCrossHttpRequest.GetCookies: TRequestCookies;
begin
  Result := FCookies;
end;

function TCrossHttpRequest.GetHeader: THttpHeader;
begin
  Result := FHeader;
end;

function TCrossHttpRequest.GetHostName: string;
begin
  Result := FHostName;
end;

function TCrossHttpRequest.GetHostPort: Word;
begin
  Result := FHostPort;
end;

function TCrossHttpRequest.GetIfModifiedSince: TDateTime;
begin
  Result := FIfModifiedSince;
end;

function TCrossHttpRequest.GetIfNoneMatch: string;
begin
  Result := FIfNoneMatch;
end;

function TCrossHttpRequest.GetIfRange: string;
begin
  Result := FIfRange;
end;

function TCrossHttpRequest.GetIsChunked: Boolean;
begin
  Result := FIsChunked;
end;

function TCrossHttpRequest.CalcIsChunked: Boolean;
var
  LEncodings: TArray<string>;
begin
  // RFC 7230 §3.3.1: Transfer-Encoding 可以是逗号分隔列表, 最终编码为最后一个
  LEncodings := FTransferEncoding.Trim.Split([',']);
  if Length(LEncodings) > 0 then
    Result := TStrUtils.SameText(LEncodings[Length(LEncodings) - 1].Trim, 'chunked')
  else
    Result := False;
end;

function TCrossHttpRequest.GetIsMultiPartFormData: Boolean;
begin
  Result := TStrUtils.SameText(FContentType, TMediaType.MULTIPART_FORM_DATA);
end;

function TCrossHttpRequest.GetIsUrlEncodedFormData: Boolean;
begin
  Result := TStrUtils.SameText(FContentType, TMediaType.APPLICATION_FORM_URLENCODED_TYPE);
end;

function TCrossHttpRequest.GetKeepAlive: Boolean;
begin
  Result := FKeepAlive;
end;

function TCrossHttpRequest.GetMethod: string;
begin
  Result := FMethod;
end;

function TCrossHttpRequest.GetParams: THttpUrlParams;
begin
  Result := FParams;
end;

function TCrossHttpRequest.GetQueryText: string;
begin
  Result := FQueryText;
end;

function TCrossHttpRequest.GetPath: string;
begin
  Result := FPath;
end;

function TCrossHttpRequest.GetPathAndQuery: string;
begin
  Result := FPathAndQuery;
end;

function TCrossHttpRequest.GetPostDataSize: Int64;
begin
  Result := FPostDataSize;
end;

function TCrossHttpRequest.GetQuery: THttpUrlParams;
begin
  Result := FQuery;
end;

function TCrossHttpRequest.GetRange: string;
begin
  Result := FRange;
end;

function TCrossHttpRequest.GetRawPathAndQuery: string;
begin
  Result := FRawPathAndQuery;
end;

function TCrossHttpRequest.GetRawRequestText: string;
begin
  Result := FRawRequestText;
end;

function TCrossHttpRequest.GetReferer: string;
begin
  Result := FReferer;
end;

function TCrossHttpRequest.GetRequestBoundary: string;
begin
  Result := FRequestBoundary;
end;

function TCrossHttpRequest.GetRequestCmdLine: string;
begin
  Result := FRequestCmdLine;
end;

function TCrossHttpRequest.GetRequestConnection: string;
begin
  Result := FRequestConnection;
end;

function TCrossHttpRequest.GetSession: ISession;
begin
  Result := FSession;
end;

function TCrossHttpRequest.GetTransferEncoding: string;
begin
  Result := FTransferEncoding;
end;

function TCrossHttpRequest.GetUserAgent: string;
begin
  Result := FUserAgent;
end;

function TCrossHttpRequest.GetVersion: string;
begin
  Result := FVersion;
end;

function TCrossHttpRequest.GetXForwardedFor: string;
begin
  Result := FXForwardedFor;
end;

function TCrossHttpRequest.ParseHeader(const ADataPtr: Pointer;
  const ADataSize: Integer): Boolean;
var
  LRequestHeader, LPortStr: string;
  LCookieValues, LCLValues: TArray<string>;
  LFirstCL: string;
  I, J: Integer;
  LPortInt: Integer;
begin
  Assert(Self <> nil, 'FRequest is nil');

  // 整体包一层 try/except 保证任何畸形输入都以 Result := False 返回,
  // 不会让异常上抛到 _OnHeaderData 环外. 常见调用点如:
  //   - Substring/IndexOf 上的越界 (请求行过短、缺少空格等)
  //   - LPortStr.ToInteger 遇到非数字时抛 EConvertError
  //   - THttpHeader.Decode 内部异常
  //   - FCookies.Decode 内部异常
  // 都被这里统一归为 400 Bad Request
  try
    SetString(FRawRequestText, MarshaledAString(ADataPtr), ADataSize);

    // 拒绝包含 NUL 字节的请求 (可能导致跨编译器字符串行为差异)
    if (FRawRequestText.IndexOf(#0) >= 0) then
      Exit(False);

    I := FRawRequestText.IndexOf(#13#10);
    // 第一行是请求命令行
    // GET /home?param=123 HTTP/1.1
    FRequestCmdLine := FRawRequestText.Substring(0, I);
    // 第二行起是请求头
    LRequestHeader := FRawRequestText.Substring(I + 2);
    // 解析请求头
    FHeader.Decode(LRequestHeader);

    // 请求行必须包含三段: METHOD SP PATH SP VERSION (RFC 7230 §3.1.1)
    // 任何一段为空都不合法, 否则会出现:
    //   - FMethod=='' 导致路由匹配疑难
    //   - FVersion 含错位片段 (如 "GET") 导致 _CreateHeader 输出伪 HTTP 状态行
    // 这里在拆分前先检查两个空格的位置严格递增, 三段均非空
    I := FRequestCmdLine.IndexOf(' ');
    if (I <= 0) then Exit(False);
    J := FRequestCmdLine.IndexOf(' ', I + 1);
    if (J <= I + 1) or (J >= FRequestCmdLine.Length - 1) then Exit(False);

    // 请求方法(GET, POST, PUT, DELETE...)
    FMethod := FRequestCmdLine.Substring(0, I).ToUpper;

    // 路径及参数(/home?param=123)
    FRawPathAndQuery := FRequestCmdLine.Substring(I + 1, J - I - 1);

    // 请求的HTTP版本(HTTP/1.1)
    FVersion := FRequestCmdLine.Substring(J + 1).ToUpper;

    // 解析?key1=value1&key2=value2参数
    J := FRawPathAndQuery.IndexOf('?');
    if (J < 0) then
    begin
      FRawPath := FRawPathAndQuery;
      FRawQueryText := '';
      FQueryText := '';
    end else
    begin
      FRawPath := FRawPathAndQuery.Substring(0, J);
      FRawQueryText := FRawPathAndQuery.Substring(J + 1);
      FQueryText := TCrossHttpUtils.UrlDecode(FRawQueryText);
    end;

    FPath := TCrossHttpUtils.UrlDecode(FRawPath);
    FPathAndQuery := FPath;
    if (FQueryText <> '') then
      FPathAndQuery := FPathAndQuery + '?' + FQueryText;

    FQuery.Decode(FRawQueryText);

    // HTTP协议版本
    if (FVersion = '') then
      FVersion := 'HTTP/1.0';
    if (FVersion = 'HTTP/1.0') then
      FHttpVerNum := 10
    else
      FHttpVerNum := 11;
    FKeepAlive := (FHttpVerNum = 11);

    FContentType := FHeader[HEADER_CONTENT_TYPE];
    FRequestBoundary := '';
    J := FContentType.IndexOf(';');
    if (J >= 0) then
    begin
      // RFC 2046: 分号前后允许有任意空白, 兼容 "; boundary=" 和 ";boundary=" 两种格式
      FRequestBoundary := FContentType.Substring(J + 1).Trim;
      if FRequestBoundary.StartsWith('boundary=', True) then
        FRequestBoundary := FRequestBoundary.Substring(9);

      FContentType := FContentType.Substring(0, J).Trim;
    end;

    // RFC 7230 §3.3.2: 多个 Content-Length 值不同时必须拒绝请求
    if FHeader.GetHeaderValues(HEADER_CONTENT_LENGTH, LCLValues) and (Length(LCLValues) > 0) then
    begin
      LFirstCL := LCLValues[0].Trim;
      for I := 1 to High(LCLValues) do
        if not TStrUtils.SameText(LCLValues[I].Trim, LFirstCL) then
          Exit(False);
      FContentLength := StrToInt64Def(LFirstCL, -1);
    end else
      FContentLength := -1;

    // IPv4: 192.168.1.100:8080
    //       192.168.1.100
    // IPv6: [fc00::20:80:5:2]:8080
    //       [fc00::20:80:5:2]
    FRequestHost := FHeader[HEADER_HOST];
    LPortStr := '';

    J := FRequestHost.IndexOf(']');
    if (J >= 0) then
    begin
      FHostName := FRequestHost.Substring(1, J - 1);
      J := FRequestHost.IndexOf(':', J);
      if (J >= 0) then
        LPortStr := FRequestHost.Substring(J + 1);
    end else
    begin
      J := FRequestHost.IndexOf(':');
      if (J >= 0) then
      begin
        FHostName := FRequestHost.Substring(0, J);
        LPortStr := FRequestHost.Substring(J + 1);
      end else
        FHostName := FRequestHost;
    end;
    // RFC 7230 §5.4: Host 头中 port 必须是十进制数字. 这里用 TryStrToInt
    // 避免 ToInteger 在畸形输入 (如 "abc"、超出 Int32 范围) 时抛 EConvertError;
    // 超出 Word (0..65535) 范围亦视为非法 port, 不静默截断高位
    if (LPortStr <> '') then
    begin
      if not TryStrToInt(LPortStr, LPortInt)
        or (LPortInt < 0) or (LPortInt > High(Word)) then
        Exit(False);
      FHostPort := Word(LPortInt);
    end else
      FHostPort := GetConnection.Server.Port;

    FRequestConnection := FHeader[HEADER_CONNECTION];
    // HTTP/1.0 默认KeepAlive=False，只有显示指定了Connection: keep-alive才认为KeepAlive=True
    // HTTP/1.1 默认KeepAlive=True，只有显示指定了Connection: close才认为KeepAlive=False
    if FHttpVerNum = 10 then
      FKeepAlive := TStrUtils.SameText(FRequestConnection, 'keep-alive')
    else if TStrUtils.SameText(FRequestConnection, 'close') then
      FKeepAlive := False;

    FTransferEncoding := FHeader[HEADER_TRANSFER_ENCODING];
    FIsChunked := CalcIsChunked;
    FContentEncoding := FHeader[HEADER_CONTENT_ENCODING];
    FAccept := FHeader[HEADER_ACCEPT];
    FReferer := FHeader[HEADER_REFERER];
    FAcceptLanguage := FHeader[HEADER_ACCEPT_LANGUAGE];
    FAcceptEncoding := FHeader[HEADER_ACCEPT_ENCODING];
    FUserAgent := FHeader[HEADER_USER_AGENT];
    FAuthorization := FHeader[HEADER_AUTHORIZATION];
    // 获取并解析 Cookie 头
    // RFC 6265 建议客户端只发送一个 Cookie 头
    // 但部分代理/旧客户端可能拆分成多行，按 RFC 7230 §3.2.2 合并处理
    if FHeader.GetHeaderValues(HEADER_COOKIE, LCookieValues)
      and (Length(LCookieValues) > 0) then
    begin
      // RFC 6265 建议客户端只发送一个 Cookie 头
      // 但部分代理/旧客户端可能拆分成多行，按 RFC 7230 §3.2.2 合并处理
      if (Length(LCookieValues) = 1) then
        FRequestCookies := LCookieValues[0]
      else
        FRequestCookies := string.Join('; ', LCookieValues);
    end else
      FRequestCookies := '';
    FIfModifiedSince := TCrossHttpUtils.RFC1123_StrToDate(FHeader[HEADER_IF_MODIFIED_SINCE]);
    FIfNoneMatch := FHeader[HEADER_IF_NONE_MATCH];
    FRange := FHeader[HEADER_RANGE];
    FIfRange := FHeader[HEADER_IF_RANGE];
    FXForwardedFor:= FHeader[HEADER_X_FORWARDED_FOR];

    // 解析Cookies
    if (FRequestCookies <> '') then
    begin
      if not FCookies.Decode(FRequestCookies, True) then Exit(False);
    end else
      FCookies.Clear;

    if IsMultiPartFormData then
      FBodyType := btMultiPart
    else if IsUrlEncodedFormData then
      FBodyType := btUrlEncoded
    else
      FBodyType := btBinary;

    Result := True;
  except
    // 任何解析异常都归一为 Result := False, 由 _OnHeaderData 发 400.
    // 不记详细错误原因 (不足类型安全且可能被恶意请求刷日志),
    // 需要调试时可临时加 Logger 输出.
    on Exception do
      Result := False;
  end;
end;

{ TCrossHttpResponse }

constructor TCrossHttpResponse.Create(const AConnection: TCrossHttpConnection;
  const ARequest: ICrossHttpRequest;
  const AQueueItem: IHttpResponseQueueItem);
begin
  FConnectionObj := AConnection;
  FConnection := AConnection;
  FRequest := ARequest;
  FQueueItem := AQueueItem;
  FHeader := THttpHeader.Create;
  FCookies := TResponseCookies.Create;
  FStatusCode := 200;
end;

destructor TCrossHttpResponse.Destroy;
begin
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);
  FQueueItem := nil;
  inherited;
end;

procedure TCrossHttpResponse.Download(const AFileName: string;
  const ACallback: TCrossConnectionCallback);
begin
  Attachment(AFileName);
  SendFile(AFileName, ACallback);
end;

function TCrossHttpResponse.GetConnection: ICrossHttpConnection;
begin
  Result := FConnection;
end;

function TCrossHttpResponse.GetContentType: string;
begin
  Result := FHeader[HEADER_CONTENT_TYPE];
end;

function TCrossHttpResponse.GetCookies: TResponseCookies;
begin
  Result := FCookies;
end;

function TCrossHttpResponse.GetHeader: THttpHeader;
begin
  Result := FHeader;
end;

function TCrossHttpResponse.GetLocation: string;
begin
  Result := FHeader[HEADER_LOCATION];
end;

function TCrossHttpResponse.GetRequest: ICrossHttpRequest;
begin
  Result := FRequest;
end;

function TCrossHttpResponse.GetSent: Boolean;
begin
  Result := (AtomicCmpExchange(FSendStatus, 0, 0) > 0);
end;

function TCrossHttpResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function TCrossHttpResponse.GetStatusText: string;
begin
  Result := FStatusText;
end;

procedure TCrossHttpResponse.Json(const AJson: string;
  const ACallback: TCrossConnectionCallback);
begin
  SetContentType(TMediaType.APPLICATION_JSON_UTF8);
  Send(AJson, ACallback);
end;

procedure TCrossHttpResponse.Redirect(const AUrl: string; const ACallback: TCrossConnectionCallback);
begin
  SetLocation(AUrl);
  SendStatus(302, '', ACallback);
end;

procedure TCrossHttpResponse.Reset;
begin
  FSendStatus := 0;
  FStatusCode := 200;
  FHeader.Clear;
  FCookies.Clear;
end;

procedure TCrossHttpResponse.Attachment(const AFileName: string);
begin
  if (GetContentType = '') then
    SetContentType(TCrossHttpUtils.GetFileMIMEType(AFileName));
  FHeader[HEADER_CONTENT_DISPOSITION] := 'attachment; filename="' +
    TCrossHttpUtils.UrlEncode(ExtractFileName(AFileName)) + '"';
end;

procedure TCrossHttpResponse.Send(const ABody: Pointer; const ACount: NativeInt;
  const ACallback: TCrossConnectionCallback);
var
  LCompressType: TCompressType;
begin
  if _CheckCompress(ACount, LCompressType) then
    SendZCompress(ABody, ACount, LCompressType, ACallback)
  else
    SendNoCompress(ABody, ACount, ACallback);
end;

procedure TCrossHttpResponse.Send(const ABody; const ACount: NativeInt;
  const ACallback: TCrossConnectionCallback);
begin
  Send(@ABody, ACount, ACallback);
end;

procedure TCrossHttpResponse.Send(const ABody: TBytes;
  const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback);
var
  LBody: TBytes;
  LOffset, LCount: NativeInt;
begin
  // 增加其引用计数
  LBody := ABody;

  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(Length(ABody), LOffset, LCount);

  Send(Pointer(PByte(LBody) + LOffset), LCount,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 减少引用计数
      LBody := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.Send(const ABody: TBytes;
  const ACallback: TCrossConnectionCallback);
begin
  Send(ABody, 0, Length(ABody), ACallback);
end;

procedure TCrossHttpResponse.Send(const ABody: TStream;
  const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback);
var
  LCompressType: TCompressType;
begin
  if (ABody <> nil) and _CheckCompress(ABody.Size, LCompressType) then
    SendZCompress(ABody, AOffset, ACount, LCompressType, ACallback)
  else
    SendNoCompress(ABody, AOffset, ACount, ACallback);
end;

procedure TCrossHttpResponse.Send(const ABody: TStream;
  const ACallback: TCrossConnectionCallback);
begin
  Send(ABody, 0, 0, ACallback);
end;

procedure TCrossHttpResponse.Send(const ABody: string;
  const ACallback: TCrossConnectionCallback);
var
  LBody: TBytes;
begin
  LBody := TEncoding.UTF8.GetBytes(ABody);
  if (GetContentType = '') then
    SetContentType(TMediaType.TEXT_HTML_UTF8);

  Send(LBody, ACallback);
end;

procedure TCrossHttpResponse.SendNoCompress(
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossConnectionCallback);
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

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendFile(const AFileName: string;
  const ACallback: TCrossConnectionCallback);
var
  LStream: TStream;
  LLastModified: TDateTime;
  LRequest: TCrossHttpRequest;
  LLastModifiedStr, LETag: string;
  LRangeStr: string;
  LRangeBegin, LRangeEnd, LOffset, LCount, LFileSize: Int64;
begin
  if not FileExists(AFileName) then
  begin
    FHeader.Remove(HEADER_CONTENT_DISPOSITION);
    SendStatus(404, ACallback);
    Exit;
  end;

  if (GetContentType = '') then
    SetContentType(TCrossHttpUtils.GetFileMIMEType(AFileName));

  try
    // 根据请求头中的时间戳决定是否需要发送文件数据
    // 当请求头中的时间戳与文件时间一致时, 浏览器会自动从本地加载文件数据
    // 服务端无需发送文件数据
    LRequest := GetRequest as TCrossHttpRequest;
    LLastModified := TFileUtils.GetLastWriteTime(AFileName);

    if (LRequest.IfModifiedSince > 0) and (LRequest.IfModifiedSince >= (LLastModified - (1 / SecsPerDay))) then
    begin
      // 304不要带任何body数据, 否则部分浏览器会报告无效的RESPONSE
      SendStatus(304, '', ACallback);
      Exit;
    end;

    LLastModifiedStr := TCrossHttpUtils.RFC1123_DateToStr(LLastModified);

    LETag := '"' + TUtils.BytesToHex(THashMD5.GetHashBytes(
      ExtractFileName(AFileName) + LLastModifiedStr)) + '"';
    if (LRequest.IfNoneMatch = LETag) then
    begin
      // 304不要带任何body数据, 否则部分浏览器会报告无效的RESPONSE
      SendStatus(304, '', ACallback);
      Exit;
    end;

    LStream := TFileUtils.OpenRead(AFileName, fmShareDenyNone);
  except
    on e: Exception do
    begin
      FHeader.Remove(HEADER_CONTENT_DISPOSITION);
      SendStatus(404, TStrUtils.Format('%s, %s', [e.ClassName, e.Message]), ACallback);
      Exit;
    end;
  end;

  LFileSize := LStream.Size;

  // 在响应头中加入文件时间戳
  // 浏览器会根据该时间戳决定是否从本地缓存中直接加载数据
  FHeader[HEADER_LAST_MODIFIED] := LLastModifiedStr;
  FHeader[HEADER_ETAG] := LETag;

  // 告诉浏览器支持分块传输
  FHeader[HEADER_ACCEPT_RANGES] := 'bytes';

  // Range 请求处理 (RFC 7233 §3.1)
  // 仅当 Range 头存在且 If-Range 校验通过 (无 If-Range 或 If-Range == ETag) 时才走分块逻辑.
  // If-Range 不匹配时, RFC 7233 §3.2 要求回退为完整 200 响应.
  LRangeStr := LRequest.Range;
  if (LRangeStr <> '')
    and ((LRequest.IfRange = '') or (LRequest.IfRange = LETag)) then
  begin
    if not TCrossHttpUtils.ParseSingleByteRange(LRangeStr, LFileSize, LRangeBegin, LRangeEnd) then
    begin
      // 不可满足的 Range -> 416 Range Not Satisfiable (RFC 7233 §4.4)
      // 必须返回 Content-Range: bytes */<size> 告知客户端实际资源大小.
      FreeAndNil(LStream);
      FHeader.Remove(HEADER_CONTENT_DISPOSITION);
      FHeader[HEADER_CONTENT_RANGE] := TStrUtils.Format('bytes */%d', [LFileSize]);
      SendStatus(416, ACallback);
      Exit;
    end;

    LOffset := LRangeBegin;
    LCount := LRangeEnd - LRangeBegin + 1;

    // 返回分块信息
    // Content-Range: bytes <start>-<end>/<size>
    FHeader[HEADER_CONTENT_RANGE] := TStrUtils.Format('bytes %d-%d/%d',
      [LRangeBegin, LRangeEnd, LFileSize]);

    // 断点续传需要返回206状态码, 而不是200
    FStatusCode := 206;
  end else
  begin
    LOffset := 0;
    LCount := LFileSize;
  end;

  // 206 Range 响应禁止压缩：Content-Range 描述的是原始字节偏移，
  // 压缩后字节与范围不对应，会导致断点续传客户端数据错乱 (RFC 7233)
  SendNoCompress(LStream, LOffset, LCount,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      FreeAndNil(LStream);

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SetContentType(const Value: string);
begin
  FHeader[HEADER_CONTENT_TYPE] := Value;
end;

procedure TCrossHttpResponse.SetLocation(const Value: string);
begin
  FHeader[HEADER_LOCATION] := Value;
end;

procedure TCrossHttpResponse.SetStatusCode(Value: Integer);
begin
  FStatusCode := Value;
end;

procedure TCrossHttpResponse.SetStatusText(const Value: string);
begin
  FStatusText := Value;
end;

function TCrossHttpResponse._CheckCompress(const ABodySize: Int64;
  out ACompressType: TCompressType): Boolean;
var
  LContType, LRequestAcceptEncoding, LEnc, LQPart: string;
  LServer: ICrossHttpServer;
  LEncodings: TArray<string>;
  I, LQSep: Integer;
  LGzipQ, LDeflateQ, LBestQ: Double;
begin
  LContType := GetContentType;
  LServer := GetConnection.Server;

  if Assigned(LServer)
    and LServer.Compressible
    and (ABodySize > 0)
    and ((LServer.MinCompressSize <= 0) or (ABodySize >= LServer.MinCompressSize))
    and ((Pos('text/', LContType.ToLower) > 0)
      or (Pos('application/json', LContType.ToLower) > 0)
      or (Pos('javascript', LContType.ToLower) > 0)
      or (Pos('xml', LContType.ToLower) > 0)
    ) then
  begin
    LRequestAcceptEncoding := GetRequest.AcceptEncoding;

    // 按 q-value 排序选最优编码 (RFC 7231 §5.3.4).
    // q 值越高优先级越高, 缺省 q=1.0; q=0 表示明确拒绝.
    LEncodings := LRequestAcceptEncoding.Split([',']);
    begin
      LGzipQ := 0;
      LDeflateQ := 0;
      for I := 0 to High(LEncodings) do
      begin
        LEnc := LEncodings[I].Trim;
        LQSep := LEnc.IndexOf(';');
        LBestQ := 1.0;
        if LQSep >= 0 then
        begin
          LQPart := LEnc.Substring(LQSep + 1).Trim.ToLower;
          LEnc := LEnc.Substring(0, LQSep).Trim;
          if LQPart.StartsWith('q=') then
            LBestQ := StrToFloatDef(Copy(LQPart, 3, MaxInt), 0);
          if LBestQ <= 0 then
            Continue;
        end;
        if TStrUtils.SameText(LEnc, 'gzip') and (LBestQ > LGzipQ) then
          LGzipQ := LBestQ
        else if TStrUtils.SameText(LEnc, 'deflate') and (LBestQ > LDeflateQ) then
          LDeflateQ := LBestQ;
      end;
      // 优先 gzip (服务器普遍偏好); 仅当 deflate q 严格更高时选 deflate
      if (LGzipQ > 0) and (LGzipQ >= LDeflateQ) then
      begin
        ACompressType := ctGZip;
        Exit(True);
      end;
      if LDeflateQ > 0 then
      begin
        ACompressType := ctDeflate;
        Exit(True);
      end;
    end;
  end;

  ACompressType := ctNone;
  Result := False;
end;

function TCrossHttpResponse._GetMemoryStreamPointer(const AStream: TStream;
  const AOffset, ACount: Int64; out P: PByte; out LSize: Int64): Boolean;
begin
  if (AStream is TCustomMemoryStream) then
  begin
    P := PByte(TCustomMemoryStream(AStream).Memory) + AOffset;
    LSize := ACount;
    Exit(True);
  end;
  Result := False;
end;

function TCrossHttpResponse._CreateHeader(const ABodySize: Int64;
  AChunked: Boolean): TBytes;
var
  LHeaderStr, LStatusText, LHttpVersion: string;
  LCookie: TResponseCookie;
begin
  if (GetContentType = '') then
    SetContentType(TMediaType.APPLICATION_OCTET_STREAM);
  if (FHeader[HEADER_CONNECTION] = '') then
  begin
    if (FStatusCode >= 400) or (not FRequest.KeepAlive) then
      FHeader[HEADER_CONNECTION] := 'close'
    else
      FHeader[HEADER_CONNECTION] := 'keep-alive';
  end;

  if (FStatusCode = 204) or (FStatusCode = 304) then
  begin
    FHeader.Remove(HEADER_CONTENT_LENGTH);
    FHeader.Remove(HEADER_TRANSFER_ENCODING);
  end
  else if AChunked then
  begin
    FHeader[HEADER_TRANSFER_ENCODING] := 'chunked';
    FHeader.Remove(HEADER_CONTENT_LENGTH);
  end else
  begin
    FHeader[HEADER_CONTENT_LENGTH] := ABodySize.ToString;
    FHeader.Remove(HEADER_TRANSFER_ENCODING);
  end;

  if (FHeader[HEADER_CROSS_HTTP_SERVER] = '') then
    FHeader[HEADER_CROSS_HTTP_SERVER] := CROSS_HTTP_SERVER_NAME;

  if (FStatusText <> '') then
  begin
    if TCrossHttpUtils.IsValidHeaderValue(FStatusText) then
      LStatusText := FStatusText
    else
    begin
      _Log('_CreateHeader: FStatusText contains invalid chars, falling back to default');
      LStatusText := TCrossHttpUtils.GetHttpStatusText(FStatusCode);
    end;
  end else
    LStatusText := TCrossHttpUtils.GetHttpStatusText(FStatusCode);

  // Parser 在 psHeader 阶段早失败时, ParseHeader 尚未运行, FRequest.Version 为空.
  // 必须回退到 'HTTP/1.1', 否则状态行成 ' 400 Bad Request' (缺版本前缀, 客户端无法识别).
  LHttpVersion := FRequest.Version;
  if (LHttpVersion = '') then
    LHttpVersion := 'HTTP/1.1';
  LHeaderStr := LHttpVersion + ' ' + FStatusCode.ToString + ' ' +
    LStatusText + #13#10;

  for LCookie in FCookies do
  begin
    try
      LHeaderStr := LHeaderStr + HEADER_SETCOOKIE + ': ' + LCookie.Encode + #13#10;
    except
      on E: Exception do
      begin
        _Log('TCrossHttpResponse._CreateHeader: skip invalid cookie: %s', [E.Message]);
        Continue;
      end;
    end;
  end;

  LHeaderStr := LHeaderStr + FHeader.Encode;

  Result := TEncoding.ASCII.GetBytes(LHeaderStr);
end;

procedure TCrossHttpResponse._Send(const ASource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossConnectionCallback);
begin
  // 用 AtomicCmpExchange 抢首次发送权限: 如果已有 Send 调用, 直接拒绝.
  // 防止两个 Send 之间的 Source/Callback 覆盖导致第一个 callback 永远不触发.
  if AtomicCmpExchange(FSendStatus, 1, 0) <> 0 then
  begin
    if Assigned(ACallback) then
      ACallback(FConnection, False);
    Exit;
  end;

  if (FConnectionObj = nil) or (FQueueItem = nil) then
  begin
    if Assigned(ACallback) then
      ACallback(FConnection, False);
    Exit;
  end;

  FConnectionObj._QueueResponseReady(FQueueItem, ASource, ACallback);
end;

procedure TCrossHttpResponse._Send(const AHeaderSource,
  ABodySource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossConnectionCallback);
var
  LHeaderDone: Boolean;
begin
  // HEAD 请求不应包含响应体 (RFC 7231 §4.3.2)
  if (FRequest.Method = 'HEAD') then
  begin
    _Send(AHeaderSource, ACallback);
    Exit;
  end;

  LHeaderDone := False;

  _Send(
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      if not LHeaderDone then
      begin
        LHeaderDone := True;
        Result := Assigned(AHeaderSource) and AHeaderSource(AData, ACount);
      end else
      begin
        Result := Assigned(ABodySource) and ABodySource(AData, ACount);
      end;
    end,
    ACallback);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody: Pointer;
  const ACount: NativeInt; const ACallback: TCrossConnectionCallback);
{
HTTP头\r\n\r\n
内容
}
var
  P: PByte;
  LSize: NativeInt;
  LHeaderBytes: TBytes;
begin
  P := ABody;
  LSize := ACount;

  _Send(
    // HEADER
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      LHeaderBytes := _CreateHeader(LSize, False);

      AData^ := @LHeaderBytes[0];
      ACount^ := Length(LHeaderBytes);

      Result := (ACount^ > 0);
    end,
    // BODY
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      AData^ := P;
      ACount^ := Min(LSize, SND_BUF_SIZE);
      Result := (ACount^ > 0);

      if (LSize > SND_BUF_SIZE) then
      begin
        Inc(P, SND_BUF_SIZE);
        Dec(LSize, SND_BUF_SIZE);
      end else
      begin
        LSize := 0;
        P := nil;
      end;
    end,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LHeaderBytes := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody; const ACount: NativeInt;
  const ACallback: TCrossConnectionCallback);
begin
  SendNoCompress(@ABody, ACount, ACallback);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody: TBytes;
  const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback);
var
  LBody: TBytes;
  LOffset, LCount: NativeInt;
begin
  // 增加其引用计数
  LBody := ABody;

  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(Length(ABody), LOffset, LCount);

  SendNoCompress(Pointer(PByte(LBody) + LOffset), LCount,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 减少引用计数
      LBody := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody: TBytes;
  const ACallback: TCrossConnectionCallback);
begin
  SendNoCompress(ABody, 0, Length(ABody), ACallback);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody: TStream;
  const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback);
var
  LOffset, LCount: Int64;
  LBody: TStream;
  LHeaderBytes, LBuffer: TBytes;
  LP: PByte;
  LSize: Int64;
begin
  if (ABody = nil) then
  begin
    SendNoCompress(nil, 0, ACallback);
    Exit;
  end;

  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(ABody.Size, LOffset, LCount);

  if _GetMemoryStreamPointer(ABody, LOffset, LCount, LP, LSize) then
  begin
    SendNoCompress(LP^, LSize, ACallback);
    Exit;
  end;

  LBody := ABody;
  LBody.Position := LOffset;

  SetLength(LBuffer, SND_BUF_SIZE);

  _Send(
    // HEADER
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      LHeaderBytes := _CreateHeader(LCount, False);

      AData^ := @LHeaderBytes[0];
      ACount^ := Length(LHeaderBytes);

      Result := (ACount^ > 0);
    end,
    // BODY
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      if (LCount <= 0) then Exit(False);

      AData^ := @LBuffer[0];
      ACount^ := LBody.Read(LBuffer[0], Min(LCount, SND_BUF_SIZE));

      Result := (ACount^ > 0);

      if Result then
        Dec(LCount, ACount^);
    end,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LHeaderBytes := nil;
      LBuffer := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody: TStream;
  const ACallback: TCrossConnectionCallback);
begin
  SendNoCompress(ABody, 0, 0, ACallback);
end;

procedure TCrossHttpResponse.SendNoCompress(const ABody: string;
  const ACallback: TCrossConnectionCallback);
var
  LBody: TBytes;
begin
  LBody := TEncoding.UTF8.GetBytes(ABody);
  if (GetContentType = '') then
    SetContentType(TMediaType.TEXT_HTML_UTF8);

  SendNoCompress(LBody, ACallback);
end;

procedure TCrossHttpResponse.SendStatus(const AStatusCode: Integer;
  const ADescription: string; const ACallback: TCrossConnectionCallback);
begin
  SetStatusCode(AStatusCode);
  Send(ADescription, ACallback);
end;

procedure TCrossHttpResponse.SendStatus(const AStatusCode: Integer;
  const ACallback: TCrossConnectionCallback);
begin
  SendStatus(AStatusCode, TCrossHttpUtils.GetHttpStatusText(AStatusCode), ACallback);
end;

procedure TCrossHttpResponse.SendZCompress(
  const AChunkSource: TCrossHttpChunkDataFunc;
  const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback);
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
  LZError: Boolean;
begin
  if (ACompressType = ctNone) then
  begin
    SendNoCompress(AChunkSource, ACallback);
    Exit;
  end;

  // 返回压缩方式
  FHeader[HEADER_CONTENT_ENCODING] := ZLIB_CONTENT_ENCODING[ACompressType];

  // 明确告知缓存服务器按照 Accept-Encoding 字段的内容, 分别缓存不同的版本
  FHeader[HEADER_VARY] := HEADER_ACCEPT_ENCODING;

  SetLength(LBuffer, SND_BUF_SIZE);

  FillChar(LZStream, SizeOf(TZStreamRec), 0);
  LZResult := Z_OK;
  LZFlush := Z_NO_FLUSH;

  if (deflateInit2(LZStream, Z_DEFAULT_COMPRESSION,
    Z_DEFLATED, ZLIB_WINDOW_BITS[ACompressType], 8, Z_DEFAULT_STRATEGY) <> Z_OK) then
  begin
    SetStatusCode(500);
    if (FQueueItem <> nil) then
      FQueueItem.StatusCode := 500;
    // 走正常队列流程: _Send → _QueueResponseReady → _SendQueueItem
    // → body 为空立即返回 False → _FinishQueueItem (配合 StatusCode>=500 触发 Disconnect) → ACallback 在锁外异步通知
    SendNoCompress(nil, 0, ACallback);
    Exit;
  end;

  LZError := False;

  SendNoCompress(
    // CHUNK
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
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
          ACount^ := 0;
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
          LZError := True;  // 标记压缩错误，回调中将向调用方传递 False
          // 标记 500 以触发 _FinishQueueItem 中 LNeedDisconnect 断开连接
          if (FQueueItem <> nil) then
            FQueueItem.StatusCode := 500;
          AData^ := nil;
          ACount^ := 0;
          Exit(False);
        end;

        // 已压缩完成的数据大小
        LOutSize := SND_BUF_SIZE - LZStream.avail_out;
      until (LOutSize > 0);

      // 已压缩的数据
      AData^ := @LBuffer[0];
      ACount^ := LOutSize;

      Result := (ACount^ > 0);
    end,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LBuffer := nil;
      deflateEnd(LZStream);

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess and not LZError);
    end);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody: Pointer;
  const ACount: NativeInt; const ACompressType: TCompressType;
  const ACallback: TCrossConnectionCallback);
var
  P: PByte;
  LSize: NativeInt;
begin
  P := ABody;
  LSize := ACount;

  SendZCompress(
    // CHUNK
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      AData^ := P;
      ACount^ := Min(LSize, SND_BUF_SIZE);
      Result := (ACount^ > 0);

      if (LSize > SND_BUF_SIZE) then
      begin
        Inc(P, SND_BUF_SIZE);
        Dec(LSize, SND_BUF_SIZE);
      end else
      begin
        LSize := 0;
        P := nil;
      end;
    end,
    ACompressType,
    ACallback);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody; const ACount: NativeInt;
  const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback);
begin
  SendZCompress(@ABody, ACount, ACompressType, ACallback);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody: TBytes;
  const AOffset, ACount: NativeInt; const ACompressType: TCompressType;
  const ACallback: TCrossConnectionCallback);
var
  LBody: TBytes;
  LOffset, LCount: NativeInt;
begin
  // 增加其引用计数
  LBody := ABody;

  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(Length(ABody), LOffset, LCount);

  SendZCompress(Pointer(PByte(LBody) + LOffset), LCount, ACompressType,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 减少引用计数
      LBody := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody: TBytes;
  const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback);
begin
  SendZCompress(ABody, 0, Length(ABody), ACompressType, ACallback);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody: TStream;
  const AOffset, ACount: Int64; const ACompressType: TCompressType;
  const ACallback: TCrossConnectionCallback);
var
  LOffset, LCount: Int64;
  LBody: TStream;
  LBuffer: TBytes;
  LP: PByte;
  LSize: Int64;
begin
  if (ABody = nil) then
  begin
    SendNoCompress(nil, 0, ACallback);
    Exit;
  end;

  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(ABody.Size, LOffset, LCount);

  if _GetMemoryStreamPointer(ABody, LOffset, LCount, LP, LSize) then
  begin
    SendZCompress(LP^, LSize, ACompressType, ACallback);
    Exit;
  end;

  LBody := ABody;
  LBody.Position := LOffset;

  SetLength(LBuffer, SND_BUF_SIZE);

  SendZCompress(
    // CHUNK
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      if (LCount <= 0) then Exit(False);

      ACount^ := LBody.Read(LBuffer[0], Min(LCount, SND_BUF_SIZE));
      AData^ := @LBuffer[0];

      Result := (ACount^ > 0);

      if Result then
        Dec(LCount, ACount^);
    end,
    ACompressType,
    // CALLBACK
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      LBuffer := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody: TStream;
  const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback);
begin
  SendZCompress(ABody, 0, 0, ACompressType, ACallback);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody: string;
  const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback);
var
  LBody: TBytes;
begin
  LBody := TEncoding.UTF8.GetBytes(ABody);
  if (GetContentType = '') then
    SetContentType(TMediaType.TEXT_HTML_UTF8);

  SendZCompress(LBody, ACompressType, ACallback);
end;

end.
