unit uMain;

{.$DEFINE __SSL__}

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants, System.ZLib, FMX.StdCtrls,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.Edit, FMX.EditBox, FMX.SpinBox,
  System.Diagnostics, FMX.Objects,
  {$IFDEF __SSL__}
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket,
  Net.CrossSslDemoCert,
  {$ENDIF}
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossSocket;

type
  TfmMain = class(TForm)
    Timer1: TTimer;
    MagicDock1: TRectangle;
    Label6: TLabel;
    btnListen: TButton;
    edtListenPort: TSpinBox;
    MagicDock2: TRectangle;
    Label7: TLabel;
    MagicDock3: TRectangle;
    Label8: TLabel;
    btnConnect: TButton;
    edtConnCount: TSpinBox;
    edtConnHost: TEdit;
    edtConnPort: TSpinBox;
    btnStart: TButton;
    MagicDock4: TRectangle;
    edtBufSize: TSpinBox;
    labelConns: TLabel;
    labelRcvData: TLabel;
    labelSndData: TLabel;
    labelSndSpeed: TLabel;
    labelRcvSpeed: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    btnDisconnect: TButton;
    Label14: TLabel;
    labelTime: TLabel;
    labelRcvCount: TLabel;
    labelSndCount: TLabel;
    checkGraceful: TCheckBox;
    Button2: TButton;
    Button3: TButton;
    labelOsVer: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnListenClick(Sender: TObject);
    procedure btnConnectClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure btnDisconnectClick(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
  private
    FOrgCaption: string;
    FSocket: {$IFDEF __SSL__}ICrossSslSocket{$ELSE}ICrossSocket{$ENDIF};
    FTesting: Boolean;
    FSentBytes, FRcvdBytes, FLastSent, FLastRcvd, FSendCount, FRcvdCount: Int64;
    FRunWatch, FSendWatch, FRecvWatch: TStopwatch;
    FBufSize: Integer;
    FBuffer: TBytes;
    FTestProc: TCrossConnectionCallback;

    procedure OnConnected(const Sender: TObject; const AConnection: ICrossConnection);
    procedure OnReceived(const Sender: TObject; const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer);
    procedure OnSent(const Sender: TObject; const AConnection: ICrossConnection;
      const ABuf: Pointer; const ALen: Integer);

    procedure InitBuffer;
    function GetBuffer: TBytes; inline;
  public
    { Public declarations }
  end;

var
  fmMain: TfmMain;

implementation

uses
  System.Threading, System.Math, System.IOUtils;

{$R *.fmx}

function BytesToStr(const Bytes: Extended): string;
const
  KB = Int64(1024);
  MB = KB * 1024;
  GB = MB * 1024;
  TB = GB * 1024;
  PB = TB * 1024;
begin
  if (Bytes = 0) then
    Result := ''
  else if (Bytes < KB) then
    Result := FormatFloat('0.##B', Bytes)
  else if (Bytes < MB) then
    Result := FormatFloat('0.##KB', Bytes / KB)
  else if (Bytes < GB) then
    Result := FormatFloat('0.##MB', Bytes / MB)
  else if (Bytes < TB) then
    Result := FormatFloat('0.##GB', Bytes / GB)
  else if (Bytes < PB) then
    Result := FormatFloat('0.##TB', Bytes / TB)
  else
    Result := FormatFloat('0.##PB', Bytes / PB)
end;

function WatchToStr(const AWatch: TStopwatch): string;
begin
  Result := '';
  if (AWatch.Elapsed.Days > 0) then
    Result := Result + AWatch.Elapsed.Days.ToString + 'd';
  if (AWatch.Elapsed.Hours > 0) then
    Result := Result + AWatch.Elapsed.Hours.ToString + 'h';
  if (AWatch.Elapsed.Minutes > 0) then
    Result := Result + AWatch.Elapsed.Minutes.ToString + 'm';
  if (AWatch.Elapsed.Seconds > 0) then
    Result := Result + AWatch.Elapsed.Seconds.ToString + 's';
end;

procedure TfmMain.btnListenClick(Sender: TObject);
begin
  if (btnListen.Tag = 0) then
  begin
    FSocket.Listen('0.0.0.0', Trunc(edtListenPort.Value),
      procedure(const AListen: ICrossListen; const ASuccess: Boolean)
      begin
        {$IFDEF DEBUG}
        TThread.Queue(nil,
          procedure
          begin
            if ASuccess then
              ShowMessage('listen ok')
            else
              ShowMessage('listen error');
          end);
        {$ENDIF}
      end);
    btnListen.Tag := 1;
    btnListen.Text := '停止';
    Self.Caption := Format('%s (%d)',
      [FOrgCaption, Trunc(edtListenPort.Value)]);
  end
  else
  begin
    FSocket.CloseAll;
    btnListen.Tag := 0;
    btnListen.Text := '启动';
    Self.Caption := FOrgCaption;
  end;
end;

procedure TfmMain.btnConnectClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to Trunc(edtConnCount.Value) do
    FSocket.Connect(edtConnHost.Text, Trunc(edtConnPort.Value),
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
//        {$IFDEF DEBUG}
//        TThread.Queue(nil,
//          procedure
//          begin
//            if ASuccess then
//              ShowMessage('connect ok')
//            else
//              ShowMessage('connect error');
//          end);
//        {$ENDIF}
      end);
end;

procedure TfmMain.Button2Click(Sender: TObject);
const
  DATA_SIZE = 10 * 1024 * 1024;
var
  LStream: TBytesStream;
  LConns: TArray<ICrossConnection>;
  I: Integer;
  B: Byte;
begin
  LConns := FSocket.LockConnections.Values.ToArray;
  if (LConns <> nil) then
  begin
    LStream := TBytesStream.Create(nil);
    for I := 1 to DATA_SIZE do
    begin
      B := RandomRange(0, 255 + 1);
      LStream.Write(B, SizeOf(Byte));
    end;
    LStream.Position := 0;

    LConns[0].SendStream(LStream,
      procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
      begin
        TThread.Queue(nil,
          procedure
          begin
            if ASuccess then
              ShowMessage('SendStream SUCCESS!!')
            else
              ShowMessage('SendStream FAILED!!');
          end);
        FreeAndNil(LStream);
      end);
  end;
  FSocket.UnlockConnections;
end;

procedure TfmMain.Button3Click(Sender: TObject);
begin
  FSocket.Connect(edtConnHost.Text, Trunc(edtConnPort.Value),
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          if ASuccess then
            ShowMessage('Connect SUCCESS!!')
          else
            ShowMessage('Connect FAILED!!');
        end);
    end);
end;

procedure TfmMain.btnDisconnectClick(Sender: TObject);
begin
  if checkGraceful.IsChecked then
    FSocket.DisconnectAll
  else
    FSocket.CloseAllConnections;
end;

procedure TfmMain.btnStartClick(Sender: TObject);
var
  LConns: TArray<ICrossConnection>;
  LConn: ICrossConnection;
  LBytes: TBytes;
begin
  if (btnStart.Tag = 0) then
  begin
    btnStart.Tag := 1;
    btnStart.Text := '停止';

    InitBuffer;

    FTesting := True;

    LConns := FSocket.LockConnections.Values.ToArray;
    try
      for LConn in LConns do
      begin
        LBytes := GetBuffer;
        LConn.SendBytes(LBytes, FTestProc);
      end;
    finally
      FSocket.UnlockConnections;
    end;
  end else
  begin
    btnStart.Tag := 0;
    btnStart.Text := '开始';
    FTesting := False;
  end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  labelOsVer.Text := TOSVersion.ToString;
  {$IFDEF CPUX64}
  labelOsVer.Text := labelOsVer.Text + ' - 64bit';
  {$ENDIF}
  {$IFDEF CPUX86}
  labelOsVer.Text := labelOsVer.Text + ' - 32bit';
  {$ENDIF}

  {$IFDEF __SSL__}
  Self.Caption := 'Cross SSL Socket Tester';
  {$ELSE}
  Self.Caption := 'Cross Socket Tester';
  {$ENDIF}

  FOrgCaption := Self.Caption;
  FSocket :=
    {$IFDEF __SSL__}
    TCrossSslSocket
    {$ELSE}
    TCrossSocket
    {$ENDIF}
    .Create(0);
  FSocket.OnConnected := OnConnected;
  FSocket.OnReceived := OnReceived;
  FSocket.OnSent := OnSent;
  FRunWatch := TStopwatch.StartNew;

  {$IFDEF __SSL__}
  FSocket.SetCertificate(SSL_SERVER_CERT);
  FSocket.SetPrivateKey(SSL_SERVER_PKEY);
  {$ENDIF}

  FTestProc :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LBytes: TBytes;
    begin
      if not FTesting or not ASuccess then Exit;

      LBytes := GetBuffer;
      AConnection.SendBytes(LBytes, FTestProc);
    end;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FTestProc := nil;

  FSocket.StopLoop;
  FSocket := nil;
end;

function TfmMain.GetBuffer: TBytes;
begin
  // 直接发送
  Result := FBuffer;

  // 压缩后发送
//  ZCompress(FBuffer, Result, zcFastest);
end;

procedure TfmMain.InitBuffer;
var
  I: Integer;
begin
  FBufSize := Max(Trunc(edtBufSize.Value), 1024);
  SetLength(FBuffer, FBufSize);
  for I := Low(FBuffer) to High(FBuffer) do
    FBuffer[I] := RandomRange(0, 255 + 1);
end;

procedure TfmMain.OnConnected(const Sender: TObject; const AConnection: ICrossConnection);
begin
  if FTesting and Assigned(FTestProc) then
    FTestProc(AConnection, True);
end;

procedure TfmMain.OnReceived(const Sender: TObject; const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  AtomicIncrement(FRcvdCount);
  AtomicIncrement(FRcvdBytes, ALen);
end;

procedure TfmMain.OnSent(const Sender: TObject; const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  AtomicIncrement(FSendCount);
  AtomicIncrement(FSentBytes, ALen);
end;

procedure TfmMain.Timer1Timer(Sender: TObject);
begin
  labelTime.Text := Format('运行时间：%s', [WatchToStr(FRunWatch)]);
  labelConns.Text := Format('活动连接：%d', [FSocket.ConnectionsCount]);

  labelRcvData.Text := Format('接收数据：%s', [BytesToStr(FRcvdBytes)]);
  labelRcvData.Hint := FRcvdBytes.ToString;
  if (FRcvdBytes > FLastRcvd) and (FRecvWatch.ElapsedTicks > 0) then
    labelRcvSpeed.Text := Format('接收速度：%s/s',
      [BytesToStr((FRcvdBytes - FLastRcvd) / FRecvWatch.Elapsed.TotalSeconds)])
  else
    labelRcvSpeed.Text := '接收速度： ';
  labelRcvCount.Text := Format('接收次数：%d', [FRcvdCount]);

  labelSndData.Text := Format('发送数据：%s', [BytesToStr(FSentBytes)]);
  labelSndData.Hint := FSentBytes.ToString;
  if (FSentBytes > FLastSent) and (FSendWatch.ElapsedTicks > 0) then
    labelSndSpeed.Text := Format('发送速度：%s/s',
      [BytesToStr((FSentBytes - FLastSent) / FSendWatch.Elapsed.TotalSeconds)])
  else
    labelSndSpeed.Text := '发送速度： ';
  labelSndCount.Text := Format('发送次数：%d', [FSendCount]);

  if (FSentBytes <> FLastSent) and ((FSendWatch.ElapsedTicks = 0) or
    (FSendWatch.Elapsed.TotalSeconds > 2)) then
  begin
    FLastSent := FSentBytes;
    FSendWatch := TStopwatch.StartNew;
  end;

  if (FRcvdBytes <> FLastRcvd) and ((FRecvWatch.ElapsedTicks = 0) or
    (FRecvWatch.Elapsed.TotalSeconds > 2)) then
  begin
    FLastRcvd := FRcvdBytes;
    FRecvWatch := TStopwatch.StartNew;
  end;
end;

end.
