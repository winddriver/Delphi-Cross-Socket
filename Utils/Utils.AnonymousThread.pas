unit Utils.AnonymousThread;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes;

type
  TAnonymousProc = reference to procedure;

  TAnonymousThread = class(TThread)
  private
    FProc: TAnonymousProc;
  protected
    procedure Execute; override;
  public
    constructor Create(AProc: TAnonymousProc);
  end;

implementation

{ TAnonymousThread }

constructor TAnonymousThread.Create(AProc: TAnonymousProc);
begin
  inherited Create(True);

  FreeOnTerminate := True;
  FProc := AProc;
end;

procedure TAnonymousThread.Execute;
begin
  if Assigned(FProc) then
    FProc();
end;

end.
