{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossServer;

{$I zLib.inc}

interface

uses
  SysUtils,

  Net.SocketAPI,
  Net.CrossSocket.Base,
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket;

type
  ICrossServerConnection = interface(ICrossSslConnection)
  ['{D25E96A4-57DC-40B1-B35B-C35550A29F62}']
  end;

  ICrossServer = interface(ICrossSslSocket)
  ['{DAEB2898-1EC4-4BCF-9BEB-078B582173AB}']
    function GetAddr: string;
    function GetPort: Word;
    function GetActive: Boolean;

    procedure SetAddr(const Value: string);
    procedure SetPort(const Value: Word);
    procedure SetActive(const Value: Boolean);

    procedure Start(const ACallback: TCrossListenCallback = nil);
    procedure Stop;

    property Addr: string read GetAddr write SetAddr;
    property Port: Word read GetPort write SetPort;

    property Active: Boolean read GetActive write SetActive;
  end;

  TCrossServerConnection = class(TCrossSslConnection, ICrossServerConnection);

  TCrossServer = class(TCrossSslSocket, ICrossServer)
  private
    FPort: Word;
    FAddr: string;
    FStarted: Integer;
  protected
    function GetAddr: string;
    function GetPort: Word;
    function GetActive: Boolean;

    procedure SetAddr(const Value: string);
    procedure SetPort(const Value: Word);
    procedure SetActive(const Value: Boolean);
  protected
    function CreateConnection(const AOwner: TCrossSocketBase; const AClientSocket: THandle;
      const AConnectType: TConnectType; const AConnectCb: TCrossConnectionCallback): ICrossConnection; override;
  public
    procedure Start(const ACallback: TCrossListenCallback = nil);
    procedure Stop;

    property Addr: string read GetAddr write SetAddr;
    property Port: Word read GetPort write SetPort;
    property Active: Boolean read GetActive write SetActive;
  end;

implementation

{ TCrossServer }

function TCrossServer.CreateConnection(const AOwner: TCrossSocketBase;
  const AClientSocket: THandle; const AConnectType: TConnectType;
  const AConnectCb: TCrossConnectionCallback): ICrossConnection;
begin
  Result := TCrossServerConnection.Create(AOwner, AClientSocket, AConnectType, AConnectCb);
end;

function TCrossServer.GetActive: Boolean;
begin
  Result := (AtomicCmpExchange(FStarted, 0, 0) = 1);
end;

function TCrossServer.GetAddr: string;
begin
  Result := FAddr;
end;

function TCrossServer.GetPort: Word;
begin
  Result := FPort;
end;

procedure TCrossServer.SetActive(const Value: Boolean);
begin
  if Value then
    Start
  else
    Stop;
end;

procedure TCrossServer.SetAddr(const Value: string);
begin
  FAddr := Value;
end;

procedure TCrossServer.SetPort(const Value: Word);
begin
  FPort := Value;
end;

procedure TCrossServer.Start(const ACallback: TCrossListenCallback);
var
  LListenArr: TArray<ICrossListen>;
  LListen: ICrossListen;
begin
  if (AtomicCmpExchange(FStarted, 0, 0) = 1) then
  begin
    if Assigned(ACallback) then
    begin
      LListenArr := LockListens.Values.ToArray;
      try
        for LListen in LListenArr do
          ACallback(LListen, True);
      finally
        UnlockListens;
      end;
    end;

    Exit;
  end;

  StartLoop;

  Listen(FAddr, FPort,
    procedure(const AListen: ICrossListen; const ASuccess: Boolean)
    begin
      if ASuccess then
        AtomicExchange(FStarted, 1);

      // 如果是监听的随机端口
      // 则在监听成功之后将实际的端口取出来
      if (FPort = 0) then
        FPort := AListen.LocalPort;

      if Assigned(ACallback) then
        ACallback(AListen, ASuccess);
    end);
end;

procedure TCrossServer.Stop;
begin
  CloseAll;
  StopLoop;
  AtomicExchange(FStarted, 0);
end;

end.
