program DirectoryResourceTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, Net.CrossHttpRouterDirUtils;

var
  LFailAt: Integer;
  LThrown: Boolean;
  LLine, LHtml: string;

procedure FailAtStage(const AStage: TDirectoryTestStage);
begin
  if Ord(AStage) = LFailAt then
  begin
    LThrown := True;
    raise EAbort.Create('测试注入的目录异常');
  end;
end;

begin
  try
    if ParamCount <> 3 then raise Exception.Create('用法: DirectoryResourceTests <目录> <阶段 -1 为正常> <上限>');
    LFailAt := StrToInt(ParamStr(2));
    // 先触发 RTL 日期/时区的首次初始化句柄，避免把正常延迟初始化当作搜索泄漏。
    LHtml := BuildDirList(ParamStr(1), '/files/', '/files');
    LHtml := '';
    if DirectoryTestLiveLists <> 0 then
      raise Exception.Create('预热正常路径未释放对象');
    DirectoryTestEntries := 0;
    DirectoryTestHook := FailAtStage;
    Writeln('READY'); Flush(Output);
    Readln(LLine);
    try
      {$IFDEF DIRECTORY_LIMIT_API}
      LHtml := BuildDirList(ParamStr(1), '/files/', '/files', StrToInt(ParamStr(3)));
      {$ELSE}
      LHtml := BuildDirList(ParamStr(1), '/files/', '/files');
      {$ENDIF}
    except
      on E: EAbort do ;
      on E: EArgumentOutOfRangeException do
      begin
        if StrToInt(ParamStr(3)) >= 0 then raise;
        LThrown := True;
      end;
    end;
    Writeln('RESULT ', DirectoryTestLiveLists, ' ', DirectoryTestEntries,
      ' ', Ord(LThrown), ' ', Length(LHtml));
    Flush(Output);
    Readln(LLine);
  except
    on E: Exception do
    begin
      Writeln('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
