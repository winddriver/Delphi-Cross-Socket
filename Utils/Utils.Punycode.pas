unit Utils.Punycode;

{$I zLib.Inc}

{
  Punycode: A Bootstring encoding of Unicode
  for Internationalized Domain Names in Applications (IDNA)

  https://datatracker.ietf.org/doc/html/rfc3492
  https://en.wikipedia.org/wiki/Punycode
}

interface

uses
  SysUtils;

const
  OVERFLOW: string = 'Overflow.';
  BAD_INPUT: string = 'Bad input.';

type
  EPunycode = class(Exception);

  TPunycode = class
  private const
    TMIN: Integer = 1;
    TMAX: Integer = 26;
    BASE: Integer = 36;
    INITIAL_N: Integer = 128;
    INITIAL_BIAS: Integer = 72;
    DAMP: Integer = 700;
    SKEW: Integer = 38;
    DELIMITER: char = '-';
  public
    class function Encode(const AInput: string): string; static;
    class function Decode(const AInput: string): string; static;
    class function Adapt(delta, numpoints: Integer; first: Boolean): Integer; static;
    class function IsBasic(c: char): Boolean; static; inline;
    class function Digit2Codepoint(d: Integer): Integer; static; inline;
    class function Codepoint2Digit(c: Integer): Integer; static; inline;

    class function IsIPv6Addr(const AStr: string): Boolean; static; inline;
    class function NeedPunycode(const AStr: string): Boolean; static;
    class function IsPunycode(const AStr: string): Boolean; static; inline;
    class function EncodeDomain(const ADomain: string): string; static;
    class function DecodeDomain(const ADomain: string): string; static;
  end;

implementation

{ TPunycode }

class function TPunycode.Adapt(delta, numpoints: Integer;
  first: Boolean): Integer;
var
  k: Integer;
begin
  if first then
    delta := delta div DAMP
  else
    delta := delta div 2;
  delta := delta + (delta div numpoints);
  k := 0;
  while (delta > ((BASE - TMIN) * TMAX) div 2) do
  begin
    delta := delta div (BASE - TMIN);
    k := k + BASE;
  end;
  Result := k + ((BASE - TMIN + 1) * delta) div (delta + SKEW);
end;

class function TPunycode.Codepoint2Digit(c: Integer): Integer;
begin
  case c of
    Ord('0')..Ord('9'): Result := c - Ord('0') + 26;
    Ord('a')..Ord('z'): Result := c - Ord('a');
    Ord('A')..Ord('Z'): Result := c - Ord('A');
  else
    raise EPunycode.Create(BAD_INPUT);
  end;
end;

class function TPunycode.Decode(const AInput: string): string;
var
  n, i, bias, d, oldi, w, k, LDigit, t, LCount, j, LChar: Integer;
  LPoints: TArray<Integer>;
  LOutput: {$IFDEF FPC}TUnicodeStringBuilder{$ELSE}TStringBuilder{$ENDIF};
begin
  SetLength(LPoints, Length(AInput));
  LCount := 0;
  n := INITIAL_N;
  i := 0;
  bias := INITIAL_BIAS;
  d := AInput.LastIndexOf(DELIMITER);
  if d > 0 then
  begin
    for j := 1 to d do
    begin
      if not IsBasic(AInput[j]) then raise EPunycode.Create(BAD_INPUT);
      LPoints[LCount] := Ord(AInput[j]);
      Inc(LCount);
    end;
    Inc(d);
  end else
    d := 0;

  while d < Length(AInput) do
  begin
    oldi := i;
    w := 1;
    k := BASE;
    while True do
    begin
      if d >= Length(AInput) then raise EPunycode.Create(BAD_INPUT);
      Inc(d);
      LDigit := Codepoint2Digit(Ord(AInput[d]));
      if LDigit > (MaxInt - i) div w then raise EPunycode.Create(OVERFLOW);
      Inc(i, LDigit * w);
      if k <= bias then t := TMIN
      else if k >= bias + TMAX then t := TMAX
      else t := k - bias;
      if LDigit < t then Break;
      if w > MaxInt div (BASE - t) then raise EPunycode.Create(OVERFLOW);
      w := w * (BASE - t);
      Inc(k, BASE);
    end;
    bias := Adapt(i - oldi, LCount + 1, oldi = 0);
    if i div (LCount + 1) > $10FFFF - n then raise EPunycode.Create(BAD_INPUT);
    Inc(n, i div (LCount + 1));
    if (n >= $D800) and (n <= $DFFF) then raise EPunycode.Create(BAD_INPUT);
    i := i mod (LCount + 1);
    if i < LCount then Move(LPoints[i], LPoints[i + 1], (LCount - i) * SizeOf(Integer));
    LPoints[i] := n;
    Inc(LCount);
    Inc(i);
  end;

  LOutput := {$IFDEF FPC}TUnicodeStringBuilder{$ELSE}TStringBuilder{$ENDIF}.Create;
  try
    for j := 0 to LCount - 1 do
    begin
      LChar := LPoints[j];
      if LChar < $10000 then LOutput.Append(Char(LChar))
      else
      begin
        Dec(LChar, $10000);
        LOutput.Append(Char($D800 + (LChar shr 10)));
        LOutput.Append(Char($DC00 + (LChar and $3FF)));
      end;
    end;
    Result := LOutput.ToString;
  finally LOutput.Free; end;
end;

class function TPunycode.DecodeDomain(const ADomain: string): string;
var
  LDomainArr: TArray<string>;
  I: Integer;
  LDomainItem: string;
begin
  LDomainArr := ADomain.Split(['.']);

  for I := 0 to High(LDomainArr) do
  begin
    LDomainItem := LDomainArr[I];
    if IsPunycode(LDomainItem) then
      LDomainArr[I] := Decode(LDomainItem.Substring(4));
  end;

  Result := string.Join('.', LDomainArr);
end;

class function TPunycode.Digit2Codepoint(d: Integer): Integer;
begin
  if d < 26 then
    Result := d + ord('a')
  else if d < 36 then
    Result := d - 26 + ord('0')
  else
    raise EPunycode.Create(BAD_INPUT);
end;

class function TPunycode.Encode(const AInput: string): string;
var
  n, b, LDelta, LBias, m, i, h, j, q, k, t: Integer;
  LOutput: {$IFDEF FPC}TUnicodeStringBuilder{$ELSE}TStringBuilder{$ENDIF};
  LPoints: TArray<Integer>;
  LChar, LLow, LCount: Integer;
begin
  n := INITIAL_N;
  LDelta := 0;
  LBias := INITIAL_BIAS;
  LOutput := {$IFDEF FPC}TUnicodeStringBuilder{$ELSE}TStringBuilder{$ENDIF}.Create;
  try
    b := 0;
    LCount := 0;
    i := 1;
    SetLength(LPoints, Length(AInput));
    while i <= Length(AInput) do
    begin
      LChar := Ord(AInput[i]);
      Inc(i);
      if (LChar >= $D800) and (LChar <= $DFFF) then
      begin
        if (LChar >= $DC00) or (i > Length(AInput)) then raise EPunycode.Create(BAD_INPUT);
        LLow := Ord(AInput[i]);
        if (LLow < $DC00) or (LLow > $DFFF) then raise EPunycode.Create(BAD_INPUT);
        LChar := $10000 + ((LChar - $D800) shl 10) + (LLow - $DC00);
        Inc(i);
      end;
      LPoints[LCount] := LChar;
      Inc(LCount);
      if LChar < $80 then
      begin
        LOutput.Append(Char(LChar));
        Inc(b);
      end;
    end;
    if b > 0 then
      LOutput.Append(DELIMITER);
    h := b;
    while h < LCount do
    begin
      m := MAXINT;
      for i := 0 to LCount - 1 do
      begin
        LChar := LPoints[i];
        if (LChar >= n) and (LChar < m) then
          m := LChar;
      end;
      if m - n > (MAXINT - LDelta) div (h + 1) then
        raise EPunycode.Create(OVERFLOW);
      LDelta := LDelta + (m - n) * (h + 1);
      n := m;
      for j := 0 to LCount - 1 do
      begin
        LChar := LPoints[j];
        if LChar < n then
        begin
          if LDelta = MaxInt then raise EPunycode.Create(OVERFLOW);
          Inc(LDelta);
        end;
        if LChar = n then
        begin
          q := LDelta;
          k := BASE;
          while True do
          begin
            if k <= LBias then
              t := TMIN
            else if k >= LBias + TMAX then
              t := TMAX
            else
              t := k - LBias;
            if q < t then
              Break;
            LOutput.Append(Chr(Digit2Codepoint(t + (q - t) mod (BASE - t))));
            q := (q - t) div (BASE - t);
            Inc(k, BASE);
          end;
          LOutput.Append(Chr(Digit2Codepoint(q)));
          LBias := Adapt(LDelta, h + 1, h = b);
          LDelta := 0;
          Inc(h);
        end;
      end;
      Inc(LDelta);
      Inc(n);
    end;
    Result := LOutput.ToString;
  finally
    FreeAndNil(LOutput);
  end;
end;

class function TPunycode.EncodeDomain(const ADomain: string): string;
var
  LDomainArr: TArray<string>;
  I: Integer;
  LDomainItem: string;
begin
  if IsIPv6Addr(ADomain) then Exit(ADomain);

  LDomainArr := ADomain.Split(['.']);

  for I := 0 to High(LDomainArr) do
  begin
    LDomainItem := LDomainArr[I];
    if NeedPunycode(LDomainItem) then
      LDomainArr[I] := 'xn--' + Encode(LDomainItem);
  end;

  Result := string.Join('.', LDomainArr);
end;

class function TPunycode.IsBasic(c: char): Boolean;
begin
  Result := Ord(c) < $80;
end;

class function TPunycode.IsIPv6Addr(const AStr: string): Boolean;
begin
  Result := (AStr.IndexOf(':') >= 0);
end;

class function TPunycode.IsPunycode(const AStr: string): Boolean;
begin
  Result := AStr.StartsWith('xn--', True);
end;

class function TPunycode.NeedPunycode(const AStr: string): Boolean;
var
  LChar: Char;
begin
  for LChar in AStr do
  begin
    case Ord(LChar) of
      Ord('A')..Ord('Z'),
      Ord('a')..Ord('z'),
      Ord('0')..Ord('9'),
      Ord('-'):;
    else
      Exit(True);
    end;
  end;

  Result := False;
end;

end.
