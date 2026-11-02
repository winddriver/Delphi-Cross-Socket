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

  Net.CrossHttpRouterDirUtils, Net.CrossHttpRouteFile,
  Net.CrossHttpUtils,

  Utils.IOUtils;

function SendRouteFile(const AResponse: ICrossHttpResponse; const ABaseDir, APath: string): Boolean;
var
  LFile: THttpRouteFile;
begin
  LFile := THttpRouteFile.Open(ABaseDir, APath);
  if LFile = nil then Exit(False);
  if LFile.Directory then
  begin
    LFile.Free;
    Exit(False);
  end;
  SendOpenedHttpFile(AResponse, LFile.RelativePath, LFile.Modified, LFile);
  Result := True;
end;

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
      LFileName, LIndex: string;
    begin
      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[AFileParamName]);
      if LFileName <> '' then
        AHandled := SendRouteFile(AResponse, ALocalDir, LFileName)
      else
      begin
        AHandled := False;
        for LIndex in LDefIndexFiles do
          if SendRouteFile(AResponse, ALocalDir, LIndex) then
          begin
            AHandled := True;
            Break;
          end;
      end;
    end;
end;

class function TNetCrossRouter.Static(
  const ALocalDir, AFileParamName: string): TCrossHttpRouterProc;
begin
  Result :=
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    var
      LFileName: string;
    begin
      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[AFileParamName]);
      AHandled := SendRouteFile(AResponse, ALocalDir, LFileName);
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
      LFile: THttpRouteFile;
      LFileName, LRelativePath, LRequestPath: string;
    begin
      LFileName := TCrossHttpUtils.GetPathWithoutParams(ARequest.Params[ADirParamName]);
      LFile := THttpRouteFile.Open(ALocalDir, LFileName);
      AHandled := LFile <> nil;
      if not AHandled then Exit;
      if LFile.Directory then
      try
        LRelativePath := LFile.RelativePath;
        {$IFDEF MSWINDOWS}
        LRelativePath := LRelativePath.Replace('\', '/');
        {$ENDIF}
        LRequestPath := TPathUtils.Combine(APath, LRelativePath, '/');
        AResponse.Send(BuildDirList('', LRequestPath, APath, AMaxEntries, LFile));
      finally
        LFile.Free;
      end else
        SendOpenedHttpFile(AResponse, LFile.RelativePath, LFile.Modified, LFile);
    end;
end;

end.
