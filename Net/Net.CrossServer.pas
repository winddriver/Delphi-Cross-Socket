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

interface

uses
  Net.CrossSocket.Base,
  Net.CrossSocket,
  Net.CrossSslSocket,
  Net.CrossSslServer;

type
  ICrossServer = interface(ICrossSslServer)
  ['{15AF35E3-BD63-4604-BF4B-238E270FADE6}']
    function GetSsl: Boolean;
    procedure SetSsl(const AValue: Boolean);

    property Ssl: Boolean read GetSsl write SetSsl;
  end;

  TCrossServerConnection = class(TCrossSslConnection)
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    constructor Create(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType); override;
    destructor Destroy; override;
  end;

  TCrossServer = class(TCrossSslServer, ICrossServer)
  private
    FSsl: Boolean;

    function GetSsl: Boolean;
    procedure SetSsl(const AValue: Boolean);
  protected
    procedure TriggerConnected(const AConnection: ICrossConnection); override;
    procedure TriggerReceived(const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer); override;

    function CreateConnection(const AOwner: ICrossSocket;
      const AClientSocket: THandle; const AConnectType: TConnectType): ICrossConnection; override;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); reintroduce; virtual;
    destructor Destroy; override;

    property Ssl: Boolean read GetSsl write SetSsl;
  end;

implementation

type
  TCrossSocketCreate = procedure(Self: Pointer; Alloc: Boolean;
    const AIoThreads: Integer);

  TCrossConnectionCreate = procedure(Self: Pointer; Alloc: Boolean;
    const AOwner: ICrossSocket; const AClientSocket: THandle;
    const AConnectType: TConnectType);

  TDestroy = procedure(Self: Pointer; Free: Boolean);

  TDirectSend = procedure(Self: Pointer; const ABuffer: Pointer;
    const ACount: Integer; const ACallback: TCrossConnectionCallback = nil);
  TTriggerConnected = procedure(Self: Pointer;
    const AConnection: ICrossConnection);
  TTriggerReceived = procedure(Self: Pointer;
    const AConnection: ICrossConnection; const ABuf: Pointer;
    const ALen: Integer);

{ TCrossServerConnection }

constructor TCrossServerConnection.Create(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType);
begin
  if (AOwner as TCrossServer).FSsl then
    inherited Create(AOwner, AClientSocket, AConnectType)
  else
    TCrossConnectionCreate(@TCrossConnection.Create)(Self, False, AOwner,
      AClientSocket, AConnectType);
end;

destructor TCrossServerConnection.Destroy;
begin
  if (Owner as TCrossServer).FSsl then
    inherited Destroy
  else
    TDestroy(@TCrossConnection.Destroy)(Self, False);
end;

procedure TCrossServerConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  if (Owner as TCrossServer).FSsl then
    inherited DirectSend(ABuffer, ACount, ACallback)
  else
    TDirectSend(@TCrossConnection.DirectSend)(Self, ABuffer, ACount, ACallback);
end;

{ TCrossServer }

constructor TCrossServer.Create(const AIoThreads: Integer; const ASsl: Boolean);
begin
  if ASsl then
    inherited Create(AIoThreads)
  else
    TCrossSocketCreate(@TCrossSocket.Create)(Self, False, AIoThreads);

  FSsl := ASsl;
end;

destructor TCrossServer.Destroy;
begin
  if FSsl then
    inherited Destroy
  else
    TDestroy(@TCrossSocket.Destroy)(Self, False);
end;

function TCrossServer.CreateConnection(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType): ICrossConnection;
begin
  Result := TCrossServerConnection.Create(AOwner, AClientSocket, AConnectType);
end;

function TCrossServer.GetSsl: Boolean;
begin
  Result := FSsl;
end;

procedure TCrossServer.SetSsl(const AValue: Boolean);
begin
  FSsl := AValue;
end;

procedure TCrossServer.TriggerConnected(const AConnection: ICrossConnection);
begin
  if FSsl then
    inherited TriggerConnected(AConnection)
  else
    TTriggerConnected(@TCrossSocket.TriggerConnected)(Self, AConnection);
end;

procedure TCrossServer.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  if FSsl then
    inherited TriggerReceived(AConnection, ABuf, ALen)
  else
    TTriggerReceived(@TCrossSocket.TriggerReceived)(Self, AConnection, ABuf, ALen);
end;

end.
