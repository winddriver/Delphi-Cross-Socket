unit Utils.EasyTimer;

{$I zLib.inc}

interface

uses
  SysUtils,
  {$IFDEF DELPHI}
  Diagnostics,
  {$ELSE}
  DTF.Types,
  DTF.Diagnostics,
  {$ENDIF}

  Utils.EasyThread,
  Utils.DateTime,
  Utils.Logger;

type
  IEasyTimer = interface
  ['{3AA98783-0800-4C4E-AA3F-037FC5307196}']
    function GetName: string;
    function GetPaused: Boolean;
    procedure SetPaused(const AValue: Boolean);

    procedure Terminate;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
  end;

  TEasyTimer = class(TInterfacedObject, IEasyTimer)
  private
    FEasyThread: IEasyThread;
    FName: string;
    FDelay: Integer;
    FInterval: Integer;
    FPaused: Boolean;

    function GetName: string;
    function GetPaused: Boolean;
    procedure SetPaused(const AValue: Boolean);

    class function _FullDateTime(const ADateTime: TDateTime): TDateTime; static;
  public
    constructor Create(const AName: string; const AProc: TProc;
      const ADelay, AInterval: Integer); overload;
    constructor Create(const AName: string; const AProc: TProc;
      const AInterval: Integer); overload;
    constructor Create(const AName: string; const AProc: TProc;
      const AStartTime: TDateTime; const AInterval: Integer); overload;
    destructor Destroy; override;

    procedure Terminate;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
  end;

implementation

{ TEasyTimer }

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const ADelay, AInterval: Integer);
var
  LFirstRun: Boolean;
  LElMSec: Int64;
begin
  FName := AName;
  FDelay := ADelay;
  FInterval := AInterval;
  LFirstRun := True;

  FEasyThread := TEasyThread.Create(
    procedure(const AEasyThread: IEasyThread)
    var
      LWatch: TStopwatch;
    begin
      LWatch := TStopwatch.StartNew;

      while not AEasyThread.Terminated do
      begin
        if not FPaused then
        begin
          LElMSec := LWatch.ElapsedMilliseconds;

          if (LFirstRun and (LElMSec >= FDelay)) or
            (not LFirstRun and (LElMSec >= FInterval)) then
          begin
            try
              LFirstRun := False;

              if Assigned(AProc) then
                AProc();
            except
              on e: Exception do
              begin
                if not (e is EAbort) then
                begin
                  AppendLog('执行EasyTimer[%s]出现异常: %s, %s', [
                    FName, e.ClassName, e.Message
                  ]);

                  {$IFDEF madExcept}
                  AppendLog('异常调用堆栈:%s', [e.StackTrace]);
                  {$ENDIF}
                end;
              end;
            end;

            LWatch.Reset;
            LWatch.Start;
          end;
        end;

        Sleep(10);
      end;
    end);
end;

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const AInterval: Integer);
begin
  Create(AName, AProc, 0, AInterval);
end;

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const AStartTime: TDateTime; const AInterval: Integer);
begin
  Create(AName, AProc,  _FullDateTime(AStartTime).MilliSecondsDiffer(Now), AInterval);
end;

destructor TEasyTimer.Destroy;
begin
  FEasyThread.Terminate;
  FEasyThread.WaitFor;

  inherited;
end;

function TEasyTimer.GetName: string;
begin
  Result := FName;
end;

function TEasyTimer.GetPaused: Boolean;
begin
  Result := FPaused;
end;

procedure TEasyTimer.SetPaused(const AValue: Boolean);
begin
  FPaused := AValue;
end;

procedure TEasyTimer.Terminate;
begin
  FEasyThread.Terminate;
end;

class function TEasyTimer._FullDateTime(const ADateTime: TDateTime): TDateTime;
begin
  if (Trunc(ADateTime) > 0) then
    Result := ADateTime
  else
  begin
    Result := Trunc(Now) + Frac(ADateTime);
    if (Now > Result) then
      Result := Result.AddDays(1);
  end;
end;

end.
