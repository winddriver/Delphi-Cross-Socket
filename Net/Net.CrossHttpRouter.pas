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
    class function &Static(const ALocalDir, AFileParamName: string): TCrossHttpRouterProc2; static;

    /// <summary>
    ///   文件列表路由
    /// </summary>
    /// <param name="APath">
    ///   请求路径, 该参数是为了在目录列表页面中定位根路径
    /// </param>
    /// <param name="ALocalDir">
    ///   本地目录
    /// </param>
    class function Dir(const APath, ALocalDir, ADirParamName: string): TCrossHttpRouterProc2; static;

    /// <summary>
    ///   含有默认首页文件的静态文件路由
    /// </summary>
    /// <param name="ALocalDir">
    ///   含有默认首页文件的本地目录
    /// </param>
    /// <param name="ADefIndexFiles">
    ///   默认的首页文件,按顺序选择,先找到哪个就使用哪个
    /// </param>
    class function Index(const ALocalDir, AFileParamName: string; const ADefIndexFiles: TArray<string>): TCrossHttpRouterProc2; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Net.CrossHttpRouterDirUtils,
  Net.CrossHttpUtils;

{ TNetCrossRouter }

class function TNetCrossRouter.Index(const ALocalDir, AFileParamName: string;
  const ADefIndexFiles: TArray<string>): TCrossHttpRouterProc2;
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
      LPath, LFile, LDefMainFile: string;
    begin
      LPath := ALocalDir;
      LFile := ARequest.Params[AFileParamName];

      if (LFile = '') then
      begin
        for LDefMainFile in LDefIndexFiles do
        begin
          LFile := TCrossHttpUtils.CombinePath(LPath, LDefMainFile);
          if TFile.Exists(LFile) then
          begin
            AResponse.SendFile(LFile);
            AHandled := True;
            Exit;
          end;
        end;
      end else
      begin
        LFile := TCrossHttpUtils.CombinePath(LPath, LFile);
        if TFile.Exists(LFile) then
        begin
          AResponse.SendFile(LFile);
          AHandled := True;
          Exit;
        end;
      end;

      AHandled := False;
    end;
end;

class function TNetCrossRouter.Static(
  const ALocalDir, AFileParamName: string): TCrossHttpRouterProc2;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LFile: string;
    begin
      AHandled := True;
      LFile := TCrossHttpUtils.CombinePath(ALocalDir, ARequest.Params[AFileParamName]);
      if (LFile = '') then
      begin
        AHandled := False;
        Exit;
      end;
      LFile := TPath.GetFullPath(LFile);
      AResponse.SendFile(LFile);
    end;
end;

class function TNetCrossRouter.Dir(
  const APath, ALocalDir, ADirParamName: string): TCrossHttpRouterProc2;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LFile: string;
    begin
      AHandled := True;

      LFile := TCrossHttpUtils.CombinePath(ALocalDir, ARequest.Params[ADirParamName]);
      if (LFile = '') then
      begin
        AHandled := False;
        Exit;
      end;

      LFile := TPath.GetFullPath(LFile);
      if (TDirectory.Exists(LFile)) then
        AResponse.Send(BuildDirList(LFile, ARequest.Path, APath))
      else if TFile.Exists(LFile) then
        AResponse.SendFile(LFile)
      else
        AHandled := False;
    end;
end;

end.
