{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSslServer;

interface

uses
  System.SysUtils, Net.SocketAPI, Net.CrossSocket, Net.CrossSslSocket;

type
  TCrossSslServer = class(TCrossSslSocket)
  private
    FPort: Word;
    FAddr: string;
    FStarted: Integer;

    function GetActive: Boolean;
    procedure SetActive(const Value: Boolean);
  protected
    procedure TriggerListened(ASocket: THandle); override;
  public
    procedure CloseAllConnections; override;
    procedure DisconnectAll; override;

    procedure Start(const ACallback: TProc<Boolean> = nil);
    procedure Stop;

    property Addr: string read FAddr write FAddr;
    property Port: Word read FPort write FPort;

    property Active: Boolean read GetActive write SetActive;
    property ConnectionsCount;

    property OnGetConnectionClass;
    property OnListened;
    property OnListenEnd;
    property OnConnected;
    property OnDisconnected;
    property OnReceived;
    property OnSent;
  end;

implementation

{ TCrossSslServer }

procedure TCrossSslServer.CloseAllConnections;
begin
  inherited;
end;

procedure TCrossSslServer.DisconnectAll;
begin
  inherited;
end;

function TCrossSslServer.GetActive: Boolean;
begin
  Result := (AtomicCmpExchange(FStarted, 0, 0) = 1);
end;

procedure TCrossSslServer.SetActive(const Value: Boolean);
begin
  if Value then
    Start
  else
    Stop;
end;

procedure TCrossSslServer.Start(const ACallback: TProc<Boolean>);
begin
  if (AtomicExchange(FStarted, 1) = 1) then
  begin
    if Assigned(ACallback) then
      ACallback(False);

    Exit;
  end;

  StartLoop;

  Listen(FAddr, FPort,
    procedure(ASocket: THandle; ASuccess: Boolean)
    var
      LAddr: TRawSockAddrIn;
      LStuff: string;
    begin
      if not ASuccess then
        AtomicExchange(FStarted, 0);

      // 如果是监听的随机端口
      // 则在监听成功之后将实际的端口取出来
      if (FPort = 0) then
      begin
        FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
        LAddr.AddrLen := SizeOf(LAddr.Addr6);
        if (TSocketAPI.GetSockName(ASocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
          TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen, LStuff, FPort);
      end;

      if Assigned(ACallback) then
        ACallback(ASuccess);
    end);
end;

procedure TCrossSslServer.Stop;
begin
  CloseAll;
  StopLoop;
  AtomicExchange(FStarted, 0);
end;

procedure TCrossSslServer.TriggerListened(ASocket: THandle);
var
  LPort: Word;
  LAddr: TRawSockAddrIn;
  LStuff: string;
begin
  inherited;

  // Delphi Tokyo 10.2以上的版本 AtomicCmpExchange 可以操作 Word 类型的变量
  // 更老的版本会触发异常
  {$IF CompilerVersion >= 32.0}
  LPort := AtomicCmpExchange(FPort, 0, 0);
  {$ELSE}
  LPort := FPort;
  {$ENDIF}

  // 如果是监听的随机端口
  // 则在监听成功之后将实际的端口取出来
  if (LPort = 0) then
  begin
    FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
    LAddr.AddrLen := SizeOf(LAddr.Addr6);
    if (TSocketAPI.GetSockName(ASocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    begin
      TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen, LStuff, LPort);
      AtomicExchange(FPort, LPort);
    end;
  end;
end;

end.
