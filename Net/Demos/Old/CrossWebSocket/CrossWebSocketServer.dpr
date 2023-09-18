program CrossWebSocketServer;

uses
  System.StartUpCopy,
  FMX.Forms,
  uCrossWebSocketServerDemo in 'uCrossWebSocketServerDemo.pas' {fmCrossWebSocketServerDemo};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfmCrossWebSocketServerDemo, fmCrossWebSocketServerDemo);
  Application.Run;
end.
