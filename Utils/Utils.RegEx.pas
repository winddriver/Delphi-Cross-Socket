{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Utils.RegEx;

interface

uses
  System.RegularExpressions, System.RegularExpressionsCore;

type
  TMatchEvaluatorProc = reference to function(const AMatch: TMatch): string;

  IScopeEvaluator = interface
    function GetMatchEvaluator: TMatchEvaluator;

    property MatchEvaluator: TMatchEvaluator read GetMatchEvaluator;
  end;

  TScopeEvaluator = class(TInterfacedObject, IScopeEvaluator)
  private
    FMatchEvaluatorProc: TMatchEvaluatorProc;

    function MatchEvaluator(const AMatch: TMatch): string;
    function GetMatchEvaluator: TMatchEvaluator;
  public
    constructor Create(AMatchEvaluatorProc: TMatchEvaluatorProc);
  end;

  TRegExHelper = record helper for TRegEx
    function Replace(const AInput: string; AEvaluator: TMatchEvaluatorProc): string; overload;
    function Replace(const AInput: string; AEvaluator: TMatchEvaluatorProc; ACount: Integer): string; overload;
    class function Replace(const AInput, APattern: string; AEvaluator: TMatchEvaluatorProc): string; overload; static;
    class function Replace(const AInput, APattern: string; AEvaluator: TMatchEvaluatorProc; AOptions: TRegExOptions): string; overload; static;
  end;

implementation

{ TScopeEvaluator }

constructor TScopeEvaluator.Create(AMatchEvaluatorProc: TMatchEvaluatorProc);
begin
  FMatchEvaluatorProc := AMatchEvaluatorProc;
end;

function TScopeEvaluator.GetMatchEvaluator: TMatchEvaluator;
begin
  Result := Self.MatchEvaluator;
end;

function TScopeEvaluator.MatchEvaluator(const AMatch: TMatch): string;
begin
  if Assigned(FMatchEvaluatorProc) then
    Result := FMatchEvaluatorProc(AMatch);
end;

{ TRegExHelper }

function TRegExHelper.Replace(const AInput: string;
  AEvaluator: TMatchEvaluatorProc; ACount: Integer): string;
var
  LScopeEvaluator: IScopeEvaluator;
begin
  LScopeEvaluator := TScopeEvaluator.Create(AEvaluator);
  Result := Self.Replace(AInput, LScopeEvaluator.MatchEvaluator, ACount);
end;

function TRegExHelper.Replace(const AInput: string;
  AEvaluator: TMatchEvaluatorProc): string;
var
  LScopeEvaluator: IScopeEvaluator;
begin
  LScopeEvaluator := TScopeEvaluator.Create(AEvaluator);
  Result := Self.Replace(AInput, LScopeEvaluator.MatchEvaluator);
end;

class function TRegExHelper.Replace(const AInput, APattern: string;
  AEvaluator: TMatchEvaluatorProc; AOptions: TRegExOptions): string;
var
  LScopeEvaluator: IScopeEvaluator;
begin
  LScopeEvaluator := TScopeEvaluator.Create(AEvaluator);
  Result := Replace(AInput, APattern, LScopeEvaluator.MatchEvaluator, AOptions);
end;

class function TRegExHelper.Replace(const AInput, APattern: string;
  AEvaluator: TMatchEvaluatorProc): string;
var
  LScopeEvaluator: IScopeEvaluator;
begin
  LScopeEvaluator := TScopeEvaluator.Create(AEvaluator);
  Result := Replace(AInput, APattern, LScopeEvaluator.MatchEvaluator);
end;

end.
