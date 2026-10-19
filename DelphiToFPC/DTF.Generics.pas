unit DTF.Generics;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils,
  Generics.Collections,
  Generics.Defaults,

  DTF.Types;

type
  {$IFDEF FPC}
  // FPC TQueue 搬移托管元素后未清空旧尾槽；仅补齐引用释放，不改变队列语义。
  TFpcQueue<T> = class(TQueue<T>)
  protected
    function PrepareAddingItem: SizeInt; override;
    procedure SetCapacity(AValue: SizeInt); override;
  end;
  {$ENDIF}

  TComparisonAnonymousFunc<T> = reference to function(const ALeft, ARight: T): Integer;

  TDelegatedComparerAnonymousFunc<T> = class(TComparer<T>)
  private
    FComparison: TComparisonAnonymousFunc<T>;
  public
    function Compare(const ALeft, ARight: T): Integer; override;
    constructor Create(AComparison: TComparisonAnonymousFunc<T>);
  end;

implementation

{$IFDEF FPC}
function TFpcQueue<T>.PrepareAddingItem: SizeInt;
var
  LOldLength, I: SizeInt;
begin
  LOldLength := FLength;
  Result := inherited PrepareAddingItem;
  if IsManagedType(T) and (FLength < LOldLength) then
    for I := FLength to LOldLength - 1 do
      FItems[I] := Default(T);
end;

procedure TFpcQueue<T>.SetCapacity(AValue: SizeInt);
var
  I: SizeInt;
begin
  inherited SetCapacity(AValue);
  if IsManagedType(T) then
    for I := FLength to High(FItems) do
      FItems[I] := Default(T);
end;
{$ENDIF}

{ TDelegatedComparerAnonymousFunc<T> }

function TDelegatedComparerAnonymousFunc<T>.Compare(const ALeft,
  ARight: T): Integer;
begin
  Result := FComparison(ALeft, ARight);
end;

constructor TDelegatedComparerAnonymousFunc<T>.Create(
  AComparison: TComparisonAnonymousFunc<T>);
begin
  FComparison := AComparison;
end;

end.

