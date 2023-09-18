unit Utils.Hash;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,

  {$IFDEF DELPHI}
  Hash,
    {$IF CompilerVersion < 35.0}
    DTF.Hash,
    {$ENDIF}
  {$ELSE FPC}
  CnMD5,
  CnSHA1,
  CnSHA2,
  DTF.Hash,
  {$ENDIF}

  Utils.Utils,
  CnPemUtils,
  CnSM3;

const
  HMAC_INNER_PAD: Byte = $36;
  HMAC_OUTER_PAD: Byte = $5C;

type
  THashBase = class abstract
  private
    FKey: TBytes;
    FHashBytes: TBytes;
    FFinished: Boolean;
  protected
    class function BytesToHex(const AData: TBytes): string; static; inline;
    class function StrToBytes(const AStr: string): TBytes; static; inline;
  public
    constructor Create; overload; virtual;

    class function CreateHash: THashBase; virtual; abstract;

    {$region '核心hash方法'}
    function GetBlockSize: Integer; virtual; abstract;
    function GetHashSize: Integer; virtual; abstract;

    // 基础 hash 方法
    // 调用顺序: Start -> Update -> Finish
    procedure Start; virtual; abstract;
    procedure Update(const AData: Pointer; const ASize: Cardinal); overload; virtual; abstract;
    procedure Update(const AData: TBytes); overload;
    procedure Update(const AData: string); overload;
    function Finish: TBytes; virtual; abstract;

    function HashAsBytes: TBytes; inline;
    function HashAsString: string; inline;

    // 带密钥的 hash 方法
    // 调用顺序: HMACStart -> Update -> HMACFinish
    procedure HMACStart(const AKey: TBytes); virtual;
    function HMACFinish: TBytes; virtual;
    {$endregion}

    class function GetHashBytes(const AData: Pointer; const ASize: Integer): TBytes; overload;
    class function GetHashBytes(const AData: TBytes): TBytes; overload; inline;
    class function GetHashBytes(const AData: string): TBytes; overload; inline;
    class function GetHashBytes(const AStream: TStream): TBytes; overload;
    class function GetHashBytesFromFile(const AFileName: TFileName): TBytes;

    class function GetHashString(const AData: Pointer; const ASize: Integer): string; overload; inline;
    class function GetHashString(const AData: TBytes): string; overload; inline;
    class function GetHashString(const AData: string): string; overload; inline;
    class function GetHashString(const AStream: TStream): string; overload; inline;
    class function GetHashStringFromFile(const AFileName: TFileName): string; inline;

    class function GetHMACBytes(const AData: Pointer; const ASize: Integer; const AKey: TBytes): TBytes; overload;
    class function GetHMACBytes(const AData, AKey: TBytes): TBytes; overload; inline;
    class function GetHMACBytes(const AData: string; const AKey: TBytes): TBytes; overload; inline;
    class function GetHMACBytes(const AStream: TStream; const AKey: TBytes): TBytes; overload;
    class function GetHMACBytesFromFile(const AFileName: TFileName; const AKey: TBytes): TBytes; overload;

    class function GetHMACBytes(const AData: Pointer; const ASize: Integer; const AKey: string): TBytes; overload; inline;
    class function GetHMACBytes(const AData: TBytes; const AKey: string): TBytes; overload; inline;
    class function GetHMACBytes(const AData, AKey: string): TBytes; overload; inline;
    class function GetHMACBytes(const AStream: TStream; const AKey: string): TBytes; overload; inline;
    class function GetHMACBytesFromFile(const AFileName: TFileName; const AKey: string): TBytes; overload; inline;

    class function GetHMACString(const AData: Pointer; const ASize: Integer; const AKey: TBytes): string; overload; inline;
    class function GetHMACString(const AData, AKey: TBytes): string; overload; inline;
    class function GetHMACString(const AData: string; const AKey: TBytes): string; overload; inline;
    class function GetHMACString(const AStream: TStream; const AKey: TBytes): string; overload; inline;
    class function GetHMACStringFromFile(const AFileName: TFileName; const AKey: TBytes): string; overload; inline;

    class function GetHMACString(const AData: Pointer; const ASize: Integer; const AKey: string): string; overload; inline;
    class function GetHMACString(const AData: TBytes; const AKey: string): string; overload; inline;
    class function GetHMACString(const AData, AKey: string): string; overload; inline;
    class function GetHMACString(const AStream: TStream; const AKey: string): string; overload; inline;
    class function GetHMACStringFromFile(const AFileName: TFileName; const AKey: string): string; overload; inline;
  end;

  // 国密 sm3 hash 算法
  THashSM3 = class(THashBase)
  private
    FContext: TCnSM3Context;
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;
  end;

  THashMD5 = class(THashBase)
  private
    {$IFDEF DELPHI}
    FMD5: System.Hash.THashMD5;
    {$ELSE}
    FMD5Context: TCnMD5Context;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;
  end;

  THashSHA1 = class(THashBase)
  private
    {$IFDEF DELPHI}
    FSHA1: System.Hash.THashSHA1;
    {$ELSE}
    FSHA1Context: TCnSHA1Context;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;
  end;

  THashSHA256 = class(THashBase)
  private
    {$IFDEF DELPHI}
    FSHA256: System.Hash.THashSHA2;
    {$ELSE}
    FSHA256Context: TCnSHA256Context;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;
  end;

  THashSHA384 = class(THashBase)
  private
    {$IFDEF DELPHI}
    FSHA384: System.Hash.THashSHA2;
    {$ELSE}
    FSHA384Context: TCnSHA384Context;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;
  end;

  THashSHA512 = class(THashBase)
  private
    {$IFDEF DELPHI}
    FSHA512: System.Hash.THashSHA2;
    {$ELSE}
    FSHA512Context: TCnSHA512Context;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;
  end;

  THashBobJenkins = class(THashBase)
  private type
    TExternalHashBobJenkins = {$IFDEF DELPHI}Hash.{$ELSE}DTF.Hash.{$ENDIF}THashBobJenkins;
  private
    FBobJenkins: TExternalHashBobJenkins;
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;

    class function GetHashValue(const AData: string): Integer; overload; static; inline;
    class function GetHashValue(const AData; ALength: Integer; AInitialValue: Integer = 0): Integer; overload; static; inline;
  end;

  THashFNV1a32 = class(THashBase)
  private type
    TExternalFNV1a32 =
      {$IFDEF DELPHI}
        {$IF CompilerVersion >= 35.0}
        Hash.
        {$ELSE}
        DTF.Hash.
        {$ENDIF}
      {$ELSE}
      DTF.Hash.
      {$ENDIF}
      THashFNV1a32;
  private
    FFNV1a32: TExternalFNV1a32;
  public
    class function CreateHash: THashBase; override;

    function GetBlockSize: Integer; override;
    function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: Cardinal); override;
    function Finish: TBytes; override;

    class function GetHashValue(const AData: string): Integer; overload; static; inline;
    class function GetHashValue(const AData; ALength: Cardinal; AInitialValue: Cardinal = TExternalFNV1a32.FNV_SEED): Integer; overload; static; inline;
  end;

implementation

{ THashBase }

class function THashBase.BytesToHex(const AData: TBytes): string;
begin
  Result := TUtils.BytesToHex(AData);
end;

class function THashBase.GetHashBytes(const AData: Pointer;
  const ASize: Integer): TBytes;
var
  LHash: THashBase;
begin
  LHash := CreateHash;
  try
    LHash.Update(AData, ASize);
    Result := LHash.Finish;
  finally
    FreeAndNil(LHash);
  end;
end;

class function THashBase.GetHashBytes(const AData: TBytes): TBytes;
begin
  Result := GetHashBytes(Pointer(AData), Length(AData));
end;

class function THashBase.GetHashBytes(const AData: string): TBytes;
begin
  Result := GetHashBytes(StrToBytes(AData));
end;

constructor THashBase.Create;
begin
  Start;
end;

class function THashBase.GetHashBytes(const AStream: TStream): TBytes;
const
  BUFFERSIZE = 4 * 1024;
var
  LHash: THashBase;
  LBuffer: TBytes;
  LBytesRead: NativeInt;
begin
  LHash := CreateHash;
  try
    SetLength(LBuffer, BUFFERSIZE);
    while True do
    begin
      LBytesRead := AStream.ReadData(LBuffer, BUFFERSIZE);
      if (LBytesRead <= 0) then Break;

      LHash.Update(Pointer(LBuffer), LBytesRead);
    end;
    Result := LHash.Finish;
  finally
    FreeAndNil(LHash);
  end;
end;

class function THashBase.GetHashBytesFromFile(
  const AFileName: TFileName): TBytes;
var
  LFile: TFileStream;
begin
  LFile := TFileStream.Create(AFileName, fmShareDenyNone or fmOpenRead);
  try
    Result := GetHashBytes(LFile);
  finally
    LFile.Free;
  end;
end;

class function THashBase.GetHashString(const AData: Pointer;
  const ASize: Integer): string;
begin
  Result := BytesToHex(GetHashBytes(AData, ASize));
end;

class function THashBase.GetHashString(const AData: TBytes): string;
begin
  Result := BytesToHex(GetHashBytes(AData));
end;

class function THashBase.GetHashString(const AData: string): string;
begin
  Result := BytesToHex(GetHashBytes(AData));
end;

class function THashBase.GetHashString(const AStream: TStream): string;
begin
  Result := BytesToHex(GetHashBytes(AStream));
end;

class function THashBase.GetHashStringFromFile(
  const AFileName: TFileName): string;
begin
  Result := BytesToHex(GetHashBytesFromFile(AFileName));
end;

class function THashBase.GetHMACBytes(const AData: Pointer;
  const ASize: Integer; const AKey: TBytes): TBytes;
var
  LHash: THashBase;
begin
  LHash := CreateHash;
  try
    LHash.HMACStart(AKey);
    LHash.Update(AData, ASize);
    Result := LHash.HMACFinish;
  finally
    FreeAndNil(LHash);
  end;
end;

class function THashBase.GetHMACBytes(const AData, AKey: TBytes): TBytes;
begin
  Result := GetHMACBytes(Pointer(AData), Length(AData), AKey);
end;

class function THashBase.GetHMACBytes(const AData: string; const AKey: TBytes): TBytes;
begin
  Result := GetHMACBytes(StrToBytes(AData), AKey);
end;

class function THashBase.GetHMACBytes(const AStream: TStream; const AKey: TBytes): TBytes;
const
  BUFFERSIZE = 4 * 1024;
var
  LHash: THashBase;
  LBuffer: TBytes;
  LBytesRead: NativeInt;
begin
  LHash := CreateHash;
  try
    LHash.HMACStart(AKey);

    SetLength(LBuffer, BUFFERSIZE);
    while True do
    begin
      LBytesRead := AStream.ReadData(LBuffer, BUFFERSIZE);
      if (LBytesRead <= 0) then Break;

      LHash.Update(Pointer(LBuffer), LBytesRead);
    end;

    Result := LHash.HMACFinish;
  finally
    FreeAndNil(LHash);
  end;
end;

class function THashBase.GetHMACBytesFromFile(
  const AFileName: TFileName; const AKey: TBytes): TBytes;
var
  LFile: TFileStream;
begin
  LFile := TFileStream.Create(AFileName, fmShareDenyNone or fmOpenRead);
  try
    Result := GetHMACBytes(LFile, AKey);
  finally
    LFile.Free;
  end;
end;

class function THashBase.GetHMACString(const AData, AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AData, AKey));
end;

class function THashBase.GetHMACString(const AData: Pointer;
  const ASize: Integer; const AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AData, ASize, AKey));
end;

class function THashBase.GetHMACString(const AData: string;
  const AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AData, AKey));
end;

class function THashBase.GetHMACString(const AStream: TStream;
  const AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AStream, AKey));
end;

class function THashBase.GetHMACStringFromFile(const AFileName: TFileName;
  const AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytesFromFile(AFileName, AKey));
end;

function THashBase.HashAsBytes: TBytes;
begin
  if not FFinished then
  begin
    FHashBytes := Finish;
    FFinished := True;
  end;

  Result := FHashBytes;
end;

function THashBase.HashAsString: string;
begin
  Result := BytesToHex(HashAsBytes);
end;

function THashBase.HMACFinish: TBytes;
var
  LTempBuffer1, LTempBuffer2: TBytes;
  I: Integer;
begin
  LTempBuffer2 := Finish;

  SetLength(LTempBuffer1, Length(FKey));
  for I := Low(FKey) to High(FKey) do
    LTempBuffer1[I] := FKey[I] xor HMAC_OUTER_PAD;

  Start;
  Update(LTempBuffer1);
  Update(LTempBuffer2);
  Result := Finish;
end;

procedure THashBase.HMACStart(const AKey: TBytes);
var
  LKeySize, LBlockSize, I: Integer;
  LTempBuffer1: TBytes;
begin
  FKey := AKey;
  LKeySize := Length(FKey);
  LBlockSize := GetBlockSize;
  if (LKeySize > LBlockSize) then
  begin
    Start;
    Update(FKey);
    FKey := Finish;
    LKeySize := Length(FKey);
  end;

  if (LKeySize < LBlockSize) then
  begin
    SetLength(FKey, LBlockSize);
    FillChar(FKey[LKeySize], LBlockSize - LKeySize, 0);
  end;

  SetLength(LTempBuffer1, Length(FKey));
  for I := Low(FKey) to High(FKey) do
    LTempBuffer1[I] := FKey[I] xor HMAC_INNER_PAD;

  Start;
  Update(LTempBuffer1);
end;

class function THashBase.StrToBytes(const AStr: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AStr);
end;

procedure THashBase.Update(const AData: TBytes);
begin
  Update(Pointer(AData), Length(AData));
end;

procedure THashBase.Update(const AData: string);
begin
  Update(StrToBytes(AData));
end;

class function THashBase.GetHMACBytes(const AData: Pointer;
  const ASize: Integer; const AKey: string): TBytes;
begin
  Result := GetHMACBytes(AData, ASize, StrToBytes(AKey));
end;

class function THashBase.GetHMACBytes(const AData: TBytes;
  const AKey: string): TBytes;
begin
  Result := GetHMACBytes(AData, StrToBytes(AKey));
end;

class function THashBase.GetHMACBytes(const AData, AKey: string): TBytes;
begin
  Result := GetHMACBytes(AData, StrToBytes(AKey));
end;

class function THashBase.GetHMACBytes(const AStream: TStream;
  const AKey: string): TBytes;
begin
  Result := GetHMACBytes(AStream, StrToBytes(AKey));
end;

class function THashBase.GetHMACBytesFromFile(const AFileName: TFileName;
  const AKey: string): TBytes;
begin
  Result := GetHMACBytesFromFile(AFileName, StrToBytes(AKey));
end;

class function THashBase.GetHMACString(const AData: Pointer;
  const ASize: Integer; const AKey: string): string;
begin
  Result := GetHMACString(AData, ASize, StrToBytes(AKey));
end;

class function THashBase.GetHMACString(const AData: TBytes;
  const AKey: string): string;
begin
  Result := GetHMACString(AData, StrToBytes(AKey));
end;

class function THashBase.GetHMACString(const AData, AKey: string): string;
begin
  Result := GetHMACString(AData, StrToBytes(AKey));
end;

class function THashBase.GetHMACString(const AStream: TStream;
  const AKey: string): string;
begin
  Result := GetHMACString(AStream, StrToBytes(AKey));
end;

class function THashBase.GetHMACStringFromFile(const AFileName: TFileName;
  const AKey: string): string;
begin
  Result := GetHMACStringFromFile(AFileName, StrToBytes(AKey));
end;

{ THashSM3 }

class function THashSM3.CreateHash: THashBase;
begin
  Result := THashSM3.Create;
end;

function THashSM3.Finish: TBytes;
var
  LDigest: TCnSM3Digest;
begin
  SM3Final(FContext, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;

function THashSM3.GetBlockSize: Integer;
begin
  Result := 64;
end;

function THashSM3.GetHashSize: Integer;
begin
  Result := SizeOf(TCnSM3Digest);
end;

procedure THashSM3.Start;
begin
  SM3Init(FContext);
  FFinished := False;
end;

procedure THashSM3.Update(const AData: Pointer; const ASize: Cardinal);
begin
  SM3Update(FContext, AData, ASize);
end;

{ THashMD5 }

class function THashMD5.CreateHash: THashBase;
begin
  Result := THashMD5.Create;
end;

function THashMD5.Finish: TBytes;
{$IFDEF DELPHI}
begin
  Result := FMD5.HashAsBytes;
end;
{$ELSE}
var
  LDigest: TCnMD5Digest;
begin
  MD5Final(FMD5Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ENDIF}

function THashMD5.GetBlockSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FMD5.GetBlockSize;
  {$ELSE}
  Result := SizeOf(TCnMD5Block);
  {$ENDIF}
end;

function THashMD5.GetHashSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FMD5.GetHashSize;
  {$ELSE}
  Result := SizeOf(TCnMD5Digest);
  {$ENDIF}
end;

procedure THashMD5.Start;
begin
  {$IFDEF DELPHI}
  FMD5.Reset;
  {$ELSE}
  MD5Init(FMD5Context);
  {$ENDIF}
end;

procedure THashMD5.Update(const AData: Pointer; const ASize: Cardinal);
begin
  {$IFDEF DELPHI}
  FMD5.Update(AData^, ASize);
  {$ELSE}
  MD5Update(FMD5Context, AData, ASize);
  {$ENDIF}
end;

{ THashSHA1 }

class function THashSHA1.CreateHash: THashBase;
begin
  Result := THashSHA1.Create;
end;

function THashSHA1.Finish: TBytes;
{$IFDEF DELPHI}
begin
  Result := FSHA1.HashAsBytes;
end;
{$ELSE}
var
  LDigest: TCnSHA1Digest;
begin
  SHA1Final(FSHA1Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ENDIF}

function THashSHA1.GetBlockSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA1.GetBlockSize;
  {$ELSE}
  Result := 64;
  {$ENDIF}
end;

function THashSHA1.GetHashSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA1.GetHashSize;
  {$ELSE}
  Result := 20;
  {$ENDIF}
end;

procedure THashSHA1.Start;
begin
  {$IFDEF DELPHI}
  FSHA1.Reset;
  {$ELSE}
  SHA1Init(FSHA1Context);
  {$ENDIF}
end;

procedure THashSHA1.Update(const AData: Pointer; const ASize: Cardinal);
begin
  {$IFDEF DELPHI}
  FSHA1.Update(AData^, ASize);
  {$ELSE}
  SHA1Update(FSHA1Context, AData, ASize);
  {$ENDIF}
end;

{ THashSHA256 }

class function THashSHA256.CreateHash: THashBase;
begin
  Result := THashSHA256.Create;
end;

function THashSHA256.Finish: TBytes;
{$IFDEF DELPHI}
begin
  Result := FSHA256.HashAsBytes;
end;
{$ELSE}
var
  LDigest: TCnSHA256Digest;
begin
  SHA256Final(FSHA256Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ENDIF}

function THashSHA256.GetBlockSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA256.GetBlockSize;
  {$ELSE}
  Result := 64;
  {$ENDIF}
end;

function THashSHA256.GetHashSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA256.GetHashSize;
  {$ELSE}
  Result := 32;
  {$ENDIF}
end;

procedure THashSHA256.Start;
begin
  {$IFDEF DELPHI}
  FSHA256 := System.Hash.THashSHA2.Create(SHA256);
  FSHA256.Reset;
  {$ELSE}
  SHA256Init(FSHA256Context);
  {$ENDIF}
end;

procedure THashSHA256.Update(const AData: Pointer; const ASize: Cardinal);
begin
  {$IFDEF DELPHI}
  FSHA256.Update(AData^, ASize);
  {$ELSE}
  SHA256Update(FSHA256Context, AData, ASize);
  {$ENDIF}
end;

{ THashSHA384 }

class function THashSHA384.CreateHash: THashBase;
begin
  Result := THashSHA384.Create;
end;

function THashSHA384.Finish: TBytes;
{$IFDEF DELPHI}
begin
  Result := FSHA384.HashAsBytes;
end;
{$ELSE}
var
  LDigest: TCnSHA384Digest;
begin
  SHA384Final(FSHA384Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ENDIF}

function THashSHA384.GetBlockSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA384.GetBlockSize;
  {$ELSE}
  Result := 128;
  {$ENDIF}
end;

function THashSHA384.GetHashSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA384.GetHashSize;
  {$ELSE}
  Result := 48;
  {$ENDIF}
end;

procedure THashSHA384.Start;
begin
  {$IFDEF DELPHI}
  FSHA384 := System.Hash.THashSHA2.Create(SHA384);
  FSHA384.Reset;
  {$ELSE}
  SHA384Init(FSHA384Context);
  {$ENDIF}
end;

procedure THashSHA384.Update(const AData: Pointer; const ASize: Cardinal);
begin
  {$IFDEF DELPHI}
  FSHA384.Update(AData^, ASize);
  {$ELSE}
  SHA384Update(FSHA384Context, AData, ASize);
  {$ENDIF}
end;

{ THashSHA512 }

class function THashSHA512.CreateHash: THashBase;
begin
  Result := THashSHA512.Create;
end;

function THashSHA512.Finish: TBytes;
{$IFDEF DELPHI}
begin
  Result := FSHA512.HashAsBytes;
end;
{$ELSE}
var
  LDigest: TCnSHA512Digest;
begin
  SHA512Final(FSHA512Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ENDIF}

function THashSHA512.GetBlockSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA512.GetBlockSize;
  {$ELSE}
  Result := 128;
  {$ENDIF}
end;

function THashSHA512.GetHashSize: Integer;
begin
  {$IFDEF DELPHI}
  Result := FSHA512.GetHashSize;
  {$ELSE}
  Result := 64;
  {$ENDIF}
end;

procedure THashSHA512.Start;
begin
  {$IFDEF DELPHI}
  FSHA512 := System.Hash.THashSHA2.Create(SHA512);
  FSHA512.Reset;
  {$ELSE}
  SHA512Init(FSHA512Context);
  {$ENDIF}
end;

procedure THashSHA512.Update(const AData: Pointer; const ASize: Cardinal);
begin
  {$IFDEF DELPHI}
  FSHA512.Update(AData^, ASize);
  {$ELSE}
  SHA512Update(FSHA512Context, AData, ASize);
  {$ENDIF}
end;

{ THashBobJenkins }

class function THashBobJenkins.CreateHash: THashBase;
begin
  Result := THashBobJenkins.Create;
end;

function THashBobJenkins.Finish: TBytes;
begin
  Result := FBobJenkins.HashAsBytes;
end;

function THashBobJenkins.GetBlockSize: Integer;
begin
  Result := 64;
end;

function THashBobJenkins.GetHashSize: Integer;
begin
  Result := SizeOf(Cardinal);
end;

class function THashBobJenkins.GetHashValue(const AData; ALength,
  AInitialValue: Integer): Integer;
begin
  Result := TExternalHashBobJenkins.GetHashValue(AData, ALength, AInitialValue);
end;

class function THashBobJenkins.GetHashValue(const AData: string): Integer;
begin
  Result := TExternalHashBobJenkins.GetHashValue(AData);
end;

procedure THashBobJenkins.Start;
begin
  FBobJenkins.Reset;
end;

procedure THashBobJenkins.Update(const AData: Pointer; const ASize: Cardinal);
begin
  FBobJenkins.Update(AData^, ASize);
end;

{ THashFNV1a32 }

class function THashFNV1a32.CreateHash: THashBase;
begin
  Result := THashFNV1a32.Create;
end;

function THashFNV1a32.Finish: TBytes;
begin
  Result := FFNV1a32.HashAsBytes;
end;

function THashFNV1a32.GetBlockSize: Integer;
begin
  Result := 64;
end;

function THashFNV1a32.GetHashSize: Integer;
begin
  Result := SizeOf(Cardinal);
end;

class function THashFNV1a32.GetHashValue(const AData; ALength,
  AInitialValue: Cardinal): Integer;
begin
  Result := TExternalFNV1a32.GetHashValue(AData, ALength, AInitialValue);
end;

class function THashFNV1a32.GetHashValue(const AData: string): Integer;
begin
  Result := TExternalFNV1a32.GetHashValue(AData);
end;

procedure THashFNV1a32.Start;
begin
  FFNV1a32.Reset;
end;

procedure THashFNV1a32.Update(const AData: Pointer; const ASize: Cardinal);
begin
  FFNV1a32.Update(AData^, ASize);
end;

end.
