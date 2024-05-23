unit Utils.SimpleWatch;

{$I zLib.inc}

interface

uses
  SysUtils,
  Utils.DateTime;

type
  TSimpleWatch = record
  private
    FLastTime: TDateTime;
  public
    class function Create: TSimpleWatch; static;

    procedure Reset;
    function ElapsedMilliseconds: Int64;

    property LastTime: TDateTime read FLastTime;
  end;

implementation

{ TSimpleWatch }

class function TSimpleWatch.Create: TSimpleWatch;
begin
  Result.Reset;
end;

function TSimpleWatch.ElapsedMilliseconds: Int64;
begin
  Result := Now.MilliSecondsDiffer(FLastTime);
end;

procedure TSimpleWatch.Reset;
begin
  FLastTime := Now;
end;

end.
