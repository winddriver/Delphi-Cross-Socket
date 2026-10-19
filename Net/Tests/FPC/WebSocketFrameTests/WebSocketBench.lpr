program WebSocketBench;
{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}
{$O+}
uses SysUtils, Classes, Windows, Net.CrossWebSocketParser;
procedure Feed(const P:TCrossWebSocketParser;const W:TBytes;const Chunk:Integer);
var Pos,N,Remain:Integer;B:Pointer;
begin
  Pos:=0;
  while Pos<Length(W) do begin
    N:=Length(W)-Pos;if (Chunk>0) and (N>Chunk) then N:=Chunk;
    B:=@W[Pos];Remain:=N;P.Decode(B,Remain);
    if Remain<>0 then raise Exception.Create('输入未消费');
    Inc(Pos,N);
  end;
end;
procedure Bench;
var CaseId,Size,Count,I,Chunk:Integer;Code:Byte;Masked:Boolean;
    Data,Wire:TBytes; P:TCrossWebSocketParser; Start,Finish,Freq:Int64;
    Events,Bytes:Int64;Name:string;
begin
  if SetThreadAffinityMask(GetCurrentThread,1)=0 then raise Exception.Create('CPU affinity failed');
  QueryPerformanceFrequency(Freq);
  Writeln('INSTANCE ',TCrossWebSocketParser.InstanceSize);
  for CaseId:=0 to 16 do begin
    Size:=32;Masked:=False;Code:=2;Chunk:=0;
    case CaseId of
      0:Name:='binary32';
      1:begin Name:='masked32';Masked:=True;end;
      2:begin Name:='binary64k';Size:=65536;end;
      3:begin Name:='masked64k';Size:=65536;Masked:=True;end;
      4:begin Name:='text32';Code:=1;end;
      5:begin Name:='text64k';Code:=1;Size:=65536;end;
      6:begin Name:='ping0';Code:=9;Size:=0;end;
      7:begin Name:='ping125';Code:=9;Size:=125;end;
      8:begin Name:='bytewise32';Chunk:=1;end;
      9:begin Name:='masked-bytewise32';Chunk:=1;Masked:=True;end;
      10:begin Name:='text-bytewise32';Chunk:=1;Code:=1;end;
      11:begin Name:='binary1';Size:=1;end;
      12:begin Name:='text0';Size:=0;Code:=1;end;
      13:begin Name:='unicode32';Code:=1;end;
      14:begin Name:='unicode-bytewise32';Code:=1;Chunk:=1;end;
      15:begin Name:='unicode-masked-bytewise32';Code:=1;Chunk:=1;Masked:=True;end;
      16:begin Name:='unicode64k';Code:=1;Size:=65536;end;
    end;
    SetLength(Data,Size);for I:=0 to Size-1 do Data[I]:=65+(I mod 26);
    if CaseId>=13 then
      for I:=0 to Size-1 do
        case I and 3 of 0:Data[I]:=$F0;1:Data[I]:=$9F;2:Data[I]:=$98;3:Data[I]:=$80;end;
    if Size=0 then Wire:=TCrossWebSocketParser.MakeFrameData(Code,True,not Masked,nil,0)
    else Wire:=TCrossWebSocketParser.MakeFrameData(Code,True,not Masked,@Data[0],Size);
    Count:=(16*1024*1024) div Length(Wire);if Count<128 then Count:=128;if Count>500000 then Count:=500000;
    Events:=0;Bytes:=0;
    P:=TCrossWebSocketParser.Create(
      procedure(const Op:Byte;const D:TBytes)begin Inc(Events);Inc(Bytes,Length(D));end,
      procedure(const K:TWsMessageType;const D:TBytes)begin Inc(Events);Inc(Bytes,Length(D));end,
      procedure begin raise Exception.Create('合法性能输入被拒绝');end);
    try
      {$IFDEF WS_NEW_API}
      P.AllowedRsvBits:=0;P.CheckTextUtf8:=True;
      if Masked then P.Role:=wprServer else P.Role:=wprClient;
      {$ENDIF}
      for I:=1 to 32 do Feed(P,Wire,Chunk);
      Events:=0;Bytes:=0;QueryPerformanceCounter(Start);
      for I:=1 to Count do Feed(P,Wire,Chunk);
      QueryPerformanceCounter(Finish);
      if (Events<>Count) or (Bytes<>Int64(Count)*Size) then raise Exception.Create('性能用例输出错误');
      Writeln(Format('BENCH %s ms=%.3f n=%d',[Name,(Finish-Start)*1000.0/Freq,Count]));
    finally P.Free;end;
  end;
end;
begin
  try Bench;except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
