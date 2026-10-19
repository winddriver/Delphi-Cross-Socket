{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpSessions;

{$I zLib.inc}

interface

uses
  SysUtils, Classes, Generics.Collections,
  {$IFDEF FPC}DTF.Types,{$ENDIF}
  Utils.SyncObjs;

type
  TSessionsBase = class;
  ISessions = interface;

  /// <summary>
  ///   Session成员接口
  /// </summary>
  ISession = interface
  ['{A3D525A1-C534-4CE6-969B-53C5B8CB77C3}']
    function GetOwner: ISessions;

    function GetSessionID: string;
    function GetCreateTime: TDateTime;
    function GetLastAccessTime: TDateTime;
    function GetExpiryTime: Integer;
    function GetValue(const AName: string): string;
    procedure SetSessionID(const ASessionID: string);
    procedure SetCreateTime(const ACreateTime: TDateTime);
    procedure SetLastAccessTime(const ALastAccessTime: TDateTime);
    procedure SetExpiryTime(const Value: Integer);
    procedure SetValue(const AName, AValue: string);

    /// <summary>
    ///   更新最后访问时间
    /// </summary>
    procedure Touch;

    /// <summary>
    ///   是否已过期
    /// </summary>
    function Expired: Boolean;

    /// <summary>
    ///   父容器
    /// </summary>
    property Owner: ISessions read GetOwner;

    /// <summary>
    ///   Session ID
    /// </summary>
    property SessionID: string read GetSessionID write SetSessionID;

    /// <summary>
    ///   创建时间
    /// </summary>
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;

    /// <summary>
    ///   最后访问时间
    /// </summary>
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;

    /// <summary>
    ///   Session过期时间(秒)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       值大于0时, 当Session超过设定值秒数没有使用就会被释放;
    ///     </item>
    ///     <item>
    ///       值等于0时, 使用父容器的超时设置
    ///     </item>
    ///     <item>
    ///       值小于0时, Session生成后一直有效
    ///     </item>
    ///   </list>
    /// </remarks>
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;

    /// <summary>
    ///   Session是一个KEY-VALUE结构的数据, 该属性用于访问其中的成员值
    /// </summary>
    property Values[const AName: string]: string read GetValue write SetValue; default;
  end;

  TSessionBase = class abstract(TInterfacedObject, ISession)
  private
    FOwner: TSessionsBase;
  protected
    function GetOwner: ISessions;
    function GetSessionID: string; virtual; abstract;
    function GetCreateTime: TDateTime; virtual; abstract;
    function GetLastAccessTime: TDateTime; virtual; abstract;
    function GetExpiryTime: Integer; virtual; abstract;
    function GetValue(const AName: string): string; virtual; abstract;
    procedure SetSessionID(const ASessionID: string); virtual; abstract;
    procedure SetCreateTime(const ACreateTime: TDateTime); virtual; abstract;
    procedure SetLastAccessTime(const ALastAccessTime: TDateTime); virtual; abstract;
    procedure SetExpiryTime(const Value: Integer); virtual; abstract;
    procedure SetValue(const AName, AValue: string); virtual; abstract;
  public
    constructor Create(const AOwner: TSessionsBase; const ASessionID: string); virtual;

    procedure Touch; virtual;
    function Expired: Boolean; virtual;

    property Owner: ISessions read GetOwner;

    property SessionID: string read GetSessionID write SetSessionID;
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
    property Values[const AName: string]: string read GetValue write SetValue; default;
  end;

  TSession = class(TSessionBase)
  protected
    FSessionID: string;
    FCreateTime: TDateTime;
    FLastAccessTime: TDateTime;
    FExpire: Integer;
    FValues: TDictionary<string, string>;

    function GetSessionID: string; override;
    function GetCreateTime: TDateTime; override;
    function GetLastAccessTime: TDateTime; override;
    function GetExpiryTime: Integer; override;
    function GetValue(const AName: string): string; override;
    procedure SetSessionID(const ASessionID: string); override;
    procedure SetCreateTime(const ACreateTime: TDateTime); override;
    procedure SetLastAccessTime(const ALastAccessTime: TDateTime); override;
    procedure SetExpiryTime(const AValue: Integer); override;
    procedure SetValue(const AName, AValue: string); override;
  public
    constructor Create(const AOwner: TSessionsBase; const ASessionID: string); override;
    destructor Destroy; override;

    property SessionID: string read GetSessionID write SetSessionID;
    property CreateTime: TDateTime read GetCreateTime write SetCreateTime;
    property LastAccessTime: TDateTime read GetLastAccessTime write SetLastAccessTime;
    property Values[const AName: string]: string read GetValue write SetValue; default;
  end;

  TSessionClass = class of TSessionBase;

  /// <summary>
  ///   Session管理接口
  /// </summary>
  ISessions = interface
  ['{5187CA76-4CC4-4986-B67B-BC3E76D6CD74}']
    function GetEnumerator: TEnumerator<ISession>;

    function GetSessionClass: TSessionClass;
    function GetCount: Integer;
    function GetItem(const AIndex: Integer): ISession;
    /// <summary>内部写锁检查过期并续期；不要在外部读锁内调用。</summary>
    function GetSession(const ASessionID: string): ISession;
    function GetExpiryTime: Integer;
    procedure SetSessionClass(const Value: TSessionClass);
    procedure SetExpiryTime(const Value: Integer);

    /// <summary>
    ///   开始写(用于线程同步)
    /// </summary>
    procedure BeginWrite;

    /// <summary>
    ///   结束写(用于线程同步)
    /// </summary>
    procedure EndWrite;

    /// <summary>
    ///   开始读(用于线程同步)
    /// </summary>
    procedure BeginRead;

    /// <summary>
    ///   结束读(用于线程同步)
    /// </summary>
    procedure EndRead;

    /// <summary>
    ///   生成新Session ID
    /// </summary>
    function NewSessionID: string;

    /// <summary>
    ///   检查是否存在指定ID的Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <param name="ASession">
    ///   如果存在指定的Session， 则将实例保存到该参数中
    /// </param>
    /// <remarks>会检查过期并刷新访问时间；不要在外部读锁内调用。</remarks>
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; overload;

    /// <summary>
    ///   检查是否存在指定ID的Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <remarks>会检查过期并刷新访问时间；不要在外部读锁内调用。</remarks>
    function ExistsSession(const ASessionID: string): Boolean; overload;

    /// <summary>
    ///   新增Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <returns>
    ///   Session实例
    /// </returns>
    function AddSession(const ASessionID: string): ISession; overload;

    /// <summary>
    ///   新增Session
    /// </summary>
    /// <returns>
    ///   Session实例
    /// </returns>
    function AddSession: ISession; overload;

    /// <summary>
    ///   新增Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <param name="ASession">
    ///   Session实例
    /// </param>
    procedure AddSession(const ASessionID: string; ASession: ISession); overload;

    /// <summary>
    ///   删除Session
    /// </summary>
    /// <param name="ASession">
    ///   Session对象
    /// </param>
    procedure RemoveSession(const ASession: ISession); overload;

    /// <summary>
    ///   删除Session
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    procedure RemoveSession(const ASessionID: string); overload;

    /// <summary>
    ///   批量删除Session
    /// </summary>
    /// <param name="ASessions">
    ///   Session对象数据
    /// </param>
    procedure RemoveSessions(const ASessions: TArray<ISession>);

    /// <summary>
    ///   清除所有Session
    /// </summary>
    procedure Clear;

    /// <summary>
    ///   Session类
    /// </summary>
    property SessionClass: TSessionClass read GetSessionClass write SetSessionClass;

    /// <summary>
    ///   Session个数
    /// </summary>
    property Count: Integer read GetCount;

    /// <summary>
    ///   获取指定序号的Session, 如果不存在则返回nil
    /// </summary>
    property Items[const AIndex: Integer]: ISession read GetItem;

    /// <summary>
    ///   获取有效Session；未知或过期ID会被替换为新的服务端ID
    /// </summary>
    /// <param name="ASessionID">
    ///   Session ID
    /// </param>
    /// <remarks>本属性会取得写锁并刷新访问时间；不要在外部读锁内调用。</remarks>
    property Sessions[const ASessionID: string]: ISession read GetSession; default;

    /// <summary>
    ///   Session过期时间(秒)
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       值大于0时, 当Session超过设定值秒数没有使用就会被释放;
    ///     </item>
    ///     <item>
    ///       值小于等于0时, Session生成后一直有效
    ///     </item>
    ///   </list>
    /// </remarks>
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
  end;

  TSessionsBase = class abstract(TInterfacedObject, ISessions)
  protected
    function GetSessionClass: TSessionClass; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetItem(const AIndex: Integer): ISession; virtual; abstract;
    function GetSession(const ASessionID: string): ISession; virtual; abstract;
    function GetExpiryTime: Integer; virtual; abstract;
    procedure SetSessionClass(const Value: TSessionClass); virtual; abstract;
    procedure SetExpiryTime(const Value: Integer); virtual; abstract;
  public
    function GetEnumerator: TEnumerator<ISession>; virtual; abstract;

    procedure BeginWrite; virtual; abstract;
    procedure EndWrite; virtual; abstract;

    procedure BeginRead; virtual; abstract;
    procedure EndRead; virtual; abstract;

    function NewSessionID: string; virtual; abstract;
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; overload; virtual; abstract;
    function ExistsSession(const ASessionID: string): Boolean; overload; virtual;
    function AddSession(const ASessionID: string): ISession; overload; virtual;
    function AddSession: ISession; overload;
    procedure AddSession(const ASessionID: string; ASession: ISession); overload; virtual; abstract;

    procedure RemoveSessions(const ASessions: TArray<ISession>); virtual; abstract;
    procedure RemoveSession(const ASession: ISession); overload; virtual;
    procedure RemoveSession(const ASessionID: string); overload; virtual;

    procedure Clear; virtual; abstract;

    property SessionClass: TSessionClass read GetSessionClass write SetSessionClass;
    property Count: Integer read GetCount;
    property Items[const AIndex: Integer]: ISession read GetItem;
    property Sessions[const ASessionID: string]: ISession read GetSession; default;
    property ExpiryTime: Integer read GetExpiryTime write SetExpiryTime;
  end;

  {$IFDEF CROSS_SESSION_TESTS}
  TSessionTestHook = reference to procedure;
  TSessionTestOptions = record
    BeforeStart, BeforeThreadStart, AfterThreadStart, BeforeCleanup, AfterThreadExit, BeforeDestroyWait: TSessionTestHook;
    CleanupIntervalMs: Cardinal;
  end;
  {$ENDIF}

  TSessions = class(TSessionsBase)
  private
    FNewGUIDFunc: TFunc<string>;
    FLocker: IReadWriteLock;
    FSessionClass: TSessionClass;
    FExpire: Integer;
    FShutdown: Integer;
    FExpiredThread: TThread;
    FExpiredThreadStarted: Boolean;
    FStopEvent: IEvent;
    {$IFDEF CROSS_SESSION_TESTS}
    FTestOptions: TSessionTestOptions;
    {$ENDIF}

    procedure _ClearExpiredSessions;
    function _FindSessionLocked(const ASessionID: string; out ASession: ISession): Boolean;
  protected
    FSessions: TDictionary<string, ISession>;

    function GetSessionClass: TSessionClass; override;
    function GetCount: Integer; override;
    function GetItem(const AIndex: Integer): ISession; override;
    function GetSession(const ASessionID: string): ISession; override;
    function GetExpiryTime: Integer; override;
    procedure SetSessionClass(const Value: TSessionClass); override;
    procedure SetExpiryTime(const Value: Integer); override;

    procedure BeforeClearExpiredSessions; virtual;
    function OnCheckExpiredSession(const ASession: ISession): Boolean; virtual;
    procedure AfterClearExpiredSessions; virtual;
    procedure CreateExpiredProcThread;
  public
    constructor Create(ANewGUIDFunc: TFunc<string>); overload; virtual;
    constructor Create; overload; virtual;
    destructor Destroy; override;

    function GetEnumerator: TEnumerator<ISession>; override;

    procedure BeginWrite; override;
    procedure EndWrite; override;

    procedure BeginRead; override;
    procedure EndRead; override;

    function NewSessionID: string; override;
    function ExistsSession(const ASessionID: string; var ASession: ISession): Boolean; override;
    procedure AddSession(const ASessionID: string; ASession: ISession); override;

    procedure RemoveSessions(const ASessions: TArray<ISession>); override;

    procedure Clear; override;

    property NewGUIDFunc: TFunc<string> read FNewGUIDFunc write FNewGUIDFunc;
  end;

{$IFDEF CROSS_SESSION_TESTS}
procedure SetSessionTestOptions(const AOptions: TSessionTestOptions);
procedure ClearExpiredSessionsForTest(const ASessions: TSessions);
{$ENDIF}

implementation

uses
  Utils.AnonymousThread, Utils.DateTime, Utils.Utils;

{$IFDEF CROSS_SESSION_TESTS}
var
  GSessionTestOptions: TSessionTestOptions;

procedure SetSessionTestOptions(const AOptions: TSessionTestOptions);
begin
  GSessionTestOptions := AOptions;
end;

procedure ClearExpiredSessionsForTest(const ASessions: TSessions);
begin
  ASessions._ClearExpiredSessions;
end;
{$ENDIF}

{ TSessionBase }

constructor TSessionBase.Create(const AOwner: TSessionsBase; const ASessionID: string);
var
  LNow: TDateTime;
begin
  LNow := Now;

  FOwner := AOwner;

  SetSessionID(ASessionID);
  SetCreateTime(LNow);
  SetLastAccessTime(LNow);
end;

function TSessionBase.Expired: Boolean;
begin
  Result := (ExpiryTime > 0) and (Now.SecondsDiffer(LastAccessTime) >= ExpiryTime);
end;

function TSessionBase.GetOwner: ISessions;
begin
  Result := FOwner;
end;

procedure TSessionBase.Touch;
begin
  LastAccessTime := Now;
end;

{ TSession }

constructor TSession.Create(const AOwner: TSessionsBase; const ASessionID: string);
begin
  FValues := TDictionary<string, string>.Create;

  inherited Create(AOwner, ASessionID);
end;

destructor TSession.Destroy;
begin
  FreeAndNil(FValues);
  inherited;
end;

function TSession.GetCreateTime: TDateTime;
begin
  Result := FCreateTime;
end;

function TSession.GetExpiryTime: Integer;
begin
  Result := FExpire;
end;

function TSession.GetLastAccessTime: TDateTime;
begin
  Result := FLastAccessTime;
end;

function TSession.GetSessionID: string;
begin
  Result := FSessionID;
end;

function TSession.GetValue(const AName: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := '';
  FLastAccessTime := Now;
end;

procedure TSession.SetCreateTime(const ACreateTime: TDateTime);
begin
  FCreateTime := ACreateTime;
end;

procedure TSession.SetExpiryTime(const AValue: Integer);
begin
  FExpire := AValue;
end;

procedure TSession.SetLastAccessTime(const ALastAccessTime: TDateTime);
begin
  FLastAccessTime := ALastAccessTime;
end;

procedure TSession.SetSessionID(const ASessionID: string);
begin
  FSessionID := ASessionID;
end;

procedure TSession.SetValue(const AName, AValue: string);
begin
  if (AValue <> '') then
    FValues.AddOrSetValue(AName, AValue)
  else
    FValues.Remove(AName);
  FLastAccessTime := Now;
end;

{ TSessionsBase }

function TSessionsBase.AddSession(const ASessionID: string): ISession;
begin
  Result := GetSessionClass.Create(Self, ASessionID);
  Result.ExpiryTime := ExpiryTime;
  AddSession(ASessionID, Result);
end;

function TSessionsBase.AddSession: ISession;
begin
  Result := AddSession(NewSessionID);
end;

function TSessionsBase.ExistsSession(const ASessionID: string): Boolean;
var
  LStuff: ISession;
begin
  Result := ExistsSession(ASessionID, LStuff);
end;

procedure TSessionsBase.RemoveSession(const ASessionID: string);
var
  LSession: ISession;
begin
  if ExistsSession(ASessionID, LSession) then
    RemoveSession(LSession);
end;

procedure TSessionsBase.RemoveSession(const ASession: ISession);
begin
  RemoveSessions([ASession]);
end;

{ TSessions }

constructor TSessions.Create(ANewGUIDFunc: TFunc<string>);
begin
  {$IFDEF CROSS_SESSION_TESTS}
  FTestOptions := GSessionTestOptions;
  if FTestOptions.CleanupIntervalMs = 0 then FTestOptions.CleanupIntervalMs := 60000;
  {$ENDIF}
  FNewGUIDFunc := ANewGUIDFunc;
  FSessions := TDictionary<string, ISession>.Create;
  FLocker := TReadWriteLock.Create;
  FSessionClass := TSession;
  FStopEvent := TEvent.Create(True, False);
  CreateExpiredProcThread;
end;

procedure TSessions.Clear;
begin
  FSessions.Clear;
end;

constructor TSessions.Create;
begin
  Create(nil);
end;

destructor TSessions.Destroy;
begin
  AtomicExchange(FShutdown, 1);
  if FStopEvent <> nil then FStopEvent.SetEvent;
  {$IFDEF CROSS_SESSION_TESTS}
  if Assigned(FTestOptions.BeforeDestroyWait) then FTestOptions.BeforeDestroyWait();
  {$ENDIF}
  // 不持会话锁等待；线程真正退出后才释放其可能访问的字典和锁。
  if FExpiredThread <> nil then
  begin
    if FExpiredThreadStarted then FExpiredThread.WaitFor;
    FreeAndNil(FExpiredThread);
  end;
  if FLocker <> nil then
  begin
    BeginWrite;
    try
      if FSessions <> nil then FSessions.Clear;
    finally
      EndWrite;
    end;
  end;
  FreeAndNil(FSessions);

  inherited;
end;

procedure TSessions.AddSession(const ASessionID: string; ASession: ISession);
begin
  if (ASession.ExpiryTime = 0) then
    ASession.ExpiryTime := ExpiryTime;
  FSessions.AddOrSetValue(ASessionID, ASession);
end;

procedure TSessions.AfterClearExpiredSessions;
begin

end;

procedure TSessions.BeforeClearExpiredSessions;
begin

end;

procedure TSessions.BeginRead;
begin
  FLocker.BeginRead;
end;

procedure TSessions.BeginWrite;
begin
  FLocker.BeginWrite;
end;

procedure TSessions.EndRead;
begin
  FLocker.EndRead;
end;

procedure TSessions.EndWrite;
begin
  FLocker.EndWrite;
end;

function TSessions.ExistsSession(const ASessionID: string;
  var ASession: ISession): Boolean;
begin
  BeginWrite;
  try
    Result := _FindSessionLocked(ASessionID, ASession);
  finally
    EndWrite;
  end;
end;

function TSessions._FindSessionLocked(const ASessionID: string;
  out ASession: ISession): Boolean;
begin
  ASession := nil;
  Result := FSessions.TryGetValue(ASessionID, ASession);
  if not Result then Exit;
  if OnCheckExpiredSession(ASession) then
  begin
    FSessions.Remove(ASessionID);
    ASession := nil;
    Exit(False);
  end;
  ASession.Touch;
end;

procedure TSessions.CreateExpiredProcThread;
begin
  FExpiredThread := TAnonymousThread.Create(
    procedure
    var
      LInterval: Cardinal;
    begin
      try
        {$IFDEF CROSS_SESSION_TESTS}
        if Assigned(FTestOptions.BeforeThreadStart) then FTestOptions.BeforeThreadStart();
        if Assigned(FTestOptions.AfterThreadStart) then FTestOptions.AfterThreadStart();
        {$ENDIF}
        LInterval := 60000;
        {$IFDEF CROSS_SESSION_TESTS}
        LInterval := FTestOptions.CleanupIntervalMs;
        {$ENDIF}
        while FStopEvent.WaitFor(LInterval) = TWaitResult.wrTimeout do
        begin
          if AtomicCmpExchange(FShutdown, 0, 0) <> 0 then Break;
          if GetExpiryTime > 0 then
          begin
            {$IFDEF CROSS_SESSION_TESTS}
            if Assigned(FTestOptions.BeforeCleanup) then FTestOptions.BeforeCleanup();
            {$ENDIF}
            if AtomicCmpExchange(FShutdown, 0, 0) = 0 then _ClearExpiredSessions;
          end;
        end;
      finally
        {$IFDEF CROSS_SESSION_TESTS}
        if Assigned(FTestOptions.AfterThreadExit) then FTestOptions.AfterThreadExit();
        {$ENDIF}
      end;
    end);
  FExpiredThread.FreeOnTerminate := False;
  {$IFDEF CROSS_SESSION_TESTS}
  if Assigned(FTestOptions.BeforeStart) then FTestOptions.BeforeStart();
  {$ENDIF}
  FExpiredThread.Start;
  FExpiredThreadStarted := True;
end;

function TSessions.NewSessionID: string;
begin
  if Assigned(FNewGUIDFunc) then
    Result := FNewGUIDFunc()
  else
    Result := TUtils.GetGUID.ToLower;
end;

function TSessions.OnCheckExpiredSession(const ASession: ISession): Boolean;
begin
  Result := ASession.Expired;
end;

function TSessions.GetCount: Integer;
begin
  Result := FSessions.Count;
end;

function TSessions.GetEnumerator: TEnumerator<ISession>;
begin
  Result := TDictionary<string, ISession>.TValueEnumerator.Create(FSessions);
end;

function TSessions.GetExpiryTime: Integer;
begin
  Result := AtomicCmpExchange(FExpire, 0, 0);
end;

function TSessions.GetItem(const AIndex: Integer): ISession;
var
  LIndex: Integer;
  LPair: TPair<string, ISession>;
begin
  LIndex := 0;
  for LPair in FSessions do
  begin
    if (LIndex = AIndex) then Exit(LPair.Value);
    Inc(LIndex);
  end;
  Result := nil;
end;

function TSessions.GetSession(const ASessionID: string): ISession;
var
  LSessionID: string;
  I: Integer;
begin
  BeginWrite;
  try
    if _FindSessionLocked(ASessionID, Result) then Exit;
    // 显式 AddSession(ID) 仍可导入指定 ID；客户端未知 ID 不参与新会话创建。
    for I := 1 to 16 do
    begin
      LSessionID := NewSessionID;
      if (LSessionID = '') or (LSessionID = ASessionID)
        or FSessions.ContainsKey(LSessionID) then Continue;
      Result := FSessionClass.Create(Self, LSessionID);
      Result.ExpiryTime := ExpiryTime;
      AddSession(LSessionID, Result);
      Exit;
    end;
    raise Exception.Create('无法生成唯一的 Session ID');
  finally
    EndWrite;
  end;
end;

function TSessions.GetSessionClass: TSessionClass;
begin
  Result := FSessionClass;
end;

procedure TSessions.RemoveSessions(const ASessions: TArray<ISession>);
var
  LSession: ISession;
begin
  for LSession in ASessions do
    FSessions.Remove(LSession.SessionID);
end;

procedure TSessions.SetExpiryTime(const Value: Integer);
begin
  AtomicExchange(FExpire, Value);
end;

procedure TSessions.SetSessionClass(const Value: TSessionClass);
begin
  FSessionClass := Value;
end;

procedure TSessions._ClearExpiredSessions;
var
  LPair: TPair<string, ISession>;
  LDelSessions: TArray<ISession>;
  LCount, LCapacity, LTotal: NativeInt;
begin
  LDelSessions := nil;
  try
    BeginWrite;
    try
      BeforeClearExpiredSessions;

      // 判定和删除保持在同一写锁内，续期/同 ID 替换不会插入其中。
      LTotal := FSessions.Count;
      LCount := 0;
      for LPair in FSessions do
      begin
        if AtomicCmpExchange(FShutdown, 0, 0) <> 0 then Break;
        if OnCheckExpiredSession(LPair.Value) then
        begin
          // 零过期不分配快照；稀疏过期只保留小数组，满后几何增长。
          if LCount = Length(LDelSessions) then
          begin
            if LCount = 0 then LCapacity := 8
            else if LCount <= LTotal div 2 then LCapacity := LCount * 2
            else LCapacity := LTotal;
            if LCapacity > LTotal then LCapacity := LTotal;
            SetLength(LDelSessions, LCapacity);
          end;
          LDelSessions[LCount] := LPair.Value;
          Inc(LCount);
        end;
      end;
      SetLength(LDelSessions, LCount);
      RemoveSessions(LDelSessions);

      AfterClearExpiredSessions;
    finally
      EndWrite;
    end;
  finally
    // 包括钩子抛异常的路径，删除对象的最后引用也只在解锁后释放。
    LPair.Value := nil;
    LDelSessions := nil;
  end;
end;

end.
