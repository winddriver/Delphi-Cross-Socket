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
  Math,
  Generics.Collections,

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossHttpServer,
  Net.CrossHttpUtils,
  Net.CrossWebSocketParser,

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
  ['{FF008E22-9938-4DC4-9421-083DA9EFFCDC}']
    function GetMaskingKey: Cardinal;

    procedure SetMaskingKey(const AValue: Cardinal);

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

    {$REGION 'Documentation'}
    /// <summary>
    ///   Masking-Key
    /// </summary>
    {$ENDREGION}
    property MaskingKey: Cardinal read GetMaskingKey write SetMaskingKey;
  end;

  TCrossWebSocketConnection = class(TCrossHttpConnection, ICrossWebSocketConnection)
  private type
    TWsFrameParseState = (wsHeader, wsBody, wsDone);
  private
    FIsWebSocket: Boolean;
    FWsParser: TCrossWebSocketParser;
    FWsSendClose: Integer;

    procedure _WebSocketRecv(var ABuf: Pointer; var ALen: Integer);

    {$region '内部发送方法'}
    procedure _WsSend(AOpCode: Byte; AFin: Boolean; AData: Pointer; ACount: NativeInt;
      ACallback: TWsServerCallback = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes; AOffset, ACount: NativeInt;
      ACallback: TWsServerCallback = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes;
      ACallback: TWsServerCallback = nil); overload;
    {$endregion}

    procedure _RespondPong(const AData: TBytes);
    procedure _RespondClose;
  protected
    procedure ParseRecvData(var ABuf: Pointer; var ALen: Integer); override;
    procedure ReleaseRequest; override;
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

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
    FMaskingKey: Cardinal;
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
      const ACallback: TWsServerCallback);

    procedure _OnOpen(const AConnection: ICrossWebSocketConnection);
    procedure _OnMessage(const AConnection: ICrossWebSocketConnection;
      const ARequestType: TWsMessageType; const ARequestData: TBytes);
    procedure _OnClose(const AConnection: ICrossWebSocketConnection);

    procedure _OnPing(const AConnection: ICrossWebSocketConnection);
    procedure _OnPong(const AConnection: ICrossWebSocketConnection);
  protected
    function GetMaskingKey: Cardinal;

    procedure SetMaskingKey(const AValue: Cardinal);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AHost: string;
      const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
    procedure LogicDisconnected(const AConnection: ICrossConnection); override;

    procedure DoOnRequest(const AConnection: ICrossHttpConnection); override;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); override;
    destructor Destroy; override;

    function OnOpen(const ACallback: TWsServerOnOpen): ICrossWebSocketServer;
    function OnMessage(const ACallback: TWsServerOnMessage): ICrossWebSocketServer;
    function OnClose(const ACallback: TWsServerOnClose): ICrossWebSocketServer;

    function OnPing(const ACallback: TWsServerOnPing): ICrossWebSocketServer;
    function OnPong(const ACallback: TWsServerOnPong): ICrossWebSocketServer;

    property MaskingKey: Cardinal read GetMaskingKey write SetMaskingKey;
  end;

implementation

{ TCrossWebSocketConnection }

constructor TCrossWebSocketConnection.Create(const AOwner: TCrossSocketBase;
  const AClientSocket: TSocket; const AConnectType: TConnectType;
  const AHost: string; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AHost, AConnectCb);

  FWsParser := TCrossWebSocketParser.Create(
    procedure(const AOpCode: Byte; const AData: TBytes)
    var
      LWsServer: TCrossWebSocketServer;
      LConnection: ICrossWebSocketConnection;
    begin
      LConnection := Self;
      LWsServer := Owner as TCrossWebSocketServer;

      case AOpCode of
        WS_OP_CLOSE:
          begin
            // 关闭帧
            // 收到关闭帧, 如果已经发送关闭帧, 直接关闭连接
            // 否则, 需要发送关闭帧, 发送完成之后关闭连接
            _RespondClose;
          end;

        WS_OP_PING:
          begin
            LWsServer._OnPing(LConnection);

            // 收到 ping 帧后立即发回 pong 帧
            // pong 帧必须将 ping 帧发来的数据原封不动地返回
            _RespondPong(AData);
          end;

        WS_OP_PONG:
          begin
            LWsServer._OnPong(LConnection);
          end;
      end;
    end,

    procedure(const AType: TWsMessageType; const AData: TBytes)
    var
      LWsServer: TCrossWebSocketServer;
      LConnection: ICrossWebSocketConnection;
    begin
      LConnection := Self;
      LWsServer := Owner as TCrossWebSocketServer;
      LWsServer._OnMessage(LConnection, AType, AData);
    end,

    procedure
    begin
      Self.Close;
    end);
end;

destructor TCrossWebSocketConnection.Destroy;
begin
  FreeAndNil(FWsParser);
  inherited ReleaseRequest;
  inherited;
end;

function TCrossWebSocketConnection.IsWebSocket: Boolean;
begin
  Result := FIsWebSocket;
end;

procedure TCrossWebSocketConnection.ParseRecvData(var ABuf: Pointer;
  var ALen: Integer);
begin
  while (ALen > 0) do
  begin
    if not FIsWebSocket then
      inherited ParseRecvData(ABuf, ALen);

    if (ALen > 0) and FIsWebSocket then
      _WebSocketRecv(ABuf, ALen);
  end;
end;

procedure TCrossWebSocketConnection.ReleaseRequest;
begin
  if not FIsWebSocket then
    inherited ReleaseRequest;
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

procedure TCrossWebSocketConnection.WsSend(
  const AData: TWsServerChunkDataFunc;
  const ACallback: TWsServerCallback);
var
  LConnection: ICrossWebSocketConnection;
  LOpCode: Byte;
  LSender: TWsServerCallback;
begin
  LConnection := Self;
  LOpCode := WS_OP_BINARY;

  LSender :=
    procedure(const AConnection: ICrossWebSocketConnection; const ASuccess: Boolean)
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
      if not Assigned(AData)
        or not AData(@LData, @LCount)
        or (LData = nil)
        or (LCount <= 0) then
      begin
        LSender := nil;

        // 结束帧
        // opcode 为 WS_OP_CONTINUATION
        // FIN 为 1
        // 结束帧只有一个头, 因为结束帧是流无数据可读时才生成的
        (AConnection as TCrossWebSocketConnection)._WsSend(LOpCode,
          True, nil, 0, ACallback);

        Exit;
      end;

      // 第一帧及中间帧
      // 第一帧 opcode 为 WS_OP_BINARY, FIN 为 0
      // 中间帧 opcode 为 WS_OP_CONTINUATION, FIN 为 0
      (AConnection as TCrossWebSocketConnection)._WsSend(LOpCode,
        False, LData, LCount, LSender);

      LOpCode := WS_OP_CONTINUATION;
    end;

  LSender(LConnection, True);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TStream;
  const AOffset, ACount: Int64; const ACallback: TWsServerCallback);
var
  LOffset, LCount: Int64;
  LBody: TStream;
  LBuffer: TBytes;
begin
  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(AData.Size, LOffset, LCount);

  if (AData is TCustomMemoryStream) then
  begin
    WsSend(Pointer(IntPtr(TCustomMemoryStream(AData).Memory) + LOffset)^, LCount, ACallback);
    Exit;
  end;

  LBody := AData;
  LBody.Position := LOffset;

  SetLength(LBuffer, SND_BUF_SIZE);

  WsSend(
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
    procedure(const AConnection: ICrossWebSocketConnection; const ASuccess: Boolean)
    begin
      LBuffer := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TStream;
  const ACallback: TWsServerCallback);
begin
  WsSend(AData, 0, 0, ACallback);
end;

procedure TCrossWebSocketConnection.WsClose;
begin
  if (AtomicExchange(FWsSendClose, 1) = 1) then Exit;

  _WsSend(WS_OP_CLOSE, True, nil, 0);
end;

procedure TCrossWebSocketConnection.WsPing;
begin
  _WsSend(WS_OP_PING, True, nil, 0);
end;

procedure TCrossWebSocketConnection._WebSocketRecv(var ABuf: Pointer;
  var ALen: Integer);
begin
  FWsParser.Decode(ABuf, ALen);
end;

procedure TCrossWebSocketConnection._RespondClose;
begin
  if (AtomicExchange(FWsSendClose, 1) = 1) then
    Disconnect
  else
  begin
    _WsSend(WS_OP_CLOSE, True, nil, 0,
      procedure(const AConnection: ICrossWebSocketConnection; const ASuccess: Boolean)
      begin
        AConnection.Disconnect;
      end);
  end;
end;

procedure TCrossWebSocketConnection._RespondPong(const AData: TBytes);
begin
  _WsSend(WS_OP_PONG, True, AData);
end;

procedure TCrossWebSocketConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  AData: Pointer; ACount: NativeInt;
  ACallback: TWsServerCallback);
var
  LWsFrameData: TBytes;
begin
  // 将数据和头打包到一起发送
  // 这是因为如果分开发送, 在多线程环境多个不同的线程数据可能会出现交叉
  // 会引起数据与头部混乱
  LWsFrameData := TCrossWebSocketParser.MakeFrameData(
    AOpCode,
    AFin,
    (Owner as ICrossWebSocketServer).MaskingKey,
    AData,
    ACount);

  SendBytes(LWsFrameData,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then
        ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
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
  if LConnection.IsWebSocket then
    _OnClose(LConnection)
  else
    inherited;
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

procedure TCrossWebSocketServer.SetMaskingKey(const AValue: Cardinal);
begin
  FMaskingKey := AValue;
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
  const ACallback: TWsServerCallback);
begin
  {
    HTTP/1.1 101 Switching Protocols
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
  }
  AConnection.Response.Header[HEADER_UPGRADE] := WEBSOCKET;
  AConnection.Response.Header[HEADER_CONNECTION] := HEADER_UPGRADE;
  AConnection.Response.Header[HEADER_SEC_WEBSOCKET_ACCEPT] :=
    TCrossWebSocketParser.MakeSecWebSocketAccept(AConnection.Request.Header[HEADER_SEC_WEBSOCKET_KEY]);
  AConnection.Response.SendStatus(101, '',
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
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

procedure TCrossWebSocketServer.DoOnRequest(
  const AConnection: ICrossHttpConnection);
var
  LConnection: ICrossWebSocketConnection;
  LConnectionObj: TCrossWebSocketConnection;
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
  // 判断是否收到 websocket 握手请求
  if ContainsText(AConnection.Request.Header[HEADER_UPGRADE], WEBSOCKET)
    and ContainsText(AConnection.Request.Header[HEADER_CONNECTION], HEADER_UPGRADE) then
  begin
    LConnectionObj.FIsWebSocket := True;
    _WebSocketHandshake(LConnection,
      procedure(const AConnection: ICrossWebSocketConnection; const ASuccess: Boolean)
      begin
        if ASuccess then
          _OnOpen(AConnection);
      end);
  end else
    inherited;
end;

function TCrossWebSocketServer.GetMaskingKey: Cardinal;
begin
  Result := FMaskingKey;
end;

end.
