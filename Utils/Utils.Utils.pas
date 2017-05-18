{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Utils.Utils;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils,
  System.Math, System.Diagnostics, System.TimeSpan, System.Character;

type
  TUtils = class
  private class var
    FAppFile, FAppPath, FAppHome, FAppDocuments, FAppName: string;
  private
    class constructor Create;
  public
    class function CalcTickDiff(StartTick, EndTick: Cardinal): Cardinal;
    class function TestTime(Proc: TProc): TTimeSpan;
    class function StrToDateTime(const S, Fmt: string): TDateTime; overload;
    class function StrToDateTime(const S: string): TDateTime; overload;
    class function DateTimeToStr(const D: TDateTime; const Fmt: string): string; overload;
    class function DateTimeToStr(const D: TDateTime): string; overload;
    class function ThreadFormat(const Fmt: string; const Args: array of const): string;
    class function BytesToStr(const Bytes: Int64): string; static;
    class function CompareVersion(const V1, V2: string): Integer; static;
    class procedure DelayCall(Tick: Cardinal; Proc: TProc); static;
    class function GetGUID: string; static;
    class function RandomStr(const ABaseChars: string; ASize: Integer): string; static;
    class function EditDistance(const source, target: string): Integer; static;
    class function SimilarText(const AStr1, AStr2: string): Single; static;

    class function IsSpaceChar(const C: Char): Boolean; static;
    class function UnicodeTrim(const S: string): string; static;
    class function UnicodeTrimLeft(const S: string): string; static;
    class function UnicodeTrimRight(const S: string): string; static;

    class procedure BinToHex(ABuffer: Pointer; ABufSize: Integer; AText: PChar); overload; static;
    class function BinToHex(ABuffer: Pointer; ABufSize: Integer): string; overload; static; inline;
    class function BytesToHex(const ABytes: TBytes; AOffset, ACount: Integer): string; overload; static; inline;
    class function BytesToHex(const ABytes: TBytes): string; overload; static; inline;

    class property AppFile: string read FAppFile;
    class property AppPath: string read FAppPath;
    class property AppHome: string read FAppHome;
    class property AppDocuments: string read FAppDocuments; // ios, android 可写
    class property AppName: string read FAppName;
  end;

implementation

{ TUtils }

class constructor TUtils.Create;
begin
  FAppFile := ParamStr(0);
  FAppName := ChangeFileExt(ExtractFileName(FAppFile), '');
  FAppPath := IncludeTrailingPathDelimiter(ExtractFilePath(FAppFile));

  {$IF defined(IOS) or defined(ANDROID)}
  FAppHome := IncludeTrailingPathDelimiter(TPath.GetHomePath);
  {$ELSE}
  FAppHome := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetHomePath, FAppName));
  {$ENDIF}

  {$IF defined(IOS) or defined(ANDROID)}
  FAppDocuments := IncludeTrailingPathDelimiter(TPath.GetDocumentsPath);
  {$ELSE}
  FAppDocuments := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetDocumentsPath, FAppName));
  {$ENDIF}
end;

class function TUtils.DateTimeToStr(const D: TDateTime;
  const Fmt: string): string;
begin
  Result := FormatDateTime(Fmt, D, TFormatSettings.Create);
end;

class function TUtils.DateTimeToStr(const D: TDateTime): string;
begin
  Result := DateTimeToStr(D, 'yyyy-mm-dd hh:nn:ss');
end;

class procedure TUtils.DelayCall(Tick: Cardinal; Proc: TProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(Tick);
      Proc();
    end).Start;
end;

class function TUtils.GetGUID: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := Format('%.8x%.4x%.4x%.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x',
    [LGuid.D1, LGuid.D2, LGuid.D3, LGuid.D4[0], LGuid.D4[1], LGuid.D4[2], LGuid.D4[3],
    LGuid.D4[4], LGuid.D4[5], LGuid.D4[6], LGuid.D4[7]]);

//  SetLength(Result, 32);
//  StrLFmt(PChar(Result), 32, '%.8x%.4x%.4x%.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x',
//    [LGuid.D1, LGuid.D2, LGuid.D3, LGuid.D4[0], LGuid.D4[1], LGuid.D4[2], LGuid.D4[3],
//    LGuid.D4[4], LGuid.D4[5], LGuid.D4[6], LGuid.D4[7]]);
end;

class function TUtils.IsSpaceChar(const C: Char): Boolean;
begin
  Result := (C.GetUnicodeCategory in [
    TUnicodeCategory.ucControl,
    TUnicodeCategory.ucUnassigned,
    TUnicodeCategory.ucSpaceSeparator
  ]);
end;

class function TUtils.RandomStr(const ABaseChars: string;
  ASize: Integer): string;
var
  LBaseLow, LBaseHigh, I: Integer;
begin
  Randomize;
  LBaseLow := Low(ABaseChars);
  LBaseHigh := High(ABaseChars);
  SetLength(Result, ASize);
  for I := Low(Result) to High(Result) do
    Result[I] := ABaseChars[RandomRange(LBaseLow, LBaseHigh + 1)];
end;

class function TUtils.CalcTickDiff(StartTick, EndTick: Cardinal): Cardinal;
begin
  if (EndTick >= StartTick) then
    Result := EndTick - StartTick
  else
    Result := High(LongWord) - StartTick + EndTick;
end;

class function TUtils.CompareVersion(const V1, V2: string): Integer;
var
  LArr1, LArr2: TArray<string>;
  I, I1, I2, LSize1, LSize2: Integer;
begin
  LArr1 := V1.Split(['.']);
  LArr2 := V2.Split(['.']);
  LSize1 := Length(LArr1);
  LSize2 := Length(LArr2);

  I := 0;
  while (I < LSize1) and (I < LSize2) do
  begin
    I1 := StrToIntDef(LArr1[I], 0);
    I2 := StrToIntDef(LArr2[I], 0);
    if (I1 > I2) then
      Exit(1)
    else if (I1 < I2) then
      Exit(-1);

    Inc(I);
  end;

  Result := (LSize1 - LSize2);
end;

class function TUtils.SimilarText(const AStr1, AStr2: string): Single;
begin
  Result := 1 - EditDistance(AStr1, AStr2) / Max(AStr1.Length, AStr2.Length);
end;

class function TUtils.StrToDateTime(const S: string): TDateTime;
begin
  Result := StrToDateTime(S, 'yyyy-mm-dd hh:nn:ss');
end;

class function TUtils.StrToDateTime(const S, Fmt: string): TDateTime;
// Fmt格式字符串：空格前是日期格式，空格后是时间格式
// 必须是这样：YYYY-MM-DD HH:NN:SS或者MM-DD-YYYY HH:NN:SS
// 不能用空格做时间单位中间的间隔符
  function GetSeparator(const S: string): Char;
  begin
    for Result in S do
      if not CharInSet(Result, ['a'..'z', 'A'..'Z']) then Exit;
    Result := #0;
  end;
var
  Fms: TFormatSettings;
  DateFmt, TimeFmt: string;
  p: Integer;
begin
  p := Fmt.IndexOf(' ');
  DateFmt := Fmt.Substring(0, p);
  TimeFmt := Fmt.Substring(p + 1);
  {$if COMPILERVERSION >= 20}
  Fms := TFormatSettings.Create;
  {$else}
  GetLocaleFormatSettings(GetThreadLocale, Fms);
  {$ifend}
  Fms.DateSeparator := GetSeparator(DateFmt);
  Fms.TimeSeparator := GetSeparator(TimeFmt);
  Fms.ShortDateFormat := DateFmt;
  Fms.LongDateFormat := DateFmt;
  Fms.ShortTimeFormat := TimeFmt;
  Fms.LongTimeFormat := TimeFmt;
  Result := System.SysUtils.StrToDateTime(S, Fms);
end;

class procedure TUtils.BinToHex(ABuffer: Pointer; ABufSize: Integer;
  AText: PChar);
const
  XD: array[0..15] of char = ('0', '1', '2', '3', '4', '5', '6', '7',
                              '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
var
  I: Integer;
  PBuffer: PByte;
  PText: PChar;
begin
  PBuffer := ABuffer;
  PText := AText;
  for I := 0 to ABufSize - 1 do
  begin
    PText[0] := XD[(PBuffer[I] shr 4) and $0f];
    PText[1] := XD[PBuffer[I] and $0f];
    Inc(PText, 2);
  end;
end;

class function TUtils.BinToHex(ABuffer: Pointer; ABufSize: Integer): string;
begin
  SetLength(Result, ABufSize * 2);
  BinToHex(ABuffer, ABufSize, PChar(Result));
end;

class function TUtils.BytesToHex(const ABytes: TBytes; AOffset,
  ACount: Integer): string;
begin
  Result := BinToHex(@ABytes[AOffset], ACount);
end;

class function TUtils.BytesToHex(const ABytes: TBytes): string;
begin
  Result := BytesToHex(ABytes, 0, Length(ABytes));
end;

class function TUtils.BytesToStr(const Bytes: Int64): string;
const
  KBYTES = Int64(1024);
  MBYTES = KBYTES * 1024;
  GBYTES = MBYTES * 1024;
  TBYTES = GBYTES * 1024;
begin
  if (Bytes = 0) then
    Result := ''
  else if (Bytes < KBYTES) then
    Result := Format('%dB', [Bytes])
  else if (Bytes < MBYTES) then
    Result := FormatFloat('0.##KB', Bytes / KBYTES)
  else if (Bytes < GBYTES) then
    Result := FormatFloat('0.##MB', Bytes / MBYTES)
  else if (Bytes < TBYTES) then
    Result := FormatFloat('0.##GB', Bytes / GBYTES)
  else
    Result := FormatFloat('0.##TB', Bytes / TBYTES);
end;

class function TUtils.TestTime(Proc: TProc): TTimeSpan;
var
  LWatch: TStopwatch;
begin
  LWatch := TStopwatch.StartNew;
  Proc();
  LWatch.Stop;
  Result := LWatch.Elapsed;
end;

class function TUtils.ThreadFormat(const Fmt: string;
  const Args: array of const): string;
begin
  Result := Format(Fmt, Args, TFormatSettings.Create);
end;

class function TUtils.UnicodeTrim(const S: string): string;
var
  I, L: Integer;
begin
  L := S.Length - 1;
  I := 0;
  if (L > -1) and not IsSpaceChar(S.Chars[I]) and not IsSpaceChar(S.Chars[L]) then Exit(S);

  while (I <= L) and IsSpaceChar(S.Chars[I]) do
    Inc(I);

  if (I > L) then Exit('');

  while IsSpaceChar(S.Chars[L]) do
    Dec(L);

  Result := S.SubString(I, L - I + 1);
end;

class function TUtils.UnicodeTrimLeft(const S: string): string;
var
  I, L: Integer;
begin
  L := S.Length - 1;
  I := 0;
  while (I <= L) and IsSpaceChar(S.Chars[I]) do
    Inc(I);
  if (I > 0) then
    Result := S.SubString(I)
  else
    Result := S;
end;

class function TUtils.UnicodeTrimRight(const S: string): string;
var
  I: Integer;
begin
  I := S.Length - 1;
  if (I >= 0) and not IsSpaceChar(S.Chars[I]) then
    Result := S
  else
  begin
    while (I >= 0) and IsSpaceChar(S.Chars[I]) do
      Dec(I);
    Result := S.SubString(0, I + 1);
  end;
end;

class function TUtils.EditDistance(const source, target: string): Integer;
var
  i, j, edIns, edDel, edRep: Integer;
  d: TArray<TArray<Integer>>;
begin
  SetLength(d, Length(source) + 1, Length(target) + 1);

  for i := 0 to source.Length do
    d[i][0] := i;

  for j := 0 to target.Length do
    d[0][j] := j;

  for i := 1 to source.Length do
  begin
    for j := 1 to target.Length do
    begin
      if((source[i - 1] = target[j - 1])) then
      begin
        d[i][j] := d[i - 1][j - 1]; //不需要编辑操作
      end else
      begin
        edIns := d[i][j - 1] + 1; //source 插入字符
        edDel := d[i - 1][j] + 1; //source 删除字符
        edRep := d[i - 1][j - 1] + 1; //source 替换字符

        d[i][j] := Min(Min(edIns, edDel), edRep);
      end;
    end;
  end;

  Result := d[source.length][target.length];
end;

end.
