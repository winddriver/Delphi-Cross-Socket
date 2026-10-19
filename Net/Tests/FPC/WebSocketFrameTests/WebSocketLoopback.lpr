program WebSocketLoopback;
{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
uses {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, SyncObjs, Net.CrossSocket.Base, Net.CrossWebSocketParser, Net.CrossHttpClient,
  Net.CrossWebSocketServer, Net.CrossWebSocketClient;
procedure Server;
var S:ICrossWebSocketServer; Ready:TEvent; Port:Word; Line:string; Opens:Integer;
begin
  Opens:=0;
  Ready:=TEvent.Create(nil,True,False,'');
  try
    S:=TCrossWebSocketServer.Create(2,False);S.Addr:='127.0.0.1';S.Port:=0;Port:=0;
    S.OnOpen(procedure(const C:ICrossWebSocketConnection)
      begin
        AtomicIncrement(Opens);
        {$IFDEF WS_NEW_API}
        (C as TCrossWebSocketConnection).SetWebSocketLimits(1024*1024,0,0);
        {$ENDIF}
      end);
    S.OnMessage(procedure(const C:ICrossWebSocketConnection;const K:TWsMessageType;const D:TBytes)
      begin C.WsSend(D);end);
    S.Start(procedure(const L:ICrossListen;const OK:Boolean)
      begin if OK then Port:=L.LocalPort;Ready.SetEvent;end);
    if (Ready.WaitFor(5000)<>wrSignaled) or (Port=0) then raise Exception.Create('listen failed');
    Writeln('READY ',Port);Flush(Output);Readln(Line);
    S.Stop;S:=nil;
    if ParamStr(2)='handshake' then begin Writeln('OPENS ',Opens);Flush(Output);end;
  finally Ready.Free;end;
end;
procedure Client;
var W:ICrossWebSocket; Opened,Closed,Received:TEvent;
begin
  Opened:=TEvent.Create(nil,True,False,'');Closed:=TEvent.Create(nil,True,False,'');Received:=TEvent.Create(nil,True,False,'');
  try
    W:=TCrossWebSocket.Create(ParamStr(2));
    W.OnOpen(procedure begin Opened.SetEvent;end);
    W.OnMessage(procedure(const K:TWsMessageType;const D:TBytes)
      begin Writeln('MESSAGE ',TEncoding.UTF8.GetString(D));Flush(Output);Received.SetEvent;end);
    W.OnClose(procedure begin Closed.SetEvent;end);
    W.Open;
    if Opened.WaitFor(5000)<>wrSignaled then raise Exception.Create('open timeout');
    W.Send('request');
    if ParamStr(3)='local' then begin
      if Received.WaitFor(5000)<>wrSignaled then raise Exception.Create('message timeout');
      W.Close;
    end;
    if Closed.WaitFor(5000)<>wrSignaled then raise Exception.Create('close timeout');
    W:=nil;
    Writeln('CLOSED');Flush(Output);
  finally Received.Free;Closed.Free;Opened.Free;end;
end;
procedure HandshakeClient;
var W:ICrossWebSocket; M:ICrossWebSocketMgr; Done:TEvent; Opens,Closes:Integer; Line:string;
begin
  Done:=TEvent.Create(nil,True,False,'');Opens:=0;Closes:=0;
  try
    M:=TCrossWebSocketMgr.Create(1);
    W:=M.CreateWebSocket(ParamStr(2));
    W.OnOpenRequest(procedure(const R:ICrossHttpClientRequest)
      begin
        if ParamStr(3)='protocol' then R.Header['Sec-WebSocket-Protocol']:='chat, superchat';
        if ParamStr(3)='extension' then R.Header['Sec-WebSocket-Extensions']:='permessage-deflate';
        if ParamStr(3)='invalid-protocol' then R.Header['Sec-WebSocket-Protocol']:='chat bad';
        if ParamStr(3)='key' then R.Header['Sec-WebSocket-Key']:='MDEyMzQ1Njc4OWFiY2RlZg==';
        if ParamStr(3)='key-ows' then R.Header['Sec-WebSocket-Key']:='  MDEyMzQ1Njc4OWFiY2RlZg==  ';
        if ParamStr(3)='filtered-protocol' then R.Header['Sec-WebSocket-Protocol']:='chat'+#13#10;
      end);
    if ParamStr(3)='response-error' then
      W.OnOpenResponse(procedure(const R:ICrossHttpClientResponse)
        begin raise Exception.Create('预期的响应观察回调异常');end);
    W.OnOpen(procedure begin AtomicIncrement(Opens);Done.SetEvent;end);
    W.OnClose(procedure begin AtomicIncrement(Closes);Done.SetEvent;end);
    W.Open;
    if Done.WaitFor(5000)<>wrSignaled then raise Exception.Create('handshake callback timeout');
    Writeln('RESULT ',AtomicCmpExchange(Opens,0,0),' ',AtomicCmpExchange(Closes,0,0));Flush(Output);
    // 父进程先检查线上关闭行为，再允许析构，避免把析构关闭误判成握手拒绝。
    Readln(Line);
    W:=nil;M.CancelAll;M:=nil;
    Writeln('COUNTS ',Opens,' ',Closes);Flush(Output);
  finally W:=nil;M:=nil;Done.Free;end;
end;
begin
  try
    if ParamStr(1)='server' then Server
    else if ParamStr(1)='handshake-client' then HandshakeClient else Client;
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
