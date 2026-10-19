type
  {$IFDEF FPC}
  TBenchManager = TMemoryManager;
  TBenchSize = PtrUInt;
  {$ELSE}
  TBenchManager = TMemoryManagerEx;
  TBenchSize = NativeInt;
  {$ENDIF}
  TBenchBioCtrl = function(B: PBIO; Cmd: Integer; Arg: Longint; P: Pointer): Longint; cdecl;
var
  BenchOriginalMM, BenchCountingMM: TBenchManager;
  BenchAllocations, BenchRequestedBytes, BenchFrequency: Int64;
  BenchThreadId: Cardinal;
  BenchOriginalBioCtrl: TBenchBioCtrl;
  BenchPendingCalls, BenchPendingNonempty: Integer;

function IsBenchThread: Boolean; inline;
begin
  {$IFDEF MSWINDOWS}Result := GetCurrentThreadId = BenchThreadId;{$ELSE}Result := True;{$ENDIF}
end;

function BenchGetMem(ASize: TBenchSize): Pointer;
begin
  if IsBenchThread then begin Inc(BenchAllocations); Inc(BenchRequestedBytes, ASize); end;
  Result := BenchOriginalMM.GetMem(ASize);
end;
function BenchAllocMem(ASize: TBenchSize): Pointer;
begin
  if IsBenchThread then begin Inc(BenchAllocations); Inc(BenchRequestedBytes, ASize); end;
  Result := BenchOriginalMM.AllocMem(ASize);
end;
function BenchReallocMem({$IFDEF FPC}var{$ENDIF} P: Pointer; ASize: TBenchSize): Pointer;
begin
  if (ASize > 0) and IsBenchThread then begin Inc(BenchAllocations); Inc(BenchRequestedBytes, ASize); end;
  Result := BenchOriginalMM.ReallocMem(P, ASize);
end;

procedure BeginAllocationCount;
begin
  BenchAllocations := 0; BenchRequestedBytes := 0;
  {$IFDEF MSWINDOWS}BenchThreadId := GetCurrentThreadId;{$ENDIF}
  GetMemoryManager(BenchOriginalMM);
  BenchCountingMM := BenchOriginalMM;
  BenchCountingMM.GetMem := BenchGetMem;
  BenchCountingMM.AllocMem := BenchAllocMem;
  BenchCountingMM.ReallocMem := BenchReallocMem;
  SetMemoryManager(BenchCountingMM);
end;

function ProbeBioCtrl(B: PBIO; Cmd: Integer; Arg: Longint; P: Pointer): Longint; cdecl;
begin
  Result := BenchOriginalBioCtrl(B, Cmd, Arg, P);
  if Cmd = BIO_CTRL_PENDING then
  begin
    Inc(BenchPendingCalls);
    if Result > 0 then Inc(BenchPendingNonempty);
  end;
end;

procedure ProbeTlsPending;
const Sizes: array[0..2] of Integer = (32, 1024, 65536);
var F: TTlsFixture; V, S, I, N: Integer; Data, Wire: TBytes;
begin
  for V := TLS1_2_VERSION to TLS1_3_VERSION do for S := 0 to High(Sizes) do
  begin
    F := TTlsFixture.Create(V);
    try
      F.Handshake; F.Socket.BenchReceive := True;
      SetLength(Data, Sizes[S]); FillChar(Data[0], Length(Data), $41);
      BenchPendingCalls := 0; BenchPendingNonempty := 0;
      for I := 1 to 100 do
      begin
        Check(SSL_write(F.Peer, Pointer(Data), Length(Data)) = Length(Data), 'BIO probe peer write failed');
        N := BIO_pending(F.PeerOut); SetLength(Wire, N);
        Check(BIO_read(F.PeerOut, Pointer(Wire), N) = N, 'BIO probe ciphertext missing');
        BenchOriginalBioCtrl := BIO_ctrl;
        BIO_ctrl := ProbeBioCtrl;
        try F.Socket.Inject(F.Connection, Wire); finally BIO_ctrl := BenchOriginalBioCtrl; end;
      end;
      Writeln('PENDING version=', V, ' bytes=', Sizes[S], ' reads=100 calls=', BenchPendingCalls,
        ' nonempty=', BenchPendingNonempty);
      Check((BenchPendingCalls = 100) and (BenchPendingNonempty = 0), 'ordinary TLS receive BIO probe differs');
    finally F.Free; end;
  end;
end;
procedure EndAllocationCount;
begin SetMemoryManager(BenchOriginalMM); end;

function BenchNow: Int64;
begin
  {$IFDEF MSWINDOWS}QueryPerformanceCounter(Result);{$ELSE}Result := 0;{$ENDIF}
end;
procedure InitBufferBench;
begin
  {$IFDEF MSWINDOWS}
  Check(SetThreadAffinityMask(GetCurrentThread, 2) <> 0, 'benchmark affinity failed');
  QueryPerformanceFrequency(BenchFrequency);
  Writeln('CLOCK frequency=', BenchFrequency, ' affinity=2');
  {$ELSE}
  raise Exception.Create('This benchmark uses Windows QPC; Linux is correctness-only');
  {$ENDIF}
end;
procedure SortBenchSamples(var A: array of Int64; L, R: Integer);
var I, J: Integer; P, T: Int64;
begin
  I := L; J := R; P := A[(L + R) div 2];
  repeat
    while A[I] < P do Inc(I);
    while A[J] > P do Dec(J);
    if I <= J then begin T := A[I]; A[I] := A[J]; A[J] := T; Inc(I); Dec(J); end;
  until I > J;
  if L < J then SortBenchSamples(A, L, J);
  if I < R then SortBenchSamples(A, I, R);
end;
procedure ReportBufferBench(const AName: string; const N: Integer;
  const AElapsed: Int64; var Samples: array of Int64);
var Index: Integer;
begin
  SortBenchSamples(Samples, 0, High(Samples));
  Index := (Length(Samples) * 99 + 99) div 100 - 1;
  Writeln('BENCH ', AName, ' n=', N,
    ' batch_ns=', Round(AElapsed * 1000000000.0 / BenchFrequency),
    ' alloc_calls=', BenchAllocations, ' requested_bytes=', BenchRequestedBytes,
    ' p99_ns=', Round(Samples[Index] * 1000000000.0 / BenchFrequency));
end;

procedure CheckBenchFrame(const Wire, Payload: TBytes; const AMasked: Boolean;
  const AOpCode: Byte; const AFin: Boolean);
var H, I: Integer; N: UInt64; B: Byte;
begin
  H := 2; N := Wire[1] and $7F;
  if N = 126 then begin N := UInt64(Wire[2]) shl 8 or Wire[3]; H := 4; end
  else if N = 127 then begin N := 0; for I := 2 to 9 do N := N shl 8 or Wire[I]; H := 10; end;
  Check((N = UInt64(Length(Payload))) and ((Wire[1] and $80 <> 0) = AMasked), 'frame length/mask differs');
  Check((Wire[0] and $0F = AOpCode) and ((Wire[0] and $80 <> 0) = AFin), 'frame opcode/FIN differs');
  if AMasked then Inc(H, 4);
  Check(Length(Wire) = H + Length(Payload), 'frame bytes length differs');
  for I := 0 to High(Payload) do
  begin
    B := Wire[H + I];
    if AMasked then B := B xor Wire[H - 4 + (I and 3)];
    Check(B = Payload[I], 'frame payload differs');
  end;
end;

procedure RunWsBufferBench;
const Sizes: array[0..7] of Integer = (0, 1, 32, 125, 126, 65535, 65536, 1048576);
var Size, N, I, M, S: Integer; Data, Wire, Saved, Expected: TBytes;
    Samples: array of Int64; Started, Elapsed, T: Int64; Name: string;
begin
  InitBufferBench;
  for M := 0 to 1 do for S := 0 to High(Sizes) do
  begin
    Size := Sizes[S]; SetLength(Data, Size);
    for I := 0 to High(Data) do Data[I] := Byte((I * 17 + S) and $FF);
    Wire := TCrossWebSocketParser.MakeFrameData(2, True, M = 0, Pointer(Data), Size);
    CheckBenchFrame(Wire, Data, M = 1, 2, True);
    Saved := Wire; Expected := Copy(Wire);
    Wire := TCrossWebSocketParser.MakeFrameData(1, False, M = 0, Pointer(Data), Size);
    CheckBenchFrame(Wire, Data, M = 1, 1, False);
    Check(CompareMem(Pointer(Saved), Pointer(Expected), Length(Expected)), 'retained frame changed');
    Saved := nil; Expected := nil; Wire := nil;
    N := 200000;
    if Size > 0 then N := (32 * 1024 * 1024) div Size;
    if N < 512 then N := 512;
    if N > 200000 then N := 200000;
    for I := 1 to 128 do Wire := TCrossWebSocketParser.MakeFrameData(2, True, M = 0, Pointer(Data), Size);
    Started := BenchNow;
    for I := 1 to N do Wire := TCrossWebSocketParser.MakeFrameData(2, True, M = 0, Pointer(Data), Size);
    Elapsed := BenchNow - Started;
    SetLength(Samples, N);
    for I := 0 to N - 1 do
    begin
      T := BenchNow;
      Wire := TCrossWebSocketParser.MakeFrameData(2, True, M = 0, Pointer(Data), Size);
      Samples[I] := BenchNow - T;
    end;
    BeginAllocationCount;
    try
      for I := 1 to N do Wire := TCrossWebSocketParser.MakeFrameData(2, True, M = 0, Pointer(Data), Size);
    finally EndAllocationCount; end;
    CheckBenchFrame(Wire, Data, M = 1, 2, True);
    Name := 'ws-' + IntToStr(M) + '-' + IntToStr(Size);
    ReportBufferBench(Name, N, Elapsed, Samples);
    Samples := nil; Wire := nil;
  end;
end;

procedure RunTlsBufferBench(const Version: Integer);
const Sizes: array[0..2] of Integer = (32, 1024, 65536);
var F: TTlsFixture; Records: TArray<TBytes>; Data: TBytes;
    Samples: array of Int64; Size, S, N, I, Count, Offset: Integer;
    T, Started, Elapsed: Int64;
begin
  InitBufferBench;
  for S := 0 to High(Sizes) do
  begin
    F := TTlsFixture.Create(Version);
    try
      F.Handshake; F.Socket.BenchReceive := True;
      Size := Sizes[S]; N := (16 * 1024 * 1024) div Size;
      if N < 512 then N := 512;
      if N > 20000 then N := 20000;
      SetLength(Data, Size); FillChar(Data[0], Size, $41);
      SetLength(Records, 128 + 3 * N);
      // 每条记录都来自同一真实TLS会话，序号不同；预生成不进入计时或分配统计窗口。
      for I := 0 to High(Records) do
      begin
        Check(SSL_write(F.Peer, @Data[0], Size) = Size, 'benchmark peer write failed');
        Count := BIO_pending(F.PeerOut); SetLength(Records[I], Count);
        Check(BIO_read(F.PeerOut, Pointer(Records[I]), Count) = Count, 'benchmark record missing');
      end;
      for I := 0 to 127 do F.Socket.Inject(F.Connection, Records[I]);
      Offset := 128; Started := BenchNow;
      for I := 0 to N - 1 do F.Socket.Inject(F.Connection, Records[Offset + I]);
      Elapsed := BenchNow - Started;
      Inc(Offset, N); SetLength(Samples, N);
      for I := 0 to N - 1 do
      begin
        T := BenchNow; F.Socket.Inject(F.Connection, Records[Offset + I]); Samples[I] := BenchNow - T;
      end;
      Inc(Offset, N); BeginAllocationCount;
      try
        for I := 0 to N - 1 do F.Socket.Inject(F.Connection, Records[Offset + I]);
      finally EndAllocationCount; end;
      Check(F.Socket.BenchBytes = Int64(Length(Records)) * Size, 'benchmark lost plaintext');
      Check(F.Socket.PendingCount = 0, 'application read generated pending output');
      ReportBufferBench('tls-' + IntToStr(Version) + '-' + IntToStr(Size), N, Elapsed, Samples);
    finally Records := nil; Samples := nil; Data := nil; F.Free; end;
  end;
end;
