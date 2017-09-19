function PosixSend(ASocket: THandle; ABuf: Pointer;
  ALen: Integer): Integer;
var
  LBuf: PByte;
  LSent, LError: Integer;
begin
  Result := 0;

  LBuf := ABuf;
  while (Result < ALen) do
  begin
    LSent := TSocketAPI.Send(ASocket, LBuf^, ALen - Result);
//    LSent := Posix.UniStd.__write(ASocket, LBuf, ALen - Result);

    if (LSent < 0) then
    begin
      LError := GetLastError;

      // 被系统信号中断, 可以重新send
      if (LError = EINTR) then
        Continue
      // 发送缓冲区已被填满了
      else if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
        Break
      // 发送出错
      else
        Exit(-1);
    end;

    Inc(Result, LSent);
    Inc(LBuf, LSent);
  end;
end;
