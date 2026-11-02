program SourceAuditTests;

{$I zLib.inc}
{$IFNDEF FPC}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IF DEFINED(FPC) AND DEFINED(POSIX)}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, Utils.IOUtils, Utils.Hash, Utils.Punycode
  {$IFDEF FPC}, DTF.StreamEx{$ENDIF};

procedure Check(AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

type
  TShortStream = class(TMemoryStream)
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

function TShortStream.Read(var Buffer; Count: Longint): Longint;
begin
  if Count > 17 then Count := 17;
  Result := inherited Read(Buffer, Count);
end;

procedure TestHash;
var
  LData: TBytes;
  LExpected: string;
  LStream: TMemoryStream;
  I: Integer;
begin
  SetLength(LData, 65536);
  for I := 0 to High(LData) do LData[I] := Byte(I and 255);
  LExpected := THashSHA256.GetHashString(@LData[5], 32769);
  for I := 0 to 1 do
  begin
    if I = 0 then LStream := TMemoryStream.Create else LStream := TShortStream.Create;
    try
      LStream.WriteBuffer(LData[0], Length(LData));
      Check(THashSHA256.GetHashStringFromStream(LStream, 5, 32769) = LExpected, '指定范围的摘要不符');
      Check(LStream.Position = 32774, '超出指定范围');
    finally LStream.Free; end;
  end;
end;

procedure TestBufferedWrite;
var
  LStream: TFastFileStream;
  LBytes: TBytes;
  I: Integer;
begin
  SetLength(LBytes, 8);
  FillChar(LBytes[0], 8, 90);
  TFileUtils.WriteAllBytes('sample', LBytes);
  LStream := TFastFileStream.Create('sample', fmOpenReadWrite, 8);
  try
    FillChar(LBytes[0], 8, 65);
    LStream.WriteBuffer(LBytes[0], 8);
    LStream.Position := 2;
    LBytes[2] := 66;
    LStream.WriteBuffer(LBytes[2], 1);
    LStream.FlushBuffer;
    LStream.Position := 12;
    LStream.WriteBuffer(LBytes[2], 1);
  finally LStream.Free; end;
  LBytes := TFileUtils.ReadAllBytes('sample');
  Check(Length(LBytes) = 13, '随机写后长度不符');
  for I := 0 to 7 do
    if I = 2 then Check(LBytes[I] = 66, '覆盖字节丢失') else Check(LBytes[I] = 65, '旧缓冲覆盖了文件内容');
  for I := 8 to 11 do Check(LBytes[I] = 0, '稀疏区写入旧数据');
  Check(LBytes[12] = 66, '文件末尾缺失');
end;

procedure TestMove;
var
  LData: TBytes;
begin
  SetLength(LData, 1);
  LData[0] := 5;
  TFileUtils.WriteAllBytes('original', LData);
  Check(TFileUtils.Move('original', '.' + PathDelim + 'original'), '移动至本身应成功');
  Check(TFileUtils.ReadAllBytes('original')[0] = 5, '同一文件被删除');
  LData[0] := 6;
  TFileUtils.WriteAllBytes('destination', LData);
  Check(not TFileUtils.Move('absent', 'destination'), '源不存在时错误返回成功');
  Check(TFileUtils.ReadAllBytes('destination')[0] = 6, '失败后目标改变');
  Check(TFileUtils.Move('original', 'destination'), '替换目标失败');
  Check(not FileExists('original') and (TFileUtils.ReadAllBytes('destination')[0] = 5), '替换结果错误');
end;

procedure TestPunycode;
var
  S: string;
  LRejected: Boolean;
begin
  S := #$D840#$DC00;
  Check(TPunycode.EncodeDomain(S + '.test') = 'xn--j50i.test', '扩展汉字编码失败');
  Check(TPunycode.DecodeDomain('xn--J50I.test') = S + '.test', '扩展汉字解码失败');
  S := 'a' + S + 'ü' + S;
  Check(TPunycode.Decode(TPunycode.Encode(S)) = S, '多种码点混合的标签不对称');
  Check(TPunycode.EncodeDomain('bücher.test') = 'xn--bcher-kva.test', 'BMP 编码变化');
  LRejected := False;
  try TPunycode.Encode(#$D800); except on EPunycode do LRejected := True; end;
  Check(LRejected, '接受了未配对的代理项');
end;

{$IFDEF FPC}
procedure TestReader;
var
  LStream: TBytesStream;
  LReader: DTF.StreamEx.TStreamReader;
begin
  LStream := TBytesStream.Create(TEncoding.UTF8.GetBytes('AB'#13#10'C'));
  try
    LReader := DTF.StreamEx.TStreamReader.Create(LStream, TEncoding.UTF8, False, 128);
    try
      Check((LReader.Peek = 65) and (LReader.Read = 65), '第一个字符错误');
      Check(LReader.ReadLine = 'B', '换行定位错误');
      Check((LReader.Read = 67) and (LReader.Read = -1), '尾字符或 EOF 错误');
    finally LReader.Free; end;
  finally LStream.Free; end;
end;
{$ENDIF}

begin
  try
    if ParamStr(1) = 'hash' then TestHash
    else if ParamStr(1) = 'buffer' then TestBufferedWrite
    else if ParamStr(1) = 'move' then TestMove
    else if ParamStr(1) = 'punycode' then TestPunycode
    {$IFDEF FPC}else if ParamStr(1) = 'reader' then TestReader{$ENDIF}
    else raise Exception.Create('未知用例');
    Writeln('PASS ', ParamStr(1));
  except
    on E: Exception do begin Writeln('FAIL ', ParamStr(1), ' ', E.Message); Halt(1); end;
  end;
end.
