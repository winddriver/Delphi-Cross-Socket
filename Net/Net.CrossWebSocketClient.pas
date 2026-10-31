{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossWebSocketClient;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,

  Net.SocketAPI,
  Net.CrossProxy,
  Net.CrossSocket.Base,
  Net.CrossHttpClient,
  Net.CrossHttpUtils,
  Net.CrossWebSocketParser,
  Net.CrossWebSocketSender,

  Utils.StrUtils,
  Utils.SyncObjs,
  Utils.Utils;

type
  {$REGION 'Documentation'}
  /// <summary>
  ///   发送数据回调
  /// </summary>
  {$ENDREGION}
  TWsClientCallback = reference to procedure(const ASuccess: Boolean);

  {$REGION 'Documentation'}
  /// <summary>
  ///   提供块数据的匿名函数
  /// </summary>
  {$ENDREGION}
  TWsClientChunkDataFunc = reference to function(const AData: PPointer; const ACount: PNativeInt): Boolean;

  {$REGION 'Documentation'}
  /// <summary>
  ///   收到消息数据事件
  /// </summary>
  {$ENDREGION}
  TWsClientOnMessage = TWsOnMessage;

  TWsClientOnOpenRequest = reference to procedure(const ARequest: ICrossHttpClientRequest);

  TWsClientOnOpenResponse = reference to procedure(const AResponse: ICrossHttpClientResponse);

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 已连接事件
  /// </summary>
  {$ENDREGION}
  TWsClientOnOpen = reference to procedure;
  {$REGION 'Documentation'}

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 已关闭事件
  /// </summary>
  {$ENDREGION}
  TWsClientOnClose = TWsClientOnOpen;

  {$REGION 'Documentation'}
  /// <summary>
  ///   收到 "Ping" 事件
  /// </summary>
  {$ENDREGION}
  TWsClientOnPing = TWsClientOnOpen;

  {$REGION 'Documentation'}
  /// <summary>
  ///   收到 "Pong" 事件
  /// </summary>
  {$ENDREGION}
  TWsClientOnPong = TWsClientOnOpen;

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 状态
  /// </summary>
  {$ENDREGION}
  TWsStatus = (
    {$REGION 'Documentation'}
    /// <summary>
    ///   未知
    /// </summary>
    {$ENDREGION}
    wsUnknown,

    {$REGION 'Documentation'}
    /// <summary>
    ///   正在连接
    /// </summary>
    {$ENDREGION}
    wsConnecting,

    {$REGION 'Documentation'}
    /// <summary>
    ///   已连接
    /// </summary>
    {$ENDREGION}
    wsConnected,

    {$REGION 'Documentation'}
    /// <summary>
    ///   已断开连接
    /// </summary>
    {$ENDREGION}
    wsDisconnected,

    {$REGION 'Documentation'}
    /// <summary>
    ///   已关闭
    /// </summary>
    {$ENDREGION}
    wsShutdown);

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 连接
  /// </summary>
  {$ENDREGION}
  ICrossWebSocketClientConnection = interface(ICrossHttpClientConnection)
  ['{E8C6864A-640C-47CE-B974-60CC81F75484}']
    procedure WsClose;
    procedure WsPing;

    procedure WsSend(const AData; const ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TBytes; const AOffset, ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TBytes; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: string; const ACallback: TWsClientCallback = nil); overload;

    procedure WsSend(const AData: TWsClientChunkDataFunc; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TStream; const AOffset, ACount: Int64; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TStream; const ACallback: TWsClientCallback = nil); overload;
  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 对象
  /// </summary>
  {$ENDREGION}
  ICrossWebSocket = interface
  ['{9764B709-3E5B-4B13-BD1D-526AC2BBEC17}']
    function GetStatus: TWsStatus;
    function GetUrl: string;

    {$REGION 'Documentation'}
    /// <summary>
    ///   打开 WebSocket
    /// </summary>
    {$ENDREGION}
    function Open: ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   关闭 WebSocket
    /// </summary>
    {$ENDREGION}
    function Close: ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送 Ping 命令
    /// </summary>
    {$ENDREGION}
    procedure Ping;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送无类型数据
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData; const ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送字节数组数据
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData: TBytes; const AOffset, ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送字节数组数据
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData: TBytes; const ACallback: TWsClientCallback = nil); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送字符串数据(会自动按UTF-8编码)
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData: string; const ACallback: TWsClientCallback = nil); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送分块数据
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData: TWsClientChunkDataFunc; const ACallback: TWsClientCallback = nil); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送流数据
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData: TStream; const AOffset, ACount: Int64; const ACallback: TWsClientCallback = nil); overload;

    {$REGION 'Documentation'}
    /// <summary>
    ///   发送流数据
    /// </summary>
    {$ENDREGION}
    procedure Send(const AData: TStream; const ACallback: TWsClientCallback = nil); overload;

    function OnOpenRequest(const ACallback: TWsClientOnOpenRequest): ICrossWebSocket;

    function OnOpenResponse(const ACallback: TWsClientOnOpenResponse): ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   注册打开 WebSocket 事件
    /// </summary>
    {$ENDREGION}
    function OnOpen(const ACallback: TWsClientOnOpen): ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   注册收到消息事件
    /// </summary>
    {$ENDREGION}
    function OnMessage(const ACallback: TWsOnMessage): ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   注册关闭 WebSocket 事件
    /// </summary>
    {$ENDREGION}
    function OnClose(const ACallback: TWsClientOnClose): ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   注册收到 Ping 命令事件
    /// </summary>
    {$ENDREGION}
    function OnPing(const ACallback: TWsClientOnPing): ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   注册收到 Pong 命令事件
    /// </summary>
    {$ENDREGION}
    function OnPong(const ACallback: TWsClientOnPong): ICrossWebSocket;

    {$REGION 'Documentation'}
    /// <summary>
    ///   WebSocket 状态
    /// </summary>
    {$ENDREGION}
    property Status: TWsStatus read GetStatus;

    {$REGION 'Documentation'}
    /// <summary>
    ///   服务器地址
    /// </summary>
    {$ENDREGION}
    property Url: string read GetUrl;

  end;

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 管理器
  /// </summary>
  /// <remarks>
  ///   WebSocket 对象需要通过它来创建
  /// </remarks>
  {$ENDREGION}
  ICrossWebSocketMgr = interface(ICrossHttpClient)
  ['{2B16E274-B59A-4FA2-AC20-AF48F69CD15C}']
    {$REGION 'Documentation'}
    /// <summary>
    ///   创建 WebSocket 对象
    /// </summary>
    {$ENDREGION}
    function CreateWebSocket(const AUrl: string): ICrossWebSocket;
  end;

  TCrossWebSocket = class;
  TCrossWebSocketMgr = class;

  TCrossWebSocketClientConnection = class(TCrossHttpClientConnection, ICrossWebSocketClientConnection)
  private
    FIsWebSocket: Boolean;
    FWebSocket: TCrossWebSocket;

    FWsParser: TCrossWebSocketParser;
    FWsSender: TCrossWebSocketSender;
    FProtocolLock: ILock;
    FProtocolOnMessage: TWsClientOnMessage;
    FProtocolOnClose: TWsClientOnClose;
    FHandshakeLimit, FHandshakeCount: Integer;
    FHandshakeReady, FHandshakeDraining: Boolean;
    FHandshakeData: TBytes;
    FHandshakeContext: IInterface;

    procedure _WebSocketRecv(var ABuf: Pointer; var ALen: Integer);
    procedure _BufferHandshake(var ABuf: Pointer; var ALen: Integer);
    procedure _ClearHandshake;
    function _GetProtocolMessage: TWsClientOnMessage;
    procedure _CloseProtocol;

    procedure _RespondPong(const AData: TBytes);
    procedure _RespondClose(const AData: TBytes);
    procedure _StopParserIfDisconnected;

    {$region '内部发送方法'}
    procedure _WsSend(AOpCode: Byte; AFin: Boolean; AData: Pointer; ACount: NativeInt;
      ACallback: TWsClientCallback = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes; AOffset, ACount: NativeInt;
      ACallback: TWsClientCallback = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes;
      ACallback: TWsClientCallback = nil); overload;
    {$endregion}
  protected
    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer); override;
    procedure InternalClose; override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

    // 内部协议按物理连接绑定；断线时解除回调并终止对应会话。
    procedure SetProtocolCallbacks(const AOnMessage: TWsClientOnMessage;
      const AOnClose: TWsClientOnClose);
    procedure SetHandshakeBufferLimit(const AValue: Integer);
    procedure SetHandshakeContext(const AContext: IInterface);
    function GetHandshakeContext: IInterface;
    function HandshakeReady: Boolean;
    procedure CompleteHandshake;

    // 开始接收前配置。接口不变，具体连接类增加可选资源策略。
    procedure SetWebSocketLimits(const AMaxMessageSize: UInt64;
      const AMessageTimeoutMs, ACloseTimeoutMs: Cardinal);
    // 发送器必须空闲；既有连接接口布局不变。
    procedure SetWebSocketSendQueueLimits(const ALimits: TWsSendQueueLimits);
    // 由调用方定期调用；内部与接收解析互斥，不创建后台线程。
    procedure CheckWebSocketTimeouts;

    procedure WsClose;
    procedure WsPing;

    procedure WsSend(const AData: Pointer; const ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData; const ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TBytes; const AOffset, ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TBytes; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: string; const ACallback: TWsClientCallback = nil); overload;

    procedure WsSend(const AData: TWsClientChunkDataFunc; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TStream; const AOffset, ACount: Int64; const ACallback: TWsClientCallback = nil); overload;
    procedure WsSend(const AData: TStream; const ACallback: TWsClientCallback = nil); overload;
  end;

  TCrossWebSocketClient = class(TCrossHttpClientSocket)
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;
  end;

  {
    WebSocket连接建立过程

    1. 首先建立网络连接

    2. 然后由客户端向服务端发送提升连接为WebSocket的请求, 格式如下:

    GET /websocket-endpoint HTTP/1.1
    Host: example.com
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
    Sec-WebSocket-Version: 13

    /websocket-endpoint 替换成实际的路径
    Sec-WebSocket-Key 是一个随机base64字符串

    3. 服务端收到客户端的提升请求后, 会响应确认的数据包

    HTTP/1.1 101 Switching Protocols
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=

    客户端收到响应后需要对 Sec-WebSocket-Accept 进行校验
    Sec-WebSocket-Accept 应等于 base64(sha1(Sec-WebSocket-Key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))

    如果校验通过, 则 websocket 连接建立完成
  }
  TCrossWebSocket = class(TInterfacedObject, ICrossWebSocket)
  private
    FUrl: string;
    FMgr: TCrossWebSocketMgr;
    FConnection: TCrossWebSocketClientConnection;
    FOpeningConnection: ICrossWebSocketClientConnection;
    FOpenSerial: UInt64;
    FStatus: TWsStatus;
    FLock: ILock;

    FOnOpenRequestEvents: TList<TWsClientOnOpenRequest>;
    FOnOpenResponseEvents: TList<TWsClientOnOpenResponse>;
    FOnOpenEvents: TList<TWsClientOnOpen>;
    FOnMessageEvents: TList<TWsClientOnMessage>;
    FOnCloseEvents: TList<TWsClientOnClose>;
    FOnPingEvents: TList<TWsClientOnPing>;
    FOnPongEvents: TList<TWsClientOnPong>;
  protected
    procedure _Lock; inline;
    procedure _Unlock; inline;

    procedure _OnOpenRequest(const ARequest: ICrossHttpClientRequest);
    procedure _OnOpenResponse(const AResponse: ICrossHttpClientResponse);
    procedure _OnOpen;
    procedure _OnMessage(const AMessageType: TWsMessageType; const AMessageData: TBytes;
      const AProtocolOnMessage: TWsClientOnMessage = nil);
    procedure _OnClose(const AConnection: ICrossWebSocketClientConnection = nil);
    function _IsCurrentOpen(const ASerial: UInt64): Boolean;

    procedure _OnPing;
    procedure _OnPong;
  protected
    function GetStatus: TWsStatus;
    function GetUrl: string;
    function GetConnection: ICrossWebSocketClientConnection;
    procedure PrepareOpenRequest(const ARequest: ICrossHttpClientRequest); virtual;
    procedure ValidateOpenRequest(const ARequest: ICrossHttpClientRequest); virtual;
    function ValidateOpenResponse(const AResponse: ICrossHttpClientResponse): Boolean; virtual;
    procedure DoOnOpen(const AConnection: ICrossWebSocketClientConnection); virtual;
  public
    constructor Create(const AMgr: TCrossWebSocketMgr; const AUrl: string); overload; virtual;
    constructor Create(const AUrl: string); overload;
    destructor Destroy; override;

    function Open: ICrossWebSocket;
    function Close: ICrossWebSocket;

    // 撤销本外观的业务开关事件；已取得的回调快照继续保活至退出。
    // 握手、认证及消息事件不受影响。
    procedure ClearLifecycleEvents;
    {$IFDEF CROSS_WS_PRIVATE_SELFTEST}
    procedure TestTriggerCloseEvent;
    {$ENDIF}

    procedure Ping;

    procedure Send(const AData: Pointer; const ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure Send(const AData; const ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure Send(const AData: TBytes; const AOffset, ACount: NativeInt; const ACallback: TWsClientCallback = nil); overload;
    procedure Send(const AData: TBytes; const ACallback: TWsClientCallback = nil); overload;
    procedure Send(const AData: string; const ACallback: TWsClientCallback = nil); overload;

    procedure Send(const AData: TWsClientChunkDataFunc; const ACallback: TWsClientCallback = nil); overload;
    procedure Send(const AData: TStream; const AOffset, ACount: Int64; const ACallback: TWsClientCallback = nil); overload;
    procedure Send(const AData: TStream; const ACallback: TWsClientCallback = nil); overload;

    function OnOpenRequest(const ACallback: TWsClientOnOpenRequest): ICrossWebSocket;
    function OnOpenResponse(const ACallback: TWsClientOnOpenResponse): ICrossWebSocket;
    function OnOpen(const ACallback: TWsClientOnOpen): ICrossWebSocket;
    function OnMessage(const ACallback: TWsClientOnMessage): ICrossWebSocket;
    function OnClose(const ACallback: TWsClientOnClose): ICrossWebSocket;

    function OnPing(const ACallback: TWsClientOnPing): ICrossWebSocket;
    function OnPong(const ACallback: TWsClientOnPong): ICrossWebSocket;

    property Status: TWsStatus read GetStatus;
    property Url: string read GetUrl;
  end;

  TCrossWebSocketMgr = class(TCrossHttpClient, ICrossWebSocketMgr)
  private
    FIoThreads: Integer;
    FWsCli, FWssCli: ICrossHttpClientSocket;
    FWsCliArr: TArray<ICrossHttpClientSocket>;

    class var FDefault: ICrossWebSocketMgr;
    class function GetDefault: ICrossWebSocketMgr; static;
  protected
    function CreateHttpCli(const AProtocol: string): ICrossHttpClientSocket; override;
    procedure SetProxySettings(const AValue: TCrossProxySettings); override;
  public
    constructor Create(const AIoThreads: Integer = 2); reintroduce;
    destructor Destroy; override;

    procedure CancelAll; override;
    function CreateWebSocket(const AUrl: string): ICrossWebSocket;

    class property &Default: ICrossWebSocketMgr read GetDefault;
  end;

implementation

{ TCrossWebSocketClientConnection }

constructor TCrossWebSocketClientConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
  FProtocolLock := TLock.Create;
  // 通用 WS 不新增限额；私有适配器在发起握手前设置有界上限。
  FHandshakeLimit := 0;
  FWsSender := TCrossWebSocketSender.Create(Self, False);
  FWsParser := TCrossWebSocketParser.Create(
    procedure(const AOpCode: Byte; const AData: TBytes)
    begin
      try
        case AOpCode of
          WS_OP_CLOSE: _RespondClose(AData);
          WS_OP_PING:
            begin
              if FWebSocket <> nil then FWebSocket._OnPing;
              if not (ConnectStatus in [csDisconnected, csClosed]) then
                _RespondPong(AData);
            end;
          WS_OP_PONG:
            if FWebSocket <> nil then FWebSocket._OnPong;
        end;
      finally
        _StopParserIfDisconnected;
      end;
    end,
    procedure(const AType: TWsMessageType; const AData: TBytes)
    var
      LProtocolOnMessage: TWsClientOnMessage;
    begin
      try
        LProtocolOnMessage := _GetProtocolMessage();
        if FWebSocket <> nil then
          FWebSocket._OnMessage(AType, AData, LProtocolOnMessage)
        else
        if Assigned(LProtocolOnMessage) then
          LProtocolOnMessage(AType, AData);
      finally
        _StopParserIfDisconnected;
      end;
    end,
    procedure
    begin
      FWsSender.FailProtocol(FWsParser.ErrorCode);
    end);
  FWsParser.Role := wprClient;
  FWsParser.AllowedRsvBits := 0;
  FWsParser.CheckTextUtf8 := True;
end;

destructor TCrossWebSocketClientConnection.Destroy;
begin
  _CloseProtocol;
  if (FWebSocket <> nil) then
  begin
    FWebSocket.FStatus := wsShutdown;
    FWebSocket.FConnection := nil;
    FWebSocket := nil;
  end;

  FreeAndNil(FWsParser);
  FreeAndNil(FWsSender);

  inherited;
end;

procedure TCrossWebSocketClientConnection.SetProtocolCallbacks(
  const AOnMessage: TWsClientOnMessage; const AOnClose: TWsClientOnClose);
var
  LClosed: Boolean;
begin
  FProtocolLock.Enter;
  try
    LClosed := ConnectStatus in [csDisconnected, csClosed];
    if not LClosed then
    begin
      if Assigned(FProtocolOnMessage) or Assigned(FProtocolOnClose) then
        raise Exception.Create('此连接已经绑定内部协议');
      FProtocolOnMessage := AOnMessage;
      FProtocolOnClose := AOnClose;
    end;
  finally
    FProtocolLock.Leave;
  end;
  if LClosed and Assigned(AOnClose) then
    AOnClose();
end;

function TCrossWebSocketClientConnection._GetProtocolMessage: TWsClientOnMessage;
begin
  FProtocolLock.Enter;
  try
    Result := FProtocolOnMessage;
  finally
    FProtocolLock.Leave;
  end;
end;

procedure TCrossWebSocketClientConnection.SetHandshakeBufferLimit(const AValue: Integer);
begin
  if AValue < 0 then raise Exception.Create('握手暂存上限不能为负数');
  _LockRecv;
  try
    if (AValue > 0) and (FHandshakeCount > AValue) then raise Exception.Create('握手暂存已超过新上限');
    FHandshakeLimit := AValue;
    if (AValue > 0) and (Length(FHandshakeData) > AValue) then SetLength(FHandshakeData, AValue);
  finally _UnlockRecv; end;
end;

procedure TCrossWebSocketClientConnection.SetHandshakeContext(const AContext: IInterface);
var Old: IInterface;
begin
  FProtocolLock.Enter;
  try
    Old := FHandshakeContext;
    FHandshakeContext := AContext;
  finally FProtocolLock.Leave; end;
  Old := nil;
end;

function TCrossWebSocketClientConnection.GetHandshakeContext: IInterface;
begin
  FProtocolLock.Enter;
  try Result := FHandshakeContext; finally FProtocolLock.Leave; end;
end;

function TCrossWebSocketClientConnection.HandshakeReady: Boolean;
begin
  _LockRecv;
  try Result := FHandshakeReady and not IsClosed; finally _UnlockRecv; end;
end;

procedure TCrossWebSocketClientConnection._ClearHandshake;
begin
  _LockRecv;
  try
    FHandshakeReady := False;
    FHandshakeData := nil;
    FHandshakeCount := 0;
  finally _UnlockRecv; end;
end;

procedure TCrossWebSocketClientConnection._BufferHandshake(var ABuf: Pointer; var ALen: Integer);
var N, Need, Capacity, MaxCapacity: Integer;
begin
  N := FHandshakeCount;
  MaxCapacity := FHandshakeLimit;
  if MaxCapacity = 0 then MaxCapacity := High(Integer);
  if ALen > MaxCapacity - N then
  begin
    ABuf := PByte(ABuf) + ALen;
    ALen := 0;
    _ClearHandshake;
    Close;
    Exit;
  end;
  Need := N + ALen;
  Capacity := Length(FHandshakeData);
  if Capacity < Need then
  begin
    if Capacity = 0 then
      if MaxCapacity < 4096 then Capacity := MaxCapacity else Capacity := 4096;
    while Capacity < Need do
      if Capacity > MaxCapacity div 2 then Capacity := MaxCapacity else Capacity := Capacity * 2;
    SetLength(FHandshakeData, Capacity);
  end;
  if ALen > 0 then Move(ABuf^, FHandshakeData[N], ALen);
  FHandshakeCount := Need;
  ABuf := PByte(ABuf) + ALen;
  ALen := 0;
end;

procedure TCrossWebSocketClientConnection.CompleteHandshake;
var Data: TBytes; P: Pointer; N: Integer;
begin
  _LockRecv;
  try
    if IsClosed or FWsSender.IsClosing then
    begin
      _ClearHandshake;
      Close;
      Exit;
    end;
    FHandshakeReady := True;
    FHandshakeDraining := True;
    try
      // 同线程重入接收也先排到暂存尾部，不能越过当前正在排空的数据。
      while (FHandshakeCount > 0) and not IsClosed do
      begin
        Data := FHandshakeData;
        FHandshakeData := nil;
        P := @Data[0];
        N := FHandshakeCount;
        FHandshakeCount := 0;
        while (N > 0) and not IsClosed do _WebSocketRecv(P, N);
      end;
      if IsClosed then
      begin FHandshakeData := nil; FHandshakeCount := 0; end;
    finally FHandshakeDraining := False; end;
  finally _UnlockRecv; end;
end;

procedure TCrossWebSocketClientConnection.InternalClose;
begin
  try _ClearHandshake; finally inherited; end;
end;

procedure TCrossWebSocketClientConnection._CloseProtocol;
var
  LOnMessage: TWsClientOnMessage;
  LOnClose: TWsClientOnClose;
  LContext: IInterface;
begin
  if FProtocolLock = nil then Exit;
  FProtocolLock.Enter;
  try
    // 局部引用让会话及其传输引用在锁外释放。
    LOnMessage := FProtocolOnMessage;
    LOnClose := FProtocolOnClose;
    FProtocolOnMessage := nil;
    FProtocolOnClose := nil;
    LContext := FHandshakeContext;
    FHandshakeContext := nil;
  finally
    FProtocolLock.Leave;
  end;
  _ClearHandshake;
  LContext := nil;
  if Assigned(LOnClose) then
    LOnClose();
end;

procedure TCrossWebSocketClientConnection.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
begin
  while (ALen > 0) do
  begin
    if IsClosed then
    begin
      ABuf := PByte(ABuf) + ALen;
      ALen := 0;
      Exit;
    end;
    if not FIsWebSocket then
    begin
      if RequestStatus = rsUpgraded then
      begin
        _BufferHandshake(ABuf, ALen);
        Exit;
      end;
      inherited ParseRecvData(ABuf, ALen);
    end;

    if (ALen > 0) and FIsWebSocket then
      if not FHandshakeReady or FHandshakeDraining then _BufferHandshake(ABuf, ALen)
      else _WebSocketRecv(ABuf, ALen);
  end;
end;

procedure TCrossWebSocketClientConnection.WsClose;
begin
  FWsSender.RequestClose;
end;

procedure TCrossWebSocketClientConnection.SetWebSocketSendQueueLimits(
  const ALimits: TWsSendQueueLimits);
begin
  FWsSender.SetQueueLimits(ALimits);
end;

procedure TCrossWebSocketClientConnection.WsPing;
begin
  _WsSend(WS_OP_PING, True, nil, 0);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: Pointer;
  const ACount: NativeInt; const ACallback: TWsClientCallback);
begin
  _WsSend(WS_OP_BINARY, True, AData, ACount, ACallback);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData;
  const ACount: NativeInt; const ACallback: TWsClientCallback);
begin
  _WsSend(WS_OP_BINARY, True, @AData, ACount, ACallback);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: TBytes;
  const AOffset, ACount: NativeInt; const ACallback: TWsClientCallback);
begin
  _WsSend(WS_OP_BINARY, True, AData, AOffset, ACount, ACallback);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: TBytes;
  const ACallback: TWsClientCallback);
begin
  WsSend(AData, 0, Length(AData), ACallback);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: TWsClientChunkDataFunc;
  const ACallback: TWsClientCallback);
begin
  if (FWebSocket = nil) or (ConnectStatus in [csDisconnected, csClosed]) then
  begin
    if Assigned(ACallback) then ACallback(False);
    Exit;
  end;
  FWsSender.SendChunks(
    function(const ABuffer: PPointer; const ACount: PNativeInt): Boolean
    begin
      Result := False;
      if Assigned(AData) then Result := AData(ABuffer, ACount);
    end,
    procedure(const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then ACallback(ASuccess);
    end);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: string;
  const ACallback: TWsClientCallback);
begin
  _WsSend(WS_OP_TEXT, True, TEncoding.UTF8.GetBytes(AData), ACallback);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: TStream;
  const AOffset, ACount: Int64; const ACallback: TWsClientCallback);
var
  LOffset, LCount: Int64;
begin
  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(AData.Size, LOffset, LCount);

  if (AData is TCustomMemoryStream) then
  begin
    WsSend((PByte(TCustomMemoryStream(AData).Memory) + LOffset)^, LCount, ACallback);
    Exit;
  end;

  AData.Position := LOffset;
  if (FWebSocket = nil) or (ConnectStatus in [csDisconnected, csClosed]) then
  begin
    if Assigned(ACallback) then ACallback(False);
    Exit;
  end;
  FWsSender.SendStream(AData, LCount,
    procedure(const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then ACallback(ASuccess);
    end);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: TStream;
  const ACallback: TWsClientCallback);
begin
  WsSend(AData, 0, 0, ACallback);
end;

procedure TCrossWebSocketClientConnection._RespondClose(const AData: TBytes);
begin
  FWsSender.ReceiveClose(AData);
end;

procedure TCrossWebSocketClientConnection._RespondPong(const AData: TBytes);
begin
  _WsSend(WS_OP_PONG, True, AData);
end;

procedure TCrossWebSocketClientConnection._StopParserIfDisconnected;
begin
  if (FWsParser <> nil) and (ConnectStatus in [csDisconnected, csClosed]) then
    FWsParser.Stop;
end;

procedure TCrossWebSocketClientConnection.SetWebSocketLimits(const AMaxMessageSize: UInt64;
  const AMessageTimeoutMs, ACloseTimeoutMs: Cardinal);
begin
  _LockRecv;
  try
    FWsParser.MaxMessageSize := AMaxMessageSize;
    FWsParser.MessageTimeoutMs := AMessageTimeoutMs;
    FWsSender.CloseTimeoutMs := ACloseTimeoutMs;
  finally
    _UnlockRecv;
  end;
end;

procedure TCrossWebSocketClientConnection.CheckWebSocketTimeouts;
var
  LConnection: ICrossConnection;
begin
  LConnection := Self;
  _LockRecv;
  try
    _StopParserIfDisconnected;
    try
      FWsParser.CheckTimeout;
    finally
      FWsSender.CheckTimeout;
      _StopParserIfDisconnected;
    end;
  finally
    _UnlockRecv;
  end;
end;

procedure TCrossWebSocketClientConnection._WebSocketRecv(var ABuf: Pointer; var ALen: Integer);
begin
  _StopParserIfDisconnected;
  FWsParser.Decode(ABuf, ALen);
end;

procedure TCrossWebSocketClientConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  AData: Pointer; ACount: NativeInt; ACallback: TWsClientCallback);
begin
  if (FWebSocket = nil) or (ConnectStatus in [csDisconnected, csClosed]) then
  begin
    if Assigned(ACallback) then ACallback(False);
    Exit;
  end;
  FWsSender.Send(AOpCode, AFin, AData, ACount,
    procedure(const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then ACallback(ASuccess);
    end);
end;

procedure TCrossWebSocketClientConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  const AData: TBytes; AOffset, ACount: NativeInt; ACallback: TWsClientCallback);
var
  LData: TBytes;
  P: PByte;
  LOffset, LCount: NativeInt;
begin
  LData := AData;

  if (LData <> nil) and (ACount > 0) then
  begin
    LOffset := AOffset;
    LCount := ACount;
    TCrossHttpUtils.AdjustOffsetCount(Length(LData), LOffset, LCount);

    P := PByte(@LData[0]) + LOffset;
  end else
  begin
    P := nil;
    LCount := 0;
  end;

  _WsSend(AOpCode, AFin, P, LCount,
    procedure(const ASuccess: Boolean)
    begin
      LData := nil;
      if Assigned(ACallback) then
        ACallback(ASuccess);
    end);
end;

procedure TCrossWebSocketClientConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  const AData: TBytes; ACallback: TWsClientCallback);
begin
  _WsSend(AOpCode, AFin, AData, 0, Length(AData), ACallback);
end;

{ TCrossWebSocketClient }

function TCrossWebSocketClient.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossWebSocketClientConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

procedure TCrossWebSocketClient.LogicDisconnected(
  const AConnection: ICrossConnection);
var
  LConnectionObj: TCrossWebSocketClientConnection;
begin
  LConnectionObj := AConnection as TCrossWebSocketClientConnection;
  try
    if (LConnectionObj.FWebSocket <> nil) then
      LConnectionObj.FWebSocket._OnClose(AConnection as ICrossWebSocketClientConnection);
  finally
    try
      // 外观可能已销毁，仍须终止该物理连接自己的协议会话。
      LConnectionObj._CloseProtocol;
    finally
      inherited LogicDisconnected(AConnection);
    end;
  end;
end;

{ TCrossWebSocket }

function TCrossWebSocket.Close: ICrossWebSocket;
var
  LConnection: ICrossWebSocketClientConnection;
  LStatus: TWsStatus;
begin
  Result := Self;
  _Lock;
  try
    LStatus := FStatus;
    if (LStatus = wsConnecting) and (FOpeningConnection <> nil) then LConnection := FOpeningConnection
    else LConnection := FConnection;
  finally _Unlock; end;
  if LStatus = wsConnecting then
  begin
    try _OnClose;
    finally if LConnection <> nil then LConnection.Close; end;
  end else if (LStatus = wsConnected) and (LConnection <> nil) then
    LConnection.WsClose;
end;

procedure TCrossWebSocket.ClearLifecycleEvents;
var
  LOpenEvents: TArray<TWsClientOnOpen>;
  LCloseEvents: TArray<TWsClientOnClose>;
begin
  _Lock;
  try
    LOpenEvents := FOnOpenEvents.ToArray;
    LCloseEvents := FOnCloseEvents.ToArray;
    FOnOpenEvents.Clear;
    FOnCloseEvents.Clear;
  finally
    _Unlock;
  end;
  // 用户闭包的最后释放不能发生在内部事件锁中。
  LOpenEvents := nil;
  LCloseEvents := nil;
end;

{$IFDEF CROSS_WS_PRIVATE_SELFTEST}
procedure TCrossWebSocket.TestTriggerCloseEvent;
begin
  _Lock;
  try if FStatus = wsDisconnected then FStatus := wsConnecting;
  finally _Unlock; end;
  _OnClose;
end;
{$ENDIF}

constructor TCrossWebSocket.Create(const AMgr: TCrossWebSocketMgr;
  const AUrl: string);
begin
  FMgr := AMgr;
  FUrl := AUrl;

  FLock := TLock.Create;

  FOnOpenRequestEvents := TList<TWsClientOnOpenRequest>.Create;
  FOnOpenResponseEvents := TList<TWsClientOnOpenResponse>.Create;
  FOnOpenEvents := TList<TWsClientOnOpen>.Create;
  FOnMessageEvents := TList<TWsOnMessage>.Create;
  FOnCloseEvents := TList<TWsClientOnClose>.Create;
  FOnPingEvents := TList<TWsClientOnPing>.Create;
  FOnPongEvents := TList<TWsClientOnPong>.Create;
end;

constructor TCrossWebSocket.Create(const AUrl: string);
begin
  Create(TCrossWebSocketMgr.Default as TCrossWebSocketMgr, AUrl);
end;

destructor TCrossWebSocket.Destroy;
begin
  FStatus := wsShutdown;

  if (FLock <> nil) then
  begin
    _Lock;
    try
      if (FConnection <> nil) then
      begin
        FConnection.FWebSocket := nil;
        FConnection.Close;
        FConnection := nil;
      end;
      if FOpeningConnection <> nil then
      begin
        FOpeningConnection.Close;
        FOpeningConnection := nil;
      end;

      FreeAndNil(FOnOpenRequestEvents);
      FreeAndNil(FOnOpenResponseEvents);
      FreeAndNil(FOnOpenEvents);
      FreeAndNil(FOnMessageEvents);
      FreeAndNil(FOnCloseEvents);

      FreeAndNil(FOnPingEvents);
      FreeAndNil(FOnPongEvents);
    finally
      _Unlock;
    end;
  end;

  inherited;
end;

function TCrossWebSocket.GetStatus: TWsStatus;
begin
  _Lock;
  try
    Result := FStatus;

    if (FStatus = wsConnected) and (FConnection = nil) then
      Result := wsDisconnected;
  finally
    _Unlock;
  end;
end;

function TCrossWebSocket.GetUrl: string;
begin
  Result := FUrl;
end;

function TCrossWebSocket.OnClose(const ACallback: TWsClientOnClose): ICrossWebSocket;
begin
  _Lock;
  try
    FOnCloseEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.OnMessage(
  const ACallback: TWsClientOnMessage): ICrossWebSocket;
begin
  _Lock;
  try
    FOnMessageEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.OnOpenRequest(const ACallback: TWsClientOnOpenRequest): ICrossWebSocket;
begin
  _Lock;
  try
    FOnOpenRequestEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.OnOpenResponse(const ACallback: TWsClientOnOpenResponse): ICrossWebSocket;
begin
  _Lock;
  try
    FOnOpenResponseEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.OnOpen(const ACallback: TWsClientOnOpen): ICrossWebSocket;
begin
  _Lock;
  try
    FOnOpenEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.OnPing(const ACallback: TWsClientOnPing): ICrossWebSocket;
begin
  _Lock;
  try
    FOnPingEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.OnPong(const ACallback: TWsClientOnPong): ICrossWebSocket;
begin
  _Lock;
  try
    FOnPongEvents.Add(ACallback);
  finally
    _Unlock;
  end;

  Result := Self;
end;

function TCrossWebSocket.Open: ICrossWebSocket;
var
  LWebSocket: ICrossWebSocket;
  LSecWebSocketKey, LSecWebSocketAccept: string;
  LProtocols: TArray<string>;
  LOpenSerial: UInt64;
begin
  LWebSocket := Self;
  Result := LWebSocket;
  _Lock;
  try
    if (FStatus in [wsConnecting, wsConnected]) then Exit;
    FStatus := wsConnecting;
    if FOpenSerial = High(UInt64) then FOpenSerial := 0;
    Inc(FOpenSerial);
    LOpenSerial := FOpenSerial;
  finally
    _Unlock;
  end;

  LSecWebSocketKey := TCrossWebSocketParser.NewSecWebSocketKey;
  LSecWebSocketAccept := TCrossWebSocketParser.MakeSecWebSocketAccept(LSecWebSocketKey);

  // 发出 WebSocket 握手请求
  FMgr.DoRequest('GET', FUrl, nil,
    nil, 0, nil,
    procedure(const ARequest: ICrossHttpClientRequest)
    begin
      _Lock;
      try
        if (FOpenSerial <> LOpenSerial) or (FStatus <> wsConnecting) then
          raise Exception.Create('WebSocket 打开已取消');
        FOpeningConnection := ARequest.Connection as ICrossWebSocketClientConnection;
      finally _Unlock; end;
      {
        GET /websocket-endpoint HTTP/1.1
        Host: example.com
        Upgrade: websocket
        Connection: Upgrade
        Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
        Sec-WebSocket-Version: 13
      }
      ARequest.Header[HEADER_UPGRADE] := WEBSOCKET;
      ARequest.Header[HEADER_CONNECTION] := HEADER_UPGRADE;
      ARequest.Header[HEADER_SEC_WEBSOCKET_KEY] := LSecWebSocketKey;
      ARequest.Header[HEADER_SEC_WEBSOCKET_VERSION] := WEBSOCKET_VERSION;
      PrepareOpenRequest(ARequest);
      _OnOpenRequest(ARequest);
      ValidateOpenRequest(ARequest);
      // 按扩展回调之后实际发送的 key 和子协议验证响应。
      LSecWebSocketAccept := TCrossWebSocketParser.MakeSecWebSocketAccept(
        ARequest.Header[HEADER_SEC_WEBSOCKET_KEY].Trim);
      ARequest.Header.GetHeaderValues('Sec-WebSocket-Protocol', LProtocols);
    end,
    procedure(const AResponse: ICrossHttpClientResponse)
    var
      LAccept, LSelected, LUpgrade: TArray<string>;
      LOffer, LToken: string;
      LValid, LProtocolFound: Boolean;
      C: Char;
    begin
      {
        HTTP/1.1 101 Switching Protocols
        Upgrade: websocket
        Connection: Upgrade
        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
      }
      try
        if not _IsCurrentOpen(LOpenSerial) then
        begin
          if AResponse <> nil then _CloseCrossData(AResponse.Connection);
          Exit;
        end;
        try
          _OnOpenResponse(AResponse);
        except
          if AResponse <> nil then _CloseCrossData(AResponse.Connection);
          if _IsCurrentOpen(LOpenSerial) then _OnClose;
          raise;
        end;
        // 连接失败
        if (AResponse = nil) then
        begin
          if _IsCurrentOpen(LOpenSerial) then _OnClose;
          Exit;
        end;

        // 验证失败
        LValid := (AResponse.StatusCode = 101) and (AResponse.Connection <> nil)
          and not AResponse.Connection.IsClosed
          and TCrossWebSocketParser.IsValidHttpVersion((AResponse as TCrossHttpClientResponse).Version)
          and AResponse.Header.ContainsToken(HEADER_UPGRADE, WEBSOCKET)
          and AResponse.Header.ContainsToken(HEADER_CONNECTION, HEADER_UPGRADE);
        LValid := AResponse.Header.GetHeaderValues(HEADER_UPGRADE, LUpgrade) and LValid;
        LValid := LValid and (Length(LUpgrade) = 1);
        if Length(LUpgrade) = 1 then LValid := LValid and SameText(LUpgrade[0], WEBSOCKET);
        LValid := AResponse.Header.GetHeaderValues(HEADER_SEC_WEBSOCKET_ACCEPT, LAccept) and LValid;
        LValid := LValid and (Length(LAccept) = 1);
        if Length(LAccept) = 1 then LValid := LValid and (LAccept[0].Trim = LSecWebSocketAccept);
        // 当前没有实现协议扩展，不能仅因用户写入请求头就接受压缩等扩展。
        LValid := LValid and not AResponse.Header.ExistsParam('Sec-WebSocket-Extensions');
        if AResponse.Header.GetHeaderValues('Sec-WebSocket-Protocol', LSelected) then
        begin
          LProtocolFound := False;
          if (Length(LSelected) = 1) and (LSelected[0] <> '') then
          begin
            for LOffer in LProtocols do
              // LProtocols 是请求初始化后的提议快照；此处比对它，不读取后来可能变化的 Header。
              // Encode 会拒绝非法发送值；下方校验只让合法提议参与子协议匹配。
              if TCrossHttpUtils.IsValidHeaderValue(LOffer) then
                for LToken in LOffer.Split([',']) do
                  if LToken.Trim = LSelected[0] then LProtocolFound := True;
            for C in LSelected[0] do
              if not TCrossHttpUtils.IsTokenChar(C) then LProtocolFound := False;
          end;
          LValid := LValid and LProtocolFound;
        end;
        if LValid then LValid := ValidateOpenResponse(AResponse);
        LValid := LValid and _IsCurrentOpen(LOpenSerial);
        if not LValid then
        begin
          // 101 已从 HTTP 池移出；握手拒绝必须真正关闭，不能只改变 WS 状态。
          _CloseCrossData(AResponse.Connection);
          if _IsCurrentOpen(LOpenSerial) then _OnClose;
          Exit;
        end;

        // 握手成功
        _Lock;
        try
          LValid := (FOpenSerial = LOpenSerial) and (FStatus = wsConnecting);
          if LValid then
          begin
            FConnection := AResponse.Connection as TCrossWebSocketClientConnection;
            FOpeningConnection := nil;
            FConnection.FWebSocket := Self;
            FConnection.FIsWebSocket := True;
          end;
        finally _Unlock; end;
        if not LValid then
        begin
          _CloseCrossData(AResponse.Connection);
          Exit;
        end;
        try
          _OnOpen;
          (AResponse.Connection as TCrossWebSocketClientConnection).CompleteHandshake;
        except
          _CloseCrossData(AResponse.Connection);
          raise;
        end;
      finally
        LWebSocket := nil;
      end;
    end);
end;

procedure TCrossWebSocket.Ping;
begin
  if (GetStatus = wsConnected) then
    FConnection.WsPing;
end;

procedure TCrossWebSocket.Send(const AData: Pointer; const ACount: NativeInt;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACount, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData; const ACount: NativeInt;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACount, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData: TBytes; const AOffset,
  ACount: NativeInt; const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, AOffset, ACount, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData: TBytes;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData: string;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData: TWsClientChunkDataFunc;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData: TStream; const AOffset,
  ACount: Int64; const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, AOffset, ACount, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket.Send(const AData: TStream;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback)
  else if Assigned(ACallback) then
    ACallback(False);
end;

procedure TCrossWebSocket._Lock;
begin
  FLock.Enter;
end;

procedure TCrossWebSocket._OnClose(const AConnection: ICrossWebSocketClientConnection);
var
  LConnection: ICrossWebSocketClientConnection;
  LOnCloseEvents: TArray<TWsClientOnClose>;
  LOnCloseEvent: TWsClientOnClose;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    // 重连后旧物理连接的晚到关闭不能清掉新会话。
    if (AConnection <> nil) and
      (FConnection <> (AConnection as TCrossWebSocketClientConnection)) and
      (FOpeningConnection <> AConnection) then Exit;
    if (FStatus = wsDisconnected) and (FConnection = nil) and (FOpeningConnection = nil) then Exit;
    FStatus := wsDisconnected;
    LOnCloseEvents := FOnCloseEvents.ToArray;

    if (FConnection <> nil) then
    begin
      LConnection := FConnection;
      FConnection.FWebSocket := nil;
      FConnection := nil;
    end else
      LConnection := FOpeningConnection;
    FOpeningConnection := nil;
  finally
    _Unlock;
  end;

  if LConnection <> nil then
    (LConnection as TCrossWebSocketClientConnection)._CloseProtocol;

  for LOnCloseEvent in LOnCloseEvents do
    if Assigned(LOnCloseEvent) then
      LOnCloseEvent();
end;

function TCrossWebSocket._IsCurrentOpen(const ASerial: UInt64): Boolean;
begin
  _Lock;
  try Result := (FOpenSerial = ASerial) and (FStatus = wsConnecting);
  finally _Unlock; end;
end;

function TCrossWebSocket.GetConnection: ICrossWebSocketClientConnection;
begin
  _Lock;
  try Result := FConnection; finally _Unlock; end;
end;

procedure TCrossWebSocket.PrepareOpenRequest(const ARequest: ICrossHttpClientRequest);
begin
end;

procedure TCrossWebSocket.ValidateOpenRequest(const ARequest: ICrossHttpClientRequest);
begin
end;

function TCrossWebSocket.ValidateOpenResponse(const AResponse: ICrossHttpClientResponse): Boolean;
begin
  Result := True;
end;

procedure TCrossWebSocket._OnMessage(const AMessageType: TWsMessageType;
  const AMessageData: TBytes; const AProtocolOnMessage: TWsClientOnMessage);
var
  LOnMessageEvents: TArray<TWsOnMessage>;
  LOnMessageEvent: TWsOnMessage;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    LOnMessageEvents := FOnMessageEvents.ToArray;
  finally
    _Unlock;
  end;

  // 协议回调可以关闭或释放外观，公开事件仍使用进入时的独立快照。
  if Assigned(AProtocolOnMessage) then
    AProtocolOnMessage(AMessageType, AMessageData);

  for LOnMessageEvent in LOnMessageEvents do
    if Assigned(LOnMessageEvent) then
      LOnMessageEvent(AMessageType, AMessageData);
end;

procedure TCrossWebSocket._OnOpenRequest(const ARequest: ICrossHttpClientRequest);
var
  LOnOpenRequestEvents: TArray<TWsClientOnOpenRequest>;
  LOnOpenRequestEvent: TWsClientOnOpenRequest;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    LOnOpenRequestEvents := FOnOpenRequestEvents.ToArray;
  finally
    _Unlock;
  end;

  for LOnOpenRequestEvent in LOnOpenRequestEvents do
    if Assigned(LOnOpenRequestEvent) then
      LOnOpenRequestEvent(ARequest);
end;

procedure TCrossWebSocket._OnOpenResponse(const AResponse: ICrossHttpClientResponse);
var
  LOnOpenResponseEvents: TArray<TWsClientOnOpenResponse>;
  LOnOpenResponseEvent: TWsClientOnOpenResponse;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    LOnOpenResponseEvents := FOnOpenResponseEvents.ToArray;
  finally
    _Unlock;
  end;

  for LOnOpenResponseEvent in LOnOpenResponseEvents do
    if Assigned(LOnOpenResponseEvent) then
      LOnOpenResponseEvent(AResponse);
end;

procedure TCrossWebSocket._OnOpen;
var
  LConnection: ICrossWebSocketClientConnection;
  LOnOpenEvents: TArray<TWsClientOnOpen>;
  LOnOpenEvent: TWsClientOnOpen;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    if (FStatus <> wsConnecting) or (FConnection = nil) then Exit;
    FStatus := wsConnected;
    LConnection := FConnection;
    LOnOpenEvents := FOnOpenEvents.ToArray;
  finally
    _Unlock;
  end;

  DoOnOpen(LConnection);

  for LOnOpenEvent in LOnOpenEvents do
    if Assigned(LOnOpenEvent) then
      LOnOpenEvent();
end;

procedure TCrossWebSocket.DoOnOpen(
  const AConnection: ICrossWebSocketClientConnection);
begin
end;

procedure TCrossWebSocket._OnPing;
var
  LOnPingEvents: TArray<TWsClientOnPing>;
  LOnPingEvent: TWsClientOnClose;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    LOnPingEvents := FOnPingEvents.ToArray;
  finally
    _Unlock;
  end;

  for LOnPingEvent in LOnPingEvents do
    if Assigned(LOnPingEvent) then
      LOnPingEvent();
end;

procedure TCrossWebSocket._OnPong;
var
  LOnPongEvents: TArray<TWsClientOnPing>;
  LOnPongEvent: TWsClientOnClose;
begin
  if (GetStatus = wsShutdown) then Exit;

  _Lock;
  try
    LOnPongEvents := FOnPongEvents.ToArray;
  finally
    _Unlock;
  end;

  for LOnPongEvent in LOnPongEvents do
    if Assigned(LOnPongEvent) then
      LOnPongEvent();
end;

procedure TCrossWebSocket._Unlock;
begin
  FLock.Leave;
end;

{ TCrossWebSocketMgr }

procedure TCrossWebSocketMgr.CancelAll;
var
  LWsCli: ICrossHttpClientSocket;
begin
  inherited CancelAll;

  for LWsCli in FWsCliArr do
    LWsCli.CloseAll;
end;

constructor TCrossWebSocketMgr.Create(const AIoThreads: Integer);
begin
  FIoThreads := AIoThreads;
  FWsCliArr := [];

  inherited Create(AIoThreads, ctNone);
end;

function TCrossWebSocketMgr.CreateHttpCli(
  const AProtocol: string): ICrossHttpClientSocket;
begin
  if TStrUtils.SameText(AProtocol, WS) then
  begin
    if (FWsCli = nil) then
    begin
      FWsCli := TCrossWebSocketClient.Create(
        Self, FIoThreads, -1, -1, False,
        False, False, ctNone);
      FWsCliArr := FWsCliArr + [FWsCli];
    end;

    Result := FWsCli;
  end else
  if TStrUtils.SameText(AProtocol, WSS) then
  begin
    if (FWssCli = nil) then
    begin
      FWssCli := TCrossWebSocketClient.Create(
        Self, FIoThreads, -1, -1,
        True, False, False, ctNone);
      FWsCliArr := FWsCliArr + [FWssCli];
    end;

    Result := FWssCli;
  end else
    Result := inherited CreateHttpCli(AProtocol);
end;

procedure TCrossWebSocketMgr.SetProxySettings(
  const AValue: TCrossProxySettings);
var
  LWsCli: ICrossHttpClientSocket;
begin
  inherited SetProxySettings(AValue);
  for LWsCli in FWsCliArr do
    (LWsCli as TObject as TCrossHttpClientSocket).SyncProxySettings(AValue);
end;

function TCrossWebSocketMgr.CreateWebSocket(
  const AUrl: string): ICrossWebSocket;
var
  LWebSocket: TCrossWebSocket;
begin
  LWebSocket := TCrossWebSocket.Create(Self, AUrl);

  Result := LWebSocket;
end;

destructor TCrossWebSocketMgr.Destroy;
begin
  if (FWsCli <> nil) then
    FWsCli.StopLoop;

  if (FWssCli <> nil) then
    FWssCli.StopLoop;

  inherited;
end;

class function TCrossWebSocketMgr.GetDefault: ICrossWebSocketMgr;
var
  LDefault: ICrossWebSocketMgr;
begin
  if (FDefault = nil) then
  begin
    LDefault := TCrossWebSocketMgr.Create;
    if AtomicCmpExchange(Pointer(FDefault), Pointer(LDefault), nil) <> nil then
      LDefault := nil
    else
      FDefault._AddRef;
  end;
  Result := FDefault;
end;

end.
