unit DTF.Generics;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils,
  Generics.Defaults,

  DTF.Types;

type
  TComparisonAnonymousFunc<T> = reference to function(const ALeft, ARight: T): Integer;

  TDelegatedComparerAnonymousFunc<T> = class(TComparer<T>)
  private
    FComparison: TComparisonAnonymousFunc<T>;
  public
    function Compare(const ALeft, ARight: T): Integer; override;
    constructor Create(AComparison: TComparisonAnonymousFunc<T>);
  end;

implementation

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

