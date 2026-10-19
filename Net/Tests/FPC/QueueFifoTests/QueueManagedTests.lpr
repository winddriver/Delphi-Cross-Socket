program QueueManagedTests;
{$I zLib.inc}
uses SysUtils,Classes,Generics.Collections
  {$IFDEF FPC},DTF.Generics{$ENDIF};
type
  IValue=interface
    ['{329D3B40-6468-48A4-9FB0-12DAA4F1D166}']
    function Id:Integer;
  end;
  TValue=class(TInterfacedObject,IValue)
  public
    Number:Integer;
    function Id:Integer;
    destructor Destroy;override;
  end;
  TAction=reference to procedure;
  TManaged=record
    Data:TBytes;
    Text:string;
    Callback:TAction;
  end;
  TCheckQueue<T>=class({$IF DEFINED(FPC) AND NOT DEFINED(RAW_QUEUE)}TFpcQueue{$ELSE}TQueue{$ENDIF}<T>)
  {$IFDEF FPC}
  public
    function Slot(const Index:Integer):T;
    function Slots:Integer;
  {$ENDIF}
  end;
var Destroyed,Invoked:Integer;
procedure Check(const OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
function TValue.Id:Integer;
begin Result:=Number;end;
destructor TValue.Destroy;
begin Inc(Destroyed);inherited;end;
{$IFDEF FPC}
function TCheckQueue<T>.Slot(const Index:Integer):T;
begin Result:=FItems[Index];end;
function TCheckQueue<T>.Slots:Integer;
begin Result:=Length(FItems);end;
{$ENDIF}
function Name(const Id:Integer):string;
begin Result:=IntToStr(Id)+'/'+StringOfChar('x',300);end;
procedure AddInterface(const Q:TCheckQueue<IValue>;const Id:Integer);
var P:TValue;Keep:IValue;
begin P:=TValue.Create;P.Number:=Id;Keep:=P;Q.Enqueue(Keep);end;
procedure PopInterface(const Q:TCheckQueue<IValue>;const Id:Integer);
var Keep:IValue;
begin Keep:=Q.Dequeue;Check(Keep.Id=Id,'接口顺序错误');end;
procedure TestInterface;
var Q:TCheckQueue<IValue>;Snapshot:TArray<IValue>;I:Integer;
begin
  Q:=TCheckQueue<IValue>.Create;
  try
    for I:=0 to 63 do AddInterface(Q,I);
    for I:=0 to 2047 do begin PopInterface(Q,I);AddInterface(Q,I+64);end;
    Check(Destroyed=2048,'wrap接口旧槽保留引用');
    Q.Capacity:=Q.Capacity*2+17;Q.TrimExcess;
    Snapshot:=Q.ToArray;Check(Length(Snapshot)=64,'接口容量变更丢项');
    for I:=0 to 63 do Check(Snapshot[I].Id=2048+I,'接口容量变更乱序');
    Snapshot:=nil;Q.Clear;Check(Destroyed=2112,'Clear接口旧槽保留引用');
    {$IFDEF FPC}for I:=0 to Q.Slots-1 do Check(Q.Slot(I)=nil,'空接口队列保留非空物理槽');{$ENDIF}
    for I:=0 to 63 do AddInterface(Q,I);
  finally Q.Free;end;
  Check(Destroyed=2176,'接口析构未全部释放');
end;
procedure AddRecord(const Q:TCheckQueue<TManaged>;const Id:Integer);
var P:TValue;Keep:IValue;V:TManaged;
begin
  P:=TValue.Create;P.Number:=Id;Keep:=P;
  V.Text:=Name(Id);SetLength(V.Data,2);V.Data[0]:=Byte(Id and $FF);V.Data[1]:=Byte(Id shr 8);
  V.Callback:=procedure begin Check(Keep.Id=Id,'回调捕获被替换');Inc(Invoked);end;
  Q.Enqueue(V);
end;
procedure PopRecord(const Q:TCheckQueue<TManaged>;const Id:Integer);
var V:TManaged;
begin
  V:=Q.Dequeue;Check((V.Text=Name(Id)) and (Length(V.Data)=2) and
    (V.Data[0]=Byte(Id and $FF)) and (V.Data[1]=Byte(Id shr 8)),'记录字段损坏');V.Callback();
end;
procedure TestRecord;
var Q:TCheckQueue<TManaged>;Snapshot:TArray<TManaged>;I:Integer;V:TManaged;
begin
  Q:=TCheckQueue<TManaged>.Create;
  try
    for I:=0 to 63 do AddRecord(Q,I);
    for I:=0 to 2047 do begin PopRecord(Q,I);AddRecord(Q,I+64);end;
    Check((Destroyed=2048) and (Invoked=2048),'wrap记录旧槽保留回调/缓冲区');
    Q.Capacity:=Q.Capacity*2+17;Q.TrimExcess;
    Snapshot:=Q.ToArray;Check(Length(Snapshot)=64,'记录容量变更丢项');
    for I:=0 to 63 do Check(Snapshot[I].Text=Name(2048+I),'记录容量变更乱序');
    Snapshot:=nil;Q.Clear;Check(Destroyed=2112,'Clear记录旧槽保留回调');
    {$IFDEF FPC}
    for I:=0 to Q.Slots-1 do begin
      V:=Q.Slot(I);Check((Length(V.Data)=0) and (V.Text='') and not Assigned(V.Callback),'空记录队列保留托管字段');end;
    {$ENDIF}
    for I:=0 to 63 do AddRecord(Q,I);
  finally Q.Free;end;
  Check((Destroyed=2176) and (Invoked=2048),'记录析构未释放或错误调用完成通知');
end;
procedure TestString;
var Q:TCheckQueue<string>;Snapshot:TArray<string>;I:Integer;
begin
  Q:=TCheckQueue<string>.Create;
  try
    for I:=0 to 63 do Q.Enqueue(Name(I));
    for I:=0 to 2047 do begin Check(Q.Dequeue=Name(I),'字符串wrap乱序');Q.Enqueue(Name(I+64));end;
    Q.Capacity:=Q.Capacity*2+17;Q.TrimExcess;
    Snapshot:=Q.ToArray;Check(Length(Snapshot)=64,'字符串容量变更丢项');
    for I:=0 to 63 do Check(Snapshot[I]=Name(2048+I),'字符串容量变更乱序');
    Snapshot:=nil;Q.Clear;
    {$IFDEF FPC}for I:=0 to Q.Slots-1 do Check(Q.Slot(I)='','空字符串队列保留旧尾槽');{$ENDIF}
  finally Q.Free;end;
end;
// 强制在队首已出队但队列未空时扩大容量，覆盖与自动搬移不同的入口。
procedure TestCapacity;
var Q:TCheckQueue<IValue>;I:Integer;
begin
  Q:=TCheckQueue<IValue>.Create;
  try
    for I:=0 to 299 do AddInterface(Q,I);
    for I:=0 to 199 do PopInterface(Q,I);
    Q.Capacity:=600;
    for I:=200 to 299 do PopInterface(Q,I);
    Check(Destroyed=300,'扩容搬移保留接口尾槽');
    for I:=0 to 299 do AddInterface(Q,I);
    for I:=0 to 199 do PopInterface(Q,I);
    Q.Capacity:=100;
    for I:=200 to 299 do PopInterface(Q,I);
    Check(Destroyed=600,'缩容搬移保留接口尾槽');
  finally Q.Free;end;
end;
begin
  try
    if ParamStr(1)='interface' then TestInterface
    else if ParamStr(1)='record' then TestRecord
    else if ParamStr(1)='string' then TestString
    else if ParamStr(1)='capacity' then TestCapacity
    else raise Exception.Create('未知用例');
    Writeln('PASS ',ParamStr(1));
  except on E:Exception do begin Writeln('FAIL ',E.Message);Halt(1);end;end;
end.
