type
  {$IFDEF FPC}TSocketBenchManager=TMemoryManager;TSocketBenchSize=PtrUInt;
  {$ELSE}TSocketBenchManager=TMemoryManagerEx;TSocketBenchSize=NativeInt;{$ENDIF}
var SocketBenchOriginal,SocketBenchCounting:TSocketBenchManager;
    SocketBenchCalls,SocketBenchBytes:Int64;
threadvar SocketBenchTracking,SocketBenchFailAllocation,SocketBenchFailureHit:Boolean;
procedure SocketBenchCheckAllocation;
begin
  if SocketBenchFailAllocation then begin
    SocketBenchFailAllocation:=False;SocketBenchFailureHit:=True;
    raise EOutOfMemory.Create('预期完成包装分配失败');
  end;
end;
function SocketBenchGetMem(N:TSocketBenchSize):Pointer;
begin SocketBenchCheckAllocation;if SocketBenchTracking then begin Inc(SocketBenchCalls);Inc(SocketBenchBytes,N);end;Result:=SocketBenchOriginal.GetMem(N);end;
function SocketBenchAllocMem(N:TSocketBenchSize):Pointer;
begin SocketBenchCheckAllocation;if SocketBenchTracking then begin Inc(SocketBenchCalls);Inc(SocketBenchBytes,N);end;Result:=SocketBenchOriginal.AllocMem(N);end;
function SocketBenchRealloc({$IFDEF FPC}var{$ENDIF}P:Pointer;N:TSocketBenchSize):Pointer;
begin if N>0 then SocketBenchCheckAllocation;if SocketBenchTracking and (N>0) then begin Inc(SocketBenchCalls);Inc(SocketBenchBytes,N);end;Result:=SocketBenchOriginal.ReallocMem(P,N);end;
{$IFDEF POSIX}
type TSocketBenchClock=record Sec,Nano:Int64;end;
function SocketBenchClockGet(Id:Integer;var Value:TSocketBenchClock):Integer;cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'clock_gettime';
{$ENDIF}
function SocketBenchTicks:Int64;
{$IFDEF POSIX}var Clock:TSocketBenchClock;{$ENDIF}
begin
  {$IFDEF MSWINDOWS}QueryPerformanceCounter(Result);{$ELSE}
  if SocketBenchClockGet(1,Clock)<>0 then Halt(2);Result:=Clock.Sec*1000000000+Clock.Nano;{$ENDIF}
end;
procedure QueueSendBench(const S:TCapacitySocket;const Count:Integer;const Allocations:Boolean);
var I:Integer;Started,Elapsed,Frequency:Int64;
begin
  Check((Count>0) and (Count<=100000),'基准发送数错误');
  {$IFDEF MSWINDOWS}Check(SetThreadAffinityMask(GetCurrentThread,4)<>0,'基准CPU绑定失败');QueryPerformanceFrequency(Frequency);
  {$ELSE}Frequency:=1000000000;{$ENDIF}
  S.FExpected:=0;SetLength(S.FData[127],1);S.FData[127][0]:=42;
  SocketBenchCalls:=0;SocketBenchBytes:=0;Elapsed:=0;
  if Allocations then begin
    GetMemoryManager(SocketBenchOriginal);SocketBenchCounting:=SocketBenchOriginal;
    SocketBenchCounting.GetMem:=SocketBenchGetMem;SocketBenchCounting.AllocMem:=SocketBenchAllocMem;
    SocketBenchCounting.ReallocMem:=SocketBenchRealloc;SetMemoryManager(SocketBenchCounting);
    try
      SocketBenchTracking:=True;
      try for I:=1 to Count do S.BenchSend;finally SocketBenchTracking:=False;end;
    finally SetMemoryManager(SocketBenchOriginal);end;
  end else begin
    Started:=SocketBenchTicks;for I:=1 to Count do S.BenchSend;Elapsed:=SocketBenchTicks-Started;
  end;
  Check(not S.FConnection.IsClosed,'排队基准实际发送失败');
  Line(Format('METRIC n=%d enqueue_us=%.3f alloc_calls=%d requested_bytes=%d',
    [Count,Elapsed*1000000.0/Frequency,SocketBenchCalls,SocketBenchBytes]));
  Line('QUEUED '+IntToStr(Count));
end;
procedure SocketSendWithAllocationFault(const S:TCapacitySocket;const Buffer:Pointer;const Count:Integer;const Callback:TCrossConnectionCallback);
begin
  GetMemoryManager(SocketBenchOriginal);SocketBenchCounting:=SocketBenchOriginal;
  SocketBenchCounting.GetMem:=SocketBenchGetMem;SocketBenchCounting.AllocMem:=SocketBenchAllocMem;
  SocketBenchCounting.ReallocMem:=SocketBenchRealloc;SetMemoryManager(SocketBenchCounting);
  try
    SocketBenchFailureHit:=False;SocketBenchFailAllocation:=True;
    try S.RawSend(Buffer,Count,Callback);finally SocketBenchFailAllocation:=False;end;
  finally SetMemoryManager(SocketBenchOriginal);end;
  Check(SocketBenchFailureHit,'未触发实际RTL分配失败');
end;
