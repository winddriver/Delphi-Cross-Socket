{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Utils.Logger;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils,
  {$IFDEF DELPHI}
  System.Diagnostics,
  {$ELSE}
  DTF.Diagnostics,
  {$ENDIF}
  Generics.Collections,

  Utils.StrUtils,
  Utils.Utils,
  Utils.DateTime,
  Utils.AnonymousThread,
  Utils.IOUtils,
  Utils.SyncObjs;

type
  TLogType = (ltNormal, ltWarning, ltError, ltException);
  TLogTypeSets = set of TLogType;

const
  LogTypeStr: array [TLogType] of string = ('', 'WAR', 'ERR', 'EXP');

type
  ILogger = interface
  ['{D9AE7F7B-95DE-4840-98FA-A49A4368D658}']
    function GetFilters: TLogTypeSets;
    procedure SetFilters(const Value: TLogTypeSets);

    function GetLogDir: string;
    function GetLogFileName(ALogType: TLogType; ADate: TDateTime): string;

    procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const AFmt: string; const AArgs: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const AFmt: string; const AArgs: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;

    procedure Flush;

    property Filters: TLogTypeSets read GetFilters write SetFilters;
  end;

  TLogItem = record
    Time: TDateTime;
    Text: string;
  end;

  TLogBuffer = TList<TLogItem>;

  TLogger = class(TInterfacedObject, ILogger)
  private const
    //FLUSH_INTERVAL = 200;
    FLUSH_INTERVAL = 1000;
  private
    FFilters: TLogTypeSets;
    FLogName: string;
    FWriteThread: TThread;

    class var FDefault: ILogger;
    class function GetDefault: ILogger; static;
    class procedure SetDefault(const Value: ILogger); static;

    function GetFilters: TLogTypeSets;
    procedure SetFilters(const Value: TLogTypeSets);
  private
    FBuffer: array [TLogType] of TLogBuffer;
    FBufferLock: array [TLogType] of ILock;
    FShutdown: Boolean;

    procedure _Lock(const ALogType: TLogType); inline;
    procedure _Unlock(const ALogType: TLogType); inline;
    procedure _WriteLogFile(const ALogType: TLogType);
    procedure _WriteAllLogFiles; inline;
    procedure _CreateWriteThread;
    procedure _Shutdown; inline;
  protected
    procedure _AppendLogToBuffer(const S: string; ALogType: TLogType);
  public
    constructor Create(const ALogName: string = ''); virtual;
    destructor Destroy; override;

    function GetLogDir: string;
    function GetLogFileName(ALogType: TLogType; ADate: TDateTime): string;

    procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const AFmt: string; const AArgs: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const AFmt: string; const AArgs: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;

    procedure Flush;

    property Filters: TLogTypeSets read GetFilters write SetFilters;

    class property &Default: ILogger read GetDefault write SetDefault;
  end;

procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
procedure AppendLog(const AFmt: string; const AArgs: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
procedure AppendLog(const AFmt: string; const AArgs: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;

function Logger: ILogger;

var
  // 默认日志目录
  // 留空由程序自动设定
  DefaultLogDir: string = '';

implementation

constructor TLogger.Create(const ALogName: string);
var
  I: TLogType;
begin
  FLogName := ALogName;
  if (FLogName = '') then
    FLogName := TUtils.AppName;
  FFilters := [ltNormal, ltWarning, ltError, ltException];

  for I := Low(TLogType) to High(TLogType) do
  begin
    FBuffer[I] := TLogBuffer.Create;
    FBufferLock[I] := TLock.Create;
  end;

  _CreateWriteThread;
end;

destructor TLogger.Destroy;
var
  I: TLogType;
begin
  Flush;

  _Shutdown;

  FreeAndNil(FWriteThread);

  for I := Low(TLogType) to High(TLogType) do
  begin
    FreeAndNil(FBuffer[I]);
    FBufferLock[I] := nil;
  end;

  inherited Destroy;
end;

procedure TLogger.Flush;
begin
  _WriteAllLogFiles;
end;

function TLogger.GetFilters: TLogTypeSets;
begin
  Result := FFilters;
end;

function TLogger.GetLogDir: string;
begin
  if (DefaultLogDir <> '') then
    Result := DefaultLogDir
  else
    Result :=
      {$IF defined(MSWINDOWS) or defined(LINUX)}
      TUtils.AppPath
      {$ELSE}
      TUtils.AppDocuments
      {$ENDIF};

  Result := Result +
      FLogName + '.log' + PathDelim;
end;

function TLogger.GetLogFileName(ALogType: TLogType; ADate: TDateTime): string;
begin
  Result := LogTypeStr[ALogType];
  if (Result <> '') then
    Result := Result + '-';
  Result := Result + TStrUtils.FormatDateTime('YYYY-MM-DD', ADate) + '.log';
end;

class function TLogger.GetDefault: ILogger;
var
  LDefault: ILogger;
begin
  if (FDefault = nil) then
  begin
    LDefault := TLogger.Create;
    if AtomicCmpExchange(Pointer(FDefault), Pointer(LDefault), nil) <> nil then
      LDefault := nil
    else
      FDefault._AddRef;
  end;
  Result := FDefault;
end;

procedure TLogger.SetFilters(const Value: TLogTypeSets);
begin
  FFilters := Value;
end;

class procedure TLogger.SetDefault(const Value: ILogger);
var
  LOldDefault: ILogger;
begin
  LOldDefault := ILogger(AtomicExchange(Pointer(FDefault), Pointer(Value)));
  if (LOldDefault <> nil) then
    LOldDefault._Release;
  if (FDefault <> nil) then
    FDefault._AddRef;
end;

procedure TLogger._CreateWriteThread;
begin
  FWriteThread := TAnonymousThread.Create(
    procedure
    var
      LWatch: TStopwatch;
    begin
      LWatch := TStopwatch.StartNew;
      while not FShutdown do
      begin
        if (LWatch.ElapsedMilliseconds > FLUSH_INTERVAL) then
        begin
          Flush;

          LWatch.Reset;
          LWatch.Start;
        end;
        Sleep(10);
      end;

      Flush;
    end);

  FWriteThread.FreeOnTerminate := False;
  FWriteThread.Start;
end;

procedure TLogger._Lock(const ALogType: TLogType);
begin
  FBufferLock[ALogType].Enter;
end;

procedure TLogger._Shutdown;
begin
  FShutdown := True;

  // Delphi BUG(截止 Delphi 11.3 该 BUG 依然存在)
  // 当程序被编译为 dll, 由第三方程序通过 LoadLibrary/FreeLibrary 的方式动态加载
  // 并且在 class destructor Destroy 中或者 finalization 中执行 TThread.WaitFor
  // 会引起死等(并没有死锁, 只是陷入死循环), 调试发现问题出在 MsgWaitForMultipleObjects
  // 一直返回 258(超时)
  //
  // 所以这里改为 Sleep, 不做 WaitFor, 以免出现上述情况
  Sleep(20);
end;

procedure TLogger._Unlock(const ALogType: TLogType);
begin
  FBufferLock[ALogType].Leave;
end;

procedure TLogger._WriteLogFile(const ALogType: TLogType);
var
  LLogDir, LLogFile: string;
  LLastTime: TDateTime;
  I: Integer;
  LLogItem: TLogItem;
  LBuffer: TMemoryStream;

  procedure _WriteLogToBuffer(const ALogItem: TLogItem);
  var
    LBytes: TBytes;
  begin
    LBytes := TEncoding.UTF8.GetBytes(ALogItem.Text);
    LBuffer.Seek(0, TSeekOrigin.soEnd);
    LBuffer.Write(LBytes, Length(LBytes));

    if IsConsole then
      Write(ALogItem.Text);
  end;

  procedure _WriteBufferToFile(const ALogFile: string);
  var
    LStream: TFileStream;
  begin
    try
      LStream := TFileUtils.OpenWrite(ALogFile);
      try
        LStream.Seek(0, TSeekOrigin.soEnd);
        LStream.Write(LBuffer.Memory^, LBuffer.Size);
        LBuffer.Clear;
      finally
        FreeAndNil(LStream);
      end;
    except
    end;
  end;
begin
  _Lock(ALogType);
  try
    if (FBuffer[ALogType].Count <= 0) then Exit;

    LLastTime := 0;
    LLogDir := GetLogDir;
    ForceDirectories(LLogDir);

    LBuffer := TMemoryStream.Create;
    try
      for I := 0 to FBuffer[ALogType].Count - 1 do
      begin
        LLogItem := FBuffer[ALogType].Items[I];
        _WriteLogToBuffer(LLogItem);

        if not LLogItem.Time.IsSameDay(LLastTime)
          or (I >= FBuffer[ALogType].Count - 1) then
        begin
          LLastTime := LLogItem.Time;
          LLogFile := LLogDir + GetLogFileName(ALogType, LLogItem.Time);
          _WriteBufferToFile(LLogFile);
        end;
      end;
      FBuffer[ALogType].Clear;
    finally
      FreeAndNil(LBuffer);
    end;
  finally
    _Unlock(ALogType);
  end;
end;

procedure TLogger._WriteAllLogFiles;
var
  I: TLogType;
begin
  for I := Low(TLogType) to High(TLogType) do
    _WriteLogFile(I);
end;

procedure TLogger.AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType; const CRLF: string);
var
  LText: string;
begin
  if not (ALogType in FFilters) then Exit;

  if (CRLF <> '') then
    LText := ALog.Replace(sLineBreak, CRLF)
  else
    LText := ALog;
  LText := TStrUtils.FormatDateTime(ATimeFormat, Now) + ' ' + LText + sLineBreak;

//  if IsConsole then
//    Write(LText);

  _AppendLogToBuffer(LText, ALogType);
end;

procedure TLogger.AppendLog(const ALog: string; ALogType: TLogType; const CRLF: string);
begin
  // 不知道什么原因, 在 FPC 中时间格式中的冒号(:)如果不用双引号包裹起来
  // 在 Linux 下调用 FormatDateTime 就有概率格式化出乱码(冒号部分变成乱码)
  AppendLog(ALog,
    {$IFDEF DELPHI}'HH:NN:SS:ZZZ'{$ELSE}'HH":"NN":"SS":"ZZZ'{$ENDIF},
    ALogType, CRLF);
end;

procedure TLogger.AppendLog(const AFmt: string; const AArgs: array of const; const ATimeFormat: string; ALogType: TLogType; const CRLF: string);
begin
  AppendLog(TStrUtils.Format(AFmt, AArgs), ATimeFormat, ALogType, CRLF);
end;

procedure TLogger.AppendLog(const AFmt: string; const AArgs: array of const; ALogType: TLogType; const CRLF: string);
begin
  AppendLog(TStrUtils.Format(AFmt, AArgs), ALogType, CRLF);
end;

procedure TLogger._AppendLogToBuffer(const S: string; ALogType: TLogType);
var
  LLogItem: TLogItem;
begin
  _Lock(ALogType);
  try
    LLogItem.Time := Now;
    LLogItem.Text := S;
    FBuffer[ALogType].Add(LLogItem);
  finally
    _Unlock(ALogType);
  end;
end;

procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = '');
begin
  Logger.AppendLog(ALog, ATimeFormat, ALogType, CRLF);
end;

procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = '');
begin
  Logger.AppendLog(ALog, ALogType, CRLF);
end;

procedure AppendLog(const AFmt: string; const AArgs: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = '');
begin
  Logger.AppendLog(AFmt, AArgs, ATimeFormat, ALogType, CRLF);
end;

procedure AppendLog(const AFmt: string; const AArgs: array of const; ALogType: TLogType = ltNormal; const CRLF: string = '');
begin
  Logger.AppendLog(AFmt, AArgs, ALogType, CRLF);
end;

function Logger: ILogger;
begin
  Result := TLogger.Default;
end;

end.

