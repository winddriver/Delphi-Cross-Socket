program MbedIoRegression;

{$APPTYPE CONSOLE}
{$I zLib.inc}

uses
  SysUtils, Classes, SyncObjs, Net.SocketAPI, Net.CrossSocket.Base,
  Net.CrossSslSocket.Types, Net.CrossSslSocket.Base, Net.CrossSslSocket.MbedTls, Net.MbedTls;

type
  TServer = class(TCrossMbedTlsSocket)
    EarlyOK, EarlyFailed, Sends, Failures: Integer;
    Received: TBytes;
    Count: Integer;
    procedure TriggerConnected(const C: ICrossConnection); override;
    procedure LogicReceived(const C: ICrossConnection; const Buf: Pointer; const Len: Integer); override;
  end;

var
  RetryBuffer: Pointer;
  Retried: Integer;

function ForceWantRead(const AData: Pointer; const ACount: Integer; out ACode: Integer): Boolean;
begin
  if ACount <> 1 then Exit(False);
  if RetryBuffer <> nil then
  begin
    if AData <> RetryBuffer then raise Exception.Create('重试变更了指针');
    Inc(Retried);
    RetryBuffer := nil;
    Exit(False);
  end;
  RetryBuffer := AData;
  ACode := MBEDTLS_ERR_SSL_WANT_READ;
  Writeln('WAIT_READ'); Flush(Output);
  Result := True;
end;

procedure TServer.TriggerConnected(const C: ICrossConnection);
begin
  // 握手尚未开始，写入必须等握手后提交；TCP 提前关闭则只结算一次失败。
  C.SendBytes(TBytes.Create(42), procedure(const Conn: ICrossConnection; const OK: Boolean)
    begin if OK then AtomicIncrement(EarlyOK) else AtomicIncrement(EarlyFailed); end);
  inherited;
end;

procedure TServer.LogicReceived(const C: ICrossConnection; const Buf: Pointer; const Len: Integer);
var
  I: Integer;
  LChunk: TBytes;
begin
  if (Count = Length(Received)) and (Len = 1) and (PByte(Buf)^ = Ord('P')) then
  begin
    // 当前泵停在业务通知，重入接收模拟其它线程持续提供密文。
    SetLength(LChunk, 32768);
    for I := 1 to 4 do
    begin
      TriggerReceived(C, Pointer(LChunk), Length(LChunk));
      if C.IsClosed then raise Exception.Create('未超过输入上限就关闭');
    end;
    TriggerReceived(C, Pointer(LChunk), 1);
    if not C.IsClosed then raise Exception.Create('阻塞期间的输入没有上限');
    Writeln('PRESSURE_CLOSED'); Flush(Output);
    Exit;
  end;
  if Len > Length(Received) - Count then raise Exception.Create('接收超过预期');
  Move(Buf^, Received[Count], Len);
  Inc(Count, Len);
  if Count = Length(Received) then
    C.SendBytes(Received, procedure(const Conn: ICrossConnection; const OK: Boolean)
      begin if OK then AtomicIncrement(Sends) else AtomicIncrement(Failures); end);
end;

procedure Run;
var
  S: TServer;
  Owner: ICrossSslSocket;
  Port: Word;
  Line: string;
begin
  S := TServer.Create(2, True);
  Owner := S;
  CrossMbedTlsTestWrite := ForceWantRead;
  S.SetCertificateFile(ParamStr(1));
  S.SetPrivateKeyFile(ParamStr(2));
  SetLength(S.Received, 262177);
  Port := 0;
  S.Listen('127.0.0.1', 0, procedure(const L: ICrossListen; const OK: Boolean)
    begin if OK then Port := L.LocalPort; end);
  if Port = 0 then raise Exception.Create('未监听');
  Writeln('PORT ', Port); Flush(Output);
  Readln(Line);
  S.StopLoop;
  Writeln('COUNTS ', S.EarlyOK, ' ', S.EarlyFailed, ' ', S.Sends, ' ', S.Failures, ' ', S.Count);
  if (S.EarlyOK <> 1) or (S.EarlyFailed <> 2) or (S.Sends <> 1) or (S.Failures <> 0)
    or (S.Count <> Length(S.Received)) or (Retried <> 1) then raise Exception.Create('字节或通知计数不符');
  CrossMbedTlsTestWrite := nil;
  Owner := nil;
end;

begin
  try Run;
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
