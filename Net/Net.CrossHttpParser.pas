{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpParser;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Math,
  ZLib,

  Net.CrossHttpUtils,

  Utils.StrUtils;

type
  TCrossHttpParseState = (psIdle, psHeader, psBodyData, psChunkSize, psChunkData, psChunkEnd, psDone);

  TOnHeaderData = procedure(const ADataPtr: Pointer; const ADataSize: Integer) of object;
  TOnGetHeaderValue = function(const AHeaderName: string; out AHeaderValue: string): Boolean of object;
  TOnBodyBegin = procedure of object;
  TOnBodyData = procedure(const ADataPtr: Pointer; const ADataSize: Integer) of object;
  TOnBodyEnd = procedure of object;
  TOnParseBegin = procedure of object;
  TOnParseSuccess = procedure of object;
  TOnParseFailed = procedure(const ACode: Integer; const AError: string) of object;

  TCrossHttpParser = class
  private
    FMaxHeaderSize, FMaxBodyDataSize: Integer;
    FOnHeaderData: TOnHeaderData;
    FOnGetHeaderValue: TOnGetHeaderValue;
    FOnBodyBegin: TOnBodyBegin;
    FOnBodyData: TOnBodyData;
    FOnBodyEnd: TOnBodyEnd;
    FOnParseBegin: TOnParseBegin;
    FOnParseSuccess: TOnParseSuccess;
    FOnParseFailed: TOnParseFailed;

    FContentLength: Int64;
    FTransferEncoding, FContentEncoding, FConnectionStr: string;
    FIsChunked: Boolean;

    FParsedBodySize: Int64;
    FParseState: TCrossHttpParseState;
    FCRCount, FLFCount: Integer;
    FHeaderStream, FChunkSizeStream: TMemoryStream;
    FChunkSize, FChunkLeftSize: Integer;
    FHasBody: Boolean;

    // 动态解压
    FZCompressed: Boolean;
    FZStream: TZStreamRec;
    FZFlush: Integer;
    FZResult: Integer;
    FZOutSize: Integer;
    FZBuffer: TBytes;

    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValue: string): Boolean;
    procedure _OnBodyBegin;
    procedure _OnBodyData(const ADataPtr: Pointer; const ADataSize: Integer);
    procedure _OnBodyEnd;
    procedure _OnParseBegin;
    procedure _OnParseSuccess;
    procedure _OnParseFailed(const ACode: Integer; const AError: string);

    procedure _Reset;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Decode(var ABuf: Pointer; var ALen: Integer);

    property MaxHeaderSize: Integer read FMaxHeaderSize write FMaxHeaderSize;
    property MaxBodyDataSize: Integer read FMaxBodyDataSize write FMaxBodyDataSize;

    property OnHeaderData: TOnHeaderData read FOnHeaderData write FOnHeaderData;
    property OnGetHeaderValue: TOnGetHeaderValue read FOnGetHeaderValue write FOnGetHeaderValue;
    property OnBodyBegin: TOnBodyBegin read FOnBodyBegin write FOnBodyBegin;
    property OnBodyData: TOnBodyData read FOnBodyData write FOnBodyData;
    property OnBodyEnd: TOnBodyEnd read FOnBodyEnd write FOnBodyEnd;
    property OnParseBegin: TOnParseBegin read FOnParseBegin write FOnParseBegin;
    property OnParseSuccess: TOnParseSuccess read FOnParseSuccess write FOnParseSuccess;
    property OnParseFailed: TOnParseFailed read FOnParseFailed write FOnParseFailed;
  end;

implementation

{ TCrossHttpParser }

constructor TCrossHttpParser.Create;
begin
  FHeaderStream := TMemoryStream.Create;
  FParseState := psIdle;
end;

destructor TCrossHttpParser.Destroy;
begin
  if (FParseState = psBodyData) and FHasBody then
  begin
    FParseState := psDone;
    _OnBodyEnd;
    _OnParseSuccess;
  end;

  FreeAndNil(FHeaderStream);

  inherited;
end;

procedure TCrossHttpParser.Decode(var ABuf: Pointer; var ALen: Integer);
var
  LPtr, LPtrEnd: PByte;
  LChunkSize: Integer;
  LLineStr, LContentLength: string;
begin
  {
  HTTP/1.1 200 OK
  Content-Type: application/json;charset=utf-8
  Content-Encoding: gzip
  Transfer-Encoding: chunked
  }
  {
  HTTP/1.1 200 OK
  Content-Type: text/plain
  Transfer-Encoding: chunked

  7\r\n
  Chunk 1\r\n
  6\r\n
  Chunk 2\r\n
  0\r\n
  \r\n
  }

  try
    if (FParseState = psIdle) then
    begin
      FParseState := psHeader;
      _OnParseBegin;
    end;

    // 在这里解析服务端发送过来的响应数据
    LPtr := ABuf;
    LPtrEnd := LPtr + ALen;

    // 使用循环处理粘包, 比递归调用节省资源
    while (LPtr < LPtrEnd) and (FParseState <> psDone) do
    begin
      case FParseState of
        psHeader:
          begin
            case LPtr^ of
              13{\r}: Inc(FCRCount);
              10{\n}: Inc(FLFCount);
            else
              FCRCount := 0;
              FLFCount := 0;
            end;

            // Header尺寸超标
            if (FMaxHeaderSize > 0) and (FHeaderStream.Size + 1 > FMaxHeaderSize) then
            begin
              _OnParseFailed(400, 'Request header too large.');
              Exit;
            end;

            // 写入请求数据
            FHeaderStream.Write(LPtr^, 1);
            Inc(LPtr);

            // HTTP头已接收完毕(\r\n\r\n是HTTP头结束的标志)
            if (FCRCount = 2) and (FLFCount = 2) then
            begin
              FCRCount := 0;
              FLFCount := 0;

              // 调用解码Header的回调
              _OnHeaderData(FHeaderStream.Memory, FHeaderStream.Size);

              // 数据体长度
              _OnGetHeaderValue(HEADER_CONTENT_LENGTH, LContentLength);

              // 数据的编码方式
              // 只有一种编码方式: chunked
              // 如果 Transfer-Encoding 不存在于 Header 中, 则数据是连续的, 不采用分块编码
              // 理论上 Transfer-Encoding 和 Content-Length 只应该存在其中一个
              _OnGetHeaderValue(HEADER_TRANSFER_ENCODING, FTransferEncoding);

              // 数据的压缩方式
              // 可能的值为: gzip deflate br 其中之一
              // br: Brotli压缩算法, Brotli通常比gzip和deflate更高效
              _OnGetHeaderValue(HEADER_CONTENT_ENCODING, FContentEncoding);

              // 读取响应头中连接保持方式
              _OnGetHeaderValue(HEADER_CONNECTION, FConnectionStr);

              FContentLength := StrToInt64Def(LContentLength, -1);
              FIsChunked := TStrUtils.SameText(FTransferEncoding, 'chunked');

              // 响应头中没有 Content-Length,Transfer-Encoding
              // 然后还是保持连接的, 这一定是非法数据
              if (FContentLength < 0) and not FIsChunked
                and TStrUtils.SameText(FConnectionStr, 'keep-alive') then
              begin
                _OnParseFailed(400, 'Invalid response data.');
                Exit;
              end;

              // 先通过响应头中的内容大小检查下是否超大了
              if (FMaxBodyDataSize > 0) and (FContentLength > FMaxBodyDataSize) then
              begin
                _OnParseFailed(400, 'Post data too large.');
                Exit;
              end;

              // 是否有body数据
              // 如果 ContentLength 大于 0, 或者是 Chunked 编码
              //   还有种特殊情况就是 ContentLength 和 Chunked 都没有
              //   并且响应头中包含 Connection: close
              //   这种需要在连接断开时处理body
              FHasBody := (FContentLength > 0) or FIsChunked
                or TStrUtils.SameText(FConnectionStr, 'close');

              // 如果需要接收 body 数据
              if FHasBody then
              begin
                FParsedBodySize := 0;

                if FIsChunked then
                begin
                  FParseState := psChunkSize;
                  FChunkSizeStream := TMemoryStream.Create;
                end else
                  FParseState := psBodyData;

                _OnBodyBegin();
              end else
              begin
                FParseState := psDone;
                Break;
              end;
            end;
          end;

        // 非Chunked编码的Post数据(有 ContentLength)
        psBodyData:
          begin
            LChunkSize := LPtrEnd - LPtr;
            if (FContentLength > 0) then
              LChunkSize := Min(FContentLength - FParsedBodySize, LChunkSize);
            if (FMaxBodyDataSize > 0) and (FParsedBodySize + LChunkSize > FMaxBodyDataSize) then
            begin
              _OnParseFailed(400, 'Post data too large.');
              Exit;
            end;

            _OnBodyData(LPtr, LChunkSize);

            Inc(FParsedBodySize, LChunkSize);
            Inc(LPtr, LChunkSize);

            if (FContentLength > 0) and (FParsedBodySize >= FContentLength) then
            begin
              FParseState := psDone;
              _OnBodyEnd();
              Break;
            end;
          end;

        // Chunked编码: 块尺寸
        psChunkSize:
          begin
            case LPtr^ of
              13{\r}: Inc(FCRCount);
              10{\n}: Inc(FLFCount);
            else
              FCRCount := 0;
              FLFCount := 0;
              FChunkSizeStream.Write(LPtr^, 1);
            end;
            Inc(LPtr);

            if (FCRCount = 1) and (FLFCount = 1) then
            begin
              SetString(LLineStr, MarshaledAString(FChunkSizeStream.Memory), FChunkSizeStream.Size);
              FParseState := psChunkData;
              FChunkSize := StrToIntDef('$' + Trim(LLineStr), -1);
              FChunkLeftSize := FChunkSize;
            end;
          end;

        // Chunked编码: 块数据
        psChunkData:
          begin
            if (FChunkLeftSize > 0) then
            begin
              LChunkSize := Min(FChunkLeftSize, LPtrEnd - LPtr);
              if (FMaxBodyDataSize > 0) and (FParsedBodySize + LChunkSize > FMaxBodyDataSize) then
              begin
                _OnParseFailed(400, 'Post data too large.');
                Exit;
              end;

              _OnBodyData(LPtr, LChunkSize);

              Inc(FParsedBodySize, LChunkSize);
              Dec(FChunkLeftSize, LChunkSize);
              Inc(LPtr, LChunkSize);
            end;

            if (FChunkLeftSize <= 0) then
            begin
              FParseState := psChunkEnd;
              FCRCount := 0;
              FLFCount := 0;
            end;
          end;

        // Chunked编码: 块结束符\r\n
        psChunkEnd:
          begin
            case LPtr^ of
              13{\r}: Inc(FCRCount);
              10{\n}: Inc(FLFCount);
            else
              FCRCount := 0;
              FLFCount := 0;
            end;
            Inc(LPtr);

            if (FCRCount = 1) and (FLFCount = 1) then
            begin
              // 最后一块的ChunSize为0
              if (FChunkSize > 0) then
              begin
                FParseState := psChunkSize;
                FChunkSizeStream.Clear;
                FCRCount := 0;
                FLFCount := 0;
              end else
              begin
                FParseState := psDone;
                FreeAndNil(FChunkSizeStream);
                _OnBodyEnd();
                Break;
              end;
            end;
          end;
      end;
    end;

    // 响应数据接收完毕
    if (FParseState = psDone) then
    begin
      _Reset;
      _OnParseSuccess();
    end;

    ABuf := LPtr;
    ALen := LPtrEnd - LPtr;
  except
    on e: Exception do
    begin
      if not (e is EAbort) then
        _OnParseFailed(500, e.Message);
    end;
  end;
end;

procedure TCrossHttpParser._OnBodyBegin;
var
  LCompressType: TCompressType;
begin
  FZCompressed := False;
  LCompressType := ctNone;

  // 根据 FContentEncoding(gzip deflate br) 判断使用哪种方式解压
  // 目前暂时只支持 gzip deflate
  // 初始化解压库
  if (FContentEncoding <> '') then
  begin
    if TStrUtils.SameText(FContentEncoding, 'gzip') then
    begin
      LCompressType := ctGZip;
      FZCompressed := True;
    end else
    if TStrUtils.SameText(FContentEncoding, 'deflate') then
    begin
      LCompressType := ctDeflate;
      FZCompressed := True;
    end;

    if FZCompressed then
    begin
      SetLength(FZBuffer, ZLIB_BUF_SIZE);

      FillChar(FZStream, SizeOf(TZStreamRec), 0);
      FZResult := Z_OK;
      FZFlush := Z_NO_FLUSH;

      if (inflateInit2(FZStream, ZLIB_WINDOW_BITS[LCompressType]) <> Z_OK) then
      begin
        _OnParseFailed(400, 'inflateInit2 failed');
        Exit;
      end;
    end;
  end;

  if Assigned(FOnBodyBegin) then
    FOnBodyBegin();
end;

procedure TCrossHttpParser._OnBodyData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  // 如果数据是压缩的, 进行解压
  if FZCompressed then
  begin
    // 往输入缓冲区填入新数据
    // 对于使用 inflate 函数解压缩数据, 通常不需要使用 Z_FINISH 进行收尾。
    // Z_FINISH 选项通常在压缩时使用, 以表示已经完成了压缩的数据块。
    // 在解压缩过程中, inflate 函数会自动处理数据流的结束。
    // 当输入数据流中的所有数据都被解压缩时, inflate 函数会返回 Z_STREAM_END,
    // 这表示数据流已经结束，不需要额外的处理。
    FZStream.avail_in := ADataSize;
    FZStream.next_in := ADataPtr;
    FZFlush := Z_NO_FLUSH;

    repeat
      // 返回 Z_STREAM_END 表示所有数据处理完毕
      if (FZResult = Z_STREAM_END) then Break;

      // 解压数据输出缓冲区
      FZStream.avail_out := ZLIB_BUF_SIZE;
      FZStream.next_out := @FZBuffer[0];

      // 进行解压处理
      // 输入缓冲区数据可以大于输出缓冲区
      // 这种情况可以多次调用 inflate 分批解压,
      // 直到 avail_in=0  表示当前输入缓冲区数据已解压完毕
      FZResult := inflate(FZStream, FZFlush);

      // 解压出错之后直接结束
      if (FZResult < 0) then
      begin
        FZOutSize := 0;
        Break;
      end;

      // 已解压完成的数据大小
      FZOutSize := ZLIB_BUF_SIZE - FZStream.avail_out;

      // 保存已解压的数据
      if (FZOutSize > 0) and Assigned(FOnBodyData) then
        FOnBodyData(@FZBuffer[0], FZOutSize);
    until ((FZResult = Z_STREAM_END) or (FZStream.avail_in = 0));
  end else
  if Assigned(FOnBodyData) then
    FOnBodyData(ADataPtr, ADataSize);
end;

procedure TCrossHttpParser._OnBodyEnd;
begin
  if FZCompressed then
    inflateEnd(FZStream);

  if Assigned(FOnBodyEnd) then
    FOnBodyEnd();
end;

function TCrossHttpParser._OnGetHeaderValue(const AHeaderName: string;
  out AHeaderValue: string): Boolean;
begin
  if Assigned(FOnGetHeaderValue) then
    Result := FOnGetHeaderValue(AHeaderName, AHeaderValue)
  else
  begin
    AHeaderValue := '';
    Result := False;
  end;
end;

procedure TCrossHttpParser._OnHeaderData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  if Assigned(FOnHeaderData) then
    FOnHeaderData(ADataPtr, ADataSize);
end;

procedure TCrossHttpParser._OnParseBegin;
begin
  if Assigned(FOnParseBegin) then
    FOnParseBegin();
end;

procedure TCrossHttpParser._OnParseFailed(const ACode: Integer;
  const AError: string);
begin
  if Assigned(FOnParseFailed) then
    FOnParseFailed(ACode, AError);

  Abort;
end;

procedure TCrossHttpParser._OnParseSuccess;
begin
  if Assigned(FOnParseSuccess) then
    FOnParseSuccess();
end;

procedure TCrossHttpParser._Reset;
begin
  FParseState := psIdle;
  FHeaderStream.Clear;
  FCRCount := 0;
  FLFCount := 0;
  FParsedBodySize := 0;
end;

end.
