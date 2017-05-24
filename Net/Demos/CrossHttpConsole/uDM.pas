unit uDM;

interface

uses
  {$IFDEF __CROSS_SSL__}
  Net.CrossSslSocket,
  {$IFDEF POSIX}
  Net.CrossSslDemoCert,
  {$ENDIF}
  {$ENDIF}
  System.SysUtils, System.Classes, System.Generics.Collections,
  Net.CrossSocket, Net.CrossHttpServer, Net.CrossHttpMiddleware;

type
  IProgress = interface
  ['{7372CE20-BBC7-4F35-932B-E148B52D89B1}']
    function GetID: Int64;
    function GetMax: Single;
    function GetPosition: Single;
    function GetTimestamp: TDateTime;

    procedure SetMax(const AValue: Single);
    procedure SetPosition(const AValue: Single);

    function ToString: string;

    property ID: Int64 read GetID;
    property Max: Single read GetMax write SetMax;
    property Position: Single read GetPosition write SetPosition;
    property Timestamp: TDateTime read GetTimestamp;
  end;

  TProgress = class(TInterfacedObject, IProgress)
  private class var
    FGlobalProgressID: Int64;
    FGlobalProgress: TDictionary<Int64, IProgress>;
  private
    class constructor Create;
    class destructor Destroy;
  private
    FID: Int64;
    FMax: Single;
    FPosition: Single;
    FTimestamp: TDateTime;

    function GetID: Int64;
    function GetMax: Single;
    function GetPosition: Single;
    function GetTimestamp: TDateTime;

    procedure SetMax(const AValue: Single);
    procedure SetPosition(const AValue: Single);
  public
    constructor Create;

    function ToString: string; override;

    class function New: IProgress;
    class function Get(const AID: Int64): IProgress;
    class function Remove(const AID: Int64): Boolean;

    property ID: Int64 read GetID;
    property Max: Single read GetMax write SetMax;
    property Position: Single read GetPosition write SetPosition;
    property Timestamp: TDateTime read GetTimestamp;
  end;

  TDM = class(TDataModule)
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
    FHttpServer: TCrossHttpServer;
    FConnCount: Integer;

    procedure _CreateRouter;

    procedure _OnConnected(Sender: TObject; AConnection: ICrossConnection);
    procedure _OnDisconnected(Sender: TObject; AConnection: ICrossConnection);
  public
    procedure Start;
    procedure Stop;

    property HttpServer: TCrossHttpServer read FHttpServer;
  end;

var
  DM: TDM;

implementation

uses
  System.Hash,
  Net.CrossHttpParams, System.Diagnostics, System.IOUtils,
  System.RegularExpressions, Utils.RegEx, System.Threading, System.Math,
  System.NetEncoding, Utils.Logger, Utils.Utils, uAppCfg;

{%CLASSGROUP 'Vcl.Controls.TControl'}

{$R *.dfm}

{ TProgress }

constructor TProgress.Create;
begin
  FID := AtomicIncrement(FGlobalProgressID);
end;

class constructor TProgress.Create;
begin
  FGlobalProgress := TDictionary<Int64, IProgress>.Create;
end;

class destructor TProgress.Destroy;
begin
  FreeAndNil(FGlobalProgress);
end;

class function TProgress.Get(const AID: Int64): IProgress;
begin
  TMonitor.Enter(FGlobalProgress);
  try
    FGlobalProgress.TryGetValue(AID, Result);
  finally
    TMonitor.Exit(FGlobalProgress);
  end;
end;

function TProgress.GetID: Int64;
begin
  Result := FID;
end;

function TProgress.GetMax: Single;
begin
  Result := FMax;
end;

function TProgress.GetTimestamp: TDateTime;
begin
  Result := FTimestamp;
end;

class function TProgress.New: IProgress;
begin
  Result := TProgress.Create;

  TMonitor.Enter(FGlobalProgress);
  try
    FGlobalProgress.AddOrSetValue(Result.ID, Result);
  finally
    TMonitor.Exit(FGlobalProgress);
  end;
end;

class function TProgress.Remove(const AID: Int64): Boolean;
begin
  TMonitor.Enter(FGlobalProgress);
  try
    Result := FGlobalProgress.ContainsKey(AID);
    if Result then
      FGlobalProgress.Remove(AID);
  finally
    TMonitor.Exit(FGlobalProgress);
  end;
end;

function TProgress.GetPosition: Single;
begin
  Result := FPosition;
end;

procedure TProgress.SetMax(const AValue: Single);
begin
  FMax := AValue;
end;

procedure TProgress.SetPosition(const AValue: Single);
begin
  if (AValue <= FMax) then
    FPosition := AValue
  else
    FPosition := FMax;
  FTimestamp := Now;
end;

function TProgress.ToString: string;
begin
  Result := Format('{"id":%d,"position":%f,"max":%f,"time":"%s"}',
    [
      FID,
      FPosition,
      FMax,
      FormatDateTime('YYYY-MM-DD HH:NN:SS:ZZZ', FTimestamp)
    ]);
end;

procedure TDM.DataModuleCreate(Sender: TObject);
begin
  FConnCount := 0;

  FHttpServer := TCrossHttpServer.Create(0);
  {$IFDEF __CROSS_SSL__}
  {$IFDEF POSIX}
  FHttpServer.SetCertificate(SSL_SERVER_CERT);
  FHttpServer.SetPrivateKey(SSL_SERVER_PKEY);
  {$ELSE}
  FHttpServer.SetCertificateFile('server.crt');
  FHttpServer.SetPrivateKeyFile('server.key');
  {$ENDIF}
  {$ENDIF}
  FHttpServer.Addr := '0.0.0.0'; // IPv4
  FHttpServer.Port := AppCfg.ListenPort;
  FHttpServer.Compressible := False;

  FHttpServer.OnConnected := _OnConnected;
  FHttpServer.OnDisconnected := _OnDisconnected;

  _CreateRouter;
end;

procedure TDM.DataModuleDestroy(Sender: TObject);
begin
  FreeAndNil(FHttpServer);
end;

procedure TDM.Start;
begin
  FHttpServer.Start;
end;

procedure TDM.Stop;
begin
  FHttpServer.Stop;
end;

procedure TDM._CreateRouter;
var
  I: Integer;
begin
//  FHttpServer.Sessions := TSessions.Create;

  FHttpServer
  .Use('/login', TNetCrossMiddleware.AuthenticateDigest(
    procedure(ARequest: ICrossHttpRequest; const AUserName: string; var ACorrectPassword: string)
    begin
      if (AUserName = 'root') then
        ACorrectPassword := 'root';
    end,
    '/login'))
  .Get('/login',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AResponse.Send('Login Success!');
    end)
  .Use('/hello', TNetCrossMiddleware.AuthenticateBasic(
    procedure(ARequest: ICrossHttpRequest; const AUserName: string; var ACorrectPassword: string)
    begin
      if (AUserName = 'root') then
        ACorrectPassword := 'root';
    end,
    '/hello'))
  .Get('/hello',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AHandled := False;
      AResponse.Send('Hello World111');
    end)
  .Get('/hello',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      AHandled := False;
      AResponse.Send('Hello World222');
    end)
  ;

  FHttpServer
  .Get('/hello',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
    begin
      AResponse.Send('Hello World');
    end)
  .Get('/yeah',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
    begin
      AResponse.Send(TUtils.RandomStr(
        'abcdefghijklmnopqrstuvwxyz',
        256 * 1024));
    end)
  .Get('/progress/:id(\d+)',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
    var
      LProgID: Int64;
      LProg: IProgress;
    begin
      LProgID := ARequest.Params['id'].ToInt64;
      LProg := TProgress.Get(LProgID);

      if (LProg <> nil) then
        AResponse.Json(LProg.ToString)
      else
        AResponse.Send('非法id');
    end)
  .Delete('/progress/:id(\d+)',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
    var
      LProgID: Int64;
    begin
      LProgID := ARequest.Params['id'].ToInt64;

      if TProgress.Remove(LProgID) then
        AResponse.Send('删除任务进度成功')
      else
        AResponse.Send('非法id');
    end)
  .Get('task',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
    begin
      TTask.Run(
        procedure
        var
          I: Integer;
          LWatch: TStopwatch;
          LSeconds: Integer;
          LProg: IProgress;
        begin
          LProg := TProgress.New;
          LProg.Max := 10;
          LProg.Position := 0;

          AResponse.Json(LProg.ToString);

          LWatch := TStopwatch.StartNew;
          for I := 1 to 10 do
          begin
            LSeconds := RandomRange(1, 10 + 1);
            Sleep(LSeconds * 500);

            LProg.Position := I;
          end;
          LWatch.Stop;
        end);
    end)
  .Get('/code',
    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse)
    begin
      AResponse.SendStatus(600, '无法获取对象池中的对象(HttpRequestDB)');
    end)
    ;

  for I := 0 to AppCfg.DirMaps.Count - 1 do
  begin
    FHttpServer.Dir(
      AppCfg.DirMaps.Names[I],
      AppCfg.DirMaps.ValueFromIndex[I]);
  end;
end;

procedure TDM._OnConnected(Sender: TObject; AConnection: ICrossConnection);
begin
  Writeln('conn count:', AtomicIncrement(FConnCount));
end;

procedure TDM._OnDisconnected(Sender: TObject; AConnection: ICrossConnection);
begin
  Writeln('conn count:', AtomicDecrement(FConnCount));
end;

end.
