unit Utils.StrUtils;

{$I zLib.inc}

interface

uses
  SysUtils
  ,Classes;

type
  TStrUtils = class
  public
    class function Format(const AFormat: string; const AArgs: array of const;
      const AFormatSettings: TFormatSettings): string; overload; static;
    class function Format(const AFormat: string; const AArgs: array of const): string; overload; static;

    class function FormatDateTime(const AFormat: string; const ADateTime: TDateTime;
      const AFormatSettings: TFormatSettings): string; overload; static;
    class function FormatDateTime(const AFormat: string; const ADateTime: TDateTime): string; overload; static;

    class function SameText(const AStr1, AStr2: string): Boolean; static;

    class function StuffString(const AText: string; const AStart, ALength: Cardinal;
      const ASubText: string): string; static;
  end;

implementation

{ TStrUtils }

class function TStrUtils.Format(const AFormat: string;
  const AArgs: array of const; const AFormatSettings: TFormatSettings): string;
begin
  Result := SysUtils.{$IFDEF DELPHI}Format{$ELSE}UnicodeFormat{$ENDIF}(AFormat, AArgs, AFormatSettings);
end;

class function TStrUtils.Format(const AFormat: string;
  const AArgs: array of const): string;
var
  LFormatSettings : TFormatSettings;
begin
  LFormatSettings := SysUtils.FormatSettings;
  Result := Format(AFormat, AArgs, LFormatSettings);
end;

class function TStrUtils.FormatDateTime(const AFormat: string;
  const ADateTime: TDateTime; const AFormatSettings: TFormatSettings): string;
begin
  Result := SysUtils.FormatDateTime(AFormat, ADateTime, AFormatSettings);
end;

class function TStrUtils.FormatDateTime(const AFormat: string;
  const ADateTime: TDateTime): string;
var
  LFormatSettings : TFormatSettings;
begin
  LFormatSettings := SysUtils.FormatSettings;
  Result := FormatDateTime(AFormat, ADateTime, LFormatSettings);
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
