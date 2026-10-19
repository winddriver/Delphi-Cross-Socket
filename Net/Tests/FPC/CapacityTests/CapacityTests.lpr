program CapacityTests;
{$I zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,cwstring,{$ENDIF}
  SysUtils,Classes,Generics.Collections,Utils.SyncObjs,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  Net.SocketAPI,Net.CrossSocket.Base,Net.CrossSocket,Net.CrossHttpUtils,Net.CrossHttpClient;
procedure Check(const OK:Boolean;const Message:string);
begin if not OK then begin Writeln('FAIL ',Message);Flush(Output);Halt(1);end;end;
procedure Await(const Event:IEvent;const Message:string);
begin Check(Event.WaitFor(5000)=TWaitResult.wrSignaled,Message);end;
procedure Line(const Value:string);
begin Writeln(Value);Flush(Output);end;
{$I ClientCapacityTests.inc}
{$I ClientNetworkTests.inc}
{$I ClientRaceTests.inc}
{$I SocketConnectGapTests.inc}
{$I SocketCapacityTests.inc}
{$I SocketSendBench.inc}
begin
  try
    if ParamStr(1)='socket-connect-gap' then TestSocketConnectGap(StrToInt(ParamStr(2)))
    else if ParamStr(1).StartsWith('socket-') then RunSocketCapacity(ParamStr(1))
    else if ParamStr(1).StartsWith('client-race-') then TestClientClosingRace(ParamStr(1),ParamStr(2))
    else if ParamStr(1).StartsWith('client-tcp-') then TestClientNetwork(ParamStr(1),ParamStr(2))
    else TestClientCapacity(ParamStr(1));
    Line('PASS '+ParamStr(1));
  except on E:Exception do begin Line('FAIL '+E.ClassName+': '+E.Message);Halt(1);end;end;
end.
