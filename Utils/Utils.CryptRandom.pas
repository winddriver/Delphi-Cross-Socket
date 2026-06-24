unit Utils.CryptRandom;
{*
  加密随机数生成工具单元
  
  提供跨平台的加密安全随机数生成功能
  - Windows: 使用 BCryptGenRandom 或 SystemFunction036 (RtlGenRandom)
  - Linux/Unix: 使用 /dev/urandom
  
  注意: 不使用 Pascal 自带的 Random/RandomRange 等函数，因为:
  1. 内置随机数生成器使用伪随机算法(如线性同余)，可预测性强
  2. 加密场景需要密码学安全的随机数(CSPRNG)，内置函数不满足要求
  3. 本单元使用操作系统提供的加密级随机数源，确保不可预测性
*}

{$I zLib.inc}

interface

function TryFillCryptRandomBytes(var ABuf; const ASize: Integer): Boolean;

implementation

uses
  SysUtils,
  Classes
  {$IFDEF MSWINDOWS}
  , Windows
  {$ENDIF}
  ;

{$IFDEF MSWINDOWS}
const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;
  STATUS_SUCCESS = 0;

type
  TBCryptGenRandom = function(hAlgorithm: Pointer; pbBuffer: Pointer;
    cbBuffer, dwFlags: Cardinal): LongInt; stdcall;
  TSystemFunction036 = function(RandomBuffer: Pointer;
    RandomBufferLength: Cardinal): LongBool; stdcall;

var
  GBCryptModule: HMODULE;
  GAdvapiModule: HMODULE;
  GBCryptGenRandom: TBCryptGenRandom;
  GSystemFunction036: TSystemFunction036;

procedure InitCryptRandomLibraries;
begin
  GBCryptModule := LoadLibrary('bcrypt.dll');
  if (GBCryptModule <> 0) then
    GBCryptGenRandom := TBCryptGenRandom(GetProcAddress(GBCryptModule, 'BCryptGenRandom'));

  GAdvapiModule := LoadLibrary('advapi32.dll');
  if (GAdvapiModule <> 0) then
    GSystemFunction036 := TSystemFunction036(GetProcAddress(GAdvapiModule, 'SystemFunction036'));
end;

procedure DoneCryptRandomLibraries;
begin
  GBCryptGenRandom := nil;
  GSystemFunction036 := nil;

  if (GBCryptModule <> 0) then
  begin
    FreeLibrary(GBCryptModule);
    GBCryptModule := 0;
  end;

  if (GAdvapiModule <> 0) then
  begin
    FreeLibrary(GAdvapiModule);
    GAdvapiModule := 0;
  end;
end;

function TryFillByBCrypt(const ABuf: Pointer; const ASize: Cardinal): Boolean;
begin
  if not Assigned(GBCryptGenRandom) then Exit(False);

  Result := GBCryptGenRandom(nil, ABuf, ASize, BCRYPT_USE_SYSTEM_PREFERRED_RNG) = STATUS_SUCCESS;
end;

function TryFillBySystemFunction036(const ABuf: Pointer; const ASize: Cardinal): Boolean;
begin
  if not Assigned(GSystemFunction036) then Exit(False);

  Result := GSystemFunction036(ABuf, ASize);
end;
{$ENDIF}

function TryFillCryptRandomBytes(var ABuf; const ASize: Integer): Boolean;
{$IFDEF MSWINDOWS}
begin
  if (ASize < 0) then Exit(False);
  if (ASize = 0) then Exit(True);

  Result := TryFillByBCrypt(@ABuf, Cardinal(ASize));
  if not Result then
    Result := TryFillBySystemFunction036(@ABuf, Cardinal(ASize));
end;
{$ELSE}
var
  LStream: TFileStream;
  LRead: Integer;
  LTotal: Integer;
  P: PByte;
begin
  if (ASize < 0) then Exit(False);
  if (ASize = 0) then Exit(True);

  Result := False;
  LStream := nil;
  try
    LStream := TFileStream.Create('/dev/urandom', fmOpenRead or fmShareDenyNone);
    try
      LTotal := 0;
      P := @ABuf;
      while LTotal < ASize do
      begin
        LRead := LStream.Read(P^, ASize - LTotal);
        if (LRead <= 0) then Exit;

        Inc(P, LRead);
        Inc(LTotal, LRead);
      end;

      Result := True;
    finally
      LStream.Free;
    end;
  except
    Result := False;
  end;
end;
{$ENDIF}

initialization
{$IFDEF MSWINDOWS}
  InitCryptRandomLibraries;
{$ENDIF}

finalization
{$IFDEF MSWINDOWS}
  DoneCryptRandomLibraries;
{$ENDIF}

end.
