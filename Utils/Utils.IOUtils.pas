unit Utils.IOUtils;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  RtlConsts,
  Masks,
  {$IFDEF MSWINDOWS}
  Windows,
  {$ELSE}
    {$IFDEF DELPHI}
    Posix.SysTypes,
    Posix.Errno,
    Posix.Unistd,
    Posix.Base,
    Posix.Stdio,
    Posix.Stdlib,
    Posix.SysStat,
    Posix.Time,
    Posix.Utime,
    {$ELSE}
    baseunix,
    unix,
    {$ENDIF}
  {$ENDIF}

  {$IFDEF FPC}
  DTF.RTL,
  {$ENDIF}

  Utils.DateTime,
  Utils.StrUtils,
  Utils.Utils;

type
  /// <summary>
  ///    Adapted from delphi rtl source code (TBufferedFileStream)
  ///    TFastFileStream adds buffering to the TFileStream. This optimizes
  ///    multiple consecutive small writes or reads. TFastFileStream will
  ///    not give performance gain, when there are random position reads or
  ///    writes, or large reads or writes. TFastFileStream may be used
  ///    as a drop in replacement for TFileStream.
  /// </summary>
  TFastFileStream = class(TFileStream)
  private
    FFilePos, FBufStartPos, FBufEndPos: Int64;
    FBuffer: PByte;
    FBufferSize: Integer;
    FModified: Boolean;
    FBuffered: Boolean;
  protected
    procedure SetSize(const ANewSize: Int64); override;
    /// <summary>
    ///    SyncBuffer writes buffered and not yet written data to the file.
    ///    When ReRead is True, then buffer will be repopulated from the file.
    ///    When ReRead is False, then buffer will be emptied, so next read or
    ///    write operation will repopulate buffer.
    /// </summary>
    procedure SyncBuffer(AReRead: Boolean);
  public
    constructor Create(const AFileName: string; AMode: Word; ABufferSize: Integer = 32768); overload;
    constructor Create(const AFileName: string; AMode: Word; ARights: Cardinal; ABufferSize: Integer = 32768); overload;
    destructor Destroy; override;
    /// <summary>
    ///    FlushBuffer writes buffered and not yet written data to the file.
    /// </summary>
    procedure FlushBuffer; inline;
    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Write(const ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
  end;

  TFileUtils = class
  private
    {$IFDEF MSWINDOWS}
    class function ConvertDateTimeToFileTime(const ADateTime: TDateTime): TFileTime; static;
    {$ELSE}
    class function ConvertDateTimeToFileTime(const ADateTime: TDateTime): time_t; static;
    {$ENDIF}
  public
    class function OpenCreate(const AFileName: string): TFileStream; static;
    class function OpenRead(const AFileName: string): TFileStream; static;
    class function OpenWrite(const AFileName: string): TFileStream; static;
    class function CreateTempFile(const ATempPath: string = ''): TFileStream; static;

    class function ReadAllBytes(const AFileName: string): TBytes; static;
    class function ReadAllText(const AFileName: string; const AEncoding: TEncoding = nil): string; static;

    class procedure WriteAllBytes(const AFileName: string; const ABytes: TBytes); static;
    class procedure WriteAllText(const AFileName, AContents: string;
      const AEncoding: TEncoding = nil; const AWriteBOM: Boolean = True); static;

    class procedure WriteAllStream(const AFileName: string; const AStream: TStream); static;

    class procedure AppendAllText(const AFileName, AContents: string;
      const AEncoding: TEncoding = nil); static;

    class function GetSize(const AFileName: string): Int64; static;

    class function GetDateTimeInfo(const APath: string; out ACreationTime,
        ALastAccessTime, ALastWriteTime: TDateTime): Boolean; static;
    class function GetCreationTime(const APath: string): TDateTime; static;
    class function GetLastAccessTime(const APath: string): TDateTime; static;
    class function GetLastWriteTime(const APath: string): TDateTime; static;

    class function SetDateTimeInfo(const APath: string; const ACreationTime,
        ALastAccessTime, ALastWriteTime: PDateTime): Boolean; static;
    class function SetCreationTime(const APath: string;
        const ACreationTime: TDateTime): Boolean; inline; static;
    class function SetLastAccessTime(const APath: string;
        const ALastAccessTime: TDateTime): Boolean; inline; static;
    class function SetLastWriteTime(const APath: string;
        const ALastWriteTime: TDateTime): Boolean; inline; static;

    class function Exists(const AFileName: string): Boolean; static; inline;
    class function Delete(const AFileName: string): Boolean; static;
    class function Copy(const ASrcFileName, ADstFileName: string): Boolean; static;
    class function Move(const ASrcFileName, ADstFileName: string): Boolean; static;
  end;

  TSearchOption = (soTopDirectoryOnly, soAllDirectories);

  TSearchRec = SysUtils.{$IFDEF DELPHI}TSearchRec{$ELSE}TUnicodeSearchRec{$ENDIF};

  TFilterPredicate = reference to function(const APath: string;
      const ASearchRec: TSearchRec): Boolean;

  TDirectoryWalkProc = reference to function (const APath: string;
      const AFileInfo: TSearchRec): Boolean;

  TDirectoryUtils = class
  public
    class procedure WalkThroughDirectory(const APath, APattern: string;
        const APreCallback, APostCallback: TDirectoryWalkProc;
        const ARecursive: Boolean); static;

    class function CreateDirectory(const ADir: string): Boolean; static;
    class function Exists(const APath: string): Boolean; inline; static;

    class function Delete(const APath: string; const ARecursive: Boolean = False): Boolean; static;
    class function Move(const ASourceDirName, ADestDirName: string; const AOverwrite: Boolean = True): Boolean; static;

    class function GetLogicalDrives: TArray<string>; static;

    class function GetFiles(const APath, ASearchPattern: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetFiles(const APath, ASearchPattern: string;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetFiles(const APath: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetFiles(const APath: string;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;

    class function GetDirectories(const APath, ASearchPattern: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetDirectories(const APath, ASearchPattern: string;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetDirectories(const APath: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetDirectories(const APath: string;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;

    class function GetFileSystemEntries(const APath, ASearchPattern: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetFileSystemEntries(const APath, ASearchPattern: string;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetFileSystemEntries(const APath: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
    class function GetFileSystemEntries(const APath: string;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
  end;

  TPathUtils = class
  public const
    CURRENT_DIR: string = '.';
    PARENT_DIR: string = '..';
    EXTENDED_PREFIX: string = '\\?\';
    EXTENDED_UNC_PREFIX: string = '\\?\UNC\';
    DIRECTORY_SEPARATOR_CHAR: Char = {$IFDEF MSWINDOWS}'\'{$ELSE}'/'{$ENDIF};
    EXTENSION_SEPARATOR_CHAR: Char = '.';
  public
    class function ChangeExtension(const APath, AExtension: string): string; static;

    class function Combine(const APath1, APath2, APathDelim: string): string; overload; static;
    class function Combine(const APath1, APath2: string): string; overload; static; inline;

    class function Combine(const APaths: array of string; const APathDelim: string): string; overload; static;
    class function Combine(const APaths: array of string): string; overload; static;

    class function GetExtensionSeparatorPos(const AFileName: string): Integer; static;

    class function GetExtension(const AFileName: string): string; static;
    class function GetFileName(const AFileName: string): string; static;
    class function GetFileNameWithoutExtension(const AFileName: string): string; static;

    class function GetFullPath(const APath: string): string; static;
    class function GetDirectoryName(const AFileName: string): string; static;

    class function GetHomePath: string; static;

    class function MatchesPattern(const AFileName, APattern: string): Boolean; static;
  end;

  TTempFileStream = class(TFastFileStream)
  private
    FTempFileName: string;
  public
    constructor Create(const ATempPath: string = ''); reintroduce;
    destructor Destroy; override;
  end;

  TFileStreamHelper = class helper for TFileStream
  public
    class function OpenCreate(const AFileName: string): TFileStream; static; inline;
    class function OpenRead(const AFileName: string): TFileStream; static; inline;
    class function OpenWrite(const AFileName: string): TFileStream; static; inline;
  end;

implementation

{$IF DEFINED(MSWINDOWS) AND DEFINED(FPC)}
function GetLogicalDriveStrings(nBufferLength: DWORD; lpBuffer: LPWSTR): DWORD; stdcall;
  external 'kernel32' name 'GetLogicalDriveStringsW';
{$ENDIF}

{ TFastFileStream }

constructor TFastFileStream.Create(const AFileName: string; AMode: Word;
  ABufferSize: Integer);
begin
{$IF Defined(MSWINDOWS)}
  Create(AFilename, AMode, 0, ABufferSize);
{$ELSEIF Defined(POSIX)}
  Create(AFilename, AMode,
    S_IRUSR or S_IWUSR or S_IRGRP or S_IWGRP or S_IROTH or S_IWOTH,
    ABufferSize);
{$ENDIF POSIX}
end;

constructor TFastFileStream.Create(const AFileName: string; AMode: Word;
  ARights: Cardinal; ABufferSize: Integer);
begin
  inherited Create(AFileName, AMode, ARights);
  FBufferSize := ABufferSize;
  GetMem(FBuffer, FBufferSize);
  FBuffered := True;
  SyncBuffer(True);
end;

destructor TFastFileStream.Destroy;
begin
  SyncBuffer(False);
  FreeMem(FBuffer, FBufferSize);
  inherited Destroy;
end;

procedure TFastFileStream.SyncBuffer(AReRead: boolean);
var
  LLen: Longint;
begin
  if FModified then
  begin
    if inherited Seek(FBufStartPos, soBeginning) <> FBufStartPos then
      raise EWriteError.Create(SWriteError);
    LLen := Longint(FBufEndPos - FBufStartPos);
    if inherited Write(FBuffer^, LLen) <> LLen then
      raise EWriteError.Create(SWriteError);
    FModified := False;
  end;
  if AReRead then
  begin
    FBufStartPos := inherited Seek(FFilePos, soBeginning);
    FBufEndPos := FBufStartPos + inherited Read(FBuffer^, FBufferSize);
  end
  else
  begin
    inherited Seek(FFilePos, soBeginning);
    FBufEndPos := FBufStartPos;
  end;
end;

procedure TFastFileStream.FlushBuffer;
begin
  SyncBuffer(False);
end;

function TFastFileStream.Read(var ABuffer; ACount: Longint): Longint;
var
  PSrc: PByte;
begin
  if ACount >= FBufferSize then
  begin
    SyncBuffer(False);
    Result := inherited Read(ABuffer, ACount)
  end
  else
  begin
    if (FBufStartPos > FFilePos) or (FFilePos + ACount > FBufEndPos) then
      SyncBuffer(True);
    if ACount < FBufEndPos - FFilePos then
      Result := ACount
    else
      Result := FBufEndPos - FFilePos;
    PSrc := FBuffer + (FFilePos - FBufStartPos);
{$IF DEFINED(CPUARM32)}
    Move(PSrc^, ABuffer, Result);
{$ELSE}
    case Result of
      SizeOf(Byte):
        PByte(@ABuffer)^ := PByte(PSrc)^;
      SizeOf(Word):
        PWord(@ABuffer)^ := PWord(PSrc)^;
      SizeOf(Cardinal):
        PCardinal(@ABuffer)^ := PCardinal(PSrc)^;
      SizeOf(UInt64):
        PUInt64(@ABuffer)^ := PUInt64(PSrc)^;
    else
      Move(PSrc^, ABuffer, Result);
    end;
{$ENDIF}
  end;
  FFilePos := FFilePos + Result;
end;

function TFastFileStream.Write(const ABuffer; ACount: Longint): Longint;
var
  PDest: PByte;
begin
  if ACount >= FBufferSize then
  begin
    SyncBuffer(False);
    Result := inherited Write(ABuffer, ACount);
    FFilePos := FFilePos + Result;
  end
  else
  begin
    if (FBufStartPos > FFilePos) or (FFilePos + ACount > FBufStartPos + FBufferSize) then
      SyncBuffer(True);
    Result := ACount;
    PDest := FBuffer + (FFilePos - FBufStartPos);
{$IF DEFINED(CPUARM32)}
    Move(ABuffer, PDest^, Result);
{$ELSE}
    case Result of
      SizeOf(Byte):
        PByte(PDest)^ := PByte(@ABuffer)^;
      SizeOf(Word):
        PWord(PDest)^ := PWord(@ABuffer)^;
      SizeOf(Cardinal):
        PCardinal(PDest)^ := PCardinal(@ABuffer)^;
      SizeOf(UInt64):
        PUInt64(PDest)^ := PUInt64(@ABuffer)^;
    else
      Move(ABuffer, PDest^, Result);
    end;
{$ENDIF}
    FModified := True;
    FFilePos := FFilePos + Result;
    if FFilePos > FBufEndPos then
      FBufEndPos := FFilePos;
  end;
end;

function TFastFileStream.Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64;
begin
  if not FBuffered then
    FFilePos := inherited Seek(AOffset, AOrigin)
  else
    case AOrigin of
      soBeginning:
        begin
          if (AOffset < FBufStartPos) or (AOffset > FBufEndPos) then
            SyncBuffer(False);
          FFilePos := AOffset;
        end;
      soCurrent:
        begin
          if (FFilePos + AOffset < FBufStartPos) or (FFilePos + AOffset > FBufEndPos) then
            SyncBuffer(False);
          FFilePos := FFilePos + AOffset;
        end;
      soEnd:
        begin
          SyncBuffer(False);
          FFilePos := inherited Seek(AOffset, soEnd);
        end;
    end;
  Result := FFilePos;
end;

procedure TFastFileStream.SetSize(const ANewSize: Int64);
begin
  if ANewSize < FBufEndPos then
    SyncBuffer(False);
  FBuffered := False;
  try
    inherited SetSize(ANewSize);
  finally
    FBuffered := True;
  end;
end;

{ TFileUtils }

{$IFDEF MSWINDOWS}
class function TFileUtils.ConvertDateTimeToFileTime(const ADateTime: TDateTime): TFileTime;
var
  LSysTime: TSystemTime;
begin
  DateTimeToSystemTime(ADateTime, LSysTime);
  SystemTimeToFileTime(LSysTime, Result);
end;
{$ELSE}
class function TFileUtils.ConvertDateTimeToFileTime(const ADateTime: TDateTime): time_t;
begin
  Result := DateTimeToFileDate(ADateTime);
end;
{$ENDIF}

class function TFileUtils.Copy(const ASrcFileName,
  ADstFileName: string): Boolean;
var
  LSrcStream, LDstStream: TStream;
begin
  if not Exists(ASrcFileName) then Exit(False);

  LSrcStream := OpenRead(ASrcFileName);
  try
    LDstStream := OpenCreate(ADstFileName);
    try
      LDstStream.CopyFrom(LSrcStream, 0);
    finally
      LDstStream.Free;
    end;
  finally
    LSrcStream.Free;
  end;

  Result := True;
end;

class function TFileUtils.CreateTempFile(const ATempPath: string): TFileStream;
begin
  Result := TTempFileStream.Create(ATempPath);
end;

class function TFileUtils.Delete(const AFileName: string): Boolean;
begin
  Result := SysUtils.DeleteFile(AFileName);
end;

class function TFileUtils.Exists(const AFileName: string): Boolean;
begin
  Result := SysUtils.FileExists(AFileName);
end;

class function TFileUtils.GetCreationTime(const APath: string): TDateTime;
var
  LTemp1, LTemp2: TDateTime;
begin
  GetDateTimeInfo(APath, Result, LTemp1, LTemp2);
end;

class function TFileUtils.GetDateTimeInfo(const APath: string;
  out ACreationTime, ALastAccessTime, ALastWriteTime: TDateTime): Boolean;
var
  LDateTime: TDateTimeInfoRec;
begin
  Result := FileGetDateTimeInfo(APath, LDateTime);
  if not Result then
  begin
    ACreationTime := 0;
    ALastAccessTime := 0;
    ALastWriteTime := 0;
    Exit;
  end;

  ACreationTime := LDateTime.CreationTime;
  ALastAccessTime := LDateTime.LastAccessTime;
  ALastWriteTime := LDateTime.TimeStamp;
end;

class function TFileUtils.GetLastAccessTime(const APath: string): TDateTime;
var
  LTemp1, LTemp2: TDateTime;
begin
  GetDateTimeInfo(APath, LTemp1, Result, LTemp2);
end;

class function TFileUtils.GetLastWriteTime(const APath: string): TDateTime;
var
  LTemp1, LTemp2: TDateTime;
begin
  GetDateTimeInfo(APath, LTemp1, LTemp2, Result);
end;

class function TFileUtils.GetSize(const AFileName: string): Int64;
var
  LTempStream: TStream;
begin
  LTempStream := OpenRead(AFileName);
  try
    Result := LTempStream.Size;
  finally
    FreeAndNil(LTempStream);
  end;
end;

class function TFileUtils.Move(const ASrcFileName,
  ADstFileName: string): Boolean;
var
  LDstDirName: string;
begin
  if not Exists(ASrcFileName) then Exit(False);

  LDstDirName := TPathUtils.GetDirectoryName(ADstFileName);
  if (LDstDirName <> '') then
    TDirectoryUtils.CreateDirectory(LDstDirName);

  if Exists(ADstFileName) then
    Delete(ADstFileName);

  Result := RenameFile(ASrcFileName, ADstFileName);
end;

class function TFileUtils.OpenCreate(const AFileName: string): TFileStream;
begin
  if not FileExists(AFileName) then
    TDirectoryUtils.CreateDirectory(ExtractFilePath(AFileName));
  Result := TFastFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
end;

class function TFileUtils.OpenRead(const AFileName: string): TFileStream;
begin
  Result := TFastFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
end;

class function TFileUtils.OpenWrite(const AFileName: string): TFileStream;
begin
  if FileExists(AFileName) then
    Result := TFastFileStream.Create(AFileName, fmOpenReadWrite or fmShareDenyWrite)
  else
  begin
    TDirectoryUtils.CreateDirectory(ExtractFilePath(AFileName));
    Result := TFastFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  end;
end;

class function TFileUtils.ReadAllBytes(const AFileName: string): TBytes;
var
  LFileStream: TFileStream;
  LFileSize: Int64;
begin
  if not Exists(AFileName) then Exit(nil);

  LFileStream := nil;
  try
    LFileStream := OpenRead(AFileName);
    LFileSize := LFileStream.Size;
    SetLength(Result, LFileSize);
    LFileStream.ReadBuffer(Result, Length(Result));
  finally
    FreeAndNil(LFileStream);
  end;
end;

class function TFileUtils.ReadAllText(const AFileName: string;
  const AEncoding: TEncoding): string;
var
  LBytes: TBytes;
begin
  LBytes := ReadAllBytes(AFileName);

  Result := TUtils.GetString(LBytes, AEncoding);
end;

class function TFileUtils.SetCreationTime(const APath: string;
  const ACreationTime: TDateTime): Boolean;
begin
  Result := SetDateTimeInfo(APath, @ACreationTime, nil, nil);
end;

class function TFileUtils.SetLastAccessTime(const APath: string;
  const ALastAccessTime: TDateTime): Boolean;
begin
  Result := SetDateTimeInfo(APath, nil, @ALastAccessTime, nil);
end;

class function TFileUtils.SetLastWriteTime(const APath: string;
  const ALastWriteTime: TDateTime): Boolean;
begin
  Result := SetDateTimeInfo(APath, nil, nil, @ALastWriteTime);
end;

class function TFileUtils.SetDateTimeInfo(const APath: string;
  const ACreationTime, ALastAccessTime, ALastWriteTime: PDateTime): Boolean;
{$IFDEF MSWINDOWS}
var
  LFileHnd: THandle;
  LFileAttr: Cardinal;
  LFileCreationTime: PFileTime;
  LFileLastAccessTime: PFileTime;
  LFileLastWriteTime: PFileTime;
begin
  Result := False;

  // establish what date-times must be set to the directory
  LFileHnd := 0;
  LFileCreationTime := nil;
  LFileLastAccessTime := nil;
  LFileLastWriteTime := nil;

  try
    try
      if Assigned(ACreationTime) then
      begin
        New(LFileCreationTime);
        LFileCreationTime^ := ConvertDateTimeToFileTime(ACreationTime^);
      end;
      if Assigned(ALastAccessTime) then
      begin
        New(LFileLastAccessTime);
        LFileLastAccessTime^ := ConvertDateTimeToFileTime(ALastAccessTime^);
      end;
      if Assigned(ALastWriteTime) then
      begin
        New(LFileLastWriteTime);
        LFileLastWriteTime^ := ConvertDateTimeToFileTime(ALastWriteTime^);
      end;

      // determine if APath points to a directory or a file
      SetLastError(ERROR_SUCCESS);
      {$WARN SYMBOL_PLATFORM OFF}
      LFileAttr := FileGetAttr(APath);
      {$WARN SYMBOL_PLATFORM ON}
      if LFileAttr and SysUtils.faDirectory <> 0 then
        LFileAttr := FILE_FLAG_BACKUP_SEMANTICS
      else
        LFileAttr := FILE_ATTRIBUTE_NORMAL;

      // set the new date-times to the directory or file
      LFileHnd := CreateFileW(PChar(APath), GENERIC_WRITE, FILE_SHARE_WRITE, nil,
        OPEN_EXISTING, LFileAttr, 0);

      if LFileHnd <> INVALID_HANDLE_VALUE then
        Result := SetFileTime(LFileHnd, LFileCreationTime, LFileLastAccessTime, LFileLastWriteTime);
    except
      on E: EConvertError do
        raise EArgumentOutOfRangeException.Create(E.Message); {?}
    end;
  finally
    CloseHandle(LFileHnd);
    SetLastError(ERROR_SUCCESS);

    if Assigned(LFileCreationTime) then
      Dispose(LFileCreationTime);
    if Assigned(LFileLastAccessTime) then
      Dispose(LFileLastAccessTime);
    if Assigned(LFileLastWriteTime) then
      Dispose(LFileLastWriteTime);
  end;
end;
{$ENDIF}
{$IFDEF POSIX}
var
  LFileName: Pointer;
  LStatBuf: {$IFDEF DELPHI}_stat{$ELSE}Stat{$ENDIF};
  LBuf: utimbuf;
  ErrCode: Integer;
  M: TMarshaller;
begin
  Result := False;

  { Do nothing if no date/time passed. Ignore ACreationTime. Unixes do not support creation times for files. }
  if (ALastAccessTime = nil) and (ALastWriteTime = nil) then
    Exit;

  LFileName := M.AsAnsi(APath, CP_UTF8).ToPointer;

  { Obtain the file times. lstat may fail }
  if ((ALastAccessTime = nil) or (ALastWriteTime = nil)) then
  begin
    ErrCode := {$IFDEF DELPHI}Stat{$ELSE}fpStat{$ENDIF}(LFileName, LStatBuf);

    { Fail if we can't access the file properly }
    if ErrCode <> 0 then
      Exit; // Fail here prematurely. Do not chnage file times if we failed to fetch the old ones.
  end;

  try
    { Preserve of set the new value }
    if ALastAccessTime <> nil then
      LBuf.actime := ConvertDateTimeToFileTime(ALastAccessTime^)
    else
      LBuf.actime := LStatBuf.st_atime;

    { Preserve of set the new value }
    if ALastWriteTime <> nil then
      LBuf.modtime := ConvertDateTimeToFileTime(ALastWriteTime^)
    else
      LBuf.modtime := LStatBuf.st_mtime;

    { Call utime to set the file times }
    {$IFDEF DELPHI}
    Result := (utime(LFileName, LBuf) = 0);
    {$ELSE}
    Result := (fpUTime(LFileName, @LBuf) = 0);
    {$ENDIF}
  except
    on E: EConvertError do // May rise in ConvertDateTimeToFileTime
      raise EArgumentOutOfRangeException.Create(E.Message); {?}
  end;
end;
{$ENDIF}

class procedure TFileUtils.WriteAllBytes(const AFileName: string;
  const ABytes: TBytes);
var
  LFileStream: TFileStream;
begin
  LFileStream := nil;
  try
    LFileStream := OpenCreate(AFileName);
    LFileStream.WriteBuffer(ABytes, Length(ABytes));
  finally
    FreeAndNil(LFileStream);
  end;
end;

class procedure TFileUtils.WriteAllText(const AFileName, AContents: string;
  const AEncoding: TEncoding; const AWriteBOM: Boolean);
var
  LFileStream: TFileStream;
  LEncoding: TEncoding;
  LBytes: TBytes;
begin
  if (AEncoding <> nil) then
    LEncoding := AEncoding
  else
    LEncoding := TEncoding.UTF8;

  LFileStream := OpenCreate(AFileName);
  try
    if AWriteBOM then
    begin
      LBytes := LEncoding.GetPreamble;
      LFileStream.WriteBuffer(LBytes, Length(LBytes));
    end;
    LBytes := LEncoding.GetBytes(AContents);
    LFileStream.WriteBuffer(LBytes, Length(LBytes));
  finally
    FreeAndNil(LFileStream);
  end;
end;

class procedure TFileUtils.WriteAllStream(const AFileName: string;
  const AStream: TStream);
var
  LFileStream: TFileStream;
begin
  LFileStream := OpenCreate(AFileName);
  try
    LFileStream.CopyFrom(AStream, 0);
  finally
    FreeAndNil(LFileStream);
  end;
end;

class procedure TFileUtils.AppendAllText(const AFileName, AContents: string;
  const AEncoding: TEncoding);
var
  LFileStream: TFileStream;
  LEncoding: TEncoding;
  LBytes: TBytes;
begin
  if (AEncoding <> nil) then
    LEncoding := AEncoding
  else
    LEncoding := TEncoding.UTF8;

  LFileStream := OpenWrite(AFileName);
  try
    LFileStream.Seek(0, soEnd);
    LBytes := LEncoding.GetBytes(AContents);
    LFileStream.WriteBuffer(LBytes, Length(LBytes));
  finally
    FreeAndNil(LFileStream);
  end;
end;

{ TFileStreamHelper }

class function TFileStreamHelper.OpenCreate(
  const AFileName: string): TFileStream;
begin
  Result := TFileUtils.OpenCreate(AFileName);
end;

class function TFileStreamHelper.OpenRead(const AFileName: string): TFileStream;
begin
  Result := TFileUtils.OpenRead(AFileName);
end;

class function TFileStreamHelper.OpenWrite(
  const AFileName: string): TFileStream;
begin
  Result := TFileUtils.OpenWrite(AFileName);
end;

{ TDirectoryUtils }

class function TDirectoryUtils.CreateDirectory(const ADir: string): Boolean;
  function _CreateDir(const Dir: string): Boolean;
  begin
    // 不直接使用 CreateDir 的返回值, 当返回 False, 还应该进一步检查错误码
    // 错误码是 ERROR_ALREADY_EXISTS 则表明目录已经存在了, 这种情况也应该算作创建成功
    // 这样处理可以在多线程并发创建同一个目录时都能返回 True
    Result := SysUtils.CreateDir(Dir)
      or (GetLastError =
        {$IFDEF MSWINDOWS}
        ERROR_ALREADY_EXISTS
        {$ELSEIF defined(DELPHI)}
        EEXIST
        {$ELSE}
        ESysEEXIST
        {$ENDIF}
      );
  end;
var
  LDir: string;
  H: Integer;
begin
  if (ADir = '') then Exit(False);

  Result := True;
  LDir := ADir;

  H := High(LDir);
  // Don't attempt to remove the root path delimiter
  if (H > 1) and IsPathDelimiter(LDir, H)
    {$IFDEF MSWINDOWS}
    and not IsDelimiter(DriveDelim, LDir, H - 1)
    {$ENDIF} then
    SetLength(LDir, Length(LDir) - 1);
  if DirectoryExists(LDir) then Exit;

  {$IFDEF MSWINDOWS}
  if (Length(LDir) < 3) or (ExtractFilePath(LDir) = LDir) then
  begin
    Result := _CreateDir(LDir);
  end else
  {$ENDIF}
  {$IFDEF POSIX}
  LDir := ExpandFileName(LDir);
  if (LDir = '') then
    Exit
  else
  {$ENDIF POSIX}
  begin
    Result := CreateDirectory(ExtractFilePath(LDir)) and _CreateDir(LDir);
  end;
end;

class function TDirectoryUtils.Delete(const APath: string;
  const ARecursive: Boolean): Boolean;
var
  LPostCallback: TDirectoryWalkProc;
begin
  Result := False;
  if not Exists(APath) then Exit;

  if ARecursive then
  begin
    LPostCallback :=
      function (const APath: string; const AFileInfo: TSearchRec): Boolean
      var
        LCompletePath: string;
      begin
        Result := True;

        if (AFileInfo.Name <> TPathUtils.PARENT_DIR) and (AFileInfo.Name <> TPathUtils.CURRENT_DIR) then
        begin
          LCompletePath := TPathUtils.Combine(APath, AFileInfo.Name);

          // clear read-only, system and hidden attributes that can compromise
          // the deletion
          {$IFDEF MSWINDOWS}
          {$WARN SYMBOL_PLATFORM OFF}
          FileSetAttr(LCompletePath, faNormal);
          {$WARN SYMBOL_PLATFORM ON}
          {$ENDIF MSWINDOWS}

          case AFileInfo.Attr and faDirectory of
            faDirectory: // remove empty directories
              RemoveDir(LCompletePath);
            0: // remove files
              SysUtils.DeleteFile(LCompletePath);
          end;
        end;
      end;

    // 删除目录中的文件和子目录
    WalkThroughDirectory(APath, '*', nil, LPostCallback, ARecursive);
  end;

  {$IFDEF MSWINDOWS}
  {$WARN SYMBOL_PLATFORM OFF}
  FileSetAttr(APath, faNormal);
  {$WARN SYMBOL_PLATFORM ON}
  {$ENDIF}

  Result := RemoveDir(APath);
end;

class function TDirectoryUtils.Exists(const APath: string): Boolean;
begin
  Result := DirectoryExists(APath);
end;

class function TDirectoryUtils.GetDirectories(const APath, ASearchPattern: string;
  const ASearchOption: TSearchOption;
  const APredicate: TFilterPredicate): TArray<string>;
var
  LPreCallback: TDirectoryWalkProc;
  LResultArray: TArray<string>;
  I, LCapacity: Integer;
begin
  LResultArray := nil;
  LCapacity := 0;
  I := 0;
  LPreCallback :=
    function (const APath: string; const AFileInfo: TSearchRec): Boolean
    var
      LCanAdd: Boolean;
    begin
      Result := True;

      if (AFileInfo.Attr and faDirectory <> 0) and
         (AFileInfo.Name <> TPathUtils.CURRENT_DIR) and (AFileInfo.Name <> TPathUtils.PARENT_DIR) then
      begin
        LCanAdd := (not Assigned(APredicate)) or
                  (Assigned(APredicate) and APredicate(APath, AFileInfo));

        if LCanAdd then
        begin
          if (I >= LCapacity) then
          begin
            LCapacity := GrowCollection(LCapacity, I + 1);
            SetLength(LResultArray, LCapacity);
          end;
          LResultArray[I] := TPathUtils.Combine(APath, AFileInfo.Name);
          Inc(I);
        end;
      end;
    end;

  WalkThroughDirectory(APath, ASearchPattern, LPreCallback, nil,
    ASearchOption = TSearchOption.soAllDirectories);

  SetLength(LResultArray, I);

  Result := LResultArray;
end;

class function TDirectoryUtils.GetDirectories(const APath,
  ASearchPattern: string; const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetDirectories(APath, ASearchPattern, TSearchOption.soTopDirectoryOnly, APredicate);
end;

class function TDirectoryUtils.GetDirectories(const APath: string;
  const ASearchOption: TSearchOption;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetDirectories(APath, '*', ASearchOption, APredicate);
end;

class function TDirectoryUtils.GetDirectories(const APath: string;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetDirectories(APath, '*', TSearchOption.soTopDirectoryOnly, APredicate);
end;

class function TDirectoryUtils.GetFiles(const APath, ASearchPattern: string;
  const ASearchOption: TSearchOption;
  const APredicate: TFilterPredicate): TArray<string>;
var
  LPreCallback: TDirectoryWalkProc;
  LResultArray: TArray<string>;
  I, LCapacity: Integer;
begin
  LResultArray := nil;
  LCapacity := 0;
  I := 0;
  LPreCallback :=
    function (const APath: string; const AFileInfo: TSearchRec): Boolean
    var
      LCanAdd: Boolean;
    begin
      Result := True;

      if AFileInfo.Attr and faDirectory = 0 then
      begin
        LCanAdd := (not Assigned(APredicate)) or
                  (Assigned(APredicate) and APredicate(APath, AFileInfo));

        if LCanAdd then
        begin
          if (I >= LCapacity) then
          begin
            LCapacity := GrowCollection(LCapacity, I + 1);
            SetLength(LResultArray, LCapacity);
          end;
          LResultArray[I] := TPathUtils.Combine(APath, AFileInfo.Name);
          Inc(I);
        end;
      end;
    end;

  WalkThroughDirectory(APath, ASearchPattern, LPreCallback, nil,
    ASearchOption = TSearchOption.soAllDirectories);

  SetLength(LResultArray, I);

  Result := LResultArray;
end;

class function TDirectoryUtils.GetFiles(const APath, ASearchPattern: string;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetFiles(APath, ASearchPattern, TSearchOption.soTopDirectoryOnly, APredicate);
end;

class function TDirectoryUtils.GetFiles(const APath: string;
  const ASearchOption: TSearchOption;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetFiles(APath, '*', ASearchOption, APredicate);
end;

class function TDirectoryUtils.GetFiles(const APath: string;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetFiles(APath, '*', TSearchOption.soTopDirectoryOnly, APredicate);
end;

class function TDirectoryUtils.GetFileSystemEntries(const APath,
  ASearchPattern: string; const ASearchOption: TSearchOption;
  const APredicate: TFilterPredicate): TArray<string>;
var
  LPreCallback: TDirectoryWalkProc;
  LResultArray: TArray<string>;
  I, LCapacity: Integer;
begin
  LResultArray := nil;
  LCapacity := 0;
  I := 0;
  LPreCallback :=
    function (const APath: string; const AFileInfo: TSearchRec): Boolean
    var
      LCanAdd: Boolean;
    begin
      Result := True;

      if (AFileInfo.Name <> TPathUtils.CURRENT_DIR) and (AFileInfo.Name <> TPathUtils.PARENT_DIR) then
      begin
        LCanAdd := (not Assigned(APredicate)) or
                  (Assigned(APredicate) and APredicate(APath, AFileInfo));

        if LCanAdd then
        begin
          if (I >= LCapacity) then
          begin
            LCapacity := GrowCollection(LCapacity, I + 1);
            SetLength(LResultArray, LCapacity);
          end;
          LResultArray[I] := TPathUtils.Combine(APath, AFileInfo.Name);
          Inc(I);
        end;
      end;
    end;

  WalkThroughDirectory(APath, ASearchPattern, LPreCallback, nil,
    ASearchOption = TSearchOption.soAllDirectories);

  SetLength(LResultArray, I);

  Result := LResultArray;
end;

class function TDirectoryUtils.GetFileSystemEntries(const APath,
  ASearchPattern: string; const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetFileSystemEntries(APath, ASearchPattern, TSearchOption.soTopDirectoryOnly, APredicate);
end;

class function TDirectoryUtils.GetFileSystemEntries(const APath: string;
  const ASearchOption: TSearchOption;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetFileSystemEntries(APath, '*', ASearchOption, APredicate);
end;

class function TDirectoryUtils.GetFileSystemEntries(const APath: string;
  const APredicate: TFilterPredicate): TArray<string>;
begin
  Result := GetFileSystemEntries(APath, '*', TSearchOption.soTopDirectoryOnly, APredicate);
end;

class function TDirectoryUtils.GetLogicalDrives: TArray<string>;
{$IFDEF MSWINDOWS}
var
  LBuff: string;
  LCurrDrive: PChar;
  LBuffLen: Integer;
  LErrCode: Cardinal;
begin
  Result := nil;

  // get the drive strings in a PChar buffer
  SetLastError(ERROR_SUCCESS);
  LBuffLen := GetLogicalDriveStrings(0, nil);
  SetLength(LBuff, LBuffLen);
  LErrCode := GetLogicalDriveStrings(LBuffLen, PChar(LBuff));

  // extract the drive strings from the PChar buffer into the Result array
  if (LErrCode <> 0) then
  begin
    LCurrDrive := PChar(LBuff);
    repeat
      SetLength(Result, Length(Result) + 1);
      Result[Length(Result) - 1] := LCurrDrive;

      LCurrDrive := StrEnd(LCurrDrive) + 1;
    until (LCurrDrive^ = #0);
  end;
end;
{$ELSE}
begin
  { Posix does not support file drives }
  SetLength(Result, 0);
end;
{$ENDIF}

class function TDirectoryUtils.Move(const ASourceDirName,
  ADestDirName: string; const AOverwrite: Boolean): Boolean;
var
  LPreCallback: TDirectoryWalkProc;
  LPostCallback: TDirectoryWalkProc;
begin
  LPreCallback :=
    function (const APath: string; const AFileInfo: TSearchRec): Boolean
    var
      LRelativeDir, LCompletePath: string;
    begin
      Result := True;

      // mirror each directory at the destination
      if (AFileInfo.Attr and SysUtils.faDirectory <> 0) and
         (AFileInfo.Name <> TPathUtils.CURRENT_DIR) and (AFileInfo.Name <> TPathUtils.PARENT_DIR) then
      begin
        // the destination is the one given by ADestDirName
        if SameFileName(ASourceDirName, APath) then
          LCompletePath := ADestDirName
        // get the difference between APath and ASourceDirName
        else
        begin
          LRelativeDir := ExtractRelativePath(ASourceDirName, APath);
          LCompletePath := TPathUtils.Combine(ADestDirName, LRelativeDir);
        end;

        LCompletePath := TPathUtils.Combine(LCompletePath, AFileInfo.Name);

        CreateDir(LCompletePath);
      end;
    end;

  LPostCallback :=
    function (const APath: string; const AFileInfo: TSearchRec): Boolean
    var
      LRelativeDir, LCompleteSrc, LCompleteDest: string;
      LDestFileExists: Boolean;
    begin
      Result := True;

      if (AFileInfo.Name <> TPathUtils.CURRENT_DIR) and (AFileInfo.Name <> TPathUtils.PARENT_DIR) then
      begin
        case AFileInfo.Attr and SysUtils.faDirectory of
          SysUtils.faDirectory: // remove directories at source
            begin
              LCompleteSrc := TPathUtils.Combine(APath, AFileInfo.Name);

              // clear read-only, system and hidden attributes that can compromise
              // the deletion and then remove the directory at source
              {$IFDEF MSWINDOWS}
              {$WARN SYMBOL_PLATFORM OFF}
              FileSetAttr(LCompleteSrc, SysUtils.faNormal);
              {$WARN SYMBOL_PLATFORM ON}
              {$ENDIF}
              RemoveDir(LCompleteSrc);
            end;

          0: // move files from source to destination
            begin
              // determine the complete source and destination paths
              LCompleteSrc := TPathUtils.Combine(APath, AFileInfo.Name);

              // the destination is the one given by ADestDirName
              if SameFileName(ASourceDirName, APath) then
                LCompleteDest := ADestDirName
              // get the difference between APath and ASourceDirName
              else
              begin
                LRelativeDir := ExtractRelativePath(ASourceDirName, APath);
                LCompleteDest := TPathUtils.Combine(ADestDirName, LRelativeDir);
              end;
              // add the file name to the destination
              LCompleteDest := TPathUtils.Combine(LCompleteDest, AFileInfo.Name);

              // clear read-only, system and hidden attributes that can compromise
              // the file displacement, move the file and reset the original
              // file attributes
              {$IFDEF MSWINDOWS}
              {$WARN SYMBOL_PLATFORM OFF}
              FileSetAttr(LCompleteSrc, SysUtils.faNormal);
              {$WARN SYMBOL_PLATFORM ON}
              {$ENDIF MSWINDOWS}

              LDestFileExists := TFileUtils.Exists(LCompleteDest);
              if LDestFileExists then
              begin
                if not AOverwrite then Exit;

                TFileUtils.Delete(LCompleteDest);
              end;

              if RenameFile(LCompleteSrc, LCompleteDest) then
              begin
                {$IFDEF MSWINDOWS}
                {$WARN SYMBOL_PLATFORM OFF}
                FileSetAttr(LCompleteDest, AFileInfo.Attr);
                {$WARN SYMBOL_PLATFORM ON}
                {$ENDIF MSWINDOWS}
              end;
            end;
        end;
      end;
    end;

  // create the destination directory
  TDirectoryUtils.CreateDirectory(ADestDirName);

  // move all directories and files
  WalkThroughDirectory(ASourceDirName, '*', LPreCallback, LPostCallback, True); // DO NOT LOCALIZE

  // delete the remaining source directory
  {$IFDEF MSWINDOWS}
  {$WARN SYMBOL_PLATFORM OFF}
  FileSetAttr(ASourceDirName, SysUtils.faDirectory);
  {$WARN SYMBOL_PLATFORM ON}
  {$ENDIF MSWINDOWS}
  Result := RemoveDir(ASourceDirName);
end;

class procedure TDirectoryUtils.WalkThroughDirectory(const APath,
  APattern: string; const APreCallback, APostCallback: TDirectoryWalkProc;
  const ARecursive: Boolean);
var
  LSearchRec: TSearchRec;
  LMatch: Boolean;
  LStop: Boolean;
begin
  if SysUtils.FindFirst(TPathUtils.Combine(APath, '*'), faAnyFile, LSearchRec) = 0 then // DO NOT LOCALIZE
  try
    LStop := False;

    repeat
      LMatch := TPathUtils.MatchesPattern(LSearchRec.Name, APattern);

      // 调用 APreCallback
      if LMatch and Assigned(APreCallback) then
        LStop := not APreCallback(APath, LSearchRec);

      if not LStop then
      begin
        // 递归处理子目录
        if ARecursive and (LSearchRec.Attr and faDirectory <> 0) and
           (LSearchRec.Name <> TPathUtils.CURRENT_DIR) and
           (LSearchRec.Name <> TPathUtils.PARENT_DIR) then
          WalkThroughDirectory(TPathUtils.Combine(APath, LSearchRec.Name),
            APattern, APreCallback, APostCallback, ARecursive);

        // 调用 APostCallback
        if LMatch and Assigned(APostCallback) then
          LStop := not APostCallback(APath, LSearchRec);
      end;
    until LStop or (SysUtils.FindNext(LSearchRec) <> 0);
  finally
    SysUtils.FindClose(LSearchRec);
  end;
end;

{ TPathUtils }

class function TPathUtils.ChangeExtension(const APath,
  AExtension: string): string;
var
  LSeparatorIdx: Integer;
begin
  if (APath = '') then Exit('');

  LSeparatorIdx := GetExtensionSeparatorPos(APath);

  if (LSeparatorIdx <= 0) then
    Result := APath
  else
    Result := System.Copy(APath, 1, LSeparatorIdx - 1);

  if (AExtension = '') then Exit;

  if (AExtension[1] <> EXTENSION_SEPARATOR_CHAR) then
    Result := Result + EXTENSION_SEPARATOR_CHAR;

  Result := Result + AExtension;
end;

class function TPathUtils.Combine(const APath1, APath2, APathDelim: string): string;
var
  LPath1EndsWithDelim, LPath2StartsWithDelim: Boolean;
begin
  if (APath1 = '') then Exit(APath2);
  if (APath2 = '') then Exit(APath1);

  LPath1EndsWithDelim := APath1.EndsWith(APathDelim, True);
  LPath2StartsWithDelim := APath2.StartsWith(APathDelim, True);
  if LPath1EndsWithDelim and LPath2StartsWithDelim then
    Result := APath1 + APath2.Substring(1)
  else if LPath1EndsWithDelim or LPath2StartsWithDelim then
    Result := APath1 + APath2
  else
    Result := APath1 + APathDelim + APath2;
end;

class function TPathUtils.Combine(const APath1, APath2: string): string;
begin
  Result := Combine(APath1, APath2, DIRECTORY_SEPARATOR_CHAR);
end;

class function TPathUtils.Combine(const APaths: array of string;
  const APathDelim: string): string;
var
  I: Integer;
begin
  if (Length(APaths) > 0) then
  begin
    Result := APaths[0];
    for I := 1 to Length(APaths) - 1 do
      Result := Combine(Result, APaths[I], APathDelim);
  end else
    Result := '';
end;

class function TPathUtils.Combine(const APaths: array of string): string;
begin
  Result := Combine(APaths, DIRECTORY_SEPARATOR_CHAR);
end;

class function TPathUtils.GetDirectoryName(const AFileName: string): string;
begin
  Result := ExtractFileDir(AFileName);
end;

class function TPathUtils.GetExtension(const AFileName: string): string;
begin
  Result := ExtractFileExt(AFileName);
end;

class function TPathUtils.GetExtensionSeparatorPos(
  const AFileName: string): Integer;
var
  I: Integer;
begin
  for I := Length(AFileName) downto 1 do
  begin
    if (AFileName[I] = EXTENSION_SEPARATOR_CHAR) then
      Exit(I);
  end;

  Result := 0;
end;

class function TPathUtils.GetFileName(const AFileName: string): string;
begin
  Result := ExtractFileName(AFileName);
end;

class function TPathUtils.GetFileNameWithoutExtension(
  const AFileName: string): string;
var
  LFileName: string;
  LExtSepPos: Integer;
begin
  LFileName := GetFileName(AFileName);
  LExtSepPos := GetExtensionSeparatorPos(LFileName);
  if (LExtSepPos > 0) then
    Result := System.Copy(LFileName, 1, LExtSepPos - 1)
  else
    Result := LFileName;
end;

class function TPathUtils.GetFullPath(const APath: string): string;
begin
  Result := ExpandFileName(APath);
end;

class function TPathUtils.GetHomePath: string;
begin
  Result := SysUtils.{$IFDEF DELPHI}GetHomePath{$ELSE}GetUserDir{$ENDIF};
end;

class function TPathUtils.MatchesPattern(const AFileName,
  APattern: string): Boolean;
begin
  if (APattern = '*') or (APattern = '*.*') then
    Result := True
  else
    Result := MatchesMask(AFileName, APattern);
end;

{ TTempFileStream }

constructor TTempFileStream.Create(const ATempPath: string);
var
  LTempPath: string;
begin
  if (ATempPath <> '') then
    LTempPath := ATempPath
  else
    LTempPath := TUtils.AppPath + 'temp';

  FTempFileName := TPathUtils.Combine(LTempPath, TUtils.GetGUID);

  if not TDirectoryUtils.Exists(LTempPath) then
    TDirectoryUtils.CreateDirectory(LTempPath);

  inherited Create(FTempFileName, fmCreate or fmShareDenyWrite);
end;

destructor TTempFileStream.Destroy;
begin
  inherited Destroy;

  if FileExists(FTempFileName) then
    TFileUtils.Delete(FTempFileName);
end;

end.
