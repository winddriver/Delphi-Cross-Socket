unit Utils.ArrayUtils;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,
  Generics.Defaults,
  Math,
  Rtti,
  TypInfo,

  {$IFDEF FPC}
  DTF.Types,
  DTF.Generics,
  {$ENDIF}

  Utils.Rtti;

type
  TArrayUtils<T> = class
  public type
    IArrayComparer = IComparer<T>;

    // reference to function(const Left, Right: T): Integer
    TArrayComparison = {$IFDEF DELPHI}TComparison<T>{$ELSE}TComparisonAnonymousFunc<T>{$ENDIF};

    // TDelegatedComparer<T> = class(TComparer<T>)
    TArrayComparer = {$IFDEF DELPHI}TDelegatedComparer<T>{$ELSE}TDelegatedComparerAnonymousFunc<T>{$ENDIF};
  public
    class procedure Sort(var AArray: array of T; const AComparer: IArrayComparer; AIndex, ACount: Integer); overload; static;
    class procedure Sort(var AArray: array of T; const AComparer: IArrayComparer); overload; static;

    class procedure Sort(var AArray: array of T; const AComparison: TArrayComparison; AIndex, ACount: Integer); overload; static;
    class procedure Sort(var AArray: array of T; const AComparison: TArrayComparison); overload; static;

    class procedure Sort(var AArray: array of T); overload; static;
    class procedure SortRandom(var AArray: array of T); static;

    class function BinarySearch(const AArray: array of T; const AItem: T;
      out AFoundIndex: Integer; const AComparer: IArrayComparer;
      AIndex, ACount: Integer): Boolean; overload; static;
    class function BinarySearch(const AArray: array of T; const AItem: T;
      out AFoundIndex: Integer; const AComparer: IArrayComparer): Boolean; overload; static;
    class function BinarySearch(const AArray: array of T; const AItem: T;
      out AFoundIndex: Integer): Boolean; overload; static;

    class procedure Copy(const AFromValues: array of T; var AToValues: array of T;
      AFromIndex, AToIndex, ACount: Integer); overload; static;
    class procedure Copy(const AFromValues: array of T; var AToValues: array of T; ACount: Integer); overload; static;
    class function Copy(const AArray: array of T; AIndex, ACount: Integer): TArray<T>; overload; static;

    class function Clone(const AArray: array of T): TArray<T>; static;
    class procedure Move(var AArray: array of T; AFromIndex, AToIndex, ACount: Integer); static;

    class procedure Insert(var AArray: TArray<T>; AIndex: Integer; const AItem: T); overload; static;
    class procedure Insert(var AArray: TArray<T>; AIndex: Integer; const AItems: array of T); overload; static;

    class procedure Append(var AArray: TArray<T>; const AItem: T); overload; static;
    class procedure Append(var AArray: TArray<T>; const AItems: array of T); overload; static;

    class procedure Remove(var AArray: TArray<T>; AIndex, ACount: Integer); overload; static;
    class procedure Remove(var AArray: TArray<T>; AIndex: Integer); overload; static;

    class procedure RemoveItem(var AArray: TArray<T>; const AItem: T); overload; static;
    class procedure RemoveItem(var AArray: TArray<T>; const AItems: array of T); overload; static;

    class function Concat(const AArrOfArr: array of TArray<T>): TArray<T>; overload; static;
    class function Concat(const AArray1, AArray2: TArray<T>): TArray<T>; overload; static;

    class function Union(const AArray1, AArray2: array of T;
      AComparison: TArrayComparison = nil): TArray<T>; static;

    class function Uniq(const AArray: array of T;
      AComparison: TArrayComparison = nil): TArray<T>; static;

    class function Intersection(const AArray1, AArray2: array of T;
      AComparison: TArrayComparison = nil): TArray<T>; static;

    class function IndexOf(const AArray: array of T; const AItem: T;
      AComparison: TArrayComparison; AIndex, ACount: Integer): Integer; overload; static;
    class function IndexOf(const AArray: array of T; const AItem: T;
      AComparison: TArrayComparison): Integer; overload; static;
    class function IndexOf(const AArray: array of T; const AItem: T): Integer; overload; static;

    class function IndexOfNoSort(const AArray: array of T; const AItem: T;
      AComparison: TArrayComparison; AIndex, ACount: Integer): Integer; overload; static;
    class function IndexOfNoSort(const AArray: array of T; const AItem: T;
      AComparison: TArrayComparison): Integer; overload; static;
    class function IndexOfNoSort(const AArray: array of T; const AItem: T): Integer; overload; static;

    class function Exists(const AArray: array of T; const AItem: T;
      AComparison: TArrayComparison = nil): Boolean; static;

    class function IsEqual(const AArray1, AArray2: array of T;
      AComparison: TArrayComparison): Boolean; overload; static;
    class function IsEqual(const AArray1, AArray2: array of T): Boolean; overload; static;

    class function Join(const AArray: array of T; const ADelimiter: string = ','): string; static;
    class function Split(const S: string; const ADelimiter: string = ','): TArray<T>; static;
  end;

implementation

{ TArrayUtils }

class procedure TArrayUtils<T>.Copy(const AFromValues: array of T;
  var AToValues: array of T; AFromIndex, AToIndex, ACount: Integer);
begin
  if (AFromIndex > High(AFromValues)) or (AToIndex > High(AToValues)) or (ACount = 0) then Exit;

  if (ACount < 0) then
    ACount := Min(Length(AFromValues) - AFromIndex, Length(AToValues) - AToIndex)
  else
  begin
    if (Length(AFromValues) - AFromIndex < ACount) then
      ACount := Length(AFromValues) - AFromIndex;
    if (Length(AToValues) - AToIndex < ACount) then
      ACount := Length(AToValues) - AToIndex;
  end;

  if (ACount <= 0) then Exit;

  if IsManagedType(T) then
    System.CopyArray(Pointer(@AToValues[AToIndex]), Pointer(@AFromValues[AFromIndex]), TypeInfo(T), ACount)
  else
    System.Move(Pointer(@AFromValues[AFromIndex])^, Pointer(@AToValues[AToIndex])^, ACount * SizeOf(T));
end;

class function TArrayUtils<T>.Copy(const AArray: array of T; AIndex,
  ACount: Integer): TArray<T>;
begin
  if (ACount = 0) then Exit(nil);

  if (ACount < 0) then
    ACount := Length(AArray) - AIndex
  else
  begin
    if (Length(AArray) - AIndex < ACount) then
      ACount := Length(AArray) - AIndex;
  end;

  if (ACount <= 0) then Exit(nil);

  SetLength(Result, ACount);
  Copy(AArray, Result, AIndex, 0, ACount);
end;

class procedure TArrayUtils<T>.Copy(const AFromValues: array of T;
  var AToValues: array of T; ACount: Integer);
begin
  Copy(AFromValues, AToValues, 0, 0, ACount);
end;

class function TArrayUtils<T>.Clone(const AArray: array of T): TArray<T>;
begin
  Result := Copy(AArray, 0, Length(AArray));
end;

class function TArrayUtils<T>.Concat(const AArrOfArr: array of TArray<T>): TArray<T>;
var
  I, LOut, LLen: Integer;
begin
  LLen := 0;
  for I := 0 to High(AArrOfArr) do
    LLen := LLen + Length(AArrOfArr[I]);
  SetLength(Result, LLen);
  LOut := 0;
  for I := 0 to High(AArrOfArr) do
  begin
    LLen := Length(AArrOfArr[I]);
    if (LLen > 0) then
    begin
      Copy(AArrOfArr[I], Result, 0, LOut, LLen);
      Inc(LOut, LLen);
    end;
  end;
end;

class function TArrayUtils<T>.Concat(const AArray1,
  AArray2: TArray<T>): TArray<T>;
begin
  Result := Concat([AArray1, AArray2]);
end;

class function TArrayUtils<T>.Exists(const AArray: array of T;
  const AItem: T; AComparison: TArrayComparison): Boolean;
begin
  Result := (IndexOfNoSort(AArray, AItem, AComparison) >= 0);
end;

class procedure TArrayUtils<T>.Move(var AArray: array of T; AFromIndex, AToIndex,
  ACount: Integer);
var
  I: Integer;
begin
  if (AFromIndex = AToIndex) or (AFromIndex > High(AArray)) or (AToIndex > High(AArray)) or (ACount = 0) then Exit;

  if (ACount < 0) then
    ACount := Min(Length(AArray) - AFromIndex, Length(AArray) - AToIndex)
  else
  begin
    if (ACount > Length(AArray) - AFromIndex) then
      ACount := Length(AArray) - AFromIndex;
    if (ACount > Length(AArray) - AToIndex) then
      ACount := Length(AArray) - AToIndex;
  end;

  if (ACount <= 0) then Exit;

  if (AFromIndex < AToIndex) then
  begin
    for I := ACount - 1 downto 0 do
      AArray[AToIndex + I] := AArray[AFromIndex + I]
  end else
  begin
    for I := 0 to ACount - 1 do
      AArray[AToIndex + I] := AArray[AFromIndex + I];
  end;
end;

class procedure TArrayUtils<T>.Insert(var AArray: TArray<T>; AIndex: Integer;
  const AItem: T);
begin
  if (AIndex > Length(AArray)) or (AIndex < 0) then Exit;

  SetLength(AArray, Length(AArray) + 1);
  Move(AArray, AIndex, AIndex + 1, Length(AArray) - AIndex);
  AArray[AIndex] := AItem;
end;

class procedure TArrayUtils<T>.Insert(var AArray: TArray<T>; AIndex: Integer;
  const AItems: array of T);
var
  I: Integer;
begin
  SetLength(AArray, Length(AArray) + Length(AItems));
  Move(AArray, AIndex, AIndex + Length(AItems), Length(AArray) - AIndex);
  for I := Low(AItems) to High(AItems) do
    AArray[AIndex + I] := AItems[I];
end;

class function TArrayUtils<T>.Intersection(const AArray1,
  AArray2: array of T; AComparison: TArrayComparison): TArray<T>;
var
  I: Integer;
  LItem: T;
begin
  I := 0;
  SetLength(Result, Length(AArray1));

  for LItem in AArray1 do
  begin
    if Exists(AArray2, LItem, AComparison) then
    begin
      Result[I] := LItem;
      Inc(I);
    end;
  end;

  SetLength(Result, I);
end;

class procedure TArrayUtils<T>.Append(var AArray: TArray<T>; const AItem: T);
begin
  Insert(AArray, Length(AArray), AItem);
end;

class procedure TArrayUtils<T>.Append(var AArray: TArray<T>;
  const AItems: array of T);
begin
  Insert(AArray, Length(AArray), AItems);
end;

class function TArrayUtils<T>.BinarySearch(const AArray: array of T;
  const AItem: T; out AFoundIndex: Integer; const AComparer: IArrayComparer; AIndex,
  ACount: Integer): Boolean;
{$IFDEF DELPHI}
begin
	Result := TArray.BinarySearch<T>(AArray, AItem, AFoundIndex, AComparer, AIndex, ACount);
end;
{$ELSE}
var
  LFoundIndex: SizeInt;
begin
  Result := TArrayHelper<T>.BinarySearch(AArray, AItem, LFoundIndex, AComparer, AIndex, ACount);
  AFoundIndex := Integer(LFoundIndex);
end;
{$ENDIF}

class function TArrayUtils<T>.BinarySearch(const AArray: array of T;
  const AItem: T; out AFoundIndex: Integer;
  const AComparer: IArrayComparer): Boolean;
begin
  Result := BinarySearch(AArray, AItem, AFoundIndex, AComparer, 0, Length(AArray));
end;

class function TArrayUtils<T>.BinarySearch(const AArray: array of T;
  const AItem: T; out AFoundIndex: Integer): Boolean;
begin
  Result := BinarySearch(AArray, AItem, AFoundIndex, TArrayComparer.Default, 0, Length(AArray));
end;

class procedure TArrayUtils<T>.Remove(var AArray: TArray<T>; AIndex,
  ACount: Integer);
var
  LSize, LLeft: Integer;
begin
  if (ACount <= 0) then Exit;

  LSize := Length(AArray);
  if (AIndex >= LSize) then Exit;

  LLeft := LSize - AIndex;
  if (ACount > LLeft) then
    ACount := LLeft;

  Move(AArray, AIndex + ACount, AIndex, Length(AArray) - (AIndex + ACount));
  SetLength(AArray, Length(AArray) - ACount);
end;

class procedure TArrayUtils<T>.Remove(var AArray: TArray<T>; AIndex: Integer);
begin
  Remove(AArray, AIndex, 1);
end;

class procedure TArrayUtils<T>.RemoveItem(var AArray: TArray<T>;
  const AItems: array of T);
var
  LItem: T;
begin
  for LItem in AItems do
    RemoveItem(AArray, LItem);
end;

class procedure TArrayUtils<T>.RemoveItem(var AArray: TArray<T>;
  const AItem: T);
var
  I: Integer;
begin
  while True do
  begin
    I := IndexOfNoSort(AArray, AItem);
    if (I < 0) then Break;

    Remove(AArray, I, 1);
  end;
end;

class function TArrayUtils<T>.IndexOf(const AArray: array of T; const AItem: T;
  AComparison: TArrayComparison; AIndex, ACount: Integer): Integer;
var
  LComparer: IComparer<T>;
begin
  Result := -1;

  if (AIndex < 0) or (ACount > Length(AArray)) then Exit;

  if Assigned(AComparison) then
    LComparer := TArrayComparer.Create(AComparison)
  else
    LComparer := TArrayComparer.Default;
  if not BinarySearch(AArray, AItem, Result, LComparer, AIndex, ACount) then
    Result := -1;
end;

class function TArrayUtils<T>.IndexOf(const AArray: array of T; const AItem: T;
  AComparison: TArrayComparison): Integer;
begin
  Result := IndexOf(AArray, AItem, AComparison, Low(AArray), Length(AArray));
end;

class function TArrayUtils<T>.IndexOf(const AArray: array of T;
  const AItem: T): Integer;
begin
  Result := IndexOf(AArray, AItem, nil);
end;

class function TArrayUtils<T>.IndexOfNoSort(const AArray: array of T;
  const AItem: T; AComparison: TArrayComparison; AIndex, ACount: Integer): Integer;
var
  LComparer: IComparer<T>;
  I: Integer;
begin
  Result := -1;

  if (AIndex < 0) or (ACount > Length(AArray)) then Exit;

  if Assigned(AComparison) then
    LComparer := TArrayComparer.Create(AComparison)
  else
    LComparer := TArrayComparer.Default;

  for I := AIndex to AIndex + ACount - 1 do
    if (LComparer.Compare(AArray[I], AItem) = 0) then Exit(I);
end;

class function TArrayUtils<T>.IndexOfNoSort(const AArray: array of T;
  const AItem: T; AComparison: TArrayComparison): Integer;
begin
  Result := IndexOfNoSort(AArray, AItem, AComparison, Low(AArray), Length(AArray));
end;

class function TArrayUtils<T>.IndexOfNoSort(const AArray: array of T;
  const AItem: T): Integer;
begin
  Result := IndexOfNoSort(AArray, AItem, nil);
end;

class function TArrayUtils<T>.IsEqual(const AArray1, AArray2: array of T;
  AComparison: TArrayComparison): Boolean;
var
  LComparer: IComparer<T>;
  I: Integer;
begin
  if (Length(AArray1) <> Length(AArray2)) then Exit(False);

  if Assigned(AComparison) then
    LComparer := TArrayComparer.Create(AComparison)
  else
    LComparer := TArrayComparer.Default;

  for I := Low(AArray1) to High(AArray1) do
    if (LComparer.Compare(AArray1[I], AArray2[I]) <> 0) then Exit(False);

  Result := True;
end;

class function TArrayUtils<T>.IsEqual(const AArray1,
  AArray2: array of T): Boolean;
begin
  Result := IsEqual(AArray1, AArray2, nil);
end;

class function TArrayUtils<T>.Join(const AArray: array of T;
  const ADelimiter: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AArray) do
  begin
    if (I > 0) then
      Result := Result + ADelimiter;
    Result := Result + (TValue.From<T>(AArray[I]).ToString);
  end;
end;

class procedure TArrayUtils<T>.Sort(var AArray: array of T;
  const AComparer: IArrayComparer; AIndex, ACount: Integer);
var
  LComparer: IArrayComparer;
begin
  if Assigned(AComparer) then
    LComparer := AComparer
  else
    LComparer := TArrayComparer.Default;

  {$IFDEF DELPHI}
  TArray.Sort<T>(AArray, LComparer, AIndex, ACount);
  {$ELSE}
  TArrayHelper<T>.Sort(AArray, LComparer, AIndex, ACount);
  {$ENDIF}
end;

class procedure TArrayUtils<T>.Sort(var AArray: array of T;
  const AComparer: IArrayComparer);
begin
  Sort(AArray, AComparer, 0, Length(AArray));
end;

class procedure TArrayUtils<T>.Sort(var AArray: array of T);
begin
  Sort(AArray, TArrayComparer.Default, 0, Length(AArray));
end;

class procedure TArrayUtils<T>.Sort(var AArray: array of T;
  const AComparison: TArrayComparison; AIndex, ACount: Integer);
var
  LComparer: IArrayComparer;
begin
  if Assigned(AComparison) then
    LComparer := TArrayComparer.Create(AComparison)
  else
    LComparer := TArrayComparer.Default;

  Sort(AArray, LComparer, AIndex, ACount);
end;

class procedure TArrayUtils<T>.Sort(var AArray: array of T;
  const AComparison: TArrayComparison);
begin
  Sort(AArray, AComparison, 0, Length(AArray));
end;

class procedure TArrayUtils<T>.SortRandom(var AArray: array of T);
begin
  Sort(AArray,
    function(const ALeft, ARight: T): Integer
    begin
      Exit(RandomRange(-1, 1 + 1));
    end);
end;

class function TArrayUtils<T>.Split(const S, ADelimiter: string): TArray<T>;
var
  LStrArray: TArray<string>;
  I: Integer;
begin
  LStrArray := S.Split([ADelimiter], TStringSplitOptions.ExcludeEmpty);
  SetLength(Result, Length(LStrArray));
  for I := Low(LStrArray) to High(LStrArray) do
    Result[I] := TRttiUtils.StrToType<T>(LStrArray[I]);
end;

class function TArrayUtils<T>.Union(const AArray1, AArray2: array of T;
  AComparison: TArrayComparison): TArray<T>;
var
  LLen1, LLen2, I: Integer;
  LItem: T;
begin
  LLen1 := Length(AArray1);
  LLen2 := Length(AArray2);
  SetLength(Result, LLen1 + LLen2);
  Copy(AArray1, Result, 0, 0, LLen1);
  I := Length(AArray1);

  for LItem in AArray2 do
  begin
    if (IndexOfNoSort(Result, LItem, AComparison, 0, LLen1) < 0) then
    begin
      Result[I] := LItem;
      Inc(I);
    end;
  end;

  SetLength(Result, I);
end;

class function TArrayUtils<T>.Uniq(const AArray: array of T;
  AComparison: TArrayComparison): TArray<T>;
var
  I: Integer;
  LItem: T;
begin
  I := 0;
  SetLength(Result, Length(AArray));

  for LItem in AArray do
  begin
    if (IndexOfNoSort(Result, LItem, AComparison, 0, I) < 0) then
    begin
      Result[I] := LItem;
      Inc(I);
    end;
  end;

  SetLength(Result, I);
end;

end.
