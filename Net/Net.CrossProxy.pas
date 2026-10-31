{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                 }
{                                                                              }
{******************************************************************************}
unit Net.CrossProxy;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  System.NetEncoding,
  System.Net.URLClient;

type
  TCrossProxyFeedResult = (
    cpfrNeedData,
    cpfrSendData,
    cpfrComplete,
    cpfrFailed);

  TCrossProxyType = (
    cptDirect,
    cptHttp,
    cptHttps,
    cptSocks4,
    cptSocks5);

  TCrossProxySettings = record
  private
    FEnabled: Boolean;
    FProxyType: TCrossProxyType;
    FHost: string;
    FPort: Word;
    FUsername: string;
    FPassword: string;
    FBypassList: string;
  public
    class function Direct: TCrossProxySettings; static;
    class function Create(const AProxyType: TCrossProxyType;
      const AHost: string; const APort: Word;
      const AUsername: string = ''; const APassword: string = '';
      const ABypassList: string = ''): TCrossProxySettings; static;

    function IsEnabled: Boolean;
    function ShouldBypass(const AHost: string): Boolean;
    function EffectiveBypassList: string;
    function UsesHttpConnect: Boolean;
    function UsesTlsProxyTransport: Boolean;
    function UsesCrossSocketHttp: Boolean;
    function UsesSocks: Boolean;
    function CacheKey: string;
    function HttpProxyAuthorization: string;
    function ToNetProxySettings: System.Net.URLClient.TProxySettings;

    property Enabled: Boolean read FEnabled write FEnabled;
    property ProxyType: TCrossProxyType read FProxyType write FProxyType;
    property Host: string read FHost write FHost;
    property Port: Word read FPort write FPort;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property BypassList: string read FBypassList write FBypassList;
  end;

  TCrossProxySettingsStore = class
  private
    class var FDefaultSettings: TCrossProxySettings;
  public
    class procedure SetDefault(const ASettings: TCrossProxySettings); static;
    class function Default: TCrossProxySettings; static;
    class function ForHost(const AHost: string): TCrossProxySettings; static;
  end;

  TCrossProxyCodec = record
  private
    class function BytesOfAscii(const AValue: string): TBytes; static;
    class function TryParseIPv4(const AHost: string; out AValue: Cardinal): Boolean; static;
    class function TryParseCidr(const ARule: string; out ANetwork,
      AMask: Cardinal): Boolean; static;
  public
    class function BuildHttpConnect(const AHost: string; const APort: Word;
      const AUsername: string = ''; const APassword: string = ''): TBytes; static;
    class function BuildSocks4Connect(const AHost: string; const APort: Word;
      const AUsername: string = ''): TBytes; static;
    class function BuildSocks5Greeting(const AHasCredentials: Boolean): TBytes; static;
    class function BuildSocks5Auth(const AUsername, APassword: string): TBytes; static;
    class function BuildSocks5Connect(const AHost: string; const APort: Word): TBytes; static;

    class function TryParseHttpConnectResponse(const AData: TBytes;
      out AConsumed: Integer; out AStatusCode: Integer): Boolean; static;
    class function TryParseSocks4Response(const AData: TBytes;
      out AConsumed: Integer; out ASuccess: Boolean): Boolean; static;
    class function TryParseSocks5MethodResponse(const AData: TBytes;
      out AConsumed: Integer; out AMethod: Byte): Boolean; static;
    class function TryParseSocks5AuthResponse(const AData: TBytes;
      out AConsumed: Integer; out ASuccess: Boolean): Boolean; static;
    class function TryParseSocks5ConnectResponse(const AData: TBytes;
      out AConsumed: Integer; out ASuccess: Boolean): Boolean; static;
  end;

implementation

const
  CRLF = #13#10;
  DEFAULT_BYPASS_LIST =
    'localhost;127.0.0.0/8;::1;10.0.0.0/8;172.16.0.0/12;192.168.0.0/16;169.254.0.0/16';

function NormalizeHost(const AHost: string): string;
begin
  Result := Trim(AHost).ToLower;
  if (Length(Result) >= 2) and (Result[1] = '[') and
    (Result[Length(Result)] = ']') then
    Result := Result.Substring(1, Length(Result) - 2);
end;

function AppendByte(var AData: TBytes; const AValue: Byte): Integer;
begin
  Result := Length(AData);
  SetLength(AData, Result + 1);
  AData[Result] := AValue;
end;

function AppendBytes(var AData: TBytes; const AValue: TBytes): Integer;
var
  LOffset: Integer;
begin
  LOffset := Length(AData);
  Result := LOffset;
  SetLength(AData, LOffset + Length(AValue));
  if Length(AValue) > 0 then
    Move(AValue[0], AData[LOffset], Length(AValue));
end;

function AppendAscii(var AData: TBytes; const AValue: string): Integer;
begin
  Result := AppendBytes(AData, TCrossProxyCodec.BytesOfAscii(AValue));
end;

class function TCrossProxySettings.Direct: TCrossProxySettings;
begin
  Result.FEnabled := False;
  Result.FProxyType := cptDirect;
  Result.FHost := '';
  Result.FPort := 0;
  Result.FUsername := '';
  Result.FPassword := '';
  Result.FBypassList := '';
end;

class function TCrossProxySettings.Create(const AProxyType: TCrossProxyType;
  const AHost: string; const APort: Word; const AUsername,
  APassword, ABypassList: string): TCrossProxySettings;
begin
  Result := Direct;
  Result.FEnabled := AProxyType <> cptDirect;
  Result.FProxyType := AProxyType;
  Result.FHost := Trim(AHost);
  Result.FPort := APort;
  Result.FUsername := AUsername;
  Result.FPassword := APassword;
  Result.FBypassList := ABypassList;
end;

function TCrossProxySettings.IsEnabled: Boolean;
begin
  Result := FEnabled and (FProxyType <> cptDirect) and
    (FHost <> '') and (FPort <> 0);
end;

function TCrossProxySettings.ShouldBypass(const AHost: string): Boolean;
var
  LRules: TArray<string>;
  LRule, LHost, LCurrentRule: string;
  LValue, LNetwork, LMask: Cardinal;
begin
  LHost := NormalizeHost(AHost);
  if LHost = '' then
    Exit(False);

  if Trim(FBypassList) = '' then
    LRules := DEFAULT_BYPASS_LIST.Split([';'])
  else
    LRules := (DEFAULT_BYPASS_LIST + ';' + FBypassList).Split([';', ',']);

  for LRule in LRules do
  begin
    LCurrentRule := NormalizeHost(LRule);
    if LCurrentRule = '' then
      Continue;

    if SameText(LCurrentRule, '*') or SameText(LCurrentRule, LHost) then
      Exit(True);

    if (LCurrentRule = 'localhost') and SameText(LHost, 'localhost') then
      Exit(True);

    if (LCurrentRule.StartsWith('*.') and
      LHost.EndsWith(LCurrentRule.Substring(1))) then
      Exit(True);

    if TCrossProxyCodec.TryParseIPv4(LHost, LValue) and
      TCrossProxyCodec.TryParseCidr(LCurrentRule, LNetwork, LMask)
      and ((LValue and LMask) = LNetwork) then
      Exit(True);
  end;

  Result := False;
end;

function TCrossProxySettings.EffectiveBypassList: string;
begin
  Result := Trim(FBypassList);
  if Result = '' then
    Result := DEFAULT_BYPASS_LIST;
  if Result <> DEFAULT_BYPASS_LIST then
    Result := DEFAULT_BYPASS_LIST + ';' + Result;
end;

function TCrossProxySettings.UsesHttpConnect: Boolean;
begin
  Result := IsEnabled and (FProxyType in [cptHttp, cptHttps]);
end;

function TCrossProxySettings.UsesTlsProxyTransport: Boolean;
begin
  Result := IsEnabled and (FProxyType = cptHttps);
end;

function TCrossProxySettings.UsesCrossSocketHttp: Boolean;
begin
  Result := IsEnabled and
    (FProxyType in [cptHttps, cptSocks4, cptSocks5]);
end;

function TCrossProxySettings.UsesSocks: Boolean;
begin
  Result := IsEnabled and (FProxyType in [cptSocks4, cptSocks5]);
end;

function TCrossProxySettings.CacheKey: string;
begin
  Result := Format('%d|%s|%d|%s|%s', [
    Ord(FProxyType), NormalizeHost(FHost), FPort,
    FUsername + #0 + FPassword, FBypassList]);
end;

function TCrossProxySettings.HttpProxyAuthorization: string;
begin
  if (FUsername = '') and (FPassword = '') then
    Exit('');

  Result := 'Basic ' + TNetEncoding.Base64.Encode(FUsername + ':' + FPassword);
end;

function TCrossProxySettings.ToNetProxySettings: System.Net.URLClient.TProxySettings;
var
  LScheme: string;
begin
  if not IsEnabled then
    Exit(System.Net.URLClient.TProxySettings.Create('direct', 80, '', '', 'http'));

  case FProxyType of
    cptHttps:
      LScheme := 'https';
    cptSocks4:
      LScheme := 'socks4';
    cptSocks5:
      LScheme := 'socks5';
  else
    LScheme := 'http';
  end;

  Result := System.Net.URLClient.TProxySettings.Create(
    FHost, FPort, FUsername, FPassword, LScheme);
end;

class procedure TCrossProxySettingsStore.SetDefault(
  const ASettings: TCrossProxySettings);
begin
  FDefaultSettings := ASettings;
end;

class function TCrossProxySettingsStore.Default: TCrossProxySettings;
begin
  Result := FDefaultSettings;
end;

class function TCrossProxySettingsStore.ForHost(
  const AHost: string): TCrossProxySettings;
begin
  Result := FDefaultSettings;
  if Result.ShouldBypass(AHost) then
    Result := TCrossProxySettings.Direct;
end;

class function TCrossProxyCodec.BytesOfAscii(const AValue: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(AValue);
end;

class function TCrossProxyCodec.TryParseIPv4(const AHost: string;
  out AValue: Cardinal): Boolean;
var
  LParts: TArray<string>;
  I, LPart: Integer;
begin
  Result := False;
  AValue := 0;
  LParts := NormalizeHost(AHost).Split(['.']);
  if Length(LParts) <> 4 then
    Exit;
  for I := 0 to 3 do
  begin
    if not TryStrToInt(LParts[I], LPart) or (LPart < 0) or (LPart > 255) then
      Exit;
    AValue := (AValue shl 8) or Cardinal(LPart);
  end;
  Result := True;
end;

class function TCrossProxyCodec.TryParseCidr(const ARule: string;
  out ANetwork, AMask: Cardinal): Boolean;
var
  LParts: TArray<string>;
  LPrefix: Integer;
  LValue: Cardinal;
begin
  Result := False;
  ANetwork := 0;
  AMask := 0;
  LParts := ARule.Split(['/']);
  if (Length(LParts) <> 2) or not TryParseIPv4(LParts[0], LValue) or
    not TryStrToInt(LParts[1], LPrefix) or (LPrefix < 0) or (LPrefix > 32) then
    Exit;
  if LPrefix = 0 then
    AMask := 0
  else
    AMask := Cardinal($FFFFFFFF) shl (32 - LPrefix);
  ANetwork := LValue and AMask;
  Result := True;
end;

class function TCrossProxyCodec.BuildHttpConnect(const AHost: string;
  const APort: Word; const AUsername, APassword: string): TBytes;
var
  LAuth: string;
begin
  Result := nil;
  AppendAscii(Result, Format(
    'CONNECT %s:%d HTTP/1.1'#13#10 +
    'Host: %s:%d'#13#10 +
    'Proxy-Connection: keep-alive'#13#10,
    [AHost, APort, AHost, APort]));
  if (AUsername <> '') or (APassword <> '') then
  begin
    LAuth := TNetEncoding.Base64.Encode(AUsername + ':' + APassword);
    AppendAscii(Result, 'Proxy-Authorization: Basic ' + LAuth + CRLF);
  end;
  AppendAscii(Result, CRLF);
end;

class function TCrossProxyCodec.BuildSocks4Connect(const AHost: string;
  const APort: Word; const AUsername: string): TBytes;
var
  LAddress: Cardinal;
begin
  Result := [4, 1, Byte(APort shr 8), Byte(APort)];
  if TryParseIPv4(AHost, LAddress) then
  begin
    AppendByte(Result, Byte(LAddress shr 24));
    AppendByte(Result, Byte(LAddress shr 16));
    AppendByte(Result, Byte(LAddress shr 8));
    AppendByte(Result, Byte(LAddress));
    AppendAscii(Result, AUsername);
    AppendByte(Result, 0);
  end
  else
  begin
    AppendByte(Result, 0);
    AppendByte(Result, 0);
    AppendByte(Result, 0);
    AppendByte(Result, 1);
    AppendAscii(Result, AUsername);
    AppendByte(Result, 0);
    AppendAscii(Result, AHost);
    AppendByte(Result, 0);
  end;
end;

class function TCrossProxyCodec.BuildSocks5Greeting(
  const AHasCredentials: Boolean): TBytes;
begin
  if AHasCredentials then
    Result := [5, 2, 0, 2]
  else
    Result := [5, 1, 0];
end;

class function TCrossProxyCodec.BuildSocks5Auth(const AUsername,
  APassword: string): TBytes;
var
  LUser, LPassword: TBytes;
begin
  LUser := BytesOfAscii(AUsername);
  LPassword := BytesOfAscii(APassword);
  if (Length(LUser) > 255) or (Length(LPassword) > 255) then
    raise EArgumentException.Create('SOCKS5 credentials exceed 255 bytes.');
  Result := [1, Length(LUser)];
  AppendBytes(Result, LUser);
  AppendByte(Result, Length(LPassword));
  AppendBytes(Result, LPassword);
end;

class function TCrossProxyCodec.BuildSocks5Connect(const AHost: string;
  const APort: Word): TBytes;
var
  LAddress: Cardinal;
  LHostBytes: TBytes;
begin
  Result := [5, 1, 0];
  if TryParseIPv4(AHost, LAddress) then
  begin
    AppendByte(Result, 1);
    AppendByte(Result, Byte(LAddress shr 24));
    AppendByte(Result, Byte(LAddress shr 16));
    AppendByte(Result, Byte(LAddress shr 8));
    AppendByte(Result, Byte(LAddress));
  end
  else
  begin
    LHostBytes := BytesOfAscii(AHost);
    if Length(LHostBytes) > 255 then
      raise EArgumentException.Create('SOCKS5 host exceeds 255 bytes.');
    AppendByte(Result, 3);
    AppendByte(Result, Length(LHostBytes));
    AppendBytes(Result, LHostBytes);
  end;
  AppendByte(Result, Byte(APort shr 8));
  AppendByte(Result, Byte(APort));
end;

class function TCrossProxyCodec.TryParseHttpConnectResponse(
  const AData: TBytes; out AConsumed, AStatusCode: Integer): Boolean;
var
  LText, LLine: string;
  LEnd, LSpace: Integer;
begin
  Result := False;
  AConsumed := 0;
  AStatusCode := 0;
  if Length(AData) = 0 then
    Exit;
  LText := TEncoding.ASCII.GetString(AData);
  LEnd := LText.IndexOf(CRLF + CRLF);
  if LEnd < 0 then
    Exit;
  LLine := LText.Substring(0, LText.IndexOf(CRLF));
  LSpace := LLine.IndexOf(' ');
  if (LSpace < 0) or not TryStrToInt(LLine.Substring(LSpace + 1, 3), AStatusCode) then
    Exit;
  AConsumed := LEnd + 4;
  Result := True;
end;

class function TCrossProxyCodec.TryParseSocks4Response(const AData: TBytes;
  out AConsumed: Integer; out ASuccess: Boolean): Boolean;
begin
  Result := Length(AData) >= 8;
  AConsumed := 0;
  ASuccess := False;
  if not Result then
    Exit;
  AConsumed := 8;
  ASuccess := AData[1] = 90;
end;

class function TCrossProxyCodec.TryParseSocks5MethodResponse(
  const AData: TBytes; out AConsumed: Integer; out AMethod: Byte): Boolean;
begin
  Result := Length(AData) >= 2;
  AConsumed := 0;
  AMethod := $FF;
  if not Result then
    Exit;
  AConsumed := 2;
  AMethod := AData[1];
end;

class function TCrossProxyCodec.TryParseSocks5AuthResponse(
  const AData: TBytes; out AConsumed: Integer; out ASuccess: Boolean): Boolean;
begin
  Result := Length(AData) >= 2;
  AConsumed := 0;
  ASuccess := False;
  if not Result then
    Exit;
  AConsumed := 2;
  ASuccess := AData[1] = 0;
end;

class function TCrossProxyCodec.TryParseSocks5ConnectResponse(
  const AData: TBytes; out AConsumed: Integer; out ASuccess: Boolean): Boolean;
var
  LAddressType, LAddressLength: Integer;
begin
  Result := False;
  AConsumed := 0;
  ASuccess := False;
  if Length(AData) < 5 then
    Exit;
  LAddressType := AData[3];
  case LAddressType of
    1: LAddressLength := 4;
    3:
      begin
        if Length(AData) < 5 then
          Exit;
        LAddressLength := 1 + AData[4];
      end;
    4: LAddressLength := 16;
  else
    Exit;
  end;
  AConsumed := 4 + LAddressLength + 2;
  if Length(AData) < AConsumed then
  begin
    AConsumed := 0;
    Exit(False);
  end;
  ASuccess := AData[1] = 0;
  Result := True;
end;

end.
