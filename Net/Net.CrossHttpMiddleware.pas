{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpMiddleware;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  //System.Hash,
  //System.NetEncoding,

  Utils.Utils,
  Utils.Base64,
  Utils.Hash,

  Net.CrossHttpServer;

type
  /// <summary>
  ///   HTTP认证获取用户密码
  /// </summary>
  TAuthGetPasswordProc = reference to procedure(const ARequest: ICrossHttpRequest; const AUserName: string; var ACorrectPassword: string);

  /// <summary>
  ///   中间件
  /// </summary>
  /// <remarks>
  ///   用于 TCrossHttpServer.Use()
  /// </remarks>
  TNetCrossMiddleware = class
  public
    /// <summary>
    ///   HTTP基本认证
    /// </summary>
    /// <param name="AAuthFunc">
    ///   用户身份认证函数
    /// </param>
    /// <remarks>
    ///   <see cref="https://zh.wikipedia.org/wiki/HTTP%E5%9F%BA%E6%9C%AC%E8%AE%A4%E8%AF%81">
    ///   维基百科: HTTP基本认证</see>
    /// </remarks>
    class function AuthenticateBasic(AAuthGetPasswordProc: TAuthGetPasswordProc; const ARealm: string = ''): TCrossHttpRouterProc; static;

    /// <summary>
    ///   HTTP摘要认证
    /// </summary>
    /// <param name="AAuthFunc">
    ///   用户身份认证函数
    /// </param>
    /// <remarks>
    ///   <see cref="https://zh.wikipedia.org/wiki/HTTP%E6%91%98%E8%A6%81%E8%AE%A4%E8%AF%81">
    ///   维基百科: HTTP摘要认证</see>
    /// </remarks>
    class function AuthenticateDigest(AAuthGetPasswordProc: TAuthGetPasswordProc; const ARealm: string = ''): TCrossHttpRouterProc; static;

    /// <summary>
    ///   跨来源资源共享
    /// </summary>
    /// <remarks>
    ///   <see href="https://zh.wikipedia.org/wiki/%E8%B7%A8%E4%BE%86%E6%BA%90%E8%B3%87%E6%BA%90%E5%85%B1%E4%BA%AB">
    ///   维基百科: 跨来源资源共享</see>
    /// </remarks>
    class function CORS: TCrossHttpRouterProc; static;

    /// <summary>
    ///   HTTP严格传输安全
    /// </summary>
    /// <remarks>
    ///   <see href="https://zh.wikipedia.org/wiki/HTTP%E4%B8%A5%E6%A0%BC%E4%BC%A0%E8%BE%93%E5%AE%89%E5%85%A8">
    ///   维基百科: HTTP严格传输安全</see>
    /// </remarks>
    class function HSTS: TCrossHttpRouterProc; static;

    class function NoCache: TCrossHttpRouterProc; static;
  end;

{$IFDEF CROSS_HTTP_AUTH_TESTS}
type
  THttpAuthTestClock = reference to function: UInt64;
  THttpAuthTestRandom = reference to function: TBytes;
  THttpAuthTestNotify = reference to procedure;
  THttpAuthTestOptions = record
    Clock: THttpAuthTestClock;
    Random: THttpAuthTestRandom;
    OnDestroy: THttpAuthTestNotify;
    NonceLifetimeMs: UInt64;
    MaxNonces, MaxUsesPerNonce, MaxTotalUses: Integer;
  end;

// 仅测试构建可见；工厂创建时复制选项，运行中的状态不读取这些全局配置。
procedure SetHttpAuthTestOptions(const AOptions: THttpAuthTestOptions);
{$ENDIF}

implementation

uses
  Generics.Collections,
  Net.CrossHttpUtils,
  Utils.CryptRandom,
  Utils.SyncObjs;

const
  AUTH_HEADER_LIMIT = 16384;
  DIGEST_NONCE_BYTES = 32;
  DIGEST_NONCE_LIFETIME_MS = 300000;
  DIGEST_MAX_NONCES = 1024;
  DIGEST_MAX_USES_PER_NONCE = 1024;
  DIGEST_MAX_TOTAL_USES = 8192;

{$IFDEF CROSS_HTTP_AUTH_TESTS}
var
  GHttpAuthTestOptions: THttpAuthTestOptions;

procedure SetHttpAuthTestOptions(const AOptions: THttpAuthTestOptions);
begin
  GHttpAuthTestOptions := AOptions;
end;
{$ENDIF}

function _QuoteAuthValue(const AValue: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AValue do
  begin
    if (Ord(C) < 32) or (Ord(C) = 127) then
      raise EArgumentException.Create('认证域不能包含控制字符');
    if (C = '"') or (C = '\') then Result := Result + '\';
    Result := Result + C;
  end;
end;

function _GetAuthValue(const ARequest: ICrossHttpRequest;
  const AScheme: string; out AValue: string): Boolean;
var
  LHeaders: TArray<string>;
  LHeader: string;
  I: Integer;
begin
  AValue := '';
  Result := False;
  if not ARequest.Header.GetHeaderValues('Authorization', LHeaders)
    or (Length(LHeaders) <> 1) then Exit;
  LHeader := LHeaders[0];
  if Length(LHeader) > AUTH_HEADER_LIMIT then Exit;
  I := Length(AScheme) + 1;
  if (Length(LHeader) < I) or (LHeader[I] <> ' ')
    or not SameText(Copy(LHeader, 1, I - 1), AScheme) then Exit;
  while (I <= Length(LHeader)) and (LHeader[I] = ' ') do Inc(I);
  AValue := Copy(LHeader, I, MaxInt);
  Result := AValue <> '';
end;

function _SameSecret(const ALeft, ARight: string): Boolean;
var
  I, LDifference: Integer;
begin
  if Length(ALeft) <> Length(ARight) then Exit(False);
  LDifference := 0;
  for I := 1 to Length(ALeft) do
    LDifference := LDifference or (Ord(ALeft[I]) xor Ord(ARight[I]));
  Result := LDifference = 0;
end;

function _DecodeBasic(const AValue: string; out AUserName, APassword: string): Boolean;
var
  LBytes, LEncoded: TBytes;
  LText: string;
  I, LLength, LPadding, LColon: Integer;
begin
  Result := False;
  AUserName := '';
  APassword := '';
  LLength := Length(AValue);
  if (LLength = 0) or (LLength mod 4 <> 0) then Exit;
  LPadding := 0;
  if AValue[LLength] = '=' then Inc(LPadding);
  if AValue[LLength - 1] = '=' then Inc(LPadding);
  for I := 1 to LLength - LPadding do
    if not CharInSet(AValue[I], ['A'..'Z', 'a'..'z', '0'..'9', '+', '/']) then Exit;
  try
    // 两套 RTL 的默认解码器均容忍非法输入，不能只依赖异常判断。
    LBytes := TBase64Utils.Decode(AValue);
    if TBase64Utils.Encode(LBytes) <> AValue then Exit;
    for I := 0 to High(LBytes) do
      if (LBytes[I] < 32) or (LBytes[I] = 127) then Exit;
    LText := TEncoding.UTF8.GetString(LBytes);
    LEncoded := TEncoding.UTF8.GetBytes(LText);
    if Length(LEncoded) <> Length(LBytes) then Exit;
    if (Length(LBytes) > 0) and not CompareMem(@LBytes[0], @LEncoded[0], Length(LBytes)) then Exit;
  except
    on E: Exception do Exit;
  end;
  LColon := Pos(':', LText);
  if LColon = 0 then Exit;
  AUserName := Copy(LText, 1, LColon - 1);
  APassword := Copy(LText, LColon + 1, MaxInt);
  Result := True;
end;

type
  TDigestFields = record
    UserName, Realm, Nonce, Uri, Response, Qop, Nc, Cnonce: string;
  end;

  TDigestNonce = class
  public
    Created: UInt64;
    UsedRequests: TDictionary<string, Byte>;
    constructor Create(const ANow: UInt64);
    destructor Destroy; override;
  end;

  IDigestAuthState = interface
    ['{18BEE312-720A-4AF0-9DA7-923D40324A8F}']
    function HasNonce(const ANonce: string): Boolean;
    function Consume(const AFields: TDigestFields): Boolean;
    function NewNonce(out ANonce: string): Boolean;
  end;

  TDigestAuthState = class(TInterfacedObject, IDigestAuthState)
  private
    FLock: ILock;
    FNonces: TObjectDictionary<string, TDigestNonce>;
    FTotalUses, FMaxNonces, FMaxUsesPerNonce, FMaxTotalUses: Integer;
    FNonceLifetimeMs: UInt64;
    {$IFDEF CROSS_HTTP_AUTH_TESTS}
    FTestOptions: THttpAuthTestOptions;
    {$ENDIF}
    function _Now: UInt64;
    function _Expired(const ANonce: TDigestNonce; const ANow: UInt64): Boolean;
    procedure _Remove(const ANonce: string);
    procedure _Prune(const ANow: UInt64);
    function _EvictOldest(const ANow: UInt64; const AWithUses: Boolean;
      const AExclude: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function HasNonce(const ANonce: string): Boolean;
    function Consume(const AFields: TDigestFields): Boolean;
    function NewNonce(out ANonce: string): Boolean;
  end;

constructor TDigestNonce.Create(const ANow: UInt64);
begin
  inherited Create;
  Created := ANow;
  UsedRequests := TDictionary<string, Byte>.Create;
end;

destructor TDigestNonce.Destroy;
begin
  UsedRequests.Free;
  inherited;
end;

constructor TDigestAuthState.Create;
begin
  inherited Create;
  FLock := TLock.Create;
  FNonces := TObjectDictionary<string, TDigestNonce>.Create([doOwnsValues]);
  FNonceLifetimeMs := DIGEST_NONCE_LIFETIME_MS;
  FMaxNonces := DIGEST_MAX_NONCES;
  FMaxUsesPerNonce := DIGEST_MAX_USES_PER_NONCE;
  FMaxTotalUses := DIGEST_MAX_TOTAL_USES;
  {$IFDEF CROSS_HTTP_AUTH_TESTS}
  FTestOptions := GHttpAuthTestOptions;
  if FTestOptions.NonceLifetimeMs > 0 then FNonceLifetimeMs := FTestOptions.NonceLifetimeMs;
  if FTestOptions.MaxNonces > 0 then FMaxNonces := FTestOptions.MaxNonces;
  if FTestOptions.MaxUsesPerNonce > 0 then FMaxUsesPerNonce := FTestOptions.MaxUsesPerNonce;
  if FTestOptions.MaxTotalUses > 0 then FMaxTotalUses := FTestOptions.MaxTotalUses;
  {$ENDIF}
end;

destructor TDigestAuthState.Destroy;
begin
  FNonces.Free;
  {$IFDEF CROSS_HTTP_AUTH_TESTS}
  if Assigned(FTestOptions.OnDestroy) then FTestOptions.OnDestroy();
  {$ENDIF}
  inherited;
end;

function TDigestAuthState._Now: UInt64;
begin
  {$IFDEF CROSS_HTTP_AUTH_TESTS}
  if Assigned(FTestOptions.Clock) then Exit(FTestOptions.Clock());
  {$ENDIF}
  Result := TThread.GetTickCount64;
end;

function TDigestAuthState._Expired(const ANonce: TDigestNonce;
  const ANow: UInt64): Boolean;
begin
  Result := ANow - ANonce.Created >= FNonceLifetimeMs;
end;

procedure TDigestAuthState._Remove(const ANonce: string);
var
  LNonce: TDigestNonce;
begin
  if FNonces.TryGetValue(ANonce, LNonce) then
  begin
    Dec(FTotalUses, LNonce.UsedRequests.Count);
    FNonces.Remove(ANonce);
  end;
end;

procedure TDigestAuthState._Prune(const ANow: UInt64);
var
  LExpired: TArray<string>;
  LPair: TPair<string, TDigestNonce>;
  I, LCount: Integer;
begin
  SetLength(LExpired, FNonces.Count);
  LCount := 0;
  for LPair in FNonces do
    if _Expired(LPair.Value, ANow) then
    begin
      LExpired[LCount] := LPair.Key;
      Inc(LCount);
    end;
  for I := 0 to LCount - 1 do _Remove(LExpired[I]);
end;

function TDigestAuthState._EvictOldest(const ANow: UInt64;
  const AWithUses: Boolean; const AExclude: string): Boolean;
var
  LPair: TPair<string, TDigestNonce>;
  LOldest: string;
  LAge, LOldestAge: UInt64;
begin
  LOldest := '';
  LOldestAge := 0;
  for LPair in FNonces do
  begin
    if (LPair.Key = AExclude) or (AWithUses and (LPair.Value.UsedRequests.Count = 0)) then Continue;
    LAge := ANow - LPair.Value.Created;
    if (LOldest = '') or (LAge > LOldestAge) then
    begin
      LOldest := LPair.Key;
      LOldestAge := LAge;
    end;
  end;
  Result := LOldest <> '';
  if Result then _Remove(LOldest);
end;

function TDigestAuthState.HasNonce(const ANonce: string): Boolean;
var
  LNonce: TDigestNonce;
begin
  FLock.Enter;
  try
    Result := FNonces.TryGetValue(ANonce, LNonce);
    if Result and _Expired(LNonce, _Now) then
    begin
      _Remove(ANonce);
      Result := False;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDigestAuthState.Consume(const AFields: TDigestFields): Boolean;
var
  LNonce: TDigestNonce;
  LUseKey: string;
  LNow: UInt64;
begin
  // 固定长度索引避免长用户名/cnonce 随重放记录长期放大内存。
  LUseKey := TUtils.BytesToHex(THashSHA256.GetHashBytes(
    AFields.UserName + #0 + AFields.Cnonce + #0 + AFields.Nc.ToLower));
  FLock.Enter;
  try
    Result := False;
    if not FNonces.TryGetValue(AFields.Nonce, LNonce) then Exit;
    LNow := _Now;
    if _Expired(LNonce, LNow) then
    begin
      _Remove(AFields.Nonce);
      Exit;
    end;
    if LNonce.UsedRequests.ContainsKey(LUseKey) then Exit;
    if LNonce.UsedRequests.Count >= FMaxUsesPerNonce then
    begin
      // 容量满时使整个 nonce 失效，不能遗忘旧 nc 后重新接受重放。
      _Remove(AFields.Nonce);
      Exit;
    end;
    if FTotalUses >= FMaxTotalUses then
    begin
      _Prune(LNow);
      if (FTotalUses >= FMaxTotalUses)
        and not _EvictOldest(LNow, True, AFields.Nonce) then
      begin
        _Remove(AFields.Nonce);
        Exit;
      end;
    end;
    LNonce.UsedRequests.Add(LUseKey, 0);
    Inc(FTotalUses);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TDigestAuthState.NewNonce(out ANonce: string): Boolean;
var
  LBytes: TBytes;
  LNonce: string;
  LNewNonce: TDigestNonce;
  LNow: UInt64;
  I: Integer;
begin
  ANonce := '';
  Result := False;
  for I := 1 to 4 do
  begin
    // 随机源可能失败，不在持锁时调用，也不降级到可预测 nonce。
    {$IFDEF CROSS_HTTP_AUTH_TESTS}
    if Assigned(FTestOptions.Random) then
      LBytes := FTestOptions.Random()
    else
    {$ENDIF}
    begin
      SetLength(LBytes, DIGEST_NONCE_BYTES);
      if not TryFillCryptRandomBytes(LBytes[0], Length(LBytes)) then Exit;
    end;
    if Length(LBytes) <> DIGEST_NONCE_BYTES then Exit;
    LNonce := TUtils.BytesToHex(LBytes);
    FLock.Enter;
    try
      LNow := _Now;
      _Prune(LNow);
      if FNonces.ContainsKey(LNonce) then Continue;
      if (FNonces.Count >= FMaxNonces) and not _EvictOldest(LNow, False, '') then Exit;
      LNewNonce := TDigestNonce.Create(LNow);
      try
        FNonces.Add(LNonce, LNewNonce);
        LNewNonce := nil;
      finally
        LNewNonce.Free;
      end;
      ANonce := LNonce;
      Exit(True);
    finally
      FLock.Leave;
    end;
  end;
end;

function _IsHex(const AValue: string; const ALength: Integer): Boolean;
var
  C: Char;
begin
  if Length(AValue) <> ALength then Exit(False);
  for C in AValue do
    if not CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F']) then Exit(False);
  Result := True;
end;

function _ParseDigest(const AValue: string; out AFields: TDigestFields): Boolean;
var
  LParams: TDictionary<string, string>;
  I, LBegin, LValueLength: Integer;
  LName, LValue, LAlgorithm, LUserHash: string;
  C: Char;
  LClosed: Boolean;

  procedure SkipSpace;
  begin
    while (I <= Length(AValue)) and CharInSet(AValue[I], [' ', #9]) do Inc(I);
  end;
begin
  Result := False;
  LParams := TDictionary<string, string>.Create;
  try
    I := 1;
    while I <= Length(AValue) do
    begin
      SkipSpace;
      LBegin := I;
      while (I <= Length(AValue)) and TCrossHttpUtils.IsTokenChar(AValue[I]) do Inc(I);
      if I = LBegin then Exit;
      LName := Copy(AValue, LBegin, I - LBegin).ToLower;
      if LParams.ContainsKey(LName) then Exit;
      SkipSpace;
      if (I > Length(AValue)) or (AValue[I] <> '=') then Exit;
      Inc(I);
      SkipSpace;
      if I > Length(AValue) then Exit;
      if AValue[I] = '"' then
      begin
        Inc(I);
        SetLength(LValue, Length(AValue) - I + 1);
        LValueLength := 0;
        LClosed := False;
        while I <= Length(AValue) do
        begin
          C := AValue[I];
          Inc(I);
          if C = '"' then
          begin
            LClosed := True;
            Break;
          end;
          if C = '\' then
          begin
            if I > Length(AValue) then Exit;
            C := AValue[I];
            Inc(I);
          end;
          if (Ord(C) < 32) or (Ord(C) = 127) then Exit;
          Inc(LValueLength);
          LValue[LValueLength] := C;
        end;
        if not LClosed then Exit;
        SetLength(LValue, LValueLength);
      end else
      begin
        LBegin := I;
        while (I <= Length(AValue)) and TCrossHttpUtils.IsTokenChar(AValue[I]) do Inc(I);
        if I = LBegin then Exit;
        LValue := Copy(AValue, LBegin, I - LBegin);
      end;
      LParams.Add(LName, LValue);
      SkipSpace;
      if I > Length(AValue) then Break;
      if AValue[I] <> ',' then Exit;
      Inc(I);
      SkipSpace;
      if I > Length(AValue) then Exit;
    end;
    if not (LParams.TryGetValue('username', AFields.UserName)
      and LParams.TryGetValue('realm', AFields.Realm)
      and LParams.TryGetValue('nonce', AFields.Nonce)
      and LParams.TryGetValue('uri', AFields.Uri)
      and LParams.TryGetValue('response', AFields.Response)
      and LParams.TryGetValue('qop', AFields.Qop)
      and LParams.TryGetValue('nc', AFields.Nc)
      and LParams.TryGetValue('cnonce', AFields.Cnonce)) then Exit;
    if LParams.TryGetValue('algorithm', LAlgorithm) and not SameText(LAlgorithm, 'MD5') then Exit;
    if LParams.TryGetValue('userhash', LUserHash) and (LUserHash <> 'false') then Exit;
    if LParams.ContainsKey('username*') or (Pos(':', AFields.UserName) > 0) then Exit;
    Result := (AFields.Qop = 'auth') and (AFields.Cnonce <> '')
      and _IsHex(AFields.Nonce, DIGEST_NONCE_BYTES * 2)
      and _IsHex(AFields.Response, 32) and _IsHex(AFields.Nc, 8)
      and (AFields.Nc <> '00000000');
  finally
    LParams.Free;
  end;
end;

{ TNetCrossMiddleware }

class function TNetCrossMiddleware.AuthenticateBasic(AAuthGetPasswordProc: TAuthGetPasswordProc;
  const ARealm: string): TCrossHttpRouterProc;
var
  LRealm: string;
begin
  LRealm := _QuoteAuthValue(ARealm);
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LAuthStr, LUserName, LPassword, LCorrectPassword, LChallengeRealm: string;
      LPasswordProc: TAuthGetPasswordProc;
      LValid: Boolean;
    begin
      AHandled := True;
      LChallengeRealm := LRealm;
      LPasswordProc := AAuthGetPasswordProc;
      LCorrectPassword := #0;
      LValid := Assigned(LPasswordProc)
        and _GetAuthValue(ARequest, 'Basic', LAuthStr)
        and _DecodeBasic(LAuthStr, LUserName, LPassword);
      // 业务查询异常继续交给服务器的既有异常处理，不伪装成错误密码。
      if LValid then
        LPasswordProc(ARequest, LUserName, LCorrectPassword);
      if not LValid or (LCorrectPassword = #0)
        or not _SameSecret(LPassword, LCorrectPassword) then
      begin
        AResponse.Header['WWW-authenticate'] := Format('Basic Realm="%s"', [LChallengeRealm]);
        AResponse.SendStatus(401);
        Exit;
      end;

      AHandled := False;
    end;
end;

class function TNetCrossMiddleware.AuthenticateDigest(
  AAuthGetPasswordProc: TAuthGetPasswordProc; const ARealm: string): TCrossHttpRouterProc;
var
  LState: IDigestAuthState;
  LRealm: string;
begin
  LRealm := _QuoteAuthValue(ARealm);
  LState := TDigestAuthState.Create;
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LKeepState: IDigestAuthState;
      LPasswordProc: TAuthGetPasswordProc;
      LFields: TDigestFields;
      LAuthStr, LCorrectPassword, LCorrectResponse, LNonce, LHA1, LHA2: string;
      LRequestRealm, LChallengeRealm: string;
      LValid: Boolean;
    begin
      AHandled := True;
      LKeepState := LState;
      LPasswordProc := AAuthGetPasswordProc;
      LRequestRealm := ARealm;
      LChallengeRealm := LRealm;
      LCorrectPassword := #0;
      LValid := Assigned(LPasswordProc)
        and _GetAuthValue(ARequest, 'Digest', LAuthStr)
        and _ParseDigest(LAuthStr, LFields)
        and (LFields.Realm = LRequestRealm)
        and (LFields.Uri = ARequest.RawPathAndParams)
        and LKeepState.HasNonce(LFields.Nonce);
      if LValid then
      begin
        // 用户回调与摘要计算都不持有状态锁，异常沿用服务器处理契约。
        LPasswordProc(ARequest, LFields.UserName, LCorrectPassword);
        LValid := LCorrectPassword <> #0;
      end;
      if LValid then
      begin
        LHA1 := TUtils.BytesToHex(THashMD5.GetHashBytes(
          LFields.UserName + ':' + LRequestRealm + ':' + LCorrectPassword));
        LHA2 := TUtils.BytesToHex(THashMD5.GetHashBytes(ARequest.Method + ':' + LFields.Uri));
        LCorrectResponse := TUtils.BytesToHex(THashMD5.GetHashBytes(LHA1 + ':' +
          LFields.Nonce + ':' + LFields.Nc + ':' + LFields.Cnonce + ':auth:' + LHA2));
        // 只在摘要正确后原子记录 nc；重查有效期，防止慢查询越过过期边界。
        LValid := _SameSecret(LCorrectResponse, LFields.Response.ToLower)
          and LKeepState.Consume(LFields);
      end;
      if not LValid then
      begin
        if not LKeepState.NewNonce(LNonce) then
        begin
          AResponse.SendStatus(503);
          Exit;
        end;
        AResponse.Header['WWW-authenticate'] := Format(
          'Digest realm="%s", qop="auth", algorithm=MD5, nonce="%s"',
          [LChallengeRealm, LNonce]);
        AResponse.SendStatus(401);
        Exit;
      end;
      AHandled := False;
    end;
end;

class function TNetCrossMiddleware.CORS: TCrossHttpRouterProc;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AHandled := False;
      AResponse.Header['Access-Control-Allow-Origin'] := '*';
      AResponse.Header['Access-Control-Allow-Methods'] := '*';
      AResponse.Header['Access-Control-Allow-Headers'] := '*';
    end;
end;

class function TNetCrossMiddleware.HSTS: TCrossHttpRouterProc;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AHandled := False;
      AResponse.Header['Strict-Transport-Security'] := 'max-age=31536000; includeSubDomains';
    end;
end;

class function TNetCrossMiddleware.NoCache: TCrossHttpRouterProc;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AHandled := False;
      AResponse.Header['Cache-Control'] := 'no-store';
      AResponse.Header['Pragma'] := 'no-cache';
      AResponse.Header['Expires'] := 'Thu, 01 Jan 1970 00:00:00 GMT';
    end;
end;

end.
