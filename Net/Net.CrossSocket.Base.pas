{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Base;

{$I zLib.inc}

// 是否将大块数据分成小块发送(仅IOCP下有效)
// 注意: 开启该开关的情况下, 同一个连接不要在一次发送尚未结束时开始另一次发送
//       否则会导致两块数据被分成小块后出现交错
{.$DEFINE __LITTLE_PIECE__}

{$IF defined(DEBUG) or defined(madExcept)}
  {$DEFINE __DEBUG__}
{$ENDIF}

interface

uses
  SysUtils,
  Classes,
  Math,
  Generics.Collections,

  {$IFDEF FPC}
  DTF.RTL,
  {$ENDIF}

  Net.SocketAPI,
  Net.CrossProxy,
  Utils.StrUtils,
  Utils.SyncObjs,
  Utils.Rtti;

const
  // 唯一编号类别
  // 唯一编号共64位, 高2位用于表示类别
  UID_RAW        = $0;
  UID_LISTEN     = $1;
  UID_CONNECTION = $2;

  // 最大唯一编号(62个1)
  UID_MASK       = UInt64($3FFFFFFFFFFFFFFF);

  IPv4_ALL   = '0.0.0.0';
  IPv6_ALL   = '::';
  IPv4v6_ALL = '';
  IPv4_LOCAL = '127.0.0.1';
  IPv6_LOCAL = '::1';

type
  ECrossSocket = class(Exception);

  ICrossSocket = interface;
  ICrossListen = interface;
  ICrossConnection = interface;
  TCrossSocketBase = class;
  TIoEventThread = class;

  /// <summary>
  ///   连接类型
  /// </summary>
  TConnectType = (
    /// <summary>
    ///   未知
    /// </summary>
    ctUnknown,
    /// <summary>
    ///   由监听Accept生成的连接
    /// </summary>
    ctAccept,
    /// <summary>
    ///   由Connect调用生成的连接
    /// </summary>
    ctConnect);

  /// <summary>
  ///   连接状态
  /// </summary>
  TConnectStatus = (
    /// <summary>
    ///   未知
    /// </summary>
    csUnknown,
    /// <summary>
    ///   正在连接
    /// </summary>
    csConnecting,
    /// <summary>
    ///   正在握手(SSL)
    /// </summary>
    csHandshaking,
    /// <summary>
    ///   已连接
    /// </summary>
    csConnected,
    /// <summary>
    ///   已断开
    /// </summary>
    csDisconnected,
    /// <summary>
    ///   已关闭
    /// </summary>
    csClosed);

  TCrossListenCallback = reference to procedure(const AListen: ICrossListen; const ASuccess: Boolean);
  TCrossConnectionCallback = reference to procedure(const AConnection: ICrossConnection; const ASuccess: Boolean);

  /// <summary>
  ///   基础数据接口
  /// </summary>
  ICrossData = interface
  ['{988404A3-D297-4C6D-9A76-16E50553596E}']
    function GetOwner: TCrossSocketBase;
    function GetSocket: TSocket;
    function GetUID: UInt64;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean;
    function GetTag: string;
    function GetUserData: Pointer;
    function GetUserObject: TObject;
    function GetUserInterface: IInterface;

    procedure SetTag(const AValue: string);
    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TObject);
    procedure SetUserInterface(const AValue: IInterface);

    /// <summary>
    ///   更新套接字地址信息
    /// </summary>
    /// <remarks>
    ///   LocalAddr, LocalPort, PeerAddr, PeerPort 都依赖于该方法
    /// </remarks>
    procedure UpdateAddr;

    /// <summary>
    ///   关闭套接字
    /// </summary>
    procedure Close;

    /// <summary>
    ///   调试信息
    /// </summary>
    function DebugInfo: string;

    /// <summary>
    ///   宿主对象
    /// </summary>
    property Owner: TCrossSocketBase read GetOwner;

    /// <summary>
    ///   套接字句柄
    /// </summary>
    property Socket: TSocket read GetSocket;

    /// <summary>
    ///   唯一编号
    /// </summary>
    property UID: UInt64 read GetUID;

    /// <summary>
    ///   本地IP地址
    /// </summary>
    property LocalAddr: string read GetLocalAddr;

    /// <summary>
    ///   本地端口
    /// </summary>
    property LocalPort: Word read GetLocalPort;

    /// <summary>
    ///   是否已关闭
    /// </summary>
    property IsClosed: Boolean read GetIsClosed;

    /// <summary>
    ///   连接标签
    /// </summary>
    property Tag: string read GetTag write SetTag;

    /// <summary>
    ///   用户数据(可以用于存储用户自定义的数据结构)
    /// </summary>
    property UserData: Pointer read GetUserData write SetUserData;

    /// <summary>
    ///   用户数据(可以用于存储用户自定义的数据结构)
    /// </summary>
    property UserObject: TObject read GetUserObject write SetUserObject;

    /// <summary>
    ///   用户数据(可以用于存储用户自定义的数据结构)
    /// </summary>
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;
  TCrossDatas = TDictionary<UInt64, ICrossData>;

  /// <summary>
  ///   监听接口
  /// </summary>
  ICrossListen = interface(ICrossData)
  ['{4008919E-8F16-4BBD-A68D-2FD1DE630702}']
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;

    /// <summary>
    ///   PF_xxx
    /// </summary>
    property Family: Integer read GetFamily;

    /// <summary>
    ///   SOCK_xxx
    /// </summary>
    property SockType: Integer read GetSockType;

    /// <summary>
    ///   IPPROTO_xxx
    /// </summary>
    property Protocol: Integer read GetProtocol;
  end;
  TCrossListens = TDictionary<UInt64, ICrossListen>;

  /// <summary>
  ///   连接接口
  /// </summary>
  ICrossConnection = interface(ICrossData)
  ['{13C2A39E-C918-49B9-BBD3-A99110F94D1B}']
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetPeerHost: string;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;
    function GetLastNetError: Integer;
    function GetProxyError: string;

    procedure SetConnectStatus(const AValue: TConnectStatus);
    procedure SetLastNetError(const AValue: Integer);

    /// <summary>
    ///   优雅关闭
    /// </summary>
    procedure Disconnect;

    /// <summary>
    ///   发送内存块数据
    /// </summary>
    /// <param name="ABuffer">
    ///   内存块指针
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBuf(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送无类型数据
    /// </summary>
    /// <param name="ABuffer">
    ///   无类型数据
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBuf(const ABuffer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABytes">
    ///   字节数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBytes(const ABytes: TBytes; const AOffset, ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABytes">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBytes(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送数据流(用于发送较大的数据)
    /// </summary>
    /// <param name="AStream">
    ///   流数据
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    /// <remarks>
    ///   由于是纯异步发送, 所以务必保证发送过程中 AStream 的有效性, 将 AStream 的释放放到回调函数中去 <br />
    /// </remarks>
    procedure SendStream(const AStream: TStream;
      const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   连接IP地址
    /// </summary>
    property PeerAddr: string read GetPeerAddr;

    /// <summary>
    ///   连接端口
    /// </summary>
    property PeerPort: Word read GetPeerPort;

    /// <summary>
    ///   连接地址名(只有Connect产生的连接这个属性才有值)
    /// </summary>
    property PeerHost: string read GetPeerHost;

    /// <summary>
    ///   连接类型
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       ctAccept, 由监听Accept生成的连接;
    ///     </item>
    ///     <item>
    ///       ctConnect, 由Connect调用生成的连接
    ///     </item>
    ///   </list>
    /// </remarks>
    property ConnectType: TConnectType read GetConnectType;

    /// <summary>
    ///   连接状态
    /// </summary>
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;

    /// <summary>
    ///   最近一次底层网络错误码(0=无错误)
    /// </summary>
    /// <remarks>
    ///   由平台实现层(Iocp/Epoll/Kqueue)在 connect/send/recv 等失败路径设置,
    ///   上层在连接失败回调中读取, 用于生成带有具体 WSA/errno 错误码的诊断日志
    /// </remarks>
    property LastNetError: Integer read GetLastNetError write SetLastNetError;
    /// <summary>
    ///   代理握手失败的协议级错误信息, 由上层连接失败回调读取
    /// </summary>
    property ProxyError: string read GetProxyError;
  end;
  TCrossConnections = TDictionary<UInt64, ICrossConnection>;

  TCrossIoThreadEvent = procedure(const Sender: TObject; const AIoThread: TIoEventThread) of object;
  TCrossListenEvent = procedure(const Sender: TObject; const AListen: ICrossListen) of object;
  TCrossConnectEvent = procedure(const Sender: TObject; const AConnection: ICrossConnection) of object;
  TCrossDataEvent = procedure(const Sender: TObject; const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer) of object;

  /// <summary>
  ///   跨平台Socket接口
  /// </summary>
  ICrossSocket = interface
  ['{2371CC3F-EB38-4C5D-8FA9-C913B9CD37A0}']
    function GetIoThreads: Integer;
    function GetConnectionsCount: Integer;
    function GetListensCount: Integer;

    function GetOnIoThreadBegin: TCrossIoThreadEvent;
    function GetOnIoThreadEnd: TCrossIoThreadEvent;
    function GetOnConnected: TCrossConnectEvent;
    function GetOnDisconnected: TCrossConnectEvent;
    function GetOnListened: TCrossListenEvent;
    function GetOnListenEnd: TCrossListenEvent;
    function GetOnReceived: TCrossDataEvent;
    function GetOnSent: TCrossDataEvent;

    function GetKeepAliveIdle: Integer;
    function GetKeepAliveInterval: Integer;
    function GetKeepAliveCount: Integer;

    procedure SetOnIoThreadBegin(const AValue: TCrossIoThreadEvent);
    procedure SetOnIoThreadEnd(const AValue: TCrossIoThreadEvent);
    procedure SetOnConnected(const AValue: TCrossConnectEvent);
    procedure SetOnDisconnected(const AValue: TCrossConnectEvent);
    procedure SetOnListened(const AValue: TCrossListenEvent);
    procedure SetOnListenEnd(const AValue: TCrossListenEvent);
    procedure SetOnReceived(const AValue: TCrossDataEvent);
    procedure SetOnSent(const AValue: TCrossDataEvent);

    procedure SetKeepAliveIdle(const AValue: Integer);
    procedure SetKeepAliveInterval(const AValue: Integer);
    procedure SetKeepAliveCount(const AValue: Integer);

    /// <summary>
    ///   启动IO循环
    /// </summary>
    procedure StartLoop;

    /// <summary>
    ///   停止IO循环
    /// </summary>
    procedure StopLoop;

    /// <summary>
    ///   处理IO事件(内部使用)
    /// </summary>
    function ProcessIoEvent: Boolean;

    /// <summary>
    ///   监听端口
    /// </summary>
    /// <param name="AHost">
    ///   监听地址:
    ///   <list type="bullet">
    ///     <item>
    ///       要监听IPv4和IPv6所有地址, 请设置为空
    ///     </item>
    ///     <item>
    ///       要单独监听IPv4, 请设置为 '0.0.0.0'
    ///     </item>
    ///     <item>
    ///       要单独监听IPv6, 请设置为 '::'
    ///     </item>
    ///     <item>
    ///       要监听IPv4环路地址, 请设置为 '127.0.0.1'
    ///     </item>
    ///     <item>
    ///       要监听IPv6环路地址, 请设置为 '::1'
    ///     </item>
    ///   </list>
    /// </param>
    /// <param name="APort">
    ///   监听端口, 设置为0则随机监听一个可用的端口
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil);

    /// <summary>
    ///   连接到主机
    /// </summary>
    /// <param name="AHost">
    ///   主机地址
    /// </param>
    /// <param name="APort">
    ///   主机端口
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    procedure Connect(const AHost: string; const APort: Word;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   连接到主机
    /// </summary>
    /// <param name="AHost">
    ///   主机地址
    /// </param>
    /// <param name="APort">
    ///   主机端口
    /// </param>
    /// <param name="ALocalPort">
    ///   本地端口(一般不需要指定, 传0由系统随机分配)
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    procedure Connect(const AHost: string; const APort, ALocalPort: Word;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送数据
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    /// <param name="ABuf">
    ///   数据指针
    /// </param>
    /// <param name="ALen">
    ///   数据尺寸
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    /// <remarks>
    ///   由于发送是异步的, 所以需要调用者保证发送完成之前数据的有效性
    /// </remarks>
    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   关闭所有连接
    /// </summary>
    /// <remarks>
    ///   正在发送中的数据将会丢失
    /// </remarks>
    procedure CloseAllConnections;

    /// <summary>
    ///   关闭所有监听
    /// </summary>
    procedure CloseAllListens;

    /// <summary>
    ///   关闭所有监听及连接
    /// </summary>
    procedure CloseAll;

    /// <summary>
    ///   断开所有连接
    /// </summary>
    /// <remarks>
    ///   正在发送中的数据会被送达
    /// </remarks>
    procedure DisconnectAll;

    /// <summary>
    ///   加锁并返回所有连接
    /// </summary>
    function LockConnections: TCrossConnections;

    /// <summary>
    ///   解锁连接
    /// </summary>
    procedure UnlockConnections;

    /// <summary>
    ///   加锁并返回所有监听
    /// </summary>
    function LockListens: TCrossListens;

    /// <summary>
    ///   解锁监听
    /// </summary>
    procedure UnlockListens;

    /// <summary>
    ///   IO线程数
    /// </summary>
    property IoThreads: Integer read GetIoThreads;

    /// <summary>
    ///   连接数
    /// </summary>
    property ConnectionsCount: Integer read GetConnectionsCount;

    /// <summary>
    ///   监听数
    /// </summary>
    property ListensCount: Integer read GetListensCount;

    /// <summary>
    ///   TCP KeepAlive 空闲秒数, 默认 5
    /// </summary>
    property KeepAliveIdle: Integer read GetKeepAliveIdle write SetKeepAliveIdle;

    /// <summary>
    ///   TCP KeepAlive 探测间隔秒数, 默认 3
    /// </summary>
    property KeepAliveInterval: Integer read GetKeepAliveInterval write SetKeepAliveInterval;

    /// <summary>
    ///   TCP KeepAlive 探测次数, 默认 5
    /// </summary>
    property KeepAliveCount: Integer read GetKeepAliveCount write SetKeepAliveCount;

    /// <summary>
    ///   IO线程开始事件
    /// </summary>
    property OnIoThreadBegin: TCrossIoThreadEvent read GetOnIoThreadBegin write SetOnIoThreadBegin;

    /// <summary>
    ///   IO线程结束事件
    /// </summary>
    property OnIoThreadEnd: TCrossIoThreadEvent read GetOnIoThreadEnd write SetOnIoThreadEnd;

    /// <summary>
    ///   监听成功事件
    /// </summary>
    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;

    /// <summary>
    ///   监听结束事件
    /// </summary>
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;

    /// <summary>
    ///   连接成功事件
    /// </summary>
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;

    /// <summary>
    ///   连接断开事件
    /// </summary>
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;

    /// <summary>
    ///   收到数据事件
    /// </summary>
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;

    /// <summary>
    ///   发出数据事件
    /// </summary>
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  TCrossData = class abstract(TInterfacedObject, ICrossData)
  private
    // 在 FPC 中, 32位程序的 AtomicIncrement 只支持32位整数
    class var FCrossUID: {$IF defined(DELPHI) or defined(CPU64)}UInt64{$ELSE}UInt32{$ENDIF};
  private
    FOwner: TCrossSocketBase;
    FSocket: TSocket;
    FUID: UInt64;
    FLocalAddr: string;
    FLocalPort: Word;
    FTag: string;
    FUserData: Pointer;
    FUserObject: TObject;
    FUserInterface: IInterface;
    FLock: ILock;
  protected
    procedure _Lock; inline;
    procedure _Unlock; inline;
  protected
    function GetOwner: TCrossSocketBase;
    function GetUIDTag: Byte; virtual;
    function GetUID: UInt64;
    function GetSocket: TSocket;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean; virtual; abstract;
    function GetTag: string;
    function GetUserData: Pointer;
    function GetUserObject: TObject;
    function GetUserInterface: IInterface;

    procedure SetTag(const AValue: string);
    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TObject);
    procedure SetUserInterface(const AValue: IInterface);
  public
    constructor Create(const AOwner: TCrossSocketBase;
      const ASocket: TSocket); virtual;
    destructor Destroy; override;

    procedure UpdateAddr; virtual;
    procedure Close; virtual; abstract;

    function DebugInfo: string; virtual; abstract;

    property Owner: TCrossSocketBase read GetOwner;
    property Socket: TSocket read GetSocket;
    property UID: UInt64 read GetUID;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
    property Tag: string read GetTag write SetTag;
    property UserData: Pointer read GetUserData write SetUserData;
    property UserObject: TObject read GetUserObject write SetUserObject;
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;

  TCrossListenBase = class(TCrossData, ICrossListen)
  private
    FFamily: Integer;
    FSockType: Integer;
    FProtocol: Integer;
    FClosed: Integer;
    FGeneration: Integer;
    FPublished: Integer;
  protected
    function GetUIDTag: Byte; override;
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;
    function GetIsClosed: Boolean; override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer); reintroduce; virtual;

    procedure Close; override;
    function DebugInfo: string; override;
    function _IsPublished: Boolean;
    property Generation: Integer read FGeneration;
  end;

  TCrossConnectAddr = record
    Family, SockType, Protocol: Integer;
    Addr: TRawSockAddrIn;
  end;

  // 一次 Connect 的状态由接口保活，不反向持有各次连接尝试。
  TCrossConnectOp = class(TInterfacedObject)
  private
    FLock: ILock;
    FHost: string;
    FLogicalPort, FLocalPort: Word;
    FGeneration, FNextIndex: Integer;
    FAddrs: TArray<TCrossConnectAddr>;
    FCallback: TCrossConnectionCallback;
    FCompleted: Boolean;
    function GetCompleted: Boolean;
  public
    constructor Create(const AHost: string; const ALogicalPort, ALocalPort: Word;
      const AGeneration: Integer; const AAddrs: TArray<TCrossConnectAddr>;
      const ACallback: TCrossConnectionCallback);
    function NextAddr(out AAddr: TCrossConnectAddr): Boolean;
    function HasNextAddr: Boolean;
    function CreateCallback: TCrossConnectionCallback;
    procedure Complete(const AConnection: ICrossConnection; const ASuccess: Boolean);
    property Host: string read FHost;
    property LogicalPort: Word read FLogicalPort;
    property LocalPort: Word read FLocalPort;
    property Generation: Integer read FGeneration;
    property Completed: Boolean read GetCompleted;
  end;

  TCrossConnectionBase = class(TCrossData, ICrossConnection)
  public const
    SND_BUF_SIZE = 32768;
  private
    FPeerAddr: string;
    FPeerPort: Word;
    FPeerHost: string;
    FConnectType: TConnectType;
    FConnectStatus: Integer;
    FLastNetError: Integer;
    FRecvLock, FSentLock: ILock;
    FConnectCb: TCrossConnectionCallback;
    FProxySettings: TCrossProxySettings;
    FProxyTargetHost: string;
    FProxyTargetPort: Word;
    FProxyStage: Integer;
    FProxyBuffer: TBytes;
    FProxyError: string;
    FConnectOp: IInterface;
    FSendLimits: IInterface;
    function _TakeConnectCallback: TCrossConnectionCallback;
    function _TakeConnectOp: IInterface;
    procedure _Close;
  protected
    procedure _LockRecv; inline;
    procedure _UnlockRecv; inline;

    procedure _LockSent; inline;
    procedure _UnlockSent; inline;
  protected
    function GetUIDTag: Byte; override;
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetPeerHost: string;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;
    function GetLastNetError: Integer;
    function GetProxyError: string;
    function GetIsClosed: Boolean; override;

    function _SetConnectStatus(const AStatus: TConnectStatus): TConnectStatus; inline;
    procedure SetConnectStatus(const AValue: TConnectStatus);
    procedure SetLastNetError(const AValue: Integer);

  public
    procedure ConfigureProxy(const ASettings: TCrossProxySettings;
      const ATargetHost: string; const ATargetPort: Word);
    function ProxyUsesTlsTransport: Boolean;
    function ProxySettings: TCrossProxySettings;
    function ProxyError: string;
    function ProxyNeedsHandshake: Boolean;
    function ProxyStart(out ASendData: TBytes): Boolean;
    function ProxyFeed(const ABuf: Pointer; const ALen: Integer;
      out ASendData, ARemain: TBytes): TCrossProxyFeedResult;

  protected
    procedure InternalClose; virtual;
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); virtual;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectedCb: TCrossConnectionCallback); reintroduce; virtual;
    destructor Destroy; override;

    procedure UpdateAddr; override;
    procedure Close; override;
    procedure Disconnect; virtual;

    procedure _SetConnectOp(const AOp: IInterface);
    function _CloseRetryingConnect(out AOp: IInterface): Boolean;

    procedure SendBuf(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendBuf(const ABuffer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendBytes(const ABytes: TBytes; const AOffset, ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendBytes(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendStream(const AStream: TStream;
      const ACallback: TCrossConnectionCallback = nil);

    function DebugInfo: string; override;

    property PeerAddr: string read GetPeerAddr;
    property PeerPort: Word read GetPeerPort;
    property PeerHost: string read GetPeerHost;
    property ConnectType: TConnectType read GetConnectType;
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;
  end;

  TIoEventThread = class(TThread)
  private
    FOwner: TCrossSocketBase;
  protected
    procedure Execute; override;
  public
    constructor Create(const AOwner: TCrossSocketBase); reintroduce;
  end;

  { TCrossSocketBase }

  TCrossSocketBase = class abstract(TInterfacedObject, ICrossSocket)
  protected const
    RCV_BUF_SIZE = 32768;
  protected class threadvar
    FRecvBuf: array [0..RCV_BUF_SIZE-1] of Byte;
  protected
    FIoThreads: Integer;

    // 设置套接字心跳参数, 用于处理异常断线(拔网线, 主机异常掉电等造成的网络异常)
    function SetKeepAlive(const ASocket: TSocket): Integer; virtual;
  private
    FMaxPendingSendCount: Integer;
    FMaxPendingSendBytes: Int64;
    FHasSendLimits: Integer;
    FKeepAliveIdle: Integer;
    FKeepAliveInterval: Integer;
    FKeepAliveCount: Integer;

    FConnections: TCrossConnections;
    FConnectionsLock: ILock;
    FConnectGeneration: Integer;

    FListens: TCrossListens;
    FListensLock: ILock;
    FListenGeneration: Integer;
    FLoopStopping: Integer;

    FOnIoThreadBegin: TCrossIoThreadEvent;
    FOnIoThreadEnd: TCrossIoThreadEvent;
    FOnListened: TCrossListenEvent;
    FOnListenEnd: TCrossListenEvent;
    FOnConnected: TCrossConnectEvent;
    FOnDisconnected: TCrossConnectEvent;
    FOnReceived: TCrossDataEvent;
    FOnSent: TCrossDataEvent;

    function _PrepareLimitedSend(const AConnection: ICrossConnection; const ALen: Integer;
      const ACallback: TCrossConnectionCallback; out APrepared: TCrossConnectionCallback): Boolean;
    procedure _LockConnections; inline;
    procedure _UnlockConnections; inline;

    procedure _LockListens; inline;
    procedure _UnlockListens; inline;
  protected
    function GetConnectionsCount: Integer;
    function GetListensCount: Integer;

    function GetOnIoThreadBegin: TCrossIoThreadEvent;
    function GetOnIoThreadEnd: TCrossIoThreadEvent;
    function GetOnConnected: TCrossConnectEvent;
    function GetOnDisconnected: TCrossConnectEvent;
    function GetOnListened: TCrossListenEvent;
    function GetOnListenEnd: TCrossListenEvent;
    function GetOnReceived: TCrossDataEvent;
    function GetOnSent: TCrossDataEvent;

    procedure SetOnIoThreadBegin(const AValue: TCrossIoThreadEvent);
    procedure SetOnIoThreadEnd(const AValue: TCrossIoThreadEvent);
    procedure SetOnConnected(const AValue: TCrossConnectEvent);
    procedure SetOnDisconnected(const AValue: TCrossConnectEvent);
    procedure SetOnListened(const AValue: TCrossListenEvent);
    procedure SetOnListenEnd(const AValue: TCrossListenEvent);
    procedure SetOnReceived(const AValue: TCrossDataEvent);
    procedure SetOnSent(const AValue: TCrossDataEvent);

    function GetKeepAliveIdle: Integer; virtual;
    function GetKeepAliveInterval: Integer; virtual;
    function GetKeepAliveCount: Integer; virtual;
    procedure SetKeepAliveIdle(const AValue: Integer); virtual;
    procedure SetKeepAliveInterval(const AValue: Integer); virtual;
    procedure SetKeepAliveCount(const AValue: Integer); virtual;
  protected
    FConnectionsCount: Integer;
    FListensCount: Integer;

    // 返回False表示已在锁外通知拒绝/空发送；无限制路径不创建完成包装。
    function _PrepareSend(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback;
      out APrepared: TCrossConnectionCallback): Boolean;
    function ProcessIoEvent: Boolean; virtual; abstract;
    function GetIoThreads: Integer; virtual;
    function _GetListenGeneration: Integer;
    function _CanListen(const AGeneration: Integer): Boolean;
    function _RegisterListen(const AListen: ICrossListen; const AGeneration: Integer): Boolean;
    procedure _StartListening;
    procedure _StopListening;

    function ResolveConnectAddrs(const AHost: string;
      const APort: Word): TArray<TCrossConnectAddr>; virtual;
    function _ConnectAddr(const AOp: IInterface;
      const AAddr: TCrossConnectAddr): Boolean; virtual; abstract;
    procedure _ConnectNextAddr(const AOp: IInterface);
    procedure _ConnectAttemptFailed(const AConnection: ICrossConnection);

    // 创建连接对象
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; overload; virtual; abstract;
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string): ICrossConnection; overload;

    // 创建监听对象
    function CreateListen(const AOwner: TCrossSocketBase; const AListenSocket: TSocket;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; virtual; abstract;

    procedure PrepareConnection(const AConnection: ICrossConnection;
      const ALogicalHost: string; const ALogicalPort: Word); virtual;

    {$region '物理事件'}
    procedure TriggerListened(const AListen: ICrossListen); virtual;
    procedure TriggerListenEnd(const AListen: ICrossListen); virtual;

    procedure TriggerConnecting(const AConnection: ICrossConnection); virtual;
    procedure TriggerConnected(const AConnection: ICrossConnection); virtual;
    procedure TriggerDisconnected(const AConnection: ICrossConnection); virtual;

    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    procedure TriggerSent(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    {$endregion}

    {$region '逻辑事件'}
    // 这几个虚方法用于在派生类中使用
    // 比如SSL中网络端口收到的是加密数据, 可能要几次接收才会收到一个完整的
    // 已加密数据包, 然后才能解密出数据, 也就是说可能几次网络端口的接收才
    // 会对应到一次实际的数据接收, 所以设计了以下接口, 以下接口是实际数据
    // 发生时才会被触发的
    procedure LogicConnected(const AConnection: ICrossConnection); virtual;
    procedure LogicDisconnected(const AConnection: ICrossConnection); virtual;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    procedure LogicSent(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    {$endregion}

    procedure TriggerIoThreadBegin(const AIoThread: TIoEventThread); virtual;
    procedure TriggerIoThreadEnd(const AIoThread: TIoEventThread); virtual;

    procedure StartLoop; virtual; abstract;
    procedure StopLoop; virtual; abstract;

    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil); virtual; abstract;

    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil); virtual; abstract;

    procedure CloseAllConnections; virtual;
    procedure CloseAllListens; virtual;
    procedure CloseAll; virtual;
    procedure DisconnectAll; virtual;
  public
    procedure Connect(const AHost: string; const APort, ALocalPort: Word;
      const ACallback: TCrossConnectionCallback = nil); overload; virtual;
    procedure Connect(const AHost: string; const APort: Word;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure ConnectTarget(const APhysicalHost: string;
      const APhysicalPort, ALocalPort: Word; const ALogicalHost: string;
      const ALogicalPort: Word;
      const ACallback: TCrossConnectionCallback = nil); virtual;
    constructor Create(const AIoThreads: Integer); virtual;
    destructor Destroy; override;

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;

    function LockConnections: TCrossConnections;
    procedure UnlockConnections;

    function LockListens: TCrossListens;
    procedure UnlockListens;

    property IoThreads: Integer read GetIoThreads;
    property ConnectionsCount: Integer read GetConnectionsCount;
    property ListensCount: Integer read GetListensCount;

    // 新连接创建时快照；<=0不限，已有连接不追溯修改。
    property MaxPendingSendCount: Integer read FMaxPendingSendCount write FMaxPendingSendCount;
    property MaxPendingSendBytes: Int64 read FMaxPendingSendBytes write FMaxPendingSendBytes;
    property KeepAliveIdle: Integer read GetKeepAliveIdle write SetKeepAliveIdle;
    property KeepAliveInterval: Integer read GetKeepAliveInterval write SetKeepAliveInterval;
    property KeepAliveCount: Integer read GetKeepAliveCount write SetKeepAliveCount;

    property OnIoThreadBegin: TCrossIoThreadEvent read GetOnIoThreadBegin write SetOnIoThreadBegin;
    property OnIoThreadEnd: TCrossIoThreadEvent read GetOnIoThreadEnd write SetOnIoThreadEnd;
    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  TCrossLogger = reference to procedure(const S: string);
  {$IFDEF CROSS_CAPACITY_TESTS}
  TCrossConnectTestHook = reference to procedure(const AConnection: ICrossConnection);
  TCrossSendRejectedTestHook = reference to procedure(const AConnection: ICrossConnection; const ABytes: Integer);
  {$ENDIF}

  function GetTagByUID(const AUID: UInt64): Byte;

  procedure _SetCrossLogger(const ALogger: TCrossLogger);
  procedure _LogLastOsError(const ATag: string = ''); overload;
  procedure _LogLastOsError(const ATagFmt: string; const ATagArgs: array of const); overload;
  procedure _Log(const S: string); overload;
  procedure _Log(const Fmt: string; const Args: array of const); overload;
  procedure _LogException(const AContext: string; const AError: Exception);
  function _CallConnectionCallback(const ACallback: TCrossConnectionCallback;
    const AConnection: ICrossConnection; const ASuccess: Boolean): Boolean;
  procedure _CloseCrossData(const AData: ICrossData);
  {$IFDEF CROSS_CAPACITY_TESTS}
  procedure GetPendingSendForTest(const AConnection: ICrossConnection; out ACount, ABytes: Int64);
  {$ENDIF}

var
  {$IFDEF CROSS_CAPACITY_TESTS}
  CrossConnectBeforeRegisterForTest: TCrossConnectTestHook;
  CrossSendRejectedForTest: TCrossSendRejectedTestHook;
  {$ENDIF}
  CrossSocketLogEnabled: Boolean = {$IFDEF DEBUG}True{$ELSE}False{$ENDIF};

{$IFDEF CROSS_LISTEN_TESTS}
type
  TCrossListenTestHook = reference to procedure(const AListen: ICrossListen);
var
  CrossListenRegisteredForTest: TCrossListenTestHook;
{$ENDIF}

implementation

uses
  {$IF defined(MSWINDOWS)}
  Net.Winsock2,
  {$ELSEIF defined(DELPHI)}
  Posix.SysSocket, Posix.NetinetIn,
  {$ELSE}
  Sockets,
  {$ENDIF}
  Utils.Logger;

var
  _CrossLogger: TCrossLogger = nil;

type
  TCrossSendLimits = class(TInterfacedObject)
  private
    FLock: ILock;
    FMaxCount: Integer;
    FMaxBytes, FCount, FBytes: Int64;
  public
    constructor Create(const AMaxCount: Integer; const AMaxBytes: Int64);
    function Reserve(const ABytes: Integer): Boolean;
    procedure Release(const ABytes: Integer);
    function WrapCallback(const ABytes: Integer;
      const ACallback: TCrossConnectionCallback): TCrossConnectionCallback;
  end;

constructor TCrossSendLimits.Create(const AMaxCount: Integer; const AMaxBytes: Int64);
begin
  inherited Create;
  FMaxCount := AMaxCount;
  FMaxBytes := AMaxBytes;
  FLock := TLock.Create;
end;

function TCrossSendLimits.Reserve(const ABytes: Integer): Boolean;
begin
  FLock.Enter;
  try
    Result := (FCount < High(Int64)) and (Int64(ABytes) <= High(Int64) - FBytes)
      and ((FMaxCount <= 0) or (FCount < FMaxCount))
      and ((FMaxBytes <= 0) or (Int64(ABytes) <= FMaxBytes - FBytes));
    if Result then begin Inc(FCount); Inc(FBytes, ABytes); end;
  finally
    FLock.Leave;
  end;
end;

procedure TCrossSendLimits.Release(const ABytes: Integer);
begin
  FLock.Enter;
  try Dec(FCount); Dec(FBytes, ABytes);
  finally FLock.Leave; end;
end;

function TCrossSendLimits.WrapCallback(const ABytes: Integer;
  const ACallback: TCrossConnectionCallback): TCrossConnectionCallback;
var
  LKeep: IInterface;
  LCompleted: Integer;
begin
  LKeep := Self;
  LCompleted := 0;
  Result := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if AtomicExchange(LCompleted, 1) <> 0 then Exit;
      // 保留最初提交长度；部分写不退额，真正完成/取消后先退额再通知。
      (LKeep as TCrossSendLimits).Release(ABytes);
      if Assigned(ACallback) then ACallback(AConnection, ASuccess);
    end;
end;

{$IFDEF CROSS_CAPACITY_TESTS}
procedure GetPendingSendForTest(const AConnection: ICrossConnection; out ACount, ABytes: Int64);
var
  LKeep: IInterface;
  LLimits: TCrossSendLimits;
begin
  ACount := 0;
  ABytes := 0;
  if AConnection = nil then Exit;
  LKeep := (AConnection as TCrossConnectionBase).FSendLimits;
  if LKeep = nil then Exit;
  LLimits := LKeep as TCrossSendLimits;
  LLimits.FLock.Enter;
  try ACount := LLimits.FCount; ABytes := LLimits.FBytes;
  finally LLimits.FLock.Leave; end;
end;
{$ENDIF}

function TCrossSocketBase._PrepareSend(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer; const ACallback: TCrossConnectionCallback;
  out APrepared: TCrossConnectionCallback): Boolean;
begin
  APrepared := nil;
  Result := False;
  if (AConnection = nil) or (ALen < 0) or ((ABuf = nil) and (ALen > 0)) then
  begin
    _CallConnectionCallback(ACallback, AConnection, False);
    Exit;
  end;
  // 默认双0的有效正长度发送仍由原后端判断状态，不增加额度锁/闭包或状态读取。
  // 此标记只在限额连接发布前从0变1；无效参数仍在上面拒绝。
  if (ALen > 0) and (FHasSendLimits = 0) then Exit(True);
  if AConnection.IsClosed or (AConnection.ConnectStatus = csDisconnected)
    or (AConnection.Socket = INVALID_SOCKET) then
  begin
    _CallConnectionCallback(ACallback, AConnection, False);
    Exit;
  end;
  if ALen = 0 then
  begin
    _CallConnectionCallback(ACallback, AConnection, True);
    Exit;
  end;
  Result := _PrepareLimitedSend(AConnection, ALen, ACallback, APrepared);
end;

function TCrossSocketBase._PrepareLimitedSend(const AConnection: ICrossConnection;
  const ALen: Integer; const ACallback: TCrossConnectionCallback;
  out APrepared: TCrossConnectionCallback): Boolean;
var
  LKeep: IInterface;
  LLimits: TCrossSendLimits;
begin
  Result := False;
  LKeep := (AConnection as TCrossConnectionBase).FSendLimits;
  if LKeep = nil then Exit(True);
  LLimits := LKeep as TCrossSendLimits;
  if not LLimits.Reserve(ALen) then
  begin
    try
      {$IFDEF CROSS_CAPACITY_TESTS}
      if Assigned(CrossSendRejectedForTest) then CrossSendRejectedForTest(AConnection, ALen);
      {$ENDIF}
    finally
      _CallConnectionCallback(ACallback, AConnection, False);
    end;
    Exit;
  end;
  try
    APrepared := LLimits.WrapCallback(ALen, ACallback);
    Result := True;
  except
    on E: Exception do
    begin
      LLimits.Release(ALen);
      _LogException('Send completion allocation failed', E);
      _CallConnectionCallback(ACallback, AConnection, False);
    end;
  end;
end;

function GetTagByUID(const AUID: UInt64): Byte;
begin
  // 取最高 2 位
  Result := (AUID shr 62) and $03;
end;

procedure _SetCrossLogger(const ALogger: TCrossLogger);
begin
  _CrossLogger := ALogger;
end;

procedure _Log(const S: string); overload;
begin
  if not CrossSocketLogEnabled then Exit;

  if Assigned(_CrossLogger) then
    _CrossLogger(S)
  else
  begin
    AppendLog(S);
  end;
end;

procedure _Log(const Fmt: string; const Args: array of const); overload;
begin
  if CrossSocketLogEnabled then
    _Log(TStrUtils.Format(Fmt, Args));
end;

procedure _LogException(const AContext: string; const AError: Exception);
begin
  try
    _Log('%s: %s, %s', [AContext, AError.ClassName, AError.Message]);
  except
    // 日志回调不能再次打断正在进行的异常收尾。
  end;
end;

function _CallConnectionCallback(const ACallback: TCrossConnectionCallback;
  const AConnection: ICrossConnection; const ASuccess: Boolean): Boolean;
begin
  Result := True;
  if not Assigned(ACallback) then Exit;
  try
    ACallback(AConnection, ASuccess);
  except
    on E: Exception do
    begin
      Result := False;
      _LogException('Connection callback', E);
    end;
  end;
end;

procedure _CloseCrossData(const AData: ICrossData);
begin
  if AData = nil then Exit;
  try
    AData.Close;
  except
    on E: Exception do _LogException('Close', E);
  end;
end;

procedure _LogLastOsError(const ATag: string);
var
  LError: Integer;
  LErrMsg: string;
begin
  if not CrossSocketLogEnabled then Exit;

  LError := GetLastError;
  if (ATag <> '') then
    LErrMsg := ATag + ' : '
  else
    LErrMsg := '';
  LErrMsg := LErrMsg + TStrUtils.Format('System Error: %0:d(0x%0:.4x), %1:s',
    [LError, SysErrorMessage(LError)]);
  _Log(LErrMsg);
end;

procedure _LogLastOsError(const ATagFmt: string; const ATagArgs: array of const);
begin
  if CrossSocketLogEnabled then
    _LogLastOsError(Format(ATagFmt, ATagArgs));
end;

{ TIoEventThread }

constructor TIoEventThread.Create(const AOwner: TCrossSocketBase);
begin
  inherited Create(True);
  FOwner := AOwner;
  Suspended := False;
end;

procedure TIoEventThread.Execute;
begin
  try
    try
      FOwner.TriggerIoThreadBegin(Self);
    except
      on E: Exception do _LogException('IoThreadBegin', E);
    end;
    while not Terminated do
    begin
      try
        if not FOwner.ProcessIoEvent then Break;
      except
        {$IFDEF __DEBUG__}
        on e: Exception do
        begin
          _Log('%s Io线程ID %d, 异常 %s, %s', [
            FOwner.ClassName, NativeUInt(Self.ThreadID), e.ClassName, e.Message
          ]);
          {$IFDEF DELPHI}
          if (e.StackTrace <> '') then
            _Log('%s 异常调用堆栈:%s', [
              FOwner.ClassName, e.StackTrace
            ]);
          {$ENDIF}
        end;
        {$ENDIF}
      end;
    end;
  finally
    try
      FOwner.TriggerIoThreadEnd(Self);
    except
      on E: Exception do _LogException('IoThreadEnd', E);
    end;
  end;
end;

{ TCrossSocketBase }

{ TCrossConnectOp }

constructor TCrossConnectOp.Create(const AHost: string;
  const ALogicalPort, ALocalPort: Word; const AGeneration: Integer;
  const AAddrs: TArray<TCrossConnectAddr>;
  const ACallback: TCrossConnectionCallback);
begin
  inherited Create;
  FLock := TLock.Create;
  FHost := AHost;
  FLogicalPort := ALogicalPort;
  FLocalPort := ALocalPort;
  FGeneration := AGeneration;
  FAddrs := AAddrs;
  FCallback := ACallback;
end;

function TCrossConnectOp.NextAddr(out AAddr: TCrossConnectAddr): Boolean;
begin
  FLock.Enter;
  try
    Result := not FCompleted and (FNextIndex < Length(FAddrs));
    if Result then
    begin
      AAddr := FAddrs[FNextIndex];
      Inc(FNextIndex);
    end;
  finally
    FLock.Leave;
  end;
end;

function TCrossConnectOp.GetCompleted: Boolean;
begin
  FLock.Enter;
  try Result := FCompleted;
  finally FLock.Leave; end;
end;

function TCrossConnectOp.HasNextAddr: Boolean;
begin
  FLock.Enter;
  try Result := not FCompleted and (FNextIndex < Length(FAddrs));
  finally FLock.Leave; end;
end;

function TCrossConnectOp.CreateCallback: TCrossConnectionCallback;
var
  LKeep: IInterface;
begin
  LKeep := Self;
  Result := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      (LKeep as TCrossConnectOp).Complete(AConnection, ASuccess);
    end;
end;

procedure TCrossConnectOp.Complete(const AConnection: ICrossConnection;
  const ASuccess: Boolean);
var
  LCallback: TCrossConnectionCallback;
begin
  FLock.Enter;
  try
    if FCompleted then Exit;
    FCompleted := True;
    LCallback := FCallback;
    FCallback := nil;
    FAddrs := nil;
  finally
    FLock.Leave;
  end;
  if Assigned(LCallback) then LCallback(AConnection, ASuccess);
end;

procedure TCrossSocketBase.CloseAll;
begin
  CloseAllListens;
  CloseAllConnections;
end;

procedure TCrossSocketBase.CloseAllConnections;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  if (FConnections = nil) then Exit;

  _LockConnections;
  try
    // 解析中及两次尝试间的操作可能不在连接表内，也必须取消。
    AtomicIncrement(FConnectGeneration);
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    _CloseCrossData(LConnection);
end;

procedure TCrossSocketBase.CloseAllListens;
var
  LListenArr: TArray<ICrossListen>;
  LListen: ICrossListen;
begin
  if (FListens = nil) then Exit;

  _LockListens;
  try
    AtomicIncrement(FListenGeneration);
    LListenArr := FListens.Values.ToArray;
  finally
    _UnlockListens;
  end;

  for LListen in LListenArr do
    _CloseCrossData(LListen);
end;

procedure TCrossSocketBase.Connect(const AHost: string; const APort: Word;
  const ACallback: TCrossConnectionCallback);
begin
  Connect(AHost, APort, 0, ACallback);
end;

procedure TCrossSocketBase.Connect(const AHost: string;
  const APort, ALocalPort: Word; const ACallback: TCrossConnectionCallback);
begin
  ConnectTarget(AHost, APort, ALocalPort, AHost, APort, ACallback);
end;

procedure TCrossSocketBase.ConnectTarget(const APhysicalHost: string;
  const APhysicalPort, ALocalPort: Word; const ALogicalHost: string;
  const ALogicalPort: Word; const ACallback: TCrossConnectionCallback);
var
  LGeneration: Integer;
  LAddrs: TArray<TCrossConnectAddr>;
  LOp: IInterface;
begin
  LGeneration := AtomicCmpExchange(FConnectGeneration, 0, 0);
  LAddrs := ResolveConnectAddrs(APhysicalHost, APhysicalPort);
  LOp := TCrossConnectOp.Create(ALogicalHost, ALogicalPort, ALocalPort,
    LGeneration, LAddrs, ACallback);
  _ConnectNextAddr(LOp);
end;

function TCrossSocketBase.ResolveConnectAddrs(const AHost: string;
  const APort: Word): TArray<TCrossConnectAddr>;
var
  LHints: TRawAddrInfo;
  LFirst, LInfo: PRawAddrInfo;
  LAddr: TCrossConnectAddr;
begin
  Result := nil;
  FillChar(LHints, SizeOf(LHints), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LFirst := TSocketAPI.GetAddrInfo(AHost, APort, LHints);
  LInfo := LFirst;
  try
    while LInfo <> nil do
    begin
      if (LInfo.ai_addr <> nil) and
        ((LInfo.ai_family = AF_INET) or (LInfo.ai_family = AF_INET6)) and
        (LInfo.ai_addrlen > 0) and
        (LInfo.ai_addrlen <= SizeOf(LAddr.Addr.Addr6)) then
      begin
        LAddr := Default(TCrossConnectAddr);
        LAddr.Family := LInfo.ai_family;
        LAddr.SockType := LInfo.ai_socktype;
        LAddr.Protocol := LInfo.ai_protocol;
        LAddr.Addr.AddrLen := LInfo.ai_addrlen;
        Move(LInfo.ai_addr^, LAddr.Addr.Addr, LInfo.ai_addrlen);
        Result := Result + [LAddr];
      end;
      LInfo := PRawAddrInfo(LInfo.ai_next);
    end;
  finally
    if LFirst <> nil then TSocketAPI.FreeAddrInfo(LFirst);
  end;
end;

procedure TCrossSocketBase._ConnectNextAddr(const AOp: IInterface);
var
  LOp: TCrossConnectOp;
  LAddr: TCrossConnectAddr;
begin
  LOp := AOp as TCrossConnectOp;
  try
    while (LOp.Generation = AtomicCmpExchange(FConnectGeneration, 0, 0))
      and LOp.NextAddr(LAddr) do
      if _ConnectAddr(AOp, LAddr) then Exit;
    // 地址耗尽或已被 CloseAllConnections 取消，统一结算一次。
    LOp.Complete(nil, False);
  except
    // 系统调用包装、构造或派生钩子抛错时也结束操作；保留原异常。
    try
      LOp.Complete(nil, False);
    except
      on E: Exception do _LogException('Connect failure callback', E);
    end;
    raise;
  end;
end;

procedure TCrossSocketBase._ConnectAttemptFailed(const AConnection: ICrossConnection);
var
  LOp: IInterface;
begin
  if (AConnection <> nil) and
    (AConnection as TCrossConnectionBase)._CloseRetryingConnect(LOp) and
    (LOp <> nil) then
    _ConnectNextAddr(LOp);
end;

constructor TCrossSocketBase.Create(const AIoThreads: Integer);
begin
  FLoopStopping := 1;
  FIoThreads := AIoThreads;

  FKeepAliveIdle := 5;
  FKeepAliveInterval := 3;
  FKeepAliveCount := 5;

  FListens := TCrossListens.Create;
  FListensLock := TLock.Create;

  FConnections := TCrossConnections.Create;
  FConnectionsLock := TLock.Create;
end;

function TCrossSocketBase.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string): ICrossConnection;
begin
  Result := CreateConnection(AOwner, AClientSocket, AConnectType, AHost, nil);
end;

procedure TCrossSocketBase.PrepareConnection(
  const AConnection: ICrossConnection; const ALogicalHost: string;
  const ALogicalPort: Word);
begin
end;

destructor TCrossSocketBase.Destroy;
begin
  FreeAndNil(FListens);
  FreeAndNil(FConnections);

  inherited;
end;

procedure TCrossSocketBase.DisconnectAll;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  if (FConnections = nil) then Exit;

  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Disconnect;
end;

procedure TCrossSocketBase.AfterConstruction;
begin
  StartLoop;
  inherited AfterConstruction;
end;

procedure TCrossSocketBase.BeforeDestruction;
begin
  StopLoop;
  inherited BeforeDestruction;
end;

function TCrossSocketBase.GetConnectionsCount: Integer;
begin
  Result := FConnectionsCount;
end;

function TCrossSocketBase.GetIoThreads: Integer;
begin
  if (FIoThreads > 0) then
    Result := FIoThreads
  else
    Result := CPUCount * 2 + 1;
end;

function TCrossSocketBase.GetListensCount: Integer;
begin
  Result := FListensCount;
end;

function TCrossSocketBase.GetOnConnected: TCrossConnectEvent;
begin
  Result := FOnConnected;
end;

function TCrossSocketBase.GetOnDisconnected: TCrossConnectEvent;
begin
  Result := FOnDisconnected;
end;

function TCrossSocketBase.GetOnIoThreadBegin: TCrossIoThreadEvent;
begin
  Result := FOnIoThreadBegin;
end;

function TCrossSocketBase.GetOnIoThreadEnd: TCrossIoThreadEvent;
begin
  Result := FOnIoThreadEnd;
end;

function TCrossSocketBase.GetOnListened: TCrossListenEvent;
begin
  Result := FOnListened;
end;

function TCrossSocketBase.GetOnListenEnd: TCrossListenEvent;
begin
  Result := FOnListenEnd;
end;

function TCrossSocketBase.GetOnReceived: TCrossDataEvent;
begin
  Result := FOnReceived;
end;

function TCrossSocketBase.GetOnSent: TCrossDataEvent;
begin
  Result := FOnSent;
end;

function TCrossSocketBase.LockConnections: TCrossConnections;
begin
  _LockConnections;
  Result := FConnections;
end;

function TCrossSocketBase.LockListens: TCrossListens;
begin
  _LockListens;
  Result := FListens;
end;

procedure TCrossSocketBase.LogicConnected(const AConnection: ICrossConnection);
var
  LConnObj: TCrossConnectionBase;
  LConnectCb: TCrossConnectionCallback;
begin
  LConnObj := AConnection as TCrossConnectionBase;

  LConnObj._TakeConnectOp;
  // 成功和关闭竞争时，由同一把锁决定唯一的通知持有者。
  LConnectCb := LConnObj._TakeConnectCallback();
  if Assigned(LConnectCb) then
    LConnectCb(AConnection, True);

  if Assigned(FOnConnected) then
    FOnConnected(Self, AConnection);
end;

procedure TCrossSocketBase.LogicDisconnected(const AConnection: ICrossConnection);
begin
  if Assigned(FOnDisconnected) then
    FOnDisconnected(Self, AConnection);
end;

procedure TCrossSocketBase.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  if Assigned(FOnReceived) then
    FOnReceived(Self, AConnection, ABuf, ALen);
end;

procedure TCrossSocketBase.LogicSent(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  if Assigned(FOnSent) then
    FOnSent(Self, AConnection, ABuf, ALen);
end;

function TCrossSocketBase.SetKeepAlive(const ASocket: TSocket): Integer;
begin
  Result := TSocketAPI.SetKeepAlive(ASocket, FKeepAliveIdle, FKeepAliveInterval, FKeepAliveCount);
end;

function TCrossSocketBase.GetKeepAliveIdle: Integer;
begin
  Result := FKeepAliveIdle;
end;

function TCrossSocketBase.GetKeepAliveInterval: Integer;
begin
  Result := FKeepAliveInterval;
end;

function TCrossSocketBase.GetKeepAliveCount: Integer;
begin
  Result := FKeepAliveCount;
end;

procedure TCrossSocketBase.SetKeepAliveIdle(const AValue: Integer);
begin
  FKeepAliveIdle := AValue;
end;

procedure TCrossSocketBase.SetKeepAliveInterval(const AValue: Integer);
begin
  FKeepAliveInterval := AValue;
end;

procedure TCrossSocketBase.SetKeepAliveCount(const AValue: Integer);
begin
  FKeepAliveCount := AValue;
end;

procedure TCrossSocketBase.SetOnConnected(const AValue: TCrossConnectEvent);
begin
  FOnConnected := AValue;
end;

procedure TCrossSocketBase.SetOnDisconnected(const AValue: TCrossConnectEvent);
begin
  FOnDisconnected := AValue;
end;

procedure TCrossSocketBase.SetOnIoThreadBegin(
  const AValue: TCrossIoThreadEvent);
begin
  FOnIoThreadBegin := AValue;
end;

procedure TCrossSocketBase.SetOnIoThreadEnd(
  const AValue: TCrossIoThreadEvent);
begin
  FOnIoThreadEnd := AValue;
end;

procedure TCrossSocketBase.SetOnListened(const AValue: TCrossListenEvent);
begin
  FOnListened := AValue;
end;

procedure TCrossSocketBase.SetOnListenEnd(const AValue: TCrossListenEvent);
begin
  FOnListenEnd := AValue;
end;

procedure TCrossSocketBase.SetOnReceived(const AValue: TCrossDataEvent);
begin
  FOnReceived := AValue;
end;

procedure TCrossSocketBase.SetOnSent(const AValue: TCrossDataEvent);
begin
  FOnSent := AValue;
end;

procedure TCrossSocketBase.TriggerConnecting(const AConnection: ICrossConnection);
var
  LConnObj: TCrossConnectionBase;
  LCancelled: Boolean;
  LStatus: Integer;
begin
  LConnObj := AConnection as TCrossConnectionBase;

  LConnObj._Lock;
  try
    _LockConnections;
    try
      // 与关闭全部串行发布，不能让已经取消的旧操作重新入表。
      LCancelled := AConnection.IsClosed
        or (AtomicCmpExchange(FLoopStopping, 0, 0) <> 0);
      if not LCancelled and (LConnObj.FConnectOp <> nil) then
        LCancelled := ((LConnObj.FConnectOp as TCrossConnectOp).Generation <> FConnectGeneration)
          or (LConnObj.FConnectOp as TCrossConnectOp).Completed;
      // Close 在锁外原子取得关闭权，状态写入也必须尊重它。
      while not LCancelled do
      begin
        LStatus := AtomicCmpExchange(LConnObj.FConnectStatus, 0, 0);
        if TConnectStatus(LStatus) in [csDisconnected, csClosed] then
          LCancelled := True
        else if AtomicCmpExchange(LConnObj.FConnectStatus,
          Integer(csConnecting), LStatus) = LStatus then Break;
      end;
      if not LCancelled then
      begin
        FConnections.AddOrSetValue(AConnection.UID, AConnection);
        FConnectionsCount := FConnections.Count;
      end;
    finally
      _UnlockConnections;
    end;
  finally
    LConnObj._Unlock;
  end;
  if LCancelled then _CloseCrossData(AConnection);
end;

procedure TCrossSocketBase.TriggerConnected(const AConnection: ICrossConnection);
var
  LConnObj: TCrossConnectionBase;
  LProxyData: TBytes;
  LStatus: Integer;
begin
  LConnObj := AConnection as TCrossConnectionBase;

  if LConnObj.ProxyNeedsHandshake then
  begin
    if LConnObj.ProxyStart(LProxyData) then
      LConnObj.SendBytes(LProxyData);
    Exit;
  end;

  LConnObj._Lock;
  try
    if AConnection.IsClosed then Exit;
    AConnection.UpdateAddr;
    repeat
      LStatus := AtomicCmpExchange(LConnObj.FConnectStatus, 0, 0);
      if TConnectStatus(LStatus) in [csDisconnected, csClosed] then Exit;
    until AtomicCmpExchange(LConnObj.FConnectStatus,
      Integer(csConnected), LStatus) = LStatus;
  finally
    LConnObj._Unlock;
  end;

  // 用户回调放在锁外执行，避免死锁
  LogicConnected(AConnection);
end;

procedure TCrossSocketBase.TriggerDisconnected(const AConnection: ICrossConnection);
var
  LConnObj: TCrossConnectionBase;
begin
  LConnObj := AConnection as TCrossConnectionBase;

  // 先设置状态并从连接列表中移除
  LConnObj._Lock;
  try
    AConnection.ConnectStatus := csClosed;
  finally
    LConnObj._Unlock;
  end;

  _LockConnections;
  try
    FConnections.Remove(AConnection.UID);
    FConnectionsCount := FConnections.Count;
  finally
    _UnlockConnections;
  end;

  // 用户回调放在锁外执行，避免死锁
  LogicDisconnected(AConnection);
end;

procedure TCrossSocketBase.TriggerIoThreadBegin(const AIoThread: TIoEventThread);
begin
  {$IFDEF __DEBUG__}
  _Log('[%s]thread%d start', [Self.ClassName, NativeUInt(TThread.Current.ThreadID)]);
  {$ENDIF}
  if Assigned(FOnIoThreadBegin) then
    FOnIoThreadBegin(Self, AIoThread);
end;

procedure TCrossSocketBase.TriggerIoThreadEnd(const AIoThread: TIoEventThread);
begin
  {$IFDEF __DEBUG__}
  _Log('[%s]thread%d exit', [Self.ClassName, NativeUInt(TThread.Current.ThreadID)]);
  {$ENDIF}
  if Assigned(FOnIoThreadEnd) then
    FOnIoThreadEnd(Self, AIoThread);
end;

function TCrossSocketBase._GetListenGeneration: Integer;
begin
  Result := AtomicCmpExchange(FListenGeneration, 0, 0);
end;

function TCrossSocketBase._CanListen(const AGeneration: Integer): Boolean;
begin
  Result := (AtomicCmpExchange(FLoopStopping, 0, 0) = 0)
    and (AGeneration = _GetListenGeneration);
end;

procedure TCrossSocketBase._StartListening;
begin
  _LockListens;
  try AtomicExchange(FLoopStopping, 0);
  finally _UnlockListens; end;
end;

procedure TCrossSocketBase._StopListening;
begin
  _LockListens;
  try AtomicExchange(FLoopStopping, 1);
  finally _UnlockListens; end;
end;

function TCrossSocketBase._RegisterListen(const AListen: ICrossListen;
  const AGeneration: Integer): Boolean;
var
  LListen: TCrossListenBase;
begin
  LListen := AListen as TCrossListenBase;
  LListen._Lock;
  try
    _LockListens;
    try
      Result := not AListen.IsClosed and _CanListen(AGeneration);
      if not Result then Exit;
      LListen.FGeneration := AGeneration;
      FListens.AddOrSetValue(AListen.UID, AListen);
      FListensCount := FListens.Count;
    finally
      _UnlockListens;
    end;
  finally
    LListen._Unlock;
  end;
  {$IFDEF CROSS_LISTEN_TESTS}
  if Result and Assigned(CrossListenRegisteredForTest) then
    CrossListenRegisteredForTest(AListen);
  {$ENDIF}
end;

procedure TCrossSocketBase.TriggerListened(const AListen: ICrossListen);
var
  LListen: TCrossListenBase;
  LRegistered: ICrossListen;
begin
  LListen := AListen as TCrossListenBase;
  if AListen.IsClosed then Exit;
  // 虚方法可能抛错或重入，不能在内部锁中执行。
  AListen.UpdateAddr;
  LListen._Lock;
  try
    _LockListens;
    try
      if AListen.IsClosed or not _CanListen(LListen.Generation) then Exit;
      if not FListens.TryGetValue(AListen.UID, LRegistered) then Exit;
      if AtomicCmpExchange(LListen.FPublished, 1, 0) <> 0 then Exit;
    finally
      _UnlockListens;
    end;
  finally
    LListen._Unlock;
  end;
  // 成功已经认领；用户主动关闭后不再重复入表或改报失败。
  if Assigned(FOnListened) then FOnListened(Self, AListen);
end;

procedure TCrossSocketBase.TriggerListenEnd(const AListen: ICrossListen);
begin
  _LockListens;
  try
    FListens.Remove(AListen.UID);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListenEnd) then
    FOnListenEnd(Self, AListen);
end;

procedure TCrossSocketBase.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnObj: TCrossConnectionBase;
  LProxyResult: TCrossProxyFeedResult;
  LProxyData, LRemain: TBytes;
begin
  LConnObj := AConnection as TCrossConnectionBase;

  LConnObj._LockRecv;
  try
    if LConnObj.ProxyNeedsHandshake then
    begin
      LProxyResult := LConnObj.ProxyFeed(ABuf, ALen, LProxyData, LRemain);
      case LProxyResult of
        cpfrSendData:
          LConnObj.SendBytes(LProxyData);
        cpfrComplete:
          begin
            TriggerConnected(AConnection);
            if Length(LRemain) > 0 then
              LogicReceived(AConnection, @LRemain[0], Length(LRemain));
          end;
        cpfrFailed:
          LConnObj.Close;
      end;
    end
    else
      LogicReceived(AConnection, ABuf, ALen);
  finally
    LConnObj._UnlockRecv;
  end;
end;

procedure TCrossSocketBase.TriggerSent(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
var
  LConnObj: TCrossConnectionBase;
begin
  LConnObj := AConnection as TCrossConnectionBase;

  LConnObj._LockSent;
  try
    LogicSent(AConnection, ABuf, ALen);
  finally
    LConnObj._UnlockSent;
  end;
end;

procedure TCrossSocketBase.UnlockConnections;
begin
  _UnlockConnections;
end;

procedure TCrossSocketBase.UnlockListens;
begin
  _UnlockListens;
end;

procedure TCrossSocketBase._LockConnections;
begin
  FConnectionsLock.Enter;
end;

procedure TCrossSocketBase._LockListens;
begin
  FListensLock.Enter;
end;

procedure TCrossSocketBase._UnlockConnections;
begin
  FConnectionsLock.Leave;
end;

procedure TCrossSocketBase._UnlockListens;
begin
  FListensLock.Leave;
end;

{ TCrossData }

constructor TCrossData.Create(const AOwner: TCrossSocketBase;
  const ASocket: TSocket);
begin
  // 理论上说62位的唯一编号永远也不可能用完
  // 所以也就不用考虑编号重置的问题了
  FUID :=
    // 高2位 标志位
    (UInt64(GetUIDTag and $03) shl 62) or
    // 低62位 编号位
    (UID_MASK and AtomicIncrement(FCrossUID));

  FOwner := AOwner;
  FSocket := ASocket;
  FLock := TLock.Create;
end;

destructor TCrossData.Destroy;
begin
  if (FSocket <> INVALID_SOCKET) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    {$IFDEF __DEBUG__}
//    _Log('close result %d', [GetLastError]);
    {$ENDIF}
    FSocket := INVALID_SOCKET;
  end;

  inherited;
end;

function TCrossData.GetLocalAddr: string;
begin
  Result := FLocalAddr;
end;

function TCrossData.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TCrossData.GetOwner: TCrossSocketBase;
begin
  Result := FOwner;
end;

function TCrossData.GetSocket: TSocket;
begin
  Result := FSocket;
end;

function TCrossData.GetTag: string;
begin
  Result := FTag;
end;

function TCrossData.GetUID: UInt64;
begin
  Result := FUID;
end;

function TCrossData.GetUIDTag: Byte;
begin
  Result := UID_RAW;
end;

function TCrossData.GetUserData: Pointer;
begin
  Result := FUserData;
end;

function TCrossData.GetUserInterface: IInterface;
begin
  Result := FUserInterface;
end;

function TCrossData.GetUserObject: TObject;
begin
  Result := FUserObject;
end;

procedure TCrossData.SetTag(const AValue: string);
begin
  FTag := AValue;
end;

procedure TCrossData.SetUserData(const AValue: Pointer);
begin
  FUserData := AValue;
end;

procedure TCrossData.SetUserInterface(const AValue: IInterface);
begin
  FUserInterface := AValue;
end;

procedure TCrossData.SetUserObject(const AValue: TObject);
begin
  FUserObject := AValue;
end;

procedure TCrossData.UpdateAddr;
var
  LAddr: TRawSockAddrIn;
begin
  {$region '本地地址信息'}
  FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
  LAddr.AddrLen := SizeOf(LAddr.Addr6);
  if (TSocketAPI.GetSockName(FSocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen,
      FLocalAddr, FLocalPort);
  {$endregion}
end;

procedure TCrossData._Lock;
begin
  FLock.Enter;
end;

procedure TCrossData._Unlock;
begin
  FLock.Leave;
end;

{ TCrossListenBase }

constructor TCrossListenBase.Create(const AOwner: TCrossSocketBase;
  const AListenSocket: TSocket; const AFamily, ASockType, AProtocol: Integer);
begin
  inherited Create(AOwner, AListenSocket);

  FFamily := AFamily;
  FSockType := ASockType;
  FProtocol := AProtocol;

  FClosed := 0;
end;

function TCrossListenBase.DebugInfo: string;
begin
  Result := TStrUtils.Format('socket=%d, listen=(%s:%d)', [
    Socket,
    LocalAddr, LocalPort
  ]);
end;

procedure TCrossListenBase.Close;
var
  LSelf: ICrossListen;
  LSocket: TSocket;
begin
  if (AtomicExchange(FClosed, 1) = 1) then Exit;
  LSelf := Self;
  _Lock;
  try
    // 原生注册/投递也持有此锁；取走句柄后，新提交只能看到关闭状态。
    LSocket := FSocket;
    FSocket := INVALID_SOCKET;
  finally
    _Unlock;
  end;
  if LSocket <> INVALID_SOCKET then
  begin
    TSocketAPI.CloseSocket(LSocket);
    FOwner.TriggerListenEnd(LSelf);
  end;
end;

function TCrossListenBase._IsPublished: Boolean;
begin
  Result := AtomicCmpExchange(FPublished, 0, 0) <> 0;
end;

function TCrossListenBase.GetFamily: Integer;
begin
  Result := FFamily;
end;

function TCrossListenBase.GetIsClosed: Boolean;
begin
  Result := (FClosed = 1);
end;

function TCrossListenBase.GetProtocol: Integer;
begin
  Result := FProtocol;
end;

function TCrossListenBase.GetSockType: Integer;
begin
  Result := FSockType;
end;

function TCrossListenBase.GetUIDTag: Byte;
begin
  Result := UID_LISTEN;
end;

{ TCrossConnectionBase }

constructor TCrossConnectionBase.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectedCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket);

  FConnectType := AConnectType;
  FPeerHost := AHost;
  FConnectCb := AConnectedCb;

  FRecvLock := TLock.Create;
  FSentLock := TLock.Create;
  if (AOwner.FMaxPendingSendCount > 0) or (AOwner.FMaxPendingSendBytes > 0) then
  begin
    FSendLimits := TCrossSendLimits.Create(AOwner.FMaxPendingSendCount, AOwner.FMaxPendingSendBytes);
    AtomicExchange(AOwner.FHasSendLimits, 1);
  end;
end;

procedure TCrossConnectionBase.SetConnectStatus(const AValue: TConnectStatus);
begin
  _SetConnectStatus(AValue);
end;

procedure TCrossConnectionBase.Close;
begin
  if (_SetConnectStatus(csClosed) = csClosed) then Exit;
  _Close;
end;

procedure TCrossConnectionBase._Close;
var
  LSelf: ICrossConnection;
begin
  if (FSocket <> INVALID_SOCKET) then
  begin
    // TriggerDisconnected removes this connection from the owner list and runs
    // the user callback; either can drop our last reference. Keep one here so
    // the object survives until InternalClose is done.
    LSelf := Self;
    try
      FOwner.TriggerDisconnected(LSelf);
    finally
      try
        InternalClose;
      finally
        // 派生类的清理或用户回调异常也不能泄漏句柄。
        if FSocket <> INVALID_SOCKET then
        begin
          TSocketAPI.CloseSocket(FSocket);
          FSocket := INVALID_SOCKET;
        end;
      end;
    end;
  end;
end;

procedure TCrossConnectionBase._SetConnectOp(const AOp: IInterface);
begin
  // 只在连接发布前设置；之后通过连接锁取走。
  FConnectOp := AOp;
end;

function TCrossConnectionBase._TakeConnectOp: IInterface;
begin
  Result := nil;
  if FLock = nil then Exit;
  _Lock;
  try
    Result := FConnectOp;
    FConnectOp := nil;
  finally
    _Unlock;
  end;
end;

function TCrossConnectionBase._CloseRetryingConnect(out AOp: IInterface): Boolean;
var
  LConnectCb: TCrossConnectionCallback;
begin
  AOp := nil;
  _Lock;
  try
    // 只关闭仍在连接的尝试，不能撤销已经成功或被外部取消的终态。
    Result := AtomicCmpExchange(FConnectStatus, Integer(csClosed),
      Integer(csConnecting)) = Integer(csConnecting);
    if not Result then Exit;
    // 末次失败保留普通 Close 通知，调用者仍可读取连接的 LastNetError。
    if (FConnectOp <> nil) and (FConnectOp as TCrossConnectOp).HasNextAddr then
    begin
      AOp := FConnectOp;
      FConnectOp := nil;
      LConnectCb := FConnectCb;
      FConnectCb := nil;
    end;
  finally
    _Unlock;
  end;
  // 闭包最后一个引用的释放也放在锁外。
  LConnectCb := nil;
  try
    _Close;
  except
    // 清理抛错不能遗留一个再也不会收到结果的操作。
    if AOp <> nil then
      (AOp as TCrossConnectOp).Complete(nil, False);
    raise;
  end;
  Result := AOp <> nil;
end;

function TCrossConnectionBase.DebugInfo: string;
begin
  Result := TStrUtils.Format('socket=%d, type=%s, local=(%s:%d), remote=(%s:%d)', [
    Socket,
    TRttiUtils.EnumToStr<TConnectType>(ConnectType),
    LocalAddr, LocalPort,
    PeerAddr, PeerPort
  ]);
end;

destructor TCrossConnectionBase.Destroy;
var
  LConnectCb: TCrossConnectionCallback;
begin
  _TakeConnectOp;
  // 连接释放时, 调用连接回调, 告知连接失败
  // 连接成功后 FConnectCb 会被置为 nil,
  // 所以如果这里 FConnectCb 不等于 nil, 则表示连接释放时仍未连接成功
  LConnectCb := _TakeConnectCallback();
  _CallConnectionCallback(LConnectCb, Self, False);

  inherited;
end;

procedure TCrossConnectionBase.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LBuffer: Pointer;
begin
  if (FSocket = INVALID_SOCKET)
    or IsClosed then
  begin
    if Assigned(ACallback) then
      ACallback(Self, False);
    Exit;
  end;

  LBuffer := ABuffer;
  FOwner.Send(Self, LBuffer, ACount,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      try
        if ASuccess then
          FOwner.TriggerSent(AConnection, LBuffer, ACount);
      finally
        // OnSent 抛异常也必须结算本次发送；保留原始成功/失败结果。
        if Assigned(ACallback) then
          ACallback(AConnection, ASuccess);
      end;
    end);
end;

procedure TCrossConnectionBase.Disconnect;
var
  LStatus: Integer;
begin
  repeat
    LStatus := AtomicCmpExchange(FConnectStatus, 0, 0);
    if TConnectStatus(LStatus) in [csDisconnected, csClosed] then Exit;
  until AtomicCmpExchange(FConnectStatus, Integer(csDisconnected), LStatus) = LStatus;

  TSocketAPI.Shutdown(FSocket, 2);
end;

function TCrossConnectionBase.GetConnectStatus: TConnectStatus;
begin
  Result := TConnectStatus(AtomicCmpExchange(FConnectStatus, 0, 0));
end;

function TCrossConnectionBase.GetLastNetError: Integer;
begin
  Result := AtomicCmpExchange(FLastNetError, 0, 0);
end;

procedure TCrossConnectionBase.ConfigureProxy(
  const ASettings: TCrossProxySettings; const ATargetHost: string;
  const ATargetPort: Word);
begin
  FProxySettings := ASettings;
  FProxyTargetHost := ATargetHost;
  FProxyTargetPort := ATargetPort;
  FProxyBuffer := nil;
  FProxyStage := 0;

  if not ASettings.IsEnabled or ASettings.ShouldBypass(ATargetHost) then
    Exit;

  if ASettings.UsesHttpConnect then
    FProxyStage := 1
  else
  if ASettings.ProxyType = cptSocks4 then
    FProxyStage := 2
  else
  if ASettings.ProxyType = cptSocks5 then
    FProxyStage := 3;
end;

function TCrossConnectionBase.ProxyNeedsHandshake: Boolean;
begin
  Result := FProxyStage <> 0;
end;

function TCrossConnectionBase.ProxyUsesTlsTransport: Boolean;
begin
  Result := FProxySettings.UsesTlsProxyTransport;
end;

function TCrossConnectionBase.ProxySettings: TCrossProxySettings;
begin
  Result := FProxySettings;
end;

function TCrossConnectionBase.ProxyError: string;
begin
  Result := FProxyError;
end;

function TCrossConnectionBase.GetProxyError: string;
begin
  Result := FProxyError;
end;

function TCrossConnectionBase.ProxyStart(out ASendData: TBytes): Boolean;
begin
  ASendData := nil;
  if FProxyStage = 0 then
    Exit(False);

  case FProxyStage of
    1:
      ASendData := TCrossProxyCodec.BuildHttpConnect(
        FProxyTargetHost, FProxyTargetPort,
        FProxySettings.Username, FProxySettings.Password);
    2:
      ASendData := TCrossProxyCodec.BuildSocks4Connect(
        FProxyTargetHost, FProxyTargetPort, FProxySettings.Username);
    3:
      ASendData := TCrossProxyCodec.BuildSocks5Greeting(
        (FProxySettings.Username <> '') or (FProxySettings.Password <> ''));
  else
    Exit(False);
  end;

  Result := Length(ASendData) > 0;
end;

function TCrossConnectionBase.ProxyFeed(const ABuf: Pointer;
  const ALen: Integer; out ASendData, ARemain: TBytes): TCrossProxyFeedResult;
var
  LConsumed, LStatus: Integer;
  LMethod: Byte;
  LSuccess: Boolean;
  LBytes: TBytes;
begin
  ASendData := nil;
  ARemain := nil;
  if (ABuf = nil) or (ALen <= 0) then
    Exit(cpfrNeedData);

  LBytes := FProxyBuffer;
  SetLength(FProxyBuffer, Length(LBytes) + ALen);
  Move(ABuf^, FProxyBuffer[Length(LBytes)], ALen);

  case FProxyStage of
    1:
      begin
        if not TCrossProxyCodec.TryParseHttpConnectResponse(
          FProxyBuffer, LConsumed, LStatus) then
          Exit(cpfrNeedData);
        if (LStatus < 200) or (LStatus >= 300) then
        begin
          // 保留代理返回的认证状态, 避免上层只能看到笼统的 Connect failed。
          if LStatus = 407 then
            FProxyError := 'HTTP proxy authentication failed (407 Proxy Authentication Required)'
          else
            FProxyError := Format('HTTP proxy CONNECT failed with status %d', [LStatus]);
          Exit(cpfrFailed);
        end;
        ARemain := Copy(FProxyBuffer, LConsumed, MaxInt);
  FProxyBuffer := nil;
  FProxyError := '';
        FProxyStage := 0;
        Exit(cpfrComplete);
      end;
    2:
      begin
        if not TCrossProxyCodec.TryParseSocks4Response(
          FProxyBuffer, LConsumed, LSuccess) then
          Exit(cpfrNeedData);
        if not LSuccess then
          Exit(cpfrFailed);
        ARemain := Copy(FProxyBuffer, LConsumed, MaxInt);
        FProxyBuffer := nil;
        FProxyStage := 0;
        Exit(cpfrComplete);
      end;
    3:
      begin
        if not TCrossProxyCodec.TryParseSocks5MethodResponse(
          FProxyBuffer, LConsumed, LMethod) then
          Exit(cpfrNeedData);
        FProxyBuffer := Copy(FProxyBuffer, LConsumed, MaxInt);
        if LMethod = 0 then
        begin
          ASendData := TCrossProxyCodec.BuildSocks5Connect(
            FProxyTargetHost, FProxyTargetPort);
          FProxyStage := 5;
        end
        else
        if LMethod = 2 then
        begin
          ASendData := TCrossProxyCodec.BuildSocks5Auth(
            FProxySettings.Username, FProxySettings.Password);
          FProxyStage := 4;
        end
        else
        begin
          // SOCKS5 返回 $FF 表示代理不接受客户端提供的任何认证方式。
          if LMethod = $FF then
            FProxyError := 'SOCKS5 proxy authentication failed: no acceptable authentication method'
          else
            FProxyError := Format('SOCKS5 proxy authentication method %d is not supported', [LMethod]);
          Exit(cpfrFailed);
        end;
        Exit(cpfrSendData);
      end;
    4:
      begin
        if not TCrossProxyCodec.TryParseSocks5AuthResponse(
          FProxyBuffer, LConsumed, LSuccess) then
          Exit(cpfrNeedData);
        if not LSuccess then
        begin
          // 用户名密码校验失败必须在连接对象销毁前保存, 供上层回调读取。
          FProxyError := 'SOCKS5 proxy username/password authentication failed';
          Exit(cpfrFailed);
        end;
        FProxyBuffer := Copy(FProxyBuffer, LConsumed, MaxInt);
        ASendData := TCrossProxyCodec.BuildSocks5Connect(
          FProxyTargetHost, FProxyTargetPort);
        FProxyStage := 5;
        Exit(cpfrSendData);
      end;
    5:
      begin
        if not TCrossProxyCodec.TryParseSocks5ConnectResponse(
          FProxyBuffer, LConsumed, LSuccess) then
          Exit(cpfrNeedData);
        if not LSuccess then
        begin
          FProxyError := 'SOCKS5 proxy CONNECT request failed';
          Exit(cpfrFailed);
        end;
        ARemain := Copy(FProxyBuffer, LConsumed, MaxInt);
        FProxyBuffer := nil;
        FProxyStage := 0;
        Exit(cpfrComplete);
      end;
  end;

  Result := cpfrFailed;
end;

procedure TCrossConnectionBase.SetLastNetError(const AValue: Integer);
begin
  AtomicExchange(FLastNetError, AValue);
end;

function TCrossConnectionBase.GetConnectType: TConnectType;
begin
  Result := FConnectType;
end;

function TCrossConnectionBase.GetIsClosed: Boolean;
begin
  Result := (GetConnectStatus = csClosed);
end;

function TCrossConnectionBase.GetPeerAddr: string;
begin
  Result := FPeerAddr;
end;

function TCrossConnectionBase.GetPeerHost: string;
begin
  Result := FPeerHost;
end;

function TCrossConnectionBase.GetPeerPort: Word;
begin
  Result := FPeerPort;
end;

function TCrossConnectionBase.GetUIDTag: Byte;
begin
  Result := UID_CONNECTION;
end;

procedure TCrossConnectionBase.InternalClose;
var
  LConnectCb: TCrossConnectionCallback;
begin
  TSocketAPI.CloseSocket(FSocket);
  FSocket := INVALID_SOCKET;

  _TakeConnectOp;
  LConnectCb := _TakeConnectCallback();
  _CallConnectionCallback(LConnectCb, Self, False);
end;

function TCrossConnectionBase._TakeConnectCallback: TCrossConnectionCallback;
begin
  Result := nil;
  // 构造可能在父类创建锁前失败，此时回调尚未赋值。
  if not Assigned(FConnectCb) then Exit;
  _Lock;
  try
    Result := FConnectCb;
    FConnectCb := nil;
  finally
    _Unlock;
  end;
end;

procedure TCrossConnectionBase.SendBuf(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
{$IF defined(POSIX) or not defined(__LITTLE_PIECE__)}
begin
  DirectSend(ABuffer, ACount, ACallback);
end;
{$ELSE} // MSWINDOWS
// Windows下 iocp 发送数据会锁定非页面内存, 为了减少非页面内存的占用
// 采用将大数据分小块发送的策略, 一个小块发送完之后再发送下一个
var
  P: PByte;
  LSize: Integer;
  LSender: TCrossConnectionCallback;
begin
  P := ABuffer;
  LSize := ACount;

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: Integer;
    begin
      if not ASuccess then
      begin
        LSender := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, False);

        AConnection.Close;

        Exit;
      end;

      LData := P;
      LCount := Min(LSize, SND_BUF_SIZE);

      if (LSize > LCount) then
      begin
        Inc(P, LCount);
        Dec(LSize, LCount);
      end else
      begin
        LSize := 0;
        P := nil;
      end;

      if (LData = nil) or (LCount <= 0) then
      begin
        LSender := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, True);

        Exit;
      end;

      (AConnection as TCrossConnectionBase).DirectSend(LData, LCount, LSender);
    end;

  LSender(Self, True);
end;
{$ENDIF}

procedure TCrossConnectionBase.SendBuf(const ABuffer; const ACount: Integer;
  const ACallback: TCrossConnectionCallback);
begin
  SendBuf(@ABuffer, ACount, ACallback);
end;

procedure TCrossConnectionBase.SendBytes(const ABytes: TBytes;
  const AOffset, ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LBytes: TBytes;
begin
  // 增加引用计数
  // 由于 SendBuf 的 ABuffer 参数是直接传递的内存地址
  // 所以并不会增加 ABytes 的引用计数, 这里为了保证发送过程中数据的有效性
  // 需要定义一个局部变量用来引用 ABytes, 以维持其引用计数
  LBytes := ABytes;
  SendBuf(@LBytes[AOffset], ACount,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 减少引用计数
      LBytes := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossConnectionBase.SendBytes(const ABytes: TBytes;
  const ACallback: TCrossConnectionCallback);
begin
  SendBytes(ABytes, 0, Length(ABytes), ACallback);
end;

procedure TCrossConnectionBase.SendStream(const AStream: TStream;
  const ACallback: TCrossConnectionCallback);
var
  LBuffer: TBytes;
  LSender: TCrossConnectionCallback;
begin
  if (AStream is TBytesStream) then
  begin
    SendBytes(
      TBytesStream(AStream).Bytes,
      TBytesStream(AStream).Position,
      TBytesStream(AStream).Size - TBytesStream(AStream).Position,
      ACallback);
    Exit;
  end;

  SetLength(LBuffer, SND_BUF_SIZE);

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: Integer;
    begin
      if not ASuccess then
      begin
        LSender := nil;
        LBuffer := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, False);

        AConnection.Close;

        Exit;
      end;

      LData := @LBuffer[0];
      LCount := AStream.Read(LBuffer[0], SND_BUF_SIZE);

      if (LData = nil) or (LCount <= 0) then
      begin
        LSender := nil;
        LBuffer := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, True);

        Exit;
      end;

      (AConnection as TCrossConnectionBase).SendBuf(LData, LCount, LSender);
    end;

  LSender(Self, True);
end;

procedure TCrossConnectionBase.UpdateAddr;
var
  LAddr: TRawSockAddrIn;
begin
  inherited;

  {$region '远端地址信息'}
  FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
  LAddr.AddrLen := SizeOf(LAddr.Addr6);
  if (TSocketAPI.GetPeerName(FSocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen, FPeerAddr, FPeerPort);
  {$endregion}
end;

procedure TCrossConnectionBase._LockRecv;
begin
  FRecvLock.Enter;
end;

procedure TCrossConnectionBase._LockSent;
begin
  FSentLock.Enter;
end;

function TCrossConnectionBase._SetConnectStatus(
  const AStatus: TConnectStatus): TConnectStatus;
begin
  Result := TConnectStatus(AtomicExchange(FConnectStatus, Integer(AStatus)));
end;

procedure TCrossConnectionBase._UnlockRecv;
begin
  FRecvLock.Leave;
end;

procedure TCrossConnectionBase._UnlockSent;
begin
  FSentLock.Leave;
end;

end.
