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

{
  The WebSocket Protocol
  https://tools.ietf.org/html/rfc6455

  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-------+-+-------------+-------------------------------+
  |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
  |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
  |N|V|V|V|       |S|             |   (if payload len==126/127)   |
  | |1|2|3|       |K|             |                               |
  +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
  |     Extended payload length continued, if payload len == 127  |
  + - - - - - - - - - - - - - - - +-------------------------------+
  |                               |Masking-key, if MASK set to 1  |
  +-------------------------------+-------------------------------+
  | Masking-key (continued)       |          Payload Data         |
  +-------------------------------- - - - - - - - - - - - - - - - +
  :                     Payload Data continued ...                :
  + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
  |                     Payload Data continued ...                |
  +---------------------------------------------------------------+
  opcode:
       *  %x0 denotes a continuation frame
       *  %x1 denotes a text frame
       *  %x2 denotes a binary frame
       *  %x3-7 are reserved for further non-control frames
       *  %x8 denotes a connection close
       *  %x9 denotes a ping
       *  %xA denotes a pong
       *  %xB-F are reserved for further control frames
  Payload length:  7 bits, 7+16 bits, or 7+64 bits
  Masking-key:  0 or 4 bytes
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  System.NetEncoding,
  System.Math,
  Net.CrossSocket.Base,
  Net.CrossHttpServer;

const
  WS_OP_CONTINUATION = $00;
  WS_OP_TEXT         = $01;
  WS_OP_BINARY       = $02;
  WS_OP_CLOSE        = $08;
  WS_OP_PING         = $09;
  WS_OP_PONG         = $0A;

  WS_MAGIC_STR = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

type
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
    procedure WsSend(const AData; ACount: NativeInt; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

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
    procedure WsSend(const AData: TBytes; AOffset, ACount: NativeInt; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="AData">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure WsSend(const AData: TBytes; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

    /// <summary>
    ///   发送字符串数据
    /// </summary>
    /// <param name="AData">
    ///   字符串数据
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    procedure WsSend(const AData: string; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

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
    procedure WsSend(const AData: TFunc<PPointer, PNativeInt, Boolean>; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

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
    procedure WsSend(const AData: TStream; const AOffset, ACount: Int64; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

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
    procedure WsSend(const AData: TStream; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
  end;

  TWsRequestType = (wsrtUnknown, wsrtText, wsrtBinary);
  TWsOnOpen = TProc<ICrossWebSocketConnection>;
  TWsOnMessage = reference to procedure(AConnection: ICrossWebSocketConnection;
    ARequestType: TWsRequestType; const ARequestData: TBytes);
  TWsOnClose = TProc<ICrossWebSocketConnection>;

  /// <summary>
  ///   跨平台WebSocket服务器
  /// </summary>
  ICrossWebSocketServer = interface(ICrossHttpServer)
  ['{FF008E22-9938-4DC4-9421-083DA9EFFCDC}']
    /// <summary>
    ///   WebSocket连接建立时触发
    /// </summary>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    function OnOpen(ACallback: TWsOnOpen): ICrossWebSocketServer;

    /// <summary>
    ///   收到WebSocket消息时触发
    /// </summary>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    function OnMessage(ACallback: TWsOnMessage): ICrossWebSocketServer;

    /// <summary>
    ///   WebSocket连接关闭时触发
    /// </summary>
    /// <param name="ACallback">
    ///   hui'diaohanshu
    /// </param>
    function OnClose(ACallback: TWsOnClose): ICrossWebSocketServer;
  end;

  TCrossWebSocketConnection = class(TCrossHttpConnection, ICrossWebSocketConnection)
  private type
    TWsFrameParseState = (wsHeader, wsBody, wsDone);
  private
    FIsWebSocket: Boolean;
    FWsFrameState: TWsFrameParseState;
    FWsFrameHeader, FWsRequestBody: TBytesStream;
    FWsFIN: Boolean;
    FWsOpCode: Byte;
    FWsMask: Boolean;
    FWsMaskKey: Cardinal;
    FWsMaskKeyShift: Integer;
    FWsPayload: Byte;
    FWsHeaderSize: Byte;
    FWsBodySize: UInt64;
    FWsSendClose: Integer;

    procedure _WebSocketRecv(ABuf: Pointer; ALen: Integer);
    procedure _ResetFrameHeader;
    procedure _ResetRequest;

    procedure _AdjustOffsetCount(const ABodySize: NativeInt; var AOffset, ACount: NativeInt); overload;
    procedure _AdjustOffsetCount(const ABodySize: Int64; var AOffset, ACount: Int64); overload;

    {$region '内部发送方法'}
    procedure _WsSend(AOpCode: Byte; AFin: Boolean; AData: Pointer; ACount: NativeInt;
      ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes; AOffset, ACount: NativeInt;
      ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

    procedure _WsSend(AOpCode: Byte; AFin: Boolean; const AData: TBytes;
      ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
    {$endregion}

    procedure _RespondPong(const AData: TBytes);
    procedure _RespondClose;

    function _OpCodeToReqType(AOpCode: Byte): TWsRequestType;
  protected
    procedure TriggerWsRequest(ARequestType: TWsRequestType;
      const ARequestData: TBytes); virtual;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); override;
    destructor Destroy; override;

    class function _MakeFrameHeader(AOpCode: Byte; AFin: Boolean; AMaskKey: Cardinal; ADataSize: UInt64): TBytes; static;

    function IsWebSocket: Boolean;
    procedure WsClose;

    procedure WsSend(const AData; ACount: NativeInt; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
    procedure WsSend(const AData: TBytes; AOffset, ACount: NativeInt; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
    procedure WsSend(const AData: TBytes; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
    procedure WsSend(const AData: string; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;

    procedure WsSend(const AData: TFunc<PPointer, PNativeInt, Boolean>; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
    procedure WsSend(const AData: TStream; const AOffset, ACount: Int64; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
    procedure WsSend(const AData: TStream; ACallback: TProc<ICrossWebSocketConnection, Boolean> = nil); overload;
  end;

  TNetCrossWebSocketServer = class(TCrossHttpServer, ICrossWebSocketServer)
  private
    FOnOpen: TWsOnOpen;
    FOnMessage: TWsOnMessage;
    FOnClose: TWsOnClose;

    procedure _WebSocketHandshake(AConnection: ICrossWebSocketConnection;
      ACallback: TProc<ICrossWebSocketConnection, Boolean>);

    procedure _OnOpen(AConnection: ICrossWebSocketConnection);
    procedure _OnMessage(AConnection: ICrossWebSocketConnection;
      ARequestType: TWsRequestType; const ARequestData: TBytes);
    procedure _OnClose(AConnection: ICrossWebSocketConnection);
  protected
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; override;
    procedure LogicReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); override;
    procedure LogicDisconnected(AConnection: ICrossConnection); override;

    procedure DoOnRequest(AConnection: ICrossHttpConnection); override;

    procedure TriggerWsRequest(AConnection: ICrossWebSocketConnection;
      ARequestType: TWsRequestType; const ARequestData: TBytes); virtual;
  public
    function OnOpen(ACallback: TWsOnOpen): ICrossWebSocketServer;
    function OnMessage(ACallback: TWsOnMessage): ICrossWebSocketServer;
    function OnClose(ACallback: TWsOnClose): ICrossWebSocketServer;
  end;

implementation

{ TCrossWebSocketConnection }

constructor TCrossWebSocketConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited;

  FWsFrameHeader := TBytesStream.Create(nil);
  FWsRequestBody := TBytesStream.Create(nil);
  _ResetRequest;
end;

destructor TCrossWebSocketConnection.Destroy;
begin
  FreeAndNil(FWsFrameHeader);
  FreeAndNil(FWsRequestBody);
  inherited;
end;

function TCrossWebSocketConnection.IsWebSocket: Boolean;
begin
  Result := FIsWebSocket;
end;

procedure TCrossWebSocketConnection.TriggerWsRequest(
  ARequestType: TWsRequestType; const ARequestData: TBytes);
begin
  TNetCrossWebSocketServer(Owner).TriggerWsRequest(Self, ARequestType, ARequestData);
end;

procedure TCrossWebSocketConnection.WsSend(const AData; ACount: NativeInt;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  _WsSend(WS_OP_BINARY, True, @AData, ACount, ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TBytes; AOffset,
  ACount: NativeInt; ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  _WsSend(WS_OP_BINARY, True, AData, AOffset, ACount, ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TBytes;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  WsSend(AData, 0, Length(AData), ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: string;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  _WsSend(WS_OP_TEXT, True, TEncoding.UTF8.GetBytes(AData), ACallback);
end;

procedure TCrossWebSocketConnection.WsSend(
  const AData: TFunc<PPointer, PNativeInt, Boolean>;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
var
  LConnection: ICrossWebSocketConnection;
  LOpCode: Byte;
  LSender: TProc<ICrossWebSocketConnection, Boolean>;
begin
  LConnection := Self;
  LOpCode := WS_OP_BINARY;

  LSender :=
    procedure(AConnection: ICrossWebSocketConnection; ASuccess: Boolean)
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
        TCrossWebSocketConnection(AConnection)._WsSend(LOpCode,
          True, nil, 0,
          procedure(AConnection: ICrossWebSocketConnection; ASuccess: Boolean)
          begin
            if Assigned(ACallback) then
              ACallback(AConnection, ASuccess);
          end);

        Exit;
      end;

      // 第一帧及中间帧
      // 第一帧 opcode 为 WS_OP_BINARY, FIN 为 0
      // 中间帧 opcode 为 WS_OP_CONTINUATION, FIN 为 0
      TCrossWebSocketConnection(AConnection)._WsSend(LOpCode,
        False, LData, LCount, LSender);

      LOpCode := WS_OP_CONTINUATION;
    end;

  LSender(LConnection, True);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TStream; const AOffset,
  ACount: Int64; ACallback: TProc<ICrossWebSocketConnection, Boolean>);
var
  LOffset, LCount: Int64;
  LBody: TStream;
  LBuffer: TBytes;
begin
  LOffset := AOffset;
  LCount := ACount;
  _AdjustOffsetCount(AData.Size, LOffset, LCount);

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
    function(AData: PPointer; ACount: PNativeInt): Boolean
    begin
      if (LCount <= 0) then Exit(False);

      AData^ := @LBuffer[0];
      ACount^ := LBody.Read(LBuffer[0], Min(LCount, SND_BUF_SIZE));

      Result := (ACount^ > 0);

      if Result then
        Dec(LCount, ACount^);
    end,
    // CALLBACK
    procedure(AConnection: ICrossWebSocketConnection; ASuccess: Boolean)
    begin
      LBuffer := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection.WsSend(const AData: TStream;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  WsSend(AData, 0, 0, ACallback);
end;

procedure TCrossWebSocketConnection.WsClose;
begin
  if (AtomicExchange(FWsSendClose, 1) = 1) then Exit;

  _WsSend(WS_OP_CLOSE, True, nil, 0);
end;

procedure TCrossWebSocketConnection._ResetRequest;
begin
  FWsFrameState := wsHeader;
  FWsFrameHeader.Clear;
  FWsRequestBody.Clear;
  FWsMaskKeyShift := 0;
end;

procedure TCrossWebSocketConnection._AdjustOffsetCount(
  const ABodySize: NativeInt; var AOffset, ACount: NativeInt);
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

procedure TCrossWebSocketConnection._AdjustOffsetCount(const ABodySize: Int64;
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

class function TCrossWebSocketConnection._MakeFrameHeader(AOpCode: Byte;
  AFin: Boolean; AMaskKey: Cardinal; ADataSize: UInt64): TBytes;
var
  LPayload: Byte;
  LHeaderSize: Integer;
begin
  LHeaderSize := 2;
  if (ADataSize < 126) then
    LPayload := ADataSize
  else if (ADataSize <= $FFFF) then
  begin
    LPayload := 126;
    Inc(LHeaderSize, 2);
  end else
  begin
    LPayload := 127;
    Inc(LHeaderSize, 8);
  end;
  if (AMaskKey <> 0) then
    Inc(LHeaderSize, 4);

  SetLength(Result, LHeaderSize);
  FillChar(Result[0], LHeaderSize, 0);

  if AFin then
    Result[0] := Result[0] or $80;
  Result[0] := Result[0] or (AOpCode and $0F);

  if (AMaskKey <> 0) then
    Result[1] := Result[1] or $80;
  Result[1] := Result[1] or (LPayload and $7F);

  if (LPayload = 126) then
  begin
    Result[2] := PByte(@ADataSize)[1];
    Result[3] := PByte(@ADataSize)[0];
  end else
  if (LPayload = 127) then
  begin
    Result[2] := PByte(@ADataSize)[7];
    Result[3] := PByte(@ADataSize)[6];
    Result[4] := PByte(@ADataSize)[5];
    Result[5] := PByte(@ADataSize)[4];
    Result[6] := PByte(@ADataSize)[3];
    Result[7] := PByte(@ADataSize)[2];
    Result[8] := PByte(@ADataSize)[1];
    Result[9] := PByte(@ADataSize)[0];
  end;

  if (AMaskKey <> 0) then
    Move(AMaskKey, Result[LHeaderSize - 4], 4);
end;

function TCrossWebSocketConnection._OpCodeToReqType(
  AOpCode: Byte): TWsRequestType;
begin
  case AOpCode of
    WS_OP_TEXT: Exit(wsrtText);
    WS_OP_BINARY: Exit(wsrtBinary);
  else
    Exit(wsrtUnknown);
  end;
end;

procedure TCrossWebSocketConnection._ResetFrameHeader;
begin
  FWsFrameState := wsHeader;
  FWsFrameHeader.Clear;
  FWsMaskKeyShift := 0;
end;

procedure TCrossWebSocketConnection._WebSocketRecv(ABuf: Pointer;
  ALen: Integer);
var
  PBuf: PByte;
  LByte: Byte;
  LReqData: TBytes;
begin
  PBuf := ABuf;
  while (ALen > 0) do
  begin
    case FWsFrameState of
      wsHeader:
        begin
          FWsFrameHeader.Write(PBuf^, 1);
          Dec(ALen);
          Inc(PBuf);

          if (FWsFrameHeader.Size = 2) then
          begin
            // 第1个字节最高位为 FIN 状态
            FWsFIN := (FWsFrameHeader.Bytes[0] and $80 <> 0);

            // 第1个字节低4位为 opcode 状态
            LByte := FWsFrameHeader.Bytes[0] and $0F;
            if (LByte <> WS_OP_CONTINUATION) then
              FWsOpCode := LByte;

            // 第2个字节最高位为 MASK 状态
            FWsMask := (FWsFrameHeader.Bytes[1] and $80 <> 0);

            // 第2个字节低7位为 payload len
            FWsPayload := FWsFrameHeader.Bytes[1] and $7F;

            FWsHeaderSize := 2;
            if (FWsPayload < 126) then
              FWsBodySize := FWsPayload
            else if (FWsPayload = 126) then
              Inc(FWsHeaderSize, 2)
            else if (FWsPayload = 127) then
              Inc(FWsHeaderSize, 8);
            if FWsMask then
              Inc(FWsHeaderSize, 4);
          end else
          if (FWsFrameHeader.Size = FWsHeaderSize) then
          begin
            FWsFrameState := wsBody;

            // 保存 mask key
            if FWsMask then
              Move(PCardinal(UIntPtr(FWsFrameHeader.Memory) + FWsHeaderSize - 4)^, FWsMaskKey, 4);

            if (FWsPayload = 126) then
              FWsBodySize := FWsFrameHeader.Bytes[3]
                + Word(FWsFrameHeader.Bytes[2]) shl 8
            else if (FWsPayload = 127) then
              FWsBodySize := FWsFrameHeader.Bytes[9]
                + UInt64(FWsFrameHeader.Bytes[8]) shl 8
                + UInt64(FWsFrameHeader.Bytes[7]) shl 16
                + UInt64(FWsFrameHeader.Bytes[6]) shl 24
                + UInt64(FWsFrameHeader.Bytes[5]) shl 32
                + UInt64(FWsFrameHeader.Bytes[4]) shl 40
                + UInt64(FWsFrameHeader.Bytes[3]) shl 48
                + UInt64(FWsFrameHeader.Bytes[2]) shl 56
                ;

            // 接收完一帧
            if (FWsBodySize <= 0) then
            begin
              // 如果这是一个独立帧或者连续帧的最后一帧
              // 则表示一次请求数据接收完成
              if FWsFIN then
                FWsFrameState := wsDone
              // 否则继续接收下一帧
              else
                _ResetFrameHeader;
            end;
          end;
        end;

      wsBody:
        begin
          LByte := PBuf^;
          // 如果 MASK 状态为 1, 则将收到的数据与 mask key 做异或处理
          if FWsMask then
          begin
            LByte := LByte xor PByte(@FWsMaskKey)[FWsMaskKeyShift];
            FWsMaskKeyShift := (FWsMaskKeyShift + 1) mod 4;
          end;
          FWsRequestBody.Write(LByte, 1);
          Dec(ALen);
          Inc(PBuf);
          Dec(FWsBodySize);

          // 接收完一帧
          if (FWsBodySize <= 0) then
          begin
            // 如果这是一个独立帧或者连续帧的最后一帧
            // 则表示一次请求数据接收完成
            if FWsFIN then
              FWsFrameState := wsDone
            // 否则继续接收下一帧
            else
              _ResetFrameHeader;
          end;
        end;
    end;
  end;

  // 一个完整的WebSocket数据帧接收完毕
  if (FWsFrameState = wsDone) then
  begin
    case FWsOpCode of
      WS_OP_CLOSE:
        begin
          // 关闭帧
          // 收到关闭帧, 如果已经发送关闭帧, 直接关闭连接
          // 否则, 需要发送关闭帧, 发送完成之后关闭连接
          _RespondClose;
          Exit;
        end;

      WS_OP_PING:
        begin
          // pong 帧必须将 ping 帧发来的数据原封不动地返回
          LReqData := FWsRequestBody.Bytes;
          SetLength(LReqData, FWsRequestBody.Size);
          _RespondPong(LReqData);
        end;

      WS_OP_TEXT, WS_OP_BINARY:
        begin
          // 收到请求数据
          LReqData := FWsRequestBody.Bytes;
          SetLength(LReqData, FWsRequestBody.Size);
          TriggerWsRequest(_OpCodeToReqType(FWsOpCode), LReqData);
        end;
    end;

    _ResetRequest;
  end;

  // 处理粘包
  if (ALen > 0) then
    _WebSocketRecv(PBuf, ALen);
end;

procedure TCrossWebSocketConnection._RespondClose;
begin
  if (AtomicExchange(FWsSendClose, 1) = 1) then
    Disconnect
  else
  begin
    _WsSend(WS_OP_CLOSE, True, nil, 0,
      procedure(AConnection: ICrossWebSocketConnection; ASuccess: Boolean)
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
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
var
  LWsFrameHeader: TBytes;
begin
  LWsFrameHeader := _MakeFrameHeader(AOpCode, AFin, 0, ACount);
  inherited SendBytes(LWsFrameHeader,
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      if not ASuccess then
      begin
        if Assigned(ACallback) then
          ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
        Exit;
      end;

      if (AData = nil) or (ACount <= 0) then
      begin
        if Assigned(ACallback) then
          ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
        Exit;
      end;

      inherited SendBuf(AData^, ACount,
        procedure(AConnection: ICrossConnection; ASuccess: Boolean)
        begin
          if Assigned(ACallback) then
            ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
        end);
    end);
end;

procedure TCrossWebSocketConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  const AData: TBytes; AOffset, ACount: NativeInt;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
var
  LData: TBytes;
  LOffset, LCount: NativeInt;
begin
  LData := AData;
  LOffset := AOffset;
  LCount := ACount;
  _AdjustOffsetCount(Length(AData), LOffset, LCount);

  _WsSend(AOpCode, AFin, @LData[LOffset], LCount,
    procedure(AConnection: ICrossWebSocketConnection; ASuccess: Boolean)
    begin
      LData := nil;
      if Assigned(ACallback) then
        ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
    end);
end;

procedure TCrossWebSocketConnection._WsSend(AOpCode: Byte; AFin: Boolean;
  const AData: TBytes; ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  _WsSend(AOpCode, AFin, AData, 0, Length(AData), ACallback);
end;

{ TNetCrossWebSocketServer }

procedure TNetCrossWebSocketServer.LogicDisconnected(
  AConnection: ICrossConnection);
var
  LConnection: ICrossWebSocketConnection;
begin
  LConnection := AConnection as ICrossWebSocketConnection;
  if LConnection.IsWebSocket then
    _OnClose(LConnection)
  else
    inherited;
end;

procedure TNetCrossWebSocketServer.LogicReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
var
  LConnection: ICrossWebSocketConnection;
begin
  LConnection := AConnection as ICrossWebSocketConnection;
  if LConnection.IsWebSocket then
    TCrossWebSocketConnection(LConnection)._WebSocketRecv(ABuf, ALen)
  else
    inherited;
end;

function TNetCrossWebSocketServer.OnClose(ACallback: TWsOnClose): ICrossWebSocketServer;
begin
  FOnClose := ACallback;
  Result := Self;
end;

function TNetCrossWebSocketServer.OnMessage(ACallback: TWsOnMessage): ICrossWebSocketServer;
begin
  FOnMessage := ACallback;
  Result := Self;
end;

function TNetCrossWebSocketServer.OnOpen(ACallback: TWsOnOpen): ICrossWebSocketServer;
begin
  FOnOpen := ACallback;
  Result := Self;
end;

procedure TNetCrossWebSocketServer.TriggerWsRequest(
  AConnection: ICrossWebSocketConnection; ARequestType: TWsRequestType;
  const ARequestData: TBytes);
begin
  _OnMessage(AConnection, ARequestType, ARequestData);
end;

procedure TNetCrossWebSocketServer._OnClose(
  AConnection: ICrossWebSocketConnection);
begin
  if Assigned(FOnClose) then
    FOnClose(AConnection);
end;

procedure TNetCrossWebSocketServer._OnMessage(
  AConnection: ICrossWebSocketConnection; ARequestType: TWsRequestType;
  const ARequestData: TBytes);
begin
  if Assigned(FOnMessage) then
    FOnMessage(AConnection, ARequestType, ARequestData);
end;

procedure TNetCrossWebSocketServer._OnOpen(
  AConnection: ICrossWebSocketConnection);
begin
  if Assigned(FOnOpen) then
    FOnOpen(AConnection);
end;

procedure TNetCrossWebSocketServer._WebSocketHandshake(
  AConnection: ICrossWebSocketConnection;
  ACallback: TProc<ICrossWebSocketConnection, Boolean>);
begin
  AConnection.Response.Header['Upgrade'] := 'websocket';
  AConnection.Response.Header['Connection'] := 'Upgrade';
  AConnection.Response.Header['Sec-WebSocket-Accept'] :=
    TNetEncoding.Base64.EncodeBytesToString(
      THashSHA1.GetHashBytes(
        AConnection.Request.Header['Sec-WebSocket-Key'] + WS_MAGIC_STR
      )
    );
  AConnection.Response.SendStatus(101, '',
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      ACallback(AConnection as ICrossWebSocketConnection, ASuccess);
    end);
end;

function TNetCrossWebSocketServer.CreateConnection(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType): ICrossConnection;
begin
  Result := TCrossWebSocketConnection.Create(AOwner, AClientSocket, AConnectType);
end;

procedure TNetCrossWebSocketServer.DoOnRequest(
  AConnection: ICrossHttpConnection);
var
  LConnection: ICrossWebSocketConnection;
begin
  LConnection := AConnection as ICrossWebSocketConnection;
  if SameText(AConnection.Request.Header['Connection'], 'Upgrade')
    and SameText(AConnection.Request.Header['Upgrade'], 'websocket') then
  begin
    TCrossWebSocketConnection(LConnection).FIsWebSocket := True;
    _WebSocketHandshake(LConnection,
      procedure(AConnection: ICrossWebSocketConnection; ASuccess: Boolean)
      begin
        if ASuccess then
          _OnOpen(AConnection);
      end);
  end else
    inherited;
end;

end.
