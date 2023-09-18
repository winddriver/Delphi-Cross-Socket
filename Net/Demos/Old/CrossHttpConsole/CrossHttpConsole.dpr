program CrossHttpConsole;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  uAppCfg in 'uAppCfg.pas',
  Utils.Utils,
  uDM in 'uDM.pas' {DM: TDataModule};

const
  APP_NAME = {$IFDEF __CROSS_SSL__}'CrossHttpServer(SSL)'{$ELSE}'CrossHttpServer'{$ENDIF};

begin
  ReportMemoryLeaksOnShutdown := True;
  Writeln(TOSVersion.ToString);

  try
    with TDM.Create(nil) do
    try
      Start();
      Writeln(APP_NAME, ' start at port:', HttpServer.Port, ', IO threads:', HttpServer.IoThreads);
      Writeln('Press enter stop');
      Readln;
      Stop();
      Writeln(APP_NAME, ' stop');
      Writeln('Press enter quit');
      Readln;
    finally
      Free;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
