{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 Souledge(soulawing@gmail.com) QQ:21305383         }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Utils.Logger;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, Utils.Utils;

type
  TLogType = (ltNormal, ltWarning, ltError, ltException);
  TLogTypeSets = set of TLogType;

const
  LogTypeStr: array [TLogType] of string = ('', 'WAR', 'ERR', 'EXP');

type
  TLogger = class
  private
    FFileLocker: array [TLogType] of TObject;
    FFilters: TLogTypeSets;

    class var FLogger: TLogger;
    class constructor Create;
    class destructor Destroy;

    procedure SetFilters(const Value: TLogTypeSets);
  protected
    procedure AppendStrToLogFile(const S: string; ALogType: TLogType);
  public
    constructor Create; virtual;
    destructor Destroy; override;

    function GetLogDir: string;
    function GetLogFileName(ALogType: TLogType; Date: TDateTime): string;

    procedure AppendLog(const Log: string; const TimeFormat: string; ALogType: TLogType = ltNormal; CRLF: string = ''); overload;
    procedure AppendLog(const Log: string; ALogType: TLogType = ltNormal; CRLF: string = ''); overload;
    procedure AppendLog(const Fmt: string; const Args: array of const; const TimeFormat: string; ALogType: TLogType = ltNormal; CRLF: string = ''); overload;
    procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; CRLF: string = ''); overload;

    property Filters: TLogTypeSets read FFilters write SetFilters;

    class property Logger: TLogger read FLogger;
  end;

procedure AppendLog(const Log: string; const TimeFormat: string; ALogType: TLogType = ltNormal; CRLF: string = ';'); overload;
procedure AppendLog(const Log: string; ALogType: TLogType = ltNormal; CRLF: string = ';'); overload;
procedure AppendLog(const Fmt: string; const Args: array of const; const TimeFormat: string; ALogType: TLogType = ltNormal; CRLF: string = ';'); overload;
procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; CRLF: string = ';'); overload;

function Logger: TLogger;

var
  // 日志目录
  // 留空由程序自动设定
  LogDir: string = '';

implementation

class constructor TLogger.Create;
begin
  FLogger := TLogger.Create;
end;

class destructor TLogger.Destroy;
begin
  FreeAndNil(FLogger);
end;

constructor TLogger.Create;
var
  i: TLogType;
begin
  FFilters := [ltNormal, ltWarning, ltError, ltException];

  for i := Low(TLogType) to High(TLogType) do
  begin
    FFileLocker[i] := TObject.Create;
  end;
end;

destructor TLogger.Destroy;
var
  i: TLogType;
begin
  for i := Low(TLogType) to High(TLogType) do
  begin
    TMonitor.Enter(FFileLocker[i]);
    TMonitor.Exit(FFileLocker[i]);
    FFileLocker[i].Free;
  end;

  inherited Destroy;
end;

function TLogger.GetLogDir: string;
begin
  if (LogDir <> '') then
    Result := LogDir
  else
    Result :=
      {$IFDEF MSWINDOWS}
      TUtils.AppPath +
      {$ELSE}
      TUtils.AppDocuments +
      {$ENDIF}
      TUtils.AppName + '.log' + PathDelim;
end;

function TLogger.GetLogFileName(ALogType: TLogType; Date: TDateTime): string;
begin
  Result := LogTypeStr[ALogType];
  if (Result <> '') then
    Result := Result + '-';
  Result := Result + TUtils.DateTimeToStr(Date, 'YYYY-MM-DD') + '.log';
end;

procedure TLogger.SetFilters(const Value: TLogTypeSets);
begin
  FFilters := Value;
end;

procedure TLogger.AppendLog(const Log: string; const TimeFormat: string; ALogType: TLogType; CRLF: string);
var
  LogText: string;
begin
  if not (ALogType in FFilters) then Exit;

  if (CRLF <> '') then
    LogText := StringReplace(Log, sLineBreak, CRLF, [rfReplaceAll])
  else
    LogText := Log;
  LogText := TUtils.DateTimeToStr(Now, TimeFormat) + ' ' + LogText + sLineBreak;

  AppendStrToLogFile(LogText, ALogType);
end;

procedure TLogger.AppendLog(const Log: string; ALogType: TLogType; CRLF: string);
begin
  AppendLog(Log, 'HH:NN:SS:ZZZ', ALogType, CRLF);
end;

procedure TLogger.AppendLog(const Fmt: string; const Args: array of const; const TimeFormat: string; ALogType: TLogType; CRLF: string);
begin
  AppendLog(TUtils.ThreadFormat(Fmt, Args), TimeFormat, ALogType, CRLF);
end;

procedure TLogger.AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType; CRLF: string);
begin
  AppendLog(TUtils.ThreadFormat(Fmt, Args), ALogType, CRLF);
end;

procedure TLogger.AppendStrToLogFile(const S: string; ALogType: TLogType);
var
  LLogDir, LLogFile: string;
  LStream: TFileStream;
  LBytes: TBytes;
begin
  LLogDir := GetLogDir;
  LLogFile := LLogDir + GetLogFileName(ALogType, Now);

  TMonitor.Enter(FFileLocker[ALogType]);
  try
    // 当没有权限写入日志文件时会触发异常
    // 这里屏蔽该异常, 以免记录日志反而影响正常的程序流程
    try
      ForceDirectories(LLogDir);
      LStream := TFile.Open(LLogFile, TFileMode.fmOpenOrCreate, TFileAccess.faReadWrite, TFileShare.fsRead);
      try
        LStream.Seek(0, TSeekOrigin.soEnd);
        LBytes := TEncoding.UTF8.GetBytes(S);
        LStream.Write(LBytes, Length(LBytes));
      finally
        FreeAndNil(LStream);
      end;
    except
    end;
  finally
    TMonitor.Exit(FFileLocker[ALogType]);
  end;
end;

procedure AppendLog(const Log: string; const TimeFormat: string; ALogType: TLogType = ltNormal; CRLF: string = ';');
begin
  Logger.AppendLog(Log, TimeFormat, ALogType, CRLF);
end;

procedure AppendLog(const Log: string; ALogType: TLogType = ltNormal; CRLF: string = ';');
begin
  Logger.AppendLog(Log, ALogType, CRLF);
end;

procedure AppendLog(const Fmt: string; const Args: array of const; const TimeFormat: string; ALogType: TLogType = ltNormal; CRLF: string = ';');
begin
  Logger.AppendLog(Fmt, Args, TimeFormat, ALogType, CRLF);
end;

procedure AppendLog(const Fmt: string; const Args: array of const; ALogType: TLogType = ltNormal; CRLF: string = ';');
begin
  Logger.AppendLog(Fmt, Args, ALogType, CRLF);
end;

function Logger: TLogger;
begin
  Result := TLogger.FLogger;
end;

end.

