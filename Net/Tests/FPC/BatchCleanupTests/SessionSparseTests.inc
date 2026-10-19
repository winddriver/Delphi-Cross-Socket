type
  {$IFDEF FPC}TSessionManager=TMemoryManager;TSessionSize=PtrUInt;
  {$ELSE}TSessionManager=TMemoryManagerEx;TSessionSize=NativeInt;{$ENDIF}
var SessionOriginalMM,SessionCountingMM:TSessionManager;
    SessionAllocCalls,SessionRequestedBytes,SessionLargestRequest:Int64;
threadvar SessionCountAllocations:Boolean;
procedure CountSessionAllocation(const N:TSessionSize);inline;
begin
  if SessionCountAllocations and (N>0) then begin
    Inc(SessionAllocCalls);Inc(SessionRequestedBytes,N);
    if N>SessionLargestRequest then SessionLargestRequest:=N;
  end;
end;
function SessionGetMem(N:TSessionSize):Pointer;
begin CountSessionAllocation(N);Result:=SessionOriginalMM.GetMem(N);end;
function SessionAllocMem(N:TSessionSize):Pointer;
begin CountSessionAllocation(N);Result:=SessionOriginalMM.AllocMem(N);end;
function SessionReallocMem({$IFDEF FPC}var{$ENDIF}P:Pointer;N:TSessionSize):Pointer;
begin CountSessionAllocation(N);Result:=SessionOriginalMM.ReallocMem(P,N);end;
procedure BenchSparseSessions(const ExpiredCount:Integer;const Allocations:Boolean);
var Started,Total:Int64;
begin
  Check(ExpiredCount in [0,1],'稀疏用例只允许0/1过期');
  {$IFDEF MSWINDOWS}Check(SetThreadAffinityMask(GetCurrentThread,4)<>0,'基准CPU绑定失败');{$ENDIF}
  Prepare(10000,ExpiredCount);
  try
    if Allocations then begin
      SessionAllocCalls:=0;SessionRequestedBytes:=0;SessionLargestRequest:=0;
      GetMemoryManager(SessionOriginalMM);SessionCountingMM:=SessionOriginalMM;
      SessionCountingMM.GetMem:=SessionGetMem;SessionCountingMM.AllocMem:=SessionAllocMem;
      SessionCountingMM.ReallocMem:=SessionReallocMem;SetMemoryManager(SessionCountingMM);
      try
        SessionCountAllocations:=True;
        try ClearExpiredSessionsForTest(Sessions);finally SessionCountAllocations:=False;end;
      finally SetMemoryManager(SessionOriginalMM);end;
      Writeln(Format('ALLOC sparse expired=%d alloc_calls=%d requested_bytes=%d largest_request=%d',
        [ExpiredCount,SessionAllocCalls,SessionRequestedBytes,SessionLargestRequest]));
    end else begin
      Sessions.Measuring:=True;Started:=Ticks;ClearExpiredSessionsForTest(Sessions);Total:=Ticks-Started;
      Sessions.Measuring:=False;
      Writeln(Format('BENCH sparse expired=%d total_us=%.3f lock_us=%.3f collect_us=%.3f remove_us=%.3f',
        [ExpiredCount,Total*1000000.0/Frequency,Sessions.LockTicks*1000000.0/Frequency,
         Sessions.CollectTicks*1000000.0/Frequency,Sessions.RemoveTicks*1000000.0/Frequency]));
    end;
    Check((Sessions.Count=10000-ExpiredCount) and (Destroyed=ExpiredCount)
      and (Sessions.Checked=10000),'稀疏扫描删除或检查数量错误');
  finally Sessions.Free;Sessions:=nil;end;
end;
procedure BenchSessionTail;
const Warmups=10;Samples=100;
var I:Integer;Started:Int64;Totals,Locks:array[0..Samples-1] of Int64;
begin
  {$IFDEF MSWINDOWS}Check(SetThreadAffinityMask(GetCurrentThread,4)<>0,'基准CPU绑定失败');{$ENDIF}
  Prepare(10000,0);
  try
    for I:=1 to Warmups do ClearExpiredSessionsForTest(Sessions);
    Sessions.Measuring:=True;
    for I:=0 to Samples-1 do begin
      Sessions.LockTicks:=0;Started:=Ticks;ClearExpiredSessionsForTest(Sessions);
      Totals[I]:=Ticks-Started;Locks[I]:=Sessions.LockTicks;
    end;
    Sessions.Measuring:=False;
    Check((Sessions.Count=10000) and (Destroyed=0) and
      (Sessions.Checked=10000*(Warmups+Samples)),'连续空清理改变活跃Session');
    for I:=0 to Samples-1 do Writeln(Format('TAIL sample=%d total_us=%.3f lock_us=%.3f',
      [I,Totals[I]*1000000.0/Frequency,Locks[I]*1000000.0/Frequency]));
  finally Sessions.Free;Sessions:=nil;end;
end;
