unit DTF.Rtti;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils,
  Rtti,
  TypInfo;

type

  { TRttiField }

  TRttiField = class(TRttiMember)
  private
    FFieldType: TRttiType;
    FRecTypInfo: PTypeInfo;
    FManagedField: PManagedField;
    FOrder: Integer;

    function GetFieldType: TRttiType;
    function GetOffset: Integer;
  protected
    function GetName: AnsiString; override;
    function GetHandle: Pointer; override;
  public
    constructor Create(AParent: TRttiType; ARecTypInfo: PTypeInfo; AManagedField: PManagedField; AOrder: Integer);
    destructor Destroy; override;

    function GetValue(Instance: Pointer): TValue;
    procedure SetValue(Instance: Pointer; const AValue: TValue);

    property FieldType: TRttiType read GetFieldType;
    property Offset: Integer read GetOffset;
  end;

  //TRttiTypeHelper = class helper for TRttiType
  //public
	 // function GetFields: TArray<TRttiField>;
  //  function GetField(const AName: string): TRttiField;
  //end;

function GetRecordFields(ARecordTypeInfo: PTypeInfo): TArray<TRttiField>;

implementation

function GetRecordFields(ARecordTypeInfo: PTypeInfo): TArray<TRttiField>;
var
  I: Integer;
  LTypeData: PTypeData;
  LMgrFieldPtr: PManagedField;
  LRttiField: TRttiField;
begin
  Result := [];
  LTypeData := GetTypeData(ARecordTypeInfo);
  if (LTypeData = nil) or (LTypeData.TotalFieldCount <= 0) then Exit;

  SetLength(Result, LTypeData.TotalFieldCount);

  LMgrFieldPtr := PManagedField(PByte(@LTypeData.TotalFieldCount) + SizeOf(LTypeData.TotalFieldCount));

  for I := 0 to LTypeData.TotalFieldCount - 1 do
  begin
    LRttiField := TRttiField.Create(nil, ARecordTypeInfo, LMgrFieldPtr, I);
    Result[I] := LRttiField;

    Inc(LMgrFieldPtr);
  end;
end;

{ TRttiField }

constructor TRttiField.Create(AParent: TRttiType; ARecTypInfo: PTypeInfo;
  AManagedField: PManagedField; AOrder: Integer);
begin
  inherited Create(AParent);

  FRecTypInfo := ARecTypInfo;
  FManagedField := AManagedField;
  FOrder := AOrder;
end;

destructor TRttiField.Destroy;
begin
  inherited Destroy;
end;

function TRttiField.GetFieldType: TRttiType;
begin
  Result := Parent;
end;

function TRttiField.GetOffset: Integer;
begin
  Result := FManagedField.FldOffset;
end;

function TRttiField.GetName: AnsiString;
begin
  // FPC中只能获取到 record 成员的类型名称
  // 无法获取到成员的实际名称
  // 截止到 2023.08.16, FPC 3.3.1 依然如此
  //Result := FManagedField.TypeRef.Name;

  // 只能暂时使用 record 类型名加下标的方式给成员命名
  Result := Format('%s_field_%d', [FRecTypInfo.Name, FOrder]);
end;

function TRttiField.GetHandle: Pointer;
begin
  Result := FManagedField.TypeRef;
end;

function TRttiField.GetValue(Instance: Pointer): TValue;
begin
  TValue.Make(PByte(Instance) + Offset, Handle, Result);
end;

procedure TRttiField.SetValue(Instance: Pointer; const AValue: TValue);
begin
  AValue.ExtractRawData(PByte(Instance) + Offset);
end;

//{ TRttiTypeHelper }
//
//function TRttiTypeHelper.GetFields: TArray<TRttiField>;
//var
//  I: Integer;
//  LTypeData: PTypeData;
//  LMgrFieldPtr: PManagedField;
//  LRttiField: TRttiField;
//begin
//  Result := [];
//  LTypeData := GetTypeData(Handle);
//  if (LTypeData = nil) or (LTypeData.TotalFieldCount <= 0) then Exit;
//
//  SetLength(Result, LTypeData.TotalFieldCount);
//
//  LMgrFieldPtr := PManagedField(PByte(@LTypeData.TotalFieldCount) + SizeOf(LTypeData.TotalFieldCount));
//
//  for I := 0 to LTypeData.TotalFieldCount - 1 do
//  begin
//    LRttiField := TRttiField.Create(Self, LMgrFieldPtr);
//    Result[I] := LRttiField;
//    //GRttiPool.AddObject(LRttiField);
//
//    Inc(LMgrFieldPtr);
//  end;
//end;
//
//function TRttiTypeHelper.GetField(const AName: string): TRttiField;
//var
//  LFields: TArray<TRttiField>;
//  LField: TRttiField;
//begin
//  Result := nil;
//  LFields := GetFields;
//
//  if (Length(LFields) <= 0) then Exit;
//
//  for LField in LFields do
//  begin
//    if TStrUtils.SameText(LField.Name, AName) then
//    	Exit(LField);
//  end;
//end;

end.

