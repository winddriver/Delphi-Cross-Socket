{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossWebSocketServer;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  StrUtils,
  Generics.Collections,

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossHttpServer,
  Net.CrossHttpUtils,
  Net.CrossWebSocketParser,
  Net.CrossWebSocketSender,

  Utils.SyncObjs,
  Utils.Utils;

type
  ICrossWebSocketConnection = interface;

  {$REGION 'Documentation'}
  /// <summary>
  ///   发送数据回调
  /// </summary>
  {$ENDREGION}
  TWsServerCallback = reference to procedure(const AWsConnection: ICrossWebSocketConnection; const ASuccess: Boolean);

  {$REGION 'Documentation'}
  /// <summary>
  ///   提供块数据的匿名函数
  /// </summary>
  {$ENDREGION}
  TWsServerChunkDataFunc = reference to function(const AData: PPointer; const ACount: PNativeInt): Boolean;

  {$REGION 'Documentation'}
  /// <summary>
  ///   收到消息数据事件
  /// </summary>
  {$ENDREGION}
  TWsServerOnMessage = reference to procedure(const AConnection: ICrossWebSocketConnection;
    const ARequestType: TWsMessageType; const ARequestData: TBytes);

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 已连接事件
  /// </summary>
  {$ENDREGION}
  TWsServerOnOpen = reference to procedure(const AConnection: ICrossWebSocketConnection);

  {$REGION 'Documentation'}
  /// <summary>
  ///   WebSocket 已关闭事件
  /// </summary>
  {$ENDREGION}
  TWsServerOnClose = TWsServerOnOpen;

  {$REGION 'Documentation'}
  /// <summary>
  ///   收到 "Ping" 事件
  /// </summary>
  {$ENDREGION}
  TWsServerOnPing = TWsServerOnOpen;

  {$REGION 'Documentation'}
  /// <summary>
  ///   收到 "Pong" 事件
  /// </summary>
  {$ENDREGION}
  TWsServerOnPong = TWsServerOnOpen;

  /// <summary>
  ///   WebSocket连接接口
  /// </summary>
  ICrossWebSocketConnection = interface(ICrossHttpConnection)
  ['{15AAA55B-1671-43A1-A9CF-D3EF08D377A6}']
    /// <summary>
    ///   是否WEB SOCKET
    /// </summary>
    function IsWebSocket: Boolean;

    /// <summary>
    ///   发送关闭握手
    /// </summary>
    procedure WsClose;

    /// <summary>
    ///   发送 Ping 包
    /// </summary>
    procedure WsPing;

    /// <summary>
    ///   发送无类型数据
    /// </summary>
    /// <param name="AData">
    ///   无类型数据
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure WsSend(const AData; const ACount: NativeInt; const ACallback: TWsServerCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="AData">
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
    procedure WsSend(const AData: TBytes; const AOffset, ACount: NativeInt; const ACallback: TWsServerCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="AData">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure WsSend(const AData: TBytes; const ACallback: TWsServerCallback = nil); overload;

    /// <summary>
    ///   发送字符串数据
    /// </summary>
    /// <param name="AData">
    ///   字符串数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure WsSend(const AData: string; const ACallback: TWsServerCallback = nil); overload;

    /// <summary>
    ///   发送碎片化数据
    /// </summary>
    /// <param name="AData">
    ///   碎片化数据源
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   回调函数说明:
    ///   <list type="bullet">
    ///     <item>
    ///       第一个参数: 待发送数据指针
    ///     </item>
    ///     <item>
    ///       第二个参数: 待发送数据长度
    ///     </item>
    ///     <item>
    ///       返回值: 数据是否有效
    ///     </item>
    ///     <item>
    ///       当待发送数据指针为nil或者长度小于等于0或者返回值为false时, 表示没有更多的数据需要发送了
    ///     </item>
    ///   </list>
    /// </remarks>
    procedure WsSend(const AData: TWsServerChunkDataFunc; const ACallback: TWsServerCallback = nil); overload;

    /// <summary>
    ///   发送流数据
    /// </summary>
    /// <param name="AData">
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
    procedure WsSend(const AData: TStream; const AOffset, ACount: Int64; const ACallback: TWsServerCallback = nil); overload;

    /// <summary>
    ///   发送流数据
    /// </summary>
    /// <param name="AData">
    ///   流数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <remarks>
    ///   必须保证发送过程中流对象的有效性, 要释放流对象可以放到回调函数中进行
    /// </remarks>
    procedure WsSend(const AData: TStream; const ACallback: TWsServerCallback = nil); overload;
  end;

  /// <summary>
  ///   跨平台WebSocket服务器
  /// </summary>
  ICrossWebSocketServer = interface(ICrossHttpServer)
  ['{13637DAA-35EF-4B0D-B2C5-74BF6A6FEC10}']

    /// <summary>
    ///   WebSocket连接建立时触发
    /// </summary>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    function OnOpen(const ACallback: TWsServerOnOpen): ICrossWebSocketServer;

    /// <summary>
    ///   收到WebSocket消息时触发
    /// </summary>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    function OnMessage(const ACallback: TWsServerOnMessage): ICrossWebSocketServer;

    /// <summary>
    ///   WebSocket连接关闭时触发
    /// </summary>
    /// <param name="ACallback">
    ///   hui'diaohanshu
    /// </param>
    function OnClose(const ACallback: TWsServerOnClose): ICrossWebSocketServer;

    /// <summary>
    ///   收到 Ping 包时触发
    /// </summary>
    /// <param name="ACallback">
    ///   hui'diaohanshu
    /// </param>
    function OnPing(const ACallback: TWsServerOnPing): ICrossWebSocketServer;

    /// <summary>
    ///   收到 Pong 包时触发
    /// </summary>
    /// <param name="ACallback">
    ///   hui'diaohanshu
    /// </param>
    function OnPong(const ACallback: TWsServerOnPong): ICrossWebSocketServer;
  end;

  TCrossWebSocketConnection = class(TCrossHttpConnection, ICrossWebSocketConnection)
  private type
    TWsFrameParseState = (wsHeader, wsBody, wsDone);
  private
    FIsWebSocket: Boolean;
    FWsParser: TCrossWebSocketParser;
    FWsSender: TCrossWebSocketSender;
    FHandshakeLimit, FHandshakeCount: Integer;
    FHandshakeReady, FHandshakeDraining: Boolean;
    FHandshakeData: TBytes;

    procedure _WebSocketRecv(var ABuf: Pointer; var ALen: Integer);
    procedure _BufferHandshake(var ABuf: Pointer; var ALen: Integer);
    procedure _ClearHandshake;

    {$region '内部发送方法'}
    procedure _WsSend(AOpCode: Byte; AFin: Boolean; AData: Pointer; ACount: NativeInt;
      ACallback: TWsServerCallback = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes; AOffset, ACount: NativeInt;
      ACallback: TWsServerCallback = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes;
      ACallback: TWsServerCallback = nil); overload;
    {$endregion}

    procedure _RespondPong(const AData: TBytes);
    procedure _RespondClose(const AData: TBytes);
    procedure _StopParserIfDisconnected;
  protected
    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer); override;
    procedure InternalClose; override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;
    procedure SetHandshakeBufferLimit(const AValue: Integer);
    function HandshakeReady: Boolean;
    procedure CompleteHandshake;

    // 开始接收前配置。接口不变，具体连接类增加可选资源策略。
    procedure SetWebSocketLimits(const AMaxMessageSize: UInt64;
      const AMessageTimeoutMs, ACloseTimeoutMs: Cardinal);
    // 发送器必须空闲；既有连接接口布局不变。
    procedure SetWebSocketSendQueueLimits(const ALimits: TWsSendQueueLimits);
    // 由调用方定期调用；内部与接收解析互斥，不创建后台线程。
    procedure CheckWebSocketTimeouts;

    function IsWebSocket: Boolean;
    procedure WsClose;
    procedure WsPing;

    procedure WsSend(const AData: Pointer; const ACount: NativeInt; const ACallback: TWsServerCallback = nil); overload;
    procedure WsSend(const AData; const ACount: NativeInt; const ACallback: TWsServerCallback = nil); overload;
    procedure WsSend(const AData: TBytes; const AOffset, ACount: NativeInt; const ACallback: TWsServerCallback = nil); overload;
    procedure WsSend(const AData: TBytes; const ACallback: TWsServerCallback = nil); overload;
    procedure WsSend(const AData: string; const ACallback: TWsServerCallback = nil); overload;

    procedure WsSend(const AData: TWsServerChunkDataFunc; const ACallback: TWsServerCallback = nil); overload;
    procedure WsSend(const AData: TStream; const AOffset, ACount: Int64; const ACallback: TWsServerCallback = nil); overload;
    procedure WsSend(const AData: TStream; const ACallback: TWsServerCallback = nil); overload;
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
  TCrossWebSocketServer = class(TCrossHttpServer, ICrossWebSocketServer)
  private
    FOnOpenEvents: TList<TWsServerOnOpen>;
    FOnOpenEventsLock: ILock;

    FOnMessageEvents: TList<TWsServerOnMessage>;
    FOnMessageEventsLock: ILock;

    FOnCloseEvents: TList<TWsServerOnClose>;
    FOnCloseEventsLock: ILock;

    FOnPingEvents: TList<TWsServerOnPing>;
    FOnPingEventsLock: ILock;

    FOnPongEvents: TList<TWsServerOnPong>;
    FOnPongEventsLock: ILock;

    procedure _WebSocketHandshake(const AConnection: ICrossWebSocketConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
      const ACallback: TWsServerCallback);

    procedure _OnOpen(const AConnection: ICrossWebSocketConnection);
    procedure _OnMessage(const AConnection: ICrossWebSocketConnection;
      const ARequestType: TWsMessageType; const ARequestData: TBytes);
    procedure _OnClose(const AConnection: ICrossWebSocketConnection);

    procedure _OnPing(const AConnection: ICrossWebSocketConnection);
    procedure _OnPong(const AConnection: ICrossWebSocketConnection);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;

    procedure DoOnRequest(const AConnection: ICrossHttpConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse); override;
    // 通用验证成功后、切换 WS 状态和发送101之前执行；False发送HTTP400。
    function PrepareWebSocketUpgrade(const AConnection: ICrossWebSocketConnection;
      const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse): Boolean; virtual;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    function OnOpen(const ACallback: TWsServerOnOpen): ICrossWebSocketServer;
    function OnMessage(const ACallback: TWsServerOnMessage): ICrossWebSocketServer;
    function OnClose(const ACallback: TWsServerOnClose): ICrossWebSocketServer;

    function OnPing(const ACallback: TWsServerOnPing): ICrossWebSocketServer;
    function OnPong(const ACallback: TWsServerOnPong): ICrossWebSocketServer;
  end;

implementation

{ TCrossWebSocketConnection }

constructor TCrossWebSocketConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);
  FWsSender := TCrossWebSocketSender.Create(Self, True);
  FHandshakeLimit := 0;
  FWsParser := TCrossWebSocketParser.Create(
    procedure(const AOpCode: Byte; const AData: TBytes)
    var
      LConnection: ICrossWebSocketConnection;
      LServer: TCrossWebSocketServer;
    begin
      LConnection := Self;
      LServer := Owner as TCrossWebSocketServer;
      try
        case AOpCode of
          WS_OP_CLOSE: _RespondClose(AData);
          WS_OP_PING:
            begin
              LServer._OnPing(LConnection);
              if not (ConnectStatus in [csDisconnected, csClosed]) then
                _RespondPong(AData);
            end;
          WS_OP_PONG: LServer._OnPong(LConnection);
        end;
      finally
        _StopParserIfDisconnected;
      end;
    end,
    procedure(const AType: TWsMessageType; const AData: TBytes)
    var
      LConnection: ICrossWebSocketConnection;
    begin
      LConnection := Self;
      try
        (Owner as TCrossWebSocketServer)._OnMessage(LConnection, AType, AData);
      finally
        _StopParserIfDisconnected;
      end;
    end,
    procedure
    begin
      FWsSender.FailProtocol(FWsParser.ErrorCode);
    end);
  FWsParser.Role := wprServer;
  FWsParser.AllowedRsvBits := 0;
  FWsParser.CheckTextUtf8 := True;
end;

destructor TCrossWebSocketConnection.Destroy;
begin
  FreeAndNil(FWsParser);
  FreeAndNil(FWsSender);
  inherited;
end;

function TCrossWebSocketConnection.IsWebSocket: Boolean;
begin
  Result := FIsWebSocket;
end;

procedure TCrossWebSocketConnection.SetHandshakeBufferLimit(const AValue: Integer);
begin
  if AValue < 0 then raise Exception.Create('握手暂存上限不能为负数');
  _LockRecv;
  try
    if (AValue > 0) and (FHandshakeCount > AValue) then raise Exception.Create('握手暂存已超过新上限');
    FHandshakeLimit := AValue;
    if (AValue > 0) and (Length(FHandshakeData) > AValue) then SetLength(FHandshakeData, AValue);
  finally _UnlockRecv; end;
end;

function TCrossWebSocketConnection.HandshakeReady: Boolean;
begin
  _LockRecv;
  try Result := FHandshakeReady and not IsClosed; finally _UnlockRecv; end;
end;

procedure TCrossWebSocketConnection._ClearHandshake;
begin
  _LockRecv;
  try
    FHandshakeReady := False;
    FHandshakeData := nil;
    FHandshakeCount := 0;
  finally _UnlockRecv; end;
end;

procedure TCrossWebSocketConnection._BufferHandshake(var ABuf: Pointer; var ALen: Integer);
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

procedure TCrossWebSocketConnection.CompleteHandshake;
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

procedure TCrossWebSocketConnection.InternalClose;
begin
  try _ClearHandshake; finally inherited; end;
end;

procedure TCrossWebSocketConnection.ParseRecvData(var ABuf: Pointer;
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
      inherited ParseRecvData(ABuf, ALen);

    if (ALen > 0) and FIsWebSocket then
      if not FHandshakeReady or FHandshakeDraining then _BufferHandshake(ABuf, ALen)
      else _WebSocketRecv(ABuf, ALen);
  end;
end;

procedure TCrossWebSocketConnection.WsSend(const AData: Pointer;
  const ACount: NativeInt; const ACallback: TWsServerCallback);
begin
  _WsSend(WS_OP_BINARY, True, AData, ACount, ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData; const ACount: NativeInt;
  const ACallback: TWsServerCallback);
begin
  _WsSend(WS_OP_BINARY, True, @AData, ACount, ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TBytes;
  const AOffset, ACount: NativeInt; const ACallback: TWsServerCallback);
begin
  _WsSend(WS_OP_BINARY, True, AData, AOffset, ACount, ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TBytes;
  const ACallback: TWsServerCallback);
begin
  WsSend(AData, 0, Length(AData), ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: string;
  const ACallback: TWsServerCallback);
begin
  _WsSend(WS_OP_TEXT, True, TEncoding.UTF8.GetBytes(AData), ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TWsServerChunkDataFunc;
  const ACallback: TWsServerCallback);
var
  LConnection: ICrossWebSocketConnection;
begin
  LConnection := Self;
  FWsSender.SendChunks(
    function(const ABuffer: PPointer; const ACount: PNativeInt): Boolean
    begin
      Result := False;
      if Assigned(AData) then Result := AData(ABuffer, ACount);
    end,
    procedure(const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then ACallback(LConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TStream;
  const AOffset, ACount: Int64; const ACallback: TWsServerCallback);
var
  LOffset, LCount: Int64;
  LConnection: ICrossWebSocketConnection;
begin
  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(AData.Size, LOffset, LCount);

  if (AData is TCustomMemoryStream) then
  begin
    WsSend(Pointer(IntPtr(TCustomMemoryStream(AData).Memory) + LOffset)^, LCount, ACallback);
    Exit;
  end;

  AData.Position := LOffset;
  LConnection := Self;
  FWsSender.SendStream(AData, LCount,
    procedure(const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then ACallback(LConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TStream;
  const ACallback: TWsServerCallback);
begin
  WsSend(AData, 0, 0, ACallback);
end;

procedure TCrossWebSocketConnection.WsClose;
begin
  FWsSender.RequestClose;
end;

procedure TCrossWebSocketConnection.SetWebSocketSendQueueLimits(
  const ALimits: TWsSendQueueLimits);
begin
  FWsSender.SetQueueLimits(ALimits);
end;

procedure TCrossWebSocketConnection.WsPing;
begin
  _WsSend(WS_OP_PING, True, nil, 0);
end;

procedure TCrossWebSocketConnection._StopParserIfDisconnected;
begin
  if (FWsParser <> nil) and (ConnectStatus in [csDisconnected, csClosed]) then
    FWsParser.Stop;
end;

procedure TCrossWebSocketConnection.SetWebSocketLimits(const AMaxMessageSize: UInt64;
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

procedure TCrossWebSocketConnection.CheckWebSocketTimeouts;
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

procedure TCrossWebSocketConnection._WebSocketRecv(var ABuf: Pointer; var ALen: Integer);
begin
  _StopParserIfDisconnected;
  FWsParser.Decode(ABuf, ALen);
end;

procedure TCrossWebSocketConnection._RespondClose(const AData: TBytes);
begin
  FWsSender.ReceiveClose(AData);
end;

procedure TCrossWebSocketConnection._RespondPong(const AData: TBytes);
begin
  _WsSend(WS_OP_PONG, True, AData);
end;

procedure TCrossWebSocketConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  AData: Pointer; ACount: NativeInt; ACallback: TWsServerCallback);
var
  LConnection: ICrossWebSocketConnection;
begin
  LConnection := Self;
  FWsSender.Send(AOpCode, AFin, AData, ACount,
    procedure(const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then ACallback(LConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  const AData: TBytes; AOffset, ACount: NativeInt;
  ACallback: TWsServerCallback);
var
  LData: TBytes;
  P: PByte;
  LOffset, LCount: NativeInt;
begin
  LData := AData;

  if (AData <> nil) and (ACount > 0) then
  begin
    LOffset := AOffset;
    LCount := ACount;
    TCrossHttpUtils.AdjustOffsetCount(Length(AData), LOffset, LCount);

    P := PByte(@AData[0]) + LOffset;
  end else
  begin
    P := nil;
    LCount := 0;
  end;

  _WsSend(AOpCode, AFin, P, LCount,
    procedure(const AConnection: ICrossWebSocketConnection; const ASuccess: Boolean)
    begin
      LData := nil;
      if Assigned(ACallback) then
        ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  const AData: TBytes; ACallback: TWsServerCallback);
begin
  _WsSend(AOpCode, AFin, AData, 0, Length(AData), ACallback);
end;

{ TCrossWebSocketServer }

constructor TCrossWebSocketServer.Create(const AIoThreads: Integer; const ASsl: Boolean);
begin
  inherited Create(AIoThreads, ASsl);

  FOnOpenEvents := TList<TWsServerOnOpen>.Create;
  FOnOpenEventsLock := TLock.Create;

  FOnMessageEvents := TList<TWsServerOnMessage>.Create;
  FOnMessageEventsLock := TLock.Create;

  FOnCloseEvents := TList<TWsServerOnClose>.Create;
  FOnCloseEventsLock := TLock.Create;

  FOnPingEvents := TList<TWsServerOnPing>.Create;
  FOnPingEventsLock := TLock.Create;

  FOnPongEvents := TList<TWsServerOnPong>.Create;
  FOnPongEventsLock := TLock.Create;
end;

destructor TCrossWebSocketServer.Destroy;
begin
  FreeAndNil(FOnOpenEvents);
  FreeAndNil(FOnMessageEvents);
  FreeAndNil(FOnCloseEvents);

  FreeAndNil(FOnPingEvents);
  FreeAndNil(FOnPongEvents);

  inherited;
end;

procedure TCrossWebSocketServer.LogicDisconnected(
  const AConnection: ICrossConnection);
var
  LConnection: ICrossWebSocketConnection;
begin
  LConnection := AConnection as ICrossWebSocketConnection;
  try
    if LConnection.IsWebSocket then _OnClose(LConnection);
  finally
    inherited LogicDisconnected(AConnection);
  end;
end;

function TCrossWebSocketServer.OnClose(const ACallback: TWsServerOnClose): ICrossWebSocketServer;
begin
  FOnCloseEventsLock.Enter;
  try
    FOnCloseEvents.Add(ACallback);
  finally
    FOnCloseEventsLock.Leave;
  end;

  Result := Self;
end;

function TCrossWebSocketServer.OnMessage(const ACallback: TWsServerOnMessage): ICrossWebSocketServer;
begin
  FOnMessageEventsLock.Enter;
  try
    FOnMessageEvents.Add(ACallback);
  finally
    FOnMessageEventsLock.Leave;
  end;

  Result := Self;
end;

function TCrossWebSocketServer.OnOpen(const ACallback: TWsServerOnOpen): ICrossWebSocketServer;
begin
  FOnOpenEventsLock.Enter;
  try
    FOnOpenEvents.Add(ACallback);
  finally
    FOnOpenEventsLock.Leave;
  end;

  Result := Self;
end;

function TCrossWebSocketServer.OnPing(
  const ACallback: TWsServerOnPing): ICrossWebSocketServer;
begin
  FOnPingEventsLock.Enter;
  try
    FOnPingEvents.Add(ACallback);
  finally
    FOnPingEventsLock.Leave;
  end;

  Result := Self;
end;

function TCrossWebSocketServer.OnPong(
  const ACallback: TWsServerOnPong): ICrossWebSocketServer;
begin
  FOnPongEventsLock.Enter;
  try
    FOnPongEvents.Add(ACallback);
  finally
    FOnPongEventsLock.Leave;
  end;

  Result := Self;
end;

procedure TCrossWebSocketServer._OnClose(
  const AConnection: ICrossWebSocketConnection);
var
  LOnCloseEvents: TArray<TWsServerOnClose>;
  LOnCloseEvent: TWsServerOnClose;
begin
  FOnCloseEventsLock.Enter;
  try
    LOnCloseEvents := FOnCloseEvents.ToArray;
  finally
    FOnCloseEventsLock.Leave;
  end;

  for LOnCloseEvent in LOnCloseEvents do
    if Assigned(LOnCloseEvent) then
      LOnCloseEvent(AConnection);
end;

procedure TCrossWebSocketServer._OnMessage(
  const AConnection: ICrossWebSocketConnection; const ARequestType: TWsMessageType;
  const ARequestData: TBytes);
var
  LOnMessageEvents: TArray<TWsServerOnMessage>;
  LOnMessageEvent: TWsServerOnMessage;
begin
  FOnMessageEventsLock.Enter;
  try
    LOnMessageEvents := FOnMessageEvents.ToArray;
  finally
    FOnMessageEventsLock.Leave;
  end;

  for LOnMessageEvent in LOnMessageEvents do
    if Assigned(LOnMessageEvent) then
      LOnMessageEvent(AConnection, ARequestType, ARequestData);
end;

procedure TCrossWebSocketServer._OnOpen(
  const AConnection: ICrossWebSocketConnection);
var
  LOnOpenEvents: TArray<TWsServerOnOpen>;
  LOnOpenEvent: TWsServerOnOpen;
begin
  FOnOpenEventsLock.Enter;
  try
    LOnOpenEvents := FOnOpenEvents.ToArray;
  finally
    FOnOpenEventsLock.Leave;
  end;

  for LOnOpenEvent in LOnOpenEvents do
    if Assigned(LOnOpenEvent) then
      LOnOpenEvent(AConnection);
end;

procedure TCrossWebSocketServer._OnPing(
  const AConnection: ICrossWebSocketConnection);
var
  LOnPingEvents: TArray<TWsServerOnPing>;
  LOnPingEvent: TWsServerOnClose;
begin
  FOnPingEventsLock.Enter;
  try
    LOnPingEvents := FOnPingEvents.ToArray;
  finally
    FOnPingEventsLock.Leave;
  end;

  for LOnPingEvent in LOnPingEvents do
    if Assigned(LOnPingEvent) then
      LOnPingEvent(AConnection);
end;

procedure TCrossWebSocketServer._OnPong(
  const AConnection: ICrossWebSocketConnection);
var
  LOnPongEvents: TArray<TWsServerOnPing>;
  LOnPongEvent: TWsServerOnClose;
begin
  FOnPongEventsLock.Enter;
  try
    LOnPongEvents := FOnPongEvents.ToArray;
  finally
    FOnPongEventsLock.Leave;
  end;

  for LOnPongEvent in LOnPongEvents do
    if Assigned(LOnPongEvent) then
      LOnPongEvent(AConnection);
end;

procedure TCrossWebSocketServer._WebSocketHandshake(
  const AConnection: ICrossWebSocketConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse;
  const ACallback: TWsServerCallback);
begin
  {
    HTTP/1.1 101 Switching Protocols
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
  }
  AResponse.Header[HEADER_UPGRADE] := WEBSOCKET;
  AResponse.Header[HEADER_CONNECTION] := HEADER_UPGRADE;
  AResponse.Header[HEADER_SEC_WEBSOCKET_ACCEPT] :=
    TCrossWebSocketParser.MakeSecWebSocketAccept(ARequest.Header[HEADER_SEC_WEBSOCKET_KEY]);
  AResponse.SendStatus(101, '',
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then
        ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
    end);
end;

function TCrossWebSocketServer.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossWebSocketConnection.Create(
    AOwner,
    AClientSocket,
    AConnectType,
    AHost,
    AConnectCb);
end;

function TCrossWebSocketServer.PrepareWebSocketUpgrade(
  const AConnection: ICrossWebSocketConnection; const ARequest: ICrossHttpRequest;
  const AResponse: ICrossHttpResponse): Boolean;
begin
  Result := True;
end;

procedure TCrossWebSocketServer.DoOnRequest(
  const AConnection: ICrossHttpConnection;
  const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse);
var
  LConnection: ICrossWebSocketConnection;
  LConnectionObj: TCrossWebSocketConnection;
  LKeys, LVersions, LHosts: TArray<string>;
  LValid, LWrongVersion: Boolean;

  procedure RejectHandshake(const ACode: Integer);
  begin
    AResponse.Header[HEADER_CONNECTION] := 'close';
    AResponse.SendStatus(ACode,
      procedure(const C: ICrossConnection; const OK: Boolean)
      begin
        // 先让已写出的 HTTP 错误响应正常结束，避免立即 Close 丢弃内核发送数据。
        if C <> nil then C.Disconnect;
      end);
  end;
begin
  LConnection := AConnection as ICrossWebSocketConnection;
  LConnectionObj := LConnection as TCrossWebSocketConnection;

  if LConnectionObj.FIsWebSocket then Exit;

  {
    GET /websocket-endpoint HTTP/1.1
    Host: example.com
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
    Sec-WebSocket-Version: 13
  }
  // 判断是否收到 websocket 握手请求, 直接使用入参 request 避免读取连接字段
  if ARequest.Header.ContainsToken(HEADER_UPGRADE, WEBSOCKET)
    or ARequest.Header.ExistsParam(HEADER_SEC_WEBSOCKET_KEY)
    or ARequest.Header.ExistsParam(HEADER_SEC_WEBSOCKET_VERSION) then
  begin
    LValid := (ARequest.Method = THttpMethod.GET)
      and TCrossWebSocketParser.IsValidHttpVersion(ARequest.Version)
      and ARequest.Header.ContainsToken(HEADER_UPGRADE, WEBSOCKET)
      and ARequest.Header.ContainsToken(HEADER_CONNECTION, HEADER_UPGRADE);
    LValid := ARequest.Header.GetHeaderValues(HEADER_HOST, LHosts) and LValid;
    LValid := LValid and (Length(LHosts) = 1);
    if Length(LHosts) = 1 then LValid := LValid and (LHosts[0].Trim <> '');
    LValid := ARequest.Header.GetHeaderValues(HEADER_SEC_WEBSOCKET_KEY, LKeys) and LValid;
    LValid := LValid and (Length(LKeys) = 1);
    if Length(LKeys) = 1 then
      LValid := LValid and TCrossWebSocketParser.IsValidSecWebSocketKey(LKeys[0]);
    LValid := ARequest.Header.GetHeaderValues(HEADER_SEC_WEBSOCKET_VERSION, LVersions) and LValid;
    LValid := LValid and (Length(LVersions) = 1);
    if not LValid then
    begin
      RejectHandshake(400);
      Exit;
    end;
    LWrongVersion := LVersions[0] <> WEBSOCKET_VERSION;
    if LWrongVersion then
    begin
      AResponse.Header[HEADER_SEC_WEBSOCKET_VERSION] := WEBSOCKET_VERSION;
      RejectHandshake(426);
      Exit;
    end;
    if not PrepareWebSocketUpgrade(LConnection, ARequest, AResponse) then
    begin
      RejectHandshake(400);
      Exit;
    end;
    LConnectionObj.FIsWebSocket := True;
    try
      _WebSocketHandshake(LConnection, ARequest, AResponse,
        procedure(const AConnection: ICrossWebSocketConnection; const ASuccess: Boolean)
        begin
          if not ASuccess or AConnection.IsClosed then
          begin
            _CloseCrossData(AConnection);
            Exit;
          end;
          try
            _OnOpen(AConnection);
            (AConnection as TCrossWebSocketConnection).CompleteHandshake;
          except
            _CloseCrossData(AConnection);
            raise;
          end;
        end);
    except
      _CloseCrossData(LConnection);
      raise;
    end;
  end else
    inherited DoOnRequest(LConnection, ARequest, AResponse);
end;

end.
