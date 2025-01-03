unit Utils.SimpleWatch;

{$I zLib.inc}

interface

uses
  SysUtils,
  Utils.DateTime;

type
  TSimpleWatch = record
  private
    FStartTime: TDateTime;
    FRunning: Boolean;
    FElapsed: Int64;
  public
    class function Create: TSimpleWatch; static;

    procedure Reset;
    procedure Start;
    procedure Stop;

    function ElapsedMilliseconds: Int64;

    property LastTime: TDateTime read FStartTime;
  end;

implementation

{ TSimpleWatch }

class function TSimpleWatch.Create: TSimpleWatch;
begin
  Result.Reset;
end;

function TSimpleWatch.ElapsedMilliseconds: Int64;
begin
  Result := FElapsed;

  if FRunning then
    Result := Result + Now.MilliSecondsDiffer(FStartTime);
end;

procedure TSimpleWatch.Reset;
begin
  FElapsed := 0;
  FStartTime := Now;
  Start;
end;

procedure TSimpleWatch.Start;
begin
  FRunning := True;
end;

procedure TSimpleWatch.Stop;
begin
  if FRunning then
  begin
    FRunning := False;
    FElapsed := FElapsed + Now.MilliSecondsDiffer(FStartTime);
  end;
end;

end.
