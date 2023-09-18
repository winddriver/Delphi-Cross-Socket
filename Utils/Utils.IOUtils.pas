unit Utils.IOUtils;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Masks,

  {$IFDEF FPC}
  DTF.RTL,
  {$ENDIF}

  Utils.Utils;

type
  { TFileUtils }

  TFileUtils = class
  public
    class function OpenCreate(const AFileName: string): TFileStream; static;
    class function OpenRead(const AFileName: string): TFileStream; static;
    class function OpenWrite(const AFileName: string): TFileStream; static;

    class function ReadAllBytes(const AFileName: string): TBytes; static;
    class function ReadAllText(const AFileName: string; const AEncoding: TEncoding = nil): string; static;

    class procedure WriteAllBytes(const AFileName: string; const ABytes: TBytes); static;
    class procedure WriteAllText(const AFileName, AContents: string;
      const AEncoding: TEncoding = nil; const AWriteBOM: Boolean = True); static;

    class procedure WriteAllStream(const AFileName: string; const AStream: TStream); static;

    class procedure AppendAllText(const AFileName, AContents: string;
      const AEncoding: TEncoding = nil); static;

    class function GetDateTimeInfo(const APath: string; out ACreationTime,
        ALastAccessTime, ALastWriteTime: TDateTime): Boolean; static;
    class function GetCreationTime(const APath: string): TDateTime; static;
    class function GetLastAccessTime(const APath: string): TDateTime; static;
    class function GetLastWriteTime(const APath: string): TDateTime; static;

    class function Exists(const AFileName: string): Boolean; static; inline;
    class function Delete(const AFileName: string): Boolean; static;
    class function CopyFile(const ASrcFileName, ADstFileName: string): Boolean; static;
    class function MoveFile(const ASrcFileName, ADstFileName: string): Boolean; static;
  end;

  TSearchOption = (soTopDirectoryOnly, soAllDirectories);

  TFilterPredicate = reference to function(const APath: string;
      const ASearchRec: TSearchRec): Boolean;

  TDirectoryWalkProc = reference to function (const APath: string;
      const AFileInfo: TSearchRec): Boolean;

  TDirectoryUtils = class
  public
    class procedure WalkThroughDirectory(const APath, APattern: string;
        const APreCallback, APostCallback: TDirectoryWalkProc;
        const ARecursive: Boolean); static;

    class procedure CreateDirectory(const APath: string); static;
    class function Exists(const APath: string): Boolean; inline; static;

    class function Delete(const APath: string; const ARecursive: Boolean = False): Boolean; static;

    class function GetFiles(const APath, ASearchPattern: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; static;
    class function GetDirectories(const APath, ASearchPattern: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; static;
    class function GetFileSystemEntries(const APath, ASearchPattern: string;
        const ASearchOption: TSearchOption;
        const APredicate: TFilterPredicate = nil): TArray<string>; overload; static;
  end;

  TPathUtils = class
  public const
    CURRENT_DIR: string = '.';
    PARENT_DIR: string = '..';
    EXTENDED_PREFIX: string = '\\?\';
    EXTENDED_UNC_PREFIX: string = '\\?\UNC\';
  public
    class function Combine(const APath1, APath2: string; const APathDelim: Char): string; overload; static;
    class function Combine(const APath1, APath2: string): string; overload; static; inline;

    class function GetExtensionSeparatorPos(const AFileName: string): Integer; static;

    class function GetExtension(const AFileName: string): string; static;
    class function GetFileName(const AFileName: string): string; static;
    class function GetFileNameWithoutExtension(const AFileName: string): string; static;

    class function GetFullPath(const APath: string): string; static;
    class function GetDirectoryName(const AFileName: string): string; static;

    class function MatchesPattern(const AFileName, APattern: string): Boolean; static;
  end;

  TFileStreamHelper = class helper for TFileStream
  public
    class function OpenCreate(const AFileName: string): TFileStream; static; inline;
    class function OpenRead(const AFileName: string): TFileStream; static; inline;
    class function OpenWrite(const AFileName: string): TFileStream; static; inline;
  end;

implementation

{ TFileUtils }

class function TFileUtils.CopyFile(const ASrcFileName,
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

class function TFileUtils.Delete(const AFileName: string): Boolean;
begin
  Result := DeleteFile(AFileName);
end;

class function TFileUtils.Exists(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
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

class function TFileUtils.MoveFile(const ASrcFileName,
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
  TDirectoryUtils.CreateDirectory(ExtractFilePath(AFileName));
  Result := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
end;

class function TFileUtils.OpenRead(const AFileName: string): TFileStream;
begin
  Result := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
end;

class function TFileUtils.OpenWrite(const AFileName: string): TFileStream;
begin
  if FileExists(AFileName) then
    Result := TFileStream.Create(AFileName, fmOpenReadWrite or fmShareDenyWrite)
  else
  begin
    TDirectoryUtils.CreateDirectory(ExtractFilePath(AFileName));
    Result := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  end;
end;

class function TFileUtils.ReadAllBytes(const AFileName: string): TBytes;
var
  LFileStream: TFileStream;
  LFileSize: Int64;
begin
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

class procedure TFileUtils.WriteAllBytes(const AFileName: string;
  const ABytes: TBytes);
var
  LFileStream: TFileStream;
begin
  LFileStream := nil;
  try
    LFileStream := OpenCreate(AFileName);
    LFileStream.Size := Length(ABytes);
    LFileStream.Seek(0, TSeekOrigin.soBeginning);
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

  LFileStream := OpenCreate(AFileName);
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

class procedure TDirectoryUtils.CreateDirectory(const APath: string);
begin
  if (APath <> '') then
    ForceDirectories(APath);
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
          FileSetAttr(LCompletePath, faNormal);
          {$ENDIF MSWINDOWS}

          case AFileInfo.Attr and faDirectory of
            faDirectory: // remove empty directories
              RemoveDir(LCompletePath);
            0: // remove files
              DeleteFile(LCompletePath);
          end;
        end;
      end;

    // 删除目录中的文件和子目录
    WalkThroughDirectory(APath, '*', nil, LPostCallback, ARecursive);
  end;

  {$IFDEF MSWINDOWS}
  FileSetAttr(APath, faNormal);
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

class procedure TDirectoryUtils.WalkThroughDirectory(const APath,
  APattern: string; const APreCallback, APostCallback: TDirectoryWalkProc;
  const ARecursive: Boolean);
var
  LSearchRec: TSearchRec;
  LMatch: Boolean;
  LStop: Boolean;
begin
  if FindFirst(TPathUtils.Combine(APath, '*'), faAnyFile, LSearchRec) = 0 then // DO NOT LOCALIZE
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
    until LStop or (FindNext(LSearchRec) <> 0);
  finally
    FindClose(LSearchRec);
  end;
end;

{ TPathUtils }

class function TPathUtils.Combine(const APath1, APath2: string;
  const APathDelim: Char): string;
var
  LPath1Ends, LPath2Starts: string;
begin
  if (APath1 = '') then Exit(APath2);
  if (APath2 = '') then Exit(APath1);

  LPath1Ends := APath1.Substring(APath1.Length - 1, 1);
  LPath2Starts := APath2.Substring(0, 1);
  if (LPath1Ends = APathDelim) and (LPath2Starts = APathDelim) then
    Result := APath1 + APath2.Substring(1)
  else if (LPath1Ends = APathDelim) and (LPath2Starts <> APathDelim) then
    Result := APath1 + APath2
  else if (LPath1Ends <> APathDelim) and (LPath2Starts = APathDelim) then
    Result := APath1 + APath2
  else
    Result := APath1 + APathDelim + APath2;
end;

class function TPathUtils.Combine(const APath1, APath2: string): string;
begin
  Result := Combine(APath1, APath2, PathDelim);
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
    if (AFileName[I] = '.') then
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

class function TPathUtils.MatchesPattern(const AFileName,
  APattern: string): Boolean;
begin
  if (APattern = '*.*') then
    Result := True
  else
    Result := MatchesMask(AFileName, APattern);
end;

end.
