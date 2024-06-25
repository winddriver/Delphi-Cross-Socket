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
  Math,

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossHttpClient,
  Net.CrossHttpUtils,
  Net.CrossWebSocketParser,

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
  ['{951728E5-5F85-44E1-847F-59C9D30EBBBA}']
    function GetStatus: TWsStatus;
    function GetUrl: string;
    function GetMaskingKey: Cardinal;

    procedure SetMaskingKey(const AValue: Cardinal);

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

    {$REGION 'Documentation'}
    /// <summary>
    ///   Masking-Key
    /// </summary>
    {$ENDREGION}
    property MaskingKey: Cardinal read GetMaskingKey write SetMaskingKey;
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
  ['{3BAFCEDA-4A23-4CB1-9347-FBC4E9EF9214}']
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
    FWsSendClose: Integer;

    procedure _WebSocketRecv(var ABuf: Pointer; var ALen: Integer);

    procedure _RespondPong(const AData: TBytes);
    procedure _RespondClose;

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
  public
    constructor Create(const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback); override;
    destructor Destroy; override;

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
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
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
    FStatus: TWsStatus;
    FMaskingKey: Cardinal;
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
    procedure _OnMessage(const AMessageType: TWsMessageType; const AMessageData: TBytes);
    procedure _OnClose;

    procedure _OnPing;
    procedure _OnPong;
  protected
    function GetStatus: TWsStatus;
    function GetUrl: string;
    function GetMaskingKey: Cardinal;

    procedure SetMaskingKey(const AValue: Cardinal);
  public
    constructor Create(const AMgr: TCrossWebSocketMgr; const AUrl: string); overload; virtual;
    constructor Create(const AUrl: string); overload;
    destructor Destroy; override;

    function Open: ICrossWebSocket;
    function Close: ICrossWebSocket;

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
    property MaskingKey: Cardinal read GetMaskingKey write SetMaskingKey;
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
  public
    constructor Create(const AIoThreads: Integer = 2); reintroduce;
    destructor Destroy; override;

    procedure CancelAll; override;
    function CreateWebSocket(const AUrl: string): ICrossWebSocket;

    class property &Default: ICrossWebSocketMgr read GetDefault;
  end;

implementation

{ TCrossWebSocketClientConnection }

constructor TCrossWebSocketClientConnection.Create(
  const AOwner: TCrossSocketBase; const AClientSocket: TSocket;
  const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback);
begin
  inherited Create(AOwner, AClientSocket, AConnectType, AConnectCb);

  FWsParser := TCrossWebSocketParser.Create(
    procedure(const AOpCode: Byte; const AData: TBytes)
    begin
      if (FWebSocket = nil) then Exit;

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
            FWebSocket._OnPing();

            // 收到 ping 帧后立即发回 pong 帧
            // pong 帧必须将 ping 帧发来的数据原封不动地返回
            _RespondPong(AData);
          end;

        WS_OP_PONG:
          begin
            FWebSocket._OnPong();
          end;
      end;
    end,

    procedure(const AType: TWsMessageType; const AData: TBytes)
    begin
      if (FWebSocket <> nil) then
        FWebSocket._OnMessage(AType, AData);
    end);
end;

destructor TCrossWebSocketClientConnection.Destroy;
begin
  if (FWebSocket <> nil) then
  begin
    FWebSocket.FConnection := nil;
    FWebSocket := nil;
  end;

  FreeAndNil(FWsParser);

  inherited;
end;

procedure TCrossWebSocketClientConnection.ParseRecvData(var ABuf: Pointer;
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

procedure TCrossWebSocketClientConnection.WsClose;
begin
  if (AtomicExchange(FWsSendClose, 1) = 1) then Exit;

  _WsSend(WS_OP_CLOSE, True, nil, 0);
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

procedure TCrossWebSocketClientConnection.WsSend(
  const AData: TWsClientChunkDataFunc; const ACallback: TWsClientCallback);
var
  LOpCode: Byte;
  LSender: TWsClientCallback;
begin
  LOpCode := WS_OP_BINARY;

  LSender :=
    procedure(const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: NativeInt;
    begin
      if not ASuccess then
      begin
        if Assigned(ACallback) then
          ACallback(False);

        Close;

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
        _WsSend(LOpCode,
          True, nil, 0, ACallback);

        Exit;
      end;

      // 第一帧及中间帧
      // 第一帧 opcode 为 WS_OP_BINARY, FIN 为 0
      // 中间帧 opcode 为 WS_OP_CONTINUATION, FIN 为 0
      _WsSend(LOpCode,
        False, LData, LCount, LSender);

      LOpCode := WS_OP_CONTINUATION;
    end;

  LSender(True);
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
  LBody: TStream;
  LBuffer: TBytes;
begin
  LOffset := AOffset;
  LCount := ACount;
  TCrossHttpUtils.AdjustOffsetCount(AData.Size, LOffset, LCount);

  if (AData is TCustomMemoryStream) then
  begin
    WsSend((PByte(TCustomMemoryStream(AData).Memory) + LOffset)^, LCount, ACallback);
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
    procedure(const ASuccess: Boolean)
    begin
      LBuffer := nil;

      if Assigned(ACallback) then
        ACallback(ASuccess);
    end);
end;

procedure TCrossWebSocketClientConnection.WsSend(const AData: TStream;
  const ACallback: TWsClientCallback);
begin
  WsSend(AData, 0, 0, ACallback);
end;

procedure TCrossWebSocketClientConnection._RespondClose;
begin
  if (AtomicExchange(FWsSendClose, 1) = 1) then
    Disconnect
  else
  begin
    _WsSend(WS_OP_CLOSE, True, nil, 0,
      procedure(const ASuccess: Boolean)
      begin
        Disconnect;
      end);
  end;
end;

procedure TCrossWebSocketClientConnection._RespondPong(const AData: TBytes);
begin
  _WsSend(WS_OP_PONG, True, AData);
end;

procedure TCrossWebSocketClientConnection._WebSocketRecv(var ABuf: Pointer;
  var ALen: Integer);
begin
  FWsParser.Decode(ABuf, ALen);
end;

procedure TCrossWebSocketClientConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  AData: Pointer; ACount: NativeInt; ACallback: TWsClientCallback);
var
  LWsFrameData: TBytes;
begin
  // 将数据和头打包到一起发送
  // 这是因为如果分开发送, 在多线程环境多个不同的线程数据可能会出现交叉
  // 会引起数据与头部混乱
  LWsFrameData := TCrossWebSocketParser.MakeFrameData(
    AOpCode,
    AFin,
    FWebSocket.MaskingKey,
    AData,
    ACount);

  SendBytes(LWsFrameData,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if Assigned(ACallback) then
        ACallback(ASuccess);
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
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossWebSocketClientConnection.Create(AOwner, AClientSocket, AConnectType, AConnectCb);
end;

procedure TCrossWebSocketClient.LogicDisconnected(
  const AConnection: ICrossConnection);
var
  LConnectionObj: TCrossWebSocketClientConnection;
begin
  LConnectionObj := AConnection as TCrossWebSocketClientConnection;
  if (LConnectionObj.FWebSocket <> nil) then
    LConnectionObj.FWebSocket._OnClose;

  inherited LogicDisconnected(AConnection);
end;

{ TCrossWebSocket }

function TCrossWebSocket.Close: ICrossWebSocket;
begin
  Result := Self;

  if (FStatus = wsConnected) then
    FConnection.WsClose;
end;

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

function TCrossWebSocket.GetMaskingKey: Cardinal;
begin
  Result := FMaskingKey;
end;

function TCrossWebSocket.GetStatus: TWsStatus;
begin
  Result := FStatus;
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

  FConnection := nil;

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
  LSecWebSocketKey, LSecWebSocketAccept: string;
begin
  Result := Self;

  _Lock;
  try
    if (FStatus in [wsConnecting, wsConnected]) then Exit;
    FStatus := wsConnecting;
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
      _OnOpenRequest(ARequest);
    end,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      {
        HTTP/1.1 101 Switching Protocols
        Upgrade: websocket
        Connection: Upgrade
        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
      }
      _OnOpenResponse(AResponse);
      // 连接失败
      if (AResponse = nil) then
      begin
        _OnClose;
        Exit;
      end;

      // 验证失败
      if (LSecWebSocketAccept <> AResponse.Header[HEADER_SEC_WEBSOCKET_ACCEPT]) then
      begin
        _OnClose;
        Exit;
      end;

      // 握手成功
      FConnection := AResponse.Connection as TCrossWebSocketClientConnection;
      FConnection.FWebSocket := Self;
      FConnection.FIsWebSocket := True;

      _OnOpen;
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
    FConnection.WsSend(AData, ACount, ACallback);
end;

procedure TCrossWebSocket.Send(const AData; const ACount: NativeInt;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACount, ACallback);
end;

procedure TCrossWebSocket.Send(const AData: TBytes; const AOffset,
  ACount: NativeInt; const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, AOffset, ACount, ACallback);
end;

procedure TCrossWebSocket.Send(const AData: TBytes;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback);
end;

procedure TCrossWebSocket.Send(const AData: string;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback);
end;

procedure TCrossWebSocket.Send(const AData: TWsClientChunkDataFunc;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback);
end;

procedure TCrossWebSocket.Send(const AData: TStream; const AOffset,
  ACount: Int64; const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, AOffset, ACount, ACallback);
end;

procedure TCrossWebSocket.Send(const AData: TStream;
  const ACallback: TWsClientCallback);
begin
  if (GetStatus = wsConnected) then
    FConnection.WsSend(AData, ACallback);
end;

procedure TCrossWebSocket.SetMaskingKey(const AValue: Cardinal);
begin
  FMaskingKey := AValue;
end;

procedure TCrossWebSocket._Lock;
begin
  FLock.Enter;
end;

procedure TCrossWebSocket._OnClose;
var
  LOnCloseEvents: TArray<TWsClientOnClose>;
  LOnCloseEvent: TWsClientOnClose;
begin
  if (FStatus = wsShutdown) then Exit;

  _Lock;
  try
    FStatus := wsDisconnected;
    LOnCloseEvents := FOnCloseEvents.ToArray;
  finally
    _Unlock;
  end;

  try
    for LOnCloseEvent in LOnCloseEvents do
      if Assigned(LOnCloseEvent) then
        LOnCloseEvent();
  finally
    if (FConnection <> nil) then
    begin
      FConnection.FWebSocket := nil;
      FConnection := nil;
    end;
  end;
end;

procedure TCrossWebSocket._OnMessage(const AMessageType: TWsMessageType;
  const AMessageData: TBytes);
var
  LOnMessageEvents: TArray<TWsOnMessage>;
  LOnMessageEvent: TWsOnMessage;
begin
  if (FStatus = wsShutdown) then Exit;

  _Lock;
  try
    LOnMessageEvents := FOnMessageEvents.ToArray;
  finally
    _Unlock;
  end;

  for LOnMessageEvent in LOnMessageEvents do
    if Assigned(LOnMessageEvent) then
      LOnMessageEvent(AMessageType, AMessageData);
end;

procedure TCrossWebSocket._OnOpenRequest(const ARequest: ICrossHttpClientRequest);
var
  LOnOpenRequestEvents: TArray<TWsClientOnOpenRequest>;
  LOnOpenRequestEvent: TWsClientOnOpenRequest;
begin
  if (FStatus = wsShutdown) then Exit;

  _Lock;
  try
    FStatus := wsConnected;
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
  if (FStatus = wsShutdown) then Exit;

  _Lock;
  try
    FStatus := wsConnected;
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
  LOnOpenEvents: TArray<TWsClientOnOpen>;
  LOnOpenEvent: TWsClientOnOpen;
begin
  if (FStatus = wsShutdown) then Exit;

  _Lock;
  try
    FStatus := wsConnected;
    LOnOpenEvents := FOnOpenEvents.ToArray;
  finally
    _Unlock;
  end;

  for LOnOpenEvent in LOnOpenEvents do
    if Assigned(LOnOpenEvent) then
      LOnOpenEvent();
end;

procedure TCrossWebSocket._OnPing;
var
  LOnPingEvents: TArray<TWsClientOnPing>;
  LOnPingEvent: TWsClientOnClose;
begin
  if (FStatus = wsShutdown) then Exit;

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
  if (FStatus = wsShutdown) then Exit;

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
      FWsCli := TCrossWebSocketClient.Create(Self, FIoThreads, -1, False, False);
      FWsCliArr := FWsCliArr + [FWsCli];
    end;

    Result := FWsCli;
  end else
  if TStrUtils.SameText(AProtocol, WSS) then
  begin
    if (FWssCli = nil) then
    begin
      FWssCli := TCrossWebSocketClient.Create(Self, FIoThreads, -1, True, False);
      FWsCliArr := FWsCliArr + [FWssCli];
    end;

    Result := FWssCli;
  end else
    Result := inherited CreateHttpCli(AProtocol);
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
