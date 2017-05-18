unit uAppCfg;

interface

uses
  System.Classes, System.SysUtils, System.IniFiles, System.Generics.Collections;

type
  TAppConfig = class
  private
    class var FInstance: TAppConfig;
    class constructor Create;
    class destructor Destroy;
  private
    FIni: TMemIniFile;
    FDirMaps: TStrings;
    function GetListenPort: Word;
    function GetRootPath: string;
    function GetDirMaps: TStrings;
  public
    constructor Create;
    destructor Destroy; override;

    property ListenPort: Word read GetListenPort;
    property DirMaps: TStrings read GetDirMaps;
    property RootPath: string read GetRootPath;
  end;

  function AppCfg: TAppConfig;

implementation

uses
  Utils.Utils;

function AppCfg: TAppConfig;
begin
  Exit(TAppConfig.FInstance);
end;

{ TAppConfig }

constructor TAppConfig.Create;
begin
  FIni := TMemIniFile.Create(TUtils.AppPath + TUtils.AppName + '.ini');
  FDirMaps := TStringList.Create;
end;

destructor TAppConfig.Destroy;
begin
  FreeAndNil(FIni);
  FreeAndNil(FDirMaps);
  inherited Destroy;
end;

class constructor TAppConfig.Create;
begin
  FInstance := TAppConfig.Create;
end;

class destructor TAppConfig.Destroy;
begin
  FreeAndNil(FInstance);
end;

function TAppConfig.GetDirMaps: TStrings;
begin
  if (FDirMaps.Count <= 0) then
    FIni.ReadSectionValues('DirMaps', FDirMaps);
  if (FDirMaps.Count <= 0) then
    FDirMaps.Values['/'] := TUtils.AppPath;
  Result := FDirMaps;
end;

function TAppConfig.GetListenPort: Word;
begin
  Result := FIni.ReadInteger('Server', 'Port', 8000);
end;

function TAppConfig.GetRootPath: string;
begin
  Result := FIni.ReadString('Server', 'RootPath', TUtils.AppPath);
end;

end.
