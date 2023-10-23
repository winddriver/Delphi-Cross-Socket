unit Utils.Base64;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,

  {$IFDEF DELPHI}
  System.NetEncoding
  {$ELSE}
  base64
  {$ENDIF};

type
  TBase64Utils = class
  public
    class function Decode(const ABase64Bytes: TBytes; out ABytes: TBytes): Boolean; overload; static;
    class function Decode(const ABase64Str: string): TBytes; overload; static;
    class function Decode(const ABase64Bytes: TBytes): TBytes; overload; static;

    class function Encode(const ABytes: TBytes; out ABase64Bytes: TBytes): Boolean; overload; static;
    class function Encode(const ABytes: TBytes): string; overload; static;
    class function Encode(const AStream: TStream): string; overload; static;
    class function Encode(const AStr: string): string; overload; static;
  end;

implementation

{ TBase64Utils }

class function TBase64Utils.Decode(const ABase64Bytes: TBytes;
  out ABytes: TBytes): Boolean;
{$IFDEF DELPHI}
begin
  ABytes := TNetEncoding.Base64.Decode(ABase64Bytes);
  Result := True;
end;
{$ELSE}
var
  LDec: TBase64DecodingStream;
  LSrc, LDst: TBytesStream;
  LSize: Integer;
begin
  Result := True;
  ABytes := nil;
  if (ABase64Bytes = nil) then Exit;

  LSrc := TBytesStream.Create(ABase64Bytes);
  LSrc.Position := 0;
  LDec := TBase64DecodingStream.Create(LSrc);
  try
    LSize := LDec.Size;
    if (LSize <= 0) then Exit;

    LDst := TBytesStream.Create(nil);
    try
      LDst.CopyFrom(LDec, LSize);

      ABytes := LDst.Bytes;
      SetLength(ABytes, LSize);
    finally
      FreeAndNil(LDst);
    end;
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

class function TBase64Utils.Encode(const ABytes: TBytes;
  out ABase64Bytes: TBytes): Boolean;
{$IFDEF DELPHI}
begin
  ABase64Bytes := TNetEncoding.Base64.Encode(ABytes);
  Result := True;
end;
{$ELSE}
var
  LEnc: TBase64EncodingStream;
  LSrc, LDst: TBytesStream;
begin
  Result := True;
  ABase64Bytes := nil;
  if (ABytes = nil) then Exit;

  LSrc := TBytesStream.Create(ABytes);
  LDst := TBytesStream.Create(nil);
  LEnc := TBase64EncodingStream.Create(LDst);
  try
    LEnc.CopyFrom(LSrc, LSrc.Size);
    LEnc.Flush;

    ABase64Bytes := LDst.Bytes;
    SetLength(ABase64Bytes, LDst.Size);
  finally
    FreeAndNil(LEnc);
    FreeAndNil(LSrc);
    FreeAndNil(LDst);
  end;
end;
{$ENDIF}

class function TBase64Utils.Encode(const ABytes: TBytes): string;
var
  LBase64Bytes: TBytes;
begin
  Encode(ABytes, LBase64Bytes);
  Result := TEncoding.UTF8.GetString(LBase64Bytes);
end;

class function TBase64Utils.Encode(const AStream: TStream): string;
var
  LBytes: TBytes;
begin
  AStream.Position := 0;
  SetLength(LBytes, AStream.Size);
  AStream.Read(LBytes, AStream.Size);

  Result := Encode(LBytes);
end;

class function TBase64Utils.Encode(const AStr: string): string;
begin
  Result := Encode(TEncoding.UTF8.GetBytes(AStr));
end;

end.
