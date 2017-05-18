program TestCrossSocket;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'uMain.pas' {fmMain};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;

  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
