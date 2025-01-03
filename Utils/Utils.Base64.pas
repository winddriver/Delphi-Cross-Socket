unit Utils.Base64;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,

  {$IFDEF DELPHI}
  System.NetEncoding
  {$ELSE}
  DTF.RTL,
  base64
  {$ENDIF};

type
  TBase64Utils = class
  private
    {$IFDEF DELPHI}
    class var FBase64Encoding: TNetEncoding;
    class function GetBase64Encoding: TNetEncoding; static;
    class destructor Destroy;
    {$ENDIF}
  public
    class function Decode(const AInput, AOutput: TStream): Integer; overload; static;
    class function Decode(const ABase64Bytes: TBytes; out ABytes: TBytes): Integer; overload; static;

    class function Decode(const ABase64Str: string): TBytes; overload; static;
    class function Decode(const ABase64Bytes: TBytes): TBytes; overload; static;

    class function Encode(const AInput, AOutput: TStream): Integer; overload; static;
    class function Encode(const ABytes: TBytes; out ABase64Bytes: TBytes): Integer; overload; static;

    class function Encode(const ABytes: TBytes): string; overload; static;
    class function Encode(const AInput: Pointer; const ASize: Integer; out ABase64Bytes: TBytes): Integer; overload; static;
    class function Encode(const AInput: Pointer; const ASize: Integer): string; overload; static;
    class function Encode(const AStream: TStream): string; overload; static;
    class function Encode(const AStr: string): string; overload; static;
  end;

implementation

{ TBase64Utils }

class function TBase64Utils.Decode(const AInput, AOutput: TStream): Integer;
{$IFDEF DELPHI}
begin
  Result := GetBase64Encoding.Decode(AInput, AOutput);
end;
{$ELSE}
const
  BUF_SIZE = $2000;
var
  LBuf: PByte;
  LDec: TBase64DecodingStream;
  LSize: Integer;
begin
  Result := 0;
  if (AInput = nil) or (AOutput = nil) then Exit;

  GetMem(LBuf, BUF_SIZE);
  try
    LDec := TBase64DecodingStream.Create(AInput);
    try
      while True do
      begin
        LSize := LDec.Read(LBuf^, BUF_SIZE);
        if (LSize > 0) then
        begin
        	 AOutput.Write(LBuf^, LSize);
          Inc(Result, LSize);
        end;

        if (LSize < BUF_SIZE) then Break;
      end;
    finally
      FreeAndNil(LDec);
    end;
  finally
    FreeMem(LBuf);
  end;
end;
{$ENDIF}

class function TBase64Utils.Decode(const ABase64Bytes: TBytes;
  out ABytes: TBytes): Integer;
{$IFDEF DELPHI}
begin
  ABytes := GetBase64Encoding.Decode(ABase64Bytes);
  Result := Length(ABytes);
end;
{$ELSE}
var
  LDec: TBase64DecodingStream;
  LSrc: TBytesStream;
  LSize: Integer;
begin
  Result := 0;
  ABytes := nil;
  if (ABase64Bytes = nil) then Exit;

  LSrc := TBytesStream.Create(ABase64Bytes);
  LSrc.Position := 0;
  LDec := TBase64DecodingStream.Create(LSrc);
  try
    LSize := LDec.Size;
    if (LSize <= 0) then Exit;

    SetLength(ABytes, LSize);
    LDec.Read(ABytes[0], LSize);
    Result := LSize;
  finally
    FreeAndNil(LDec);
    FreeAndNil(LSrc);
  end;
end;
{$ENDIF}

class function TBase64Utils.Decode(const ABase64Str: string): TBytes;
begin
  Decode(TEncoding.UTF8.GetBytes(ABase64Str), Result);
end;

class function TBase64Utils.Decode(const ABase64Bytes: TBytes): TBytes;
begin
  Decode(ABase64Bytes, Result);
end;

class function TBase64Utils.Encode(const AInput, AOutput: TStream): Integer;
{$IFDEF DELPHI}
begin
  Result := GetBase64Encoding.Encode(AInput, AOutput);
end;
{$ELSE}
const
  BUF_SIZE = $2000;
var
  LBuf: PByte;
  LEnc: TBase64EncodingStream;
  LSize: Integer;
  LOrgPos: Int64;
begin
  Result := 0;
  if (AInput = nil) or (AOutput = nil) then Exit;

  GetMem(LBuf, BUF_SIZE);
  try
    LOrgPos := AOutput.Position;
    LEnc := TBase64EncodingStream.Create(AOutput);
    try
      while True do
      begin
        LSize := AInput.Read(LBuf^, BUF_SIZE);
        if (LSize > 0) then
          LEnc.Write(LBuf^, LSize);

        if (LSize < BUF_SIZE) then Break;
      end;
    finally
      FreeAndNil(LEnc);
    end;
    Result := AOutput.Position - LOrgPos;
  finally
    FreeMem(LBuf);
  end;
end;
{$ENDIF}

class function TBase64Utils.Encode(const ABytes: TBytes;
  out ABase64Bytes: TBytes): Integer;
{$IFDEF DELPHI}
begin
  ABase64Bytes := GetBase64Encoding.Encode(ABytes);
  Result := Length(ABase64Bytes);
end;
{$ELSE}
var
  LEnc: TBase64EncodingStream;
  LDst: TBytesStream;
  LSize: Integer;
begin
  Result := 0;
  ABase64Bytes := nil;
  if (ABytes = nil) then Exit;

  LDst := TBytesStream.Create(nil);
  try
    LEnc := TBase64EncodingStream.Create(LDst);
    try
      LEnc.Write(ABytes[0], Length(ABytes));
    finally
      FreeAndNil(LEnc);
    end;

    LSize := LDst.Size;
    if (LSize <= 0) then Exit;

    ABase64Bytes := LDst.Bytes;
    SetLength(ABase64Bytes, LSize);
    Result := LSize;
  finally
    FreeAndNil(LDst);
  end;
end;
{$ENDIF}

class function TBase64Utils.Encode(const ABytes: TBytes): string;
var
  LBase64Bytes: TBytes;
begin
  Encode(ABytes, LBase64Bytes);
  SetString(Result, MarshaledAString(LBase64Bytes), Length(LBase64Bytes));
end;

class function TBase64Utils.Encode(const AInput: Pointer; const ASize: Integer;
  out ABase64Bytes: TBytes): Integer;
begin
  Result := Encode(BytesOf(AInput, ASize), ABase64Bytes);
end;

class function TBase64Utils.Encode(const AInput: Pointer;
  const ASize: Integer): string;
begin
  Result := Encode(BytesOf(AInput, ASize));
end;

class function TBase64Utils.Encode(const AStream: TStream): string;
var
  LBytes: TBytes;
begin
  if (AStream = nil) or (AStream.Size <= 0) then Exit('');

  if (AStream is TBytesStream) then
  begin
    LBytes := TBytesStream(AStream).Bytes;
    SetLength(LBytes, AStream.Size);
  end else
  begin
    AStream.Position := 0;
    SetLength(LBytes, AStream.Size);
    AStream.Read(LBytes, AStream.Size);
  end;

  Result := Encode(LBytes);
end;

class function TBase64Utils.Encode(const AStr: string): string;
begin
  Result := Encode(TEncoding.UTF8.GetBytes(AStr));
end;

{$IFDEF DELPHI}
class destructor TBase64Utils.Destroy;
begin
  if (FBase64Encoding <> nil) then
    FreeAndNil(FBase64Encoding);
end;

class function TBase64Utils.GetBase64Encoding: TNetEncoding;
var
  LEncoding: TBase64Encoding;
begin
  if (FBase64Encoding = nil) then
  begin
    // Delphi 默认的 TNetEncoding.Base64 会每隔 76 个字符添加一次回车换行
    // 这里自己建一个 TBase64Encoding 对象, 不做换行处理
    LEncoding := TBase64Encoding.Create(0);
    if (AtomicCmpExchange(Pointer(FBase64Encoding), Pointer(LEncoding), nil) <> nil) then
      LEncoding.Free
    {$IFDEF AUTOREFCOUNT}
    else
      FBase64Encoding.__ObjAddRef
    {$ENDIF AUTOREFCOUNT};
  end;
  Result := FBase64Encoding;
end;
{$ENDIF}

end.
