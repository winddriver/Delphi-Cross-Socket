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
    class function Dir(const APath, ALocalDir, ADirParamName: string): TCrossHttpRouterProc; static;

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
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LFileName, LResolvedPath: string;
    begin
      AHandled := True;

      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[ADirParamName]);
      if not TCrossHttpUtils.TryUrlPathToLocalPath(ALocalDir, LFileName, LResolvedPath) then
      begin
        AHandled := False;
        Exit;
      end;

      if (TDirectoryUtils.Exists(LResolvedPath)) then
        AResponse.Send(BuildDirList(LResolvedPath, ARequest.Path, APath))
      else if TFileUtils.Exists(LResolvedPath) then
        AResponse.SendFile(LResolvedPath)
      else
        AHandled := False;
    end;
end;

end.
