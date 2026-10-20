program HostFallbackProbe;
{$I ../../../../zLib.inc}
uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  {$IFDEF MSWINDOWS}Net.Winsock2,{$ELSE}
    {$IFDEF FPC}Sockets, BaseUnix,{$ELSE}Posix.SysSocket, Posix.NetinetIn,{$ENDIF}
  {$ENDIF}
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket;

type
  TProbeSocket = class(TCrossSocket);

var
  Calls, Successes: Integer;
  Done: TEvent;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

function ResolveFamilies(const APort: Word): string;
var
  LHints: TRawAddrInfo;
  LInfo, LItem: PRawAddrInfo;
  LFamily: string;
begin
  FillChar(LHints, SizeOf(LHints), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LInfo := TSocketAPI.GetAddrInfo('localhost', APort, LHints);
  Check(LInfo <> nil, 'localhost resolution failed');
  Result := '';
  try
    LItem := LInfo;
    while LItem <> nil do
    begin
      if LItem.ai_family = AF_INET then LFamily := '4' else
      if LItem.ai_family = AF_INET6 then LFamily := '6' else LFamily := '?';
      if Pos(LFamily, Result) = 0 then Result := Result + LFamily;
      LItem := PRawAddrInfo(LItem.ai_next);
    end;
  finally
    TSocketAPI.FreeAddrInfo(LInfo);
  end;
end;

function ConnectCallback: TCrossConnectionCallback;
begin
  Result := procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      AtomicIncrement(Calls);
      if ASuccess then
      begin
        AtomicIncrement(Successes);
        if AConnection <> nil then AConnection.Close;
      end;
      Done.SetEvent;
    end;
end;

procedure Run;
var
  LSocket: TProbeSocket;
  LFamilies: string;
  LPort: Word;
  LSignaled: Boolean;
begin
  CrossSocketLogEnabled := False;
  if ParamStr(1) = 'discover' then
  begin
    Writeln('FAMILIES ', ResolveFamilies(1));
    Exit;
  end;
  LPort := StrToInt(ParamStr(1));
  LFamilies := ResolveFamilies(LPort);
  Check(LFamilies = ParamStr(2), 'localhost address order changed');
  LSocket := TProbeSocket.Create(2);
  Done := TEvent.Create(nil, True, False, '');
  try
    // 使用公开Connect及系统解析器；不能覆盖解析方法或改变生产代码语义。
    LSocket.Connect('localhost', LPort, 0, ConnectCallback());
    LSignaled := Done.WaitFor(10000) = wrSignaled;
    LSocket.CloseAll;
    LSocket.StopLoop;
    Writeln('OBSERVED localhost families=', LFamilies, ' callbacks=', Calls,
      ' successful=', Successes, ' remaining=', LSocket.ConnectionsCount);
    Check(LSignaled, 'callback timed out');
    Check(Calls = 1, 'callback count is not exactly one');
    Check(Successes = 1, 'later localhost address was not attempted successfully');
    Check(LSocket.ConnectionsCount = 0, 'closed connection remains registered');
    Writeln('PASS host-fallback');
  finally
    LSocket.Free;
    Done.Free;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
