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
    class function Decode(const ABase64Str: string): TBytes; static;

    class function Encode(const ABytes: TBytes): string; overload; static;
    class function Encode(const AStream: TStream): string; overload; static;
    class function Encode(const AStr: string): string; overload; static;
  end;

implementation

{ TBase64Utils }

class function TBase64Utils.Decode(const ABase64Str: string): TBytes;
{$IFDEF DELPHI}
begin
  Result := TNetEncoding.Base64.DecodeStringToBytes(ABase64Str);
end;
{$ELSE}
var
  LDec: TBase64DecodingStream;
  LSrc, LDst: TBytesStream;
  LSize: Integer;
begin
  Result := nil;
  if (ABase64Str = '') then Exit;

  LSrc := TBytesStream.Create(TEncoding.UTF8.GetBytes(ABase64Str));
  LSrc.Position := 0;
  LDec := TBase64DecodingStream.Create(LSrc);
  try
    LSize := LDec.Size;
    if (LSize <= 0) then Exit;

    LDst := TBytesStream.Create(nil);
    try
      LDst.CopyFrom(LDec, LSize);

      Result := LDst.Bytes;
      SetLength(Result, LSize);
    finally
      FreeAndNil(LDst);
    end;
  finally
    FreeAndNil(LDec);
    FreeAndNil(LSrc);
  end;
end;
{$ENDIF}

class function TBase64Utils.Encode(const ABytes: TBytes): string;
{$IFDEF DELPHI}
begin
  Result := TNetEncoding.Base64.EncodeBytesToString(ABytes);
end;
{$ELSE}
var
  LEnc: TBase64EncodingStream;
  LSrc, LDst: TBytesStream;
begin
  LSrc := TBytesStream.Create(ABytes);
  LDst := TBytesStream.Create(nil);
  LEnc := TBase64EncodingStream.Create(LDst);
  try
    LEnc.CopyFrom(LSrc, LSrc.Size);
    LEnc.Flush;

    SetString(Result, MarshaledAString(LDst.Memory), LDst.Size);
  finally
    FreeAndNil(LEnc);
    FreeAndNil(LSrc);
    FreeAndNil(LDst);
  end;
end;
{$ENDIF}

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
