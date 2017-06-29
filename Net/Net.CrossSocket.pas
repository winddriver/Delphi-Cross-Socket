{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket;

{
# Delphi 跨平台 Socket 通讯库

作者: WiNDDRiVER(soulawing@gmail.com)

## 特性

- 针对不同平台使用不同的IO模型:
  - IOCP
  > Windows

  - KQUEUE
  > FreeBSD(MacOSX, iOS...)

  - EPOLL
  > Linux(Linux, Android...)

- 支持极高的并发

  - Windows
  > 能跑10万以上的并发数, 需要修改注册表调整默认的最大端口数

  - Mac
  > 做了初步测试, 测试环境为虚拟机中的 OSX 10.9.5, 即便修改了系统的句柄数限制,
  > 最多也只能打开32000多个并发连接, 或许 OSX Server 版能支持更高的并发吧

- 同时支持IPv4、IPv6

- 零内存拷贝

## 已通过测试
- Windows
- OSX
- iOS
- Android
- Linux

## 已知问题
- iOS做了初步测试, 连接数超过80以后还有些问题, 不过通常iOS下的应用谁会去开好几十
  连接呢？

- Android初步测试, 并发到450之后就无法增加了, 可能受限于系统的文件句柄数设置.

- Ubuntu桌面版下似乎有内存泄漏
  但是追查不到到底是哪部分代码造成的,
  甚至无法确定是delphi内置的rtl库还是我所写的代码引起的.
  通过 LeakCheck 库能粗略看出引起内存泄漏的是一个 AnsiString 变量,
  并不能定位到具体的代码.
  但是我自己的代码里根本没有任何地方定义或者使用过类似的变量,
  其它Linux发行版本尚未测试.
}

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  Net.CrossSocket.EventLoop,
  {$IFDEF MSWINDOWS}
  Net.CrossSocket.IocpLoop,
  {$ELSEIF defined(MACOS) or defined(IOS)}
  Net.CrossSocket.KqueueLoop,
  {$ELSEIF defined(LINUX) or defined(ANDROID)}
  Net.CrossSocket.EpollLoop,
  {$ENDIF}
  Net.SocketAPI;

type
  TEventLoop =
    {$IFDEF MSWINDOWS}
    TIocpLoop
    {$ELSEIF defined(MACOS) or defined(IOS)}
    TKqueueLoop
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollLoop
    {$ENDIF};


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

  TCustomCrossSocket = class;

  /// <summary>
  ///   连接接口
  /// </summary>
  ICrossConnection = interface
  ['{13C2A39E-C918-49B9-BBD3-A99110F94D1B}']
    function GetOwner: TCustomCrossSocket;
    function GetSocket: THandle;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;

    // 初始化
    procedure Initialize;

    // 回收资源
    procedure Finalize;

    /// <summary>
    ///   强制关闭
    /// </summary>
    procedure Close;

    /// <summary>
    ///   优雅关闭
    /// </summary>
    procedure Disconnect;

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
      const ACallback: TProc<ICrossConnection, Boolean> = nil);

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
    ///   宿主对象
    /// </summary>
    property Owner: TCustomCrossSocket read GetOwner;

    /// <summary>
    ///   Socket句柄
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
  end;

  TCrossConnection = class(TInterfacedObject, ICrossConnection)
  public const
    SND_BUF_SIZE = 32768;
  private
    FOwner: TCustomCrossSocket;
    FSocket: THandle;
    FLocalAddr, FPeerAddr: string;
    FLocalPort, FPeerPort: Word;
    FConnectType: Integer;

    function GetOwner: TCustomCrossSocket;
    function GetSocket: THandle;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;
  protected
    procedure Initialize; virtual;
    procedure Finalize; virtual;

    procedure DirectSend(const ABuffer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); virtual;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    procedure Close; virtual;
    procedure Disconnect; virtual;

    procedure SendBuf(const ABuffer; ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil);
    procedure SendBytes(const ABytes: TBytes; AOffset, ACount: Integer;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;
    procedure SendBytes(const ABytes: TBytes;
      const ACallback: TProc<ICrossConnection, Boolean> = nil); overload;
    procedure SendStream(const AStream: TStream;
      const ACallback: TProc<ICrossConnection, Boolean> = nil);

    property Owner: TCustomCrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property PeerAddr: string read GetPeerAddr;
    property PeerPort: Word read GetPeerPort;
    property ConnectType: TConnectType read GetConnectType;
  end;

  TCrossConnectionClass = class of TCrossConnection;

  TCrossSockEvent = procedure(Sender: TObject; ASocket: THandle) of object;
  TCrossConnEvent = procedure(Sender: TObject; AConnection: ICrossConnection) of object;
  TCrossConnDataEvent = procedure(Sender: TObject; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer) of object;
  TCrossConnClassEvent = procedure(Sender: TObject; var AConnClass: TCrossConnectionClass) of object;

  TCustomCrossSocket = class(TEventLoop)
  private
    FConnections: TDictionary<THandle, ICrossConnection>;
    FConnectionsLocker: TMultiReadExclusiveWriteSynchronizer;
    FListenSockets: TDictionary<THandle, Byte>;
    FListenSocketsLocker: TMultiReadExclusiveWriteSynchronizer;
    FOnGetConnectionClass: TCrossConnClassEvent;
    FOnListened: TCrossSockEvent;
    FOnListenEnd: TCrossSockEvent;
    FOnConnected: TCrossConnEvent;
    FOnConnectFailed: TCrossSockEvent;
    FOnDisconnected: TCrossConnEvent;
    FOnReceived: TCrossConnDataEvent;
    FOnSent: TCrossConnDataEvent;
  protected
    procedure TriggerListened(ASocket: THandle); override;
    procedure TriggerListenEnd(ASocket: THandle); override;
    procedure TriggerConnected(ASocket: THandle; AConnectType: Integer); overload; override;
    procedure TriggerConnectFailed(ASocket: THandle); override;
    procedure TriggerDisconnected(ASocket: THandle); overload; override;

    // 收到数据后会触发该调用
    // 参数 ABuf 中的数据只有在调用所在线程使用才能保证有效性
    // 如果要在其它线程中使用该数据, 请自行复制一份
    procedure TriggerReceived(ASocket: THandle; ABuf: Pointer; ALen: Integer); overload; override;

    function IsListen(ASocket: THandle): Boolean; override;

    procedure TriggerConnected(AConnection: ICrossConnection); overload; virtual;
    procedure TriggerDisconnected(AConnection: ICrossConnection); overload; virtual;
    procedure TriggerReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); overload; virtual;
    procedure TriggerSent(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); overload; virtual;

    {$region '逻辑事件'}
    // 这几个虚方法用于在派生类中使用
    // 比如SSL中网络端口收到的是加密数据, 可能要几次接收才会收到一个完整的
    // 已加密数据包, 然后才能解密出数据, 也就是说可能几次网络端口的接收才
    // 会对应到一次实际的数据接收, 所以设计了以下接口, 以下接口是实际数据
    // 发生时才会被触发的
    procedure LogicConnected(AConnection: ICrossConnection); virtual;
    procedure LogicConnectFailed(ASocket: THandle); virtual;
    procedure LogicDisconnected(AConnection: ICrossConnection); virtual;
    procedure LogicReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    procedure LogicSent(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    {$endregion}

    function GetConnectionClass: TCrossConnectionClass; virtual;

    procedure CloseAllConnections; override;
    procedure CloseAllListens; override;
    procedure CloseAll; override;
    procedure DisconnectAll; override;

    property OnGetConnectionClass: TCrossConnClassEvent read FOnGetConnectionClass write FOnGetConnectionClass;
    property OnListened: TCrossSockEvent read FOnListened write FOnListened;
    property OnListenEnd: TCrossSockEvent read FOnListenEnd write FOnListenEnd;
    property OnConnectFailed: TCrossSockEvent read FOnConnectFailed write FOnConnectFailed;
    property OnConnected: TCrossConnEvent read FOnConnected write FOnConnected;
    property OnDisconnected: TCrossConnEvent read FOnDisconnected write FOnDisconnected;
    property OnReceived: TCrossConnDataEvent read FOnReceived write FOnReceived;
    property OnSent: TCrossConnDataEvent read FOnSent write FOnSent;
  public
    constructor Create(AIoThreads: Integer); override;
    destructor Destroy; override;

    function LockConnections: TDictionary<THandle, ICrossConnection>;
    function GetConnection(const ASocket: THandle): ICrossConnection;
    procedure UnlockConnections;
  end;

  TCrossSocket = class(TCustomCrossSocket)
  public
    procedure AfterConstruction; override;

    /// <summary>
    ///   启动IO处理
    /// </summary>
    procedure StartLoop; override;

    /// <summary>
    ///   停止IO处理
    /// </summary>
    procedure StopLoop; override;

    /// <summary>
    ///   连接到服务器
    /// </summary>
    /// <param name="AHost">
    ///   地址
    /// </param>
    /// <param name="APort">
    ///   端口
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <returns>
    ///   返回值只能表明 connect 调用是否成功
    ///   <list type="bullet">
    ///     <item>
    ///       0, 调用成功
    ///     </item>
    ///     <item>
    ///       非0, 调用失败
    ///     </item>
    ///   </list>
    ///   当回调被触发时才表明连接建立或连接失败
    /// </returns>
    function Connect(const AHost: string; APort: Word;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; override;

    /// <summary>
    ///   建立监听
    /// </summary>
    /// <param name="AHost">
    ///   地址
    ///   <list type="bullet">
    ///     <item>
    ///       '', 监听所有IPv4及IPv6地址
    ///     </item>
    ///     <item>
    ///       '0.0.0.0', 监听所有IPv4地址
    ///     </item>
    ///     <item>
    ///       '::', 监听所有IPv6地址
    ///     </item>
    ///     <item>
    ///       '127.0.0.1', 监听本地IPv4回环地址
    ///     </item>
    ///     <item>
    ///       '::1', 监听本地IPv6回环地址
    ///     </item>
    ///   </list>
    /// </param>
    /// <param name="APort">
    ///   端口
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <returns>
    ///   返回值只能表明 bind 是否调用成功
    ///   <list type="bullet">
    ///     <item>
    ///       0, 调用成功
    ///     </item>
    ///     <item>
    ///       非0, 调用失败
    ///     </item>
    ///   </list>
    ///   当回调被触发时才表明监听成功或失败
    /// </returns>
    function Listen(const AHost: string; APort: Word;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; override;

    /// <summary>
    ///   强制关闭所有连接
    /// </summary>
    procedure CloseAllConnections; override;

    /// <summary>
    ///   强制关闭所有监听
    /// </summary>
    procedure CloseAllListens; override;

    /// <summary>
    ///   强制关闭所有连接及监听
    /// </summary>
    procedure CloseAll; override;

    /// <summary>
    ///   优雅断开所有连接
    /// </summary>
    procedure DisconnectAll; override;

    /// <summary>
    ///   监听数
    /// </summary>
    property ListensCount;

    /// <summary>
    ///   连接数
    /// </summary>
    property ConnectionsCount;

    property OnGetConnectionClass;
    property OnListened;
    property OnListenEnd;
    property OnConnectFailed;
    property OnConnected;
    property OnDisconnected;
    property OnReceived;
    property OnSent;
  end;

implementation

uses
  System.Math, Utils.Logger;

{ TCrossConnection }

constructor TCrossConnection.Create;
begin
end;

destructor TCrossConnection.Destroy;
begin
  Finalize;
  inherited;
end;

procedure TCrossConnection.Close;
begin
  if (FSocket <> INVALID_HANDLE_VALUE) then
    FOwner.CloseSocket(FSocket);
end;

procedure TCrossConnection.Disconnect;
begin
  if (FSocket <> INVALID_HANDLE_VALUE) then
    FOwner.Disconnect(FSocket);
end;

procedure TCrossConnection.Finalize;
begin
end;

procedure TCrossConnection.DirectSend(const ABuffer; ACount: Integer;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LConnection: ICrossConnection;
  LBuffer: Pointer;
begin
  LConnection := Self as ICrossConnection;

  if (FSocket = INVALID_HANDLE_VALUE) then
  begin
    if Assigned(ACallback) then
      ACallback(LConnection, False);
    Exit;
  end;

  LBuffer := @ABuffer;
  FOwner.Send(FSocket, ABuffer, ACount,
    procedure(ASocket: THandle; ASuccess: Boolean)
    begin
      if ASuccess then
        FOwner.TriggerSent(LConnection, LBuffer, ACount);

      if Assigned(ACallback) then
        ACallback(LConnection, ASuccess);
    end);
end;

procedure TCrossConnection.SendBuf(const ABuffer; ACount: Integer;
  const ACallback: TProc<ICrossConnection, Boolean>);
var
  LConnection: ICrossConnection;
  P: PByte;
  LSize: Integer;
  LSender: TProc<ICrossConnection, Boolean>;
begin
  LConnection := Self;
  P := @ABuffer;
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

      if (LSize > SND_BUF_SIZE) then
      begin
        Inc(P, SND_BUF_SIZE);
        Dec(LSize, SND_BUF_SIZE);
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

      TCrossConnection(AConnection).DirectSend(LData^, LCount, LSender);
    end;

  LSender(LConnection, True);
end;

procedure TCrossConnection.SendBytes(const ABytes: TBytes; AOffset,
  ACount: Integer; const ACallback: TProc<ICrossConnection, Boolean>);
var
  LBytes: TBytes;
begin
  // 增加引用计数
  // 由于 SendBuf 的 ABuffer 参数是直接传递的内存地址
  // 所以并不会增加 ABytes 的引用计数, 这里为了保证发送过程中数据的有效性
  // 需要定义一个局部变量用来引用 ABytes, 以维持其引用计数
  LBytes := ABytes;
  SendBuf(LBytes[AOffset], ACount,
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      // 减少引用计数
      LBytes := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossConnection.SendBytes(const ABytes: TBytes;
  const ACallback: TProc<ICrossConnection, Boolean>);
begin
  SendBytes(ABytes, 0, Length(ABytes), ACallback);
end;

procedure TCrossConnection.SendStream(const AStream: TStream;
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

      TCrossConnection(AConnection).DirectSend(LData^, LCount, LSender);
    end;

  LSender(LConnection, True);
end;

function TCrossConnection.GetConnectType: TConnectType;
begin
  case FConnectType of
    CT_ACCEPT: Exit(ctAccept);
    CT_CONNECT: Exit(ctConnect);
  else
    Exit(ctUnknown);
  end;
end;

function TCrossConnection.GetLocalAddr: string;
begin
  Result := FLocalAddr;
end;

function TCrossConnection.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TCrossConnection.GetOwner: TCustomCrossSocket;
begin
  Result := FOwner;
end;

function TCrossConnection.GetPeerAddr: string;
begin
  Result := FPeerAddr;
end;

function TCrossConnection.GetPeerPort: Word;
begin
  Result := FPeerPort;
end;

function TCrossConnection.GetSocket: THandle;
begin
  Result := FSocket;
end;

procedure TCrossConnection.Initialize;
begin
end;

{ TCustomCrossSocket }

constructor TCustomCrossSocket.Create(AIoThreads: Integer);
begin
  inherited Create(AIoThreads);

  FConnections := TDictionary<THandle, ICrossConnection>.Create;
  FConnectionsLocker := TMultiReadExclusiveWriteSynchronizer.Create;
  FListenSockets := TDictionary<THandle, Byte>.Create;
  FListenSocketsLocker := TMultiReadExclusiveWriteSynchronizer.Create;
end;

destructor TCustomCrossSocket.Destroy;
begin
  FConnectionsLocker.BeginWrite;
  FConnections.Clear;
  FreeAndNil(FConnections);
  FConnectionsLocker.EndWrite;
  FreeAndNil(FConnectionsLocker);

  FListenSocketsLocker.BeginWrite;
  FListenSockets.Clear;
  FreeAndNil(FListenSockets);
  FListenSocketsLocker.EndWrite;
  FreeAndNil(FListenSocketsLocker);

  inherited Destroy;
end;

function TCustomCrossSocket.GetConnection(
  const ASocket: THandle): ICrossConnection;
begin
  FConnections.TryGetValue(ASocket, Result);
end;

function TCustomCrossSocket.GetConnectionClass: TCrossConnectionClass;
begin
  Result := TCrossConnection;
  if Assigned(FOnGetConnectionClass) then
    FOnGetConnectionClass(Self, Result);
end;

procedure TCustomCrossSocket.CloseAllConnections;
var
  LConnection: ICrossConnection;
begin
  FConnectionsLocker.BeginRead;
  try
    for LConnection in FConnections.Values.ToArray do
      LConnection.Close;
  finally
    FConnectionsLocker.EndRead;
  end;
end;

procedure TCustomCrossSocket.CloseAllListens;
var
  LSocket: THandle;
begin
  FListenSocketsLocker.BeginRead;
  try
    for LSocket in FListenSockets.Keys.ToArray do
      StopListen(LSocket);
  finally
    FListenSocketsLocker.EndRead;
  end;
end;

procedure TCustomCrossSocket.CloseAll;
begin
  CloseAllConnections;
  CloseAllListens;
end;

procedure TCustomCrossSocket.DisconnectAll;
var
  LConnection: ICrossConnection;
begin
  FConnectionsLocker.BeginRead;
  try
    for LConnection in FConnections.Values.ToArray do
      LConnection.Disconnect;
  finally
    FConnectionsLocker.EndRead;
  end;
end;

procedure TCustomCrossSocket.TriggerListened(ASocket: THandle);
begin
  FListenSocketsLocker.BeginWrite;
  try
    FListenSockets.AddOrSetValue(ASocket, 1);
    Inc(FListensCount);
  finally
    FListenSocketsLocker.EndWrite;
  end;

  if Assigned(FOnListened) then
    FOnListened(Self, ASocket);
end;

procedure TCustomCrossSocket.TriggerListenEnd(ASocket: THandle);
begin
  if Assigned(FOnListenEnd) then
    FOnListenEnd(Self, ASocket);

  FListenSocketsLocker.BeginWrite;
  try
    FListenSockets.Remove(ASocket);
    Dec(FListensCount);
  finally
    FListenSocketsLocker.EndWrite;
  end;
end;

procedure TCustomCrossSocket.TriggerConnected(ASocket: THandle;
  AConnectType: Integer);
var
  LConnObj: TCrossConnection;
  LConnection: ICrossConnection;
  LAddr: TRawSockAddrIn;
begin
  inherited TriggerConnected(ASocket, AConnectType);

  FConnectionsLocker.BeginWrite;
  try
    if Assigned(FConnections) then
    begin
      LConnObj := GetConnectionClass.Create;
      LConnection := LConnObj;
      LConnObj.FOwner := Self;
      LConnObj.FSocket := ASocket;
      LConnObj.FConnectType := AConnectType;
      FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
      LAddr.AddrLen := SizeOf(LAddr.Addr6);
      if (TSocketAPI.GetPeerName(ASocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
        TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen,
          LConnObj.FPeerAddr, LConnObj.FPeerPort);
      if (TSocketAPI.GetSockName(ASocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
        TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen,
          LConnObj.FLocalAddr, LConnObj.FLocalPort);
      LConnObj.Initialize;

      FConnections.AddOrSetValue(ASocket, LConnection);
    end else
      LConnection := nil;
  finally
    FConnectionsLocker.EndWrite;
  end;

  if (LConnection <> nil) then
  begin
    AtomicIncrement(FConnectionsCount);
    TriggerConnected(LConnection);
  end;
end;

procedure TCustomCrossSocket.TriggerConnectFailed(ASocket: THandle);
begin
  LogicConnectFailed(ASocket);

  if Assigned(FOnConnectFailed) then
    FOnConnectFailed(Self, ASocket);
end;

procedure TCustomCrossSocket.TriggerDisconnected(ASocket: THandle);
var
  LConnection: ICrossConnection;
begin
  FConnectionsLocker.BeginWrite;
  try
    if Assigned(FConnections) and FConnections.TryGetValue(ASocket, LConnection) then
      FConnections.Remove(ASocket)
    else
      LConnection := nil;
  finally
    FConnectionsLocker.EndWrite;
  end;

  if (LConnection <> nil) then
  begin
    AtomicExchange((LConnection as TCrossConnection).FSocket, INVALID_HANDLE_VALUE);
    TriggerDisconnected(LConnection);
    AtomicDecrement(FConnectionsCount);
  end;

  inherited TriggerDisconnected(ASocket);
end;

procedure TCustomCrossSocket.TriggerReceived(ASocket: THandle; ABuf: Pointer;
  ALen: Integer);
var
  LConnection: ICrossConnection;
begin
  FConnectionsLocker.BeginRead;
  try
    if Assigned(FConnections) then
      FConnections.TryGetValue(ASocket, LConnection)
    else
      LConnection := nil;
  finally
    FConnectionsLocker.EndRead;
  end;

  if (LConnection <> nil) then
    TriggerReceived(LConnection, ABuf, ALen);
end;

procedure TCustomCrossSocket.TriggerConnected(AConnection: ICrossConnection);
begin
  LogicConnected(AConnection);

  if Assigned(FOnConnected) then
    FOnConnected(Self, AConnection);
end;

procedure TCustomCrossSocket.TriggerDisconnected(AConnection: ICrossConnection);
begin
  LogicDisconnected(AConnection);

  if Assigned(FOnDisconnected) then
    FOnDisconnected(Self, AConnection);
end;

procedure TCustomCrossSocket.TriggerReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
  LogicReceived(AConnection, ABuf, ALen);

  if Assigned(FOnReceived) then
    FOnReceived(Self, AConnection, ABuf, ALen);
end;

procedure TCustomCrossSocket.TriggerSent(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
  LogicSent(AConnection, ABuf, ALen);

  if Assigned(FOnSent) then
    FOnSent(Self, AConnection, ABuf, ALen);
end;

function TCustomCrossSocket.IsListen(ASocket: THandle): Boolean;
begin
  FListenSocketsLocker.BeginRead;
  try
    Result := FListenSockets.ContainsKey(ASocket);
  finally
    FListenSocketsLocker.EndRead;
  end;
end;

function TCustomCrossSocket.LockConnections: TDictionary<THandle, ICrossConnection>;
begin
  FConnectionsLocker.BeginRead;
  Result := FConnections;
end;

procedure TCustomCrossSocket.LogicConnected(AConnection: ICrossConnection);
begin
end;

procedure TCustomCrossSocket.LogicConnectFailed(ASocket: THandle);
begin

end;

procedure TCustomCrossSocket.LogicDisconnected(AConnection: ICrossConnection);
begin

end;

procedure TCustomCrossSocket.LogicReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin

end;

procedure TCustomCrossSocket.LogicSent(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin

end;

procedure TCustomCrossSocket.UnlockConnections;
begin
  FConnectionsLocker.EndRead;
end;

{ TCrossSocket }

procedure TCrossSocket.AfterConstruction;
begin
  inherited AfterConstruction;
  StartLoop;
end;

procedure TCrossSocket.CloseAll;
begin
  inherited CloseAll;
end;

procedure TCrossSocket.CloseAllConnections;
begin
  inherited CloseAllConnections;
end;

procedure TCrossSocket.CloseAllListens;
begin
  inherited CloseAllListens;
end;

function TCrossSocket.Connect(const AHost: string; APort: Word;
  const ACallback: TProc<THandle, Boolean>): Integer;
begin
  Result := inherited Connect(AHost, APort, ACallback);
end;

procedure TCrossSocket.DisconnectAll;
begin
  inherited DisconnectAll;
end;

function TCrossSocket.Listen(const AHost: string; APort: Word;
  const ACallback: TProc<THandle, Boolean>): Integer;
begin
  Result := inherited Listen(AHost, APort, ACallback);
end;

procedure TCrossSocket.StartLoop;
begin
  inherited StartLoop;
end;

procedure TCrossSocket.StopLoop;
begin
  inherited StopLoop;
end;

end.

