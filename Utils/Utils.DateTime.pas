{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Utils.DateTime;

interface

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  System.SysUtils,
  System.DateUtils,
  System.Types,
  System.Math;

type
  TDateTimeHelper = record helper for TDateTime
  private const
    CMillisPerDay = Int64(MSecsPerSec * SecsPerMin * MinsPerHour * HoursPerDay);
  private
    function GetDay: Word; inline;
    function GetDate: TDateTime; inline;
    function GetDayOfWeek: Word; inline;
    function GetDayOfYear: Word; inline;
    function GetHour: Word; inline;
    function GetMillisecond: Word; inline;
    function GetMinute: Word; inline;
    function GetMonth: Word; inline;
    function GetSecond: Word; inline;
    function GetTime: TDateTime; inline;
    function GetYear: Integer; inline;
    class function GetNow: TDateTime; static; inline;
    class function GetToday: TDateTime; static; inline;
    class function GetTomorrow: TDateTime; static; inline;
    class function GetYesterDay: TDateTime; static; inline;
    procedure SetYear(const Value: Integer); inline;
    procedure SetDay(const Value: Word); inline;
    procedure SetHour(const Value: Word); inline;
    procedure SetMillisecond(const Value: Word); inline;
    procedure SetMinute(const Value: Word); inline;
    procedure SetMonth(const Value: Word); inline;
    procedure SetSecond(const Value: Word); inline;
    procedure SetDate(const Value: TDateTime); inline;
    procedure SetTime(const Value: TDateTime); inline;
  public
    class function Create(const AYear, AMonth, ADay: Word): TDateTime; overload; static; inline;
    class function Create(const AYear, AMonth, ADay, AHour, AMinute, ASecond,
      AMillisecond: Word): TDateTime; overload; static; inline;
    class function Create(const AStr: string): TDateTime; overload; static; inline;

    {$IFDEF MSWINDOWS}
    class function Create(const ASysTime: TSystemTime): TDateTime; overload; static; inline;
    class function Create(const AFileTime: TFileTime): TDateTime; overload; static; inline;
    {$ENDIF}

    class function TryStrToDateTime(const AStr: string;
      out ADateTime: TDateTime; const AConvertToLocal: Boolean = True): Boolean; static;

    class property Now: TDateTime read GetNow;
    class property Today: TDateTime read GetToday;
    class property Yesterday: TDateTime read GetYesterDay;
    class property Tomorrow: TDateTime read GetTomorrow;

    property Date: TDateTime read GetDate write SetDate;
    property Time: TDateTime read GetTime write SetTime;

    property DayOfWeek: Word read GetDayOfWeek;
    property DayOfYear: Word read GetDayOfYear;

    property Year: Integer read GetYear write SetYear;
    property Month: Word read GetMonth write SetMonth;
    property Day: Word read GetDay write SetDay;
    property Hour: Word read GetHour write SetHour;
    property Minute: Word read GetMinute write SetMinute;
    property Second: Word read GetSecond write SetSecond;
    property Millisecond: Word read GetMillisecond write SetMillisecond;

    function ToString(const AFormatStr: string = ''): string; overload; inline;
    function ToISO8601(const AIsUtcDateTime: Boolean = False): string;
    function ToRFC1123(const AIsUtcDateTime: Boolean = False): string;
    function ToMilliseconds: Int64; inline;

    function StartOfYear: TDateTime; inline;
    function EndOfYear: TDateTime; inline;
    function StartOfMonth: TDateTime; inline;
    function EndOfMonth: TDateTime; inline;
    function StartOfWeek: TDateTime; inline;
    function EndOfWeek: TDateTime; inline;
    function StartOfDay: TDateTime; inline;
    function EndOfDay: TDateTime; inline;

    function AddYears(const ANumberOfYears: Integer = 1): TDateTime; inline;
    function AddMonths(const ANumberOfMonths: Integer = 1): TDateTime; inline;
    function AddDays(const ANumberOfDays: Integer = 1): TDateTime; inline;
    function AddHours(const ANumberOfHours: Int64 = 1): TDateTime; inline;
    function AddMinutes(const ANumberOfMinutes: Int64 = 1): TDateTime; inline;
    function AddSeconds(const ANumberOfSeconds: Int64 = 1): TDateTime; inline;
    function AddMilliseconds(const ANumberOfMilliseconds: Int64 = 1): TDateTime; inline;

    function DecYears(const ANumberOfYears: Integer = 1): TDateTime; inline;
    function DecMonths(const ANumberOfMonths: Integer = 1): TDateTime; inline;
    function DecDays(const ANumberOfDays: Integer = 1): TDateTime; inline;
    function DecHours(const ANumberOfHours: Int64 = 1): TDateTime; inline;
    function DecMinutes(const ANumberOfMinutes: Int64 = 1): TDateTime; inline;
    function DecSeconds(const ANumberOfSeconds: Int64 = 1): TDateTime; inline;
    function DecMilliseconds(const ANumberOfMilliseconds: Int64 = 1): TDateTime; inline;

    function CompareTo(const ADateTime: TDateTime): TValueRelationship; inline;
    function Equals(const ADateTime: TDateTime): Boolean; inline;
    function IsSameDay(const ADateTime: TDateTime): Boolean; inline;
    function IsSameMonth(const ADateTime: TDateTime): Boolean;
    function IsSameYear(const ADateTime: TDateTime): Boolean;
    function InRange(const AStartDateTime, AEndDateTime: TDateTime; const AInclusive: Boolean = True): Boolean; inline;
    function IsInLeapYear: Boolean; inline;
    function IsToday: Boolean; inline;
    function IsAM: Boolean; inline;
    function IsPM: Boolean; inline;

    function YearsBetween(const ADateTime: TDateTime): Integer; inline;
    function MonthsBetween(const ADateTime: TDateTime): Integer; inline;
    function WeeksBetween(const ADateTime: TDateTime): Integer; inline;
    function DaysBetween(const ADateTime: TDateTime): Integer; inline;
    function HoursBetween(const ADateTime: TDateTime): Int64; inline;
    function MinutesBetween(const ADateTime: TDateTime): Int64; inline;
    function SecondsBetween(const ADateTime: TDateTime): Int64; inline;
    function MilliSecondsBetween(const ADateTime: TDateTime): Int64; inline;

    function YearsDiffer(const ADateTime: TDateTime): Integer; inline;
    function MonthsDiffer(const ADateTime: TDateTime): Integer; inline;
    function WeeksDiffer(const ADateTime: TDateTime): Integer; inline;
    function DaysDiffer(const ADateTime: TDateTime): Integer; inline;
    function HoursDiffer(const ADateTime: TDateTime): Int64; inline;
    function MinutesDiffer(const ADateTime: TDateTime): Int64; inline;
    function SecondsDiffer(const ADateTime: TDateTime): Int64; inline;
    function MilliSecondsDiffer(const ADateTime: TDateTime): Int64; inline;

    function WithinYears(const ADateTime: TDateTime; const AYears: Integer): Boolean; inline;
    function WithinMonths(const ADateTime: TDateTime; const AMonths: Integer): Boolean; inline;
    function WithinWeeks(const ADateTime: TDateTime; const AWeeks: Integer): Boolean; inline;
    function WithinDays(const ADateTime: TDateTime; const ADays: Integer): Boolean; inline;
    function WithinHours(const ADateTime: TDateTime; const AHours: Int64): Boolean; inline;
    function WithinMinutes(const ADateTime: TDateTime; const AMinutes: Int64): Boolean; inline;
    function WithinSeconds(const ADateTime: TDateTime; const ASeconds: Int64): Boolean; inline;
    function WithinMilliseconds(const ADateTime: TDateTime; const AMilliseconds: Int64): Boolean; inline;

    function ToUniversalTime(const AForceDaylight: Boolean = False): TDateTime; inline;
    function ToLocalTime: TDateTime; inline;
  end;

implementation

{ TDateTimeHelper }

function TDateTimeHelper.AddDays(const ANumberOfDays: Integer): TDateTime;
begin
  Result := IncDay(Self, ANumberOfDays);
end;

function TDateTimeHelper.AddHours(const ANumberOfHours: Int64): TDateTime;
begin
  Result := IncHour(Self, ANumberOfHours);
end;

function TDateTimeHelper.AddMilliseconds(const ANumberOfMilliseconds: Int64): TDateTime;
begin
  Result := IncMilliSecond(Self, ANumberOfMilliseconds);
end;

function TDateTimeHelper.AddMinutes(const ANumberOfMinutes: Int64): TDateTime;
begin
  Result := IncMinute(Self, ANumberOfMinutes);
end;

function TDateTimeHelper.AddMonths(const ANumberOfMonths: Integer): TDateTime;
begin
  Result := IncMonth(Self, ANumberOfMonths);
end;

function TDateTimeHelper.AddSeconds(const ANumberOfSeconds: Int64): TDateTime;
begin
  Result := IncSecond(Self, ANumberOfSeconds);
end;

function TDateTimeHelper.AddYears(const ANumberOfYears: Integer): TDateTime;
begin
  Result := IncYear(Self, ANumberOfYears);
end;

function TDateTimeHelper.CompareTo(const ADateTime: TDateTime): TValueRelationship;
begin
  Result := CompareDateTime(Self, ADateTime);
end;

class function TDateTimeHelper.Create(const AYear, AMonth,
  ADay: Word): TDateTime;
begin
  Result := EncodeDate(AYear, AMonth, ADay);
end;

class function TDateTimeHelper.Create(const AYear, AMonth, ADay, AHour, AMinute,
  ASecond, AMillisecond: Word): TDateTime;
begin
  Result := EncodeDateTime(AYear, AMonth, ADay, AHour, AMinute, ASecond, AMillisecond);
end;

function TDateTimeHelper.DaysBetween(const ADateTime: TDateTime): Integer;
begin
  Result := System.DateUtils.DaysBetween(Self, ADateTime);
end;

function TDateTimeHelper.DaysDiffer(const ADateTime: TDateTime): Integer;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds) div CMillisPerDay;
end;

function TDateTimeHelper.DecDays(const ANumberOfDays: Integer): TDateTime;
begin
  Result := AddDays(0 - ANumberOfDays);
end;

function TDateTimeHelper.DecHours(const ANumberOfHours: Int64): TDateTime;
begin
  Result := AddHours(0 - ANumberOfHours);
end;

function TDateTimeHelper.DecMilliseconds(
  const ANumberOfMilliseconds: Int64): TDateTime;
begin
  Result := AddMilliseconds(0 - ANumberOfMilliseconds);
end;

function TDateTimeHelper.DecMinutes(const ANumberOfMinutes: Int64): TDateTime;
begin
  Result := AddMinutes(0 - ANumberOfMinutes);
end;

function TDateTimeHelper.DecMonths(const ANumberOfMonths: Integer): TDateTime;
begin
  Result := AddMonths(0 - ANumberOfMonths);
end;

function TDateTimeHelper.DecSeconds(const ANumberOfSeconds: Int64): TDateTime;
begin
  Result := AddSeconds(0 - ANumberOfSeconds);
end;

function TDateTimeHelper.DecYears(const ANumberOfYears: Integer): TDateTime;
begin
  Result := AddYears(0 - ANumberOfYears);
end;

function TDateTimeHelper.EndOfDay: TDateTime;
begin
  Result := EndOfTheDay(Self);
end;

function TDateTimeHelper.EndOfMonth: TDateTime;
begin
  Result := EndOfTheMonth(Self);
end;

function TDateTimeHelper.EndOfWeek: TDateTime;
begin
  Result := EndOfTheWeek(Self);
end;

function TDateTimeHelper.EndOfYear: TDateTime;
begin
  Result := EndOfTheYear(Self);
end;

function TDateTimeHelper.Equals(const ADateTime: TDateTime): Boolean;
begin
  Result := SameDateTime(Self, ADateTime);
end;

function TDateTimeHelper.GetDate: TDateTime;
begin
  Result := DateOf(Self);
end;

function TDateTimeHelper.GetDay: Word;
begin
  Result := DayOf(Self);
end;

function TDateTimeHelper.GetDayOfWeek: Word;
begin
  Result := DayOfTheWeek(Self);
end;

function TDateTimeHelper.GetDayOfYear: Word;
begin
  Result := DayOfTheYear(Self);
end;

function TDateTimeHelper.GetHour: Word;
begin
  Result := HourOf(Self);
end;

function TDateTimeHelper.GetMillisecond: Word;
begin
  Result := MilliSecondOf(Self);
end;

function TDateTimeHelper.GetMinute: Word;
begin
  Result := MinuteOf(Self);
end;

function TDateTimeHelper.GetMonth: Word;
begin
  Result := MonthOf(Self);
end;

class function TDateTimeHelper.GetNow: TDateTime;
begin
  Result := System.SysUtils.Now;
end;

function TDateTimeHelper.GetSecond: Word;
begin
  Result := SecondOf(Self);
end;

function TDateTimeHelper.GetTime: TDateTime;
begin
  Result := TimeOf(Self);
end;

class function TDateTimeHelper.GetToday: TDateTime;
begin
  Result := System.SysUtils.Date;
end;

class function TDateTimeHelper.GetTomorrow: TDateTime;
begin
  Result := System.SysUtils.Date + 1;
end;

function TDateTimeHelper.GetYear: Integer;
begin
  Result := YearOf(Self);
end;

class function TDateTimeHelper.GetYesterDay: TDateTime;
begin
  Result := System.SysUtils.Date - 1;
end;

function TDateTimeHelper.HoursBetween(const ADateTime: TDateTime): Int64;
begin
  Result := System.DateUtils.HoursBetween(Self, ADateTime);
end;

function TDateTimeHelper.HoursDiffer(const ADateTime: TDateTime): Int64;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds)
    div (MSecsPerSec * SecsPerMin * MinsPerHour);
end;

function TDateTimeHelper.InRange(const AStartDateTime, AEndDateTime: TDateTime; const AInclusive: Boolean): Boolean;
begin
  Result := DateTimeInRange(Self, AStartDateTime, AEndDateTime, AInclusive);
end;

function TDateTimeHelper.IsAM: Boolean;
begin
  Result := System.DateUtils.IsAM(Self);
end;

function TDateTimeHelper.IsInLeapYear: Boolean;
begin
  Result := System.DateUtils.IsInLeapYear(Self);
end;

function TDateTimeHelper.IsPM: Boolean;
begin
  Result := System.DateUtils.IsPM(Self);
end;

function TDateTimeHelper.IsSameDay(const ADateTime: TDateTime): Boolean;
begin
  Result := (Trunc(Self) = Trunc(ADateTime));
end;

function TDateTimeHelper.IsSameMonth(const ADateTime: TDateTime): Boolean;
var
  Y, M1, M2, D: Word;
begin
  DecodeDate(Self, Y, M1, D);
  DecodeDate(ADateTime, Y, M2, D);
  Result := (M1 = M2);
end;

function TDateTimeHelper.IsSameYear(const ADateTime: TDateTime): Boolean;
var
  Y1, Y2, M, D: Word;
begin
  DecodeDate(Self, Y1, M, D);
  DecodeDate(ADateTime, Y2, M, D);
  Result := (Y1 = Y2);
end;

function TDateTimeHelper.IsToday: Boolean;
begin
  Result := System.DateUtils.IsToday(Self);
end;

function TDateTimeHelper.MilliSecondsBetween(const ADateTime: TDateTime): Int64;
begin
  Result := System.DateUtils.MilliSecondsBetween(Self, ADateTime);
end;

function TDateTimeHelper.MilliSecondsDiffer(const ADateTime: TDateTime): Int64;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds);
end;

function TDateTimeHelper.MinutesBetween(const ADateTime: TDateTime): Int64;
begin
  Result := System.DateUtils.MinutesBetween(Self, ADateTime);
end;

function TDateTimeHelper.MinutesDiffer(const ADateTime: TDateTime): Int64;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds)
    div (MSecsPerSec * SecsPerMin);
end;

function TDateTimeHelper.MonthsBetween(const ADateTime: TDateTime): Integer;
begin
  Result := System.DateUtils.MonthsBetween(Self, ADateTime);
end;

function TDateTimeHelper.MonthsDiffer(const ADateTime: TDateTime): Integer;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds)
     div Round(CMillisPerDay * ApproxDaysPerMonth);
end;

function TDateTimeHelper.SecondsBetween(const ADateTime: TDateTime): Int64;
begin
  Result := System.DateUtils.SecondsBetween(Self, ADateTime);
end;

function TDateTimeHelper.SecondsDiffer(const ADateTime: TDateTime): Int64;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds)
    div (MSecsPerSec);
end;

procedure TDateTimeHelper.SetDate(const Value: TDateTime);
begin
  Self := Trunc(Value) + Frac(Self);
end;

procedure TDateTimeHelper.SetDay(const Value: Word);
begin
  Self := RecodeDay(Self, Value);
end;

procedure TDateTimeHelper.SetHour(const Value: Word);
begin
  Self := RecodeHour(Self, Value);
end;

procedure TDateTimeHelper.SetMillisecond(const Value: Word);
begin
  Self := RecodeMilliSecond(Self, Value);
end;

procedure TDateTimeHelper.SetMinute(const Value: Word);
begin
  Self := RecodeMinute(Self, Value);
end;

procedure TDateTimeHelper.SetMonth(const Value: Word);
begin
  Self := RecodeMonth(Self, Value);
end;

procedure TDateTimeHelper.SetSecond(const Value: Word);
begin
  Self := RecodeSecond(Self, Value);
end;

procedure TDateTimeHelper.SetTime(const Value: TDateTime);
begin
  Self := Trunc(Self) + Frac(Value);
end;

procedure TDateTimeHelper.SetYear(const Value: Integer);
begin
  Self := RecodeYear(Self, Value);
end;

function TDateTimeHelper.StartOfDay: TDateTime;
begin
  Result := StartOfTheDay(Self);
end;

function TDateTimeHelper.StartOfMonth: TDateTime;
begin
  Result := StartOfTheMonth(Self);
end;

function TDateTimeHelper.StartOfWeek: TDateTime;
begin
  Result := StartOfTheWeek(Self);
end;

function TDateTimeHelper.StartOfYear: TDateTime;
begin
  Result := StartOfTheYear(Self);
end;

function TDateTimeHelper.ToISO8601(const AIsUtcDateTime: Boolean): string;
const
  NEG: array [Boolean] of string = ('-', '+');
var
  LOffset: TDateTime;
  LYear, LMonth, LDay, LHour, LMinute, LSecond, LMilliseconds: Word;
begin
  DecodeDate(Self, LYear, LMonth, LDay);
  DecodeTime(Self, LHour, LMinute, LSecond, LMilliseconds);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%d', [LYear, LMonth, LDay, LHour, LMinute, LSecond, LMilliseconds]);

  if not AIsUtcDateTime and (Self <> 0) then
    LOffset := Self - TTimeZone.Local.ToUniversalTime(Self)
  else
    LOffset := 0;

  if (LOffset <> 0) then
  begin
    DecodeTime(LOffset, LHour, LMinute, LSecond, LMilliseconds);
    Result := Format('%s%s%.2d:%.2d', [Result, NEG[LOffset > 0], LHour, LMinute]);
  end else
    Result := Result + 'Z';
end;

function TDateTimeHelper.ToLocalTime: TDateTime;
begin
  if (Self <> 0) then
    Result := TTimeZone.Local.ToLocalTime(Self)
  else
    Result := Self;
end;

function TDateTimeHelper.ToMilliseconds: Int64;
var
  LTimeStamp: TTimeStamp;
begin
  LTimeStamp := DateTimeToTimeStamp(Self);
  Result := (Int64(LTimeStamp.Date) * MSecsPerDay) + LTimeStamp.Time;
end;

function TDateTimeHelper.ToRFC1123(const AIsUtcDateTime: Boolean): string;
const
  ShortDayNamesEnglish :array[1..7] of string =
    ('Mon','Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun');
  ShortMonthNamesEnglish :array[1..12] of string = ('Jan', 'Feb','Mar', 'Apr',
     'May','Jun','Jul','Aug', 'Sep','Oct','Nov','Dec');
var
  LDateTime: TDateTime;
begin
  if not AIsUtcDateTime then
    LDateTime := Self.ToUniversalTime
  else
    LDateTime := Self;

  Result := ShortDayNamesEnglish[DayOfTheWeek(LDateTime)] + ', ' +
    FormatDateTime('dd', LDateTime) + ' ' +
    ShortMonthNamesEnglish[MonthOf(LDateTime)] + ' ' +
    FormatDateTime('yyyy hh:nn:ss', LDateTime) + ' GMT';
end;

function TDateTimeHelper.ToString(const AFormatStr: string): string;
begin
  if (AFormatStr = '') then
    Result := DateToStr(Self)
  else
    Result := FormatDateTime(AFormatStr, Self);
end;

function TDateTimeHelper.ToUniversalTime(
  const AForceDaylight: Boolean): TDateTime;
begin
  if (Self <> 0) then
    Result := TTimeZone.Local.ToUniversalTime(Self, AForceDaylight)
  else
    Result := Self;
end;

class function TDateTimeHelper.TryStrToDateTime(const AStr: string;
  out ADateTime: TDateTime; const AConvertToLocal: Boolean): Boolean;

  function ParseDateTimePart(P: PChar; var AValue: Integer; MaxLen: Integer): PChar;
  var
    V: Integer;
  begin
    Result := P;
    V := 0;
    while (Result^ in ['0'..'9']) and (MaxLen > 0) do
    begin
      V := V * 10 + (Ord(Result^) - Ord('0'));
      Inc(Result);
      Dec(MaxLen);
    end;
    AValue := V;
  end;

var
  P: PChar;
  LMSecsSince1970: Int64;
  LYear, LMonth, LDay, LHour, LMin, LSec, LMSec: Integer;
  LOffsetHour, LOffsetMin: Integer;
  LSign: Double;
  LTime: TDateTime;
begin
  ADateTime := 0;
  if (AStr = '') then Exit(False);

  P := PChar(AStr);
  if (P^ = '/') and (StrLComp('Date(', P + 1, 5) = 0) then  // .NET: milliseconds since 1970-01-01
  begin
    Inc(P, 6);
    LMSecsSince1970 := 0;
    while (P^ <> #0) and (P^ in ['0'..'9']) do
    begin
      LMSecsSince1970 := LMSecsSince1970 * 10 + (Ord(P^) - Ord('0'));
      Inc(P);
    end;
    if (P^ = '+') or (P^ = '-') then // timezone information
    begin
      Inc(P);
      while (P^ <> #0) and (P^ in ['0'..'9']) do
        Inc(P);
    end;
    if (P[0] = ')') and (P[1] = '/') and (P[2] = #0) then
      ADateTime := TDateTime(UnixDateDelta + (LMSecsSince1970 / MSecsPerDay))
    else
      Exit(False); // invalid format
  end else
  begin
    if (P^ = '-') then // negative year
      Inc(P);
    P := ParseDateTimePart(P, LYear, 4);
    if (P^ <> '-') then
      Exit(False); // invalid format
    P := ParseDateTimePart(P + 1, LMonth, 2);
    if (P^ <> '-') then
      Exit(False); // invalid format
    P := ParseDateTimePart(P + 1, LDay, 2);

    LHour := 0;
    LMin := 0;
    LSec := 0;
    LMSec := 0;
    if not TryEncodeDate(LYear, LMonth, LDay, ADateTime) then Exit(False);

    // ISO8601
    // "2015-02-01T16:08:19.202Z"
    // "2015-02-01T16:08:19.202+08:00"
    // "2015-02-01T16:08:19.202+0800"
    // "2015-02-01T16:08:19.202+08"
    // "2015-02-01T16:08:19.202+8"
    if (P^ = 'T') then
    begin
      P := ParseDateTimePart(P + 1, LHour, 2);
      if (P^ <> ':') then
        Exit(False); // invalid format
      P := ParseDateTimePart(P + 1, LMin, 2);
      if (P^ = ':') then
      begin
        P := ParseDateTimePart(P + 1, LSec, 2);
        if (P^ = '.') then
          P := ParseDateTimePart(P + 1, LMSec, 3);
      end;
      if not TryEncodeTime(LHour, LMin, LSec, LMSec, LTime) then Exit(False);
      ADateTime := ADateTime + LTime;
      if (P^ <> 'Z') then
      begin
        if (P^ = '+') or (P^ = '-') then
        begin
          if (P^ = '+') then
            LSign := -1 //  +0100 means that the time is 1 hour later than UTC
          else
            LSign := 1;

          P := ParseDateTimePart(P + 1, LOffsetHour, 2);
          if (P^ = ':') then
            Inc(P);
          ParseDateTimePart(P, LOffsetMin, 2);

          if not TryEncodeTime(LOffsetHour, LOffsetMin, 0, 0, LTime) then Exit(False);
          ADateTime := ADateTime + (LTime * LSign);
        end else
          Exit(False); // invalid format
      end;

      // 带时区格式的时间转换为本地时间
      if AConvertToLocal then
        ADateTime := ADateTime.ToLocalTime;
    end else
    // "2015-02-01 16:08:19.202"
    if (P^ = ' ') then
    begin
      P := ParseDateTimePart(P + 1, LHour, 2);
      if (P^ <> ':') then
        Exit(False); // invalid format
      P := ParseDateTimePart(P + 1, LMin, 2);
      if (P^ = ':') then
      begin
        P := ParseDateTimePart(P + 1, LSec, 2);
        if (P^ = '.') then
          P := ParseDateTimePart(P + 1, LMSec, 3);
      end;
      if not TryEncodeTime(LHour, LMin, LSec, LMSec, LTime) then Exit(False);
      ADateTime := ADateTime + LTime;
    end else
    if (P^ <> #0) then
      Exit(False);
  end;

  Result := True;
end;

function TDateTimeHelper.WeeksBetween(const ADateTime: TDateTime): Integer;
begin
  Result := System.DateUtils.WeeksBetween(Self, ADateTime);
end;

function TDateTimeHelper.WeeksDiffer(const ADateTime: TDateTime): Integer;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds)
     div (CMillisPerDay * DaysPerWeek);
end;

function TDateTimeHelper.WithinDays(const ADateTime: TDateTime;
  const ADays: Integer): Boolean;
begin
  Result := System.DateUtils.WithinPastDays(Self, ADateTime, ADays);
end;

function TDateTimeHelper.WithinHours(const ADateTime: TDateTime;
  const AHours: Int64): Boolean;
begin
  Result := System.DateUtils.WithinPastHours(Self, ADateTime, AHours);
end;

function TDateTimeHelper.WithinMilliseconds(const ADateTime: TDateTime;
  const AMilliseconds: Int64): Boolean;
begin
  Result := System.DateUtils.WithinPastMilliSeconds(Self, ADateTime, AMilliseconds);
end;

function TDateTimeHelper.WithinMinutes(const ADateTime: TDateTime;
  const AMinutes: Int64): Boolean;
begin
  Result := System.DateUtils.WithinPastMinutes(Self, ADateTime, AMinutes);
end;

function TDateTimeHelper.WithinMonths(const ADateTime: TDateTime;
  const AMonths: Integer): Boolean;
begin
  Result := System.DateUtils.WithinPastMonths(Self, ADateTime, AMonths);
end;

function TDateTimeHelper.WithinSeconds(const ADateTime: TDateTime;
  const ASeconds: Int64): Boolean;
begin
  Result := System.DateUtils.WithinPastSeconds(Self, ADateTime, ASeconds);
end;

function TDateTimeHelper.WithinWeeks(const ADateTime: TDateTime;
  const AWeeks: Integer): Boolean;
begin
  Result := System.DateUtils.WithinPastWeeks(Self, ADateTime, AWeeks);
end;

function TDateTimeHelper.WithinYears(const ADateTime: TDateTime;
  const AYears: Integer): Boolean;
begin
  Result := System.DateUtils.WithinPastYears(Self, ADateTime, AYears);
end;

function TDateTimeHelper.YearsBetween(const ADateTime: TDateTime): Integer;
begin
  Result := System.DateUtils.YearsBetween(Self, ADateTime);
end;

function TDateTimeHelper.YearsDiffer(const ADateTime: TDateTime): Integer;
begin
  Result := (Self.ToMilliseconds - ADateTime.ToMilliseconds)
     div Round(CMillisPerDay * ApproxDaysPerYear);
end;

class function TDateTimeHelper.Create(const AStr: string): TDateTime;
begin
  TryStrToDateTime(AStr, Result);
end;

{$IFDEF MSWINDOWS}
class function TDateTimeHelper.Create(const ASysTime: TSystemTime): TDateTime;
begin
  Result := Create(
    ASysTime.wYear,
    ASysTime.wMonth,
    ASysTime.wDay,
    ASysTime.wHour,
    ASysTime.wMinute,
    ASysTime.wSecond,
    ASysTime.wMilliseconds
  ).ToLocalTime;
end;

class function TDateTimeHelper.Create(const AFileTime: TFileTime): TDateTime;
var
  LSysTime: TSystemTime;
begin
  if FileTimeToSystemTime(AFileTime, LSysTime) then
    Result := Create(LSysTime)
  else
    Result := 0;
end;
{$ENDIF}

end.
