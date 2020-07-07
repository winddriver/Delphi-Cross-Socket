unit uDM;

interface

uses
  Net.CrossSslSocket,
  Net.CrossSslDemoCert,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossHttpServer,
  Net.CrossHttpMiddleware,
  Net.CrossHttpUtils;

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
    FHttpServer: ICrossHttpServer;
    FShutdown: Boolean;

    procedure _CreateRouter;
    procedure _CreateWatchThread;

    procedure _OnConnected(const Sender: TObject; const AConnection: ICrossConnection);
    procedure _OnDisconnected(const Sender: TObject; const AConnection: ICrossConnection);
  public
    procedure Start;
    procedure Stop;

    property HttpServer: ICrossHttpServer read FHttpServer;
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
  FHttpServer := TCrossHttpServer.Create(0, True);
//  {$IFDEF __CROSS_SSL__}
  if FHttpServer.SSL then
  begin
    FHttpServer.SetCertificate(SSL_SERVER_CERT);
    FHttpServer.SetPrivateKey(SSL_SERVER_PKEY);
  end;
//  {$ENDIF}
//  FHttpServer.Addr := IPv4_ALL; // IPv4
//  FHttpServer.Addr := IPv6_ALL; // IPv6
  FHttpServer.Addr := IPv4v6_ALL; // IPv4v6
  FHttpServer.Port := AppCfg.ListenPort;
  FHttpServer.Compressible := True;

  FHttpServer.OnConnected := _OnConnected;
  FHttpServer.OnDisconnected := _OnDisconnected;

  _CreateRouter;
  _CreateWatchThread;
end;

procedure TDM.DataModuleDestroy(Sender: TObject);
begin
  FHttpServer := nil;
end;

procedure TDM.Start;
begin
  FHttpServer.Start;
end;

procedure TDM.Stop;
begin
  FHttpServer.Stop;
  FShutdown := True;
  Sleep(150);
end;

procedure TDM._CreateRouter;
var
  I: Integer;
begin
//  FHttpServer.Sessions := TSessions.Create;

//  FHttpServer
//  .Use('/login', TNetCrossMiddleware.AuthenticateDigest(
//    procedure(ARequest: ICrossHttpRequest; const AUserName: string; var ACorrectPassword: string)
//    begin
//      if (AUserName = 'root') then
//        ACorrectPassword := 'root';
//    end,
//    '/login'))
//  .Get('/login',
//    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse; var AHandled: Boolean)
//    begin
//      AResponse.Send('Login Success!');
//    end)
//  .Use('/hello', TNetCrossMiddleware.AuthenticateBasic(
//    procedure(ARequest: ICrossHttpRequest; const AUserName: string; var ACorrectPassword: string)
//    begin
//      if (AUserName = 'root') then
//        ACorrectPassword := 'root';
//    end,
//    '/hello'))
//  .Get('/hello',
//    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse; var AHandled: Boolean)
//    begin
//      AHandled := False;
//      AResponse.Send('Hello World111');
//    end)
//  .Get('/hello',
//    procedure(ARequest: ICrossHttpRequest; AResponse: ICrossHttpResponse; var AHandled: Boolean)
//    begin
//      AHandled := False;
//      AResponse.Send('Hello World222');
//    end)
  ;

  FHttpServer
  .Get('/hello',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    begin
      AResponse.Send('Hello World');
    end)
  .Get('/null',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    begin
      AResponse.Send('');
    end)
  .Get('/yeah',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    begin
      AResponse.Send(TUtils.RandomStr(
        'abcdefghijklmnopqrstuvwxyz',
        256 * 1024));
    end)
  .Get('/progress/:id(\d+)',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
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
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
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
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
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
  .Dir('/static', 'D:\')
  .Dir('/g', 'G:\')
  .Get('/file',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    var
      LStream: TStream;
    begin
      LStream := TFile.OpenRead('d:\2.txt');
      AResponse.ContentType := TMediaType.TEXT_HTML;
      AResponse.SendNoCompress(LStream,
        StrToInt64Def(ARequest.Query['pos'], 0),
        StrToInt64Def(ARequest.Query['count'], 0),
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          FreeAndNil(LStream);
        end);
    end)
  .Get('/stream',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    var
      LStream: TMemoryStream;
    begin
      LStream := TMemoryStream.Create;
      LStream.LoadFromFile('d:\2.txt');
      AResponse.ContentType := TMediaType.TEXT_HTML;
      AResponse.SendZCompress(LStream,
        StrToInt64Def(ARequest.Query['pos'], 0),
        StrToInt64Def(ARequest.Query['count'], 0),
        TCompressType.ctGZip,
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          FreeAndNil(LStream);
        end);
    end)
  .Get('/bytes',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    var
      LBytes: TBytes;
    begin
      LBytes := TFile.ReadAllBytes('d:\2.txt');
      AResponse.ContentType := TMediaType.TEXT_HTML;
      AResponse.SendNoCompress(LBytes,
        StrToInt64Def(ARequest.Query['pos'], 0),
        StrToInt64Def(ARequest.Query['count'], 0),
        procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
        begin
          LBytes := nil;
        end);
    end)
  .Post('/post',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse)
    var
      LResult: string;
    begin
      case ARequest.BodyType of
        btNone:
          LResult := 'Body是空的';

        btUrlEncoded:
          LResult := 'Body第一个参数是: ' + (ARequest.Body as THttpUrlParams).Items[0].Name + '=' + (ARequest.Body as THttpUrlParams).Items[0].Value;

        btMultiPart:
          LResult := 'Body第一个参数是: ' + (ARequest.Body as THttpMultiPartFormData).Items[0].Name + '=' + (ARequest.Body as THttpMultiPartFormData).Items[0].AsString;

        btBinary:
          LResult := 'Body是二进制数据';
      end;

      AResponse.Send(LResult);
    end)
    ;

  for I := 0 to AppCfg.DirMaps.Count - 1 do
  begin
    FHttpServer.Dir(
      AppCfg.DirMaps.Names[I],
      AppCfg.DirMaps.ValueFromIndex[I]);
  end;
end;

procedure TDM._CreateWatchThread;
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      LLastConCount, LCurConCount: Integer;
    begin
      LLastConCount := 0;
      while not FShutdown do
      begin
        LCurConCount := FHttpServer.ConnectionsCount;
        if (LCurConCount <> LLastConCount) then
        begin
          LLastConCount := LCurConCount;
          Writeln('conn count:', LCurConCount);
        end;
        Sleep(100);
      end;
    end).Start;
end;

procedure TDM._OnConnected(const Sender: TObject; const AConnection: ICrossConnection);
begin
//  if (FHttpServer.ConnectionsCount > 100) then
//    AConnection.Close;
end;

procedure TDM._OnDisconnected(const Sender: TObject; const AConnection: ICrossConnection);
begin
end;

end.
