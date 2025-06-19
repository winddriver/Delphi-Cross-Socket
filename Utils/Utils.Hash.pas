unit Utils.Hash;

{$I zLib.inc}

{$DEFINE __CN_MD5__}
{$DEFINE __CN_SHA1__}
{$DEFINE __CN_SHA2__}

{$IF defined(FPC) or (defined(DELPHI) and (CompilerVersion < 35.0))}
{$DEFINE _DTF_HASH__}
{$ENDIF}

interface

uses
  SysUtils,
  Classes,
  ZLib,

  {$IFDEF DELPHI}
  System.Hash,
  {$ENDIF}

  {$IFDEF __CN_MD5__}
  CnMD5,
  {$ENDIF}
  {$IFDEF __CN_SHA1__}
  CnSHA1,
  {$ENDIF}
  {$IFDEF __CN_SHA2__}
  CnSHA2,
  {$ENDIF}

  {$IFDEF _DTF_HASH__}
  DTF.Hash,
  {$ENDIF}

  Utils.Utils,
  CnPemUtils,
  CnSM3;

const
  HMAC_INNER_PAD: Byte = $36;
  HMAC_OUTER_PAD: Byte = $5C;
  BUFFER_SIZE = 32 * 1024;

type
  THashClass = class of THashBase;

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
    class function GetBlockSize: Integer; virtual; abstract;
    class function GetHashSize: Integer; virtual; abstract;
    class function GetHashStrLen: Integer; virtual;

    // 基础 hash 方法
    // 调用顺序: Start -> Update -> Finish
    procedure Start; virtual; abstract;
    procedure Update(const AData: Pointer; const ASize: NativeInt); overload; virtual; abstract;
    procedure Update(const AData: TBytes); overload;
    procedure Update(const AData: string); overload;
    procedure UpdateFromStream(const AStream: TStream; const APos: Int64 = 0;
      const ASize: Int64 = -1);
    function Finish: TBytes; virtual; abstract;

    function HashAsBytes: TBytes; inline;
    function HashAsString: string; inline;

    // 带密钥的 hash 方法
    // 调用顺序: HMACStart -> Update -> HMACFinish
    procedure HMACStart(const AKey: TBytes); virtual;
    function HMACFinish: TBytes; virtual;

    function HMACAsBytes: TBytes; inline;
    function HMACAsString: string; inline;
    {$endregion}

    class function GetHashBytes(const AData: Pointer; const ASize: NativeInt): TBytes; overload;
    class function GetHashBytes(const AData: TBytes): TBytes; overload; inline;
    class function GetHashBytes(const AData: string): TBytes; overload; inline;
    class function GetHashBytesFromStream(const AStream: TStream; const APos: Int64 = 0;
      const ASize: Int64 = -1): TBytes; overload;
    class function GetHashBytesFromFile(const AFileName: TFileName): TBytes;

    class function GetHashString(const AData: Pointer; const ASize: NativeInt): string; overload; inline;
    class function GetHashString(const AData: TBytes): string; overload; inline;
    class function GetHashString(const AData: string): string; overload; inline;
    class function GetHashStringFromStream(const AStream: TStream; const APos: Int64 = 0;
      const ASize: Int64 = -1): string; overload; inline;
    class function GetHashStringFromFile(const AFileName: TFileName): string; //inline;

    class function GetHMACBytes(const AData: Pointer; const ASize: NativeInt; const AKey: TBytes): TBytes; overload;
    class function GetHMACBytes(const AData, AKey: TBytes): TBytes; overload; inline;
    class function GetHMACBytes(const AData: string; const AKey: TBytes): TBytes; overload; inline;
    class function GetHMACBytesFromStream(const AStream: TStream; const AKey: TBytes;
      const APos: Int64 = 0; const ASize: Int64 = -1): TBytes; overload;
    class function GetHMACBytesFromFile(const AFileName: TFileName; const AKey: TBytes): TBytes; overload;

    class function GetHMACBytes(const AData: Pointer; const ASize: NativeInt; const AKey: string): TBytes; overload; inline;
    class function GetHMACBytes(const AData: TBytes; const AKey: string): TBytes; overload; inline;
    class function GetHMACBytes(const AData, AKey: string): TBytes; overload; inline;
    class function GetHMACBytesFromStream(const AStream: TStream; const AKey: string;
      const APos: Int64 = 0; const ASize: Int64 = -1): TBytes; overload; inline;
    class function GetHMACBytesFromFile(const AFileName: TFileName; const AKey: string): TBytes; overload; inline;

    class function GetHMACString(const AData: Pointer; const ASize: NativeInt; const AKey: TBytes): string; overload; inline;
    class function GetHMACString(const AData, AKey: TBytes): string; overload; inline;
    class function GetHMACString(const AData: string; const AKey: TBytes): string; overload; inline;
    class function GetHMACStringFromStream(const AStream: TStream; const AKey: TBytes;
      const APos: Int64 = 0; const ASize: Int64 = -1): string; overload; inline;
    class function GetHMACStringFromFile(const AFileName: TFileName; const AKey: TBytes): string; overload; inline;

    class function GetHMACString(const AData: Pointer; const ASize: NativeInt; const AKey: string): string; overload; inline;
    class function GetHMACString(const AData: TBytes; const AKey: string): string; overload; inline;
    class function GetHMACString(const AData, AKey: string): string; overload; inline;
    class function GetHMACStringFromStream(const AStream: TStream; const AKey: string;
      const APos: Int64 = 0; const ASize: Int64 = -1): string; overload; inline;
    class function GetHMACStringFromFile(const AFileName: TFileName; const AKey: string): string; overload; inline;
  end;

  // 国密 sm3 hash 算法
  THashSM3 = class(THashBase)
  private
    FContext: TCnSM3Context;
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashMD5 = class(THashBase)
  private
    {$IFDEF __CN_MD5__}
    FMD5Context: TCnMD5Context;
    {$ELSE}
    FMD5: System.Hash.THashMD5;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashSHA1 = class(THashBase)
  private
    {$IFDEF __CN_SHA1__}
    FSHA1Context: TCnSHA1Context;
    {$ELSE}
    FSHA1: System.Hash.THashSHA1;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashSHA256 = class(THashBase)
  private
    {$IFDEF __CN_SHA2__}
    FSHA256Context: TCnSHA256Context;
    {$ELSE}
    FSHA256: System.Hash.THashSHA2;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashSHA384 = class(THashBase)
  private
    {$IFDEF __CN_SHA2__}
    FSHA384Context: TCnSHA384Context;
    {$ELSE}
    FSHA384: System.Hash.THashSHA2;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashSHA512 = class(THashBase)
  private
    {$IFDEF __CN_SHA2__}
    FSHA512Context: TCnSHA512Context;
    {$ELSE}
    FSHA512: System.Hash.THashSHA2;
    {$ENDIF}
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashCrc32 = class(THashBase)
  private
    FCrc32: UInt32;
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;
  end;

  THashBobJenkins = class(THashBase)
  private type
    TExternalHashBobJenkins = {$IFDEF _DTF_HASH__}DTF.Hash.{$ELSE}System.Hash.{$ENDIF}THashBobJenkins;
  private
    FBobJenkins: TExternalHashBobJenkins;
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;

    class function GetHashValue(const AData: string): Integer; overload; static; inline;
    class function GetHashValue(const AData; ALength: Integer; AInitialValue: Integer = 0): Integer; overload; static; inline;
  end;

  THashFNV1a32 = class(THashBase)
  private type
    TExternalFNV1a32 ={$IFDEF _DTF_HASH__}DTF.Hash.{$ELSE}System.Hash.{$ENDIF}THashFNV1a32;
  private
    FFNV1a32: TExternalFNV1a32;
  public
    class function CreateHash: THashBase; override;

    class function GetBlockSize: Integer; override;
    class function GetHashSize: Integer; override;

    procedure Start; override;
    procedure Update(const AData: Pointer; const ASize: NativeInt); override;
    function Finish: TBytes; override;

    class function GetHashValue(const AData: string): Integer; overload; static; inline;
    class function GetHashValue(const AData; ALength: NativeInt; AInitialValue: Cardinal = TExternalFNV1a32.FNV_SEED): Integer; overload; static; inline;
  end;

implementation

{ THashBase }

class function THashBase.BytesToHex(const AData: TBytes): string;
begin
  if (AData <> nil) then
    Result := TUtils.BytesToHex(AData)
  else
    Result := '';
end;

class function THashBase.GetHashBytes(const AData: Pointer;
  const ASize: NativeInt): TBytes;
var
  LHash: THashBase;
begin
  LHash := CreateHash;
  try
    if (AData <> nil) and (ASize > 0) then
      LHash.Update(AData, ASize);
    Result := LHash.Finish;
  finally
    FreeAndNil(LHash);
  end;
end;

class function THashBase.GetHashBytes(const AData: TBytes): TBytes;
begin
  Result := GetHashBytes(PByte(AData), Length(AData));
end;

class function THashBase.GetHashBytes(const AData: string): TBytes;
begin
  Result := GetHashBytes(StrToBytes(AData));
end;

constructor THashBase.Create;
begin
  Start;
end;

class function THashBase.GetHashBytesFromStream(const AStream: TStream;
  const APos, ASize: Int64): TBytes;
var
  LHash: THashBase;
begin
  LHash := CreateHash;
  try
    LHash.UpdateFromStream(AStream, APos, ASize);
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
  LFile := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Result := GetHashBytesFromStream(LFile, 0, LFile.Size);
  finally
    LFile.Free;
  end;
end;

class function THashBase.GetHashString(const AData: Pointer;
  const ASize: NativeInt): string;
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

class function THashBase.GetHashStringFromStream(const AStream: TStream;
  const APos, ASize: Int64): string;
begin
  Result := BytesToHex(GetHashBytesFromStream(AStream, APos, ASize));
end;

class function THashBase.GetHashStrLen: Integer;
begin
  Result := GetHashSize * 2;
end;

class function THashBase.GetHashStringFromFile(
  const AFileName: TFileName): string;
begin
  Result := BytesToHex(GetHashBytesFromFile(AFileName));
end;

class function THashBase.GetHMACBytes(const AData: Pointer;
  const ASize: NativeInt; const AKey: TBytes): TBytes;
var
  LHash: THashBase;
begin
  LHash := CreateHash;
  try
    LHash.HMACStart(AKey);

    if (AData <> nil) and (ASize > 0) then
      LHash.Update(AData, ASize);

    Result := LHash.HMACFinish;
  finally
    FreeAndNil(LHash);
  end;
end;

class function THashBase.GetHMACBytes(const AData, AKey: TBytes): TBytes;
begin
  Result := GetHMACBytes(PByte(AData), Length(AData), AKey);
end;

class function THashBase.GetHMACBytes(const AData: string; const AKey: TBytes): TBytes;
begin
  Result := GetHMACBytes(StrToBytes(AData), AKey);
end;

class function THashBase.GetHMACBytesFromStream(const AStream: TStream; const AKey: TBytes;
  const APos, ASize: Int64): TBytes;
var
  LHash: THashBase;
begin
  LHash := CreateHash;
  try
    LHash.HMACStart(AKey);
    LHash.UpdateFromStream(AStream, APos, ASize);
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
  LFile := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Result := GetHMACBytesFromStream(LFile, AKey, 0, LFile.Size);
  finally
    LFile.Free;
  end;
end;

class function THashBase.GetHMACString(const AData, AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AData, AKey));
end;

class function THashBase.GetHMACString(const AData: Pointer;
  const ASize: NativeInt; const AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AData, ASize, AKey));
end;

class function THashBase.GetHMACString(const AData: string;
  const AKey: TBytes): string;
begin
  Result := BytesToHex(GetHMACBytes(AData, AKey));
end;

class function THashBase.GetHMACStringFromStream(const AStream: TStream;
  const AKey: TBytes; const APos, ASize: Int64): string;
begin
  Result := BytesToHex(GetHMACBytesFromStream(AStream, AKey, APos, ASize));
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

function THashBase.HMACAsBytes: TBytes;
begin
  if not FFinished then
  begin
    FHashBytes := HMACFinish;
    FFinished := True;
  end;

  Result := FHashBytes;
end;

function THashBase.HMACAsString: string;
begin
  Result := BytesToHex(HMACAsBytes);
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
  if (AStr <> '') then
    Result := TEncoding.UTF8.GetBytes(AStr)
  else
    Result := nil;
end;

procedure THashBase.Update(const AData: TBytes);
begin
  Update(PByte(AData), Length(AData));
end;

procedure THashBase.Update(const AData: string);
begin
  Update(StrToBytes(AData));
end;

procedure THashBase.UpdateFromStream(const AStream: TStream; const APos,
  ASize: Int64);
var
  LBuffer: TBytes;
  LBytesRead: NativeInt;
  LBufSize, LSize: Int64;
begin
  if (AStream = nil) then Exit;

  if (APos >= 0) then
    AStream.Position := APos;
  if (ASize > 0) then
    LSize := ASize
  else
    LSize := AStream.Size - AStream.Position;

  if (LSize <= 0) then Exit;

  if (LSize > BUFFER_SIZE) then
    LBufSize := BUFFER_SIZE
  else
    LBufSize := LSize;
  SetLength(LBuffer, LBufSize);

  while (LSize > 0) do
  begin
    LBytesRead := AStream.ReadData(LBuffer, LBufSize);
    if (LBytesRead <= 0) then Break;

    Update(PByte(LBuffer), LBytesRead);

    Dec(LSize, LBytesRead);

    if (LBytesRead < LBufSize) or (LSize <= 0) then Break;
  end;
end;

class function THashBase.GetHMACBytes(const AData: Pointer;
  const ASize: NativeInt; const AKey: string): TBytes;
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

class function THashBase.GetHMACBytesFromStream(const AStream: TStream;
  const AKey: string; const APos, ASize: Int64): TBytes;
begin
  Result := GetHMACBytesFromStream(AStream, StrToBytes(AKey), APos, ASize);
end;

class function THashBase.GetHMACBytesFromFile(const AFileName: TFileName;
  const AKey: string): TBytes;
begin
  Result := GetHMACBytesFromFile(AFileName, StrToBytes(AKey));
end;

class function THashBase.GetHMACString(const AData: Pointer;
  const ASize: NativeInt; const AKey: string): string;
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

class function THashBase.GetHMACStringFromStream(const AStream: TStream;
  const AKey: string; const APos, ASize: Int64): string;
begin
  Result := GetHMACStringFromStream(AStream, StrToBytes(AKey), APos, ASize);
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

class function THashSM3.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashSM3.GetHashSize: Integer;
begin
  Result := SizeOf(TCnSM3Digest);
end;

procedure THashSM3.Start;
begin
  SM3Init(FContext);
end;

procedure THashSM3.Update(const AData: Pointer; const ASize: NativeInt);
begin
  SM3Update(FContext, AData, ASize);
end;

{ THashMD5 }

class function THashMD5.CreateHash: THashBase;
begin
  Result := THashMD5.Create;
end;

function THashMD5.Finish: TBytes;
{$IFDEF __CN_MD5__}
var
  LDigest: TCnMD5Digest;
begin
  MD5Final(FMD5Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ELSE}
begin
  Result := FMD5.HashAsBytes;
end;
{$ENDIF}

class function THashMD5.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashMD5.GetHashSize: Integer;
begin
  Result := 16;
end;

procedure THashMD5.Start;
begin
  {$IFDEF __CN_MD5__}
  MD5Init(FMD5Context);
  {$ELSE}
  FMD5.Reset;
  {$ENDIF}
end;

procedure THashMD5.Update(const AData: Pointer; const ASize: NativeInt);
begin
  {$IFDEF __CN_MD5__}
  MD5Update(FMD5Context, AData, ASize);
  {$ELSE}
  FMD5.Update(AData^, ASize);
  {$ENDIF}
end;

{ THashSHA1 }

class function THashSHA1.CreateHash: THashBase;
begin
  Result := THashSHA1.Create;
end;

function THashSHA1.Finish: TBytes;
{$IFDEF __CN_SHA1__}
var
  LDigest: TCnSHA1Digest;
begin
  SHA1Final(FSHA1Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ELSE}
begin
  Result := FSHA1.HashAsBytes;
end;
{$ENDIF}

class function THashSHA1.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashSHA1.GetHashSize: Integer;
begin
  Result := 20;
end;

procedure THashSHA1.Start;
begin
  {$IFDEF __CN_SHA1__}
  SHA1Init(FSHA1Context);
  {$ELSE}
  FSHA1.Reset;
  {$ENDIF}
end;

procedure THashSHA1.Update(const AData: Pointer; const ASize: NativeInt);
begin
  {$IFDEF __CN_SHA1__}
  SHA1Update(FSHA1Context, AData, ASize);
  {$ELSE}
  FSHA1.Update(AData^, ASize);
  {$ENDIF}
end;

{ THashSHA256 }

class function THashSHA256.CreateHash: THashBase;
begin
  Result := THashSHA256.Create;
end;

function THashSHA256.Finish: TBytes;
{$IFDEF __CN_SHA2__}
var
  LDigest: TCnSHA256Digest;
begin
  SHA256Final(FSHA256Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ELSE}
begin
  Result := FSHA256.HashAsBytes;
end;
{$ENDIF}

class function THashSHA256.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashSHA256.GetHashSize: Integer;
begin
  Result := 32;
end;

procedure THashSHA256.Start;
begin
  {$IFDEF __CN_SHA2__}
  SHA256Init(FSHA256Context);
  {$ELSE}
  FSHA256 := System.Hash.THashSHA2.Create(SHA256);
  FSHA256.Reset;
  {$ENDIF}
end;

procedure THashSHA256.Update(const AData: Pointer; const ASize: NativeInt);
begin
  {$IFDEF __CN_SHA2__}
  SHA256Update(FSHA256Context, AData, ASize);
  {$ELSE}
  FSHA256.Update(AData^, ASize);
  {$ENDIF}
end;

{ THashSHA384 }

class function THashSHA384.CreateHash: THashBase;
begin
  Result := THashSHA384.Create;
end;

function THashSHA384.Finish: TBytes;
{$IFDEF __CN_SHA2__}
var
  LDigest: TCnSHA384Digest;
begin
  SHA384Final(FSHA384Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ELSE}
begin
  Result := FSHA384.HashAsBytes;
end;
{$ENDIF}

class function THashSHA384.GetBlockSize: Integer;
begin
  Result := 128;
end;

class function THashSHA384.GetHashSize: Integer;
begin
  Result := 48;
end;

procedure THashSHA384.Start;
begin
  {$IFDEF __CN_SHA2__}
  SHA384Init(FSHA384Context);
  {$ELSE}
  FSHA384 := System.Hash.THashSHA2.Create(SHA384);
  FSHA384.Reset;
  {$ENDIF}
end;

procedure THashSHA384.Update(const AData: Pointer; const ASize: NativeInt);
begin
  {$IFDEF __CN_SHA2__}
  SHA384Update(FSHA384Context, AData, ASize);
  {$ELSE}
  FSHA384.Update(AData^, ASize);
  {$ENDIF}
end;

{ THashSHA512 }

class function THashSHA512.CreateHash: THashBase;
begin
  Result := THashSHA512.Create;
end;

function THashSHA512.Finish: TBytes;
{$IFDEF __CN_SHA2__}
var
  LDigest: TCnSHA512Digest;
begin
  SHA512Final(FSHA512Context, LDigest);
  SetLength(Result, SizeOf(LDigest));
  Move(LDigest, Result[0], SizeOf(LDigest));
end;
{$ELSE}
begin
  Result := FSHA512.HashAsBytes;
end;
{$ENDIF}

class function THashSHA512.GetBlockSize: Integer;
begin
  Result := 128;
end;

class function THashSHA512.GetHashSize: Integer;
begin
  Result := 64;
end;

procedure THashSHA512.Start;
begin
  {$IFDEF __CN_SHA2__}
  SHA512Init(FSHA512Context);
  {$ELSE}
  FSHA512 := System.Hash.THashSHA2.Create(SHA512);
  FSHA512.Reset;
  {$ENDIF}
end;

procedure THashSHA512.Update(const AData: Pointer; const ASize: NativeInt);
begin
  {$IFDEF __CN_SHA2__}
  SHA512Update(FSHA512Context, AData, ASize);
  {$ELSE}
  FSHA512.Update(AData^, ASize);
  {$ENDIF}
end;

{ THashCrc32 }

class function THashCrc32.CreateHash: THashBase;
begin
  Result := THashCrc32.Create;
end;

function THashCrc32.Finish: TBytes;
begin
  SetLength(Result, GetHashSize);
  Move(FCrc32, Result[0], GetHashSize);
end;

class function THashCrc32.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashCrc32.GetHashSize: Integer;
begin
  Result := SizeOf(UInt32);
end;

procedure THashCrc32.Start;
begin
  FCrc32 := 0;
end;

procedure THashCrc32.Update(const AData: Pointer; const ASize: NativeInt);
begin
  FCrc32 := ZLib.crc32(FCrc32, AData, ASize);
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

class function THashBobJenkins.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashBobJenkins.GetHashSize: Integer;
begin
  Result := SizeOf(NativeInt);
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

procedure THashBobJenkins.Update(const AData: Pointer; const ASize: NativeInt);
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

class function THashFNV1a32.GetBlockSize: Integer;
begin
  Result := 64;
end;

class function THashFNV1a32.GetHashSize: Integer;
begin
  Result := SizeOf(NativeInt);
end;

class function THashFNV1a32.GetHashValue(const AData; ALength: NativeInt;
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

procedure THashFNV1a32.Update(const AData: Pointer; const ASize: NativeInt);
begin
  FFNV1a32.Update(AData^, ASize);
end;

end.

