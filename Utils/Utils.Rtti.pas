unit Utils.Rtti;

{$I zLib.inc}

interface

uses
  SysUtils,
  Rtti,
  TypInfo

  {$IFDEF FPC}
  ,DTF.Types
  {$ENDIF}
  ;

type
  TRttiUtils = class
  private class var
    FContext: TRttiContext;
  private
    class constructor Create;
  public type
    TSetMethodArgProc = reference to procedure(const AArg: TRttiParameter; AIndex: Integer; var AValue: TValue);
  public
    {$IFDEF DELPHI}
    class function GetFields(const AContext: TRttiContext;
      const AInstance: TValue): TArray<TRttiField>; overload; static;
    class function GetFields(const AInstance: TValue): TArray<TRttiField>; overload; static;
    class function GetField<T>(const AInstance: TValue; const AFieldName: string): T; static;
    class function SetField(const AInstance: TValue; const AFieldName: string; const AValue: TValue): Boolean; static;
    {$ENDIF}

    class function GetProperties(const AContext: TRttiContext;
      const AInstance: TValue): TArray<TRttiProperty>; overload; static;
    class function GetProperties(const AInstance: TValue): TArray<TRttiProperty>; overload; static;
    class function GetProperty<T>(const AInstance: TValue;
      const APropName: string): T; static;

    class function SetProperty(const AInstance: TValue;
      const APropName: string; const AValue: TValue): Boolean; static;

    class function GetMethods(const AContext: TRttiContext;
      const AInstance: TValue): TArray<TRttiMethod>; overload; static;
    class function GetMethods(const AInstance: TValue): TArray<TRttiMethod>; overload; static;

    class function GetMethod(const AContext: TRttiContext;
      const AInstance: TValue; const AMethod: string): TRttiMethod; overload; static;
    class function GetMethod(const AInstance: TValue; const AMethod: string): TRttiMethod; overload; static;

    class function GetArrayElType(ATypeInfo: PTypeInfo): PTypeInfo; static;
    class function ClassInheritsFrom(AChildClass, AParentClass: TClass): Boolean; overload; static; inline;
    class function ClassInheritsFrom(AChildClass: TClass; const AParentClassName: string): Boolean; overload; static;
    class function ClassInheritsFrom(AChildClass, AParentClass: PTypeInfo): Boolean; overload; static; inline;
    class function IntfInheritsFrom(AChildIntf, AParentIntf: PTypeInfo): Boolean; static;

    class function IsBytes(ATypeInfo: PTypeInfo): Boolean; static;
    class function IsBaseType(ATypeInfo: PTypeInfo): Boolean; static;
    class function IsRecord(ATypeInfo: PTypeInfo): Boolean; static;
    class function IsArray(ATypeInfo: PTypeInfo): Boolean; static;

    class function Invoke(
      const AInstance: TValue;
      const AMethod: string;
      const Args: array of TValue): TValue; overload; static;

    ///	<summary>
    ///	  动态调用方法
    ///	</summary>
    ///	<param name="AObj">
    ///	  对象实例
    ///	</param>
    ///	<param name="AMethod">
    ///	  方法名称
    ///	</param>
    ///	<param name="ASetMethodArgFunc">
    ///	  设置调用参数的回调
    ///	</param>
    ///	<param name="AMethodArgs">
    ///	  生成的调用参数数组，如果有var或者out型的参数，函数调用完之后，该参数值也会回写到该参数数组中
    ///	</param>
    class function Invoke(
      const AInstance: TValue;
      const AMethod: TRttiMethod;
      const ASetMethodArgFunc: TSetMethodArgProc;
      out AMethodArgs: TArray<TValue>;
      out AOutResult: TValue): Boolean; overload; static;

    class function Invoke(
      const AInstance: TValue;
      const AMethod: string;
      const ASetMethodArgFunc: TSetMethodArgProc;
      out AMethodArgs: TArray<TValue>;
      out AOutResult: TValue): Boolean; overload; static;

    class function Invoke(
      const AInstance: TValue;
      const AMethod: string;
      const ASetMethodArgFunc: TSetMethodArgProc;
      out AOutResult: TValue): Boolean; overload; static;

    ///	<summary>
    ///	  在多线程环境下安全的获取某个类的单一实例
    ///	</summary>
    ///	<param name="T">
    ///	  类
    ///	</param>
    ///	<param name="AInstance">
    ///	  类实例全局变量
    ///	</param>
    ///	<param name="AConstructor">
    ///	  创建类实例的函数
    ///	</param>
    class function GetSingletonObj<T: class>(var AInstance; AConstructor: TFunc<T>): T; static;

    class function EnumToStr<T>(e: T): string; static;
    class function StrToEnum<T>(const s: string): T; static;

    class function TryStrToType<T>(const S: string; out AOut: T): Boolean; static;
    class function StrToType<T>(const S: string): T; static;

    class function MakeEmptyTValue(ATypeInfo: PTypeInfo): TValue; static;
  end;

  TValueHelper = record helper for TValue
    {$IFDEF FPC}
    function Cast(ATypeInfo: PTypeInfo): TValue;
    function TryAsType<T>(out AResult: T): Boolean;
    function AsType<T>: T;
    function IsInstanceOf(AClass: TClass): Boolean;
    {$ENDIF}

    function GetArrayElType: PTypeInfo; inline;
  end;

  TRttiObjectHelper = class helper for TRttiObject
  public
    function GetRttiType: TRttiType;
    procedure SetValue(AInstance: Pointer; const AValue: TValue);
    function HasAttribute<T: TCustomAttribute>(
      const ADoSomething: TProc<T>): Boolean; overload;
    function HasAttribute<T: TCustomAttribute>: Boolean; overload;
    function ForEachAttribute<T: TCustomAttribute>(
      const ADoSomething: TProc<T>): Integer;
    function IsType(ATypeInfo: PTypeInfo): Boolean; overload;
    function IsType<T>: Boolean; overload;
    function InheritsFrom(ATypeInfo: PTypeInfo): Boolean; overload;
    function InheritsFrom<T>: Boolean; overload;
  end;

implementation

{ TRttiUtils }

class constructor TRttiUtils.Create;
begin
  FContext := TRttiContext.Create;
end;

class function TRttiUtils.EnumToStr<T>(e: T): string;
var
  i: Integer;
begin
  if (SizeOf(T) = SizeOf(Integer)) then
    i := PInteger(@e)^
  else
    i := PByte(@e)^;
  Result := UnicodeString(GetEnumName(TypeInfo(T), i));
end;

class function TRttiUtils.ClassInheritsFrom(AChildClass, AParentClass: TClass): Boolean;
begin
  Result := AChildClass.InheritsFrom(AParentClass);
end;

class function TRttiUtils.ClassInheritsFrom(AChildClass: TClass; const AParentClassName: string): Boolean;
begin
  while (AChildClass <> nil) do
    if AChildClass.ClassNameIs(AParentClassName) then
      Exit(True)
    else
      AChildClass := AChildClass.ClassParent;
  Result := False;
end;

class function TRttiUtils.ClassInheritsFrom(AChildClass,
  AParentClass: PTypeInfo): Boolean;
begin
  Result := GetTypeData(AChildClass).ClassType.InheritsFrom(GetTypeData(AParentClass).ClassType);
end;

{$IFDEF DELPHI}
class function TRttiUtils.GetFields(const AContext: TRttiContext;
  const AInstance: TValue): TArray<TRttiField>;
var
  LRttiType: TRttiType;
begin
  LRttiType := AContext.GetType(AInstance.TypeInfo);
  Result := LRttiType.GetFields;
end;

class function TRttiUtils.GetFields(const AInstance: TValue): TArray<TRttiField>;
begin
  Result := GetFields(FContext, AInstance);
end;

class function TRttiUtils.GetField<T>(const AInstance: TValue;
  const AFieldName: string): T;
var
  LRttiType: TRttiType;
  LRttiField: TRttiField;
  LValue: TValue;
begin
  LRttiType := FContext.GetType(AInstance.TypeInfo);
  LRttiField := LRttiType.GetField(AFieldName);
  if (LRttiField = nil) then Exit(Default(T));

  LValue := LRttiField.GetValue(AInstance.GetReferenceToRawData);
  if not LValue.TryAsType<T>(Result) then
    Result := Default(T);
end;

class function TRttiUtils.SetField(const AInstance: TValue;
  const AFieldName: string; const AValue: TValue): Boolean;
var
  LRttiType: TRttiType;
  LRttiField: TRttiField;
begin
  LRttiType := FContext.GetType(AInstance.TypeInfo);
  LRttiField := LRttiType.GetField(AFieldName);
  if (LRttiField = nil) then Exit(False);

  LRttiField.SetValue(AInstance.GetReferenceToRawData, AValue);
  Result := True;
end;
{$ENDIF}

class function TRttiUtils.GetProperties(const AContext: TRttiContext;
  const AInstance: TValue): TArray<TRttiProperty>;
var
  LRttiType: TRttiType;
begin
  LRttiType := AContext.GetType(AInstance.TypeInfo);
  Result := LRttiType.GetProperties;
end;

class function TRttiUtils.GetProperties(const AInstance: TValue): TArray<TRttiProperty>;
begin
  Result := GetProperties(FContext, AInstance);
end;

class function TRttiUtils.GetProperty<T>(const AInstance: TValue;
  const APropName: string): T;
var
  LRttiType: TRttiType;
  LRttiProp: TRttiProperty;
  LValue: TValue;
begin
  LRttiType := FContext.GetType(AInstance.TypeInfo);
  LRttiProp := LRttiType.GetProperty(APropName);
  if (LRttiProp = nil) then Exit(Default(T));

  LValue := LRttiProp.GetValue(AInstance.GetReferenceToRawData);
  if not LValue.TryAsType<T>(Result) then
    Result := Default(T);
end;

class function TRttiUtils.GetMethods(const AContext: TRttiContext;
  const AInstance: TValue): TArray<TRttiMethod>;
var
  LRttiType: TRttiType;
begin
  LRttiType := AContext.GetType(AInstance.TypeInfo);
  Result := LRttiType.GetMethods;
end;

class function TRttiUtils.GetMethods(const AInstance: TValue): TArray<TRttiMethod>;
begin
  Result := GetMethods(FContext, AInstance);
end;

class function TRttiUtils.GetMethod(const AContext: TRttiContext;
  const AInstance: TValue; const AMethod: string): TRttiMethod;
var
  LRttiType: TRttiType;
begin
  LRttiType := AContext.GetType(AInstance.TypeInfo);
  Result := LRttiType.GetMethod(AMethod);
end;

class function TRttiUtils.GetMethod(const AInstance: TValue;
  const AMethod: string): TRttiMethod;
begin
  Result := GetMethod(FContext, AInstance, AMethod);
end;

class function TRttiUtils.GetSingletonObj<T>(var AInstance;
  AConstructor: TFunc<T>): T;
var
  LInstance: TObject;
begin
  if not Assigned(AConstructor) then Exit(nil);

  if (TObject(AInstance) = nil) then
  begin
    TObject(LInstance) := AConstructor();
    if AtomicCmpExchange(Pointer(AInstance), Pointer(LInstance), nil) <> nil then
      LInstance.Free;
    {$IFDEF AUTOREFCOUNT}
    TObject(AInstance).__ObjAddRef;
    {$ENDIF AUTOREFCOUNT}
  end;
  Result := T(AInstance);
end;

class function TRttiUtils.SetProperty(const AInstance: TValue;
  const APropName: string; const AValue: TValue): Boolean;
var
  LRttiType: TRttiType;
  LRttiProp: TRttiProperty;
begin
  LRttiType := FContext.GetType(AInstance.TypeInfo);
  LRttiProp := LRttiType.GetProperty(APropName);
  if (LRttiProp = nil) then Exit(False);

  LRttiProp.SetValue(AInstance.GetReferenceToRawData, AValue);
  Result := True;
end;

class function TRttiUtils.StrToEnum<T>(const s: string): T;
var
  i: Integer;
begin
  i := GetEnumValue(TypeInfo(T), s);
  Result := T(Pointer(@i)^);
end;

class function TRttiUtils.TryStrToType<T>(const S: string;
  out AOut: T): Boolean;
var
  LTypeInfo: PTypeInfo;
  LResult: TValue;
  LInt: Integer;
  LInt64: Int64;
  LDate: TDateTime;
  LFloat: Extended;
  LVar: Variant;
  LBool: Boolean;
  LEnumVal: Integer;
begin
  LTypeInfo := TypeInfo(T);

  case LTypeInfo.Kind of
    tkInteger:
      begin
        Result := TryStrToInt(S, LInt);
        if Result then
          LResult := TValue.From<Integer>(LInt);
      end;

    tkInt64{$IFDEF FPC}, tkQWord{$ENDIF}:
      begin
        Result := TryStrToInt64(S, LInt64);
        if Result then
          LResult := TValue.From<Int64>(LInt64);
      end;

    tkFloat:
      begin
        if (LTypeInfo = TypeInfo(TDateTime)) or
          (LTypeInfo = TypeInfo(TTime)) or
          (LTypeInfo = TypeInfo(TDate)) then
        begin
          Result := TryStrToDateTime(S, LDate);
          if Result then
            LResult := TValue.From<TDateTime>(LDate);
        end else
        begin
          Result := TryStrToFloat(S, LFloat);
          if Result then
            LResult := TValue.From<Extended>(LFloat);
        end;
      end;

    tkVariant:
      begin
        LVar := S;
        Result := True;
        LResult := TValue.From<Variant>(LVar);
      end;

    tkChar, tkWChar{$IFDEF FPC}, tkUChar, tkSString, tkAString{$ELSE}, tkString{$ENDIF}, tkLString, tkWString, tkUString:
      begin
        Result := True;
        LResult := TValue.From<string>(S);
      end;

    tkEnumeration:
      begin
        {$IFDEF DELPHI}
        if (GetTypeData(LTypeInfo).BaseType^ = TypeInfo(Boolean)) then
        {$ELSE FPC}
        if (GetTypeData(LTypeInfo).BaseType = TypeInfo(Boolean)) then
        {$ENDIF}
        begin
          Result := TryStrToBool(S, LBool);
          if Result then
            LResult := TValue.From<Boolean>(LBool);
        end else
        begin
          LEnumVal := GetEnumValue(LTypeInfo, S);

          if (LEnumVal < GetTypeData(LTypeInfo).MinValue) then
            LEnumVal := GetTypeData(LTypeInfo).MinValue
          else if (LEnumVal > GetTypeData(LTypeInfo).MaxValue) then
            LEnumVal := GetTypeData(LTypeInfo).MaxValue;

          Result := True;
          TValue.Make(@LEnumVal, LTypeInfo, LResult);
        end;
      end;

    {$IFDEF FPC}
    tkBool:
      begin
        Result := TryStrToBool(S, LBool);
        if Result then
          LResult := TValue.From<Boolean>(LBool);
      end;
    {$ENDIF}

    tkSet:
      begin
        LEnumVal := StringToSet(LTypeInfo, S);
        Result := True;
        TValue.Make(@LEnumVal, LTypeInfo, LResult);
      end;
  else
    Result := False;
  end;

  if Result then
    Result := LResult.TryAsType<T>(AOut)
  else
    AOut := Default(T);
end;

class function TRttiUtils.StrToType<T>(const S: string): T;
begin
  if not (TRttiUtils.TryStrToType<T>(S, Result)) then
    Result := Default(T);
end;

class function TRttiUtils.GetArrayElType(ATypeInfo: PTypeInfo): PTypeInfo;
{$IFDEF DELPHI}
var
  LRef: PPTypeInfo;
begin
  case ATypeInfo.Kind of
    tkDynArray:
      LRef := GetTypeData(ATypeInfo).DynArrElType;

    tkArray:
	    LRef := GetTypeData(ATypeInfo).ArrayData.ElType;
  else
    LRef := nil;
  end;

  if (LRef <> nil) then
    Result := LRef^
  else
    Result := nil;
end;
{$ELSE FPC}
begin
  case ATypeInfo.Kind of
    tkDynArray:
      Result := GetTypeData(ATypeInfo).ElType2;

    tkArray:
      Result := GetTypeData(ATypeInfo).ArrayData.ElType;
	else
    Result := nil;
  end;
end;
{$ENDIF}

class function TRttiUtils.Invoke(const AInstance: TValue;
  const AMethod: string; const Args: array of TValue): TValue;
var
  LRttiType: TRttiType;
  LRttiMethod: TRttiMethod;
begin
  LRttiType := FContext.GetType(AInstance.TypeInfo);
  LRttiMethod := LRttiType.GetMethod(AMethod);

  if (LRttiMethod <> nil) then
    Result := LRttiMethod.Invoke(AInstance, Args)
  else
    Result := Default(TValue);
end;

class function TRttiUtils.Invoke(const AInstance: TValue;
  const AMethod: TRttiMethod; const ASetMethodArgFunc: TSetMethodArgProc;
  out AMethodArgs: TArray<TValue>; out AOutResult: TValue): Boolean;
var
  LMethodParams: TArray<TRttiParameter>;
  I: Integer;
begin
  AMethodArgs := nil;
  if (AMethod = nil) then Exit(False);

  if Assigned(ASetMethodArgFunc) then
  begin
    LMethodParams := AMethod.GetParameters;
    SetLength(AMethodArgs, Length(LMethodParams));
    for I := Low(LMethodParams) to High(LMethodParams) do
      ASetMethodArgFunc(LMethodParams[I], I, AMethodArgs[I]);
  end;

  AOutResult := AMethod.Invoke(AInstance, AMethodArgs);
  Result := True;
end;

class function TRttiUtils.Invoke(const AInstance: TValue; const AMethod: string;
  const ASetMethodArgFunc: TSetMethodArgProc;
  out AMethodArgs: TArray<TValue>; out AOutResult: TValue): Boolean;
var
  LRttiType: TRttiType;
  LRttiMethod: TRttiMethod;
begin
  LRttiType := FContext.GetType(AInstance.TypeInfo);
  LRttiMethod := LRttiType.GetMethod(AMethod);

  Result := TRttiUtils.Invoke(AInstance, LRttiMethod, ASetMethodArgFunc,
    AMethodArgs, AOutResult);
end;

class function TRttiUtils.Invoke(const AInstance: TValue; const AMethod: string;
  const ASetMethodArgFunc: TSetMethodArgProc; out AOutResult: TValue): Boolean;
var
  LArgs: TArray<TValue>;
begin
  Result := Invoke(AInstance, AMethod, ASetMethodArgFunc, LArgs, AOutResult);
end;

class function TRttiUtils.IntfInheritsFrom(AChildIntf,
  AParentIntf: PTypeInfo): Boolean;
var
  LChildIntf: PTypeInfo;
begin
  LChildIntf := AChildIntf;
  while True do
  begin
    if (LChildIntf = AParentIntf) then Exit(True);

    if (GetTypeData(LChildIntf).IntfParent = nil) then Break;

    {$IFDEF DELPHI}
    LChildIntf := GetTypeData(LChildIntf).IntfParent^;
    {$ELSE FPC}
    LChildIntf := GetTypeData(LChildIntf).IntfParent;
    {$ENDIF}
    if (LChildIntf = nil) then Break;
  end;

  Result := False;
end;

class function TRttiUtils.IsArray(ATypeInfo: PTypeInfo): Boolean;
begin
  Exit(ATypeInfo.Kind in [tkArray, tkDynArray]);
end;

class function TRttiUtils.IsBaseType(ATypeInfo: PTypeInfo): Boolean;
begin
  case ATypeInfo.Kind of
    tkInteger,
    tkInt64,
    tkFloat,
    tkEnumeration,
    tkSet,
    {$IFDEF FPC}
    tkBool,
    tkQWord,
    tkUChar,
    tkSString,
    tkAString,
    {$ELSE}
    tkString,
    {$ENDIF}
    tkChar,
    tkWChar,
    tkLString,
    tkWString,
    tkUString,
    tkVariant: Exit(True);
  end;
  Exit(False);
end;

class function TRttiUtils.IsBytes(ATypeInfo: PTypeInfo): Boolean;
var
  LArrayElType: PTypeInfo;
  LArrayElTypeData: PTypeData;
begin
  if (ATypeInfo.Kind in [tkArray, tkDynArray]) then
  begin
    LArrayElType := TRttiUtils.GetArrayElType(ATypeInfo);
    if (LArrayElType <> nil) and (LArrayElType.Kind = tkInteger) then
    begin
      LArrayElTypeData := GetTypeData(LArrayElType);
      if (LArrayElTypeData <> nil)
        and (LArrayElTypeData.OrdType in [otSByte, otUByte]) then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TRttiUtils.IsRecord(ATypeInfo: PTypeInfo): Boolean;
begin
  Exit(ATypeInfo.Kind = tkRecord);
end;

class function TRttiUtils.MakeEmptyTValue(ATypeInfo: PTypeInfo): TValue;
begin
  // 直接使用 TValue.Empty 转换到某些类型的数据会触发异常
  // 比如 TValue.Empty 就无法直接转换为任何 record 类型数据
  // 使用 TValue.Make(nil, ATypeInfo, Result) 生成的 TValue 则不会触发异常
  // 这相当于将目标数据全部置零
  TValue.Make(nil, ATypeInfo, Result);
end;

{ TValueHelper }

function TValueHelper.GetArrayElType: PTypeInfo;
begin
  Result := TRttiUtils.GetArrayElType(Self.TypeInfo);
end;

{$IFDEF FPC}
function TValueHelper.Cast(ATypeInfo: PTypeInfo): TValue;
begin
  Make(Self.GetReferenceToRawData, ATypeInfo, Result);
end;

function TValueHelper.TryAsType<T>(out AResult: T): Boolean;
var
  LOutValue: TValue;
begin
  if (Self.TypeInfo = nil) then
  begin
    AResult := Default(T);
    Exit(True);
  end;

  LOutValue := Cast(System.TypeInfo(T));
  LOutValue.ExtractRawData(@AResult);

  Result := True;
end;

function TValueHelper.AsType<T>: T;
begin
  if not (TryAsType<T>(Result)) then
    Result := Default(T);
end;

function TValueHelper.IsInstanceOf(AClass: TClass): Boolean;
var
  LAsObj: TObject;
begin
  Result := False;
  if not IsObject then Exit;

  LAsObj := AsObject;
  Result := (LAsObj <> nil) and LAsObj.InheritsFrom(AClass);
end;
{$ENDIF}

{ TRttiObjectHelper }

function TRttiObjectHelper.ForEachAttribute<T>(
  const ADoSomething: TProc<T>): Integer;
var
  LAttribute: TCustomAttribute;
begin
  Result := 0;
  for LAttribute in Self.GetAttributes do
  begin
    if (LAttribute is T) then
    begin
      if Assigned(ADoSomething) then
        ADoSomething(T(LAttribute));
      Inc(Result);
    end;
  end;
end;

function TRttiObjectHelper.GetRttiType: TRttiType;
begin
  Result := nil;

  {$IFDEF DELPHI}
  if Self is TRttiField then
    Result := TRttiField(Self).FieldType
  else
  {$ENDIF}
  if Self is TRttiProperty then
    Result := TRttiProperty(Self).PropertyType
  else
  if Self is TRttiParameter then
    Result := TRttiParameter(Self).ParamType;
end;

function TRttiObjectHelper.HasAttribute<T>(
  const ADoSomething: TProc<T>): Boolean;
var
  LAttribute: TCustomAttribute;
begin
  for LAttribute in Self.GetAttributes do
  begin
    if (LAttribute is T) then
    begin
      if Assigned(ADoSomething) then
        ADoSomething(T(LAttribute));
      Exit(True);
    end;
  end;
  Result := False;
end;

function TRttiObjectHelper.HasAttribute<T>: Boolean;
begin
  Result := HasAttribute<T>(nil);
end;

function TRttiObjectHelper.IsType(ATypeInfo: PTypeInfo): Boolean;
var
  LRttiType: TRttiType;
  LTypInfo: PTypeInfo;
begin
  LRttiType := GetRttiType;
  if (LRttiType = nil) then Exit(False);

  LTypInfo := LRttiType.Handle;
  Exit(LTypInfo = ATypeInfo);
end;

function TRttiObjectHelper.IsType<T>: Boolean;
begin
  Result := IsType(TypeInfo(T));
end;

function TRttiObjectHelper.InheritsFrom(ATypeInfo: PTypeInfo): Boolean;
var
  LRttiType: TRttiType;
  LTypInfo: PTypeInfo;
begin
  LRttiType := GetRttiType;
  if (LRttiType = nil) then Exit(False);

  LTypInfo := LRttiType.Handle;

  case LTypInfo.Kind of
    tkClass: Exit(TRttiUtils.ClassInheritsFrom(LTypInfo, ATypeInfo));
    tkInterface: Exit(TRttiUtils.IntfInheritsFrom(LTypInfo, ATypeInfo));
  else
    Exit(LTypInfo = ATypeInfo);
  end;
end;

function TRttiObjectHelper.InheritsFrom<T>: Boolean;
begin
  Result := InheritsFrom(TypeInfo(T));
end;

procedure TRttiObjectHelper.SetValue(AInstance: Pointer; const AValue: TValue);
begin
  {$IFDEF DELPHI}
  if Self is TRttiField then
    TRttiField(Self).SetValue(AInstance, AValue)
  else
  {$ENDIF}
  if Self is TRttiProperty then
    TRttiProperty(Self).SetValue(AInstance, AValue)
  else
  if Self is TRttiParameter then
    TRttiParameter(Self).SetValue(AInstance, AValue);
end;

end.

