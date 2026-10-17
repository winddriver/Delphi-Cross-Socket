program ProxyClientGui;
uses
  System.StartUpCopy,
  FMX.Forms,
  ProxyClientGui.Main in 'ProxyClientGui.Main.pas' {ProxyMainForm},
  ProxyDns in 'ProxyDns.pas',
  ProxyUdp in 'ProxyUdp.pas';

{$R *.res}
begin
  Application.Initialize;
  Application.CreateForm(TProxyMainForm, ProxyMainForm);
  Application.Run;
end.
