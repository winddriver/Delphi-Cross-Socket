unit DTF.Character;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils,
  Character;

type
  TCharHelper = record helper for Char
  public
    class function ConvertFromUtf32(AChar: UCS4Char): UnicodeString; static;
    class function ConvertToUtf32(const AString: UnicodeString; AIndex: Integer): UCS4Char; overload; static;
    class function ConvertToUtf32(const AString: UnicodeString; AIndex: Integer; out ACharLength: Integer): UCS4Char; overload; static;
    class function ConvertToUtf32(const AHighSurrogate, ALowSurrogate: UnicodeChar): UCS4Char; overload; static;

    class function GetNumericValue(AChar: UnicodeChar): Double; overload; static;
    class function GetNumericValue(const AString: UnicodeString; AIndex: Integer): Double; overload; static;

    class function GetUnicodeCategory(AChar: UnicodeChar): TUnicodeCategory; overload; static; inline;
    class function GetUnicodeCategory(const AString: UnicodeString; AIndex: Integer): TUnicodeCategory; overload; static;

    class function IsControl(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsControl(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsDigit(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsDigit(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsSurrogate(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsSurrogate(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static;
    class function IsHighSurrogate(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsHighSurrogate(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static;
    class function IsLowSurrogate(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsLowSurrogate(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static;
    class function IsSurrogatePair(const AHighSurrogate, ALowSurrogate: UnicodeChar): Boolean; overload; static; inline;
    class function IsSurrogatePair(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static;

    class function IsLetter(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsLetter(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsLetterOrDigit(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsLetterOrDigit(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsLower(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsLower(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsNumber(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsNumber(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static;

    class function IsPunctuation(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsPunctuation(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsSeparator(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsSeparator(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsSymbol(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsSymbol(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsUpper(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsUpper(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static; inline;

    class function IsWhiteSpace(AChar: UnicodeChar): Boolean; overload; static; inline;
    class function IsWhiteSpace(const AString: UnicodeString; AIndex: Integer): Boolean; overload; static;

    class function ToLower(AChar: UnicodeChar): UnicodeChar; overload; static;
    class function ToLower(const AString: UnicodeString): UnicodeString; inline; overload; static;
    class function ToLower(const AString: UnicodeString; const AOptions: TCharacterOptions): UnicodeString; overload; static;

    class function ToUpper(AChar: UnicodeChar): UnicodeChar; overload; static;
    class function ToUpper(const AString: UnicodeString): UnicodeString; inline; overload; static;
    class function ToUpper(const AString: UnicodeString; const AOptions: TCharacterOptions): UnicodeString; overload; static;

    function GetNumericValue: Double; overload;
    function GetUnicodeCategory: TUnicodeCategory; overload;
    function IsControl: Boolean; overload;
    function IsDigit: Boolean; overload;
    function IsSurrogate: Boolean; overload;
    function IsHighSurrogate: Boolean; overload;
    function IsLowSurrogate: Boolean; overload;
    function IsInArray(const ASomeChars: array of Char): Boolean; overload;
    function IsLetter: Boolean; overload;
    function IsLetterOrDigit: Boolean; overload;
    function IsLower: Boolean; overload;
    function IsNumber: Boolean; overload;
    function IsPunctuation: Boolean; overload;
    function IsSeparator: Boolean; overload;
    function IsSymbol: Boolean; overload;
    function IsUpper: Boolean; overload;
    function IsWhiteSpace: Boolean; overload;
    function ToLower: UnicodeChar; overload;
    function ToUpper: UnicodeChar; overload;
  end;

implementation

{ TCharHelper }

class function TCharHelper.ConvertFromUtf32(AChar: UCS4Char): UnicodeString;
begin
  Result:= TCharacter.ConvertFromUtf32(AChar);
end;

class function TCharHelper.ConvertToUtf32(const AString: UnicodeString;
  AIndex: Integer; out ACharLength: Integer): UCS4Char;
begin
  Result:= TCharacter.ConvertToUtf32(AString, AIndex, ACharLength);
end;

class function TCharHelper.ConvertToUtf32(const AString: UnicodeString;
  AIndex: Integer): UCS4Char;
begin
  Result:= TCharacter.ConvertToUtf32(AString, AIndex);
end;

class function TCharHelper.ConvertToUtf32(const AHighSurrogate,
  ALowSurrogate: UnicodeChar): UCS4Char;
begin
  Result:= TCharacter.ConvertToUtf32(AHighSurrogate, ALowSurrogate);
end;

class function TCharHelper.GetNumericValue(const AString: UnicodeString;
  AIndex: Integer): Double;
begin
  Result:= TCharacter.GetNumericValue(AString, AIndex);
end;

class function TCharHelper.GetNumericValue(AChar: UnicodeChar): Double;
begin
  Result:= TCharacter.GetNumericValue(AChar);
end;

class function TCharHelper.GetUnicodeCategory(
  AChar: UnicodeChar): TUnicodeCategory;
begin
  Result:= TCharacter.GetUnicodeCategory(AChar);
end;

class function TCharHelper.GetUnicodeCategory(const AString: UnicodeString;
  AIndex: Integer): TUnicodeCategory;
begin
  Result:= TCharacter.GetUnicodeCategory(AString, AIndex);
end;

class function TCharHelper.IsControl(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsControl(AString, AIndex);
end;

class function TCharHelper.IsControl(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsControl(AChar);
end;

class function TCharHelper.IsDigit(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsDigit(AString, AIndex);
end;

class function TCharHelper.IsDigit(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsDigit(AChar);
end;

class function TCharHelper.IsHighSurrogate(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsHighSurrogate(AChar);
end;

class function TCharHelper.IsHighSurrogate(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsHighSurrogate(AString, AIndex);
end;

class function TCharHelper.IsLetter(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsLetter(AString, AIndex);
end;

class function TCharHelper.IsLetter(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsLetter(AChar);
end;

class function TCharHelper.IsLetterOrDigit(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsLetterOrDigit(AChar);
end;

class function TCharHelper.IsLetterOrDigit(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsLetterOrDigit(AString, AIndex);
end;

class function TCharHelper.IsLower(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsLower(AString, AIndex);
end;

class function TCharHelper.IsLower(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsLower(AChar);
end;

class function TCharHelper.IsLowSurrogate(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsLowSurrogate(AChar);
end;

class function TCharHelper.IsLowSurrogate(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsLowSurrogate(AString, AIndex);
end;

class function TCharHelper.IsNumber(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsNumber(AChar);
end;

class function TCharHelper.IsNumber(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsNumber(AString, AIndex);
end;

class function TCharHelper.IsPunctuation(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsPunctuation(AChar);
end;

class function TCharHelper.IsPunctuation(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsPunctuation(AString, AIndex);
end;

class function TCharHelper.IsSeparator(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsSeparator(AString, AIndex);
end;

class function TCharHelper.IsSeparator(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsSeparator(AChar);
end;

class function TCharHelper.IsSurrogate(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsSurrogate(AString, AIndex);
end;

class function TCharHelper.IsSurrogate(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsSurrogate(AChar);
end;

class function TCharHelper.IsSurrogatePair(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsSurrogatePair(AString, AIndex);
end;

class function TCharHelper.IsSurrogatePair(const AHighSurrogate,
  ALowSurrogate: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsSurrogatePair(AHighSurrogate, ALowSurrogate);
end;

class function TCharHelper.IsSymbol(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsSymbol(AString, AIndex);
end;

class function TCharHelper.IsSymbol(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsSymbol(AChar);
end;

class function TCharHelper.IsUpper(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsUpper(AString, AIndex);
end;

class function TCharHelper.IsUpper(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsUpper(AChar);
end;

class function TCharHelper.IsWhiteSpace(AChar: UnicodeChar): Boolean;
begin
  Result:= TCharacter.IsWhiteSpace(AChar);
end;

class function TCharHelper.IsWhiteSpace(const AString: UnicodeString;
  AIndex: Integer): Boolean;
begin
  Result:= TCharacter.IsWhiteSpace(AString, AIndex);
end;

class function TCharHelper.ToLower(const AString: UnicodeString;
  const AOptions: TCharacterOptions): UnicodeString;
begin
  Result:= TCharacter.ToLower(AString, AOptions);
end;

class function TCharHelper.ToLower(const AString: UnicodeString): UnicodeString;
begin
  Result:= TCharacter.ToLower(AString);
end;

class function TCharHelper.ToLower(AChar: UnicodeChar): UnicodeChar;
begin
  Result:= TCharacter.ToLower(AChar);
end;

class function TCharHelper.ToUpper(AChar: UnicodeChar): UnicodeChar;
begin
  Result:= TCharacter.ToUpper(AChar);
end;

class function TCharHelper.ToUpper(const AString: UnicodeString): UnicodeString;
begin
  Result:= TCharacter.ToUpper(AString);
end;

class function TCharHelper.ToUpper(const AString: UnicodeString;
  const AOptions: TCharacterOptions): UnicodeString;
begin
  Result:= TCharacter.ToUpper(AString, AOptions);
end;

function TCharHelper.GetNumericValue: Double;
begin
  Result := GetNumericValue(Self);
end;

function TCharHelper.GetUnicodeCategory: TUnicodeCategory;
begin
  Result := GetUnicodeCategory(Self);
end;

function TCharHelper.IsControl: Boolean;
begin
  Result := IsControl(Self);
end;

function TCharHelper.IsDigit: Boolean;
begin
  Result := IsDigit(Self);
end;

function TCharHelper.IsHighSurrogate: Boolean;
begin
  Result := IsHighSurrogate(Self);
end;

function TCharHelper.IsInArray(const ASomeChars: array of Char): Boolean;
var
  LChar: Char;
begin
  for LChar in ASomeChars do
    if (LChar = Self) then Exit(True);
  Result := False;
end;

function TCharHelper.IsLetter: Boolean;
begin
  Result := IsLetter(Self);
end;

function TCharHelper.IsLetterOrDigit: Boolean;
begin
  Result := IsLetterOrDigit(Self);
end;

function TCharHelper.IsLower: Boolean;
begin
  Result := IsLower(Self);
end;

function TCharHelper.IsLowSurrogate: Boolean;
begin
  Result := IsLowSurrogate(Self);
end;

function TCharHelper.IsNumber: Boolean;
begin
  Result := IsNumber(Self);
end;

function TCharHelper.IsPunctuation: Boolean;
begin
  Result := IsPunctuation(Self);
end;

function TCharHelper.IsSeparator: Boolean;
begin
  Result := IsSeparator(Self);
end;

function TCharHelper.IsSurrogate: Boolean;
begin
  Result := IsSurrogate(Self);
end;

function TCharHelper.IsSymbol: Boolean;
begin
  Result := IsSymbol(Self);
end;

function TCharHelper.IsUpper: Boolean;
begin
  Result := IsUpper(Self);
end;

function TCharHelper.IsWhiteSpace: Boolean;
begin
  Result := IsWhiteSpace(Self);
end;

function TCharHelper.ToLower: UnicodeChar;
begin
  Result := ToLower(Self);
end;

function TCharHelper.ToUpper: UnicodeChar;
begin
  Result := ToUpper(Self);
end;

end.

