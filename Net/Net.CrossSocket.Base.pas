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

// 是否将大块数据分成小块发送(仅IOCP下有效)
// 注意: 开启该开关的情况下, 同一个连接不要在一次发送尚未结束时开始另一次发送
//       否则会导致两块数据被分成小块后出现交错
{.$DEFINE __LITTLE_PIECE__}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  Net.SocketAPI;

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
  TAbstractCrossSocket = class;
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

  /// <summary>
  ///   基础数据接口
  /// </summary>
  ICrossData = interface
  ['{988404A3-D297-4C6D-9A76-16E50553596E}']
    function GetOwner: ICrossSocket;
    function GetUID: UInt64;
    function GetSocket: THandle;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean;
    function GetUserData: Pointer;
    function GetUserObject: TObject;
    function GetUserInterface: IInterface;

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
    ///   宿主对象
    /// </summary>
    property Owner: ICrossSocket read GetOwner;

    /// <summary>
    ///   唯一编号
    /// </summary>
    property UID: UInt64 read GetUID;

    /// <summary>
    ///   套接字句柄
    /// </summary>
    property Socket: THandle read GetSocket;

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
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;

    procedure SetConnectStatus(const Value: TConnectStatus);

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
    procedure SendBuf(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;

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
    procedure SendBuf(const ABuffer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;

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
    procedure SendBytes(const ABytes: TBytes; AOffset, ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;

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
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;

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
      const ACallback: TProc<ICrossConnection, Boolean> = nil);

    /// <summary>
    ///   连接IP地址
    /// </summary>
    property PeerAddr: string read GetPeerAddr;

    /// <summary>
    ///   连接端口
    /// </summary>
    property PeerPort: Word read GetPeerPort;

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
  end;
  TCrossConnections = TDictionary<UInt64, ICrossConnection>;

  TCrossIoThreadEvent = procedure(Sender: TObject; AIoThread: TIoEventThread) of object;
  TCrossListenEvent = procedure(Sender: TObject; AListen: ICrossListen) of object;
  TCrossConnectEvent = procedure(Sender: TObject; AConnection: ICrossConnection) of object;
  TCrossDataEvent = procedure(Sender: TObject; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer) of object;

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

    procedure SetOnIoThreadBegin(const Value: TCrossIoThreadEvent);
    procedure SetOnIoThreadEnd(const Value: TCrossIoThreadEvent);
    procedure SetOnConnected(const Value: TCrossConnectEvent);
    procedure SetOnDisconnected(const Value: TCrossConnectEvent);
    procedure SetOnListened(const Value: TCrossListenEvent);
    procedure SetOnListenEnd(const Value: TCrossListenEvent);
    procedure SetOnReceived(const Value: TCrossDataEvent);
    procedure SetOnSent(const Value: TCrossDataEvent);

    /// <summary>
    ///   启动IO循环
    /// </summary>
    procedure StartLoop;

    /// <summary>
    ///   停止IO循环
    /// </summary>
    procedure StopLoop;

    /// <summary>
    ///   处理IO事件
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
    procedure Listen(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossListen, Boolean> = nil);

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
    procedure Connect(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossConnection, Boolean> = nil);

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
    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil);

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
    ///   创建连接对象(内部使用)
    /// </summary>
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection;

    /// <summary>
    ///   创建监听对象(内部使用)
    /// </summary>
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen;

    {$region '物理事件'}
    /// <summary>
    ///   监听成功后触发(内部使用)
    /// </summary>
    /// <param name="AListen">
    ///   监听对象
    /// </param>
    procedure TriggerListened(AListen: ICrossListen);

    /// <summary>
    ///   监听结束后触发(内部使用)
    /// </summary>
    /// <param name="AListen">
    ///   监听对象
    /// </param>
    procedure TriggerListenEnd(AListen: ICrossListen);

    /// <summary>
    ///   正在连接(内部使用)
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    procedure TriggerConnecting(AConnection: ICrossConnection);

    /// <summary>
    ///   连接成功后触发(内部使用)
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    procedure TriggerConnected(AConnection: ICrossConnection);

    /// <summary>
    ///   连接断开后触发(内部使用)
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    procedure TriggerDisconnected(AConnection: ICrossConnection);
    {$endregion}

    /// <summary>
    ///   IO线程开始时触发
    /// </summary>
    procedure TriggerIoThreadBegin(AIoThread: TIoEventThread);

    /// <summary>
    ///   IO线程结束时触发
    /// </summary>
    procedure TriggerIoThreadEnd(AIoThread: TIoEventThread);

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
    class var FCrossUID: UInt64;
  private
    [unsafe]FOwner: ICrossSocket;
    FUID: UInt64;
    FSocket: THandle;
    FLocalAddr: string;
    FLocalPort: Word;
    FUserData: Pointer;
    FUserObject: TObject;
    FUserInterface: IInterface;
  protected
    function GetOwner: ICrossSocket;
    function GetUIDTag: Byte; virtual;
    function GetUID: UInt64;
    function GetSocket: THandle;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean; virtual; abstract;
    function GetUserData: Pointer;
    function GetUserObject: TObject;
    function GetUserInterface: IInterface;

    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TObject);
    procedure SetUserInterface(const AValue: IInterface);
  public
    constructor Create(AOwner: ICrossSocket; ASocket: THandle); virtual;
    destructor Destroy; override;

    procedure UpdateAddr; virtual;
    procedure Close; virtual; abstract;

    property Owner: ICrossSocket read GetOwner;
    property UID: UInt64 read GetUID;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
    property UserData: Pointer read GetUserData write SetUserData;
    property UserObject: TObject read GetUserObject write SetUserObject;
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;

  TAbstractCrossListen = class(TCrossData, ICrossListen)
  private
    FFamily: Integer;
    FSockType: Integer;
    FProtocol: Integer;
    FClosed: Integer;
  protected
    function GetUIDTag: Byte; override;
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;
    function GetIsClosed: Boolean; override;
  public
    constructor Create(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer); reintroduce; virtual;

    procedure Close; override;

    property Owner: ICrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
  end;

  TAbstractCrossConnection = class(TCrossData, ICrossConnection)
  public const
    SND_BUF_SIZE = 32768;
  private
    FPeerAddr: string;
    FPeerPort: Word;
    FConnectType: TConnectType;
    FConnectStatus: Integer;
  protected
    function GetUIDTag: Byte; override;
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;
    function GetIsClosed: Boolean; override;

    function _SetConnectStatus(const AStatus: TConnectStatus): TConnectStatus; inline;
    procedure SetConnectStatus(const Value: TConnectStatus);

    procedure DirectSend(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); virtual;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); reintroduce; virtual;

    procedure UpdateAddr; override;
    procedure Close; override;
    procedure Disconnect; virtual;

    procedure SendBuf(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;
    procedure SendBuf(const ABuffer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload; inline;
    procedure SendBytes(const ABytes: TBytes; AOffset, ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;
    procedure SendBytes(const ABytes: TBytes;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload; inline;
    procedure SendStream(const AStream: TStream;
      const ACallback: TProc<ICrossConnection, Boolean> = nil);

    property Owner: ICrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;

    property PeerAddr: string read GetPeerAddr;
    property PeerPort: Word read GetPeerPort;
    property ConnectType: TConnectType read GetConnectType;
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;
  end;

  TIoEventThread = class(TThread)
  private
    [unsafe]FCrossSocket: ICrossSocket;
  protected
    procedure Execute; override;
  public
    constructor Create(ACrossSocket: ICrossSocket); reintroduce;
  end;

  TAbstractCrossSocket = class abstract(TInterfacedObject, ICrossSocket)
  protected const
    RCV_BUF_SIZE = 32768;
  protected class threadvar
    FRecvBuf: array [0..RCV_BUF_SIZE-1] of Byte;
  protected
    FIoThreads: Integer;

    // 设置套接字心跳参数, 用于处理异常断线(拔网线, 主机异常掉电等造成的网络异常)
    function SetKeepAlive(ASocket: THandle): Integer;
  private
    FConnections: TCrossConnections;
    FConnectionsLock: TObject;

    FListens: TCrossListens;
    FListensLock: TObject;

    FOnIoThreadBegin: TCrossIoThreadEvent;
    FOnIoThreadEnd: TCrossIoThreadEvent;
    FOnListened: TCrossListenEvent;
    FOnListenEnd: TCrossListenEvent;
    FOnConnected: TCrossConnectEvent;
    FOnDisconnected: TCrossConnectEvent;
    FOnReceived: TCrossDataEvent;
    FOnSent: TCrossDataEvent;

    procedure _LockConnections; inline;
    procedure _UnlockConnections; inline;

    procedure _LockListens; inline;
    procedure _UnlockListens; inline;

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

    procedure SetOnIoThreadBegin(const Value: TCrossIoThreadEvent);
    procedure SetOnIoThreadEnd(const Value: TCrossIoThreadEvent);
    procedure SetOnConnected(const Value: TCrossConnectEvent);
    procedure SetOnDisconnected(const Value: TCrossConnectEvent);
    procedure SetOnListened(const Value: TCrossListenEvent);
    procedure SetOnListenEnd(const Value: TCrossListenEvent);
    procedure SetOnReceived(const Value: TCrossDataEvent);
    procedure SetOnSent(const Value: TCrossDataEvent);
  protected
    FConnectionsCount: Integer;
    FListensCount: Integer;

    function ProcessIoEvent: Boolean; virtual; abstract;
    function GetIoThreads: Integer; virtual;

    // 创建连接对象
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; virtual; abstract;

    // 创建监听对象
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; virtual; abstract;

    {$region '物理事件'}
    procedure TriggerListened(AListen: ICrossListen); virtual;
    procedure TriggerListenEnd(AListen: ICrossListen); virtual;

    procedure TriggerConnecting(AConnection: ICrossConnection); virtual;
    procedure TriggerConnected(AConnection: ICrossConnection); virtual;
    procedure TriggerDisconnected(AConnection: ICrossConnection); virtual;

    procedure TriggerReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    procedure TriggerSent(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    {$endregion}

    {$region '逻辑事件'}
    // 这几个虚方法用于在派生类中使用
    // 比如SSL中网络端口收到的是加密数据, 可能要几次接收才会收到一个完整的
    // 已加密数据包, 然后才能解密出数据, 也就是说可能几次网络端口的接收才
    // 会对应到一次实际的数据接收, 所以设计了以下接口, 以下接口是实际数据
    // 发生时才会被触发的
    procedure LogicConnected(AConnection: ICrossConnection); virtual;
    procedure LogicDisconnected(AConnection: ICrossConnection); virtual;
    procedure LogicReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    procedure LogicSent(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    {$endregion}

    procedure TriggerIoThreadBegin(AIoThread: TIoEventThread); virtual;
    procedure TriggerIoThreadEnd(AIoThread: TIoEventThread); virtual;

    procedure StartLoop; virtual; abstract;
    procedure StopLoop; virtual; abstract;

    procedure Listen(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossListen, Boolean> = nil); virtual; abstract;

    procedure Connect(const AHost: string; APort: Word;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); virtual; abstract;

    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); virtual; abstract;

    procedure CloseAllConnections; virtual;
    procedure CloseAllListens; virtual;
    procedure CloseAll; virtual;
    procedure DisconnectAll; virtual;
  public
    constructor Create(AIoThreads: Integer); virtual;
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

    property OnIoThreadBegin: TCrossIoThreadEvent read GetOnIoThreadBegin write SetOnIoThreadBegin;
    property OnIoThreadEnd: TCrossIoThreadEvent read GetOnIoThreadEnd write SetOnIoThreadEnd;
    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  function GetTagByUID(const AUID: UInt64): Byte;

  procedure _LogLastOsError(const ATag: string = '');
  procedure _Log(const S: string); overload;
  procedure _Log(const Fmt: string; const Args: array of const); overload;

implementation

uses
  Utils.Logger;

function GetTagByUID(const AUID: UInt64): Byte;
begin
  // 取最高 2 位
  Result := (AUID shr 62) and $03;
end;

procedure _Log(const S: string); overload;
begin
  if IsConsole then
    Writeln(S)
  else
    AppendLog(S);
end;

procedure _Log(const Fmt: string; const Args: array of const); overload;
begin
  _Log(Format(Fmt, Args));
end;

procedure _LogLastOsError(const ATag: string);
{$IFDEF DEBUG}
var
  LError: Integer;
  LErrMsg: string;
{$ENDIF}
begin
  {$IFDEF DEBUG}
  LError := GetLastError;
  if (ATag <> '') then
    LErrMsg := ATag + ' : '
  else
    LErrMsg := '';
  LErrMsg := LErrMsg + Format('System Error.  Code: %0:d(%0:.4x), %1:s',
    [LError, SysErrorMessage(LError)]);
  _Log(LErrMsg);
  {$ENDIF}
end;

{ TIoEventThread }

constructor TIoEventThread.Create(ACrossSocket: ICrossSocket);
begin
  inherited Create(True);
  FCrossSocket := ACrossSocket;
  Suspended := False;
end;

procedure TIoEventThread.Execute;
var
  {$IFDEF DEBUG}
  LRunCount: Int64;
  {$ENDIF}
  LCrossSocketObj: TAbstractCrossSocket;
begin
  LCrossSocketObj := FCrossSocket as TAbstractCrossSocket;
  try
    LCrossSocketObj.TriggerIoThreadBegin(Self);
    {$IFDEF DEBUG}
    LRunCount := 0;
    {$ENDIF}
    while not Terminated do
    begin
      try
        if not LCrossSocketObj.ProcessIoEvent then Break;
      except
        {$IFDEF DEBUG}
        on e: Exception do
          _Log('%s Io线程ID %d, 异常 %s, %s', [TAbstractCrossSocket(FCrossSocket).ClassName, Self.ThreadID, e.ClassName, e.Message]);
        {$ENDIF}
      end;
      {$IFDEF DEBUG}
      Inc(LRunCount)
      {$ENDIF};
    end;
    {$IFDEF DEBUG}
  //  _Log('%s Io线程ID %d, 被调用了 %d 次', [TAbstractCrossSocket(FCrossSocket).ClassName, Self.ThreadID, LRunCount]);
    {$ENDIF}
  finally
    LCrossSocketObj.TriggerIoThreadEnd(Self);
  end;
end;

{ TAbstractCrossSocket }

procedure TAbstractCrossSocket.CloseAll;
begin
  CloseAllListens;
  CloseAllConnections;
end;

procedure TAbstractCrossSocket.CloseAllConnections;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Close;
end;

procedure TAbstractCrossSocket.CloseAllListens;
var
  LListenArr: TArray<ICrossListen>;
  LListen: ICrossListen;
begin
  _LockListens;
  try
    LListenArr := FListens.Values.ToArray;
  finally
    _UnlockListens;
  end;

  for LListen in LListenArr do
    LListen.Close;
end;

constructor TAbstractCrossSocket.Create(AIoThreads: Integer);
begin
  FIoThreads := AIoThreads;

  FListens := TCrossListens.Create;
  FListensLock := TObject.Create;

  FConnections := TCrossConnections.Create;
  FConnectionsLock := TObject.Create;
end;

destructor TAbstractCrossSocket.Destroy;
begin
  FreeAndNil(FListens);
  FreeAndNil(FListensLock);

  FreeAndNil(FConnections);
  FreeAndNil(FConnectionsLock);

  inherited;
end;

procedure TAbstractCrossSocket.DisconnectAll;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Disconnect;
end;

procedure TAbstractCrossSocket.AfterConstruction;
begin
  StartLoop;
  inherited AfterConstruction;
end;

procedure TAbstractCrossSocket.BeforeDestruction;
begin
  StopLoop;
  inherited BeforeDestruction;
end;

function TAbstractCrossSocket.GetConnectionsCount: Integer;
begin
  Result := FConnectionsCount;
end;

function TAbstractCrossSocket.GetIoThreads: Integer;
begin
  if (FIoThreads > 0) then
    Result := FIoThreads
  else
    Result := CPUCount * 2 + 1;
end;

function TAbstractCrossSocket.GetListensCount: Integer;
begin
  Result := FListensCount;
end;

function TAbstractCrossSocket.GetOnConnected: TCrossConnectEvent;
begin
  Result := FOnConnected;
end;

function TAbstractCrossSocket.GetOnDisconnected: TCrossConnectEvent;
begin
  Result := FOnDisconnected;
end;

function TAbstractCrossSocket.GetOnIoThreadBegin: TCrossIoThreadEvent;
begin
  Result := FOnIoThreadBegin;
end;

function TAbstractCrossSocket.GetOnIoThreadEnd: TCrossIoThreadEvent;
begin
  Result := FOnIoThreadEnd;
end;

function TAbstractCrossSocket.GetOnListened: TCrossListenEvent;
begin
  Result := FOnListened;
end;

function TAbstractCrossSocket.GetOnListenEnd: TCrossListenEvent;
begin
  Result := FOnListenEnd;
end;

function TAbstractCrossSocket.GetOnReceived: TCrossDataEvent;
begin
  Result := FOnReceived;
end;

function TAbstractCrossSocket.GetOnSent: TCrossDataEvent;
begin
  Result := FOnSent;
end;

function TAbstractCrossSocket.LockConnections: TCrossConnections;
begin
  _LockConnections;
  Result := FConnections;
end;

function TAbstractCrossSocket.LockListens: TCrossListens;
begin
  _LockListens;
  Result := FListens;
end;

procedure TAbstractCrossSocket.LogicConnected(AConnection: ICrossConnection);
begin

end;

procedure TAbstractCrossSocket.LogicDisconnected(AConnection: ICrossConnection);
begin

end;

procedure TAbstractCrossSocket.LogicReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin

end;

procedure TAbstractCrossSocket.LogicSent(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin

end;

function TAbstractCrossSocket.SetKeepAlive(ASocket: THandle): Integer;
begin
  Result := TSocketAPI.SetKeepAlive(ASocket, 5, 3, 5);
end;

procedure TAbstractCrossSocket.SetOnConnected(const Value: TCrossConnectEvent);
begin
  FOnConnected := Value;
end;

procedure TAbstractCrossSocket.SetOnDisconnected(const Value: TCrossConnectEvent);
begin
  FOnDisconnected := Value;
end;

procedure TAbstractCrossSocket.SetOnIoThreadBegin(
  const Value: TCrossIoThreadEvent);
begin
  FOnIoThreadBegin := Value;
end;

procedure TAbstractCrossSocket.SetOnIoThreadEnd(
  const Value: TCrossIoThreadEvent);
begin
  FOnIoThreadEnd := Value;
end;

procedure TAbstractCrossSocket.SetOnListened(const Value: TCrossListenEvent);
begin
  FOnListened := Value;
end;

procedure TAbstractCrossSocket.SetOnListenEnd(const Value: TCrossListenEvent);
begin
  FOnListenEnd := Value;
end;

procedure TAbstractCrossSocket.SetOnReceived(const Value: TCrossDataEvent);
begin
  FOnReceived := Value;
end;

procedure TAbstractCrossSocket.SetOnSent(const Value: TCrossDataEvent);
begin
  FOnSent := Value;
end;

procedure TAbstractCrossSocket.TriggerConnecting(AConnection: ICrossConnection);
begin
  AConnection.ConnectStatus := csConnecting;

  _LockConnections;
  try
    if not FConnections.ContainsKey(AConnection.UID) then
      Inc(FConnectionsCount);

    FConnections.AddOrSetValue(AConnection.UID, AConnection);
  finally
    _UnlockConnections;
  end;
end;

procedure TAbstractCrossSocket.TriggerConnected(AConnection: ICrossConnection);
begin
  AConnection.UpdateAddr;
  AConnection.ConnectStatus := csConnected;

  LogicConnected(AConnection);

  if Assigned(FOnConnected) then
    FOnConnected(Self, AConnection);
end;

procedure TAbstractCrossSocket.TriggerDisconnected(AConnection: ICrossConnection);
begin
  AConnection.ConnectStatus := csClosed;

  _LockConnections;
  try
    if not FConnections.ContainsKey(AConnection.UID) then Exit;

    FConnections.Remove(AConnection.UID);
    Dec(FConnectionsCount);
  finally
    _UnlockConnections;
  end;

  LogicDisconnected(AConnection);

  if Assigned(FOnDisconnected) then
    FOnDisconnected(Self, AConnection);
end;

procedure TAbstractCrossSocket.TriggerIoThreadBegin(AIoThread: TIoEventThread);
begin
  if Assigned(FOnIoThreadBegin) then
    FOnIoThreadBegin(Self, AIoThread);
end;

procedure TAbstractCrossSocket.TriggerIoThreadEnd(AIoThread: TIoEventThread);
begin
  if Assigned(FOnIoThreadEnd) then
    FOnIoThreadEnd(Self, AIoThread);
end;

procedure TAbstractCrossSocket.TriggerListened(AListen: ICrossListen);
begin
  AListen.UpdateAddr;

  _LockListens;
  try
    FListens.AddOrSetValue(AListen.UID, AListen);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListened) then
    FOnListened(Self, AListen);
end;

procedure TAbstractCrossSocket.TriggerListenEnd(AListen: ICrossListen);
begin
  _LockListens;
  try
    if not FListens.ContainsKey(AListen.UID) then Exit;
    FListens.Remove(AListen.UID);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListenEnd) then
    FOnListenEnd(Self, AListen);
end;

procedure TAbstractCrossSocket.TriggerReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
  LogicReceived(AConnection, ABuf, ALen);

  if Assigned(FOnReceived) then
    FOnReceived(Self, AConnection, ABuf, ALen);
end;

procedure TAbstractCrossSocket.TriggerSent(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
  LogicSent(AConnection, ABuf, ALen);

  if Assigned(FOnSent) then
    FOnSent(Self, AConnection, ABuf, ALen);
end;

procedure TAbstractCrossSocket.UnlockConnections;
begin
  _UnlockConnections;
end;

procedure TAbstractCrossSocket.UnlockListens;
begin
  _UnlockListens;
end;

procedure TAbstractCrossSocket._LockConnections;
begin
  System.TMonitor.Enter(FConnectionsLock);
end;

procedure TAbstractCrossSocket._LockListens;
begin
  System.TMonitor.Enter(FListensLock);
end;

procedure TAbstractCrossSocket._UnlockConnections;
begin
  System.TMonitor.Exit(FConnectionsLock);
end;

procedure TAbstractCrossSocket._UnlockListens;
begin
  System.TMonitor.Exit(FListensLock);
end;

{ TCrossData }

constructor TCrossData.Create(AOwner: ICrossSocket; ASocket: THandle);
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
end;

destructor TCrossData.Destroy;
begin
  if (FSocket <> INVALID_HANDLE_VALUE) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    {$IFDEF DEBUG}
//    _Log('close result %d', [GetLastError]);
    {$ENDIF}
    FSocket := INVALID_HANDLE_VALUE;
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

function TCrossData.GetOwner: ICrossSocket;
begin
  Result := FOwner;
end;

function TCrossData.GetSocket: THandle;
begin
  Result := FSocket;
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

{ TAbstractCrossListen }

constructor TAbstractCrossListen.Create(AOwner: ICrossSocket; AListenSocket: THandle;
  AFamily, ASockType, AProtocol: Integer);
begin
  inherited Create(AOwner, AListenSocket);

  FFamily := AFamily;
  FSockType := ASockType;
  FProtocol := AProtocol;

  FClosed := 0;
end;

procedure TAbstractCrossListen.Close;
begin
  if (AtomicExchange(FClosed, 1) = 1) then Exit;

  if (FSocket <> INVALID_HANDLE_VALUE) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FOwner.TriggerListenEnd(Self);
    FSocket := INVALID_HANDLE_VALUE;
  end;
end;

function TAbstractCrossListen.GetFamily: Integer;
begin
  Result := FFamily;
end;

function TAbstractCrossListen.GetIsClosed: Boolean;
begin
  Result := (FClosed = 1);
end;

function TAbstractCrossListen.GetProtocol: Integer;
begin
  Result := FProtocol;
end;

function TAbstractCrossListen.GetSockType: Integer;
begin
  Result := FSockType;
end;

function TAbstractCrossListen.GetUIDTag: Byte;
begin
  Result := UID_LISTEN;
end;

{ TAbstractCrossConnection }

constructor TAbstractCrossConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited Create(AOwner, AClientSocket);

  FConnectType := AConnectType;
end;

procedure TAbstractCrossConnection.SetConnectStatus(const Value: TConnectStatus);
begin
  _SetConnectStatus(Value);
end;

procedure TAbstractCrossConnection.Close;
begin
  if (_SetConnectStatus(csClosed) = csClosed) then Exit;

  if (FSocket <> INVALID_HANDLE_VALUE) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FOwner.TriggerDisconnected(Self);
    FSocket := INVALID_HANDLE_VALUE;
  end;
end;

procedure TAbstractCrossConnection.DirectSend(ABuffer: Pointer; ACount: Integer;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LConnection: ICrossConnection;
  LBuffer: Pointer;
begin
  LConnection := Self as ICrossConnection;

  if (FSocket = INVALID_HANDLE_VALUE)
    or IsClosed then
  begin
    if Assigned(ACallback) then
      ACallback(LConnection, False);
    Exit;
  end;

  LBuffer := ABuffer;
  FOwner.Send(LConnection, LBuffer, ACount,
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      if ASuccess then
        (FOwner as TAbstractCrossSocket).TriggerSent(AConnection, LBuffer, ACount);

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TAbstractCrossConnection.Disconnect;
begin
  if (_SetConnectStatus(csDisconnected) in [csDisconnected, csClosed]) then Exit;

  TSocketAPI.Shutdown(FSocket, 2);
end;

function TAbstractCrossConnection.GetConnectStatus: TConnectStatus;
begin
  Result := TConnectStatus(AtomicCmpExchange(FConnectStatus, 0, 0));
end;

function TAbstractCrossConnection.GetConnectType: TConnectType;
begin
  Result := FConnectType;
end;

function TAbstractCrossConnection.GetIsClosed: Boolean;
begin
  Result := (GetConnectStatus = csClosed);
end;

function TAbstractCrossConnection.GetPeerAddr: string;
begin
  Result := FPeerAddr;
end;

function TAbstractCrossConnection.GetPeerPort: Word;
begin
  Result := FPeerPort;
end;

function TAbstractCrossConnection.GetUIDTag: Byte;
begin
  Result := UID_CONNECTION;
end;

procedure TAbstractCrossConnection.SendBuf(ABuffer: Pointer; ACount: Integer;
  const ACallback: TProc<ICrossConnection, Boolean>);
{$IF defined(POSIX) or not defined(__LITTLE_PIECE__)}
begin
  DirectSend(ABuffer, ACount, ACallback);
end;
{$ELSE} // MSWINDOWS
// Windows下 iocp 发送数据会锁定非页面内存, 为了减少非页面内存的占用
// 采用将大数据分小块发送的策略, 一个小块发送完之后再发送下一个
var
  LConnection: ICrossConnection;
  P: PByte;
  LSize: Integer;
  LSender: TProc<ICrossConnection, Boolean>;
begin
  LConnection := Self;
  P := ABuffer;
  LSize := ACount;

  LSender :=
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
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

      TAbstractCrossConnection(AConnection).DirectSend(LData, LCount, LSender);
    end;

  LSender(LConnection, True);
end;
{$ENDIF}

procedure TAbstractCrossConnection.SendBuf(const ABuffer; ACount: Integer;
  const ACallback: TProc<ICrossConnection, Boolean>);
begin
  SendBuf(@ABuffer, ACount, ACallback);
end;

procedure TAbstractCrossConnection.SendBytes(const ABytes: TBytes; AOffset,
  ACount: Integer; const ACallback: TProc<ICrossConnection, Boolean>);
var
  LBytes: TBytes;
begin
  // 增加引用计数
  // 由于 SendBuf 的 ABuffer 参数是直接传递的内存地址
  // 所以并不会增加 ABytes 的引用计数, 这里为了保证发送过程中数据的有效性
  // 需要定义一个局部变量用来引用 ABytes, 以维持其引用计数
  LBytes := ABytes;
  SendBuf(@LBytes[AOffset], ACount,
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      // 减少引用计数
      LBytes := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TAbstractCrossConnection.SendBytes(const ABytes: TBytes;
  const ACallback: TProc<ICrossConnection, Boolean>);
begin
  SendBytes(ABytes, 0, Length(ABytes), ACallback);
end;

procedure TAbstractCrossConnection.SendStream(const AStream: TStream;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LConnection: ICrossConnection;
  LBuffer: TBytes;
  LSender: TProc<ICrossConnection, Boolean>;
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

  LConnection := Self;
  SetLength(LBuffer, SND_BUF_SIZE);

  LSender :=
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
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

      TAbstractCrossConnection(AConnection).DirectSend(LData, LCount, LSender);
    end;

  LSender(LConnection, True);
end;

procedure TAbstractCrossConnection.UpdateAddr;
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

function TAbstractCrossConnection._SetConnectStatus(
  const AStatus: TConnectStatus): TConnectStatus;
begin
  Result := TConnectStatus(AtomicExchange(FConnectStatus, Integer(AStatus)));
end;

end.
