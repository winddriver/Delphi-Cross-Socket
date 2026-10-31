program ProxyClient;

{$APPTYPE CONSOLE}
{$I zLib.inc}

uses
  SysUtils,
  Classes,
  Net.CrossSocket.Base,
  Net.CrossProxy,
  Net.CrossHttpClient,
  Net.CrossHttpParams,
  Net.CrossWebSocketClient,
  Net.CrossWebSocketParser,
  Net.SocketAPI,
  Net.Winsock2,
  Winapi.Windows,
  Net.OpenSSL,
  Utils.Utils;

function ProxyTypeOf(const AValue: string): TCrossProxyType;
begin
  if SameText(AValue, 'http') then Exit(cptHttp);
  if SameText(AValue, 'https') then Exit(cptHttps);
  if SameText(AValue, 'socks4') then Exit(cptSocks4);
  if SameText(AValue, 'socks5') then Exit(cptSocks5);
  Result := cptDirect;
end;

procedure Usage;
begin
  Writeln('ProxyClient <http|doh|udp|ws> <proxy-type> <proxy-host> <proxy-port> [user] [password]');
  Writeln('Examples:');
  Writeln('  ProxyClient http socks5 127.0.0.1 10808');
  Writeln('  ProxyClient doh http 127.0.0.1 10809');
  Writeln('  ProxyClient ws socks5 127.0.0.1 10808');
  Writeln('  ProxyClient udp direct 0 0');
  Writeln('proxy-type: direct, http, https, socks4, socks5');
end;

function ReadSocketBytes(const ASocket: TSocket; var ABuffer; const ACount: Integer): Boolean;
var
  LOffset, LCount: Integer;
begin
  LOffset := 0;
  while LOffset < ACount do
  begin
    LCount := TSocketAPI.Recv(ASocket, PByte(@ABuffer)[LOffset], ACount - LOffset);
    if LCount <= 0 then
      Exit(False);
    Inc(LOffset, LCount);
  end;
  Result := True;
end;

procedure SendSocketBytes(const ASocket: TSocket; const ABuffer; const ACount: Integer);
begin
  if TSocketAPI.Send(ASocket, ABuffer, ACount) <> ACount then
    raise Exception.Create('Short write during SOCKS5 UDP handshake');
end;

procedure TestSocks5Udp(const ASettings: TCrossProxySettings);
const
  CQuery: array[0..31] of Byte =
    ($CA, $FE, $01, $00, $00, $01, $00, $00, $00, $00, $00, $00,
     $03, $77, $77, $77, $06, $67, $6F, $6F, $67, $6C, $65, $03,
     $63, $6F, $6D, $00, $00, $01, $00, $01);
var
  LHints: TRawAddrInfo;
  LAddrInfo: PRawAddrInfo;
  LTcpSocket, LUdpSocket: TSocket;
  LGreeting: array[0..2] of Byte;
  LAuth: TBytes;
  LAssociate: array[0..9] of Byte;
  LResponse: array[0..2047] of Byte;
  LPacket: TBytes;
  LRelayAddr: sockaddr_in;
  LFromAddr: sockaddr;
  LFromLen, LSent, LReceived, I: Integer;
  LStarted: Cardinal;
begin
  if ASettings.ProxyType <> cptSocks5 then
    raise Exception.Create('SOCKS5 UDP ASSOCIATE requires proxy-type socks5');
  FillChar(LHints, SizeOf(LHints), 0);
  LHints.ai_family := AF_INET;
  LHints.ai_socktype := SOCK_STREAM;
  LHints.ai_protocol := IPPROTO_TCP;
  LAddrInfo := TSocketAPI.GetAddrInfo(ASettings.Host, ASettings.Port, LHints);
  if LAddrInfo = nil then
    raise Exception.Create('Unable to resolve SOCKS5 proxy');
  try
    LTcpSocket := TSocketAPI.NewSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if TSocketAPI.Connect(LTcpSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) <> 0 then
      raise Exception.Create('Unable to connect SOCKS5 proxy');
    try
      TSocketAPI.SetRecvTimeout(LTcpSocket, 5000);
      LGreeting[0] := $05;
      LGreeting[1] := $01; // NMETHODS
      LGreeting[2] := $00; // NO AUTHENTICATION REQUIRED
      SendSocketBytes(LTcpSocket, LGreeting[0], SizeOf(LGreeting));
      LGreeting[0] := 0;
      if not ReadSocketBytes(LTcpSocket, LGreeting[0], 2) or
        (LGreeting[0] <> $05) then
        raise Exception.CreateFmt('Invalid SOCKS5 method response (%x %x)',
          [LGreeting[0], LGreeting[1]]);
      if LGreeting[1] = $02 then
      begin
        if (Length(ASettings.Username) > 255) or (Length(ASettings.Password) > 255) then
          raise Exception.Create('SOCKS5 credentials exceed 255 bytes');
        SetLength(LAuth, 3 + Length(ASettings.Username) + Length(ASettings.Password));
        LAuth[0] := $01;
        LAuth[1] := Length(ASettings.Username);
        if Length(ASettings.Username) > 0 then
          Move(ASettings.Username[1], LAuth[2], Length(ASettings.Username));
        LAuth[2 + Length(ASettings.Username)] := Length(ASettings.Password);
        if Length(ASettings.Password) > 0 then
          Move(ASettings.Password[1], LAuth[3 + Length(ASettings.Username)], Length(ASettings.Password));
        SendSocketBytes(LTcpSocket, LAuth[0], Length(LAuth));
        if not ReadSocketBytes(LTcpSocket, LGreeting[0], 2) or
          (LGreeting[0] <> $01) or (LGreeting[1] <> $00) then
          raise Exception.Create('SOCKS5 username/password authentication failed');
      end
      else if LGreeting[1] <> $00 then
        raise Exception.CreateFmt('SOCKS5 method %d is not supported', [LGreeting[1]]);
      FillChar(LAssociate, SizeOf(LAssociate), 0);
      LAssociate[0] := $05;
      LAssociate[1] := $03; // UDP ASSOCIATE
      LAssociate[3] := $01; // IPv4, 0.0.0.0:0
      SendSocketBytes(LTcpSocket, LAssociate[0], SizeOf(LAssociate));
      if not ReadSocketBytes(LTcpSocket, LAssociate[0], 4) or
        (LAssociate[1] <> $00) or (LAssociate[3] <> $01) then
        raise Exception.Create('SOCKS5 UDP ASSOCIATE failed');
      if not ReadSocketBytes(LTcpSocket, LAssociate[4], 6) then
        raise Exception.Create('Incomplete SOCKS5 UDP relay address');
      FillChar(LRelayAddr, SizeOf(LRelayAddr), 0);
      LRelayAddr.sin_family := AF_INET;
      Move(LAssociate[4], LRelayAddr.sin_addr, 4);
      Move(LAssociate[8], LRelayAddr.sin_port, 2);
      // Some local SOCKS listeners return 0.0.0.0 as the relay address.
      // In that case the relay is reachable on the proxy endpoint itself.
      if LRelayAddr.sin_addr.S_addr = 0 then
        LRelayAddr.sin_addr.S_addr := PSockAddrIn(LAddrInfo.ai_addr)^.sin_addr.S_addr;
      LUdpSocket := TSocketAPI.NewSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
      try
        SetLength(LPacket, 4 + 4 + 2 + Length(CQuery));
        FillChar(LPacket[0], Length(LPacket), 0);
        LPacket[2] := 0; // FRAG
        LPacket[3] := 1; // IPv4 target
        LPacket[4] := 1; LPacket[5] := 1; LPacket[6] := 1; LPacket[7] := 1;
        LPacket[8] := 0; LPacket[9] := 53;
        for I := 0 to High(CQuery) do LPacket[10 + I] := CQuery[I];
        LSent := TSocketAPI.SendTo(LUdpSocket, @LRelayAddr, SizeOf(LRelayAddr), LPacket[0], Length(LPacket));
        LFromLen := SizeOf(LFromAddr);
        TSocketAPI.SetNonBlock(LUdpSocket, True);
        LStarted := GetTickCount;
        LReceived := -1;
        while (LReceived <= 0) and (GetTickCount - LStarted < 5000) do
        begin
          LReceived := TSocketAPI.RecvFrom(LUdpSocket, @LFromAddr, LFromLen,
            LResponse[0], Length(LResponse));
          if LReceived <= 0 then
            Sleep(50);
        end;
        if (LSent = Length(LPacket)) and (LReceived > 12) and
          (LResponse[0] = 0) and (LResponse[1] = 0) and
          (LResponse[3] = 1) and (LResponse[10] = $CA) and (LResponse[11] = $FE) then
          Writeln('SOCKS5 UDP DNS success')
        else
          Writeln('SOCKS5 UDP DNS failed (sent=', LSent, ', received=', LReceived, ')');
      finally
        TSocketAPI.CloseSocket(LUdpSocket);
      end;
    finally
      TSocketAPI.CloseSocket(LTcpSocket);
    end;
  finally
    TSocketAPI.FreeAddrInfo(LAddrInfo);
  end;
end;

procedure TestUdp(const ASettings: TCrossProxySettings);
const
  // DNS query: ID=CAFE, recursion desired, QNAME=www.google.com, QTYPE=A.
  CQuery: array[0..31] of Byte =
    ($CA, $FE, $01, $00, $00, $01, $00, $00, $00, $00, $00, $00,
     $03, $77, $77, $77, $06, $67, $6F, $6F, $67, $6C, $65, $03,
     $63, $6F, $6D, $00, $00, $01, $00, $01);
var
  LHints: TRawAddrInfo;
  LAddrInfo: PRawAddrInfo;
  LSocket: TSocket;
  LBuffer: array[0..2047] of Byte;
  LSent, LReceived: Integer;
begin
  if ASettings.ProxyType = cptSocks5 then
  begin
    TestSocks5Udp(ASettings);
    Exit;
  end;
  FillChar(LHints, SizeOf(LHints), 0);
  LHints.ai_family := AF_UNSPEC;
  LHints.ai_socktype := SOCK_DGRAM;
  LHints.ai_protocol := IPPROTO_UDP;
  LAddrInfo := TSocketAPI.GetAddrInfo('8.8.8.8', 53, LHints);
  if LAddrInfo = nil then
    raise Exception.Create('Unable to resolve the UDP test endpoint');
  try
    LSocket := TSocketAPI.NewSocket(LAddrInfo.ai_family, SOCK_DGRAM, IPPROTO_UDP);
    if not TSocketAPI.IsValidSocket(LSocket) then
      raise Exception.Create('Unable to create UDP socket');
    try
      TSocketAPI.SetRecvTimeout(LSocket, 5000);
      if TSocketAPI.Connect(LSocket, LAddrInfo.ai_addr, LAddrInfo.ai_addrlen) <> 0 then
        raise Exception.Create('Unable to connect the UDP test socket');
      LSent := TSocketAPI.Send(LSocket, CQuery[0], Length(CQuery));
      LReceived := TSocketAPI.Recv(LSocket, LBuffer[0], Length(LBuffer));
      if (LSent = Length(CQuery)) and (LReceived >= 12) and
        (LBuffer[0] = $CA) and (LBuffer[1] = $FE) then
        Writeln('UDP DNS success via the local routing/proxy stack')
      else
        Writeln('UDP DNS failed (sent=', LSent, ', received=', LReceived, ')');
    finally
      TSocketAPI.CloseSocket(LSocket);
    end;
  finally
    TSocketAPI.FreeAddrInfo(LAddrInfo);
  end;
end;

function SettingsFromArgs: TCrossProxySettings;
var
  LType: TCrossProxyType;
begin
  LType := ProxyTypeOf(ParamStr(2));
  if LType = cptDirect then
    Exit(TCrossProxySettings.Direct);
  Result := TCrossProxySettings.Create(LType, ParamStr(3), StrToInt(ParamStr(4)),
    ParamStr(5), ParamStr(6));
end;

procedure TestHttp(const ASettings: TCrossProxySettings; const AUrl: string);
var
  LClient: ICrossHttpClient;
begin
  LClient := TCrossHttpClient.Create;
  LClient.ProxySettings := ASettings;
  // This is a connectivity probe; certificate validation is outside this Demo's scope.
  LClient.VerifyPeer := False;
  Writeln('HTTP GET ', AUrl, ' via ', ParamStr(2));
  LClient.DoRequest('GET', AUrl, THttpHeader(nil), Pointer(nil), 0, TStream(nil),
    procedure(const ARequest: ICrossHttpClientRequest)
    begin
      if SameText(ParamStr(1), 'doh') then
        ARequest.Header['Accept'] := 'application/dns-json';
    end,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      if AResponse = nil then
        Writeln('FAILED: no response')
      else if AResponse.Content = nil then
        Writeln('FAILED: ', AResponse.StatusCode, ' ', AResponse.StatusText)
      else begin
        Writeln(AResponse.StatusCode, ' ', AResponse.StatusText);
        Writeln(TUtils.GetString(AResponse.Content));
      end;
    end);
  Readln;
end;

procedure TestWebSocket(const ASettings: TCrossProxySettings);
var
  LManager: TCrossWebSocketMgr;
  LSocket: ICrossWebSocket;
begin
  LManager := TCrossWebSocketMgr.Create;
  LManager.ProxySettings := ASettings;
  LSocket := LManager.CreateWebSocket('wss://ws.postman-echo.com/raw');
  LSocket.OnOpen(procedure begin Writeln('WebSocket OPEN'); LSocket.Send('cross-socket proxy demo'); end);
  LSocket.OnMessage(procedure(const AType: TWsMessageType; const AData: TBytes)
    begin Writeln('WebSocket MESSAGE: ', TUtils.GetString(AData)); end);
  LSocket.OnClose(procedure begin Writeln('WebSocket CLOSE'); end);
  LSocket.Open;
end;

var
  LSettings: TCrossProxySettings;
begin
  CrossSocketLogEnabled := False;
  if ParamCount < 4 then begin Usage; Exit; end;
  try
    LSettings := SettingsFromArgs;
    if SameText(ParamStr(1), 'http') then
      TestHttp(LSettings, 'https://www.google.com/')
    else if SameText(ParamStr(1), 'doh') then
      TestHttp(LSettings, 'https://cloudflare-dns.com/dns-query?name=www.google.com&type=A')
    else if SameText(ParamStr(1), 'ws') then
      TestWebSocket(LSettings)
    else if SameText(ParamStr(1), 'udp') then
      TestUdp(LSettings)
    else begin Usage; Exit; end;
    if not SameText(ParamStr(1), 'ws') then
      Exit;
    Readln;
  except
    on E: Exception do Writeln(E.ClassName, ': ', E.Message);
  end;
end.
