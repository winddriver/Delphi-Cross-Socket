program TestCrossSocket;

uses
//  FastMM4,
  System.StartUpCopy,
  System.SysUtils,
  System.Classes,
  FMX.Forms,
  uMain in 'uMain.pas' {fmMain};

{$R *.res}

{$IF CompilerVersion >= 32.0}
procedure _Fuck_10_2_1_Fmx_Leak;
begin
  CheckSynchronize;
end;
{$ENDIF}

begin
  {$IF CompilerVersion >= 32.0}
  AddExitProc(_Fuck_10_2_1_Fmx_Leak);
  {$ENDIF}

  ReportMemoryLeaksOnShutdown := True;

  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
