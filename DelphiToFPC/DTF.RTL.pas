unit DTF.RTL;

{$I zLib.inc}

interface

uses
  SysUtils
  ,Classes

  {$IFDEF MSWINDOWS}
  ,Windows
  {$ELSE}
  ,BaseUnix
  {$ENDIF}
  ;

const
  INFINITE = Cardinal(-1);

  {$IF DEFINED(FPC) AND NOT DEFINED(MSWINDOWS)}
  EINTR       = ESysEINTR;
  EAGAIN      = ESysEAGAIN;
  EWOULDBLOCK = ESysEWOULDBLOCK;
  EMFILE      = ESysEMFILE;
  EINPROGRESS = ESysEINPROGRESS;

  AI_PASSIVE  = $00000001;
 {$ENDIF}

function GetLastError: Integer; inline;

function GrowCollection(const AOldCapacity, ANewCount: Integer): Integer;

implementation

function GetLastError: Integer;
begin
  {$IFDEF MSWINDOWS}
  Result := Windows.GetLastError;
  {$ELSE}
  Result := fpgeterrno;
  {$ENDIF}
end;

function GrowCollection(const AOldCapacity, ANewCount: Integer): Integer;
begin
  Result := AOldCapacity;

  repeat
    if Result > 64 then
      Result := (Result * 3) div 2
    else
      if Result > 8 then
        Result := Result + 16
      else
        Result := Result + 4;
    if Result < 0 then
      OutOfMemoryError;
  until (Result >= ANewCount);
end;

end.
