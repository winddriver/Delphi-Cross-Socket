function PosixSend(ASocket: THandle; ABuf: Pointer;
  ALen: Integer): Integer;
var
  LBuf: PByte;
  LSent, LError: Integer;
  LFlags: Integer;
begin
  Result := 0;

  // 在向一个已经关闭的套接字发送数据时系统会直接抛出EPIPE异常导致程序非正常退出
  // LINUX下可以在send时带上MSG_NOSIGNAL参数就能避免这种情况的发生
  // OSX中可以通过设置套接字的SO_NOSIGPIPE参数达到同样的目的
  //{$IF defined(LINUX) or defined(ANDROID) or defined(FREEBSD)}
  {$IFNDEF MACOS}
  LFlags := MSG_NOSIGNAL;
  {$ELSE}
  LFlags := 0;
  {$ENDIF}

  LBuf := ABuf;
  while (Result < ALen) do
  begin
    LSent := TSocketAPI.Send(ASocket, LBuf^, ALen - Result, LFlags);

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
