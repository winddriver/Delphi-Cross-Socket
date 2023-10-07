unit Utils.RegEx;

{$I zLib.inc}

interface

uses
  SysUtils
  ,Classes
  ,Variants

  {$IFDEF DELPHI}
  ,System.RegularExpressionsCore
  {$ELSE}
  ,DTF.Types
  ,uregexpr
  {$ENDIF}
  ;

resourcestring
  SRegExInvalidIndexType = 'Invalid index type';
  SRegExIndexOutOfBounds = 'Index out of bounds (%d)';
  SRegExInvalidGroupName = 'Invalid group name (%s)';

type
  ERegEx = class(Exception);
  IRegEx = interface;

  // roNotEmpty 只用于 Split
  TRegExOption = (roIgnoreCase, roMultiLine, roSingleLine, roExtended, roNotEmpty);
  TRegExOptions = set of TRegExOption;

  TGroup = record
  private
    FIndex: Integer;
    FLength: Integer;
    FSuccess: Boolean;
    FValue: string;

    constructor Create(const AValue: string; const AIndex, ALength: Integer; const ASuccess: Boolean);
    function GetValue: string;
  public
    property Index: Integer read FIndex;
    property Length: Integer read FLength;
    property Success: Boolean read FSuccess;
    property Value: string read GetValue;
  end;

  TGroupCollectionEnumerator = class;

  TGroupCollection = record
  private
    FList: TArray<TGroup>;
    FRegEx: IRegEx;

    constructor Create(const ARegEx: IRegEx; const AValue: string;
      const AIndex, ALength: Integer; const ASuccess: Boolean);
    function GetCount: Integer;
    function GetItem(const AIndex: Variant): TGroup;
  public
    function GetEnumerator: TGroupCollectionEnumerator;
    property Count: Integer read GetCount;
    property Item[const AIndex: Variant]: TGroup read GetItem; default;
  end;

  TGroupCollectionEnumerator = class
  private
    FCollection: TGroupCollection;
    FIndex: Integer;
  public
    constructor Create(const ACollection: TGroupCollection);
    function GetCurrent: TGroup;
    function MoveNext: Boolean;
    property Current: TGroup read GetCurrent;
  end;

  TMatch = record
  private
    FGroup: TGroup;
    FGroups: TGroupCollection;
    FRegEx: IRegEx;

    constructor Create(const ARegEx: IRegEx; const AValue: string;
      const AIndex, ALength: Integer; const ASuccess: Boolean);
    function GetIndex: Integer;
    function GetGroups: TGroupCollection;
    function GetLength: Integer;
    function GetSuccess: Boolean;
    function GetValue: string;
  public
    function NextMatch: TMatch;
    property Groups: TGroupCollection read GetGroups;
    property Index: Integer read GetIndex;
    property Length: Integer read GetLength;
    property Success: Boolean read GetSuccess;
    property Value: string read GetValue;
  end;

  TMatchCollectionEnumerator = class;

  TMatchCollection = record
  private
    FRegEx: IRegEx;
    FList: TArray<TMatch>;

    constructor Create(const ARegEx: IRegEx; const AInput: string;
      const AStartPos: Integer);
    function GetCount: Integer;
    function GetItem(const AIndex: Integer): TMatch;
  public
    function GetEnumerator: TMatchCollectionEnumerator;
    property Count: Integer read GetCount;
    property Item[const AIndex: Integer]: TMatch read GetItem; default;
  end;

  TMatchCollectionEnumerator = class
  private
    FCollection: TMatchCollection;
    FIndex: Integer;
  public
    constructor Create(const ACollection: TMatchCollection);
    function GetCurrent: TMatch;
    function MoveNext: Boolean;
    property Current: TMatch read GetCurrent;
  end;

  TMatchEvaluator = reference to function(const AMatch: TMatch): string;

  IRegEx = interface
  ['{E0681094-E838-42F5-B64C-33491CD57855}']
    function GetSubject: string;
    function GetPattern: string;
    function GetStartPos: Integer;
    function GetOptions: TRegExOptions;
    function GetGroupCount: Integer;
    function GetGroupLengths(const AIndex: Integer): Integer;
    function GetGroupOffsets(const AIndex: Integer): Integer;
    function GetGroups(const AIndex: Integer): string;

    function GetMatchedLength: Integer;
    function GetMatchedOffset: Integer;
    function GetMatchedText: string;

    procedure SetSubject(const AValue: string);
    procedure SetPattern(const AValue: string);
    procedure SetStartPos(const AValue: Integer);
    procedure SetOptions(const AValue: TRegExOptions);

    function GetGroupIndex(const AGroupName: string): Integer;
    function Match: Boolean;
    function MatchAgain: Boolean;

    function Replace(const AEvaluator: TMatchEvaluator; const ACount: Integer): string; overload;
    function Replace(const AEvaluator: TMatchEvaluator): string; overload;

    function Replace(const AReplacement: string; const ACount: Integer): string; overload;
    function Replace(const AReplacement: string): string; overload;

    function Split(const ACount: Integer): TArray<string>; overload;
    function Split: TArray<string>; overload;

    property Subject: string read GetSubject write SetSubject;
    property Pattern: string read GetPattern write SetPattern;
    property StartPos: Integer read GetStartPos write SetStartPos;
    property Options: TRegExOptions read GetOptions write SetOptions;

    property GroupCount: Integer read GetGroupCount;
    property Groups[const AIndex: Integer]: string read GetGroups;
    property GroupLengths[const AIndex: Integer]: Integer read GetGroupLengths;
    property GroupOffsets[const AIndex: Integer]: Integer read GetGroupOffsets;

    property MatchedText: string read GetMatchedText;
    property MatchedLength: Integer read GetMatchedLength;
    property MatchedOffset: Integer read GetMatchedOffset;
  end;

  { TRegEx }

  TRegEx = class(TInterfacedObject, IRegEx)
  private
    FStartPos: Integer;
    FOptions: TRegExOptions;
    {$IFDEF DELPHI}
    FRegEx: TPerlRegEx;
    {$ELSE}
    FRegEx: TRegExpr;
    {$ENDIF}
  private
    function GetSubject: string;
    function GetPattern: string;
    function GetStartPos: Integer;
    function GetOptions: TRegExOptions;
    function GetGroupCount: Integer;
    function GetGroupLengths(const AIndex: Integer): Integer;
    function GetGroupOffsets(const AIndex: Integer): Integer;
    function GetGroups(const AIndex: Integer): string;

    function GetMatchedLength: Integer;
    function GetMatchedOffset: Integer;
    function GetMatchedText: string;

    procedure SetSubject(const AValue: string);
    procedure SetPattern(const AValue: string);
    procedure SetStartPos(const AValue: Integer);
    procedure SetOptions(const AValue: TRegExOptions);

    procedure UpdateOptions;
  public
    constructor Create(const APattern: string); overload;
    constructor Create; overload;
    destructor Destroy; override;

    function GetGroupIndex(const AGroupName: string): Integer;
    function Match: Boolean; overload;
    function MatchAgain: Boolean;

    function Replace(const AEvaluator: TMatchEvaluator; const ACount: Integer): string; overload;
    function Replace(const AEvaluator: TMatchEvaluator): string; overload;

    function Replace(const AReplacement: string; const ACount: Integer): string; overload;
    function Replace(const AReplacement: string): string; overload;

    function Split(const ACount: Integer): TArray<string>; overload;
    function Split: TArray<string>; overload;

    property Subject: string read GetSubject write SetSubject;
    property Pattern: string read GetPattern write SetPattern;
    property StartPos: Integer read GetStartPos write SetStartPos; // 起始为: 1
    property Options: TRegExOptions read GetOptions write SetOptions;

    property GroupCount: Integer read GetGroupCount;
    property Groups[const AIndex: Integer]: string read GetGroups;
    property GroupLengths[const AIndex: Integer]: Integer read GetGroupLengths;
    property GroupOffsets[const AIndex: Integer]: Integer read GetGroupOffsets;

    property MatchedText: string read GetMatchedText;
    property MatchedLength: Integer read GetMatchedLength;
    property MatchedOffset: Integer read GetMatchedOffset;

    class function IsMatch(const AInput, APattern: string; const AOptions: TRegExOptions; const AStartPos: Integer): Boolean; overload; static;
    class function IsMatch(const AInput, APattern: string; const AOptions: TRegExOptions): Boolean; overload; static;
    class function IsMatch(const AInput, APattern: string; const AStartPos: Integer): Boolean; overload; static;
    class function IsMatch(const AInput, APattern: string): Boolean; overload; static;

    class function Match(const AInput, APattern: string; const AOptions: TRegExOptions; const AStartPos: Integer): TMatch; overload; static;
    class function Match(const AInput, APattern: string; const AOptions: TRegExOptions): TMatch; overload; static;
    class function Match(const AInput, APattern: string; const AStartPos: Integer): TMatch; overload; static;
    class function Match(const AInput, APattern: string): TMatch; overload; static;

    class function Matches(const AInput, APattern: string; const AOptions: TRegExOptions; const AStartPos: Integer): TMatchCollection; overload; static;
    class function Matches(const AInput, APattern: string; const AOptions: TRegExOptions): TMatchCollection; overload; static;
    class function Matches(const AInput, APattern: string; const AStartPos: Integer): TMatchCollection; overload; static;
    class function Matches(const AInput, APattern: string): TMatchCollection; overload; static;

    class function Replace(const AInput, APattern, AReplacement: string; const AOptions: TRegExOptions; const ACount, AStartPos: Integer): string; overload; static;
    class function Replace(const AInput, APattern, AReplacement: string; const AOptions: TRegExOptions; const ACount: Integer): string; overload; static;
    class function Replace(const AInput, APattern, AReplacement: string; const AOptions: TRegExOptions): string; overload; static;
    class function Replace(const AInput, APattern, AReplacement: string; const ACount, AStartPos: Integer): string; overload; static;
    class function Replace(const AInput, APattern, AReplacement: string; const ACount: Integer): string; overload; static;
    class function Replace(const AInput, APattern, AReplacement: string): string; overload; static;

    class function Replace(const AInput, APattern: string; const AEvaluator: TMatchEvaluator; const AOptions: TRegExOptions; const ACount, AStartPos: Integer): string; overload; static;
    class function Replace(const AInput, APattern: string; const AEvaluator: TMatchEvaluator; const AOptions: TRegExOptions; const ACount: Integer): string; overload; static;
    class function Replace(const AInput, APattern: string; const AEvaluator: TMatchEvaluator; const AOptions: TRegExOptions): string; overload; static;
    class function Replace(const AInput, APattern: string; const AEvaluator: TMatchEvaluator; const ACount, AStartPos: Integer): string; overload; static;
    class function Replace(const AInput, APattern: string; const AEvaluator: TMatchEvaluator; const ACount: Integer): string; overload; static;
    class function Replace(const AInput, APattern: string; const AEvaluator: TMatchEvaluator): string; overload; static;

    class function Split(const AInput, APattern: string; const AOptions: TRegExOptions; const ACount, AStartPos: Integer): TArray<string>; overload; static;
    class function Split(const AInput, APattern: string; const AOptions: TRegExOptions; const ACount: Integer): TArray<string>; overload; static;
    class function Split(const AInput, APattern: string; const AOptions: TRegExOptions): TArray<string>; overload; static;
    class function Split(const AInput, APattern: string; const ACount, AStartPos: Integer): TArray<string>; overload; static;
    class function Split(const AInput, APattern: string; const ACount: Integer): TArray<string>; overload; static;
    class function Split(const AInput, APattern: string): TArray<string>; overload; static;
  end;

implementation

{ TGroup }

constructor TGroup.Create(const AValue: string; const AIndex, ALength: Integer;
  const ASuccess: Boolean);
begin
  FSuccess := ASuccess;
  FValue := AValue;
  FIndex := AIndex;
  FLength := ALength;
end;

function TGroup.GetValue: string;
begin
  Result := FValue.Substring(FIndex - 1, FLength);
end;

{ TGroupCollection }

constructor TGroupCollection.Create(const ARegEx: IRegEx; const AValue: string;
  const AIndex, ALength: Integer; const ASuccess: Boolean);
var
  I: Integer;
begin
  FRegEx := ARegEx;

  if ASuccess then
  begin
    SetLength(FList, FRegEx.GroupCount + 1);
    FList[0] := TGroup.Create(AValue, AIndex, ALength, ASuccess);
    for I := 1 to Length(FList) - 1 do
      FList[I] := TGroup.Create(AValue, FRegEx.GroupOffsets[I], FRegEx.GroupLengths[I], ASuccess);
  end;
end;

function TGroupCollection.GetCount: Integer;
begin
  Result := Length(FList);
end;

function TGroupCollection.GetEnumerator: TGroupCollectionEnumerator;
begin
  Result := TGroupCollectionEnumerator.Create(Self);
end;

function TGroupCollection.GetItem(const AIndex: Variant): TGroup;
var
  LIndex: Integer;
begin
  case VarType(AIndex) of
    varString, varUString, varOleStr:
      LIndex := FRegEx.GetGroupIndex(string(AIndex));
    varSmallint, varByte, varShortInt, varWord, varInteger,
    {$IFDEF DELPHI}varUInt32{$ELSE}varLongWord{$ENDIF}, varInt64, varUInt64:
      LIndex := AIndex;
  else
    raise ERegEx.CreateRes(@SRegExInvalidIndexType);
  end;

  if (LIndex >= 0) and (LIndex < Length(FList)) then
    Result := FList[LIndex]
  else
    raise ERegEx.CreateResFmt(@SRegExIndexOutOfBounds, [LIndex]);
end;

{ TGroupCollectionEnumerator }

constructor TGroupCollectionEnumerator.Create(
  const ACollection: TGroupCollection);
begin
  FCollection := ACollection;
  FIndex := -1;
end;

function TGroupCollectionEnumerator.GetCurrent: TGroup;
begin
  Result := FCollection.Item[FIndex];
end;

function TGroupCollectionEnumerator.MoveNext: Boolean;
begin
  Result := FIndex < FCollection.Count - 1;
  if Result then
    Inc(FIndex);
end;

{ TMatch }

constructor TMatch.Create(const ARegEx: IRegEx; const AValue: string;
  const AIndex, ALength: Integer; const ASuccess: Boolean);
begin
  FGroup := TGroup.Create(AValue, AIndex, ALength, ASuccess);
  FGroups := TGroupCollection.Create(ARegEx, AValue, AIndex, ALength, ASuccess);
  FRegEx := ARegEx;
end;

function TMatch.GetGroups: TGroupCollection;
begin
  Result := FGroups;
end;

function TMatch.GetIndex: Integer;
begin
  Result := FGroup.Index;
end;

function TMatch.GetLength: Integer;
begin
  Result := FGroup.Length;
end;

function TMatch.GetSuccess: Boolean;
begin
  Result := FGroup.Success;
end;

function TMatch.GetValue: string;
begin
  Result := FGroup.Value;
end;

function TMatch.NextMatch: TMatch;
var
  LSuccess: Boolean;
begin
  LSuccess := FRegEx.MatchAgain;
  if LSuccess then
    Result := TMatch.Create(FRegEx, FRegEx.Subject,
      FRegEx.MatchedOffset, FRegEx.MatchedLength, LSuccess)
  else
    Result := TMatch.Create(FRegEx, FRegEx.Subject, 0, 0, LSuccess)
end;

{ TMatchCollection }

constructor TMatchCollection.Create(const ARegEx: IRegEx; const AInput: string;
  const AStartPos: Integer);
var
  LCount: Integer;
  LResult: Boolean;
begin
  FRegEx := ARegEx;
  FRegEx.Subject := AInput;
  FRegEx.StartPos := AStartPos;
  LCount := 0;
  SetLength(FList, 0);
  LResult := FRegEx.MatchAgain;
  while LResult do
  begin
    if (LCount mod 100 = 0) then
      SetLength(FList, Length(FList) + 100);
    FList[LCount] := TMatch.Create(ARegEx, AInput, FRegEx.MatchedOffset,
      FRegEx.MatchedLength, LResult);
    LResult := FRegEx.MatchAgain;
    Inc(LCount);
  end;
  if (Length(FList) > LCount) then
    SetLength(FList, LCount);
end;

function TMatchCollection.GetCount: Integer;
begin
  Result := Length(FList);
end;

function TMatchCollection.GetEnumerator: TMatchCollectionEnumerator;
begin
  Result := TMatchCollectionEnumerator.Create(Self);
end;

function TMatchCollection.GetItem(const AIndex: Integer): TMatch;
begin
  if (AIndex >= 0) and (AIndex < Length(FList)) then
    Result := FList[AIndex]
  else
    raise ERegEx.CreateResFmt(@SRegExIndexOutOfBounds, [AIndex]);
end;

{ TMatchCollectionEnumerator }

constructor TMatchCollectionEnumerator.Create(
  const ACollection: TMatchCollection);
begin
  FCollection := ACollection;
  FIndex := -1;
end;

function TMatchCollectionEnumerator.GetCurrent: TMatch;
begin
  Result := FCollection.Item[FIndex];
end;

function TMatchCollectionEnumerator.MoveNext: Boolean;
begin
  Result := FIndex < FCollection.Count - 1;
  if Result then
    Inc(FIndex);
end;

{ TRegEx }

constructor TRegEx.Create(const APattern: string);
begin
  {$IFDEF DELPHI}
  FRegEx := TPerlRegEx.Create;
  {$ELSE}
  FRegEx := TRegExpr.Create(APattern);
  {$ENDIF}

  FStartPos := 1;
  FOptions := [roIgnoreCase];
  UpdateOptions;

  SetPattern(APattern);
end;

constructor TRegEx.Create;
begin
  Create('');
end;

destructor TRegEx.Destroy;
begin
  FreeAndNil(FRegEx);

  inherited;
end;

function TRegEx.GetGroupCount: Integer;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.GroupCount;
  {$ELSE}
  Result := FRegEx.SubExprMatchCount;
  {$ENDIF}
end;

function TRegEx.GetGroupIndex(const AGroupName: string): Integer;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.NamedGroup(AGroupName);
  {$ELSE}
  Result := FRegEx.MatchIndexFromName(AGroupName);
  {$ENDIF}
end;

function TRegEx.GetGroupLengths(const AIndex: Integer): Integer;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.GroupLengths[AIndex];
  {$ELSE}
  Result := FRegEx.MatchLen[AIndex];
  {$ENDIF}
end;

function TRegEx.GetGroupOffsets(const AIndex: Integer): Integer;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.GroupOffsets[AIndex];
  {$ELSE}
  Result := FRegEx.MatchPos[AIndex];
  {$ENDIF}
end;

function TRegEx.GetGroups(const AIndex: Integer): string;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.Groups[AIndex];
  {$ELSE}
  Result := FRegEx.Match[AIndex];
  {$ENDIF}
end;

function TRegEx.GetMatchedLength: Integer;
begin
  Result := GetGroupLengths(0);
end;

function TRegEx.GetMatchedOffset: Integer;
begin
  Result := GetGroupOffsets(0);
end;

function TRegEx.GetMatchedText: string;
begin
  Result := GetGroups(0);
end;

function TRegEx.GetOptions: TRegExOptions;
begin
  Result := FOptions;
end;

function TRegEx.GetPattern: string;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.RegEx;
  {$ELSE}
  Result := FRegEx.Expression;
  {$ENDIF}
end;

function TRegEx.GetStartPos: Integer;
begin
  Result := FStartPos;
end;

function TRegEx.GetSubject: string;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.Subject;
  {$ELSE}
  Result := FRegEx.InputString;
  {$ENDIF}
end;

class function TRegEx.IsMatch(const AInput, APattern: string;
  const AOptions: TRegExOptions; const AStartPos: Integer): Boolean;
var
  LRegEx: IRegEx;
begin
  LRegEx := TRegEx.Create(APattern);
  LRegEx.Subject := AInput;
  LRegEx.StartPos := AStartPos;
  LRegEx.Options := AOptions;
  Result := LRegEx.Match;
end;

class function TRegEx.IsMatch(const AInput, APattern: string;
  const AOptions: TRegExOptions): Boolean;
begin
  Result := IsMatch(AInput, APattern, AOptions, 1);
end;

class function TRegEx.IsMatch(const AInput, APattern: string; const AStartPos: Integer): Boolean;
begin
  Result := IsMatch(AInput, APattern, [roIgnoreCase], AStartPos);
end;

class function TRegEx.IsMatch(const AInput, APattern: string): Boolean;
begin
  Result := IsMatch(AInput, APattern, 1);
end;

class function TRegEx.Match(const AInput, APattern: string;
  const AOptions: TRegExOptions; const AStartPos: Integer): TMatch;
var
  LRegEx: IRegEx;
  LSuccess: Boolean;
begin
  LRegEx := TRegEx.Create(APattern);
  LRegEx.Subject := AInput;
  LRegEx.StartPos := AStartPos;
  LRegEx.Options := AOptions;
  LSuccess := LRegEx.Match;
  if LSuccess then
    Result := TMatch.Create(LRegEx, LRegEx.Subject,
      LRegEx.MatchedOffset, LRegEx.MatchedLength, LSuccess)
  else
    Result := TMatch.Create(LRegEx, LRegEx.Subject, 0, 0, LSuccess);
end;

class function TRegEx.Match(const AInput, APattern: string;
  const AOptions: TRegExOptions): TMatch;
begin
  Result := Match(AInput, APattern, AOptions, 1);
end;

class function TRegEx.Match(const AInput, APattern: string; const AStartPos: Integer): TMatch;
begin
  Result := Match(AInput, APattern, [roIgnoreCase], AStartPos);
end;

class function TRegEx.Match(const AInput, APattern: string): TMatch;
begin
  Result := Match(AInput, APattern, 1);
end;

function TRegEx.Match: Boolean;
begin
  {$IFDEF DELPHI}
  FRegEx.Start := FStartPos;
  Result := FRegEx.MatchAgain; // MatchAgain 才会处理 StartPos
  {$ELSE}
  Result := FRegEx.ExecPos(FStartPos);
  {$ENDIF}
end;

function TRegEx.MatchAgain: Boolean;
begin
  {$IFDEF DELPHI}
  Result := FRegEx.MatchAgain;
  {$ELSE}
  Result := FRegEx.ExecNext;
  {$ENDIF}
end;

class function TRegEx.Matches(const AInput, APattern: string;
  const AOptions: TRegExOptions; const AStartPos: Integer): TMatchCollection;
var
  LRegEx: IRegEx;
begin
  LRegEx := TRegEx.Create(APattern);
  LRegEx.Subject := AInput;
  LRegEx.StartPos := AStartPos;
  LRegEx.Options := AOptions;

  Result := TMatchCollection.Create(LRegEx, AInput, AStartPos);
end;

class function TRegEx.Matches(const AInput, APattern: string;
  const AOptions: TRegExOptions): TMatchCollection;
begin
  Result := Matches(AInput, APattern, AOptions, 1);
end;

class function TRegEx.Matches(const AInput, APattern: string;
  const AStartPos: Integer): TMatchCollection;
begin
  Result := Matches(AInput, APattern, [roIgnoreCase], AStartPos);
end;

class function TRegEx.Matches(const AInput, APattern: string): TMatchCollection;
begin
  Result := Matches(AInput, APattern, 1);
end;

function TRegEx.Replace(const AEvaluator: TMatchEvaluator;
  const ACount: Integer): string;
var
  LRegEx: IRegEx;
  LMatch: TMatch;
  LPrevPos: Integer;
  I: Integer;
  LReplaceStr: string;
begin
  Result := '';
  LPrevPos := 1;

  if Assigned(AEvaluator) and Match then
  begin
    LRegEx := Self;
    I := 0;

    while True do
    begin
      Result := Result + System.Copy(
        Self.Subject,
        LPrevPos,
        Self.MatchedOffset - LPrevPos);

      LMatch := TMatch.Create(LRegEx, Self.Subject,
        Self.MatchedOffset, Self.MatchedLength, True);
      LReplaceStr := AEvaluator(LMatch);

      {$IFDEF FPC}
      Result := Result + FRegEx.Substitute(LReplaceStr);
      {$ELSE}
      FRegEx.Replacement := LReplaceStr;
      Result := Result + FRegEx.ComputeReplacement;
      {$ENDIF}

      LPrevPos := Self.MatchedOffset + Self.MatchedLength;

      Inc(I);

      if ((ACount > 0) and (I >= ACount))
        or (not MatchAgain) then
        Break;
    end;
  end;

  Result := Result + System.Copy(Self.Subject, LPrevPos, MaxInt);
end;

function TRegEx.Replace(const AReplacement: string;
  const ACount: Integer): string;
begin
  Result := Replace(
    function(const AMatch: TMatch): string
    begin
      Result := AReplacement;
    end,
    ACount);
end;

function TRegEx.Replace(const AEvaluator: TMatchEvaluator): string;
begin
  Result := Replace(AEvaluator, -1);
end;

function TRegEx.Replace(const AReplacement: string): string;
begin
  Result := Replace(AReplacement, -1);
end;

class function TRegEx.Replace(const AInput, APattern, AReplacement: string;
  const AOptions: TRegExOptions; const ACount, AStartPos: Integer): string;
var
  LRegEx: IRegEx;
begin
  LRegEx := TRegEx.Create(APattern);
  LRegEx.Subject := AInput;
  LRegEx.StartPos := AStartPos;
  LRegEx.Options := AOptions;

  Result := LRegEx.Replace(AReplacement, ACount);
end;

class function TRegEx.Replace(const AInput, APattern, AReplacement: string;
  const AOptions: TRegExOptions; const ACount: Integer): string;
begin
  Result := Replace(AInput, APattern, AReplacement, AOptions, ACount, 1);
end;

class function TRegEx.Replace(const AInput, APattern, AReplacement: string;
  const AOptions: TRegExOptions): string;
begin
  Result := Replace(AInput, APattern, AReplacement, AOptions, -1, 1);
end;

class function TRegEx.Replace(const AInput, APattern, AReplacement: string;
  const ACount, AStartPos: Integer): string;
begin
  Result := Replace(AInput, APattern, AReplacement, [roIgnoreCase], ACount, AStartPos);
end;

class function TRegEx.Replace(const AInput, APattern, AReplacement: string;
  const ACount: Integer): string;
begin
  Result := Replace(AInput, APattern, AReplacement, ACount, 1);
end;

class function TRegEx.Replace(const AInput, APattern,
  AReplacement: string): string;
begin
  Result := Replace(AInput, APattern, AReplacement, -1, 1);
end;

class function TRegEx.Replace(const AInput, APattern: string;
  const AEvaluator: TMatchEvaluator; const AOptions: TRegExOptions;
  const ACount, AStartPos: Integer): string;
var
  LRegEx: IRegEx;
begin
  LRegEx := TRegEx.Create(APattern);
  LRegEx.Subject := AInput;
  LRegEx.StartPos := AStartPos;
  LRegEx.Options := AOptions;

  Result := LRegEx.Replace(AEvaluator, ACount);
end;

class function TRegEx.Replace(const AInput, APattern: string;
  const AEvaluator: TMatchEvaluator; const AOptions: TRegExOptions;
  const ACount: Integer): string;
begin
  Result := Replace(AInput, APattern, AEvaluator, AOptions, ACount, 1);
end;

class function TRegEx.Replace(const AInput, APattern: string;
  const AEvaluator: TMatchEvaluator; const AOptions: TRegExOptions): string;
begin
  Result := Replace(AInput, APattern, AEvaluator, AOptions, -1, 1);
end;

class function TRegEx.Replace(const AInput, APattern: string;
  const AEvaluator: TMatchEvaluator; const ACount, AStartPos: Integer): string;
begin
  Result := Replace(AInput, APattern, AEvaluator, [roIgnoreCase], ACount, AStartPos);
end;

class function TRegEx.Replace(const AInput, APattern: string;
  const AEvaluator: TMatchEvaluator; const ACount: Integer): string;
begin
  Result := Replace(AInput, APattern, AEvaluator, ACount, -1);
end;

class function TRegEx.Replace(const AInput, APattern: string;
  const AEvaluator: TMatchEvaluator): string;
begin
  Result := Replace(AInput, APattern, AEvaluator, -1, 1);
end;

procedure TRegEx.SetOptions(const AValue: TRegExOptions);
begin
  if (FOptions = AValue) then Exit;

  FOptions := AValue;
  UpdateOptions;
end;

procedure TRegEx.SetPattern(const AValue: string);
begin
  {$IFDEF DELPHI}
  FRegEx.RegEx := AValue;
  {$ELSE}
  FRegEx.Expression := AValue;
  {$ENDIF}
end;

procedure TRegEx.SetStartPos(const AValue: Integer);
begin
  FStartPos := AValue;
end;

procedure TRegEx.SetSubject(const AValue: string);
begin
  {$IFDEF DELPHI}
  FRegEx.Subject := AValue;
  {$ELSE}
  FRegEx.InputString := AValue;
  {$ENDIF}
end;

function TRegEx.Split(const ACount: Integer): TArray<string>;
var
  LPrevPos: Integer;
  I: Integer;
  LSplitedStr: string;
begin
  Result := [];
  LPrevPos := 1;

  if Match then
  begin
    I := 0;

    while True do
    begin
      LSplitedStr := System.Copy(
        Self.Subject,
        LPrevPos,
        Self.MatchedOffset - LPrevPos);

      LPrevPos := Self.MatchedOffset + Self.MatchedLength;

      if (LSplitedStr <> '') or not (roNotEmpty in FOptions) then
      begin
        Result := Result + [LSplitedStr];
        Inc(I);
      end;

      if ((ACount > 0) and (I >= ACount))
        or (not MatchAgain) then
        Break;
    end;
  end;

  LSplitedStr := System.Copy(Self.Subject, LPrevPos, MaxInt);
  if (LSplitedStr <> '') or not (roNotEmpty in FOptions) then
    Result := Result + [LSplitedStr];
end;

function TRegEx.Split: TArray<string>;
begin
  Result := Split(-1);
end;

class function TRegEx.Split(const AInput, APattern: string;
  const AOptions: TRegExOptions; const ACount,
  AStartPos: Integer): TArray<string>;
var
  LRegEx: IRegEx;
begin
  LRegEx := TRegEx.Create(APattern);
  LRegEx.Subject := AInput;
  LRegEx.StartPos := AStartPos;
  LRegEx.Options := AOptions;

  Result := LRegEx.Split(ACount);
end;

class function TRegEx.Split(const AInput, APattern: string;
  const AOptions: TRegExOptions; const ACount: Integer): TArray<string>;
begin
  Result := Split(AInput, APattern, AOptions, ACount, 1);
end;

class function TRegEx.Split(const AInput, APattern: string;
  const AOptions: TRegExOptions): TArray<string>;
begin
  Result := Split(AInput, APattern, AOptions, -1, 1);
end;

class function TRegEx.Split(const AInput, APattern: string; const ACount,
  AStartPos: Integer): TArray<string>;
begin
  Result := Split(AInput, APattern, [roIgnoreCase], ACount, AStartPos);
end;

class function TRegEx.Split(const AInput, APattern: string;
  const ACount: Integer): TArray<string>;
begin
  Result := Split(AInput, APattern, ACount, 1);
end;

class function TRegEx.Split(const AInput, APattern: string): TArray<string>;
begin
  Result := Split(AInput, APattern, -1, 1);
end;

procedure TRegEx.UpdateOptions;
begin
  {$IFDEF DELPHI}
  if (roIgnoreCase in FOptions) then
    FRegEx.Options := FRegEx.Options + [preCaseLess];
  if (roMultiLine in FOptions) then
    FRegEx.Options := FRegEx.Options + [preMultiLine];
  if (roSingleLine in FOptions) then
    FRegEx.Options := FRegEx.Options + [preSingleLine];
  if (roExtended in FOptions) then
    FRegEx.Options := FRegEx.Options + [preExtended];
  {$ELSE}
  FRegEx.ModifierI := roIgnoreCase in FOptions;
  FRegEx.ModifierS := roSingleLine in FOptions;
  FRegEx.ModifierM := roMultiLine in FOptions;
  FRegEx.ModifierX := roExtended in FOptions;
  {$ENDIF}
end;

end.
