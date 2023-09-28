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

end.
