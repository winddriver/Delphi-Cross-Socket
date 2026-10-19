program WebSocketTlsCapacityTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  Net.OpenSSL, Net.CrossSocket.Base, Net.CrossSslSocket.Types,
  Net.CrossWebSocketParser, Net.CrossWebSocketServer;

procedure Require(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure RunServer;
var
  LServer: TCrossWebSocketServer;
  LKeepServer: ICrossWebSocketServer;
  LConnection: ICrossWebSocketConnection;
  LReady, LSmallDone, LMainDone, LTailDone, LClosed: TEvent;
  LPort: Word;
  LSmallCalls, LSmallSuccess, LMainCalls, LMainSuccess: Integer;
  LTailCalls, LTailSuccess, LReadCalls, LCloseCalls: Integer;
  LData: TBytes;
  LLine, LMode: string;
  LInfo: TSslInfo;
  {$IFDEF CROSS_CAPACITY_TESTS}
  LRejectedCount, LRejectedSize: Integer;
  LRejectedConnection: ICrossConnection;
  LPendingCount, LPendingBytes: Int64;
  {$ENDIF}
begin
  LMode := ParamStr(1);
  Require((LMode = 'normal') or (LMode = 'limit'), '未知模式');
  LSmallCalls := 0; LSmallSuccess := 0; LMainCalls := 0; LMainSuccess := 0;
  LTailCalls := 0; LTailSuccess := 0; LReadCalls := 0; LCloseCalls := 0;
  LPort := 0;
  {$IFDEF CROSS_CAPACITY_TESTS}
  LRejectedCount := 0; LRejectedSize := 0;
  CrossSendRejectedForTest :=
    procedure(const C: ICrossConnection; const ABytes: Integer)
    begin
      // 只观测真实 Reserve 失败，不改写物理结果或调度。
      LRejectedConnection := C;
      AtomicExchange(LRejectedSize, ABytes);
      AtomicIncrement(LRejectedCount);
    end;
  {$ENDIF}
  LReady := TEvent.Create(nil, True, False, '');
  LSmallDone := TEvent.Create(nil, True, False, '');
  LMainDone := TEvent.Create(nil, True, False, '');
  LTailDone := TEvent.Create(nil, True, False, '');
  LClosed := TEvent.Create(nil, True, False, '');
  try
    LServer := TCrossWebSocketServer.Create(2, True);
    LKeepServer := LServer;
    LServer.Addr := '127.0.0.1'; LServer.Port := 0;
    LServer.SetCertificateFile(ParamStr(4));
    LServer.SetPrivateKeyFile(ParamStr(5));
    {$IFDEF WS_BASE_LIMITS}
    // 在新连接构造前配置；4KiB 容纳握手和小消息，小于首个大应用记录。
    if LMode = 'limit' then LServer.MaxPendingSendBytes := 4096;
    {$ENDIF}
    SetLength(LData, 64 * 1024);
    FillChar(LData[0], Length(LData), Ord('j'));
    LServer.OnOpen(
      procedure(const C: ICrossWebSocketConnection)
      begin
        LConnection := C;
        Require(C.GetSslInfo(LInfo), '真实 TLS 连接未返回协商信息');
        Require(LInfo.SslVersion = ParamStr(6), '本端 TLS 版本不符合指定值');
      end);
    LServer.OnClose(
      procedure(const C: ICrossWebSocketConnection)
      begin
        AtomicIncrement(LCloseCalls);
        LClosed.SetEvent;
      end);
    LServer.OnMessage(
      procedure(const C: ICrossWebSocketConnection; const K: TWsMessageType; const D: TBytes)
      begin
        if TEncoding.UTF8.GetString(D) = 'small' then
          C.WsSend(D,
            procedure(const AConnection: ICrossWebSocketConnection; const OK: Boolean)
            begin
              AtomicIncrement(LSmallCalls);
              if OK then AtomicIncrement(LSmallSuccess);
              LSmallDone.SetEvent;
            end)
        else
        begin
          Require(TEncoding.UTF8.GetString(D) = 'large', '未知消息');
          C.WsSend(
            function(const ABuffer: PPointer; const ACount: PNativeInt): Boolean
            begin
              if AtomicIncrement(LReadCalls) <> 1 then Exit(False);
              // 发送泵已接纳当前消息；先真正排队后续消息，再交付大帧。
              C.WsSend('must-not-send',
                procedure(const AConnection: ICrossWebSocketConnection; const OK: Boolean)
                begin
                  AtomicIncrement(LTailCalls);
                  if OK then AtomicIncrement(LTailSuccess);
                  LTailDone.SetEvent;
                end);
              ABuffer^ := @LData[0]; ACount^ := Length(LData);
              Result := True;
            end,
            procedure(const AConnection: ICrossWebSocketConnection; const OK: Boolean)
            begin
              AtomicIncrement(LMainCalls);
              if OK then AtomicIncrement(LMainSuccess);
              LMainDone.SetEvent;
            end);
        end;
      end);
    LServer.Start(
      procedure(const L: ICrossListen; const OK: Boolean)
      begin
        if OK then LPort := L.LocalPort;
        LReady.SetEvent;
      end);
    Require((LReady.WaitFor(5000) = wrSignaled) and (LPort <> 0), '监听失败');
    Writeln('READY ', LPort); Flush(Output);
    Readln(LLine);
    Require(LSmallDone.WaitFor(5000) = wrSignaled, '小消息未完成');
    Require(LClosed.WaitFor(5000) = wrSignaled, '连接未关闭');
    if LMode = 'limit' then
    begin
      Require(LMainDone.WaitFor(5000) = wrSignaled, '大帧缺少完成通知');
      Require(LTailDone.WaitFor(5000) = wrSignaled, '后续消息没有取消');
    end;
    LServer.Stop;
    Writeln('RESULT version=', LInfo.SslVersion, ' small=', LSmallCalls, '/', LSmallSuccess,
      ' main=', LMainCalls, '/', LMainSuccess, ' tail=', LTailCalls, '/', LTailSuccess,
      ' reads=', LReadCalls, ' closes=', LCloseCalls); Flush(Output);
    {$IFDEF CROSS_CAPACITY_TESTS}
    GetPendingSendForTest(LConnection, LPendingCount, LPendingBytes);
    Writeln('BASE rejected=', LRejectedCount, ' bytes=', LRejectedSize,
      ' pending=', LPendingCount, '/', LPendingBytes); Flush(Output);
    Require((LPendingCount = 0) and (LPendingBytes = 0), '底层额度未完全归还');
    if LMode = 'limit' then
    begin
      Require((LRejectedCount = 1) and (LRejectedSize > 4096), '未观测到唯一真实底层大密文拒绝');
      Require(LRejectedConnection = (LConnection as ICrossConnection), '拒绝来自其他连接');
    end else Require(LRejectedCount = 0, '正常路径发生了底层限额拒绝');
    {$ENDIF}
    Require((LSmallCalls = 1) and (LSmallSuccess = 1), '正常小消息未恰好一次成功');
    Require(LCloseCalls = 1, '关闭通知次数不为一次');
    if LMode = 'limit' then
    begin
      Require((LMainCalls = 1) and (LMainSuccess = 0), '底层拒绝未传成 WS 一次 False');
      Require((LTailCalls = 1) and (LTailSuccess = 0), '排队消息未恰好一次取消');
      Require(LReadCalls = 1, '失败后继续读取了 provider');
    end;
  finally
    if LKeepServer <> nil then LKeepServer.Stop;
    {$IFDEF CROSS_CAPACITY_TESTS}
    CrossSendRejectedForTest := nil;
    LRejectedConnection := nil;
    {$ENDIF}
    LConnection := nil; LKeepServer := nil;
    LData := nil;
    LClosed.Free; LTailDone.Free; LMainDone.Free; LSmallDone.Free; LReady.Free;
  end;
end;

begin
  SetTextCodePage(Output, 65001);
  try
    Require(ParamCount = 6, '用法: 模式 SSL Crypto 证书 私钥 TLS版本');
    TSSLTools.LibSSL := ParamStr(2); TSSLTools.LibCRYPTO := ParamStr(3);
    TSSLTools.LoadSSL;
    try RunServer; finally TSSLTools.UnloadSSL; end;
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do begin Writeln('FAIL ', E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
