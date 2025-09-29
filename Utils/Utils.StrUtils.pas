unit Utils.StrUtils;

{$I zLib.inc}

interface

uses
  SysUtils
  ,Classes
  ,Math;

type
  TStrBuilder = {$IFDEF FPC}TUnicodeStringBuilder{$ELSE}TStringBuilder{$ENDIF};

  TStrUtils = class
  public
    class function Format(const AFormat: string; const AArgs: array of const;
      const AFormatSettings: TFormatSettings): string; overload; static;
    class function Format(const AFormat: string; const AArgs: array of const): string; overload; static;

    class function FormatDateTime(const AFormat: string; const ADateTime: TDateTime;
      const AFormatSettings: TFormatSettings): string; overload; static;
    class function FormatDateTime(const AFormat: string; const ADateTime: TDateTime): string; overload; static;

    class function SameText(const AStr1, AStr2: string): Boolean; static; inline;

    // 将字符串中指定部分替换为新内容
    class function StuffString(const AText: string; const AStart, ALength: Cardinal;
      const ASubText: string): string; static;

    // 字符串查找替换, 并保留具有指定标志区域的内容
    class function ReplaceReserve(const AInputStr, AOldStr, ANewStr: string;
      const AReserveStartTag, AReserveEndTag: string; const AReplaceFlags: TReplaceFlags = [rfReplaceAll]): string; static;

    class function Left(const AStr: string; const ALen: Integer): string; static; inline;
    class function Right(const AStr: string; const ALen: Integer): string; static; inline;
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

class function TStrUtils.Left(const AStr: string; const ALen: Integer): string;
begin
  Result := AStr.Substring(0, ALen);
end;

class function TStrUtils.ReplaceReserve(const AInputStr, AOldStr, ANewStr,
  AReserveStartTag, AReserveEndTag: string;
  const AReplaceFlags: TReplaceFlags): string;

  function _SameText(const AText1, AText2: PChar; const AMaxLen: Cardinal): Boolean;
  begin
    if (rfIgnoreCase in AReplaceFlags) then
      Result := (StrLIComp(AText1, AText2, AMaxLen) = 0)
    else
      Result := (StrLComp(AText1, AText2, AMaxLen) = 0);
  end;

var
  P: PChar;
  I, LInputLen, LOldStrLen, LReserveStartTagLen, LReserveEndTagLen: Integer;
  LIsWithinFlags, LReplaced: Boolean;
  LStrBuilder: TStrBuilder;
begin
  LInputLen := Length(AInputStr);
  LOldStrLen := Length(AOldStr);
  LReserveStartTagLen := Length(AReserveStartTag);
  LReserveEndTagLen := Length(AReserveEndTag);
  LIsWithinFlags := False;
  LReplaced := False;

  P := PChar(AInputStr);
  I := 0;

  LStrBuilder := TStrBuilder.Create;
  try
    while (I < LInputLen) do
    begin
      // 检查起始标志
      if not LIsWithinFlags
        and (LReserveStartTagLen > 0)
        and (I <= LInputLen - LReserveStartTagLen)
        and _SameText(P + I, PChar(AReserveStartTag), LReserveStartTagLen) then
      begin
        LIsWithinFlags := True;
        LStrBuilder.Append(AReserveStartTag);
        Inc(I, LReserveStartTagLen);
        Continue;
      end;

      // 检查结束标志
      if LIsWithinFlags
        and (LReserveEndTagLen > 0)
        and (I <= LInputLen - LReserveEndTagLen)
        and _SameText(P + I, PChar(AReserveEndTag), LReserveEndTagLen) then
      begin
        LIsWithinFlags := False;
        LStrBuilder.Append(AReserveEndTag);
        Inc(I, LReserveEndTagLen);
        Continue;
      end;

      // 进行替换
      if not LIsWithinFlags
        and (not LReplaced or (rfReplaceAll in AReplaceFlags))
        and (I <= LInputLen - LOldStrLen)
        and _SameText(P + I, PChar(AOldStr), LOldStrLen) then
      begin
        LStrBuilder.Append(ANewStr);
        Inc(I, LOldStrLen);
        LReplaced := True;
        Continue;
      end;

      // 将当前字符添加到结果字符串
      LStrBuilder.Append(AInputStr[I + 1]);
      Inc(I);
    end;

    Result := LStrBuilder.ToString;
  finally
    FreeAndNil(LStrBuilder);
  end;
end;

class function TStrUtils.Right(const AStr: string; const ALen: Integer): string;
begin
  Result := AStr.Substring(Max(AStr.Length - ALen, 0));
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
