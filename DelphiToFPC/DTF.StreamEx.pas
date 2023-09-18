unit DTF.StreamEx;

{$I zLib.inc}

interface

uses
  Sysutils,
  Classes,

  DTF.Consts,
  DTF.Character;

type
  TTextReader = class
  public
    procedure Close; virtual; abstract;
    function Peek: Integer; virtual; abstract;
    function Read: Integer; overload; virtual; abstract;
    function Read(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; overload; virtual; abstract;
    function ReadBlock(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; virtual; abstract;
    function ReadLine: string; virtual; abstract;
    function ReadToEnd: string; virtual; abstract;
    procedure Rewind; virtual; abstract;
  end;

  TTextWriter = class
  public
    procedure Close; virtual; abstract;
    procedure Flush; virtual; abstract;
    procedure Write(Value: Boolean); overload; virtual; abstract;
    procedure Write(Value: Char); overload; virtual; abstract;
    procedure Write(Value: Char; Count: Integer); overload; virtual;
    procedure Write(const Value: TUnicodeCharArray); overload; virtual; abstract;
    procedure Write(Value: Double); overload; virtual; abstract;
    procedure Write(Value: Integer); overload; virtual; abstract;
    procedure Write(Value: Int64); overload; virtual; abstract;
    procedure Write(Value: TObject); overload; virtual; abstract;
    procedure Write(Value: Single); overload; virtual; abstract;
    procedure Write(const Value: string); overload; virtual; abstract;
    procedure Write(Value: Cardinal); overload; virtual; abstract;
    procedure Write(Value: UInt64); overload; virtual; abstract;
    procedure Write(const Format: string; Args: array of const); overload; virtual; abstract;
    procedure Write(const Value: TUnicodeCharArray; Index, Count: Integer); overload; virtual; abstract;
    procedure WriteLine; overload; virtual; abstract;
    procedure WriteLine(Value: Boolean); overload; virtual; abstract;
    procedure WriteLine(Value: Char); overload; virtual; abstract;
    procedure WriteLine(const Value: TUnicodeCharArray); overload; virtual; abstract;
    procedure WriteLine(Value: Double); overload; virtual; abstract;
    procedure WriteLine(Value: Integer); overload; virtual; abstract;
    procedure WriteLine(Value: Int64); overload; virtual; abstract;
    procedure WriteLine(Value: TObject); overload; virtual; abstract;
    procedure WriteLine(Value: Single); overload; virtual; abstract;
    procedure WriteLine(const Value: string); overload; virtual; abstract;
    procedure WriteLine(Value: Cardinal); overload; virtual; abstract;
    procedure WriteLine(Value: UInt64); overload; virtual; abstract;
    procedure WriteLine(const Format: string; Args: array of const); overload; virtual; abstract;
    procedure WriteLine(const Value: TUnicodeCharArray; Index, Count: Integer); overload; virtual; abstract;
  end;

  TBinaryReader = class
  strict private
    FStream: TStream;
    FEncoding: TEncoding;
    FOwnsStream: Boolean;
    FTwoBytesPerChar: Boolean;
    FCharBytes: TBytes;
    FOneChar: TUnicodeCharArray;
    FMaxCharsSize: Integer;
    function InternalReadChar: Integer;
    function InternalReadChars(const Chars: TUnicodeCharArray; Index, Count: Integer): Integer;
  protected
    function GetBaseStream: TStream; virtual;
    function Read7BitEncodedInt: Integer; virtual;
  public
    constructor Create(Stream: TStream; AEncoding: TEncoding = nil; AOwnsStream: Boolean = False); overload;
    constructor Create(const Filename: string; Encoding: TEncoding = nil); overload;
    destructor Destroy; override;
    procedure Close; virtual;
    function PeekChar: Integer; virtual;
    function Read: Integer; overload; virtual;
    function Read(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; overload; virtual;
    function Read(const Buffer: TBytes; Index, Count: Integer): Integer; overload; virtual;
    function ReadBoolean: Boolean; virtual;
    function ReadByte: Byte; virtual;
    function ReadBytes(Count: Integer): TBytes; virtual;
    function ReadChar: Char; virtual;
    function ReadChars(Count: Integer): TUnicodeCharArray; virtual;
    function ReadDouble: Double; virtual;
    function ReadSByte: ShortInt; inline;
    function ReadShortInt: ShortInt; virtual;
    function ReadSmallInt: SmallInt; virtual;
    function ReadInt16: SmallInt; inline;
    function ReadInteger: Integer; virtual;
    function ReadInt32: Integer; inline;
    function ReadInt64: Int64; virtual;
    function ReadSingle: Single; virtual;
    function ReadString: string; virtual;
    function ReadWord: Word; virtual;
    function ReadUInt16: Word; inline;
    function ReadCardinal: Cardinal; virtual;
    function ReadUInt32: Cardinal; inline;
    function ReadUInt64: UInt64; virtual;
    property BaseStream: TStream read GetBaseStream;
  end;

  TBinaryWriter = class
  strict private
    FStream: TStream;
    FOwnsStream: Boolean;
    FEncoding: TEncoding;
    class var FNull: TBinaryWriter;
    class destructor Destroy;
    class function GetNull: TBinaryWriter; static;
  protected
    function GetBaseStream: TStream; virtual;
    procedure Write7BitEncodedInt(Value: Integer); virtual;
    constructor Create; overload;
  public
    constructor Create(Stream: TStream); overload;
    constructor Create(Stream: TStream; Encoding: TEncoding); overload;
    constructor Create(Stream: TStream; Encoding: TEncoding; AOwnsStream: Boolean); overload;
    constructor Create(const Filename: string; Append: Boolean = False); overload;
    constructor Create(const Filename: string; Append: Boolean; Encoding: TEncoding); overload;
    destructor Destroy; override;
    procedure Close; virtual;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; virtual;
    procedure Write(Value: Byte); overload; virtual;
    procedure Write(Value: Boolean); overload; virtual;
    procedure Write(Value: Char); overload; virtual;
    procedure Write(const Value: TUnicodeCharArray); overload; virtual;
    procedure Write(const Value: TBytes); overload; virtual;
    procedure Write(Value: Double); overload; virtual;
    procedure Write(Value: Integer); overload; virtual;
    procedure Write(Value: SmallInt); overload; virtual;
    procedure Write(Value: ShortInt); overload; virtual;
    procedure Write(Value: Word); overload; virtual;
    procedure Write(Value: Cardinal); overload; virtual;
    procedure Write(Value: Int64); overload; virtual;
    procedure Write(Value: Single); overload; virtual;
    procedure Write(const Value: string); overload; virtual;
    procedure Write(Value: UInt64); overload; virtual;
    procedure Write(const Value: TUnicodeCharArray; Index, Count: Integer); overload; virtual;
    procedure Write(const Value: TBytes; Index, Count: Integer); overload; virtual;
    property BaseStream: TStream read GetBaseStream;
    class property Null: TBinaryWriter read GetNull;
  end;

  TStringReader = class(TTextReader)
  private
    FData: string;   //String Data being read
    FIndex: Integer; //Next character index to be read
  public
    constructor Create(S: string);
    procedure Close; override;
    function Peek: Integer; override;
    function Read: Integer; overload; override;
    function Read(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; overload; override;
    function ReadBlock(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; override;
    function ReadLine: string; override;
    function ReadToEnd: string; override;
    procedure Rewind; override;
  end;

  TStringWriter = class(TTextWriter)
  private
    FBuilder: TUnicodeStringBuilder;
    FOwnsBuilder: Boolean;
  public
    constructor Create; overload;
    constructor Create(Builder: TUnicodeStringBuilder); overload;
    destructor Destroy; override;
    procedure Close; override;
    procedure Flush; override;
    procedure Write(Value: Boolean); override;
    procedure Write(Value: Char); override;
    procedure Write(Value: Char; Count: Integer); override;
    procedure Write(const Value: TUnicodeCharArray); override;
    procedure Write(Value: Double); override;
    procedure Write(Value: Integer); override;
    procedure Write(Value: Int64); override;
    procedure Write(Value: TObject); override;
    procedure Write(Value: Single); override;
    procedure Write(const Value: string); override;
    procedure Write(Value: Cardinal); override;
    procedure Write(Value: UInt64); override;
    procedure Write(const Format: string; Args: array of const); override;
    procedure Write(const Value: TUnicodeCharArray; Index, Count: Integer); override;
    procedure WriteLine; override;
    procedure WriteLine(Value: Boolean); override;
    procedure WriteLine(Value: Char); override;
    procedure WriteLine(const Value: TUnicodeCharArray); override;
    procedure WriteLine(Value: Double); override;
    procedure WriteLine(Value: Integer); override;
    procedure WriteLine(Value: Int64); override;
    procedure WriteLine(Value: TObject); override;
    procedure WriteLine(Value: Single); override;
    procedure WriteLine(const Value: string); override;
    procedure WriteLine(Value: Cardinal); override;
    procedure WriteLine(Value: UInt64); override;
    procedure WriteLine(const Format: string; Args: array of const); override;
    procedure WriteLine(const Value: TUnicodeCharArray; Index, Count: Integer); override;
    function ToString: string;
  end;

  TStreamWriter = class(TTextWriter)
  private
    FStream: TStream;
    FEncoding: TEncoding;
    FNewLine: string;
    FAutoFlush: Boolean;
    FOwnsStream: Boolean;
  protected
    FBufferIndex: Integer;
    FBuffer: TBytes;
    procedure WriteBytes(Bytes: TBytes);
  public
    constructor Create(Stream: TStream); overload;
    constructor Create(Stream: TStream; Encoding: TEncoding; BufferSize: Integer = 4096); overload;
    constructor Create(const Filename: string; Append: Boolean = False); overload;
    constructor Create(const Filename: string; Append: Boolean; Encoding: TEncoding; BufferSize: Integer = 4096); overload;
    destructor Destroy; override;
    procedure Close; override;
    procedure Flush; override;
    procedure OwnStream; inline;
    procedure Write(Value: Boolean); override;
    procedure Write(Value: Char); override;
    procedure Write(const Value: TUnicodeCharArray); override;
    procedure Write(Value: Double); override;
    procedure Write(Value: Integer); override;
    procedure Write(Value: Int64); override;
    procedure Write(Value: TObject); override;
    procedure Write(Value: Single); override;
    procedure Write(const Value: string); override;
    procedure Write(Value: Cardinal); override;
    procedure Write(Value: UInt64); override;
    procedure Write(const Format: string; Args: array of const); override;
    procedure Write(const Value: TUnicodeCharArray; Index, Count: Integer); override;
    procedure WriteLine; override;
    procedure WriteLine(Value: Boolean); override;
    procedure WriteLine(Value: Char); override;
    procedure WriteLine(const Value: TUnicodeCharArray); override;
    procedure WriteLine(Value: Double); override;
    procedure WriteLine(Value: Integer); override;
    procedure WriteLine(Value: Int64); override;
    procedure WriteLine(Value: TObject); override;
    procedure WriteLine(Value: Single); override;
    procedure WriteLine(const Value: string); override;
    procedure WriteLine(Value: Cardinal); override;
    procedure WriteLine(Value: UInt64); override;
    procedure WriteLine(const Format: string; Args: array of const); override;
    procedure WriteLine(const Value: TUnicodeCharArray; Index, Count: Integer); override;
    property AutoFlush: Boolean read FAutoFlush write FAutoFlush;
    property NewLine: string read FNewLine write FNewLine;
    property Encoding: TEncoding read FEncoding;
    property BaseStream: TStream read FStream;
  end;

  TStreamReader = class(TTextReader)
  private type
    TBufferedData = class(TUnicodeStringBuilder)
    private
      FStart: Integer;
      FBufferSize: Integer;
      function GetChars(AIndex: Integer): Char; inline;
    public
      constructor Create(ABufferSize: Integer);
      procedure Clear; inline;
      function Length: Integer; inline;
      function PeekChar: Char; inline;
      function MoveChar: Char; inline;
      procedure MoveArray(DestinationIndex, Count: Integer; var Destination: TUnicodeCharArray);
      procedure MoveString(Count, NewPos: Integer; var Destination: string);
      procedure TrimBuffer;
      property Chars[AIndex: Integer]: Char read GetChars;
    end;

  private
    FBufferSize: Integer;
    FDetectBOM: Boolean;
    FEncoding: TEncoding;
    FOwnsStream: Boolean;
    FSkipPreamble: Boolean;
    FStream: TStream;
    function DetectBOM(var Encoding: TEncoding; Buffer: TBytes): Integer;
    function GetEndOfStream: Boolean;
    function SkipPreamble(Encoding: TEncoding; Buffer: TBytes): Integer;
  protected
    FBufferedData: TBufferedData;
    FNoDataInStream: Boolean;
    procedure FillBuffer(var Encoding: TEncoding);
  public
    constructor Create(Stream: TStream); overload;
    constructor Create(Stream: TStream; DetectBOM: Boolean); overload;
    constructor Create(Stream: TStream; Encoding: TEncoding;
      DetectBOM: Boolean = False; BufferSize: Integer = 4096); overload;
    constructor Create(const Filename: string); overload;
    constructor Create(const Filename: string; DetectBOM: Boolean); overload;
    constructor Create(const Filename: string; Encoding: TEncoding;
      DetectBOM: Boolean = False; BufferSize: Integer = 4096); overload;
    destructor Destroy; override;
    procedure Close; override;
    procedure DiscardBufferedData;
    procedure OwnStream; inline;
    function Peek: Integer; override;
    function Read: Integer; overload; override;
    function Read(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; overload; override;
    function ReadBlock(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer; override;
    function ReadLine: string; override;
    function ReadToEnd: string; override;
    procedure Rewind; override;
    property BaseStream: TStream read FStream;
    property CurrentEncoding: TEncoding read FEncoding write FEncoding;
    property EndOfStream: Boolean read GetEndOfStream;

    property BufferedData: TBufferedData read FBufferedData;
    property NoDataInStream: Boolean read FNoDataInStream;
  end;

implementation

{ TTextWriter }

procedure TTextWriter.Write(Value: Char; Count: Integer);
begin
  Write(string.Create(Value, Count));
end;

{ TBinaryReader }

procedure TBinaryReader.Close;
begin
  if FOwnsStream then
    FreeAndNil(FStream);
end;

constructor TBinaryReader.Create(Stream: TStream; AEncoding: TEncoding; AOwnsStream: Boolean);
begin
  inherited Create;
  if Stream = nil then
    raise EArgumentNilException.CreateRes(@SArgumentNil);
  FStream := Stream;
  if AEncoding = nil then
    FEncoding := TEncoding.UTF8
  else
    FEncoding := AEncoding;
  FOwnsStream := AOwnsStream;
  FTwoBytesPerChar := FEncoding is TUnicodeEncoding;
  FMaxCharsSize := FEncoding.GetMaxByteCount($80);
end;

constructor TBinaryReader.Create(const Filename: string; Encoding: TEncoding);
begin
  Create(TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite), Encoding, True);
end;

destructor TBinaryReader.Destroy;
begin
  if not TEncoding.IsStandardEncoding(FEncoding) then
    FEncoding.Free;
  if FOwnsStream then
    FStream.Free;
  inherited;
end;

function TBinaryReader.GetBaseStream: TStream;
begin
  Result := FStream;
end;

function TBinaryReader.InternalReadChar: Integer;
var
  CharCount: Integer;
  ByteCount: Integer;
  Index: Integer;
  Position: Int64;
  CharByte: Byte;
begin
  if FCharBytes = nil then
    SetLength(FCharBytes, $80);
  if FOneChar = nil then
    SetLength(FOneChar, 1);
  Index := 0;
  Position := FStream.Position;
  try
    CharCount := 0;
    if FTwoBytesPerChar then
      ByteCount := 2
    else
      ByteCount := 1;
    while (CharCount = 0) and (Index < Length(FCharBytes)) do
    begin
      if FStream.Read(CharByte, SizeOf(CharByte)) = 0 then
        ByteCount := 0;
      FCharBytes[Index] := CharByte;
      Inc(Index);
      if ByteCount = 2 then
      begin
        if FStream.Read(CharByte, SizeOf(CharByte)) = 0 then
          ByteCount := 1;
        FCharBytes[Index] := CharByte;
        Inc(Index);
      end;
      if ByteCount = 0 then
        Exit(-1);
      CharCount := FEncoding.GetChars(FCharBytes, 0, Index, FOneChar, 0);
    end;
  except
    FStream.Position := Position;
    raise;
  end;
  if CharCount > 0 then
    Result := Integer(FOneChar[0])
  else
    Result := -1;
end;

function TBinaryReader.InternalReadChars(const Chars: TUnicodeCharArray; Index, Count: Integer): Integer;
var
  BytesToRead, RemainingChars, CharCount: Integer;
begin
  if FCharBytes = nil then
    SetLength(FCharBytes, $80);
  RemainingChars := Count;
  while RemainingChars > 0 do
  begin
    BytesToRead := RemainingChars;
    if FTwoBytesPerChar then
      BytesToRead := BytesToRead shl 1;
    if BytesToRead > Length(FCharBytes) then
      BytesToRead := Length(FCharBytes);
    BytesToRead := FStream.Read(FCharBytes[0], BytesToRead);
    if BytesToRead = 0 then
      Break;
    CharCount := FEncoding.GetChars(FCharBytes, 0, BytesToRead, Chars, Index);
    Dec(RemainingChars, CharCount);
    Inc(Index, CharCount);
  end;
  Result := Count - RemainingChars;
end;

function TBinaryReader.PeekChar: Integer;
var
  Position: Int64;
begin
  Position := FStream.Position;
  try
    Result := InternalReadChar;
  finally
    FStream.Position := Position;
  end;
end;

function TBinaryReader.Read(var Buffer: TUnicodeCharArray; Index, Count: Integer): Integer;
begin
  if Index < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Index']); // do not localize
  if Count < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Count']); // do not localize
  if Length(Buffer) - Index < Count  then
    raise EArgumentOutOfRangeException.CreateRes(@sArgumentOutOfRange_OffLenInvalid);
  Result := InternalReadChars(Buffer, Index, Count);
end;

function TBinaryReader.Read: Integer;
begin
  Result := InternalReadChar;
end;

function TBinaryReader.Read(const Buffer: TBytes; Index, Count: Integer): Integer;
begin
  if Index < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Index']); // do not localize
  if Count < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Count']); // do not localize
  if Length(Buffer) - Index < Count  then
    raise EArgumentOutOfRangeException.CreateRes(@sArgumentOutOfRange_OffLenInvalid);
  Result := FStream.Read(Buffer[Index], Count);
end;

function TBinaryReader.Read7BitEncodedInt: Integer;
var
  Shift: Integer;
  Value: Integer;
begin
  Shift := 0;
  Result := 0;
  repeat
    if Shift = 35 then
      raise EStreamError.CreateRes(@SInvalid7BitEncodedInteger);
    Value := ReadByte;
    Result := Result or ((Value and $7F) shl Shift);
    Inc(Shift, 7);
  until Value and $80 = 0;
end;

function TBinaryReader.ReadBoolean: Boolean;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadByte: Byte;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadBytes(Count: Integer): TBytes;
var
  BytesRead: Integer;
begin
  if Count < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Count']); // do not localize
  SetLength(Result, Count);
  BytesRead := FStream.Read(Result[0], Count);
  if BytesRead <> Count then
    SetLength(Result, BytesRead);
end;

function TBinaryReader.ReadCardinal: Cardinal;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadChar: Char;
var
  Value: Integer;
begin
  Value := Read;
  if Value = -1 then
    raise EStreamError.CreateRes(@SReadPastEndOfStream);
  Result := Char(Value);
end;

function TBinaryReader.ReadChars(Count: Integer): TUnicodeCharArray;
var
  CharsRead: Integer;
begin
  if Count < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Count']); // do not localize
  SetLength(Result, Count);
  CharsRead := InternalReadChars(Result, 0, Count);
  if CharsRead <> Count then
    SetLength(Result, CharsRead);
end;

function TBinaryReader.ReadDouble: Double;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadInt64: Int64;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadInteger: Integer;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadInt32: Integer;
begin
  Result := ReadInteger;
end;

function TBinaryReader.ReadShortInt: ShortInt;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadSByte: ShortInt;
begin
  Result := ReadShortInt;
end;

function TBinaryReader.ReadSmallInt: SmallInt;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadInt16: SmallInt;
begin
  Result := ReadSmallInt;
end;

function TBinaryReader.ReadSingle: Single;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadString: string;
var
  Bytes: TBytes;
  ByteCount, BytesRead: Integer;
begin
  ByteCount := Read7BitEncodedInt;
  if ByteCount < 0 then
    raise EStreamError.CreateRes(@SInvalidStringLength);
  if ByteCount > 0 then
  begin
    SetLength(Bytes, ByteCount);
    BytesRead := FStream.Read(Bytes[0], ByteCount);
    if BytesRead <> ByteCount then
      raise EStreamError.CreateRes(@SReadPastEndOfStream);
    Result := FEncoding.GetString(Bytes);
  end else
    Result := '';
end;

function TBinaryReader.ReadUInt32: Cardinal;
begin
  Result := ReadCardinal;
end;

function TBinaryReader.ReadUInt64: UInt64;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadWord: Word;
begin
  FStream.ReadBuffer(Result, SizeOf(Result));
end;

function TBinaryReader.ReadUInt16: Word;
begin
  Result := ReadWord;
end;

{ TNullStream }

type
  TNullStream = class(TStream)
  public
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; overload; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; overload; override;
  end;

function TNullStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TNullStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TNullStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  Result := 0;
end;

function TNullStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := 0;
end;

{ TBinaryWriter }

constructor TBinaryWriter.Create(Stream: TStream; Encoding: TEncoding);
begin
  Create(Stream, Encoding, False);
end;

constructor TBinaryWriter.Create(Stream: TStream);
begin
  Create(Stream, nil, False);
end;

constructor TBinaryWriter.Create(Stream: TStream; Encoding: TEncoding; AOwnsStream: Boolean);
begin
  inherited Create;
  if Stream = nil then
    raise EArgumentNilException.CreateRes(@SArgumentNil);
  FStream := Stream;
  if Encoding = nil then
    FEncoding := TEncoding.UTF8
  else
    FEncoding := Encoding;
  FOwnsStream := AOwnsStream;
end;

procedure TBinaryWriter.Close;
begin
  if FOwnsStream then
    FreeAndNil(FStream);
end;

constructor TBinaryWriter.Create(const Filename: string; Append: Boolean; Encoding: TEncoding);
begin
  if not Append or not FileExists(Filename) then
    FStream := TFileStream.Create(Filename, fmCreate)
  else
  begin
    FStream := TFileStream.Create(Filename, fmOpenWrite);
    FStream.Seek(0, soEnd);
  end;
  Create(FStream, Encoding, True);
end;

constructor TBinaryWriter.Create(const Filename: string; Append: Boolean);
begin
  Create(Filename, Append, nil);
end;

constructor TBinaryWriter.Create;
begin
  Create(TNullStream.Create, nil, True);
end;

destructor TBinaryWriter.Destroy;
begin
  if not TEncoding.IsStandardEncoding(FEncoding) then
    FEncoding.Free;
  if FOwnsStream then
    FStream.Free;
  inherited;
end;

class destructor TBinaryWriter.Destroy;
begin
  FNull.Free;
end;

class function TBinaryWriter.GetNull: TBinaryWriter;
var
  Writer: TBinaryWriter;
begin
  if FNull = nil then
  begin
    Writer := TBinaryWriter.Create;
    Writer := AtomicCmpExchange(Pointer(FNull), Pointer(Writer), nil);
    Writer.Free;
  end;
  Result := FNull;
end;

function TBinaryWriter.GetBaseStream: TStream;
begin
  Result := FStream;
end;

function TBinaryWriter.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := FStream.Seek(Offset, Origin);
end;

procedure TBinaryWriter.Write(Value: Char);
var
  Bytes: TBytes;
begin
  if Value.IsSurrogate then
    raise EArgumentException.CreateRes(@SNoSurrogates);
  Bytes := FEncoding.GetBytes(Value);
  FStream.WriteBuffer(Bytes, Length(Bytes));
end;

procedure TBinaryWriter.Write(Value: Byte);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: Boolean);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(const Value: TUnicodeCharArray);
var
  Bytes: TBytes;
begin
  Bytes := FEncoding.GetBytes(Value);
  FStream.WriteBuffer(Bytes, Length(Bytes));
end;

procedure TBinaryWriter.Write(const Value: string);
var
  Bytes: TBytes;
begin
  Bytes := FEncoding.GetBytes(Value);
  Write7BitEncodedInt(Length(Bytes));
  FStream.WriteBuffer(Bytes, Length(Bytes));
end;

procedure TBinaryWriter.Write(Value: Single);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: Int64);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(const Value: TBytes; Index, Count: Integer);
begin
  if Index < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Index']); // do not localize
  if Count < 0 then
    raise EArgumentOutOfRangeException.CreateResFmt(@sArgumentOutOfRange_NeedNonNegValue, ['Count']); // do not localize
  if Length(Value) - Index < Count  then
    raise EArgumentOutOfRangeException.CreateRes(@sArgumentOutOfRange_OffLenInvalid);
  FStream.WriteBuffer(Value, Index, Count);
end;

procedure TBinaryWriter.Write(const Value: TBytes);
begin
  FStream.WriteBuffer(Value, Length(Value));
end;

procedure TBinaryWriter.Write(const Value: TUnicodeCharArray; Index, Count: Integer);
var
  Bytes: TBytes;
begin
  Bytes := FEncoding.GetBytes(Value, Index, Count);
  FStream.WriteBuffer(Bytes, Length(Bytes));
end;

procedure TBinaryWriter.Write(Value: UInt64);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: Double);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: SmallInt);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: Integer);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: Cardinal);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: Word);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write(Value: ShortInt);
begin
  FStream.Write(Value, SizeOf(Value));
end;

procedure TBinaryWriter.Write7BitEncodedInt(Value: Integer);
begin
  repeat
    if Value > $7f then
      Write(Byte((Value and $7f) or $80))
    else
      Write(Byte(Value));
    Value := Value shr 7;
  until Value = 0;
end;

{ TStringReader }

procedure TStringReader.Close;
begin
  FData := '';
  FIndex := -1;
end;

constructor TStringReader.Create(S: string);
begin
  inherited Create;

  FIndex := Low(S);
  FData := S;
end;

function TStringReader.Peek: Integer;
begin
  Result := -1;
  if (FIndex >= Low(FData)) and (FIndex <= High(FData)) then
    Result := Integer(FData[FIndex]);
end;

function TStringReader.Read: Integer;
begin
  Result := -1;
  if (FIndex >= Low(FData)) and (FIndex <= High(FData)) then
  begin
    Result := Integer(FData[FIndex]);
    Inc(FIndex);
    if FIndex > High(FData) then
      FIndex := -1;
  end;
end;

function TStringReader.Read(var Buffer: TUnicodeCharArray; Index,
  Count: Integer): Integer;
begin
  Result := -1;

  if FIndex = -1 then
    Exit;

  if Length(Buffer) < Index + Count then
    raise EArgumentOutOfRangeException.CreateRes(@SInsufficientReadBuffer);

  if Count > FData.Length - FIndex + Low(FData) then
    Count := FData.Length - FIndex + Low(FData);
  Result := Count;

  FData.CopyTo(FIndex-Low(FData), Buffer, Index, Count);

  Inc(FIndex, Count);
  if FIndex > High(FData) then
    FIndex := -1;
end;

function TStringReader.ReadBlock(var Buffer: TUnicodeCharArray; Index,
  Count: Integer): Integer;
begin
  Result := Read(Buffer, Index, Count);
end;

function TStringReader.ReadLine: string;
var
  StartIndex: Integer;
  EndIndex: Integer;
begin
  Result := '';
  if FIndex = -1 then
    Exit;

  StartIndex := FIndex;
  EndIndex := FIndex;

  while True do
  begin
    if EndIndex > High(FData) then
    begin
      FIndex := EndIndex;
      Break;
    end;
    if FData[EndIndex] = #10 then
    begin
      FIndex := EndIndex + 1;
      Break;
    end
    else
    if (FData[EndIndex] = #13) and (EndIndex + 1 <= High(FData)) and (FData[EndIndex + 1] = #10) then
    begin
      FIndex := EndIndex + 2;
      Break;
    end
    else
    if FData[EndIndex] = #13 then
    begin
      FIndex := EndIndex + 1;
      Break;
    end;
    Inc(EndIndex);
  end;

  Result := FData.SubString(StartIndex-Low(FData), (EndIndex - StartIndex));

  if FIndex > High(FData) then
    FIndex := -1;
end;

function TStringReader.ReadToEnd: string;
begin
  Result := '';
  if FIndex = -1 then
    Exit;
  Result := FData.SubString(FIndex-Low(FData));
  FIndex := -1;
end;

procedure TStringReader.Rewind;
begin
  FIndex := Low(FData);
end;

{ TStringWriter }

procedure TStringWriter.Close;
begin
end;

constructor TStringWriter.Create;
begin
  inherited Create;

  FOwnsBuilder := True;
  FBuilder := TUnicodeStringBuilder.Create;
end;

constructor TStringWriter.Create(Builder: TUnicodeStringBuilder);
begin
  inherited Create;

  if not Assigned(Builder) then
    raise EArgumentException.CreateResFmt(@SParamIsNil, ['Builder']); // DO NOT LOCALIZE

  FOwnsBuilder := False;
  FBuilder := Builder;
end;

destructor TStringWriter.Destroy;
begin
  if FOwnsBuilder then
  begin
    FBuilder.Free;
    FBuilder := nil;
  end;
  inherited;
end;

procedure TStringWriter.Flush;
begin

end;

function TStringWriter.ToString: string;
begin
  Result := FBuilder.ToString;
end;

procedure TStringWriter.Write(Value: Cardinal);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Boolean);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Char);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Char; Count: Integer);
begin
  FBuilder.Append(Value, Count);
end;

procedure TStringWriter.Write(const Value: TUnicodeCharArray; Index, Count: Integer);
begin
  FBuilder.Append(Value, Index, Count);
end;

procedure TStringWriter.Write(const Format: string; Args: array of const);
begin
  FBuilder.AppendFormat(Format, Args);
end;

procedure TStringWriter.Write(Value: UInt64);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: TObject);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Single);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(const Value: string);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Int64);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(const Value: TUnicodeCharArray);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Double);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.Write(Value: Integer);
begin
  FBuilder.Append(Value);
end;

procedure TStringWriter.WriteLine(const Value: TUnicodeCharArray);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Double);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Integer);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine;
begin
  FBuilder.AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Boolean);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Char);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Int64);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: UInt64);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(const Format: string; Args: array of const);
begin
  FBuilder.AppendFormat(Format, Args).AppendLine;
end;

procedure TStringWriter.WriteLine(const Value: TUnicodeCharArray; Index, Count: Integer);
begin
  FBuilder.Append(Value, Index, Count).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Cardinal);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: TObject);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(Value: Single);
begin
  FBuilder.Append(Value).AppendLine;
end;

procedure TStringWriter.WriteLine(const Value: string);
begin
  FBuilder.Append(Value).AppendLine;
end;

{ TStreamWriter }

procedure TStreamWriter.Close;
begin
  Flush;
  if FOwnsStream  then
    FreeAndNil(FStream);
end;

constructor TStreamWriter.Create(Stream: TStream);
begin
  inherited Create;
  FOwnsStream := False;
  FStream := Stream;
  FEncoding := TEncoding.UTF8;
  SetLength(FBuffer, 1024);
  FBufferIndex := 0;
  FNewLine := sLineBreak;
  FAutoFlush := True;
end;

constructor TStreamWriter.Create(Stream: TStream; Encoding: TEncoding; BufferSize: Integer);
begin
  inherited Create;
  FOwnsStream := False;
  FStream := Stream;
  FEncoding := Encoding;
  if BufferSize >= 128 then
    SetLength(FBuffer, BufferSize)
  else
    SetLength(FBuffer, 128);
  FBufferIndex := 0;
  FNewLine := sLineBreak;
  FAutoFlush := True;
  if Stream.Position = 0 then
    WriteBytes(FEncoding.GetPreamble);
end;

constructor TStreamWriter.Create(const Filename: string; Append: Boolean);
begin
  if not Append or not FileExists(Filename) then
    FStream := TFileStream.Create(Filename, fmCreate)
  else
  begin
    FStream := TFileStream.Create(Filename, fmOpenWrite);
    FStream.Seek(0, soEnd);
  end;
  Create(FStream);
  FOwnsStream := True;
end;

constructor TStreamWriter.Create(const Filename: string; Append: Boolean;
  Encoding: TEncoding; BufferSize: Integer);
begin
  if not Append or not FileExists(Filename) then
    FStream := TFileStream.Create(Filename, fmCreate)
  else
  begin
    FStream := TFileStream.Create(Filename, fmOpenWrite);
    FStream.Seek(0, soEnd);
  end;
  Create(FStream, Encoding, BufferSize);
  FOwnsStream := True;
end;

destructor TStreamWriter.Destroy;
begin
  Close;
  SetLength(FBuffer, 0);
  inherited;
end;

procedure TStreamWriter.Flush;
begin
  if FBufferIndex = 0 then
    Exit;
  if FStream = nil then
    Exit;

  try
    FStream.WriteBuffer(FBuffer, 0, FBufferIndex);
  finally
    FBufferIndex := 0;
  end;
end;

procedure TStreamWriter.OwnStream;
begin
  FOwnsStream := True;
end;

procedure TStreamWriter.Write(Value: Cardinal);
begin
  WriteBytes(FEncoding.GetBytes(UIntToStr(Value)));
end;

procedure TStreamWriter.Write(const Value: string);
begin
  WriteBytes(FEncoding.GetBytes(Value));
end;

procedure TStreamWriter.Write(Value: UInt64);
begin
  WriteBytes(FEncoding.GetBytes(UIntToStr(Value)));
end;

procedure TStreamWriter.Write(const Value: TUnicodeCharArray; Index, Count: Integer);
var
  Bytes: TBytes;
begin
  SetLength(Bytes, Count * 4);
  SetLength(Bytes, FEncoding.GetBytes(Value, Index, Count, Bytes, 0));
  WriteBytes(Bytes);
end;

procedure TStreamWriter.WriteBytes(Bytes: TBytes);
var
  ByteIndex: Integer;
  WriteLen: Integer;
begin
  ByteIndex := 0;

  while ByteIndex < Length(Bytes) do
  begin
    WriteLen := Length(Bytes) - ByteIndex;
    if WriteLen > Length(FBuffer) - FBufferIndex then
      WriteLen := Length(FBuffer) - FBufferIndex;

    Move(Bytes[ByteIndex], FBuffer[FBufferIndex], WriteLen);

    Inc(FBufferIndex, WriteLen);
    Inc(ByteIndex, WriteLen);

    if FBufferIndex >= Length(FBuffer) then
      Flush;
  end;

  if FAutoFlush then
    Flush;
end;

procedure TStreamWriter.Write(const Format: string; Args: array of const);
begin
  WriteBytes(FEncoding.GetBytes(SysUtils.Format(Format, Args)));
end;

procedure TStreamWriter.Write(Value: Single);
begin
  WriteBytes(FEncoding.GetBytes(FloatToStr(Value)));
end;

procedure TStreamWriter.Write(const Value: TUnicodeCharArray);
begin
  WriteBytes(FEncoding.GetBytes(Value));
end;

procedure TStreamWriter.Write(Value: Double);
begin
  WriteBytes(FEncoding.GetBytes(FloatToStr(Value)));
end;

procedure TStreamWriter.Write(Value: Integer);
begin
  WriteBytes(FEncoding.GetBytes(IntToStr(Value)));
end;

procedure TStreamWriter.Write(Value: Char);
begin
  WriteBytes(FEncoding.GetBytes(Value));
end;

procedure TStreamWriter.Write(Value: TObject);
begin
  WriteBytes(FEncoding.GetBytes(Value.ToString));
end;

procedure TStreamWriter.Write(Value: Int64);
begin
  WriteBytes(FEncoding.GetBytes(IntToStr(Value)));
end;

procedure TStreamWriter.Write(Value: Boolean);
begin
  WriteBytes(FEncoding.GetBytes(BoolToStr(Value, True)));
end;

procedure TStreamWriter.WriteLine(const Value: TUnicodeCharArray);
begin
  WriteBytes(FEncoding.GetBytes(Value));
  WriteBytes(FEncoding.GetBytes(FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Double);
begin
  WriteBytes(FEncoding.GetBytes(FloatToStr(Value) + FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Integer);
begin
  WriteBytes(FEncoding.GetBytes(IntToStr(Value) + FNewLine));
end;

procedure TStreamWriter.WriteLine;
begin
  WriteBytes(FEncoding.GetBytes(FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Boolean);
begin
  WriteBytes(FEncoding.GetBytes(BoolToStr(Value, True) + FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Char);
begin
  WriteBytes(FEncoding.GetBytes(Value));
  WriteBytes(FEncoding.GetBytes(FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Int64);
begin
  WriteBytes(FEncoding.GetBytes(IntToStr(Value) + FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: UInt64);
begin
  WriteBytes(FEncoding.GetBytes(UIntToStr(Value) + FNewLine));
end;

procedure TStreamWriter.WriteLine(const Format: string; Args: array of const);
begin
  WriteBytes(FEncoding.GetBytes(SysUtils.Format(Format, Args) + FNewLine));
end;

procedure TStreamWriter.WriteLine(const Value: TUnicodeCharArray; Index, Count: Integer);
var
  Bytes: TBytes;
begin
  SetLength(Bytes, Count * 4);
  SetLength(Bytes, FEncoding.GetBytes(Value, Index, Count, Bytes, 0));
  WriteBytes(Bytes);
  WriteBytes(FEncoding.GetBytes(FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Cardinal);
begin
  WriteBytes(FEncoding.GetBytes(UIntToStr(Value) + FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: TObject);
begin
  WriteBytes(FEncoding.GetBytes(Value.ToString + FNewLine));
end;

procedure TStreamWriter.WriteLine(Value: Single);
begin
  WriteBytes(FEncoding.GetBytes(FloatToStr(Value) + FNewLine));
end;

procedure TStreamWriter.WriteLine(const Value: string);
begin
  WriteBytes(FEncoding.GetBytes(Value + FNewLine));
end;

{ TStreamReader.TBufferedData }

constructor TStreamReader.TBufferedData.Create(ABufferSize: Integer);
begin
  inherited Create;
  FBufferSize := ABufferSize;
end;

procedure TStreamReader.TBufferedData.Clear;
begin
  inherited Length := 0;
  FStart := 0;
end;

function TStreamReader.TBufferedData.GetChars(AIndex: Integer): Char;
begin
  Result := FData[FStart + 1 + AIndex];
end;

function TStreamReader.TBufferedData.Length: Integer;
begin
  Result := FLength - FStart;
end;

function TStreamReader.TBufferedData.PeekChar: Char;
begin
  Result := FData[FStart + 1];
end;

function TStreamReader.TBufferedData.MoveChar: Char;
begin
  Result := FData[FStart + 1];
  Inc(FStart);
end;

procedure TStreamReader.TBufferedData.MoveArray(DestinationIndex, Count: Integer;
  var Destination: TUnicodeCharArray);
begin
  CopyTo(FStart, Destination, DestinationIndex, Count);
  Inc(FStart, Count);
end;

procedure TStreamReader.TBufferedData.MoveString(Count, NewPos: Integer;
  var Destination: string);
begin
  if (FStart = 0) and (Count = inherited Length) then
    Destination := ToString
  else
    Destination := ToString(FStart, Count);
  Inc(FStart, NewPos);
end;

procedure TStreamReader.TBufferedData.TrimBuffer;
begin
  if inherited Length > FBufferSize then
  begin
    Remove(0, FStart);
    FStart := 0;
  end;
end;

{ TStreamReader }

constructor TStreamReader.Create(Stream: TStream);
begin
  Create(Stream, TEncoding.UTF8, True);
end;

constructor TStreamReader.Create(Stream: TStream; DetectBOM: Boolean);
begin
  Create(Stream, TEncoding.UTF8, DetectBOM);
end;

constructor TStreamReader.Create(Stream: TStream; Encoding: TEncoding;
  DetectBOM: Boolean; BufferSize: Integer);
begin
  inherited Create;

  if not Assigned(Stream) then
    raise EArgumentException.CreateResFmt(@SParamIsNil, ['Stream']); // DO NOT LOCALIZE
  if not Assigned(Encoding) then
    raise EArgumentException.CreateResFmt(@SParamIsNil, ['Encoding']); // DO NOT LOCALIZE

  FEncoding := Encoding;
  FBufferSize := BufferSize;
  if FBufferSize < 128 then
    FBufferSize := 128;
  FBufferedData := TBufferedData.Create(FBufferSize);
  FNoDataInStream := False;
  FStream := Stream;
  FOwnsStream := False;
  FDetectBOM := DetectBOM;
  FSkipPreamble := not FDetectBOM;
end;

constructor TStreamReader.Create(const Filename: string; Encoding: TEncoding;
  DetectBOM: Boolean; BufferSize: Integer);
begin
  Create(TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite), Encoding, DetectBOM, BufferSize);
  FOwnsStream := True;
end;

constructor TStreamReader.Create(const Filename: string; DetectBOM: Boolean);
begin
  Create(TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite), DetectBOM);
  FOwnsStream := True;
end;

constructor TStreamReader.Create(const Filename: string);
begin
  Create(TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite));
  FOwnsStream := True;
end;

destructor TStreamReader.Destroy;
begin
  Close;
  inherited;
end;

procedure TStreamReader.Close;
begin
  if FOwnsStream then
    FreeAndNil(FStream);
  FreeAndNil(FBufferedData);
end;

procedure TStreamReader.DiscardBufferedData;
begin
  if FBufferedData <> nil then
  begin
    FBufferedData.Clear;
    FNoDataInStream := False;
  end;
end;

function TStreamReader.DetectBOM(var Encoding: TEncoding; Buffer: TBytes): Integer;
var
  LEncoding: TEncoding;
begin
  // try to automatically detect the buffer encoding
  LEncoding := nil;
  Result := TEncoding.GetBufferEncoding(Buffer, LEncoding, nil);
  if LEncoding <> nil then
    Encoding := LEncoding
  else if Encoding = nil then
    Encoding := TEncoding.Default;

  FDetectBOM := False;
end;

procedure TStreamReader.FillBuffer(var Encoding: TEncoding);
const
  BufferPadding = 4;
var
  LString: string;
  LBuffer: TBytes;
  BytesRead: Integer;
  StartIndex: Integer;
  ByteCount: Integer;
  ByteBufLen: Integer;
  ExtraByteCount: Integer;

  procedure AdjustEndOfBuffer(const ABuffer: TBytes; Offset: Integer);
  var
    Pos, Size: Integer;
    Rewind: Integer;
  begin
    Dec(Offset);
    for Pos := Offset downto 0 do
    begin
      for Size := Offset - Pos + 1 downto 1 do
      begin
        if Encoding.GetCharCount(ABuffer, Pos, Size) > 0 then
        begin
          Rewind := Offset - (Pos + Size - 1);
          if Rewind <> 0 then
          begin
            FStream.Position := FStream.Position - Rewind;
            BytesRead := BytesRead - Rewind;
          end;
          Exit;
        end;
      end;
    end;
  end;

begin
  SetLength(LBuffer, FBufferSize + BufferPadding);

  // Read data from stream
  BytesRead := FStream.Read(LBuffer[0], FBufferSize);
  FNoDataInStream := BytesRead = 0;

  // Check for byte order mark and calc start index for character data
  if FDetectBOM then
    StartIndex := DetectBOM(Encoding, LBuffer)
  else if FSkipPreamble then
    StartIndex := SkipPreamble(Encoding, LBuffer)
  else
    StartIndex := 0;

  // Adjust the end of the buffer to be sure we have a valid encoding
  if not FNoDataInStream then
    AdjustEndOfBuffer(LBuffer, BytesRead);

  // Convert to string and calc byte count for the string
  ByteBufLen := BytesRead - StartIndex;
  LString := FEncoding.GetString(LBuffer, StartIndex, ByteBufLen);
  ByteCount := FEncoding.GetByteCount(LString);

  // If byte count <> number of bytes read from the stream
  // the buffer boundary is mid-character and additional bytes
  // need to be read from the stream to complete the character
  ExtraByteCount := 0;
  while (ByteCount <> ByteBufLen) and (ExtraByteCount < FEncoding.GetMaxByteCount(1)) do
  begin
    // Expand buffer if padding is used
    if (StartIndex + ByteBufLen) = Length(LBuffer) then
      SetLength(LBuffer, Length(LBuffer) + BufferPadding);

    // Read one more byte from the stream into the
    // buffer padding and convert to string again
    BytesRead := FStream.Read(LBuffer[StartIndex + ByteBufLen], 1);
    if BytesRead = 0 then
      // End of stream, append what's been read and discard remaining bytes
      Break;

    Inc(ExtraByteCount);

    Inc(ByteBufLen);
    LString := FEncoding.GetString(LBuffer, StartIndex, ByteBufLen);
    ByteCount := FEncoding.GetByteCount(LString);
  end;

  // Add string to character data buffer
  FBufferedData.Append(LString);
end;

function TStreamReader.GetEndOfStream: Boolean;
begin
  if not FNoDataInStream and (FBufferedData <> nil) and (FBufferedData.Length < 1) then
    FillBuffer(FEncoding);
  Result := FNoDataInStream and ((FBufferedData = nil) or (FBufferedData.Length = 0));
end;

procedure TStreamReader.OwnStream;
begin
  FOwnsStream := True;
end;

function TStreamReader.Peek: Integer;
begin
  Result := -1;
  if (FBufferedData <> nil) and (not EndOfStream) then
  begin
    if FBufferedData.Length < 1 then
      FillBuffer(FEncoding);
    Result := Integer(FBufferedData.PeekChar);
  end;
end;

function TStreamReader.Read(var Buffer: TUnicodeCharArray; Index,
  Count: Integer): Integer;
begin
  Result := -1;
  if (FBufferedData <> nil) and (not EndOfStream) then
  begin
    while (FBufferedData.Length < Count) and (not EndOfStream) and (not FNoDataInStream) do
      FillBuffer(FEncoding);

    if FBufferedData.Length > Count then
      Result := Count
    else
      Result := FBufferedData.Length;

    FBufferedData.MoveArray(Index, Result, Buffer);
    FBufferedData.TrimBuffer;
  end;
end;

function TStreamReader.ReadBlock(var Buffer: TUnicodeCharArray; Index,
  Count: Integer): Integer;
begin
  Result := Read(Buffer, Index, Count);
end;

function TStreamReader.Read: Integer;
begin
  Result := -1;
  if (FBufferedData <> nil) and (not EndOfStream) then
  begin
    if FBufferedData.Length < 1 then
      FillBuffer(FEncoding);
    Result := Integer(FBufferedData.MoveChar);
  end;
end;

function TStreamReader.ReadLine: string;
var
  NewLineIndex: Integer;
  PostNewLineIndex: Integer;
  LChar: Char;
begin
  Result := '';
  if FBufferedData = nil then
    Exit;
  NewLineIndex := 0;
  PostNewLineIndex := 0;

  while True do
  begin
    if (NewLineIndex + 2 > FBufferedData.Length) and (not FNoDataInStream) then
      FillBuffer(FEncoding);

    if NewLineIndex >= FBufferedData.Length then
    begin
      if FNoDataInStream then
      begin
        PostNewLineIndex := NewLineIndex;
        Break;
      end
      else
      begin
        FillBuffer(FEncoding);
        if FBufferedData.Length = 0 then
          Break;
      end;
    end;
    LChar := FBufferedData.Chars[NewLineIndex];
    if LChar = #10 then
    begin
      PostNewLineIndex := NewLineIndex + 1;
      Break;
    end
    else if LChar = #13 then
    begin
      if (NewLineIndex + 1 < FBufferedData.Length) and (FBufferedData.Chars[NewLineIndex + 1] = #10) then
        PostNewLineIndex := NewLineIndex + 2
      else
        PostNewLineIndex := NewLineIndex + 1;
      Break;
    end;

    Inc(NewLineIndex);
  end;

  FBufferedData.MoveString(NewLineIndex, PostNewLineIndex, Result);
  FBufferedData.TrimBuffer;
end;

function TStreamReader.ReadToEnd: string;
begin
  Result := '';
  if (FBufferedData <> nil) and (not EndOfStream) then
  begin
    repeat
      FillBuffer(FEncoding);
    until FNoDataInStream;
    FBufferedData.MoveString(FBufferedData.Length, FBufferedData.Length, Result);
    FBufferedData.Clear;
  end;
end;

function TStreamReader.SkipPreamble(Encoding: TEncoding; Buffer: TBytes): Integer;
var
  I: Integer;
  LPreamble: TBytes;
  BOMPresent: Boolean;
begin
  Result := 0;
  LPreamble := Encoding.GetPreamble;
  if (Length(LPreamble) > 0) then
  begin
    if Length(Buffer) >= Length(LPreamble) then
    begin
      BOMPresent := True;
      for I := 0 to Length(LPreamble) - 1 do
        if LPreamble[I] <> Buffer[I] then
        begin
          BOMPresent := False;
          Break;
        end;
      if BOMPresent then
        Result := Length(LPreamble);
    end;
  end;
  FSkipPreamble := False;
end;

procedure TStreamReader.Rewind;
begin
  DiscardBufferedData;
  FSkipPreamble := not FDetectBOM;
  FStream.Position := 0;
end;

end.
