{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.MbedBIO;

interface

uses
  System.SysUtils,
  System.IOUtils,
  Net.MbedTls;

const
  SSL_BIO_ERROR = -1;
  SSL_BIO_UNSET = -2;
  SSL_BIO_SIZE  = 16384; // default BIO write size if not set

  SSL_FAILED  = -1;
  SSL_SUCCESS = 0;

  // BIO_TYPE
  BIO_BUFFER = 1;
  BIO_SOCKET = 2;
  BIO_SSL    = 3;
  BIO_MEMORY = 4;
  BIO_BIO    = 5;
  BIO_FILE   = 6;

type
  PBIO = ^BIO;

  BIO = record
    prev: PBIO; // previous in chain
    next: PBIO; // next in chain
    pair: PBIO; // BIO paired with
    mem: PByte; // memory buffer
    wrSz: Integer; // write buffer size (mem)
    wrIdx: Integer; // current index for write buffer
    rdIdx: Integer; // current read index
    readRq: Integer; // read request
    memLen: Integer; // memory buffer length
    &type: Integer; // method type
  end;

  // 抽象 IO API
function SSL_BIO_new(&type: Integer): PBIO;
function BIO_make_bio_pair(b1, b2: PBIO): Integer;

function BIO_ctrl_pending(BIO: PBIO): Integer;
function BIO_set_write_buf_size(BIO: PBIO; size: Integer): Integer;

function BIO_read(BIO: PBIO; buf: Pointer; size: Integer): Integer;
function BIO_write(BIO: PBIO; buf: Pointer; size: Integer): Integer;

function BIO_free(BIO: PBIO): Integer;
function BIO_free_all(BIO: PBIO): Integer;

function BIO_net_recv(ctx: Pointer; buf: Pointer; size: Size_T): Integer; cdecl;
function BIO_net_send(ctx: Pointer; buf: Pointer; size: Size_T): Integer; cdecl;

implementation

// Return the number of pending bytes in read and write buffers
function BIO_ctrl_pending(BIO: PBIO): Integer;
var
  pair: PBIO;
begin
  if (BIO = nil) then
    Exit(0);

  if (BIO.&type = BIO_MEMORY) then
    Exit(BIO.memLen);

  // type BIO_BIO then check paired buffer
  if (BIO.&type = BIO_BIO) and (BIO.pair <> nil) then
  begin
    pair := BIO.pair;
    if (pair.wrIdx > 0) and (pair.wrIdx <= pair.rdIdx) then
      // in wrap around state where begining of buffer is being overwritten
      Exit(pair.wrSz - pair.rdIdx + pair.wrIdx)
    else
      // simple case where has not wrapped around
      Exit(pair.wrIdx - pair.rdIdx);
  end;

  Result := 0;
end;

function BIO_set_write_buf_size(BIO: PBIO; size: Integer): Integer;
begin
  if (BIO = nil) or (BIO.&type <> BIO_BIO) or (size < 0) then
    Exit(SSL_FAILED);

  // if already in pair then do not change size
  if BIO.pair <> nil then
    Exit(SSL_FAILED);

  BIO.wrSz := size;
  if (BIO.wrSz < 0) then
    Exit(SSL_FAILED);

  if (BIO.mem <> nil) then
    FreeMem(BIO.mem);

  GetMem(BIO.mem, BIO.wrSz);
  if (BIO.mem = nil) then
    Exit(SSL_FAILED);

  BIO.wrIdx := 0;
  BIO.rdIdx := 0;
  Result := SSL_SUCCESS;
end;

{ * Joins two BIO_BIO types. The write of b1 goes to the read of b2 and vise
  * versa. Creating something similar to a two way pipe.
 * Reading and writing between the two BIOs is not thread safe, they are
 * expected to be used by the same thread.
 * }
function BIO_make_bio_pair(b1, b2: PBIO): Integer;
begin
  if (b1 = nil) or (b2 = nil) then
    Exit(SSL_FAILED);

  // both are expected to be of type BIO and not already paired
  if (b1.&type <> BIO_BIO)
    or (b2.&type <> BIO_BIO) or (b1.pair <> nil) or (b2.pair <> nil) then
    Exit(SSL_FAILED);

  // set default write size if not already set
  if (b1.mem = nil)
    and (BIO_set_write_buf_size(b1, SSL_BIO_SIZE) <> SSL_SUCCESS) then
    Exit(SSL_FAILED);

  if (b2.mem = nil)
    and (BIO_set_write_buf_size(b2, SSL_BIO_SIZE) <> SSL_SUCCESS) then
    Exit(SSL_FAILED);

  b1.pair := b2;
  b2.pair := b1;
  Result := SSL_SUCCESS;
end;

// Does not advance read index pointer
function BIO_nread0(BIO: PBIO; buf: PPointer): Integer;
var
  pair: PBIO;
begin
  if (BIO = nil) or (buf = nil) then
    Exit(0);

  // if paired read from pair
  if (BIO.pair <> nil) then
  begin
    pair := BIO.pair;

    // case where have wrapped around write buffer
    buf^ := pair.mem + pair.rdIdx;
    if (pair.wrIdx > 0) and (pair.rdIdx >= pair.wrIdx) then
      Exit(pair.wrSz - pair.rdIdx)
    else
      Exit(pair.wrIdx - pair.rdIdx);
  end;

  Result := 0;
end;

function BIO_nread(BIO: PBIO; buf: PPointer; num: Integer): Integer;
var
  sz: Integer;
begin
  sz := SSL_BIO_UNSET;
  if (BIO = nil) or (buf = nil) then
    Exit(SSL_FAILED);

  if (BIO.pair <> nil) then
  begin
    // special case if asking to read 0 bytes
    if (num = 0) then
    begin
      buf^ := BIO.pair.mem + BIO.pair.rdIdx;
      Exit(0);
    end;

    // get amount able to read and set buffer pointer
    sz := BIO_nread0(BIO, buf);
    if (sz = 0) then
      Exit(SSL_BIO_ERROR);

    if (num < sz) then
      sz := num;

    BIO.pair.rdIdx := BIO.pair.rdIdx + sz;

    // check if have read to the end of the buffer and need to reset
    if (BIO.pair.rdIdx = BIO.pair.wrSz) then
    begin
      BIO.pair.rdIdx := 0;
      if (BIO.pair.wrIdx = BIO.pair.wrSz) then
        BIO.pair.wrIdx := 0;
    end;

    // check if read up to write index, if so then reset indexs
    if (BIO.pair.rdIdx = BIO.pair.wrIdx) then
    begin
      BIO.pair.rdIdx := 0;
      BIO.pair.wrIdx := 0;
    end;
  end;

  Result := sz;
end;

function BIO_nwrite(BIO: PBIO; buf: PPointer; num: Integer): Integer;
var
  sz: Integer;
begin
  sz := SSL_BIO_UNSET;
  if (BIO = nil) or (buf = nil) then
    Exit(0);

  if (BIO.pair <> nil) then
  begin
    if num = 0 then
    begin
      buf^ := BIO.mem + BIO.wrIdx;
      Exit(0);
    end;
    if (BIO.wrIdx < BIO.rdIdx) then
      // if wrapped around only write up to read index. In this case
      // rdIdx is always greater then wrIdx so sz will not be negative.
      sz := BIO.rdIdx - BIO.wrIdx
    else if (BIO.rdIdx > 0) and (BIO.wrIdx = BIO.rdIdx) then
      Exit(SSL_BIO_ERROR) // no more room to write
    else
    begin
      // write index is past read index so write to end of buffer
      sz := BIO.wrSz - BIO.wrIdx;
      if (sz <= 0) then
      begin
        // either an error has occured with write index or it is at the
        // end of the write buffer.
        if (BIO.rdIdx = 0) then
          // no more room, nothing has been read
          Exit(SSL_BIO_ERROR);

        BIO.wrIdx := 0;

        // check case where read index is not at 0
        if (BIO.rdIdx > 0) then
          sz := BIO.rdIdx // can write up to the read index
        else
          sz := BIO.wrSz; // no restriction other then buffer size
      end;
    end;

    if (num < sz) then
      sz := num;

    buf^ := BIO.mem + BIO.wrIdx;
    BIO.wrIdx := BIO.wrIdx + sz;

    // if at the end of the buffer and space for wrap around then set
    // write index back to 0
    if (BIO.wrIdx = BIO.wrSz) and (BIO.rdIdx > 0) then
      BIO.wrIdx := 0;
  end;

  Result := sz;
end;

// Reset BIO to initial state
function BIO_reset(BIO: PBIO): Integer;
begin
  if (BIO = nil) then
    // -1 is consistent failure even for FILE type
    Exit(SSL_BIO_ERROR);

  case BIO.&type of
    BIO_BIO:
      begin
        BIO.rdIdx := 0;
        BIO.wrIdx := 0;
        Exit(0);
      end;
  end;

  Result := SSL_BIO_ERROR;
end;

function BIO_read(BIO: PBIO; buf: Pointer; size: Integer): Integer;
var
  sz: Integer;
  pt: PPointer;
begin
  sz := BIO_nread(BIO, @pt, size);
  if (sz > 0) then
    Move(pt^, buf^, sz);

  Result := sz;
end;

function BIO_write(BIO: PBIO; buf: Pointer; size: Integer): Integer;
var
  sz: Integer;
  data: Pointer;
begin
  // internal function where arguments have already been sanity checked
  sz := BIO_nwrite(BIO, @data, size);

  // test space for write
  if (sz <= 0) then
    Exit(sz);

  Move(buf^, data^, sz);
  Result := sz;
end;

// support bio type only
function SSL_BIO_new(&type: Integer): PBIO;
begin
  GetMem(Result, SizeOf(BIO));
  FillChar(Result^, SizeOf(BIO), 0);
  Result.&type := &type;
end;

function BIO_free(BIO: PBIO): Integer;
begin
  // unchain?, doesn't matter in goahead since from free all
  if (BIO <> nil) then
  begin
    // remove from pair by setting the paired bios pair to nil
    if (BIO.pair <> nil) then
      BIO.pair.pair := nil;

    if (BIO.mem <> nil) then
      FreeMem(BIO.mem);

    FreeMem(BIO);
  end;

  Result := 0;
end;

function BIO_free_all(BIO: PBIO): Integer;
var
  next: PBIO;
begin
  while (BIO <> nil) do
  begin
    next := BIO.next;
    BIO_free(BIO);
    BIO := next;
  end;

  Result := 0;
end;

function BIO_net_send(ctx: Pointer; buf: Pointer; size: Size_T): Integer;
var
  BIO: PBIO;
  sz: Integer;
begin
  BIO := PBIO(ctx);
  sz := BIO_write(BIO, buf, size);
  if (sz <= 0) then
    Exit(MBEDTLS_ERR_SSL_WANT_WRITE);

  Result := sz;
end;

function BIO_net_recv(ctx: Pointer; buf: Pointer; size: Size_T): Integer;
var
  BIO: PBIO;
  sz: Integer;
begin
  BIO := PBIO(ctx);
  sz := BIO_read(BIO, buf, size);
  if (sz <= 0) then
    Exit(MBEDTLS_ERR_SSL_WANT_READ);

  Result := sz;
end;

end.
