unit ProxyClientGui.Main;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.StdCtrls,
  FMX.Edit,
  FMX.ListBox,
  FMX.Memo,
  FMX.Layouts,
  Net.SocketAPI,
  Net.Winsock2,
  Net.CrossProxy,
  Net.CrossHttpClient,
  Net.CrossHttpParams,
  Net.CrossWebSocketClient,
  Net.CrossWebSocketParser,
  Utils.Utils,
  ProxyDns,
  ProxyUdp,
  FMX.Memo.Types,
  FMX.ScrollBox,
  FMX.Controls.Presentation;

type
  TProxyMainForm = class(TForm)
    ProxyType: TComboBox;
    ProxyHost: TEdit;
    ProxyPort: TEdit;
    ProxyUser: TEdit;
    ProxyPassword: TEdit;
    UseAuth: TCheckBox;
    GoogleButton: TButton;
    DnsDirectButton: TButton;
    DnsProxyButton: TButton;
    UdpDnsButton: TButton;
    ResolveButton: TButton;
    WsDirectButton: TButton;
    WsProxyButton: TButton;
    LogMemo: TMemo;
    EdtWS: TEdit;
    Label1: TLabel;
    procedure HttpClick(Sender: TObject);
    procedure DohDirectClick(Sender: TObject);
    procedure DohProxyClick(Sender: TObject);
    procedure UdpDnsClick(Sender: TObject);
    procedure ResolveClick(Sender: TObject);
    procedure WsDirectClick(Sender: TObject);
    procedure WsProxyClick(Sender: TObject);
    procedure AuthClick(Sender: TObject);
  private
    FWebSocket: ICrossWebSocket;
    function Settings: TCrossProxySettings;
    function ProxyLabel(const AUseProxy: Boolean): string;
    procedure Log(const AText: string);
    procedure Request(const AUrl: string; const AProxy: Boolean);
    procedure ResolveDns(const AProxy: Boolean);
    procedure ToggleProxyAddress;
    procedure WebSocket(const AProxy: Boolean);
  end;

var
  ProxyMainForm: TProxyMainForm;

implementation

{$R *.fmx}

procedure TProxyMainForm.AuthClick(Sender: TObject);
begin
  if UseAuth.IsChecked then begin
    ProxyPort.Text := '10810'; ProxyUser.Text := 'demo'; ProxyPassword.Text := 'demo123';
  end else begin
    ProxyPort.Text := '10808'; ProxyUser.Text := 'user'; ProxyPassword.Text := '';
  end;
  Log('Use Auth ' + IfThen(UseAuth.IsChecked, 'enabled', 'disabled') +
    ': ' + ProxyHost.Text + ':' + ProxyPort.Text);
end;

function TProxyMainForm.Settings: TCrossProxySettings;
var
  LType: TCrossProxyType;
begin
  LType := cptDirect;
  if SameText(ProxyType.Text, 'http') then
    LType := cptHttp;
  if SameText(ProxyType.Text, 'https') then
    LType := cptHttps;
  if SameText(ProxyType.Text, 'socks4') then
    LType := cptSocks4;
  if SameText(ProxyType.Text, 'socks5') then
    LType := cptSocks5;
  Result :=
      TCrossProxySettings
          .Create(LType, ProxyHost.Text, StrToIntDef(ProxyPort.Text, 0), ProxyUser.Text, ProxyPassword.Text);
end;

function TProxyMainForm.ProxyLabel(const AUseProxy: Boolean): string;
begin
  if not AUseProxy then
    Exit('direct');
  case Settings.ProxyType of
    cptHttp: Exit('via proxy http');
    cptHttps: Exit('via proxy https');
    cptSocks4: Exit('via proxy socks4');
    cptSocks5: Exit('via proxy socks5');
  else
    Exit('direct');
  end;
end;

procedure TProxyMainForm.Log(const AText: string);
begin
  TThread.Queue(nil, procedure begin LogMemo.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' ' + AText); end);
end;

procedure TProxyMainForm.Request(const AUrl: string; const AProxy: Boolean);
var
  LClient: ICrossHttpClient;
begin
  LClient := TCrossHttpClient.Create;
  if AProxy then
    LClient.ProxySettings := Settings;
  LClient.VerifyPeer := False;
  Log('HTTP ' + AUrl + ' ' + ProxyLabel(AProxy));
  LClient.DoRequest(
      'GET',
      AUrl,
      THttpHeader(nil),
      Pointer(nil),
      0,
      TStream(nil),
      procedure(const ARequest: ICrossHttpClientRequest) begin end,
      procedure(const AResponse: ICrossHttpClientResponse)
      begin
        // Keep the asynchronous client alive until the response callback runs.
        if LClient = nil then
          Exit;
        if AResponse = nil then
          Log('HTTP FAILED: no response')
        else if AResponse.Content = nil then
          // StatusText 包含 Cross Socket 返回的代理认证或 CONNECT 失败原因。
          Log(Format('HTTP FAILED: %d %s', [AResponse.StatusCode, AResponse.StatusText]))
        else
          Log(Format('HTTP %d %s, %d bytes', [AResponse.StatusCode, AResponse.StatusText, AResponse.Content.Size]));
      end
  );
end;

procedure TProxyMainForm.ResolveDns(const AProxy: Boolean);
var
  LSettings: TCrossProxySettings;
  LServer, LIP, LIPv6: string;
begin
  LSettings := TCrossProxySettings.Direct;
  LServer := DNS_DIRECT_SERVER;
  if AProxy then begin
    LSettings := Settings;
    LServer := DNS_PROXY_SERVER;
  end;
  Log('DNS apple.com ' + ProxyLabel(AProxy) + ' server ' + LServer + ':53');
  try
    LIP := QueryDnsA(LServer, LSettings);
    LIPv6 := QueryDnsAAAA(LServer, LSettings);
    Log('DNS A apple.com -> ' + LIP);
    Log('DNS AAAA apple.com -> ' + LIPv6);
  except
    on E: Exception do
      Log('DNS FAILED: ' + E.Message);
  end;
end;

procedure TProxyMainForm.ToggleProxyAddress;
begin
  if SameText(ProxyHost.Text, '127.0.0.1') then
    ProxyHost.Text := '::1'
  else
    ProxyHost.Text := '127.0.0.1';
  Log(
      'Proxy address switched to '
          + ProxyHost.Text
          + ':'
          + ProxyPort.Text
          + ' ('
          + IfThen(ProxyHost.Text = '::1', 'IPv6', 'IPv4')
          + ')'
  );
end;

procedure TProxyMainForm.WebSocket(const AProxy: Boolean);
var
  LManager: TCrossWebSocketMgr;
begin
  LManager := TCrossWebSocketMgr.Create;
  if AProxy then
    LManager.ProxySettings := Settings;
  FWebSocket := LManager.CreateWebSocket(EdtWS.Text);
  FWebSocket.OnOpen(
      procedure
      begin
        Log('WebSocket OPEN ' + ProxyLabel(AProxy));
        FWebSocket.Send('proxy demo ping');
      end
  );
  FWebSocket.OnMessage(
      procedure(const AType: TWsMessageType; const AData: TBytes)
      begin
        Log('WebSocket MESSAGE: ' + TUtils.GetString(AData));
      end
  );
  FWebSocket.OnClose(procedure begin Log('WebSocket CLOSE'); end);
  FWebSocket.Open;
end;

procedure TProxyMainForm.HttpClick(Sender: TObject);
begin
  Request('https://www.google.com/', True);
end;
procedure TProxyMainForm.DohDirectClick(Sender: TObject);
begin
  ResolveDns(False);
end;
procedure TProxyMainForm.DohProxyClick(Sender: TObject);
begin
  ResolveDns(True);
end;
procedure TProxyMainForm.UdpDnsClick(Sender: TObject);
var
  LSettings: TCrossProxySettings;
begin
  if SameText(ProxyType.Text, 'direct') then
    LSettings := TCrossProxySettings.Direct
  else
    LSettings := Settings;
  if SameText(ProxyType.Text, 'direct') then
    Log('UDP DNS direct server ' + UDP_DIRECT_DNS_SERVER + ':53')
  else
    Log('UDP DNS ' + ProxyLabel(True) + ' proxy ' + ProxyHost.Text + ':' + ProxyPort.Text + ' target ' + UDP_PROXY_DNS_SERVER + ':53');
  TThread.CreateAnonymousThread(
    procedure
    var LResult: string;
    begin
      try LResult := TestUdpDns(LSettings, UseAuth.IsChecked); except on E: Exception do LResult := 'UDP DNS FAILED: ' + E.Message; end;
      Log(LResult);
    end).Start;
end;
procedure TProxyMainForm.ResolveClick(Sender: TObject);
begin
  ToggleProxyAddress;
end;
procedure TProxyMainForm.WsDirectClick(Sender: TObject);
begin
  WebSocket(False);
end;
procedure TProxyMainForm.WsProxyClick(Sender: TObject);
begin
  WebSocket(True);
end;

end.
