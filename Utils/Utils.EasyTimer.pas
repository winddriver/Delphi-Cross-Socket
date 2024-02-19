unit Utils.EasyTimer;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
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
    function GetLastTick: UInt64;
    procedure SetPaused(const AValue: Boolean);

    procedure Terminate;
    procedure WaitFor;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
    property LastTick: UInt64 read GetLastTick;
  end;

  TEasyTimer = class(TInterfacedObject, IEasyTimer)
  private
    FEasyThread: IEasyThread;
    FName: string;
    FDelay, FInterval: Int64;
    FPaused: Boolean;
    FLastTick: UInt64;

    function GetName: string;
    function GetPaused: Boolean;
    function GetLastTick: UInt64;
    procedure SetPaused(const AValue: Boolean);

    class function _FullDateTime(const ADateTime: TDateTime): TDateTime; static;
  public
    constructor Create(const AName: string; const AProc: TProc;
      const ADelay, AInterval: Int64; const APaused: Boolean = False); overload;
    constructor Create(const AName: string; const AProc: TProc;
      const AInterval: Int64; const APaused: Boolean = False); overload;
    constructor Create(const AName: string; const AProc: TProc;
      const AStartTime: TDateTime; const AInterval: Int64;
      const APaused: Boolean = False); overload;
    destructor Destroy; override;

    procedure Terminate;
    procedure WaitFor;

    property Name: string read GetName;
    property Paused: Boolean read GetPaused write SetPaused;
    property LastTick: UInt64 read GetLastTick;
  end;

implementation

{ TEasyTimer }

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const ADelay, AInterval: Int64; const APaused: Boolean = False);
var
  LFirstRun: Boolean;
  LElMSec: Int64;
begin
  FName := AName;
  FDelay := ADelay;
  FInterval := AInterval;
  LFirstRun := True;
  FPaused := APaused;

  FEasyThread := TEasyThread.Create(
    procedure(const AEasyThread: IEasyThread)
    var
      LWatch: TStopwatch;
    begin
      LWatch := TStopwatch.StartNew;

      while not AEasyThread.Terminated do
      begin
        try
          if not FPaused then
          begin
            FLastTick := TThread.GetTickCount64;
            LElMSec := LWatch.ElapsedMilliseconds;

            if (LFirstRun and (LElMSec >= FDelay)) or
              (not LFirstRun and (LElMSec >= FInterval)) then
            begin
              LFirstRun := False;

              try
                if Assigned(AProc) then
                  AProc();
              finally
                LWatch.Reset;
                LWatch.Start;
              end;
            end;
          end;
        except
          on e: Exception do
          begin
            if not (e is EAbort) then
            begin
              AppendLog('执行EasyTimer[%s]出现异常: %s, %s', [
                FName, e.ClassName, e.Message
              ]);

              {$IFDEF DELPHI}
              if (e.StackTrace <> '') then
                AppendLog('异常调用堆栈:%s', [e.StackTrace]);
              {$ENDIF}
            end;
          end;
        end;

        Sleep(10);
      end;
    end);
end;

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const AInterval: Int64; const APaused: Boolean = False);
begin
  Create(AName, AProc, 0, AInterval, APaused);
end;

constructor TEasyTimer.Create(const AName: string; const AProc: TProc;
  const AStartTime: TDateTime; const AInterval: Int64;
  const APaused: Boolean = False);
begin
  Create(AName, AProc,
    _FullDateTime(AStartTime).MilliSecondsDiffer(Now),
    AInterval, APaused);
end;

destructor TEasyTimer.Destroy;
begin
  Terminate;
  WaitFor;

  inherited;
end;

function TEasyTimer.GetLastTick: UInt64;
begin
  Result := FLastTick;
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

procedure TEasyTimer.WaitFor;
begin
  FEasyThread.WaitFor;
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
