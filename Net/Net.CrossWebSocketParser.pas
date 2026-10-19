{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossWebSocketParser;

{$I zLib.inc}

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
  SysUtils,
  Classes,

  Net.CrossSocket.Base,

  Utils.Hash,
  Utils.Base64,
  Utils.Utils,
  Utils.CryptRandom;

const
  WS_OP_CONTINUATION = $00;
  WS_OP_TEXT         = $01;
  WS_OP_BINARY       = $02;
  WS_OP_CLOSE        = $08;
  WS_OP_PING         = $09;
  WS_OP_PONG         = $0A;

  WS_MAGIC_STR       = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

type
  TWsMessageType = (wtUnknown, wtText, wtBinary);
  TWsFrameParseState = (wsHeader, wsBody, wsDone);

  TWsOnCommand = reference to procedure(const AOpCode: Byte; const AData: TBytes);
  TWsOnMessage = reference to procedure(const AType: TWsMessageType; const AData: TBytes);
  TWsOnFailed = reference to procedure;

  TWsParserRole = (wprAny, wprClient, wprServer);

  TCrossWebSocketParser = class
  private
    FWsFrameState: TWsFrameParseState;
    FHeader: array[0..13] of Byte;
    FHeaderRead, FHeaderNeeded: Integer;
    FHeaderDecoded: Boolean;
    FFrameOpCode, FFramePayload: Byte;
    FFrameFIN, FFrameMasked: Boolean;
    FFrameRemaining: UInt64;
    FMaskKey: array[0..3] of Byte;
    FMaskOffset: Integer;
    FWsMessageBody: TMemoryStream;
    FMessageActive: Boolean;
    FMessageOpCode: Byte;
    FMessageStartedAt: UInt64;
    FControlData: TBytes;
    FControlWritten: Integer;
    FStopped: Boolean;
    FErrorCode: Word;
    FRole: TWsParserRole;
    FAllowedRsvBits: Byte;
    FCheckTextUtf8: Boolean;
    FMaxMessageSize: UInt64;
    FMessageTimeoutMs: Cardinal;
    FOnCommand: TWsOnCommand;
    FOnMessage: TWsOnMessage;
    FWsOnFailed: TWsOnFailed;

    procedure _ResetFrameHeader;
    procedure _ResetRequest;
    function _Fail(const ACode: Word): Boolean;
    function _ReadBaseHeader: Boolean;
    function _ReadFullHeader: Boolean;
    procedure _ReadBody(const AData: PByte; const ACount: Integer); inline;
    procedure _FrameEnd;
    procedure _FinishFrame(var ABuf: Pointer; var ALen: Integer);
    procedure _DecodeFrames(var ABuf: Pointer; var ALen: Integer);
    class function _IsValidUtf8(AData: PByte; ACount: NativeInt): Boolean; static;
  protected
    procedure TriggerCommand(const AOpCode: Byte; const AData: TBytes);
    procedure TriggerMessage(const AType: TWsMessageType; const AData: TBytes);
    procedure TriggerFailed;
    function IsValidOpCode(const AOpCode: Byte): Boolean; virtual;
    function IsValidBodySize(const ABodySize: UInt64): Boolean; virtual;
    function IsValidCloseCode(const ACode: Word): Boolean; virtual;
  public
    constructor Create(const AOnCommand: TWsOnCommand;
      const AOnMessage: TWsOnMessage; const AWsOnFailed: TWsOnFailed);
    destructor Destroy; override;
    procedure Decode(var ABuf: Pointer; var ALen: Integer);
    // 外部取消不触发协议失败回调。
    procedure Stop;
    // 与 Decode 串行调用；启用期限后，静默连接也需要外部定期检查。
    procedure CheckTimeout;
    class function TickCount: UInt64; static;
    class function OpCodeToReqType(AOpCode: Byte): TWsMessageType; static;
    // 客户端每帧生成新的随机掩码；服务端不加掩码。
    class function MakeFrameData(AOpCode: Byte; AFin, AIsServer: Boolean;
      AData: Pointer; ADataSize: UInt64): TBytes; static;
    class function NewSecWebSocketKey: string; static;
    class function IsValidSecWebSocketKey(const AKey: string): Boolean; static;
    class function IsValidHttpVersion(const AVersion: string): Boolean; static;
    class function MakeSecWebSocketAccept(const ASecWebSocketKey: string): string; static;

    // 开始接收前配置。独立解析器默认保留原有掩码、扩展及文本策略；
    // 标准客户端/服务端显式开启严格校验。允许 RSV 不代表已经实现扩展解码。
    property Role: TWsParserRole read FRole write FRole;
    property AllowedRsvBits: Byte read FAllowedRsvBits write FAllowedRsvBits;
    property CheckTextUtf8: Boolean read FCheckTextUtf8 write FCheckTextUtf8;
    // 0 不增加应用限制，仍检查平台容量及整数溢出。
    property MaxMessageSize: UInt64 read FMaxMessageSize write FMaxMessageSize;
    property MessageTimeoutMs: Cardinal read FMessageTimeoutMs write FMessageTimeoutMs;
    property Stopped: Boolean read FStopped;
    property ErrorCode: Word read FErrorCode;
  end;

{$IFDEF CROSS_WS_SENDER_SELFTEST}
var
  // 仅专项测试模拟随机源返回失败，正式构建不包含该入口。
  CrossWebSocketMaskFailureForTest: Boolean;
{$ENDIF}

implementation

constructor TCrossWebSocketParser.Create(const AOnCommand: TWsOnCommand;
  const AOnMessage: TWsOnMessage; const AWsOnFailed: TWsOnFailed);
begin
  inherited Create;
  FOnCommand := AOnCommand;
  FOnMessage := AOnMessage;
  FWsOnFailed := AWsOnFailed;
  FRole := wprAny;
  FAllowedRsvBits := $70;
  FWsMessageBody := TMemoryStream.Create;
  _ResetRequest;
end;

destructor TCrossWebSocketParser.Destroy;
begin
  FControlData := nil;
  FreeAndNil(FWsMessageBody);
  inherited;
end;

class function TCrossWebSocketParser.TickCount: UInt64;
begin
  {$IFDEF FPC}
  Result := GetTickCount64;
  {$ELSE}
  Result := TThread.GetTickCount64;
  {$ENDIF}
end;

procedure TCrossWebSocketParser._ResetFrameHeader;
begin
  FWsFrameState := wsHeader;
  FHeaderRead := 0;
  FHeaderNeeded := 2;
  FHeaderDecoded := False;
  FFrameRemaining := 0;
  FMaskOffset := 0;
  FControlWritten := 0;
end;

procedure TCrossWebSocketParser._ResetRequest;
begin
  FWsMessageBody.Clear;
  FControlData := nil;
  FMessageActive := False;
  FMessageOpCode := WS_OP_CONTINUATION;
  FMessageStartedAt := 0;
  _ResetFrameHeader;
end;

procedure TCrossWebSocketParser.Stop;
begin
  if FStopped then Exit;
  FStopped := True;
  _ResetRequest;
end;

function TCrossWebSocketParser._Fail(const ACode: Word): Boolean;
begin
  Result := False;
  if FStopped then Exit;
  FErrorCode := ACode;
  Stop;
  TriggerFailed;
end;

procedure TCrossWebSocketParser.CheckTimeout;
begin
  if FStopped or not FMessageActive or (FMessageTimeoutMs = 0) then Exit;
  if TickCount - FMessageStartedAt >= UInt64(FMessageTimeoutMs) then
    _Fail(1008);
end;

function TCrossWebSocketParser.IsValidBodySize(const ABodySize: UInt64): Boolean;
begin
  Result := ABodySize < High(Cardinal);
end;

function TCrossWebSocketParser.IsValidOpCode(const AOpCode: Byte): Boolean;
begin
  case AOpCode of
    WS_OP_CONTINUATION, WS_OP_TEXT, WS_OP_BINARY, WS_OP_CLOSE, WS_OP_PING, WS_OP_PONG:
      Result := True;
  else
    Result := False;
  end;
end;

function TCrossWebSocketParser.IsValidCloseCode(const ACode: Word): Boolean;
begin
  Result := ((ACode >= 1000) and (ACode <= 1014))
    or ((ACode >= 3000) and (ACode <= 4999));
  if (ACode = 1004) or (ACode = 1005) or (ACode = 1006) then
    Result := False;
  // 独立解析器保留扩展状态码；严格端点的扩展可覆写本方法。
  if (FRole = wprAny) and (ACode >= 2000) and (ACode <= 2999) then
    Result := True;
end;

function TCrossWebSocketParser._ReadBaseHeader: Boolean;
var
  LCheckOpCode: Byte;
begin
  FFrameFIN := (FHeader[0] and $80) <> 0;
  FFrameOpCode := FHeader[0] and $0F;
  FFrameMasked := (FHeader[1] and $80) <> 0;
  FFramePayload := FHeader[1] and $7F;
  if (FHeader[0] and $70 and not FAllowedRsvBits) <> 0 then
    Exit(_Fail(1002));
  case FRole of
    wprClient: if FFrameMasked then Exit(_Fail(1002));
    wprServer: if not FFrameMasked then Exit(_Fail(1002));
  end;
  if FFrameOpCode >= WS_OP_CLOSE then
  begin
    if not FFrameFIN or (FFramePayload > 125) then Exit(_Fail(1002));
    LCheckOpCode := FFrameOpCode;
  end else
  if FFrameOpCode = WS_OP_CONTINUATION then
  begin
    if not FMessageActive then Exit(_Fail(1002));
    // 保留旧虚方法语义，连续帧传所属消息的 opcode。
    LCheckOpCode := FMessageOpCode;
  end else
  begin
    if FMessageActive then Exit(_Fail(1002));
    LCheckOpCode := FFrameOpCode;
  end;
  if not IsValidOpCode(LCheckOpCode) then Exit(_Fail(1002));
  if (FFrameOpCode <> WS_OP_CONTINUATION) and (FFrameOpCode < WS_OP_CLOSE) then
  begin
    FMessageActive := True;
    FMessageOpCode := FFrameOpCode;
    if FMessageTimeoutMs <> 0 then FMessageStartedAt := TickCount;
  end;
  FHeaderNeeded := 2;
  case FFramePayload of
    126: Inc(FHeaderNeeded, 2);
    127: Inc(FHeaderNeeded, 8);
  end;
  if FFrameMasked then Inc(FHeaderNeeded, 4);
  Result := True;
end;

function TCrossWebSocketParser._ReadFullHeader: Boolean;
var
  LSize, LCurrentSize: UInt64;
  I: Integer;
begin
  if FFramePayload < 126 then
    LSize := FFramePayload
  else
  if FFramePayload = 126 then
  begin
    LSize := (UInt64(FHeader[2]) shl 8) or FHeader[3];
    if LSize < 126 then Exit(_Fail(1002));
  end else
  begin
    if (FHeader[2] and $80) <> 0 then Exit(_Fail(1002));
    LSize := 0;
    for I := 2 to 9 do LSize := (LSize shl 8) or FHeader[I];
    if LSize <= $FFFF then Exit(_Fail(1002));
  end;
  // 仍然按单帧调用，不改变现有子类的大小策略。
  if not IsValidBodySize(LSize) then Exit(_Fail(1009));
  if FFrameMasked then
    Move(FHeader[FHeaderNeeded - 4], FMaskKey[0], SizeOf(FMaskKey));
  FMaskOffset := 0;
  FFrameRemaining := LSize;
  if FFrameOpCode >= WS_OP_CLOSE then
  begin
    if LSize > 125 then Exit(_Fail(1002));
    if (FFrameOpCode = WS_OP_CLOSE) and (LSize = 1) then Exit(_Fail(1002));
    SetLength(FControlData, NativeInt(LSize));
    FControlWritten := 0;
  end else
  begin
    LCurrentSize := UInt64(FWsMessageBody.Size);
    if LCurrentSize > UInt64(High(NativeInt)) then Exit(_Fail(1009));
    if LSize > UInt64(High(NativeInt)) - LCurrentSize then Exit(_Fail(1009));
    if FMaxMessageSize <> 0 then
    begin
      if LCurrentSize > FMaxMessageSize then Exit(_Fail(1009));
      if LSize > FMaxMessageSize - LCurrentSize then Exit(_Fail(1009));
    end;
  end;
  FWsFrameState := wsBody;
  Result := True;
end;

procedure TCrossWebSocketParser._ReadBody(const AData: PByte; const ACount: Integer);
var
  LTarget: PByte;
  LByte: Byte;
  LPosition: NativeInt;
  LOffset, I: Integer;
begin
  if not FFrameMasked then
  begin
    if FFrameOpCode >= WS_OP_CLOSE then
    begin
      Move(AData^, FControlData[FControlWritten], ACount);
      Inc(FControlWritten, ACount);
    end else
      FWsMessageBody.Write(AData^, ACount);
    Exit;
  end;
  // 单字节拆包直接解码到局部变量，避免写流后再回读目标位置。
  if ACount = 1 then
  begin
    LByte := AData^ xor FMaskKey[FMaskOffset];
    if FFrameOpCode >= WS_OP_CLOSE then
    begin
      FControlData[FControlWritten] := LByte;
      Inc(FControlWritten);
    end else
      FWsMessageBody.Write(LByte, 1);
    // 写入成功后再推进，分配失败时输入和掩码位置保持一致。
    FMaskOffset := (FMaskOffset + 1) and 3;
    Exit;
  end;
  if FFrameOpCode >= WS_OP_CLOSE then
  begin
    LTarget := @FControlData[FControlWritten];
    Move(AData^, LTarget^, ACount);
    Inc(FControlWritten, ACount);
  end else
  begin
    LPosition := NativeInt(FWsMessageBody.Position);
    FWsMessageBody.Write(AData^, ACount);
    // TMemoryStream.Write 完整写入或抛异常；可能扩容，之后再取指针。
    LTarget := PByte(FWsMessageBody.Memory) + LPosition;
  end;
  if FFrameMasked then
  begin
    LOffset := FMaskOffset;
    for I := 0 to ACount - 1 do
    begin
      LTarget[I] := LTarget[I] xor FMaskKey[LOffset];
      LOffset := (LOffset + 1) and 3;
    end;
    FMaskOffset := LOffset;
  end;
end;

class function TCrossWebSocketParser._IsValidUtf8(AData: PByte; ACount: NativeInt): Boolean;
var
  LByte, LMin, LMax: Byte;
  LRemaining: Integer;
begin
  Result := False;
  LRemaining := 0;
  LMin := $80;
  LMax := $BF;
  while ACount > 0 do
  begin
    LByte := AData^;
    Inc(AData);
    Dec(ACount);
    if LRemaining > 0 then
    begin
      if (LByte < LMin) or (LByte > LMax) then Exit;
      Dec(LRemaining);
      LMin := $80;
      LMax := $BF;
      Continue;
    end;
    if LByte < $80 then Continue;
    LMin := $80;
    LMax := $BF;
    case LByte of
      $C2..$DF: LRemaining := 1;
      $E0: begin LRemaining := 2; LMin := $A0; end;
      $E1..$EC, $EE..$EF: LRemaining := 2;
      $ED: begin LRemaining := 2; LMax := $9F; end;
      $F0: begin LRemaining := 3; LMin := $90; end;
      $F1..$F3: LRemaining := 3;
      $F4: begin LRemaining := 3; LMax := $8F; end;
    else
      Exit;
    end;
  end;
  Result := LRemaining = 0;
end;

procedure TCrossWebSocketParser._FrameEnd;
var
  LData: TBytes;
  LOpCode: Byte;
  LSize: NativeInt;
  LCloseCode: Word;
begin
  if FMessageTimeoutMs <> 0 then
  begin
    CheckTimeout;
    if FStopped then Exit;
  end;
  LOpCode := FFrameOpCode;
  if LOpCode >= WS_OP_CLOSE then
  begin
    LData := FControlData;
    FControlData := nil;
    _ResetFrameHeader;
    if LOpCode = WS_OP_CLOSE then
    begin
      try
        if Length(LData) > 0 then
        begin
          if Length(LData) < 2 then begin _Fail(1002); Exit; end;
          LCloseCode := (Word(LData[0]) shl 8) or LData[1];
          if not IsValidCloseCode(LCloseCode) then begin _Fail(1002); Exit; end;
          if Length(LData) > 2 then
            if not _IsValidUtf8(@LData[2], Length(LData) - 2) then
            begin _Fail(1007); Exit; end;
        end;
      except
        Stop;
        raise;
      end;
      Stop;
    end;
    TriggerCommand(LOpCode, LData);
    if FMessageTimeoutMs <> 0 then CheckTimeout;
    Exit;
  end;
  if not FFrameFIN then
  begin
    _ResetFrameHeader;
    Exit;
  end;
  LOpCode := FMessageOpCode;
  LSize := NativeInt(FWsMessageBody.Size);
  // 完整消息校验一次，允许 UTF-8 字符跨分片、跨输入块。
  if FCheckTextUtf8 and (LOpCode = WS_OP_TEXT) then
    if not _IsValidUtf8(PByte(FWsMessageBody.Memory), LSize) then
    begin _Fail(1007); Exit; end;
  try
    SetLength(LData, LSize);
    if LSize > 0 then Move(FWsMessageBody.Memory^, LData[0], LSize);
  except
    Stop;
    raise;
  end;
  _ResetRequest;
  case LOpCode of
    WS_OP_TEXT, WS_OP_BINARY: TriggerMessage(OpCodeToReqType(LOpCode), LData);
  else
    TriggerCommand(LOpCode, LData);
  end;
end;

procedure TCrossWebSocketParser._FinishFrame(var ABuf: Pointer; var ALen: Integer);
begin
  try
    _FrameEnd;
  finally
    if FStopped and (ALen > 0) then
    begin
      ABuf := PByte(ABuf) + ALen;
      ALen := 0;
    end;
  end;
end;

procedure TCrossWebSocketParser.Decode(var ABuf: Pointer; var ALen: Integer);
var
  LCount: Integer;
begin
  // 常见的正文续收路径没有帧头校验、回调或异常保护帧。
  if (ALen > 0) and (ABuf <> nil) and not FStopped
    and (FMessageTimeoutMs = 0) and (FWsFrameState = wsBody) then
    if UInt64(ALen) < FFrameRemaining then
    begin
      LCount := ALen;
      _ReadBody(PByte(ABuf), LCount);
      ABuf := PByte(ABuf) + LCount;
      Dec(FFrameRemaining, UInt64(LCount));
      ALen := 0;
      Exit;
    end;
  _DecodeFrames(ABuf, ALen);
end;

procedure TCrossWebSocketParser._DecodeFrames(var ABuf: Pointer; var ALen: Integer);
var
  LCount: Integer;
  LValid: Boolean;
begin
  if ALen < 0 then raise ECrossSocket.Create('输入长度不能为负数');
  if (ALen > 0) and (ABuf = nil) then
    raise ECrossSocket.Create('非空输入需要有效的缓冲区');
  if FMessageTimeoutMs <> 0 then
    try
      CheckTimeout;
    finally
      if FStopped and (ALen > 0) then
      begin
        ABuf := PByte(ABuf) + ALen;
        ALen := 0;
      end;
    end;
  if FStopped then
  begin
    ABuf := PByte(ABuf) + ALen;
    ALen := 0;
    Exit;
  end;
  while ALen > 0 do
  begin
    if FWsFrameState = wsHeader then
    begin
      LCount := FHeaderNeeded - FHeaderRead;
      if LCount > ALen then LCount := ALen;
      if LCount > 0 then
      begin
        Move(PByte(ABuf)^, FHeader[FHeaderRead], LCount);
        Inc(FHeaderRead, LCount);
        ABuf := PByte(ABuf) + LCount;
        Dec(ALen, LCount);
      end;
      if FHeaderRead < FHeaderNeeded then Continue;
      // 异常保护只围绕帧头校验/分配，不在每个正文输入块上建立异常帧。
      try
        if not FHeaderDecoded then
        begin
          FHeaderDecoded := True;
          if not _ReadBaseHeader then
          begin
            ABuf := PByte(ABuf) + ALen;
            ALen := 0;
            Exit;
          end;
          if FHeaderRead < FHeaderNeeded then Continue;
        end;
        LValid := _ReadFullHeader;
      except
        Stop;
        ABuf := PByte(ABuf) + ALen;
        ALen := 0;
        raise;
      end;
      if not LValid then
      begin
        ABuf := PByte(ABuf) + ALen;
        ALen := 0;
        Exit;
      end;
      if FFrameRemaining = 0 then _FinishFrame(ABuf, ALen);
    end else
    begin
      LCount := ALen;
      if UInt64(LCount) > FFrameRemaining then LCount := Integer(FFrameRemaining);
      _ReadBody(PByte(ABuf), LCount);
      // 每个成功消费的块立即提交位置，回调异常无需在正文热路径补偿。
      ABuf := PByte(ABuf) + LCount;
      Dec(ALen, LCount);
      Dec(FFrameRemaining, UInt64(LCount));
      if FFrameRemaining = 0 then _FinishFrame(ABuf, ALen);
    end;
  end;
end;

class function TCrossWebSocketParser.MakeFrameData(AOpCode: Byte;
  AFin, AIsServer: Boolean; AData: Pointer; ADataSize: UInt64): TBytes;
var
  LPayload: Byte;
  LHeaderSize, LDataSize, I: Integer;
  LMasked: Boolean;
  LRandomOK: Boolean;
  LMaskingKey: Cardinal;
  LMaskKey: PByte;
begin
  LMasked := not AIsServer;
  LMaskingKey := 0;
  if LMasked then
  begin
    {$IFDEF CROSS_WS_SENDER_SELFTEST}
    if CrossWebSocketMaskFailureForTest then LRandomOK := False else
    {$ENDIF}
      LRandomOK := TryFillCryptRandomBytes(LMaskingKey, SizeOf(LMaskingKey));
    if not LRandomOK then
      raise ECrossSocket.Create(
        'Failed to generate WebSocket masking key: CSPRNG unavailable');
  end;

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
  if LMasked then
    Inc(LHeaderSize, 4);

  // 实体帧必须先验证 UInt64，再窄化到数组/Move 使用的 Integer。
  // nil 载荷保留仅构造任意长度头部的既有用途。
  LDataSize := 0;
  if (AData <> nil) and (ADataSize > 0) then
  begin
    if ADataSize > UInt64(High(Integer) - LHeaderSize) then
      raise ECrossSocket.Create('WebSocket 实体帧长度超出支持范围');
    LDataSize := Integer(ADataSize);
  end;
  SetLength(Result, LHeaderSize + LDataSize);
  FillChar(Result[0], LHeaderSize, 0);

  if AFin then
    Result[0] := Result[0] or $80;
  Result[0] := Result[0] or (AOpCode and $0F);

  if LMasked then
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

  if LMasked then
    Move(LMaskingKey, Result[LHeaderSize - 4], 4);

  if (LDataSize > 0) then
  begin
    if LMasked then
    begin
      LMaskKey := PByte(@LMaskingKey);
      for I := 0 to LDataSize - 1 do
        Result[LHeaderSize + I] := PByte(AData)[I] xor LMaskKey[I mod 4];
    end else
      Move(AData^, Result[LHeaderSize], LDataSize);
  end;
end;

class function TCrossWebSocketParser.MakeSecWebSocketAccept(
  const ASecWebSocketKey: string): string;
begin
  Result := TBase64Utils.Encode(
    THashSHA1.GetHashBytes(ASecWebSocketKey + WS_MAGIC_STR)
  );
end;

class function TCrossWebSocketParser.IsValidSecWebSocketKey(const AKey: string): Boolean;
var
  LBytes: TBytes;
begin
  Result := False;
  if (Length(AKey) <> 24) or (Copy(AKey, 23, 2) <> '==') then Exit;
  try
    LBytes := TBase64Utils.Decode(AKey);
    Result := (Length(LBytes) = 16) and (TBase64Utils.Encode(LBytes) = AKey);
  except
    on E: Exception do Result := False;
  end;
end;

class function TCrossWebSocketParser.IsValidHttpVersion(const AVersion: string): Boolean;
var
  LParts: TArray<string>;
  LMajor, LMinor: Integer;
  C: Char;
begin
  Result := False;
  if Copy(AVersion, 1, 5) <> 'HTTP/' then Exit;
  LParts := Copy(AVersion, 6, MaxInt).Split(['.']);
  if (Length(LParts) <> 2) or (LParts[0] = '') or (LParts[1] = '') then Exit;
  for C in LParts[0] + LParts[1] do
    if (C < '0') or (C > '9') then Exit;
  if not TryStrToInt(LParts[0], LMajor) or not TryStrToInt(LParts[1], LMinor) then Exit;
  Result := (LMajor > 1) or ((LMajor = 1) and (LMinor >= 1));
end;

class function TCrossWebSocketParser.NewSecWebSocketKey: string;
const
  WS_KEY_SIZE = 16;  // RFC 6455 S4.1: 16 bytes -> 24-char base64
var
  LKeyBytes: TBytes;
begin
  SetLength(LKeyBytes, WS_KEY_SIZE);
  if not TryFillCryptRandomBytes(LKeyBytes[0], WS_KEY_SIZE) then
    raise ECrossSocket.Create('Failed to generate WebSocket key: CSPRNG unavailable');
  Result := TBase64Utils.Encode(LKeyBytes);
end;

class function TCrossWebSocketParser.OpCodeToReqType(AOpCode: Byte): TWsMessageType;
begin
  case AOpCode of
    WS_OP_TEXT: Exit(wtText);
    WS_OP_BINARY: Exit(wtBinary);
  else
    Exit(wtUnknown);
  end;
end;

procedure TCrossWebSocketParser.TriggerCommand(const AOpCode: Byte;
  const AData: TBytes);
begin
  if Assigned(FOnCommand) then
    FOnCommand(AOpCode, AData);
end;

procedure TCrossWebSocketParser.TriggerFailed;
begin
  if Assigned(FWsOnFailed) then
    FWsOnFailed();
end;

procedure TCrossWebSocketParser.TriggerMessage(const AType: TWsMessageType;
  const AData: TBytes);
begin
  if Assigned(FOnMessage) then
    FOnMessage(AType, AData);
end;

end.
