program WebSocketStreamTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, Math, Generics.Collections,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossHttpUtils, Net.CrossHttpClient,
  Net.CrossHttpServer, Net.CrossWebSocketClient, Net.CrossWebSocketServer,
  Net.CrossWebSocketSender;

type
  TPendingWrite = record
    Data: TBytes;
    Buffer: Pointer;
    Callback: TCrossConnectionCallback;
  end;
  TWire = class
  public
    Frames: TList<TBytes>;
    Pending: TList<TPendingWrite>;
    AutoComplete: Boolean;
    CloseCount, BufferChecks: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Send(const C: ICrossConnection; const P: Pointer; const N: Integer;
      const Done: TCrossConnectionCallback);
    procedure Complete(const C: ICrossConnection; const OK: Boolean);
    function CompletedMessages: TArray<string>;
  end;
  TProbeStream = class(TStream)
  private
    FPosition: Int64;
  protected
    function GetSize: Int64; override;
  public
    DeclaredSize, ActualSize, MaxRead, FailReadAt, Reads: Integer;
    NegativeEnd, SizeError, SeekError: Boolean;
    Destroyed: PInteger;
    constructor Create;
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;
  TClientConnection = class(TCrossWebSocketClientConnection)
  public
    Wire: TWire;
    procedure DirectSend(const P: Pointer; const N: Integer;
      const Done: TCrossConnectionCallback = nil); override;
    procedure Close; override;
    procedure Feed(const Data: AnsiString);
  end;
  TClientSocket = class(TCrossWebSocketClient)
  public
    Wire: TWire;
    Connection: TClientConnection;
    Keep: ICrossConnection;
    procedure Connect(const Host: string; const Port, LocalPort: Word;
      const Done: TCrossConnectionCallback = nil); override;
  end;
  TClientManager = class(TCrossWebSocketMgr)
  protected
    function CreateHttpCli(const Protocol: string): ICrossHttpClientSocket; override;
  public
    Wire: TWire;
    Socket: TClientSocket;
    SocketKeep: ICrossHttpClientSocket;
  end;
  TServerConnection = class(TCrossWebSocketConnection)
  public
    Wire: TWire;
    procedure DirectSend(const P: Pointer; const N: Integer;
      const Done: TCrossConnectionCallback = nil); override;
    procedure Close; override;
    procedure Feed(const Data: AnsiString);
    procedure Cleanup;
  end;

procedure Require(const Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

constructor TWire.Create;
begin
  Frames := TList<TBytes>.Create;
  Pending := TList<TPendingWrite>.Create;
  AutoComplete := True;
end;

destructor TWire.Destroy;
begin
  Pending.Free;
  Frames.Free;
  inherited;
end;

procedure TWire.Send(const C: ICrossConnection; const P: Pointer; const N: Integer;
  const Done: TCrossConnectionCallback);
var
  Item: TPendingWrite;
begin
  SetLength(Item.Data, N);
  if N > 0 then Move(P^, Item.Data[0], N);
  Frames.Add(Item.Data);
  if AutoComplete then
  begin
    if Assigned(Done) then Done(C, True);
  end else
  begin
    Item.Buffer := P;
    Item.Callback := Done;
    Pending.Add(Item);
  end;
end;

procedure TWire.Complete(const C: ICrossConnection; const OK: Boolean);
var
  Item: TPendingWrite;
begin
  Require(Pending.Count > 0, '没有待完成的物理写');
  Item := Pending[0];
  Pending.Delete(0);
  Require((Length(Item.Data) = 0) or CompareMem(Item.Buffer, @Item.Data[0], Length(Item.Data)),
    '完成之前实际发送缓冲区已被释放或改写');
  Inc(BufferChecks);
  if Assigned(Item.Callback) then Item.Callback(C, OK);
end;

function TWire.CompletedMessages: TArray<string>;
var
  Frame: TBytes;
  Current: string;
  N, I, Start, MaskAt: Integer;
  B: Byte;
begin
  Result := nil;
  Current := '';
  for Frame in Frames do
  begin
    Require(Length(Frame) >= 2, '帧头缺失');
    N := Frame[1] and $7f;
    Require(N < 126, '本专项只发送小帧');
    Start := 2;
    MaskAt := -1;
    if Frame[1] and $80 <> 0 then begin MaskAt := 2; Start := 6; end;
    Require(Length(Frame) = Start + N, '帧长度错误');
    Require(Frame[0] and $0f in [0, 1, 2], '出现不应有的控制帧');
    for I := 0 to N - 1 do
    begin
      B := Frame[Start + I];
      if MaskAt >= 0 then B := B xor Frame[MaskAt + I mod 4];
      Current := Current + Char(B);
    end;
    if Frame[0] and $80 <> 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Current;
      Current := '';
    end;
  end;
end;

constructor TProbeStream.Create;
begin
  DeclaredSize := 8;
  ActualSize := 8;
  MaxRead := 8;
end;

destructor TProbeStream.Destroy;
begin
  if Destroyed <> nil then Inc(Destroyed^);
  inherited;
end;

function TProbeStream.GetSize: Int64;
begin
  if SizeError then raise EStreamError.Create('size-error');
  Result := DeclaredSize;
end;

function TProbeStream.Read(var Buffer; Count: Longint): Longint;
var
  I: Integer;
begin
  Inc(Reads);
  if Reads = FailReadAt then raise EReadError.Create('read-error');
  if FPosition >= ActualSize then
  begin
    if NegativeEnd then Exit(-1);
    Exit(0);
  end;
  Result := Min(Int64(Count), Min(Int64(MaxRead), ActualSize - FPosition));
  for I := 0 to Result - 1 do PByte(@Buffer)[I] := Ord('a') + FPosition + I;
  Inc(FPosition, Result);
end;

function TProbeStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
  raise EStreamError.Create('测试源不可写');
end;

function TProbeStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  if SeekError then raise EStreamError.Create('seek-error');
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent: Inc(FPosition, Offset);
    soEnd: FPosition := DeclaredSize + Offset;
  end;
  Result := FPosition;
end;

procedure TClientConnection.DirectSend(const P: Pointer; const N: Integer;
  const Done: TCrossConnectionCallback);
begin Wire.Send(Self, P, N, Done); end;

procedure TClientConnection.Close;
begin
  if IsClosed then Exit;
  Inc(Wire.CloseCount);
  ConnectStatus := csClosed;
end;

procedure TClientConnection.Feed(const Data: AnsiString);
var P: Pointer; N: Integer;
begin
  P := PAnsiChar(Data); N := Length(Data);
  _LockRecv;
  try ParseRecvData(P, N); Require(N = 0, '客户端握手未全部消费');
  finally _UnlockRecv; end;
end;

procedure TClientSocket.Connect(const Host: string; const Port, LocalPort: Word;
  const Done: TCrossConnectionCallback);
begin
  Connection := TClientConnection.Create(Self, INVALID_SOCKET, ctConnect, Host, nil);
  Connection.Wire := Wire;
  Connection.ConnectStatus := csConnected;
  Keep := Connection;
  if Assigned(Done) then Done(Keep, True);
end;

function TClientManager.CreateHttpCli(const Protocol: string): ICrossHttpClientSocket;
begin
  if SocketKeep = nil then
  begin
    Socket := TClientSocket.Create(Self, 1, -1, -1, False, False, False, ctNone);
    Socket.Wire := Wire;
    SocketKeep := Socket;
  end;
  Result := SocketKeep;
end;

procedure TServerConnection.DirectSend(const P: Pointer; const N: Integer;
  const Done: TCrossConnectionCallback);
begin Wire.Send(Self, P, N, Done); end;

procedure TServerConnection.Close;
begin
  if IsClosed then Exit;
  Inc(Wire.CloseCount);
  ConnectStatus := csClosed;
end;

procedure TServerConnection.Feed(const Data: AnsiString);
var P: Pointer; N: Integer;
begin
  P := PAnsiChar(Data); N := Length(Data);
  _LockRecv;
  try ParseRecvData(P, N); Require(N = 0, '服务端握手未全部消费');
  finally _UnlockRecv; end;
end;

procedure TServerConnection.Cleanup;
begin ConnectStatus := csClosed; InternalClose; end;

procedure Run(const Side, TestCase: string);
var
  Wire: TWire;
  ServerObject: TCrossWebSocketServer;
  Server: ICrossWebSocketServer;
  ServerConnection: TServerConnection;
  Manager: TClientManager;
  ManagerKeep: ICrossWebSocketMgr;
  WebSocket: ICrossWebSocket;
  Connection: ICrossConnection;
  ClientConnection: TClientConnection;
  Stream, Following: TProbeStream;
  MainCalls, TailCalls, FollowingCalls, BlockerCalls, Destroyed, Opens, Rounds: Integer;
  MainOK, TailOK, FollowingOK, Failure, SetupFailure, CancelQueued: Boolean;
  ErrorClass, ErrorMessage, Expected: string;
  Messages: TArray<string>;
  Offset, Count: Int64;
  {$IFDEF WS_STREAM_QUEUE_LIMITS}QueueLimits: TWsSendQueueLimits;{$ENDIF}
  procedure SendText(const Text: string; const Done: TWsClientCallback);
  begin
    if Side = 'client' then WebSocket.Send(Text, Done)
    else ServerConnection.WsSend(Text,
      procedure(const C: ICrossWebSocketConnection; const OK: Boolean)
      begin Require((C as ICrossConnection) = Connection, '服务端回调连接错误'); if Assigned(Done) then Done(OK); end);
  end;
  procedure SendStream(const Data: TStream; const AOffset, ACount: Int64; const Done: TWsClientCallback);
  begin
    if Side = 'client' then WebSocket.Send(Data, AOffset, ACount, Done)
    else ServerConnection.WsSend(Data, AOffset, ACount,
      procedure(const C: ICrossWebSocketConnection; const OK: Boolean)
      begin Require((C as ICrossConnection) = Connection, '服务端回调连接错误'); if Assigned(Done) then Done(OK); end);
  end;
  procedure CaptureError(const E: Exception);
  begin
    if ErrorClass = '' then begin ErrorClass := E.ClassName; ErrorMessage := E.Message; end;
  end;
begin
  Require((Side = 'client') or (Side = 'server'), '未知端点');
  Wire := TWire.Create;
  Stream := TProbeStream.Create;
  Following := TProbeStream.Create;
  ServerConnection := nil; ServerObject := nil; ClientConnection := nil; Manager := nil;
  Destroyed := 0; Opens := 0; MainCalls := 0; TailCalls := 0; FollowingCalls := 0; BlockerCalls := 0;
  MainOK := False; TailOK := False; FollowingOK := False;
  Stream.Destroyed := @Destroyed;
  Failure := (TestCase = 'eof') or (TestCase = 'negative') or (TestCase = 'read-first')
    or (TestCase = 'read-later') or (TestCase = 'eof-callback-error');
  SetupFailure := (TestCase = 'size-error') or (TestCase = 'seek-error');
  CancelQueued := TestCase = 'queued-no-read';
  if (TestCase = 'eof') or (TestCase = 'negative') or (TestCase = 'eof-callback-error') then Stream.ActualSize := 3;
  if TestCase = 'negative' then Stream.NegativeEnd := True;
  if (TestCase = 'short') or (TestCase = 'queued-no-read') then Stream.MaxRead := 1;
  if TestCase = 'read-first' then Stream.FailReadAt := 1;
  if TestCase = 'read-later' then begin Stream.MaxRead := 3; Stream.FailReadAt := 2; end;
  Stream.SizeError := TestCase = 'size-error';
  Stream.SeekError := TestCase = 'seek-error';
  if TestCase = 'empty' then begin Stream.DeclaredSize := 0; Stream.ActualSize := 0; end;
  Offset := 0; Count := 0; Expected := 'abcdefgh';
  if TestCase = 'range' then begin Offset := 2; Count := 3; Expected := 'cde'; end;
  if TestCase = 'empty' then Expected := '';
  try
    if Side = 'client' then
    begin
      Manager := TClientManager.Create(1); Manager.Wire := Wire; ManagerKeep := Manager;
      WebSocket := Manager.CreateWebSocket('ws://localhost/stream');
      WebSocket.OnOpenRequest(procedure(const R: ICrossHttpClientRequest)
        begin R.Header['Sec-WebSocket-Key'] := 'dGhlIHNhbXBsZSBub25jZQ=='; end);
      WebSocket.OnOpen(procedure begin Inc(Opens); end);
      WebSocket.Open;
      Require(Manager.Socket <> nil, '未经过真实客户端请求入口');
      ClientConnection := Manager.Socket.Connection; Connection := ClientConnection;
      ClientConnection.Feed('HTTP/1.1 101 Switching Protocols'#13#10'Upgrade: websocket'#13#10 +
        'Connection: Upgrade'#13#10'Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo='#13#10#13#10);
      Require((Opens = 1) and (WebSocket.Status = wsConnected), '真实客户端握手失败');
    end else
    begin
      ServerObject := TCrossWebSocketServer.Create(1, False); Server := ServerObject;
      Server.OnOpen(procedure(const C: ICrossWebSocketConnection) begin Inc(Opens); end);
      ServerConnection := TServerConnection.Create(ServerObject, INVALID_SOCKET, ctAccept, '', nil);
      ServerConnection.Wire := Wire; ServerConnection.ConnectStatus := csConnected; Connection := ServerConnection;
      ServerConnection.Feed('GET /stream HTTP/1.1'#13#10'Host: localhost'#13#10'Upgrade: websocket'#13#10 +
        'Connection: Upgrade'#13#10'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=='#13#10 +
        'Sec-WebSocket-Version: 13'#13#10#13#10);
      Require((Opens = 1) and ServerConnection.IsWebSocket, '真实服务端握手失败');
    end;
    Require(Wire.Pending.Count = 0, '握手写入未完成');
    {$IFDEF WS_STREAM_QUEUE_LIMITS}
    QueueLimits := Default(TWsSendQueueLimits);
    QueueLimits.MaxMessageCount := 4;
    QueueLimits.MaxMessageBytes := 256;
    QueueLimits.MaxControlCount := 2;
    QueueLimits.MaxControlBytes := 256;
    if Side = 'client' then ClientConnection.SetWebSocketSendQueueLimits(QueueLimits)
    else ServerConnection.SetWebSocketSendQueueLimits(QueueLimits);
    {$ENDIF}
    Wire.Frames.Clear; Wire.AutoComplete := False;
    if not SetupFailure then
      SendText('B', procedure(const OK: Boolean) begin Require(OK, '阻塞帧失败'); Inc(BlockerCalls); end);
    try
      SendStream(Stream, Offset, Count,
        procedure(const OK: Boolean)
        begin
          Inc(MainCalls); MainOK := OK;
          Require(Destroyed = 0, '回调前借用流被释放');
          if (TestCase = 'eof-callback-error') and not OK then raise Exception.Create('callback-error');
        end);
    except on E: Exception do CaptureError(E); end;
    Require(Stream.Reads = 0, '排队流或Size/Seek失败流被提前读取');
    if SetupFailure then
    begin
      Require((ErrorClass = 'EStreamError') and (ErrorMessage = TestCase), 'Size/Seek未保持同步异常');
      Require((MainCalls = 0) and (Wire.CloseCount = 0) and (Wire.Frames.Count = 0), '入队前异常改变了发送状态');
    end;
    SendText('T', procedure(const OK: Boolean) begin Inc(TailCalls); TailOK := OK; end);
    if Failure then
      SendStream(Following, 0, 0, procedure(const OK: Boolean) begin Inc(FollowingCalls); FollowingOK := OK; end);
    if CancelQueued then Connection.Close;
    Rounds := 0;
    while Wire.Pending.Count > 0 do
    begin
      Inc(Rounds); Require(Rounds < 40, '发送队列没有收敛');
      try Wire.Complete(Connection, True); except on E: Exception do CaptureError(E); end;
    end;
    Messages := Wire.CompletedMessages;
    Writeln('OBS calls=', MainCalls, ' success=', Ord(MainOK), ' reads=', Stream.Reads,
      ' closes=', Wire.CloseCount, ' following_reads=', Following.Reads, ' error=', ErrorClass);
    Require(Destroyed = 0, '发送器取得了借用流所有权');
    Require(TailCalls = 1, '后续消息没有恰好一次通知');
    if Failure then
    begin
      Require((MainCalls = 1) and not MainOK, '提前EOF或读取异常被报告为成功');
      Require((FollowingCalls = 1) and not FollowingOK and not TailOK, '后续排队消息没有取消');
      Require(Following.Reads = 0, '取消的后续流被读取');
      Require((Wire.CloseCount = 1) and (ErrorClass = 'EReadError'), '读取失败未关闭或原错误被覆盖');
      if (TestCase = 'read-first') or (TestCase = 'read-later') then
        Require(ErrorMessage = 'read-error', '数据源原始读取异常被覆盖');
      Require((Length(Messages) = 1) and (Messages[0] = 'B'), '失败的流仍作为完整消息发送');
    end else
    if CancelQueued then
    begin
      Require((MainCalls = 1) and not MainOK and not TailOK and (Stream.Reads = 0),
        '未轮到的流取消后仍被读取或成功通知');
      Require((Wire.CloseCount = 1) and (ErrorClass = '') and (Length(Messages) = 1)
        and (Messages[0] = 'B'), '排队取消改变了在途帧结算或继续发送');
    end else
    if SetupFailure then
      Require(TailOK and (Length(Messages) = 1) and (Messages[0] = 'T'), '同步参数异常破坏了后续发送')
    else
    begin
      Require((MainCalls = 1) and MainOK and TailOK and (ErrorClass = ''), '正常短读/空流未成功');
      Require((Length(Messages) = 3) and (Messages[0] = 'B') and (Messages[1] = Expected)
        and (Messages[2] = 'T'), '实际帧内容或消息顺序错误');
      Require(Wire.CloseCount = 0, '正常流错误关闭');
      if TestCase = 'short' then Require(Stream.Reads = 8, '合法1字节短读没有持续推进');
    end;
    Require(Wire.BufferChecks > 0, '没有验证在途缓冲区');
  finally
    if Connection <> nil then Connection.Close;
    while Wire.Pending.Count > 0 do
      try Wire.Complete(Connection, False); except on E: Exception do ; end;
    if ServerConnection <> nil then ServerConnection.Cleanup;
    WebSocket := nil;
    if Manager <> nil then
    begin
      if Manager.Socket <> nil then Manager.Socket.Keep := nil;
      Manager.SocketKeep := nil;
    end;
    Connection := nil; Server := nil; ManagerKeep := nil;
    Stream.Free; Following.Free;
    Wire.Free;
  end;
  Require(Destroyed = 1, '调用方释放借用流不唯一');
end;

begin
  SetTextCodePage(Output, 65001);
  try
    Require(ParamCount = 2, '用法: WebSocketStreamTests <client|server> <用例>');
    Run(ParamStr(1), ParamStr(2));
    Writeln('PASS');
  except on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
