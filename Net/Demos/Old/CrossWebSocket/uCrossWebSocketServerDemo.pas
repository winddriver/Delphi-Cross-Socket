unit uCrossWebSocketServerDemo;

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Variants,
  System.IOUtils,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.Controls.Presentation,
  FMX.StdCtrls,
  FMX.ScrollBox,
  FMX.Memo,
  Net.CrossSocket.Base,
  Net.CrossHttpServer,
  Net.CrossWebSocketServer;

type
  TfmCrossWebSocketServerDemo = class(TForm)
    btnStart: TButton;
    btnClose: TButton;
    btnBroadcast: TButton;
    Memo1: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnBroadcastClick(Sender: TObject);
  private
    FServer: ICrossWebSocketServer;

    procedure _ForEach(AProc: TProc<ICrossWebSocketConnection>);
    procedure _ProcChatMessage(AConnection: ICrossWebSocketConnection;
      const AChatMessage: string);
  public
    procedure AddLog(const S: string); overload;
    procedure AddLog(const Fmt: string; const Args: array of const); overload;
  end;

var
  fmCrossWebSocketServerDemo: TfmCrossWebSocketServerDemo;

implementation

uses
  Utils.Utils;

{$R *.fmx}

procedure TfmCrossWebSocketServerDemo.AddLog(const Fmt: string; const Args: array of const);
begin
  AddLog(Format(Fmt, Args));
end;

procedure TfmCrossWebSocketServerDemo.AddLog(const S: string);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      Memo1.Lines.Add(FormatDateTime('HH:NN:SS:ZZZ', Now) + ' ' + S);
      Memo1.GoToTextEnd;
    end);
end;

procedure TfmCrossWebSocketServerDemo.btnStartClick(Sender: TObject);
begin
  if (btnStart.Tag = 0) then
  begin
    FServer.Addr := '0.0.0.0';
    FServer.Port := 12345;
    FServer.Start();

    btnStart.Tag := 1;
    btnStart.Text := 'Stop';
  end else
  begin
    FServer.Stop();

    btnStart.Tag := 0;
    btnStart.Text := 'Start';
  end;
end;

procedure TfmCrossWebSocketServerDemo.btnBroadcastClick(Sender: TObject);
begin
  _ForEach(
    procedure(AConnection: ICrossWebSocketConnection)
    begin
      AConnection.WsSend('Hello, I''m CrossWebSocketServer!');
    end);
end;

procedure TfmCrossWebSocketServerDemo.btnCloseClick(Sender: TObject);
begin
  _ForEach(
    procedure(AConnection: ICrossWebSocketConnection)
    begin
      AConnection.WsClose;
    end);
end;

procedure TfmCrossWebSocketServerDemo.FormCreate(Sender: TObject);
begin
  FServer := TNetCrossWebSocketServer.Create(0, False);
  if FServer.Ssl then
  begin
    FServer.SetCertificateFile('server.crt');
    FServer.SetPrivateKeyFile('server.key');
  end;

  // 绑定WebSocket事件
  FServer
  .OnOpen(
    procedure(const AConnection: ICrossWebSocketConnection)
    begin
      AddLog('OnOpen [%s:%d]%s',
        [AConnection.PeerAddr, AConnection.PeerPort,
         AConnection.Request.Path]);
    end)
  .OnMessage(
    procedure(const AConnection: ICrossWebSocketConnection;
      const ARequestType: TWsRequestType; const ARequestData: TBytes)
    var
      LMessage: string;
    begin
      LMessage := TEncoding.UTF8.GetString(ARequestData);

      _ProcChatMessage(AConnection, Format('[%s:%d]%s',
        [AConnection.PeerAddr, AConnection.PeerPort, LMessage]));

      AddLog('OnMessage [%s:%d]%s : %s',
        [AConnection.PeerAddr, AConnection.PeerPort,
         AConnection.Request.Path,
         LMessage]);
    end)
  .OnClose(
    procedure(const AConnection: ICrossWebSocketConnection)
    begin
      AddLog('OnClose [%s:%d]%s',
        [AConnection.PeerAddr, AConnection.PeerPort,
         AConnection.Request.Path]);
    end)
  ;

  // 同时可以处理普通的HTTP请求
  // 在浏览器中访问 http://localhost:12345/index.html 进行测试
  FServer
  .Dir('/', TPath.Combine(TUtils.AppPath, '../../web'))
  ;
  FServer.Get('/hello',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AResponse.Send('OK');
      AHandled := True;
    end);

end;

procedure TfmCrossWebSocketServerDemo.FormDestroy(Sender: TObject);
begin
  FServer.Stop;
  FServer := nil;
end;

procedure TfmCrossWebSocketServerDemo._ForEach(AProc: TProc<ICrossWebSocketConnection>);
var
  LConnections: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  LConnections := FServer.LockConnections.Values.ToArray;
  FServer.UnlockConnections;

  for LConnection in LConnections do
  begin
    if Assigned(AProc) then
      AProc(LConnection as ICrossWebSocketConnection);
  end;
end;

procedure TfmCrossWebSocketServerDemo._ProcChatMessage(AConnection: ICrossWebSocketConnection;
  const AChatMessage: string);
begin
  _ForEach(
    procedure(AConnection: ICrossWebSocketConnection)
    begin
      AConnection.WsSend(AChatMessage);
    end);
end;

end.
