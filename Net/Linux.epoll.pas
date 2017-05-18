{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 Souledge(soulawing@gmail.com) QQ:21305383         }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Linux.epoll;

interface

uses
  Posix.Base;

const
  EPOLLIN  = $01; { The associated file is available for read(2) operations. }
  EPOLLPRI = $02; { There is urgent data available for read(2) operations. }
  EPOLLOUT = $04; { The associated file is available for write(2) operations. }
  EPOLLERR = $08; { Error condition happened on the associated file descriptor. }
  EPOLLHUP = $10; { Hang up happened on the associated file descriptor. }
  EPOLLONESHOT = $40000000; { Sets the One-Shot behaviour for the associated file descriptor. }
  EPOLLET  = $80000000; { Sets  the  Edge  Triggered  behaviour  for  the  associated file descriptor. }

  { Valid opcodes ( "op" parameter ) to issue to epoll_ctl }
  EPOLL_CTL_ADD = 1;
  EPOLL_CTL_DEL = 2;
  EPOLL_CTL_MOD = 3;

type
  EPoll_Data = record
    case integer of
      0: (ptr: pointer);
      1: (fd: Integer);
      2: (u32: Cardinal);
      3: (u64: UInt64);
  end;
  TEPoll_Data =  Epoll_Data;
  PEPoll_Data = ^Epoll_Data;

  EPoll_Event = packed record
    Events: Cardinal;
    Data  : TEpoll_Data;
  end;

  TEPoll_Event =  Epoll_Event;
  PEpoll_Event = ^Epoll_Event;

{ open an epoll file descriptor }
function epoll_create(size: Integer): Integer; cdecl;
  external libc name _PU + 'epoll_create';
  {$EXTERNALSYM epoll_create}

{ control interface for an epoll descriptor }
function epoll_ctl(epfd, op, fd: Integer; event: pepoll_event): Integer; cdecl;
  external libc name _PU + 'epoll_ctl';
  {$EXTERNALSYM epoll_ctl}

{ wait for an I/O event on an epoll file descriptor }
function epoll_wait(epfd: Integer; events: pepoll_event; maxevents, timeout: Integer): Integer; cdecl;
  external libc name _PU + 'epoll_wait';
  {$EXTERNALSYM epoll_wait}

implementation

end.
