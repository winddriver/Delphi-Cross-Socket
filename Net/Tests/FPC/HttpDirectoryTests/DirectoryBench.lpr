program DirectoryBench;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes,
  {$IFDEF FPC}DTF.Diagnostics,{$ELSE}Diagnostics,{$ENDIF}
  Net.CrossHttpRouterDirUtils;

{$Q-}
function HashText(const AText: string): UInt64;
var
  I: Integer;
begin
  Result := UInt64($CBF29CE484222325);
  for I := 1 to Length(AText) do
    Result := (Result xor Ord(AText[I])) * UInt64(1099511628211);
end;

function Build(const ADirectory: string; const AMaxEntries: Integer): string;
begin
  {$IFDEF DIRECTORY_LIMIT_API}
  Result := BuildDirList(ADirectory, '/files/', '/files', AMaxEntries);
  {$ELSE}
  Result := BuildDirList(ADirectory, '/files/', '/files');
  {$ENDIF}
end;

var
  LHtml, LLine: string;
  LWatch: TStopwatch;
  LElapsed: Int64;
  I, LMax, LIterations: Integer;
begin
  try
    if ParamCount <> 3 then raise Exception.Create('用法: DirectoryBench <目录> <上限> <次数>');
    LMax := StrToInt(ParamStr(2));
    LIterations := StrToInt(ParamStr(3));
    if LIterations <= 0 then raise Exception.Create('次数必须为正数');
    LWatch := TStopwatch.StartNew;
    Writeln('READY'); Flush(Output);
    Readln(LLine);
    LHtml := Build(ParamStr(1), LMax);
    LHtml := '';
    LWatch := TStopwatch.StartNew;
    for I := 1 to LIterations do
    begin
      // 前一页面先释放，避免人为同时持有两次结果。
      LHtml := '';
      LHtml := Build(ParamStr(1), LMax);
    end;
    LElapsed := LWatch.ElapsedTicks;
    Writeln('RESULT ', LElapsed, ' ', TStopwatch.Frequency, ' ', LIterations,
      ' ', Length(LHtml), ' ', HashText(LHtml));
    Flush(Output);
    // 保留结果，父进程读取操作系统峰值工作集 / VmHWM 后再退出。
    Readln(LLine);
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
