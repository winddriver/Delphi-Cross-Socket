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

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, System.Diagnostics,
  System.Generics.Collections, Utils.Utils, Utils.DateTime;

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
    procedure AppendLog(const Fmt: string; const Args: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;

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
    FLUSH_INTERVAL = 200;
  private
    FFilters: TLogTypeSets;

    class var FLogger: ILogger;
    class constructor Create;
    class destructor Destroy;

    function GetFilters: TLogTypeSets;
    procedure SetFilters(const Value: TLogTypeSets);
  private
    FBuffer: array [TLogType] of TLogBuffer;
    FBufferLock: array [TLogType] of TObject;
    FShutdown, FQuit: Boolean;

    procedure _Lock(const ALogType: TLogType); inline;
    procedure _Unlock(const ALogType: TLogType); inline;
    procedure _WriteLogFile(const ALogType: TLogType);
    procedure _WriteAllLogFiles; inline;
    procedure _CreateWriteThread;
    procedure _Shutdown; inline;
  protected
    procedure _AppendLogToBuffer(const S: string; ALogType: TLogType);
  public
    constructor Create; virtual;
    destructor Destroy; override;

    function GetLogDir: string;
    function GetLogFileName(ALogType: TLogType; ADate: TDateTime): string;

    procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const Fmt: string; const Args: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;
    procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ''); overload;

    procedure Flush;

    property Filters: TLogTypeSets read GetFilters write SetFilters;

    class property Logger: ILogger read FLogger;
  end;

procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ';'); overload;
procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = ';'); overload;
procedure AppendLog(const Fmt: string; const Args: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ';'); overload;
procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ';'); overload;

function Logger: ILogger;

var
  // 默认日志目录
  // 留空由程序自动设定
  DefaultLogDir: string = '';

implementation

class constructor TLogger.Create;
begin
  FLogger := TLogger.Create;
end;

class destructor TLogger.Destroy;
begin
end;

constructor TLogger.Create;
var
  I: TLogType;
begin
  FFilters := [ltNormal, ltWarning, ltError, ltException];

  for I := Low(TLogType) to High(TLogType) do
  begin
    FBuffer[I] := TLogBuffer.Create;
    FBufferLock[I] := TObject.Create;
  end;

  _CreateWriteThread;
end;

destructor TLogger.Destroy;
var
  I: TLogType;
begin
  Flush;

  _Shutdown;

  for I := Low(TLogType) to High(TLogType) do
  begin
    FreeAndNil(FBuffer[I]);
    FreeAndNil(FBufferLock[I]);
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
      {$IFDEF MSWINDOWS}
      TUtils.AppPath +
      {$ELSE}
      TUtils.AppDocuments +
      {$ENDIF}
      TUtils.AppName + '.log' + PathDelim;
end;

function TLogger.GetLogFileName(ALogType: TLogType; ADate: TDateTime): string;
begin
  Result := LogTypeStr[ALogType];
  if (Result <> '') then
    Result := Result + '-';
  Result := Result + TUtils.DateTimeToStr(ADate, 'YYYY-MM-DD') + '.log';
end;

procedure TLogger.SetFilters(const Value: TLogTypeSets);
begin
  FFilters := Value;
end;

procedure TLogger._CreateWriteThread;
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      LWatch: TStopwatch;
    begin
      LWatch := TStopwatch.StartNew;
      while not FShutdown do
      begin
        if (LWatch.ElapsedTicks > FLUSH_INTERVAL) then
        begin
          Flush;

          LWatch.Reset;
          LWatch.Start;
        end;
        Sleep(10);
      end;

      Flush;

      FQuit := True;
    end).Start;
end;

procedure TLogger._Lock(const ALogType: TLogType);
begin
  System.TMonitor.Enter(FBufferLock[ALogType]);
end;

procedure TLogger._Shutdown;
begin
  FShutdown := True;
  while not FQuit do
    Sleep(1);
end;

procedure TLogger._Unlock(const ALogType: TLogType);
begin
  System.TMonitor.Exit(FBufferLock[ALogType]);
end;

procedure TLogger._WriteLogFile(const ALogType: TLogType);
var
  LLogDir, LLogFile: string;
  LLastTime: TDateTime;
  I: Integer;
  LLogItem: TLogItem;
  LBuffer: TBytesStream;

  procedure _WriteLogToBuffer(const ALogItem: TLogItem);
  var
    LBytes: TBytes;
  begin
    LBytes := TEncoding.UTF8.GetBytes(ALogItem.Text);
    LBuffer.Seek(0, TSeekOrigin.soEnd);
    LBuffer.Write(LBytes, Length(LBytes));
  end;

  procedure _WriteBufferToFile(const ALogFile: string);
  var
    LStream: TFileStream;
    LBytes: TBytes;
  begin
    try
      LStream := TFile.Open(ALogFile, TFileMode.fmOpenOrCreate, TFileAccess.faReadWrite, TFileShare.fsRead);
      try
        LStream.Seek(0, TSeekOrigin.soEnd);
        LBytes := LBuffer.Bytes;
        SetLength(LBytes, LBuffer.Size);
        LStream.Write(LBytes, Length(LBytes));
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

    LBuffer := TBytesStream.Create(nil);
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
          LBuffer.Clear;
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
    LText := StringReplace(ALog, sLineBreak, CRLF, [rfReplaceAll])
  else
    LText := ALog;
  LText := TUtils.DateTimeToStr(Now, ATimeFormat) + ' ' + LText + sLineBreak;

  _AppendLogToBuffer(LText, ALogType);
end;

procedure TLogger.AppendLog(const ALog: string; ALogType: TLogType; const CRLF: string);
begin
  AppendLog(ALog, 'HH:NN:SS:ZZZ', ALogType, CRLF);
end;

procedure TLogger.AppendLog(const Fmt: string; const Args: array of const; const ATimeFormat: string; ALogType: TLogType; const CRLF: string);
begin
  AppendLog(TUtils.ThreadFormat(Fmt, Args), ATimeFormat, ALogType, CRLF);
end;

procedure TLogger.AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType; const CRLF: string);
begin
  AppendLog(TUtils.ThreadFormat(Fmt, Args), ALogType, CRLF);
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

procedure AppendLog(const ALog: string; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ';');
begin
  Logger.AppendLog(ALog, ATimeFormat, ALogType, CRLF);
end;

procedure AppendLog(const ALog: string; ALogType: TLogType = ltNormal; const CRLF: string = ';');
begin
  Logger.AppendLog(ALog, ALogType, CRLF);
end;

procedure AppendLog(const Fmt: string; const Args: array of const; const ATimeFormat: string; ALogType: TLogType = ltNormal; const CRLF: string = ';');
begin
  Logger.AppendLog(Fmt, Args, ATimeFormat, ALogType, CRLF);
end;

procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; const CRLF: string = ';');
begin
  Logger.AppendLog(Fmt, Args, ALogType, CRLF);
end;

function Logger: ILogger;
begin
  Result := TLogger.FLogger;
end;

end.

