program MultipartStreamTests;
{$I zLib.inc}
uses SysUtils,Classes,Math
  {$IFDEF MSWINDOWS},Windows{$ENDIF}
  ,Net.CrossHttpParams;
type
  TPatternStream=class(TStream)
  private
    FPosition:Int64;
  protected
    function GetSize:Int64;override;
  public
    ReportedSize,StopAt:Int64;
    MaxRead,SizeCalls,ReadCalls:Integer;
    constructor Create(const ASize:Int64);
    destructor Destroy;override;
    function Read(var Buffer;Count:Longint):Longint;override;
    function Write(const Buffer;Count:Longint):Longint;override;
    function Seek(const Offset:Int64;Origin:TSeekOrigin):Int64;override;
  end;
  TCountForm=class(THttpMultiPartFormData)
  public destructor Destroy;override;end;
var DestroyedStreams,DestroyedForms:Integer;Frequency:Int64;
{$IFDEF POSIX}
type TClockTime=record Sec,Nano:Int64;end;
function ClockTime(AClock:Integer;var ATime:TClockTime):Integer;cdecl;
  external {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF} name 'clock_gettime';
{$ENDIF}
{$IFDEF MSWINDOWS}
function SparseControl(AHandle:THandle;ACode:DWORD;AIn:Pointer;AInSize:DWORD;
  AOut:Pointer;AOutSize:DWORD;var AReturned:DWORD;AOverlapped:Pointer):BOOL;stdcall;
  external 'kernel32.dll' name 'DeviceIoControl';
{$ENDIF}
procedure Check(const OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
function Ticks:Int64;
{$IFDEF POSIX}var T:TClockTime;{$ENDIF}
begin
  {$IFDEF MSWINDOWS}QueryPerformanceCounter(Result);{$ELSE}
  Check(ClockTime(1,T)=0,'clock_gettime');Result:=T.Sec*1000000000+T.Nano;{$ENDIF}
end;
constructor TPatternStream.Create(const ASize:Int64);
begin inherited Create;ReportedSize:=ASize;StopAt:=-1;end;
destructor TPatternStream.Destroy;
begin Inc(DestroyedStreams);inherited;end;
destructor TCountForm.Destroy;
begin Inc(DestroyedForms);inherited;end;
function TPatternStream.GetSize:Int64;
begin Inc(SizeCalls);Result:=ReportedSize;end;
function TPatternStream.Read(var Buffer;Count:Longint):Longint;
var I:Integer;P:PByte;
begin
  Inc(ReadCalls);Result:=0;
  if (Count<=0) or (FPosition<0) or (FPosition>=ReportedSize) then Exit;
  if (StopAt>=0) and (FPosition>=StopAt) then Exit;
  Result:=Min(Int64(Count),ReportedSize-FPosition);
  if MaxRead>0 then Result:=Min(Result,MaxRead);
  if StopAt>=0 then Result:=Min(Int64(Result),StopAt-FPosition);
  P:=@Buffer;for I:=0 to Result-1 do P[I]:=Byte((FPosition+I) and $FF);
  Inc(FPosition,Result);
end;
function TPatternStream.Write(const Buffer;Count:Longint):Longint;
begin Result:=0;raise EWriteError.Create('测试流只读');end;
function TPatternStream.Seek(const Offset:Int64;Origin:TSeekOrigin):Int64;
begin
  case Origin of soBeginning:FPosition:=Offset;soCurrent:FPosition:=FPosition+Offset;soEnd:FPosition:=ReportedSize+Offset;end;
  Result:=FPosition;
end;
function Payload(const N,Seed:Integer):TBytes;
var I:Integer;
begin SetLength(Result,N);for I:=0 to N-1 do Result[I]:=Byte((I+Seed) and $FF);end;
function Header(const F:THttpMultiPartFormData;const Index:Integer):TBytes;
var Text:string;Field:TFormField;
begin
  Field:=F.Items[Index];Text:='';if Index>0 then Text:=#13#10;
  Text:=Text+'--'+F.Boundary+#13#10+'Content-Disposition: form-data; name="'+Field.Name+'"';
  if Field.FileName<>'' then Text:=Text+'; filename="'+Field.FileName+'"';
  Text:=Text+#13#10;
  if Field.ContentType<>'' then Text:=Text+'Content-Type: '+Field.ContentType+#13#10;
  Result:=TEncoding.UTF8.GetBytes(Text+#13#10);
end;
function Ending(const F:THttpMultiPartFormData):TBytes;
begin Result:=TEncoding.ASCII.GetBytes(#13#10+'--'+F.Boundary+'--'#13#10);end;
function Oracle(const F:THttpMultiPartFormData;const Bodies:TArray<TBytes>):TBytes;
var M:TMemoryStream;B:TBytes;I:Integer;
begin
  M:=TMemoryStream.Create;
  try
    for I:=0 to F.Count-1 do begin
      B:=Header(F,I);if Length(B)>0 then M.WriteBuffer(B[0],Length(B));
      B:=Bodies[I];if Length(B)>0 then M.WriteBuffer(B[0],Length(B));
    end;
    B:=Ending(F);M.WriteBuffer(B[0],Length(B));SetLength(Result,M.Size);
    if Length(Result)>0 then Move(M.Memory^,Result[0],Length(Result));
  finally M.Free;end;
end;
function TempName:string;
var Id:TGUID;
begin
  CreateGUID(Id);Result:=ExtractFilePath(ParamStr(0))+'multipart-'+GUIDToString(Id)+'.tmp';
  Check(not FileExists(Result),'临时路径冲突');
end;
procedure MakeForm(const N,Total:Integer;const Mixed:Boolean;
  out F:THttpMultiPartFormData;out Bodies:TArray<TBytes>;out Path:string);
var I,Size,Base:Integer;Stream:TFileStream;B:TBytes;UseFile:Boolean;
begin
  F:=THttpMultiPartFormData.Create;F.Boundary:='DCS-test';Path:='';SetLength(Bodies,N);
  if N=0 then Exit;
  if Total<0 then Base:=64 else Base:=Total div N;
  try
    if Mixed and (N>0) then begin
      Path:=TempName;Stream:=TFileStream.Create(Path,fmCreate);
      try B:=Payload(Base,7);if Base>0 then Stream.WriteBuffer(B[0],Base);finally Stream.Free;end;
    end;
    for I:=0 to N-1 do begin
      Size:=Base;if (Total>=0) and (I=0) then Inc(Size,Total mod N);
      UseFile:=Mixed and (Odd(I) or (N=1));
      if (Total<0) and (I mod 10=0) and not UseFile then Size:=0;
      if UseFile then begin
        Bodies[I]:=Payload(Size,7);Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
        try F.AddFile('field'+IntToStr(I),'payload.bin',Stream,True);except Stream.Free;raise;end;
      end else begin
        Bodies[I]:=Payload(Size,I);F.AddField('field'+IntToStr(I),Bodies[I]);
      end;
    end;
  except F.Free;F:=nil;if Path<>'' then SysUtils.DeleteFile(Path);raise;end;
end;
function Drain(const S:TStream;const Block:Integer;out Calls:Integer):TBytes;
var M:TMemoryStream;Buffer:TBytes;N:Integer;
begin
  M:=TMemoryStream.Create;SetLength(Buffer,Block);Calls:=0;
  try
    repeat
      FillChar(Buffer[0],Block,$CC);N:=S.Read(Buffer[0],Block);Inc(Calls);
      Check(Calls<1000000,'读取未前进');Check((N>=0) and (N<=Block),'Read返回值越界');
      if N>0 then M.WriteBuffer(Buffer[0],N);
    until N=0;
    SetLength(Result,M.Size);if Length(Result)>0 then Move(M.Memory^,Result[0],Length(Result));
  finally M.Free;end;
end;
procedure Equal(const A,B:TBytes;const Msg:string);
begin Check((Length(A)=Length(B)) and ((Length(A)=0) or CompareMem(@A[0],@B[0],Length(A))),Msg);end;
procedure TestWire(const N:Integer);
const Blocks:array[0..3] of Integer=(1,17,4096,65536);
var F:THttpMultiPartFormData;S:THttpMultiPartFormStream;Bodies:TArray<TBytes>;
  Expected,Actual,Buffer:TBytes;Path:string;I,J,Calls,Pos,Count,Got:Integer;
begin
  MakeForm(N,-1,True,F,Bodies,Path);S:=nil;
  try
    Expected:=Oracle(F,Bodies);S:=THttpMultiPartFormStream.Create(F);
    Check(S.Size=Length(Expected),'总长度与字节预期不同');
    for I:=0 to High(Blocks) do begin
      if (N>=1000) and (Blocks[I]=1) then Continue;
      S.Position:=0;Actual:=Drain(S,Blocks[I],Calls);Equal(Expected,Actual,'分块读取字节不同');
    end;
    SetLength(Buffer,97);RandSeed:=17;
    for I:=0 to 127 do begin
      Pos:=Random(Length(Expected)+2);S.Seek(Pos,soBeginning);Count:=Random(98);
      Got:=S.Read(Buffer[0],Count);Check(Got=Min(Count,Max(0,Length(Expected)-Pos)),'随机Seek长度');
      for J:=0 to Got-1 do Check(Buffer[J]=Expected[Pos+J],'随机Seek字节');
    end;
    Check(S.Seek(-9,soBeginning)=-1,'负位置语义');Check(S.Read(Buffer[0],1)=0,'负位置仍读取');
    Check(S.Seek(High(Int64),soBeginning)=S.Size,'超出末尾未夹紧');
  finally S.Free;F.Free;if Path<>'' then Check(SysUtils.DeleteFile(Path),'临时文件未删除');end;
end;
procedure TestProbe(const Name:string);
var F:THttpMultiPartFormData;S:THttpMultiPartFormStream;P:TPatternStream;
  B,Expected,H,T:TBytes;Bodies:TArray<TBytes>;Calls,N:Integer;Raised:Boolean;Size:Int64;
begin
  F:=THttpMultiPartFormData.Create;F.Boundary:='probe';P:=TPatternStream.Create(32);S:=nil;
  F.AddFile('part','data.bin',P,True);H:=Header(F,0);T:=Ending(F);
  try
    if Name='init-overflow' then P.ReportedSize:=High(Int64)
    else if Name='init-total-overflow' then begin
      P.ReportedSize:=High(Int64) div 2;
      F.AddFile('second','data.bin',TPatternStream.Create(High(Int64) div 2),True);
    end
    else if Name='init-tail-overflow' then P.ReportedSize:=High(Int64)-Length(H)
    else if Name='negative-size' then P.ReportedSize:=-1
    else if Name='read-overflow' then P.ReportedSize:=High(Int64)-Length(H)-Length(T);
    Raised:=False;
    try S:=THttpMultiPartFormStream.Create(F);except on E:EStreamError do Raised:=True;end;
    if (Copy(Name,1,5)='init-') or (Name='negative-size') then begin Check(Raised,'初始化长度越界未拒绝');Exit;end;
    Check(not Raised,'普通初始化失败');
    SetLength(B,65536);
    if Name='short-read' then begin
      P.MaxRead:=3;SetLength(Bodies,1);Bodies[0]:=Payload(32,0);Expected:=Oracle(F,Bodies);
      B:=Drain(S,65536,Calls);Equal(B,Expected,'合法短读产生未填充字节');
      Check(P.ReadCalls>1,'未执行短读循环');
    end else if Name='early-zero' then begin
      P.MaxRead:=3;P.StopAt:=5;Raised:=False;
      try S.Read(B[0],Length(B));except on E:EReadError do Raised:=True;end;
      Check(Raised,'提前返回0未抛EReadError');Check(S.Position=Length(H)+5,'失败后跳过未实际读取字节');
    end else if (Name='length-grow') or (Name='length-shrink') or (Name='length-between') then begin
      if Name='length-between' then Check(S.Read(B[0],Length(H)+4)=Length(H)+4,'前段读取');
      if Name='length-shrink' then P.ReportedSize:=5 else P.ReportedSize:=64;
      Raised:=False;try S.Read(B[0],1);except on E:EReadError do Raised:=True;end;
      Check(Raised,'字段长度变化没有拒绝');
    end else if Name='seek-overflow' then begin
      Size:=S.Size;S.Seek(10,soBeginning);Check(S.Seek(High(Int64),soCurrent)=Size,'正向Seek溢出');
      S.Seek(-1,soBeginning);Check(S.Seek(Low(Int64),soCurrent)=-1,'负向Seek溢出');
      Check(S.Seek(High(Int64),soEnd)=Size,'从末尾Seek溢出');
      Check(S.Seek(Low(Int64),soEnd)=-1,'从末尾负向夹紧');
    end else if Name='read-overflow' then begin
      Check(S.Size=High(Int64),'稀疏测试总长度错误');S.Seek(High(Int64)-1,soBeginning);
      FillChar(B[0],2,$CC);N:=S.Read(B[0],2);
      Check((N=1) and (B[0]=10) and (B[1]=$CC) and (S.Position=High(Int64)),'Read加法溢出导致错误长度');
    end else raise Exception.Create('未知Probe用例');
  finally S.Free;F.Free;end;
end;
procedure TestCount(const N:Integer);
var F:THttpMultiPartFormData;S:THttpMultiPartFormStream;Streams:TArray<TPatternStream>;
  B:TBytes;I,InitCalls,ReadCalls,Calls:Integer;
begin
  F:=THttpMultiPartFormData.Create;F.Boundary:='count';SetLength(Streams,N);S:=nil;
  try
    for I:=0 to N-1 do begin Streams[I]:=TPatternStream.Create(16);F.AddFile(IntToStr(I),'data.bin',Streams[I],True);end;
    S:=THttpMultiPartFormStream.Create(F);InitCalls:=0;
    for I:=0 to N-1 do begin Inc(InitCalls,Streams[I].SizeCalls);Streams[I].SizeCalls:=0;end;
    B:=Drain(S,4096,Calls);ReadCalls:=0;for I:=0 to N-1 do Inc(ReadCalls,Streams[I].SizeCalls);
    Writeln(Format('COUNT fields=%d init=%d read=%d calls=%d bytes=%d',[N,InitCalls,ReadCalls,Calls,Length(B)]));
    Check(InitCalls=N,'初始化重复查询字段Size');Check(ReadCalls<=N+Calls+2,'顺序读取Size查询不是线性');
  finally S.Free;F.Free;end;
end;
procedure TestOwnership;
var F:TCountForm;S:THttpMultiPartFormStream;P:TPatternStream;OwnForm,OwnStream:Integer;D,E:Integer;
begin
  for OwnForm:=0 to 1 do for OwnStream:=0 to 1 do begin
    D:=DestroyedStreams;E:=DestroyedForms;F:=TCountForm.Create;P:=TPatternStream.Create(1);
    F.AddFile('p','p.bin',P,OwnStream=1);S:=THttpMultiPartFormStream.Create(F,OwnForm=1);S.Free;
    Check(DestroyedForms=E+OwnForm,'视图表单所有权');
    Check(DestroyedStreams=D+OwnForm*OwnStream,'视图底层流所有权');
    if OwnForm=0 then F.Free;if OwnStream=0 then P.Free;
    Check((DestroyedForms=E+1) and (DestroyedStreams=D+1),'资源析构重复或遗漏');
  end;
end;
procedure TestOwnershipFailure;
var F:TCountForm;S:THttpMultiPartFormStream;P:TPatternStream;Owned,D,E:Integer;Raised:Boolean;
begin
  for Owned:=0 to 1 do begin
    D:=DestroyedStreams;E:=DestroyedForms;F:=TCountForm.Create;P:=TPatternStream.Create(High(Int64));
    F.AddFile('bad','bad.bin',P,True);S:=nil;Raised:=False;
    try
      try S:=THttpMultiPartFormStream.Create(F,Owned=1);except on Error:EStreamError do Raised:=True;end;
      if S<>nil then begin S.Free;S:=nil;end;
      if Owned=1 then F:=nil;
      Check(Raised,'所有权用例未触发构造失败');
      Check((DestroyedForms=E+Owned) and (DestroyedStreams=D+Owned),'构造失败释放了借用资源或遗漏自有资源');
    finally F.Free;end;
    Check((DestroyedForms=E+1) and (DestroyedStreams=D+1),'构造失败后资源未释放一次');
  end;
end;
procedure TestSparse;
var F:THttpMultiPartFormData;S:THttpMultiPartFormStream;FileStream:TFileStream;
  Path:string;Huge:Int64;H,T,B:TBytes;Value:Byte;N:Integer;
  {$IFDEF MSWINDOWS}Returned:DWORD;{$ENDIF}
begin
  Path:=TempName;Huge:=(Int64(1) shl 31)+19;F:=THttpMultiPartFormData.Create;F.Boundary:='sparse';S:=nil;
  try
    FileStream:=TFileStream.Create(Path,fmCreate);
    try
      {$IFDEF MSWINDOWS}Returned:=0;Check(SparseControl(FileStream.Handle,$900C4,nil,0,nil,0,Returned,nil),'标记稀疏文件失败');{$ENDIF}
      FileStream.Position:=Huge-1;Value:=$7B;FileStream.WriteBuffer(Value,1);
      F.AddFile('large','large.bin',FileStream,True);
    except FileStream.Free;raise;end;
    H:=Header(F,0);T:=Ending(F);S:=THttpMultiPartFormStream.Create(F);
    Check(S.Size=Length(H)+Huge+Length(T),'>2GiB总长度被截断');
    SetLength(B,Length(T)+1);S.Seek(Length(H)+Huge-1,soBeginning);N:=S.Read(B[0],Length(B));
    Check((N=Length(B)) and (B[0]=$7B),'大文件末尾读取');
    Check(CompareMem(@B[1],@T[0],Length(T)),'大文件结束边界');
    S.Seek(Length(H)+(Int64(1) shl 30),soBeginning);Check(S.Read(B[0],4)=4,'稀疏洞读取');
    Check((B[0]=0) and (B[1]=0) and (B[2]=0) and (B[3]=0),'稀疏洞内容');
  finally S.Free;F.Free;if FileExists(Path) then Check(SysUtils.DeleteFile(Path),'稀疏文件未清理');end;
end;
procedure Bench(const Kind:string;const N,Block:Integer);
var F:THttpMultiPartFormData;S:THttpMultiPartFormStream;Bodies:TArray<TBytes>;Path:string;
  B:TBytes;Start,Elapsed,Bytes:Int64;Got:Integer;
begin
  MakeForm(N,65536,Kind='mixed',F,Bodies,Path);S:=nil;
  try
    S:=THttpMultiPartFormStream.Create(F);SetLength(B,Block);Bytes:=0;Start:=Ticks;
    repeat Got:=S.Read(B[0],Block);Inc(Bytes,Got);until Got=0;
    Elapsed:=Ticks-Start;Check(Bytes=S.Size,'基准未读完');
    Writeln(Format('BENCH %s fields=%d block=%d bytes=%d us=%.3f',[Kind,N,Block,Bytes,Elapsed*1000000.0/Frequency]));
  finally S.Free;F.Free;if Path<>'' then Check(SysUtils.DeleteFile(Path),'基准文件未清理');end;
end;
var Name:string;
begin
  {$IFDEF MSWINDOWS}QueryPerformanceFrequency(Frequency);{$ELSE}Frequency:=1000000000;{$ENDIF}
  try
    Name:=ParamStr(1);
    if Name='bench' then Bench(ParamStr(2),StrToInt(ParamStr(3)),StrToInt(ParamStr(4)))
    else begin
      if Copy(Name,1,5)='wire-' then TestWire(StrToInt(Copy(Name,6,20)))
      else if Copy(Name,1,6)='count-' then TestCount(StrToInt(Copy(Name,7,20)))
      else if Name='sparse-file' then TestSparse
      else if Name='ownership' then TestOwnership
      else if Name='ownership-init' then TestOwnershipFailure
      else TestProbe(Name);
      Writeln('PASS ',Name);
    end;
  except on E:Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
