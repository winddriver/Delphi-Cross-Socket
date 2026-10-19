program SocketCloseOnExecTests;

{$I ../../../../zLib.inc}

uses
  {$IFDEF FPC}cthreads,{$ENDIF}
  SysUtils, Classes,
  {$IFDEF DELPHI}
  Posix.Base, Posix.SysSocket, Posix.NetinetIn, Posix.Fcntl,
  Posix.Errno, Posix.Dlfcn,
  {$ELSE}
  BaseUnix, Sockets, dl,
  {$ENDIF}
  Net.SocketAPI;

const
  TEST_CLOEXEC = $80000;
  TEST_NONBLOCK = $800;

function c_fork: Integer; cdecl; external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name 'fork';
function c_execv(APath: PAnsiChar; AArgs: Pointer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name 'execv';
function c_waitpid(APid: Integer; AStatus: PInteger; AOptions: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name 'waitpid';
procedure c_exit(AStatus: Integer); cdecl; external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name '_exit';
function c_dup(AFd: Integer): Integer; cdecl; external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name 'dup';
function c_dup2(AFd, ATarget: Integer): Integer; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name 'dup2';
function c_readlink(APath: PAnsiChar; ABuffer: Pointer; ASize: NativeUInt): NativeInt; cdecl;
  external {$IFDEF FPC}'c'{$ELSE}libc{$ENDIF} name 'readlink';

procedure Check(AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

function LastError: Integer;
begin
  {$IFDEF DELPHI}Result := Posix.Errno.errno;{$ELSE}Result := fpgeterrno;{$ENDIF}
end;

function GetFdFlags(AFd: Integer): Integer;
begin
  {$IFDEF DELPHI}Result := fcntl(AFd, F_GETFD);{$ELSE}Result := fpfcntl(AFd, F_GETFD);{$ENDIF}
end;

procedure CheckFlags(AFd: Integer);
var LFlags: Integer;
begin
  Check(AFd <> INVALID_SOCKET, '创建或接入失败: ' + IntToStr(LastError));
  if ParamStr(1) <> 'no-fcntl' then
  begin
    LFlags := GetFdFlags(AFd);
    Check((LFlags >= 0) and ((LFlags and 1) = 1), '缺少 FD_CLOEXEC');
  end;
end;

function Accept4Calls: Integer;
type TCountFunc = function: Integer; cdecl;
var LHandle: {$IFDEF DELPHI}NativeUInt{$ELSE}Pointer{$ENDIF}; LFunc: TCountFunc;
begin
  LHandle := dlopen(nil, RTLD_LAZY);
  Check(Pointer(LHandle) <> nil, '无法读取注入器计数');
  try
    LFunc := TCountFunc(dlsym(LHandle, 'socket_test_accept4_calls'));
    Check(Assigned(LFunc), '未加载测试注入器');
    Result := LFunc();
  finally
    dlclose(LHandle);
  end;
end;

function FdCount: Integer;
var LSearch: TSearchRec;
begin
  Result := 0;
  if FindFirst('/proc/self/fd/*', faAnyFile, LSearch) = 0 then
  try
    repeat
      if (LSearch.Name <> '.') and (LSearch.Name <> '..') then Inc(Result);
    until FindNext(LSearch) <> 0;
  finally
    FindClose(LSearch);
  end;
end;

function NewListener(out AAddress: sockaddr_in): Integer;
var LSize: Integer;
begin
  Result := TSocketAPI.NewTcp;
  Check(Result <> INVALID_SOCKET, '创建监听 socket 失败');
  FillChar(AAddress, SizeOf(AAddress), 0);
  AAddress.sin_family := AF_INET;
  // 127.0.0.1 + 临时端口，测试运行于 x86_64 Linux。
  AAddress.sin_addr.s_addr := $0100007F;
  Check(TSocketAPI.Bind(Result, PSockAddr(@AAddress), SizeOf(AAddress)) = 0, 'bind 失败');
  Check(TSocketAPI.Listen(Result) = 0, 'listen 失败');
  LSize := SizeOf(AAddress);
  Check(TSocketAPI.GetSockName(Result, PSockAddr(@AAddress), LSize) = 0, 'getsockname 失败');
end;

function FdTarget(AFd: Integer): AnsiString;
var LPath: AnsiString; LBuffer: array[0..255] of AnsiChar; LSize: NativeInt;
begin
  LPath := AnsiString('/proc/self/fd/' + IntToStr(AFd));
  LSize := c_readlink(PAnsiChar(LPath), @LBuffer[0], SizeOf(LBuffer));
  if LSize < 0 then Result := ''
  else SetString(Result, PAnsiChar(@LBuffer[0]), LSize);
end;

procedure CheckExecClosed(AFd: Integer);
var
  LPath, LMode, LFd, LTarget: AnsiString;
  LArgs: array[0..4] of PAnsiChar;
  LPid, LStatus: Integer;
begin
  // fork 前准备参数；子进程只调用 execv / _exit。
  LPath := AnsiString(ParamStr(0)); LMode := '--closed'; LFd := AnsiString(IntToStr(AFd));
  LTarget := FdTarget(AFd); Check(LTarget <> '', '无法读取 socket 身份');
  LArgs[0] := PAnsiChar(LPath); LArgs[1] := PAnsiChar(LMode);
  LArgs[2] := PAnsiChar(LFd); LArgs[3] := PAnsiChar(LTarget); LArgs[4] := nil;
  LPid := c_fork;
  Check(LPid >= 0, 'fork 失败');
  if LPid = 0 then
  begin
    c_execv(PAnsiChar(LPath), @LArgs[0]);
    c_exit(127);
  end;
  Check(c_waitpid(LPid, @LStatus, 0) = LPid, 'waitpid 失败');
  Check(LStatus = 0, 'socket 在 exec 后仍被继承: status=' + IntToStr(LStatus));
end;

procedure TestConnection(AWithAddress, AFailFcntl: Boolean);
var LAddress, LPeer: sockaddr_in; LListener, LClient, LAccepted, LSize, LBefore, LError: Integer;
  LSent, LReceived: Byte;
begin
  LListener := NewListener(LAddress); LClient := INVALID_SOCKET; LAccepted := INVALID_SOCKET;
  try
    LClient := TSocketAPI.NewTcp;
    Check(LClient <> INVALID_SOCKET, '创建客户端失败');
    Check(TSocketAPI.Connect(LClient, PSockAddr(@LAddress), SizeOf(LAddress)) = 0, 'connect 失败');
    LBefore := FdCount;
    if AWithAddress then
    begin
      LSize := SizeOf(LPeer);
      LAccepted := TSocketAPI.Accept(LListener, PSockAddr(@LPeer), @LSize);
      if not AFailFcntl then
        Check((LSize = SizeOf(LPeer)) and (LPeer.sin_family = AF_INET), '地址回写错误');
    end else
      LAccepted := TSocketAPI.Accept(LListener, nil, nil);
    LError := LastError;
    if AFailFcntl then
    begin
      Check(LAccepted = INVALID_SOCKET, 'fcntl 失败仍返回接入 socket');
      Check(LError = 5, 'fcntl 失败 errno 未保留');
      Check(FdCount = LBefore, '接入失败泄漏描述符');
      Exit;
    end;
    CheckFlags(LAccepted); CheckFlags(LListener); CheckFlags(LClient);
    LSent := 123; LReceived := 0;
    Check(TSocketAPI.Send(LClient, LSent, 1, 0) = 1, 'send 失败');
    Check(TSocketAPI.Recv(LAccepted, LReceived, 1, 0) = 1, 'recv 失败');
    Check(LReceived = LSent, '载荷不一致');
    if ParamStr(1) <> 'no-fcntl' then
    begin
      CheckExecClosed(LListener); CheckExecClosed(LClient); CheckExecClosed(LAccepted);
    end;
  finally
    if LAccepted <> INVALID_SOCKET then TSocketAPI.CloseSocket(LAccepted);
    if LClient <> INVALID_SOCKET then TSocketAPI.CloseSocket(LClient);
    TSocketAPI.CloseSocket(LListener);
  end;
end;

type
  TAcceptThread = class(TThread)
  public
    Listener: Integer;
    ErrorText: string;
    procedure Execute; override;
  end;

procedure CheckAcceptError(AListener, AExpected: Integer);
var LFd, LError: Integer;
begin
  // 使 FPC 的旧 errno 与 libc 的新 errno 不同，验证同步路径。
  {$IFDEF FPC}fpSetErrno(1234);{$ENDIF}
  LFd := TSocketAPI.Accept(AListener, nil, nil);
  LError := LastError;
  Check(LFd = INVALID_SOCKET, '错误路径意外成功');
  Check(LError = AExpected, 'accept errno 错误: ' + IntToStr(LError) + ', expected ' + IntToStr(AExpected));
end;

procedure TAcceptThread.Execute;
begin
  try
    CheckAcceptError(Listener, 11); CheckAcceptError(Listener, 11);
  except
    on E: Exception do ErrorText := E.Message;
  end;
end;

procedure TestErrors;
var LAddress: sockaddr_in; LListener, i: Integer; LThreads: array[0..1] of TAcceptThread;
begin
  LListener := NewListener(LAddress);
  try
    Check(TSocketAPI.SetNonBlock(LListener) = 0, '设置非阻塞失败');
    if ParamStr(1) = 'enosys' then
    begin
      CheckAcceptError(LListener, 11); CheckAcceptError(LListener, 11);
      Check(Accept4Calls = 1, 'ENOSYS 未缓存');
      for i := 0 to High(LThreads) do
      begin
        LThreads[i] := TAcceptThread.Create(True);
        LThreads[i].Listener := LListener; LThreads[i].Start;
      end;
      for i := 0 to High(LThreads) do
      begin
        LThreads[i].WaitFor;
        Check(LThreads[i].ErrorText = '', LThreads[i].ErrorText);
        LThreads[i].Free;
      end;
      Check(Accept4Calls = 3, 'ENOSYS 缓存没有按线程隔离');
    end else
    begin
      CheckAcceptError(LListener, StrToInt(ParamStr(2)));
      Check(Accept4Calls = 1, '异常路径重复调用 accept4');
    end;
  finally
    TSocketAPI.CloseSocket(LListener);
  end;
end;

procedure TestCreation;
var LFd, LBefore, LError, i, LSaved: Integer;
begin
  if (ParamStr(1) = 'get-fail') or (ParamStr(1) = 'set-fail') then
  begin
    LBefore := FdCount;
    for i := 1 to 64 do
    begin
      LFd := TSocketAPI.NewTcp; LError := LastError;
      Check(LFd = INVALID_SOCKET, '设置失败仍返回新 socket');
      Check(LError = 5, '创建失败 errno 未保留');
    end;
    Check(FdCount = LBefore, '创建失败泄漏描述符');
    Exit;
  end;
  if ParamStr(1) = 'explicit' then
  begin
    LFd := TSocketAPI.NewSocket(AF_INET, SOCK_STREAM or TEST_CLOEXEC, 0);
    Check((LFd = INVALID_SOCKET) and (LastError = 22), '移除了调用者明确指定的 CLOEXEC');
    Exit;
  end;
  if ParamStr(1) = 'socket-error' then
  begin
    LFd := TSocketAPI.NewTcp; LError := LastError;
    Check((LFd = INVALID_SOCKET) and (LError = 1), 'socket 非 EINVAL 错误被回退掩盖');
    Exit;
  end;
  LFd := TSocketAPI.NewUdp;
  try CheckFlags(LFd); finally TSocketAPI.CloseSocket(LFd); end;
  LFd := TSocketAPI.NewSocket(AF_INET, SOCK_STREAM or TEST_NONBLOCK, 0);
  try CheckFlags(LFd); finally TSocketAPI.CloseSocket(LFd); end;
  if ParamStr(1) <> 'no-fcntl' then
  begin
    LSaved := c_dup(0); Check(LSaved >= 0, '无法保存 stdin');
    TSocketAPI.CloseSocket(0);
    try
      LFd := TSocketAPI.NewTcp;
      Check(LFd = 0, '未覆盖描述符 0'); CheckFlags(LFd);
      TSocketAPI.CloseSocket(LFd);
    finally
      c_dup2(LSaved, 0); TSocketAPI.CloseSocket(LSaved);
    end;
  end;
end;

var LTarget: AnsiString; LFdFlags, LFdError: Integer;
begin
  if ParamStr(1) = '--closed' then
  begin
    LFdFlags := GetFdFlags(StrToInt(ParamStr(2))); LFdError := LastError;
    if (LFdFlags = -1) and (LFdError = 9) then Halt(0);
    // Delphi 运行库可能将已关闭的编号用于管道；比较原 socket 身份。
    LTarget := FdTarget(StrToInt(ParamStr(2)));
    if (LTarget <> '') and (LTarget <> AnsiString(ParamStr(3))) then Halt(0);
    Halt(1);
  end;
  try
    if (ParamStr(1) = 'error') or (ParamStr(1) = 'enosys') then TestErrors
    else if ParamStr(1) = 'accept-set-fail' then TestConnection(False, True)
    else
    begin
      TestCreation;
      if (ParamStr(1) = 'normal') or (ParamStr(1) = 'missing') or (ParamStr(1) = 'load-fail') or
        (ParamStr(1) = 'no-fcntl') or (ParamStr(1) = 'fallback') then
      begin
        TestConnection(False, False); TestConnection(True, False);
        if ParamStr(1) = 'missing' then Check(Accept4Calls = 0, '缺失符号仍调用 accept4');
      end;
    end;
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do begin Writeln('FAIL ', E.Message); Halt(1); end;
  end;
end.
