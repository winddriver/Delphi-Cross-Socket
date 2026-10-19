// 本文件仅用于每项独立进程运行的真实刷新故障测试，不向生产单元增加钩子。
{$IFDEF MSWINDOWS}
type
  TBodyFlushOverlapped = record
    Internal, InternalHigh: NativeUInt;
    Offset, OffsetHigh: Cardinal;
    Event: THandle;
  end;
  TBodyFlushFault = record
    Handle: THandle;
    Overlapped: TBodyFlushOverlapped;
    Active: Boolean;
  end;

function BodyFlushOpenFile(AName: PWideChar; AAccess, ASharing: Cardinal;
  ASecurity: Pointer; ACreation, AFlags: Cardinal; ATemplate: THandle): THandle; stdcall;
  external 'kernel32.dll' name 'CreateFileW';
function BodyFlushLock(AHandle: THandle; AFlags, AReserved, ALow, AHigh: Cardinal;
  var AOverlapped: TBodyFlushOverlapped): LongBool; stdcall;
  external 'kernel32.dll' name 'LockFileEx';
function BodyFlushUnlock(AHandle: THandle; AReserved, ALow, AHigh: Cardinal;
  var AOverlapped: TBodyFlushOverlapped): LongBool; stdcall;
  external 'kernel32.dll' name 'UnlockFileEx';
function BodyFlushClose(AHandle: THandle): LongBool; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
function BodyFlushHandleCount(AProcess: THandle; var ACount: Cardinal): LongBool; stdcall;
  external 'kernel32.dll' name 'GetProcessHandleCount';

procedure StartBodyFlushFault(var AFault: TBodyFlushFault; const AFileName: string);
begin
  // 共享字节锁禁止所有句柄写入；流持有的原句柄没有被关闭或替换。
  AFault.Handle := BodyFlushOpenFile(PWideChar(AFileName), $80000000,
    $00000001 or $00000002 or $00000004, nil, 3, $00000080, 0);
  if AFault.Handle = THandle(High(NativeUInt)) then
    raise Exception.Create('无法打开刷新故障的锁句柄');
  if not BodyFlushLock(AFault.Handle, 1, 0, 4096, 0, AFault.Overlapped) then
  begin
    BodyFlushClose(AFault.Handle);
    raise Exception.Create('无法建立共享字节区锁');
  end;
  AFault.Active := True;
end;

procedure StopBodyFlushFault(var AFault: TBodyFlushFault);
begin
  if not AFault.Active then Exit;
  AFault.Active := False;
  try
    if not BodyFlushUnlock(AFault.Handle, 0, 4096, 0, AFault.Overlapped) then
      raise Exception.Create('无法释放测试字节区锁');
  finally
    BodyFlushClose(AFault.Handle);
  end;
end;

function BodyFlushSystemHandles: Integer;
var
  LCount: Cardinal;
begin
  if not BodyFlushHandleCount(THandle(High(NativeUInt)), LCount) then
    raise Exception.Create('无法读取测试进程句柄数');
  Result := LCount;
end;
{$ELSE}
type
  TBodyFlushRLimit = record
    Current, Maximum: UInt64;
  end;
  TBodyFlushFault = record
    OldLimit: TBodyFlushRLimit;
    OldSignal: Pointer;
    Active: Boolean;
  end;

function BodyFlushGetRLimit(AResource: Integer; var ALimit: TBodyFlushRLimit): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'getrlimit';
function BodyFlushSetRLimit(AResource: Integer; ALimit: Pointer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'setrlimit';
function BodyFlushSignal(ANumber: Integer; AHandler: Pointer): Pointer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'signal';
function BodyFlushReadLink(APath, ABuffer: PAnsiChar; ASize: NativeUInt): NativeInt; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'readlink';

procedure StartBodyFlushFault(var AFault: TBodyFlushFault; const AFileName: string);
var
  LLimit: TBodyFlushRLimit;
begin
  // Linux RLIMIT_FSIZE=1、SIGXFSZ=25；只降低当前独立测试子进程软限额，稍后恢复。
  if BodyFlushGetRLimit(1, AFault.OldLimit) <> 0 then
    raise Exception.Create('无法读取子进程文件大小上限');
  AFault.OldSignal := BodyFlushSignal(25, Pointer(1));
  if AFault.OldSignal = Pointer(High(NativeUInt)) then
    raise Exception.Create('无法在测试子进程忽略 SIGXFSZ');
  LLimit := AFault.OldLimit;
  LLimit.Current := 0;
  if BodyFlushSetRLimit(1, @LLimit) <> 0 then
  begin
    BodyFlushSignal(25, AFault.OldSignal);
    raise Exception.Create('无法限制测试子进程文件写入');
  end;
  AFault.Active := True;
end;

procedure StopBodyFlushFault(var AFault: TBodyFlushFault);
begin
  if not AFault.Active then Exit;
  AFault.Active := False;
  try
    if BodyFlushSetRLimit(1, @AFault.OldLimit) <> 0 then
      raise Exception.Create('无法恢复测试子进程文件大小上限');
  finally
    BodyFlushSignal(25, AFault.OldSignal);
  end;
end;

function BodyFlushSystemHandles: Integer;
begin
  Result := StorageFileCount('/proc/self/fd');
end;

function BodyFlushFileHandles(const AFileName: string): Integer;
var
  F: TSearchRec;
  LName, LTarget, LExpected: UTF8String;
  LBuffer: array[0..4095] of AnsiChar;
  LSize: NativeInt;
begin
  Result := 0;
  LExpected := UTF8Encode(AFileName);
  if FindFirst('/proc/self/fd/*', faAnyFile, F) <> 0 then Exit;
  try
    repeat
      if (F.Name = '.') or (F.Name = '..') then Continue;
      LName := UTF8Encode('/proc/self/fd/' + F.Name);
      LSize := BodyFlushReadLink(PAnsiChar(LName), @LBuffer[0], SizeOf(LBuffer));
      if LSize < 0 then Continue;
      SetString(LTarget, PAnsiChar(@LBuffer[0]), LSize);
      if (LTarget = LExpected) or (LTarget = LExpected + ' (deleted)') then Inc(Result);
    until FindNext(F) <> 0;
  finally
    FindClose(F);
  end;
end;
{$ENDIF}

procedure TestBodyFlush(const ACase: string);
const
  GZIP_64: array[0..23] of Byte = ($1f,$8b,$08,$00,$00,$00,$00,$00,$02,$ff,$ab,$a8,
    $a0,$0c,$00,$00,$12,$ac,$d2,$3a,$40,$00,$00,$00);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TMemoryConnection;
  LConnection: ICrossHttpConnection;
  LDirectory, LFileName: string;
  LId: TGUID;
  F: TSearchRec;
  LFault: TBodyFlushFault;
  LHeader, LPrefix, LTail: AnsiString;
  LProbe: TFileStream;
  LHandlesBefore, LHandlesAfter, LPublished, LCleanupErrors: Integer;
  LErrorResponse, LDisconnect: Boolean;
  procedure Require(const AValue: Boolean; const AMessage: string);
  begin
    // 失败也必须展开清理，不能调用外层会 Halt 的 Check。
    if not AValue then raise Exception.Create(AMessage);
  end;
begin
  Require((ACase = 'plain') or (ACase = 'chunked') or (ACase = 'gzip'), '未知刷新故障用例');
  CreateGUID(LId);
  LDirectory := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'body-flush-' + GUIDToString(LId);
  Require(ForceDirectories(LDirectory), '无法创建专用刷新测试目录');
  FillChar(LFault, SizeOf(LFault), 0);
  LServerObject := nil;
  LObject := nil;
  LCleanupErrors := 0;
  LPublished := -1;
  LErrorResponse := False;
  LDisconnect := False;
  LHandlesBefore := 0;
  try
    LServerObject := TQueueServer.Create;
    LServer := LServerObject;
    LServerObject.StoragePath := LDirectory;
    LServerObject.AutoDeleteFiles := False;
    {$IFDEF HTTP_BODY_STORAGE}LServerObject.BodyMemoryThreshold := 8;{$ENDIF}
    {$IFDEF HTTP_BODY_TEMP_PATH}LServerObject.BodyTempPath := LDirectory;{$ENDIF}
    LObject := TMemoryConnection.Create(LServerObject);
    LConnection := LObject;
    LHeader := 'POST /body-flush HTTP/1.1'#13#10'Host: localhost'#13#10 +
      'Content-Type: application/octet-stream'#13#10;
    if ACase = 'gzip' then
    begin
      LHeader := LHeader + 'Content-Encoding: gzip'#13#10'Content-Length: 48'#13#10#13#10;
      SetString(LPrefix, PAnsiChar(@GZIP_64[0]), Length(GZIP_64));
      LTail := LPrefix;
    end else
    if ACase = 'chunked' then
    begin
      LHeader := LHeader + 'Transfer-Encoding: chunked'#13#10#13#10;
      LPrefix := '10'#13#10'xxxxxxxxxxxxxxxx'#13#10;
      LTail := '10'#13#10'xxxxxxxxxxxxxxxx'#13#10'0'#13#10'X-Final: present'#13#10#13#10;
    end else
    begin
      LHeader := LHeader + 'Content-Length: 32'#13#10#13#10;
      LPrefix := 'xxxxxxxxxxxxxxxx';
      LTail := LPrefix;
    end;
    LObject.Feed(LHeader + LPrefix);
    Require(LServerObject.Responses.Count = 0, '未完成正文被发布');
    Require(StorageFileCount(LDirectory) = 1, '部分正文未产生唯一临时文件');
    Require(FindFirst(IncludeTrailingPathDelimiter(LDirectory) + '*', faAnyFile, F) = 0, '找不到临时正文文件');
    try
      repeat
        if (F.Name <> '.') and (F.Name <> '..') then
        begin
          LFileName := IncludeTrailingPathDelimiter(LDirectory) + F.Name;
          Break;
        end;
      until FindNext(F) <> 0;
    finally
      FindClose(F);
    end;
    Require(LFileName <> '', '没有定位临时正文文件');
    LProbe := TFileStream.Create(LFileName, fmOpenRead or fmShareDenyNone);
    try
      Require(LProbe.Size = 0, '夹具没有留下待刷新的小正文缓冲');
    finally
      LProbe.Free;
    end;
    LHandlesBefore := BodyFlushSystemHandles;
    {$IFNDEF MSWINDOWS}Require(BodyFlushFileHandles(LFileName) = 1, '没有唯一定位临时文件原句柄');{$ENDIF}
    StartBodyFlushFault(LFault, LFileName);
    try
      LObject.Feed(LTail);
    except
      on E: EAbort do ; // Parser 的失败终止信号，由实际事件层隔离。
    end;
    LPublished := LServerObject.Responses.Count;
    LObject.CompleteWrites;
    LErrorResponse := Pos('HTTP/1.1 500', LObject.Sent) > 0;
    LDisconnect := (LObject.CloseRequests + LObject.DisconnectRequests) > 0;
  finally
    try
      // 原写入故障保持到请求释放；析构仍可报告同一个真实 EWriteError。
      if LObject <> nil then
      begin
        try LObject.Cleanup; except on E: EWriteError do Inc(LCleanupErrors); end;
        try LObject.CompleteWrites; except on E: EWriteError do Inc(LCleanupErrors); end;
      end;
      if LServerObject <> nil then
        try LServerObject.Responses.Clear; except on E: EWriteError do Inc(LCleanupErrors); end;
      try LConnection := nil; except on E: EWriteError do Inc(LCleanupErrors); end;
      LObject := nil;
      try LServer := nil; except on E: EWriteError do Inc(LCleanupErrors); end;
      LServerObject := nil;
    finally
      StopBodyFlushFault(LFault);
    end;
    LHandlesAfter := BodyFlushSystemHandles;
    Writeln('BODY_FLUSH published=', LPublished, ' response500=', Ord(LErrorResponse),
      ' disconnect=', Ord(LDisconnect), ' cleanup_write_errors=', LCleanupErrors,
      ' handles_before=', LHandlesBefore, ' handles_after=', LHandlesAfter,
      ' files=', StorageFileCount(LDirectory));
    {$IFNDEF MSWINDOWS}
    if LFileName <> '' then Require(BodyFlushFileHandles(LFileName) = 0, '临时文件原句柄仍打开，包括已unlink的文件');
    {$ENDIF}
    Require(StorageFileCount(LDirectory) = 0, '刷新失败后的临时文件未删除');
    Require(RemoveDir(LDirectory), '专用刷新测试目录未清理');
  end;
  Require(LPublished = 0, '真实刷新失败前已把请求发布到业务');
  Require(LErrorResponse, '真实写入失败未返回500错误');
  Require(LDisconnect, '失败响应完成后没有请求关闭连接');
  Require(LHandlesAfter < LHandlesBefore, '临时文件句柄未随清理回收');
end;
