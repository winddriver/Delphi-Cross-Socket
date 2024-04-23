{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket;

{$I zLib.inc}

interface

uses
  Net.CrossSocket.Base,
  {$IFDEF MSWINDOWS}
  Net.CrossSocket.Iocp
  {$ELSEIF defined(MACOS) or defined(BSD)}
  Net.CrossSocket.Kqueue
  {$ELSEIF defined(LINUX) or defined(ANDROID)}
  Net.CrossSocket.Epoll
  {$ENDIF};

type
  TCrossListen =
    {$IFDEF MSWINDOWS}
    TIocpListen
    {$ELSEIF defined(MACOS) or defined(BSD)}
    TKqueueListen
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollListen
    {$ENDIF};

  TCrossConnection =
    {$IFDEF MSWINDOWS}
    TIocpConnection
    {$ELSEIF defined(MACOS) or defined(BSD)}
    TKqueueConnection
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollConnection
    {$ENDIF};

  TCrossSocket =
    {$IFDEF MSWINDOWS}
    TIocpCrossSocket
    {$ELSEIF defined(MACOS) or defined(BSD)}
    TKqueueCrossSocket
    {$ELSEIF defined(LINUX) or defined(ANDROID)}
    TEpollCrossSocket
    {$ENDIF};

implementation

end.

