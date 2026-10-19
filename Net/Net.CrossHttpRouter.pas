{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpRouter;

{$I zLib.inc}

interface

uses
  Net.CrossHttpServer;

type
  /// <summary>
  ///   路由
  /// </summary>
  /// <remarks>
  ///   用于 TCrossHttpServer.Route(), Get(), Post() 等
  /// </remarks>
  TNetCrossRouter = class
  public
    /// <summary>
    ///   静态文件路由
    /// </summary>
    /// <param name="ALocalDir">
    ///   本地目录
    /// </param>
    class function &Static(const ALocalDir, AFileParamName: string): TCrossHttpRouterProc; static;

    /// <summary>
    ///   文件列表路由
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 该参数是为了在目录列表页面中定位根路径
    /// </param>
    /// <param name="ALocalDir">
    ///   本地目录
    /// </param>
    class function Dir(const APath, ALocalDir, ADirParamName: string): TCrossHttpRouterProc; overload; static;
    /// <summary>
    ///   限制目录列表条目数，0 表示完整列表；负数拒绝。只排序枚举前 N 项，直接下载不受限制。
    /// </summary>
    class function Dir(const APath, ALocalDir, ADirParamName: string;
      const AMaxEntries: Integer): TCrossHttpRouterProc; overload; static;

    /// <summary>
    ///   含有默认首页文件的静态文件路由
    /// </summary>
    /// <param name="ALocalDir">
    ///   含有默认首页文件的本地目录
    /// </param>
    /// <param name="ADefIndexFiles">
    ///   默认的首页文件,按顺序选择,先找到哪个就使用哪个
    /// </param>
    class function Index(const ALocalDir, AFileParamName: string; const ADefIndexFiles: TArray<string>): TCrossHttpRouterProc; static;
  end;

implementation

uses
  SysUtils,
  Classes,

  Net.CrossHttpRouterDirUtils,
  Net.CrossHttpUtils,

  Utils.IOUtils;

{ TNetCrossRouter }

class function TNetCrossRouter.Index(const ALocalDir, AFileParamName: string;
  const ADefIndexFiles: TArray<string>): TCrossHttpRouterProc;
var
  LDefIndexFiles: TArray<string>;
begin
  if (ADefIndexFiles <> nil) then
    LDefIndexFiles := ADefIndexFiles
  else
    LDefIndexFiles := [
      'index.html',
      'main.html',
      'index.js',
      'main.js',
      'index.htm',
      'main.htm'
    ];

  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LLocalBaseDir, LFileName, LDefMainFileName, LResolvedPath: string;
    begin
      LLocalBaseDir := TPathUtils.GetFullPath(ALocalDir);
      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[AFileParamName]);

      if (LFileName = '') then
      begin
        for LDefMainFileName in LDefIndexFiles do
        begin
          if TCrossHttpUtils.TryUrlPathToLocalPath(LLocalBaseDir, LDefMainFileName, LResolvedPath)
            and TFileUtils.Exists(LResolvedPath) then
          begin
            AResponse.SendFile(LResolvedPath);
            AHandled := True;
            Exit;
          end;
        end;
      end else
      begin
        if TCrossHttpUtils.TryUrlPathToLocalPath(LLocalBaseDir, LFileName, LResolvedPath)
          and TFileUtils.Exists(LResolvedPath) then
        begin
          AResponse.SendFile(LResolvedPath);
          AHandled := True;
          Exit;
        end;
      end;

      AHandled := False;
    end;
end;

class function TNetCrossRouter.Static(
  const ALocalDir, AFileParamName: string): TCrossHttpRouterProc;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LFileName, LResolvedPath: string;
    begin
      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[AFileParamName]);
      if not TCrossHttpUtils.TryUrlPathToLocalPath(ALocalDir, LFileName, LResolvedPath) then
      begin
        AHandled := False;
        Exit;
      end;
      if not TFileUtils.Exists(LResolvedPath) then
      begin
        AHandled := False;
        Exit;
      end;
      AResponse.SendFile(LResolvedPath);
      AHandled := True;
    end;
end;

class function TNetCrossRouter.Dir(
  const APath, ALocalDir, ADirParamName: string): TCrossHttpRouterProc;
begin
  Result := Dir(APath, ALocalDir, ADirParamName, 0);
end;

class function TNetCrossRouter.Dir(
  const APath, ALocalDir, ADirParamName: string;
  const AMaxEntries: Integer): TCrossHttpRouterProc;
begin
  if AMaxEntries < 0 then
    raise EArgumentOutOfRangeException.Create('目录条目上限不能为负数');
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LFileName, LResolvedPath, LLocalBaseDir, LRelativePath, LRequestPath: string;
    begin
      AHandled := True;

      LLocalBaseDir := TPathUtils.GetFullPath(ALocalDir);
      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[ADirParamName]);
      if not TCrossHttpUtils.TryUrlPathToLocalPath(LLocalBaseDir, LFileName, LResolvedPath) then
      begin
        AHandled := False;
        Exit;
      end;

      if (TDirectoryUtils.Exists(LResolvedPath)) then
      begin
        // 导航使用已通过边界检查的路径，不能重新展示被 .. 消除的请求片段。
        if TPathUtils.IsSamePath(LLocalBaseDir, LResolvedPath) then
          LRelativePath := ''
        else
          LRelativePath := Copy(LResolvedPath,
            Length(IncludeTrailingPathDelimiter(LLocalBaseDir)) + 1, MaxInt);
        {$IFDEF MSWINDOWS}
        LRelativePath := LRelativePath.Replace('\', '/');
        {$ENDIF}
        LRequestPath := TPathUtils.Combine(APath, LRelativePath, '/');
        AResponse.Send(BuildDirList(LResolvedPath, LRequestPath, APath, AMaxEntries));
      end else
      if TFileUtils.Exists(LResolvedPath) then
        AResponse.SendFile(LResolvedPath)
      else
        AHandled := False;
    end;
end;

end.
