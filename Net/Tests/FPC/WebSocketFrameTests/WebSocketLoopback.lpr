program WebSocketLoopback;
{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
uses SysUtils, Classes, SyncObjs, Net.CrossSocket.Base, Net.CrossWebSocketParser,
  Net.CrossWebSocketServer, Net.CrossWebSocketClient;
procedure Server;
var S:ICrossWebSocketServer; Ready:TEvent; Port:Word; Line:string;
begin
  Ready:=TEvent.Create(nil,True,False,'');
  try
    S:=TCrossWebSocketServer.Create(2,False);S.Addr:='127.0.0.1';S.Port:=0;Port:=0;
    S.OnOpen(procedure(const C:ICrossWebSocketConnection)
      begin
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
begin
  try
    if ParamStr(1)='server' then Server else Client;
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
