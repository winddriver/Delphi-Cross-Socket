program HttpDirectoryTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  SysUtils, Classes,
  Net.SocketAPI, Net.CrossSocket.Base, Net.CrossHttpServer, Net.CrossHttpRouter, Net.CrossHttpUtils, Net.CrossHttpRouteFile;

type
  TMemoryConnection = class(TCrossHttpConnection)
  private
    FOutput: TMemoryStream;
    FCleaned: Boolean;
  protected
    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); override;
  public
    constructor Create(const AServer: TCrossHttpServer); reintroduce;
    destructor Destroy; override;
    procedure Feed(const AData: AnsiString);
    procedure Cleanup;
    procedure WriteResponse;
  end;

constructor TMemoryConnection.Create(const AServer: TCrossHttpServer);
begin
  inherited Create(AServer, INVALID_SOCKET, ctAccept, '', nil);
  FOutput := TMemoryStream.Create;
  ConnectStatus := csConnected;
end;

destructor TMemoryConnection.Destroy;
begin
  FOutput.Free;
  inherited;
end;

procedure TMemoryConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
begin
  // 只替换网络写入，仍执行真实解析、路由、目录读取、文件发送和响应队列。
  FOutput.WriteBuffer(ABuffer^, ACount);
  if Assigned(ACallback) then ACallback(Self, True);
end;

procedure TMemoryConnection.Feed(const AData: AnsiString);
var
  LBuffer: Pointer;
  LLength, LBefore: Integer;
begin
  LBuffer := PAnsiChar(AData);
  LLength := Length(AData);
  _LockRecv;
  try
    while LLength > 0 do
    begin
      LBefore := LLength;
      ParseRecvData(LBuffer, LLength);
      if LLength >= LBefore then raise Exception.Create('解析未消费输入');
    end;
  finally
    _UnlockRecv;
  end;
end;

procedure TMemoryConnection.Cleanup;
begin
  if FCleaned then Exit;
  FCleaned := True;
  ConnectStatus := csClosed;
  InternalClose;
end;

procedure TMemoryConnection.WriteResponse;
var
  LHandle: THandle;
begin
  if FOutput.Size = 0 then raise Exception.Create('没有响应输出');
  {$IFDEF MSWINDOWS}
  LHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  {$ELSE}
  LHandle := 1;
  {$ENDIF}
  if FileWrite(LHandle, FOutput.Memory^, FOutput.Size) <> FOutput.Size then
    raise Exception.Create('无法输出完整响应');
end;

// 使用与静态路由相同的打开对象，验证打开后替换路径不能替换发送源或目录枚举源。
procedure CheckPinned;
var
  LFile: THttpRouteFile;
  LPath: string;
  LEntry: THttpFileEntry;
  LByte: Byte;
begin
  LPath := IncludeTrailingPathDelimiter(ParamStr(2)) + ParamStr(3);
  LFile := THttpRouteFile.Open(ParamStr(2), ParamStr(3));
  if LFile = nil then raise Exception.Create('无法打开测试对象');
  try
    if RenameFile(LPath, LPath + '.old') then
    begin
      if not RenameFile(LPath + '.replacement', LPath) then raise Exception.Create('无法替换路径');
    end
    {$IFNDEF MSWINDOWS}else raise Exception.Create('POSIX 测试没有执行替换'){$ENDIF};
    if LFile.Directory then
    begin
      if not LFile.NextEntry(LEntry) or (LEntry.Name <> 'original') then
        raise Exception.Create('目录枚举使用了替换路径');
    end else
    begin
      LFile.ReadBuffer(LByte, 1);
      if LByte <> Ord('A') then raise Exception.Create('读取了替换文件');
    end;
  finally
    LFile.Free;
  end;
end;

procedure Run;
var
  LServer: ICrossHttpServer;
  LConnection: ICrossHttpConnection;
  LObject: TMemoryConnection;
  LMount, LExtraHeader: string;
  LMaxEntries: Integer;
begin
  if ParamStr(1) = '--pin' then
  begin
    CheckPinned;
    Exit;
  end;
  if not (ParamCount in [3, 4, 5, 6]) then raise Exception.Create('用法: HttpDirectoryTests <目录> <请求目标> <挂载路径> [条目上限]');
  LMaxEntries := 0;
  if ParamCount >= 4 then LMaxEntries := StrToInt(ParamStr(4));
  LMount := TCrossHttpUtils.UrlDecode(ParamStr(3));
  LServer := TCrossHttpServer.Create(1, False);
  LServer.Compressible := False;
  if ParamStr(5) = 'static' then
    LServer.Get(LMount + '/*', TNetCrossRouter.Static(ParamStr(1), '*'))
  else if ParamStr(5) = 'index' then
    LServer.Get(LMount + '/*', TNetCrossRouter.Index(ParamStr(1), '*', ['jump/outside.txt']))
  else
  {$IFDEF DIRECTORY_LIMIT_API}
  LServer.Get(LMount + '/*', TNetCrossRouter.Dir(LMount, ParamStr(1), '*', LMaxEntries));
  {$ELSE}
  LServer.Get(LMount + '/*', TNetCrossRouter.Dir(LMount, ParamStr(1), '*'));
  {$ENDIF}
  LObject := TMemoryConnection.Create(LServer as TCrossHttpServer);
  LConnection := LObject;
  try
    // runner 对所有请求目标做 URL 编码，线上字节保持 ASCII。
    if ParamCount = 6 then LExtraHeader := TCrossHttpUtils.UrlDecode(ParamStr(6)) + #13#10;
    LObject.Feed(AnsiString('GET ' + ParamStr(2) + ' HTTP/1.1'#13#10 +
      'Host: localhost'#13#10 + LExtraHeader + #13#10));
    if LConnection.Pending <> 0 then raise Exception.Create('响应尚未发送完成');
    LObject.WriteResponse;
  finally
    LObject.Cleanup;
    LConnection := nil;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
