program FileStreamCleanupTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, RtlConsts,
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  Utils.IOUtils;

type
  {$IFDEF FPC}
  TTestMemoryManager = TMemoryManager;
  TTestSize = PtrUInt;
  TFreeResult = PtrUInt;
  {$ELSE}
  TTestMemoryManager = TMemoryManagerEx;
  TTestSize = NativeInt;
  TFreeResult = Integer;
  {$ENDIF}

var
  OriginalManager, TrackingManager: TTestMemoryManager;
  BufferSize: TTestSize;
  BufferPointer: Pointer;
  BufferAllocations: Integer;
  BufferFreed: Boolean;

function TrackGetMem(ASize: TTestSize): Pointer;
begin
  Result := OriginalManager.GetMem(ASize);
  if ASize = BufferSize then
  begin
    Inc(BufferAllocations);
    BufferPointer := Result;
  end;
end;

function TrackFreeMem(APointer: Pointer): TFreeResult;
begin
  Result := OriginalManager.FreeMem(APointer);
  if (APointer <> nil) and (APointer = BufferPointer) then BufferFreed := True;
end;

{$IFDEF FPC}
function TrackFreeMemSize(APointer: Pointer; ASize: PtrUInt): PtrUInt;
begin
  Result := OriginalManager.FreeMemSize(APointer, ASize);
  if (APointer <> nil) and (APointer = BufferPointer) then BufferFreed := True;
end;
{$ENDIF}

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure Run;
const
  DATA: AnsiString = 'buffered-write';
var
  LCase, LFileName, LErrorClass, LErrorMessage, LFlushClass, LFlushMessage: string;
  LStream, LDestroy: TFastFileStream;
  LHandle: THandle;
  LTemp, LFailure, LClosed, LWrite, LFlushFirst, LDeleted: Boolean;
  LMode: Word;
  {$IFDEF MSWINDOWS}
  LLockHandle: THandle;
  LOverlapped: TOverlapped;
  {$ENDIF}
begin
  Check(ParamCount = 2, '用法: FileStreamCleanupTests <用例> <独占测试目录>');
  LCase := ParamStr(1);
  LTemp := LCase.StartsWith('temp-');
  LFailure := (LCase = 'readonly-destroy') or (LCase = 'readonly-flush-destroy')
    or (LCase = 'temp-failure') or (LCase = 'temp-failure-after-flush');
  LWrite := (LCase <> 'readonly-clean') and (LCase <> 'temp-empty');
  LFlushFirst := (LCase = 'readonly-flush-destroy') or (LCase = 'temp-failure-after-flush')
    or (LCase = 'writable-flush');
  LFileName := IncludeTrailingPathDelimiter(ParamStr(2)) + 'original.bin';
  LMode := fmOpenRead or fmShareDenyNone;
  if LCase.StartsWith('writable-') then LMode := fmCreate or fmShareDenyNone;
  if LTemp then BufferSize := 32768 else BufferSize := 123457;
  LStream := nil;
  {$IFDEF MSWINDOWS}LLockHandle := INVALID_HANDLE_VALUE;{$ENDIF}
  GetMemoryManager(OriginalManager);
  TrackingManager := OriginalManager;
  TrackingManager.GetMem := TrackGetMem;
  TrackingManager.FreeMem := TrackFreeMem;
  {$IFDEF FPC}TrackingManager.FreeMemSize := TrackFreeMemSize;{$ENDIF}
  SetMemoryManager(TrackingManager);
  try
    if LTemp then
      LStream := TFileUtils.CreateTempFile(ParamStr(2)) as TFastFileStream
    else
      LStream := TFastFileStream.Create(LFileName, LMode, Integer(BufferSize));
    LFileName := LStream.FileName;
    LHandle := LStream.Handle;
    Check(BufferAllocations = 1, '没有唯一识别实际缓冲区分配');
    if LWrite then
      Check(LStream.Write(DATA[1], Length(DATA)) = Length(DATA), '小写入没有进入缓冲区');
    {$IFDEF MSWINDOWS}
    if LTemp and LFailure then
    begin
      // 第二个真实只读句柄加共享字节锁，禁止所有句柄写入；不关闭或替换流拥有的句柄。
      LLockHandle := CreateFileW(PWideChar(LFileName), GENERIC_READ,
        FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, 0);
      Check(LLockHandle <> INVALID_HANDLE_VALUE, '无法打开测试用文件锁句柄');
      FillChar(LOverlapped, SizeOf(LOverlapped), 0);
      Check(LockFileEx(LLockHandle, LOCKFILE_FAIL_IMMEDIATELY, 0, 4096, 0, LOverlapped),
        '无法建立共享字节锁');
    end;
    {$ENDIF}
    if LFlushFirst then
    begin
      try
        LStream.FlushBuffer;
      except
        on E: Exception do
        begin
          LFlushClass := E.ClassName;
          LFlushMessage := E.Message;
        end;
      end;
    end;
    LDestroy := LStream;
    LStream := nil;
    try
      LDestroy.Free;
    except
      on E: Exception do
      begin
        LErrorClass := E.ClassName;
        LErrorMessage := E.Message;
      end;
    end;
    // 此前不再打开文件，原生句柄值不会因本用例新打开文件而被复用。
    LClosed := FileSeek(LHandle, Int64(0), 0) = -1;
  finally
    SetMemoryManager(OriginalManager);
    {$IFDEF MSWINDOWS}
    if LLockHandle <> INVALID_HANDLE_VALUE then
    begin
      UnlockFileEx(LLockHandle, 0, 4096, 0, LOverlapped);
      CloseHandle(LLockHandle);
    end;
    {$ENDIF}
    if LStream <> nil then LStream.Free;
  end;
  LDeleted := not FileExists(LFileName);
  Writeln('OBS allocated=', BufferAllocations, ' freed=', Ord(BufferFreed),
    ' closed=', Ord(LClosed), ' deleted=', Ord(LDeleted), ' error=', LErrorClass);
  if LFailure then
  begin
    Check(LErrorClass = 'EWriteError', '析构未保留实际写入失败类型: ' + LErrorClass);
    Check(LErrorMessage = SWriteError, '析构覆盖了原始写入异常消息');
    if LFlushFirst then
      Check((LFlushClass = LErrorClass) and (LFlushMessage = LErrorMessage), '显式刷新与析构异常不一致');
  end else
    Check((LErrorClass = '') and (LFlushClass = ''), '正常路径出现异常');
  Check(BufferFreed, '真实缓冲区未释放');
  Check(LClosed, '真实文件句柄未关闭');
  if LTemp then Check(LDeleted, '临时文件未删除')
  else Check(not LDeleted, '普通文件被误删除');
end;

begin
  SetTextCodePage(Output, 65001);
  try
    Run;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
