unit Utils.EasyThread;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Types,

  Utils.AnonymousThread;

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
    FTerminated: Boolean;

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

implementation

{ TEasyThread }

constructor TEasyThread.Create(const AEasyThreadProc: TAnonymousProc);
begin
  FThread := TAnonymousThread.Create(
    procedure
    begin
      if Assigned(AEasyThreadProc) then
        AEasyThreadProc();
    end);

  FThread.FreeOnTerminate := False;
  FThread.Start;
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
  WaitFor;

  FreeAndNil(FThread);

  inherited;
end;

function TEasyThread.GetTerminated: Boolean;
begin
  Result := FTerminated;
end;

function TEasyThread.GetThreadID: TThreadID;
begin
  Result := FThread.ThreadID;
end;

procedure TEasyThread.Terminate;
begin
  FTerminated := True;
end;

procedure TEasyThread.WaitFor;
begin
  // TThread.WaitFor 在线程退出后调用会死循环
  // 所以这里通过检查线程的结束状态(FThread.Finished)来实现
  while (FThread <> nil) and not FThread.Finished do
    Sleep(1);
end;

end.
