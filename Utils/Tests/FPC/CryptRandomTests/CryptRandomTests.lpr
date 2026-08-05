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
  I: Integer;
begin
  try
    for I := 0 to ITERATION_COUNT - 1 do
      if not TryFillCryptRandomBytes(LBuffer[0], SizeOf(LBuffer)) then
      begin
        FErrorMessage := Format('random generation failed at iteration %d', [I]);
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
