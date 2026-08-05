program CryptRandomTests;

{$I zLib.inc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Classes,
  Utils.CryptRandom;

type
  TCryptRandomThread = class(TThread)
  private
    FErrorMessage: string;
  protected
    procedure Execute; override;
  public
    property ErrorMessage: string read FErrorMessage;
  end;

procedure Fail(const AMessage: string);
begin
  raise Exception.Create(AMessage);
end;

procedure AssertTrue(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    Fail(AMessage);
end;

function BytesEqual(const ALeft, ARight: TBytes): Boolean;
var
  I: Integer;
begin
  if Length(ALeft) <> Length(ARight) then Exit(False);

  for I := 0 to Length(ALeft) - 1 do
    if ALeft[I] <> ARight[I] then Exit(False);

  Result := True;
end;

procedure TestInvalidAndEmptySizes;
var
  LValue: Byte;
begin
  LValue := $A5;
  AssertTrue(not TryFillCryptRandomBytes(LValue, -1),
    'negative size must fail');
  AssertTrue(LValue = $A5, 'negative size must not change the buffer');

  AssertTrue(TryFillCryptRandomBytes(LValue, 0),
    'zero size must succeed');
  AssertTrue(LValue = $A5, 'zero size must not change the buffer');
end;

procedure TestBufferSizes;
const
  SIZES: array[0..4] of Integer = (1, 4, 16, 257, 65536);
var
  LBuffer: TBytes;
  I: Integer;
begin
  for I := Low(SIZES) to High(SIZES) do
  begin
    SetLength(LBuffer, SIZES[I]);
    AssertTrue(TryFillCryptRandomBytes(LBuffer[0], Length(LBuffer)),
      Format('failed to fill %d random bytes', [SIZES[I]]));
  end;
end;

procedure TestSingleRange;
const
  RANGES: array[0..4] of Integer = (1, 2, 3, 10, MaxInt);
  ITERATION_COUNT = 512;
var
  LAllEqual: Boolean;
  LFirst: Integer;
  LValue: Integer;
  I, J: Integer;
begin
  LValue := 123;
  AssertTrue(not TryCryptRandom(-1, LValue),
    'negative single range must fail');
  AssertTrue(LValue = 0, 'negative single range must clear the output');

  LValue := 123;
  AssertTrue(not TryCryptRandom(0, LValue),
    'zero single range must fail');
  AssertTrue(LValue = 0, 'zero single range must clear the output');

  for I := Low(RANGES) to High(RANGES) do
    for J := 0 to ITERATION_COUNT - 1 do
    begin
      AssertTrue(TryCryptRandom(RANGES[I], LValue),
        Format('failed to generate a value below %d', [RANGES[I]]));
      AssertTrue((LValue >= 0) and (LValue < RANGES[I]),
        Format('value %d is outside [0, %d)', [LValue, RANGES[I]]));
    end;

  AssertTrue(TryCryptRandom(MaxInt, LFirst),
    'failed to generate the first bounded integer');
  LAllEqual := True;
  for I := 1 to 31 do
  begin
    AssertTrue(TryCryptRandom(MaxInt, LValue),
      'failed to generate a subsequent bounded integer');
    if LValue <> LFirst then
      LAllEqual := False;
  end;
  AssertTrue(not LAllEqual, 'all bounded integer samples are identical');
end;

procedure TestIntervalRange;
const
  ITERATION_COUNT = 512;
var
  LAllEqual: Boolean;
  LFirst: Integer;
  LValue: Integer;
  I: Integer;

  procedure CheckRange(const ARangeFrom, ARangeTo, ALower,
    AUpper: Integer);
  var
    LValue: Integer;
    I: Integer;
  begin
    for I := 0 to ITERATION_COUNT - 1 do
    begin
      AssertTrue(TryCryptRandom(ARangeFrom, ARangeTo, LValue),
        Format('failed to generate a value between %d and %d',
          [ARangeFrom, ARangeTo]));
      AssertTrue((LValue >= ALower) and (LValue < AUpper),
        Format('value %d is outside [%d, %d)',
          [LValue, ALower, AUpper]));
    end;
  end;
begin
  CheckRange(-10, 10, -10, 10);
  CheckRange(-100, -10, -100, -10);
  CheckRange(10, -10, -10, 10);
  CheckRange(Low(Integer), High(Integer), Low(Integer), High(Integer));
  CheckRange(High(Integer), Low(Integer), Low(Integer), High(Integer));
  CheckRange(Low(Integer), Low(Integer) + 1,
    Low(Integer), Low(Integer) + 1);
  CheckRange(High(Integer), High(Integer) - 1,
    High(Integer) - 1, High(Integer));

  AssertTrue(TryCryptRandom(-42, -42, LValue),
    'equal negative boundaries must succeed');
  AssertTrue(LValue = -42,
    'equal negative boundaries must return their common value');
  AssertTrue(TryCryptRandom(High(Integer), High(Integer), LValue),
    'equal maximum boundaries must succeed');
  AssertTrue(LValue = High(Integer),
    'equal maximum boundaries must return their common value');

  AssertTrue(TryCryptRandom(-1000, 1000, LFirst),
    'failed to generate the first interval integer');
  LAllEqual := True;
  for I := 1 to 31 do
  begin
    AssertTrue(TryCryptRandom(-1000, 1000, LValue),
      'failed to generate a subsequent interval integer');
    if LValue <> LFirst then
      LAllEqual := False;
  end;
  AssertTrue(not LAllEqual, 'all interval integer samples are identical');
end;

procedure TestDoubleRange;
const
  ITERATION_COUNT = 4096;
var
  LAllEqual: Boolean;
  LFirst: Double;
  LValue: Double;
  I: Integer;
begin
  AssertTrue(TryCryptRandom(LFirst),
    'failed to generate the first random double');
  AssertTrue((LFirst >= 0) and (LFirst < 1),
    'the first random double is outside [0, 1)');

  LAllEqual := True;
  for I := 1 to ITERATION_COUNT - 1 do
  begin
    AssertTrue(TryCryptRandom(LValue),
      'failed to generate a subsequent random double');
    AssertTrue((LValue >= 0) and (LValue < 1),
      'a random double is outside [0, 1)');
    if LValue <> LFirst then
      LAllEqual := False;
  end;

  AssertTrue(not LAllEqual, 'all random double samples are identical');
end;

procedure TestFreshOutputs;
const
  SAMPLE_COUNT = 16;
  SAMPLE_SIZE = 32;
var
  LFirst, LCurrent: TBytes;
  LAllEqual: Boolean;
  I: Integer;
begin
  SetLength(LFirst, SAMPLE_SIZE);
  AssertTrue(TryFillCryptRandomBytes(LFirst[0], Length(LFirst)),
    'failed to create the first random sample');

  LAllEqual := True;
  for I := 1 to SAMPLE_COUNT - 1 do
  begin
    SetLength(LCurrent, SAMPLE_SIZE);
    AssertTrue(TryFillCryptRandomBytes(LCurrent[0], Length(LCurrent)),
      'failed to create a subsequent random sample');
    if not BytesEqual(LFirst, LCurrent) then
      LAllEqual := False;
  end;

  AssertTrue(not LAllEqual, 'all random samples are identical');
end;

procedure TCryptRandomThread.Execute;
const
  ITERATION_COUNT = 256;
  BUFFER_SIZE = 32;
var
  LBuffer: array[0..BUFFER_SIZE - 1] of Byte;
  LDouble: Double;
  LInteger: Integer;
  I: Integer;
begin
  try
    for I := 0 to ITERATION_COUNT - 1 do
      if not TryFillCryptRandomBytes(LBuffer[0], SizeOf(LBuffer)) then
      begin
        FErrorMessage := Format('random generation failed at iteration %d', [I]);
        Exit;
      end;

    for I := 0 to ITERATION_COUNT - 1 do
      if not TryCryptRandom(97, LInteger) or
        (LInteger < 0) or (LInteger >= 97) then
      begin
        FErrorMessage := Format('bounded integer failed at iteration %d', [I]);
        Exit;
      end;

    for I := 0 to ITERATION_COUNT - 1 do
      if not TryCryptRandom(50, -50, LInteger) or
        (LInteger < -50) or (LInteger >= 50) then
      begin
        FErrorMessage := Format('interval integer failed at iteration %d', [I]);
        Exit;
      end;

    for I := 0 to ITERATION_COUNT - 1 do
      if not TryCryptRandom(LDouble) or
        (LDouble < 0) or (LDouble >= 1) then
      begin
        FErrorMessage := Format('random double failed at iteration %d', [I]);
        Exit;
      end;
  except
    on E: Exception do
      FErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TestConcurrentCalls;
const
  THREAD_COUNT = 8;
var
  LThreads: array[0..THREAD_COUNT - 1] of TCryptRandomThread;
  I: Integer;
begin
  for I := Low(LThreads) to High(LThreads) do
    LThreads[I] := nil;
  try
    for I := Low(LThreads) to High(LThreads) do
      LThreads[I] := TCryptRandomThread.Create(True);
    for I := Low(LThreads) to High(LThreads) do
      LThreads[I].Start;
    for I := Low(LThreads) to High(LThreads) do
      LThreads[I].WaitFor;
    for I := Low(LThreads) to High(LThreads) do
      AssertTrue(LThreads[I].ErrorMessage = '',
        Format('thread %d failed: %s', [I, LThreads[I].ErrorMessage]));
  finally
    for I := Low(LThreads) to High(LThreads) do
      LThreads[I].Free;
  end;
end;

begin
  try
    TestInvalidAndEmptySizes;
    TestBufferSizes;
    TestSingleRange;
    TestIntervalRange;
    TestDoubleRange;
    TestFreshOutputs;
    TestConcurrentCalls;
    Writeln('All cryptographic random tests passed.');
  except
    on E: Exception do
    begin
      Writeln(StdErr, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
