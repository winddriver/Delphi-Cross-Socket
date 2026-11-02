unit Net.CrossHttpRouteFile;

interface

{$I zLib.inc}

uses
  SysUtils, Classes;

type
  THttpFileEntry = record
    Name: string;
    Size: Int64;
    Time: TDateTime;
    Directory, ReadOnly, SysFile, Hidden: Boolean;
  end;

  // 打开之后发送、取元数据和列目录都使用同一个对象，不重新解析请求路径。
  THttpRouteFile = class(THandleStream)
  private
    FDirectory: Boolean;
    FModified: TDateTime;
    FRelativePath: string;
    {$IFDEF POSIX}
    FSearch: Pointer;
    {$ENDIF}
  public
    class function Open(const ABaseDir, AUrlPath: string): THttpRouteFile; static;
    destructor Destroy; override;
    function NextEntry(out AEntry: THttpFileEntry): Boolean;
    property Directory: Boolean read FDirectory;
    property Modified: TDateTime read FModified;
    property RelativePath: string read FRelativePath;
  end;

implementation

uses
  DateUtils, Net.CrossHttpUtils, Utils.IOUtils
  {$IFDEF MSWINDOWS}, Windows{$ENDIF}
  {$IFDEF POSIX}
    {$IFDEF DELPHI}, Posix.Base, Posix.Dirent, Posix.Fcntl, Posix.SysStat{$ELSE}, BaseUnix{$ENDIF}
  {$ENDIF};

{$IFDEF MSWINDOWS}

type
  TNtName = record
    Length, MaximumLength: Word;
    Buffer: PWideChar;
  end;
  TNtAttributes = record
    Length: Cardinal;
    RootDirectory: THandle;
    ObjectName: ^TNtName;
    Attributes: Cardinal;
    SecurityDescriptor, SecurityQoS: Pointer;
  end;
  TNtIo = record
    Status, Information: NativeUInt;
  end;
  TFileDirInfo = record
    Next, Index: Cardinal;
    Created, Accessed, Modified, Changed, Size, Allocation: Int64;
    Attributes, NameBytes: Cardinal;
    Name: array[0..511] of WideChar;
  end;

function NtOpenFile(var AFile: THandle; AAccess: Cardinal; var AAttrs: TNtAttributes;
  var AIo: TNtIo; AShare, AOptions: Cardinal): LongInt; stdcall; external 'ntdll.dll';
function NtQueryDirectoryFile(AFile, AEvent: THandle; AApc, AContext: Pointer;
  var AIo: TNtIo; ABuffer: Pointer; ALength, AClass: Cardinal; ASingle: Byte;
  APattern: Pointer; ARestart: Byte): LongInt; stdcall; external 'ntdll.dll';

function OpenChild(AParent: THandle; const AName: string): THandle;
const
  OBJ_CASE_INSENSITIVE = $40;
  FILE_SYNCHRONOUS_IO_NONALERT = $20;
  FILE_OPEN_REPARSE_POINT = $200000;
var
  LName: TNtName;
  LAttrs: TNtAttributes;
  LIo: TNtIo;
begin
  Result := INVALID_HANDLE_VALUE;
  if (AName = '') or (Length(AName) > High(Word) div SizeOf(WideChar))
    or (Pos(':', AName) <> 0) then Exit;
  LName.Length := Length(AName) * SizeOf(WideChar);
  LName.MaximumLength := LName.Length;
  LName.Buffer := PWideChar(AName);
  FillChar(LAttrs, SizeOf(LAttrs), 0);
  LAttrs.Length := SizeOf(LAttrs);
  LAttrs.RootDirectory := AParent;
  LAttrs.ObjectName := @LName;
  LAttrs.Attributes := OBJ_CASE_INSENSITIVE;
  // 每次只打开一个分量。原生相对打开避免盘符、设备别名和已改名父目录被二次解析。
  if NtOpenFile(Result, GENERIC_READ or SYNCHRONIZE, LAttrs, LIo, FILE_SHARE_READ or FILE_SHARE_WRITE,
    FILE_OPEN_REPARSE_POINT or FILE_SYNCHRONOUS_IO_NONALERT) < 0 then Result := INVALID_HANDLE_VALUE;
end;

function ReadInfo(AFile: THandle; out ADir: Boolean; out AModified: TDateTime): Boolean;
var
  LInfo: TByHandleFileInformation;
  LTime: TSystemTime;
begin
  Result := GetFileInformationByHandle(AFile, LInfo) and
    ((LInfo.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0) and
    (GetFileType(AFile) = FILE_TYPE_DISK);
  if not Result then Exit;
  ADir := (LInfo.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0;
  if not FileTimeToSystemTime(LInfo.ftLastWriteTime, LTime) then Exit(False);
  AModified := SystemTimeToDateTime(LTime);
end;

function THttpRouteFile.NextEntry(out AEntry: THttpFileEntry): Boolean;
var
  LData: TFileDirInfo;
  LIo: TNtIo;
  LLocal: TFileTime;
  LTime: TSystemTime;
  LStatus: LongInt;
begin
  repeat
    LStatus := NtQueryDirectoryFile(Handle, 0, nil, nil, LIo, @LData, SizeOf(LData),
      1 {FileDirectoryInformation}, 1, nil, 0);
    if Cardinal(LStatus) = $80000006 then Exit(False); // STATUS_NO_MORE_FILES
    if LStatus < 0 then raise EReadError.Create('不能读取静态目录');
    SetString(AEntry.Name, PWideChar(@LData.Name[0]), LData.NameBytes div SizeOf(WideChar));
  until (AEntry.Name <> '.') and (AEntry.Name <> '..') and
    ((LData.Attributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0);
  AEntry.Directory := (LData.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0;
  AEntry.ReadOnly := (LData.Attributes and FILE_ATTRIBUTE_READONLY) <> 0;
  AEntry.SysFile := (LData.Attributes and FILE_ATTRIBUTE_SYSTEM) <> 0;
  AEntry.Hidden := (LData.Attributes and FILE_ATTRIBUTE_HIDDEN) <> 0;
  AEntry.Size := LData.Size;
  if FileTimeToLocalFileTime(PFileTime(@LData.Modified)^, LLocal) and FileTimeToSystemTime(LLocal, LTime) then
    AEntry.Time := SystemTimeToDateTime(LTime);
  Result := True;
end;

{$ELSE}

const
  {$IF DEFINED(LINUX) OR DEFINED(ANDROID)}
    {$IF DEFINED(CPUARM) OR DEFINED(CPUARM64) OR DEFINED(CPUAARCH64)}
    NO_FOLLOW = $8000;
    {$ELSE}
    NO_FOLLOW = $20000;
    {$ENDIF}
    CLOSE_ON_EXEC = $80000;
    PATH_ONLY = $200000;
  {$ELSE}
    NO_FOLLOW = $100;
    {$IFDEF MACOS}
    CLOSE_ON_EXEC = $1000000;
    STAT_NO_FOLLOW = $20;
    {$ELSE}
    CLOSE_ON_EXEC = $100000;
    STAT_NO_FOLLOW = $200;
    {$ENDIF}
  {$ENDIF}
  {$IF DEFINED(LINUX) AND DEFINED(CPU32)}
    {$IFDEF CPUARM}LARGE_FILE = $20000;{$ELSE}LARGE_FILE = $8000;{$ENDIF}
  {$ELSE}LARGE_FILE = 0;{$ENDIF}
  READ_FLAGS = O_RDONLY or O_NONBLOCK or O_NOCTTY or CLOSE_ON_EXEC or LARGE_FILE;

type
  TNativeStat = {$IFDEF DELPHI}_stat{$ELSE}BaseUnix.Stat{$ENDIF};

function RouteOpen(APath: PAnsiChar; AFlags: Integer): Integer; cdecl;
  external {$IFDEF DELPHI}libc name _PU + 'open'{$ELSE}'c' name 'open'{$ENDIF};
function RouteOpenAt(AParent: Integer; APath: PAnsiChar; AFlags: Integer): Integer; cdecl;
  external {$IFDEF DELPHI}libc name _PU + 'openat'{$ELSE}'c' name 'openat'{$ENDIF};
function RouteFdOpenDir(AFile: Integer): Pointer; cdecl;
  external {$IFDEF DELPHI}libc name _PU + 'fdopendir'{$ELSE}'c' name 'fdopendir'{$ENDIF};
{$IF NOT (DEFINED(LINUX) OR DEFINED(ANDROID))}
function RouteStatAt(AParent: Integer; AName: PAnsiChar; var AStat: TNativeStat; AFlags: Integer): Integer; cdecl;
  external {$IFDEF DELPHI}libc name _PU + 'fstatat' + _INODE_SUFFIX{$ELSE}'c' name
    {$IF DEFINED(DARWIN) AND (DEFINED(CPUI386) OR DEFINED(CPUX86_64)) AND
        DEFINED(MAC_OS_X_VERSION_MIN_REQUIRED) AND (MAC_OS_X_VERSION_MIN_REQUIRED >= 1060)}'fstatat$INODE64'
    {$ELSE}'fstatat'{$ENDIF}{$ENDIF};
{$ENDIF}
function RouteCloseDir(ASearch: Pointer): Integer; cdecl;
  external {$IFDEF DELPHI}libc name _PU + 'closedir'{$ELSE}'c' name 'closedir'{$ENDIF};
{$IFDEF FPC}
function RouteReadDir(ASearch: Pointer): PDirent; cdecl;
  external 'c' name
    {$IF DEFINED(LINUX) AND DEFINED(CPU32)}'readdir64'
    {$ELSEIF DEFINED(DARWIN) AND (DEFINED(CPUI386) OR DEFINED(CPUX86_64)) AND
      DEFINED(MAC_OS_X_VERSION_MIN_REQUIRED) AND (MAC_OS_X_VERSION_MIN_REQUIRED >= 1060)}'readdir$INODE64'
    {$ELSE}'readdir'{$ENDIF};
{$ENDIF}

function OpenChild(AParent: THandle; const AName: string): THandle;
begin
  Result := RouteOpenAt(AParent, PAnsiChar(UTF8String(AName)), READ_FLAGS or NO_FOLLOW);
end;

function ReadStat(AFile: THandle; out AStat: TNativeStat): Boolean;
begin
  Result := ({$IFDEF DELPHI}fstat{$ELSE}fpFStat{$ENDIF}(AFile, AStat) = 0)
    and ((AStat.st_mode and S_IFMT = S_IFREG) or (AStat.st_mode and S_IFMT = S_IFDIR));
end;

function ReadInfo(AFile: THandle; out ADir: Boolean; out AModified: TDateTime): Boolean;
var
  LStat: TNativeStat;
begin
  Result := ReadStat(AFile, LStat);
  if not Result then Exit;
  ADir := LStat.st_mode and S_IFMT = S_IFDIR;
  AModified := UnixToDateTime(LStat.st_mtime, True);
end;

function THttpRouteFile.NextEntry(out AEntry: THttpFileEntry): Boolean;
var
  LItem: PDirent;
  LFile: THandle;
  LStat: TNativeStat;
begin
  if FSearch = nil then
  begin
    // fdopendir 接管自己的描述符；该描述符与下载/后续 openat 使用的目录句柄分离。
    LFile := OpenChild(Handle, '.');
    if LFile = THandle(-1) then raise EReadError.Create('不能打开静态目录');
    FSearch := RouteFdOpenDir(LFile);
    if FSearch = nil then
    begin
      FileClose(LFile);
      raise EReadError.Create('不能枚举静态目录');
    end;
  end;
  repeat
    LItem := {$IFDEF DELPHI}Posix.Dirent.readdir(FSearch){$ELSE}RouteReadDir(FSearch){$ENDIF};
    if LItem = nil then Exit(False);
    AEntry.Name := UTF8ToString(PAnsiChar(@LItem^.d_name[0]));
    if (AEntry.Name = '.') or (AEntry.Name = '..') then Continue;
    {$IF DEFINED(LINUX) OR DEFINED(ANDROID)}
    // O_PATH 只取元数据；即使目录里有 FIFO/设备，也不触发它的打开操作。
    LFile := RouteOpenAt(Handle, PAnsiChar(@LItem^.d_name[0]), PATH_ONLY or CLOSE_ON_EXEC or NO_FOLLOW);
    if LFile = THandle(-1) then Continue;
    try
      if not ReadStat(LFile, LStat) then Continue;
    finally
      FileClose(LFile);
    end;
    {$ELSE}
    if RouteStatAt(Handle, PAnsiChar(@LItem^.d_name[0]), LStat, STAT_NO_FOLLOW) <> 0 then Continue;
    if (LStat.st_mode and S_IFMT <> S_IFREG) and (LStat.st_mode and S_IFMT <> S_IFDIR) then Continue;
    {$ENDIF}
    AEntry.Directory := LStat.st_mode and S_IFMT = S_IFDIR;
    AEntry.Size := LStat.st_size;
    AEntry.Time := UnixToDateTime(LStat.st_mtime, False);
    AEntry.ReadOnly := LStat.st_mode and S_IWUSR = 0;
    AEntry.Hidden := (AEntry.Name <> '') and (AEntry.Name[1] = '.');
    AEntry.SysFile := False;
    Exit(True);
  until False;
end;

{$ENDIF}

class function THttpRouteFile.Open(const ABaseDir, AUrlPath: string): THttpRouteFile;
var
  LBase, LResolved, LRelative, LPart: string;
  LParts: TArray<string>;
  LFile, LNext: THandle;
  LDir: Boolean;
  LModified: TDateTime;
begin
  Result := nil;
  LBase := TPathUtils.GetFullPath(ABaseDir);
  if not TCrossHttpUtils.TryUrlPathToLocalPath(LBase, AUrlPath, LResolved) then Exit;
  LRelative := Copy(LResolved, Length(IncludeTrailingPathDelimiter(LBase)) + 1, MaxInt);
  LParts := LRelative.Split([PathDelim], TStringSplitOptions.ExcludeEmpty);
  {$IFDEF MSWINDOWS}
  LFile := CreateFileW(PWideChar(LBase), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, nil,
    OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  {$ELSE}
  LFile := RouteOpen(PAnsiChar(UTF8String(LBase)), READ_FLAGS);
  {$ENDIF}
  if LFile = THandle(-1) then Exit;
  try
    if not ReadInfo(LFile, LDir, LModified) or not LDir then Exit;
    for LPart in LParts do
    begin
      if not LDir or (LPart = '.') or (LPart = '..') then Exit;
      LNext := OpenChild(LFile, LPart);
      if LNext = THandle(-1) then Exit;
      FileClose(LFile);
      LFile := LNext;
      if not ReadInfo(LFile, LDir, LModified) then Exit;
    end;
    Result := THttpRouteFile.Create(LFile);
    LFile := THandle(-1);
    Result.FDirectory := LDir;
    Result.FModified := LModified;
    Result.FRelativePath := LRelative;
  finally
    if LFile <> THandle(-1) then FileClose(LFile);
  end;
end;

destructor THttpRouteFile.Destroy;
begin
  {$IFDEF POSIX}
  if FSearch <> nil then RouteCloseDir(FSearch);
  {$ENDIF}
  FileClose(Handle);
  inherited;
end;

end.
