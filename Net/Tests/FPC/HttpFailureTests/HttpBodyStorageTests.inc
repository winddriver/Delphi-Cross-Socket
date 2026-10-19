function StorageFileCount(const APath: string): Integer;
var
  F: TSearchRec;
begin
  Result := 0;
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faAnyFile, F) <> 0 then Exit;
  try
    repeat
      if (F.Name <> '.') and (F.Name <> '..') then Inc(Result);
    until FindNext(F) <> 0;
  finally
    FindClose(F);
  end;
end;

procedure TestBodyStorage(const ACase: string);
const
  GZIP_64: array[0..23] of Byte = ($1f,$8b,$08,$00,$00,$00,$00,$00,$02,$ff,$ab,$a8,
    $a0,$0c,$00,$00,$12,$ac,$d2,$3a,$40,$00,$00,$00);
var
  LServerObject: TQueueServer;
  LServer: ICrossHttpServer;
  LObject: TMemoryConnection;
  LConnection: ICrossHttpConnection;
  LRequest: ICrossHttpRequest;
  LResponse: ICrossHttpResponse;
  LDirectory, LStoragePath, LLine: string;
  LId: TGUID;
  LHeader, LWire, LExpected, LChunk: AnsiString;
  LRead: TBytes;
  LLimit, LThreshold, LBodySize: Int64;
  LDisk, LReject, LPartial, LBench: Boolean;
  I, LBlocks: Integer;
  LFile: TFileStream;
  procedure Check(const AValue: Boolean; const AMessage: string);
  begin
    // 本组有临时文件，红例也必须展开 finally 后再由主程序返回非零。
    if not AValue then raise Exception.Create(AMessage);
  end;
begin
  CreateGUID(LId);
  LDirectory := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'body-' + GUIDToString(LId);
  ForceDirectories(LDirectory);
  LStoragePath := LDirectory;
  LThreshold := 16;
  LBodySize := 32;
  LLimit := 0;
  LDisk := True;
  LReject := ACase.StartsWith('limit-') or (ACase = 'disk-error');
  LPartial := ACase = 'disconnect';
  LBench := ACase.StartsWith('bench-');
  if ACase = 'default' then begin LThreshold := 0; LDisk := False; end;
  if ACase = 'below' then begin LBodySize := 15; LDisk := False; end;
  if ACase = 'equal' then begin LBodySize := 16; LDisk := False; end;
  if ACase = 'form' then begin LDisk := False; LThreshold := 2; end;
  if ACase = 'large-limit' then LLimit := Int64(High(Cardinal)) + 5;
  if ACase = 'limit-plain' then LLimit := 20;
  if ACase = 'limit-gzip' then LLimit := 32;
  if LBench then
  begin
    LBodySize := 32 * 1024 * 1024;
    LThreshold := 128 * 1024;
    if ACase = 'bench-memory' then begin LThreshold := 0; LDisk := False; end;
  end;
  if (ACase = 'disk-error') or (ACase = 'separate-path') then
  begin
    LStoragePath := IncludeTrailingPathDelimiter(LDirectory) + 'not-a-directory';
    LFile := TFileStream.Create(LStoragePath, fmCreate);
    LFile.Free;
  end;
  LServerObject := TQueueServer.Create;
  LServer := LServerObject;
  LServerObject.StoragePath := LStoragePath;
  LServerObject.AutoDeleteFiles := False;
  LServerObject.MaxPostDataSize := LLimit;
  if ACase = 'large-header-limit' then LServerObject.MaxHeaderSize := Int64(High(Cardinal)) + 5;
  {$IFDEF HTTP_BODY_STORAGE}
  LServerObject.BodyMemoryThreshold := LThreshold;
  {$ENDIF}
  {$IFDEF HTTP_BODY_TEMP_PATH}
  if ACase = 'disk-error' then LServerObject.BodyTempPath := LStoragePath
  else LServerObject.BodyTempPath := LDirectory;
  {$ENDIF}
  LObject := TMemoryConnection.Create(LServerObject);
  LConnection := LObject;
  try
    if LBench then
    begin
      Writeln('BASELINE'); Flush(Output); Readln(LLine);
      LObject.Feed('POST /storage HTTP/1.1'#13#10'Host: localhost'#13#10 +
        'Content-Type: application/octet-stream'#13#10'Content-Length: ' + AnsiString(IntToStr(LBodySize)) + #13#10#13#10);
      LChunk := AnsiString(StringOfChar('x', 65536));
      LBlocks := LBodySize div Length(LChunk);
      for I := 1 to LBlocks do LObject.Feed(LChunk);
      LExpected := '';
    end
    else
    begin
      LExpected := AnsiString(StringOfChar('x', LBodySize));
      LWire := LExpected;
      LHeader := 'POST /storage HTTP/1.1'#13#10'Host: localhost'#13#10;
      if ACase = 'form' then
      begin
        LHeader := LHeader + 'Content-Type: application/x-www-form-urlencoded'#13#10;
        LWire := 'name=abcdefghijklmnopqrstuvwxyz'; LExpected := LWire;
      end
      else LHeader := LHeader + 'Content-Type: application/octet-stream'#13#10;
      if (ACase = 'gzip') or (ACase = 'limit-gzip') then
      begin
        LHeader := LHeader + 'Content-Encoding: gzip'#13#10;
        SetString(LWire, PAnsiChar(@GZIP_64[0]), Length(GZIP_64));
        LExpected := AnsiString(StringOfChar('x', 64));
      end;
      if (ACase = 'chunked') or (ACase = 'large-limit') then
      begin
        LHeader := LHeader + 'Transfer-Encoding: chunked'#13#10#13#10;
        LWire := AnsiString(IntToHex(Length(LWire), 1)) + #13#10 + LWire + #13#10'0'#13#10#13#10;
      end
      else LHeader := LHeader + 'Content-Length: ' + AnsiString(IntToStr(Length(LWire) + Ord(LPartial))) + #13#10#13#10;
      // 逐段输入，确保越过阈值发生在接收过程中。
      LObject.Feed(LHeader);
      try
        for I := 1 to Length(LWire) do LObject.Feed(Copy(LWire, I, 1));
      except
        // 生产事件层会隔离 Parser 由正文异常生成的终止信号。
        on E: EAbort do if ACase <> 'disk-error' then raise;
      end;
    end;
    if LReject or LPartial then
    begin
      Check(LServerObject.Responses.Count = 0, '失败或未完成正文进入了业务');
      if LPartial then Check(StorageFileCount(LDirectory) = 1, '接收途中未按阈值落盘');
      LObject.CompleteWrites;
      LObject.Cleanup;
      if ACase = 'disk-error' then DeleteFile(LStoragePath);
      Check(StorageFileCount(LDirectory) = 0, '失败/断开后残留临时正文');
      Exit;
    end;
    Check(LServerObject.Responses.Count = 1, '合法正文未进入业务: ' + string(LObject.Sent));
    LResponse := LServerObject.Responses[0];
    LRequest := LResponse.Request;
    Check(LRequest.RawBody <> nil, '缺少可读的原始正文流');
    Check((LRequest.RawBody is TMemoryStream) = not LDisk, '正文存储与阈值不一致');
    Check(StorageFileCount(LDirectory) = Ord(LDisk) + Ord(ACase = 'separate-path'), '临时文件数量错误');
    if LBench then
    begin
      Writeln('MEMORY_READY'); Flush(Output); Readln(LLine);
      Check(LRequest.RawBody.Size = LBodySize, '大正文尺寸错误');
      SetLength(LRead, 65536);
      while LRequest.RawBody.Position < LRequest.RawBody.Size do
      begin
        LRequest.RawBody.ReadBuffer(LRead[0], Length(LRead));
        for I := 0 to High(LRead) do Check(LRead[I] = Ord('x'), '大正文内容错误');
      end;
    end
    else
    begin
      Check(LRequest.RawBody.Size = Length(LExpected), '原始正文尺寸错误');
      SetLength(LRead, Length(LExpected));
      LRequest.RawBody.ReadBuffer(LRead[0], Length(LRead));
      Check(CompareMem(@LRead[0], PAnsiChar(LExpected), Length(LRead)), '原始正文发生变化');
    end;
    LResponse.SendNoCompress('ok');
    LObject.CompleteWrites;
    LObject.Cleanup;
    LServerObject.Responses.Clear;
    LResponse := nil;
    Check(StorageFileCount(LDirectory) = Ord(LDisk) + Ord(ACase = 'separate-path'), '外部仍持请求时提前删除正文');
    // 连接有意保留最近完整请求，释放该缓存所有者后只剩测试持有的请求引用。
    LConnection := nil;
    LObject := nil;
    LRequest.RawBody.Position := 0;
    Check(LRequest.RawBody.Read(LRead[0], 1) = 1, '连接关闭后保留的请求正文不可读');
    LRequest := nil;
    if ACase = 'separate-path' then DeleteFile(LStoragePath);
    Check(StorageFileCount(LDirectory) = 0, '请求释放后未删除临时正文');
  finally
    if LObject <> nil then
    begin
      LObject.Cleanup;
      LObject.CompleteWrites;
    end;
    LServerObject.Responses.Clear;
    LResponse := nil; LRequest := nil;
    LConnection := nil; LServer := nil;
    if (ACase = 'disk-error') or (ACase = 'separate-path') then DeleteFile(LStoragePath);
    Check(StorageFileCount(LDirectory) = 0, '测试退出后有临时文件残留');
    Check(RemoveDir(LDirectory), '专用空测试目录未清理');
  end;
end;
