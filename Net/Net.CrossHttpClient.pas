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
  StrUtils,
  Math,
  Generics.Collections,
  ZLib,

  {$IFDEF DELPHI}
  Diagnostics,
  {$ELSE}
  DTF.Types,
  DTF.Diagnostics,
  {$ENDIF}

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket,
  Net.CrossHttpParams,
  Net.CrossHttpUtils,

  Utils.IOUtils,
  Utils.Hash,
  Utils.RegEx,
  Utils.SyncObjs,
  Utils.EasyTimer,
  Utils.Logger;

const
  CROSS_HTTP_CLIENT_NAME = 'CrossHttpClient/1.0';
  CRLF = #13#10;

type
  ECrossHttpClient = class(Exception);

  ICrossHttpClientConnection = interface;
  ICrossHttpClientRequest = interface;
  ICrossHttpClientResponse = interface;
  ICrossHttpClient = interface;

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
    ///   发送请求失败
    /// </summary>
    rsSendFailed,

    /// <summary>
    ///   正在等待响应(请求发送成功)
    /// </summary>
    rsReponsding,

    /// <summary>
    ///   响应失败(连接断开/数据异常)
    /// </summary>
    rsRespondFailed,

    /// <summary>
    ///   响应超时
    /// </summary>
    rsRespondTimeout,

    /// <summary>
    ///   响应成功
    /// </summary>
    rsRespondSuccess);

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
    {$REGION 'Documentation'}
    /// <summary>
    ///   获取可用连接
    /// </summary>
    {$ENDREGION}
    procedure GetConnection(const AProtocol, AHost: string; const APort: Word;
      const ACallback: TCrossHttpGetConnectionProc);
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   HTTP客户端
  /// </summary>
  {$ENDREGION}
  ICrossHttpClient = interface
  ['{99CC5305-02FE-48DA-9D62-3AE1A5FA86D1}']
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
  end;

  TCrossHttpClientConnection = class(TCrossSslConnection, ICrossHttpClientConnection)
  private
    FProtocol, FHost: string;
    FPort: Word;
    FPending: Integer;
    FWatch: TStopwatch;
    FStatus: Integer; // TRequestStatus

    FRequest: ICrossHttpClientRequest;
    FResponse: ICrossHttpClientResponse;

    procedure _BeginRequest; inline;
    procedure _EndRequest; inline;
    function _IsIdle: Boolean; inline;
    procedure _UpdateWatch;
    function _IsTimeout: Boolean;
    function _SetRequestStatus(const AStatus: TRequestStatus): TRequestStatus;
  protected
    function GetHost: string;
    function GetPort: Word;
    function GetProtocol: string;
    function GetRequestStatus: TRequestStatus;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: THandle;
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
    function GetConnection: ICrossHttpClientConnection;
  protected
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
    {$endregion}
  public
    constructor Create(const AConnection: TCrossHttpClientConnection);
    destructor Destroy; override;

    property Connection: ICrossHttpClientConnection read GetConnection;
    property Header: THttpHeader read GetHeader;
    property Cookies: TRequestCookies read GetCookies;
  end;

  TCrossHttpClientResponse = class(TInterfacedObject, ICrossHttpClientResponse)
  private type
    TCrossHttpParseState = (psHeader, psBodyData, psChunkSize, psChunkData, psChunkEnd, psDone);
  private
    FConnection: TCrossHttpClientConnection;
    FCallback: TCrossHttpResponseProc;

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

    FResponseBodySize: Int64;
    FParseState: TCrossHttpParseState;
    FCRCount, FLFCount: Integer;
    FRawRequest: TBytesStream;
    FChunkSizeStream: TBytesStream;
    FChunkSize, FChunkLeftSize: Integer;
    FResponseBodyStream: TStream;
    FNeedFreeResponseBodyStream: Boolean;

    // 动态解压
    FZCompressed: Boolean;
    FZStream: TZStreamRec;
    FZFlush: Integer;
    FZResult: Integer;
    FZOutSize: Integer;
    FZBuffer: TBytes;

    procedure _SetResponseStream(const AValue: TStream);
    procedure _SetStatus(const AStatusCode: Integer; const AStatusText: string = '');
  protected
    function ParseHeader: Boolean;
    procedure ParseRecvData(const ABuf: Pointer; ALen: Integer);

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
    constructor Create(const AConnection: TCrossHttpClientConnection);
    destructor Destroy; override;

    property Connection: ICrossHttpClientConnection read GetConnection;
    property Header: THttpHeader read GetHeader;
    property Cookies: TResponseCookies read GetCookies;
    property Content: TStream read GetContent;
    property ContentType: string read GetContentType;
    property StatusCode: Integer read GetStatusCode;
    property StatusText: string read GetStatusText;
  end;

  TCrossHttpClientSocket = class(TCrossSslSocket, ICrossHttpClientSocket)
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: THandle;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); override;

    function ReUseConnection(const AProtocol: string): Boolean; virtual;
  public
    procedure GetConnection(const AProtocol, AHost: string; const APort: Word;
      const ACallback: TCrossHttpGetConnectionProc); virtual;
  end;

  TCrossHttpClient = class(TInterfacedObject, ICrossHttpClient)
  private
    FCompressType: TCompressType;
    FHttpCli, FHttpsCli: ICrossHttpClientSocket;
    FIoThreads: Integer;
    FLock: ILock;
    FTimer: IEasyTimer;

    procedure _Lock; inline;
    procedure _Unlock; inline;

    procedure _ProcTimeout;
  protected
    function CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket; virtual;
  public
    constructor Create(const AIoThreads: Integer = 2;
      const ACompressType: TCompressType = ctNone);

    {$region '裸数据请求'}
    // 所有请求方法的核心
    procedure DoRequest(const AMethod, AUrl: string;
      const AHttpHeaders: THttpHeader;
      const ARequestBody: TCrossHttpChunkDataFunc;
      const AResponseStream: TStream;
      const AInitProc: TCrossHttpRequestInitProc;
      const ACallback: TCrossHttpResponseProc); overload;

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
  end;

const
  SND_BUF_SIZE = 32768;

implementation

{$region '辅助函数'}
procedure _AdjustOffsetCount(const ABodySize: Int64;
  var AOffset, ACount: Int64); overload;
begin
  {$region '修正 AOffset'}
  // 偏移为正数, 从头部开始计算偏移
  if (AOffset >= 0) then
  begin
    if (AOffset >= ABodySize) then
      AOffset := ABodySize - 1;
  end else
  // 偏移为负数, 从尾部开始计算偏移
  begin
    AOffset := ABodySize + AOffset;
  end;

  if (AOffset < 0) then
    AOffset := 0;
  {$endregion}

  {$region '修正 ACount'}
  // ACount<=0表示需要处理所有数据
  if (ACount <= 0) then
    ACount := ABodySize;

  if (ABodySize - AOffset < ACount) then
    ACount := ABodySize - AOffset;
  {$endregion}
end;

procedure _AdjustOffsetCount(const ABodySize: NativeInt;
  var AOffset, ACount: NativeInt); overload;
begin
  {$region '修正 AOffset'}
  // 偏移为正数, 从头部开始计算偏移
  if (AOffset >= 0) then
  begin
    if (AOffset >= ABodySize) then
      AOffset := ABodySize - 1;
  end else
  // 偏移为负数, 从尾部开始计算偏移
  begin
    AOffset := ABodySize + AOffset;
  end;

  if (AOffset < 0) then
    AOffset := 0;
  {$endregion}

  {$region '修正 ACount'}
  // ACount<=0表示需要处理所有数据
  if (ACount <= 0) then
    ACount := ABodySize;

  if (ABodySize - AOffset < ACount) then
    ACount := ABodySize - AOffset;
  {$endregion}
end;
{$endregion}

{ TCrossHttpClientConnection }

constructor TCrossHttpClientConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: THandle; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback);
begin
  // 肯定是要发起请求才会新建连接
  // 所以直接将连接状态锁定
  // 避免被别的请求占用
  _BeginRequest;

  inherited Create(AOwner, AClientSocket, AConnectType, AConnectCb);

  FWatch := TStopwatch.Create;
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

procedure TCrossHttpClientConnection._BeginRequest;
begin
  AtomicIncrement(FPending);
end;

procedure TCrossHttpClientConnection._EndRequest;
begin
  AtomicDecrement(FPending);
end;

function TCrossHttpClientConnection._IsIdle: Boolean;
begin
  Result := (AtomicCmpExchange(FPending, 0, 0) = 0);
end;

function TCrossHttpClientConnection._IsTimeout: Boolean;
begin
  // 暂时超时时间设置为2分钟
  // 实际连接每收到一个数据包, 都会更新计时器
  // 所以不用担心2分钟无法完成大数据的收取
  // 一个正常的响应, 如果数据很大会被拆分成很多小的数据包发回
  // 每个小的数据包不太可能2分钟还传不完, 如果真出现2分钟传不完一个小数据包的情况
  // 那是真应该判定超时了, 因为这个网络环境确实太恶劣了, 基本也无法完成正常的网络交互
  Result := (GetRequestStatus = rsReponsding)
    and (FWatch.ElapsedMilliseconds >= 120000);
end;

function TCrossHttpClientConnection._SetRequestStatus(
  const AStatus: TRequestStatus): TRequestStatus;
begin
  Result := TRequestStatus(AtomicExchange(FStatus, Integer(AStatus)));
end;

procedure TCrossHttpClientConnection._UpdateWatch;
begin
  FWatch.Reset;
  FWatch.Start;
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

            LChunkHeader := LChunkHeader + TEncoding.ANSI.GetBytes(IntToHex(LChunkSize, 0)) + [13, 10];

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

procedure TCrossHttpClientRequest._Send(const ASource: TCrossHttpChunkDataFunc;
  const ACallback: TCrossHttpResponseProc);
var
  LHttpConnection: ICrossHttpClientConnection;
  LResponse: ICrossHttpClientResponse;
  LSender: TCrossConnectionCallback;
begin
  LHttpConnection := FConnection;
  LResponse := FConnection.FResponse;
  (LResponse as TCrossHttpClientResponse).FCallback := ACallback;

  // 更新计时器
  FConnection._UpdateWatch;

  // 标记正在发送请求
  FConnection._SetRequestStatus(rsSending);

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
    begin
      if not ASuccess then
      begin
        LHttpConnection.Close;
        (LResponse as TCrossHttpClientResponse).TriggerResponseFailed(400);

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
        // 标记正在等待响应
        FConnection._SetRequestStatus(rsReponsding);
        LSender := nil;
        Exit;
      end;

      LHttpConnection.SendBuf(LData^, LCount, LSender);
    end;

  LSender(LHttpConnection, True);
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
  if (FHeader[HEADER_CONTENT_TYPE] = '') then
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
    + TCrossHttpUtils.UrlEncode(FPath, ['/']) + ' '
    + HTTP_VER_STR[FHttpVersion] + CRLF;

  LHeaderStr := LHeaderStr + FHeader.Encode;

  Result := TEncoding.ANSI.GetBytes(LHeaderStr);
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
  FRawRequest := TBytesStream.Create;

  FParseState := psHeader;
end;

destructor TCrossHttpClientResponse.Destroy;
begin
  FreeAndNil(FHeader);
  FreeAndNil(FRawRequest);
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

function TCrossHttpClientResponse.ParseHeader: Boolean;
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
  SetString(FRawResponseHeader, MarshaledAString(FRawRequest.Memory), FRawRequest.Size);
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
    if SameText(LHeader.Name, HEADER_SETCOOKIE) then
      FCookies.Add(TResponseCookie.Create(LHeader.Value, FConnection.FHost));
  end;

  FContentType := FHeader[HEADER_CONTENT_TYPE];
  FContentLength := StrToInt64Def(FHeader[HEADER_CONTENT_LENGTH], -1);

  // 数据的编码方式
  // 只有一种编码方式: chunked
  // 如果 Transfer-Encoding 不存在于 Header 中, 则数据是连续的, 不采用分块编码
  // 理论上 Transfer-Encoding 和 Content-Length 只应该存在其中一个
  FTransferEncoding := FHeader[HEADER_TRANSFER_ENCODING];

  FIsChunked := SameText(FTransferEncoding, 'chunked');

  // 数据的压缩方式
  // 可能的值为: gzip deflate br 其中之一
  // br: Brotli压缩算法, Brotli通常比gzip和deflate更高效
  FContentEncoding := FHeader[HEADER_CONTENT_ENCODING];

  Result := True;
end;

procedure TCrossHttpClientResponse.ParseRecvData(const ABuf: Pointer;
  ALen: Integer);
var
  LHttpConnection: ICrossHttpClientConnection;
  LRequest: ICrossHttpClientRequest;
  pch: PByte;
  LChunkSize: Integer;
  LLineStr: string;
begin
  {
  HTTP/1.1 200 OK
  Content-Type: application/json;charset=utf-8
  Content-Encoding: gzip
  Transfer-Encoding: chunked
  }
  {
  HTTP/1.1 200 OK
  Content-Type: text/plain
  Transfer-Encoding: chunked

  7\r\n
  Chunk 1\r\n
  6\r\n
  Chunk 2\r\n
  0\r\n
  \r\n
  }
  LHttpConnection := FConnection;
  LRequest := FConnection.FRequest;

  try
    // 在这里解析服务端发送过来的响应数据
    pch := ABuf;
    while (ALen > 0) do
    begin
      // 使用循环处理粘包, 比递归调用节省资源
      while (ALen > 0) and (FParseState <> psDone) do
      begin
        case FParseState of
          psHeader:
            begin
              case pch^ of
                13{\r}: Inc(FCRCount);
                10{\n}: Inc(FLFCount);
              else
                FCRCount := 0;
                FLFCount := 0;
              end;

              // 写入请求数据
              FRawRequest.Write(pch^, 1);
              Dec(ALen);
              Inc(pch);

              // HTTP头已接收完毕(\r\n\r\n是HTTP头结束的标志)
              if (FCRCount = 2) and (FLFCount = 2) then
              begin
                FCRCount := 0;
                FLFCount := 0;

                if not ParseHeader then
                begin
                  TriggerResponseFailed(500, 'Invalid HTTP response header');
                  Exit;
                end;

                // 如果 ContentLength 大于 0, 或者是 Chunked 编码, 则还需要接收 body 数据
                if (FContentLength > 0) or FIsChunked then
                begin
                  FResponseBodySize := 0;

                  if FIsChunked then
                  begin
                    FParseState := psChunkSize;
                    FChunkSizeStream := TBytesStream.Create(nil);
                  end else
                    FParseState := psBodyData;

                  TriggerResponseDataBegin;
                end else
                begin
                  FParseState := psDone;
                  Break;
                end;
              end;
            end;

          // 非Chunked编码的Post数据(有 ContentLength)
          psBodyData:
            begin
              LChunkSize := Min((FContentLength - FResponseBodySize), ALen);
              TriggerResponseData(pch, LChunkSize);

              Inc(FResponseBodySize, LChunkSize);
              Inc(pch, LChunkSize);
              Dec(ALen, LChunkSize);

              if (FResponseBodySize >= FContentLength) then
              begin
                FParseState := psDone;
                TriggerResponseDataEnd;
                Break;
              end;
            end;

          // Chunked编码: 块尺寸
          psChunkSize:
            begin
              case pch^ of
                13{\r}: Inc(FCRCount);
                10{\n}: Inc(FLFCount);
              else
                FCRCount := 0;
                FLFCount := 0;
                FChunkSizeStream.Write(pch^, 1);
              end;
              Dec(ALen);
              Inc(pch);

              if (FCRCount = 1) and (FLFCount = 1) then
              begin
                SetString(LLineStr, MarshaledAString(FChunkSizeStream.Memory), FChunkSizeStream.Size);
                FParseState := psChunkData;
                FChunkSize := StrToIntDef('$' + Trim(LLineStr), -1);
                FChunkLeftSize := FChunkSize;
              end;
            end;

          // Chunked编码: 块数据
          psChunkData:
            begin
              if (FChunkLeftSize > 0) then
              begin
                LChunkSize := Min(FChunkLeftSize, ALen);
                TriggerResponseData(pch, LChunkSize);

                Inc(FResponseBodySize, LChunkSize);
                Dec(FChunkLeftSize, LChunkSize);
                Inc(pch, LChunkSize);
                Dec(ALen, LChunkSize);
              end;

              if (FChunkLeftSize <= 0) then
              begin
                FParseState := psChunkEnd;
                FCRCount := 0;
                FLFCount := 0;
              end;
            end;

          // Chunked编码: 块结束符\r\n
          psChunkEnd:
            begin
              case pch^ of
                13{\r}: Inc(FCRCount);
                10{\n}: Inc(FLFCount);
              else
                FCRCount := 0;
                FLFCount := 0;
              end;
              Dec(ALen);
              Inc(pch);

              if (FCRCount = 1) and (FLFCount = 1) then
              begin
                // 最后一块的ChunSize为0
                if (FChunkSize > 0) then
                begin
                  FParseState := psChunkSize;
                  FChunkSizeStream.Clear;
                  FCRCount := 0;
                  FLFCount := 0;
                end else
                begin
                  FParseState := psDone;
                  FreeAndNil(FChunkSizeStream);
                  TriggerResponseDataEnd;
                  Break;
                end;
              end;
            end;
        end;
      end;

      // 响应数据接收完毕
      if (FParseState = psDone) then
      begin
        FParseState := psHeader;
        FRawRequest.Clear;
        FCRCount := 0;
        FLFCount := 0;
        FResponseBodySize := 0;

        // 只有在等待响应状态的情况才应该触发完成响应回调
        // 因为有可能响应完成的数据在超时后才到来, 这时候请求状态已经被置为超时
        // 不应该再触发完成回调
        if (LHttpConnection.RequestStatus = rsReponsding) then
          TriggerResponseSuccess;
      end;
    end;
  except
    on e: Exception do
      TriggerResponseFailed(400, e.Message);
  end;
end;

procedure TCrossHttpClientResponse.TriggerResponseFailed(const AStatusCode: Integer; const AStatusText: string);
begin
  try
    _SetStatus(AStatusCode, AStatusText);

    FConnection._SetRequestStatus(rsRespondFailed);

    if Assigned(FCallback) then
      FCallback(FConnection.FResponse);
  finally
    FConnection._EndRequest;
  end;
end;

procedure TCrossHttpClientResponse.TriggerResponseSuccess;
begin
  try
    FConnection._SetRequestStatus(rsRespondSuccess);

    if Assigned(FCallback) then
      FCallback(FConnection.FResponse);
  finally
    FConnection._EndRequest;
  end;
end;

procedure TCrossHttpClientResponse.TriggerResponseData(const ABuf: Pointer;
  const ALen: Integer);
begin
  if (FResponseBodyStream = nil)
    or (ABuf = nil) or (ALen <= 0) then Exit;

  // 如果数据是压缩的, 进行解压
  if FZCompressed then
  begin
    // 往输入缓冲区填入新数据
    // 对于使用 inflate 函数解压缩数据, 通常不需要使用 Z_FINISH 进行收尾。
    // Z_FINISH 选项通常在压缩时使用, 以表示已经完成了压缩的数据块。
    // 在解压缩过程中, inflate 函数会自动处理数据流的结束。
    // 当输入数据流中的所有数据都被解压缩时, inflate 函数会返回 Z_STREAM_END,
    // 这表示数据流已经结束，不需要额外的处理。
    FZStream.avail_in := ALen;
    FZStream.next_in := ABuf;
    FZFlush := Z_NO_FLUSH;

    repeat
      // 返回 Z_STREAM_END 表示所有数据处理完毕
      if (FZResult = Z_STREAM_END) then Break;

      // 解压数据输出缓冲区
      FZStream.avail_out := ZLIB_BUF_SIZE;
      FZStream.next_out := @FZBuffer[0];

      // 进行解压处理
      // 输入缓冲区数据可以大于输出缓冲区
      // 这种情况可以多次调用 inflate 分批解压,
      // 直到 avail_in=0  表示当前输入缓冲区数据已解压完毕
      FZResult := inflate(FZStream, FZFlush);

      // 解压出错之后直接结束
      if (FZResult < 0) then
      begin
        FZOutSize := 0;
        Break;
      end;

      // 已解压完成的数据大小
      FZOutSize := ZLIB_BUF_SIZE - FZStream.avail_out;

      // 保存已解压的数据
      if (FZOutSize > 0) then
        FResponseBodyStream.Write(FZBuffer[0], FZOutSize);
    until ((FZResult = Z_STREAM_END) or (FZStream.avail_in = 0));
  end else
    FResponseBodyStream.Write(ABuf^, ALen);
end;

procedure TCrossHttpClientResponse.TriggerResponseDataBegin;
var
  LCompressType: TCompressType;
begin
  if (FResponseBodyStream = nil) then
  begin
    FResponseBodyStream := TBytesStream.Create;
    FNeedFreeResponseBodyStream := True;
  end;
  FResponseBodyStream.Size := 0;

  FZCompressed := False;
  LCompressType := ctNone;

  // 根据 FContentEncoding(gzip deflate br) 判断使用哪种方式解压
  // 目前暂时只支持 gzip deflate
  // 初始化解压库
  if (FContentEncoding <> '') then
  begin
    if SameText(FContentEncoding, 'gzip') then
    begin
      LCompressType := ctGZip;
      FZCompressed := True;
    end else
    if SameText(FContentEncoding, 'deflate') then
    begin
      LCompressType := ctDeflate;
      FZCompressed := True;
    end;

    if FZCompressed then
    begin
      SetLength(FZBuffer, ZLIB_BUF_SIZE);

      FillChar(FZStream, SizeOf(TZStreamRec), 0);
      FZResult := Z_OK;
      FZFlush := Z_NO_FLUSH;

      if (inflateInit2(FZStream, ZLIB_WINDOW_BITS[LCompressType]) <> Z_OK) then
      begin
        TriggerResponseFailed(400, 'inflateInit2 failed');
        Abort;
      end;
    end;
  end;
end;

procedure TCrossHttpClientResponse.TriggerResponseDataEnd;
begin
  if FZCompressed then
    inflateEnd(FZStream);

  if (FResponseBodyStream <> nil) and (FResponseBodyStream.Size > 0) then
    FResponseBodyStream.Position := 0;
end;

procedure TCrossHttpClientResponse.TriggerResponseTimeout;
begin
  try
    // 408 = Request Time-out
    _SetStatus(408);

    FConnection._SetRequestStatus(rsRespondTimeout);

    if Assigned(FCallback) then
      FCallback(FConnection.FResponse);
  finally
    FConnection._EndRequest;
  end;
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

function TCrossHttpClientSocket.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: THandle; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossHttpClientConnection.Create(AOwner, AClientSocket, AConnectType, AConnectCb);
end;

procedure TCrossHttpClientSocket.GetConnection(const AProtocol, AHost: string;
  const APort: Word; const ACallback: TCrossHttpGetConnectionProc);
var
  LConns: TCrossConnections;
  LConn: ICrossConnection;
  LHttpConn: ICrossHttpClientConnection;
  LHttpConnObj: TCrossHttpClientConnection;
begin
  {$region '先从已有连接中找空闲的连接'}
  if ReUseConnection(AProtocol) then
  begin
    LConns := LockConnections;
    try
      for LConn in LConns.Values do
      begin
        LHttpConn := LConn as ICrossHttpClientConnection;
        LHttpConnObj := LHttpConn as TCrossHttpClientConnection;

        if (LHttpConnObj.ConnectStatus = csConnected)
          and (LHttpConnObj.FProtocol = AProtocol)
          and (LHttpConnObj.FHost = AHost)
          and (LHttpConnObj.FPort = APort)
          and LHttpConnObj._IsIdle then
        begin
          if Assigned(ACallback) then
            ACallback(LHttpConn);

          Exit;
        end;
      end;
    finally
      UnlockConnections;
    end;
  end;
  {$endregion}

  {$region '没有空闲连接则建立新连接'}
  LHttpConn := nil;
  Connect(AHost, APort,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if ASuccess then
      begin
        LHttpConn := AConnection as ICrossHttpClientConnection;
        LHttpConnObj := LHttpConn as TCrossHttpClientConnection;
        LHttpConnObj.FProtocol := AProtocol;
        LHttpConnObj.FHost := AHost;
        LHttpConnObj.FPort := APort;
      end;

      if Assigned(ACallback) then
        ACallback(LHttpConn);
    end);
  {$endregion}
end;

procedure TCrossHttpClientSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnObj: TCrossHttpClientConnection;
  LResponseObj: TCrossHttpClientResponse;
begin
  LConnObj := AConnection as TCrossHttpClientConnection;
  LConnObj._UpdateWatch;

  LResponseObj := LConnObj.FResponse as TCrossHttpClientResponse;
  LResponseObj.ParseRecvData(ABuf, ALen);
end;

function TCrossHttpClientSocket.ReUseConnection(
  const AProtocol: string): Boolean;
begin
  Result := SameText(AProtocol, HTTP) or SameText(AProtocol, HTTPS);
end;

{ TCrossHttpClient }

constructor TCrossHttpClient.Create(const AIoThreads: Integer;
  const ACompressType: TCompressType);
begin
  FIoThreads := AIoThreads;
  FCompressType := ACompressType;
  FLock := TLock.Create;
  FTimer := TEasyTimer.Create('',
    procedure
    begin
      _ProcTimeout;
    end,
    5000);
end;

function TCrossHttpClient.CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket;
begin
  if SameText(AProtocol, HTTP) then
  begin
    if (FHttpCli = nil) then
      FHttpCli := TCrossHttpClientSocket.Create(FIoThreads, False);

    Result := FHttpCli;
  end else
  if SameText(AProtocol, HTTPS) then
  begin
    if (FHttpsCli = nil) then
      FHttpsCli := TCrossHttpClientSocket.Create(FIoThreads, True);

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
  LProtocol, LHost, LPath: string;
  LPort: Word;
  LHttpCli: ICrossHttpClientSocket;
begin
  if not TCrossHttpUtils.ExtractUrl(AUrl, LProtocol, LHost, LPort, LPath) then
  begin
    if Assigned(ACallback) then
      ACallback(nil);
    Exit;
  end;

  // 根据协议创建HttpCli对象
  _Lock;
  try
    LHttpCli := CreateHttpCli(LProtocol);
  finally
    _Unlock;
  end;

  // 获取可用连接
  LHttpCli.GetConnection(LProtocol, LHost, LPort,
    procedure(const AHttpConnection: ICrossHttpClientConnection)
    var
      LHttpConnectionObj: TCrossHttpClientConnection;
      LRequestObj: TCrossHttpClientRequest;
      LResponseObj: TCrossHttpClientResponse;
      LHttpHeader: TNameValue;
    begin
      // 没取到可用连接, 应该是连接失败了
      if (AHttpConnection = nil) then
      begin
        if Assigned(ACallback) then
          ACallback(nil);
        Exit;
      end;

      // 取到了可用连接, 准备发送请求
      LHttpConnectionObj := AHttpConnection as TCrossHttpClientConnection;

      // 新建请求对象
      LRequestObj := TCrossHttpClientRequest.Create(LHttpConnectionObj);
      LRequestObj.FCompressType := FCompressType;

      // 新建响应对象
      LResponseObj := TCrossHttpClientResponse.Create(LHttpConnectionObj);

      // 将请求和响应对象放到连接中
      LHttpConnectionObj.FRequest := LRequestObj;
      LHttpConnectionObj.FResponse := LResponseObj;

      // 设置请求头
      if (AHttpHeaders <> nil) then
      begin
        for LHttpHeader in AHttpHeaders do
          LRequestObj.Header[LHttpHeader.Name] := LHttpHeader.Value;
      end;

      // 设置响应数据流
      LResponseObj._SetResponseStream(AResponseStream);

      // 调用初始化函数
      if Assigned(AInitProc) then
        AInitProc(LRequestObj);

      // 发起请求
      LRequestObj.DoRequest(AMethod, LPath, ARequestBody, ACallback);
    end);
end;

procedure TCrossHttpClient.DoRequest(const AMethod, AUrl: string;
  const AHttpHeaders: THttpHeader; const ARequestBody: Pointer;
  const ABodySize: NativeInt; const AResponseStream: TStream;
  const AInitProc: TCrossHttpRequestInitProc;
  const ACallback: TCrossHttpResponseProc);
var
  P: PByte;
  LBodySize: NativeInt;
  LChunkDataFunc: TCrossHttpChunkDataFunc;
begin
  P := ARequestBody;
  LBodySize := ABodySize;

  if (P <> nil) and (LBodySize > 0) then
    LChunkDataFunc :=
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
      end
  else
    LChunkDataFunc := nil;

  DoRequest(AMethod, AUrl, AHttpHeaders,
    LChunkDataFunc,
    AResponseStream,
    AInitProc,
    ACallback);
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
  _AdjustOffsetCount(Length(LBody), LOffset, LCount);

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
    _AdjustOffsetCount(ARequestBody.Size, LOffset, LCount);

    if (ARequestBody is TCustomMemoryStream) then
    begin
      DoRequest(AMethod, AUrl, AHttpHeaders,
        Pointer(IntPtr(TCustomMemoryStream(ARequestBody).Memory) + LOffset), LCount,
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
      if (LCount <= 0) then Exit(False);

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
  begin
    LConns := AHttpCli.LockConnections;
    try
      for LConn in LConns.Values do
      begin
        LHttpConn := LConn as ICrossHttpClientConnection;
        LHttpConnObj := LHttpConn as TCrossHttpClientConnection;

        if not LHttpConnObj.IsClosed
          and LHttpConnObj._IsTimeout then
        begin
          (LHttpConnObj.FResponse as TCrossHttpClientResponse).TriggerResponseTimeout;
        end;
      end;
    finally
      AHttpCli.UnlockConnections;
    end;
  end;
var
  LHttpCliArr: TArray<ICrossHttpClientSocket>;
  LHttpCli: ICrossHttpClientSocket;
begin
  LHttpCliArr := [];

  _Lock;
  try
    if (FHttpCli <> nil) then
      LHttpCliArr := LHttpCliArr + [FHttpCli];

    if (FHttpsCli <> nil) then
      LHttpCliArr := LHttpCliArr + [FHttpsCli];
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

end.
