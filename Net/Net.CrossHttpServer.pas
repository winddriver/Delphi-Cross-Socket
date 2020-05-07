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

{
  Linux下需要安装zlib1g-dev开发包
  sudo apt-get install zlib1g-dev
}

interface

uses
  System.Classes,
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  System.NetEncoding,
  System.RegularExpressionsCore,
  System.RegularExpressionsConsts,
  System.ZLib,
  System.Hash,
  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossServer,
  {$IFDEF __CROSS_SSL__}
    Net.CrossSslSocket,
    Net.CrossSslServer,
  {$ENDIF}
  Net.CrossHttpParams,
  Net.CrossHttpUtils,
  Utils.Logger;

const
  CROSS_HTTP_SERVER_NAME = 'CrossHttpServer/2.0';
  MIN_COMPRESS_SIZE = 512;

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

  /// <summary>
  ///   HTTP连接接口
  /// </summary>
  ICrossHttpConnection = interface(ICrossConnection)
  ['{72E9AC44-958C-4C6F-8769-02EA5EC3E9A8}']
    function GetRequest: ICrossHttpRequest;
    function GetResponse: ICrossHttpResponse;
    function GetServer: ICrossHttpServer;

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
    function GetRawPathAndParams: string;
    function GetMethod: string;
    function GetPath: string;
    function GetVersion: string;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
    function GetSession: ISession;
    function GetParams: THttpUrlParams;
    function GetQuery: THttpUrlParams;
    function GetBody: TObject;
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
    property RawPathAndParams: string read GetRawPathAndParams;

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
    ///       CONNECT <br />
    ///     </item>
    ///     <item>
    ///       PATCH <br />
    ///     </item>
    ///     <item>
    ///       COPY <br />
    ///     </item>
    ///     <item>
    ///       LINK <br />
    ///     </item>
    ///     <item>
    ///       UNLINK <br />
    ///     </item>
    ///     <item>
    ///       PURGE <br />
    ///     </item>
    ///     <item>
    ///       LOCK <br />
    ///     </item>
    ///     <item>
    ///       UNLOCK <br />
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
    ///   Body数据, 通过检查BodyType可以知道数据类型:
    ///   <list type="bullet">
    ///     <item>
    ///       btNone(nil)
    ///     </item>
    ///     <item>
    ///       btUrlEncoded(THttpUrlParams)
    ///     </item>
    ///     <item>
    ///       btMultiPart(THttpMultiPartFormData)
    ///     </item>
    ///     <item>
    ///       btBinary(TBytesStream)
    ///     </item>
    ///   </list>
    /// </summary>
    property Body: TObject read GetBody;

    /// <summary>
    ///   Body的类型,
    ///   <list type="bullet">
    ///     <item>
    ///       btNone(nil)
    ///     </item>
    ///     <item>
    ///       btUrlEncoded(THttpUrlParams)
    ///     </item>
    ///     <item>
    ///       btMultiPart(THttpMultiPartFormData)
    ///     </item>
    ///     <item>
    ///       btBinary(TBytesStream)
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
  ///   压缩类型
  /// </summary>
  TCompressType = (ctGZip, ctDeflate);

  /// <summary>
  ///   提供块数据的匿名函数
  /// </summary>
  TCrossHttpChunkDataFunc = reference to function(const AData: PPointer; const ACount: PNativeInt): Boolean;

  /// <summary>
  ///   HTTP应答接口
  /// </summary>
  ICrossHttpResponse = interface
  ['{5E15C20F-E221-4B10-90FC-222173A6F3E8}']
    function GetConnection: ICrossHttpConnection;
    function GetRequest: ICrossHttpRequest;
    function GetStatusCode: Integer;
    procedure SetStatusCode(Value: Integer);
    function GetContentType: string;
    procedure SetContentType(const Value: string);
    function GetLocation: string;
    procedure SetLocation(const Value: string);
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetSent: Boolean;

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
    ///   本方法实现了一边压缩一边发送数据, 所以可以支持无限大的分块数据的压缩发送, 而不用占用太多的内存和CPU <br /><br />
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
    ///   回调函数 <br />
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
    ///   回调函数 <br />
    /// </param>
    procedure Send(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABody">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数 <br />
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
    ///   回调函数 <br />
    /// </param>
    procedure Send(const ABody: string; const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送Json字符串数据
    /// </summary>
    /// <param name="AJson">
    ///   Json字符串数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数 <br />
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

  /// <summary>
  ///   路由接口
  /// </summary>
  ICrossHttpRouter = interface
  ['{2B095450-6A5D-450F-8DCD-6911526C733F}']
    function GetMethod: string;
    function GetPath: string;
    function IsMatch(const ARequest: ICrossHttpRequest): Boolean;
    procedure Execute(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean);

    property Method: string read GetMethod;
    property Path: string read GetPath;
  end;
  TCrossHttpRouters = TList<ICrossHttpRouter>;

  TCrossHttpRouterProc = reference to procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse);
  TCrossHttpRouterMethod = procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse) of object;
  TCrossHttpRouterProc2 = reference to procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean);
  TCrossHttpRouterMethod2 = procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean) of object;

  TCrossHttpConnEvent = procedure(const Sender: TObject; const AConnection: ICrossHttpConnection) of object;
  TCrossHttpRequestEvent = procedure(const Sender: TObject; const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean) of object;
  TCrossHttpRequestExceptionEvent = procedure(const Sender: TObject; const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; const AException: Exception) of object;
  TCrossHttpDataEvent = procedure(const Sender: TObject; const AClient: ICrossHttpConnection; const ABuf: Pointer; const ALen: Integer) of object;

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
  ///     Post(APath, ARouter) <br />
  ///   </para>
  ///   <para>
  ///     Delete(APath, ARouter) <br />
  ///   </para>
  ///   <para>
  ///     All(APath, ARouter) <br />
  ///   </para>
  ///   <para>
  ///     其中AMehod和APath都支持正则表达式, ARouter可以是一个对象方法也可以是匿名函数 <br />
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
  ICrossHttpServer = interface({$IFDEF __CROSS_SSL__}ICrossSslServer{$ELSE}ICrossServer{$ENDIF})
  ['{224D16AA-317C-435E-9C2E-92868E578DB3}']
    function GetStoragePath: string;
    function GetAutoDeleteFiles: Boolean;
    function GetMaxHeaderSize: Int64;
    function GetMaxPostDataSize: Int64;
    function GetCompressible: Boolean;
    function GetMinCompressSize: Int64;
    function GetSessions: ISessions;
    function GetSessionIDCookieName: string;
    function GetOnRequest: TCrossHttpRequestEvent;
    function GetOnRequestException: TCrossHttpRequestExceptionEvent;
    function GetOnPostDataBegin: TCrossHttpConnEvent;
    function GetOnPostData: TCrossHttpDataEvent;
    function GetOnPostDataEnd: TCrossHttpConnEvent;

    procedure SetStoragePath(const Value: string);
    procedure SetAutoDeleteFiles(const Value: Boolean);
    procedure SetMaxHeaderSize(const Value: Int64);
    procedure SetMaxPostDataSize(const Value: Int64);
    procedure SetCompressible(const Value: Boolean);
    procedure SetMinCompressSize(const Value: Int64);
    procedure SetSessions(const Value: ISessions);
    procedure SetSessionIDCookieName(const Value: string);
    procedure SetOnRequest(const Value: TCrossHttpRequestEvent);
    procedure SetOnRequestException(const Value: TCrossHttpRequestExceptionEvent);
    procedure SetOnPostDataBegin(const Value: TCrossHttpConnEvent);
    procedure SetOnPostData(const Value: TCrossHttpDataEvent);
    procedure SetOnPostDataEnd(const Value: TCrossHttpConnEvent);

    /// <summary>
    ///   创建路由对象
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="ARouterProc">
    ///   路由匿名函数
    /// </param>
    /// <param name="ARouterMethod">
    ///   路由方法
    /// </param>
    /// <param name="ARouterProc2">
    ///   路由匿名函数
    /// </param>
    /// <param name="ARouterMethod2">
    ///   路由方法
    /// </param>
    function CreateRouter(const AMethod, APath: string;
      ARouterProc: TCrossHttpRouterProc; ARouterMethod: TCrossHttpRouterMethod;
      ARouterProc2: TCrossHttpRouterProc2; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpRouter;

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
    function Use(const AMethod, APath: string;
      AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareProc2">
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
      AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

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
    ///   中间件处理匿名方法, 执行完处理方法之后还会继续执行后续匹配的中间件及路由
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
      AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareMethod2">
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
      AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
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
    function Use(const APath: string;
      AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareProc2">
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
      AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareMethod">
    ///   中间件处理匿名方法, 执行完处理方法之后还会继续执行后续匹配的中间件及路由
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
      AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    /// <summary>
    ///   注册中间件
    /// </summary>
    /// <param name="APath">
    ///   请求路径
    /// </param>
    /// <param name="AMiddlewareMethod2">
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
      AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

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
    function Use(AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Use(AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

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
    function Use(AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Use(AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册路由(请求处理函数)
    /// </summary>
    /// <param name="AMethod">
    ///   请求方式, GET/POST/PUT/DELETE等, 支持正则表达式, * 表示处理全部请求方式
    /// </param>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Route(const AMethod, APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Route(const AMethod, APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

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
    function Route(const AMethod, APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Route(const AMethod, APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册GET路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Get(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Get(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册GET路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Get(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Get(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册PUT路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Put(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Put(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册PUT路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Put(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Put(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

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
    function Post(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Post(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册POST路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Post(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Post(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    /// <summary>
    ///   注册DELETE路由(请求处理函数)
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 支持正则表达式, * 表示处理全部请求路径,<br />例如:
    ///   /path/:param1/:param2(\d+)|/path/:param <br />
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
    function Delete(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Delete(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

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
    function Delete(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Delete(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

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
    function All(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function All(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

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
    function All(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function All(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

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
    function ClearRouter: ICrossHttpServer;

    /// <summary>
    ///   锁定并返回路由列表
    /// </summary>
    function LockRouters: TCrossHttpRouters;

    /// <summary>
    ///   解锁路由列表
    /// </summary>
    procedure UnlockRouters;

    /// <summary>
    ///   锁定并返回中间件列表
    /// </summary>
    function LockMiddlewares: TCrossHttpRouters;

    /// <summary>
    ///   解锁中间件列表
    /// </summary>
    procedure UnlockMiddlewares;

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

    property OnRequest: TCrossHttpRequestEvent read GetOnRequest write SetOnRequest;
    property OnRequestException: TCrossHttpRequestExceptionEvent read GetOnRequestException write SetOnRequestException;
    property OnPostDataBegin: TCrossHttpConnEvent read GetOnPostDataBegin write SetOnPostDataBegin;
    property OnPostData: TCrossHttpDataEvent read GetOnPostData write SetOnPostData;
    property OnPostDataEnd: TCrossHttpConnEvent read GetOnPostDataEnd write SetOnPostDataEnd;
  end;

  TCrossHttpConnection = class({$IFDEF __CROSS_SSL__}TCrossSslConnection{$ELSE}TCrossConnection{$ENDIF}, ICrossHttpConnection)
  private
    FRequest: ICrossHttpRequest;
    FResponse: ICrossHttpResponse;

    function GetRequest: ICrossHttpRequest;
    function GetResponse: ICrossHttpResponse;
    function GetServer: ICrossHttpServer;
  public
    constructor Create(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType); override;

    property Request: ICrossHttpRequest read GetRequest;
    property Response: ICrossHttpResponse read GetResponse;
    property Server: ICrossHttpServer read GetServer;
  end;

  TCrossHttpRequest = class(TInterfacedObject, ICrossHttpRequest)
  private
    function GetConnection: ICrossHttpConnection;
    function GetRawRequestText: string;
    function GetRawPathAndParams: string;
    function GetMethod: string;
    function GetPath: string;
    function GetVersion: string;
    function GetHeader: THttpHeader;
    function GetCookies: TRequestCookies;
    function GetSession: ISession;
    function GetParams: THttpUrlParams;
    function GetQuery: THttpUrlParams;
    function GetBody: TObject;
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
  private type
    TCrossHttpParseState = (psHeader, psPostData, psChunkSize, psChunkData, psChunkEnd, psDone);
  private
    FParseState: TCrossHttpParseState;
    CR, LF: Integer;
    FChunkSizeStream: TBytesStream;
    FChunkSize, FChunkLeftSize: Integer;

    FRawRequest: TBytesStream;
    FRawRequestText: string;
    FMethod, FPath, FVersion: string;
    FRawPath, FRawParamsText, FRawPathAndParams: string;
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
  protected
    function ParseRequestData: Boolean; virtual;
  private
    // Request 是 Connection 的子对象, 它的生命周期跟随 Connection
    // 这里使用弱引用, 不增加 Connection 的引用计数, 避免循环引用造成接口对象无法自动释放
    [unsafe]FConnection: ICrossHttpConnection;
    FHeader: THttpHeader;
    FCookies: TRequestCookies;
    FSession: ISession;
    FParams: THttpUrlParams;
    FQuery: THttpUrlParams;
    FBody: TObject;
    FBodyType: TBodyType;
  public
    constructor Create(AConnection: ICrossHttpConnection);
    destructor Destroy; override;

    procedure Reset;

    property Connection: ICrossHttpConnection read GetConnection;
    property RawRequestText: string read GetRawRequestText;
    property RawPathAndParams: string read GetRawPathAndParams;
    property Method: string read GetMethod;
    property Path: string read GetPath;
    property Version: string read GetVersion;
    property Header: THttpHeader read GetHeader;
    property Cookies: TRequestCookies read GetCookies;
    property Session: ISession read GetSession;
    property Params: THttpUrlParams read GetParams;
    property Query: THttpUrlParams read GetQuery;
    property Body: TObject read GetBody;
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
    // Response 是 Connection 的子对象, 它的生命周期跟随 Connection
    // 这里使用弱引用, 不增加 Connection 的引用计数, 避免循环引用造成接口对象无法自动释放
    [unsafe]FConnection: ICrossHttpConnection;
    FStatusCode: Integer;
    FHeader: THttpHeader;
    FCookies: TResponseCookies;
    FSendStatus: Integer;

    procedure Reset;

    function GetConnection: ICrossHttpConnection;
    function GetRequest: ICrossHttpRequest;
    function GetStatusCode: Integer;
    procedure SetStatusCode(Value: Integer);
    function GetContentType: string;
    procedure SetContentType(const Value: string);
    function GetLocation: string;
    procedure SetLocation(const Value: string);
    function GetHeader: THttpHeader;
    function GetCookies: TResponseCookies;
    function GetSent: Boolean;

    function _CreateHeader(const ABodySize: Int64; AChunked: Boolean): TBytes;

    {$region '内部: 基础发送方法'}
    procedure _Send(const ASource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure _Send(const AHeaderSource, ABodySource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;
    {$endregion}

    function _CheckCompress(const ABodySize: Int64; var ACompressType: TCompressType): Boolean;
    procedure _AdjustOffsetCount(const ABodySize: NativeInt; var AOffset, ACount: NativeInt); overload;
    procedure _AdjustOffsetCount(const ABodySize: Int64; var AOffset, ACount: Int64); overload;

    {$region '压缩发送'}
    procedure SendZCompress(const AChunkSource: TCrossHttpChunkDataFunc; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody; const ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: TBytes; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: TStream; const AOffset, ACount: Int64; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: TStream; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendZCompress(const ABody: string; const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback = nil); overload;
    {$endregion}

    {$region '不压缩发送'}
    procedure SendNoCompress(const AChunkSource: TCrossHttpChunkDataFunc; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: TBytes; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: TStream; const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: TStream; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendNoCompress(const ABody: string; const ACallback: TCrossConnectionCallback = nil); overload;
    {$endregion}

    {$region '常规方法'}
    procedure Send(const ABody; const ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody: TBytes; const AOffset, ACount: NativeInt; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody: TBytes; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody: TStream; const AOffset, ACount: Int64; const ACallback: TCrossConnectionCallback = nil); overload;
    procedure Send(const ABody: TStream; const ACallback: TCrossConnectionCallback = nil); overload;
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
  public
    constructor Create(AConnection: ICrossHttpConnection);
    destructor Destroy; override;
  end;

  TCrossHttpRouter = class(TInterfacedObject, ICrossHttpRouter)
  private
    FMethod, FPath: string;
    FRouterProc: TCrossHttpRouterProc;
    FRouterMethod: TCrossHttpRouterMethod;
    FRouterProc2: TCrossHttpRouterProc2;
    FRouterMethod2: TCrossHttpRouterMethod2;
    FMethodPattern, FPathPattern: string;
    FPathParamKeys: TArray<string>;
    FMethodRegEx, FPathRegEx: TPerlRegEx; // 直接使用TPerlRegEx比使用TRegEx速度快1倍
    FRegExLock: TObject;

    function MakeMethodPattern(const AMethod: string): string;
    function MakePathPattern(const APath: string; var AKeys: TArray<string>): string;
    procedure RemakePattern;

    function GetMethod: string;
    function GetPath: string;
  public
    constructor Create(const AMethod, APath: string;
      ARouterProc: TCrossHttpRouterProc;
      ARouterMethod: TCrossHttpRouterMethod;
      ARouterProc2: TCrossHttpRouterProc2;
      ARouterMethod2: TCrossHttpRouterMethod2);
    destructor Destroy; override;

    function IsMatch(const ARequest: ICrossHttpRequest): Boolean;
    procedure Execute(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean);
  end;

  TCrossHttpServer = class({$IFDEF __CROSS_SSL__}TCrossSslServer{$ELSE}TCrossServer{$ENDIF}, ICrossHttpServer)
  private const
    HTTP_METHOD_COUNT = 16;
    HTTP_METHODS: array [0..HTTP_METHOD_COUNT-1] of string = (
      'GET', 'POST', 'PUT', 'DELETE',
      'HEAD', 'OPTIONS', 'TRACE', 'CONNECT',
      'PATCH', 'COPY', 'LINK', 'UNLINK',
      'PURGE', 'LOCK', 'UNLOCK', 'PROPFIND');
    SESSIONID_COOKIE_NAME = 'cross_sessionid';
  private
    FMethodTags: array [0..HTTP_METHOD_COUNT-1] of TBytes;
    FStoragePath: string;
    FAutoDeleteFiles: Boolean;
    FMaxPostDataSize: Int64;
    FMaxHeaderSize: Int64;
    FMinCompressSize: Integer;
    FSessionIDCookieName: string;
    FRouters: TCrossHttpRouters;
    FRoutersLock: TMultiReadExclusiveWriteSynchronizer;
    FMiddlewares: TCrossHttpRouters;
    FMiddlewaresLock: TMultiReadExclusiveWriteSynchronizer;
    FSessions: ISessions;
    FOnRequest: TCrossHttpRequestEvent;
    FOnRequestException: TCrossHttpRequestExceptionEvent;
    FOnPostDataBegin: TCrossHttpConnEvent;
    FOnPostData: TCrossHttpDataEvent;
    FOnPostDataEnd: TCrossHttpConnEvent;
    FCompressible: Boolean;

    function IsValidHttpRequest(ABuf: Pointer; ALen: Integer): Boolean;
    procedure ParseRecvData(const AConnection: ICrossConnection; const ABuf: Pointer; ALen: Integer);

    function RegisterRouter(const AMethod, APath: string;
      ARouterProc: TCrossHttpRouterProc;
      ARouterMethod: TCrossHttpRouterMethod;
      ARouterProc2: TCrossHttpRouterProc2;
      ARouterMethod2: TCrossHttpRouterMethod2): TCrossHttpServer;
    function RegisterMiddleware(const AMethod, APath: string;
      AMiddlewareProc: TCrossHttpRouterProc;
      AMiddlewareMethod: TCrossHttpRouterMethod;
      AMiddlewareProc2: TCrossHttpRouterProc2;
      AMiddlewareMethod2: TCrossHttpRouterMethod2): TCrossHttpServer;
  private
    function GetStoragePath: string;
    function GetAutoDeleteFiles: Boolean;
    function GetMaxHeaderSize: Int64;
    function GetMaxPostDataSize: Int64;
    function GetCompressible: Boolean;
    function GetMinCompressSize: Int64;
    function GetSessions: ISessions;
    function GetSessionIDCookieName: string;
    function GetOnRequest: TCrossHttpRequestEvent;
    function GetOnRequestException: TCrossHttpRequestExceptionEvent;
    function GetOnPostDataBegin: TCrossHttpConnEvent;
    function GetOnPostData: TCrossHttpDataEvent;
    function GetOnPostDataEnd: TCrossHttpConnEvent;

    procedure SetStoragePath(const Value: string);
    procedure SetAutoDeleteFiles(const Value: Boolean);
    procedure SetMaxHeaderSize(const Value: Int64);
    procedure SetMaxPostDataSize(const Value: Int64);
    procedure SetCompressible(const Value: Boolean);
    procedure SetMinCompressSize(const Value: Int64);
    procedure SetSessions(const Value: ISessions);
    procedure SetSessionIDCookieName(const Value: string);
    procedure SetOnRequest(const Value: TCrossHttpRequestEvent);
    procedure SetOnRequestException(const Value: TCrossHttpRequestExceptionEvent);
    procedure SetOnPostDataBegin(const Value: TCrossHttpConnEvent);
    procedure SetOnPostData(const Value: TCrossHttpDataEvent);
    procedure SetOnPostDataEnd(const Value: TCrossHttpConnEvent);
  protected
    function CreateConnection(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType): ICrossConnection; override;

    function CreateRouter(const AMethod, APath: string;
      ARouterProc: TCrossHttpRouterProc; ARouterMethod: TCrossHttpRouterMethod;
      ARouterProc2: TCrossHttpRouterProc2; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpRouter; virtual;

    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;
  protected
    procedure TriggerPostDataBegin(const AConnection: ICrossHttpConnection); virtual;
    procedure TriggerPostData(const AConnection: ICrossHttpConnection;
      const ABuf: Pointer; const ALen: Integer); virtual;
    procedure TriggerPostDataEnd(const AConnection: ICrossHttpConnection); virtual;

    // 处理请求
    procedure DoOnRequest(const AConnection: ICrossHttpConnection); virtual;
  public
    constructor Create(const AIoThreads: Integer); override;
    destructor Destroy; override;

    function Use(const AMethod, APath: string;
      AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    function Use(const AMethod, APath: string;
      AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

    function Use(const AMethod, APath: string;
      AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Use(const AMethod, APath: string;
      AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Use(const APath: string;
      AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;

    function Use(const APath: string;
      AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;

    function Use(const APath: string;
      AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;

    function Use(const APath: string;
      AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Use(AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Use(AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function Use(AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Use(AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Route(const AMethod, APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Route(const AMethod, APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function Route(const AMethod, APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Route(const AMethod, APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Get(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Get(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function Get(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Get(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Put(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Put(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function Put(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Put(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Post(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Post(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function Post(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Post(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function Delete(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function Delete(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function Delete(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function Delete(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function All(const APath: string; ARouterProc: TCrossHttpRouterProc): ICrossHttpServer; overload;
    function All(const APath: string; ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer; overload;
    function All(const APath: string; ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer; overload;
    function All(const APath: string; ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer; overload;

    function &Static(const APath, ALocalStaticDir: string): ICrossHttpServer;
    function Dir(const APath, ALocalDir: string): ICrossHttpServer;
    function Index(const APath, ALocalDir: string; const ADefIndexFiles: TArray<string>): ICrossHttpServer;

    function RemoveRouter(const AMethod, APath: string): ICrossHttpServer;
    function ClearRouter: ICrossHttpServer;

    function LockRouters: TCrossHttpRouters;
    procedure UnlockRouters;

    function LockMiddlewares: TCrossHttpRouters;
    procedure UnlockMiddlewares;

    property StoragePath: string read GetStoragePath write SetStoragePath;
    property AutoDeleteFiles: Boolean read GetAutoDeleteFiles write SetAutoDeleteFiles;
    property MaxHeaderSize: Int64 read GetMaxHeaderSize write SetMaxHeaderSize;
    property MaxPostDataSize: Int64 read GetMaxPostDataSize write SetMaxPostDataSize;
    property Compressible: Boolean read GetCompressible write SetCompressible;
    property MinCompressSize: Int64 read GetMinCompressSize write SetMinCompressSize;
    property Sessions: ISessions read GetSessions write SetSessions;
    property SessionIDCookieName: string read GetSessionIDCookieName write SetSessionIDCookieName;

    property OnRequest: TCrossHttpRequestEvent read GetOnRequest write SetOnRequest;
    property OnRequestException: TCrossHttpRequestExceptionEvent read GetOnRequestException write SetOnRequestException;
    property OnPostDataBegin: TCrossHttpConnEvent read GetOnPostDataBegin write SetOnPostDataBegin;
    property OnPostData: TCrossHttpDataEvent read GetOnPostData write SetOnPostData;
    property OnPostDataEnd: TCrossHttpConnEvent read GetOnPostDataEnd write SetOnPostDataEnd;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  Utils.RegEx, Utils.Utils,
  Net.CrossHttpRouter;


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

{ TCrossHttpConnection }

constructor TCrossHttpConnection.Create(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType);
var
  LConnection: ICrossHttpConnection;
begin
  inherited;

  LConnection := Self;

  FRequest := TCrossHttpRequest.Create(LConnection);
  FResponse := TCrossHttpResponse.Create(LConnection);
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

{ TCrossHttpRouter }

constructor TCrossHttpRouter.Create(const AMethod, APath: string;
  ARouterProc: TCrossHttpRouterProc; ARouterMethod: TCrossHttpRouterMethod;
  ARouterProc2: TCrossHttpRouterProc2; ARouterMethod2: TCrossHttpRouterMethod2);
begin
  FMethod := AMethod;
  FPath := APath;
  FRouterProc := ARouterProc;
  FRouterMethod := ARouterMethod;
  FRouterProc2 := ARouterProc2;
  FRouterMethod2 := ARouterMethod2;

  FMethodRegEx := TPerlRegEx.Create;
  FMethodRegEx.Options := [preCaseLess];

  FPathRegEx := TPerlRegEx.Create;
  FPathRegEx.Options := [preCaseLess];

  FRegExLock := TObject.Create;

  RemakePattern;
end;

destructor TCrossHttpRouter.Destroy;
begin
  TMonitor.Enter(FRegExLock);
  try
    FreeAndNil(FMethodRegEx);
    FreeAndNil(FPathRegEx);
  finally
    TMonitor.Exit(FRegExLock);
  end;
  FreeAndNil(FRegExLock);

  inherited;
end;

function TCrossHttpRouter.MakeMethodPattern(const AMethod: string): string;
var
  LPattern: string;
begin
  LPattern := AMethod;

  // 通配符*转正则表达式
  LPattern := TRegEx.Replace(LPattern, '(?<!\.)\*', '.*');

  if not LPattern.StartsWith('^') then
    LPattern := '^' + LPattern;
  if not LPattern.EndsWith('$') then
    LPattern := LPattern + '$';

  Result := LPattern;
end;

function TCrossHttpRouter.MakePathPattern(const APath: string;
  var AKeys: TArray<string>): string;
var
  LPattern: string;
  LKeys: TArray<string>;
begin
  LKeys := [];
  LPattern := APath;

  // 最后增加 /?
  if APath.EndsWith('/') then
    LPattern := LPattern + '?'
  else
    LPattern := LPattern + '/?';

  // 将 /( 替换成 /(?:
  LPattern := TRegEx.Replace(LPattern, '\/\(', '/(?:');

  // 将 / . 替换成 \/ \.
  LPattern := TRegEx.Replace(LPattern, '([\/\.])', '\\$1');

  // 提取形如 :keyname 的参数名称
  // 可以在参数后面增加正则限定参数 :number(\d+), :word(\w+)
  LPattern := TRegEx.Replace(LPattern, '(\\\/)?(\\\.)?:(\w+)(\(.*?\))?(\*)?(\?)?',
    function(const Match: TMatch): string
    var
      LSlash, LFormat, LKey, LCapture, LStar, LOptional: string;
    begin
      if not Match.Success then Exit('');

      if (Match.Groups.Count > 1) then
        LSlash := Match.Groups[1].Value
      else
        LSlash := '';
      if (Match.Groups.Count > 2) then
        LFormat := Match.Groups[2].Value
      else
        LFormat := '';
      if (Match.Groups.Count > 3) then
        LKey := Match.Groups[3].Value
      else
        LKey := '';
      if (Match.Groups.Count > 4) then
        LCapture := Match.Groups[4].Value
      else
        LCapture := '';
      if (Match.Groups.Count > 5) then
        LStar := Match.Groups[5].Value
      else
        LStar := '';
      if (Match.Groups.Count > 6) then
        LOptional := Match.Groups[6].Value
      else
        LOptional := '';

      if (LCapture = '') then
        LCapture := '([^\\/' + LFormat + ']+?)';

      Result := '';
      if (LOptional = '') then
        Result := Result + LSlash;
      Result := Result + '(?:' + LFormat;
      if (LOptional <> '') then
        Result := Result + LSlash;
      Result := Result + LCapture;
      if (LStar <> '') then
        Result := Result + '((?:[\\/' + LFormat + '].+?)?)';
      Result := Result + ')' + LOptional;

      LKeys := LKeys + [LKey];
    end);

  // 通配符*转正则表达式
  LPattern := TRegEx.Replace(LPattern, '(?<!\.)\*', '.*');

  if not LPattern.StartsWith('^') then
    LPattern := '^' + LPattern;
  if not LPattern.EndsWith('$') then
    LPattern := LPattern + '$';

  AKeys := LKeys;
  Result := LPattern;
end;

procedure TCrossHttpRouter.RemakePattern;
begin
  if (FPath.Chars[0] <> '/') then
    FPath := '/' + FPath;

  FMethodPattern := MakeMethodPattern(FMethod);
  FPathPattern := MakePathPattern(FPath, FPathParamKeys);

  TMonitor.Enter(FRegExLock);
  try
    FMethodRegEx.RegEx := FMethodPattern;
    FPathRegEx.RegEx := FPathPattern;
  finally
    TMonitor.Exit(FRegExLock);
  end;
end;

function TCrossHttpRouter.IsMatch(const ARequest: ICrossHttpRequest): Boolean;
  function _IsMatchMethod: Boolean;
  begin
    // Method中不包括参数, 使用SameText辅助加速
    if (FMethod = '*') or SameText(ARequest.Method, FMethod) then Exit(True);

    FMethodRegEx.Subject := ARequest.Method;
    Result := FMethodRegEx.Match;
  end;

  function _IsMatchPath: Boolean;
  var
    I: Integer;
  begin
    // Path中不包括参数时, 使用SameText辅助加速
    if (FPath = '*') or ((Length(FPathParamKeys) = 0) and SameText(ARequest.Path, FPath)) then Exit(True);

    FPathRegEx.Subject := ARequest.Path;
    Result := FPathRegEx.Match;
    if not Result then Exit;

    // 将Path中的参数解析出来保存到Request.Params中
    // 注意: TPerlRegEx.GroupCount 是实际 GroupCount - 1
    for I := 1 to FPathRegEx.GroupCount do
      ARequest.Params[FPathParamKeys[I - 1]] := FPathRegEx.Groups[I];
  end;
begin
  ARequest.Params.Clear;

  TMonitor.Enter(FRegExLock);
  try
    Result := _IsMatchMethod and _IsMatchPath;
  finally
    TMonitor.Exit(FRegExLock);
  end;
end;

procedure TCrossHttpRouter.Execute(const ARequest: ICrossHttpRequest;
  const AResponse: ICrossHttpResponse; var AHandled: Boolean);
begin
  if Assigned(FRouterProc) then
  begin
    FRouterProc(ARequest, AResponse);
  end else
  if Assigned(FRouterMethod) then
  begin
    FRouterMethod(ARequest, AResponse);
  end else
  if Assigned(FRouterProc2) then
  begin
    FRouterProc2(ARequest, AResponse, AHandled);
  end else
  if Assigned(FRouterMethod2) then
  begin
    FRouterMethod2(ARequest, AResponse, AHandled);
  end;
end;

function TCrossHttpRouter.GetMethod: string;
begin
  Result := FMethod;
end;

function TCrossHttpRouter.GetPath: string;
begin
  Result := FPath;
end;

{ TCrossHttpServer }

function TCrossHttpServer.All(const APath: string;
  ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('*', APath, ARouterProc);
end;

function TCrossHttpServer.All(const APath: string;
  ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Route('*', APath, ARouterProc2);
end;

function TCrossHttpServer.All(const APath: string;
  ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('*', APath, ARouterMethod);
end;

function TCrossHttpServer.All(const APath: string;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Route('*', APath, ARouterMethod2);
end;

constructor TCrossHttpServer.Create(const AIoThreads: Integer);
var
  I: Integer;
begin
  inherited Create(AIoThreads);

  FRouters := TCrossHttpRouters.Create;
  FRoutersLock := TMultiReadExclusiveWriteSynchronizer.Create;

  FMiddlewares := TCrossHttpRouters.Create;
  FMiddlewaresLock := TMultiReadExclusiveWriteSynchronizer.Create;

  for I := Low(FMethodTags) to High(FMethodTags) do
    FMethodTags[I] := TEncoding.ANSI.GetBytes(HTTP_METHODS[I]);

  Port := 80;
  Addr := '';

  FCompressible := True;
  FMinCompressSize := MIN_COMPRESS_SIZE;
  FStoragePath := TPath.Combine(TUtils.AppPath, 'temp') + TPath.DirectorySeparatorChar;
  FSessionIDCookieName := SESSIONID_COOKIE_NAME;
end;

function TCrossHttpServer.CreateConnection(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType): ICrossConnection;
begin
  Result := TCrossHttpConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TCrossHttpServer.CreateRouter(const AMethod, APath: string;
  ARouterProc: TCrossHttpRouterProc; ARouterMethod: TCrossHttpRouterMethod;
  ARouterProc2: TCrossHttpRouterProc2;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpRouter;
begin
  Result := TCrossHttpRouter.Create(AMethod, APath,
    ARouterProc, ARouterMethod,
    ARouterProc2, ARouterMethod2);
end;

destructor TCrossHttpServer.Destroy;
begin
  Stop;

  FRoutersLock.BeginWrite;
  FreeAndNil(FRouters);
  FRoutersLock.EndWrite;
  FreeAndNil(FRoutersLock);

  FMiddlewaresLock.BeginWrite;
  FreeAndNil(FMiddlewares);
  FMiddlewaresLock.EndWrite;
  FreeAndNil(FMiddlewaresLock);

  inherited Destroy;
end;

function TCrossHttpServer.Dir(const APath, ALocalDir: string): ICrossHttpServer;
var
  LReqPath: string;
begin
  LReqPath := APath;
  if not LReqPath.EndsWith('/') then
    LReqPath := LReqPath + '/';
  LReqPath := LReqPath + '?:dir(*)';
  Result := Get(LReqPath, TNetCrossRouter.Dir(APath, ALocalDir, 'dir'));
end;

function TCrossHttpServer.Delete(const APath: string;
  ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('DELETE', APath, ARouterProc);
end;

function TCrossHttpServer.Delete(const APath: string;
  ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Route('DELETE', APath, ARouterProc2);
end;

function TCrossHttpServer.Delete(const APath: string;
  ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('DELETE', APath, ARouterMethod);
end;

function TCrossHttpServer.Delete(const APath: string;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Route('DELETE', APath, ARouterMethod2);
end;

procedure TCrossHttpServer.DoOnRequest(const AConnection: ICrossHttpConnection);
var
  LRequest: ICrossHttpRequest;
  LResponse: ICrossHttpResponse;
  LSessionID: string;
  LHandled: Boolean;
  LRouter, LMiddleware: ICrossHttpRouter;
  LMiddlewares, LRouters: TArray<ICrossHttpRouter>;
begin
  LRequest := AConnection.Request;
  LResponse := AConnection.Response;

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

    {$region '中间件'}
    FMiddlewaresLock.BeginRead;
    try
      // 先将中间件保存到临时数组中
      // 然后再执行中间件
      // 这样做是为了减少加锁的时间
      LMiddlewares := FMiddlewares.ToArray;
    finally
      FMiddlewaresLock.EndRead;
    end;
    for LMiddleware in LMiddlewares do
    begin
      // 执行匹配的中间件
      if LMiddleware.IsMatch(LRequest) then
      begin
        // 中间件通常用于请求的预处理
        // 所以默认将 LHandled 置为 False, 以保证后续路由能被执行
        // 除非用户在中间件中明确指定了 LHandled := True, 表明该请求无需后续路由响应了
        LHandled := False;
        LMiddleware.Execute(LRequest, LResponse, LHandled);

        // 如果已经发送了数据, 则后续的事件和路由响应都不需要执行了
        if LHandled or LResponse.Sent then Exit;
      end;
    end;
    {$endregion}

    {$region '响应请求事件'}
    if Assigned(FOnRequest) then
    begin
      LHandled := False;
      FOnRequest(Self, LRequest, LResponse, LHandled);

      // 如果已经发送了数据, 则后续的事件和路由响应都不需要执行了
      if LHandled or LResponse.Sent then Exit;
    end;
    {$endregion}

    {$region '路由'}
    FRoutersLock.BeginRead;
    try
      // 先将路由保存到临时数组中
      // 然后再执行路由
      // 这样做是为了减少加锁时间
      LRouters := FRouters.ToArray;
    finally
      FRoutersLock.EndRead;
    end;
    for LRouter in LRouters do
    begin
      // 执行匹配的路由
      if LRouter.IsMatch(LRequest) then
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
      else if (e is ECrossHttpException) then
        LResponse.SendStatus(ECrossHttpException(e).StatusCode, ECrossHttpException(e).Message)
      else
        LResponse.SendStatus(500, e.Message);
    end;
  end;
end;

function TCrossHttpServer.Get(const APath: string;
  ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('GET', APath, ARouterProc);
end;

function TCrossHttpServer.Get(const APath: string;
  ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Route('GET', APath, ARouterProc2);
end;

function TCrossHttpServer.Get(const APath: string;
  ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('GET', APath, ARouterMethod);
end;

function TCrossHttpServer.Get(const APath: string;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Route('GET', APath, ARouterMethod2);
end;

function TCrossHttpServer.GetAutoDeleteFiles: Boolean;
begin
  Result := FAutoDeleteFiles;
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

function TCrossHttpServer.GetMinCompressSize: Int64;
begin
  Result := FMinCompressSize;
end;

function TCrossHttpServer.GetOnPostData: TCrossHttpDataEvent;
begin
  Result := FOnPostData;
end;

function TCrossHttpServer.GetOnPostDataBegin: TCrossHttpConnEvent;
begin
  Result := FOnPostDataBegin;
end;

function TCrossHttpServer.GetOnPostDataEnd: TCrossHttpConnEvent;
begin
  Result := FOnPostDataEnd;
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

procedure TCrossHttpServer.SetAutoDeleteFiles(const Value: Boolean);
begin
  FAutoDeleteFiles := Value;
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

procedure TCrossHttpServer.SetMinCompressSize(const Value: Int64);
begin
  FMinCompressSize := Value;
end;

procedure TCrossHttpServer.SetOnPostData(const Value: TCrossHttpDataEvent);
begin
  FOnPostData := Value;
end;

procedure TCrossHttpServer.SetOnPostDataBegin(const Value: TCrossHttpConnEvent);
begin
  FOnPostDataBegin := Value;
end;

procedure TCrossHttpServer.SetOnPostDataEnd(const Value: TCrossHttpConnEvent);
begin
  FOnPostDataEnd := Value;
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
  LReqPath := LReqPath + ':file(*)';
  Result := Get(LReqPath, TNetCrossRouter.Static(ALocalStaticDir, 'file'));
end;

function TCrossHttpServer.Index(const APath, ALocalDir: string;
  const ADefIndexFiles: TArray<string>): ICrossHttpServer;
var
  LReqPath: string;
begin
  LReqPath := APath;
  if not LReqPath.EndsWith('/') then
    LReqPath := LReqPath + '/';
  LReqPath := LReqPath + ':file(*)';
  Result := Get(LReqPath, TNetCrossRouter.Index(ALocalDir, 'file', ADefIndexFiles));
end;

function TCrossHttpServer.IsValidHttpRequest(ABuf: Pointer;
  ALen: Integer): Boolean;
var
  LBytes: TBytes;
  I: Integer;
begin
  for I := Low(FMethodTags) to High(FMethodTags) do
  begin
    LBytes := FMethodTags[I];
    if (ALen >= Length(LBytes)) and
      CompareMem(ABuf, Pointer(LBytes), Length(LBytes)) then Exit(True);
  end;
  Result := False;
end;

procedure TCrossHttpServer.ParseRecvData(const AConnection: ICrossConnection;
  const ABuf: Pointer; ALen: Integer);
var
  LHttpConnection: ICrossHttpConnection;
  LRequest: TCrossHttpRequest;
  LResponse: TCrossHttpResponse;
  pch: PByte;
  LChunkSize: Integer;
  LLineStr: string;

  procedure _Error(AStatusCode: Integer; const AErrMsg: string);
  begin
    LHttpConnection.Response.SendStatus(AStatusCode, AErrMsg);
  end;

begin
  LHttpConnection := AConnection as ICrossHttpConnection;
  LRequest := LHttpConnection.Request as TCrossHttpRequest;
  LResponse := LHttpConnection.Response as TCrossHttpResponse;

  // 在这里解析客户端浏览器发送过来的请求数据
  pch := ABuf;
  while (ALen > 0) do
  begin
    // 使用循环处理粘包, 比递归调用节省资源
    while (ALen > 0) and (LRequest.FParseState <> psDone) do
    begin
      case LRequest.FParseState of
        psHeader:
          begin
            case pch^ of
              13{\r}: Inc(LRequest.CR);
              10{\n}: Inc(LRequest.LF);
            else
              LRequest.CR := 0;
              LRequest.LF := 0;
            end;

            // Header尺寸超标
            if (FMaxHeaderSize > 0) and (LRequest.FRawRequest.Size + 1 > FMaxHeaderSize) then
            begin
              _Error(400, 'Request header too large.');
              Exit;
            end;

            // 写入请求数据
            LRequest.FRawRequest.Write(pch^, 1);
            Dec(ALen);
            Inc(pch);

            // 如果不是有效的Http请求直接断开
            // HTTP 请求命令中最长的命令是 PROPFIND, 长度为8个字符
            // 所以在收到8个字节的时候进行检测
            if (LRequest.FRawRequest.Size = 8) and
              not IsValidHttpRequest(LRequest.FRawRequest.Memory, LRequest.FRawRequest.Size) then
            begin
              _Error(400, 'Request method invalid.');
              Exit;
            end;

            // HTTP头已接收完毕(\r\n\r\n是HTTP头结束的标志)
            if (LRequest.CR = 2) and (LRequest.LF = 2) then
            begin
              LRequest.CR := 0;
              LRequest.LF := 0;

              if not LRequest.ParseRequestData then
              begin
                _Error(400, 'Request data invalid.');
                Exit;
              end;

              // Post数据尺寸超标, 直接断开连接
              if (FMaxPostDataSize > 0) and (LRequest.FContentLength > FMaxPostDataSize) then
              begin
                _Error(400, 'Post data too large.');
                Exit;
              end;

              // 如果 RequestContentLength 大于 0, 或者是 Chunked 编码, 则还需要接收 post 数据
              if (LRequest.FContentLength > 0) or LRequest.IsChunked then
              begin
                LRequest.FPostDataSize := 0;

                if LRequest.IsChunked then
                begin
                  LRequest.FParseState := psChunkSize;
                  LRequest.FChunkSizeStream := TBytesStream.Create(nil);
                end else
                  LRequest.FParseState := psPostData;

                TriggerPostDataBegin(LHttpConnection);
              end else
              begin
                LRequest.FBodyType := btNone;
                LRequest.FParseState := psDone;
                Break;
              end;
            end;
          end;

        // 非Chunked编码的Post数据(有RequestContentLength)
        psPostData:
          begin
            LChunkSize := Min((LRequest.ContentLength - LRequest.FPostDataSize), ALen);
            // Post数据尺寸超标, 直接断开连接
            if (FMaxPostDataSize > 0) and (LRequest.FPostDataSize + LChunkSize > FMaxPostDataSize) then
            begin
              _Error(400, 'Post data too large.');
              Exit;
            end;
            TriggerPostData(LHttpConnection, pch, LChunkSize);

            Inc(LRequest.FPostDataSize, LChunkSize);
            Inc(pch, LChunkSize);
            Dec(ALen, LChunkSize);

            if (LRequest.FPostDataSize >= LRequest.ContentLength) then
            begin
              LRequest.FParseState := psDone;
              TriggerPostDataEnd(LHttpConnection);
              Break;
            end;
          end;

        // Chunked编码: 块尺寸
        psChunkSize:
          begin
            case pch^ of
              13{\r}: Inc(LRequest.CR);
              10{\n}: Inc(LRequest.LF);
            else
              LRequest.CR := 0;
              LRequest.LF := 0;
              LRequest.FChunkSizeStream.Write(pch^, 1);
            end;
            Dec(ALen);
            Inc(pch);

            if (LRequest.CR = 1) and (LRequest.LF = 1) then
            begin
              SetString(LLineStr, MarshaledAString(LRequest.FChunkSizeStream.Memory), LRequest.FChunkSizeStream.Size);
              LRequest.FParseState := psChunkData;
              LRequest.FChunkSize := StrToIntDef('$' + Trim(LLineStr), -1);
              LRequest.FChunkLeftSize := LRequest.FChunkSize;
            end;
          end;

        // Chunked编码: 块数据
        psChunkData:
          begin
            if (LRequest.FChunkLeftSize > 0) then
            begin
              LChunkSize := Min(LRequest.FChunkLeftSize, ALen);
              // Post数据尺寸超标, 直接断开连接
              if (FMaxPostDataSize > 0) and (LRequest.FPostDataSize + LChunkSize > FMaxPostDataSize) then
              begin
                _Error(400, 'Post data too large.');
                Exit;
              end;
              TriggerPostData(LHttpConnection, pch, LChunkSize);

              Inc(LRequest.FPostDataSize, LChunkSize);
              Dec(LRequest.FChunkLeftSize, LChunkSize);
              Inc(pch, LChunkSize);
              Dec(ALen, LChunkSize);
            end;

            if (LRequest.FChunkLeftSize <= 0) then
            begin
              LRequest.FParseState := psChunkEnd;
              LRequest.CR := 0;
              LRequest.LF := 0;
            end;
          end;

        // Chunked编码: 块结束符\r\n
        psChunkEnd:
          begin
            case pch^ of
              13{\r}: Inc(LRequest.CR);
              10{\n}: Inc(LRequest.LF);
            else
              LRequest.CR := 0;
              LRequest.LF := 0;
            end;
            Dec(ALen);
            Inc(pch);

            if (LRequest.CR = 1) and (LRequest.LF = 1) then
            begin
              // 最后一块的ChunSize为0
              if (LRequest.FChunkSize > 0) then
              begin
                LRequest.FParseState := psChunkSize;
                LRequest.FChunkSizeStream.Clear;
                LRequest.CR := 0;
                LRequest.LF := 0;
              end else
              begin
                LRequest.FParseState := psDone;
                FreeAndNil(LRequest.FChunkSizeStream);
                TriggerPostDataEnd(LHttpConnection);
                Break;
              end;
            end;
          end;
      end;
    end;

    // 处理请求
    if (LRequest.FParseState = psDone) then
    begin
      DoOnRequest(LHttpConnection);

      LRequest.Reset;
      LResponse.Reset;
    end;
  end;
end;

function TCrossHttpServer.Post(const APath: string;
  ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('POST', APath, ARouterProc);
end;

function TCrossHttpServer.Post(const APath: string;
  ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Route('POST', APath, ARouterProc2);
end;

function TCrossHttpServer.Post(const APath: string;
  ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('POST', APath, ARouterMethod);
end;

function TCrossHttpServer.Post(const APath: string;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Route('POST', APath, ARouterMethod2);
end;

function TCrossHttpServer.Put(const APath: string;
  ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Route('PUT', APath, ARouterMethod);
end;

function TCrossHttpServer.Put(const APath: string;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Route('PUT', APath, ARouterMethod2);
end;

function TCrossHttpServer.Put(const APath: string;
  ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Route('PUT', APath, ARouterProc);
end;

function TCrossHttpServer.Put(const APath: string;
  ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Route('PUT', APath, ARouterProc2);
end;

function TCrossHttpServer.RegisterMiddleware(const AMethod, APath: string;
  AMiddlewareProc: TCrossHttpRouterProc;
  AMiddlewareMethod: TCrossHttpRouterMethod;
  AMiddlewareProc2: TCrossHttpRouterProc2;
  AMiddlewareMethod2: TCrossHttpRouterMethod2): TCrossHttpServer;
var
  LMiddleware: ICrossHttpRouter;
begin
  LMiddleware := CreateRouter(AMethod, APath,
    AMiddlewareProc, AMiddlewareMethod,
    AMiddlewareProc2, AMiddlewareMethod2);
  FMiddlewaresLock.BeginWrite;
  try
    FMiddlewares.Add(LMiddleware);
  finally
    FMiddlewaresLock.EndWrite;
  end;
  Result := Self;
end;

function TCrossHttpServer.RegisterRouter(const AMethod, APath: string;
  ARouterProc: TCrossHttpRouterProc; ARouterMethod: TCrossHttpRouterMethod;
  ARouterProc2: TCrossHttpRouterProc2; ARouterMethod2: TCrossHttpRouterMethod2): TCrossHttpServer;
var
  LRouter: ICrossHttpRouter;
begin
  LRouter := CreateRouter(AMethod, APath,
    ARouterProc, ARouterMethod,
    ARouterProc2, ARouterMethod2);
  FRoutersLock.BeginWrite;
  try
    FRouters.Add(LRouter);
  finally
    FRoutersLock.EndWrite;
  end;
  Result := Self;
end;

function TCrossHttpServer.Route(const AMethod, APath: string;
  ARouterProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := RegisterRouter(AMethod, APath, ARouterProc, nil, nil, nil);
end;

function TCrossHttpServer.Route(const AMethod, APath: string;
  ARouterProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := RegisterRouter(AMethod, APath, nil, nil, ARouterProc2, nil);
end;

function TCrossHttpServer.Route(const AMethod, APath: string;
  ARouterMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := RegisterRouter(AMethod, APath, nil, ARouterMethod, nil, nil);
end;

function TCrossHttpServer.Route(const AMethod, APath: string;
  ARouterMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := RegisterRouter(AMethod, APath, nil, nil, nil, ARouterMethod2);
end;

function TCrossHttpServer.RemoveRouter(const AMethod, APath: string): ICrossHttpServer;
var
  I: Integer;
begin
  FRoutersLock.BeginWrite;
  try
    for I := FRouters.Count - 1 downto 0 do
      if SameText(FRouters[I].Method, AMethod) and SameText(FRouters[I].Path, APath) then
        FRouters.Delete(I);
  finally
    FRoutersLock.EndWrite;
  end;
  Result := Self;
end;

function TCrossHttpServer.ClearRouter: ICrossHttpServer;
begin
  FRoutersLock.BeginWrite;
  try
    FRouters.Clear;
  finally
    FRoutersLock.EndWrite;
  end;
  Result := Self;
end;

procedure TCrossHttpServer.TriggerPostDataBegin(
  const AConnection: ICrossHttpConnection);
var
  LRequest: TCrossHttpRequest;
  LMultiPart: THttpMultiPartFormData;
  LStream: TStream;
begin
  LRequest := AConnection.Request as TCrossHttpRequest;
  case LRequest.BodyType of
    btMultiPart:
    begin
      if (FStoragePath <> '') and not TDirectory.Exists(FStoragePath) then
        TDirectory.CreateDirectory(FStoragePath);

      LMultiPart := THttpMultiPartFormData.Create;
      LMultiPart.StoragePath := FStoragePath;
      LMultiPart.AutoDeleteFiles := FAutoDeleteFiles;
      LMultiPart.InitWithBoundary(LRequest.RequestBoundary);
      FreeAndNil(LRequest.FBody);
      LRequest.FBody := LMultiPart;
    end;

    btUrlEncoded:
    begin
      LStream := TBytesStream.Create;
      FreeAndNil(LRequest.FBody);
      LRequest.FBody := LStream;
    end;

    btBinary:
    begin
      LStream := TBytesStream.Create(nil);
      FreeAndNil(LRequest.FBody);
      LRequest.FBody := LStream;
    end;
  end;

  if Assigned(FOnPostDataBegin) then
    FOnPostDataBegin(Self, AConnection);
end;

procedure TCrossHttpServer.TriggerPostData(const AConnection: ICrossHttpConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LRequest: TCrossHttpRequest;
begin
  LRequest := AConnection.Request as TCrossHttpRequest;

  case LRequest.GetBodyType of
    btMultiPart: (LRequest.Body as THttpMultiPartFormData).Decode(ABuf, ALen);
    btUrlEncoded: (LRequest.Body as TStream).Write(ABuf^, ALen);
    btBinary: (LRequest.Body as TStream).Write(ABuf^, ALen);
  end;

  if Assigned(FOnPostData) then
    FOnPostData(Self, AConnection, ABuf, ALen);
end;

procedure TCrossHttpServer.TriggerPostDataEnd(
  const AConnection: ICrossHttpConnection);
var
  LRequest: TCrossHttpRequest;
  LUrlEncodedStr: string;
  LUrlEncodedBody: THttpUrlParams;
begin
  LRequest := AConnection.Request as TCrossHttpRequest;

  case LRequest.GetBodyType of
    btUrlEncoded:
    begin
      SetString(LUrlEncodedStr,
        MarshaledAString((LRequest.Body as TBytesStream).Memory),
        (LRequest.Body as TBytesStream).Size);
      LUrlEncodedBody := THttpUrlParams.Create;
      LUrlEncodedBody.Decode(LUrlEncodedStr);
      FreeAndNil(LRequest.FBody);
      LRequest.FBody := LUrlEncodedBody;
    end;

    btBinary:
    begin
      (LRequest.Body as TStream).Position := 0;
    end;
  end;

  if Assigned(FOnPostDataEnd) then
    FOnPostDataEnd(Self, AConnection);
end;

function TCrossHttpServer.LockMiddlewares: TCrossHttpRouters;
begin
  Result := FMiddlewares;
  FMiddlewaresLock.BeginWrite;
end;

function TCrossHttpServer.LockRouters: TCrossHttpRouters;
begin
  Result := FRouters;
  FRoutersLock.BeginWrite;
end;

procedure TCrossHttpServer.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  ParseRecvData(AConnection as ICrossHttpConnection, ABuf, ALen);
end;

function TCrossHttpServer.Use(const AMethod, APath: string;
  AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := RegisterMiddleware(AMethod, APath, nil, AMiddlewareMethod, nil, nil);
end;

function TCrossHttpServer.Use(const AMethod, APath: string;
  AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := RegisterMiddleware(AMethod, APath, AMiddlewareProc, nil, nil, nil);
end;

function TCrossHttpServer.Use(const APath: string;
  AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Use('*', APath, AMiddlewareMethod);
end;

function TCrossHttpServer.Use(const APath: string;
  AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Use('*', APath, AMiddlewareProc);
end;

function TCrossHttpServer.Use(
  AMiddlewareMethod: TCrossHttpRouterMethod): ICrossHttpServer;
begin
  Result := Use('*', '*', AMiddlewareMethod);
end;

procedure TCrossHttpServer.UnlockMiddlewares;
begin
  FMiddlewaresLock.EndWrite;
end;

procedure TCrossHttpServer.UnlockRouters;
begin
  FRoutersLock.EndWrite;
end;

function TCrossHttpServer.Use(
  AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Use('*', '*', AMiddlewareMethod2);
end;

function TCrossHttpServer.Use(
  AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Use('*', '*', AMiddlewareProc2);
end;

function TCrossHttpServer.Use(const AMethod, APath: string;
  AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := RegisterMiddleware(AMethod, APath, nil, nil, nil, AMiddlewareMethod2);
end;

function TCrossHttpServer.Use(const AMethod, APath: string;
  AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := RegisterMiddleware(AMethod, APath, nil, nil, AMiddlewareProc2, nil);
end;

function TCrossHttpServer.Use(const APath: string;
  AMiddlewareMethod2: TCrossHttpRouterMethod2): ICrossHttpServer;
begin
  Result := Use('*', APath, AMiddlewareMethod2);
end;

function TCrossHttpServer.Use(const APath: string;
  AMiddlewareProc2: TCrossHttpRouterProc2): ICrossHttpServer;
begin
  Result := Use('*', APath, AMiddlewareProc2);
end;

function TCrossHttpServer.Use(
  AMiddlewareProc: TCrossHttpRouterProc): ICrossHttpServer;
begin
  Result := Use('*', '*', AMiddlewareProc);
end;

{ TCrossHttpRequest }

constructor TCrossHttpRequest.Create(AConnection: ICrossHttpConnection);
begin
  FConnection := AConnection;

  FRawRequest := TBytesStream.Create(nil);
  FHeader := THttpHeader.Create;
  FCookies := TRequestCookies.Create;
  FParams := THttpUrlParams.Create;
  FQuery := THttpUrlParams.Create;

  Reset;
end;

destructor TCrossHttpRequest.Destroy;
begin
  FreeAndNil(FRawRequest);
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);
  FreeAndNil(FParams);
  FreeAndNil(FQuery);
  FreeAndNil(FBody);
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
  Result := SameText(FTransferEncoding, 'chunked');
end;

function TCrossHttpRequest.GetIsMultiPartFormData: Boolean;
begin
  Result := SameText(FContentType, 'multipart/form-data');
end;

function TCrossHttpRequest.GetIsUrlEncodedFormData: Boolean;
begin
  Result := SameText(FContentType, 'application/x-www-form-urlencoded');
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

function TCrossHttpRequest.GetPath: string;
begin
  Result := FPath;
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

function TCrossHttpRequest.GetRawPathAndParams: string;
begin
  Result := FRawPathAndParams;
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

function TCrossHttpRequest.ParseRequestData: Boolean;
var
  LRequestHeader: string;
  I, J: Integer;
begin
  SetString(FRawRequestText, MarshaledAString(FRawRequest.Memory), FRawRequest.Size);
  I := FRawRequestText.IndexOf(#13#10);
  // 第一行是请求命令行
  // GET /home?param=123 HTTP/1.1
  FRequestCmdLine := FRawRequestText.Substring(0, I);
  // 第二行起是请求头
  LRequestHeader := FRawRequestText.Substring(I + 2);
  // 解析请求头
  FHeader.Decode(LRequestHeader);

  // 请求方法(GET, POST, PUT, DELETE...)
  I := FRequestCmdLine.IndexOf(' ');
  FMethod := FRequestCmdLine.Substring(0, I).ToUpper;

  // 路径及参数(/home?param=123)
  J := FRequestCmdLine.IndexOf(' ', I + 1);
  FRawPathAndParams := FRequestCmdLine.Substring(I + 1, J - I - 1);

  // 请求的HTTP版本(HTTP/1.1)
  FVersion := FRequestCmdLine.Substring(J + 1).ToUpper;

  // 解析?key1=value1&key2=value2参数
  J := FRawPathAndParams.IndexOf('?');
  if (J < 0) then
  begin
    FRawPath := FRawPathAndParams;
    FRawParamsText := '';
  end else
  begin
    FRawPath := FRawPathAndParams.Substring(0, J);
    FRawParamsText := FRawPathAndParams.Substring(J + 1);
  end;
  FPath := TNetEncoding.URL.Decode(FRawPath);

  FQuery.Decode(FRawParamsText);

  // HTTP协议版本
  if (FVersion = '') then
    FVersion := 'HTTP/1.0';
  if (FVersion = 'HTTP/1.0') then
    FHttpVerNum := 10
  else
    FHttpVerNum := 11;
  FKeepAlive := (FHttpVerNum = 11);

  // 解析Cookies
  FCookies.Decode(FHeader['Cookie'], True);

  FContentType := FHeader['Content-Type'];
  FRequestBoundary := '';
  J := FContentType.IndexOf(';');
  if (J >= 0) then
  begin
    FRequestBoundary := FContentType.Substring(J + 1);
    if FRequestBoundary.StartsWith(' boundary=', True) then
      FRequestBoundary := FRequestBoundary.Substring(10);

    FContentType := FContentType.Substring(0, J);
  end;

  FContentLength := StrToInt64Def(FHeader['Content-Length'], -1);

  FRequestHost := FHeader['Host'];
  J := FRequestHost.IndexOf(':');
  if (J >= 0) then
  begin
    FHostName := FRequestHost.Substring(0, J);
    FHostPort := FRequestHost.Substring(J + 1).ToInteger;
  end else
  begin
    FHostName := FRequestHost;
    FHostPort := TCrossHttpServer(FConnection.Owner).Port;
  end;

  FRequestConnection := FHeader['Connection'];
  // HTTP/1.0 默认KeepAlive=False，只有显示指定了Connection: keep-alive才认为KeepAlive=True
  // HTTP/1.1 默认KeepAlive=True，只有显示指定了Connection: close才认为KeepAlive=False
  if FHttpVerNum = 10 then
    FKeepAlive := SameText(FRequestConnection, 'keep-alive')
  else if SameText(FRequestConnection, 'close') then
    FKeepAlive := False;

  FTransferEncoding:= FHeader['Transfer-Encoding'];
  FContentEncoding:= FHeader['Content-Encoding'];
  FAccept:= FHeader['Accept'];
  FReferer:= FHeader['Referer'];
  FAcceptLanguage:= FHeader['Accept-Language'];
  FAcceptEncoding:= FHeader['Accept-Encoding'];
  FUserAgent:= FHeader['User-Agent'];
  FAuthorization:= FHeader['Authorization'];
  FRequestCookies:= FHeader['Cookie'];
  FIfModifiedSince := TCrossHttpUtils.RFC1123_StrToDate(FHeader['If-Modified-Since']);
  FIfNoneMatch := FHeader['If-None-Match'];
  FRange := FHeader['Range'];
  FIfRange := FHeader['If-Range'];
  FXForwardedFor:= FHeader['X-Forwarded-For'];

  if IsMultiPartFormData then
    FBodyType := btMultiPart
  else if IsUrlEncodedFormData then
    FBodyType := btUrlEncoded
  else
    FBodyType := btBinary;

  Result := True;
end;

procedure TCrossHttpRequest.Reset;
begin
  FRawRequest.Clear;

  FParseState := psHeader;
  CR := 0;
  LF := 0;
  FPostDataSize := 0;
  FreeAndNil(FBody);
end;

{ TCrossHttpResponse }

constructor TCrossHttpResponse.Create(AConnection: ICrossHttpConnection);
begin
  FConnection := AConnection;
  FHeader := THttpHeader.Create;
  FCookies := TResponseCookies.Create;
  FStatusCode := 200;
end;

destructor TCrossHttpResponse.Destroy;
begin
  FreeAndNil(FHeader);
  FreeAndNil(FCookies);
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
  Result := FHeader['Content-Type'];
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
  Result := FHeader['Location'];
end;

function TCrossHttpResponse.GetRequest: ICrossHttpRequest;
begin
  Result := FConnection.Request;
end;

function TCrossHttpResponse.GetSent: Boolean;
begin
  Result := (AtomicCmpExchange(FSendStatus, 0, 0) > 0);
end;

function TCrossHttpResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
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
  FStatusCode :=  200;
  FHeader.Clear;
  FCookies.Clear;
  FSendStatus := 0;
end;

procedure TCrossHttpResponse.Attachment(const AFileName: string);
begin
  if (GetContentType = '') then
    SetContentType(TCrossHttpUtils.GetFileMIMEType(AFileName));
  FHeader['Content-Disposition'] := 'attachment; filename="' +
    TNetEncoding.URL.Encode(TPath.GetFileName(AFileName)) + '"';
end;

procedure TCrossHttpResponse.Send(const ABody; const ACount: NativeInt;
  const ACallback: TCrossConnectionCallback);
var
  LCompressType: TCompressType;
begin
  if _CheckCompress(ACount, LCompressType) then
    SendZCompress(ABody, ACount, LCompressType, ACallback)
  else
    SendNoCompress(ABody, ACount, ACallback);
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
  _AdjustOffsetCount(Length(ABody), LOffset, LCount);

  Send(LBody[LOffset], LCount,
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
  if _CheckCompress(ABody.Size, LCompressType) then
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
  LIsFirstChunk: Boolean;
  LChunkState: TChunkState;
  LChunkData: Pointer;
  LChunkSize: NativeInt;
begin
  LIsFirstChunk := True;
  LChunkState := csHead;

  _Send(
    // HEADER
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      LHeaderBytes := _CreateHeader(0, True);

      AData^ := @LHeaderBytes[0];
      ACount^ := Length(LHeaderBytes);

      Result := (ACount^ > 0);
    end,
    // BODY
    function(const AData: PPointer; const ACount: PNativeInt): Boolean
    begin
      case LChunkState of
        csHead:
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
              ACount^ := Length(CHUNK_END);

              Result := (ACount^ > 0);

              Exit;
            end;

            LChunkHeader := TEncoding.ANSI.GetBytes(IntToHex(LChunkSize, 0)) + [13, 10];
            if LIsFirstChunk then
              LIsFirstChunk := False
            else
              LChunkHeader := [13, 10] + LChunkHeader;

            LChunkState := csBody;

            AData^ := @LChunkHeader[0];
            ACount^ := Length(LChunkHeader);

            Result := (ACount^ > 0);
          end;

        csBody:
          begin
            LChunkState := csHead;

            AData^ := LChunkData;
            ACount^ := LChunkSize;

            Result := (ACount^ > 0);
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
  LStream: TFileStream;
  LLastModified: TDateTime;
  LRequest: TCrossHttpRequest;
  LLastModifiedStr, LETag: string;
  LRangeStr: string;
  LRangeStrArr: TArray<string>;
  LRangeBegin, LRangeEnd, LOffset, LCount: Int64;
begin
  if not TFile.Exists(AFileName) then
  begin
    FHeader.Remove('Content-Disposition');
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
    LLastModified := TFile.GetLastWriteTime(AFileName);

    if (LRequest.IfModifiedSince > 0) and (LRequest.IfModifiedSince >= (LLastModified - (1 / SecsPerDay))) then
    begin
      // 304不要带任何body数据, 否则部分浏览器会报告无效的RESPONSE
      SendStatus(304, '', ACallback);
      Exit;
    end;

    LLastModifiedStr := TCrossHttpUtils.RFC1123_DateToStr(LLastModified);

    LETag := '"' + TUtils.BytesToHex(THashMD5.GetHashBytes(AFileName + LLastModifiedStr)) + '"';
    if (LRequest.IfNoneMatch = LETag) then
    begin
      // 304不要带任何body数据, 否则部分浏览器会报告无效的RESPONSE
      SendStatus(304, '', ACallback);
      Exit;
    end;

    LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  except
    on e: Exception do
    begin
      FHeader.Remove('Content-Disposition');
      SendStatus(404, Format('%s, %s', [e.ClassName, e.Message]), ACallback);
      Exit;
    end;
  end;

  // 在响应头中加入文件时间戳
  // 浏览器会根据该时间戳决定是否从本地缓存中直接加载数据
  FHeader['Last-Modified'] := LLastModifiedStr;
  FHeader['ETag'] := LETag;

  // 告诉浏览器支持分块传输
  FHeader['Accept-Ranges'] := 'bytes';

  // 收到分块取数据头
  // Range: bytes=[x]-[y]
  LRangeStr := LRequest.Range;
  if (LRangeStr <> '')
    and ((LRequest.IfRange = '') or (LRequest.IfRange = LETag)) then
  begin
    LRangeStr := LRangeStr.Substring(LRangeStr.IndexOf('=') + 1);
    LRangeStrArr := LRangeStr.Split(['-']);
    if (Length(LRangeStrArr) >= 2) then
    begin
      LRangeBegin := StrToInt64Def(LRangeStrArr[0], 0);
      LRangeEnd := StrToInt64Def(LRangeStrArr[1], 0);
    end else
    if (Length(LRangeStrArr) >= 1) then
    begin
      LRangeBegin := StrToInt64Def(LRangeStrArr[0], 0);
      LRangeEnd := LStream.Size - 1;
    end else
    begin
      LRangeBegin := 0;
      LRangeEnd := LStream.Size - 1;
    end;

    LOffset := LRangeBegin;
    LCount := LRangeEnd - LRangeBegin + 1;

    // 返回分块信息
    // Content-Range: bytes [x]-[y]/file-size
    FHeader['Content-Range'] := Format('bytes %d-%d/%d',
      [LRangeBegin, LRangeEnd, LStream.Size]);

    // 断点续传需要返回206状态码, 而不是200
    FStatusCode := 206;
  end else
  begin
    LOffset := 0;
    LCount := LStream.Size;
  end;

  Send(LStream, LOffset, LCount,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      FreeAndNil(LStream);

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SetContentType(const Value: string);
begin
  FHeader['Content-Type'] := Value;
end;

procedure TCrossHttpResponse.SetLocation(const Value: string);
begin
  FHeader['Location'] := Value;
end;

procedure TCrossHttpResponse.SetStatusCode(Value: Integer);
begin
  FStatusCode := Value;
end;

procedure TCrossHttpResponse._AdjustOffsetCount(const ABodySize: NativeInt;
  var AOffset, ACount: NativeInt);
begin
  {$region '修正 AOffset'}
  // 偏移为正数, 从头部开始计算偏移
  if (AOffset >= 0) then
  begin
    AOffset := AOffset;
    if (AOffset >= ABodySize) then
      AOffset := ABodySize - 1;
  end else
  // 偏移为负数, 从尾部开始计算偏移
  begin
    AOffset := ABodySize + AOffset;
    if (AOffset < 0) then
      AOffset := 0;
  end;
  {$endregion}

  {$region '修正 ACount'}
  // ACount<=0表示需要处理所有数据
  if (ACount <= 0) then
    ACount := ABodySize;

  if (ABodySize - AOffset < ACount) then
    ACount := ABodySize - AOffset;
  {$endregion}
end;

procedure TCrossHttpResponse._AdjustOffsetCount(const ABodySize: Int64;
  var AOffset, ACount: Int64);
begin
  {$region '修正 AOffset'}
  // 偏移为正数, 从头部开始计算偏移
  if (AOffset >= 0) then
  begin
    AOffset := AOffset;
    if (AOffset >= ABodySize) then
      AOffset := ABodySize - 1;
  end else
  // 偏移为负数, 从尾部开始计算偏移
  begin
    AOffset := ABodySize + AOffset;
    if (AOffset < 0) then
      AOffset := 0;
  end;
  {$endregion}

  {$region '修正 ACount'}
  // ACount<=0表示需要处理所有数据
  if (ACount <= 0) then
    ACount := ABodySize;

  if (ABodySize - AOffset < ACount) then
    ACount := ABodySize - AOffset;
  {$endregion}
end;

function TCrossHttpResponse._CheckCompress(const ABodySize: Int64;
  var ACompressType: TCompressType): Boolean;
var
  LContType, LRequestAcceptEncoding: string;
  LServer: ICrossHttpServer;
begin
  LContType := GetContentType;
  LServer := FConnection.Server;

  if LServer.Compressible
    and (ABodySize > 0)
    and ((LServer.MinCompressSize <= 0) or (ABodySize >= LServer.MinCompressSize))
    and ((Pos('text/', LContType) > 0)
      or (Pos('application/json', LContType) > 0)
      or (Pos('javascript', LContType) > 0)
      or (Pos('xml', LContType) > 0)
    ) then
  begin
    LRequestAcceptEncoding := GetRequest.AcceptEncoding;

    if (Pos('gzip', LRequestAcceptEncoding) > 0) then
    begin
      ACompressType := ctGZip;
      Exit(True);
    end else
    if (Pos('deflate', LRequestAcceptEncoding) > 0) then
    begin
      ACompressType := ctDeflate;
      Exit(True);
    end;
  end;

  Result := False;
end;

function TCrossHttpResponse._CreateHeader(const ABodySize: Int64;
  AChunked: Boolean): TBytes;
var
  LHeaderStr: string;
  LCookie: TResponseCookie;
begin
  if (GetContentType = '') then
    SetContentType(TMediaType.APPLICATION_OCTET_STREAM);
  if (FHeader['Connection'] = '') then
  begin
    if FConnection.Request.KeepAlive then
      FHeader['Connection'] := 'keep-alive'
    else
      FHeader['Connection'] := 'close';
  end;

  if AChunked then
    FHeader['Transfer-Encoding'] := 'chunked'
  else
    FHeader['Content-Length'] := ABodySize.ToString;

  if (FHeader['Server'] = '') then
    FHeader['Server'] := CROSS_HTTP_SERVER_NAME;

  LHeaderStr := FConnection.Request.Version + ' ' + FStatusCode.ToString + ' ' +
    TCrossHttpUtils.GetHttpStatusText(FStatusCode) + #13#10;

  for LCookie in FCookies do
    LHeaderStr := LHeaderStr + 'Set-Cookie: ' + LCookie.Encode + #13#10;

  LHeaderStr := LHeaderStr + FHeader.Encode;

  Result := TEncoding.ANSI.GetBytes(LHeaderStr);
end;

procedure TCrossHttpResponse._Send(const ASource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossConnectionCallback);
var
  LSender: TCrossConnectionCallback;
  LKeepAlive: Boolean;
  LStatusCode: Integer;
begin
  AtomicIncrement(FSendStatus);

  LKeepAlive := FConnection.Request.KeepAlive;
  LStatusCode := FStatusCode;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
    begin
      if not ASuccess then
      begin
        if Assigned(ACallback) then
          ACallback(AConnection, False);

        AConnection.Close;

        LSender := nil;

        Exit;
      end;

      LData := nil;
      LCount := 0;
      if not Assigned(ASource)
        or not ASource(@LData, @LCount)
        or (LData = nil)
        or (LCount <= 0) then
      begin
        if Assigned(ACallback) then
          ACallback(AConnection, True);

        if not LKeepAlive
          or (LStatusCode >= 400{如果发送的是出错状态码, 则发送完成之后断开连接}) then
          AConnection.Disconnect;

        LSender := nil;

        Exit;
      end;

      AConnection.SendBuf(LData^, LCount, LSender);
    end;

  LSender(FConnection, True);
end;

procedure TCrossHttpResponse._Send(const AHeaderSource,
  ABodySource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossConnectionCallback);
var
  LHeaderDone: Boolean;
begin
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

procedure TCrossHttpResponse.SendNoCompress(const ABody; const ACount: NativeInt;
  const ACallback: TCrossConnectionCallback);
var
  P: PByte;
  LSize: NativeInt;
  LHeaderBytes: TBytes;
begin
  P := @ABody;
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
  _AdjustOffsetCount(Length(ABody), LOffset, LCount);

  SendNoCompress(LBody[LOffset], LCount,
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
begin
  LOffset := AOffset;
  LCount := ACount;
  _AdjustOffsetCount(ABody.Size, LOffset, LCount);

  if (ABody is TCustomMemoryStream) then
  begin
    SendNoCompress(Pointer(IntPtr(TCustomMemoryStream(ABody).Memory) + LOffset)^, LCount, ACallback);
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
  FStatusCode := AStatusCode;
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
const
  WINDOW_BITS: array [TCompressType] of Integer = (15 + 16{gzip}, 15{deflate});
  CONTENT_ENCODING: array [TCompressType] of string = ('gzip', 'deflate');
var
  LZStream: TZStreamRec;
  LZFlush: Integer;
  LZResult: Integer;
  LOutSize: Integer;
  LBuffer: TBytes;
begin
  // 返回压缩方式
  FHeader['Content-Encoding'] := CONTENT_ENCODING[ACompressType];

  // 明确告知缓存服务器按照 Accept-Encoding 字段的内容, 分别缓存不同的版本
  FHeader['Vary'] := 'Accept-Encoding';

  SetLength(LBuffer, SND_BUF_SIZE);

  FillChar(LZStream, SizeOf(TZStreamRec), 0);
  LZResult := Z_OK;
  LZFlush := Z_NO_FLUSH;

  if (deflateInit2(LZStream, Z_DEFAULT_COMPRESSION,
    Z_DEFLATED, WINDOW_BITS[ACompressType], 8, Z_DEFAULT_STRATEGY) <> Z_OK) then
  begin
    if Assigned(ACallback) then
      ACallback(FConnection, False);
    Exit;
  end;

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
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossHttpResponse.SendZCompress(const ABody; const ACount: NativeInt;
  const ACompressType: TCompressType; const ACallback: TCrossConnectionCallback);
var
  P: PByte;
  LSize: NativeInt;
begin
  P := @ABody;
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
  _AdjustOffsetCount(Length(ABody), LOffset, LCount);

  SendZCompress(LBody[LOffset], LCount, ACompressType,
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
begin
  LOffset := AOffset;
  LCount := ACount;
  _AdjustOffsetCount(ABody.Size, LOffset, LCount);

  if (ABody is TCustomMemoryStream) then
  begin
    SendZCompress(Pointer(IntPtr(TCustomMemoryStream(ABody).Memory) + LOffset)^, LCount, ACompressType, ACallback);
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

      ACount^ := LBody.Read(LBuffer, Min(LCount, SND_BUF_SIZE));
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
