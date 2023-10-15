unit Utils.StrUtils;

{$I zLib.inc}

interface

uses
  SysUtils
  ,Classes;

type
  TStrUtils = class
  public
    class function Format(const AFmt: string; const AArgs: array of const; const AFormatSettings: TFormatSettings): string; overload; static;
    class function Format(const AFmt: string; const AArgs: array of const): string; overload; static;

    class function SameText(const AStr1, AStr2: string): Boolean; static;

    class function StuffString(const AText: string; const AStart, ALength: Cardinal;
      const ASubText: string): string; static;
  end;

implementation

{ TStrUtils }

class function TStrUtils.Format(const AFmt: string;
  const AArgs: array of const; const AFormatSettings: TFormatSettings): string;
begin
  Result := SysUtils.{$IFDEF DELPHI}Format{$ELSE}UnicodeFormat{$ENDIF}(AFmt, AArgs, AFormatSettings);
end;

class function TStrUtils.Format(const AFmt: string;
  const AArgs: array of const): string;
begin
  Result := SysUtils.{$IFDEF DELPHI}Format{$ELSE}UnicodeFormat{$ENDIF}(AFmt, AArgs);
end;

class function TStrUtils.SameText(const AStr1, AStr2: string): Boolean;
begin
  Result := SysUtils.{$IFDEF DELPHI}SameText{$ELSE}UnicodeSameText{$ENDIF}(AStr1, AStr2);
end;

class function TStrUtils.StuffString(const AText: string; const AStart,
  ALength: Cardinal; const ASubText: string): string;
begin
  Result := Copy(AText, 1, AStart - 1) +
    ASubText +
    Copy(AText, AStart + ALength, MaxInt);
end;

end.
