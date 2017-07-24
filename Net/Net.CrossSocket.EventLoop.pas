{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.EventLoop;

interface

uses
  System.SysUtils, System.Classes,
  {$IFDEF POSIX}
  Posix.SysSocket, Posix.NetinetIn, Posix.UniStd, Posix.NetDB, Posix.Errno,
  {$IFDEF MACOS}BSD.kqueue{$ELSE}Linux.epoll{$ENDIF},
  {$ENDIF}
  {$IFDEF MSWINDOWS}
  Winapi.Windows, Net.Winsock2, Net.Wship6,
  {$ENDIF}
  Net.SocketAPI, Utils.Logger;

const
  CT_ACCEPT  = 1;
  CT_CONNECT = 2;

type
  TAbstractEventLoop = class;

  TIoEventThread = class(TThread)
  private
    FLoop: TAbstractEventLoop;
  protected
    procedure Execute; override;
  public
    constructor Create(ALoop: TAbstractEventLoop); reintroduce;
  end;

  TAbstractEventLoop = class abstract
  protected const
    RCV_BUF_SIZE = 32768;
  protected class threadvar
    FRecvBuf: array [0..RCV_BUF_SIZE-1] of Byte;
  protected
    FIoThreads: Integer;
    FListensCount: Integer;
    FConnectionsCount: Integer;

    // 设置套接字心跳参数, 用于处理异常断线(拔网线, 主机异常掉电等造成的网络异常)
    function SetKeepAlive(ASocket: THandle): Integer;
  protected
    function ProcessIoEvent: Boolean; virtual; abstract;
    function GetIoThreads: Integer; virtual;

    procedure TriggerListened(ASocket: THandle); virtual; abstract;
    procedure TriggerListenEnd(ASocket: THandle); virtual; abstract;
    procedure TriggerConnected(ASocket: THandle; AConnectType: Integer); overload; virtual; abstract;
    procedure TriggerConnectFailed(ASocket: THandle); virtual; abstract;
    procedure TriggerDisconnected(ASocket: THandle); overload; virtual; abstract;
    procedure TriggerReceived(ASocket: THandle; ABuf: Pointer; ALen: Integer); overload; virtual; abstract;

    function IsListen(ASocket: THandle): Boolean; virtual; abstract;

    procedure StartLoop; virtual; abstract;
    procedure StopLoop; virtual; abstract;

    /// <summary>
    ///   建立监听
    /// </summary>
    /// <param name="AHost">
    ///   地址
    ///   <list type="bullet">
    ///     <item>
    ///       '', 监听所有IPv4及IPv6地址
    ///     </item>
    ///     <item>
    ///       '0.0.0.0', 监听所有IPv4地址
    ///     </item>
    ///     <item>
    ///       '::', 监听所有IPv6地址
    ///     </item>
    ///     <item>
    ///       '127.0.0.1', 监听本地IPv4回环地址
    ///     </item>
    ///     <item>
    ///       '::1', 监听本地IPv6回环地址
    ///     </item>
    ///   </list>
    /// </param>
    /// <param name="APort">
    ///   端口
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <returns>
    ///   返回值只能表明 bind 是否调用成功
    ///   <list type="bullet">
    ///     <item>
    ///       0, 调用成功
    ///     </item>
    ///     <item>
    ///       非0, 调用失败
    ///     </item>
    ///   </list>
    ///   当回调被触发时才表明监听成功或失败
    /// </returns>
    function Listen(const AHost: string; APort: Word;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; virtual; abstract;

    /// <summary>
    ///   连接到服务器
    /// </summary>
    /// <param name="AHost">
    ///   地址
    /// </param>
    /// <param name="APort">
    ///   端口
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <returns>
    ///   返回值只能表明 connect 调用是否成功
    ///   <list type="bullet">
    ///     <item>
    ///       0, 调用成功
    ///     </item>
    ///     <item>
    ///       非0, 调用失败
    ///     </item>
    ///   </list>
    ///   当回调被触发时才表明连接建立或连接失败
    /// </returns>
    function Connect(const AHost: string; APort: Word;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; virtual; abstract;

    // 发送数据, 返回发送的字节数, -1失败
    // 由于发送是异步的, 所以需要调用者保证发送完成之前缓存的有效性
    // 发送可能会被拆成多次io调用, 返回值只能表明首次发送成功与否
    /// <summary>
    ///   向指定套接字发送数据
    /// </summary>
    /// <param name="ASocket">
    ///   套接字
    /// </param>
    /// <param name="ABuf">
    ///   待发送数据
    /// </param>
    /// <param name="ALen">
    ///   数据尺寸
    /// </param>
    /// <param name="ACallback">
    ///   回调函数
    /// </param>
    /// <returns>
    ///   返回值只能表明 send 是否调用成功
    ///   <list type="bullet">
    ///     <item>
    ///       0, 调用成功
    ///     </item>
    ///     <item>
    ///       非0, 调用失败
    ///     </item>
    ///   </list>
    ///   当回调被触发时才表明发送成功或失败
    /// </returns>
    function Send(ASocket: THandle; const ABuf; ALen: Integer;
      const ACallback: TProc<THandle, Boolean> = nil): Integer; virtual; abstract;

    function Disconnect(ASocket: THandle): Integer; virtual;
    function CloseSocket(ASocket: THandle): Integer; virtual;
    function StopListen(ASocket: THandle): Integer; virtual;
    procedure CloseAllConnections; virtual; abstract;
    procedure CloseAllListens; virtual; abstract;
    procedure CloseAll; virtual; abstract;
    procedure DisconnectAll; virtual; abstract;

    property ListensCount: Integer read FListensCount;
    property ConnectionsCount: Integer read FConnectionsCount;
  public
    constructor Create(AIoThreads: Integer); virtual;

    procedure BeforeDestruction; override;

    property IoThreads: Integer read GetIoThreads;
  end;

  procedure __RaiseLastOSError;
  function _Again(AErrCode: Integer): Boolean;

implementation

procedure __RaiseLastOSError;
{$IFDEF DEBUG}
var
  LError: Integer;
  LErrMsg: string;
{$ENDIF}
begin
  {$IFDEF DEBUG}
  LError := GetLastError;
  LErrMsg := Format('System Error.  Code: %d, %s',
    [LError, SysErrorMessage(LError)]);
  if IsConsole then
    Writeln(LErrMsg)
  else
    AppendLog(LErrMsg);
//  RaiseLastOSError(LError);
  {$ENDIF}
end;

function _Again(AErrCode: Integer): Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := (AErrCode = WSAEINTR)
    or (AErrCode = WSAEWOULDBLOCK)
    or (AErrCode = WSAEINPROGRESS);
  {$ENDIF MSWINDOWS}

  {$IFDEF POSIX}
  // EINTR 被系统中断调用暂时打断
  // EAGAIN(EWOULDBLOCK) 缓存中没数据了
  Result := (AErrCode = EINTR)
    or (AErrCode = EAGAIN)
    or (AErrCode = EWOULDBLOCK);
  {$ENDIF}
end;

{ TIoEventThread }

constructor TIoEventThread.Create(ALoop: TAbstractEventLoop);
begin
  inherited Create(True);
  FLoop := ALoop;
  Suspended := False;
end;

procedure TIoEventThread.Execute;
{$IFDEF DEBUG}
var
  LRunCount: Int64;
{$ENDIF}
begin
  {$IFDEF DEBUG}
  LRunCount := 0;
  {$ENDIF}
  while not Terminated do
  begin
    try
      if not FLoop.ProcessIoEvent then Break;
    except
      {$IFDEF DEBUG}
      on e: Exception do
        AppendLog('%s Io线程ID %d, 异常 %s, %s', [FLoop.ClassName, Self.ThreadID, e.ClassName, e.Message]);
      {$ENDIF}
    end;
    {$IFDEF DEBUG}
    Inc(LRunCount)
    {$ENDIF};
  end;
  {$IFDEF DEBUG}
  AppendLog('%s Io线程ID %d, 被调用了 %d 次', [FLoop.ClassName, Self.ThreadID, LRunCount]);
  {$ENDIF}
end;

{ TAbstractEventLoop }

constructor TAbstractEventLoop.Create(AIoThreads: Integer);
begin
  FIoThreads := AIoThreads;
end;

function TAbstractEventLoop.CloseSocket(ASocket: THandle): Integer;
begin
  Result := TSocketAPI.CloseSocket(ASocket);
  if (Result = 0) then
    TriggerDisconnected(ASocket);
end;

function TAbstractEventLoop.Disconnect(ASocket: THandle): Integer;
begin
  Result := TSocketAPI.Shutdown(ASocket, 2);
end;

procedure TAbstractEventLoop.BeforeDestruction;
begin
  StopLoop;
  inherited BeforeDestruction;
end;

function TAbstractEventLoop.GetIoThreads: Integer;
begin
  if (FIoThreads > 0) then
    Result := FIoThreads
  else
    Result := CPUCount * 2 + 1;
end;

function TAbstractEventLoop.SetKeepAlive(ASocket: THandle): Integer;
begin
  Result := TSocketAPI.SetKeepAlive(ASocket, 5, 3, 5);
end;

function TAbstractEventLoop.StopListen(ASocket: THandle): Integer;
begin
  Result := TSocketAPI.CloseSocket(ASocket);
  if (Result = 0) then
    TriggerListenEnd(ASocket);
end;

end.
