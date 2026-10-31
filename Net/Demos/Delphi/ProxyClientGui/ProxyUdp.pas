unit ProxyUdp;

interface

uses
  System.SysUtils,
  Net.SocketAPI,
  Net.Winsock2,
  Net.CrossProxy;

const
  UDP_DIRECT_DNS_SERVER = '223.5.5.5';
  UDP_PROXY_DNS_SERVER = '1.1.1.1';

function TestUdpDns(const ASettings: TCrossProxySettings;
  const AUseAuth: Boolean): string;

implementation

function BuildDnsQuery(const AType: Word): TBytes;
begin
  Result := [$CA, $FE, $01, $00, $00, $01, $00, $00, $00, $00, $00, $00,
    $05, $61, $70, $70, $6C, $65, $03, $63, $6F, $6D, $00,
    Byte(AType shr 8), Byte(AType), $00, $01];
end;

function ParseDnsAddress(const ABuffer; const ALength, AType: Integer): string;
var
  B: PByte; O, I, Count, RType, RLength: Integer;
begin
  Result := '';
  if ALength < 12 then Exit;
  B := @ABuffer;
  O := 12;
  while (O < ALength) and (B[O] <> 0) do Inc(O, B[O] + 1);
  Inc(O, 5);
  Count := (B[6] shl 8) or B[7];
  for I := 1 to Count do
  begin
    if O >= ALength then Exit;
    if (B[O] and $C0) = $C0 then Inc(O, 2)
    else begin while (O < ALength) and (B[O] <> 0) do Inc(O, B[O] + 1); Inc(O); end;
    if O + 10 >= ALength then Exit;
    RType := (B[O] shl 8) or B[O + 1];
    RLength := (B[O + 8] shl 8) or B[O + 9];
    Inc(O, 10);
    if O + RLength > ALength then Exit;
    if (RType = AType) and (AType = 1) and (RLength = 4) then
      Exit(Format('%d.%d.%d.%d', [B[O], B[O + 1], B[O + 2], B[O + 3]]));
    if (RType = AType) and (AType = 28) and (RLength = 16) then
      Exit(Format('%x:%x:%x:%x:%x:%x:%x:%x', [
        (B[O] shl 8) or B[O+1], (B[O+2] shl 8) or B[O+3],
        (B[O+4] shl 8) or B[O+5], (B[O+6] shl 8) or B[O+7],
        (B[O+8] shl 8) or B[O+9], (B[O+10] shl 8) or B[O+11],
        (B[O+12] shl 8) or B[O+13], (B[O+14] shl 8) or B[O+15]]));
    Inc(O, RLength);
  end;
end;

function ReadBytes(const ASocket: TSocket; var ABuffer; const ACount: Integer): Boolean;
var
  LOffset, LRead: Integer;
begin
  LOffset := 0;
  while LOffset < ACount do
  begin
    LRead := TSocketAPI.Recv(ASocket, PByte(@ABuffer)[LOffset], ACount - LOffset);
    if LRead <= 0 then Exit(False);
    Inc(LOffset, LRead);
  end;
  Result := True;
end;

procedure WriteBytes(const ASocket: TSocket; const ABuffer; const ACount: Integer);
begin
  if TSocketAPI.Send(ASocket, ABuffer, ACount) <> ACount then
    raise Exception.Create('Short write during SOCKS5 UDP handshake');
end;

function TestDirectUdp(const AType: Word): string;
var
  LH: TRawAddrInfo;
  LI: PRawAddrInfo;
  LS: TSocket;
  LBuf: array[0..2047] of Byte;
  LQuery: TBytes;
  LSent, LReceived: Integer;
begin
  FillChar(LH, SizeOf(LH), 0);
  LH.ai_family := AF_INET;
  LH.ai_socktype := SOCK_DGRAM;
  LH.ai_protocol := IPPROTO_UDP;
  LI := TSocketAPI.GetAddrInfo(UDP_DIRECT_DNS_SERVER, 53, LH);
  if LI = nil then raise Exception.Create('Unable to resolve UDP DNS server');
  try
    LS := TSocketAPI.NewSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if not TSocketAPI.IsValidSocket(LS) then raise Exception.Create('Unable to create UDP socket');
    try
      TSocketAPI.SetRecvTimeout(LS, 5000);
      if TSocketAPI.Connect(LS, LI.ai_addr, LI.ai_addrlen) <> 0 then
        raise Exception.Create('Unable to connect UDP DNS server');
      LQuery := BuildDnsQuery(AType);
      LSent := TSocketAPI.Send(LS, LQuery[0], Length(LQuery));
      LReceived := TSocketAPI.Recv(LS, LBuf[0], Length(LBuf));
      if (LSent = Length(LQuery)) and (LReceived >= 12) and
         (LBuf[0] = $CA) and (LBuf[1] = $FE) then
        Result := ParseDnsAddress(LBuf, LReceived, AType)
      else
        Result := Format('UDP DNS failed, sent=%d received=%d', [LSent, LReceived]);
    finally
      TSocketAPI.CloseSocket(LS);
    end;
  finally
    TSocketAPI.FreeAddrInfo(LI);
  end;
end;

function TestSocks5Udp(const ASettings: TCrossProxySettings;
  const AUseAuth: Boolean; const AType: Word): string;
var
  LH: TRawAddrInfo;
  LI: PRawAddrInfo;
  LTcp, LUdp: TSocket;
  LMethod, LAssociate: array[0..21] of Byte;
  LAuth, LPacket, LQuery, LUserBytes, LPasswordBytes: TBytes;
  LResponse: array[0..2047] of Byte;
  LRelay: TRawSockAddrIn;
  LFrom: TRawSockAddrIn;
  LDnsHints: TRawAddrInfo;
  LDnsInfo: PRawAddrInfo;
  LRelayLen, LFromLen, LSent, LReceived, I: Integer;
begin
  FillChar(LH, SizeOf(LH), 0);
  LH.ai_family := AF_UNSPEC; LH.ai_socktype := SOCK_STREAM; LH.ai_protocol := IPPROTO_TCP;
  LI := TSocketAPI.GetAddrInfo(ASettings.Host, ASettings.Port, LH);
  if LI = nil then raise Exception.Create('Unable to resolve SOCKS5 proxy');
  try
    LTcp := TSocketAPI.NewSocket(LI.ai_family, SOCK_STREAM, IPPROTO_TCP);
    if TSocketAPI.Connect(LTcp, LI.ai_addr, LI.ai_addrlen) <> 0 then
      raise Exception.Create('Unable to connect SOCKS5 proxy');
    try
      TSocketAPI.SetRecvTimeout(LTcp, 5000);
      // Use Auth 关闭时只声明无认证，避免客户端意外尝试用户名密码认证。
      LMethod[0] := 5; LMethod[1] := 1; LMethod[2] := Ord(AUseAuth) * 2;
      WriteBytes(LTcp, LMethod[0], 3);
      if not ReadBytes(LTcp, LMethod[0], 2) or (LMethod[0] <> 5) then
        raise Exception.Create('Invalid SOCKS5 method response');
      if LMethod[1] = 2 then
      begin
        if not AUseAuth then
          raise Exception.Create('SOCKS5 proxy selected authentication unexpectedly');
        LUserBytes := TEncoding.ASCII.GetBytes(ASettings.Username);
        LPasswordBytes := TEncoding.ASCII.GetBytes(ASettings.Password);
        SetLength(LAuth, 3 + Length(LUserBytes) + Length(LPasswordBytes));
        LAuth[0] := 1; LAuth[1] := Length(LUserBytes);
        if Length(LUserBytes) > 0 then Move(LUserBytes[0], LAuth[2], Length(LUserBytes));
        LAuth[2 + Length(LUserBytes)] := Length(LPasswordBytes);
        if Length(LPasswordBytes) > 0 then Move(LPasswordBytes[0], LAuth[3 + Length(LUserBytes)], Length(LPasswordBytes));
        WriteBytes(LTcp, LAuth[0], Length(LAuth));
        if not ReadBytes(LTcp, LMethod[0], 2) or (LMethod[1] <> 0) then
          raise Exception.Create('SOCKS5 username/password authentication failed');
      end else if LMethod[1] <> 0 then
        raise Exception.Create('SOCKS5 proxy rejected the requested authentication method');
      FillChar(LAssociate, SizeOf(LAssociate), 0);
      LAssociate[0] := 5; LAssociate[1] := 3; LAssociate[3] := 1;
      WriteBytes(LTcp, LAssociate[0], 10);
      if not ReadBytes(LTcp, LAssociate[0], 4) or (LAssociate[1] <> 0) or
        not (LAssociate[3] in [1, 4]) then
        raise Exception.Create('SOCKS5 UDP ASSOCIATE failed');
      if LAssociate[3] = 1 then
      begin
        if not ReadBytes(LTcp, LAssociate[4], 6) then raise Exception.Create('Incomplete IPv4 UDP relay address');
        FillChar(LRelay, SizeOf(LRelay), 0); LRelay.Addr.sin_family := AF_INET;
        Move(LAssociate[4], LRelay.Addr.sin_addr, 4); Move(LAssociate[8], LRelay.Addr.sin_port, 2);
        if LRelay.Addr.sin_addr.S_addr = 0 then LRelay.Addr.sin_addr.S_addr := PSockAddrIn(LI.ai_addr)^.sin_addr.S_addr;
        LRelayLen := SizeOf(sockaddr_in);
      end
      else
      begin
        if not ReadBytes(LTcp, LAssociate[4], 18) then raise Exception.Create('Incomplete IPv6 UDP relay address');
        FillChar(LRelay, SizeOf(LRelay), 0); LRelay.Addr6.sin6_family := AF_INET6;
        Move(LAssociate[4], LRelay.Addr6.sin6_addr, 16); Move(LAssociate[20], LRelay.Addr6.sin6_port, 2);
        if IN6ADDR_ISANY(@LRelay.Addr6.sin6_addr) then LRelay.Addr6.sin6_addr := PSockAddrIn6(LI.ai_addr)^.sin6_addr;
        LRelayLen := SizeOf(sockaddr_in6);
      end;
      LUdp := TSocketAPI.NewSocket(LRelay.Addr.sin_family, SOCK_DGRAM, IPPROTO_UDP);
      try
        FillChar(LDnsHints, SizeOf(LDnsHints), 0);
        LDnsHints.ai_family := AF_INET;
        LDnsHints.ai_socktype := SOCK_DGRAM;
        LDnsHints.ai_protocol := IPPROTO_UDP;
        LDnsInfo := TSocketAPI.GetAddrInfo(UDP_PROXY_DNS_SERVER, 53, LDnsHints);
        if LDnsInfo = nil then
          raise Exception.Create('Unable to resolve proxy UDP DNS server');
        try
        LQuery := BuildDnsQuery(AType);
        SetLength(LPacket, 10 + Length(LQuery)); FillChar(LPacket[0], Length(LPacket), 0);
        // 代理 UDP 测试使用独立的 DNS 服务器，和 direct 模式区分开。
        LPacket[3] := 1;
        // UDP_PROXY_DNS_SERVER is used as the actual SOCKS5 UDP target.
        Move(PSockAddrIn(LDnsInfo.ai_addr)^.sin_addr, LPacket[4], 4);
        LPacket[8] := 0; LPacket[9] := 53;
        for I := 0 to High(LQuery) do LPacket[10 + I] := LQuery[I];
        // TRawSockAddrIn 头部包含 AddrLen，SendTo 必须传入实际 sockaddr 联合体地址。
        if LRelay.Addr.sin_family = AF_INET then
          LSent := TSocketAPI.SendTo(LUdp, @LRelay.Addr, LRelayLen, LPacket[0], Length(LPacket))
        else
          LSent := TSocketAPI.SendTo(LUdp, @LRelay.Addr6, LRelayLen, LPacket[0], Length(LPacket));
        // IPv6 UDP relay 可能返回 sockaddr_in6，接收地址缓冲区不能使用 16 字节 sockaddr。
        LFromLen := SizeOf(sockaddr_in6);
        LReceived := TSocketAPI.RecvFrom(LUdp, @LFrom.Addr, LFromLen, LResponse[0], Length(LResponse));
        if (LSent = Length(LPacket)) and (LReceived > 12) and (LResponse[3] = 1) and
           (LResponse[10] = $CA) and (LResponse[11] = $FE) then
          Result := ParseDnsAddress(LResponse[10], LReceived - 10, AType)
        else Result := Format('SOCKS5 UDP DNS failed, sent=%d received=%d', [LSent, LReceived]);
        finally TSocketAPI.FreeAddrInfo(LDnsInfo); end;
      finally TSocketAPI.CloseSocket(LUdp); end;
    finally TSocketAPI.CloseSocket(LTcp); end;
  finally TSocketAPI.FreeAddrInfo(LI); end;
end;

function TestUdpDns(const ASettings: TCrossProxySettings;
  const AUseAuth: Boolean): string;
begin
  if ASettings.ProxyType <> cptSocks5 then
    if ASettings.IsEnabled then
      Exit('UDP proxy test is supported only for socks5 (UDP ASSOCIATE)');
  if ASettings.IsEnabled then
  begin
    Result := 'UDP DNS A apple.com -> ' + TestSocks5Udp(ASettings, AUseAuth, 1) + sLineBreak;
    Result := Result + 'UDP DNS AAAA apple.com -> ' + TestSocks5Udp(ASettings, AUseAuth, 28);
  end
  else
  begin
    Result := 'UDP DNS A apple.com -> ' + TestDirectUdp(1) + sLineBreak;
    Result := Result + 'UDP DNS AAAA apple.com -> ' + TestDirectUdp(28);
  end;
end;

end.
