program CrossHttpConsole;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  uAppCfg in 'uAppCfg.pas',
  Utils.Utils,
  Net.CrossHttpServer,
  uDM in 'uDM.pas' {DM: TDataModule};

begin
  ReportMemoryLeaksOnShutdown := True;
  Writeln(TOSVersion.ToString);

  try
    with TDM.Create(nil) do
    try
      Start();
      Writeln('CrossHttpServer start at port:', AppCfg.ListenPort, ', IO threads:', HttpServer.IoThreads);
      Readln;
      Stop();
    finally
      Free;
    end;
    Writeln('CrossHttpServer quit');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
