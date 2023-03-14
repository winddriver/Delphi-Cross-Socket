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
  System.SysUtils,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.Math,
  System.Diagnostics,
  System.TimeSpan,
  System.Character,
  System.SysConst,
  System.Generics.Defaults,
  System.Generics.Collections;

type
  TConstProc = reference to procedure;
  TConstProc<T> = reference to procedure (const Arg1: T);
  TConstProc<T1,T2> = reference to procedure (const Arg1: T1; const Arg2: T2);
  TConstProc<T1,T2,T3> = reference to procedure (const Arg1: T1; const Arg2: T2; const Arg3: T3);
  TConstProc<T1,T2,T3,T4> = reference to procedure (const Arg1: T1; const Arg2: T2; const Arg3: T3; const Arg4: T4);

  TConstFunc<TResult> = reference to function: TResult;
  TConstFunc<T,TResult> = reference to function (const Arg1: T): TResult;
  TConstFunc<T1,T2,TResult> = reference to function (const Arg1: T1; const Arg2: T2): TResult;
  TConstFunc<T1,T2,T3,TResult> = reference to function (const Arg1: T1; const Arg2: T2; const Arg3: T3): TResult;
  TConstFunc<T1,T2,T3,T4,TResult> = reference to function (const Arg1: T1; const Arg2: T2; const Arg3: T3; const Arg4: T4): TResult;

  TUnicodeCategories = set of TUnicodeCategory;

  TUtils = class
  private class var
    FAppFile, FAppPath, FAppHome, FAppDocuments, FAppName: string;
  private
    class constructor Create;
  public
    class function CalcTickDiff(AStartTick, AEndTick: Cardinal): Cardinal;
    class function TestTime(AProc: TProc): TTimeSpan;
    class function StrToDateTime(const S, Fmt: string): TDateTime; overload;
    class function StrToDateTime(const S: string): TDateTime; overload;
    class function DateTimeToStr(const D: TDateTime; const Fmt: string): string; overload;
    class function DateTimeToStr(const D: TDateTime): string; overload;
    class function ThreadFormat(const Fmt: string; const Args: array of const): string;

    class function BytesToStr(const BytesCount: Int64): string; static;
    class procedure DelayCall(ATick: Cardinal; AProc: TProc); static;
    class function GetGUID: string; static;
    class function RandomStr(const ABaseChars: string; ASize: Integer): string; static;
    class function StrSimilarity(const AStr1, AStr2: string): Single; static;

    class function ToDBC(const AChar: Char): Char; overload; static;
    class function ToDBC(const AStr: string): string; overload; static;
    class function ClearStr(const AStr: string; const AKeepChars: array of Char): string; static;

    class function IsSpaceChar(const C: Char): Boolean; static;
    class function UnicodeTrim(const S: string): string; static;
    class function UnicodeTrimLeft(const S: string): string; static;
    class function UnicodeTrimRight(const S: string): string; static;
    class function UnicodeClear(const S: string; const ACats: TUnicodeCategories): string; overload; static;
    class function UnicodeClear(const S: string): string; overload; static;
    class function StrIPos(const ASubStr, AStr: string; AOffset: Integer): Integer; static;
    class function Replace(const AStr: string; const ASubStrs: array of string;
      const ANewStr: string; const AReplaceFlags: TReplaceFlags = [rfReplaceAll, rfIgnoreCase]): string; static;

    class function EndsWith(const AStr: string; const AValues: array of string; const AIgnoreCase: Boolean): Boolean; overload; static;
    class function EndsWith(const AStr: string; const AValues: array of string): Boolean; overload; static;

    class function StartsWith(const AStr: string; const AValues: array of string; const AIgnoreCase: Boolean): Boolean; overload; static;
    class function StartsWith(const AStr: string; const AValues: array of string): Boolean; overload; static;

    class function CompareStringIncludeNumber(const AStr1, AStr2: string;
      const AIgnoreCase: Boolean = False): Integer; static;
    class function CompareVersion(const V1, V2: string): Integer; static;

    // 内存数据转16进制字符串(由于系统自带的转出来是大写, 我希望转成小写的, 所以自己写了这个方法)
    class procedure BinToHex(ABuffer: Pointer; ABufSize: Integer; AText: PChar); overload; static;
    class function BinToHex(ABuffer: Pointer; ABufSize: Integer): string; overload; static; inline;
    class function BytesToHex(const ABytes: TBytes; AOffset, ACount: Integer): string; overload; static; inline;
    class function BytesToHex(const ABytes: TBytes): string; overload; static; inline;

    class procedure HexToBin(AText: PChar; ABuffer: Pointer; ABufSize: Integer); overload; static; inline;
    class procedure HexToBin(const AText: string; ABuffer: Pointer; ABufSize: Integer); overload; static; inline;
    class function HexToBytes(AText: PChar): TBytes; overload; static;
    class function HexToBytes(const AText: string): TBytes; overload; static; inline;

    class function GetFullFileName(const AFileName: string): string; static;
    class function GetFileSize(const AFileName: string): Int64; static;
    class function MoveFile(const ASrcFileName, ADstFileName: string): Boolean; static;
    class function MoveDir(const ASrcDirName, ADstDirName: string): Boolean; static;

    class function StrToPChar(const S: string): PChar; static;
    class function PCharToStr(const S: PChar): string; static;

    // 判断两段日期是否有交集
    class function IsCrossDate(const AStartDate1, AEndDate1, AStartDate2, AEndDate2: TDateTime): Boolean; static;

    // 获取缓存中的字符串编码
    class function GetBufEncoding(const ABuf: Pointer; const ACount: Integer;
      var AEncoding: TEncoding; const ADefaultEncoding: TEncoding): Integer; static;

    // 自动检测缓存中的字符串编码并解码出字符串
    class function GetString(const AStrBuf: PByte; ABufSize: Integer;
      const AEncoding: TEncoding = nil): string; overload; static;
    class function GetString(const AStrBytes: TBytes; AIndex, ACount: Integer;
      const AEncoding: TEncoding = nil): string; overload; static;
    class function GetString(const AStrBytes: TBytes;
      const AEncoding: TEncoding = nil): string; overload; static;

    class function ArrayOfToTArray<T>(const AValues: array of T): TArray<T>; static;
    class function IIF<T>(const ATrueFalse: Boolean; const ATrueValue, AFalseValue: T): T; static;

    class function IndexOfArray<T>(const AArray: array of T; const AItem: T;
      const AComparison: TComparison<T> = nil; const AIndex: Integer = 0;
      const ACount: Integer = 0): Integer; static;
    class function ExistsInArray<T>(const AArray: array of T; const AItem: T): Boolean; static;

    class property AppFile: string read FAppFile;
    class property AppPath: string read FAppPath;
    class property AppHome: string read FAppHome;
    class property AppDocuments: string read FAppDocuments; // ios, android 可写
    class property AppName: string read FAppName;
  end;

  TEncodingHelper = class helper for TEncoding
    /// <summary>
    ///   从内存块中直接解码出字符串, 省去先将内存块转换为TBytes, 从而提高效率
    /// </summary>
    function GetString(const ABytes: PByte; AByteCount: Integer): string; overload;
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

class procedure TUtils.DelayCall(ATick: Cardinal; AProc: TProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(ATick);
      AProc();
    end).Start;
end;

class function TUtils.EndsWith(const AStr: string;
  const AValues: array of string; const AIgnoreCase: Boolean): Boolean;
var
  LValue: string;
begin
  for LValue in AValues do
    if AStr.EndsWith(LValue, AIgnoreCase) then Exit(True);

  Result := False;
end;

class function TUtils.EndsWith(const AStr: string;
  const AValues: array of string): Boolean;
begin
  Result := EndsWith(AStr, AValues, False);
end;

class function TUtils.ExistsInArray<T>(const AArray: array of T;
  const AItem: T): Boolean;
begin
  Result := (IndexOfArray(AArray, AItem, nil, 0, 0) >= 0);
end;

class function TUtils.GetBufEncoding(const ABuf: Pointer; const ACount: Integer;
  var AEncoding: TEncoding; const ADefaultEncoding: TEncoding): Integer;

  function ContainsPreamble(const APreamble: TBytes; out APreambleSize: Integer): Boolean;
  begin
    if (ACount < Length(APreamble)) then Exit(False);

    Result := CompareMem(ABuf, @APreamble[0], Length(APreamble));

    if Result then
      APreambleSize := Length(APreamble)
    else
      APreambleSize := 0;
  end;

begin
  if (AEncoding = nil) then
  begin
    if ContainsPreamble(TEncoding.UTF8.GetPreamble, Result) then
      AEncoding := TEncoding.UTF8
    else if ContainsPreamble(TEncoding.Unicode.GetPreamble, Result) then
      AEncoding := TEncoding.Unicode
    else if ContainsPreamble(TEncoding.BigEndianUnicode.GetPreamble, Result) then
      AEncoding := TEncoding.BigEndianUnicode
    else
    begin
      if (ADefaultEncoding <> nil) then
        AEncoding := ADefaultEncoding
      else
        AEncoding := TEncoding.UTF8;
      ContainsPreamble(AEncoding.GetPreamble, Result);
    end;
  end else
  begin
    ContainsPreamble(AEncoding.GetPreamble, Result);
  end;
end;

class function TUtils.GetFileSize(const AFileName: string): Int64;
var
  LFileStream: TStream;
begin
  LFileStream := TFile.Open(AFileName, TFileMode.fmOpen, TFileAccess.faRead, TFileShare.fsReadWrite);
  try
    Result := LFileStream.Size;
  finally
    FreeAndNil(LFileStream);
  end;
end;

class function TUtils.GetFullFileName(const AFileName: string): string;
begin
  if
    {$IFDEF MSWINDOWS}
    // Windows 下不以驱动器号开头的文件名都视为相对路径
    not TPath.DriveExists(AFileName)
    {$ELSE}
    // Posix 下直接调用相对路径的现成函数判断
    TPath.IsRelativePath(AFileName)
    {$ENDIF}
  then
    // 相对路径的文件名用程序所在路径补全
    Result := TPath.Combine(TUtils.AppPath, AFileName)
  else
    Result := AFileName;
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

class function TUtils.GetString(const AStrBuf: PByte; ABufSize: Integer;
  const AEncoding: TEncoding): string;
var
  LEncoding: TEncoding;
  LBomLen: Integer;
begin
  if (AStrBuf = nil) or (ABufSize <= 0) then Exit('');

  LEncoding := AEncoding;
  LBomLen := TUtils.GetBufEncoding(AStrBuf, ABufSize, LEncoding, TEncoding.UTF8);

  Result := LEncoding.GetString(PByte(NativeInt(AStrBuf) + LBomLen), ABufSize - LBomLen);
end;

class function TUtils.GetString(const AStrBytes: TBytes; AIndex,
  ACount: Integer; const AEncoding: TEncoding): string;
begin
  Result := GetString(PByte(@AStrBytes[AIndex]), ACount);
end;

class function TUtils.GetString(const AStrBytes: TBytes;
  const AEncoding: TEncoding): string;
begin
  Result := GetString(AStrBytes, 0, Length(AStrBytes), AEncoding);
end;

class procedure TUtils.HexToBin(AText: PChar; ABuffer: Pointer;
  ABufSize: Integer);
begin
  System.Classes.HexToBin(AText, ABuffer, ABufSize);
end;

class procedure TUtils.HexToBin(const AText: string; ABuffer: Pointer;
  ABufSize: Integer);
begin
  HexToBin(PChar(AText), ABuffer, ABufSize);
end;

class function TUtils.HexToBytes(AText: PChar): TBytes;
var
  LBufSize: Integer;
begin
  LBufSize := StrLen(AText) div 2;
  SetLength(Result, LBufSize);
  HexToBin(AText, Pointer(Result), LBufSize);
end;

class function TUtils.HexToBytes(const AText: string): TBytes;
begin
  Result := HexToBytes(PChar(AText));
end;

class function TUtils.IIF<T>(const ATrueFalse: Boolean; const ATrueValue,
  AFalseValue: T): T;
begin
  if ATrueFalse then
    Result := ATrueValue
  else
    Result := AFalseValue;
end;

class function TUtils.IndexOfArray<T>(const AArray: array of T; const AItem: T;
  const AComparison: TComparison<T>; const AIndex, ACount: Integer): Integer;
var
  LComparer: IComparer<T>;
  LIndex, LCount, I: Integer;
begin
  if (Length(AArray) = 0) then Exit(-1);

  if Assigned(AComparison) then
    LComparer := TComparer<T>.Construct(AComparison)
  else
    LComparer := TComparer<T>.Default;

  if (AIndex >= 0) then
    LIndex := AIndex
  else
    LIndex := 0;

  if (ACount >= 0) then
    LCount := ACount
  else
    LCount := 0;

  if (LCount <= 0) then
    LCount := Length(AArray) - LIndex;

  for I := LIndex to LIndex + LCount - 1 do
    if (LComparer.Compare(AArray[I], AItem) = 0) then Exit(I);

  Result := -1;
end;

class function TUtils.IsCrossDate(const AStartDate1, AEndDate1, AStartDate2,
  AEndDate2: TDateTime): Boolean;
begin
  Result := (AEndDate1 >= AStartDate2) and (AStartDate1 <= AEndDate2);
end;

class function TUtils.IsSpaceChar(const C: Char): Boolean;
begin
  Result := (C.GetUnicodeCategory in [
    TUnicodeCategory.ucControl,
    TUnicodeCategory.ucFormat,
    TUnicodeCategory.ucUnassigned,
    TUnicodeCategory.ucSpaceSeparator
  ]);
end;

class function TUtils.MoveDir(const ASrcDirName, ADstDirName: string): Boolean;
begin
  Result := False;
  if not TDirectory.Exists(ASrcDirName) then Exit;

  TDirectory.CreateDirectory(ADstDirName);

  TDirectory.GetFiles(ASrcDirName, '*', TSearchOption.soAllDirectories,
    function(const ADirName: string; const AFileInfo: TSearchRec): Boolean
    var
      LSrcFileName, LDstFileName: string;
    begin
      Result := False;

      LSrcFileName := TPath.Combine(ADirName, AFileInfo.Name);
      LDstFileName := TPath.Combine(ADstDirName, AFileInfo.Name);

      if (AFileInfo.Attr and System.SysUtils.faDirectory = 0) then
      begin
        {$IFDEF MSWINDOWS}
        FileSetAttr(LSrcFileName, System.SysUtils.faNormal);
        {$ENDIF MSWINDOWS}

        MoveFile(LSrcFileName, LDstFileName);

        {$IFDEF MSWINDOWS}
        FileSetAttr(LDstFileName, AFileInfo.Attr);
        {$ENDIF MSWINDOWS}
      end else
      begin
        TDirectory.CreateDirectory(LDstFileName);
      end;
    end);

  if TDirectory.Exists(ASrcDirName) then
    TDirectory.Delete(ASrcDirName, True);

  Result := True;
end;

class function TUtils.MoveFile(const ASrcFileName,
  ADstFileName: string): Boolean;
var
  LDstDirName: string;
begin
  if not TFile.Exists(ASrcFileName) then Exit(False);

  LDstDirName := TPath.GetDirectoryName(ADstFileName);
  if (LDstDirName <> '') then
    TDirectory.CreateDirectory(LDstDirName);

  if TFile.Exists(ADstFileName) then
    TFile.Delete(ADstFileName);

  Result := RenameFile(ASrcFileName, ADstFileName);
end;

class function TUtils.PCharToStr(const S: PChar): string;
begin
  SetString(Result, S, StrLen(S));
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

class function TUtils.Replace(const AStr: string;
  const ASubStrs: array of string; const ANewStr: string;
  const AReplaceFlags: TReplaceFlags): string;
var
  LSubStr: string;
begin
  Result := AStr;
  for LSubStr in ASubStrs do
    Result := Result.Replace(LSubStr, ANewStr, AReplaceFlags);
end;

class function TUtils.CalcTickDiff(AStartTick, AEndTick: Cardinal): Cardinal;
begin
  if (AEndTick >= AStartTick) then
    Result := AEndTick - AStartTick
  else
    Result := High(Cardinal) - AStartTick + AEndTick;
end;

class function TUtils.CompareStringIncludeNumber(const AStr1,
  AStr2: string; const AIgnoreCase: Boolean): Integer;
var
  I, J, LStrLen1, LStrLen2: Integer;
  C1, C2: Char;
  LNumStr1, LNumStr2: string;
  LNum1, LNum2: Int64;
begin
  I := 0;
  J := 0;
  LStrLen1 := AStr1.Length;
  LStrLen2 := AStr2.Length;

  while (I < LStrLen1)
   and (J < LStrLen2) do
  begin
    C1 := AStr1.Chars[I];
    C2 := AStr2.Chars[J];

    if C1.IsDigit and C2.IsDigit then
    begin
      LNumStr1 := C1;
      LNumStr2 := C2;

      Inc(I);
      while (I < LStrLen1) do
      begin
        C1 := AStr1.Chars[I];
        if not C1.IsDigit then Break;

        LNumStr1 := LNumStr1 + C1;
        Inc(I);
      end;

      Inc(J);
      while (J < LStrLen2) do
      begin
        C2 := AStr2.Chars[J];
        if not C2.IsDigit then Break;

        LNumStr2 := LNumStr2 + C2;
        Inc(J);
      end;

      LNum1 := StrToInt64Def(LNumStr1, -1);
      LNum2 := StrToInt64Def(LNumStr2, -1);

      if (LNum1 > LNum2) then Exit(1)
      else if (LNum1 < LNum2) then Exit(-1);
    end else
    begin
      if AIgnoreCase then
      begin
        C1 := C1.ToUpper;
        C2 := C2.ToUpper;
      end;

      if (C1 > C2) then Exit(1)
      else if (C1 < C2) then Exit(-1);

      Inc(I);
      Inc(J);
    end;
  end;

  LStrLen1 := LStrLen1 - I;
  LStrLen2 := LStrLen2 - J;

  if (LStrLen1 > LStrLen2) then Exit(1)
  else if (LStrLen1 < LStrLen2) then Exit(-1)
  else Exit(0);
end;

class function TUtils.CompareVersion(const V1, V2: string): Integer;
begin
  Result := CompareStringIncludeNumber(V1, V2, True);
end;

class function TUtils.StrSimilarity(const AStr1, AStr2: string): Single;
// 算法来源:
//   https://en.wikipedia.org/wiki/S%C3%B8rensen%E2%80%93Dice_coefficient
//   https://github.com/aceakash/string-similarity
var
  LFirstBigrams: TDictionary<string, Integer>;
  I, LCount, LIntersectionSize : Integer;
  LBigram: string;
begin
  if (AStr1 = AStr2) then Exit(1);
  if (AStr1.Length < 2) or (AStr2.Length < 2) then Exit(0);

  LFirstBigrams := TDictionary<string, Integer>.Create;
  try
    for I := 0 to AStr1.Length - 2 do
    begin
      LBigram := AStr1.Substring(I, 2);
      if LFirstBigrams.TryGetValue(LBigram, LCount) then
        LFirstBigrams.AddOrSetValue(LBigram, LCount + 1)
      else
        LFirstBigrams.Add(LBigram, 1);
    end;

    LIntersectionSize := 0;
    for I := 0 to AStr2.Length - 2 do
    begin
      LBigram := AStr2.Substring(I, 2);
      if LFirstBigrams.TryGetValue(LBigram, LCount)
        and (LCount > 0) then
      begin
        LFirstBigrams.AddOrSetValue(LBigram, LCount - 1);
        Inc(LIntersectionSize);
      end;
    end;

    Result := (2.0 * LIntersectionSize) / (AStr1.Length + AStr2.Length - 2);
  finally
    FreeAndNil(LFirstBigrams);
  end;
end;

class function TUtils.StartsWith(const AStr: string;
  const AValues: array of string; const AIgnoreCase: Boolean): Boolean;
var
  LValue: string;
begin
  for LValue in AValues do
    if AStr.StartsWith(LValue, AIgnoreCase) then Exit(True);

  Result := False;
end;

class function TUtils.StartsWith(const AStr: string;
  const AValues: array of string): Boolean;
begin
  Result := StartsWith(AStr, AValues, False);
end;

class function TUtils.StrIPos(const ASubStr, AStr: string;
  AOffset: Integer): Integer;
var
  I, LIterCnt, L, J: Integer;
  PSubStr, PS: PChar;
  LCh: Char;
begin
  PSubStr := Pointer(ASubStr);
  PS := Pointer(AStr);
  if (PSubStr = nil) or (PS = nil) or (AOffset < 1) then
    Exit(0);
  L := Length(ASubStr);
  { Calculate the number of possible iterations. }
  LIterCnt := Length(AStr) - AOffset - L + 2;
  if (L > 0) and (LIterCnt > 0) then
  begin
    Inc(PS, AOffset - 1);
    I := 0;
    LCh := UpCase(PSubStr[0]);
    if L = 1 then   // Special case when Substring length is 1
      repeat
        if UpCase(PS[I]) = LCh then
          Exit(I + AOffset);
        Inc(I);
      until I = LIterCnt
    else
      repeat
        if UpCase(PS[I]) = LCh then
        begin
          J := 1;
          repeat
            if UpCase(PS[I + J]) = UpCase(PSubStr[J]) then
            begin
              Inc(J);
              if J = L then
                Exit(I + AOffset);
            end
            else
              Break;
          until False;
        end;
        Inc(I);
      until I = LIterCnt;
  end;

  Result := 0;
end;

class function TUtils.StrToDateTime(const S: string): TDateTime;
begin
  Result := StrToDateTime(S, 'yyyy-mm-dd hh:nn:ss');
end;

class function TUtils.StrToPChar(const S: string): PChar;
begin
  if (S <> '') then
    Result := PChar(S)
  else
    Result := nil;
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

class function TUtils.ArrayOfToTArray<T>(const AValues: array of T): TArray<T>;
var
  I: Integer;
begin
  SetLength(Result, Length(AValues));
  for I := Low(Result) to High(Result) do
    Result[I] := AValues[I];
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

class function TUtils.BytesToStr(const BytesCount: Int64): string;
const
  KBYTES = Int64(1024);
  MBYTES = KBYTES * 1024;
  GBYTES = MBYTES * 1024;
  TBYTES = GBYTES * 1024;
begin
  if (BytesCount = 0) then
    Result := ''
  else if (BytesCount < KBYTES) then
    Result := Format('%dB', [BytesCount])
  else if (BytesCount < MBYTES) then
    Result := FormatFloat('0.##KB', BytesCount / KBYTES)
  else if (BytesCount < GBYTES) then
    Result := FormatFloat('0.##MB', BytesCount / MBYTES)
  else if (BytesCount < TBYTES) then
    Result := FormatFloat('0.##GB', BytesCount / GBYTES)
  else
    Result := FormatFloat('0.##TB', BytesCount / TBYTES);
end;

class function TUtils.TestTime(AProc: TProc): TTimeSpan;
var
  LWatch: TStopwatch;
begin
  LWatch := TStopwatch.StartNew;
  AProc();
  LWatch.Stop;
  Result := LWatch.Elapsed;
end;

class function TUtils.ThreadFormat(const Fmt: string;
  const Args: array of const): string;
begin
  Result := Format(Fmt, Args, TFormatSettings.Create);
end;

class function TUtils.ToDBC(const AChar: Char): Char;
begin
  if (Ord(AChar) = $3000) then
    Result := ' '
  else if (Ord(AChar) > $FF00) and (Ord(AChar) < $FF5F) then
    Result := Chr(Ord(AChar) - $FEE0)
  else
    Result := AChar;
end;

class function TUtils.ToDBC(const AStr: string): string;
var
  I: Integer;
begin
  SetLength(Result, Length(AStr));

  for I := 1 to Length(AStr) do
    Result[I] := ToDBC(AStr[I]);
end;

class function TUtils.ClearStr(const AStr: string;
  const AKeepChars: array of Char): string;
var
  I, J: Integer;
  C: Char;
begin
  SetLength(Result, Length(AStr));
  J := 1;
  for I := 1 to Length(AStr) do
  begin
    C := AStr[I];
    if C.IsInArray(AKeepChars) then
    begin
      Result[J] := C;
      J := J + 1;
    end;
  end;
  SetLength(Result, J - 1);
end;

class function TUtils.UnicodeClear(const S: string;
  const ACats: TUnicodeCategories): string;
var
  LChar: Char;
  I: Integer;
begin
  SetLength(Result, Length(S));
  I := 1;

  for LChar in S do
  begin
    if not (LChar.GetUnicodeCategory in ACats) then
    begin
      Result[I] := LChar;
      Inc(I);
    end;
  end;

  SetLength(Result, I - 1);
end;

class function TUtils.UnicodeClear(const S: string): string;
begin
  Result := UnicodeClear(S, [
    TUnicodeCategory.ucControl,
    TUnicodeCategory.ucFormat,
    TUnicodeCategory.ucUnassigned
  ]);
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

{ TEncodingHelper }

function TEncodingHelper.GetString(const ABytes: PByte; AByteCount: Integer): string;
var
  LSize: Integer;
begin
  if (ABytes = nil) then
    raise EEncodingError.CreateRes(@SInvalidSourceArray);
  if (AByteCount < 0) then
    raise EEncodingError.CreateResFmt(@SInvalidCharCount, [AByteCount]);

  LSize := GetCharCount(ABytes, AByteCount);
  if (AByteCount > 0) and (LSize = 0) then
    raise EEncodingError.CreateRes(@SNoMappingForUnicodeCharacter);
  SetLength(Result, LSize);
  GetChars(ABytes, AByteCount, PChar(Result), LSize);
end;

end.
