unit DTF.Hash;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes;

type
  /// <summary> Hash related Exceptions </summary>
  EHashException = class(Exception);

  /// <summary> Record with common functionality to all Hash functions</summary>
  THash = record
    /// <summary>Convert a Digest into an Integer if it's length its four</summary>
    class function DigestAsInteger(const ADigest: TBytes): Integer; static;
    /// <summary>Convert a Digest into a hexadecimal value string</summary>
    class function DigestAsString(const ADigest: TBytes): string; static;
    /// <summary>Convert a Digest into a GUID if it's length its sixteen</summary>
    class function DigestAsStringGUID(const ADigest: TBytes): string; static;
    /// <summary> Gets a random string with the given length</summary>
    class function GetRandomString(const ALen: Integer = 10): string; static;
    /// <summary> Gets the BigEndian memory representation of a cardinal value</summary>
    class function ToBigEndian(AValue: Cardinal): Cardinal; overload; static; inline;
    /// <summary> Gets the BigEndian memory representation of a UInt64 value</summary>
    class function ToBigEndian(AValue: UInt64): UInt64; overload; static; inline;
  end;

  /// <summary> Record to generate BobJenkins Hash values from data. Stores internal state of the process</summary>
  THashBobJenkins = record
  private
    FHash: Integer;
    function GetDigest: TBytes;

    class function HashLittle(const Data; Len, InitVal: Integer): Integer; static;
  public
    /// <summary>Initialize the Record used to calculate the BobJenkins Hash</summary>
    class function Create: THashBobJenkins; static;

    /// <summary> Puts the state machine of the generator in it's initial state.</summary>
    procedure Reset(AInitialValue: Integer = 0);

    /// <summary> Update the Hash value with the given Data. </summary>
    procedure Update(const AData; ALength: Cardinal); overload; inline;
    procedure Update(const AData: TBytes; ALength: Cardinal = 0); overload; inline;
    procedure Update(const Input: string); overload; inline;

    /// <summary> Returns the hash value as a TBytes</summary>
    function HashAsBytes: TBytes;
    /// <summary> Returns the hash value as integer</summary>
    function HashAsInteger: Integer;
    /// <summary> Returns the hash value as string</summary>
    function HashAsString: string;

    /// <summary> Hash the given string and returns it's hash value as integer</summary>
    class function GetHashBytes(const AData: string): TBytes; static;
    /// <summary> Hash the given string and returns it's hash value as string</summary>
    class function GetHashString(const AString: string): string; static;
    /// <summary> Hash the given string and returns it's hash value as integer</summary>
    class function GetHashValue(const AData: string): Integer; overload; static; inline;
    /// <summary> Hash the given Data and returns it's hash value as integer</summary>
    class function GetHashValue(const AData; ALength: Integer; AInitialValue: Integer = 0): Integer; overload; static; inline;
  end;

  /// <summary> Record to generate FNV1a 32-bit Hash values from data. Stores internal state of the process</summary>
  THashFNV1a32 = record
  public const
    FNV_PRIME = $01000193; //   16777619
    FNV_SEED  = $811C9DC5; // 2166136261
  private
    FHash: Cardinal;
    function GetDigest: TBytes;

    class function Hash(const Data; Len, InitVal: Cardinal): Cardinal; static;
  public
    /// <summary>Initialize the Record used to calculate the FNV1a Hash</summary>
    class function Create: THashFNV1a32; static;

    /// <summary> Puts the state machine of the generator in it's initial state.</summary>
    procedure Reset(AInitialValue: Cardinal = FNV_SEED);

    /// <summary> Update the Hash value with the given Data. </summary>
    procedure Update(const AData; ALength: Cardinal); overload; inline;
    procedure Update(const AData: TBytes; ALength: Cardinal = 0); overload; inline;
    procedure Update(const Input: string); overload; inline;

    /// <summary> Returns the hash value as a TBytes</summary>
    function HashAsBytes: TBytes;
    /// <summary> Returns the hash value as integer</summary>
    function HashAsInteger: Integer;
    /// <summary> Returns the hash value as string</summary>
    function HashAsString: string;

    /// <summary> Hash the given string and returns it's hash value as integer</summary>
    class function GetHashBytes(const AData: string): TBytes; static;
    /// <summary> Hash the given string and returns it's hash value as string</summary>
    class function GetHashString(const AString: string): string; overload; static;
    class function GetHashString(const AString: RawByteString): string; overload; static;
    /// <summary> Hash the given string and returns it's hash value as integer</summary>
    class function GetHashValue(const AData: string): Integer; overload; static; inline;
    class function GetHashValue(const AData: RawByteString): Integer; overload; static; inline;
    /// <summary> Hash the given Data and returns it's hash value as integer</summary>
    class function GetHashValue(const AData; ALength: Cardinal; AInitialValue: Cardinal = FNV_SEED): Integer; overload; static; inline;
  end;

implementation

{ THash }

class function THash.ToBigEndian(AValue: Cardinal): Cardinal;
begin
  Result := (AValue shr 24) or (AValue shl 24) or ((AValue shr 8) and $FF00) or ((AValue shl 8) and $FF0000);
end;

class function THash.ToBigEndian(AValue: UInt64): UInt64;
begin
  Result := UInt64(ToBigEndian(Cardinal(AValue))) shl 32 or ToBigEndian(Cardinal(AValue shr 32));
end;

class function THash.DigestAsInteger(const ADigest: TBytes): Integer;
begin
  if Length(ADigest) <> 4 then
    raise EHashException.Create('Digest size must be 4 to Generate a Integer');
  Result := PInteger(@ADigest[0])^;
end;

class function THash.DigestAsString(const ADigest: TBytes): string;
const
  XD: array[0..15] of char = ('0', '1', '2', '3', '4', '5', '6', '7',
                              '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
var
  I, L: Integer;
  PC: PChar;
  PB: PByte;
begin
  L := Length(ADigest);
  SetLength(Result, L * 2);
  PC := Pointer(Result);
  PB := PByte(ADigest);
  for I := 0 to L - 1 do
  begin
    PC[0] := XD[(PB^ shr 4) and $0f];
    PC[1] := XD[PB^ and $0f];
    Inc(PC, 2);
    Inc(PB);
  end;
end;

class function THash.DigestAsStringGUID(const ADigest: TBytes): string;
var
  LGUID: TGUID;
begin
  LGUID := TGUID.Create(ADigest);
  LGUID.D1 := ToBigEndian(LGUID.D1);
  LGUID.D2 := Word((WordRec(LGUID.D2).Lo shl 8) or WordRec(LGUID.D2).Hi);
  LGUID.D3 := Word((WordRec(LGUID.D3).Lo shl 8) or WordRec(LGUID.D3).Hi);
  Result := LGUID.ToString;
end;

class function THash.GetRandomString(const ALen: Integer): string;
const
  ValidChars: string = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-/*_';
var
  I, L: Integer;
  PC, PV: PChar;
begin
  L := Length(ValidChars);
  SetLength(Result, ALen);
  PC := Pointer(Result);
  PV := Pointer(ValidChars);
  for I := 1 to ALen do
  begin
    PC^ := PV[Random(L)];
    Inc(PC);
  end;
end;

{ THashBobJenkins }

class function THashBobJenkins.HashLittle(const Data; Len, InitVal: Integer): Integer;
  function Rot(x, k: Cardinal): Cardinal; inline;
  begin
    Result := (x shl k) or (x shr (32 - k));
  end;

  procedure Mix(var a, b, c: Cardinal); inline;
  begin
    Dec(a, c); a := a xor Rot(c, 4); Inc(c, b);
    Dec(b, a); b := b xor Rot(a, 6); Inc(a, c);
    Dec(c, b); c := c xor Rot(b, 8); Inc(b, a);
    Dec(a, c); a := a xor Rot(c,16); Inc(c, b);
    Dec(b, a); b := b xor Rot(a,19); Inc(a, c);
    Dec(c, b); c := c xor Rot(b, 4); Inc(b, a);
  end;

  procedure Final(var a, b, c: Cardinal); inline;
  begin
    c := c xor b; Dec(c, Rot(b,14));
    a := a xor c; Dec(a, Rot(c,11));
    b := b xor a; Dec(b, Rot(a,25));
    c := c xor b; Dec(c, Rot(b,16));
    a := a xor c; Dec(a, Rot(c, 4));
    b := b xor a; Dec(b, Rot(a,14));
    c := c xor b; Dec(c, Rot(b,24));
  end;

{$POINTERMATH ON}
var
  pb: PByte;
  pd: PCardinal absolute pb;
  a, b, c: Cardinal;
label
  case_1, case_2, case_3, case_4, case_5, case_6,
  case_7, case_8, case_9, case_10, case_11, case_12;
begin
  a := Cardinal($DEADBEEF) + Cardinal(Len) + Cardinal(InitVal);
  b := a;
  c := a;

  pb := @Data;

  // 4-byte aligned data
  if (Cardinal(pb) and 3) = 0 then
  begin
    while Len > 12 do
    begin
      Inc(a, pd[0]);
      Inc(b, pd[1]);
      Inc(c, pd[2]);
      Mix(a, b, c);
      Dec(Len, 12);
      Inc(pd, 3);
    end;

    case Len of
      0: Exit(Integer(c));
      1: Inc(a, pd[0] and $FF);
      2: Inc(a, pd[0] and $FFFF);
      3: Inc(a, pd[0] and $FFFFFF);
      4: Inc(a, pd[0]);
      5:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1] and $FF);
      end;
      6:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1] and $FFFF);
      end;
      7:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1] and $FFFFFF);
      end;
      8:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1]);
      end;
      9:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1]);
        Inc(c, pd[2] and $FF);
      end;
      10:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1]);
        Inc(c, pd[2] and $FFFF);
      end;
      11:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1]);
        Inc(c, pd[2] and $FFFFFF);
      end;
      12:
      begin
        Inc(a, pd[0]);
        Inc(b, pd[1]);
        Inc(c, pd[2]);
      end;
    end;
  end
  else
  begin
    // Ignoring rare case of 2-byte aligned data. This handles all other cases.
    while Len > 12 do
    begin
      Inc(a, pb[0] + pb[1] shl 8 + pb[2] shl 16 + pb[3] shl 24);
      Inc(b, pb[4] + pb[5] shl 8 + pb[6] shl 16 + pb[7] shl 24);
      Inc(c, pb[8] + pb[9] shl 8 + pb[10] shl 16 + pb[11] shl 24);
      Mix(a, b, c);
      Dec(Len, 12);
      Inc(pb, 12);
    end;

    case Len of
      0: Exit(Integer(c));
      1: goto case_1;
      2: goto case_2;
      3: goto case_3;
      4: goto case_4;
      5: goto case_5;
      6: goto case_6;
      7: goto case_7;
      8: goto case_8;
      9: goto case_9;
      10: goto case_10;
      11: goto case_11;
      12: goto case_12;
    end;

case_12:
    Inc(c, pb[11] shl 24);
case_11:
    Inc(c, pb[10] shl 16);
case_10:
    Inc(c, pb[9] shl 8);
case_9:
    Inc(c, pb[8]);
case_8:
    Inc(b, pb[7] shl 24);
case_7:
    Inc(b, pb[6] shl 16);
case_6:
    Inc(b, pb[5] shl 8);
case_5:
    Inc(b, pb[4]);
case_4:
    Inc(a, pb[3] shl 24);
case_3:
    Inc(a, pb[2] shl 16);
case_2:
    Inc(a, pb[1] shl 8);
case_1:
    Inc(a, pb[0]);
  end;

  Final(a, b, c);
  Result := Integer(c);
end;

{$POINTERMATH OFF}

class function THashBobJenkins.Create: THashBobJenkins;
begin
  Result.FHash := 0;
end;

function THashBobJenkins.GetDigest: TBytes;
begin
  SetLength(Result, 4);
  PCardinal(@Result[0])^ := THash.ToBigEndian(Cardinal(FHash));
end;

class function THashBobJenkins.GetHashString(const AString: string): string;
begin
  Result := GetHashValue(AString).ToHexString(8);
end;

class function THashBobJenkins.GetHashValue(const AData: string): Integer;
begin
  Result := HashLittle(Pointer(AData)^, Length(AData) * SizeOf(Char), 0);
end;

class function THashBobJenkins.GetHashValue(const AData; ALength: Integer; AInitialValue: Integer): Integer;
begin
  Result := HashLittle(AData, ALength, AInitialValue);
end;

function THashBobJenkins.HashAsBytes: TBytes;
begin
  Result := GetDigest;
end;

function THashBobJenkins.HashAsInteger: Integer;
begin
  Result := FHash;
end;

function THashBobJenkins.HashAsString: string;
begin
  Result := FHash.ToHexString(8);
end;

class function THashBobJenkins.GetHashBytes(const AData: string): TBytes;
var
  LHash: Integer;
begin
  SetLength(Result, 4);
  LHash := HashLittle(Pointer(AData)^, Length(AData) * SizeOf(Char), 0);
  PCardinal(@Result[0])^ := THash.ToBigEndian(Cardinal(LHash));
end;

procedure THashBobJenkins.Reset(AInitialValue: Integer);
begin
  FHash := AInitialValue;
end;

procedure THashBobJenkins.Update(const Input: string);
begin
  FHash := HashLittle(Pointer(Input)^, Length(Input) * SizeOf(Char), FHash);
end;

procedure THashBobJenkins.Update(const AData; ALength: Cardinal);
begin
  FHash := HashLittle(AData, ALength, FHash);
end;

procedure THashBobJenkins.Update(const AData: TBytes; ALength: Cardinal);
begin
  if ALength = 0 then
    ALength := Length(AData);
  FHash := HashLittle(PByte(AData)^, ALength, FHash);
end;

{ THashFNV1a32 }

class function THashFNV1a32.Hash(const Data; Len, InitVal: Cardinal): Cardinal;
var
  P, PEnd: PByte;
begin
  Result := InitVal;
  P := @Data;
  PEnd := P + Len;
  while P < PEnd do
  begin
    Result := (Result xor Cardinal(P^)) * FNV_PRIME;
    Inc(P);
  end;
end;

class function THashFNV1a32.Create: THashFNV1a32;
begin
  Result.FHash := FNV_SEED;
end;

function THashFNV1a32.GetDigest: TBytes;
begin
  SetLength(Result, 4);
  PCardinal(@Result[0])^ := FHash;
end;

class function THashFNV1a32.GetHashString(const AString: string): string;
begin
  Result := GetHashValue(AString).ToHexString(8);
end;

class function THashFNV1a32.GetHashValue(const AData: string): Integer;
begin
  Result := Integer(Hash(Pointer(AData)^, Length(AData) * SizeOf(Char), FNV_SEED));
end;

class function THashFNV1a32.GetHashString(const AString: RawByteString): string;
begin
  Result := GetHashValue(AString).ToHexString(8);
end;

class function THashFNV1a32.GetHashValue(const AData: RawByteString): Integer;
begin
  Result := Integer(Hash(Pointer(AData)^, Length(AData), FNV_SEED));
end;

class function THashFNV1a32.GetHashValue(const AData; ALength: Cardinal; AInitialValue: Cardinal): Integer;
begin
  Result := Integer(Hash(AData, ALength, AInitialValue));
end;

function THashFNV1a32.HashAsBytes: TBytes;
begin
  Result := GetDigest;
end;

function THashFNV1a32.HashAsInteger: Integer;
begin
  Result := Integer(FHash);
end;

function THashFNV1a32.HashAsString: string;
begin
  Result := FHash.ToHexString(8);
end;

class function THashFNV1a32.GetHashBytes(const AData: string): TBytes;
var
  LHash: Cardinal;
begin
  SetLength(Result, 4);
  LHash := Hash(Pointer(AData)^, Length(AData) * SizeOf(Char), FNV_SEED);
  PCardinal(@Result[0])^ := LHash;
end;

procedure THashFNV1a32.Reset(AInitialValue: Cardinal);
begin
  FHash := AInitialValue;
end;

procedure THashFNV1a32.Update(const Input: string);
begin
  FHash := Hash(Pointer(Input)^, Length(Input) * SizeOf(Char), FHash);
end;

procedure THashFNV1a32.Update(const AData; ALength: Cardinal);
begin
  FHash := Hash(AData, ALength, FHash);
end;

procedure THashFNV1a32.Update(const AData: TBytes; ALength: Cardinal);
begin
  if ALength = 0 then
    ALength := Length(AData);
  FHash := Hash(PByte(AData)^, ALength, FHash);
end;

end.
