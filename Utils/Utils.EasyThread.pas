unit Utils.EasyThread;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Types,

  Utils.AnonymousThread,
  Utils.SyncObjs;

type
  IEasyThread = interface;

  TEasyThreadProc = reference to procedure(const AEasyThread: IEasyThread);

  IEasyThread = interface
  ['{0515FF7C-50A4-4A49-B2C4-F38A52BC97EB}']
    function GetTerminated: Boolean;
    function GetThreadID: TThreadID;

    procedure Terminate;
    procedure WaitFor;

    property Terminated: Boolean read GetTerminated;
    property ThreadID: TThreadID read GetThreadID;
  end;

  TEasyThread = class(TInterfacedObject, IEasyThread)
  private
    FThread: TThread;
    FTerminated: Integer;
    FThreadStarted: Boolean;
    FJoined: Integer;
    FWaitLock: ILock;

    function _IsWorkerThread: Boolean;
    function GetTerminated: Boolean;
    function GetThreadID: TThreadID;
  public
    constructor Create(const AEasyThreadProc: TAnonymousProc); overload;
    constructor Create(const AEasyThreadProc: TEasyThreadProc); overload;
    destructor Destroy; override;

    procedure Terminate;
    procedure WaitFor;

    property Terminated: Boolean read GetTerminated;
    property ThreadID: TThreadID read GetThreadID;
  end;

{$IFDEF CROSS_EASY_THREAD_TESTS}
procedure SetEasyThreadStartHook(const AHook: TAnonymousProc);
{$ENDIF}

implementation

{$IFDEF CROSS_EASY_THREAD_TESTS}
var
  GEasyThreadStartHook: TAnonymousProc;

procedure SetEasyThreadStartHook(const AHook: TAnonymousProc);
begin
  GEasyThreadStartHook := AHook;
end;
{$ENDIF}

{ TEasyThread }

constructor TEasyThread.Create(const AEasyThreadProc: TAnonymousProc);
begin
  FWaitLock := TLock.Create;
  FThread := TAnonymousThread.Create(
    procedure
    begin
      if Assigned(AEasyThreadProc) then
        AEasyThreadProc();
    end);

  FThread.FreeOnTerminate := False;
  {$IFDEF CROSS_EASY_THREAD_TESTS}
  if Assigned(GEasyThreadStartHook) then GEasyThreadStartHook();
  {$ENDIF}
  FThread.Start;
  FThreadStarted := True;
end;

constructor TEasyThread.Create(const AEasyThreadProc: TEasyThreadProc);
var
  LEasyThread: IEasyThread;
begin
  LEasyThread := Self;

  Create(
    procedure
    begin
      try
        if Assigned(AEasyThreadProc) then
          AEasyThreadProc(LEasyThread);
      finally
        LEasyThread := nil;
      end;
    end);
end;

destructor TEasyThread.Destroy;
begin
  Terminate;
  if FThread <> nil then
  begin
    if _IsWorkerThread then
    begin
      // Execute 尚未返回，不能等待或释放正在执行自身回调的 TThread。
      FThread.FreeOnTerminate := True;
      FThread := nil;
    end else
    begin
      WaitFor;
      FreeAndNil(FThread);
    end;
  end;

  inherited;
end;

function TEasyThread.GetTerminated: Boolean;
begin
  Result := AtomicCmpExchange(FTerminated, 0, 0) <> 0;
end;

function TEasyThread._IsWorkerThread: Boolean;
begin
  // 已结束或已 join 的线程 ID 可能被新线程复用，不能据此转交自动释放。
  Result := (FThread <> nil) and (AtomicCmpExchange(FJoined, 0, 0) = 0)
    and not FThread.Finished
    and (FThread.ThreadID = TThread.CurrentThread.ThreadID);
end;

function TEasyThread.GetThreadID: TThreadID;
begin
  Result := FThread.ThreadID;
end;

procedure TEasyThread.Terminate;
begin
  AtomicExchange(FTerminated, 1);
end;

procedure TEasyThread.WaitFor;
begin
  if (FThread = nil) or not FThreadStarted then Exit;
  // 必须先识别工作线程；外部 waiter 可能持有等待锁并等待当前回调结束。
  if _IsWorkerThread then Exit;
  FWaitLock.Enter;
  try
    if AtomicCmpExchange(FJoined, 0, 0) = 0 then
    begin
      // Finished 不代表原生线程已经回收，首次 join 仍不可省略。
      FThread.WaitFor;
      AtomicExchange(FJoined, 1);
    end;
  finally
    FWaitLock.Leave;
  end;
end;

end.
