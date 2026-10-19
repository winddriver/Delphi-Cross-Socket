{$IFDEF LINUX}
type TConnectGapSocket=class(TCrossSocket)
  public Disconnects:Integer;
  protected procedure LogicDisconnected(const C:ICrossConnection);override;
end;
procedure TConnectGapSocket.LogicDisconnected(const C:ICrossConnection);
begin Inc(Disconnects);inherited;end;
{$ENDIF}
procedure TestSocketConnectGap(const Port:Word);
{$IFDEF LINUX}
var S:TConnectGapSocket;Keep:ICrossSocket;Connection:ICrossConnection;Calls:Integer;
begin
  Calls:=0;S:=TConnectGapSocket.Create(1);Keep:=S;
  try
    CrossConnectBeforeRegisterForTest:=procedure(const C:ICrossConnection)
      begin Connection:=C;Keep.CloseAllConnections;end;
    Keep.Connect('127.0.0.1',Port,procedure(const C:ICrossConnection;const OK:Boolean)
      begin Inc(Calls);Check(not OK,'关闭登记仍通知成功');end);
    Check((Connection<>nil) and Connection.IsClosed,'连接闭态被覆盖');
    Check((Calls=1) and (S.Disconnects=1),'关闭后被重新登记或重复失败通知');
  finally CrossConnectBeforeRegisterForTest:=nil;Keep.CloseAll;Keep.StopLoop;Connection:=nil;Keep:=nil;end;
end;
{$ELSE}
begin raise Exception.Create('登记检查后关闭用例当前仅在Linux运行');end;
{$ENDIF}
