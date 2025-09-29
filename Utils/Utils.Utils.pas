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

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Types,
  Math,
  {$IFDEF DELPHI}
  System.Diagnostics,
  {$ELSE FPC}
  DTF.Types,
  DTF.Consts,
  DTF.Character,
  DTF.Diagnostics,
  DTF.Generics,
  {$ENDIF}
  System.TimeSpan,
  Character,
  SysConst,
  Generics.Defaults,
  Generics.Collections,

  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}

  Utils.AnonymousThread;

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
    FAppFile, FAppPath, FAppHome, FAppName: string;
    FSysPath: string;
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
    class function IsSpaceStr(const S: string): Boolean; static;
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
    class procedure BinToHex(ABinBuf: Pointer; ABufSize: Integer; AText: PChar); overload; static;
    class function BinToHex(ABinBuf: Pointer; ABufSize: Integer): string; overload; static; //inline;
    class function BytesToHex(const ABytes: TBytes; AOffset, ACount: Integer): string; overload; static; //inline;
    class function BytesToHex(const ABytes: TBytes): string; overload; static; //inline;

    class function HexCharToByte(const AHexChar: Char; out AByte: Byte): Boolean; static;
    class function HexToBin(AText: PChar; ABinBuf: Pointer; ABufSize: Integer): Integer; overload; static;
    class function HexToBin(const AText: string; ABinBuf: Pointer; ABufSize: Integer): Integer; overload; static; inline;
    class function HexToBytes(AText: PChar): TBytes; overload; static;
    class function HexToBytes(const AText: string): TBytes; overload; static; inline;

    class function GetFullFileName(const AFileName: string): string; static;
    class function GetFileSize(const AFileName: string): Int64; static;

    class function CopyFile(const ASrcFileName, ADstFileName: string): Boolean; static;
    class function MoveFile(const ASrcFileName, ADstFileName: string): Boolean; static;
    class function MoveDir(const ASrcDirName, ADstDirName: string): Boolean; static;

    class function StrToPChar(const S: string): PChar; static;
    class function PCharToStr(const S: PChar): string; static;

    // 判断两段日期是否有交集
    class function IsCrossDate(const AStartDate1, AEndDate1, AStartDate2, AEndDate2: TDateTime): Boolean; static;

    // 判断缓存中是不是UTF8编码的字符串
    class function IsUTF8(const ABuf: Pointer; const ABufSize: Integer): Boolean;

    // 获取缓存中的字符串编码
    class function GetBufEncoding(const ABuf: Pointer; const ABufSize: Integer;
      var AEncoding: TEncoding; const ADefaultEncoding: TEncoding): Integer; static;

    // 自动检测缓存中的字符串编码并解码出字符串
    class function GetString(const AStrBuf: PByte; ABufSize: Integer;
      const AEncoding: TEncoding = nil): string; overload; static;
    class function GetString(const AStrBytes: TBytes; AIndex, ACount: Integer;
      const AEncoding: TEncoding = nil): string; overload; static;
    class function GetString(const AStrBytes: TBytes;
      const AEncoding: TEncoding = nil): string; overload; static;
    class function GetString(const AStrStream: TStream;
      const AEncoding: TEncoding = nil): string; overload; static;

    class function ArrayOfToTArray<T>(const AValues: array of T): TArray<T>; static;
    class function IIF<T>(const ATrueFalse: Boolean; const ATrueValue, AFalseValue: T): T; static;

    class function IndexOfArray<T>(const AArray: array of T; const AItem: T;
      const AComparison: {$IFDEF DELPHI}TComparison<T>{$ELSE}TComparisonAnonymousFunc<T>{$ENDIF} = nil;
      const AIndex: Integer = 0; const ACount: Integer = 0): Integer; static;
    class function ExistsInArray<T>(const AArray: array of T; const AItem: T): Boolean; static;

    // 获取调用堆栈信息
    class function GetStackTrace: string; static;

    class property AppFile: string read FAppFile;
    class property AppPath: string read FAppPath;
    class property AppHome: string read FAppHome;
    class property AppName: string read FAppName;

    class property SysPath: string read FSysPath;
  end;

  TEncodingHelper = class helper for TEncoding
    /// <summary>
    ///   从内存块中直接解码出字符串, 省去先将内存块转换为TBytes, 从而提高效率
    /// </summary>
    function GetString(const ABytes: PByte; AByteCount: Integer): string; overload;
  end;

implementation

uses
  Utils.IOUtils;

{ TUtils }

class constructor TUtils.Create;
begin
  FAppFile := ParamStr(0);
  FAppName := ChangeFileExt(ExtractFileName(FAppFile), '');
  FAppPath := IncludeTrailingPathDelimiter(ExtractFilePath(FAppFile));
  FAppHome := IncludeTrailingPathDelimiter(TPathUtils.Combine(TPathUtils.GetHomePath, FAppName));

  {$IFDEF MSWINDOWS}
  SetLength(FSysPath, MAX_PATH);
  Windows.GetSystemDirectoryW(PChar(FSysPath), MAX_PATH);
  SetLength(FSysPath, StrLen(PChar(FSysPath)));
  {$ELSE}
  FSysPath := '/';
  {$ENDIF}
end;

class function TUtils.DateTimeToStr(const D: TDateTime;
  const Fmt: string): string;
begin
  Result := FormatDateTime(Fmt, D);
end;

class function TUtils.DateTimeToStr(const D: TDateTime): string;
begin
  Result := DateTimeToStr(D, 'yyyy-mm-dd hh:nn:ss');
end;

class procedure TUtils.DelayCall(ATick: Cardinal; AProc: TProc);
begin
  TAnonymousThread.Create(
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
  Result := (IndexOfArray<T>(AArray, AItem, nil, 0, 0) >= 0);
end;

class function TUtils.GetBufEncoding(const ABuf: Pointer; const ABufSize: Integer;
  var AEncoding: TEncoding; const ADefaultEncoding: TEncoding): Integer;

  function ContainsPreamble(const APreamble: TBytes; out APreambleSize: Integer): Boolean;
  begin
    APreambleSize := 0;
    if (Length(APreamble) <= 0)
      or (ABufSize < Length(APreamble)) then Exit(False);

    Result := CompareMem(ABuf, @APreamble[0], Length(APreamble));

    if Result then
      APreambleSize := Length(APreamble);
  end;

begin
  Result := 0;

  if (AEncoding = nil) then
  begin
    if ContainsPreamble(TEncoding.UTF8.GetPreamble, Result) then
      AEncoding := TEncoding.UTF8
    else if ContainsPreamble(TEncoding.Unicode.GetPreamble, Result) then
      AEncoding := TEncoding.Unicode
    else if ContainsPreamble(TEncoding.BigEndianUnicode.GetPreamble, Result) then
      AEncoding := TEncoding.BigEndianUnicode
    else if IsUTF8(ABuf, ABufSize) then
      AEncoding := TEncoding.UTF8
    else
    begin
      if (ADefaultEncoding <> nil) then
        AEncoding := ADefaultEncoding
      else
        AEncoding := TEncoding.Default;
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
  LFileStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Result := LFileStream.Size;
  finally
    FreeAndNil(LFileStream);
  end;
end;

class function TUtils.GetFullFileName(const AFileName: string): string;
begin
  Result := TPathUtils.GetFullPath(AFileName);
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
  LBomLen := TUtils.GetBufEncoding(AStrBuf, ABufSize, LEncoding, TEncoding.Default);

  Result := LEncoding.GetString(AStrBuf + LBomLen, ABufSize - LBomLen);
end;

class function TUtils.GetString(const AStrBytes: TBytes; AIndex,
  ACount: Integer; const AEncoding: TEncoding): string;
begin
  if (AStrBytes = nil) or (ACount <= 0) then
    Result := ''
  else
    Result := GetString(PByte(AStrBytes) + AIndex, ACount, AEncoding);
end;

class function TUtils.GetString(const AStrBytes: TBytes;
  const AEncoding: TEncoding): string;
begin
  Result := GetString(AStrBytes, 0, Length(AStrBytes), AEncoding);
end;

class function TUtils.GetStackTrace: string;
{$IFDEF DELPHI}
// 需要启用 madExcept 或其他能提供调用堆栈的库
var
  E: Exception;
begin
  E := Exception(ExceptObject);
  if (E <> nil) then
    Result := E.StackTrace
  else
    Result := '';
end;
{$ELSE}
// FPC
// 需要开启调试信息相关编译开关
// -g  生成调试信息
// -gl 生成代码行信息
var
	LStack: PExceptObject;
  LStackTrace: string;
  I: Integer;
begin
  Result := '';
  LStack :=	RaiseList;
  if (LStack = nil) then Exit;

  LStackTrace := BackTraceStrFunc(LStack.Addr);

  for I :=0 to LStack.FrameCount - 1 do
    LStackTrace := LStackTrace + sLineBreak + BackTraceStrFunc(LStack.Frames[I]);

  Result := LStackTrace;
end;
{$ENDIF}

class function TUtils.GetString(const AStrStream: TStream;
  const AEncoding: TEncoding): string;
var
  LBuf: TBytes;
  LBufSize: Integer;
  P: PByte;
begin
  if (AStrStream = nil) or (AStrStream.Size <= 0) then Exit('');

  if (AStrStream is TCustomMemoryStream) then
  begin
    P := (AStrStream as TCustomMemoryStream).Memory;
    LBufSize := AStrStream.Size;
  end else
  begin
    AStrStream.Position := 0;
    LBufSize := AStrStream.Size;
    SetLength(LBuf, LBufSize);
    AStrStream.ReadBuffer(LBuf, LBufSize);
    P := Pointer(LBuf);
  end;

  Result := GetString(P, LBufSize, AEncoding);
end;

class function TUtils.HexToBin(AText: PChar; ABinBuf: Pointer;
  ABufSize: Integer): Integer;
{$IFDEF DELPHI}
begin
  Result := Classes.HexToBin(AText, ABinBuf, ABufSize);
end;
{$ELSE FPC}
var
  I: Integer;
  H, L: Byte;
  LHexValue: PChar;
  LBinValue: PByte;
begin
  I := ABufSize;
  LHexValue := AText;
  LBinValue := ABinBuf;

  while (I > 0) do
  begin
    if not HexCharToByte(LHexValue^, H) then Break;
    Inc(LHexValue);
    if not HexCharToByte(LHexValue^, L) then Break;
    Inc(LHexValue);

    LBinValue^ := Byte(L + (H shl 4));
    Inc(LBinValue);

    Dec(I);
  end;

  Result := ABufSize - I;
end;
{$ENDIF}

class function TUtils.HexCharToByte(const AHexChar: Char; out AByte: Byte): Boolean;
begin
  case Ord(AHexChar) of
    Ord('0')..Ord('9'):
      begin
        AByte := (Ord(AHexChar)) and 15;
        Result := True;
      end;

    Ord('A')..Ord('F'), Ord('a')..Ord('f'):
      begin
        AByte := (Ord(AHexChar) + 9) and 15;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

class function TUtils.HexToBin(const AText: string; ABinBuf: Pointer;
  ABufSize: Integer): Integer;
begin
  Result := HexToBin(PChar(AText), ABinBuf, ABufSize);
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
  const AComparison: {$IFDEF DELPHI}TComparison<T>{$ELSE}TComparisonAnonymousFunc<T>{$ENDIF};
  const AIndex, ACount: Integer): Integer;
var
  LComparer: IComparer<T>;
  LIndex, LCount, I: Integer;
begin
  if (Length(AArray) = 0) then Exit(-1);

  {$IFDEF DELPHI}
  if Assigned(AComparison) then
    LComparer := TComparer<T>.Construct(AComparison)
  else
    LComparer := TComparer<T>.Default;
	{$ELSE}
  if Assigned(AComparison) then
    LComparer := TDelegatedComparerAnonymousFunc<T>.Create(AComparison)
  else
    LComparer := TDelegatedComparerAnonymousFunc<T>.Default;
  {$ENDIF}

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

class function TUtils.IsSpaceStr(const S: string): Boolean;
var
  LChar: Char;
begin
  for LChar in S do
    if not IsSpaceChar(LChar) then
      Exit(False);

  Result := True;
end;

class function TUtils.IsUTF8(const ABuf: Pointer; const ABufSize: Integer): Boolean;

  function _IsUTF8(const P, PEnd: PByte; out AUTF8Size: ShortInt): Boolean;
  var
    I: ShortInt;
  begin
    Result := False;

    // UTF8最多6个字节
    // 第一个字节高位有多少个1就表示这个字符要占用几个字节

    if (P^ and $FE) = $FC then      // 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
      AUTF8Size := 6
    else if (P^ and $FC) = $F8 then // 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
      AUTF8Size := 5
    else if (P^ and $F8) = $F0 then // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      AUTF8Size := 4
    else if (P^ and $F0) = $E0 then // 1110xxxx 10xxxxxx 10xxxxxx
      AUTF8Size := 3
    else if (P^ and $E0) = $C0 then // 110xxxxx 10xxxxxx
      AUTF8Size := 2
    else
      Exit;

    if (P + AUTF8Size > PEnd) then Exit;

    for I := 1 to AUTF8Size - 1 do
      if (P[I] and $C0 <> $80) then Exit;

    Result := True;
  end;

var
  P, PEnd: PByte;
  LUTF8Size: ShortInt;
begin
  P := ABuf;
  PEnd := P + ABufSize;

  while (P < PEnd) do
  begin
    // $00 - $7F
    if P^ and $80 = 0 then
      Inc(P)
    else if _IsUTF8(P, PEnd, LUTF8Size) then
      Inc(P, LUTF8Size)
    else
      Exit(False);
  end;

  Result := True;
end;

class function TUtils.MoveDir(const ASrcDirName, ADstDirName: string): Boolean;
begin
  Result := TDirectoryUtils.Move(ASrcDirName, ADstDirName);
end;

class function TUtils.MoveFile(const ASrcFileName,
  ADstFileName: string): Boolean;
begin
  Result := TFileUtils.Move(ASrcFileName, ADstFileName);
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

class function TUtils.CopyFile(const ASrcFileName,
  ADstFileName: string): Boolean;
begin
  Result := TFileUtils.Copy(ASrcFileName, ADstFileName);
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
  LFormatSettings: TFormatSettings;
  DateFmt, TimeFmt: string;
  p: Integer;
begin
  p := Fmt.IndexOf(' ');
  DateFmt := Fmt.Substring(0, p);
  TimeFmt := Fmt.Substring(p + 1);

  LFormatSettings := FormatSettings;
  LFormatSettings.DateSeparator := GetSeparator(DateFmt);
  LFormatSettings.TimeSeparator := GetSeparator(TimeFmt);
  LFormatSettings.ShortDateFormat := DateFmt;
  LFormatSettings.LongDateFormat := DateFmt;
  LFormatSettings.ShortTimeFormat := TimeFmt;
  LFormatSettings.LongTimeFormat := TimeFmt;
  Result := SysUtils.StrToDateTime(S, LFormatSettings);
end;

class procedure TUtils.BinToHex(ABinBuf: Pointer; ABufSize: Integer;
  AText: PChar);
const
  XD: array[0..15] of Char = (
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
var
  I: Integer;
  PBuffer: PByte;
  PText: PChar;
begin
  PBuffer := ABinBuf;
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

class function TUtils.BinToHex(ABinBuf: Pointer; ABufSize: Integer): string;
begin
  if (ABinBuf = nil) or (ABufSize <= 0) then Exit('');

  SetLength(Result, ABufSize * 2);
  BinToHex(ABinBuf, ABufSize, PChar(Result));
end;

class function TUtils.BytesToHex(const ABytes: TBytes; AOffset,
  ACount: Integer): string;
begin
  if (ABytes = nil) or (AOffset < 0)
    or (AOffset + ACount > Length(ABytes)) then Exit('');

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
var
  LFormatSettings: TFormatSettings;
begin
  LFormatSettings := FormatSettings;
  Result := Format(Fmt, Args, LFormatSettings);
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
