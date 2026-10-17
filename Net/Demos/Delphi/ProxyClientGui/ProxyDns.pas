unit ProxyDns;

interface

uses
  System.SysUtils,
  Net.SocketAPI,
  Net.Winsock2,
  Net.CrossProxy;

const
  DNS_DIRECT_SERVER = '223.5.5.5';
  DNS_PROXY_SERVER = '8.8.8.8';

function QueryDnsA(const AServer: string; const AProxy: TCrossProxySettings): string;
function QueryDnsAAAA(const AServer: string; const AProxy: TCrossProxySettings): string;

implementation

procedure SendAll(const S: TSocket; const B; N: Integer);
var
  P, C: Integer;
begin
  P := 0;
  while P < N do begin
    C := TSocketAPI.Send(S, PByte(@B)[P], N - P);
    if C <= 0 then
      raise Exception.Create('DNS send failed');
    Inc(P, C);
  end;
end;

procedure ReadAll(const S: TSocket; var B; N: Integer);
var
  P, C: Integer;
begin
  P := 0;
  while P < N do begin
    C := TSocketAPI.Recv(S, PByte(@B)[P], N - P);
    if C <= 0 then
      raise Exception.Create('DNS receive failed');
    Inc(P, C);
  end;
end;

function QueryDnsType(const AServer: string; const AProxy: TCrossProxySettings; const AType: Word): string;
var
  Q: array[0..27] of Byte;
var
  H: TRawAddrInfo;
  I: PRawAddrInfo;
  S: TSocket;
  P, A: TBytes;
  R: array[0..2047] of Byte;
  G: array[0..3] of Byte;
  Auth, UserBytes, PasswordBytes: TBytes;
  LenBuf: array[0..1] of Byte;
  N, L, O, C: Integer;
  B: array[0..3] of Byte;
  IP: string;
begin
  Q[0] := $CA;
  Q[1] := $FE;
  Q[2] := $01;
  Q[3] := $00;
  Q[4] := $00;
  Q[5] := $01;
  Q[6] := $00;
  Q[7] := $00;
  Q[8] := $00;
  Q[9] := $00;
  Q[10] := $00;
  Q[11] := $00;
  Q[12] := $05;
  Q[13] := $61;
  Q[14] := $70;
  Q[15] := $70;
  Q[16] := $6C;
  Q[17] := $65;
  Q[18] := $03;
  Q[19] := $63;
  Q[20] := $6F;
  Q[21] := $6D;
  Q[22] := $00;
  Q[23] := AType shr 8;
  Q[24] := AType and $FF;
  Q[25] := $00;
  Q[26] := $01;
  if AProxy.IsEnabled and (AProxy.ProxyType <> cptSocks5) then
    raise Exception.Create('DNS proxy test currently requires SOCKS5');
  FillChar(H, SizeOf(H), 0);
  H.ai_family := AF_UNSPEC;
  H.ai_socktype := SOCK_STREAM;
  H.ai_protocol := IPPROTO_TCP;
  I := TSocketAPI.GetAddrInfo(AProxy.Host, AProxy.Port, H);
  if not AProxy.IsEnabled then begin
    TSocketAPI.FreeAddrInfo(I);
    I := TSocketAPI.GetAddrInfo(AServer, 53, H);
  end;
  if I = nil then
    raise Exception.Create('DNS endpoint resolve failed');
  try
    S := TSocketAPI.NewSocket(I.ai_family, SOCK_STREAM, IPPROTO_TCP);
    try
      if TSocketAPI.Connect(S, I.ai_addr, I.ai_addrlen) <> 0 then
        raise Exception.Create('DNS endpoint connect failed');
      TSocketAPI.SetRecvTimeout(S, 5000);
      if AProxy.IsEnabled then begin
        if (AProxy.Username <> '') or (AProxy.Password <> '') then begin
          G[0] := $05;
          G[1] := $02;
          G[2] := $00;
          G[3] := $02;
          SendAll(S, G, 4);
          ReadAll(S, G, 2);
          if G[1] <> $02 then
            raise Exception.Create('SOCKS5 proxy did not select username/password authentication');
          if (Length(AProxy.Username) > 255) or (Length(AProxy.Password) > 255) then
            raise Exception.Create('SOCKS5 credentials exceed 255 bytes');
          UserBytes := TEncoding.ASCII.GetBytes(AProxy.Username);
          PasswordBytes := TEncoding.ASCII.GetBytes(AProxy.Password);
          SetLength(Auth, 3 + Length(UserBytes) + Length(PasswordBytes));
          Auth[0] := $01;
          Auth[1] := Length(UserBytes);
          if Length(UserBytes) > 0 then
            Move(UserBytes[0], Auth[2], Length(UserBytes));
          Auth[2 + Length(UserBytes)] := Length(PasswordBytes);
          if Length(PasswordBytes) > 0 then
            Move(PasswordBytes[0], Auth[3 + Length(UserBytes)], Length(PasswordBytes));
          SendAll(S, Auth[0], Length(Auth));
          ReadAll(S, G, 2);
          if (G[0] <> $01) or (G[1] <> $00) then
            raise Exception.Create('SOCKS5 username/password authentication failed');
        end
        else begin
          G[0] := $05;
          G[1] := $01;
          G[2] := $00;
          SendAll(S, G, 3);
          ReadAll(S, G, 2);
          if G[1] <> 0 then
            raise Exception.Create('SOCKS5 authentication required');
        end;
        SetLength(A, 10);
        FillChar(A[0], 10, 0);
        A[0] := $05;
        A[1] := $01;
        A[3] := $01;
        A[4] := 8;
        A[5] := 8;
        A[6] := 8;
        A[7] := 8;
        A[8] := 0;
        A[9] := 53;
        SendAll(S, A[0], 10);
        ReadAll(S, A[0], 4);
        if A[1] <> 0 then
          raise Exception.Create('SOCKS5 connect to DNS failed');
        ReadAll(S, A[0], 6);
      end;
      SetLength(P, 29);
      P[0] := 0;
      P[1] := 27;
      Move(Q[0], P[2], 27);
      SendAll(S, P[0], Length(P));
      ReadAll(S, LenBuf[0], 2);
      L := LenBuf[0] shl 8 or LenBuf[1];
      if L > SizeOf(R) then
        raise Exception.Create('DNS response too large');
      ReadAll(S, R[0], L);
      O := 12;
      while (O < L) and (R[O] <> 0) do
        Inc(O, R[O] + 1);
      Inc(O, 5);
      C := R[6] shl 8 or R[7];
      while (C > 0) and (O + 11 < L) do begin
        if (R[O] and $C0) = $C0 then
          Inc(O, 2)
        else begin
          while (O < L) and (R[O] <> 0) do
            Inc(O, R[O] + 1);
          Inc(O);
        end;
        N := R[O] shl 8 or R[O + 1];
        Inc(O, 2);
        Inc(O, 2);
        Inc(O, 4);
        L := L;
        if (N = AType) and (O + 1 < L) then begin
          N := R[O] shl 8 or R[O + 1];
          Inc(O, 2);
          if (AType = 1) and (N = 4) then begin
            IP := Format('%d.%d.%d.%d', [R[O], R[O + 1], R[O + 2], R[O + 3]]);
            Break;
          end
          else if (AType = 28) and (N = 16) then begin
            IP :=
                Format(
                    '%x:%x:%x:%x:%x:%x:%x:%x',
                    [
                        R[O] shl 8 or R[O + 1],
                        R[O + 2] shl 8 or R[O + 3],
                        R[O + 4] shl 8 or R[O + 5],
                        R[O + 6] shl 8 or R[O + 7],
                        R[O + 8] shl 8 or R[O + 9],
                        R[O + 10] shl 8 or R[O + 11],
                        R[O + 12] shl 8 or R[O + 13],
                        R[O + 14] shl 8 or R[O + 15]
                    ]
                );
            Break;
          end;
          Inc(O, N);
        end
        else
          Inc(O, N);
        Dec(C);
      end;
      Result := IP;
    finally
      TSocketAPI.CloseSocket(S);
    end;
  finally
    TSocketAPI.FreeAddrInfo(I);
  end;
end;

function QueryDnsA(const AServer: string; const AProxy: TCrossProxySettings): string;
begin
  Result := QueryDnsType(AServer, AProxy, 1);
end;

function QueryDnsAAAA(const AServer: string; const AProxy: TCrossProxySettings): string;
begin
  Result := QueryDnsType(AServer, AProxy, 28);
end;

end.
